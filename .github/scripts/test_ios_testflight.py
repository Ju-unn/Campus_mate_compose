"""ios_testflight.py 와 ios-testflight.yml 의 검사.

실행(저장소 루트): python -m unittest discover -s .github/scripts -v
워크플로 구조 검사는 PyYAML 이 있을 때만 돈다(backend/.venv 에 있다). 표준 라이브러리 외 의존성은 없다.
"""

from __future__ import annotations

import base64
import contextlib
import io
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import ios_testflight as t

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "ios-testflight.yml"

# 머리줄을 쪼개 둔다 — 통째로 두면 비밀 스캐너가 진짜 키로 본다.
PEM = "PRIVATE " + "KEY-----"
P8 = f"-----BEGIN {PEM}\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg\n-----END {PEM}\n".encode()
PLIST = {
    "API_KEY": "AIzaFakeFirebaseApiKey000",
    "BUNDLE_ID": "io.example.app",
    "CLIENT_ID": "111-fake.apps.googleusercontent.com",
    "REVERSED_CLIENT_ID": "com.googleusercontent.apps.111-fake",
    "GCM_SENDER_ID": "111111111111",
    "PLIST_VERSION": "1",
}
XCCONFIG_TEXT = "KAKAO_NATIVE_APP_KEY = kakaofromxcconfigfile0000\nGOOGLE_IOS_CLIENT_ID = 111-fake.apps.googleusercontent.com\n"
ASC = ("APPLE_TEAM_ID", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8_B64")


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def good_env() -> dict[str, str]:
    return {
        "APPLE_TEAM_ID": "TEAM000001",
        "ASC_KEY_ID": "KEYID00001",
        "ASC_ISSUER_ID": "00000000-1111-2222-3333-444444444444",
        "ASC_KEY_P8_B64": b64(P8),
        "IOS_GOOGLE_SERVICE_INFO_B64": b64(plistlib.dumps(PLIST)),
        "KAKAO_NATIVE_APP_KEY": "kakaofakenativekey0000000000000",
        "GOOGLE_WEB_CLIENT_ID": "222-web.apps.googleusercontent.com",
        "GOOGLE_IOS_CLIENT_ID": PLIST["CLIENT_ID"],
        "GOOGLE_REVERSED_CLIENT_ID": PLIST["REVERSED_CLIENT_ID"],
        "SUPABASE_URL": "https://fakeref.supabase.co",
        "SUPABASE_ANON_KEY": "sb_publishable_fakeanonkey",
        "API_BASE_URL": "https://fake-api.example.run.app",
    }


def wrapped(value: str) -> str:
    return "\n".join(value[i : i + 16] for i in range(0, len(value), 16))


def run_main(argv: list[str], env: dict[str, str], stdin: str = "") -> tuple[int, str]:
    out = io.StringIO()
    with mock.patch.dict(os.environ, env, clear=True), contextlib.redirect_stdout(out), mock.patch(
        "sys.stdin", io.StringIO(stdin)
    ):
        code = t.main(argv)
    return code, out.getvalue()


class SecretProblemsTest(unittest.TestCase):
    def test_all_twelve_names_are_required(self):
        self.assertEqual(len(t.REQUIRED), 12)
        self.assertEqual(t.secret_problems(good_env()), [])

    def test_empty_and_missing_secrets_are_reported_by_name(self):
        env = good_env()
        env["ASC_KEY_ID"] = ""
        del env["SUPABASE_URL"]
        problems = t.secret_problems(env)
        self.assertEqual(len(problems), 2)
        self.assertTrue(problems[0].startswith("ASC_KEY_ID"))
        self.assertTrue(problems[1].startswith("SUPABASE_URL"))

    def test_pasted_newline_is_reported(self):
        env = good_env()
        env["APPLE_TEAM_ID"] = "TEAM000001\n"
        self.assertEqual([p.split(":")[0] for p in t.secret_problems(env)], ["APPLE_TEAM_ID"])

    def test_double_slash_breaks_xcconfig_values_only(self):
        env = good_env()
        env["GOOGLE_IOS_CLIENT_ID"] = "a//b"
        env["SUPABASE_URL"] = "https://still-fine.supabase.co"
        self.assertEqual([p.split(":")[0] for p in t.secret_problems(env)], ["GOOGLE_IOS_CLIENT_ID"])

    def test_base64_secrets_must_decode_to_the_right_file(self):
        env = good_env()
        env["ASC_KEY_P8_B64"] = b64(b"not a key")
        env["IOS_GOOGLE_SERVICE_INFO_B64"] = "%%%not-base64%%%"
        names = [p.split(":")[0] for p in t.secret_problems(env)]
        self.assertEqual(names, ["ASC_KEY_P8_B64", "IOS_GOOGLE_SERVICE_INFO_B64"])

    def test_wrapped_base64_lines_are_accepted(self):
        env = good_env()
        raw = env["IOS_GOOGLE_SERVICE_INFO_B64"]
        env["IOS_GOOGLE_SERVICE_INFO_B64"] = "\r\n".join(raw[i : i + 64] for i in range(0, len(raw), 64))
        self.assertEqual(t.secret_problems(env), [])

    def test_presence_flag_stands_in_for_a_value_kept_out_of_this_step(self):
        env = {k: v for k, v in good_env().items() if k not in ASC}
        env.update({f"HAS_{name}": "true" for name in ASC})
        self.assertEqual(t.secret_problems(env), [])
        env["HAS_ASC_KEY_ID"] = "false"
        self.assertEqual([p.split(":")[0] for p in t.secret_problems(env)], ["ASC_KEY_ID"])

    def test_check_secrets_can_check_only_named_secrets(self):
        env = {name: good_env()[name] for name in ASC}
        self.assertEqual(run_main(["check-secrets", *ASC], env)[0], 0)
        env["ASC_ISSUER_ID"] = ""
        code, out = run_main(["check-secrets", *ASC], env)
        self.assertEqual(code, 1)
        self.assertIn("ASC_ISSUER_ID", out)
        self.assertNotIn("SUPABASE_URL", out)

    def test_check_secrets_never_prints_values(self):
        env = good_env()
        env["KAKAO_NATIVE_APP_KEY"] = "kakao secret with space"
        code, out = run_main(["check-secrets"], env)
        self.assertEqual(code, 1)
        self.assertIn("KAKAO_NATIVE_APP_KEY", out)
        for value in env.values():
            self.assertNotIn(value, out)

    def test_check_secrets_passes(self):
        code, _ = run_main(["check-secrets"], good_env())
        self.assertEqual(code, 0)


class BuildSettingsTest(unittest.TestCase):
    def test_parses_xcodebuild_show_build_settings(self):
        text = (
            "Command line invocation:\n"
            "Build settings for action build and target Runner:\n"
            "    APS_ENVIRONMENT = production\n"
            "    PRODUCT_BUNDLE_IDENTIFIER = io.example.app\n"
            "    OTHER_LDFLAGS = $(inherited) -ObjC = x\n"
        )
        settings = t.parse_build_settings(text)
        self.assertEqual(settings["APS_ENVIRONMENT"], "production")
        self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "io.example.app")
        self.assertEqual(settings["OTHER_LDFLAGS"], "$(inherited) -ObjC = x")


class PlistProblemsTest(unittest.TestCase):
    settings = {"PRODUCT_BUNDLE_IDENTIFIER": "io.example.app"}

    def test_matching_plist_passes(self):
        self.assertEqual(t.plist_problems(PLIST, self.settings, good_env()), [])

    def test_bundle_id_mismatch_is_reported(self):
        plist = dict(PLIST, BUNDLE_ID="com.other.app")
        problems = t.plist_problems(plist, self.settings, good_env())
        self.assertEqual(len(problems), 1)
        self.assertIn("BUNDLE_ID", problems[0])

    def test_missing_project_bundle_id_is_reported(self):
        self.assertEqual(len(t.plist_problems(PLIST, {}, good_env())), 1)

    def test_google_client_id_mismatch_names_only(self):
        env = good_env()
        env["GOOGLE_REVERSED_CLIENT_ID"] = "com.googleusercontent.apps.999-other"
        problems = t.plist_problems(PLIST, self.settings, env)
        self.assertEqual(len(problems), 1)
        self.assertIn("GOOGLE_REVERSED_CLIENT_ID", problems[0])
        self.assertNotIn(env["GOOGLE_REVERSED_CLIENT_ID"], problems[0])
        self.assertNotIn(PLIST["REVERSED_CLIENT_ID"], problems[0])

    def test_plist_without_client_id_is_not_a_mismatch(self):
        plist = {k: v for k, v in PLIST.items() if "CLIENT_ID" not in k}
        self.assertEqual(t.plist_problems(plist, self.settings, good_env()), [])


class EntitlementsTest(unittest.TestCase):
    def test_repo_entitlements_resolve_push_environment(self):
        text = (ROOT / "frontend" / "ios" / "Runner" / "Runner.entitlements").read_text(encoding="utf-8")
        resolved = t.resolve_entitlements(text, {"APS_ENVIRONMENT": "production"})
        self.assertEqual(plistlib.loads(resolved.encode())["aps-environment"], "production")

    def test_unresolved_variable_fails_with_its_name(self):
        with self.assertRaises(ValueError) as ctx:
            t.resolve_entitlements("<string>$(AppIdentifierPrefix)x ${EMPTY}</string>", {"EMPTY": ""})
        self.assertIn("AppIdentifierPrefix", str(ctx.exception))
        self.assertIn("EMPTY", str(ctx.exception))


class RedactTest(unittest.TestCase):
    xcconfig = t.parse_build_settings(XCCONFIG_TEXT)

    def test_secret_values_cover_env_files_and_dart_define_encoding(self):
        env = good_env()
        values = t.secret_values(env, PLIST, self.xcconfig)
        self.assertIn(env["APPLE_TEAM_ID"], values)
        self.assertIn(PLIST["API_KEY"], values)
        self.assertIn("kakaofromxcconfigfile0000", values)  # 이 단계 env 에 없어도 파일에서 가린다
        self.assertIn(b64(f"SUPABASE_URL={env['SUPABASE_URL']}".encode()), values)
        self.assertNotIn(PLIST["BUNDLE_ID"], values)  # 번들 ID 는 pbxproj 에 공개돼 있고 진단에 필요하다
        self.assertNotIn("1", values)

    def test_wrapped_value_is_split_into_maskable_lines(self):
        env = good_env()
        env["IOS_GOOGLE_SERVICE_INFO_B64"] = wrapped(env["IOS_GOOGLE_SERVICE_INFO_B64"])
        values = t.secret_values(env, {}, {})
        self.assertTrue(all("\n" not in v for v in values))
        for part in env["IOS_GOOGLE_SERVICE_INFO_B64"].split():
            if len(part) >= 8:
                self.assertIn(part, values)

    def test_redact_hides_values_tokens_and_certificate_owner_names(self):
        env = good_env()
        jwt = "eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJmYWtlIn0.c2lnbmF0dXJlc2lnbmF0dXJl"
        dart_defines = b64(f"API_BASE_URL={env['API_BASE_URL']}".encode())
        text = (
            f"team {env['APPLE_TEAM_ID']} key {PLIST['API_KEY']}\n"
            f"DART_DEFINES={dart_defines}\n"
            f"Authorization: Bearer {jwt}\n"
            "Signing Identity: \"Apple Distribution: Hong Gildong (TEAM000001)\"\n"
        )
        out = t.redact(text, t.secret_values(env, PLIST, {}))
        for leaked in (env["APPLE_TEAM_ID"], PLIST["API_KEY"], dart_defines, jwt, "Hong Gildong"):
            self.assertNotIn(leaked, out)
        self.assertIn("Apple Distribution: ***", out)

    def test_owner_name_found_once_is_hidden_everywhere(self):
        text = (
            "summary for Kim Cheolsu\n"
            "Signing Identity: Apple Distribution: Kim Cheolsu (ABC)\n"
            'error: Team "Lee Younghee" does not have permission\n'
            "teamName = Park Minsu;\n"
            "account Park Minsu / Lee Younghee\n"
        )
        out = t.redact(text, [])
        for name in ("Kim Cheolsu", "Lee Younghee", "Park Minsu"):
            self.assertNotIn(name, out)

    def test_scrub_filters_stdin(self):
        env = good_env()
        code, out = run_main(["scrub", "missing.plist", "missing.xcconfig"], env, stdin=f"url {env['SUPABASE_URL']}\nok\n")
        self.assertEqual(code, 0)
        self.assertEqual(out, "url ***\nok\n")

    def test_scrub_rewrites_files_and_drops_unreadable_ones(self):
        env = good_env()
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp, "logs", "x.xcdistributionlogs")
            logs.mkdir(parents=True)
            (logs / "verbose.log").write_text(f"key {env['ASC_KEY_ID']}", encoding="utf-8")
            (logs / "blob.bin").write_bytes(b"\xff\xfe\x00binary")
            code, _ = run_main(["scrub", "missing.plist", "missing.xcconfig", str(Path(tmp, "logs"))], env)
            self.assertEqual(code, 0)
            self.assertEqual((logs / "verbose.log").read_text(encoding="utf-8"), "key ***")
            self.assertFalse((logs / "blob.bin").exists())

    def test_scrub_deletes_a_file_it_could_not_rewrite(self):
        env = good_env()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp, "export-upload.log")
            log.write_text(f"key {env['ASC_KEY_ID']}", encoding="utf-8")
            with mock.patch.object(Path, "write_text", side_effect=OSError("disk full")):
                code, _ = run_main(["scrub", "missing.plist", "missing.xcconfig", tmp], env)
            self.assertEqual(code, 0)
            self.assertFalse(log.exists())

    def test_scrub_failing_to_delete_an_unrewritable_file_stops_the_step(self):
        env = good_env()
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "export-upload.log").write_text(f"key {env['ASC_KEY_ID']}", encoding="utf-8")
            with mock.patch.object(Path, "write_text", side_effect=OSError("disk full")), mock.patch.object(
                Path, "unlink", side_effect=PermissionError("locked")
            ):
                with self.assertRaises(PermissionError):
                    run_main(["scrub", "missing.plist", "missing.xcconfig", tmp], env)

    def test_scrub_stdin_hides_an_owner_name_on_lines_after_it_was_found(self):
        stdin = "Signing Identity: Apple Distribution: Kim Cheolsu (ABC)\nerror: Kim Cheolsu has no access\n"
        code, out = run_main(["scrub", "missing.plist", "missing.xcconfig"], good_env(), stdin=stdin)
        self.assertEqual(code, 0)
        self.assertNotIn("Kim Cheolsu", out)
        self.assertEqual(out.splitlines()[1], "error: *** has no access")

    def test_build_target_name_after_team_is_not_a_person_name(self):
        text = "Signing team: Runner\nProducts/Applications/Runner.app\n"
        self.assertEqual(t.redact(text, []), text)

    def test_mask_emits_add_mask_for_file_values_and_wrapped_secrets(self):
        env = good_env()
        env["IOS_GOOGLE_SERVICE_INFO_B64"] = wrapped(env["IOS_GOOGLE_SERVICE_INFO_B64"])
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp, "GoogleService-Info.plist")
            plist_path.write_bytes(plistlib.dumps(PLIST))
            xcconfig_path = Path(tmp, "Secrets.xcconfig")
            xcconfig_path.write_text(XCCONFIG_TEXT, encoding="utf-8")
            code, out = run_main(["mask", str(plist_path), str(xcconfig_path)], env)
        self.assertEqual(code, 0)
        self.assertIn(f"::add-mask::{PLIST['API_KEY']}\n", out)
        self.assertIn("::add-mask::kakaofromxcconfigfile0000\n", out)
        self.assertTrue(all(line.startswith("::add-mask::") for line in out.splitlines()))


class DecodeTest(unittest.TestCase):
    def test_decode_writes_secret_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp, "keys", "AuthKey.p8")
            code, out = run_main(["decode", "ASC_KEY_P8_B64", str(target)], good_env())
            self.assertEqual(code, 0)
            self.assertEqual(target.read_bytes(), P8)
            self.assertNotIn("PRIVATE", out)


@unittest.skipUnless(shutil.which("bash"), "bash 없음")
class WorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import yaml
        except ImportError:  # pragma: no cover - PyYAML 없는 곳에서는 건너뛴다
            raise unittest.SkipTest("PyYAML 없음")
        cls.text = WORKFLOW.read_text(encoding="utf-8")
        cls.wf = yaml.safe_load(cls.text)
        cls.job = cls.wf["jobs"]["testflight"]
        cls.steps = cls.job["steps"]
        cls.runs = [s["run"] for s in cls.steps if "run" in s]

    def step(self, snippet: str) -> dict:
        found = [s for s in self.steps if snippet in s.get("run", "")]
        self.assertEqual(len(found), 1, snippet)
        return found[0]

    def test_manual_trigger_only(self):
        triggers = self.wf[True]  # PyYAML 은 on 키를 True 로 읽는다
        self.assertEqual(list(triggers), ["workflow_dispatch"])

    def test_owner_only_read_only_serialized_environment(self):
        self.assertEqual(self.wf["permissions"], {"contents": "read"})
        self.assertEqual(self.job["if"], "github.triggering_actor == github.repository_owner")
        self.assertEqual(self.job["environment"], "ios-release")
        self.assertIs(self.wf["concurrency"]["cancel-in-progress"], False)
        self.assertEqual(self.job["runs-on"], "macos-latest")
        self.assertLessEqual(self.job["timeout-minutes"], 90)

    def test_build_name_is_an_input_defaulting_to_the_release_version(self):
        # 앱 버전 이름(CFBundleShortVersionString)은 pubspec 의 version(1.0.0+1, 저장소 규칙)을 건드리지 않고 이 입력으로 정한다.
        build_name = self.wf[True]["workflow_dispatch"]["inputs"]["build_name"]
        self.assertEqual(build_name["default"], "1.0.2")
        self.assertIs(build_name["required"], True)
        self.assertEqual(self.job["env"]["BUILD_NAME"], "${{ inputs.build_name }}")

    def test_build_name_shape_is_checked_before_the_build(self):
        build = self.step("flutter build ipa")["run"]
        self.assertLess(build.index('"$BUILD_NAME" =~'), build.index("flutter build ipa"))

    def test_pipefail_shell(self):
        self.assertEqual(self.job["defaults"]["run"]["shell"], "bash")

    def test_secrets_only_reach_the_run_steps_that_need_them(self):
        self.assertNotIn("secrets.", str(self.job.get("env", {})))
        for step in self.steps:
            env = step.get("env", {})
            if "uses" in step:
                self.assertNotIn("secrets.", str(step), step["uses"])
            for key, value in env.items():
                if "secrets." in value and not key.startswith("HAS_"):
                    self.assertEqual(value, "${{ secrets.%s }}" % key)
        for name in t.REQUIRED:
            self.assertIn("${{ secrets.%s }}" % name, self.text)

    def test_signing_key_and_team_live_only_in_the_upload_step(self):
        upload = self.step("xcodebuild -exportArchive")
        for name in ASC:
            holders = [s for s in self.steps if name in s.get("env", {})]
            self.assertEqual(holders, [upload], name)
        run = upload["run"]
        self.assertIn("check-secrets " + " ".join(ASC), run)
        self.assertRegex(run, r"trap 'rm -f [^']*\$KEY")
        self.assertLess(run.index("trap "), run.index("decode ASC_KEY_P8_B64"))
        self.assertNotIn("decode ASC_KEY_P8_B64", "".join(r for r in self.runs if r is not run))

    def test_early_check_sees_only_presence_of_upload_secrets(self):
        check = self.step('"$TOOL" check-secrets\n')
        for name in ASC:
            self.assertEqual(check["env"][f"HAS_{name}"], "${{ secrets.%s != '' }}" % name)

    def test_no_hardcoded_identifiers(self):
        self.assertNotIn("io.github.juunn", self.text)

    def test_third_party_actions_are_pinned_to_commit(self):
        for step in self.steps:
            uses = step.get("uses", "")
            if uses and not uses.startswith("actions/"):
                self.assertRegex(uses, r"@[0-9a-f]{40}$")

    def test_checkout_drops_the_token(self):
        checkout = next(s for s in self.steps if s.get("uses", "").startswith("actions/checkout"))
        self.assertIs(checkout["with"]["persist-credentials"], False)

    def test_run_scripts_parse_and_avoid_inline_expressions(self):
        for script in self.runs:
            self.assertNotIn("${{", script)
            self.assertNotRegex(script, r"set -[a-wyz]*x")
            result = subprocess.run(["bash", "-n"], input=script, encoding="utf-8", capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_masks_are_registered_before_the_build(self):
        restore = self.steps.index(self.step('"$TOOL" mask "$PLIST" "$XCCONFIG"'))
        build = self.steps.index(self.step("flutter build ipa"))
        self.assertLess(restore, build)

    def test_build_and_upload_output_goes_through_the_scrubber(self):
        for snippet, log in (("flutter build ipa", "flutter-build-ipa.log"), ("xcodebuild -exportArchive", "export-upload.log")):
            self.assertIn(f'| python3 -u "$TOOL" scrub "$PLIST" "$XCCONFIG" | tee "$RUNNER_TEMP/logs/{log}"', self.step(snippet)["run"])

    # 내보내기 옵션의 uploadSymbols 는 dSYM 을 애플에만 올린다 — Crashlytics 에는 업로드 뒤의 별도 단계가 올린다.
    def dsym_step(self) -> dict:
        return self.step("upload-symbols")

    def test_crashlytics_dsym_upload_comes_after_the_testflight_upload(self):
        step = self.dsym_step()
        self.assertLess(self.steps.index(self.step("xcodebuild -exportArchive")), self.steps.index(step))
        self.assertNotIn("if", step)  # 기본(앞 단계가 모두 성공했을 때만)으로 돈다
        # 도구는 SPM 체크아웃(Flutter 가 build/ios/SourcePackages 에 받는다)이나 CocoaPods 에 있다 — Pods 한 곳만 보면 SPM 프로젝트에서 못 찾는다.
        self.assertIn("build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols", step["run"])
        self.assertIn("ios/Pods/FirebaseCrashlytics/upload-symbols", step["run"])
        self.assertIn('-gsp "$PLIST" -p ios "$ARCHIVE/dSYMs"', step["run"])

    def test_crashlytics_dsym_step_gets_no_secrets(self):
        step = self.dsym_step()
        self.assertNotIn("secrets.", str(step))
        for name in t.REQUIRED:
            self.assertNotIn(name, step.get("env", {}))
            self.assertNotIn(name, step["run"])

    def test_crashlytics_dsym_failure_does_not_fail_the_job(self):
        # 앱은 이미 TestFlight 에 올라갔다 — 심볼 올리기가 틀어져도 잡을 빨갛게 만들지 않는다.
        step = self.dsym_step()
        self.assertIs(step.get("continue-on-error"), True)
        self.assertIn("::warning::", step["run"])  # 도구나 dSYMs 폴더가 없으면 경고 한 줄
        self.assertNotIn("::error::", step["run"])
        self.assertNotRegex(step["run"], r"exit [1-9]")

    def test_crashlytics_dsym_output_goes_through_the_scrubber(self):
        run = self.dsym_step()["run"]
        self.assertIn('-p ios "$ARCHIVE/dSYMs" 2>&1 | python3 -u "$TOOL" scrub "$PLIST" "$XCCONFIG"', run)
        # 못 찾았을 때 찍는 점검 줄(ls · find)도 같은 지우개를 거친다 — 폴더 이름에 값이 섞여 있을 수 있다.
        self.assertIn('} 2>&1 | python3 -u "$TOOL" scrub "$PLIST" "$XCCONFIG" || true', run)

    ARCHIVE_DIR = "build/ios/archive/Runner.xcarchive"

    # 단계의 run 을 임시 폴더에서 진짜 bash 로 돌린다(GitHub 와 같은 -e -o pipefail). 문자열 검사로는 "어디서 무엇을 찾나"를 못 잡는다.
    # populate(work) 가 가짜 파일을 만든다. 돌려주는 값: (끝난 프로세스, {파일 이름: 내용} — calls.txt · summary.md 중 생긴 것).
    def run_step(self, step: dict, populate) -> tuple[subprocess.CompletedProcess, dict[str, str]]:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "bin").mkdir()
            # 윈도우 개발 PC 의 python3 는 스토어 안내용 가짜라, 지우개를 돌릴 진짜 파이썬으로 잇는다.
            (work / "bin" / "python3").write_text(
                f'#!/bin/sh\nexec "{Path(sys.executable).as_posix()}" "$@"\n', encoding="utf-8", newline="\n"
            )
            populate(work)
            env = {
                **os.environ,
                "PATH": f"{(work / 'bin').as_posix()}{os.pathsep}{os.environ['PATH']}",
                "HOME": work.as_posix(),
                "TOOL": t.__file__,
                "PLIST": "ios/Runner/GoogleService-Info.plist",
                "XCCONFIG": "ios/Flutter/Secrets.xcconfig",
                "ARCHIVE": self.ARCHIVE_DIR,
                "GITHUB_STEP_SUMMARY": (work / "summary.md").as_posix(),
            }
            done = subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", step["run"]],
                cwd=work,
                env=env,
                encoding="utf-8",
                errors="replace",
                capture_output=True,
            )
            files = {n: (work / n).read_text(encoding="utf-8") for n in ("calls.txt", "summary.md") if (work / n).exists()}
            return done, files

    def run_dsym_step(self, uploader_at: str | None = None, dsyms: bool = True, uploader_exit: int = 0):
        def populate(work: Path) -> None:
            (work / self.ARCHIVE_DIR / "Products").mkdir(parents=True)
            if dsyms:
                (work / self.ARCHIVE_DIR / "dSYMs").mkdir()
            if uploader_at:
                uploader = work / uploader_at
                uploader.parent.mkdir(parents=True)
                uploader.write_text(
                    f'#!/bin/sh\necho "$@" >> "{(work / "calls.txt").as_posix()}"\nexit {uploader_exit}\n',
                    encoding="utf-8",
                    newline="\n",
                )
                uploader.chmod(0o755)

        done, files = self.run_step(self.dsym_step(), populate)
        return done, files.get("calls.txt", "")

    SPM_UPLOADER = "build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
    POD_UPLOADER = "ios/Pods/FirebaseCrashlytics/upload-symbols"

    def test_crashlytics_dsym_step_uploads_with_the_tool_from_either_place(self):
        for place in (self.SPM_UPLOADER, self.POD_UPLOADER):
            done, calls = self.run_dsym_step(uploader_at=place)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(
                calls.strip(), "-gsp ios/Runner/GoogleService-Info.plist -p ios build/ios/archive/Runner.xcarchive/dSYMs", place
            )
            self.assertNotIn("::warning::", done.stdout, place)

    def test_crashlytics_dsym_warning_says_which_half_is_missing(self):
        no_tool, calls = self.run_dsym_step(uploader_at=None)
        self.assertEqual(no_tool.returncode, 0, no_tool.stderr)
        self.assertEqual(calls, "")
        self.assertRegex(no_tool.stdout, r"::warning::[^\n]*upload-symbols[^\n]*찾지 못")
        self.assertNotIn("dSYMs 폴더가 없", no_tool.stdout)
        # 다음 실행에서 어디를 뒤졌는지 로그로 남는다 — 줄마다 무엇을 보는지 머리글이 붙는다.
        for header in (
            "ios/Pods/FirebaseCrashlytics",
            "SPM 체크아웃 목록",
            "firebase-ios-sdk/Crashlytics",
            "보관본",
            "보관본 dSYMs",
            "DerivedData 의 upload-symbols",
        ):
            self.assertIn(f"== {header} ==", no_tool.stdout)

        no_dsyms, calls = self.run_dsym_step(uploader_at=self.SPM_UPLOADER, dsyms=False)
        self.assertEqual(no_dsyms.returncode, 0, no_dsyms.stderr)
        self.assertEqual(calls, "")
        self.assertRegex(no_dsyms.stdout, r"::warning::[^\n]*dSYMs 폴더가 없")
        self.assertNotRegex(no_dsyms.stdout, r"::warning::[^\n]*upload-symbols[^\n]*찾지 못")
        self.assertIn("Products", no_dsyms.stdout)  # dSYMs 가 없으면 보관본 안에 무엇이 있는지가 단서다

    def test_crashlytics_dsym_upload_failure_is_only_a_warning(self):
        done, calls = self.run_dsym_step(uploader_at=self.SPM_UPLOADER, uploader_exit=1)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(calls)
        self.assertRegex(done.stdout, r"::warning::[^\n]*실패")

    # 광고 식별자(IDFA) 부품은 앱에 넣지 않기로 했다(docs/decisions/2026-10-20-launch-day-decisions.md). Podfile 의 $FirebaseAnalyticsWithoutAdIdSupport
    # 는 CocoaPods 전용이라 SPM 으로 오는 firebase_analytics 에는 듣지 않는다 — SPM 쪽은 이 환경변수(존재만 본다)가 켠다.
    AD_ID_SWITCH = "FIREBASE_ANALYTICS_WITHOUT_ADID"
    AD_ID_PARTS = ("GoogleAppMeasurementIdentitySupport", "GoogleAdsOnDeviceConversion")

    def test_ad_id_switch_reaches_every_step_that_resolves_swift_packages(self):
        # 패키지 해석(manifest 평가)은 번들 ID 확인(xcodebuild -showBuildSettings)과 flutter build ipa 두 곳에서 일어난다.
        for snippet in ("xcodebuild -showBuildSettings", "flutter build ipa"):
            step = self.step(snippet)
            effective = {**self.job.get("env", {}), **step.get("env", {})}
            self.assertEqual(effective.get(self.AD_ID_SWITCH), "true", snippet)

    def ad_id_step(self) -> dict:
        return self.step(self.AD_ID_PARTS[1])

    def run_ad_id_check(self, frameworks: tuple[str, ...] | None):
        """frameworks 가 None 이면 앱의 Frameworks 폴더 자체가 없는 보관본."""

        def populate(work: Path) -> None:
            if frameworks is not None:
                folder = work / self.ARCHIVE_DIR / "Products/Applications/Runner.app/Frameworks"
                folder.mkdir(parents=True)
                for name in frameworks:
                    (folder / f"{name}.framework").mkdir()

        return self.run_step(self.ad_id_step(), populate)

    def test_ad_id_check_runs_on_the_archive_before_the_upload(self):
        step = self.ad_id_step()
        self.assertLess(self.steps.index(self.step("flutter build ipa")), self.steps.index(step))
        self.assertLess(self.steps.index(step), self.steps.index(self.step("xcodebuild -exportArchive")))
        self.assertNotIn("if", step)
        self.assertNotIn("secrets.", str(step))
        self.assertIn('ls "$FRAMEWORKS" 2>&1 | python3 -u "$TOOL" scrub "$PLIST" "$XCCONFIG"', step["run"])

    def test_ad_id_parts_in_the_app_only_raise_a_warning(self):
        step = self.ad_id_step()
        self.assertIs(step.get("continue-on-error"), True)
        self.assertNotIn("::error::", step["run"])
        self.assertNotRegex(step["run"], r"exit [1-9]")
        both, _ = self.run_ad_id_check(self.AD_ID_PARTS + ("Flutter",))
        self.assertEqual(both.returncode, 0, both.stderr)
        for name in self.AD_ID_PARTS:
            self.assertRegex(both.stdout, rf"::warning::[^\n]*{name}")
        self.assertIn("Flutter.framework", both.stdout)  # 목록도 로그에 남는다
        for name in self.AD_ID_PARTS:  # 하나만 있어도 그 이름이 경고에 나온다
            one, _ = self.run_ad_id_check((name, "Flutter"))
            self.assertEqual(one.returncode, 0, one.stderr)
            self.assertRegex(one.stdout, rf"::warning::[^\n]*{name}")

    def test_app_without_ad_id_parts_passes_quietly_and_lists_frameworks(self):
        done, files = self.run_ad_id_check(("Flutter", "FirebaseAnalytics", "GoogleAppMeasurement"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("::warning::", done.stdout)
        self.assertIn("FirebaseAnalytics.framework", done.stdout)  # 맥에서 눈으로 확인할 목록
        self.assertIn("광고 식별자 부품 없음", files["summary.md"])

    def test_missing_frameworks_folder_is_not_reported_as_clean(self):
        done, files = self.run_ad_id_check(None)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertRegex(done.stdout, r"::warning::[^\n]*Frameworks 폴더")
        self.assertNotIn("광고 식별자 부품 없음", files.get("summary.md", ""))

    # PR 컴파일 점검(ios-build.yml)도 배포 빌드와 같은 부품(Core)으로 컴파일해야, Core 로 안 되는 변화가 merge 전에 드러난다.
    BUILD_WORKFLOW = ROOT / ".github" / "workflows" / "ios-build.yml"
    BUILD_FRAMEWORKS = "build/ios/iphoneos/Runner.app/Frameworks"

    def compile_check_job(self) -> dict:
        import yaml

        return yaml.safe_load(self.BUILD_WORKFLOW.read_text(encoding="utf-8"))["jobs"]["ios-build"]

    def test_both_ios_workflows_switch_off_the_ad_id_parts(self):
        self.assertEqual(self.job["env"][self.AD_ID_SWITCH], "true")
        self.assertEqual(self.compile_check_job()["env"][self.AD_ID_SWITCH], "true")

    def test_compile_check_warns_about_ad_id_parts_after_building(self):
        steps = self.compile_check_job()["steps"]
        build = next(i for i, s in enumerate(steps) if "flutter build ios" in s.get("run", ""))
        check = next(i for i, s in enumerate(steps) if self.AD_ID_PARTS[1] in s.get("run", ""))
        self.assertLess(build, check)
        step = steps[check]
        self.assertIs(step.get("continue-on-error"), True)
        self.assertNotIn("::error::", step["run"])
        self.assertNotRegex(step["run"], r"exit [1-9]")
        for name in self.AD_ID_PARTS:
            self.assertIn(name, step["run"])

        def populate(names: tuple[str, ...]):
            def make(work: Path) -> None:
                folder = work / self.BUILD_FRAMEWORKS
                folder.mkdir(parents=True)
                for name in names:
                    (folder / f"{name}.framework").mkdir()

            return make

        dirty, _ = self.run_step(step, populate(self.AD_ID_PARTS + ("Flutter",)))
        self.assertEqual(dirty.returncode, 0, dirty.stderr)
        for name in self.AD_ID_PARTS:
            self.assertRegex(dirty.stdout, rf"::warning::[^\n]*{name}")
        clean, _ = self.run_step(step, populate(("Flutter", "FirebaseAnalytics")))
        self.assertEqual(clean.returncode, 0, clean.stderr)
        self.assertNotIn("::warning::", clean.stdout)
        self.assertIn("FirebaseAnalytics.framework", clean.stdout)
        missing, _ = self.run_step(step, lambda work: None)
        self.assertEqual(missing.returncode, 0, missing.stderr)
        self.assertRegex(missing.stdout, r"::warning::[^\n]*Frameworks 폴더")

    def test_signs_without_dev_certificate_and_uploads_with_api_key(self):
        joined = "\n".join(self.runs)
        self.assertIn("flutter build ipa --release --no-codesign", joined)
        self.assertIn('--build-number="$BUILD_NUMBER"', joined)
        self.assertIn('--build-name="$BUILD_NAME"', joined)
        for define in t.DART_DEFINES:
            self.assertIn(f'--dart-define={define}="${define}"', joined)
        self.assertIn("--entitlements", joined)
        # find -exec ... \; 는 codesign 이 실패해도 0 으로 끝난다 — + 로 묶어야 실패가 단계를 멈춘다.
        self.assertRegex(joined, r"-exec codesign [^\n]*\{\} \+")
        self.assertNotRegex(joined, r"-exec codesign [^\n]*\\;")
        self.assertRegex(joined, r"xcodebuild -exportArchive[\s\S]*-allowProvisioningUpdates")
        for flag in ("-authenticationKeyPath", "-authenticationKeyID", "-authenticationKeyIssuerID"):
            self.assertEqual(joined.count(flag), 1, flag)
        self.assertIn("<string>app-store-connect</string>", joined)
        self.assertIn("<string>upload</string>", joined)

    def test_only_our_scrubbed_logs_are_uploaded_after_a_clean_gather(self):
        gather = next(s for s in self.steps if s.get("id") == "logs")
        upload = next(s for s in self.steps if s.get("uses", "").startswith("actions/upload-artifact"))
        self.assertEqual(gather["if"], "failure()")
        self.assertEqual(upload["if"], "failure() && steps.logs.outcome == 'success'")
        self.assertRegex(gather["run"], r"scrub[^\n]*failure-logs")
        self.assertNotIn("xcdistributionlogs", gather["run"])
        self.assertNotIn("$RUNNER_TEMP/export", gather["run"])
        copied = set(re.findall(r"logs/([\w.-]+\.log)", gather["run"]))
        self.assertEqual(copied, {"flutter-build-ipa.log", "export-upload.log"})
        self.assertNotRegex(str(upload["with"]["path"]), r"\.ipa|xcarchive")


if __name__ == "__main__":
    unittest.main()
