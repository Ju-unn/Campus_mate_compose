"""영역 3 알림 10개(E-CHAT-17 · 26 · 27 · 28 · 29 · 30 · 31 · 33 · 35 · 59, 묶음 area3-chat-nt)의 PC 쪽 시험 — 폰 · 운영 · gcloud 없이
가짜 HTTP · 가짜 알림창 · 가짜 앱 · 가짜 시계로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3_chat_nt`.

가짜 알림창(test_area4_push.World)에 서버 규칙을 흉내 내는 [Base10.push_rule] 을 더했다 — 올바른 서버(줄바꿈 → 공백 · 40자 · 방에 있으면 안 보냄 · 스위치 · 앞이면 배너 없음)면
pass, 어긋난 서버면 fail 이어야 한다. 시계는 가짜(`self.now`): `time.sleep` · 알림을 지켜보는 시간이 시계를 그만큼 흘리고, 서버의 "방에 있다" 30초 창이 그 시계로 닫힌다.
계정은 만든 순서대로 id-1(폰 계정 · Mina) · id-2(상대 · Jiho) · id-3(대조 · Ctlx), 토큰은 tok-1 · tok-2 · tok-3.
"""

import re
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from e2e import area1, area3, area3_chat_nt, notify, tools
from e2e.test_area1_phone import FakePhone
from e2e.test_area4_push import CTL, ME, PARTNER, PushBase
from e2e.tools import Blocked, Reply

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ['E-CHAT-17', 'E-CHAT-26', 'E-CHAT-27', 'E-CHAT-28', 'E-CHAT-29', 'E-CHAT-30', 'E-CHAT-31', 'E-CHAT-33', 'E-CHAT-35', 'E-CHAT-59']
WINDOW = 30  # 서버 chat/router.py IN_ROOM_WINDOW


class Phone10(FakePhone):
    """가짜 앱. [acts] 는 앱이 k 번째 `step` 에 닿을 때 세상에서 일어나는 일(함수 또는 None) — 첫 멈춤은 midway 를 부르기 전에, 다음 멈춤은 stepper 가
    hub.wait 로 부를 때마다 하나씩 돈다. [answers] 는 앱이 끝에 하는 말(앱을 켠 횟수만큼 차례로)."""

    def __init__(self, world, *answers, acts=(), on_call=None):
        super().__init__(*answers)
        self.world, self.acts, self.on_call = world, list(acts), on_call
        self.hub = mock.Mock()
        self.hub.go.side_effect = lambda extra=None: world.log.append('go')
        self.hub.wait.side_effect = self._next_step

    def _next_step(self, timeout=None):
        act = self.acts.pop(0) if self.acts else None
        if act:
            act()
        return {'step': 'x'}

    def __call__(self, midway=None, **job):
        self.world.log.append(f"app:{job.get('phase', '-')}")
        self.jobs.append(job)
        if self.on_call:
            self.on_call(job)
        if midway:
            self._next_step()
            midway({'step': 'x'})
        said = self.answers.pop(0) if len(self.answers) > 1 else self.answers[0]
        return said(job) if callable(said) else said  # 일감에 든 값(방금 보낸 글 등)을 앱이 되말하는 판


class Base10(PushBase):
    def setUp(self):
        super().setUp()
        patches = [
            mock.patch.object(area3_chat_nt, 'time', SimpleNamespace(sleep=self._sleep, monotonic=lambda: self.now)),
            mock.patch.object(notify, 'background', self._home),
            mock.patch.object(notify, 'tap_notification', lambda s, title, body=None: self.world.log.append(f'tap:{title}:{body}')),
            mock.patch.object(notify, 'kill_app', mock.Mock(side_effect=AssertionError('앱은 죽이지 않는다 — 밖(HOME)에 둘 뿐'))),
            mock.patch.object(notify, 'expect_none', self._expect_none),
            mock.patch.object(notify, 'wait_new', self._wait_new),
        ]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fresh()

    def fresh(self):
        """한 시험 안에서 판을 여러 번 돌릴 때(subTest) 세상을 처음으로 — 패치는 그대로 두고 가짜 알림창 · 시계 · 서버 상태를 비운다."""
        self.world.reset()
        self.now = 0.0
        self.slept, self.watched = [], []
        self.front = True  # 앱이 앞에 있다 — HOME 으로 내리면 False
        self.last_read = None  # 서버가 아는 폰 계정의 읽음 시각(가짜 시계)
        self.switch = {'new_message': True}
        self.sent, self.left = [], False
        self.send_cost = 0  # 보내기 한 번이 흘리는 가짜 시간(늦은 보내기를 흉내 낸다)
        self.window = True  # 서버가 읽음 시각 30초 창을 지키는가
        self.cut = 40
        self.swap_newline = True
        self.deliver = True  # 서버가 푸시를 보내는가(앞이면 배너 없음과 따로)
        self.partner_delivers = True  # 어긋난 서버 — 폰 계정의 방 상대(tok-2)의 알림만 안 간다(알림 길 자체는 살아 있다)
        self.controls = True  # 상대(대조)의 알림은 뜨는가
        self.show_in_front = False  # 어긋난 앱 — 앞에 있어도 배너를 띄운다
        self.ignore_switch = False  # 어긋난 서버 — 알림 스위치가 꺼져도 보낸다
        self.granted = True  # 기기의 알림 권한 — 꺼져 있으면 서버가 보내도 알림창에 안 뜬다
        self.sent_at = {}  # 글 → 서버가 찍은 보낸 가짜 시각
        self.world.on('POST', '/messages', self.push_rule)
        self.world.on('POST', '/leave', self._left)

    # ── 가짜 시계 · 알림창 ─────────────────────────────────────────────────────────────────────────
    def _sleep(self, seconds):
        self.slept.append(seconds)
        self.now += seconds

    def _home(self, serial):
        self.world.log.append('background')
        self.front = False

    def _front(self, serial):
        self.world.log.append('front')
        self.front = True

    def _expect_none(self, serial, before, seconds=0):
        self.watched.append(('watch', seconds))
        self.now += seconds
        return self.world.new(before)

    def _wait_new(self, serial, before, count=1, seconds=0, match=None):
        new = self.world.new(before)
        self.watched.append(('wait', seconds, match is not None))
        if not [n for n in new if match is None or match(n)]:
            self.now += seconds
        return new

    def stamp(self):
        """폰 계정이 방에 들어오거나 나와 서버가 읽음 시각을 찍었다."""
        self.last_read = self.now

    def in_window(self):
        return self.window and self.last_read is not None and self.now - self.last_read < WINDOW

    # ── 가짜 서버 ──────────────────────────────────────────────────────────────────────────────────
    def push_rule(self, body, url):
        """chat/router.py send_message · _notify_message — 상대(tok-2)의 글은 폰 계정에게, 대조(tok-3)의 글도 폰 계정에게 간다."""
        who = self.world.callers[-1][2]
        self.sent.append((who, body['body']))
        self.now += self.send_cost
        self.sent_at[body['body']] = self.now
        title = {'tok-2': PARTNER, 'tok-3': CTL}.get(who)
        if title is None or not self.deliver or (who == 'tok-3' and not self.controls) or (who == 'tok-2' and not self.partner_delivers):
            return []
        if not self.granted:
            return []  # 권한이 꺼진 기기 — FCM 이 가도 알림창에는 안 뜬다
        if (who == 'tok-2' and self.in_window()) or (not self.switch['new_message'] and not self.ignore_switch) or (self.front and not self.show_in_front):
            return []  # 방에 있다 · 스위치 꺼짐 · 앱이 앞(배너 없음)
        text = body['body'].replace('\n', ' ') if self.swap_newline else body['body']
        return [(title, text[:self.cut])]

    def _left(self, body, url):
        self.left = True
        return []

    def rules(self):
        def participants(b, u):
            at = None if self.last_read is None else self.iso(self.last_read)
            return Reply(200, [{'last_read_at': at, 'left_at': 'x' if self.left else None}])

        def messages(b, u):
            query = parse_qs(urlsplit(u).query)
            if 'kind' in query:
                return Reply(200, [{'match_id': 'm'}] if self.left else [])
            want = query.get('body', [None])[0]
            return Reply(200, [{'body': text, 'created_at': self.iso(self.sent_at[text])} for _, text in self.sent if want is None or want == f'eq.{text}'])

        return [('GET', 'match_participants', participants), ('GET', 'messages?', messages),
                ('GET', 'notification_settings', lambda b, u: Reply(200, [dict(self.switch)]))]

    @staticmethod
    def iso(seconds):
        return (datetime(2026, 10, 7, tzinfo=timezone.utc) + timedelta(seconds=seconds)).isoformat()

    def go10(self, case, phone=None, rules=()):
        return self.go_push(case, [*rules, *self.rules()], phone=phone if phone is not None else Phone10(self.world))

    def sent_by(self, who):
        return [text for sender, text in self.sent if sender == who]

    def at(self, prefix):
        return [i for i, line in enumerate(self.world.log) if line.startswith(prefix)]


# ── 알림 하나가 오는 판 — 26 · 27 · 17 · 59 ────────────────────────────────────────────────────────

class OneMessageTest(Base10):
    def test_26_the_partners_hello_arrives_once_titled_with_the_nickname_and_the_arrival_time_is_noted(self):
        result = self.go10('E-CHAT-26')
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('도착까지', result[1])
        self.assertEqual(self.sent_by('tok-2'), ['안녕하세요'])
        self.assertEqual(self.phone.jobs, [{'token_hash': 'h'}])  # 앱은 로그인해 홈에 머물 뿐 — 알림은 PC 가 읽는다

    def test_26_the_phone_goes_home_and_the_old_notifications_are_read_before_the_partner_sends(self):
        self.go10('E-CHAT-26')
        self.assertLess(self.at('background')[0], self.at('read')[0])
        self.assertLess(self.at('read')[0], self.at('POST chat/')[0])

    def test_26_a_wrong_title_or_wrong_text_or_a_second_copy_or_nothing_is_a_fail(self):
        for label, change in (('cut text', lambda: setattr(self, 'cut', 3)), ('nothing', lambda: setattr(self, 'deliver', False))):
            with self.subTest(label):
                self.fresh()
                change()
                result = self.go10('E-CHAT-26')
                self.assertEqual(result[0], 'fail', result)
        self.fresh()
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])] if self.world.callers[-1][2] == 'tok-2' else [])  # 한 번 더 뜬다
        self.assertEqual(self.go10('E-CHAT-26')[0], 'fail')

    def test_26_works_at_night_because_new_message_is_exempt_from_quiet_hours(self):
        """backend cards/push.py _QUIET_HOURS_EXEMPT 에 new_message — 밤이라고 막으면 E-CHAT-34 와 어긋난다."""
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))) as night:
            self.assertEqual(self.go10('E-CHAT-26')[0], 'pass')
        night.assert_not_called()
        push = (ROOT / 'backend' / 'app' / 'cards' / 'push.py').read_text(encoding='utf-8')
        self.assertRegex(push, r'_QUIET_HOURS_EXEMPT = \{[^}]*"new_message"')

    def test_26_the_push_connection_is_checked_before_the_app_starts_and_the_permission_is_given_then_taken_back(self):
        self.go10('E-CHAT-26')
        self.assertEqual(self.delivery, [('S', 0)])
        self.assertEqual((self.world.log[0], self.world.log[-1]), ('grant', 'revoke'))

    def test_27_a_fifty_char_text_arrives_as_exactly_its_first_forty_chars(self):
        result = self.go10('E-CHAT-27')
        self.assertEqual(result[0], 'pass', result)
        text = self.sent_by('tok-2')[0]
        self.assertEqual(len(text), 50)
        self.assertTrue(text[:12].isascii() and not text[12:].isascii())  # 앞은 번호표(영문), 뒤는 한글 — 한글은 BMP 라 코드포인트 수 = UTF-16 칸 수

    def test_27_forty_one_or_thirty_nine_or_no_cut_is_a_fail_that_names_the_length(self):
        for cut in (41, 39, 50):
            with self.subTest(cut=cut):
                self.fresh()
                self.cut = cut
                result = self.go10('E-CHAT-27')
                self.assertEqual(result[0], 'fail', result)
                self.assertIn(str(cut), result[1])

    def test_17_the_newline_becomes_a_space_in_the_notification_and_stays_two_lines_in_the_room(self):
        phone = Phone10(self.world, {'result': 'pass'}, {'result': 'pass', 'shown': True, 'lines': 2, 'bodies': ['첫줄\n둘째줄']})
        result = self.go10('E-CHAT-17', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.sent_by('tok-2'), ['첫줄\n둘째줄'])
        self.assertEqual([j.get('phase') for j in phone.jobs], [None, 'room'])
        self.assertEqual({k: phone.jobs[1][k] for k in ('nickname', 'body')}, {'nickname': PARTNER, 'body': '첫줄\n둘째줄'})
        self.assertIn('token_hash', phone.jobs[1])  # 앱을 새로 켜 다시 로그인한다 — 1회용 토큰이라 새로 받는다

    def test_17_a_notification_that_keeps_the_newline_is_a_fail(self):
        self.swap_newline = False
        phone = Phone10(self.world, {'result': 'pass'}, {'result': 'pass', 'shown': True, 'lines': 2, 'bodies': []})
        self.assertEqual(self.go10('E-CHAT-17', phone)[0], 'fail')

    def test_17_one_line_or_a_missing_bubble_in_the_room_is_a_fail(self):
        for said in ({'shown': True, 'lines': 1, 'bodies': ['첫줄\n둘째줄']}, {'shown': False, 'lines': 0, 'bodies': ['첫줄 둘째줄']}):
            with self.subTest(said=said):
                self.fresh()
                phone = Phone10(self.world, {'result': 'pass'}, {'result': 'pass', **said})
                result = self.go10('E-CHAT-17', phone)
                self.assertEqual(result[0], 'fail', result)

    def test_17_the_room_is_not_opened_when_the_notification_never_came(self):
        self.deliver = False
        phone = Phone10(self.world, {'result': 'pass'}, {'result': 'pass', 'shown': True, 'lines': 2, 'bodies': []})
        self.assertEqual(self.go10('E-CHAT-17', phone)[0], 'fail')
        self.assertEqual(len(phone.jobs), 1)

    def test_59_the_partner_leaves_and_b_gets_nothing_then_a_control_message_proves_the_path_is_alive(self):
        result = self.go10('E-CHAT-59')
        self.assertEqual(result[0], 'pass', result)
        self.assertTrue(self.left)
        self.assertEqual(self.sent_by('tok-2'), [])  # 나가기는 글을 보내지 않는다
        self.assertEqual(len(self.sent_by('tok-3')), 1)
        self.assertLess(self.at('POST chat/matches/')[0], self.at('POST chat/matches/')[-1])  # 나가기 → 대조 메시지

    def test_59_a_notification_for_the_leave_is_a_fail(self):
        self.world.on('POST', '/leave', lambda b, u: [(PARTNER, '나갔어요')])
        result = self.go10('E-CHAT-59')
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('나갔어요', result[1])

    def test_59_a_control_that_never_arrives_is_blocked_not_a_pass(self):
        self.controls = False
        self.assertEqual(self.go10('E-CHAT-59')[0], 'blocked')

    def test_59_a_leave_that_did_not_leave_a_system_line_is_a_fail(self):
        """나가기가 실제로 됐다는 증거(나감 줄 1개) 없이 "알림 0건" 만 보면 아무것도 안 한 가설이 통과한다."""
        self.world.rules[:] = [r for r in self.world.rules if r[1] != '/leave']
        self.world.on('POST', '/leave', lambda b, u: [])  # 서버가 나가기를 안 했다(self.left 가 안 켜진다)
        self.assertEqual(self.go10('E-CHAT-59')[0], 'fail')


# ── 방에 있는 동안 · 방에서 나온 직후 — 28 · 29 ────────────────────────────────────────────────────

class RoomWindowTest(Base10):
    def run28(self, acts=None):
        phone = Phone10(self.world, {'result': 'pass', 'loaded': True}, acts=[None, self.stamp] if acts is None else acts)
        return self.go10('E-CHAT-28', phone), phone

    def test_28_a_message_sent_within_seconds_of_entering_the_room_gives_no_notification_and_a_late_one_proves_the_path(self):
        result, phone = self.run28()
        self.assertEqual(result[0], 'pass', result)
        first, second = self.sent_by('tok-2')
        self.assertNotEqual(first, second)
        self.assertEqual(phone.acts, [])  # 앱 멈춤 둘(홈 · 방 안)을 다 지났다
        self.assertEqual(len(phone.jobs), 1)
        self.assertIn(('watch', notify.NOTICE_WAIT), self.watched)  # 알림이 안 오는 것을 알림 기다림 시간만큼 지켜본다
        self.assertIn('들어간 지', result[1])

    def test_28_it_waits_for_the_read_stamp_then_goes_home_then_sends_in_that_order(self):
        self.run28()
        stamp, home, send = self.at('GET match_participants')[0], self.at('background')[0], self.at('POST chat/')[0]  # 보낸 뒤에도 서버 값을 한 번 더 읽는다 — 보내기 전 첫 읽기가 기준
        self.assertLess(stamp, home)
        self.assertLess(home, send)

    def test_28_the_control_goes_after_the_server_window_so_it_is_not_itself_suppressed(self):
        self.run28()
        self.assertGreaterEqual(self.now, WINDOW)
        self.assertEqual(len(self.sent_by('tok-2')), 2)

    def test_28_a_server_that_notifies_a_partner_who_is_in_the_room_is_a_fail(self):
        self.window = False
        result, _ = self.run28()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('옴', result[1])

    def test_28_zero_notifications_with_a_dead_path_is_blocked_not_a_pass(self):
        self.deliver = False  # 첫 건도 대조도 안 뜬다 — 알림 길이 죽었을 수 있다
        result, _ = self.run28()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('대조', result[1])

    def test_28_a_send_that_comes_after_the_server_window_proves_nothing_and_is_blocked(self):
        self.send_cost = 40
        result, _ = self.run28()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('30초', result[1])

    def test_28_the_gap_is_the_two_server_clock_values_and_the_note_carries_it(self):
        self.send_cost = 12  # 읽음 시각이 찍힌 뒤 12초 만에 보낸 것으로 서버가 기록한다(서버가 안 보내는 창 30초 안)
        result, _ = self.run28()
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('12.0초', result[1])
        self.assertIn('시나리오의 10초보다 늦음', result[1])

    def test_28_a_gap_just_inside_the_margin_is_judged_and_one_past_it_is_blocked(self):
        self.send_cost = area3_chat_nt.IN_ROOM_LIMIT
        self.assertEqual(self.run28()[0][0], 'pass')
        self.fresh()
        self.send_cost = area3_chat_nt.IN_ROOM_LIMIT + 1
        result, _ = self.run28()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('30초', result[1])

    def test_28_the_margin_is_the_server_window_minus_five_seconds(self):
        self.assertEqual(area3_chat_nt.IN_ROOM_LIMIT, area3_chat_nt.SERVER_WINDOW - 5)
        self.assertEqual(area3_chat_nt.SERVER_WINDOW, WINDOW)

    def test_28_a_message_stamped_before_the_read_time_is_blocked(self):
        """읽음 시각이 보낸 시각보다 늦으면 보낼 때 서버는 아직 방에 있다고 몰랐다 — 알림이 가는 게 맞아 판정할 수 없다."""
        self.send_cost = -5
        result, _ = self.run28()
        self.assertEqual(result[0], 'blocked', result)

    def test_28_a_room_that_never_stamped_the_read_time_is_blocked_before_anything_is_sent(self):
        result, _ = self.run28(acts=[None, None])
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.sent, [])

    def run29(self, acts=None):
        phone = Phone10(self.world, {'result': 'pass', 'left': True}, acts=[None, self.stamp] if acts is None else acts)
        return self.go10('E-CHAT-29', phone), phone

    def test_29_the_first_message_ten_seconds_after_leaving_is_silent_and_the_one_at_forty_comes(self):
        result, phone = self.run29()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.sent_by('tok-2')), 2)
        self.assertEqual(self.slept, [10, 5])  # 나온 뒤 10초에 첫 건, 첫 건 뒤 25초 지켜보고 5초 더 → 나온 뒤 40초에 둘째
        self.assertEqual(sum(self.slept) + 25, 40)
        self.assertIn(('watch', 25), self.watched)
        self.assertIn(('wait', 60, True), self.watched)  # 아무 알림이 아니라 그 글(match)을 기다린다
        self.assertLess(self.at('background')[0], self.at('POST chat/')[0])

    def test_29_a_server_that_notifies_inside_the_window_is_a_fail_naming_the_first_message(self):
        self.window = False
        result, _ = self.run29()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('첫', result[1])

    def test_29_no_notification_for_the_second_message_while_the_path_is_alive_is_a_fail(self):
        self.partner_delivers = False  # 방 상대의 알림만 안 가고, 새 상대의 대조는 간다 — 서버 규칙이 틀린 것
        result, _ = self.run29()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('40초', result[1])
        self.assertEqual(len(self.sent_by('tok-3')), 1)  # 길 확인용 새 상대의 메시지

    def test_29_no_notification_and_a_dead_path_is_blocked_not_a_fail(self):
        self.deliver = False  # 대조도 안 온다 — FCM 길이 죽은 폰에서 서버 규칙을 탓하면 허위 fail
        result, _ = self.run29()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('알림 길', result[1])

    def test_29_the_path_check_goes_through_a_new_partner_in_a_new_room(self):
        self.partner_delivers = False
        self.run29()
        rooms = [line.split('/')[2] for line in self.world.log if line.startswith('POST chat/matches/') and line.endswith('/messages')]
        self.assertEqual(len(rooms), 3)  # 첫 건 · 둘째 · 길 확인
        self.assertEqual(rooms[0], rooms[1])
        self.assertNotEqual(rooms[2], rooms[0])
        self.assertEqual(self.sent_by('tok-3'), [self.sent[-1][1]])

    def test_29_the_path_is_not_checked_when_the_second_notification_came(self):
        self.run29()
        self.assertEqual(self.sent_by('tok-3'), [])

    def test_29_a_notification_for_the_first_message_that_shows_up_late_is_a_fail(self):
        def late_first(body, url):
            return [(PARTNER, self.sent_by('tok-2')[0])] if len(self.sent_by('tok-2')) == 2 else []
        self.world.on('POST', '/messages', late_first)
        result, _ = self.run29()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('첫', result[1])

    def test_29_two_notifications_for_the_second_message_is_a_fail(self):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])] if len(self.sent_by('tok-2')) == 2 else [])
        self.assertEqual(self.run29()[0][0], 'fail')

    def test_29_a_room_that_never_stamped_the_read_time_is_blocked(self):
        result, _ = self.run29(acts=[None, None])
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.sent, [])


# ── 목록 앞에서 · 알림을 눌러 방 열기 — 30 · 31 ─────────────────────────────────────────────────────

LIST_SAID = {'result': 'pass', 'list_front': True, 'resumed': True, 'badge_before': None, 'badge': '1', 'last_before': '아직 메시지가 없어요', 'nav_badge': '1', 'ms': 900}


def list_says(**changes):
    return lambda job: {**LIST_SAID, 'last': job['body'], **changes}


class ListAndTapTest(Base10):
    def run30(self, said=None, acts=(None, None, None)):
        phone = Phone10(self.world, list_says() if said is None else said, acts=acts)
        return self.go10('E-CHAT-30', phone), phone

    def test_30_the_partner_sends_while_the_app_stays_on_the_list_and_no_system_notification_pops_up(self):
        result, phone = self.run30()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.acts, [])
        self.assertEqual(sorted(phone.jobs[0]), ['body', 'nickname', 'token_hash'])
        self.assertEqual(self.sent_by('tok-2'), [phone.jobs[0]['body']])
        self.assertEqual(self.world.log[self.at('POST chat/')[0] - 1], 'read')  # 앞에 있던 알림을 읽어 둔 바로 뒤에 보낸다
        self.assertLess(self.at('POST chat/')[0], self.at('background')[0])  # 앱이 앞에 있는 동안 보낸다 — HOME 은 지켜본 뒤 대조 때 한다
        self.assertIn(('watch', notify.NOTICE_WAIT), self.watched)
        self.assertIn('ms', result[1])

    def test_30_a_notification_that_pops_up_in_front_is_a_fail_and_needs_no_control(self):
        self.show_in_front = True
        result, _ = self.run30()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('안 와야 할', result[1])
        self.assertEqual(self.sent_by('tok-3'), [])

    def test_30_zero_notifications_with_a_dead_path_is_blocked_not_a_pass(self):
        self.controls = False
        self.assertEqual(self.run30()[0][0], 'blocked')

    def test_30_a_list_that_did_not_update_by_itself_is_a_fail(self):
        for label, said in (('last line', list_says(last='아직 메시지가 없어요')), ('no badge', list_says(badge=None)),
                            ('badge stayed', list_says(badge_before='1', badge='1')), ('left the list', list_says(list_front=False)),
                            ('app was not in the foreground', list_says(resumed=False))):
            with self.subTest(label):
                self.fresh()
                result, _ = self.run30(said)
                self.assertEqual(result[0], 'fail', result)

    def test_30_a_badge_that_goes_from_one_to_two_is_plus_one(self):
        result, _ = self.run30(list_says(badge_before='1', badge='2'))
        self.assertEqual(result[0], 'pass', result)

    def test_30_a_badge_that_jumps_by_two_is_a_fail(self):
        result, _ = self.run30(list_says(badge_before=None, badge='2'))
        self.assertEqual(result[0], 'fail', result)

    def run31(self, said=None):
        opened = {'result': 'pass', 'room': True, 'nickname': True, 'message': True, 'screen': ['home'], 'room_ms': 900, 'opened_at': 'T'}
        phone = Phone10(self.world, opened if said is None else said, acts=[None])
        return self.go10('E-CHAT-31', phone), phone

    def test_31_the_notification_is_tapped_while_the_app_is_outside_and_the_room_opens(self):
        result, phone = self.run31()
        self.assertEqual(result[0], 'pass', result)
        body = self.sent_by('tok-2')[0]
        self.assertIn(f'tap:{PARTNER}:{body}', self.world.log)  # 제목 + 본문으로 그 줄만 누른다(옛 알림을 피함)
        self.assertEqual({k: phone.jobs[0][k] for k in ('nickname', 'body', 'phase')}, {'nickname': PARTNER, 'body': body, 'phase': 'hold'})
        self.assertLess(self.at('background')[0], self.at('POST chat/')[0])
        self.assertLess(self.at('POST chat/')[0], self.at('tap:')[0])
        self.assertIn('도착까지', result[1])

    def test_31_a_room_that_did_not_open_or_a_missing_nickname_or_message_is_a_fail_that_names_the_screens(self):
        for key in ('room', 'nickname', 'message'):
            with self.subTest(key):
                self.fresh()
                opened = {'result': 'pass', 'room': True, 'nickname': True, 'message': True, 'screen': ['consent'], 'room_ms': 900, 'opened_at': 'T'}
                result, _ = self.run31({**opened, key: False})
                self.assertEqual(result[0], 'fail', result)
                self.assertIn('약관 동의', result[1])

    def test_31_no_notification_means_nothing_is_tapped_and_the_result_is_a_fail(self):
        self.deliver = False
        result, _ = self.run31()
        self.assertEqual(result[0], 'fail', result)
        self.assertEqual(self.at('tap:'), [])

    def test_31_the_app_is_only_sent_home_never_killed(self):
        """kill_app 이 불리면 가짜가 AssertionError 를 내 가설이 죽는다 — 통과면 안 불렸다(꺼진 앱은 E-CHAT-32 의 몫)."""
        self.assertEqual(self.run31()[0][0], 'pass')
        self.assertEqual(len(self.at('background')), 1)


# ── 알림 설정 · 알림 권한 — 33 · 35 ────────────────────────────────────────────────────────────────

class OutOfRoomBase(Base10):
    """앱을 다시 앞으로 가져오는 길(`_front`)까지 가짜로 단 바탕 — 33 · 35 는 HOME 으로 내렸다 다시 앞으로 온다."""

    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(area3_chat_nt, '_front', self._front)
        patcher.start()
        self.addCleanup(patcher.stop)


class SwitchTest(OutOfRoomBase):
    def off(self):
        self.switch['new_message'] = False

    def on(self):
        self.switch['new_message'] = True

    def run33(self, acts=None):
        phone = Phone10(self.world, {'result': 'pass'}, acts=[None, self.off, self.on] if acts is None else acts)
        return self.go10('E-CHAT-33', phone), phone

    def test_33_no_notification_while_the_app_has_it_off_and_one_after_it_is_on_again(self):
        result, phone = self.run33()
        self.assertEqual(result[0], 'pass', result)
        off, on = self.sent_by('tok-2')
        self.assertNotEqual(off, on)
        self.assertEqual(phone.acts, [])
        self.assertEqual(sorted(phone.jobs[0]), ['nickname', 'token_hash'])
        self.assertIn(('watch', notify.NOTICE_WAIT), self.watched)
        self.assertIn(('wait', notify.NOTICE_WAIT, True), self.watched)  # 켠 뒤에는 그 글(match)을 기다린다

    def test_33_each_message_goes_after_the_phone_is_sent_home_and_the_app_comes_back_between(self):
        self.run33()
        posts, homes, fronts = self.at('POST chat/'), self.at('background'), self.at('front')
        self.assertEqual(len(posts), 2)
        self.assertLess(homes[0], posts[0])
        self.assertLess(posts[0], fronts[0])
        self.assertLess(fronts[0], homes[1])
        self.assertLess(homes[1], posts[1])

    def test_33_the_server_value_is_read_after_each_tap(self):
        self.run33()
        reads = [i for i, line in enumerate(self.world.log) if line.startswith('GET notification_settings')]
        self.assertGreaterEqual(len(reads), 2)

    def test_33_a_server_that_still_sends_while_it_is_off_is_a_fail(self):
        self.ignore_switch = True
        result, _ = self.run33()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('끈 동안', result[1])

    def test_33_an_app_that_did_not_turn_it_off_is_a_fail_on_the_server_value(self):
        result, _ = self.run33(acts=[None, None, self.on])
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('new_message', result[1])

    def test_33_no_notification_after_turning_it_on_again_is_a_fail(self):
        result, _ = self.run33(acts=[None, self.off, None])  # 다시 켰다고 하지만 서버 값은 꺼진 채
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('다시 켠 뒤', result[1])

    def test_33_no_notification_after_a_real_turn_on_with_a_live_path_is_a_fail_via_a_new_room(self):
        self.partner_delivers = False  # 서버 값은 켜졌는데 방 상대의 알림만 안 온다 — 새 상대의 대조는 온다
        result, _ = self.run33()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('다시 켠 뒤', result[1])
        self.assertEqual(len(self.sent_by('tok-3')), 1)
        rooms = [line.split('/')[2] for line in self.world.log if line.startswith('POST chat/matches/') and line.endswith('/messages')]
        self.assertNotEqual(rooms[-1], rooms[0])

    def test_33_no_notification_after_a_real_turn_on_and_a_dead_path_is_blocked(self):
        self.deliver = False  # 대조도 안 온다 — 길이 죽은 폰에서 서버 규칙을 탓하면 허위 fail
        result, _ = self.run33()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('알림 길', result[1])

    def test_33_the_path_is_not_checked_when_the_server_value_never_turned_on(self):
        """스위치가 서버에서 꺼진 채면 대조 메시지도 막힌다 — 그걸 길이 죽은 것으로 읽으면 안 되니 대조를 안 보내고 서버 값 어긋남으로 fail 한다."""
        self.run33(acts=[None, self.off, None])
        self.assertEqual(self.sent_by('tok-3'), [])

    def test_33_the_phone_is_given_two_seconds_to_come_back_to_the_front_before_the_app_goes_on(self):
        self.run33()
        self.assertEqual(self.slept, [2])

    def test_33_two_notifications_after_turning_it_on_is_a_fail(self):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])] if self.switch['new_message'] and not self.front else [])
        result, _ = self.run33()
        self.assertEqual(result[0], 'fail', result)

    def test_33_it_runs_at_night_too(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))) as night:
            self.assertEqual(self.run33()[0][0], 'pass')
        night.assert_not_called()


def live_says(test, seconds, **changes):
    """35 앱의 끝말 — 방 안에서 그 글을 [seconds] 초 뒤에 봤다(서버가 찍은 보낸 시각 기준)."""
    return lambda job: {'result': 'pass', 'loaded': True, 'bubble': True, 'seen_at': test.iso(test.sent_at[job['body']] + seconds), **changes}


class PermissionTest(OutOfRoomBase):
    """35 — 알림 권한이 꺼진 기기. `_permitted` 래퍼를 쓰지 않는다(권한을 주지 않는다) — 끝에 꺼 둔 채로 돌려놓는다."""

    def setUp(self):
        super().setUp()
        self.reset35()
        self.dialog = True  # 로그인 뒤 권한 창이 뜬다
        patches = [
            mock.patch.object(notify, 'grant_notifications', self._grant),
            mock.patch.object(notify, 'revoke_notifications', self._revoke),
            mock.patch.object(area3_chat_nt, '_granted', lambda s: self.permission),
            mock.patch.object(area3_chat_nt, '_tap_node', self._tap),
        ]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, [{'token': 't'}] if self.token_row else []))

    def reset35(self):
        self.granted = self.permission = False  # 시작할 때 이미 꺼져 있는 기기 — `permission` 은 `_granted` 가 읽는 값(None 이면 못 읽음)
        self.token_row = False

    def _grant(self, serial):
        self.world.log.append('grant')
        self.granted = self.permission = True

    def _revoke(self, serial):
        self.world.log.append('revoke')
        self.granted = self.permission = False

    def _tap(self, serial, matches):
        self.world.log.append('deny' if self.dialog else 'no-dialog')
        return self.dialog

    def run35(self, said=None):
        def on_call(job):
            if job.get('phase') == 'again':
                self.token_row = True  # 권한을 켜고 다시 로그인하면 기기 토큰이 올라온다
        phone = Phone10(self.world, live_says(self, 1.2) if said is None else said, {'result': 'pass'}, acts=[None, None], on_call=on_call)
        return self.go10('E-CHAT-35', phone), phone

    def test_35_with_the_permission_off_nothing_pops_up_and_the_room_still_shows_the_message_live(self):
        result, phone = self.run35()
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('지연 1.20초', result[1])
        first, live = self.sent_by('tok-2')
        control = self.sent_by('tok-3')  # 대조는 새 상대의 새 방 — 폰 계정이 방금 입장한 방의 읽음 시각 창(30초)에 안 걸린다
        self.assertEqual(len({first, live, *control}), 3)
        rooms = [line.split('/')[2] for line in self.world.log if line.startswith('POST chat/matches/') and line.endswith('/messages')]
        self.assertEqual(len(rooms), 3)
        self.assertEqual(rooms[0], rooms[1])
        self.assertNotEqual(rooms[2], rooms[0])
        self.assertEqual(phone.jobs[0]['body'], live)
        self.assertIn(('watch', notify.NOTICE_WAIT), self.watched)

    def test_35_the_permission_is_never_given_before_the_first_login_and_is_taken_back_at_the_end(self):
        self.run35()
        log = self.world.log
        first_login = log.index('app:-')
        self.assertIn('revoke', log[:first_login])  # 앱을 켜기 전에 확실히 꺼 둔다
        self.assertNotIn('grant', log[:first_login])  # `_permitted` 래퍼(먼저 grant)를 안 쓴다
        self.assertLess(first_login, log.index('grant'))
        self.assertEqual(log.count('grant'), 1)  # 대조 때 한 번뿐
        self.assertEqual(log[-1], 'revoke')

    def test_35_the_dialog_is_denied_and_the_phone_goes_home_before_the_first_send(self):
        self.run35()
        log = self.world.log
        self.assertLess(log.index('deny'), log.index('background'))
        self.assertLess(log.index('background'), self.at('POST chat/')[0])
        self.assertLess(self.at('POST chat/')[0], log.index('front'))
        self.assertLess(log.index('front'), self.at('POST chat/')[1])  # 앱이 앞으로 온 뒤 방 안에서 보낸다

    def test_35_a_phone_that_shows_no_dialog_is_fine_and_the_note_says_so(self):
        self.dialog = False
        result, _ = self.run35()
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('권한 창', result[1])

    def test_35_a_registered_token_with_the_permission_off_is_only_a_note(self):
        self.token_row = True
        result, _ = self.run35()
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('push_tokens', result[1])

    def test_35_a_notification_that_pops_up_with_the_permission_off_is_a_fail(self):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])] if self.world.callers[-1][2] == 'tok-2' and not self.front and not self.sent_by('tok-3') else [])
        result, _ = self.run35()
        self.assertEqual(result[0], 'fail', result)
        self.assertIn('권한', result[1])

    def test_35_the_live_display_must_be_within_two_seconds_and_the_bubble_must_exist(self):
        for label, said in (('slow', live_says(self, 3.0)), ('no bubble', live_says(self, 1.0, bubble=False))):
            with self.subTest(label):
                self.fresh()
                self.reset35()
                result, _ = self.run35(said)
                self.assertEqual(result[0], 'fail', result)

    def test_35_a_clock_that_runs_behind_the_server_is_not_judged_and_the_note_says_so(self):
        result, _ = self.run35(live_says(self, -0.4))
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('시계', result[1])

    def test_35_a_control_that_never_arrives_is_blocked_and_the_permission_is_still_taken_back(self):
        self.deliver = False
        result, _ = self.run35()
        self.assertEqual(result[0], 'blocked', result)
        self.assertIn('대조', result[1])
        self.assertEqual(self.world.log[-1], 'revoke')

    def test_35_a_phone_whose_permission_cannot_be_turned_off_is_blocked_before_the_app_starts(self):
        self.permission = True
        with mock.patch.object(notify, 'revoke_notifications', lambda s: self.world.log.append('revoke')):
            result, phone = self.run35()
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(phone.jobs, [])

    def test_35_a_phone_whose_permission_state_cannot_be_read_is_blocked(self):
        self.permission = None
        with mock.patch.object(notify, 'revoke_notifications', lambda s: self.world.log.append('revoke')):
            self.assertEqual(self.run35()[0][0], 'blocked')


# ── 등록 · 시간 상한 · 앱 쪽과 맞는지 ──────────────────────────────────────────────────────────────

DART = ROOT / 'frontend' / 'integration_test' / 'area3_chat_nt.dart'
LIMITS = {'E-CHAT-17': 540, 'E-CHAT-28': 480, 'E-CHAT-29': 540, 'E-CHAT-30': 480, 'E-CHAT-31': 540, 'E-CHAT-33': 600, 'E-CHAT-35': 600}


class WiringTest(unittest.TestCase):
    def test_the_bundle_is_exactly_the_ten_cases_and_each_is_a_phone_case(self):
        self.assertEqual(area3.BUNDLES['area3-chat-nt'], BUNDLE)
        for case in BUNDLE:
            self.assertIs(area1.PHONE[case], area3_chat_nt.PHONE_NT[case])

    def test_no_other_bundle_or_api_list_has_these_numbers(self):
        for name, cases in {**area1.BUNDLES, **area3.BUNDLES}.items():
            if name != 'area3-chat-nt':
                self.assertEqual(set(cases) & set(BUNDLE), set(), name)
        self.assertEqual(set(area3.CASES) & set(BUNDLE), set())

    def test_every_case_but_35_runs_inside_the_permission_wrapper_and_35_does_not(self):
        for case in BUNDLE:
            wrapped = hasattr(area1.PHONE[case], '__wrapped__')
            self.assertEqual(wrapped, case != 'E-CHAT-35', case)

    def test_the_slow_cases_get_the_worked_out_limit_and_the_fast_ones_keep_the_default(self):
        for case in BUNDLE:
            self.assertEqual(tools.CASE_LIMITS.get(case), LIMITS.get(case), case)
        for case, limit in LIMITS.items():
            self.assertGreater(limit, tools.CASE_LIMIT)
        for case in ('E-CHAT-26', 'E-CHAT-27', 'E-CHAT-59'):
            self.assertLessEqual(area3_chat_nt.WORST[case] + area3_chat_nt.MARGIN, tools.CASE_LIMIT, case)

    def test_every_limit_covers_the_waits_of_its_own_case_plus_the_margin(self):
        for case, worst in area3_chat_nt.WORST.items():
            self.assertGreaterEqual(tools.CASE_LIMITS.get(case, tools.CASE_LIMIT), worst + area3_chat_nt.MARGIN, case)
        self.assertEqual(sorted(area3_chat_nt.WORST), sorted(BUNDLE))

    def test_the_progress_program_imports_the_module_right_after_phone8(self):
        main = (ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8')
        self.assertIn('from e2e import area3_chat_nt  # noqa: F401', main)
        self.assertLess(main.index('from e2e import area3_phone8 '), main.index('from e2e import area3_chat_nt '))

    def test_the_docstring_tells_every_case_how_it_differs_from_the_scenario(self):
        doc = area3_chat_nt.__doc__
        self.assertIn('시나리오와 다르게 도는 것', doc)
        for case in BUNDLE:
            self.assertIn(case.replace('E-CHAT-', ''), doc, case)
        self.assertIn('_QUIET_HOURS_EXEMPT', doc)  # new_message 는 조용한 시간 예외 — 낮 제한을 안 건 이유


class AppSideTest(unittest.TestCase):
    def setUp(self):
        self.dart = DART.read_text(encoding='utf-8')

    def test_the_app_knows_the_same_ten_numbers(self):
        keys = re.findall(r"^\s*'(E-CHAT-\d+)'", self.dart, re.M)
        self.assertEqual(sorted(keys), sorted(BUNDLE))

    def test_it_is_a_part_of_area3_and_registered_there(self):
        self.assertTrue(self.dart.startswith("part of 'area3.dart';"))
        area3_dart = (DART.parent / 'area3.dart').read_text(encoding='utf-8')
        self.assertIn("part 'area3_chat_nt.dart';", area3_dart)
        self.assertIn('...area3CasesChatNt,', area3_dart)
        self.assertLess(area3_dart.index('...area3Cases8,'), area3_dart.index('...area3CasesChatNt,'))
        self.assertIn("import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';", area3_dart)

    def test_every_top_level_name_starts_with_nt_so_the_other_parts_cannot_collide(self):
        names = []
        for line in self.dart.splitlines():
            if not line or line[0] in ' \t}/)' or line.startswith(('part', 'import')):
                continue
            head = re.split(r'\(| = ', line)[0]
            names.append(head.split()[-1])
        self.assertTrue(names)
        for name in names:
            self.assertTrue(name.startswith('_nt') or name == 'area3CasesChatNt', name)

    def test_the_app_reads_only_job_keys_the_pc_sends(self):
        read = set(re.findall(r"job\['(\w+)'\]", self.dart))
        self.assertLessEqual(read, {'nickname', 'body', 'phase', 'token_hash', 'case'})
        self.assertTrue({'nickname', 'body', 'phase'} <= read)

    def test_30_measures_that_it_stayed_in_front_before_the_judged_step_where_the_pc_sends_it_home(self):
        self.assertLess(self.dart.index("'list_front'"), self.dart.index("step('judged'"))
        self.assertLess(self.dart.index("'resumed'"), self.dart.index("step('judged'"))
        self.assertNotIn("'front'", self.dart)

    def test_the_steps_the_pc_waits_for_are_the_ones_the_app_says(self):
        steps = set(re.findall(r"step\('(\w+)'", self.dart))
        self.assertEqual(steps, {'home', 'in_room', 'left', 'ready', 'judged', 'holding', 'off', 'on', 'signed_in'})


if __name__ == '__main__':
    unittest.main()
