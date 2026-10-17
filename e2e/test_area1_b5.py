"""영역 1 묶음 5(재부팅 · 식은 서버) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
학생증 검토 이후 가설(E-GATE-33 · 39~43 · 46 · 49)은 학생증 제거(10-17)로 서버 경로 · 앱 화면과 함께 뺐다.
저장소 루트에서 `python -m unittest e2e.test_area1_b5`."""

import unittest
from types import SimpleNamespace
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area1_b5
from e2e.test_area1_b3 import PhotoBase
from e2e.test_area1_phone import FakePhone
from e2e.tools import Reply

PHONE = ['E-AUTH-18']
COLD = 'E-AUTH-14'
GONE = ['E-GATE-33', 'E-GATE-39', 'E-GATE-40', 'E-GATE-41', 'E-GATE-42', 'E-GATE-43', 'E-GATE-46', 'E-GATE-49']


class BundleTest(unittest.TestCase):
    def test_bundle_has_the_phone_case_then_the_slow_cold_start_last(self):
        self.assertEqual(area1.BUNDLES['area1-b5'], PHONE + [COLD])
        self.assertIn(COLD, area1.CASES)
        self.assertLessEqual(set(PHONE), set(area1.PHONE))

    def test_student_id_review_cases_are_gone_everywhere(self):
        # 앱이 이 번호를 모르면 "모르는 가설" 로 실패한다 — 등록도 남기지 않는다.
        for case in GONE:
            self.assertNotIn(case, area1.CASES)
            self.assertNotIn(case, area1.PHONE)
            self.assertNotIn(case, area1_b5.tools.CASE_LIMITS)

    def test_cases_left_out_are_written_with_a_reason(self):
        for case in ('E-AUTH-15', 'E-ONB-09', 'E-ONB-42', 'E-ONB-05', 'E-ONB-74'):
            self.assertNotIn(case, area1.BUNDLES['area1-b5'])
            self.assertTrue(area1_b5.LEFT_OUT[case], case)


class TimeLimitTest(unittest.TestCase):
    """가설 하나에 420초 상한(tools.CASE_LIMIT)이 걸린다 — 재부팅을 기다리는 가설은 따로 늘려야 한다."""

    def test_the_reboot_case_gets_a_longer_limit_than_the_default(self):
        self.assertGreater(area1_b5.tools.CASE_LIMITS['E-AUTH-18'], area1_b5.tools.CASE_LIMIT)

    def test_the_cold_start_api_case_is_not_phone_limited(self):
        self.assertNotIn(COLD, area1.PHONE)
        # 서버 API 묶음은 상한을 안 건다 — 16분 쉬는 가설이 420초에 잘리면 안 된다(__main__.case_limit 은 폰 가설에만 건다)
        self.assertIsNone(cli.case_limit(COLD, phone_case=False))
        self.assertEqual(cli.case_limit('E-AUTH-18', phone_case=True), area1_b5.CASE_LIMIT_SLOW)


class Base5(PhotoBase):
    def phone(self, *answers, **kw):
        phone = FakePhone(*answers, **kw)
        phone.serial = 'S1'
        phone.hub = SimpleNamespace(port=8765)
        return phone

    def run_case(self, case):
        return area1.CASES[case](self.run)


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



if __name__ == '__main__':
    unittest.main()
