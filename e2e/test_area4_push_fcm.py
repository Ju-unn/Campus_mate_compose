"""영역 4 FCM 직접 발송 둘(E-PUSH-56 · 57)의 PC 쪽 시험 — 폰 · 운영 · gcloud · FCM 없이 가짜 gcloud · 가짜 HTTP · 가짜 알림창 · 가짜 앱으로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_fcm`.

가장 중요한 것: 액세스 토큰 · 프로젝트 주소 · FCM 응답 본문이 가설의 결과 줄 · 메모 · 예외 글 어디에도 안 나온다. 시험이 일부러 알아볼 수 있는 가짜 값(SECRET · PROJECT)을 쓰고 모든 출력에서 그것을 찾는다.
"""

import re
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from e2e import area1, area4_push_fcm as fcm, notify, tools
from e2e.tools import Blocked, Reply

SECRET = 'ya29.SECRET-ACCESS-TOKEN-xyz'
PROJECT = 'secret-project-123'
DEVICE = 'device-token-aaa'
SERIAL = 'emulator-5554'
HOME = {'home': True, 'conversations': False, 'room': False, 'reviews': False}
LIST = {'home': False, 'conversations': True, 'room': False, 'reviews': False}


class FakePhone:
    def __init__(self, answer):
        self.serial, self.answer, self.jobs = SERIAL, answer, []

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if midway:
            midway({'step': 'holding'})
        return {'result': 'pass', **self.answer}


class Base(unittest.TestCase):
    def setUp(self):
        self.tokens = [{'token': DEVICE}]
        self.sent, self.log = [], []
        self.shown = True  # 알림이 알림창에 뜨는가
        patchers = [
            mock.patch.object(fcm.area3_phone, '_person', lambda run: {'id': 'id-1', 'email': 'a@e2e.test', 'nickname': 'n'}),
            mock.patch.object(fcm, '_rows', lambda run, path: list(self.tokens)),
            mock.patch.object(fcm, '_wait_for', lambda until, seconds: bool(until())),
            mock.patch.object(fcm.notify, 'require_daytime', lambda: self.log.append('day')),
            mock.patch.object(fcm.notify, 'ensure_delivery', lambda serial: None),
            mock.patch.object(fcm.notify, 'read_notifications', lambda serial: []),
            mock.patch.object(fcm.notify, 'background', lambda serial: self.log.append('background')),
            mock.patch.object(fcm.notify, 'wait_new', self.wait_new),
            mock.patch.object(fcm.notify, 'tap_notification', lambda serial, title, body=None: self.log.append(('tap', title, body))),
            mock.patch.object(fcm.time, 'sleep', lambda s: None),
            mock.patch.object(fcm.notify, 'grant_notifications', lambda serial: None),
            mock.patch.object(fcm.notify, 'revoke_notifications', lambda serial: None),
        ]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        if not self.shown or not self.sent:
            return []
        _, title, body, _ = self.sent[-1]
        return [notify.Notice('k', title, body, 'c')]

    def fake_send(self, creds, token, title, body, data):
        self.sent.append((token, title, body, data))

    def run_case(self, case, answer, **kw):
        run = mock.Mock()
        run.link = lambda email: 'link-token'
        route, judge = {'E-PUSH-56': ('zzz', fcm._judge_56), 'E-PUSH-57': ('chat', fcm._judge_57)}[case]
        phone = FakePhone(answer)
        result = fcm._run(run, phone, route, judge, send=kw.get('send', self.fake_send), creds=kw.get('creds', lambda: (SECRET, PROJECT)))
        return result, phone

    def assert_clean(self, *outputs):
        for out in outputs:
            for secret in (SECRET, PROJECT):
                self.assertNotIn(secret, str(out))


class CaseTest(Base):
    def test_56_an_unknown_route_leaves_the_home_screen_as_it_was(self):
        (result, note), phone = self.run_case('E-PUSH-56', HOME)
        self.assertEqual(result, 'pass', note)
        token, title, body, data = self.sent[0]
        self.assertEqual((token, data), (DEVICE, {'route': 'zzz'}))
        self.assertEqual(phone.jobs[0]['route'], 'zzz')
        self.assertEqual(phone.jobs[0]['phase'], 'hold')
        self.assertEqual(self.log[-1][:2], ('tap', title))  # 알림창에서 그 알림을 눌렀다
        self.assertIn('background', self.log)

    def test_56_fails_when_the_app_jumped_to_another_screen_or_lost_home(self):
        for answer in ({**HOME, 'conversations': True}, {**HOME, 'room': True}, {**HOME, 'reviews': True}, {**HOME, 'home': False}):
            with self.subTest(answer):
                (result, note), _ = self.run_case('E-PUSH-56', answer)
                self.assertEqual(result, 'fail', note)

    def test_57_a_chat_notice_without_a_match_id_opens_the_list_and_not_a_room(self):
        (result, note), _ = self.run_case('E-PUSH-57', LIST)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.sent[0][3], {'route': 'chat'})  # match_id 를 안 싣는다

    def test_57_fails_when_the_list_does_not_open_or_a_room_opens(self):
        for answer in (HOME, {**LIST, 'room': True}):
            with self.subTest(answer):
                (result, note), _ = self.run_case('E-PUSH-57', answer)
                self.assertEqual(result, 'fail', note)

    def test_a_notice_that_never_arrives_is_a_fail_and_nothing_is_tapped(self):
        self.shown = False
        (result, note), _ = self.run_case('E-PUSH-56', HOME)
        self.assertEqual(result, 'fail', note)
        self.assertFalse([e for e in self.log if isinstance(e, tuple)])

    def test_it_only_runs_in_the_daytime(self):
        self.run_case('E-PUSH-56', HOME)
        self.assertEqual(self.log[0], 'day')

    def test_it_sends_nothing_unless_there_is_exactly_one_device_token(self):
        for tokens in ([], [{'token': 'a'}, {'token': 'b'}]):
            with self.subTest(len(tokens)):
                self.tokens = tokens
                self.sent.clear()
                with self.assertRaises(Blocked):
                    self.run_case('E-PUSH-56', HOME)
                self.assertEqual(self.sent, [])

    def test_gcloud_trouble_blocks_before_any_account_is_made(self):
        run = mock.Mock()
        made = []
        with mock.patch.object(fcm.area3_phone, '_person', lambda run: made.append(1)):
            with self.assertRaises(Blocked):
                fcm._run(run, FakePhone({}), 'zzz', fcm._judge_56, creds=lambda: (_ for _ in ()).throw(Blocked('gcloud 가 이 PC 에 없음')))
        self.assertEqual(made, [])

    def test_the_result_note_carries_no_secret(self):
        for case, answer in (('E-PUSH-56', HOME), ('E-PUSH-57', LIST), ('E-PUSH-56', {**HOME, 'conversations': True})):
            (result, note), _ = self.run_case(case, answer)
            self.assert_clean(result, note)

    def test_the_notice_title_is_random_so_an_old_notice_is_not_picked(self):
        self.run_case('E-PUSH-56', HOME)
        first = self.sent[0][1]
        self.sent.clear()
        self.run_case('E-PUSH-56', HOME)
        self.assertNotEqual(first, self.sent[0][1])
        self.assertTrue(re.fullmatch(r'E2E-[0-9a-f]{6}', first))


class GcloudTest(unittest.TestCase):
    def done(self, out='', code=0, err=''):
        return subprocess.CompletedProcess(['gcloud'], code, out, err)

    def test_it_reads_the_token_and_the_project_with_gcloud(self):
        calls = []

        def run(cmd, **kw):
            calls.append(cmd[1:])
            return self.done(SECRET if cmd[1] == 'auth' else PROJECT)
        with mock.patch.object(fcm.shutil, 'which', lambda name: 'gcloud'), mock.patch.object(fcm.subprocess, 'run', run):
            self.assertEqual(fcm.credentials(), (SECRET, PROJECT))
        self.assertEqual(calls, [['auth', 'print-access-token'], ['config', 'get-value', 'project']])

    def test_a_missing_or_failing_gcloud_is_blocked_with_no_output_in_the_message(self):
        with mock.patch.object(fcm.shutil, 'which', lambda name: None):
            with self.assertRaises(Blocked):
                fcm._gcloud('auth', 'print-access-token')
        with mock.patch.object(fcm.shutil, 'which', lambda name: 'gcloud'), \
                mock.patch.object(fcm.subprocess, 'run', lambda *a, **k: self.done(SECRET, 1, f'ERROR {PROJECT} {SECRET}')):
            with self.assertRaises(Blocked) as caught:
                fcm._gcloud('auth', 'print-access-token')
        self.assertNotIn(SECRET, str(caught.exception))
        self.assertNotIn(PROJECT, str(caught.exception))
        with mock.patch.object(fcm.shutil, 'which', lambda name: 'gcloud'), mock.patch.object(fcm.subprocess, 'run', lambda *a, **k: self.done('')):
            with self.assertRaises(Blocked):  # 프로젝트가 안 정해져 빈 출력
                fcm._gcloud('config', 'get-value', 'project')

    def test_a_gcloud_that_hangs_or_cannot_start_is_blocked(self):
        for error in (subprocess.TimeoutExpired('gcloud', 1), OSError(f'{SECRET}')):
            with self.subTest(type(error).__name__):
                def boom(*a, **k):
                    raise error
                with mock.patch.object(fcm.shutil, 'which', lambda name: 'gcloud'), mock.patch.object(fcm.subprocess, 'run', boom):
                    with self.assertRaises(Blocked) as caught:
                        fcm._gcloud('auth', 'print-access-token')
                self.assertNotIn(SECRET, str(caught.exception))


class SendTest(unittest.TestCase):
    def send(self, reply=None, error=None):
        seen = {}

        def call(method, url, headers=None, body=None, raw=None, tries=4, retry=True):
            seen.update(method=method, url=url, headers=headers, body=body, retry=retry)
            if error:
                raise error
            return reply
        with mock.patch.object(tools, 'call', call):
            try:
                fcm.fcm_send((SECRET, PROJECT), DEVICE, 'T', 'B', {'route': 'zzz'})
                failure = None
            except Blocked as blocked:
                failure = str(blocked)
        return seen, failure

    def test_the_request_has_the_shape_of_the_servers_fcm_sender_and_is_not_retried(self):
        seen, failure = self.send(Reply(200, {'name': f'projects/{PROJECT}/messages/1'}))
        self.assertIsNone(failure)
        self.assertEqual(seen['method'], 'POST')
        self.assertEqual(seen['url'], f'https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send')
        self.assertEqual(seen['headers'], {'Authorization': f'Bearer {SECRET}'})
        self.assertEqual(seen['body'], {'message': {'token': DEVICE, 'notification': {'title': 'T', 'body': 'B'},
                                                    'data': {'route': 'zzz'}, 'android': {'priority': 'high'}}})
        self.assertIs(seen['retry'], False)  # 재시도 기록에 경로(프로젝트 주소)가 남지 않게

    def test_the_server_payload_and_this_one_are_the_same_shape(self):
        source = (tools.ROOT / 'backend' / 'app' / 'cards' / 'push.py').read_text(encoding='utf-8')
        for piece in ('"token": token', '"notification": {"title": title, "body": body}', '"android": {"priority": "high"}',
                      'messages:send'):
            self.assertIn(piece, source)

    def test_every_failure_is_blocked_with_a_status_number_and_no_secret(self):
        for status in (400, 401, 403, 404, 429, 500):
            with self.subTest(status):
                _, failure = self.send(Reply(status, {'error': {'message': f'{SECRET} {PROJECT}'}}))
                self.assertIsNotNone(failure)
                self.assertIn(str(status), failure)
                self.assertNotIn(SECRET, failure)
                self.assertNotIn(PROJECT, failure)

    def test_a_network_error_never_leaks_its_own_text(self):
        _, failure = self.send(error=OSError(f'cannot reach https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send {SECRET}'))
        self.assertIsNotNone(failure)
        self.assertNotIn(PROJECT, failure)
        self.assertNotIn(SECRET, failure)


class RegistryTest(unittest.TestCase):
    def dart(self, name='area4_push_fcm.dart'):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_two_are_phone_cases_in_one_bundle_and_no_longer_left_out(self):
        from e2e import area4_push_a4
        self.assertEqual(area1.BUNDLES['area4-push-fcm'], ['E-PUSH-56', 'E-PUSH-57'])
        for case in ('E-PUSH-56', 'E-PUSH-57'):
            self.assertIs(area1.PHONE[case], fcm.PHONE[case])
            self.assertNotIn(case, area4_push_a4.LEFT_OUT)
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 420)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        self.assertIn('area4_push_fcm', main.__loader__.get_source('e2e.__main__'))

    def test_the_app_registers_the_two_and_the_part_is_wired(self):
        self.assertEqual(re.findall(r"^\s*'(E-PUSH-\d+)':", self.dart(), re.M), ['E-PUSH-56', 'E-PUSH-57'])
        self.assertIn("part 'area4_push_fcm.dart';", self.dart('area4.dart'))
        self.assertIn('..._pushFcmCases,', self.dart('area4.dart'))

    def test_every_key_the_pc_reads_is_a_key_the_app_says(self):
        said = set(re.findall(r"'(\w+)':", self.dart()))
        source = (tools.ROOT / 'e2e' / 'area4_push_fcm.py').read_text(encoding='utf-8')
        read = set(re.findall(r"said\.get\('(\w+)'", source)) | set(re.findall(r"for key in \(([^)]*)\)", source.split('def _judge_56')[1]))
        keys = {k for part in read for k in re.findall(r"\w+", part)}
        self.assertGreaterEqual(len(keys & {'home', 'conversations', 'room', 'reviews'}), 4)
        self.assertEqual(sorted(keys & {'home', 'conversations', 'room', 'reviews'} - said), [])

    def test_the_app_stops_once_at_holding_like_the_other_tap_cases(self):
        self.assertEqual(re.findall(r"step\('(\w+)'", self.dart()), ['holding'])

    def test_no_secret_is_written_in_the_files_or_printed(self):
        text = (tools.ROOT / 'e2e' / 'area4_push_fcm.py').read_text(encoding='utf-8')
        self.assertNotRegex(text, r'ya29\.')
        self.assertNotRegex(text, r'AIza|projects/[a-z][a-z0-9-]{4,}/')  # 실제 키 · 프로젝트 이름 모양
        self.assertNotIn('print(', text)
        self.assertNotIn('logging', text)

    def test_nothing_outside_the_test_files_changed(self):
        out = subprocess.run(['git', 'diff', '--name-only', 'origin/main...HEAD'], cwd=tools.ROOT, capture_output=True, text=True).stdout.split()
        self.assertEqual([p for p in out if p.startswith(('frontend/lib/', 'backend/', 'supabase/'))], [])


if __name__ == '__main__':
    unittest.main()
