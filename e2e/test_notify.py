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
ACCEPT = record(OURS, f'0|{OURS}|12|FCM-Notification:2|10123', '대화 신청이 왔어요', '민트 님이 대화를 신청했어요', wrapped=False)


class ParseTest(unittest.TestCase):
    def test_reads_only_our_app_with_key_title_text_and_channel(self):
        found = notify.parse_notifications(USB + CARD + ACCEPT)
        self.assertEqual([(n.title, n.text, n.channel) for n in found],
                         [('오늘의 카드가 도착했어요', '지금 확인해 보세요', 'campus_mate_default'),
                          ('대화 신청이 왔어요', '민트 님이 대화를 신청했어요', 'campus_mate_default')])
        self.assertIn('FCM-Notification:1', found[0].key)

    def test_a_title_that_ends_with_a_parenthesis_is_kept_whole(self):
        found = notify.parse_notifications(record(OURS, 'k1', '제목', '안녕(웃음)'))
        self.assertEqual(found[0].text, '안녕(웃음)')

    def test_dotted_extras_between_title_and_text_do_not_leak_into_the_value(self):
        # 실제 dump 는 title · text 사이에 `android.reduced.images=true` 같은 점 있는 키가 낀다 — 값이 거기서 끝나야 한다
        dump = record(OURS, 'k1', '친구가 가입했어요', '본문')
        text_line = 'android.text=String (본문)'
        self.assertEqual(dump.count(text_line), 1)
        dotted = dump.replace(text_line, 'android.reduced.images=true\n      android.subText=null\n'
                              '      android.template=android.app.Notification$BigTextStyle\n      ' + text_line + '\n      android.progress=0')
        [got] = notify.parse_notifications(dotted)
        self.assertEqual((got.title, got.text), ('친구가 가입했어요', '본문'))

    def test_keys_that_are_not_android_dot_also_end_the_value(self):
        # text 바로 뒤에 androidx · google 접두어 키가 와도 본문에 새지 않는다
        dump = record(OURS, 'k1', '제목', '본문')
        text_line = 'android.text=String (본문)'
        tail = (text_line + '\n      androidx.core.app.extra.COMPAT_TEMPLATE=String (x)\n      google.sent_time=Long (1700000000000)')
        [got] = notify.parse_notifications(dump.replace(text_line, tail))
        self.assertEqual((got.title, got.text), ('제목', '본문'))

    def test_a_body_line_with_an_equals_sign_is_still_part_of_the_body(self):
        dump = record(OURS, 'k1', '제목', 'x').replace('android.text=String (x)', 'android.text=String (a\nb=c\nd.e=f)')
        [got] = notify.parse_notifications(dump)
        self.assertEqual(got.text, 'a\nb=c\nd.e=f')

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
        self.assertEqual([n.title for n in got], ['대화 신청이 왔어요'])

    def test_wait_new_waits_for_the_requested_count(self):
        with self.reads(USB + CARD, USB + CARD + ACCEPT):
            got = notify.wait_new('S', [], count=2, seconds=60)
        self.assertEqual(len(got), 2)

    def test_wait_new_gives_up_after_the_time_and_returns_what_it_has(self):
        ticks = iter(range(0, 1000, 10))
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)), \
                mock.patch.object(tools, 'adb', return_value=USB):
            self.assertEqual(notify.wait_new('S', [], count=1, seconds=60), [])

    def test_wait_new_with_a_match_keeps_waiting_past_an_unrelated_new_one(self):
        ticks = iter(range(0, 1000, 10))
        dumps = [USB + ACCEPT, USB + ACCEPT, USB + ACCEPT + CARD]  # 다른 새 알림이 먼저 오고 기다리던 것이 뒤따른다
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)),                 mock.patch.object(notify.time, 'sleep', lambda s: None), mock.patch.object(tools, 'adb', side_effect=dumps):
            got = notify.wait_new('S', [], seconds=60, match=lambda n: n.title == '오늘의 카드가 도착했어요')
        self.assertEqual({n.title for n in got} >= {'오늘의 카드가 도착했어요'}, True)

    def test_wait_new_with_a_match_gives_up_and_returns_what_arrived_instead(self):
        ticks = iter(range(0, 1000, 10))
        with mock.patch.object(notify.time, 'monotonic', side_effect=lambda: next(ticks)),                 mock.patch.object(notify.time, 'sleep', lambda s: None), mock.patch.object(tools, 'adb', return_value=USB + ACCEPT):
            got = notify.wait_new('S', [], seconds=60, match=lambda n: False)
        self.assertEqual(len(got), 1)  # 안 맞아도 온 것은 돌려준다 — 가설이 메모에 실제 글을 남긴다

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
    FRONT = "  topResumedActivity=ActivityRecord{1 u0 " + OURS + "/.MainActivity t5}"
    OTHER = "  topResumedActivity=ActivityRecord{2 u0 com.android.systemui/.Shade t1}"

    def setUp(self):
        patch = mock.patch.object(notify.time, 'sleep')
        patch.start()
        self.addCleanup(patch.stop)

    def run_tap(self, dump, title='오늘의 카드가 도착했어요', body=None, tops=None, dumps=None):
        """[tops]: 앞 앱을 읽을 때마다 다음 값(마지막은 계속), 기본은 바로 우리 앱. [dumps]: 화면 덤프를 읽을 때마다 다음 값."""
        sent, reads = [], []
        tops = list(tops or [self.FRONT])
        dumps = list(dumps or [dump])

        def read(*a, **k):
            reads.append(1)
            text = dumps.pop(0) if len(dumps) > 1 else dumps[0]
            return subprocess.CompletedProcess([], 0, stdout=text.encode('utf-8'), stderr=b'')

        def adb(s, *a, check=True):
            sent.append(a)
            if a[:3] == ('shell', 'dumpsys', 'activity'):
                return tops.pop(0) if len(tops) > 1 else tops[0]
            return ''
        self.reads = reads
        with mock.patch.object(notify.subprocess, 'run', read), mock.patch.object(tools, 'adb', adb):
            try:
                notify.tap_notification('S', title, body)
            finally:
                self.sent = sent

    def taps(self):
        return [a[-2:] for a in self.sent if a[:3] == ('shell', 'input', 'tap')]

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
        self.run_tap(ui(('대화 신청이 왔어요', '[0,0][100,100]')), title='대화 신청이 왔어요')
        self.assertIn(('shell', 'input', 'tap', '50', '50'), self.sent)

    # ── 눌렀는데 앱이 안 열린 경우(실기기: 짧은 닉네임 제목 알림을 눌러도 알림창이 그대로 열려 있었다) ──
    ROW = ui(('Rbxpr', '[170,600][260,660]'), ('E2E-tap-79bda2', '[170,670][420,720]'))

    def test_after_the_tap_the_app_must_come_to_the_front_or_it_taps_again(self):
        self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        self.assertEqual(len(self.taps()), 2)  # 첫 눌림에 안 열려 한 번 더

    def test_the_second_tap_lands_on_a_different_spot_the_body_line(self):
        self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        self.assertEqual(self.taps(), [('215', '630'), ('295', '695')])  # 제목 글자 한가운데 → 본문 줄 한가운데

    def test_a_tap_that_never_opens_the_app_is_blocked_after_three_tries_and_the_shade_is_closed(self):
        with self.assertRaises(Blocked) as why:
            self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', tops=[self.OTHER])
        self.assertEqual(len(self.taps()), 3)
        self.assertIn('앱이 앞으로 안 옴', str(why.exception))
        self.assertIn(('shell', 'cmd', 'statusbar', 'collapse'), self.sent)

    def test_the_shade_is_opened_again_before_a_retry_in_case_the_tap_did_not_close_it(self):
        self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        expands = [a for a in self.sent if a == ('shell', 'cmd', 'statusbar', 'expand-notifications')]
        self.assertEqual(len(expands), 2)

    def test_a_slow_start_whose_notice_vanished_after_the_first_tap_is_a_pass_not_a_false_blocked(self):
        # 첫 누름이 먹혀 알림이 사라졌는데 앱이 8초를 넘겨 뜬다 — 재시도 때 알림이 없다고 blocked 하면 앱이 실제로 열렸는데도 실패로 읽힌다
        gone = ui(('다른 알림', '[100,300][500,360]'))
        self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', dumps=[self.ROW, self.ROW, gone], tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        self.assertEqual(len(self.taps()), 1)

    def test_a_missing_notice_on_a_retry_is_still_blocked_when_the_app_never_came(self):
        gone = ui(('다른 알림', '[100,300][500,360]'))
        with self.assertRaises(Blocked):
            self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2', dumps=[self.ROW, self.ROW, gone], tops=[self.OTHER])

    def test_a_body_above_the_title_does_not_make_the_title_the_row(self):
        above = ui(('E2E-tap-79bda2', '[170,500][420,550]'), ('Rbxpr', '[170,600][260,660]'))
        with self.assertRaises(Blocked):
            self.run_tap(above, title='Rbxpr', body='E2E-tap-79bda2')
        self.assertEqual(self.taps(), [])

    def test_the_app_already_in_front_after_the_first_tap_means_one_tap_only(self):
        self.run_tap(self.ROW, title='Rbxpr', body='E2E-tap-79bda2')
        self.assertEqual(len(self.taps()), 1)

    def test_with_a_body_it_picks_the_row_whose_body_matches_not_an_older_row_with_the_same_title(self):
        old_and_new = ui(('매칭됐어요!', '[100,300][500,360]'), ('옛 닉네임 님이 신청을 수락했어요.', '[100,370][500,420]'),
                         ('매칭됐어요!', '[100,700][500,760]'), ('Mina 님이 신청을 수락했어요.', '[100,770][500,820]'))
        self.run_tap(old_and_new, title='매칭됐어요!', body='Mina 님이 신청을 수락했어요.')
        self.assertEqual(self.taps()[0], ('300', '730'))  # 아래쪽(새) 줄의 제목

    def test_a_body_that_no_row_has_is_blocked_not_a_tap_on_the_wrong_row(self):
        with self.assertRaises(Blocked):
            self.run_tap(ui(('Rbxpr', '[170,600][260,660]'), ('다른 글', '[170,670][420,720]')), title='Rbxpr', body='E2E-tap-79bda2')
        self.assertEqual(self.taps(), [])

    SAMSUNG = ui(('Eoswc', '[204,748][322,803]'), ('오전 6:42', '[345,754][472,800]'), ('E2E-32-fe6a3b1c', '[204,806][960,862]'),
                 ('다른 알림', '[204,951][272,1009]'))

    def test_without_a_body_the_second_tap_is_the_first_text_line_under_the_title_not_the_time_beside_it(self):
        # 실기기(삼성): 짧은 제목 글자를 눌러도 안 열리고 아래 본문 줄을 누르면 열린다 — 본문을 안 줘도 제목만 세 번 누르지 않는다
        self.run_tap(self.SAMSUNG, title='Eoswc', tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        self.assertEqual(self.taps(), [('263', '775'), ('582', '834')])

    def test_without_a_body_and_with_nothing_under_the_title_it_taps_the_title_again(self):
        self.run_tap(ui(('Rbxpr', '[170,600][260,660]')), title='Rbxpr', tops=[self.OTHER] * notify.FRONT_WAIT + [self.FRONT])
        self.assertEqual(self.taps(), [('215', '630'), ('215', '630')])

    def test_a_shade_that_is_still_moving_is_read_again_until_the_spot_stops_changing(self):
        moving = ui(('Rbxpr', '[170,900][260,960]'))
        still = ui(('Rbxpr', '[170,600][260,660]'))
        self.run_tap(still, title='Rbxpr', dumps=[moving, still, still])
        self.assertEqual(self.taps(), [('215', '630')])  # 움직이던 때의 좌표(930)가 아니라 멈춘 뒤의 좌표
        self.assertEqual(len(self.reads), 3)


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


class UiDumpTest(unittest.TestCase):
    """실기기 확인(통합대장2): `adb shell uiautomator dump /dev/tty` 는 파이프로 받으면 XML 없이 안내 한 줄만 준다 — `exec-out` 만 XML 을 준다."""

    NOTICE = b'UI hierchary dumped to: /dev/tty'
    XML = '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\' ?><hierarchy rotation="0"><node text="오늘의 카드" bounds="[0,0][10,10]" /></hierarchy>'.encode('utf-8')

    def phone(self, via_shell=None):
        sent = []

        def fake(serial, *args, check=False):
            sent.append(args)
            return self.XML if args[0] == 'exec-out' else (self.NOTICE if via_shell is None else via_shell)
        return sent, mock.patch.object(tools, 'adb_bytes', fake)

    def test_the_dump_is_read_through_exec_out_not_shell(self):
        sent, patch = self.phone()
        with patch:
            self.assertIs(notify.screen_has('S', '오늘의 카드'), True)
        self.assertEqual(sent, [('exec-out', 'uiautomator', 'dump', '/dev/tty')])

    def test_a_dump_that_is_only_the_notice_line_is_blocked_not_read_as_nothing_on_screen(self):
        # 빈 화면을 읽고 "없음" 으로 판정하면 안 온다 · 안 보인다 가설이 헛통과한다
        with mock.patch.object(tools, 'adb_bytes', return_value=self.NOTICE), mock.patch.object(notify, 'DUMP_PAUSE', 0):
            with self.assertRaises(Blocked):
                notify.screen_has('S', '아무 글')

    def test_an_empty_dump_is_blocked_too(self):
        with mock.patch.object(tools, 'adb_bytes', return_value=b''), mock.patch.object(notify, 'DUMP_PAUSE', 0):
            with self.assertRaises(Blocked):
                notify.screen_has('S', '아무 글')

    def test_a_dump_that_fails_while_the_app_animates_is_read_again_up_to_three_times(self):
        # 앱이 애니메이션 중이면 uiautomator 가 한순간 XML 을 못 준다(E-HOME-30 첫 실행) — 곧 다시 읽으면 된다
        replies = [self.NOTICE, b'', self.XML]
        with mock.patch.object(tools, 'adb_bytes', side_effect=replies) as read, mock.patch.object(notify, 'DUMP_PAUSE', 0):
            self.assertIs(notify.screen_has('S', '오늘의 카드'), True)
        self.assertEqual(read.call_count, 3)

    def test_a_dump_that_never_comes_is_blocked_after_exactly_three_tries_one_second_apart(self):
        with mock.patch.object(tools, 'adb_bytes', return_value=self.NOTICE) as read, mock.patch.object(notify.time, 'sleep') as sleep:
            with self.assertRaises(Blocked):
                notify.screen_has('S', '아무 글')
        self.assertEqual(read.call_count, 3)
        self.assertEqual([c.args for c in sleep.call_args_list], [(1,), (1,)])  # 마지막 실패 뒤에는 쉬지 않는다

    def test_a_dump_that_comes_at_once_is_read_once_without_waiting(self):
        with mock.patch.object(tools, 'adb_bytes', return_value=self.XML) as read, mock.patch.object(notify.time, 'sleep') as sleep:
            notify.screen_has('S', '오늘의 카드')
        self.assertEqual((read.call_count, sleep.call_count), (1, 0))

    def test_the_second_copy_in_area2_phone3_reads_the_same_way(self):
        from e2e import area2_phone3
        sent, patch = self.phone()
        with patch:
            self.assertIn('오늘의 카드', area2_phone3._dump('S'))
        self.assertEqual(sent, [('exec-out', 'uiautomator', 'dump', '/dev/tty')])


class DeliveryTest(unittest.TestCase):
    """재부팅 뒤 푸시 연결이 죽어 FCM 이 폰에 안 뜬다 — Wi-Fi 를 껐다 켜면 GCM 이 다시 연결한다(실기기 확인)."""

    def phone(self, connects, wifi_on='1'):
        """connects: 읽을 때마다 다음 값(마지막은 계속). None 은 못 읽는 모양."""
        sent, reads = [], list(connects)

        def fake(serial, *args, check=True):
            sent.append(args)
            if args[:3] == ('shell', 'settings', 'get'):
                return wifi_on + chr(10)
            if args[:2] == ('shell', 'dumpsys'):
                value = reads.pop(0) if len(reads) > 1 else reads[0]
                return 'x' if value is None else f'GcmService state connects={value} lastConnect=0'
            return ''
        return sent, mock.patch.object(tools, 'adb', fake)

    def setUp(self):
        for target in (notify.time, ):
            for name in ('sleep',):
                patch = mock.patch.object(target, name)
                patch.start()
                self.addCleanup(patch.stop)
        notify._DELIVERY_READY.clear()

    def test_wifi_is_turned_off_then_on_and_the_gcm_connect_count_must_grow(self):
        sent, patch = self.phone([1, 1, 2])
        with patch:
            notify.prepare_delivery('S')
        toggles = [a[-1] for a in sent if a[:3] == ('shell', 'svc', 'wifi')]
        self.assertEqual(toggles, ['disable', 'enable'])

    def test_a_connect_count_that_never_grows_is_blocked(self):
        sent, patch = self.phone([3])
        with patch, mock.patch.object(notify, 'DELIVERY_WAIT', 6), mock.patch.object(notify.time, 'monotonic', side_effect=iter(range(0, 1000, 2))):
            with self.assertRaises(Blocked):
                notify.prepare_delivery('S')
        self.assertEqual([a[-1] for a in sent if a[:3] == ('shell', 'svc', 'wifi')][-1], 'enable')  # 실패해도 Wi-Fi 는 켜 둔다

    def test_a_connect_count_that_cannot_be_read_after_the_toggle_is_blocked_not_a_pass(self):
        sent, patch = self.phone([3, None])
        with patch, mock.patch.object(notify, 'DELIVERY_WAIT', 6), mock.patch.object(notify.time, 'monotonic', side_effect=iter(range(0, 1000, 2))):
            with self.assertRaises(Blocked):
                notify.prepare_delivery('S')

    def test_wifi_is_switched_back_on_even_when_enable_itself_fails_the_first_time(self):
        sent = []

        def fake(serial, *args, check=True):
            sent.append((args, check))
            if args[:3] == ('shell', 'settings', 'get'):
                return '1'
            if args[:2] == ('shell', 'dumpsys'):
                return 'connects=1'
            if args[:3] == ('shell', 'svc', 'wifi') and args[-1] == 'enable' and check:
                raise subprocess.CalledProcessError(1, 'adb')  # 엄격한 enable 이 터진다 — 그래도 느슨한(check=False) 복구 enable 이 뒤따라야 한다
            return ''
        with mock.patch.object(tools, 'adb', fake):
            with self.assertRaises(subprocess.CalledProcessError):
                notify.prepare_delivery('S')
        wifi = [(a[-1], check) for a, check in sent if a[:3] == ('shell', 'svc', 'wifi')]
        self.assertEqual(wifi[0][0], 'disable')
        self.assertEqual(wifi[-1], ('enable', False))  # 마지막 손길은 실패해도 안 던지는 켜기

    def test_an_unreadable_connect_count_is_blocked_before_touching_wifi(self):
        sent, patch = self.phone([None])
        with patch:
            with self.assertRaises(Blocked):
                notify.prepare_delivery('S')
        self.assertEqual([a for a in sent if a[:3] == ('shell', 'svc', 'wifi')], [])

    def test_a_phone_with_wifi_off_is_blocked_and_left_alone(self):
        sent, patch = self.phone([1, 2], wifi_on='0')
        with patch:
            with self.assertRaises(Blocked):
                notify.prepare_delivery('S')
        self.assertEqual([a for a in sent if a[:3] == ('shell', 'svc', 'wifi')], [])

    def test_ensure_delivery_prepares_once_per_phone(self):
        sent, patch = self.phone([1, 2])
        with patch:
            notify.ensure_delivery('S')
            notify.ensure_delivery('S')
        self.assertEqual([a[-1] for a in sent if a[:3] == ('shell', 'svc', 'wifi')], ['disable', 'enable'])

    def test_a_failed_preparation_is_not_remembered_as_done(self):
        sent, patch = self.phone([None])
        with patch:
            with self.assertRaises(Blocked):
                notify.ensure_delivery('S')
            with self.assertRaises(Blocked):
                notify.ensure_delivery('S')


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
