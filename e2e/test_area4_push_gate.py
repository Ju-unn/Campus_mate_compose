"""영역 4 PUSH 채팅 게이트 배치 11개(area4_push_gate.py)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 알림창 · 가짜 시계로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_gate`.

가짜 서버 [GateWorld] 는 영역 2 기기 시험의 World(표 저장소 + 열 검사 + 알림 스위치)에 matches · match_participants 표(운영 열 이름)와
**chat-gate 배치 흉내**를 더했다 — backend/app/chat/batch_router.py run_chat_gate 와 같은 순서(통과 도장 → 기한 닫기 → 리마인드 창)로
가짜 시계의 now 를 보고 폰 계정(id-1)에게 리마인드를 띄운다. 매시 정각 예약 실행도 가짜 시계가 정각을 지날 때 저절로 돈다.
배치는 진짜 `area2._batch`(→ batch_gate 관문) 위에서 부르고, gcloud 자리(`tools.batch`)만 가짜다.
"""

import itertools
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area4_push_gate as gate, batch_gate, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area2 import Base
from e2e.test_area2_time_device import RESERVED, SETTINGS, AppPhone, World as DeviceWorld, select_names
from e2e.test_area3 import Fake
from e2e.tools import Blocked, Reply

ME, PARTNER, CTL = 'Mina', 'Jiho', 'Ctlx'  # 계정을 만드는 차례 — 폰 계정 · 상대 · 대조 상대
PHONE_ID, PARTNER_ID = 'id-1', 'id-2'
TITLE, BODY = '신뢰 확인이 기다리고 있어요', '카카오톡 아이디를 공유할지 정해 주세요'
CASES = [f'E-PUSH-{n}' for n in (40, 41, 42, 43, 44, 45, 46, 47, 48, 79, 80)]
GATE_COLUMNS = {
    'matches': {'id', 'profile_a', 'profile_b', 'created_at', 'trust_passed_at', 'chat_closed_at'},  # 20260920160544
    'match_participants': {'match_id', 'profile_id', 'trust_response', 'responded_at', 'left_at', 'last_read_at'},  # 20260920160544
}


def seoul(day, hour, minute=0, second=0):
    return datetime(2026, 10, day, hour, minute, second, tzinfo=SEOUL)


# 2026-10-06 은 화요일
TUE = lambda h, m=0, s=0: seoul(6, h, m, s)  # noqa: E731
WED = lambda h, m=0, s=0: seoul(7, h, m, s)  # noqa: E731


def reminder_at(created):
    """backend/app/chat/gate.py reminder_at 과 같다 — 24시간 뒤, 그 시각이 22~8시면 다음 아침 8시."""
    base = (created + timedelta(hours=24)).astimezone(SEOUL)
    if base.hour >= 22:
        return (base + timedelta(days=1)).replace(hour=8, minute=0, second=0, microsecond=0)
    if base.hour < 8:
        return base.replace(hour=8, minute=0, second=0, microsecond=0)
    return base


class Clock:
    """가짜 시계 — [advance] 로만 간다. 정각을 지날 때마다 [on_hour] 를 부른다(Cloud Scheduler 의 매시 예약 실행)."""

    def __init__(self, now):
        self.now, self.start, self.on_hour = now, now, []

    def advance(self, seconds):
        end = self.now + timedelta(seconds=seconds)
        tick = self.now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        while tick <= end:
            self.now = tick
            for callback in self.on_hour:
                callback(tick)
            tick += timedelta(hours=1)
        self.now = max(end, self.now)  # 콜백이 시계를 앞으로 보냈을 수 있다

    def mono(self):
        return (self.now - self.start).total_seconds()


class GateWorld(DeviceWorld):
    """영역 2 기기 시험의 World + matches · match_participants + chat-gate 배치 흉내. [bug] 에 이름을 넣으면 그 모양으로 어긋난 서버가 된다:
    remind_all(수락한 사람에게도 · 창 밖에도) · ignore_switch · ignore_left · no_close · close_notice · close_other(닫으며 알림) · double_scheduled."""

    def __init__(self, clock):
        super().__init__()
        self.clock = clock
        self.bug, self.scheduler, self.gate_on, self.hide, self.duplicate = set(), True, True, False, False
        self.gate_runs = []  # (시각, 'hand' | 'scheduled')
        self.on('POST', r'/chat/matches/[^/]+/messages', self.message)
        clock.on_hour.append(lambda at: self.run_gate(at, 'scheduled') if self.scheduler else None)

    # 표 — 운영 열 이름만 받는다(없는 열은 400)
    def _table(self, method, name, sent):
        if name not in GATE_COLUMNS:
            return super()._table(method, name, sent)
        query, body = sent['query'], sent['body']
        used = {column for column, _ in select_names(query.get('select', '')) if column != '*'}
        used |= {key for key in query if key not in RESERVED}
        if method in ('POST', 'PATCH'):
            used |= {key for row in (body if isinstance(body, list) else [body]) for key in row}
        wrong = sorted(used - GATE_COLUMNS[name])
        if wrong:
            self.rejected.append((name, wrong[0]))
            return Reply(400, {'code': '42703', 'message': f'column {name}.{wrong[0]} does not exist'})
        if method == 'POST' and name == 'matches':  # 운영은 created_at 이 기본값 now()
            for row in body if isinstance(body, list) else [body]:
                row.setdefault('created_at', self.clock.now.astimezone(timezone.utc).isoformat())
        return Fake._table(self, method, name, sent)

    def phone_id(self):
        """폰에 마지막으로 로그인한 계정 — 기기 토큰이 그 사람 것이다."""
        rows = self.tables.get('push_tokens', [])
        return rows[-1]['profile_id'] if rows else PHONE_ID

    def nickname_of(self, token):
        return next(s['body']['nickname'] for s in reversed(self.sent)
                    if s['auth'] == token and isinstance(s['body'], dict) and 'nickname' in s['body'])

    def message(self, sent):
        match = next(m for m in self.tables['matches'] if m['id'] == sent['path'].split('/')[3])
        sender = self.owner_of(sent)
        receiver = match['profile_b'] if match['profile_a'] == sender else match['profile_a']
        if receiver == self.phone_id() and self.permitted():
            self.post(self.nickname_of(sent['auth']), sent['body']['body'])
        return Reply(201, {'message': {}})

    def run_gate(self, at, how):
        """chat-gate 한 번 — 통과 도장 → 기한 닫기 → 리마인드 창(backend/app/chat/batch_router.py)."""
        self.gate_runs.append((at, how))
        if not self.gate_on:
            return
        people = {}
        for person in self.tables.get('match_participants', []):
            people.setdefault(person['match_id'], []).append(person)
        for match in self.tables.get('matches', []):
            if match.get('trust_passed_at') or match.get('chat_closed_at'):
                continue
            both = people.get(match['id'], [])
            if 'ignore_left' not in self.bug and any(p.get('left_at') for p in both):
                continue
            if len(both) == 2 and all(p.get('trust_response') == 'accept' for p in both):
                match['trust_passed_at'] = at.isoformat()
                continue
            created = datetime.fromisoformat(match['created_at'])
            if created + timedelta(hours=48) <= at:
                if 'no_close' not in self.bug:
                    match['chat_closed_at'] = at.isoformat()
                    if 'close_notice' in self.bug:
                        self.post(TITLE, BODY)
                    if 'close_other' in self.bug:
                        self.post('방이 닫혔어요', '48시간이 지났어요')
                continue
            start = reminder_at(created)
            for person in both:
                if 'remind_all' not in self.bug and (person.get('trust_response') or not start <= at < start + timedelta(hours=1)):
                    continue
                switched_off = not {**SETTINGS, **self.settings.get(person['profile_id'], {})}['trust_reminder']
                if switched_off and 'ignore_switch' not in self.bug:
                    continue
                if person['profile_id'] == self.phone_id() and self.permitted() and not self.hide:
                    for _ in range(2 if self.duplicate or ('double_scheduled' in self.bug and how == 'scheduled') else 1):
                        self.post(TITLE, BODY)


class GatePhone(AppPhone):
    """AppPhone + 일감 우편함(hub) + 중간 멈춤(midway)이 돌려준 값을 적어 둔다."""

    def __init__(self, world, *answers, log=None, **kw):
        super().__init__(world, *answers, **kw)
        self.case = 'E-PUSH-X'
        self.extras, self.told = [], []
        self.hub = mock.Mock()
        self.hub.tell.side_effect = lambda job: (self.told.append(job), log.append('tell') if log is not None else None)
        self.hub.result.return_value = {'result': 'pass', 'room': True, 'nickname': True, 'room_ms': 3200, 'screen': []}

    def __call__(self, midway=None, **job):
        if midway:
            return super().__call__(lambda said: self.extras.append(midway(said)), **job)
        return super().__call__(**job)


class GateBase(Base):
    START = TUE(12, 20)

    def setUp(self):
        super().setUp()
        self.clock = Clock(self.START)
        self.world = GateWorld(self.clock)
        self.log, self.batches, self.windows, self.granted, self.on_background = [], [], [], True, None
        self.world.permitted = lambda: self.granted
        self.names = itertools.chain([ME, PARTNER, CTL], (f'Ex{i}' for i in itertools.count()))
        self.daytime = mock.Mock()
        for patcher in (
            mock.patch.object(tools, 'call', self.world), mock.patch.object(tools, 'batch', self.gcloud),
            mock.patch.object(batch_gate, 'now_seoul', lambda: self.clock.now),
            mock.patch.object(batch_gate, 'HISTORY', Path(self.root) / 'runs.jsonl'),
            mock.patch.object(area1, '_nickname', lambda: next(self.names)),
            mock.patch.object(notify, 'require_daytime', self.daytime),
            mock.patch.object(notify, 'grant_notifications', lambda s: self.log.append('grant')),
            mock.patch.object(notify, 'revoke_notifications', lambda s: self.log.append('revoke')),
            mock.patch.object(notify, 'read_notifications', lambda s: list(self.world.shade)),
            mock.patch.object(notify, 'background', self.background),
            mock.patch.object(notify, 'kill_app', lambda s: self.log.append('kill')),
            mock.patch.object(notify, 'tap_notification', self.tap),
            mock.patch.object(notify, 'wait_new', lambda s, before, count=1, seconds=0, match=None: self.fresh(before)),
            mock.patch.object(notify, 'expect_none', self.expect_none),
            mock.patch.object(tools, 'adb', self.adb), mock.patch.object(tools.Run, 'shot', lambda run, serial, case: None),
            mock.patch('time.sleep', lambda s: self.clock.advance(s)), mock.patch('time.monotonic', self.clock.mono),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    # 가짜 기기 · 배치
    def gcloud(self, name):
        self.world.sent.append({'method': 'BATCH', 'path': name, 'query': {}, 'body': None, 'auth': '', 'apikey': None})
        self.batches.append((name, self.clock.now))
        self.log.append('batch')
        self.world.run_gate(self.clock.now, 'hand')

    def background(self, serial):
        self.log.append('background')
        if self.on_background:
            self.on_background()

    def tap(self, serial, title):
        self.log.append(f'tap:{title}')
        if not any(n.title == title for n in self.world.shade):
            raise Blocked(f'알림창에서 "{title}" 줄을 못 찾음')

    def adb(self, serial, *args, check=True):
        if 'monkey' in args:
            self.log.append('front')
        return ''

    def fresh(self, before):
        seen = {n.key for n in before}
        return [n for n in self.world.shade if n.key not in seen]

    def expect_none(self, serial, before, seconds=0):
        self.windows.append(('none', seconds))
        self.clock.advance(seconds)
        return self.fresh(before)

    # 가설 돌리기
    def phone(self, *answers, **kw):
        return GatePhone(self.world, *answers, log=self.log, **kw)

    def go(self, case, phone=None):
        self.app = phone or self.phone()
        self.app.serial, self.app.case = 'S', case
        result = area1.attempt_phone(self.run, case, self.app)
        self.assertEqual(self.world.rejected, [], '가설이 없는 열 · 표를 물었다(운영이면 400 · 404)')
        return result

    # 보는 도구
    def reminders(self):
        return [n for n in self.world.shade if n.title == TITLE]

    def matches(self):
        return self.world.tables.get('matches', [])

    def mine(self):
        """폰 계정 · 상대 사이 매칭."""
        return next(m for m in self.matches() if {m['profile_a'], m['profile_b']} == {PHONE_ID, PARTNER_ID})

    def anchor(self):
        """폰 계정이 없는 매칭 = 배치가 돌았는지 보는 앵커."""
        return next(m for m in self.matches() if PHONE_ID not in (m['profile_a'], m['profile_b']))

    def person(self, who, match=None):
        match = match or self.mine()
        return next(p for p in self.world.tables['match_participants'] if p['match_id'] == match['id'] and p['profile_id'] == who)

    def at(self, method, piece, key=None):
        """world.sent 안에서 처음 맞는 요청의 자리 — 순서 비교용."""
        return next(i for i, s in enumerate(self.world.sent)
                    if s['method'] == method and piece in s['path'] and (key is None or (isinstance(s['body'], dict) and key in s['body'])))

    def batch_at(self):
        return self.at('BATCH', 'chat-gate')

    def control_arrived(self):
        return any(n.title == CTL for n in self.world.shade)

    def created_patches(self):
        return [s for s in self.world.sent
                if s['method'] == 'PATCH' and s['path'].endswith('/matches') and isinstance(s['body'], dict) and 'created_at' in s['body']]


# ── 시각 창(순수 함수) ──────────────────────────────────────────────────────────────────────────────

class WindowTest(unittest.TestCase):
    def test_a_start_is_open_from_minute_6_to_minute_48_of_every_hour_from_8_to_21(self):
        for hour, minute in ((8, 6), (8, 48), (9, 6), (12, 30), (20, 48), (21, 6), (21, 48)):
            self.assertIsNone(gate.gate_window_refusal(TUE(hour, minute)), (hour, minute))
            self.assertIsNone(gate.gate_window_refusal(TUE(hour, minute, 59)), (hour, minute))

    def test_the_minutes_just_outside_are_shut_in_every_hour(self):
        for hour in (8, 12, 21):
            for minute in (0, 5, 49, 59):
                self.assertIsNotNone(gate.gate_window_refusal(TUE(hour, minute)), (hour, minute))
        for hour, minute in ((7, 30), (7, 59), (22, 6), (23, 30), (0, 30)):
            self.assertIsNotNone(gate.gate_window_refusal(TUE(hour, minute)), (hour, minute))

    def test_the_refusal_names_the_next_open_minute_with_the_weekday_when_it_is_another_day(self):
        said = {
            TUE(8, 5): '지금은 실행 금지 시간 — 08:06 에 다시', TUE(8, 49): '지금은 실행 금지 시간 — 09:06 에 다시',
            TUE(12, 0): '지금은 실행 금지 시간 — 12:06 에 다시', TUE(12, 59): '지금은 실행 금지 시간 — 13:06 에 다시',
            TUE(7, 0): '지금은 실행 금지 시간 — 08:06 에 다시', TUE(21, 49): '지금은 실행 금지 시간 — 수요일 08:06 에 다시',
            TUE(23, 0): '지금은 실행 금지 시간 — 수요일 08:06 에 다시',
        }
        for now, text in said.items():
            self.assertEqual(gate.gate_window_refusal(now), text, now)

    def test_the_case_that_waits_for_the_next_scheduled_run_must_start_by_20_48_so_that_run_is_before_22_quiet_hours(self):
        self.assertIsNone(gate.gate_window_refusal(TUE(20, 48), last_hour=20))
        self.assertEqual(gate.gate_window_refusal(TUE(21, 6), last_hour=20), '지금은 실행 금지 시간 — 수요일 08:06 에 다시')

    def test_the_morning_window_is_0706_to_0748(self):
        for now in (TUE(7, 6), TUE(7, 48), TUE(7, 48, 59)):
            self.assertIsNone(gate.morning_refusal(now), now)
        self.assertEqual(gate.morning_refusal(TUE(7, 5)), '지금은 실행 금지 시간 — 07:06 에 다시')
        self.assertEqual(gate.morning_refusal(TUE(7, 49)), '지금은 실행 금지 시간 — 수요일 07:06 에 다시')
        self.assertEqual(gate.morning_refusal(TUE(12, 20)), '지금은 실행 금지 시간 — 수요일 07:06 에 다시')
        self.assertEqual(gate.morning_refusal(TUE(6, 0)), '지금은 실행 금지 시간 — 07:06 에 다시')


# ── 모든 가설 공통 ──────────────────────────────────────────────────────────────────────────────────

class CommonTest(GateBase):
    def test_the_blocked_note_says_when_to_come_back(self):
        self.clock.now = TUE(12, 3)
        self.assertEqual(self.go('E-PUSH-40'), ('blocked', '지금은 실행 금지 시간 — 12:06 에 다시'))
        self.clock.now = TUE(12, 20)
        self.assertEqual(self.go('E-PUSH-44'), ('blocked', '지금은 실행 금지 시간 — 수요일 07:06 에 다시'))

    def test_the_46_waits_for_the_next_scheduled_run_so_it_is_blocked_from_21_06(self):
        self.clock.now = TUE(21, 6)
        self.assertEqual(self.go('E-PUSH-46'), ('blocked', '지금은 실행 금지 시간 — 수요일 08:06 에 다시'))

    def test_a_second_case_in_the_same_hour_is_blocked_before_any_account_because_chat_gate_runs_once_per_hour(self):
        self.assertEqual(self.go('E-PUSH-40')[0], 'pass')
        users = len(self.world.users)
        self.clock.now = TUE(12, 30)
        self.assertEqual(self.go('E-PUSH-41'), ('blocked', '지금은 실행 금지 시간 — 13:06 에 다시'))
        self.assertEqual((len(self.world.users), len(self.batches)), (users, 1))

    def test_the_next_hour_is_open_again(self):
        self.go('E-PUSH-40')
        self.clock.now = TUE(13, 20)
        self.assertEqual(self.go('E-PUSH-41')[0], 'pass')
        self.assertEqual(len(self.batches), 2)

    def test_the_window_is_checked_again_just_before_the_batch_when_getting_ready_took_long(self):
        self.clock.now = TUE(12, 47)
        self.on_background = lambda: self.clock.advance(150)  # 폰 준비가 길어져 12:49 가 됐다
        result = self.go('E-PUSH-40')
        self.assertEqual(result, ('blocked', '지금은 실행 금지 시간 — 13:06 에 다시'))
        self.assertEqual((self.batches, self.created_patches()), ([], []))

    def test_the_notification_permission_is_given_first_and_taken_back_even_when_blocked(self):
        self.clock.now = TUE(12, 47)
        self.on_background = lambda: self.clock.advance(150)
        self.assertEqual(self.go('E-PUSH-40')[0], 'blocked')
        self.assertEqual((self.log[0], self.log[-1]), ('grant', 'revoke'))


def _outside(case):
    def check(self):
        self.clock.now = TUE(12, 20) if case == 'E-PUSH-44' else TUE(12, 3)
        phone = self.phone()
        result = self.go(case, phone)
        self.assertEqual(result[0], 'blocked')
        self.assertIn('지금은 실행 금지 시간', result[1])
        self.assertEqual((self.world.users, phone.jobs, self.batches, self.log), ([], [], [], []))
    return check


def _daytime(case):
    def check(self):
        self.clock.now = WED(7, 20) if case == 'E-PUSH-44' else TUE(12, 20)
        self.go(case)
        self.assertEqual(self.daytime.call_count, 0 if case == 'E-PUSH-44' else 1)
    return check


for _case in CASES:  # 가설마다 새 세계에서 — 계정 번호(id-1 = 폰)가 가설마다 1부터라서 한 시험 안에서 돌리지 않는다
    setattr(CommonTest, f'test_{_case[-2:]}_outside_the_window_is_blocked_before_any_account_app_permission_or_batch', _outside(_case))
    setattr(CommonTest, f'test_{_case[-2:]}_needs_daytime_only_if_it_is_not_the_morning_case', _daytime(_case))


# ── 40 · 41 · 43 · 45 · 47 · 48 : 한 번 부르고 폰 계정 알림만 본다 ─────────────────────────────────────────

class Remind40Test(GateBase):
    def test_a_match_24h_old_and_unanswered_sends_one_reminder_to_the_phone(self):
        result = self.go('E-PUSH-40')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.reminders()), 1)
        self.assertIn('못 봄', result[1])  # 상대(B) 쪽 알림 1개와 reminded 2 는 폰이 하나라 못 본다

    def test_the_batch_is_called_exactly_once_through_the_gate(self):
        self.go('E-PUSH-40')
        self.assertEqual([name for name, _ in self.batches], ['chat-gate'])

    def test_created_at_is_moved_to_24h5m_before_now_right_before_the_batch_never_earlier(self):
        self.go('E-PUSH-40')
        (patch,) = self.created_patches()
        self.assertLess(self.world.sent.index(patch), self.batch_at())
        self.assertEqual(datetime.fromisoformat(patch['body']['created_at']), self.batches[0][1] - timedelta(hours=24, minutes=5))
        self.assertEqual(self.world.sent[self.batch_at() - 1], patch)  # 사이에 아무것도 안 끼었다
        self.assertEqual(patch['query'], {'id': f"eq.{self.mine()['id']}"})

    def test_only_the_phone_accounts_match_is_aged_never_the_anchor(self):
        self.go('E-PUSH-40')
        self.assertNotEqual(self.mine()['created_at'], self.anchor()['created_at'])
        self.assertEqual(len(self.created_patches()), 1)

    def test_the_anchor_match_has_both_accepted_and_no_stamp_before_the_batch(self):
        seen = {}
        self.gcloud_before = self.gcloud
        original = self.world.run_gate

        def spy(at, how):
            seen['anchor'] = dict(self.anchor())
            seen['accepted'] = [p['trust_response'] for p in self.world.tables['match_participants'] if p['match_id'] == self.anchor()['id']]
            original(at, how)

        self.world.run_gate = spy
        self.go('E-PUSH-40')
        self.assertIsNone(seen['anchor'].get('trust_passed_at'))
        self.assertEqual(seen['accepted'], ['accept', 'accept'])
        self.assertTrue(self.anchor()['trust_passed_at'])

    def test_a_second_copy_of_the_reminder_is_a_fail(self):
        self.world.duplicate = True
        result = self.go('E-PUSH-40')
        self.assertEqual(result[0], 'fail')
        self.assertIn('2개', result[1])

    def test_no_reminder_when_the_batch_ran_is_a_fail(self):
        self.world.hide = True  # 배치는 돌았는데 서버가 안 보낸 것과 같다
        result = self.go('E-PUSH-40')
        self.assertEqual(result[0], 'fail')
        self.assertIn('신뢰 확인이 기다리고 있어요', result[1])

    def test_no_reminder_and_no_sign_that_the_batch_ran_is_blocked_not_a_fail(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-40')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])

    def test_a_different_text_is_a_fail_that_names_what_arrived(self):
        original = self.world.post
        self.world.post = lambda title, text: original(title, '다른 문구')
        result = self.go('E-PUSH-40')
        self.assertEqual(result[0], 'fail')
        self.assertIn('다른 문구', result[1])


class Silent41Test(GateBase):
    def test_41_a_phone_account_that_already_accepted_gets_nothing_and_a_control_message_proves_the_path(self):
        result = self.go('E-PUSH-41')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.reminders(), [])
        self.assertTrue(self.control_arrived())
        self.assertEqual(self.person(PHONE_ID)['trust_response'], 'accept')
        self.assertIsNone(self.person(PARTNER_ID).get('trust_response'))
        self.assertIn('못 봄', result[1])
        self.assertIn(('none', 60), self.windows)

    def test_41_the_acceptance_is_written_before_the_batch_and_created_at_is_aged_right_before_it(self):
        self.go('E-PUSH-41')
        accepted = next(i for i, s in enumerate(self.world.sent) if s['method'] == 'PATCH' and s['query'].get('profile_id') == f'eq.{PHONE_ID}')
        self.assertLess(accepted, self.batch_at())
        self.assertEqual(self.world.sent[self.batch_at() - 1], self.created_patches()[0])

    def test_41_a_reminder_to_the_one_who_accepted_is_a_fail(self):
        self.world.bug.add('remind_all')
        self.assertEqual(self.go('E-PUSH-41')[0], 'fail')

    def test_41_nothing_arrived_and_no_stamp_is_blocked_not_a_pass(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-41')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])
        self.assertFalse(self.control_arrived())  # 앵커를 못 봤으면 대조도 안 한다

    def test_41_a_control_message_that_never_arrives_is_blocked(self):
        self.world.permitted = lambda: not any(s['path'].endswith('/messages') for s in self.world.sent)
        result = self.go('E-PUSH-41')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('대조 알림', result[1])


class Switch43Test(GateBase):
    def test_43_with_the_reminder_switch_off_the_phone_gets_nothing_and_a_message_still_arrives(self):
        result = self.go('E-PUSH-43')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.reminders(), [])
        self.assertTrue(self.control_arrived())  # 스위치는 trust_reminder 만 껐다
        self.assertIn('못 봄', result[1])

    def test_43_the_switch_is_turned_off_for_the_phone_account_before_the_batch(self):
        self.go('E-PUSH-43')
        flip = next(s for s in self.world.sent if s['method'] == 'PATCH' and s['path'] == '/cards/notification-settings')
        self.assertEqual((flip['auth'], flip['body']), ('tok-1', {'trust_reminder': False}))
        self.assertLess(self.world.sent.index(flip), self.batch_at())

    def test_43_a_reminder_with_the_switch_off_is_a_fail(self):
        self.world.bug.add('ignore_switch')
        self.assertEqual(self.go('E-PUSH-43')[0], 'fail')

    def test_43_no_stamp_is_blocked(self):
        self.world.gate_on = False
        self.assertEqual(self.go('E-PUSH-43')[0], 'blocked')


class Expired45Test(GateBase):
    def test_45_a_window_that_ended_a_minute_ago_sends_nothing(self):
        result = self.go('E-PUSH-45')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.reminders(), [])
        self.assertTrue(self.control_arrived())
        (patch,) = self.created_patches()
        self.assertEqual(datetime.fromisoformat(patch['body']['created_at']), self.batches[0][1] - timedelta(hours=25, minutes=1))

    def test_45_a_reminder_after_the_window_is_a_fail(self):
        self.world.bug.add('remind_all')
        self.assertEqual(self.go('E-PUSH-45')[0], 'fail')

    def test_45_no_stamp_is_blocked(self):
        self.world.gate_on = False
        self.assertEqual(self.go('E-PUSH-45')[0], 'blocked')


class Left47Test(GateBase):
    def test_47_when_the_partner_left_the_phone_gets_nothing(self):
        result = self.go('E-PUSH-47')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.reminders(), [])
        self.assertTrue(self.control_arrived())
        self.assertTrue(self.person(PARTNER_ID)['left_at'])
        self.assertIsNone(self.person(PHONE_ID).get('left_at'))  # 나간 쪽은 상대여야 폰이 본다

    def test_47_leaving_is_written_before_the_batch(self):
        self.go('E-PUSH-47')
        self.assertLess(self.at('PATCH', 'match_participants', 'left_at'), self.batch_at())

    def test_47_a_reminder_to_the_one_who_stayed_is_a_fail(self):
        self.world.bug.add('ignore_left')
        self.assertEqual(self.go('E-PUSH-47')[0], 'fail')

    def test_47_no_stamp_is_blocked(self):
        self.world.gate_on = False
        self.assertEqual(self.go('E-PUSH-47')[0], 'blocked')


class Closed48Test(GateBase):
    def test_48_a_49h_old_match_is_closed_without_any_notification(self):
        result = self.go('E-PUSH-48')
        self.assertEqual(result[0], 'pass', result)
        self.assertTrue(self.mine()['chat_closed_at'])
        self.assertEqual([n for n in self.world.shade if n.title != CTL], [])
        self.assertTrue(self.control_arrived())
        (patch,) = self.created_patches()
        self.assertEqual(datetime.fromisoformat(patch['body']['created_at']), self.batches[0][1] - timedelta(hours=49))

    def test_48_a_notification_when_closing_is_a_fail(self):
        self.world.bug.add('close_notice')
        self.assertEqual(self.go('E-PUSH-48')[0], 'fail')

    def test_48_any_other_notification_when_closing_is_a_fail_too(self):
        self.world.bug.add('close_other')
        result = self.go('E-PUSH-48')
        self.assertEqual(result[0], 'fail')
        self.assertIn('방이 닫혔어요', result[1])

    def test_48_not_closed_while_the_anchor_shows_the_batch_ran_is_a_fail(self):
        self.world.bug.add('no_close')
        result = self.go('E-PUSH-48')
        self.assertEqual(result[0], 'fail')
        self.assertIn('chat_closed_at', result[1])

    def test_48_neither_closed_nor_stamped_is_blocked(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-48')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])

    def test_48_the_closing_alone_proves_the_batch_ran_even_if_the_anchor_is_missing(self):
        original = self.world.run_gate

        def only_closing(at, how):
            original(at, how)
            self.anchor().pop('trust_passed_at', None)

        self.world.run_gate = only_closing
        self.assertEqual(self.go('E-PUSH-48')[0], 'pass')


# ── 44 : 밤 → 아침 ──────────────────────────────────────────────────────────────────────────────────

class Morning44Test(GateBase):
    START = TUE(7, 20)

    def test_44_nothing_in_the_7_oclock_hour_then_the_8_oclock_scheduled_run_brings_it(self):
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.reminders()), 1)
        self.assertEqual([(name, at) for name, at in self.batches], [('chat-gate', self.START)])  # 손 호출은 07시 한 번뿐
        self.assertEqual(self.world.gate_runs[-1], (TUE(8, 0), 'scheduled'))
        self.assertIn(('none', 60), self.windows)
        self.assertTrue(self.control_arrived())  # 07시대 0개를 믿을 근거

    def test_44_created_at_is_yesterday_0200_seoul_in_absolute_time(self):
        self.go('E-PUSH-44')
        (patch,) = self.created_patches()
        self.assertEqual(datetime.fromisoformat(patch['body']['created_at']), seoul(5, 2, 0))
        self.assertLess(self.world.sent.index(patch), self.batch_at())

    def test_44_the_7_oclock_anchor_is_checked_after_the_7_oclock_call_and_before_judging_zero(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])
        self.assertEqual(self.world.gate_runs[0][1], 'hand')

    def test_44_a_reminder_in_the_7_oclock_hour_is_a_fail(self):
        self.world.bug.add('remind_all')
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'fail')
        self.assertIn('안 와야 할 알림', result[1])

    def test_44_when_the_8_oclock_run_never_comes_it_is_called_by_hand_in_the_8_oclock_hour_and_the_note_says_so(self):
        self.world.scheduler = False
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.batches), 2)
        self.assertEqual((self.batches[0][1].hour, self.batches[1][1].hour), (7, 8))
        self.assertGreaterEqual(self.batches[1][1], TUE(8, 6))
        self.assertIn('손', result[1])
        self.assertEqual(len(self.created_patches()), 1)  # 어제 02:00 은 그대로 — 다시 안 옮긴다

    def test_44_a_hand_call_that_brings_nothing_either_is_a_fail(self):
        self.world.scheduler = False
        original = self.world.run_gate

        def late(at, how):  # 7시 호출은 정상(앵커 도장), 8시 호출은 알림을 안 보낸다
            self.world.hide = at.hour >= 8
            original(at, how)

        self.world.run_gate = late
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'fail')

    def test_44_the_reminders_from_both_the_scheduled_run_and_a_hand_call_are_only_a_memo_not_a_fail(self):
        self.world.scheduler = True
        self.world.bug.add('double_scheduled')  # 8시에 2개가 와도
        result = self.go('E-PUSH-44')
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('2개', result[1])

    def test_44_a_hand_call_time_that_already_passed_is_blocked_and_calls_nothing(self):
        self.world.scheduler = False
        self.clock.on_hour.append(lambda at: setattr(self.clock, 'now', at + timedelta(minutes=50)) if at.hour == 8 else None)
        result = self.go('E-PUSH-44')
        self.assertEqual(result, ('blocked', '지금은 실행 금지 시간 — 09:06 에 다시'))
        self.assertEqual(len(self.batches), 1)

    def test_44_between_0803_and_0806_it_waits_for_0806_before_the_hand_call(self):
        self.world.scheduler = False
        self.go('E-PUSH-44')
        self.assertGreaterEqual(self.batches[1][1], TUE(8, 6))
        self.assertLess(self.batches[1][1], TUE(8, 7))

    def test_44_the_second_call_goes_through_the_gate_so_two_hand_calls_in_the_7_oclock_hour_are_impossible(self):
        self.world.scheduler = False
        self.assertEqual(self.go('E-PUSH-44')[0], 'pass')
        self.clock.now = TUE(7, 40)
        self.assertEqual(self.go('E-PUSH-44'), ('blocked', '지금은 실행 금지 시간 — 수요일 07:06 에 다시'))


# ── 46 : 같은 시간 두 번 ─────────────────────────────────────────────────────────────────────────────

class Twice46Test(GateBase):
    def test_46_one_hand_call_plus_the_next_scheduled_run_makes_two_reminders_which_is_the_known_limit(self):
        result = self.go('E-PUSH-46')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.reminders()), 2)
        self.assertIn('알려진 한계', result[1])
        self.assertEqual(len(self.batches), 1)  # 손 호출은 한 번뿐 — 두 번째는 정각 예약 실행
        self.assertEqual(self.world.gate_runs[-1], (TUE(13, 0), 'scheduled'))

    def test_46_created_at_is_24h2m_old_not_24h5m_so_the_next_scheduled_run_has_minutes_to_spare_inside_the_window(self):
        self.go('E-PUSH-46')
        (patch,) = self.created_patches()
        self.assertEqual(datetime.fromisoformat(patch['body']['created_at']), self.batches[0][1] - timedelta(hours=24, minutes=2))

    def test_46_it_waits_until_three_minutes_after_the_next_hour_before_judging(self):
        self.go('E-PUSH-46')
        self.assertGreaterEqual(self.clock.now, TUE(13, 3))

    def test_46_only_one_reminder_means_the_scheduled_run_may_not_have_come_so_it_is_blocked(self):
        self.world.scheduler = False
        result = self.go('E-PUSH-46')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('예약 실행', result[1])

    def test_46_three_or_more_reminders_is_a_fail(self):
        self.world.bug.add('double_scheduled')
        result = self.go('E-PUSH-46')
        self.assertEqual(result[0], 'fail')
        self.assertIn('3개', result[1])

    def test_46_no_first_reminder_with_a_stamped_anchor_is_a_fail_and_does_not_wait_for_the_next_hour(self):
        self.world.hide = True
        result = self.go('E-PUSH-46')
        self.assertEqual(result[0], 'fail')
        self.assertLess(self.clock.now, TUE(13, 0))

    def test_46_no_first_reminder_and_no_stamp_is_blocked(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-46')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])

    def test_46_created_at_is_24h5m_old_so_the_window_still_holds_the_next_scheduled_run_even_from_minute_6(self):
        self.clock.now = TUE(12, 6)
        self.assertEqual(self.go('E-PUSH-46')[0], 'pass')
        self.assertEqual(len(self.reminders()), 2)

    def test_46_from_minute_48_it_is_still_two_and_the_note_names_the_hour(self):
        self.clock.now = TUE(20, 48)
        self.assertEqual(self.go('E-PUSH-46')[0], 'pass')


# ── 42 · 79 · 80 : 앱이 말하는 가설 ─────────────────────────────────────────────────────────────────

class Open42Test(GateBase):
    def room(self, **kw):
        return {'result': 'pass', 'room': True, 'nickname': True, 'room_ms': 3200, 'screen': [], **kw}

    def test_42_the_app_stays_alive_in_the_back_and_pressing_the_reminder_opens_the_room(self):
        phone = self.phone(self.room())
        result = self.go('E-PUSH-42', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.extras, [{'tapped': True}])
        self.assertEqual(len(phone.jobs), 1)  # 앱은 한 번만 켠다(죽이지 않는다)
        self.assertEqual(phone.jobs[0]['nickname'], PARTNER)

    def test_42_the_order_is_back_then_batch_then_tap_and_the_app_is_never_killed(self):
        self.go('E-PUSH-42')
        self.assertEqual(self.log, ['grant', 'background', 'batch', f'tap:{TITLE}', 'revoke'])
        self.assertLess(self.world.sent.index(self.created_patches()[0]), self.batch_at())

    def test_42_no_nickname_in_the_app_bar_is_a_fail(self):
        result = self.go('E-PUSH-42', self.phone(self.room(nickname=False)))
        self.assertEqual(result[0], 'fail')
        self.assertIn('앱바 닉네임', result[1])

    def test_42_no_room_names_the_screen_that_was_showing(self):
        result = self.go('E-PUSH-42', self.phone(self.room(room=False, screen=['home'])))
        self.assertEqual(result[0], 'fail')
        self.assertIn('홈', result[1])

    def test_42_no_reminder_with_a_stamped_anchor_is_a_fail_and_the_app_is_told_not_to_judge(self):
        self.world.hide = True
        phone = self.phone({'result': 'pass', 'skipped': True})
        result = self.go('E-PUSH-42', phone)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(phone.extras, [{'tapped': False}])
        self.assertNotIn(f'tap:{TITLE}', self.log)

    def test_42_no_reminder_and_no_stamp_is_blocked(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-42')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])

    def test_42_a_phone_whose_token_never_reaches_the_server_is_blocked_before_the_batch(self):
        result = self.go('E-PUSH-42', self.phone(push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertIn('기기 토큰', result[1])
        self.assertEqual(self.batches, [])


class Killed79Test(GateBase):
    def room(self, **kw):
        return {'result': 'pass', 'room': True, 'nickname': True, 'room_ms': 3200, 'screen': [], **kw}

    def test_79_kill_the_app_batch_wait_for_the_reminder_tell_the_job_then_tap_and_the_room_opens(self):
        result = self.go('E-PUSH-79')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.log, ['grant', 'background', 'kill', 'batch', 'tell', f'tap:{TITLE}', 'revoke'])
        self.assertLess(self.world.sent.index(self.created_patches()[0]), self.batch_at())
        self.assertEqual(self.app.told, [{'case': 'E-PUSH-79', 'phase': 'tap', 'nickname': PARTNER}])
        self.assertIn('3200', result[1])  # 앱이 말한 ms 를 메모
        self.assertIn('못 봄', result[1])  # 상대 쪽(둘 다 꺼짐)은 폰이 하나라 못 봄

    def test_79_the_app_gets_30_seconds_plus_boot_to_answer(self):
        self.go('E-PUSH-79')
        (call,) = self.app.hub.result.call_args_list
        self.assertGreaterEqual(call.args[0], 60)

    def test_79_a_room_that_never_opens_is_a_fail_and_names_the_screen(self):
        phone = self.phone()
        phone.hub.result.return_value = self.room(room=False, nickname=False, screen=['consent'])
        result = self.go('E-PUSH-79', phone)
        self.assertEqual(result[0], 'fail')
        self.assertIn('약관 동의', result[1])

    def test_79_a_room_without_the_nickname_is_a_fail(self):
        phone = self.phone()
        phone.hub.result.return_value = self.room(nickname=False)
        self.assertEqual(self.go('E-PUSH-79', phone)[0], 'fail')

    def test_79_an_app_that_never_answers_is_a_fail(self):
        phone = self.phone()
        phone.hub.result.return_value = None
        self.assertEqual(self.go('E-PUSH-79', phone)[0], 'fail')

    def test_79_no_reminder_with_a_stamped_anchor_is_a_fail_and_nothing_is_pressed(self):
        self.world.hide = True
        result = self.go('E-PUSH-79')
        self.assertEqual(result[0], 'fail')
        self.assertNotIn('tell', self.log)
        self.assertNotIn(f'tap:{TITLE}', self.log)

    def test_79_no_reminder_and_no_stamp_is_blocked(self):
        self.world.gate_on = False
        self.assertEqual(self.go('E-PUSH-79')[0], 'blocked')


class Front80Test(GateBase):
    def front(self, **kw):
        return {'result': 'pass', 'list': True, 'row': True, 'screen': ['conversations'], **kw}

    def setUp(self):
        super().setUp()
        self.world.hide = True  # 앞에 있는 앱은 배너를 안 띄운다(서버는 보냈다)

    def test_80_with_the_app_in_front_no_banner_then_a_control_message_in_the_back_and_the_list_stays(self):
        phone = self.phone(self.front())
        result = self.go('E-PUSH-80', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.reminders(), [])
        self.assertTrue(self.control_arrived())
        self.assertEqual(phone.jobs[0]['nickname'], PARTNER)
        self.assertIn('서버 발송', result[1])  # 앞에서는 배너가 없다는 것만 확인 — 서버가 보냈는지는 응답을 못 읽음

    def test_80_the_app_stays_in_front_for_the_batch_and_the_watch_then_goes_back_for_the_control_and_returns(self):
        self.go('E-PUSH-80')
        self.assertEqual(self.log, ['grant', 'batch', 'background', 'front', 'revoke'])
        self.assertLess(self.batch_at(), self.at('POST', '/messages'))  # 대조 메시지는 배치 뒤

    def test_80_a_banner_while_the_app_is_in_front_is_a_fail(self):
        self.world.hide = False
        result = self.go('E-PUSH-80', self.phone(self.front()))
        self.assertEqual(result[0], 'fail')
        self.assertIn('안 와야 할 알림', result[1])

    def test_80_a_list_that_vanished_is_a_fail(self):
        self.assertEqual(self.go('E-PUSH-80', self.phone(self.front(list=False)))[0], 'fail')

    def test_80_a_lost_row_is_a_fail(self):
        result = self.go('E-PUSH-80', self.phone(self.front(row=False)))
        self.assertEqual(result[0], 'fail')
        self.assertIn(PARTNER, result[1])

    def test_80_no_stamp_is_blocked_before_judging_silence(self):
        self.world.gate_on = False
        result = self.go('E-PUSH-80')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('배치가 돈 것 같지 않아', result[1])

    def test_80_a_control_message_that_never_arrives_is_blocked(self):
        self.world.permitted = lambda: not any(s['path'].endswith('/messages') for s in self.world.sent)
        result = self.go('E-PUSH-80')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('대조 알림', result[1])


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_the_bundle_is_the_11_cases_in_number_order_and_each_is_a_phone_case(self):
        self.assertEqual(area1.BUNDLES['area4-push-gate'], CASES)
        self.assertEqual(cli.BUNDLES['area4-push-gate'], CASES)
        for case in CASES:
            self.assertIn(case, area1.PHONE)

    def test_the_hour_long_cases_get_4500_seconds_and_the_others_900(self):
        for case in CASES:
            want = 4500 if case in ('E-PUSH-44', 'E-PUSH-46') else 900
            self.assertEqual(tools.CASE_LIMITS[case], want, case)
            self.assertGreater(cli.case_limit(case, True), tools.CASE_LIMIT)

    def test_the_a1_cases_keep_their_limits(self):
        self.assertEqual(tools.CASE_LIMITS['E-PUSH-12'], 900)


if __name__ == '__main__':
    unittest.main()
