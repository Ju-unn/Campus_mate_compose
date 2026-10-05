"""영역 1 묶음 6(두 기기 · 에뮬 네트워크) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b6`."""

import subprocess
import unittest
from types import SimpleNamespace
from unittest import mock

from e2e import area1, area1_b6
from e2e.test_area1 import Base
from e2e.test_area1_phone import FakePhone
from e2e.tools import Reply

PHONE = ['E-ONB-74', 'E-ONB-05']
REFERRALS = ('GET', '/rest/v1/referrals')
HEARTS = ('GET', '/rest/v1/heart_transactions')
PROFILES = ('GET', '/rest/v1/profiles')
USERS = ('POST', '/auth/v1/admin/users')
SAVED = {'result': 'pass', 'outcome': 'saved'}
TAKEN = {'result': 'pass', 'outcome': 'taken'}
BOTH = 'List of devices attached\nR58M\tdevice\nemulator-5554\tdevice\n'


def raising(error):
    """호출하면 [error] 를 던지는 가짜 앱 — Run.phone 이 중간에 터지는 경우."""
    def call(this, midway=None, **job):
        raise error
    return type('Raising', (FakePhone,), {'__call__': call})


class BundleTest(unittest.TestCase):
    def test_bundle_is_the_emulator_case_then_the_two_device_case(self):
        self.assertEqual(area1.BUNDLES['area1-b6'], PHONE)
        self.assertLessEqual(set(PHONE), set(area1.PHONE))


class Base6(Base):
    def phone(self, *answers, serial='emulator-5554', **kw):
        phone = FakePhone(*answers, **kw)
        phone.serial = serial
        phone.hub = SimpleNamespace(port=8766)
        return phone


class Onb74Test(Base6):
    def setUp(self):
        super().setUp()
        patches = [mock.patch.object(area1_b6.emu, 'go_offline'), mock.patch.object(area1_b6.emu, 'go_online', return_value=True),
                   mock.patch.object(area1_b6.area1_emu.notify, 'grant_notifications')]
        self.offline, self.online, _ = [p.start() for p in patches]
        for p in patches:
            self.addCleanup(p.stop)

    def go(self, phone, routes=None):
        self.fake = self.serve({PROFILES: Reply(200, [{'referral_code': 'ABC234'}]), **(routes or {})})
        return area1.attempt_phone(self.run, 'E-ONB-74', phone)

    def test_cuts_the_network_while_the_app_waits_then_restores_it_and_finds_no_row_or_heart(self):
        phone = self.phone(midway_step={'step': 'typed'})
        self.assertEqual(self.go(phone)[0], 'pass')
        self.offline.assert_called_once_with('emulator-5554')
        self.online.assert_called_once_with('emulator-5554')
        self.assertEqual(phone.jobs[0]['code'], 'ABC234')  # 추천인의 코드를 넣는다
        self.assertEqual(phone.acted, ['typed'])

    def test_fails_when_a_referral_row_or_a_heart_appeared(self):
        for routes in ({REFERRALS: Reply(200, [{'referrer_id': 'id-1'}])}, {HEARTS: Reply(200, [{'amount': 50}])}):
            self.assertEqual(self.go(self.phone(), routes)[0], 'fail', routes)

    def test_the_network_comes_back_even_when_the_app_failed(self):
        result, note = self.go(self.phone({'result': 'fail', 'note': '문구가 안 뜸'}))
        self.assertEqual(result, 'fail')
        self.assertIn('문구가 안 뜸', note)
        self.online.assert_called_once()

    def test_the_network_comes_back_when_the_app_says_blocked(self):
        result, note = self.go(self.phone({'result': 'blocked', 'note': '20 에 못 감'}))
        self.assertEqual(result, 'blocked')
        self.assertIn('20 에 못 감', note)
        self.online.assert_called_once()  # 예외가 올라와도 에뮬이 오프라인으로 남지 않는다

    def test_the_network_comes_back_when_the_phone_run_itself_raises(self):
        phone = self.phone()
        phone.__class__ = raising(area1_b6.Blocked('우편함 끊김'))
        self.assertEqual(self.go(phone)[0], 'blocked')
        self.online.assert_called_once()

    def test_blocks_when_the_network_does_not_come_back(self):
        self.online.return_value = False
        result, note = self.go(self.phone())
        self.assertEqual(result, 'blocked')
        self.assertIn('네트워크', note)

    def test_a_real_phone_is_blocked_before_any_account_is_made(self):
        fake = self.serve()
        result, _ = area1.attempt_phone(self.run, 'E-ONB-74', self.phone(serial='R58M'))
        self.assertEqual(result, 'blocked')
        self.assertEqual(fake.users, [])
        self.offline.assert_not_called()


class OtherPhoneTest(Base6):
    """두 번째 기기의 우편함 · adb reverse 를 만든다 — Hub 와 adb 는 가짜."""

    CFG = {'E2E_DEVICE_A': 'R58M', 'E2E_DEVICE_B': 'emulator-5554'}

    def other(self, mine, attached=BOTH, adb=None):
        self.run.cfg = {**self.run.cfg, **self.CFG}
        self.hubs = []
        patches = [mock.patch.object(area1_b6.tools, 'Hub', side_effect=lambda port: self.hubs.append(SimpleNamespace(port=port, close=mock.Mock())) or self.hubs[-1]),
                   mock.patch.object(area1_b6.tools, 'adb', **({'side_effect': adb} if adb else {'return_value': ''})),
                   mock.patch.object(area1_b6.tools, 'devices', return_value=attached)]
        _, self.adb, _ = [p.start() for p in patches]
        for p in patches:
            self.addCleanup(p.stop)
        return area1_b6._other_phone(self.run, self.phone(serial=mine), 'E-ONB-05')

    def test_the_phone_gets_the_emulator_as_its_partner_on_the_emulators_own_port(self):
        other, hub = self.other('R58M')
        self.assertEqual(other.serial, 'emulator-5554')
        self.assertEqual(hub.port, area1_b6.tools.DEVICES['B'])
        self.adb.assert_called_with('emulator-5554', 'reverse', f'tcp:{area1_b6.tools.DEVICE_PORT}', f'tcp:{hub.port}')

    def test_the_emulator_gets_the_phone_as_its_partner(self):
        other, hub = self.other('emulator-5554')
        self.assertEqual(other.serial, 'R58M')
        self.assertEqual(hub.port, area1_b6.tools.DEVICES['A'])

    def test_a_failed_adb_reverse_closes_the_mailbox_it_just_opened(self):
        def boom(serial, *args, **kw):
            raise subprocess.CalledProcessError(1, 'adb')

        with self.assertRaises(subprocess.CalledProcessError):
            self.other('R58M', adb=boom)
        self.hubs[0].close.assert_called_once()

    def test_a_listed_but_offline_device_is_not_a_partner(self):
        with self.assertRaises(area1_b6.Blocked):
            self.other('R58M', attached='List of devices attached\nR58M\tdevice\nemulator-5554\toffline\n')
        self.assertEqual(self.hubs, [])

    def test_blocks_when_the_other_device_is_unknown_or_not_attached(self):
        self.run.cfg = {**self.run.cfg, 'E2E_DEVICE_A': 'R58M', 'E2E_DEVICE_B': ''}
        with mock.patch.object(area1_b6.tools, 'DEFAULT_SERIALS', {}):
            with self.assertRaises(area1_b6.Blocked):
                area1_b6._other_phone(self.run, self.phone(serial='R58M'), 'E-ONB-05')
        with self.assertRaises(area1_b6.Blocked) as caught:
            self.other('R58M', attached='List of devices attached\nR58M\tdevice\n')
        self.assertIn('emulator-5554', str(caught.exception))
        self.assertEqual(self.hubs, [])  # 우편함을 열기 전에 막는다


class Onb05Test(Base6):
    FIRST = Reply(200, [{'id': 'id-1'}])  # 첫 기기의 계정이 닉네임을 가졌다
    SECOND = Reply(200, [{'id': 'id-2'}])

    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(area1_b6.notify, 'grant_notifications')
        patcher.start()
        self.addCleanup(patcher.stop)
        wait = mock.patch.object(area1_b6, 'RELEASE_WAIT', 0.3)
        wait.start()
        self.addCleanup(wait.stop)

    def go(self, mine, other, routes=None):
        self.hub = SimpleNamespace(close=mock.Mock())
        patcher = mock.patch.object(area1_b6, '_other_phone', return_value=(other, self.hub))
        patcher.start()
        self.addCleanup(patcher.stop)
        self.fake = self.serve({PROFILES: self.FIRST, **(routes or {})})
        return area1.attempt_phone(self.run, 'E-ONB-05', mine)

    def pair(self, mine_said, other_said):
        return (self.phone(mine_said, serial='R58M', midway_step={'step': 'typed'}),
                self.phone(other_said, serial='emulator-5554', midway_step={'step': 'typed'}))

    def test_two_accounts_get_the_same_new_nickname_and_exactly_one_is_saved(self):
        mine, other = self.pair(SAVED, TAKEN)
        self.assertEqual(self.go(mine, other)[0], 'pass')
        self.assertEqual(mine.jobs[0]['nickname'], other.jobs[0]['nickname'])
        self.assertEqual(len(self.fake.users), 2)  # 기기마다 따로 만든 계정
        self.assertEqual((mine.acted, other.acted), (['typed'], ['typed']))
        self.hub.close.assert_called_once()

    def test_the_other_way_round_also_passes(self):
        mine, other = self.pair(TAKEN, SAVED)
        self.assertEqual(self.go(mine, other, {PROFILES: self.SECOND})[0], 'pass')

    def test_fails_when_the_account_holding_the_nickname_is_the_one_whose_app_was_refused(self):
        mine, other = self.pair(SAVED, TAKEN)
        result, note = self.go(mine, other, {PROFILES: self.SECOND})
        self.assertEqual(result, 'fail')
        self.assertIn('저장했다는', note)

    def test_both_apps_are_let_go_only_after_both_have_stopped(self):
        order = []
        barrier_seen = []

        class Slow(FakePhone):
            def __call__(this, midway=None, **job):
                order.append('stopped')
                midway(this.midway_step)
                barrier_seen.append(len(order))  # 풀려난 때 두 앱이 모두 멈춰 있었어야 한다
                return super().__call__(**job)

        mine, other = Slow(SAVED), Slow(TAKEN)
        for phone, serial in ((mine, 'R58M'), (other, 'emulator-5554')):
            phone.serial = serial
            phone.hub = SimpleNamespace(port=1)
        self.assertEqual(self.go(mine, other)[0], 'pass')
        self.assertEqual(barrier_seen, [2, 2])

    def test_fails_when_both_saved_or_both_were_refused(self):
        for a, b in ((SAVED, SAVED), (TAKEN, TAKEN)):
            mine, other = self.pair(a, b)
            result, note = self.go(mine, other)
            self.assertEqual(result, 'fail', (a, b))
            self.assertIn('한쪽만', note)

    def test_fails_when_the_database_holds_two_profiles_with_that_nickname(self):
        mine, other = self.pair(SAVED, TAKEN)
        result, note = self.go(mine, other, {PROFILES: Reply(200, [{'id': 'id-1'}, {'id': 'id-2'}])})
        self.assertEqual(result, 'fail')
        self.assertIn('2', note)

    def test_an_app_that_ends_before_stopping_does_not_hang_the_other_and_its_note_is_kept(self):
        mine = self.phone({'result': 'fail', 'note': '04-1 에 못 감'}, serial='R58M')
        mine.__class__ = type('Early', (FakePhone,), {'__call__': lambda this, midway=None, **job: this.answers[0]})
        other = self.phone(SAVED, serial='emulator-5554', midway_step={'step': 'typed'})
        result, note = self.go(mine, other)
        self.assertEqual(result, 'fail')
        self.assertIn('04-1 에 못 감', note)

    def test_an_app_that_says_blocked_makes_the_case_blocked_not_fail(self):
        mine, other = self.pair({'result': 'blocked', 'note': '04-1 에 못 감'}, TAKEN)
        result, note = self.go(mine, other)
        self.assertEqual(result, 'blocked')
        self.assertIn('04-1 에 못 감', note)

    def test_a_case_timeout_in_one_device_thread_reaches_the_runner(self):
        # 러너(run_case)가 CaseTimeout 을 잡아 blocked(시간 초과)로 끝낸다 — 여기서 fail 로 바꾸면 그 가설을 한 번 더 돈다.
        mine, other = self.pair(SAVED, TAKEN)
        other.__class__ = raising(area1_b6.tools.CaseTimeout('adb 가 안 끝남'))
        with self.assertRaises(area1_b6.tools.CaseTimeout):
            self.go(mine, other)
        self.hub.close.assert_called_once()

    def test_the_mailbox_is_closed_even_when_making_an_account_fails(self):
        mine, other = self.pair(SAVED, TAKEN)
        result, _ = self.go(mine, other, {USERS: Reply(500, None)})
        self.assertEqual(result, 'blocked')
        self.hub.close.assert_called_once()

    def test_blocks_before_making_accounts_when_the_second_device_is_missing(self):
        mine, _ = self.pair(SAVED, TAKEN)
        self.fake = self.serve()
        with mock.patch.object(area1_b6, '_other_phone', side_effect=area1_b6.Blocked('E2E_DEVICE_B 가 없다')):
            result, _ = area1.attempt_phone(self.run, 'E-ONB-05', mine)
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.fake.users, [])


if __name__ == '__main__':
    unittest.main()
