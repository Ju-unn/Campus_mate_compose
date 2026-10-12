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

    def test_signs_without_dev_certificate_and_uploads_with_api_key(self):
        joined = "\n".join(self.runs)
        self.assertIn("flutter build ipa --release --no-codesign", joined)
        self.assertIn('--build-number="$BUILD_NUMBER"', joined)
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
