"""알림 읽기 · 누르기 · 앱 상태 도우미(`e2e/notify.py`)의 시험. 폰 없이: `python -m unittest e2e.test_notify`."""
import subprocess
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from e2e import notify, tools
from e2e.tools import Blocked

SEOUL = timezone(timedelta(hours=9))
OURS = tools.PACKAGE


def record(pkg, key, title, text, channel='campus_mate_default', wrapped=True):
    """안드로이드 13~14 의 dumpsys notification 한 건(줄 모양을 둘 다 만든다 — 값이 `String (글)` 로 싸이거나 맨글)."""
    value = (lambda v: f'String ({v})') if wrapped else (lambda v: v)
    return (f'  NotificationRecord(0x0abc123: pkg={pkg} user=UserHandle{{0}} id=0 tag=null importance=4 key={key}: '
            f'Notification(channel={channel} shortcut=null contentView=null))\n'
            f'    uid=10123 userId=0\n    extras={{\n'
            f'      android.title={value(title)}\n      android.text={value(text)}\n    }}\n')


USB = record('android', '0|android|1|null|1000', 'USB 디버깅이 연결됨', '탭하여 끄기', channel='ADB')
CARD = record(OURS, f'0|{OURS}|11|FCM-Notification:1|10123', '오늘의 카드가 도착했어요', '지금 확인해 보세요')
ACCEPT = record(OURS, f'0|{OURS}|12|FCM-Notification:2|10123', '나를 수락한 사람이 있어요', '민트 님이 대화를 하고 싶어 해요', wrapped=False)


class ParseTest(unittest.TestCase):
    def test_reads_only_our_app_with_key_title_text_and_channel(self):
        found = notify.parse_notifications(USB + CARD + ACCEPT)
        self.assertEqual([(n.title, n.text, n.channel) for n in found],
                         [('오늘의 카드가 도착했어요', '지금 확인해 보세요', 'campus_mate_default'),
                          ('나를 수락한 사람이 있어요', '민트 님이 대화를 하고 싶어 해요', 'campus_mate_default')])
        self.assertIn('FCM-Notification:1', found[0].key)

    def test_a_title_that_ends_with_a_parenthesis_is_kept_whole(self):
        found = notify.parse_notifications(record(OURS, 'k1', '제목', '안녕(웃음)'))
        self.assertEqual(found[0].text, '안녕(웃음)')

    def test_a_multiline_body_is_read_whole_and_unwrapped(self):
        dump = record(OURS, 'k1', '제목', 'x').replace('android.text=String (x)', 'android.text=SpannableString (줄1\n줄2)')
        self.assertEqual(notify.parse_notifications(dump)[0].text, '줄1\n줄2')

    def test_other_apps_text_is_never_returned(self):
        found = notify.parse_notifications(USB + CARD)
        self.assertNotIn('USB', repr(found))

    def test_a_dump_without_any_record_is_blocked_so_that_none_cannot_pass_by_mistake(self):
        for dump in ('', 'Permission Denial: can\'t dump notification', 'Current Notification Manager state:\n'):
            with self.subTest(dump=dump), mock.patch.object(tools, 'adb', return_value=dump):
                with self.assertRaises(Blocked):
                    notify.read_notifications('S')

    def test_our_app_having_none_is_an_empty_list_not_blocked(self):
        with mock.patch.object(tools, 'adb', return_value=USB):
            self.assertEqual(notify.read_notifications('S'), [])


class WaitTest(unittest.TestCase):
    def reads(self, *dumps):
        calls = iter(dumps)
        return mock.patch.object(tools, 'adb', side_effect=lambda *a, **k: next(calls))

    def setUp(self):
        for name in ('sleep',):
            patch = mock.patch.object(notify.time, name)
            patch.start()
            self.addCleanup(patch.stop)

    def test_wait_new_returns_only_what_was_not_there_before(self):
        before = notify.parse_notifications(USB + CARD)
        with self.reads(USB + CARD, USB + CARD + ACCEPT):
            got = notify.wait_new('S', before, count=1, seconds=60)
        self.assertEqual([n.title for n in got], ['나를 수락한 사람이 있어요'])

    def test_wait_new_waits_for_the_requested_count(self):
        with self.reads(USB + CARD, USB + CARD + ACCEPT):
            got = notify.wait_new('S', [], count=2, seconds=60)
        self.assertEqual(len(got), 2)

    def test_wait_new_gives_up_after_the_time_and_returns_what_it_has(self):
        ticks = iter(range(0, 1000, 10))
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)), \
                mock.patch.object(tools, 'adb', return_value=USB):
            self.assertEqual(notify.wait_new('S', [], count=1, seconds=60), [])

    def test_expect_none_returns_what_showed_up_during_the_whole_time(self):
        ticks = iter(range(0, 1000, 10))
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)), \
                mock.patch.object(tools, 'adb', side_effect=[USB, USB, USB, USB + CARD, USB + CARD, USB + CARD, USB + CARD]):
            self.assertEqual([n.title for n in notify.expect_none('S', [], seconds=60)], ['오늘의 카드가 도착했어요'])

    def test_expect_none_keeps_watching_after_the_first_one_to_catch_a_later_one(self):
        ticks = iter(range(0, 1000, 10))
        dumps = [USB, USB + CARD, USB + CARD, USB + CARD + ACCEPT, USB + CARD + ACCEPT, USB + CARD + ACCEPT, USB + CARD + ACCEPT]
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)),                 mock.patch.object(tools, 'adb', side_effect=dumps):
            got = notify.expect_none('S', [], seconds=60)
        self.assertEqual(len(got), 2)

    def test_expect_none_is_empty_when_nothing_came(self):
        ticks = iter(range(0, 1000, 10))
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)), \
                mock.patch.object(tools, 'adb', return_value=USB):
            self.assertEqual(notify.expect_none('S', [], seconds=60), [])


def ui(*nodes):
    """uiautomator dump(/dev/tty) — 맨 끝에 안내 줄이 붙는다."""
    body = ''.join(f'<node text="{text}" bounds="{bounds}" />' for text, bounds in nodes)
    return f'<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\' ?><hierarchy rotation="0">{body}</hierarchy>UI hierchary dumped to: /dev/tty'


class TapTest(unittest.TestCase):
    def setUp(self):
        patch = mock.patch.object(notify.time, 'sleep')
        patch.start()
        self.addCleanup(patch.stop)

    def run_tap(self, dump, title='오늘의 카드가 도착했어요'):
        sent = []
        done = subprocess.CompletedProcess([], 0, stdout=dump.encode('utf-8'), stderr=b'')
        with mock.patch.object(notify.subprocess, 'run', return_value=done), \
                mock.patch.object(tools, 'adb', lambda s, *a, check=True: sent.append(a) or ''):
            try:
                notify.tap_notification('S', title)
            finally:
                self.sent = sent

    def test_opens_the_shade_taps_the_middle_of_the_title_and_closes_it_when_done(self):
        self.run_tap(ui(('CampusMate', '[10,200][400,260]'), ('오늘의 카드가 도착했어요', '[100,300][500,360]')))
        self.assertEqual(self.sent[0], ('shell', 'cmd', 'statusbar', 'expand-notifications'))
        self.assertIn(('shell', 'input', 'tap', '300', '330'), self.sent)

    def test_a_title_that_is_not_on_the_shade_is_blocked_and_the_shade_is_closed(self):
        with self.assertRaises(Blocked):
            self.run_tap(ui(('다른 알림', '[100,300][500,360]')))
        self.assertIn(('shell', 'cmd', 'statusbar', 'collapse'), self.sent)

    def test_an_empty_dump_is_blocked_not_a_parse_error(self):
        with self.assertRaises(Blocked):
            self.run_tap('')

    def test_unicode_in_the_dump_is_read_as_utf8(self):
        self.run_tap(ui(('나를 수락한 사람이 있어요', '[0,0][100,100]')), title='나를 수락한 사람이 있어요')
        self.assertIn(('shell', 'input', 'tap', '50', '50'), self.sent)


class AppStateTest(unittest.TestCase):
    def setUp(self):
        patch = mock.patch.object(notify.time, 'sleep')
        patch.start()
        self.addCleanup(patch.stop)

    def adb(self, pids):
        sent = []
        pids = iter(pids)

        def fake(serial, *a, check=True):
            sent.append(a)
            if a[:2] == ('shell', 'pidof'):
                return next(pids)
            return ''
        return sent, mock.patch.object(tools, 'adb', fake)

    def test_background_presses_home(self):
        sent, patch = self.adb([])
        with patch:
            notify.background('S')
        self.assertEqual(sent, [('shell', 'input', 'keyevent', 'KEYCODE_HOME')])

    def test_kill_app_goes_home_then_kills_the_process_without_force_stop(self):
        sent, patch = self.adb(['1234\n', ''])
        with patch:
            notify.kill_app('S')
        self.assertEqual(sent[0], ('shell', 'input', 'keyevent', 'KEYCODE_HOME'))
        self.assertIn(('shell', 'am', 'kill', tools.PACKAGE), sent)
        self.assertNotIn('force-stop', ' '.join(' '.join(a) for a in sent))  # 멈춘 앱이 되면 FCM 이 아예 안 온다

    def test_kill_app_retries_then_falls_back_to_run_as_kill(self):
        sent, patch = self.adb(['1234\n'] * 6 + [''])  # 다섯 번 시도 · 마지막 pid 읽기 · run-as 뒤 확인
        with patch:
            notify.kill_app('S')
        self.assertTrue(any(a[:4] == ('shell', 'run-as', tools.PACKAGE, 'kill') for a in sent))

    def test_kill_app_that_never_dies_is_blocked(self):
        sent, patch = self.adb(['1234\n'] * 30)
        with patch, self.assertRaises(Blocked):
            notify.kill_app('S')

    def test_alive_reads_pidof(self):
        sent, patch = self.adb(['99\n', ''])
        with patch:
            self.assertTrue(notify.alive('S'))
            self.assertFalse(notify.alive('S'))


class DaytimeTest(unittest.TestCase):
    def at(self, hour, minute=0):
        return datetime(2026, 10, 5, hour, minute, tzinfo=SEOUL)

    def test_inside_08_to_22_passes(self):
        for h, m in ((8, 0), (12, 30), (21, 59)):
            with self.subTest(h=h):
                notify.require_daytime(self.at(h, m))

    def test_outside_is_blocked(self):
        for h, m in ((7, 59), (22, 0), (3, 0)):
            with self.subTest(h=h), self.assertRaises(Blocked):
                notify.require_daytime(self.at(h, m))

    def test_other_time_zones_are_read_in_seoul_time(self):
        utc = datetime(2026, 10, 5, 3, 0, tzinfo=timezone.utc)  # 서울 12시
        notify.require_daytime(utc)


if __name__ == '__main__':
    unittest.main()
