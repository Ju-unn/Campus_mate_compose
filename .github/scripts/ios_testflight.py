#!/usr/bin/env python3
"""iOS TestFlight 워크플로(.github/workflows/ios-testflight.yml)의 안전장치.

비밀 값은 어디에도 출력하지 않는다. 문제를 알릴 때는 비밀 이름만 쓴다. 표준 라이브러리만 쓴다.
로컬 검사(저장소 루트): python -m unittest discover -s .github/scripts -v

  check-secrets [NAME ...]          비밀이 비었거나 모양이 틀리면 이름만 출력하고 실패(이름을 안 주면 12개 전부)
                                    값 대신 HAS_<NAME>=true 만 받은 비밀은 있는지만 본다(값은 쓰는 단계에서 다시 검사)
  decode NAME OUT                   base64 비밀 NAME 을 파일 OUT 으로 푼다(권한 600)
  mask PLIST XCCONFIG               로그 마스킹 명령(::add-mask::)을 낸다 — 두 파일 안 값, dart-define 인코딩
  check-plist PLIST SETTINGS        plist 의 BUNDLE_ID · CLIENT_ID 가 앱 설정과 같은지 본다
  entitlements SRC SETTINGS OUT     Runner.entitlements 의 $(변수) 를 빌드 설정 값으로 채운다
  scrub PLIST XCCONFIG [PATH ...]   PATH 없으면 표준입력을, 있으면 그 파일 · 폴더를 비밀을 지워 다시 쓴다
                                    지울 값은 이 단계 env 의 비밀 + 두 파일 안 값 — 그래서 각 단계 env 에 비밀을 다 줄 필요가 없다
"""

from __future__ import annotations

import base64
import binascii
import os
import plistlib
import re
import sys
from pathlib import Path

REQUIRED = (
    "APPLE_TEAM_ID",
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_KEY_P8_B64",
    "IOS_GOOGLE_SERVICE_INFO_B64",
    "KAKAO_NATIVE_APP_KEY",
    "GOOGLE_WEB_CLIENT_ID",
    "GOOGLE_IOS_CLIENT_ID",
    "GOOGLE_REVERSED_CLIENT_ID",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "API_BASE_URL",
)
B64 = ("ASC_KEY_P8_B64", "IOS_GOOGLE_SERVICE_INFO_B64")
# Secrets.xcconfig 에 들어가는 값. xcconfig 는 // 뒤를 주석으로 버린다.
XCCONFIG = ("KAKAO_NATIVE_APP_KEY", "GOOGLE_IOS_CLIENT_ID", "GOOGLE_REVERSED_CLIENT_ID")
# 앱 코드가 String.fromEnvironment 로 읽는 값(lib/core/env.dart, lib/core/supabase/supabase_config.dart).
DART_DEFINES = ("SUPABASE_URL", "SUPABASE_ANON_KEY", "API_BASE_URL", "KAKAO_NATIVE_APP_KEY", "GOOGLE_WEB_CLIENT_ID")
# plist 의 구글 ID 와 짝이 되는 비밀.
PLIST_PAIRS = (("CLIENT_ID", "GOOGLE_IOS_CLIENT_ID"), ("REVERSED_CLIENT_ID", "GOOGLE_REVERSED_CLIENT_ID"))

SETTING = re.compile(r"^\s*([A-Za-z0-9_]+) = (.*)$")
VARIABLE = re.compile(r"\$\((\w+)\)|\$\{(\w+)\}")
JWT = re.compile(r"eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,}")
# 개인 개발자 계정은 팀 이름 = 실명이다. 이 모양에서 찾은 이름은 로그 전체에서 가린다.
OWNER_NAMES = (
    re.compile(r"\b(?:Apple|iPhone|iOS) (?:Development|Distribution): ([^(\r\n\"']+?) \("),
    re.compile(r"\bTeam:? \"([^\"\r\n]+)\""),
    re.compile(r"\b[Tt]eam(?:Name| name)?\s*[:=]\s*\"?([^\"(\r\n;,]+?)\"?\s*(?:[(;,]|$)", re.M),
)
# 위 세 번째 모양이 이름으로 잘못 집는 빌드 용어. 실명일 수 없어서 가리지 않는다(진단에 필요한 앱 경로가 지워진다).
NOT_NAMES = {"Runner", "Pods", "Release", "Debug", "Profile"}


def decode_b64(value: str) -> bytes:
    return base64.b64decode("".join(value.split()), validate=True)


def secret_problems(env, names=REQUIRED) -> list[str]:
    problems = []
    for name in names:
        value = env.get(name, "")
        if not value and env.get(f"HAS_{name}") == "true":
            continue  # 값은 쓰는 단계에서만 받는다 — 여기서는 있는지만 안다
        if not value:
            problems.append(f"{name}: 비어 있음")
        elif name in B64:
            problem = _b64_problem(name, value)
            if problem:
                problems.append(f"{name}: {problem}")
        elif any(c.isspace() for c in value):
            problems.append(f"{name}: 공백이나 줄바꿈이 섞임")
        elif name in XCCONFIG and "//" in value:
            problems.append(f"{name}: // 가 들어 있음(xcconfig 가 그 뒤를 주석으로 버린다)")
    return problems


def _b64_problem(name: str, value: str) -> str:
    try:
        data = decode_b64(value)
    except (binascii.Error, ValueError):
        return "base64 로 풀리지 않음"
    if name == "ASC_KEY_P8_B64" and b"BEGIN PRIVATE KEY" not in data:
        return "풀어 보니 .p8 키 파일이 아님"
    if name == "IOS_GOOGLE_SERVICE_INFO_B64":
        try:
            if not isinstance(plistlib.loads(data), dict):
                raise ValueError
        except Exception:
            return "풀어 보니 plist 가 아님"
    return ""


def parse_build_settings(text: str) -> dict[str, str]:
    settings = {}
    for line in text.splitlines():
        match = SETTING.match(line)
        if match:
            settings[match.group(1)] = match.group(2)
    return settings


def plist_problems(plist: dict, settings: dict, env) -> list[str]:
    problems = []
    bundle_id = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "")
    if not bundle_id:
        problems.append("앱 번들 ID(PRODUCT_BUNDLE_IDENTIFIER)를 빌드 설정에서 읽지 못함")
    elif plist.get("BUNDLE_ID") != bundle_id:
        problems.append(
            f"GoogleService-Info.plist 의 BUNDLE_ID({plist.get('BUNDLE_ID')}) 가 앱 번들 ID({bundle_id}) 와 다름"
            " — Firebase 에서 이 번들 ID 의 iOS 앱 plist 를 다시 받는다"
        )
    for key, name in PLIST_PAIRS:
        if key in plist and plist[key] != env.get(name):
            problems.append(f"{name} 가 GoogleService-Info.plist 의 {key} 와 다름")
    return problems


def resolve_entitlements(text: str, settings: dict) -> str:
    missing = sorted({a or b for a, b in VARIABLE.findall(text) if not settings.get(a or b)})
    if missing:
        raise ValueError("빌드 설정에 없는 변수: " + ", ".join(missing))
    return VARIABLE.sub(lambda m: settings[m.group(1) or m.group(2)], text)


def load_plist(path: str) -> dict:
    try:
        data = plistlib.loads(Path(path).read_bytes())
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def load_xcconfig(path: str) -> dict:
    try:
        return parse_build_settings(Path(path).read_text(encoding="utf-8"))
    except OSError:
        return {}


def secret_values(env, plist: dict, xcconfig: dict) -> list[str]:
    values = [env.get(name, "") for name in REQUIRED]
    # 번들 ID 는 pbxproj 에 공개돼 있고 실패 진단에 필요해서 남긴다.
    values += [v for k, v in plist.items() if isinstance(v, str) and k != "BUNDLE_ID"]
    values += list(xcconfig.values())
    # Flutter 는 dart-define 을 하나씩 base64("이름=값") 해 DART_DEFINES 로 넘긴다.
    values += [base64.b64encode(f"{n}={env[n]}".encode()).decode() for n in DART_DEFINES if env.get(n)]
    # 줄바꿈이 섞인 값(줄 바꾼 base64)은 줄마다 가린다. 짧은 조각(예: PLIST_VERSION "1")은 로그를 망가뜨리기만 한다.
    parts = {part for value in values for part in value.split()}
    return sorted((p for p in parts if len(p) >= 8), key=len, reverse=True)


def redact(text: str, values: list[str], known_names: set[str] | None = None) -> str:
    """known_names 를 주면 이 글에서 찾은 실명을 거기 더하고, 거기 든 이름은 이후 글에서도 가린다(줄 단위 입력용)."""
    names = {m.group(1).strip() for pattern in OWNER_NAMES for m in pattern.finditer(text)}
    names = {n for n in names if len(n) >= 3 and "***" not in n and n not in NOT_NAMES}
    if known_names is not None:
        known_names |= names
        names = known_names
    for value in sorted(set(values) | names, key=len, reverse=True):
        text = text.replace(value, "***")
    return JWT.sub("***", text)


def _scrub_paths(paths: list[str], values: list[str]) -> None:
    files = []
    for path in map(Path, paths):
        files += [p for p in path.rglob("*") if p.is_file()] if path.is_dir() else [path]
    for file in files:
        try:
            file.write_text(redact(file.read_text(encoding="utf-8"), values), encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            # 검사하지 못했거나 다시 쓰지 못한 파일은 올리지 않는다. 지우지도 못하면 예외로 끝나 업로드 단계가 건너뛴다.
            file.unlink(missing_ok=True)


def _fail(problems: list[str], hint: str) -> int:
    for problem in problems:
        print(f"::error::{problem}")
    print(hint)
    return 1


def main(argv: list[str]) -> int:
    env = os.environ
    command, args = argv[0], argv[1:]
    if command == "check-secrets":
        names = tuple(args) or REQUIRED
        problems = secret_problems(env, names)
        if problems:
            return _fail(problems, "GitHub > Settings > Secrets and variables > Actions(또는 Environments > ios-release)에서 위 이름의 값을 다시 넣는다.")
        print(f"비밀 {len(names)}개 확인")
    elif command == "decode":
        name, out = args
        target = Path(out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(decode_b64(env[name]))
        target.chmod(0o600)
        print(f"{name} → {target.name}")
    elif command == "mask":
        for value in secret_values(env, load_plist(args[0]), load_xcconfig(args[1])):
            print(f"::add-mask::{value}")
    elif command == "check-plist":
        plist_path, settings_path = args
        settings = parse_build_settings(Path(settings_path).read_text(encoding="utf-8"))
        problems = plist_problems(load_plist(plist_path), settings, env)
        if problems:
            return _fail(problems, "번들 ID 와 구글 ID 가 서로 맞아야 푸시 · 구글 로그인이 된다.")
        print(f"번들 ID {settings['PRODUCT_BUNDLE_IDENTIFIER']} — GoogleService-Info.plist 와 일치")
    elif command == "entitlements":
        src, settings_path, out = args
        settings = parse_build_settings(Path(settings_path).read_text(encoding="utf-8"))
        try:
            resolved = resolve_entitlements(Path(src).read_text(encoding="utf-8"), settings)
        except ValueError as error:
            return _fail([str(error)], f"{src} 의 $(변수) 를 빌드 설정에 맞추거나 값으로 바꾼다.")
        keys = sorted(plistlib.loads(resolved.encode()))
        Path(out).write_text(resolved, encoding="utf-8")
        print("권한(entitlements): " + ", ".join(keys))
    elif command == "scrub":
        values = secret_values(env, load_plist(args[0]), load_xcconfig(args[1]))
        if len(args) > 2:
            _scrub_paths(args[2:], values)
        else:
            if hasattr(sys.stdin, "reconfigure"):
                sys.stdin.reconfigure(errors="replace")  # 빌드 로그의 깨진 바이트로 멈추지 않게
            seen_names: set[str] = set()  # 메모리에만 둔다 — 디스크에 남기면 그게 새 유출 표면이다
            for line in sys.stdin:
                sys.stdout.write(redact(line, values, seen_names))
                sys.stdout.flush()
    else:
        print(f"모르는 명령: {command}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
