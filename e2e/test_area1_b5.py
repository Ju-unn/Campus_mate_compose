"""영역 1 묶음 5(학생증 검토 이후 · 재부팅 · 식은 서버) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b5`."""

import unittest
from types import SimpleNamespace
from unittest import mock
from urllib.parse import urlsplit

from e2e import __main__ as cli
from e2e import area1, area1_b3, area1_b5
from e2e.test_area1_b3 import PhotoBase
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Reply

CASES = ['E-GATE-33', 'E-GATE-40', 'E-GATE-42', 'E-GATE-46', 'E-GATE-49']
PHONE = ['E-GATE-39', 'E-GATE-41', 'E-GATE-43', 'E-AUTH-18']
COLD = 'E-AUTH-14'
SUBMIT = ('POST', '/student-verification')
WITHDRAW = ('POST', '/account/withdraw')
PROFILES = ('GET', '/rest/v1/profiles')
ATTEMPTS = ('GET', '/rest/v1/student_verification_attempts')
FILES = ('POST', '/storage/v1/object/list/student-id-temp')
PENDING_ROW = {'result': 'pending', 'reject_reason': None, 'reviewed_at': None}
VERIFIED_ROW = {'result': 'verified', 'reject_reason': None, 'reviewed_at': '2026-10-05T00:00:00+00:00'}
ONE_FILE = Reply(200, [{'name': 'a.jpg', 'id': 'o1'}])
NO_FILE = Reply(200, [])
IS_PENDING = Reply(200, [{'student_verification': 'pending'}])


class BundleTest(unittest.TestCase):
    def test_bundle_has_the_api_cases_then_the_phone_cases_and_the_slow_cold_start_last(self):
        self.assertEqual(area1.BUNDLES['area1-b5'], CASES + PHONE + [COLD])
        self.assertLessEqual(set(CASES + [COLD]), set(area1.CASES))
        self.assertLessEqual(set(PHONE), set(area1.PHONE))

    def test_cases_left_out_are_written_with_a_reason(self):
        for case in ('E-AUTH-15', 'E-GATE-48', 'E-ONB-09', 'E-ONB-42', 'E-ONB-05', 'E-ONB-74'):
            self.assertNotIn(case, area1.BUNDLES['area1-b5'])
            self.assertTrue(area1_b5.LEFT_OUT[case], case)


class TimeLimitTest(unittest.TestCase):
    """가설 하나에 420초 상한(tools.CASE_LIMIT)이 걸린다 — 알림 60초를 계정마다 기다리거나 재부팅을 기다리는 가설은 따로 늘려야 한다."""

    def test_slow_phone_cases_get_a_longer_limit_than_the_default(self):
        for case in ('E-GATE-43', 'E-AUTH-18'):
            self.assertGreater(area1_b5.tools.CASE_LIMITS[case], area1_b5.tools.CASE_LIMIT, case)

    def test_the_quick_phone_cases_keep_the_default_limit(self):
        for case in ('E-GATE-39', 'E-GATE-41'):
            self.assertNotIn(case, area1_b5.tools.CASE_LIMITS)

    def test_the_cold_start_api_case_is_not_phone_limited(self):
        self.assertNotIn(COLD, area1.PHONE)
        # 서버 API 묶음은 상한을 안 건다 — 16분 쉬는 가설이 420초에 잘리면 안 된다(__main__.case_limit 은 폰 가설에만 건다)
        self.assertIsNone(cli.case_limit(COLD, phone_case=False))
        self.assertEqual(cli.case_limit('E-GATE-43', phone_case=True), area1_b5.CASE_LIMIT_SLOW)


class Base5(PhotoBase):
    def phone(self, *answers, **kw):
        phone = FakePhone(*answers, **kw)
        phone.serial = 'S1'
        phone.hub = SimpleNamespace(port=8765)
        return phone

    def writes(self, fake, method, table):
        return [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == method and f'/{table}' in urlsplit(u).path]

    def run_case(self, case):
        return area1.CASES[case](self.run)


class Gate33Test(Base5):
    def test_server_rechecks_the_name_without_uploading_anything(self):
        fake = self.serve({SUBMIT: [Reply(400, {'detail': area1_b5.REAL_NAME_REQUIRED}),
                                    Reply(400, {'detail': area1_b5.REAL_NAME_INVALID})]})
        self.assertEqual(self.run_case('E-GATE-33')[0], 'pass')
        sent = b''.join(raw for _, _, raw in fake.raws).decode('utf-8', 'replace')
        self.assertIn('\r\n\r\n 김 \r\n', sent)  # 앞뒤 공백 이름이 그대로 간다
        self.assertIn('\r\n\r\n김ㄱ\r\n', sent)  # 자모가 섞인 이름

    def test_fails_when_a_reply_is_accepted_or_has_the_wrong_text(self):
        self.serve({SUBMIT: [Reply(200, {'ok': True}), Reply(400, {'detail': area1_b5.REAL_NAME_REQUIRED})]})
        result, note = self.run_case('E-GATE-33')
        self.assertEqual(result, 'fail')
        self.assertIn('공백', note)
        self.assertIn('자모', note)

    def test_fails_when_a_file_or_an_attempt_was_left_behind(self):
        self.serve({SUBMIT: Reply(400, {'detail': area1_b5.REAL_NAME_REQUIRED}), FILES: ONE_FILE,
                    ATTEMPTS: Reply(200, [PENDING_ROW])})
        result, note = self.run_case('E-GATE-33')
        self.assertEqual(result, 'fail')
        self.assertIn('student-id-temp 파일 1개', note)
        self.assertIn('attempts 1행', note)


class SubmittedTest(Base5):
    """대기(pending) 계정을 API 로 만드는 공용 준비 — E-GATE-40 · 42 · 49 와 폰 3개가 쓴다."""

    def test_submits_the_set_photo_with_the_real_name_once_and_never_retries(self):
        self.put('id_name.jpg')
        fake = self.serve({PROFILES: IS_PENDING})
        account = area1_b5._submitted(self.run)
        self.assertEqual(account['id'], 'id-1')
        self.assertEqual([m for m, p, _ in fake.calls if p == '/student-verification'], ['POST'])
        self.assertIn(b'id_name.jpg', fake.raws[-1][2])  # 사진 세트의 그 파일이 올라간다
        self.assertIn('홍길동'.encode(), fake.raws[-1][2])

    def test_every_student_id_post_is_sent_without_retry_so_vision_runs_once(self):
        self.put('id_name.jpg')
        fake = self.serve({PROFILES: IS_PENDING, ATTEMPTS: Reply(200, [PENDING_ROW])})
        spy = mock.Mock(wraps=fake)
        with mock.patch.object(area1_b5.tools, 'call', spy):
            account = area1_b5._submitted(self.run)
            area1_b5._resubmit(self.run, account)
        posts = [c for c in spy.call_args_list if c.args[1].endswith('/student-verification')]
        self.assertEqual(len(posts), 2)
        self.assertTrue(all(c.kwargs.get('retry') is False for c in posts), [c.kwargs for c in posts])

    def test_blocks_when_the_photo_set_is_missing_before_making_an_account(self):
        fake = self.serve()
        with self.assertRaises(area1_b5.Blocked) as caught:
            area1_b5._submitted(self.run)
        self.assertIn('id_name.jpg', str(caught.exception))
        self.assertEqual(fake.users, [])

    def test_blocks_when_the_server_rejects_the_upload_or_does_not_hold_it_for_review(self):
        self.put('id_name.jpg')
        self.serve({SUBMIT: Reply(500, {'detail': 'x'})})
        with self.assertRaises(area1_b5.Blocked):
            area1_b5._submitted(self.run)
        self.serve({PROFILES: Reply(200, [{'student_verification': 'verified'}])})
        with self.assertRaises(area1_b5.Blocked) as caught:
            area1_b5._submitted(self.run)
        self.assertIn('verified', str(caught.exception))


class Gate40Test(Base5):
    def setUp(self):
        super().setUp()
        self.put('id_name.jpg')

    def test_resubmitting_while_in_review_is_409_and_adds_no_row(self):
        self.serve({PROFILES: IS_PENDING, ATTEMPTS: Reply(200, [PENDING_ROW]), FILES: ONE_FILE,
                    SUBMIT: [Reply(200, None), Reply(409, {'detail': area1_b5.IN_REVIEW})]})
        self.assertEqual(self.run_case('E-GATE-40')[0], 'pass')

    def test_fails_when_accepted_or_the_rows_grow(self):
        for second, rows in ((Reply(200, None), [PENDING_ROW]), (Reply(409, {'detail': area1_b5.IN_REVIEW}), [PENDING_ROW, PENDING_ROW])):
            self.serve({PROFILES: IS_PENDING, ATTEMPTS: [Reply(200, [PENDING_ROW]), Reply(200, rows)], FILES: ONE_FILE,
                        SUBMIT: [Reply(200, None), second]})
            self.assertEqual(self.run_case('E-GATE-40')[0], 'fail', second)


class Gate42Test(Base5):
    def setUp(self):
        super().setUp()
        self.put('id_name.jpg')

    def test_approving_in_the_dashboard_order_keeps_the_file(self):
        fake = self.serve({PROFILES: IS_PENDING, FILES: ONE_FILE})
        result, note = self.run_case('E-GATE-42')
        self.assertEqual(result, 'pass')
        self.assertIn('지워야', note)
        patches = [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == 'PATCH']
        self.assertEqual([urlsplit(u).path for u, _ in patches], ['/rest/v1/student_verification_attempts', '/rest/v1/profiles'])
        self.assertTrue(all('=eq.id-1' in u for u, _ in patches))  # 이 계정만
        self.assertEqual(patches[0][1]['result'], 'verified')
        self.assertTrue(patches[0][1]['reviewed_at'])
        self.assertEqual(patches[1][1], {'student_verification': 'verified'})

    def test_fails_when_the_file_vanished_by_itself(self):
        self.serve({PROFILES: IS_PENDING, FILES: [ONE_FILE, NO_FILE]})
        result, note = self.run_case('E-GATE-42')
        self.assertEqual(result, 'fail')
        self.assertIn('student-id-temp 파일 0개', note)

    def test_blocks_when_there_was_no_file_to_begin_with(self):
        self.serve({PROFILES: IS_PENDING, FILES: NO_FILE})
        with self.assertRaises(area1_b5.Blocked):
            area1.CASES['E-GATE-42'](self.run)


class Gate46Test(Base5):
    def test_a_verified_account_gets_409_and_no_file(self):
        self.serve({SUBMIT: Reply(409, {'detail': area1_b5.ALREADY_DONE})})
        self.assertEqual(self.run_case('E-GATE-46')[0], 'pass')

    def test_fails_when_accepted_or_a_file_went_up(self):
        self.serve({SUBMIT: Reply(200, None)})
        self.assertEqual(self.run_case('E-GATE-46')[0], 'fail')
        self.serve({SUBMIT: Reply(409, {'detail': area1_b5.ALREADY_DONE}), FILES: ONE_FILE})
        result, note = self.run_case('E-GATE-46')
        self.assertEqual(result, 'fail')
        self.assertIn('파일 1개', note)


class Gate49Test(Base5):
    def setUp(self):
        super().setUp()
        self.put('id_name.jpg')

    def test_withdrawing_in_review_clears_the_file_at_once(self):
        fake = self.serve({PROFILES: IS_PENDING, FILES: [ONE_FILE, NO_FILE], WITHDRAW: Reply(200, {'ok': True})})
        self.assertEqual(self.run_case('E-GATE-49')[0], 'pass')
        self.assertEqual([p for m, p, _ in fake.calls if p == '/account/withdraw'], ['/account/withdraw'])

    def test_fails_when_the_file_stays(self):
        self.serve({PROFILES: IS_PENDING, FILES: ONE_FILE, WITHDRAW: Reply(200, {'ok': True})})
        result, note = self.run_case('E-GATE-49')
        self.assertEqual(result, 'fail')
        self.assertIn('파일 1개', note)

    def test_blocks_when_the_file_was_never_there_and_does_not_withdraw(self):
        fake = self.serve({PROFILES: IS_PENDING, FILES: NO_FILE})
        with self.assertRaises(area1_b5.Blocked):
            self.run_case('E-GATE-49')
        self.assertNotIn('/account/withdraw', [p for _, p, _ in fake.calls])


class ColdStartTest(Base5):
    def run_cold(self, ticks, routes=None):
        self.serve(routes)
        with mock.patch.object(area1_b5.time, 'sleep') as sleep, mock.patch.object(area1_b5.time, 'monotonic', side_effect=ticks):
            return self.run_case(COLD), sleep

    def test_rests_over_fifteen_minutes_then_signs_up_and_notes_the_time(self):
        (result, note), sleep = self.run_cold([100.0, 102.4])
        self.assertEqual(result, 'pass')
        self.assertIn('2.4', note)
        sleep.assert_called_once_with(area1_b5.COLD_REST)
        self.assertGreater(area1_b5.COLD_REST, 15 * 60)

    def test_a_slow_but_successful_signup_passes_and_keeps_the_time_in_the_note(self):
        # 시나리오 통과 조건은 "가입 성공(훅 시간 초과 오류 0건)" — 훅이 5초를 넘기면 Supabase 가 오류를 내 200 이 아니다.
        # 잰 시간은 메일 발송까지 든 요청 전체라 5초 한도로 자르면 훅이 빨라도 틀리게 fail 이 난다(그러면 16분을 또 쉰다).
        (result, note), _ = self.run_cold([100.0, 105.2])
        self.assertEqual(result, 'pass')
        self.assertIn('5.2', note)

    def test_fails_when_the_signup_is_refused(self):
        (result, note), _ = self.run_cold([100.0, 101.0], {('POST', '/auth/v1/otp'): Reply(500, {'msg': 'hook timeout'})})
        self.assertEqual(result, 'fail')
        self.assertIn('500', note)


class PhoneBase(Base5):
    def setUp(self):
        super().setUp()
        self.put('id_name.jpg')

    def go(self, case, phone, routes=None):
        self.fake = self.serve({PROFILES: IS_PENDING, ATTEMPTS: Reply(200, [PENDING_ROW]), **(routes or {})})
        return area1.attempt_phone(self.run, case, phone)

    def grants(self):
        grant = ('S1', 'shell', 'pm', 'grant', area1_b5.tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS')
        return [c.args for c in self.adb_calls.call_args_list].count(grant)


class Gate39Test(PhoneBase):
    def test_launches_twice_the_second_time_without_a_new_login_and_keeps_one_pending_row(self):
        phone = self.phone()
        self.assertEqual(self.go('E-GATE-39', phone)[0], 'pass')
        first, second = phone.jobs
        self.assertIn('token_hash', first)
        self.assertEqual(second['fresh'], False)
        self.assertNotIn('token_hash', second)
        self.assertEqual(self.grants(), 1)

    def test_fails_when_the_second_launch_made_another_attempt_row(self):
        result, note = self.go('E-GATE-39', self.phone(), {ATTEMPTS: Reply(200, [PENDING_ROW, PENDING_ROW])})
        self.assertEqual(result, 'fail')
        self.assertIn('attempts', note)

    def test_app_failure_on_the_second_launch_is_kept(self):
        result, note = self.go('E-GATE-39', self.phone(APP_PASS, {'result': 'fail', 'note': '실명 칸 1개'}))
        self.assertEqual(result, 'fail')
        self.assertIn('실명 칸 1개', note)


class Gate41Test(PhoneBase):
    def test_pc_approves_while_the_app_waits_and_the_rows_end_verified(self):
        phone = self.phone(midway_step={'step': 'waiting'})
        fake_rows = {ATTEMPTS: Reply(200, [VERIFIED_ROW]), PROFILES: Reply(200, [{'student_verification': 'verified'}])}
        # 준비 때는 pending 이어야 하므로 프로필은 처음 한 번만 pending
        result = self.go('E-GATE-41', phone, {PROFILES: [IS_PENDING, fake_rows[PROFILES]], ATTEMPTS: fake_rows[ATTEMPTS]})
        self.assertEqual(result[0], 'pass')
        self.assertEqual(phone.acted, ['waiting'])
        patches = [urlsplit(u).path for (m, u) in self.fake.urls if m == 'PATCH']
        self.assertEqual(patches[-2:], ['/rest/v1/student_verification_attempts', '/rest/v1/profiles'])

    def test_fails_when_only_the_attempt_row_ended_verified(self):
        phone = self.phone(midway_step={'step': 'waiting'})
        result, note = self.go('E-GATE-41', phone, {ATTEMPTS: Reply(200, [VERIFIED_ROW])})
        self.assertEqual(result, 'fail')
        self.assertIn('profiles', note)

    def test_fails_when_the_rows_did_not_end_verified(self):
        phone = self.phone(midway_step={'step': 'waiting'})
        result, note = self.go('E-GATE-41', phone)
        self.assertEqual(result, 'fail')
        self.assertIn('verified', note)


class Auth18Test(Base5):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(area1_b5, '_reboot')
        self.reboot = patcher.start()
        self.addCleanup(patcher.stop)

    def test_logs_in_reboots_then_relaunches_without_a_new_login(self):
        self.serve()
        phone = self.phone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-18', phone)[0], 'pass')
        first, second = phone.jobs
        self.assertEqual(first['phase'], 'login')
        self.assertIn('token_hash', first)
        self.assertEqual((second['fresh'], second['expect'], second['phase']), (False, 'home', 'rebooted'))
        self.reboot.assert_called_once_with(phone)

    def test_does_not_reboot_when_the_first_login_failed(self):
        self.serve()
        phone = self.phone({'result': 'fail', 'note': '홈에 못 감'})
        result, note = area1.attempt_phone(self.run, 'E-AUTH-18', phone)
        self.assertEqual(result, 'fail')
        self.assertIn('홈에 못 감', note)
        self.reboot.assert_not_called()


class RebootTest(unittest.TestCase):
    """_reboot 자체 — adb 를 가짜로 부른다. getprop 은 [props] 를 차례로(마지막은 계속) 돌려준다: 빈 글자 = 기기가 내려가 있음."""

    def boot(self, props, locked=False):
        calls = []
        props = list(props)

        def adb(serial, *args, check=True):
            calls.append(args)
            if args[:2] == ('shell', 'getprop'):
                return props.pop(0) if len(props) > 1 else props[0]
            if args[:3] == ('shell', 'dumpsys', 'window'):
                return 'mKeyguardShowing=true' if locked else 'mKeyguardShowing=false'
            return ''

        phone = SimpleNamespace(serial='S1', hub=SimpleNamespace(port=8765))
        for patcher in (mock.patch.object(area1_b5.tools, 'adb', side_effect=adb), mock.patch.object(area1_b5.time, 'sleep')):
            patcher.start()
            self.addCleanup(patcher.stop)
        return phone, calls

    def test_reboots_waits_for_it_to_go_down_and_come_up_then_reconnects_the_app_mailbox(self):
        phone, calls = self.boot(['1', '', '', '0', '1'])
        area1_b5._reboot(phone)
        kinds = [c[0] if c[0] != 'shell' else f'shell {c[1]}' for c in calls]
        self.assertEqual(kinds[0], 'reboot')
        self.assertEqual(kinds.count('shell getprop'), 5)  # 내려가는 걸 보고 · 올라오는 걸 볼 때까지
        self.assertLess(max(i for i, k in enumerate(kinds) if k == 'shell getprop'), kinds.index('shell wm'))
        self.assertEqual(calls[-1], ('reverse', f'tcp:{area1_b5.tools.DEVICE_PORT}', 'tcp:8765'))

    def test_a_phone_that_never_goes_down_is_blocked_not_mistaken_for_booted(self):
        phone, _ = self.boot(['1'])  # 늘 켜져 있음 — 옛 부팅의 boot_completed=1 을 새 부팅으로 읽으면 안 된다
        with self.assertRaises(area1_b5.Blocked) as caught:
            area1_b5._reboot(phone)
        self.assertIn('내려가지', str(caught.exception))

    def test_blocks_when_the_phone_never_finishes_booting(self):
        phone, _ = self.boot([''])
        with self.assertRaises(area1_b5.Blocked) as caught:
            area1_b5._reboot(phone)
        self.assertIn('부팅', str(caught.exception))

    def test_blocks_when_a_screen_lock_is_still_up_after_booting(self):
        phone, calls = self.boot(['', '1'], locked=True)
        with self.assertRaises(area1_b5.Blocked) as caught:
            area1_b5._reboot(phone)
        self.assertIn('잠금', str(caught.exception))
        self.assertNotIn('reverse', [c[0] for c in calls])  # 잠긴 채로는 연결을 되살리지 않는다


class Gate43Test(Base5):
    TOKENS = ('GET', '/rest/v1/push_tokens')
    OKAY = area1_b5.APPROVED
    NO = area1_b5.REJECTED

    def setUp(self):
        super().setUp()
        self.put('id_name.jpg')
        names = {'require_daytime': mock.DEFAULT, 'read_notifications': mock.DEFAULT, 'background': mock.DEFAULT,
                 'wait_new': mock.DEFAULT, 'tap_notification': mock.DEFAULT}
        patcher = mock.patch.multiple(area1_b5.notify, **names)
        self.m = patcher.start()
        self.addCleanup(patcher.stop)
        sleep = mock.patch.object(area1_b5.time, 'sleep')
        sleep.start()
        self.addCleanup(sleep.stop)
        self.m['read_notifications'].return_value = []
        self.m['wait_new'].side_effect = lambda serial, before, seconds=60: [notice(*self.expected.pop(0))]
        self.expected = [self.OKAY, self.NO]

    def go(self, routes=None, phone=None):
        self.fake = self.serve({PROFILES: IS_PENDING, ATTEMPTS: Reply(200, [PENDING_ROW]), self.TOKENS: Reply(200, [{'token': 't'}]),
                                **(routes or {})})
        return area1.attempt_phone(self.run, 'E-GATE-43', phone or self.phone(midway_step={'step': 'waiting'}))

    def test_one_account_is_approved_and_one_rejected_and_each_notice_is_looked_for_by_its_exact_text(self):
        phone = self.phone(midway_step={'step': 'waiting'})
        self.assertEqual(self.go(phone=phone)[0], 'pass')
        self.assertEqual([job['verdict'] for job in phone.jobs], ['approved', 'rejected'])
        self.assertEqual(self.m['tap_notification'].call_args_list, [mock.call('S1', self.OKAY[0]), mock.call('S1', self.NO[0])])
        self.m['background'].assert_called()
        self.m['require_daytime'].assert_called_once()
        patches = [urlsplit(u).path for (m, u) in self.fake.urls if m == 'PATCH']
        self.assertIn('/rest/v1/student_verification_attempts', patches)

    def test_the_reject_reason_is_written_so_the_app_can_show_it(self):
        self.go()
        reasons = [b for (m, u), (_, _, b) in zip(self.fake.urls, self.fake.calls) if m == 'PATCH' and b and b.get('result') == 'rejected']
        self.assertEqual([r['reject_reason'] for r in reasons], [area1_b3.REJECT_REASON])

    def test_fails_when_the_notice_does_not_come_or_has_other_text(self):
        self.m['wait_new'].side_effect = lambda serial, before, seconds=60: [notice('다른 제목', '다른 본문')]
        result, note = self.go()
        self.assertEqual(result, 'fail')
        self.assertIn('알림', note)
        self.assertIn(self.OKAY[0], note)
        self.m['wait_new'].side_effect = lambda serial, before, seconds=60: []
        self.assertEqual(self.go()[0], 'fail')

    def test_blocks_at_night_before_making_any_account(self):
        self.m['require_daytime'].side_effect = area1_b5.Blocked('서울 시각 23:00')
        fake_before = self.serve()
        result, note = area1.attempt_phone(self.run, 'E-GATE-43', self.phone())
        self.assertEqual(result, 'blocked')
        self.assertEqual(fake_before.users, [])

    def test_blocks_when_the_device_token_never_reaches_the_server(self):
        result, note = self.go({self.TOKENS: Reply(200, [])})
        self.assertEqual(result, 'blocked')
        self.assertIn('토큰', note)
        self.m['background'].assert_not_called()


def notice(title, text):
    return area1_b5.notify.Notice(key=f'{title}', title=title, text=text, channel='c')


if __name__ == '__main__':
    unittest.main()
