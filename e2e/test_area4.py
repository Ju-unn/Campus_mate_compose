"""영역 4 설정(SET) 1차 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 상태를 가진 가짜 DB 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4`."""

import json
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from e2e import area1, area4, notify, tools
from e2e.test_area1 import FakeServer, Base
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Blocked, Reply

DEFAULTS = {'card_arrived': True, 'acceptance_received': True, 'match_made': True, 'new_message': True,
            'trust_reminder': True, 'new_friend_review': True, 'marketing': False, 'quiet_hours': True}
SEOUL = timezone(timedelta(hours=9))


class FakeDb(FakeServer):
    """알림 스위치 · 프로필 · 비공개 · 차단 표를 기억하는 가짜 운영. PATCH 가 행을 바꾸고 GET 이 읽는다."""

    def __init__(self, routes=None):
        super().__init__(routes)
        self.settings = None  # 행이 없으면 None
        self.profiles = {}  # id → 행
        self.private = {}
        self.blocks = []

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        parts = urlsplit(url)
        path, query = parts.path, parse_qs(parts.query)
        self.calls.append((method, path, body))
        self.urls.append((method, url))
        if path == '/cards/notification-settings' and method == 'PATCH':
            self.settings = {**(self.settings or DEFAULTS), **body}
            return Reply(200, {'ok': True})
        if path == '/rest/v1/notification_settings':
            if method == 'GET':
                return Reply(200, [self.settings] if self.settings else [])
            if method == 'DELETE':
                self.settings = None
                return Reply(204, None)
        if path == '/rest/v1/profiles' and method in ('GET', 'PATCH'):
            who = query.get('id', [None])[0]
            who = who.replace('eq.', '') if who else next(iter(self.profiles), None)
            if method == 'PATCH':
                self.profiles.setdefault(who, {}).update(body)
                return Reply(200, None)
            if who not in self.profiles and 'nickname' in query.get('select', [''])[0]:
                return Reply(200, [{'nickname': f'nick-{who}'}])  # 닉네임만 읽는 가설은 아무 계정이나 있다
            return Reply(200, [self.profiles[who]] if who in self.profiles else [])
        if path == '/rest/v1/profile_private' and method in ('GET', 'PATCH'):
            who = query.get('profile_id', [None])[0]
            who = who.replace('eq.', '') if who else next(iter(self.private), None)
            if method == 'PATCH':
                self.private.setdefault(who, {}).update(body)
                return Reply(200, None)
            return Reply(200, [self.private[who]] if who in self.private else [])
        if path == '/rest/v1/blocks':
            if method == 'POST':
                self.blocks += body if isinstance(body, list) else [body]
                return Reply(201, None)
            if method == 'GET':
                return Reply(200, [dict(b) for b in self.blocks])
        return super().__call__(method, url, headers, body, raw)


def serve_db(case, **tables):
    patcher = mock.patch.object(tools, 'call', db := FakeDb())
    patcher.start()
    case.addCleanup(patcher.stop)
    for name, value in tables.items():
        setattr(db, name, value)
    return db


class AirplaneTest(unittest.TestCase):
    def test_enable_runs_the_command_and_confirms_the_state(self):
        calls = []

        def fake_adb(serial, *args, check=True):
            calls.append(args)
            return 'enabled\n' if args[-1] == 'airplane-mode' else ''

        with mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(notify.time, 'sleep'):
            notify.airplane('S', True)
        self.assertEqual(calls[0], ('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable'))
        self.assertEqual(calls[-1], ('shell', 'cmd', 'connectivity', 'airplane-mode'))

    def test_state_that_does_not_change_is_blocked_not_fail(self):
        with mock.patch.object(tools, 'adb', return_value='disabled\n'), mock.patch.object(notify.time, 'sleep'):
            with self.assertRaises(Blocked):
                notify.airplane('S', True)

    def test_disable_waits_for_the_network_to_come_back(self):
        sleeps = []
        with mock.patch.object(tools, 'adb', return_value='disabled\n'), \
                mock.patch.object(notify.time, 'sleep', sleeps.append):
            notify.airplane('S', False, settle=7)
        self.assertEqual(sleeps, [7])


class EnsureOnlineTest(unittest.TestCase):
    def run_with(self, states):
        calls, sleeps = [], []
        answers = iter(states)

        def fake_adb(serial, *args, check=True):
            calls.append(args)
            return next(answers) if args[-1] == 'airplane-mode' else ''

        with mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(notify.time, 'sleep', sleeps.append):
            notify.ensure_online('S')
        return calls, sleeps

    def test_turns_airplane_off_and_waits_the_full_settle_when_still_on(self):
        calls, sleeps = self.run_with(['enabled\n', 'disabled\n'])
        self.assertIn(('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable'), calls)
        self.assertEqual(sleeps, [notify.SETTLE_SECONDS])

    def test_does_nothing_when_already_online(self):
        calls, sleeps = self.run_with(['disabled\n'])
        self.assertEqual(calls, [('shell', 'cmd', 'connectivity', 'airplane-mode')])
        self.assertEqual(sleeps, [])


class StepperTest(unittest.TestCase):
    def test_handlers_run_once_per_app_step_with_go_between(self):
        events = []

        class Hub:
            def __init__(self):
                self.said = [{'step': 'b'}, {'step': 'c'}]

            def go(self):
                events.append('go')

            def wait(self, timeout):
                return self.said.pop(0)

        phone = mock.Mock(hub=Hub(), serial='S')
        midway = area4.stepper(phone, lambda s: events.append('a'), lambda s: events.append(s['step']),
                               lambda s: events.append(s['step']))
        midway({'step': 'a'})
        # 마지막 go 는 Run.phone 이 넣는다 — 여기서는 단계 사이에만.
        self.assertEqual(events, ['a', 'go', 'b', 'go', 'c'])

    def test_app_that_goes_silent_in_the_middle_is_blocked(self):
        phone = mock.Mock(hub=mock.Mock(wait=mock.Mock(return_value=None)), serial='S')
        with self.assertRaises(Blocked):
            area4.stepper(phone, lambda s: None, lambda s: None)({'step': 'a'})


class SwitchesApiTest(Base):
    def test_set_08_each_switch_flips_only_its_own_column(self):
        db = serve_db(self)
        self.assertEqual(area4.CASES['E-SET-08'](self.run), ('pass', ''))
        patches = [b for m, p, b in db.calls if p == '/cards/notification-settings']
        self.assertEqual(len(patches), 8)
        self.assertEqual([list(b) for b in patches], [[k] for k in DEFAULTS])  # 하나씩
        self.assertEqual(db.settings, {k: not v for k, v in DEFAULTS.items()})

    def test_set_08_fails_when_a_switch_changes_two_columns(self):
        db = serve_db(self)
        original = db.__call__

        def sloppy(method, url, headers=None, body=None, raw=None):
            if method == 'PATCH' and body == {'new_message': False}:
                body = {'new_message': False, 'trust_reminder': False}
            return original(method, url, headers, body, raw)

        with mock.patch.object(tools, 'call', sloppy):
            result, note = area4.CASES['E-SET-08'](self.run)
        self.assertEqual(result, 'fail')
        self.assertIn('trust_reminder', note)


class PhoneCaseTest(Base):
    def attempt(self, case, *answers, **tables):
        db = serve_db(self, **tables)
        phone = FakePhone(*answers)
        phone.serial = 'S'
        phone.hub = mock.Mock(wait=mock.Mock(return_value={'step': 'next'}))  # 두 번 멈추는 가설용 우편함
        with mock.patch.object(area4.notify, 'airplane') as plane, \
                mock.patch.object(area4.notify, 'ensure_online') as online:
            result = area1.attempt_phone(self.run, case, phone)
        self.online = online
        return result, phone, db, plane

    def test_set_05_pauses_matching_in_the_db_then_the_app_must_see_it_off(self):
        (result, note), phone, db, _ = self.attempt('E-SET-05')
        self.assertEqual(result, 'pass')
        self.assertEqual(phone.jobs[0]['paused'], True)
        self.assertTrue(any(p == '/rest/v1/profiles' and b == {'matching_paused': True} for m, p, b in db.calls))

    def test_set_07_needs_an_account_without_a_settings_row(self):
        (result, note), phone, _, _ = self.attempt('E-SET-07', settings=dict(DEFAULTS))
        self.assertEqual(result, 'blocked')

    def test_set_07_default_account_starts_the_app(self):
        (result, _), phone, _, _ = self.attempt('E-SET-07')
        self.assertEqual((result, 'token_hash' in phone.jobs[0]), ('pass', True))

    def test_set_09_app_flips_three_then_restart_must_show_the_db_values(self):
        db = serve_db(self)
        phone = FakePhone(APP_PASS)
        phone.serial = 'S'

        def app(midway=None, **job):  # 첫 켬에서 앱이 세 개를 눌렀다고 보고 DB 에 반영
            phone.jobs.append(job)
            if 'flip' in job:
                db.settings = {**DEFAULTS, **{k: not DEFAULTS[k] for k in job['flip']}}
            return APP_PASS

        result = area1.attempt_phone(self.run, 'E-SET-09', app)
        self.assertEqual(result[0], 'pass')
        first, second = phone.jobs
        self.assertEqual(sorted(first['flip']), ['marketing', 'new_message', 'quiet_hours'])
        self.assertEqual(second['fresh'], False)
        self.assertEqual(second['switches'], db.settings)

    def test_set_09_fails_when_the_db_did_not_take_the_flips(self):
        serve_db(self)
        (result, note), _, _, _ = self.attempt('E-SET-09')
        self.assertEqual(result, 'fail')
        self.assertIn('notification_settings', note)

    def test_set_14_expected_seven_cells_come_from_the_db(self):
        when = datetime(2026, 3, 14, 15, 30, tzinfo=timezone.utc).isoformat()
        profiles = {'id-1': {'birth_year': 2004, 'created_at': when, 'universities': {'name': '테스트대'}}}
        private = {'id-1': {'real_name': None, 'kakao_id': 'e2e1001'}}
        (result, _), phone, _, _ = self.attempt('E-SET-14', profiles=profiles, private=private)
        self.assertEqual(result, 'pass')
        self.assertEqual(phone.jobs[0]['texts'], ['base+e2e1001@gmail.com', '인증 완료', '—', '2004', '테스트대', 'e2e1001', '2026.03.15'])

    def test_set_15_sets_created_at_to_korean_00_30(self):
        (result, _), phone, db, _ = self.attempt('E-SET-15')
        self.assertEqual(result, 'pass')
        patch = [b for m, p, b in db.calls if p == '/rest/v1/profiles' and m == 'PATCH' and 'created_at' in b][0]
        moment = datetime.fromisoformat(patch['created_at']).astimezone(SEOUL)
        self.assertEqual((moment.hour, moment.minute), (0, 30))
        self.assertEqual(phone.jobs[0]['date'], moment.strftime('%Y.%m.%d'))

    def test_set_16_empties_only_the_real_name_so_the_account_screen_still_opens(self):
        (result, _), phone, db, _ = self.attempt('E-SET-16')
        self.assertEqual(result, 'pass')
        self.assertEqual(phone.jobs[0]['dashes'], 1)
        # 활성 계정은 출생연도가 비면 DB 제약(profiles_active_requires_onboarding)이 막고, 카톡 아이디가 비면 서버 온보딩 판정
        # (onboarding_progress.py 의 kakao_id 단계)이 앱을 온보딩으로 보내 계정 화면에 못 간다(폰 10-04) — 실명만 비운다.
        self.assertNotIn(('PATCH', '/rest/v1/profiles', {'birth_year': None}), db.calls)
        kakao = [b for m, p, b in db.calls if p == '/rest/v1/profile_private' and m == 'PATCH']
        self.assertEqual(kakao, [{'real_name': None}])

    def test_set_19_new_kakao_id_must_land_in_the_db(self):
        db = serve_db(self)
        sent = {}

        def app(midway=None, **job):
            sent.update(job)
            db.private.setdefault('id-1', {})['kakao_id'] = job['value']
            return APP_PASS

        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-19', app)[0], 'pass')
        self.assertRegex(sent['value'], r'^e2e\d+')

    def test_set_19_fails_when_the_db_keeps_the_old_id(self):
        (result, note), _, _, _ = self.attempt('E-SET-19', private={'id-1': {'kakao_id': 'old'}})
        self.assertEqual(result, 'fail')
        self.assertIn('kakao_id', note)

    def test_set_21_trimmed_value_is_what_is_saved(self):
        db = serve_db(self)

        def app(midway=None, **job):
            db.private.setdefault('id-1', {})['kakao_id'] = job['value'].strip()
            return APP_PASS

        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-21', app)[0], 'pass')

    def test_set_20_blank_never_reaches_the_db(self):
        (result, _), phone, db, _ = self.attempt('E-SET-20', private={'id-1': {'kakao_id': 'keep'}})
        self.assertEqual(result, 'pass')

    def test_set_20_fails_if_the_db_changed(self):
        db = serve_db(self, private={'id-1': {'kakao_id': 'keep'}})

        def app(midway=None, **job):
            db.private['id-1']['kakao_id'] = ''
            return APP_PASS

        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-20', app)[0], 'fail')

    def test_cut_only_cases_cut_once_and_leave_the_restore_to_ensure_online(self):
        for case in ('E-SET-06', 'E-SET-10', 'E-SET-22'):
            with self.subTest(case):
                (result, _), phone, _, plane = self.attempt(case, private={'id-1': {'kakao_id': 'keep'}}) \
                    if case == 'E-SET-22' else self.attempt(case)
                self.assertEqual(result, 'pass', case)
                self.assertEqual([c.args[1] for c in plane.call_args_list], [True], case)
                self.online.assert_called_once_with('S')

    def test_set_17_cuts_then_restores_in_the_middle_then_checks_once_more(self):
        (result, _), _, _, plane = self.attempt('E-SET-17')
        self.assertEqual(result, 'pass')
        self.assertEqual([c.args[1] for c in plane.call_args_list], [True, False])
        self.online.assert_called_once_with('S')

    def test_set_06_fails_when_matching_got_paused_while_offline(self):
        (result, note), _, _, _ = self.attempt('E-SET-06', profiles={'id-1': {'matching_paused': True}})
        self.assertEqual(result, 'fail')
        self.assertIn('matching_paused', note)

    def test_set_10_fails_when_a_settings_row_appeared_while_offline(self):
        (result, note), _, _, _ = self.attempt('E-SET-10', settings=dict(DEFAULTS))
        self.assertEqual(result, 'fail')
        self.assertIn('notification_settings', note)

    def test_network_is_restored_even_when_the_app_fails(self):
        db = serve_db(self)
        phone = FakePhone({'result': 'fail', 'note': 'x'})
        phone.serial = 'S'
        with mock.patch.object(area4.notify, 'airplane'), mock.patch.object(area4.notify, 'ensure_online') as online:
            result = area1.attempt_phone(self.run, 'E-SET-06', phone)
        self.assertEqual(result[0], 'fail')
        online.assert_called_once_with('S')

    def test_set_25_two_blocked_users_with_their_nicknames_and_today(self):
        db = serve_db(self)
        (result, _), phone, db, _ = self.attempt('E-SET-25')
        self.assertEqual(result, 'pass')
        self.assertEqual(len(db.blocks), 2)
        self.assertEqual(len(phone.jobs[0]['nicknames']), 2)
        self.assertTrue(all(__import__('re').fullmatch(r'\d{4}\.\d{2}\.\d{2}', d) for d in phone.jobs[0]['dates']))

    def test_set_27_cancel_keeps_both_rows(self):
        db = serve_db(self)
        (result, _), _, _, _ = self.attempt('E-SET-27')
        self.assertEqual(result, 'pass')

    def test_set_27_fails_when_a_row_disappeared(self):
        db = serve_db(self)

        def app(midway=None, **job):
            db.blocks.pop()
            return APP_PASS

        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-27', app)[0], 'fail')

    def test_set_28_last_unblock_empties_the_table(self):
        db = serve_db(self)

        def app(midway=None, **job):
            db.blocks.clear()
            return APP_PASS

        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-28', app)[0], 'pass')

    def test_set_28_fails_when_the_row_is_still_there(self):
        (result, note), _, _, _ = self.attempt('E-SET-28')
        self.assertEqual(result, 'fail')


class BundleTest(unittest.TestCase):
    PLAN = ('E-SET-01 05 06 07 09 10 11 13 14 15 16 17 18 19 20 21 22 23 24 25 27 28').split()

    def test_set_one_is_the_plan_plus_the_api_case(self):
        cases = [f'E-SET-{n}' if not n.startswith('E-') else n for n in self.PLAN]
        cases = [c if c.startswith('E-SET-') else f'E-SET-{c}' for c in cases]
        self.assertEqual(area1.BUNDLES['area4-set1'], ['E-SET-08'] + cases)

    def test_every_case_is_registered_once_and_runnable(self):
        bundle = area1.BUNDLES['area4-set1']
        self.assertEqual(len(bundle), len(set(bundle)))
        for case in bundle:
            self.assertTrue(case in area1.PHONE or case in area1.CASES, case)

    def test_left_out_cases_have_reasons_and_are_not_in_the_bundle(self):
        for case, reason in area4.LEFT_OUT.items():
            self.assertTrue(reason)
            self.assertNotIn(case, area1.BUNDLES['area4-set1'])
        self.assertEqual(sorted(area4.LEFT_OUT), ['E-SET-55', 'E-SET-56', 'E-SET-57'])  # 나머지는 area4_extra 묶음

    def test_contact_cases_are_listed_for_the_emulator_bundle_only(self):
        self.assertEqual(area4.EMULATOR, [f'E-SET-{n}' for n in range(29, 43)])
        for case in area4.EMULATOR:
            self.assertNotIn(case, area1.BUNDLES['area4-set1'])  # 폰 A 묶음에는 안 섞인다
            self.assertIn(case, area1.BUNDLES['area4-contacts'])  # 에뮬 묶음(area4_contacts.py)에만 있다


if __name__ == '__main__':
    unittest.main()
