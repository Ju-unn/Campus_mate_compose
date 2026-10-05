"""에뮬(B) 준비 점검 · 에뮬만 하는 조작 · 영역 1 B에뮬 가설 — 기기 · 운영 없이 돈다(adb 는 가짜)."""

import contextlib
import unittest
from datetime import datetime, timezone
from unittest import mock

from e2e import area1, area1_emu, emu, tools
from e2e.test_area1 import Base, Reply
from e2e.test_area1_phone import FakePhone

S = 'emulator-5554'


class FakeAdb:
    """기기 대신 답한다 — [answers] 는 (명령 안에 든 글자 → 출력, 목록이면 차례로 마지막은 계속). 부른 명령은 [calls] 에 남는다."""

    def __init__(self, answers=None):
        self.answers = {k: (list(v) if isinstance(v, list) else v) for k, v in (answers or {}).items()}
        self.calls = []

    def __call__(self, serial, *args, check=True):
        line = ' '.join(args)
        self.calls.append(line)
        for key, out in self.answers.items():
            if key in line:
                if isinstance(out, list):
                    return out.pop(0) if len(out) > 1 else out[0]
                return out
        return ''

    def ran(self, text):
        return [c for c in self.calls if text in c]


def patched(adb):
    return mock.patch.object(tools, 'adb', adb)


CHROME = '1 activities found:\n  priority=0 preferredOrder=0 match=0x0\n  com.android.chrome/com.google.android.apps.chrome.Main\n'
NONE = '0 activities found\n'
LOSS = '1 packets transmitted, 0 received, 100% packet loss'
PONG = '1 packets transmitted, 1 received, 0% packet loss'

GOOD = {
    'getprop sys.boot_completed': '1\n', 'getprop ro.build.version.sdk': '34\n', 'getprop ro.product.cpu.abi': 'x86_64\n',
    'getprop ro.kernel.qemu': '1\n', 'getprop ro.debuggable': '0\n',
    'pm list packages': f'package:{tools.PACKAGE}\n', 'run-as': 'uid=10150(u0_a150) gid=10150 context=u:r:untrusted_app\n',
    'reverse --list': f'host-19 tcp:{tools.DEVICE_PORT} tcp:8766\n', 'which svc': '/system/bin/svc\n',
    'query-activities': CHROME,
}


class CheckTest(unittest.TestCase):
    def rows(self, answers=None, attached=True, wait=0):
        adb = FakeAdb({**GOOD, **(answers or {})})
        listing = f'List of devices attached\n{S}\tdevice\n' if attached else 'List of devices attached\n'
        with patched(adb), mock.patch.object(tools, 'devices', return_value=listing):
            return emu.check(S, wait=wait, sleep=lambda s: None), adb

    def test_everything_good_has_no_failed_hard_row_and_reports_root_and_browser_hints(self):
        rows, _ = self.rows()
        self.assertTrue(all(r.ok for r in rows if r.hard), [r for r in rows if r.hard and not r.ok])
        text = ' '.join(r.detail for r in rows)
        self.assertIn('34', text)
        self.assertIn('com.android.chrome', text)
        self.assertTrue(any('blocked' in r.detail for r in rows if '시계' in r.name))  # ro.debuggable=0 → AUTH-19 는 blocked 예상

    def test_debuggable_image_says_root_may_work(self):
        rows, _ = self.rows({'getprop ro.debuggable': '1\n'})
        self.assertFalse(any('blocked' in r.detail for r in rows if '시계' in r.name))

    def test_not_attached_fails_and_stops_before_asking_the_device(self):
        rows, adb = self.rows(attached=False)
        self.assertFalse(rows[0].ok)
        self.assertEqual(adb.calls, [])

    def test_waits_for_boot_then_goes_on(self):
        rows, _ = self.rows({'getprop sys.boot_completed': ['', '', '1\n']}, wait=30)
        self.assertTrue([r for r in rows if '부팅' in r.name][0].ok)

    def test_never_booted_fails_the_boot_row(self):
        rows, _ = self.rows({'getprop sys.boot_completed': ''}, wait=0)
        self.assertFalse([r for r in rows if '부팅' in r.name][0].ok)

    def test_missing_app_or_run_as_fails(self):
        rows, _ = self.rows({'pm list packages': ''})
        self.assertFalse([r for r in rows if '앱' in r.name][0].ok)
        rows, _ = self.rows({'run-as': 'run-as: package not debuggable\n'})
        self.assertFalse([r for r in rows if 'run-as' in r.name][0].ok)

    def test_check_only_reads(self):
        _, adb = self.rows()
        for call in adb.calls:
            self.assertFalse(any(w in call for w in ('disable', 'enable', 'settings put', 'date -u', 'kill', ' root', 'push')), call)


class NetworkTest(unittest.TestCase):
    def test_only_emulators(self):
        for serial in ('R5CR12345', None, ''):
            with self.assertRaises(tools.Blocked):
                emu.require_emulator(serial)
        emu.require_emulator(S)

    def test_online_reads_packet_loss_and_100_percent_is_offline(self):
        for out, expected in ((PONG, True), (LOSS, False), ('connect: Network is unreachable', False), ('', False)):
            with patched(FakeAdb({'ping': out})):
                self.assertEqual(emu.online(S), expected, out)

    def test_go_offline_cuts_wifi_and_data_and_refuses_a_real_phone(self):
        adb = FakeAdb({'ping': LOSS})
        with patched(adb):
            emu.go_offline(S, sleep=lambda s: None)
        self.assertTrue(adb.ran('svc wifi disable') and adb.ran('svc data disable'))
        adb = FakeAdb()
        with patched(adb), self.assertRaises(tools.Blocked):
            emu.go_offline('R5CR12345')
        self.assertEqual(adb.calls, [])  # 실폰에는 아무것도 안 보낸다

    def test_still_online_after_cutting_is_blocked_and_turned_back_on(self):
        adb = FakeAdb({'ping': PONG})
        with patched(adb), self.assertRaises(tools.Blocked):
            emu.go_offline(S, sleep=lambda s: None)
        self.assertTrue(adb.ran('svc wifi enable'))

    def test_go_online_turns_on_and_waits_until_ping_works(self):
        adb = FakeAdb({'ping': ['connect: Network is unreachable', PONG]})
        with patched(adb):
            self.assertTrue(emu.go_online(S, sleep=lambda s: None))
        self.assertTrue(adb.ran('svc wifi enable') and adb.ran('svc data enable'))

    def test_mobile_data_that_the_emulator_cannot_toggle_does_not_kill_the_case(self):
        # 에뮬은 모바일 데이터가 없어 `svc data enable` 이 종료 코드 20 으로 끝난다(10-05 첫 실행) — 되는 것(와이파이)만으로 판정
        calls = []

        def adb(serial, *args, check=True):
            line = ' '.join(args)
            calls.append(line)
            if 'svc data' in line and check:
                raise tools.subprocess.CalledProcessError(20, 'adb')
            return PONG if 'ping' in line else ''
        with patched(adb):
            self.assertTrue(emu.go_online(S, sleep=lambda s: None))
        self.assertIn('shell svc wifi enable', calls)
        self.assertIn('shell svc data enable', calls)  # 시도는 한다

    def test_offline_still_cuts_wifi_when_data_cannot_be_cut(self):
        online = [True]

        def adb(serial, *args, check=True):
            line = ' '.join(args)
            if 'svc data' in line and check:
                raise tools.subprocess.CalledProcessError(20, 'adb')
            if 'svc wifi disable' in line:
                online[0] = False
            return PONG if online[0] and 'ping' in line else (LOSS if 'ping' in line else '')
        with patched(adb):
            emu.go_offline(S, sleep=lambda s: None)  # 예외 없이 끝난다
        self.assertFalse(online[0])

    def test_go_online_gives_dns_a_moment_after_the_first_pong(self):
        pauses = []
        with patched(FakeAdb({'ping': PONG})):
            emu.go_online(S, sleep=pauses.append)
        self.assertIn(2, pauses)

    def test_go_online_gives_up_and_says_so(self):
        with patched(FakeAdb({'ping': ''})):
            self.assertFalse(emu.go_online(S, timeout=4, sleep=lambda s: None))


NOON = lambda: datetime(2026, 10, 4, 12, 0, tzinfo=timezone.utc)


class ClockTest(unittest.TestCase):
    def test_root_refused_is_blocked(self):
        adb = FakeAdb({'root': 'adbd cannot run as root in production builds', 'shell id': 'uid=2000(shell)'})
        with patched(adb), self.assertRaises(tools.Blocked) as ctx:
            emu.root(S, sleep=lambda s: None)
        self.assertIn('root', str(ctx.exception))

    def test_root_restores_the_mailbox_forward_because_adbd_restart_drops_it(self):
        hub = mock.Mock(port=8766)
        adb = FakeAdb({'root': 'restarting adbd as root', 'shell id': 'uid=0(root)'})
        with patched(adb):
            emu.root(S, hub, sleep=lambda s: None)
        self.assertTrue(adb.ran(f'reverse tcp:{tools.DEVICE_PORT} tcp:8766'))

    def test_clock_goes_forward_then_is_put_back_even_when_the_body_fails(self):
        adb = FakeAdb()
        target = int(datetime(2026, 10, 4, 14, 0, tzinfo=timezone.utc).timestamp())
        with patched(adb), mock.patch.object(emu, 'epoch', return_value=target):
            with self.assertRaises(RuntimeError), emu.clock_shifted(S, hours=2, now=NOON):
                raise RuntimeError('app failed')
        dates = adb.ran('date -u')
        self.assertEqual(dates[0], 'shell date -u 100414002026.00')  # +2시간 (MMDDhhmmYYYY.ss)
        self.assertEqual(len(dates), 2)  # 되돌림
        self.assertTrue(adb.ran('settings put global auto_time 1'))

    def test_clock_that_did_not_move_is_blocked(self):
        adb = FakeAdb()
        with patched(adb), mock.patch.object(emu, 'epoch', return_value=0), self.assertRaises(tools.Blocked):
            with emu.clock_shifted(S, hours=2, now=NOON):
                pass
        self.assertTrue(adb.ran('settings put global auto_time 1'))  # 못 바꿨어도 자동 시각은 되돌린다


    def test_date_refused_still_turns_auto_time_back_on(self):
        calls = []

        def adb(serial, *args, check=True):
            line = ' '.join(args)
            calls.append(line)
            if line.startswith('shell date -u'):
                raise tools.subprocess.CalledProcessError(1, 'adb')  # root 가 아니면 date 가 종료 코드 1
            return ''
        with patched(adb), self.assertRaises(tools.subprocess.CalledProcessError):
            with emu.clock_shifted(S, hours=2, now=NOON):
                pass
        self.assertIn('shell settings put global auto_time 1', calls)

    def test_clock_functions_refuse_a_real_phone(self):
        adb = FakeAdb()
        with patched(adb):
            for call in (lambda: emu.root('R5CR12345'), lambda: emu.clock_shifted('R5CR12345', 2).__enter__(),
                         lambda: emu.browsers_disabled('R5CR12345').__enter__()):
                with self.assertRaises(tools.Blocked):
                    call()
        self.assertEqual(adb.calls, [])


class TimezoneAdb(FakeAdb):
    """기기 시간대를 기억한다 — `service call alarm 3 s16 <값>` 이 바꾸고 `getprop persist.sys.timezone` 이 읽는다. [stuck] 이면 바꿔도 안 먹는다."""

    def __init__(self, zone='GMT', stuck=False):
        super().__init__()
        self.zone, self.stuck = zone, stuck

    def __call__(self, serial, *args, check=True):
        line = ' '.join(args)
        self.calls.append(line)
        if line == 'shell getprop persist.sys.timezone':
            return f'{self.zone}\n'
        if line.startswith('shell service call alarm 3 s16 ') and not self.stuck:
            self.zone = args[-1]
        return ''


class TimezoneTest(unittest.TestCase):
    def sets(self, adb):
        return [c.rsplit(' ', 1)[1] for c in adb.ran('service call alarm 3')]

    def test_a_device_in_another_zone_is_set_to_seoul_for_the_body_and_put_back_after(self):
        adb = TimezoneAdb('GMT')
        with patched(adb):
            with emu.seoul_timezone(S, sleep=lambda s: None):
                self.assertEqual(adb.zone, 'Asia/Seoul')
        self.assertEqual((self.sets(adb), adb.zone), (['Asia/Seoul', 'GMT'], 'GMT'))

    def test_a_device_already_in_seoul_is_left_alone(self):
        adb = TimezoneAdb('Asia/Seoul')
        with patched(adb), emu.seoul_timezone(S, sleep=lambda s: None):
            pass
        self.assertEqual(adb.ran('service call'), [])

    def test_the_zone_is_put_back_even_when_the_body_fails(self):
        adb = TimezoneAdb('GMT')
        with patched(adb), self.assertRaises(RuntimeError):
            with emu.seoul_timezone(S, sleep=lambda s: None):
                raise RuntimeError('app failed')
        self.assertEqual(adb.zone, 'GMT')

    def test_a_zone_that_did_not_change_is_blocked_and_the_body_never_runs(self):
        adb, ran = TimezoneAdb('GMT', stuck=True), []
        with patched(adb), self.assertRaises(tools.Blocked) as ctx:
            with emu.seoul_timezone(S, sleep=lambda s: None):
                ran.append(1)
        self.assertIn('시간대', str(ctx.exception))
        self.assertEqual(ran, [])

    def test_a_real_phone_is_refused_without_touching_it(self):
        adb = TimezoneAdb('GMT')
        with patched(adb), self.assertRaises(tools.Blocked):
            with emu.seoul_timezone('R5CR12345', sleep=lambda s: None):
                pass
        self.assertEqual(adb.calls, [])

    def test_the_zone_takes_a_moment_to_show_so_it_is_read_again(self):
        adb = TimezoneAdb('GMT')
        reads = []

        def slow(serial, *args, check=True):
            line = ' '.join(args)
            if line == 'shell getprop persist.sys.timezone':
                reads.append(1)
                if adb.zone == 'Asia/Seoul' and len(reads) < 3:
                    return 'GMT\n'
            return adb(serial, *args, check=check)
        with patched(slow):
            with emu.seoul_timezone(S, sleep=lambda s: None):
                self.assertEqual(adb.zone, 'Asia/Seoul')
        self.assertEqual(adb.zone, 'GMT')


class BrowserTest(unittest.TestCase):
    def test_disables_every_browser_then_enables_them_again(self):
        adb = FakeAdb({'query-activities': [CHROME, NONE], 'pm disable-user': 'Package com.android.chrome new state: disabled-user'})
        with patched(adb):
            with emu.browsers_disabled(S):
                self.assertTrue(adb.ran('pm disable-user --user 0 com.android.chrome'))
                self.assertFalse(adb.ran('pm enable'))
        self.assertTrue(adb.ran('pm enable com.android.chrome'))

    def test_cannot_disable_is_blocked(self):
        adb = FakeAdb({'query-activities': CHROME, 'pm disable-user': 'Exception: SecurityException: Shell cannot change component state'})
        with patched(adb), self.assertRaises(tools.Blocked):
            with emu.browsers_disabled(S):
                pass

    def test_a_browser_that_comes_back_is_blocked_and_still_enabled_after(self):
        adb = FakeAdb({'query-activities': CHROME, 'pm disable-user': 'new state: disabled-user'})
        with patched(adb), self.assertRaises(tools.Blocked):
            with emu.browsers_disabled(S):
                pass
        self.assertTrue(adb.ran('pm enable com.android.chrome'))


class CaseTest(Base):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(area1_emu.notify, 'grant_notifications')  # 실제 adb 는 부르지 않는다
        self.grant = patcher.start()
        self.addCleanup(patcher.stop)

    def phone(self, **kw):
        phone = FakePhone(**kw)
        phone.serial = S
        return phone

    def test_auth_22_phone_crash_still_turns_the_network_on(self):
        self.serve()
        phone = self.phone()
        online = []
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', side_effect=lambda s: online.append(s) or True),                 mock.patch.object(phone, 'answers', [ZeroDivisionError]), mock.patch.object(FakePhone, '__call__', side_effect=ZeroDivisionError):
            with self.assertRaises(ZeroDivisionError):
                area1.attempt_phone(self.run, 'E-AUTH-22', phone)
        self.assertTrue(online)

    def test_gate_47_crash_still_turns_the_network_on(self):
        self.serve()
        online = []
        with mock.patch.object(area1_emu.area1_b3, '_submit', side_effect=ZeroDivisionError),                 mock.patch.object(emu, 'go_online', side_effect=lambda s: online.append(s) or True):
            with self.assertRaises(ZeroDivisionError):
                area1.attempt_phone(self.run, 'E-GATE-47', self.phone())
        self.assertTrue(online)

    def test_network_that_stays_down_after_the_case_is_blocked_not_silent(self):
        self.serve()
        phone = self.phone(midway_step={'step': 'online'})
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=False):
            result, note = area1.attempt_phone(self.run, 'E-AUTH-22', phone)
        self.assertEqual(result, 'blocked')
        self.assertIn('네트워크', note)

    def test_clock_case_runs_last_because_root_stays_on(self):
        self.assertEqual(area1.BUNDLES['area1-emu'][-1], 'E-AUTH-19')

    def test_every_case_refuses_a_real_phone(self):
        self.serve()
        for case in area1_emu.PHONE:
            phone = FakePhone()
            phone.serial = 'R5CR12345'
            self.assertEqual(area1.attempt_phone(self.run, case, phone)[0], 'blocked', case)

    def test_every_emulator_case_pre_grants_the_notification_permission(self):
        # 첫 로그인의 알림 권한 창이 가설 도중 앱 앞을 가리지 않게(영역 4 SET 도 같은 이유로 미리 준다) — 에뮬 시리얼에만
        self.serve({('GET', '/rest/v1/student_verification_attempts'): Reply(200, [])})
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=True),                 mock.patch.object(emu, 'root'), mock.patch.object(emu, 'browsers_disabled', side_effect=tools.Blocked('x')),                 mock.patch.object(emu, 'clock_shifted', side_effect=tools.Blocked('x')),                 mock.patch.object(area1_emu.area1_b3, '_push'), mock.patch.object(area1_emu.area1_b3, '_photos'):
            for case in area1_emu.PHONE:
                self.grant.reset_mock()
                area1.attempt_phone(self.run, case, self.phone())
                self.grant.assert_called_once_with(S, )

    def test_a_real_phone_never_gets_the_permission_call(self):
        self.serve()
        phone = FakePhone()
        phone.serial = 'R5CR12345'
        for case in area1_emu.PHONE:
            area1.attempt_phone(self.run, case, phone)
        self.grant.assert_not_called()

    def test_a_device_without_the_notification_permission_still_runs(self):
        self.serve()
        self.grant.side_effect = tools.Blocked('안드로이드 12 이하')
        with mock.patch.object(emu, 'go_online', return_value=True), mock.patch.object(emu, 'go_offline'):
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-22', self.phone(midway_step={'step': 'online'}))[0], 'pass')

    def test_bundle_is_the_four_emulator_hypotheses(self):
        self.assertEqual(sorted(area1.BUNDLES['area1-emu']), ['E-AUTH-19', 'E-AUTH-22', 'E-GATE-12', 'E-GATE-47'])
        self.assertTrue(set(area1_emu.PHONE) <= set(area1.PHONE))

    def test_auth_22_runs_login_offline_restart_and_always_turns_the_network_back_on(self):
        self.serve()
        phone = self.phone(midway_step={'step': 'online'})
        offline, online = [], []
        with mock.patch.object(emu, 'go_offline', side_effect=lambda s: offline.append(s)), \
                mock.patch.object(emu, 'go_online', side_effect=lambda s: online.append(s) or True):
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-22', phone)[0], 'pass')
        self.assertEqual([j['phase'] for j in phone.jobs], ['login', 'offline', 'restart'])
        self.assertIs(phone.jobs[1]['fresh'], False)
        self.assertEqual(len(offline), 1)
        self.assertGreaterEqual(len(online), 2)  # 앱이 멈춘 사이 + 끝에 한 번 더
        # 에뮬(소프트웨어 렌더링 + 세션 새로고침)은 실폰 기준 5초가 모자란다 — 끝의 다시 실행은 30초까지 기다리고, 앱이 걸린 시간을 알린다
        self.assertEqual(phone.jobs[2]['limit'], 30)

    def test_auth_22_passes_on_with_the_apps_timing_notes_so_a_slow_pass_is_visible(self):
        self.serve()
        phone = FakePhone({'result': 'pass'}, {'result': 'pass', 'note': '다시 시도 → 홈 900ms'},
                          {'result': 'pass', 'note': '7000ms (시나리오 5초 초과)'}, midway_step={'step': 'online'})
        phone.serial = S
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=True):
            result, note = area1.attempt_phone(self.run, 'E-AUTH-22', phone)
        self.assertEqual(result, 'pass')
        self.assertIn('900ms', note)
        self.assertIn('시나리오 5초 초과', note)

    def test_auth_22_app_failure_still_restores_the_network(self):
        self.serve()
        phone = self.phone()
        phone.answers = [{'result': 'fail', 'note': 'x'}]
        online = []
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', side_effect=lambda s: online.append(s) or True):
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-22', phone)[0], 'fail')
        self.assertTrue(online)

    def test_auth_22_network_that_is_still_down_at_the_very_end_is_blocked(self):
        # 앱이 멈춘 사이엔 켜졌지만(첫 호출 True) 끝에서 다시 읽었더니 안 닿는다 → 다음 가설이 엉뚱하게 틀리지 않게 blocked
        self.serve()
        phone = self.phone(midway_step={'step': 'online'})
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', side_effect=[True, False]):
            result, note = area1.attempt_phone(self.run, 'E-AUTH-22', phone)
        self.assertEqual(result, 'blocked')
        self.assertIn('네트워크', note)

    def test_gate_47_network_that_is_still_down_at_the_end_is_blocked(self):
        self.serve({('GET', '/rest/v1/student_verification_attempts'): Reply(200, [])})
        with mock.patch.object(area1_emu.area1_b3, '_push'), mock.patch.object(area1_emu.area1_b3, '_photos'),                 mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=False):
            result, note = area1.attempt_phone(self.run, 'E-GATE-47', self.phone(midway_step={'step': 'filled'}))
        self.assertEqual(result, 'blocked')
        self.assertIn('네트워크', note)

    def test_auth_22_network_that_does_not_come_back_is_blocked(self):
        self.serve()
        phone = self.phone(midway_step={'step': 'online'})
        with mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=False):
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-22', phone)[0], 'blocked')

    def test_auth_19_needs_root_else_blocked_without_touching_the_clock(self):
        self.serve()
        with mock.patch.object(emu, 'root', side_effect=tools.Blocked('root 안 됨')), mock.patch.object(emu, 'clock_shifted') as clock:
            result, note = area1.attempt_phone(self.run, 'E-AUTH-19', self.phone())
        self.assertEqual(result, 'blocked')
        self.assertIn('root', note)
        clock.assert_not_called()

    def test_auth_19_logs_in_then_reopens_two_hours_later(self):
        self.serve()
        phone = self.phone()
        shifted = []

        @contextlib.contextmanager
        def clock(serial, hours):
            shifted.append(hours)
            yield
        with mock.patch.object(emu, 'root'), mock.patch.object(emu, 'clock_shifted', clock):
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-19', phone)[0], 'pass')
        self.assertEqual(shifted, [2])
        self.assertEqual([j['phase'] for j in phone.jobs], ['login', 'later'])
        self.assertEqual(phone.jobs[1]['expect'], 'home')

    def test_gate_12_opens_the_app_with_browsers_disabled(self):
        self.serve()
        state = []

        @contextlib.contextmanager
        def browsers(serial):
            state.append('off')
            yield
            state.append('on')
        with mock.patch.object(emu, 'browsers_disabled', browsers):
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-12', self.phone())[0], 'pass')
        self.assertEqual(state, ['off', 'on'])

    def test_gate_47_cuts_the_network_while_the_app_waits_and_the_server_never_saw_a_submit(self):
        self.serve({('GET', '/rest/v1/student_verification_attempts'): Reply(200, [])})
        phone = self.phone(midway_step={'step': 'filled'})
        cut, back = [], []
        with mock.patch.object(area1_emu.area1_b3, '_push'), mock.patch.object(area1_emu.area1_b3, '_photos'), \
                mock.patch.object(emu, 'go_offline', side_effect=lambda s: cut.append(s)), \
                mock.patch.object(emu, 'go_online', side_effect=lambda s: back.append(s) or True):
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-47', phone)[0], 'pass')
        self.assertEqual((len(cut), len(back)), (1, 1))
        self.assertEqual(phone.jobs[0]['photo'], 'id_ok.jpg')

    def test_gate_47_a_submit_row_on_the_server_fails(self):
        self.serve({('GET', '/rest/v1/student_verification_attempts'): Reply(200, [{'result': 'verified'}])})
        with mock.patch.object(area1_emu.area1_b3, '_push'), mock.patch.object(area1_emu.area1_b3, '_photos'), \
                mock.patch.object(emu, 'go_offline'), mock.patch.object(emu, 'go_online', return_value=True):
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-47', self.phone(midway_step={'step': 'filled'}))[0], 'fail')


if __name__ == '__main__':
    unittest.main()
