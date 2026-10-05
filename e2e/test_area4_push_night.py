"""영역 4 PUSH 밤·아침·시각 경계 13개(area4_push_night.py)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 알림창 · 가짜 시계로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_night`.

가짜 서버 [NightWorld] 는 영역 2 시각 시험의 [World] 위에 backend/app/cards/push.py 의 규칙(스위치 → 조용한 시간 → 보관/버림, 아침 묶음)을
옮겨 얹었다. 시계는 시험이 쥔 [Clock] 하나이고 `time.sleep` 과 알림 기다리기가 그 시계를 앞으로 보낸다 — 그래서 21:59:20 까지 기다리기 같은
시각 논리가 실제로 돈다. 표 열 이름은 운영처럼 검사한다(없는 열이면 400).
기대 문구는 시험 쪽에 따로 적었다(backend 의 router.py · push.py 에서 옮김) — 가설 코드가 읽는 상수와 같은 곳에서 가져오지 않는다.
"""

import inspect
import itertools
import json
import tempfile
import time
import unittest
from datetime import timedelta
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area3_phone, area4_push, area4_push_night as night, batch_gate, notify, tools
from e2e import test_area2_time_device as base
from e2e.test_area2_time_device import MON, TUE, WED, DeviceBase, seoul
from e2e.tools import Blocked, Reply

ACCEPT = '나를 수락한 사람이 있어요'
MATCH = '매칭됐어요!'
PUBLIC = '카카오톡 아이디를 주고받았어요'
REVIEW = '새 지인 리뷰가 도착했어요'
FRIEND = '친구가 가입했어요'
TRUST = '카카오톡 아이디·실사진 공개를 수락했어요'
ME, PARTNER, THIRD = 'Mina', 'Jiho', 'Nick3'  # 계정을 만드는 차례 — 받는 사람(id-1) · 상대(id-2) · 세 번째(id-3)
TUESDAY = '2026-10-06'

EXEMPT = {'card_arrived', 'new_message'}
DEFERRED = {'acceptance_received', 'match_made', 'new_friend_review', 'verification_result'}
BUNDLES = {  # backend/app/cards/push.py _BUNDLES
    ('acceptance_received', 'acceptances'): (ACCEPT, '밤사이 {n}명이 나를 수락했어요'),
    ('match_made', 'match'): (MATCH, '밤사이 {n}명과 매칭됐어요'),
    ('match_made', 'chat'): (PUBLIC, '밤사이 {n}명과 프로필이 공개됐어요'),
    ('new_friend_review', 'friend_reviews'): (REVIEW, '밤사이 리뷰 {n}개가 도착했어요'),
}
EXTRA_COLUMNS = {  # supabase/migrations 에서 옮긴 열 목록(시각 시험 World 가 모르는 표)
    'matches': {'id', 'profile_a', 'profile_b', 'created_at', 'trust_passed_at', 'chat_closed_at'},  # 20260920160544
    'match_participants': {'match_id', 'profile_id', 'trust_response', 'responded_at', 'left_at', 'last_read_at'},
    'friend_reviews': {'id', 'reviewer_id', 'reviewee_id', 'tags', 'comment', 'status', 'created_at'},  # 20260928040000
    'referrals': {'referee_id', 'referrer_id', 'created_at', 'rewarded_at'},  # 20260928010000
    'profiles': base.COLUMNS['profiles'] | {'referral_code'},
}
BODY_CHECKED = {'pending_pushes', 'matches', 'match_participants', 'referrals'}


class NightWorld(base.World):
    """시각 시험 World + 밤 보관·아침 묶음이 있는 알림 서버. 시계는 [clock].now, 시간 보내기는 [tick](초)."""

    def __init__(self, clock, tick):
        super().__init__()
        self.clock, self.tick = clock, tick
        self.token_owner, self.nicknames, self.decided_at, self.row_ids = {}, {}, [], itertools.count(1)
        self.scheduled_runs = False  # 참이면 시계가 정각을 넘을 때마다 Cloud Scheduler 의 chat-gate 가 돈다
        self.ignore_quiet = False  # 결함 흉내: 조용한 시간을 안 봄
        self.ignore_switches = False  # 결함 흉내: 보낼 때 스위치를 다시 안 봄
        self.never_defer = False  # 결함 흉내: 보관하지 않고 버림
        self.hold_always = False  # 결함 흉내: 방해 금지를 꺼도 보관함
        self.drop_messages = False  # 결함 흉내: 메시지를 저장만 하고 알림은 안 보냄
        self.decide_takes = 0  # 수락 요청 하나가 걸리는 초
        for method, pattern, reply in (
            ('POST', r'/cards/acceptances/[^/]+', self.accept_back), ('POST', r'/chat/matches/[^/]+/messages', self.message),
            ('POST', r'/chat/matches/[^/]+/trust', self.trust), ('POST', r'/friend-reviews', self.review),
            ('POST', r'/referral/redeem', self.redeem), ('POST', r'/profile-onboarding/basic-info', self.basic_info),
        ):
            self.on(method, pattern, reply)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        reply = super().__call__(method, url, headers, body, raw, **options)
        if urlsplit(url).path == '/auth/v1/verify' and reply.status == 200:  # 토큰 번호 = 계정 번호가 아니다(아침에 다시 로그인한다)
            email = body['token_hash'][2:]
            self.token_owner[reply.body['access_token']] = next(u['id'] for u in self.users if u['email'] == email)
        return reply

    def owner_of(self, sent):
        return self.token_owner[sent['auth']]

    def nick(self, pid):
        return self.nicknames.get(pid, f'닉{pid}')

    def _table(self, method, name, sent):
        reply = super()._table(method, name, sent)
        if name == 'profiles' and method == 'GET' and reply.status == 200:
            for row in reply.body:
                row.update(nickname=self.nick(row['id']), referral_code=f"CODE{row['id'][3:]}")
        return reply

    def basic_info(self, sent):
        self.nicknames[self.owner_of(sent)] = sent['body']['nickname']
        return Reply(200, None)

    # 서버의 알림 관문(push.py notify)
    def quiet(self):
        return self.clock.now.hour >= 22 or self.clock.now.hour < 8

    def push(self, target, kind, title, body, data, defer=True):
        config = {**base.SETTINGS, **self.settings.get(target, {})}
        if not self.ignore_switches and not config.get(kind, True):
            return
        if (config['quiet_hours'] or self.hold_always) and kind not in EXEMPT and self.quiet() and not self.ignore_quiet:
            if defer and kind in DEFERRED and not self.never_defer:
                self.tables.setdefault('pending_pushes', []).append({
                    'id': f'p{next(self.row_ids)}', 'profile_id': target, 'kind': kind, 'title': title, 'body': body, 'data': data,
                    'created_at': self.clock.now.isoformat()})
            return
        if self.permitted() and any(t['profile_id'] == target for t in self.tables.get('push_tokens', [])):
            self.post(title, body)

    def chat_gate(self):
        """매시 chat-gate — 양쪽 수락 도장 + 조용하지 않은 시각이면 보관함 비우기(묶음 · 한 건씩)."""
        for match in self.tables.get('matches', []):
            mine = [p for p in self.tables.get('match_participants', []) if p['match_id'] == match['id']]
            if not match.get('trust_passed_at') and len(mine) == 2 and all(p.get('trust_response') == 'accept' for p in mine):
                match['trust_passed_at'] = self.clock.now.isoformat()
        if self.quiet() and not self.ignore_quiet:
            return
        groups = {}
        for row in self.tables.get('pending_pushes', []):
            groups.setdefault((row['profile_id'], row['kind'], row['data'].get('route')), []).append(row)
        for (profile, kind, route), rows in groups.items():
            if len(rows) > 1 and (kind, route) in BUNDLES:
                title, text = BUNDLES[(kind, route)]
                pushes = [(kind, title, text.format(n=len(rows)), {'route': route})]
            else:
                pushes = [(r['kind'], r['title'], r['body'], r['data']) for r in rows]
            for pushed in pushes:
                self.push(profile, *pushed)
            gone = {r['id'] for r in rows}
            self.tables['pending_pushes'] = [r for r in self.tables['pending_pushes'] if r['id'] not in gone]

    # 카드 · 매칭
    def decide(self, sent):
        card = next(c for c in self.tables['daily_cards'] if c['id'] == sent['path'].split('/')[2])
        if sent['body']['decision'] == 'accept':
            self.decided_at.append(self.clock.now)
            self.push(card['target_id'], 'acceptance_received', ACCEPT, f"{self.nick(card['owner_id'])} 님이 대화를 하고 싶어 해요",
                      {'route': 'acceptances', 'card_id': card['id']})
        if self.decide_takes:
            self.tick(self.decide_takes)
        return Reply(200, {'ok': True})

    def accept_back(self, sent):
        card = next(c for c in self.tables['daily_cards'] if c['id'] == sent['path'].rsplit('/', 1)[1])
        me, owner = self.owner_of(sent), card['owner_id']
        if sent['body']['decision'] != 'accept':
            return Reply(200, {'matched': False})
        low, high = sorted((owner, me))
        match_id = f"m{len(self.tables.get('matches', [])) + 1}"
        self.tables.setdefault('matches', []).append({'id': match_id, 'profile_a': low, 'profile_b': high, 'trust_passed_at': None})
        self.tables.setdefault('match_participants', []).extend({'match_id': match_id, 'profile_id': p} for p in (low, high))
        data = {'route': 'match', 'match_id': match_id}
        self.push(owner, 'match_made', MATCH, f'{self.nick(me)} 님도 수락했어요', data)
        self.push(me, 'match_made', MATCH, f'{self.nick(owner)} 님과 대화를 시작해 보세요', data, defer=False)  # 방금 누른 쪽은 보관 없이 버림
        return Reply(200, {'matched': True, 'match_id': match_id})

    # 채팅 · 신뢰
    def other(self, match_id, me):
        match = next(m for m in self.tables['matches'] if m['id'] == match_id)
        return match['profile_b'] if match['profile_a'] == me else match['profile_a']

    def message(self, sent):
        me, match_id = self.owner_of(sent), sent['path'].split('/')[3]
        if not self.drop_messages:
            self.push(self.other(match_id, me), 'new_message', self.nick(me), sent['body']['body'], {'route': 'chat', 'match_id': match_id})
        return Reply(201, {'id': 'x'})

    def trust(self, sent):
        me, match_id = self.owner_of(sent), sent['path'].split('/')[3]
        other = self.other(match_id, me)
        parts = {p['profile_id']: p for p in self.tables['match_participants'] if p['match_id'] == match_id}
        parts[me]['trust_response'] = 'accept'
        self.push(other, 'new_message', self.nick(me), TRUST, {'route': 'chat', 'match_id': match_id})
        if parts[other].get('trust_response') != 'accept':
            return Reply(200, {'passed': False})
        next(m for m in self.tables['matches'] if m['id'] == match_id)['trust_passed_at'] = self.clock.now.isoformat()
        data = {'route': 'chat', 'match_id': match_id}
        self.push(other, 'match_made', PUBLIC, f'{self.nick(me)} 님의 프로필이 공개됐어요', data)
        self.push(me, 'match_made', PUBLIC, f'{self.nick(other)} 님의 프로필이 공개됐어요', data, defer=False)
        return Reply(200, {'passed': True, 'kakao_id': 'k'})

    # 지인 리뷰 · 추천
    def review(self, sent):
        me, target = self.owner_of(sent), sent['body']['reviewee_id']
        linked = any({r['referee_id'], r['referrer_id']} == {me, target} for r in self.tables.get('referrals', []))
        if not linked:
            return Reply(404, {'detail': '프로필을 찾을 수 없어요'})
        self.tables.setdefault('friend_reviews', []).append({'id': f'r{next(self.row_ids)}', 'reviewer_id': me, 'reviewee_id': target})
        self.push(target, 'new_friend_review', REVIEW, f'{self.nick(me)} 님이 리뷰를 남겼어요', {'route': 'friend_reviews'})
        return Reply(201, {'id': 'r'})

    def redeem(self, sent):
        me, referrer = self.owner_of(sent), 'id-' + sent['body']['code'].removeprefix('CODE')
        self.tables.setdefault('referrals', []).append({'referee_id': me, 'referrer_id': referrer})
        self.push(referrer, 'new_friend_review', FRIEND, f'{self.nick(me)} 님이 가입했어요, 리뷰를 남겨 주세요',
                  {'route': 'friend_review_write', 'profile_id': me})
        return Reply(200, {'referrer_id': referrer})


class NightBase(DeviceBase):
    """밤 22:30 에서 시작하는 가짜 세계. 시계는 `time.sleep` · 알림 기다리기로만 앞으로 간다."""

    START = TUE(22, 30)

    def setUp(self):
        super().setUp()
        self.names = itertools.chain([ME, PARTNER], (f'Nick{i}' for i in itertools.count(3)))
        history = Path(tempfile.mkdtemp()) / 'runs.jsonl'  # 진짜 chat-gate 호출 기록(임시 폴더)이 시험에 섞이지 않게
        patcher = mock.patch.object(batch_gate, 'HISTORY', history)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.history = history
        self.world = NightWorld(self.clock, self.tick)
        self.world.permitted = lambda: self.granted
        self.batch_times = []
        for patcher in (
            mock.patch.object(tools, 'call', self.world), mock.patch.object(area1, '_nickname', lambda: next(self.names)),
            mock.patch.object(time, 'sleep', self.tick), mock.patch.dict(base.COLUMNS, EXTRA_COLUMNS),
            mock.patch.object(base, 'BODY_CHECKED', base.BODY_CHECKED | BODY_CHECKED),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.scripts['chat-gate'] = self.world.chat_gate

    def tick(self, seconds):
        before = self.clock.now
        self.clock.now += timedelta(seconds=seconds)
        if self.world.scheduled_runs:
            top = before.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
            while top <= self.clock.now:
                self.world.chat_gate()
                top += timedelta(hours=1)

    def batch(self, name):
        self.batch_times.append(self.clock.now)
        self.world.sent.append({'method': 'BATCH', 'path': name, 'query': {}, 'body': None, 'auth': '', 'apikey': None})
        super().batch(name)

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        self.windows.append(('new', seconds))
        self.tick(2)
        if not self.fresh(before):
            self.tick(max(0, seconds - 2))
        return self.fresh(before)

    def expect_none(self, serial, before, seconds=0):
        self.windows.append(('none', seconds))
        self.tick(seconds)
        return self.fresh(before)

    # 시험 도우미
    def state(self, number):
        return json.loads((self.run.out / f'night_{number}.json').read_text(encoding='utf-8'))

    def pending(self, owner=None):
        return [r for r in self.world.tables.get('pending_pushes', []) if owner in (None, r['profile_id'])]

    def case(self, number, now=None, phone=None):
        if now:
            self.clock.now = now
        phone = phone or self.phone()
        return self.go(f'E-PUSH-{number}', phone), phone

    def arrived(self, since, titles):
        """[since] 번째 알림 뒤에 알림창에 뜬 것 중 제목이 [titles] 인 (제목, 본문) 들."""
        return sorted((n.title, n.text) for n in self.world.shade[since:] if n.title in titles)


# ── 시각 창(순수 함수) ──────────────────────────────────────────────────────────────────────────────

class WindowTest(unittest.TestCase):
    def test_the_morning_window_is_minute_06_to_48_of_every_hour_from_08_to_21(self):
        for now in (WED(8, 6), WED(8, 48, 59), WED(9, 6), WED(14, 30), WED(21, 6), WED(21, 48, 59)):
            self.assertIsNone(night.morning_refusal(now), now)

    def test_just_outside_the_morning_window_names_the_next_open_minute(self):
        shut = {WED(8, 5, 59): '08:06', WED(8, 49): '09:06', WED(9, 0): '09:06', WED(9, 55): '10:06', WED(7, 59): '08:06',
                WED(0, 30): '08:06', WED(21, 49): '목요일 08:06', WED(23, 0): '목요일 08:06'}
        for now, when in shut.items():
            self.assertEqual(night.morning_refusal(now), f'지금은 실행 금지 시간 — {when} 에 다시', now)

    def test_the_seven_oclock_window_for_85_is_0706_to_0748(self):
        for now in (WED(7, 6), WED(7, 30), WED(7, 48, 59)):
            self.assertIsNone(night.early_refusal(now), now)
        shut = {WED(7, 5, 59): '07:06', WED(6, 0): '07:06', WED(7, 49): '목요일 07:06', WED(8, 0): '목요일 07:06', WED(8, 10): '목요일 07:06'}
        for now, when in shut.items():
            self.assertEqual(night.early_refusal(now), f'지금은 실행 금지 시간 — {when} 에 다시', now)

    def test_the_boundary_start_window_is_xx50_00_to_xx58_30_of_the_hour_before_the_boundary(self):
        for hour in (21, 7):
            self.assertIsNone(night.edge_refusal(TUE(hour, 50), hour))
            self.assertIsNone(night.edge_refusal(TUE(hour, 58, 30), hour))
            self.assertEqual(night.edge_refusal(TUE(hour, 49, 59), hour), f'지금은 실행 금지 시간 — {hour:02d}:50 에 다시')
            self.assertEqual(night.edge_refusal(TUE(hour, 58, 31), hour), f'지금은 실행 금지 시간 — 수요일 {hour:02d}:50 에 다시')
            self.assertEqual(night.edge_refusal(TUE(hour, 59, 30), hour), f'지금은 실행 금지 시간 — 수요일 {hour:02d}:50 에 다시')
        self.assertEqual(night.edge_refusal(TUE(12), 21), '지금은 실행 금지 시간 — 21:50 에 다시')
        self.assertEqual(night.edge_refusal(TUE(12), 7), '지금은 실행 금지 시간 — 수요일 07:50 에 다시')


class StepTest(unittest.TestCase):
    NIGHT = {'night_date': TUESDAY}  # 화요일 밤에 1단계를 끝냈다

    def test_with_no_state_only_the_night_window_starts_stage_one(self):
        self.assertEqual(night.night_step(TUE(22, 30), None), ('night', None))
        self.assertEqual(night.night_step(TUE(22, 0), None), ('night', None))
        self.assertEqual(night.night_step(TUE(23, 59), None), ('night', None))
        self.assertEqual(night.night_step(WED(9, 6), None), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(night.night_step(TUE(21, 59), None), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))

    def test_next_day_inside_the_morning_window_runs_stage_two(self):
        self.assertEqual(night.night_step(WED(8, 6), self.NIGHT), ('morning', None))
        self.assertEqual(night.night_step(WED(15, 30), self.NIGHT), ('morning', None))
        self.assertEqual(night.night_step(WED(21, 48), self.NIGHT), ('morning', None))

    def test_next_day_outside_the_window_but_before_the_day_ends_names_the_next_open_minute(self):
        self.assertEqual(night.night_step(WED(8, 5), self.NIGHT), (None, '지금은 실행 금지 시간 — 08:06 에 다시'))
        self.assertEqual(night.night_step(WED(0, 30), self.NIGHT), (None, '지금은 실행 금지 시간 — 08:06 에 다시'))
        self.assertEqual(night.night_step(WED(9, 0), self.NIGHT), (None, '지금은 실행 금지 시간 — 09:06 에 다시'))

    def test_after_the_last_open_minute_the_morning_is_over_and_the_answer_is_stage_one_again(self):
        self.assertEqual(night.night_step(WED(21, 49), self.NIGHT), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(night.night_step(WED(22, 30), self.NIGHT), ('night', None))

    def test_the_same_night_again_is_stage_one_not_the_morning(self):
        self.assertEqual(night.night_step(TUE(23, 30), self.NIGHT), ('night', None))

    def test_a_state_older_than_one_day_is_ignored(self):
        self.assertEqual(night.night_step(seoul(10, 8, 9, 6), self.NIGHT), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(night.night_step(seoul(10, 8, 22, 30), self.NIGHT), ('night', None))

    def test_a_finished_state_means_the_next_night_starts_over(self):
        done = {**self.NIGHT, 'done': True}
        self.assertEqual(night.night_step(WED(9, 6), done), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(night.night_step(WED(22, 30), done), ('night', None))

    def test_the_seven_oclock_morning_of_85_uses_its_own_window(self):
        early = night.EARLY_HOURS
        self.assertEqual(night.night_step(WED(7, 6), self.NIGHT, early), ('morning', None))
        self.assertEqual(night.night_step(WED(7, 48), self.NIGHT, early), ('morning', None))
        self.assertEqual(night.night_step(WED(7, 5), self.NIGHT, early), (None, '지금은 실행 금지 시간 — 07:06 에 다시'))
        self.assertEqual(night.night_step(WED(2, 0), self.NIGHT, early), (None, '지금은 실행 금지 시간 — 07:06 에 다시'))
        self.assertEqual(night.night_step(WED(7, 49), self.NIGHT, early), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(night.night_step(WED(9, 6), self.NIGHT), ('morning', None))  # 같은 때 다른 가설의 창이라면 열려 있다


# ── 밤 1단계 · 아침 2단계 ───────────────────────────────────────────────────────────────────────────

TWO_STAGE = {
    # 번호: (보관 행 [(kind, route)], 아침에 뜰 알림 [(제목, 본문)])
    '15': ([('acceptance_received', 'acceptances')], [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')]),
    '23': ([('match_made', 'match')], [(MATCH, f'{PARTNER} 님도 수락했어요')]),
    '52': ([('new_friend_review', 'friend_reviews')], [(REVIEW, f'{PARTNER} 님이 리뷰를 남겼어요')]),
    '83': ([('acceptance_received', 'acceptances')] * 2, [(ACCEPT, '밤사이 2명이 나를 수락했어요')]),
    '84': ([('acceptance_received', 'acceptances')], []),  # 아침에 스위치를 끈다 → 아무것도 안 온다
    '85': ([('acceptance_received', 'acceptances')], [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')]),
    '86': ([('match_made', 'chat')], [(PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')]),
    '87': ([('new_friend_review', 'friend_reviews')] * 2, [(REVIEW, '밤사이 리뷰 2개가 도착했어요')]),
    '88': ([('new_friend_review', 'friend_review_write')] * 2, None),  # 문구는 시험이 가입한 두 계정의 닉네임에서
}
MORNING_AT = {'85': WED(7, 10)}  # 07시대 창을 쓰는 가설, 나머지는 낮
TITLES = {ACCEPT, MATCH, PUBLIC, REVIEW, FRIEND}


def want_for(world, number):
    """(보관 행 모양, 아침에 뜰 알림) — 88 은 가입한 두 계정(id-3 · id-4)의 닉네임에서 나오므로 계정이 만들어진 뒤에야 안다."""
    rows, want = TWO_STAGE[number]
    if want is None:
        want = [(FRIEND, f'{world.nicknames[uid]} 님이 가입했어요, 리뷰를 남겨 주세요') for uid in ('id-3', 'id-4')]
    return rows, want


class NightStageTest(NightBase):
    def contract(self, number):
        (result, note), phone = self.case(number)
        rows, want = want_for(self.world, number)
        self.assertEqual(result, 'blocked', (result, note))
        self.assertEqual(note, night.night_note(number), number)
        saved = self.state(number)
        self.assertEqual(saved['night_date'], TUESDAY)
        self.assertEqual((saved['receiver']['id'], saved['receiver']['email']), ('id-1', self.world.users[0]['email']))
        self.assertEqual([(r['kind'], r['data']['route']) for r in saved['rows']], rows)
        self.assertEqual([tuple(w) for w in saved['want']], [] if number == '84' else want)
        self.assertEqual(self.pending(), [], '밤에 만든 보관 행은 08시 예약 chat-gate 가 먹지 못하게 지운다')
        self.assertEqual(self.arrived(0, {FRIEND} if number == '88' else TITLES - {FRIEND}), [], '밤에는 보관 알림이 안 온다')
        self.assertEqual(self.batches, [], '밤 단계는 배치를 안 부른다')
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + self.world.users[0]['email']}])
        self.assertIn(('none', 60), self.windows)  # "안 온다" 를 60초 지켜봤다
        self.assertFalse(self.granted)  # 권한은 되돌린다 — 아침 단계가 다시 준다


for _number in TWO_STAGE:
    setattr(NightStageTest, f'test_{_number}_night_stage_records_the_held_rows_deletes_them_and_ends_blocked_with_the_next_step',
            lambda self, n=_number: self.contract(n))


class TwoStageBase(NightBase):
    def after_night(self, number, morning=None):
        (result, _), _ = self.case(number)
        self.assertEqual(result, 'blocked')
        self.world.scheduled_runs = number == '85'
        self.clock.now = morning or MORNING_AT.get(number, WED(9, 20))
        self.shade_before = len(self.world.shade)

    def morning(self, number, phone=None):
        phone = phone or self.phone()
        return self.go(f'E-PUSH-{number}', phone), phone


class MorningStageTest(TwoStageBase):
    def contract(self, number):
        self.after_night(number)
        _, want = want_for(self.world, number)
        saved = self.state(number)
        (result, note), phone = self.morning(number)
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(self.arrived(self.shade_before, TITLES), sorted(want), number)
        self.assertEqual(self.pending(), [])
        self.assertTrue(self.state(number)['done'])
        # 로그인은 받는 사람(id-1) 계정으로 다시
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + saved['receiver']['email']}])
        # 기록한 행을 새 id 로 심고 곧바로 손 호출 — 사이에 다른 요청이 끼면 08시 예약이 먼저 먹을 수 있다
        planted = [s for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/rest/v1/pending_pushes']
        self.assertEqual(len(planted), 1)
        self.assertEqual([(r['profile_id'], r['kind'], r['title'], r['body'], r['data']) for r in planted[0]['body']],
                         [('id-1', r['kind'], r['title'], r['body'], r['data']) for r in saved['rows']])
        self.assertEqual(len({r['id'] for r in planted[0]['body']}), len(saved['rows']))
        after = self.world.sent[self.world.sent.index(planted[0]) + 1]
        self.assertEqual((after['method'], after['path']), ('BATCH', 'chat-gate'))
        self.assertEqual(self.batches, ['chat-gate'], '손 호출은 한 번(85 는 07시대 한 번 — 08:00 예약이 보냈다)')
        self.assertFalse(self.granted)


for _number in TWO_STAGE:
    setattr(MorningStageTest, f'test_{_number}_morning_stage_plants_the_rows_calls_chat_gate_once_and_judges_the_notification',
            lambda self, n=_number: self.contract(n))


class MorningDeliveryTest(TwoStageBase):
    """아침 단계도 푸시 연결 점검(notify.ensure_delivery)을 — 다시 로그인하기 전에, 죽은 연결이면 심은 행도 없이 blocked."""

    def test_a_dead_push_link_blocks_the_morning_stage_before_login_and_before_any_row_is_planted(self):
        self.after_night('15')
        self.prepared.clear()
        self.prepare_error = Blocked('GCM 연결 횟수를 못 읽음 — 푸시 연결을 점검할 수 없음')
        (result, note), phone = self.morning('15')
        self.assertEqual(result, 'blocked', (result, note))
        self.assertIn('푸시 연결', note)
        self.assertEqual((phone.jobs, self.batches), ([], []))
        planted = [s for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/rest/v1/pending_pushes']
        self.assertEqual(planted, [])

    def test_the_morning_stage_checks_the_link_once_on_the_phone(self):
        self.after_night('15')
        self.prepared.clear()
        self.morning('15')
        self.assertEqual([serial for serial, _ in self.prepared], ['S'])


class MorningBehaviourTest(TwoStageBase):
    def test_83_two_accepts_come_as_one_bundled_notification_not_two(self):
        self.after_night('83')
        self.assertEqual(self.morning('83')[0][0], 'pass')
        self.assertEqual(len([n for n in self.world.shade[self.shade_before:] if n.title == ACCEPT]), 1)

    def test_83_a_server_that_does_not_bundle_is_a_fail(self):
        self.after_night('83')
        with mock.patch.dict(BUNDLES, clear=True):
            self.assertEqual(self.morning('83')[0][0], 'fail')

    def test_88_signups_are_not_bundled_and_no_night_words_appear(self):
        self.after_night('88')
        self.assertEqual(self.morning('88')[0][0], 'pass')
        mine = [n for n in self.world.shade[self.shade_before:] if n.title == FRIEND]
        self.assertEqual(len(mine), 2)
        self.assertEqual([n for n in mine if '밤사이' in n.text], [])

    def test_88_a_server_that_bundles_the_signups_is_a_fail(self):
        self.after_night('88')
        with mock.patch.dict(BUNDLES, {('new_friend_review', 'friend_review_write'): (FRIEND, '밤사이 {n}명이 가입했어요')}):
            self.assertEqual(self.morning('88')[0][0], 'fail')

    def test_a_different_text_is_a_fail_that_names_what_arrived(self):
        self.after_night('15')
        self.scripts['chat-gate'] = lambda: (self.world.tables.__setitem__('pending_pushes', []), self.world.post(ACCEPT, '다른 문구'))
        result = self.morning('15')[0]
        self.assertEqual(result[0], 'fail')
        self.assertIn('다른 문구', result[1])

    def test_a_notification_that_does_not_come_is_a_fail_once_the_batch_is_known_to_have_run(self):
        self.after_night('15')
        self.scripts['chat-gate'] = lambda: self.world.tables.__setitem__('pending_pushes', [])  # 행은 지웠는데 알림은 안 보낸 서버
        self.assertEqual(self.morning('15')[0][0], 'fail')

    def test_a_batch_that_leaves_the_row_in_place_is_blocked_not_a_fail(self):
        self.after_night('15')
        self.scripts['chat-gate'] = lambda: None  # 배치가 안 돈 것 같다 — 알림이 없는 것을 결함으로 셀 수 없다
        result = self.morning('15')[0]
        self.assertEqual(result[0], 'blocked')
        self.assertIn('안 사라짐', result[1])
        self.assertFalse(self.state('15').get('done'))
        self.assertEqual(self.pending(), [], '심은 행이 남았으면 08시 예약이 먹기 전에 지운다')

    def test_the_morning_stage_before_its_window_creates_nothing(self):
        self.after_night('15')
        self.clock.now = WED(7, 30)
        users, tokens = len(self.world.users), len(self.world.tables['push_tokens'])
        phone = self.phone()
        self.assertEqual(self.go('E-PUSH-15', phone), ('blocked', '지금은 실행 금지 시간 — 08:06 에 다시'))
        self.assertEqual((phone.jobs, self.batches, len(self.world.users), len(self.world.tables['push_tokens'])), ([], [], users, tokens))

    def test_the_manual_chat_gate_goes_through_the_batch_gate(self):
        self.after_night('15')
        self.clock.now = WED(9, 3)  # 정각 ±5분은 금지
        with mock.patch.object(area2, '_batch', base.ORIGINAL_BATCH), mock.patch.object(tools, 'batch') as gcloud, \
                mock.patch.object(batch_gate, 'now_seoul', lambda: WED(9, 3)):
            result = self.go('E-PUSH-15', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertIn('지금은 실행 금지 시간', result[1])
        gcloud.assert_not_called()

    def test_a_morning_in_an_hour_that_already_had_a_manual_chat_gate_is_refused_before_anything_is_written(self):
        # chat-gate 는 같은 시(時)에 손으로 두 번 못 부른다 — 두 단계 가설은 시간(時)마다 하나씩 아침을 돈다. 심기 전에 멈춘다
        self.after_night('15')
        self.history.write_text(f'{WED(9, 20).isoformat()}\n', encoding='utf-8')
        self.log.clear()
        phone = self.phone()
        self.assertEqual(self.go('E-PUSH-15', phone), ('blocked', '지금은 실행 금지 시간 — 10:06 에 다시'))
        self.assertEqual((phone.jobs, self.batches, self.pending(), self.log), ([], [], [], []))
        self.assertFalse(self.state('15').get('done'))

    def test_a_receiver_that_this_run_did_not_make_is_refused_before_anything_is_written(self):
        self.after_night('15')
        saved = self.state('15')
        saved['receiver']['id'] = 'someone-elses-id'
        (self.run.out / 'night_15.json').write_text(json.dumps(saved), encoding='utf-8')
        phone = self.phone()
        self.assertEqual(self.go('E-PUSH-15', phone)[0], 'blocked')
        self.assertEqual((phone.jobs, self.batches), ([], []))

    def test_a_finished_state_makes_the_next_night_start_stage_one_again(self):
        self.after_night('15')
        self.assertEqual(self.morning('15')[0][0], 'pass')
        self.clock.now = WED(22, 30)
        (result, note), _ = self.case('15')
        self.assertEqual((result, note), ('blocked', night.night_note('15')))
        self.assertEqual(self.state('15')['night_date'], '2026-10-07')

    def test_the_notification_permission_is_given_first_and_taken_back_at_the_end_of_the_morning(self):
        self.after_night('15')
        self.log.clear()
        self.morning('15')
        self.assertEqual((self.log[0], self.log[-1]), ('grant', 'revoke'))

    # 84 — 스위치는 보낼 때 다시 본다
    def test_84_the_switch_is_turned_off_before_the_row_is_planted_and_then_nothing_comes(self):
        self.after_night('84')
        result, phone = self.morning('84')
        self.assertEqual(result[0], 'pass', result)
        flip = next(i for i, s in enumerate(self.world.sent) if s['method'] == 'PATCH' and s['path'] == '/cards/notification-settings')
        plant = next(i for i, s in enumerate(self.world.sent) if s['method'] == 'POST' and s['path'] == '/rest/v1/pending_pushes')
        self.assertLess(flip, plant)
        self.assertEqual(self.world.sent[flip]['body'], {'acceptance_received': False})
        self.assertEqual(self.arrived(self.shade_before, {ACCEPT}), [])
        self.assertEqual(self.pending(), [])
        controls = [s for s in self.world.sent[plant:] if s['path'].startswith('/chat/matches/') and s['body']['body'].startswith('E2E-ctl-')]
        self.assertEqual(len(controls), 1, '"안 온다" 를 믿으려면 같은 길로 대조 메시지가 와야 한다')

    def test_84_a_server_that_ignores_the_switch_is_a_fail(self):
        self.after_night('84')
        self.world.ignore_switches = True
        self.assertEqual(self.morning('84')[0][0], 'fail')

    def test_84_without_an_arriving_control_the_silence_is_blocked(self):
        self.after_night('84')
        self.world.drop_messages = True  # 같은 길로 보낸 대조 메시지도 안 오는 세계 — "안 온다" 를 믿을 수 없다
        self.assertEqual(self.morning('84')[0][0], 'blocked')

    # 85 — 07시대 배치는 보관 알림을 그대로 둔다
    def test_85_the_seven_oclock_batch_leaves_the_row_and_the_scheduled_eight_oclock_job_delivers_it(self):
        self.after_night('85')
        result, _ = self.morning('85')
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('예약', result[1])
        self.assertEqual(self.batches, ['chat-gate'], '08시 예약이 보냈으니 손 호출은 한 번뿐')
        self.assertEqual(self.arrived(self.shade_before, {ACCEPT}), [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')])
        self.assertEqual(self.pending(), [])

    def test_85_the_anchor_match_is_made_before_the_row_is_planted_and_stamped_by_the_batch(self):
        self.after_night('85')
        self.morning('85')
        paths = [(s['method'], s['path']) for s in self.world.sent]
        both_accept = next(i for i, s in enumerate(self.world.sent)
                           if s['method'] == 'PATCH' and s['path'] == '/rest/v1/match_participants' and s['body'].get('trust_response') == 'accept')
        plant = paths.index(('POST', '/rest/v1/pending_pushes'))
        self.assertLess(both_accept, plant)
        self.assertEqual(self.world.sent[plant + 1]['method'], 'BATCH')
        self.assertTrue(all(m['trust_passed_at'] for m in self.world.tables['matches'][-1:]))

    def test_85_when_the_scheduled_job_did_not_send_it_waits_to_0806_and_calls_the_batch_by_hand(self):
        self.after_night('85')
        self.world.scheduled_runs = False
        result, _ = self.morning('85')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['chat-gate', 'chat-gate'])
        first, second = self.batch_times
        self.assertEqual(first.hour, 7)
        self.assertGreaterEqual((second.hour, second.minute), (8, 6))
        self.assertIn('손으로', result[1])

    def test_85_a_batch_at_seven_that_already_sent_the_notification_is_a_fail(self):
        self.after_night('85')
        self.world.ignore_quiet = True  # 결함: 07시대인데 조용한 시간을 안 봄
        result, _ = self.morning('85')
        self.assertEqual(result[0], 'fail')

    def test_85_without_the_anchor_the_untouched_row_proves_nothing_and_is_blocked(self):
        self.after_night('85')
        self.scripts['chat-gate'] = lambda: None
        result, _ = self.morning('85')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('앵커', result[1])
        self.assertEqual(self.pending(), [], '심은 행은 남기지 않는다')

    def test_85_before_0706_the_morning_stage_is_refused_with_0706(self):
        self.after_night('85')
        self.clock.now = WED(6, 59)
        phone = self.phone()
        self.assertEqual(self.go('E-PUSH-85', phone), ('blocked', '지금은 실행 금지 시간 — 07:06 에 다시'))
        self.assertEqual(phone.jobs, [])

    def test_85_the_night_note_says_the_morning_is_at_seven(self):
        self.assertIn('07:06', night.night_note('85'))
        self.assertIn('08:06', night.night_note('15'))
        for number in ('15', '85'):
            self.assertIn('같은 번호', night.night_note(number))
            self.assertIn('같은 --bundle', night.night_note(number))


# ── 밤 단일 단계 16 · 33 ────────────────────────────────────────────────────────────────────────────

class SingleNightTest(NightBase):
    def test_16_with_quiet_hours_off_the_accept_arrives_at_night_and_nothing_is_held(self):
        (result, note), phone = self.case('16')
        self.assertEqual(result, 'pass', (result, note))
        flips = self.world.by('PATCH', '/cards/notification-settings')
        self.assertEqual([(s['auth'], s['body']) for s in flips], [('tok-1', {'quiet_hours': False})])
        self.assertLess(self.world.sent.index(flips[0]), self.world.sent.index(self.world.by('POST', '/cards/')[0]))
        self.assertEqual(self.arrived(0, {ACCEPT}), [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')])
        self.assertEqual(self.pending(), [])
        self.assertFalse((self.run.out / 'night_16.json').exists())  # 단계가 하나다

    def test_16_a_server_that_still_holds_the_accept_when_quiet_hours_is_off_is_a_fail(self):
        self.world.hold_always = True
        (result, note), _ = self.case('16')
        self.assertEqual(result, 'fail')
        self.assertIn('pending_pushes', note)
        self.assertEqual(self.pending(), [], '실패해도 보관 행은 지운다')

    def test_16_in_daytime_it_is_blocked_before_any_account_is_made(self):
        (result, note), phone = self.case('16', TUE(12))
        self.assertEqual((result, note), ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual((self.world.users, phone.jobs, self.log), ([], [], []))

    def test_33_a_message_comes_at_night_even_with_quiet_hours_on(self):
        (result, note), _ = self.case('33')
        self.assertEqual(result, 'pass', (result, note))
        sent = self.world.by('POST', '/chat/matches/')
        self.assertEqual(len(sent), 1)
        self.assertEqual(self.arrived(0, {PARTNER}), [(PARTNER, sent[0]['body']['body'])])
        self.assertEqual(self.pending(), [])
        gets = self.world.by('GET', '/cards/notification-settings')
        self.assertEqual(len(gets), 1, 'quiet_hours 가 정말 켜져 있는지 먼저 본다')

    def test_33_with_quiet_hours_already_off_the_exception_proves_nothing_and_is_blocked(self):
        self.world.settings['id-1'] = {'quiet_hours': False}
        (result, note), _ = self.case('33')
        self.assertEqual(result, 'blocked')
        self.assertIn('quiet_hours', note)
        self.assertEqual(self.world.by('POST', '/chat/matches/'), [])

    def test_33_no_message_notification_is_a_fail(self):
        self.world.drop_messages = True
        self.assertEqual(self.case('33')[0][0], 'fail')

    def test_33_in_daytime_it_is_blocked_before_any_account_is_made(self):
        (result, note), phone = self.case('33', TUE(9))
        self.assertEqual(result, 'blocked')
        self.assertEqual((self.world.users, phone.jobs), ([], []))


class NightGateTest(NightBase):
    def test_every_case_with_a_night_stage_is_refused_outside_2200_to_2359_before_any_account_or_permission(self):
        for number in TWO_STAGE:
            for now, when in ((TUE(12), '22:00'), (TUE(21, 59, 59), '22:00'), (WED(0, 0), '22:00'), (WED(7, 59), '22:00')):
                with self.subTest(case=number, now=now):
                    self.world.users.clear()
                    self.log.clear()
                    phone = self.phone()
                    self.assertEqual(self.case(number, now, phone)[0], ('blocked', f'지금은 실행 금지 시간 — {when} 에 다시'))
                    self.assertEqual((self.world.users, phone.jobs, self.log, self.batches), ([], [], [], []))

    def test_a_night_stage_is_allowed_on_a_monday_because_it_calls_no_daily_cards_batch(self):
        self.assertEqual(self.case('15', MON(22, 30))[0][0], 'blocked')
        self.assertTrue((self.run.out / 'night_15.json').exists())

    def test_a_prep_that_runs_past_midnight_is_blocked_before_the_partner_acts(self):
        self.clock.now = TUE(23, 59, 40)
        self.world.on_link = lambda: self.tick(30)  # 로그인 준비가 길어져 자정을 넘는다
        (result, note), _ = self.case('15')
        self.assertEqual(result, 'blocked')
        self.assertIn('창을 벗어남', note)
        self.assertEqual(self.world.by('POST', '/cards/'), [])
        self.assertFalse((self.run.out / 'night_15.json').exists())

    def test_quiet_hours_off_is_blocked_because_the_night_hold_cannot_be_seen(self):
        class Everyone(dict):
            def get(self, key, default=None):
                return {'quiet_hours': False}

        self.world.settings = Everyone()
        for number in ('15', '23', '83'):
            with self.subTest(case=number):
                (result, note), _ = self.case(number)
                self.assertEqual(result, 'blocked')
                self.assertIn('quiet_hours', note)

    def test_a_phone_that_never_reaches_home_does_not_go_on_to_the_partner(self):
        phone = self.phone()
        phone.answers = [{'result': 'fail', 'note': '홈 못 감'}]
        (result, _), _ = self.case('15', phone=phone)
        self.assertEqual(result, 'fail')
        self.assertEqual(self.world.by('POST', '/cards/'), [])
        self.assertFalse((self.run.out / 'night_15.json').exists())


class NightFailureTest(NightBase):
    def test_a_server_that_sends_at_night_instead_of_holding_is_a_fail_and_leaves_no_state(self):
        self.world.ignore_quiet = True
        (result, note), _ = self.case('15')
        self.assertEqual(result, 'fail')
        self.assertFalse((self.run.out / 'night_15.json').exists())

    def test_a_server_that_neither_sends_nor_holds_is_a_fail_naming_the_pending_rows(self):
        self.world.never_defer = True
        (result, note), _ = self.case('15')
        self.assertEqual(result, 'fail')
        self.assertIn('pending_pushes', note)
        self.assertFalse((self.run.out / 'night_15.json').exists())

    def test_the_partner_side_row_of_a_match_is_a_fail_when_the_server_holds_it_for_the_one_who_just_pressed(self):
        original = NightWorld.accept_back

        def holds_both(world, sent):
            card = next(c for c in world.tables['daily_cards'] if c['id'] == sent['path'].rsplit('/', 1)[1])
            reply = original(world, sent)
            world.tables['pending_pushes'].append({'id': 'pp', 'profile_id': world.owner_of(sent), 'kind': 'match_made', 'title': MATCH,
                                                   'body': f'{world.nick(card["owner_id"])} 님과 대화를 시작해 보세요', 'data': {'route': 'match'}})
            return reply

        self.world.handlers[:] = [h for h in self.world.handlers if '/cards/acceptances/' not in h[1].pattern]
        self.world.on('POST', r'/cards/acceptances/[^/]+', lambda sent: holds_both(self.world, sent))
        (result, note), _ = self.case('23')
        self.assertEqual(result, 'fail')
        self.assertIn('id-2', note)
        self.assertEqual(self.pending(), [], '실패해도 보관 행은 지운다')

    def test_23_only_the_first_presser_has_a_match_row_and_the_partner_has_none(self):
        (result, _), _ = self.case('23')
        self.assertEqual(result, 'blocked')
        saved = self.state('23')
        self.assertEqual([(r['kind'], r['data']['route']) for r in saved['rows']], [('match_made', 'match')])
        pair = [m for m in self.world.tables['matches'] if {m['profile_a'], m['profile_b']} == {'id-1', 'id-2'}]
        self.assertEqual(len(pair), 1)

    def test_an_exception_in_the_middle_still_clears_the_rows_it_made(self):
        with mock.patch.object(notify, 'expect_none', side_effect=RuntimeError('알림창 읽기 터짐')), self.assertRaises(RuntimeError):
            self.case('15')
        self.assertEqual(self.pending(), [], '수락 직후(보관 행이 생긴 뒤)에 터져도 행을 지운다')

    def test_a_row_that_cannot_be_deleted_is_reported_as_a_problem_not_swallowed(self):
        self.world.on('DELETE', r'/rest/v1/pending_pushes', Reply(500, {'message': 'x'}))
        self.world.handlers.insert(0, self.world.handlers.pop())
        (result, note), _ = self.case('15')
        self.assertEqual(result, 'fail')
        self.assertIn('지우지 못', note)


# ── 시각 경계 72 · 73 ───────────────────────────────────────────────────────────────────────────────

class EdgeTest(NightBase):
    START = TUE(21, 52)

    def accept_times(self):
        return self.world.decided_at

    def test_72_the_21_59_accept_arrives_and_the_22_00_accept_is_held(self):
        (result, note), phone = self.case('72')
        self.assertEqual(result, 'pass', (result, note))
        first, second = self.accept_times()
        self.assertTrue(TUE(21, 59, 20) <= first < TUE(22, 0), first)
        self.assertGreaterEqual(second, TUE(22, 0, 20))
        self.assertEqual(self.arrived(0, {ACCEPT}), [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')])  # 21:59 몫 하나뿐
        self.assertEqual(self.pending(), [], '시험 뒤 보관 행은 지운다(08시 예약이 먹지 않게)')
        self.assertIn('21:59', note)  # 잰 시각이 메모에 남는다
        self.assertIn('22:00', note)
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + self.world.users[0]['email']}])

    def test_72_two_cards_come_from_two_different_accepters(self):
        self.case('72')
        cards = self.world.tables['daily_cards']
        self.assertEqual(sorted((c['owner_id'], c['target_id']) for c in cards[:2]), [('id-2', 'id-1'), ('id-3', 'id-1')])

    def test_72_a_server_that_holds_the_21_59_accept_is_a_fail(self):
        self.world.quiet = lambda: self.clock.now.hour >= 21  # 결함: 방해 금지가 21시에 시작
        self.assertEqual(self.case('72')[0][0], 'fail')

    def test_72_a_server_that_sends_the_22_00_accept_is_a_fail(self):
        self.world.ignore_quiet = True
        self.assertEqual(self.case('72')[0][0], 'fail')

    def test_72_a_first_accept_that_runs_past_2159_59_is_blocked_with_the_measured_time(self):
        self.world.decide_takes = 45
        (result, note), _ = self.case('72')
        self.assertEqual(result, 'blocked')
        self.assertIn('경계를 못 맞춤', note)
        self.assertEqual(len(self.accept_times()), 1)
        self.assertEqual(self.pending(), [])

    def test_72_a_second_accept_before_2200_is_blocked(self):
        with mock.patch.object(night, '_sleep_until', lambda target: None):  # 기다리지 않으면 두 번째가 22:00 전에 나간다
            (result, note), _ = self.case('72', TUE(21, 58, 20))
        self.assertEqual(result, 'blocked')
        self.assertIn('경계를 못 맞춤', note)
        self.assertEqual(len(self.accept_times()), 1)

    def test_72_outside_its_start_window_is_blocked_before_any_account(self):
        for now, when in ((TUE(21, 49, 59), '21:50'), (TUE(21, 58, 31), '수요일 21:50'), (TUE(12), '21:50')):
            with self.subTest(now=now):
                self.world.users.clear()
                phone = self.phone()
                self.assertEqual(self.case('72', now, phone)[0], ('blocked', f'지금은 실행 금지 시간 — {when} 에 다시'))
                self.assertEqual((self.world.users, phone.jobs, self.log), ([], [], []))

    def test_72_a_prep_that_runs_past_215920_is_blocked(self):
        self.clock.now = TUE(21, 58, 20)
        self.world.on_link = lambda: self.tick(120)
        (result, note), _ = self.case('72')
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.accept_times(), [])

    def test_72_with_quiet_hours_off_it_is_blocked(self):
        self.world.settings['id-1'] = {'quiet_hours': False}
        self.assertEqual(self.case('72')[0][0], 'blocked')

    def test_73_the_07_59_accept_is_held_and_the_08_00_accept_arrives_at_once(self):
        (result, note), _ = self.case('73', TUE(7, 52))
        self.assertEqual(result, 'pass', (result, note))
        first, second = self.accept_times()
        self.assertTrue(TUE(7, 59, 20) <= first < TUE(8, 0), first)
        self.assertGreaterEqual(second, TUE(8, 0, 20))
        self.assertEqual(self.arrived(0, {ACCEPT}), [(ACCEPT, f'{THIRD} 님이 대화를 하고 싶어 해요')])  # 두 번째 수락자 몫만
        self.assertEqual(self.pending(), [])
        self.assertIn('07:59', note)

    def test_73_the_first_accept_is_watched_only_until_just_before_0800(self):
        self.case('73', TUE(7, 52))
        watch = [s for kind, s in self.windows if kind == 'none']
        self.assertTrue(watch and all(s < 60 for s in watch), watch)  # 60초를 통째로 보면 08:00 예약 실행이 낀다

    def test_73_the_scheduled_job_sending_the_first_held_accept_does_not_disturb_the_verdict_and_is_noted(self):
        self.world.scheduled_runs = True
        (result, note), _ = self.case('73', TUE(7, 52))
        self.assertEqual(result, 'pass', (result, note))
        self.assertIn('예약', note)
        self.assertEqual(len([n for n in self.world.shade if n.title == ACCEPT]), 2)

    def test_73_a_server_that_still_holds_the_08_00_accept_is_a_fail(self):
        self.world.quiet = lambda: True  # 결함: 08시 뒤에도 방해 금지
        self.assertEqual(self.case('73', TUE(7, 52))[0][0], 'fail')

    def test_73_a_server_that_sends_the_07_59_accept_is_a_fail(self):
        self.world.ignore_quiet = True
        self.assertEqual(self.case('73', TUE(7, 52))[0][0], 'fail')

    def test_73_outside_its_start_window_is_blocked_before_any_account(self):
        for now, when in ((TUE(7, 49), '07:50'), (TUE(7, 59), '수요일 07:50'), (TUE(14), '수요일 07:50')):
            with self.subTest(now=now):
                self.world.users.clear()
                phone = self.phone()
                self.assertEqual(self.case('73', now, phone)[0], ('blocked', f'지금은 실행 금지 시간 — {when} 에 다시'))
                self.assertEqual((self.world.users, phone.jobs, self.log), ([], [], []))


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

NUMBERS = '15 16 23 33 52 72 73 83 84 85 86 87 88'.split()
WITH_NIGHT_STAGE = '15 16 23 33 52 83 84 85 86 87 88'.split()


class RegistryTest(unittest.TestCase):
    def test_the_13_cases_are_phone_cases_in_the_three_bundles(self):
        ids = [f'E-PUSH-{n}' for n in NUMBERS]
        self.assertEqual(area1.BUNDLES['area4-push-night'], ids)
        self.assertEqual(area1.BUNDLES['area4-push-night-a'], [f'E-PUSH-{n}' for n in WITH_NIGHT_STAGE])
        self.assertEqual(area1.BUNDLES['area4-push-edge'], ['E-PUSH-72', 'E-PUSH-73'])
        for case in ids:
            self.assertIn(case, area1.PHONE)

    def test_limits_cover_the_waits_85_is_the_longest(self):
        for number in NUMBERS:
            self.assertGreaterEqual(tools.CASE_LIMITS[f'E-PUSH-{number}'], 900, number)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-PUSH-85'], 4500)

    def test_each_case_has_an_app_alias_in_the_dart_piece_that_area4_pulls_in(self):
        folder = tools.ROOT / 'frontend' / 'integration_test'
        piece = (folder / 'area4_push_night.dart').read_text(encoding='utf-8')
        self.assertTrue(piece.startswith("part of 'area4.dart';"))
        for number in NUMBERS:
            self.assertIn(f"'{number}'", piece)
        self.assertIn("area1Cases['E-ONB-61']", piece)
        area4 = (folder / 'area4.dart').read_text(encoding='utf-8')
        self.assertIn("part 'area4_push_night.dart';", area4)
        self.assertIn('..._pushNightCases,', area4)

    def test_the_module_is_imported_by_the_program_entry(self):
        self.assertIn('from e2e import area4_push_night', (tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'))

    def test_the_shared_scene_takes_only_one_new_parameter_daytime_defaulting_to_true(self):
        params = inspect.signature(area4_push._Scene.__init__).parameters
        self.assertEqual(list(params), ['self', 'run', 'phone', 'daytime'])
        self.assertIs(params['daytime'].default, True)

    def test_a_scene_built_for_the_night_does_not_ask_for_daytime_but_the_default_still_does(self):
        run, phone = mock.Mock(), mock.Mock()
        patches = (mock.patch.object(notify, 'require_daytime'), mock.patch.object(area3_phone, '_person', return_value={'id': 'x', 'email': 'e'}),
                   mock.patch.object(area4_push, '_app'), mock.patch.object(area4_push, '_wait_for', return_value=True),
                   mock.patch.object(notify, 'background'), mock.patch.object(notify, 'ensure_delivery'))  # 푸시 연결 점검은 실제 adb 를 부른다
        with patches[0] as daytime, patches[1], patches[2], patches[3], patches[4], patches[5]:
            area4_push._Scene(run, phone, daytime=False)
            daytime.assert_not_called()
            area4_push._Scene(run, phone)
            daytime.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
