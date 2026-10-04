"""영역 3 SAFE-35~46 연락처 차단 가설의 PC 쪽 — 가짜 서버 · 가짜 폰 · 가짜 adb, 기기 · 운영 없이 돈다."""

import contextlib
import unittest
from unittest import mock

from e2e import area1, area3_contacts, contacts, emu, tools
from e2e.test_area1 import Base, Reply
from e2e.test_area1_phone import FakePhone

S = 'emulator-5554'
CASES = ['E-SAFE-35', 'E-SAFE-36', 'E-SAFE-37', 'E-SAFE-38', 'E-SAFE-39', 'E-SAFE-40', 'E-SAFE-41', 'E-SAFE-42', 'E-SAFE-43',
         'E-SAFE-45', 'E-SAFE-46']
HMAC = '\\x' + 'ab12' * 16


class HookedPhone(FakePhone):
    """앱이 돌기 직전 · 직후에 [before] · [after] 를 부른다(job 을 받는다) — 앱이 서버 상태를 바꾸는 것을 흉내."""

    def __init__(self, *answers, before=None, after=None, **kw):
        super().__init__(*answers, **kw)
        self.before, self.after = before, after

    def __call__(self, midway=None, **job):
        if self.before:
            self.before(job)
        if midway and self.after:  # 멈춘 사이엔 이미 바뀐 상태
            self.after(job)
        return super().__call__(midway=midway, **job)


class Recorder:
    """contacts.on_device 대신 — 무엇을 넣고 어떤 권한으로 앱을 켰는지만 남긴다."""

    def __init__(self):
        self.runs = []

    @contextlib.contextmanager
    def on_device(self, serial, crowd, granted):
        self.runs.append((serial, list(crowd), granted))
        yield


class CaseTest(Base):
    def setUp(self):
        super().setUp()
        self.recorder = Recorder()
        self.rows = []  # contact_blocks 행 — 호출 순서대로 쓸 목록(마지막은 계속)
        self.excluded = {'b': False}  # 지인 차단이 먹은 뒤인가
        for target, kw in (
            (mock.patch.object(contacts, 'on_device', self.recorder.on_device), {}),
            (mock.patch('e2e.notify.grant_notifications'), {}),
            (mock.patch.object(contacts, 'tap_dialog'), {}),
            (mock.patch.object(area3_contacts.time, 'sleep'), {}),
            (mock.patch.object(area3_contacts, '_person', side_effect=self.person), {}),
            (mock.patch.object(area3_contacts, '_candidates', side_effect=self.candidates), {}),
        ):
            target.start()
            self.addCleanup(target.stop)
        self.serve({('GET', '/rest/v1/contact_blocks'): Reply(200, [])})

    def person(self, run, gender='male', phone=None, **_):
        n = len(self.people)
        who = {'id': f'{gender}-{n}', 'email': f'{gender}{n}@x.test', 'token': 't', 'phone': phone}
        self.people.append(who)
        return who

    people = []

    def candidates(self, run, account):
        # 지인 차단이 먹은 뒤엔 서로 안 보인다
        if self.excluded['b']:
            return {}
        other = [p['id'] for p in self.people if p['id'] != account['id']]
        return {i: 1.0 for i in other}

    def phone(self, excludes=False, **kw):
        """[excludes] 면 앱이 도는 동안 지인 차단이 먹는다(준비 확인은 앱이 돌기 전이라 서로 후보로 보인다)."""
        phone = HookedPhone(before=(lambda job: self.excluded.update(b=True)) if excludes else None, **kw)
        phone.serial = S
        return phone

    def blocks(self, *rows):
        self.serve({('GET', '/rest/v1/contact_blocks'): Reply(200, list(rows))})

    def row(self, i=0, created='2026-10-05T00:00:00+00:00', hmac=None):
        return {'id': f'blk-{i}', 'contact_hmac': hmac or HMAC, 'created_at': created}

    def attempt(self, case, phone=None):
        self.people = []
        return area1.attempt_phone(self.run, case, phone or self.phone())

    def test_bundle_is_the_eleven_contact_cases_and_not_the_api_only_one(self):
        self.assertEqual(area1.BUNDLES['area3-contacts'], CASES)
        self.assertNotIn('E-SAFE-44', area1.BUNDLES['area3-contacts'])  # API 만(area3_safe.safe_44)
        self.assertTrue(set(CASES) <= set(area1.PHONE))

    def test_every_case_refuses_a_real_phone_before_touching_anything(self):
        for case in CASES:
            phone = FakePhone()
            phone.serial = 'R5CR12345'
            self.assertEqual(self.attempt(case, phone)[0], 'blocked', case)
        self.assertEqual(self.recorder.runs, [])
        self.assertEqual(self.people, [])  # 계정도 안 만들었다

    # 35 · 36 — 권한 안내
    def test_35_asks_with_no_permission_and_taps_allow_while_the_app_waits(self):
        with mock.patch.object(contacts, 'tap_dialog') as tap:
            result = self.attempt('E-SAFE-35', self.phone(midway_step={'step': 'dialog'}))
        self.assertEqual(result[0], 'pass')
        self.assertFalse(self.recorder.runs[0][2])  # 권한 없음
        self.assertEqual(len(self.recorder.runs[0][1]), 3)  # 연락처 3명
        tap.assert_called_once_with(S, True)

    def test_36_runs_the_app_twice_later_and_deny_and_both_end_in_the_settings_app(self):
        settings = 'mResumedActivity: ActivityRecord{1 u0 com.android.settings/.Settings$AppInfoActivity}'
        phone = self.phone(top=settings, midway_step={'step': 'dialog'})
        with mock.patch.object(contacts, 'tap_dialog') as tap:
            self.assertEqual(self.attempt('E-SAFE-36', phone)[0], 'pass')
        self.assertEqual([j['phase'] for j in phone.jobs], ['later', 'deny'])
        tap.assert_called_once_with(S, False)  # 두 번째 판만 OS 창이 뜬다
        self.assertEqual(len(self.recorder.runs), 2)

    def test_36_fails_when_the_settings_app_is_not_on_top_after_a_variant(self):
        self.assertEqual(self.attempt('E-SAFE-36', self.phone())[0], 'fail')  # 크롬이 맨 위

    # 37 — 서버에는 해시만
    def test_37_keeps_only_the_hash_on_the_server(self):
        self.blocks(self.row())
        self.assertEqual(self.attempt('E-SAFE-37')[0], 'pass')
        name, numbers = self.recorder.runs[0][1][0]
        self.assertEqual(name, '테스트지인')

    def test_37_fails_when_a_phone_number_is_in_the_row(self):
        self.blocks(self.row())
        with mock.patch.object(area3_contacts, '_number', return_value='010-1234-5678'):
            self.blocks({'id': 'x', 'contact_hmac': HMAC, 'created_at': 'z', 'number': '01012345678'})
            self.assertEqual(self.attempt('E-SAFE-37')[0], 'fail')

    def test_37_needs_exactly_one_row(self):
        self.blocks()
        self.assertEqual(self.attempt('E-SAFE-37')[0], 'fail')

    # 38 · 39 · 45 — 양방향 후보
    def friend_flow(self, case, rows=1, excludes=True, **kw):
        self.blocks(*[self.row(i) for i in range(rows)])
        return self.attempt(case, self.phone(excludes=excludes, **kw))

    def test_38_blocks_the_friends_number_and_both_drop_out_of_each_others_candidates(self):
        self.assertEqual(self.friend_flow('E-SAFE-38')[0], 'pass')
        _, crowd, _ = self.recorder.runs[0]
        friend = [p for p in self.people if p['id'].startswith('female')][0]
        self.assertIn(friend['phone'], [n for _, numbers in crowd for n in numbers])  # F 의 번호가 B 연락처에 있다

    def test_38_fails_if_either_side_still_sees_the_other(self):
        result, note = self.friend_flow('E-SAFE-38', excludes=False)  # 차단이 안 먹음
        self.assertEqual(result, 'fail')
        self.assertIn('후보', note)

    def test_38_is_blocked_when_they_were_not_candidates_before(self):
        with mock.patch.object(area3_contacts, '_candidates', return_value={}):
            self.assertEqual(self.friend_flow('E-SAFE-38')[0], 'blocked')

    def test_39_stores_the_number_in_the_plus_82_shape(self):
        self.assertEqual(self.friend_flow('E-SAFE-39')[0], 'pass')
        _, crowd, _ = self.recorder.runs[0]
        friend = [p for p in self.people if p['id'].startswith('female')][0]
        shapes = [n for _, numbers in crowd for n in numbers if n.startswith('+82 10-')]
        self.assertEqual(shapes, ['+82 ' + friend['phone'][1:]])

    # 40 · 41 · 42 · 43
    def test_40_a_landline_only_contact_blocks_nothing(self):
        self.blocks()
        self.assertEqual(self.attempt('E-SAFE-40')[0], 'pass')
        self.assertEqual(self.recorder.runs[0][1][0][1], ('02-123-4567',))
        self.blocks(self.row())
        self.assertEqual(self.attempt('E-SAFE-40')[0], 'fail')

    def test_41_one_person_with_two_mobile_numbers_makes_two_rows(self):
        self.blocks(self.row(0, hmac='\\x01'), self.row(1, hmac='\\x02'))
        self.assertEqual(self.attempt('E-SAFE-41')[0], 'pass')
        self.assertEqual(len(self.recorder.runs[0][1][0][1]), 2)
        self.blocks(self.row(0))
        self.assertEqual(self.attempt('E-SAFE-41')[0], 'fail')

    def test_42_blocking_the_same_person_again_keeps_one_row_with_the_same_id(self):
        self.blocks(self.row(0))
        self.assertEqual(self.attempt('E-SAFE-42', self.phone(midway_step={'step': 'first'}))[0], 'pass')

    def test_42_a_new_id_after_the_second_block_fails(self):
        seen = iter([[self.row(0)], [self.row(7)]])  # 첫 확인 때와 끝에서 id 가 다르다
        with mock.patch.object(area3_contacts, '_rows', side_effect=lambda run, path: next(seen)):
            result, note = self.attempt('E-SAFE-42', self.phone(midway_step={'step': 'first'}))
        self.assertEqual(result, 'fail')
        self.assertIn('id', note)

    def test_43_201_people_become_201_rows_in_two_requests(self):
        rows = [self.row(i, created='2026-10-05T00:00:00+00:00' if i < 200 else '2026-10-05T00:00:01+00:00') for i in range(201)]
        self.blocks(*rows)
        phone = self.phone()
        self.assertEqual(self.attempt('E-SAFE-43', phone)[0], 'pass')
        self.assertEqual(len(self.recorder.runs[0][1]), 201)
        self.assertEqual(phone.jobs[0]['pick'], 'all')

    def test_43_fails_when_it_was_one_request_or_a_row_is_missing(self):
        same = [self.row(i) for i in range(201)]  # 요청이 하나였다 → created_at 이 하나
        self.blocks(*same)
        result, note = self.attempt('E-SAFE-43')
        self.assertEqual(result, 'fail')
        self.assertIn('요청', note)
        self.blocks(*same[:200])
        self.assertEqual(self.attempt('E-SAFE-43')[0], 'fail')

    # 45 — 해제하면 다시 후보
    def test_45_lifts_the_block_and_they_are_candidates_again(self):
        # 멈춘 사이(midway)엔 차단이 먹은 상태, 앱이 끝난 뒤엔 풀린 상태
        class Unblocking(HookedPhone):
            def __call__(inner, midway=None, **job):
                self.excluded['b'] = True
                result = FakePhone.__call__(inner, midway=midway, **job)
                self.excluded['b'] = False
                return result
        phone = Unblocking(midway_step={'step': 'blocked'})
        phone.serial = S
        self.blocks()
        self.assertEqual(self.attempt('E-SAFE-45', phone)[0], 'pass')

    def test_45_is_blocked_when_the_block_never_took_effect_before_the_unblock(self):
        phone = self.phone(midway_step={'step': 'blocked'})  # 차단 뒤에도 서로 후보 → 해제를 확인할 수 없다
        self.blocks()
        result, note = self.attempt('E-SAFE-45', phone)
        self.assertEqual(result, 'blocked')
        self.assertIn('차단', note)

    def test_45_fails_when_the_row_stays_after_the_unblock(self):
        self.blocks(self.row())
        with mock.patch.object(area3_contacts, '_candidates', side_effect=lambda run, a: {'x': 1.0}):
            result, note = self.attempt('E-SAFE-45', self.phone(midway_step={'step': 'blocked'}))
        self.assertIn(result, ('fail', 'blocked'))

    def test_45_shows_the_app_failure_when_the_app_never_reached_the_midway_step(self):
        # 앱이 'blocked' 에 닿기 전에 실패(midway 를 안 부름)하면 준비 blocked 가 아니라 앱의 실패 사유가 보여야 한다
        class Dies(HookedPhone):
            def __call__(inner, midway=None, **job):
                return FakePhone.__call__(inner, midway=None, **job)
        phone = Dies({'result': 'fail', 'note': '16b 줄이 20초 안에 1 줄이 안 됨'})
        phone.serial = S
        self.blocks()
        result, note = self.attempt('E-SAFE-45', phone)
        self.assertEqual(result, 'fail')
        self.assertIn('16b', note)


class ReinstallTest(Base):
    def test_46_wipes_the_app_then_logs_in_again_and_the_block_still_holds(self):
        calls = []
        reinstalled = []
        persons = []

        def person(run, gender='male', phone=None, **_):
            who = {'id': f'{gender}-{len(persons)}', 'email': f'{gender}@x.test', 'token': 't', 'phone': phone}
            persons.append(who)
            return who

        state = {'blocked': False}

        def candidates(run, account):
            return {} if state['blocked'] else {p['id']: 1.0 for p in persons if p['id'] != account['id']}

        class Blocking(HookedPhone):
            def __call__(inner, midway=None, **job):
                if job.get('phase') == 'block':
                    state['blocked'] = True
                return FakePhone.__call__(inner, midway=midway, **job)
        phone = Blocking(midway_step={'step': 'blocked'})
        phone.serial = S
        self.serve({('GET', '/rest/v1/contact_blocks'): Reply(200, [{'id': 'b', 'contact_hmac': '\\x01', 'created_at': 'z'}])})
        patches = [mock.patch.object(contacts, 'on_device', Recorder().on_device),
                   mock.patch('e2e.notify.grant_notifications'),
                   mock.patch.object(area3_contacts, '_person', side_effect=person),
                   mock.patch.object(area3_contacts, '_candidates', side_effect=candidates),
                   mock.patch.object(area3_contacts, 'reinstall', side_effect=lambda serial: reinstalled.append(serial)),
                   mock.patch.object(contacts, 'grant')]
        with contextlib.ExitStack() as stack:
            for patcher in patches:
                stack.enter_context(patcher)
            result = area1.attempt_phone(self.run, 'E-SAFE-46', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual([j['phase'] for j in phone.jobs], ['block', 'after'])
        self.assertEqual(reinstalled, [S])
        self.assertNotEqual(phone.jobs[0]['token_hash'], '')
        self.assertIn('token_hash', phone.jobs[1])  # 지운 뒤라 새로 로그인한다
        self.assertNotIn('fresh', phone.jobs[1])

    def test_reinstall_uninstalls_then_installs_with_all_permissions_and_refuses_a_real_phone(self):
        adb_calls = []

        def adb(serial, *args, check=True):
            adb_calls.append(' '.join(args))
            return 'Success'
        apk = mock.Mock()
        apk.is_file.return_value = True
        with mock.patch.object(tools, 'adb', adb), mock.patch.object(area3_contacts, 'APK', apk), \
                mock.patch.object(area3_contacts.time, 'sleep'):
            area3_contacts.reinstall(S)
        self.assertEqual(adb_calls[0], f'uninstall {tools.PACKAGE}')
        self.assertTrue(adb_calls[1].startswith('install -r -g'))
        with mock.patch.object(tools, 'adb') as real, mock.patch.object(area3_contacts, 'APK', apk), self.assertRaises(tools.Blocked):
            area3_contacts.reinstall('R5CR12345')
        real.assert_not_called()

    def test_reinstall_without_a_built_apk_is_blocked_before_uninstalling(self):
        apk = mock.Mock()
        apk.is_file.return_value = False
        adb = mock.Mock(return_value='')
        with mock.patch.object(tools, 'adb', adb), mock.patch.object(area3_contacts, 'APK', apk), self.assertRaises(tools.Blocked):
            area3_contacts.reinstall(S)
        adb.assert_not_called()  # 지우고 나서 깔 파일이 없는 최악을 피한다

    def test_a_failed_install_is_blocked(self):
        apk = mock.Mock()
        apk.is_file.return_value = True

        def adb(serial, *args, check=True):
            return 'Failure [INSTALL_FAILED_VERSION_DOWNGRADE]' if args[0] == 'install' else 'Success'
        with mock.patch.object(tools, 'adb', adb), mock.patch.object(area3_contacts, 'APK', apk), self.assertRaises(tools.Blocked):
            area3_contacts.reinstall(S)


if __name__ == '__main__':
    unittest.main()
