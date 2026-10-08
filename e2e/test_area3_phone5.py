"""영역 3 배치 가설 9개(E-CHAT-50 · 51 · 52 · 55 · 57 · 65 · 66 · 67 · 69, 묶음 area3-phone-5)의 PC 쪽 시험 — 폰 · 운영 · gcloud 없이 가짜 앱 ·
가짜 서버 · 가짜 배치로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3_phone5`.

가짜 서버는 e2e/test_area3.py 의 Fake, 가짜 폰은 [Phone5], 가짜 gcloud(`tools.batch`)는 [Base5.gcloud] — 운영 배치(backend chat/batch_router.py ·
account/batch_router.py)의 규칙을 같은 모양으로 흉내 내서 가짜 표(matches · match_participants · messages · profiles)를 바꾼다. 실제 호출은 0건이다.
시계도 가짜 — `batch_gate.now_seoul` 을 화요일 14:20 에 둔다(낮 · 정각에서 먼저 멀다). 통과 기록(HISTORY)은 임시 파일이라 실제 기록을 안 건드린다.
계정은 만든 순서대로 id-1(폰 계정 = 받는 쪽 B) · id-2(상대 A) · …, 토큰은 tok-1 · tok-2 …
"""

import itertools
import re
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2, area3, area3_phone5, batch_gate, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area3_phone import App
from e2e.test_area3_phone2 import Phone2
from e2e.tools import Blocked, Reply

TITLE, BODY = '신뢰 확인이 기다리고 있어요', '카카오톡 아이디를 공유할지 정해 주세요'
GATE_OVER = '응답 기한이 지나 이 대화는 종료됐어요'
OPENED = {'result': 'pass', 'room': True, 'nickname': True, 'message': True, 'screen': ['home'], 'room_ms': 900, 'opened_at': '2026-10-06T05:20:07Z'}
BUNDLE = ['E-CHAT-50', 'E-CHAT-51', 'E-CHAT-52', 'E-CHAT-55', 'E-CHAT-57', 'E-CHAT-65', 'E-CHAT-66', 'E-CHAT-67', 'E-CHAT-69']
GATED = [c for c in BUNDLE if c != 'E-CHAT-69']  # chat-gate 를 부르는 8개


def at(hhmm, day=6):
    """2026-10 의 [day]일(기본 화요일) 서울 시각 — 월요일(5일)은 daily-cards 만 막는다."""
    hour, minute = map(int, hhmm.split(':'))
    return datetime(2026, 10, day, hour, minute, tzinfo=SEOUL)


def when(value):
    return datetime.fromisoformat(value) if isinstance(value, str) else value


class Phone5(App):
    """폰 대신. [says] 는 일감의 phase(없으면 None) → 앱이 할 말(dict 또는 일감 → dict). midway 가 오면 앱이 step 에서 멈춘 것처럼 그 자리에서 부른다.
    알림 누름 판은 hub.tell · hub.result 로 — 전부 [events] 에 남겨 순서를 센다."""

    case = 'E-CHAT-50'

    def __init__(self, events, says, on_app=None, tapped=None):
        super().__init__(lambda job: None)
        self.events, self.says, self.on_app, self.tapped = events, says, on_app or (lambda job: None), tapped
        self.hub = mock.Mock()
        self.hub.tell.side_effect = lambda job: events.append(('tell', job))
        self.hub.result.side_effect = lambda timeout: events.append(('result', timeout)) or self.tapped

    def __call__(self, midway=None, **job):
        self.events.append(('app', job))
        self.jobs.append(job)
        self.on_app(job)
        say = self.says.get(job.get('phase'), {})
        if midway and not (isinstance(say, dict) and say.get('loaded') is False):  # 방 읽기를 못 끝낸 앱은 step 을 부르지 않는다(area3_b8.dart _liveBody)
            self.events.append('step')
            midway({'step': 'x'})
            self.events.append('go')
        return {'result': 'pass', **(say(job) if callable(say) else say)}


class Base5(Phone2):
    """가짜 폰 · 서버 · notify · 시계 · gcloud 를 갖춘 바탕. 배치 서버 규칙은 [sim_gate] · [sim_cleanup]."""

    def setUp(self):
        super().setUp()
        self.events, self.pushed, self.clock = [], [], [at('14:20')]
        area3_phone5._FAILED.clear()  # 배치 뒤 fail 의 기억은 시험끼리 새지 않게
        self.batch_works, self.ignore, self.off, self.at_gcloud = True, lambda match: False, set(), None
        self.old = [notify.Notice('old', '남은 알림', '', 'c')]
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        fakes = [
            mock.patch.object(batch_gate, 'now_seoul', lambda: self.clock[0]),
            mock.patch.object(batch_gate, 'HISTORY', Path(folder.name) / 'runs.jsonl'),
            mock.patch.object(tools, 'batch', self.gcloud),
            mock.patch.object(area2, '_mine', lambda run: {u['id'] for u in self.fake.users}),
            mock.patch.object(notify, 'read_notifications', lambda s: self.events.append(('read', s)) or self.old),
            mock.patch.object(notify, 'kill_app', lambda s: self.events.append('kill')),
            mock.patch.object(notify, 'wait_new', self.wait_new),
            mock.patch.object(notify, 'expect_none', self.expect_none),
            mock.patch.object(notify, 'tap_notification', lambda s, title: self.events.append(('tap', title))),
            mock.patch('time.monotonic', side_effect=itertools.count()),  # 기다림(_wait_for)이 진짜 시간을 안 쓰고 한 번에 한 칸씩 흐른다
        ]
        for patcher in fakes:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake.on('GET', r'/chat/conversations', self.conversations)
        self.fake.on('GET', r'/chat/matches/[^/]+', self.room)
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', self.post_message)
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', self.leave)
        self.fake.on('POST', r'/chat/matches/[^/]+/trust', self.trust)
        self.fake.on('PATCH', r'/cards/notification-settings', self.switch)

    # ── 가짜 서버 쪽 API ────────────────────────────────────────────────────────────────────────────
    def user_of(self, sent):
        return 'id-' + sent['auth'].removeprefix('tok-')

    def match_of(self, sent):
        return next(m for m in self.fake.tables['matches'] if m['id'] == sent['path'].split('/')[3])

    def parts(self, match_id):
        return [p for p in self.fake.tables.get('match_participants', []) if p['match_id'] == match_id]

    def post_message(self, sent):
        match = self.match_of(sent)
        self.events.append(('send', self.user_of(sent), sent['body']['body']))
        if match.get('chat_closed_at'):
            return Reply(409, {'detail': '종료된 대화예요'})
        self.fake.tables.setdefault('messages', []).append({'match_id': match['id'], 'sender_id': self.user_of(sent), 'kind': 'text',
                                                              'body': sent['body']['body'], 'created_at': datetime.now(timezone.utc).isoformat()})
        return Reply(201, {'id': 'm'})

    def leave(self, sent):
        for part in self.parts(self.match_of(sent)['id']):
            if part['profile_id'] == self.user_of(sent):
                part['left_at'] = datetime.now(timezone.utc).isoformat()
        self.events.append(('leave', self.user_of(sent)))
        return Reply(200, {'ok': True})

    def trust(self, sent):
        match = self.match_of(sent)
        for part in self.parts(match['id']):
            if part['profile_id'] == self.user_of(sent):
                part['trust_response'] = 'accept'
        self.events.append(('trust', self.user_of(sent)))
        return Reply(200, {'passed': False})

    def switch(self, sent):
        self.events.append(('switch', self.user_of(sent), sent['body']))
        if sent['body'].get('trust_reminder') is False:
            self.off.add(self.user_of(sent))
        return Reply(200, {})

    def conversations(self, sent):
        me = self.user_of(sent)
        rows = [{'match_id': m['id']} for m in self.fake.tables.get('matches', []) if not m.get('chat_closed_at')
                and any(p['profile_id'] == me and not p.get('left_at') for p in self.parts(m['id']))]
        return Reply(200, {'conversations': rows})

    def room(self, sent):
        match = self.match_of(sent)
        return Reply(200, {'chat_closed_at': match.get('chat_closed_at'), 'gate': {'passed': bool(match.get('trust_passed_at'))}})

    # ── 가짜 gcloud(운영 배치 규칙 흉내) ────────────────────────────────────────────────────────────
    def gcloud(self, name):
        self.events.append(('gcloud', name))
        self.at_gcloud = [dict(m) for m in self.fake.tables.get('matches', [])]
        if self.batch_works:
            {'chat-gate': self.sim_gate, 'cleanup': self.sim_cleanup}[name]()

    def sim_gate(self):
        """chat/batch_router.py run_chat_gate — 한쪽이 나간 방은 건너뛰고, 둘 다 수락이면 도장, 48시간이 넘으면 닫고, 24~25시간이면 아직 안 수락한 사람에게 리마인드."""
        now = datetime.now(timezone.utc)
        for match in self.fake.tables.get('matches', []):
            parts = self.parts(match['id'])
            if match.get('trust_passed_at') or match.get('chat_closed_at') or self.ignore(match) or any(p.get('left_at') for p in parts):
                continue
            if len(parts) == 2 and all(p.get('trust_response') == 'accept' for p in parts):
                match['trust_passed_at'] = now.isoformat()
                continue
            age = now - when(match.get('created_at') or now.isoformat())
            if age >= timedelta(hours=48):
                match['chat_closed_at'] = now.isoformat()
            elif timedelta(hours=24) <= age < timedelta(hours=25):
                self.pushed += [p['profile_id'] for p in parts if not p.get('trust_response') and p['profile_id'] not in self.off]

    def sim_cleanup(self):
        """account/batch_router.py run_cleanup — 탈퇴 30일 지난 계정의 auth 사용자 · profiles · (cascade) 매칭 · 메시지."""
        for profile in list(self.fake.tables.get('profiles', [])):
            if profile.get('status') != 'withdrawn' or datetime.now(timezone.utc) - when(profile['withdrawn_at']) < timedelta(days=30):
                continue
            tables = self.fake.tables
            gone = {m['id'] for m in tables.get('matches', []) if profile['id'] in {p['profile_id'] for p in self.parts(m['id'])}}
            tables['profiles'].remove(profile)
            tables['matches'] = [m for m in tables.get('matches', []) if m['id'] not in gone]
            tables['messages'] = [m for m in tables.get('messages', []) if m['match_id'] not in gone]
            self.fake.users[:] = [u for u in self.fake.users if u['id'] != profile['id']]

    # ── 가짜 notify ─────────────────────────────────────────────────────────────────────────────────
    def notices(self):
        """폰 계정(id-1)에게 간 리마인드만 — 알림을 받을 기기는 폰 하나뿐이다."""
        return [notify.Notice(f'n{i}', TITLE, BODY, 'c') for i, who in enumerate(self.pushed) if who == 'id-1']

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        self.events.append(('wait_new', before is self.old, seconds))
        return self.notices()

    def expect_none(self, serial, before, seconds=0):
        self.events.append(('expect_none', before is self.old, seconds))
        return self.notices()

    # ── 한 판 돌리기 ────────────────────────────────────────────────────────────────────────────────
    def go(self, case, says=None, tokens=1, tapped=None, on_app=None):
        """[case] 를 돌린다. 폰이 로그인하면 기기 토큰이 서버에 올라온 것으로 친다([tokens] 줄)."""
        def app_event(job):
            if job.get('phase') in ('login', None):
                for _ in range(tokens):
                    self.put('push_tokens', profile_id='id-1', token='t')
            (on_app or (lambda j: None))(job)
        phone = Phone5(self.events, says or {}, app_event, tapped)
        phone.case = case
        return self.case(case, None, phone)[0], phone

    def names(self):
        return [e if isinstance(e, str) else e[0] for e in self.events]

    def matches(self):
        return self.fake.tables['matches']

    def target(self):
        """가설이 만든 방 — 맨 앞은 배치가 돌았다는 증거로 만든 확인용 방(sentinel)이다."""
        return self.matches()[1]

    def aged(self, match):
        """gcloud 를 부르던 순간의 이 방 나이."""
        row = next(m for m in self.at_gcloud if m['id'] == match['id'])
        return datetime.now(timezone.utc) - when(row['created_at'])

    def assertAge(self, match, expected):
        self.assertLess(abs((self.aged(match) - expected).total_seconds()), 60, f'{self.aged(match)} ≠ {expected}')


class ChatGateCommon(Base5):
    """배치를 부르는 8개가 다 같이 지켜야 하는 것 — 시각 관문 · 이번 실행 계정 · 운영 배치 안전."""

    def says_for(self, case):
        return {'E-CHAT-50': {'login': {}, 'tap': {}}}.get(case, {})

    def slip(self):
        """준비가 끝나고(확인용 방까지 만든 뒤) 시각이 정각 직전(14:57)이 된 것처럼 — 폰이 배치 뒤에야 켜지는 가설(55 · 66 · 67)도 같은 자리에서 막는다."""
        real = area3_phone5._sentinel
        return mock.patch.object(area3_phone5, '_sentinel', lambda run: (real(run), self.clock.__setitem__(0, at('14:57')))[0])

    def test_every_case_calls_the_batch_only_through_the_gate_and_never_around_it(self):
        """gcloud(tools.batch) 직접 호출 뮤턴트 — 앱이 로그인한 사이 시각이 정각 직전(14:57)이 되면 관문이 막아야 하고 gcloud 는 0번이다."""
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                with self.slip():
                    result, note = self.go(case, self.says_for(case), tapped=OPENED)[0]
                self.assertEqual(result, 'blocked', note)
                self.assertIn('15:06', note)
                self.assertNotIn('gcloud', self.names())

    def test_a_closed_gate_never_moves_a_match_time(self):
        """시각(created_at)은 관문을 지난 뒤에만 옮긴다 — 막히면 방은 만들어진 그대로(DB 기본 시각)다."""
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                with self.slip():
                    self.go(case, self.says_for(case), tapped=OPENED)
                self.assertTrue(all('created_at' not in m for m in self.fake.tables.get('matches', [])), case)

    def test_the_gate_is_recorded_once_and_gcloud_is_called_once_with_chat_gate(self):
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                self.go(case, self.says_for(case), tapped=OPENED)
                self.assertEqual(self.events.count(('gcloud', 'chat-gate')), 1, case)
                self.assertEqual(len(batch_gate.HISTORY.read_text(encoding='utf-8').splitlines()), 1, case)

    def test_the_time_is_moved_after_the_gate_has_recorded(self):
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                seen = []
                real = area3_phone5._ages
                with mock.patch.object(area3_phone5, '_ages', lambda *a: seen.append(batch_gate.HISTORY.exists()) or real(*a)):
                    self.go(case, self.says_for(case), tapped=OPENED)
                self.assertEqual(seen, [True], case)  # _ages 가 불린 순간 관문 기록이 이미 있다

    def test_a_second_chat_gate_in_the_same_hour_is_blocked_before_any_account_is_made(self):
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                batch_gate.HISTORY.write_text(at('14:10').isoformat() + chr(10), encoding='utf-8')
                result, note = self.go(case, self.says_for(case))[0]
                self.assertEqual(result, 'blocked', case)
                self.assertIn('15:06', note)
                self.assertEqual(self.fake.users, [], case)
                self.assertNotIn('gcloud', self.names())

    def test_a_closed_minute_inside_the_preparation_time_is_blocked_before_any_account_is_made(self):
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                self.clock[0] = at('14:50')  # 준비가 끝날 즈음(14:58)이 정각 −5분 안
                result, note = self.go(case, self.says_for(case))[0]
                self.assertEqual(result, 'blocked', case)
                self.assertIn('8분 뒤', note)
                self.assertEqual(self.fake.users, [], case)

    def test_the_batch_never_touches_accounts_this_run_did_not_make(self):
        """이번 실행이 만든 계정이 아니면 시각 · 상태를 쓰지 않는다(area2._guard) — 가짜로 "낯선 id" 를 만들어 본다."""
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                with mock.patch.object(area2, '_mine', lambda run: set()):
                    result, note = self.go(case, self.says_for(case), tapped=OPENED)[0]
                self.assertEqual(result, 'blocked', case)
                self.assertIn('이번 실행이 만든 계정이 아니라', note)
                self.assertNotIn('gcloud', self.names())

    def test_a_batch_that_never_runs_is_blocked_after_the_wait_not_a_pass(self):
        """확인용 방이 안 닫히면 배치가 안 돈 것이다 — 알림 0건 · 방이 그대로 같은 "안 바뀜" 가설이 헛통과하지 않는다."""
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                self.batch_works = False
                with mock.patch('time.monotonic', side_effect=itertools.count()):
                    result, note = self.go(case, self.says_for(case), tapped=OPENED)[0]
                self.assertEqual(result, 'blocked', case)
                self.assertIn('확인용 방', note)
                self.assertIn('120초', note)

    def test_the_sentinel_room_is_aged_to_be_closed_and_belongs_to_two_accounts_of_this_run(self):
        for case in GATED:
            with self.subTest(case):
                self.setUp()
                self.go(case, self.says_for(case), tapped=OPENED)
                sentinel = self.matches()[0]
                self.assertAge(sentinel, timedelta(hours=48, minutes=5))
                self.assertIsNotNone(sentinel.get('chat_closed_at'), case)
                made = {u['id'] for u in self.fake.users}
                self.assertLessEqual({sentinel['profile_a'], sentinel['profile_b']}, made)
                self.assertFalse({sentinel['profile_a'], sentinel['profile_b']} & {'id-1', 'id-2'})  # 폰 계정 · 상대와 따로

    def test_the_batch_wait_polls_the_database_with_a_cap(self):
        """시나리오 "1~2분 기다린다" — 상한 120초."""
        self.assertEqual(area3_phone5.BATCH_WAIT, 120)


class DaytimeTest(Base5):
    """E-CHAT-50 · 51 · 52 는 낮 10~20시(방해 금지 22~08시를 피함) — notify.require_daytime(08~22)보다 좁다."""

    def test_the_hour_rule_is_ten_to_twenty_not_the_looser_eight_to_twenty_two(self):
        for case in ('E-CHAT-50', 'E-CHAT-51', 'E-CHAT-52'):
            for hhmm in ('09:30', '20:30', '21:30', '23:30'):  # 관문은 열린 분인데 낮이 아닌 시각
                with self.subTest(case=case, at=hhmm):
                    self.setUp()
                    self.clock[0] = at(hhmm)
                    result, note = self.go(case)[0]
                    self.assertEqual(result, 'blocked')
                    self.assertIn('10', note)
                    self.assertIn(hhmm, note)
                    self.assertEqual(self.fake.users, [])  # 준비 전에 막는다
                    self.assertNotIn('gcloud', self.names())

    def test_require_daytime_would_have_let_eight_to_twenty_two_through(self):
        notify.require_daytime(at('21:30'))  # 느슨한 규칙은 통과 — 그래서 따로 둔 함수가 필요하다

    def test_ten_oclock_hour_after_the_closed_minutes_is_open(self):
        self.clock[0] = at('10:06')
        area3_phone5._midday(self.clock[0])
        self.clock[0] = at('19:46')
        area3_phone5._start(daytime=True)  # 준비 8분 뒤 19:54 도 아직 낮 · 관문 열림

    def test_preparation_time_that_crosses_twenty_is_blocked_by_the_hour_rule(self):
        with self.assertRaisesRegex(Blocked, '낮'):
            area3_phone5._midday(at('19:52') + timedelta(minutes=area3_phone5.PREP_MINUTES))

    def test_the_other_cases_do_not_need_daytime(self):
        for case in ('E-CHAT-55', 'E-CHAT-57', 'E-CHAT-65', 'E-CHAT-66', 'E-CHAT-67'):
            with self.subTest(case):
                self.setUp()
                self.clock[0] = at('22:30')  # 낮이 아니어도 관문만 열려 있으면 간다
                result, note = self.go(case, {'login': {}, 'list': {'waited': True, 'rows': []}}, tapped=OPENED)[0]
                self.assertNotIn('낮', note, case)


class Chat50Test(Base5):
    CASE = 'E-CHAT-50'

    def says(self):
        return {'login': {}, 'tap': {}}

    def run50(self, **kw):
        return self.go(self.CASE, self.says(), tapped=kw.pop('tapped', OPENED), **kw)

    def test_pass_path_order_and_what_the_phone_and_the_other_side_do(self):
        (result, note), phone = self.run50()
        self.assertEqual(result, 'pass', note)
        self.assertEqual([n for n in self.names() if n not in ('send',)],
                         ['trust', 'app', 'read', 'kill', 'gcloud', 'wait_new', 'wait_new', 'tell', 'tap', 'result'])
        self.assertEqual(self.events[self.names().index('app')], ('app', {'token_hash': 'h', 'phase': 'login'}))
        self.assertIn(('trust', 'id-2'), self.events)  # A(상대)만 수락해 둔다 — 폰 계정(B)은 아직
        self.assertIn(('gcloud', 'chat-gate'), self.events)
        self.assertIn(('wait_new', True, 60), self.events)
        self.assertIn(('result', 90), self.events)

    def test_the_tap_job_names_the_partner_and_a_message_already_in_the_room(self):
        self.run50()
        tell = next(e[1] for e in self.events if e[0] == 'tell')
        self.assertEqual(tell['phase'], 'tap')
        self.assertEqual(tell['nickname'], self.nick(2))
        self.assertEqual(tell['case'], self.CASE)
        sent = [r for r in self.fake.tables['messages'] if r['body'] == tell['body']]
        self.assertEqual([(r['sender_id'], r.get('kind', 'text')) for r in sent], [('id-2', 'text')])  # 푸시 없이 DB 로 넣은 상대의 글
        self.assertIn(('tap', TITLE), self.events)

    def test_the_room_is_aged_a_day_and_five_minutes_the_sentinel_two_days(self):
        self.run50()
        self.assertAge(self.target(), timedelta(hours=24, minutes=5))
        self.assertAge(self.matches()[0], timedelta(hours=48, minutes=5))

    def test_only_the_partner_accepted_before_the_batch(self):
        self.run50()
        accepted = {p['profile_id'] for p in self.fake.tables['match_participants'] if p.get('trust_response') == 'accept'}
        self.assertEqual(accepted, {'id-2'})

    def test_no_reminder_is_a_fail_and_nothing_is_tapped(self):
        self.ignore = lambda match: match is self.target()  # 배치가 이 방을 못 봄
        (result, note), _ = self.run50()
        self.assertEqual(result, 'fail')
        self.assertIn('0건', note)
        self.assertNotIn('tap', self.names())

    def test_two_reminders_is_a_fail(self):
        twice = [notify.Notice('a', TITLE, BODY, 'c'), notify.Notice('b', TITLE, BODY, 'c')]
        with mock.patch.object(Base5, 'notices', lambda s: twice):
            (result, note), _ = self.run50()
        self.assertEqual(result, 'fail')
        self.assertIn('2건', note)

    def test_the_wrong_words_are_a_fail_and_the_memo_shows_what_came(self):
        with mock.patch.object(Base5, 'notices', lambda s: [notify.Notice('k', '다른 제목', BODY, 'c')]):
            (result, note), _ = self.run50()
        self.assertEqual(result, 'fail')
        self.assertIn('다른 제목', note)

    def test_the_room_must_open_from_the_notification(self):
        for key in ('room', 'nickname', 'message'):
            with self.subTest(key):
                self.setUp()
                (result, note), _ = self.go(self.CASE, self.says(), tapped={**OPENED, key: False})
                self.assertEqual(result, 'fail')
                self.assertIn(key, note)

    def test_an_app_that_never_answers_after_the_tap_is_a_fail(self):
        (result, note), _ = self.go(self.CASE, self.says(), tapped=None)
        self.assertEqual(result, 'fail')
        self.assertIn('시간 안에 답하지 않음', note)

    def test_a_missing_device_token_is_blocked_before_the_app_is_killed_and_before_the_batch(self):
        with mock.patch('time.monotonic', side_effect=itertools.count()):
            (result, note), _ = self.go(self.CASE, self.says(), tokens=0)
        self.assertEqual(result, 'blocked')
        self.assertIn('30초', note)
        self.assertNotIn('kill', self.names())
        self.assertNotIn('gcloud', self.names())

    def test_a_blocked_login_turn_stops_before_the_batch(self):
        (result, _), _ = self.go(self.CASE, {'login': {'result': 'blocked', 'note': '앱 준비 안 됨'}})
        self.assertEqual(result, 'blocked')
        self.assertNotIn('gcloud', self.names())

    def test_a_notification_that_cannot_be_tapped_is_blocked(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            (result, note), _ = self.run50()
        self.assertEqual(result, 'blocked')
        self.assertIn('못 찾음', note)

    def test_permission_is_granted_before_the_app_and_revoked_after(self):
        self.run50()
        self.assertEqual(self.perm, [('grant', 'S'), ('revoke', 'S')])


class NoReminderTest(Base5):
    """E-CHAT-51 · 52 — 리마인드가 안 가야 하는 두 경우. 둘 다 앱은 홈까지만, 알림은 PC 가 지켜본다."""

    def run_case(self, case, **kw):
        return self.go(case, {'login': {}}, **kw)

    def test_51_pass_path_a_room_past_the_reminder_window_gets_nothing(self):
        (result, note), phone = self.run_case('E-CHAT-51')
        self.assertEqual(result, 'pass', note)
        self.assertEqual([n for n in self.names()], ['app', 'read', 'kill', 'gcloud', 'expect_none'])
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'phase': 'login'}])
        self.assertIn(('expect_none', True, 60), self.events)
        self.assertAge(self.target(), timedelta(hours=25, minutes=5))
        self.assertEqual(self.events.count(('trust', 'id-2')), 0)  # 이 줄에는 수락 얘기가 없다

    def test_51_a_reminder_that_comes_anyway_is_a_fail_with_what_came(self):
        self.pushed = ['id-1']
        (result, note), _ = self.run_case('E-CHAT-51')
        self.assertEqual(result, 'fail')
        self.assertIn(TITLE, note)

    def test_52_pass_path_the_switch_is_off_before_the_batch_and_nothing_comes(self):
        (result, note), _ = self.run_case('E-CHAT-52')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.names(), ['switch', 'trust', 'app', 'read', 'kill', 'gcloud', 'expect_none'])
        self.assertIn(('switch', 'id-1', {'trust_reminder': False}), self.events)  # B(폰 계정)의 스위치만
        self.assertAge(self.target(), timedelta(hours=24, minutes=5))  # 51 과 달리 창 안에 있다
        self.assertIn(('trust', 'id-2'), self.events)  # 50 과 같은 준비: A 만 수락

    def test_52_without_the_switch_the_sim_server_would_remind_so_the_check_has_teeth(self):
        with mock.patch.object(area3_phone5.notify_factory, 'switches', lambda *a, **k: None):
            (result, note), _ = self.run_case('E-CHAT-52')
        self.assertEqual(result, 'fail')
        self.assertIn(TITLE, note)

    def test_52_a_failed_switch_call_is_blocked_before_anything_is_started(self):
        self.fake.handlers.insert(0, ('PATCH', re.compile(r'/cards/notification-settings'), Reply(500, {'detail': 'down'})))
        (result, note), _ = self.run_case('E-CHAT-52')
        self.assertEqual(result, 'blocked')
        self.assertIn('알림 스위치', note)
        self.assertNotIn('gcloud', self.names())

    def test_a_missing_device_token_is_blocked(self):
        for case in ('E-CHAT-51', 'E-CHAT-52'):
            with self.subTest(case):
                self.setUp()
                with mock.patch('time.monotonic', side_effect=itertools.count()):
                    (result, note), _ = self.run_case(case, tokens=0)
                self.assertEqual(result, 'blocked')
                self.assertNotIn('gcloud', self.names())


class Chat55Test(Base5):
    CASE = 'E-CHAT-55'
    LIST = {'waited': True, 'rows': []}

    def run55(self, says=None):
        return self.go(self.CASE, {None: says or self.LIST})  # 55 는 한 판뿐이라 일감에 phase 가 없다

    def test_pass_path_closed_ten_messages_stay_and_both_lists_lack_the_room(self):
        (result, note), phone = self.run55()
        self.assertEqual(result, 'pass', note)
        self.assertAge(self.target(), timedelta(hours=48, minutes=5))
        self.assertIsNotNone(self.target().get('chat_closed_at'))
        self.assertEqual(len([m for m in self.fake.tables['messages'] if m['match_id'] == self.target()['id']]), 10)
        self.assertEqual(self.names(), ['gcloud', 'app'])  # 방 준비는 DB · A 의 목록은 API · B 의 목록은 배치 뒤에 앱이
        job = phone.jobs[0]
        self.assertEqual(set(job), {'token_hash', 'control'})  # phase 도 닉네임도 없다 — 앱은 control 방 줄만 기다리고 줄 닉네임을 전부 말한다
        self.assertNotEqual(job['control'], self.nick(2))  # 아직 열린 다른 방 하나 — 목록이 그려졌다는 증거

    def test_a_control_room_stays_open_and_is_a_third_person(self):
        self.run55()
        control = self.matches()[2]
        self.assertIsNone(control.get('chat_closed_at'))
        self.assertNotIn('created_at', control)  # 만든 그대로(지금) — 배치가 건드릴 이유가 없다

    def test_a_room_the_batch_did_not_close_is_a_fail(self):
        self.ignore = lambda match: match is self.target()
        (result, note), _ = self.run55()
        self.assertEqual(result, 'fail')
        self.assertIn('chat_closed_at', note)

    def test_deleted_messages_are_a_fail(self):
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.fake.tables.__setitem__('messages', []))):
            (result, note), _ = self.run55()
        self.assertEqual(result, 'fail')
        self.assertIn('messages', note)

    def test_the_room_still_in_the_other_side_list_is_a_fail(self):
        self.fake.handlers.insert(0, ('GET', re.compile(r'/chat/conversations'),
                                      lambda sent: Reply(200, {'conversations': [{'match_id': self.target()['id']}]})))
        (result, note), _ = self.run55()
        self.assertEqual(result, 'fail')
        self.assertIn('A 목록', note)

    def test_the_room_still_in_the_app_list_is_a_fail(self):
        (result, note), _ = self.run55(lambda job: {'waited': True, 'rows': [self.nick(2)]})
        self.assertEqual(result, 'fail')
        self.assertIn('B 목록', note)

    def test_a_list_that_never_drew_is_blocked_not_a_pass(self):
        (result, note), _ = self.run55({'waited': False, 'rows': []})
        self.assertEqual(result, 'blocked')
        self.assertIn('목록', note)

    def test_the_other_sides_list_is_read_with_the_other_sides_token(self):
        self.run55()
        reads = self.fake.by('GET', '/chat/conversations')
        self.assertEqual([r['auth'] for r in reads], ['tok-2'])


class Chat57Test(Base5):
    CASE = 'E-CHAT-57'

    def says(self, **extra):
        return {None: {'error': GATE_OVER, 'error_now': GATE_OVER, **extra}}

    def run57(self, says=None, on_app=None):
        return self.go(self.CASE, says or self.says(), on_app=on_app)

    def test_pass_path_the_batch_runs_while_the_app_waits_in_the_room(self):
        (result, note), phone = self.run57()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.names(), ['app', 'step', 'gcloud', 'go'])  # 앱이 방을 연 채 멈춘 사이에 배치
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'text': 'E2E-57'}])
        self.assertAge(self.target(), timedelta(hours=48, minutes=5))
        self.assertIsNotNone(self.target().get('chat_closed_at'))

    def test_the_room_is_still_young_when_the_app_opens_it(self):
        """방은 앱이 열 때 만든 그대로(DB 기본 시각)다 — 나이를 옮기는 것은 앱이 멈춘 뒤 관문을 지나서."""
        seen = []
        self.run57(on_app=lambda job: seen.append('created_at' in self.target()))
        self.assertEqual(seen, [False])

    def test_ten_messages_stay_on_a_pass(self):
        (result, _), _ = self.run57()
        self.assertEqual(result, 'pass')
        self.assertEqual(len([m for m in self.fake.tables['messages'] if m['match_id'] == self.target()['id']]), 10)

    def test_a_saved_new_row_is_a_fail(self):
        """앱이 보내기를 눌렀는데 저장돼 버린 서버 — 새 행이 생기면 fail."""
        saved = lambda job: self.put('messages', match_id=self.target()['id'], sender_id='id-1', kind='text', body='E2E-57') or             {'error': GATE_OVER, 'error_now': GATE_OVER}
        (result, note), _ = self.run57({None: saved})
        self.assertEqual(result, 'fail')
        self.assertIn('새 행', note)

    def test_other_words_or_no_words_are_a_fail(self):
        for error in ('종료된 대화예요', None, '네트워크 연결을 확인해 주세요'):
            with self.subTest(error):
                self.setUp()
                (result, note), _ = self.run57(self.says(error=error))
                self.assertEqual(result, 'fail')
                self.assertIn('응답 기한', note)

    def test_the_first_error_counts_even_if_the_last_one_was_cleared(self):
        (result, note), _ = self.run57(self.says(error_now=None))
        self.assertEqual(result, 'pass')
        self.assertIn('지워', note)  # 끝 값이 달라졌음을 메모에 남긴다

    def test_a_room_the_batch_did_not_close_is_a_fail_not_a_pass_of_the_sentence(self):
        self.ignore = lambda match: match is self.target()
        (result, note), _ = self.run57()
        self.assertEqual(result, 'fail')
        self.assertIn('chat_closed_at', note)

    def test_a_closed_gate_blocks_without_running_the_app_to_the_end(self):
        late = lambda job: self.clock.__setitem__(0, at('14:57'))
        (result, note), _ = self.run57(on_app=late)
        self.assertEqual(result, 'blocked')
        self.assertNotIn('go', self.names())  # 앱을 이어 보내지 않는다

    def test_the_phone_account_is_the_one_who_sends_and_the_partner_wrote_the_ten_lines(self):
        self.run57()
        lines = [m for m in self.fake.tables['messages'] if m['match_id'] == self.target()['id']]
        self.assertEqual({m['sender_id'] for m in lines}, {'id-2'})


class Chat65Test(Base5):
    CASE = 'E-CHAT-65'

    def says(self, rows=None):
        return {'login': {}, 'list': lambda job: {'waited': True, 'rows': [self.nick(2)] if rows is None else rows}}

    def run65(self, says=None, **kw):
        return self.go(self.CASE, says or self.says(), **kw)

    def test_pass_path_partner_left_before_the_batch_and_the_room_stays(self):
        (result, note), phone = self.run65()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.names(), ['leave', 'app', 'read', 'kill', 'gcloud', 'expect_none', 'app'])
        self.assertIn(('leave', 'id-2'), self.events)  # A 가 나간다(API) — 폰 계정(B)이 아니다
        self.assertAge(self.target(), timedelta(hours=48, minutes=5))
        self.assertIsNone(self.target().get('chat_closed_at'))
        self.assertEqual([j['phase'] for j in phone.jobs], ['login', 'list'])
        self.assertEqual(set(phone.jobs[1]), {'token_hash', 'phase', 'control'})
        self.assertNotEqual(phone.jobs[1]['control'], self.nick(2))  # 목록이 그려졌다는 증거로 열린 다른 방 하나

    def test_a_closed_room_is_a_fail(self):
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.target().__setitem__('chat_closed_at', 'x'))):
            (result, note), _ = self.run65()
        self.assertEqual(result, 'fail')
        self.assertIn('chat_closed_at', note)

    def test_a_room_row_that_is_gone_is_a_fail_not_a_pass_of_not_closed(self):
        """방 행이 없으면 chat_closed_at 이 null 인지 읽을 수가 없다 — "안 닫혔다" 로 헛통과하면 안 된다."""
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.fake.tables.__setitem__(
                'matches', [m for m in s.matches() if m is not s.target()]))):
            (result, note), _ = self.run65()
        self.assertEqual(result, 'fail', note)
        self.assertIn('matches 행', note)

    def test_a_reminder_is_a_fail(self):
        self.pushed = ['id-1']
        (result, note), _ = self.run65()
        self.assertEqual(result, 'fail')
        self.assertIn(TITLE, note)

    def test_the_room_missing_from_the_list_is_a_fail(self):  # 목록은 그려졌는데(waited) 그 방 줄이 없다
        (result, note), _ = self.run65(self.says(rows=[]))
        self.assertEqual(result, 'fail')
        self.assertIn('목록', note)

    def test_a_list_that_never_drew_is_blocked(self):
        (result, note), _ = self.run65({'login': {}, 'list': {'waited': False, 'rows': []}})
        self.assertEqual(result, 'blocked')

    def test_a_missing_device_token_is_blocked(self):
        with mock.patch('time.monotonic', side_effect=itertools.count()):
            (result, _), _ = self.run65(tokens=0)
        self.assertEqual(result, 'blocked')
        self.assertNotIn('gcloud', self.names())


class Chat66Test(Base5):
    CASE = 'E-CHAT-66'

    def run66(self, card=True, **kw):
        return self.go(self.CASE, {None: {'card': card}}, **kw)

    def test_pass_path_both_accepted_in_the_db_and_the_next_batch_stamps_the_pass(self):
        (result, note), phone = self.run66()
        self.assertEqual(result, 'pass', note)
        self.assertAge(self.target(), timedelta(hours=50))
        self.assertTrue(all(p.get('trust_response') == 'accept' for p in self.parts(self.target()['id'])))
        self.assertIsNotNone(self.target().get('trust_passed_at'))
        self.assertIsNone(self.target().get('chat_closed_at'))
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        self.assertEqual([r['auth'] for r in self.fake.by('GET', f"/chat/matches/{self.target()['id']}")], ['tok-2'])  # A 쪽 화면은 방 머리말의 passed 로

    def test_the_two_acceptances_are_in_before_the_batch_and_the_pass_stamp_is_empty(self):
        seen = []
        real = self.gcloud
        with mock.patch.object(tools, 'batch', lambda name: (seen.append((self.target().get('trust_passed_at'),
                                                                          [p.get('trust_response') for p in self.parts(self.target()['id'])])), real(name))[1]):
            self.run66()
        self.assertEqual(seen, [(None, ['accept', 'accept'])])

    def test_a_missing_pass_stamp_is_a_fail(self):
        self.ignore = lambda match: match is self.target()
        (result, note), _ = self.run66()
        self.assertEqual(result, 'fail')
        self.assertIn('trust_passed_at', note)

    def test_a_closed_room_is_a_fail(self):
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.target().update(chat_closed_at='x', trust_passed_at='y'))):
            (result, note), _ = self.run66()
        self.assertEqual(result, 'fail')
        self.assertIn('chat_closed_at', note)

    def test_no_card_on_the_phone_is_a_fail(self):
        (result, note), _ = self.run66(card=False)
        self.assertEqual(result, 'fail')
        self.assertIn('카드', note)

    def test_the_other_side_not_passed_is_a_fail(self):
        self.fake.handlers.insert(0, ('GET', re.compile(r'/chat/matches/[^/]+'), Reply(200, {'chat_closed_at': None, 'gate': {'passed': False}})))
        (result, note), _ = self.run66()
        self.assertEqual(result, 'fail')
        self.assertIn('A 쪽', note)


class Chat67Test(Base5):
    CASE = 'E-CHAT-67'

    def says(self, seconds=0.5, bubble=True):
        def live(job):
            body = [m for m in self.fake.tables['messages'] if m['sender_id'] == 'id-2'][-1]
            return {'seen_at': (when(body['created_at']) + timedelta(seconds=seconds)).isoformat(), 'bubble': bubble}
        return {None: live}

    def run67(self, says=None):
        return self.go(self.CASE, says or self.says())

    def test_pass_path_a_passed_room_survives_the_batch_and_the_message_shows_in_time(self):
        (result, note), phone = self.run67()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.names(), ['gcloud', 'app', 'step', 'send', 'go'])  # 배치 뒤 앱을 켜고, 앱이 멈춘 사이 A 가 보낸다
        self.assertAge(self.target(), timedelta(hours=72))
        self.assertIsNotNone(self.target().get('trust_passed_at'))
        self.assertIsNone(self.target().get('chat_closed_at'))
        sent = next(e for e in self.events if e[0] == 'send')
        self.assertEqual(sent[1], 'id-2')  # 보내는 쪽 A
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'body': sent[2]}])
        self.assertRegex(sent[2], r'^E2E-67-\w+$')

    def test_a_late_bubble_is_a_fail_at_the_two_second_edge(self):
        for seconds, expected in ((2.0, 'pass'), (2.2, 'fail'), (0.0, 'pass'), (30.0, 'fail')):
            with self.subTest(seconds):
                self.setUp()
                (result, note), _ = self.run67(self.says(seconds=seconds))
                self.assertEqual(result, expected, note)
                if expected == 'fail':
                    self.assertIn('2.0', note)

    def test_a_bubble_that_never_showed_is_a_fail(self):
        (result, note), _ = self.run67({None: {'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'fail')
        self.assertIn('말풍선', note)

    def test_the_fail_note_says_when_the_app_saw_the_message_so_a_late_frame_is_told_from_a_missing_message(self):
        (result, note), _ = self.run67({None: {'seen_at': '2026-10-06T17:07:20+00:00', 'bubble': False}})
        self.assertEqual(result, 'fail')
        self.assertIn('seen_at 2026-10-06T17:07:20+00:00', note)
        self.setUp()  # 두 번째 실행은 깨끗한 가짜 서버에서
        (_, note), _ = self.run67({None: {'seen_at': None, 'bubble': False}})
        self.assertIn('seen_at None', note)

    def test_a_room_the_app_could_not_load_is_blocked_and_nothing_is_sent(self):
        """방 읽기를 못 끝낸 앱은 step 을 부르지 않는다 — 구독 전에 보내면 가짜 실패라 글을 보내지 않고 blocked."""
        (result, note), _ = self.run67({None: {'loaded': False, 'error': '네트워크 오류', 'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'blocked', note)
        self.assertIn('안 읽힘', note)
        self.assertIn('네트워크 오류', note)
        self.assertNotIn('send', self.names())
        self.assertEqual([m for m in self.fake.tables.get('messages', []) if m.get('sender_id') == 'id-2'], [])

    def test_the_bubble_fail_note_carries_the_apps_diagnosis(self):
        (result, note), _ = self.run67({None: {'loaded': True, 'passed': True, 'vm_count': 3, 'vm_bodies': ['뷰모델글'], 'screen_bodies': ['화면글'],
                                               'error': '오류문구', 'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'fail')
        self.assertIn('seen_at None', note)  # 기존 문구는 그대로
        for part in ('loaded True', 'passed True', '글 3건', '뷰모델글', '화면글', '오류문구'):
            self.assertIn(part, note)

    def test_a_passing_bubble_note_has_no_diagnosis(self):
        live = self.says()[None]
        (result, note), _ = self.run67({None: lambda job: {**live(job), 'loaded': True, 'passed': True, 'vm_count': 1, 'vm_bodies': ['x'],
                                                          'screen_bodies': ['x'], 'error': None}})
        self.assertEqual(result, 'pass', note)
        self.assertNotIn('뷰모델', note)

    # ── 채널 측정: 앱이 잰 방 채널 사실 한 구절(area3_b5.dart _RoomChannelWatch) — 통과 · 실패 모두 메모에 ───────────────

    OK_EVENT = {'ms': 350, 'status': 'ok', 'extension': 'postgres_changes', 'message': 'Subscribed to PostgreSQL'}

    def measured(self, seconds=0.5, bubble=True, **channel):
        """말풍선 이야기([says])에 채널 측정 키만 더한 앱 — 키를 안 주면 옛 앱과 같다."""
        live = self.says(seconds=seconds, bubble=bubble)[None]
        return {None: lambda job: {**live(job), **channel}}

    def test_a_passing_note_says_when_the_channel_joined_what_it_was_at_send_and_the_system_events(self):
        (result, note), _ = self.run67(self.measured(joined_ms=420, joined_at_send=True, system_events=[self.OK_EVENT]))
        self.assertEqual(result, 'pass', note)
        self.assertRegex(note, r'^지연 [\d.]+초\(앱 시계 − 서버가 찍은 보낸 시각\)')  # 기존 문구는 그대로 앞에
        for part in ('채널 joined 420ms', '보낼 때 joined=True', 'system 1건(첫 ok 350ms)', 'postgres_changes/ok', 'Subscribed to PostgreSQL'):
            self.assertIn(part, note)

    def test_a_failing_note_carries_the_channel_phrase_whether_the_bubble_never_showed_or_showed_late(self):
        channel = dict(joined_ms=420, joined_at_send=True, system_events=[self.OK_EVENT])
        for label, says in (('안 뜸', self.measured(bubble=False, seen_at=None, **channel)), ('늦게 뜸', self.measured(seconds=30.0, **channel))):
            with self.subTest(label):
                self.setUp()
                (result, note), _ = self.run67(says)
                self.assertEqual(result, 'fail', note)
                for part in ('채널 joined 420ms', '보낼 때 joined=True', 'system 1건(첫 ok 350ms)'):
                    self.assertIn(part, note)

    def test_an_app_that_says_nothing_about_the_channel_leaves_every_note_as_it_was(self):
        (_, passed), _ = self.run67()
        self.setUp()
        (_, failed), _ = self.run67(self.failing())
        for note in (passed, failed):
            self.assertNotIn('채널 joined', note)
            self.assertNotIn('보낼 때 joined', note)
            self.assertNotIn('system', note)

    def test_a_channel_that_was_not_joined_at_send_stands_out_in_both_a_pass_and_a_fail(self):
        for label, says in (('pass', self.measured(joined_ms=3100, joined_at_send=False, system_events=[])),
                            ('fail', self.measured(bubble=False, seen_at=None, joined_ms=3100, joined_at_send=False, system_events=[]))):
            with self.subTest(label):
                self.setUp()
                (_, note), _ = self.run67(says)
                self.assertIn('보낼 때 joined=False', note)

    def test_a_channel_never_seen_joined_and_no_system_events_are_told_plainly(self):
        (_, note), _ = self.run67(self.measured(joined_ms=None, joined_at_send=None, system_events=[]))
        for part in ('채널 joined 못 봄', '보낼 때 joined=None', 'system 0건'):
            self.assertIn(part, note)

    def test_system_events_without_an_ok_say_so_and_keep_each_shape_so_the_next_run_can_learn_it(self):
        events = [{'ms': 200, 'status': 'error', 'extension': 'postgres_changes', 'message': 'bad filter'},
                  {'ms': 640, 'status': 'ok', 'extension': 'system', 'message': 'Replication connection established'}]
        (_, note), _ = self.run67(self.measured(joined_ms=100, joined_at_send=True, system_events=events[:1]))
        self.assertIn('system 1건(ok 없음)', note)
        self.assertIn('200ms postgres_changes/error', note)
        self.setUp()
        (_, note), _ = self.run67(self.measured(joined_ms=100, joined_at_send=True, system_events=events))
        self.assertIn('system 2건(첫 ok 640ms)', note)
        self.assertIn('640ms system/ok', note)

    FLOOR_PHRASE = '하한'

    def test_the_system_event_count_is_told_as_a_lower_bound_whenever_the_app_reported_events(self):
        """앱은 채널을 처음 찾은 관찰에서 system 바인딩을 건다(area3_b5.dart _RoomChannelWatch) — 그 전 이벤트는 못 본다. 건수를 정확한 값으로 읽지 않게 단서를 붙인다."""
        for label, events in (('0건', []), ('1건', [self.OK_EVENT]), ('ok 없음', [{'ms': 200, 'status': 'error', 'extension': 'postgres_changes', 'message': 'bad'}])):
            with self.subTest(label):
                self.setUp()
                (_, note), _ = self.run67(self.measured(joined_ms=100, joined_at_send=True, system_events=events))
                self.assertIn(self.FLOOR_PHRASE, note)
                self.assertIn('채널을 늦게 찾으면 앞 이벤트는 못 봄', note)

    def test_no_lower_bound_phrase_when_the_app_said_nothing_about_system_events_or_the_report_is_malformed(self):
        """앱이 system_events 를 말하지 않았거나 목록이 아니면 건수 자체가 없으니 하한 단서도 없다."""
        for label, says in (('말 안 함', self.measured(joined_ms=100, joined_at_send=True)), ('목록 아님', self.measured(system_events='junk'))):
            with self.subTest(label):
                self.setUp()
                (_, note), _ = self.run67(says)
                self.assertNotIn(self.FLOOR_PHRASE, note)

    def test_a_malformed_channel_report_never_turns_the_result_into_an_error(self):
        for report in ({'joined_ms': 'soon', 'joined_at_send': 'maybe', 'system_events': 'junk'},
                       {'system_events': [None, 7, {'ms': 5}, {'status': 'ok'}]}, {'system_events': None}, {'joined_ms': None}):
            with self.subTest(report):
                self.setUp()
                (result, note), _ = self.run67(self.measured(**report))
                self.assertEqual(result, 'pass', note)

    def test_the_channel_measurements_add_no_server_read_to_a_pass(self):
        """통과 경로의 추가 DB 호출 0 — 채널 측정은 앱이 말한 값만 문장으로 옮긴다."""
        (result, note), _ = self.run67(self.measured(joined_ms=420, joined_at_send=True, system_events=[self.OK_EVENT]))
        self.assertEqual(result, 'pass', note)
        after_send = self.fake.sent[[i for i, s in enumerate(self.fake.sent) if s['path'].endswith('/messages') and s['method'] == 'POST'][-1] + 1:]
        reads = [(s['path'], s['query'].get('select'), s['auth']) for s in after_send if s['path'].startswith('/rest/v1/')]
        self.assertEqual(reads, [('/rest/v1/messages', 'created_at', 'svc')])

    # ── 진단: 말풍선이 안 떴을 때 서버가 가진 사실 · 다시 읽기 해석 ─────────────────────────────────────

    def failing(self, **extra):
        return {None: {'seen_at': None, 'bubble': False, **extra}}

    def reread(self, found, **extra):
        """앱이 방 뷰모델 reconnect() 뒤에 말한 것(area3_b5.dart _batchLiveBubble)."""
        return {'found': found, 'vm_count': 1 if found else 0, 'vm_bodies': ['본문'] if found else [], 'finished': True, 'error': None, **extra}

    def intercept(self, table, respond, when=lambda sent: True):
        """[table] 읽기 중 [when](sent) 인 것만 [respond](sent) 로 바꿔 답한다 — 나머지는 가짜 표 그대로."""
        self.fake.handlers.insert(0, ('GET', re.compile(rf'/rest/v1/{table}'),
                                      lambda sent: respond(sent) if when(sent) else self.fake._table('GET', table, sent)))

    def diagnosis_read(self, select, by_b=False):
        """진단 읽기(select 가 정확히 [select]; [by_b] 면 B 의 토큰, 아니면 서비스 키)만 가리는 조건 — 기존 읽기는 건드리지 않는다."""
        return lambda sent: sent['query'].get('select') == select and (sent['auth'] == 'tok-1') == by_b

    def hide_from_b(self):
        """B 의 토큰(tok-1)으로 messages 를 읽으면 0행 — RLS 가 가린 것처럼. 서비스 키 읽기는 그대로 표에서."""
        self.intercept('messages', lambda sent: Reply(200, []), when=lambda sent: sent['auth'] == 'tok-1')

    def lose_the_row(self):
        """서버가 201 을 주고도 행을 안 남긴 것처럼."""
        self.fake.handlers.insert(0, ('POST', re.compile(r'/chat/matches/[^/]+/messages'), Reply(201, {'id': 'm'})))

    def sent_body(self):
        return next(e for e in self.events if e[0] == 'send')[2]

    MESSAGES, PARTICIPANTS, ROOM = 'id,sender_id,kind,created_at', 'profile_id,left_at,last_read_at', 'created_at,trust_passed_at,chat_closed_at'

    def test_the_bubble_fail_note_carries_the_servers_facts_row_b_token_read_participant_and_room(self):
        (result, note), _ = self.run67(self.failing())
        self.assertEqual(result, 'fail')
        self.assertIn('seen_at None', note)  # 기존 문구는 그대로
        for part in ('서버 진단', 'DB 행 1건', "A 가 보낸 것 1건 · kind ['text']", 'B 토큰으로 읽기 200 · 보이는 행 1건',
                     '참가자 2행 · B left_at None', 'B last_read_at None', '방 created_at', 'trust_passed_at', 'chat_closed_at None'):
            self.assertIn(part, note)
        read = next(s for s in self.fake.sent if s['auth'] == 'tok-1' and s['path'] == '/rest/v1/messages')  # 공개 키 + B 의 토큰(RLS 를 거친다)
        self.assertEqual(read['apikey'], 'anon')
        self.assertEqual(read['query'], {'match_id': f"eq.{self.target()['id']}", 'body': f'eq.{self.sent_body()}', 'select': self.MESSAGES})

    def test_a_row_the_b_token_cannot_see_is_told_apart_from_a_row_that_is_not_there(self):
        self.hide_from_b()
        (_, note), _ = self.run67(self.failing())
        self.assertIn('DB 행 1건', note)
        self.assertIn('B 토큰으로 읽기 200 · 보이는 행 0건', note)

    def test_a_passing_bubble_reads_no_diagnosis_and_keeps_its_note(self):
        (result, note), _ = self.run67()
        self.assertEqual(result, 'pass', note)
        self.assertRegex(note, r'^지연 [\d.]+초\(앱 시계 − 서버가 찍은 보낸 시각\)$')
        after_send = self.fake.sent[[i for i, s in enumerate(self.fake.sent) if s['path'].endswith('/messages') and s['method'] == 'POST'][-1] + 1:]
        reads = [(s['path'], s['query'].get('select'), s['auth']) for s in after_send if s['path'].startswith('/rest/v1/')]
        self.assertEqual(reads, [('/rest/v1/messages', 'created_at', 'svc')])  # 지연을 재는 기존 읽기 하나뿐 — 진단 읽기 0건

    def test_a_diagnosis_read_that_fails_is_told_in_the_note_and_the_fail_stays_a_fail(self):
        for table, select, reply in (('messages', self.MESSAGES, Reply(500, {'message': 'boom'})), ('match_participants', self.PARTICIPANTS, Reply(500, None)),
                                     ('matches', self.ROOM, Reply(503, None))):
            with self.subTest(table):
                self.setUp()
                self.intercept(table, lambda sent, reply=reply: reply, when=self.diagnosis_read(select))
                (result, note), _ = self.run67(self.failing())
                self.assertEqual(result, 'fail', note)  # blocked 로 안 바뀐다
                self.assertIn('읽지 못함', note)
                self.assertIn('B 말풍선', note)
                self.assertIn('서버 진단', note)

    def test_a_b_token_read_the_server_refuses_is_told_with_its_status_and_the_other_facts_still_come(self):
        self.intercept('messages', lambda sent: Reply(401, {'code': '42501'}), when=self.diagnosis_read(self.MESSAGES, by_b=True))
        (result, note), _ = self.run67(self.failing())
        self.assertEqual(result, 'fail', note)
        self.assertIn('B 토큰으로 읽기 읽지 못함(상태 401)', note)
        self.assertIn('DB 행 1건', note)
        self.assertIn('참가자 2행', note)

    def test_a_read_that_drops_the_connection_is_told_by_its_kind_only_and_the_fail_stays_a_fail(self):
        def drop(sent):
            raise ConnectionResetError('https://secret.example/rest/v1/x')  # 예외 글에 주소가 들어도 메모엔 종류만
        self.intercept('match_participants', drop, when=self.diagnosis_read(self.PARTICIPANTS))
        (result, note), _ = self.run67(self.failing())
        self.assertEqual(result, 'fail', note)
        self.assertIn('읽지 못함(ConnectionResetError)', note)
        self.assertNotIn('secret.example', note)

    def test_a_read_that_answers_in_an_unexpected_shape_is_told_not_crashed(self):
        for by_b in (False, True):
            with self.subTest(by_b=by_b):
                self.setUp()
                self.intercept('messages', lambda sent: Reply(200, {'not': 'a list'}), when=self.diagnosis_read(self.MESSAGES, by_b=by_b))
                (result, note), _ = self.run67(self.failing())
                self.assertEqual(result, 'fail', note)
                self.assertIn('읽지 못함', note)

    def test_a_message_the_app_finds_after_reconnecting_is_a_guess_that_only_the_live_channel_missed_it(self):
        (result, note), _ = self.run67(self.failing(after_reconnect=self.reread(True)))
        self.assertEqual(result, 'fail')
        self.assertIn('추정: 다시 읽으면 보임 — 실시간 채널만 글을 못 받음(서버 저장·RLS 는 정상)', note)
        self.assertNotIn('앱이 다시 읽어도 못 가져옴', note)

    def test_a_message_the_app_cannot_find_even_after_reconnecting_with_db_and_b_token_fine_blames_the_app(self):
        (_, note), _ = self.run67(self.failing(after_reconnect=self.reread(False)))
        self.assertIn('추정: DB·RLS 정상인데 앱이 다시 읽어도 못 가져옴', note)
        self.assertNotIn('다시 읽으면 보임', note)

    def test_no_row_in_the_db_after_a_201_is_a_guess_that_the_server_lied(self):
        self.lose_the_row()
        (result, note), _ = self.run67(self.failing(after_reconnect=self.reread(False)))
        self.assertEqual(result, 'fail')
        self.assertIn('DB 행 0건', note)
        self.assertIn('추정: 서버가 201 을 줬는데 행이 없음', note)

    def test_a_row_the_b_token_cannot_see_is_a_guess_about_rls_or_the_participant_row(self):
        self.hide_from_b()
        (_, note), _ = self.run67(self.failing(after_reconnect=self.reread(False)))
        self.assertIn('추정: B 토큰으로 안 읽힘 — RLS/참가자 쪽', note)
        self.assertNotIn('DB·RLS 정상', note)

    def test_a_reconnect_that_did_not_finish_or_ended_in_an_error_cannot_blame_the_app(self):
        for extra in ({'finished': False}, {'error': '네트워크 오류'}):
            with self.subTest(extra):
                self.setUp()
                (_, note), _ = self.run67(self.failing(after_reconnect=self.reread(False, **extra)))
                self.assertIn('추정: 앱의 다시 읽기가 제시간에 안 끝나거나 오류로 끝나 가르지 못함', note)
                self.assertNotIn('DB·RLS 정상', note)

    def test_a_guess_with_a_read_it_could_not_make_does_not_call_the_server_fine(self):
        self.intercept('messages', lambda sent: Reply(500, None), when=self.diagnosis_read(self.MESSAGES))
        (_, note), _ = self.run67(self.failing(after_reconnect=self.reread(True)))
        self.assertIn('읽지 못함', note)
        self.assertNotIn('서버 저장·RLS 는 정상', note)
        self.assertIn('추정: 다시 읽으면 보임', note)

    def test_the_guess_is_set_apart_from_the_facts_and_only_comes_when_the_app_reconnected(self):
        (_, note), _ = self.run67(self.failing())  # 옛 앱 — 다시 읽기를 안 말함
        self.assertIn('서버 진단', note)
        self.assertNotIn('추정', note)

    def test_the_apps_state_before_the_reconnect_and_what_it_found_after_are_in_the_note(self):
        (_, note), _ = self.run67(self.failing(disconnected_before=True, socket_before='open', rt_token_is_session=False,
                                               channels_before=['realtime:messages:m1 joined=false'], after_reconnect=self.reread(True)))
        for part in ('재연결 전 isDisconnected True', '소켓 open', '실시간 토큰이 세션 토큰과 같음 False', 'realtime:messages:m1 joined=false',
                     '재연결 뒤 찾음 True', '뷰모델 글 1건'):
            self.assertIn(part, note)

    def test_a_send_that_fails_is_a_fail_with_the_status(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/chat/matches/[^/]+/messages'), Reply(409, {'detail': '종료된 대화예요'})))
        (result, note), _ = self.run67({None: {'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'fail')
        self.assertIn('409', note)

    def test_a_room_row_that_is_gone_is_a_fail_not_a_pass_of_not_closed(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/chat/matches/[^/]+/messages'), Reply(404, {'detail': '방이 없어요'})))  # 방이 없으면 서버는 404
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.fake.tables.__setitem__(
                'matches', [m for m in s.matches() if m is not s.target()]))):
            (result, note), _ = self.run67({None: {'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'fail', note)
        self.assertIn('matches 행', note)

    def test_a_room_the_batch_closed_is_a_fail(self):
        real = Base5.sim_gate
        with mock.patch.object(Base5, 'sim_gate', lambda s: (real(s), s.target().__setitem__('chat_closed_at', 'x'))):
            (result, note), _ = self.run67({None: {'seen_at': None, 'bubble': False}})
        self.assertEqual(result, 'fail')
        self.assertIn('chat_closed_at', note)

    def test_a_negative_delay_from_clock_skew_is_noted_not_failed(self):
        (result, note), _ = self.run67(self.says(seconds=-0.8))
        self.assertEqual(result, 'pass')
        self.assertIn('시계 차', note)


class Chat69Test(Base5):
    """API 가설 — 폰 없음. 정리 배치(cleanup)는 관문의 04:00 ±5분만 본다."""
    CASE = 'E-CHAT-69'

    def setUp(self):
        super().setUp()
        for pid in ('id-1', 'id-2'):
            self.put('profiles', id=pid)

    def run69(self):
        return area3_phone5.attempt(self.run_, self.CASE)

    def test_pass_path_the_withdrawn_account_goes_and_takes_the_room_and_messages(self):
        result, note = self.run69()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.events.count(('gcloud', 'cleanup')), 1)
        self.assertEqual([r['id'] for r in self.fake.tables['profiles']], ['id-1'])  # 탈퇴한 상대(id-2)만 사라지고 산 계정은 남는다
        self.assertEqual(self.fake.tables['matches'], [])
        self.assertEqual(self.fake.tables['messages'], [])
        self.assertEqual([u['id'] for u in self.fake.users], ['id-1'])

    def test_only_the_partner_is_withdrawn_and_31_days_back_and_in_one_patch(self):
        self.run69()
        patches = [s for s in self.fake.by('PATCH', '/rest/v1/profiles') if 'withdrawn_at' in s['body']]
        self.assertEqual([p['query']['id'] for p in patches], ['eq.id-2'])
        body = patches[0]['body']
        self.assertEqual(body['status'], 'withdrawn')
        self.assertLess(abs((datetime.now(timezone.utc) - when(body['withdrawn_at'])).total_seconds() - 31 * 86400), 60)

    def test_the_room_has_messages_from_both_sides_before_the_batch(self):
        seen = []
        real = self.gcloud
        with mock.patch.object(tools, 'batch', lambda name: (seen.append(sorted({m['sender_id'] for m in self.fake.tables['messages']})), real(name))[1]):
            self.run69()
        self.assertEqual(seen, [['id-1', 'id-2']])

    def test_a_surviving_room_or_message_is_a_fail(self):
        for table in ('matches', 'messages'):
            with self.subTest(table):
                self.setUp()
                real = Base5.sim_cleanup
                keep = {}
                def leaky(s):
                    keep['rows'] = list(s.fake.tables[table])
                    real(s)
                    s.fake.tables[table] = keep['rows']
                with mock.patch.object(Base5, 'sim_cleanup', leaky):
                    result, note = self.run69()
                self.assertEqual(result, 'fail', note)
                self.assertIn(table, note)

    def test_a_deleted_living_account_is_a_fail(self):
        with mock.patch.object(Base5, 'sim_cleanup', lambda s: s.fake.users.clear() or s.fake.tables['profiles'].clear()):
            result, note = self.run69()
        self.assertEqual(result, 'fail')
        self.assertIn('산 계정', note)

    def test_a_user_that_stays_is_blocked_after_the_wait(self):
        self.batch_works = False
        with mock.patch('time.monotonic', side_effect=itertools.count()):
            result, note = self.run69()
        self.assertEqual(result, 'blocked')
        self.assertIn('120초', note)

    def test_a_row_left_in_profiles_with_the_user_gone_is_a_fail(self):
        real = Base5.sim_cleanup
        def half(s):
            gone = [p for p in s.fake.tables['profiles'] if p['id'] == 'id-2']
            real(s)
            s.fake.tables['profiles'] += gone
        with mock.patch.object(Base5, 'sim_cleanup', half):
            result, note = self.run69()
        self.assertEqual(result, 'fail')
        self.assertIn('profiles', note)

    def test_the_cleanup_gate_is_the_four_oclock_five_minutes(self):
        for hhmm in ('03:56', '04:00', '04:05'):
            with self.subTest(hhmm):
                self.setUp()
                self.clock[0] = at(hhmm)
                result, note = self.run69()
                self.assertEqual(result, 'blocked')
                self.assertIn('04:06', note)
                self.assertEqual(self.fake.users, [])  # 준비 전에 막는다
                self.assertNotIn('gcloud', self.names())

    def test_a_closed_minute_in_the_middle_of_the_preparation_is_blocked_by_the_gate_itself(self):
        real = area3_phone5._withdraw

        def slow(*args):
            self.clock[0] = at('04:00')
            return real(*args)
        with mock.patch.object(area3_phone5, '_withdraw', slow):
            result, note = self.run69()
        self.assertEqual(result, 'blocked')
        self.assertNotIn('gcloud', self.names())  # 관문을 거치지 않고는 gcloud 로 안 간다

    def test_no_daytime_rule_for_cleanup(self):
        self.clock[0] = at('23:30')
        self.assertEqual(self.run69()[0], 'pass')

    def test_the_guard_stops_a_stranger_account(self):
        with mock.patch.object(area2, '_mine', lambda run: set()):
            result, note = self.run69()
        self.assertEqual(result, 'blocked')
        self.assertIn('이번 실행이 만든 계정이 아니라', note)
        self.assertNotIn('gcloud', self.names())


class NoRerunTest(Base5):
    """진행 프로그램(run_case)은 fail 이면 같은 가설을 한 번 더 돈다 — 그런데 chat-gate 는 같은 시에 한 번뿐이라, 다시 돌린 쪽이 관문에 막혀 blocked 가 되고
    첫 fail 이 덮인다. 그래서 배치를 부른 뒤의 fail 은 기억해 두고 다시는 안 돈다(배치 전의 fail · blocked 는 그대로 다시 돈다)."""

    def phone(self, says=None):
        """가설을 두 번 부를 수 있는 폰 — 앱이 켜질 때마다 지금까지 만든 계정 모두의 기기 토큰이 올라온 것으로 친다."""
        return Phone5(self.events, says or {'login': {}}, lambda job: [self.put('push_tokens', profile_id=u['id'], token='t') for u in self.fake.users])

    def test_a_fail_after_the_batch_is_not_run_again(self):
        self.pushed = ['id-1']  # 리마인드가 와 버리는 서버 — 51 이 fail
        phone = self.phone()
        first = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        users = len(self.fake.users)
        second = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second, first)  # 같은 결과를 그대로 — 관문 blocked 로 덮이지 않는다
        self.assertEqual(self.events.count(('gcloud', 'chat-gate')), 1)
        self.assertEqual(len(phone.jobs), 1)  # 두 번째 판은 앱도 안 켠다
        self.assertEqual(len(self.fake.users), users)  # 계정도 안 만든다

    def test_the_second_run_would_have_been_blocked_by_the_gate_without_it(self):
        """이 안전망이 없을 때의 모습 — 같은 시 두 번째 chat-gate 는 관문이 막는다(기록이 남아 있으므로)."""
        self.pushed = ['id-1']
        phone = self.phone()
        area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        area3_phone5._FAILED.clear()
        again = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(again[0], 'blocked')
        self.assertIn('15:06', again[1])

    def test_a_fail_before_the_batch_is_run_again(self):
        phone = self.phone({'login': {'result': 'fail', 'note': '홈 안 나옴'}})
        first = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(first[0], 'fail')
        self.assertNotIn('gcloud', self.names())
        phone.says['login'] = {}  # 다시 돌리면 이번엔 홈에 닿는다
        second = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(second[0], 'pass', second[1])

    def test_a_blocked_gate_is_run_again(self):
        slip = mock.patch.object(area3_phone5, '_sentinel', lambda run: self.clock.__setitem__(0, at('14:57')) or area3._pair(run))
        phone = self.phone()
        with slip:
            first = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(first[0], 'blocked')
        self.clock[0] = at('14:20')
        second = area1.attempt_phone(self.run_, 'E-CHAT-51', phone)
        self.assertEqual(second[0], 'pass', second[1])
        self.assertEqual(self.events.count(('gcloud', 'chat-gate')), 1)

    def test_the_cleanup_case_is_not_run_again_either(self):
        for pid in ('id-1', 'id-2'):
            self.put('profiles', id=pid)
        real = Base5.sim_cleanup

        def leaky(s):  # 방을 못 지우는 서버 — cascade 가 안 된다
            kept = list(s.fake.tables['matches'])
            real(s)
            s.fake.tables['matches'] = kept
        with mock.patch.object(Base5, 'sim_cleanup', leaky):
            first = area3_phone5.attempt(self.run_, 'E-CHAT-69')
        self.assertEqual(first[0], 'fail')
        second = area3_phone5.attempt(self.run_, 'E-CHAT-69')
        self.assertEqual(second, first)
        self.assertEqual(self.events.count(('gcloud', 'cleanup')), 1)

    def test_a_phone_case_gets_a_longer_limit_than_the_default_four_twenty(self):
        """기본 상한 420초는 배치 기다림(120 + 20)에 알림(60 + 10) · 눌러 열기(90) · 계정 준비를 더하면 모자란다 — blocked(시간 초과)로 잘못 끝난다."""
        worst = (area3_phone5.BATCH_WAIT + area3_phone5.SETTLE + area3_phone5.NOTICE_WAIT + area3_phone5.WATCH_MORE + area3_phone5.TOKEN_WAIT
                 + area3_phone5.APP_WAIT)
        self.assertGreater(tools.CASE_LIMIT, 0)
        for case in GATED:
            self.assertGreaterEqual(tools.CASE_LIMITS[case], worst + 300, case)
        self.assertNotIn('E-CHAT-69', tools.CASE_LIMITS)  # 폰이 아니라 상한을 안 건다(API 가설)


# ── 등록부 · 안전망 ──────────────────────────────────────────────────────────────────────────────────

class RegistryTest(Base5):
    """이 시험 모듈이 area3_phone5 를 직접 import 하므로 __main__ 의 import 가 빠져도 BUNDLES 는 차 보인다 —
    그래서 __main__.py 원문과 Dart 원문을 직접 읽어 등록 줄을 본다(형제 RegistryTest 와 같은 방법)."""

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundle_is_the_nine_cases_eight_on_the_phone_and_one_api(self):
        self.assertEqual(area3.BUNDLES['area3-phone-5'], BUNDLE)
        self.assertEqual(list(area3_phone5.PHONE5), GATED)
        self.assertEqual(list(area3_phone5.CASES), ['E-CHAT-69'])
        self.assertLessEqual(set(GATED), set(area1.PHONE))
        self.assertFalse(set(area3_phone5.CASES) & set(area1.PHONE))
        self.assertFalse(set(BUNDLE) & set(area3.CASES))  # 영역 3 API 묶음(area3-api)과 안 겹친다 — 다른 시험이 area3.CASES 를 센다

    def test_main_imports_the_module_and_runs_the_bundle(self):
        from e2e import __main__ as main
        self.assertRegex((tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'), r'(?m)^from e2e import area3_phone5\b')  # 주석 처리된 줄은 안 센다
        self.assertEqual(main.BUNDLES['area3-phone-5'], BUNDLE)
        self.assertTrue(set(GATED) <= set(area1.PHONE) and not set(GATED) & set(main.API_CASES))
        self.assertIs(main.API_CASES['E-CHAT-69'], area3_phone5)  # API 가설은 자기 모듈의 attempt 로
        self.assertEqual(main.BUNDLES['area3-api'], area3.BUNDLES['area3-api'])  # 앞 묶음은 그대로

    def test_main_registers_the_api_case_after_the_dicts_it_extends(self):
        text = (tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8')
        self.assertRegex(text, r'(?m)^API_CASES\.update\(\{c: area3_phone5 for c in area3_phone5\.CASES\}\)')
        self.assertLess(text.index('\nAPI_CASES = '), text.index('API_CASES.update('))

    def test_the_numbers_do_not_collide_with_the_other_bundles(self):
        for name, bundle in area3.BUNDLES.items():
            if name != 'area3-phone-5':
                self.assertFalse(set(bundle) & set(BUNDLE), name)

    def test_the_app_part_is_declared_and_merged_into_the_case_map_like_its_siblings(self):
        part = self.dart('area3_b5.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), GATED)
        main = self.dart('area3.dart')
        self.assertRegex(main, r"(?m)^part 'area3_b5\.dart';")  # 주석 처리된 줄은 안 센다
        merge = re.search(r'(?m)^  \.\.\.area3Cases5,', main)  # area3Cases 맵 끝에서 합친다(area3Cases3 · area3CasesSafe 와 같다)
        self.assertTrue(merge, '...area3Cases5, 줄이 없거나 주석 처리됨')
        self.assertLess(re.search(r'(?m)^  \.\.\.area3CasesSafe,', main).start(), merge.start())
        self.assertLess(re.search(r'(?m)^  \.\.\.area3Cases3,', main).start(), merge.start())
        self.assertNotIn('area3Cases5', self.dart('e2e_test.dart'))  # e2e_test.dart 는 area3Cases 하나만 펼친다

    def test_the_app_reads_the_phases_and_keys_the_pc_sends(self):
        dart = self.dart('area3_b5.dart')
        sent = {}
        for case in GATED:
            self.setUp()
            self.events.clear()
            self.go(case, {'login': {}, 'tap': {}, 'list': {'waited': True, 'rows': []}, None: {'seen_at': None}}, tapped=OPENED)
            jobs = [e[1] for e in self.events if e[0] in ('app', 'tell')]
            sent[case] = {key for job in jobs for key in job} - {'case'}
            for job in jobs:
                if 'phase' in job:
                    self.assertIn(f"'{job['phase']}' =>", dart, (case, job))
        for key in set().union(*sent.values()) - {'phase', 'token_hash'}:
            self.assertIn(f"job['{key}']", dart, key)  # 앱이 읽지 않는 키를 PC 가 보내지 않는다
        self.assertIn("job['phase']", dart)

    def test_the_app_says_the_keys_the_pc_reads(self):
        dart = self.dart('area3_b5.dart')
        for key in ('waited', 'rows', 'error', 'error_now', 'card', 'seen_at', 'bubble'):
            self.assertIn(f"'{key}':", dart, key)

    def test_the_tap_phase_reuses_the_siblings_room_check_and_the_names_exist(self):
        dart = self.dart('area3_b5.dart')
        sibling = self.dart('area3_b3.dart')
        for name in ('_openedByNotification', '_homeAfterLogin'):
            self.assertIn(name, dart, name)
            self.assertIn(f'Future<Map<String, Object?>?> {name}(', sibling, name)  # 형제가 정의한 그 이름이다
        for name in ('_chatField', '_sendButton', '_openRoom', '_toConversations', '_row'):
            self.assertRegex(self.dart('area3.dart') + self.dart('area3_b2.dart'), rf'\b{name}\b', name)

    def test_the_private_names_of_the_part_do_not_clash_with_the_siblings(self):
        """같은 라이브러리의 part 들은 비공개 이름을 같이 쓴다 — 이 파트가 새로 정의한 이름이 다른 파트와 겹치면 컴파일이 깨진다."""
        def defs(text):  # 들여쓰기 없는 줄 = 맨 바깥 정의
            return set(re.findall(r'(?m)^(?:const |final )?(?:[A-Za-z][\w<>?, ]*? )?(_?[A-Za-z]\w*)\s*(?:=|\()', text))
        mine = defs(self.dart('area3_b5.dart')) - {'part'}
        self.assertIn('_batchListRows', mine)
        self.assertIn('area3Cases5', mine)
        for sibling in ('area3.dart', 'area3_b2.dart', 'area3_b3.dart', 'area3_safe.dart', 'area1.dart', 'support.dart'):
            self.assertEqual(mine & defs(self.dart(sibling)), set(), sibling)


if __name__ == '__main__':
    unittest.main()
