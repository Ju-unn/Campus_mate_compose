"""가설 하나에 시간 상한을 거는 일 — 가짜 adb · 가짜 우편함으로, 기기 · 운영 없이 돈다.
발단: 에뮬 연락처 201명 넣기가 17분 넘게 걸려 SAFE-43 이 결과 없이 멈췄다(logcat 으로 보면 content 명령이 분당 33번, 603번 필요)."""

import subprocess
import time
import unittest
from unittest import mock

from e2e import __main__ as cli
from e2e import contacts, tools
from e2e.test_contacts import PEOPLE, ROWS, ScriptAdb
from e2e.test_emu import patched

S = 'emulator-5554'


class AdbTimeoutTest(unittest.TestCase):
    def run_adb(self, side_effect=None, **env):
        done = mock.Mock(stdout='ok')
        with mock.patch.object(tools.subprocess, 'run', side_effect=side_effect, return_value=done) as run:
            result = tools.adb(S, 'shell', 'ls')
        return result, run

    def test_every_adb_command_has_a_time_limit(self):
        result, run = self.run_adb()
        self.assertEqual(result, 'ok')
        self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT)

    def test_a_command_that_hangs_ends_the_case_instead_of_waiting_forever(self):
        with self.assertRaises(tools.CaseTimeout) as caught:
            self.run_adb(side_effect=subprocess.TimeoutExpired('adb', 1))
        self.assertIn('shell ls', str(caught.exception))

    def test_patience_lets_one_long_command_take_longer_and_then_goes_back(self):
        with tools.adb_patience(900):
            _, run = self.run_adb()
        self.assertEqual(run.call_args.kwargs['timeout'], 900)
        _, run = self.run_adb()
        self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT)

    def test_the_case_deadline_shortens_a_command_that_would_outlast_it(self):
        with tools.case_deadline(30):
            _, run = self.run_adb()
        self.assertLessEqual(run.call_args.kwargs['timeout'], 30)

    def test_after_the_deadline_the_next_adb_call_raises_once_then_cleanup_can_run(self):
        with tools.case_deadline(0.01):
            time.sleep(0.05)
            with self.assertRaises(tools.CaseTimeout):
                self.run_adb()
            result, _ = self.run_adb()  # 뒤처리(연락처 지우기 · 권한 되돌리기)는 막히지 않는다
        self.assertEqual(result, 'ok')

    def test_no_deadline_outside_a_case(self):
        _, run = self.run_adb()
        self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT)


class HubTimeoutTest(unittest.TestCase):
    def test_waiting_for_the_app_past_the_case_deadline_is_a_timeout_not_a_silent_none(self):
        hub = tools.Hub(0)
        try:
            with tools.case_deadline(0.05), self.assertRaises(tools.CaseTimeout):
                hub.wait(30)
        finally:
            hub.close()

    def test_a_wait_shorter_than_the_deadline_still_returns_none(self):
        hub = tools.Hub(0)
        try:
            with tools.case_deadline(30):
                self.assertIsNone(hub.wait(0.05))
        finally:
            hub.close()


class RunCaseTest(unittest.TestCase):
    def test_a_case_past_its_limit_is_blocked_with_where_it_stood_and_is_not_retried(self):
        calls = []

        def once(case):
            calls.append(case)
            raise tools.CaseTimeout('연락처 스크립트가 900초 안에 안 끝남')
        attempt, result, note = cli.run_case(once, 'E-SAFE-43', limit=420, where=lambda: '런처 화면')
        self.assertEqual((attempt, result), (1, 'blocked'))
        self.assertIn('시간 초과', note)
        self.assertIn('연락처 스크립트', note)
        self.assertIn('지금 보이는 것: 런처 화면', note)
        self.assertEqual(calls, ['E-SAFE-43'])

    def test_a_failing_where_does_not_hide_the_timeout(self):
        def once(case):
            raise tools.CaseTimeout('x')
        _, result, note = cli.run_case(once, 'E-A-01', limit=1, where=mock.Mock(side_effect=OSError('adb')))
        self.assertEqual(result, 'blocked')
        self.assertIn('시간 초과', note)

    def test_the_limit_is_set_for_the_case_and_cleared_after(self):
        seen = []
        cli.run_case(lambda case: seen.append(tools._deadline) or ('pass', ''), 'E-A-01', limit=60)
        self.assertIsNotNone(seen[0])
        self.assertIsNone(tools._deadline)

    def test_without_a_limit_nothing_is_set(self):
        seen = []
        cli.run_case(lambda case: seen.append(tools._deadline) or ('pass', ''), 'E-A-01')
        self.assertEqual(seen, [None])

    def test_a_fail_is_still_retried_once(self):
        answers = iter([('fail', 'x'), ('pass', '')])
        self.assertEqual(cli.run_case(lambda case: next(answers), 'E-A-01', limit=60), (2, 'pass', ''))

    def test_phone_cases_get_a_limit_and_api_cases_do_not(self):
        self.assertEqual(cli.case_limit('E-SAFE-35', phone_case=True), tools.CASE_LIMIT)
        self.assertIsNone(cli.case_limit('E-ANY-01', phone_case=False))

    def test_201_person_cases_are_allowed_longer_than_the_default(self):
        for case in ('E-SET-39', 'E-SAFE-43'):
            self.assertGreater(cli.case_limit(case, phone_case=True), tools.CASE_LIMIT, case)


class InsertSpeedTest(unittest.TestCase):
    def test_contact_inserts_are_run_a_few_at_a_time_not_one_by_one(self):
        adb = ScriptAdb({'content query': ROWS})
        with patched(adb):
            contacts.insert(S, PEOPLE)
        script = adb.scripts[1]  # 0 은 raw_contacts, 1 은 이름 · 번호
        lines = script.strip().splitlines()
        self.assertIn('wait', lines)
        self.assertTrue(any(line.rstrip().endswith('&') for line in lines))
        self.assertEqual(sum('content insert' in line for line in lines), 5)  # 이름 2 + 번호 3

    def test_the_insert_script_is_given_time_to_finish(self):
        patience = []
        adb = ScriptAdb({'content query': ROWS})
        real = tools.adb_patience

        def spy(seconds):
            patience.append(seconds)
            return real(seconds)
        with patched(adb), mock.patch.object(tools, 'adb_patience', spy):
            contacts.insert(S, PEOPLE)
        self.assertTrue(patience and max(patience) >= 600)


class BytesAndGuardsTest(unittest.TestCase):
    """화면 사진 · uiautomator dump 같은 바이트 출력과 `adb devices` 도 같은 상한을 쓴다(검토에서 timeout 없는 직접 호출로 지적)."""

    def test_screencap_has_the_adb_time_limit(self):
        with mock.patch.object(tools.subprocess, 'run', return_value=mock.Mock(stdout=b'png')) as run:
            self.assertEqual(tools.screencap(S), b'png')
        self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT)

    def test_a_hung_screencap_is_a_case_timeout_so_the_report_cannot_hang(self):
        with mock.patch.object(tools.subprocess, 'run', side_effect=subprocess.TimeoutExpired('adb', 1)), self.assertRaises(tools.CaseTimeout):
            tools.screencap(S)

    def test_the_ui_dumps_go_through_the_limited_call(self):
        from e2e import area2_phone3, notify
        for dump in (contacts._dump, area2_phone3._dump, notify._ui_dump):
            with mock.patch.object(tools.subprocess, 'run', return_value=mock.Mock(stdout='<xml/>'.encode())) as run:
                self.assertEqual(dump(S), '<xml/>')
            self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT, dump)

    def test_devices_has_the_time_limit(self):
        with mock.patch.object(tools.subprocess, 'run', return_value=mock.Mock(stdout='List')) as run:
            tools.devices()
        self.assertEqual(run.call_args.kwargs['timeout'], tools.ADB_TIMEOUT)


class CleanupAfterTimeoutTest(unittest.TestCase):
    def run_adb(self):
        with mock.patch.object(tools.subprocess, 'run', return_value=mock.Mock(stdout='ok')):
            return tools.adb(S, 'shell', 'ls')

    def test_a_command_cut_by_its_own_limit_also_lifts_the_case_deadline(self):
        with tools.case_deadline(1000):
            with mock.patch.object(tools.subprocess, 'run', side_effect=subprocess.TimeoutExpired('adb', 1)), self.assertRaises(tools.CaseTimeout):
                tools.adb(S, 'shell', 'ls')
            self.assertIsNone(tools._deadline)

    def test_cleanup_still_runs_when_the_body_finishes_after_the_deadline(self):
        ran = []

        def fake_run(cmd, **kw):  # 진짜 tools.adb 를 거쳐 상한 검사가 실제로 일어나게 한다
            line = ' '.join(cmd)
            ran.append(line)
            out = ROWS if 'content query' in line else ('READ_CONTACTS: granted=false' if 'dumpsys package' in line else '')
            return mock.Mock(stdout=out)
        with mock.patch.object(tools.subprocess, 'run', side_effect=fake_run), tools.case_deadline(1000):
            with self.assertRaises(tools.Blocked), contacts.on_device(S, PEOPLE, False):
                tools._deadline = time.monotonic() - 1  # 본문이 끝나기 전에 상한이 지났다
                raise tools.Blocked('x')
        self.assertTrue([c for c in ran if 'content delete' in c][-1:], '연락처 지우기가 안 불림')
        self.assertTrue([c for c in ran if 'pm revoke' in c], '권한 되돌리기가 안 불림')

    def test_a_script_cut_by_the_time_limit_is_killed_on_the_device(self):
        class Hangs(ScriptAdb):
            def __call__(self, serial, *args, check=True):
                if args[:3] == ('shell', 'sh', contacts.REMOTE):
                    raise tools.CaseTimeout('끝나지 않음')
                return super().__call__(serial, *args, check=check)
        adb = Hangs()
        with patched(adb), self.assertRaises(tools.CaseTimeout):
            contacts._run(S, ['content insert --uri x'])
        self.assertTrue(adb.ran(f'pkill -f {contacts.REMOTE}'))


class LiftTest(unittest.TestCase):
    def test_lift_keeps_a_deadline_that_has_not_passed_so_a_second_on_device_in_one_case_is_still_bounded(self):
        with tools.case_deadline(1000):
            tools.lift_deadline()
            self.assertIsNotNone(tools._deadline)

    def test_lift_releases_a_deadline_that_has_passed(self):
        with tools.case_deadline(1000):
            tools._deadline = time.monotonic() - 1
            tools.lift_deadline()
            self.assertIsNone(tools._deadline)


class WiringTest(unittest.TestCase):
    def test_a_phone_case_in_cmd_run_gets_the_limit_and_the_where_reporter(self):
        with mock.patch.object(cli, 'run_case', return_value=(1, 'pass', '')) as run_case:
            cli._run_one(mock.Mock(), 'E-SAFE-35', mock.Mock(), {})
        self.assertEqual(run_case.call_args.kwargs['limit'], tools.CASE_LIMIT)
        self.assertTrue(callable(run_case.call_args.kwargs['where']))

    def test_an_api_case_in_cmd_run_gets_no_limit(self):
        with mock.patch.object(cli, 'run_case', return_value=(1, 'pass', '')) as run_case:
            cli._run_one(mock.Mock(), next(k for k in cli.API_CASES if k not in cli.area1.PHONE), mock.Mock(), {})
        self.assertIsNone(run_case.call_args.kwargs['limit'])

    def test_where_saves_a_picture_and_names_the_top_screen(self):
        run = mock.Mock()
        run.shot.return_value = mock.Mock(name='shot')
        run.shot.return_value.name = 'E-X-시간초과.png'
        with mock.patch.object(tools, 'adb', return_value='  topResumedActivity=ActivityRecord{x com.android.launcher3/.Launcher}'):
            text = cli._where(run, {'sn': S}, 'E-X')
        self.assertIn('launcher3', text)
        self.assertIn('E-X-시간초과.png', text)

    def test_where_before_the_phone_was_opened_says_so(self):
        self.assertIn('안 만짐', cli._where(mock.Mock(), {}, 'E-X'))

    def test_the_ai_regeneration_cases_wait_longer_than_the_default(self):
        from e2e import area2_phone3
        for case in area2_phone3.AI:
            self.assertGreater(cli.case_limit(case, True), area2_phone3.AI_WAIT, case)


if __name__ == '__main__':
    unittest.main()
