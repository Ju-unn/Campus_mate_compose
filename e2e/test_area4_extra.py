"""영역 2·4 미등록 가설 10개 시험 — 운영 · 기기 없이 가짜 HTTP · 가짜 adb 로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area4_extra`."""

import os
import unittest
from unittest import mock

from e2e import area1, area2, area2_phone3, area4, area4_extra, tools, twodev
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.test_area2 import Base, Fake
from e2e.tools import Blocked, Reply

SIX_NOT_CODED = ['E-HEART-06', 'E-HEART-47', 'E-HEART-50', 'E-SET-55', 'E-SET-56', 'E-SET-57']


def paths_reply(*paths):
    return lambda b, u: Reply(200, {'paths': {p: {} for p in paths}})


class RegistryTest(unittest.TestCase):
    def test_each_case_is_in_exactly_the_registry_that_matches_its_signature(self):
        self.assertEqual(sorted(area4_extra.CASES), ['E-HEART-46'])  # (run)
        self.assertEqual(sorted(area4_extra.PHONE), ['E-HEART-49', 'E-HEART-51', 'E-SET-04', 'E-SET-12', 'E-SET-26',
                                                    'E-SET-43', 'E-SET-52', 'E-SET-53'])  # (run, phone)
        self.assertEqual(sorted(area4_extra.TWO), ['E-SET-67'])  # (run, two)
        for case, registry in (('E-HEART-46', area1.CASES), ('E-HEART-49', area1.PHONE), ('E-SET-53', area1.PHONE), ('E-SET-67', twodev.TWO)):
            self.assertIn(case, registry)
        self.assertNotIn('E-SET-67', area1.PHONE)
        self.assertNotIn('E-HEART-49', area1.CASES)

    def test_bundles_split_by_device(self):
        self.assertEqual(area1.BUNDLES['area4-extra'], ['E-HEART-49', 'E-HEART-51', 'E-SET-04', 'E-SET-12', 'E-SET-26'])
        self.assertEqual(area1.BUNDLES['area4-extra-emu'], ['E-SET-43', 'E-SET-52', 'E-SET-53'])
        self.assertEqual(area1.BUNDLES['area4-extra-two'], ['E-SET-67'])
        self.assertEqual(area1.BUNDLES['area4-extra-ai'], ['E-HEART-46'])

    def test_the_six_that_code_cannot_do_are_not_registered(self):
        every = {*area1.CASES, *area1.PHONE, *twodev.TWO}
        for case in SIX_NOT_CODED:
            self.assertNotIn(case, every)
        self.assertEqual(sorted(c for c in area4.LEFT_OUT if c in SIX_NOT_CODED), ['E-SET-55', 'E-SET-56', 'E-SET-57'])

    def test_the_two_device_case_has_a_long_enough_case_limit(self):
        self.assertGreater(tools.CASE_LIMITS['E-SET-67'], area4_extra.HOLD + 600)


class Heart46Test(Base):
    def setUp(self):
        super().setUp()
        area2_phone3._PAID.pop('E-HEART-46', None)
        self.addCleanup(area2_phone3._PAID.pop, 'E-HEART-46', None)

    def test_without_the_real_ai_switch_it_is_blocked_before_anything_is_made(self):
        fake = Fake()
        with mock.patch.object(tools, 'call', fake), mock.patch.dict(os.environ, {'E2E_REAL_AI': '0'}):
            result, memo = area2.attempt_with(self.run, area4_extra.heart_46)
        self.assertEqual(result, 'blocked')
        self.assertEqual(fake.calls, [])  # 계정도 만들지 않았다

    def test_a_second_call_after_money_was_spent_is_not_run_again(self):
        area2_phone3._PAID['E-HEART-46'] = ('fail', '하트 0')
        with mock.patch.dict(os.environ, {'E2E_REAL_AI': '1'}):
            self.assertEqual(area4_extra.heart_46(self.run), ('fail', '하트 0 — 유료 호출 뒤라 다시 하지 않음'))
            area2_phone3._PAID['E-HEART-46'] = ('pass', '')
            with self.assertRaises(Blocked):
                area4_extra.heart_46(self.run)


class OpenapiTest(Base):
    def run_case(self, case, rules, phone=None):
        phone = phone or FakePhone()
        with mock.patch.object(tools, 'call', Fake(rules)):
            return area1.attempt_phone(self.run, case, phone), phone

    def test_heart_49_passes_when_no_refund_gift_or_transfer_route_exists_and_asks_the_app(self):
        (result, memo), phone = self.run_case('E-HEART-49', [('GET', '/openapi.json', paths_reply('/me/hearts', '/heart-tasks/{task}'))])
        self.assertEqual(result, 'pass')
        self.assertEqual(len(phone.jobs), 1)

    def test_heart_49_names_a_forbidden_route(self):
        (result, memo), _ = self.run_case('E-HEART-49', [('GET', '/openapi.json', paths_reply('/me/hearts', '/hearts/Gift'))])
        self.assertEqual(result, 'fail')
        self.assertIn('/hearts/gift', memo)

    def test_an_unreadable_openapi_is_blocked_not_a_pass(self):
        for case in ('E-HEART-49', 'E-HEART-51'):
            rules = [('GET', '/openapi.json', lambda b, u: Reply(404, {'detail': 'x'})),
                     ('GET', '/cards/today', lambda b, u: Reply(200, {'cards': [], 'locked_card_available': False}))]
            (result, memo), _ = self.run_case(case, rules)
            self.assertEqual(result, 'blocked', case)
            self.assertIn('openapi', memo)

    def test_heart_51_passes_with_no_locked_card_and_no_store_route(self):
        rules = [('GET', '/cards/today', lambda b, u: Reply(200, {'cards': [], 'locked_card_available': False})),
                 ('GET', '/openapi.json', paths_reply('/cards/today'))]
        (result, memo), phone = self.run_case('E-HEART-51', rules)
        self.assertEqual(result, 'pass')

    def test_heart_51_fails_on_a_locked_card_a_missing_flag_or_a_store_route(self):
        for flag in (True, None):
            body = {'cards': []} if flag is None else {'cards': [], 'locked_card_available': flag}
            rules = [('GET', '/cards/today', lambda b, u, body=body: Reply(200, body)), ('GET', '/openapi.json', paths_reply('/cards/today'))]
            (result, memo), _ = self.run_case('E-HEART-51', rules)
            self.assertEqual(result, 'fail', flag)
            self.assertIn('locked_card_available', memo)
        rules = [('GET', '/cards/today', lambda b, u: Reply(200, {'cards': [], 'locked_card_available': False})),
                 ('GET', '/openapi.json', paths_reply('/heart_store/items'))]
        (result, memo), _ = self.run_case('E-HEART-51', rules)
        self.assertEqual(result, 'fail')
        self.assertIn('/heart_store/items', memo)


class RealContractTest(unittest.TestCase):
    def test_account_withdrawal_is_not_a_heart_withdrawal(self):
        self.assertEqual(area4_extra._named(['/account/withdraw', '/me/hearts'], area4_extra.FORBIDDEN_HEART), [])
        self.assertEqual(area4_extra._named(['/hearts/withdraw'], area4_extra.FORBIDDEN_HEART), ['/hearts/withdraw'])

    def test_a_real_sync_that_was_aborted_does_not_cut_the_hold_short(self):
        sync = twodev.Sync()
        sync.abort()  # A 가 먼저 끝났다
        plan = {}

        def two(p, **_):
            plan.update(p)
            return 'pass', 'ok'
        base = Set67Test('test_it_is_a_two_device_case_with_both_sides_steps_and_the_app_job_keys')
        base.setUp()
        self.addCleanup(base.tearDown)
        base.run_two(two)
        slept = []
        with mock.patch.object(area4_extra.time, 'sleep', slept.append):
            plan[('B', 'b-now')]({}, sync)
        self.assertEqual(slept, [area4_extra.HOLD])

    def test_the_two_batch_cases_are_wrapped_so_a_fail_is_not_rerun(self):
        self.assertIs(area1.PHONE['E-SET-04'].__wrapped__, area4_extra.p_set_04)
        self.assertIs(area1.PHONE['E-SET-43'].__wrapped__, area4_extra.p_set_43)


class MailDisabledTest(unittest.TestCase):
    QUERY = 'priority=0 preferredOrder=0\n  com.google.android.gm/.ComposeActivityGmail\n  com.android.email/.Compose\n'

    def fake_adb(self, outputs, calls):
        def adb(serial, *args, check=True):
            calls.append(args)
            if args[:3] == ('shell', 'pm', 'query-activities'):
                return outputs.pop(0) if len(outputs) > 1 else outputs[0]
            return 'Package x new state: disabled-user' if 'disable-user' in args else ''
        return adb

    def test_every_mail_app_is_turned_off_inside_and_back_on_after(self):
        calls = []
        with mock.patch.object(tools, 'adb', self.fake_adb(['', ''], calls)):
            pass
        calls.clear()
        outputs = [self.QUERY, '']  # 끈 뒤 다시 보면 없다
        with mock.patch.object(tools, 'adb', self.fake_adb(outputs, calls)):
            with area4_extra.mail_disabled('emulator-5554'):
                self.assertIn(('shell', 'pm', 'disable-user', '--user', '0', 'com.android.email'), calls)
                self.assertNotIn(('shell', 'pm', 'enable', 'com.android.email'), calls)
        self.assertIn(('shell', 'pm', 'enable', 'com.google.android.gm'), calls)
        self.assertIn(('shell', 'pm', 'enable', 'com.android.email'), calls)

    def test_they_are_turned_back_on_even_when_the_body_raises(self):
        calls = []
        with mock.patch.object(tools, 'adb', self.fake_adb([self.QUERY, ''], calls)):
            with self.assertRaises(RuntimeError):
                with area4_extra.mail_disabled('emulator-5554'):
                    raise RuntimeError('boom')
        self.assertIn(('shell', 'pm', 'enable', 'com.android.email'), calls)

    def test_a_failure_before_anything_is_off_does_not_crash_the_cleanup(self):
        def broken(serial, *args, check=True):
            raise tools.Blocked('adb 없음')
        with mock.patch.object(tools, 'adb', broken):
            with self.assertRaises(Blocked):
                with area4_extra.mail_disabled('emulator-5554'):
                    pass

    def test_an_app_that_will_not_turn_off_is_blocked_and_the_others_come_back(self):
        calls = []

        def adb(serial, *args, check=True):
            calls.append(args)
            if args[:3] == ('shell', 'pm', 'query-activities'):
                return self.QUERY
            return 'Package x new state: disabled-user' if 'com.android.email' in args else 'Error'
        with mock.patch.object(tools, 'adb', adb):
            with self.assertRaises(Blocked):
                with area4_extra.mail_disabled('emulator-5554'):
                    pass
        self.assertIn(('shell', 'pm', 'enable', 'com.android.email'), calls)  # 이미 끈 것은 되켠다

    def test_a_real_phone_is_refused(self):
        with self.assertRaises(Blocked):
            with area4_extra.mail_disabled('R5CT123'):
                pass

    def test_mail_apps_are_read_from_the_sendto_query(self):
        with mock.patch.object(tools, 'adb', lambda s, *a, check=True: self.QUERY):
            self.assertEqual(area4_extra.mail_apps('emulator-5554'), ['com.android.email', 'com.google.android.gm'])


class Set12Test(Base):
    def world(self, new_message=None):
        """실제 서버처럼 — 새 계정은 notification_settings 행이 없고(16d 를 열어도 읽기만 한다), PostgREST PATCH 는 없는 행에는 아무 일도 안 하고,
        행은 앱 경로(PATCH /cards/notification-settings)가 처음 쓸 때 만든다(upsert). [new_message] 가 None 이면 행 없음."""
        state = {} if new_message is None else {'new_message': new_message}

        def read(body, url):
            return Reply(200, [dict(state)] if state else [])

        def rest_write(body, url):
            if state:
                state.update(body)
            return Reply(204, None)

        def api_write(body, url):
            state.update({'new_message': True, **state, **body})
            return Reply(200, {})
        return state, Fake([('GET', 'notification_settings', read), ('PATCH', 'notification_settings', rest_write),
                            ('PATCH', '/cards/notification-settings', api_write)])

    def test_another_device_turns_it_off_in_the_middle_and_the_app_is_asked_twice(self):
        state, fake = self.world()  # 새 홈 계정 — 행이 아직 없다
        phone = FakePhone()
        with mock.patch.object(tools, 'call', fake):
            result, memo = area1.attempt_phone(self.run, 'E-SET-12', phone)
        self.assertEqual((result, state.get('new_message')), ('pass', False), memo)
        self.assertEqual([j.get('phase') for j in phone.jobs], ['opened', 'relaunched'])
        self.assertTrue(phone.jobs[1]['fresh'] is False)

    def test_a_switch_that_was_already_off_is_a_wrong_setup_not_a_pass(self):
        state, fake = self.world(False)
        with mock.patch.object(tools, 'call', fake):
            result, memo = area1.attempt_phone(self.run, 'E-SET-12', FakePhone())
        self.assertEqual(result, 'blocked')


class Set26Test(Base):
    def world(self, unblocked=True, left='2026-10-06T00:00:00+00:00'):
        return Fake([
            ('GET', 'match_participants', lambda b, u: Reply(200, [{'left_at': left}])),
            ('GET', 'blocks?blocker_id', lambda b, u: Reply(200, [] if unblocked else [{'blocker_id': 'x'}])),
            ('GET', 'select=nickname', lambda b, u: Reply(200, [{'nickname': 'Bbbbb'}])),
        ])

    def test_unblocked_and_the_room_stays_left(self):
        phone = FakePhone()
        fake = self.world()
        with mock.patch.object(tools, 'call', fake):
            result, memo = area1.attempt_phone(self.run, 'E-SET-26', phone)
        self.assertEqual(result, 'pass')
        self.assertIn('/blocks/', ' '.join(p for m, p, _ in fake.calls if m == 'POST'))
        self.assertEqual(phone.jobs[0]['nickname'], 'Bbbbb')

    def test_a_block_row_that_is_still_there_or_a_restored_room_is_a_fail(self):
        with mock.patch.object(tools, 'call', self.world(unblocked=False)):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-26', FakePhone())[0], 'fail')
        with mock.patch.object(tools, 'call', Fake([('GET', 'match_participants', lambda b, u: Reply(200, [{'left_at': None}]))])):
            # 차단 직후부터 방을 안 나간 것 — 준비가 틀린 것이라 blocked
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-26', FakePhone())[0], 'blocked')


class FakeSync:
    def __init__(self, set_names=()):
        self.names = set(set_names)
        self.waited = []

    def set(self, name):
        self.names.add(name)

    def wait(self, name, seconds):
        self.waited.append((name, seconds))
        return name in self.names or name == 'hold-never'


class Set67Test(Base):
    def run_two(self, fake_two=None):
        seen = {}

        def two(plan, a_job=None, b_job=None, **limit):
            seen.update(plan=plan, a_job=a_job, b_job=b_job, limit=limit)
            return 'pass', 'ok'
        with mock.patch.object(tools, 'call', self.server()):
            result = twodev.TWO['E-SET-67'](self.run, fake_two or two)
        return result, seen

    def capture_plan(self):
        return self.run_two()[1]

    @staticmethod
    def server(*rules):
        return Fake([*rules, ('GET', 'select=nickname', lambda b, u: Reply(200, [{'nickname': 'Bbbbb'}]))])

    def test_it_is_a_two_device_case_with_both_sides_steps_and_the_app_job_keys(self):
        result, seen = self.run_two()
        self.assertEqual(result[0], 'pass')
        self.assertEqual(set(seen['plan']), {('A', 'a-in'), ('A', 'a-out'), ('B', 'wait'), ('B', 'b-in'), ('B', 'b-now')})
        self.assertIn('token_hash', seen['a_job'])
        self.assertNotIn('token_hash', seen['b_job'])  # B 는 A 가 로그인한 뒤에 토큰을 받는다
        self.assertEqual(seen['a_job']['nickname'], seen['b_job']['nickname'])
        self.assertGreaterEqual(seen['limit']['side_timeout']['B'], area4_extra.HOLD + 300)

    def test_b_gets_its_token_only_after_a_is_in_and_a_waits_for_b(self):
        result, seen = self.run_two()
        with mock.patch.object(tools, 'call', self.server()):
            with self.assertRaises(Blocked):
                seen['plan'][('B', 'wait')]({}, FakeSync())  # A 가 안 들어왔다
            sync = FakeSync({'a-in'})
            self.assertIn('token_hash', seen['plan'][('B', 'wait')]({}, sync))
        sync = FakeSync({'b-in'})
        seen['plan'][('A', 'a-in')]({}, sync)
        self.assertIn('a-in', sync.names)

    def test_b_holds_for_five_minutes_after_a_signed_out_and_the_server_account_is_checked(self):
        with mock.patch.object(area4_extra, 'HOLD', 7):
            result, seen = self.run_two()
            sync = FakeSync({'a-out'})
            with mock.patch.object(tools, 'call', self.server(('GET', '/profiles/me', lambda b, u: Reply(200, {'ok': 1})))):
                seen['plan'][('B', 'b-in')]({}, sync)
            slept = []
            with mock.patch.object(area4_extra.time, 'sleep', slept.append):
                self.assertEqual(slept, [])  # b-in(곧바로 보기)은 기다리지 않는다 — 위에서 이미 불렀다
                seen['plan'][('B', 'b-now')]({}, sync)
            self.assertEqual(slept, [7])
        self.assertIn('b-in', sync.names)

    def test_a_server_that_no_longer_knows_the_account_after_the_logout_is_a_fail(self):
        def two(plan, a_job=None, b_job=None, **limit):
            with mock.patch.object(tools, 'call', self.server(('GET', '/profiles/me', lambda b, u: Reply(401, {'detail': 'x'})))):
                plan[('B', 'b-in')]({}, FakeSync({'a-out'}))
            return 'pass', 'ok'
        with mock.patch.object(tools, 'call', self.server()):
            result = twodev.TWO['E-SET-67'](self.run, two)
        self.assertEqual(result[0], 'fail')


if __name__ == '__main__':
    unittest.main()
