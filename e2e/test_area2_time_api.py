"""영역 2 시간 API 가설(묶음 area2-time-api) 시험 — 운영 없이 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area2_time_api`.

가짜 서버([Server])는 시간이 걸린 서버 규칙(후보 15일 · 결정 90일 · 만료 14일 · 수락 7일 · 투표 하루/주 · 달 한도 ·
접속 갱신 1시간)을 SQL · 라우터 그대로 흉내 낸다. 올바른 서버면 pass, 규칙 숫자 하나를 바꾼 서버(시험마다 [Server] 인자)면 fail 이어야 한다.
시계는 [FROZEN](화요일 낮) 으로 얼려 시험이 오늘이 월요일인지에 흔들리지 않는다 — 월요일 분기는 따로 본다.
PostgREST 처럼 모르는 열 · 표 이름은 400 으로 돌려준다([SCHEMA] 는 supabase/migrations 에서 대조한 열)."""

import re
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area2_time_api as T, area3, area3_safe, tools
from e2e.area1 import SEOUL
from e2e.test_area2 import Base
from e2e.test_area3 import Fake as TableFake
from e2e.tools import Reply

UTC = timezone.utc
FROZEN = datetime(2026, 10, 6, 12, 0, tzinfo=SEOUL)  # 화요일 낮
MONDAY = datetime(2026, 10, 5, 10, 0, tzinfo=SEOUL)
IN_REVIEW = '이미 확인 중이에요, 결과를 기다려 주세요'

# 표 → 열. 출처: 20260913054544_create_profiles · 20260920043514 · 20260920160537_create_daily_cards · 20260920160544_create_matches ·
# 20260920043832_create_heart_ledger · 20260927020000_create_polls · 20260928030000_create_heart_task_submissions ·
# 20261008010000_social_login_pending_profiles(school_email_verified_at — 계정 공장이 프로필을 직접 만든다)
SCHEMA = {
    'profiles': {'id', 'status', 'gender', 'last_active_at', 'matching_paused', 'student_verification', 'is_smoker', 'religion', 'mbti',
                 'preferred_mbti_flags', 'preferred_height_min', 'preferred_height_max', 'preferred_age_min', 'preferred_age_max',
                 'interest_tags', 'my_traits', 'ideal_traits', 'height_cm', 'birth_year', 'university_id', 'nickname',
                 'school_email_verified_at'},
    'daily_cards': {'id', 'owner_id', 'target_id', 'source', 'issued_at', 'expires_at'},
    'card_decisions': {'card_id', 'decision', 'decided_at'},
    'acceptance_responses': {'card_id', 'responder_id', 'decision', 'decided_at'},
    'matches': {'id', 'profile_a', 'profile_b', 'created_at', 'trust_passed_at', 'chat_closed_at'},
    'polls': {'id', 'author_id', 'question', 'option_a_label', 'option_b_label', 'status', 'created_at'},
    'heart_transactions': {'id', 'profile_id', 'amount', 'reason', 'ref_id', 'created_at'},
    'entitlements': {'profile_id', 'heart_balance', 'updated_at'},
    'heart_task_submissions': {'id', 'profile_id', 'task', 'storage_path', 'status', 'reward_hearts', 'reject_reason', 'created_at',
                               'reviewed_at'},
}


def at(text):
    return datetime.fromisoformat(text.replace('Z', '+00:00'))


def day_start(now, tz=SEOUL):
    local = now.astimezone(tz)
    return local.replace(hour=0, minute=0, second=0, microsecond=0)


def week_start(now, tz=SEOUL):
    start = day_start(now, tz)
    return start - timedelta(days=start.weekday())


def month_start(now, tz=SEOUL):
    return day_start(now, tz).replace(day=1)


class Server(TableFake):
    """표 저장소 + 시간 규칙이 든 API. [rules] 의 숫자 · 스위치를 바꿔 어긋난 서버를 만든다."""

    def __init__(self, **rules):
        super().__init__()
        self.clock = lambda: FROZEN.astimezone(UTC)
        self.options = []  # (메서드, 경로, call 에 더 넘긴 키워드 — retry=False 등)
        self.rules = {'candidate_days': 15, 'active_days': 14, 'decided_days': 90, 'expired_days': 14, 'ar_days': 90,
                      'matches_block': True, 'ar_clause': True, 'count_paused': False, 'ttl_days': 7, 'ttl_check': True,
                      'expiry_check': True, 'coef': {3: 1.0, 7: 0.7}, 'touch_minutes': 60, 'weekly_cap': 30,
                      'day_window': 'seoul', 'week_window': 'seoul', 'month_window': 'seoul', 'poll_limit': 10,
                      'reviewing_any_month': True, 'poll_day_limit_window': 'seoul', 'gender_check': True, 'rpc_ignores_p_now': False}
        self.rules.update(rules)
        self.profiles = {}
        for method, pattern, handler in (
                ('GET', r'/matching/candidates', self._candidates), ('GET', r'/cards/acceptances', self._acceptances),
                ('POST', r'/cards/acceptances/[^/]+', self._respond), ('GET', r'/cards/[^/]+', self._card),
                ('POST', r'/cards/[^/]+/decision', self._decide), ('PATCH', r'/cards/matching-paused', self._pause),
                ('POST', r'/rest/v1/rpc/region_active_counts', self._counts), ('POST', r'/rest/v1/rpc/poll_vote_reward_due', self._reward_due), ('POST', r'/rest/v1/rpc/grant_hearts', self._grant),
                ('POST', r'/community/polls', self._new_poll), ('DELETE', r'/community/polls/[^/]+', self._drop_poll),
                ('POST', r'/community/polls/[^/]+/votes', self._vote), ('GET', r'/heart-tasks', self._tasks),
                ('POST', r'/heart-tasks/[^/]+/submissions', self._submit), ('GET', r'/home/summary', self._home)):
            self.on(method, pattern, handler)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.options.append((method, urlsplit(url).path, options))
        return super().__call__(method, url, headers, body, raw)

    def override(self, method, pattern, reply):
        """기본 서버 규칙보다 먼저 맞는 답 — 서버가 어긋났거나 죽은 경우를 시험이 만든다."""
        self.handlers.insert(0, (method, re.compile(pattern), reply))

    # ── 표 ──
    def now(self):
        return self.clock()

    def rows(self, table):
        return self.tables.setdefault(table, [])

    def profile(self, pid):
        return self.profiles.setdefault(pid, {'id': pid, 'status': 'active', 'gender': None, 'matching_paused': False,
                                              'last_active_at': self.now().isoformat()})

    def _unknown(self, name, sent):
        """PostgREST 처럼 — 없는 열(select · 필터 · 정렬 · 넣는 값)은 400 42703."""
        known = SCHEMA.get(name)
        if known is None:
            return None
        query, body = sent['query'], sent['body']
        used = set()
        for key, value in query.items():
            if key == 'select':
                used |= {re.sub(r'\(.*', '', c) for c in value.split(',')} - {'*'}
            elif key == 'order':
                used |= {c.split('.')[0] for c in value.split(',')}
            elif key == 'or':
                used |= set(re.findall(r'(\w+)\.(?:eq|lt|gt|gte|lte)\.', value))
            elif key not in ('limit', 'offset', 'on_conflict'):
                used.add(key)
        for row in body if isinstance(body, list) else [body] if isinstance(body, dict) else []:
            used |= set(row)
        missing = used - known
        return Reply(400, {'code': '42703', 'message': f'column {name}.{sorted(missing)[0]} does not exist'}) if missing else None

    def _table(self, method, name, sent):
        bad = self._unknown(name, sent)
        if bad:
            return bad
        query = sent['query']
        if name == 'universities':
            return Reply(200, [{'region_group': 'e2e'}])
        if name == 'profiles' and 'id' in query:
            row = self.profile(query['id'][3:])
            if method == 'PATCH' and self.rules['gender_check'] and 'gender' in sent['body'] and sent['body']['gender'] is None:
                return Reply(400, {'code': '23514', 'message': 'profiles_active_requires_onboarding'})  # active 는 성별이 있어야 한다
            if method == 'PATCH':
                row.update(sent['body'])
                return Reply(200, None)
            return Reply(200, [dict(row)])
        if name == 'matches' and method == 'GET' and 'or' in query:
            who = re.search(r'profile_a\.eq\.([^,)]+)', query['or']).group(1)
            return Reply(200, [dict(m) for m in self.rows('matches') if who in (m['profile_a'], m['profile_b'])])
        return super()._table(method, name, sent)

    @staticmethod
    def who(sent):
        return f"id-{sent['auth'].removeprefix('tok-')}"

    def decision(self, card_id):
        return next((d for d in self.rows('card_decisions') if d['card_id'] == card_id), None)

    # ── 후보 · 카드 ──
    def _candidates(self, sent):
        me, now, r = self.who(sent), self.now(), self.rules
        mine = self.profile(me)
        vectors = {v['profile_id'] for v in self.rows('profile_vectors')}
        out = []
        for pid, p in self.profiles.items():
            if pid == me or pid not in vectors or p['gender'] in (None, mine['gender']) or p['status'] != 'active' or p['matching_paused']:
                continue
            last = at(p['last_active_at'])
            if last <= now - timedelta(days=r['candidate_days']):
                continue
            if self._rested(me, pid, now):
                continue
            days = (now - last).days
            coef = next((v for limit, v in sorted(r['coef'].items()) if days <= limit), 0.4)
            out.append({'profile_id': pid, 'score': round(coef, 4)})
        return Reply(200, {'candidates': out})

    def _rested(self, me, pid, now):
        r = self.rules
        for card in self.rows('daily_cards'):
            if card['owner_id'] != me or card['target_id'] != pid:
                continue
            d, expires = self.decision(card['id']), card['expires_at'] and at(card['expires_at'])
            if d is None and (expires is None or expires > now):
                return True
            if d is not None and at(d['decided_at']) > now - timedelta(days=r['decided_days']):
                return True
            if d is None and expires is not None and expires > now - timedelta(days=r['expired_days']):
                return True
        if r['ar_clause']:
            for ar in self.rows('acceptance_responses'):
                card = next(c for c in self.rows('daily_cards') if c['id'] == ar['card_id'])
                if ar['responder_id'] == me and card['owner_id'] == pid and at(ar['decided_at']) > now - timedelta(days=r['ar_days']):
                    return True
        return bool(r['matches_block']) and any({m['profile_a'], m['profile_b']} == {me, pid} and (r['matches_block'] is True or me == m['profile_a'])
                                                for m in self.rows('matches'))  # 'low_side_only' = 한쪽에게만 숨기는 서버

    def _card(self, sent):
        card_id = sent['path'].rsplit('/', 1)[1]
        mine = any(c['id'] == card_id and c['owner_id'] == self.who(sent) for c in self.rows('daily_cards'))
        return Reply(200, {'card_id': card_id}) if mine else Reply(404, {'detail': '카드를 찾을 수 없어요'})

    def _decide(self, sent):
        card_id, now = sent['path'].split('/')[2], self.now()
        card = next((c for c in self.rows('daily_cards') if c['id'] == card_id and c['owner_id'] == self.who(sent)), None)
        if card is None:
            return Reply(404, {'detail': '카드를 찾을 수 없어요'})
        if self.decision(card_id):
            return Reply(409, {'detail': '이미 결정한 카드예요'})
        if self.rules['expiry_check'] and card['expires_at'] and at(card['expires_at']) <= now:
            return Reply(409, {'detail': '지난 카드예요'})
        self.rows('card_decisions').append({'card_id': card_id, 'decision': sent['body']['decision'], 'decided_at': now.isoformat()})
        return Reply(200, {'ok': True})

    def _acceptances(self, sent):
        me, now, ttl = self.who(sent), self.now(), timedelta(days=self.rules['ttl_days'])
        out = []
        for card in self.rows('daily_cards'):
            d = self.decision(card['id'])
            answered = any(a['card_id'] == card['id'] for a in self.rows('acceptance_responses'))
            if card['target_id'] == me and d and d['decision'] == 'accept' and not answered and at(d['decided_at']) > now - ttl:
                out.append({'card_id': card['id'], 'expires_at': (at(d['decided_at']) + ttl).isoformat(), 'profile': {}})
        return Reply(200, {'acceptances': out})

    def _respond(self, sent):
        card_id, me, now = sent['path'].rsplit('/', 1)[1], self.who(sent), self.now()
        card = next((c for c in self.rows('daily_cards') if c['id'] == card_id and c['target_id'] == me), None)
        d = card and self.decision(card_id)
        if not d or d['decision'] != 'accept':
            return Reply(404, {'detail': '수락을 찾을 수 없어요'})
        if any(a['card_id'] == card_id for a in self.rows('acceptance_responses')):
            return Reply(409, {'detail': '이미 답한 수락이에요'})
        if self.rules['ttl_check'] and at(d['decided_at']) <= now - timedelta(days=self.rules['ttl_days']):
            return Reply(410, {'detail': '기한이 지났어요'})
        choice = sent['body']['decision']
        self.rows('acceptance_responses').append({'card_id': card_id, 'responder_id': me, 'decision': choice, 'decided_at': now.isoformat()})
        if choice != 'accept':
            return Reply(200, {'matched': False})
        match = {'id': str(uuid.uuid4()), 'profile_a': min(me, card['owner_id']), 'profile_b': max(me, card['owner_id']),
                 'created_at': now.isoformat()}
        self.rows('matches').append(match)
        return Reply(200, {'matched': True, 'match_id': match['id']})

    def _pause(self, sent):
        self.profile(self.who(sent))['matching_paused'] = sent['body']['paused']
        return Reply(200, {'ok': True})

    def _counts(self, sent):
        now, found = self.now(), {}
        for p in self.profiles.values():
            if (p['status'] == 'active' and (self.rules['count_paused'] or not p['matching_paused']) and p['gender']
                    and at(p['last_active_at']) > now - timedelta(days=self.rules['active_days'])):
                found[p['gender']] = found.get(p['gender'], 0) + 1
        return Reply(200, [{'region_group': 'e2e', 'gender': g, 'active_count': n} for g, n in found.items()])

    # ── 하트 · 투표 ──
    def _grant(self, sent):
        body = sent['body']
        self.rows('heart_transactions').append({'id': str(uuid.uuid4()), 'profile_id': body['p_profile_id'], 'amount': body['p_amount'],
                                                'reason': body['p_reason'], 'ref_id': body['p_ref_id'], 'created_at': self.now().isoformat()})
        return Reply(204, None)

    def _window(self, kind, start_of, now, length):
        """[kind] 가 seoul 이면 서울 달력 경계, rolling 이면 지금부터 거꾸로 [length]."""
        return (start_of(now), start_of(now) + length) if kind == 'seoul' else (now - length, now + timedelta(seconds=1))

    def _votes(self, voter, now):
        return [t for t in self.rows('heart_transactions') if t['profile_id'] == voter and t['reason'] == 'poll_vote']

    def _due(self, voter, now):
        mine = self._votes(voter, now)
        lo, hi = self._window(self.rules['day_window'], day_start, now, timedelta(days=1))
        wlo, whi = self._window(self.rules['week_window'], week_start, now, timedelta(days=7))
        today = any(lo <= at(t['created_at']) < hi for t in mine)
        week = sum(t['amount'] for t in mine if wlo <= at(t['created_at']) < whi)
        return not today and week + 10 <= self.rules['weekly_cap']

    def _reward_due(self, sent):
        """poll_vote_reward_due(p_voter uuid, p_now timestamptz) — 인자 이름이 다르면 PostgREST 처럼 404 PGRST202."""
        body = sent['body']
        if not isinstance(body, dict) or set(body) != {'p_voter', 'p_now'}:
            return Reply(404, {'code': 'PGRST202', 'message': 'Could not find the function'})
        when = self.now() if self.rules['rpc_ignores_p_now'] else at(body['p_now'])
        return Reply(200, self._due(body['p_voter'], when))

    def _vote(self, sent):
        poll_id, voter, now = sent['path'].split('/')[3], self.who(sent), self.now()
        due = self._due(voter, now)
        self.rows('poll_votes').append({'poll_id': poll_id, 'voter_id': voter})
        if due:
            self._grant({'body': {'p_profile_id': voter, 'p_amount': 10, 'p_reason': 'poll_vote', 'p_ref_id': None}})
        return Reply(200, {'poll': {}, 'rewarded': due})

    def _new_poll(self, sent):
        author, now = self.who(sent), self.now()
        lo, hi = self._window(self.rules['poll_day_limit_window'], day_start, now, timedelta(days=1))
        if len([p for p in self.rows('polls') if p['author_id'] == author and lo <= at(p['created_at']) < hi]) >= self.rules['poll_limit']:
            return Reply(429, {'detail': '하루에 10개까지'})
        poll = {'id': str(uuid.uuid4()), 'author_id': author, 'question': sent['body']['question'], 'created_at': now.isoformat()}
        self.rows('polls').append(poll)
        return Reply(201, {'id': poll['id']})

    def _drop_poll(self, sent):
        poll_id = sent['path'].rsplit('/', 1)[1]
        self.tables['polls'] = [p for p in self.rows('polls') if p['id'] != poll_id]
        return Reply(204, None)

    def _tasks(self, sent):
        me, now, r = self.who(sent), self.now(), self.rules
        mlo, mhi = self._window(r['month_window'], month_start, now, timedelta(days=31))
        if r['month_window'] == 'seoul':
            mhi = (mlo + timedelta(days=32)).replace(day=1)
        out = []
        for task, limit in (('everytime_post', 1), ('kakao_share', 3)):
            mine = [s for s in self.rows('heart_task_submissions') if s['profile_id'] == me and s['task'] == task]
            used = len([s for s in mine if s['status'] in ('submitted', 'approved') and mlo <= at(s['created_at']) < mhi])
            reviewing = any(s['status'] == 'submitted' and (r['reviewing_any_month'] or mlo <= at(s['created_at']) < mhi) for s in mine)
            state = 'reviewing' if reviewing else 'done' if used >= limit else 'open'
            out.append({'task': task, 'state': state, 'used': used, 'limit': limit})
        wlo, whi = self._window(r['week_window'], week_start, now, timedelta(days=7))
        votes = len([t for t in self._votes(me, now) if wlo <= at(t['created_at']) < whi])
        out.append({'task': 'poll_vote', 'state': 'open', 'used': votes, 'limit': 3})
        return Reply(200, {'tasks': out})

    def _submit(self, sent):
        task, me = sent['path'].split('/')[2], self.who(sent)
        if any(s['profile_id'] == me and s['task'] == task and s['status'] == 'submitted' for s in self.rows('heart_task_submissions')):
            return Reply(409, {'detail': IN_REVIEW})
        self.rows('heart_task_submissions').append({'id': str(uuid.uuid4()), 'profile_id': me, 'task': task, 'status': 'submitted',
                                                    'created_at': self.now().isoformat()})
        return Reply(201, {'task': {}})

    # ── 홈 ──
    def _home(self, sent):
        me, now = self.profile(self.who(sent)), self.now()
        if at(me['last_active_at']) < now - timedelta(minutes=self.rules['touch_minutes']):
            me['last_active_at'] = now.isoformat()
        return Reply(200, {})


class TimeBase(Base):
    """얼린 시계(화요일 낮) 위에서 가설을 돈다. [serve] 로 가짜 서버를 끼운다 — 시계도 같이 얼린다."""

    def setUp(self):
        super().setUp()
        self.freeze(FROZEN)

    def freeze(self, when):
        patcher = mock.patch.object(area2, '_now', lambda: when.astimezone(UTC))
        patcher.start()
        self.addCleanup(patcher.stop)
        self.when = when

    def server(self, **rules):
        fake = Server(**rules)
        fake.clock = lambda: self.when.astimezone(UTC)
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    def case(self, number):
        return T.attempt(self.run, number)

    def passes(self, number, **rules):
        self.server(**rules)
        result, memo = self.case(number)
        self.assertEqual(result, 'pass', f'{number}: {memo}')

    def fails(self, number, *words, **rules):
        self.server(**rules)
        result, memo = self.case(number)
        self.assertEqual(result, 'fail', f'{number}: {result} {memo}')
        for word in words:
            self.assertIn(word, memo)


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

NUMBERS = ('E-CARD-10 E-CARD-32 E-CARD-50 E-CARD-51 E-CARD-52 E-CARD-53 E-CARD-54 E-CARD-68 E-CARD-80 E-CARD-81 E-CARD-84 '
           'E-POLL-07 E-POLL-08 E-POLL-09 E-POLL-16 E-HEART-17 E-HEART-18 E-HOME-07 E-HOME-08').split()


class RegistryTest(unittest.TestCase):
    def test_exactly_the_19_assigned_hypotheses_and_none_is_taken_by_another_module(self):
        self.assertEqual(sorted(T.CASES), sorted(NUMBERS))
        self.assertEqual(len(NUMBERS), 19)
        for module in (area1, area2, area3, area3_safe):
            self.assertFalse(set(T.CASES) & set(module.CASES), module.__name__)

    def test_bundle_lists_every_case_in_order(self):
        self.assertEqual(T.BUNDLES, {'area2-time-api': list(T.CASES)})

    def test_every_case_is_reachable_from_the_command_line(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area2-time-api'], list(T.CASES))
        self.assertTrue(all(main.API_CASES[c] is T for c in T.CASES))


MIDNIGHT = datetime(2026, 10, 6, 23, 59, 30, tzinfo=SEOUL)
LAST_DAY = datetime(2026, 10, 31, 23, 59, 30, tzinfo=SEOUL)
WAIT = '지금은 실행 금지 시간 — 자정 직후(00:01)에 다시'


class MidnightGuardTest(TimeBase):
    def test_refusal_is_given_only_inside_the_last_60_seconds_before_seoul_midnight(self):
        self.assertEqual(T.midnight_refusal(MIDNIGHT), WAIT)
        self.assertIsNotNone(T.midnight_refusal(datetime(2026, 10, 6, 23, 59, 1, tzinfo=SEOUL)))
        self.assertIsNone(T.midnight_refusal(datetime(2026, 10, 6, 23, 59, 0, tzinfo=SEOUL)))  # 정확히 60초 남음 — 통과
        self.assertIsNone(T.midnight_refusal(FROZEN))
        self.assertIsNone(T.midnight_refusal(datetime(2026, 10, 7, 0, 0, 0, tzinfo=SEOUL)))

    def test_midnight_is_read_in_seoul_even_for_a_utc_clock(self):
        self.assertIsNotNone(T.midnight_refusal(MIDNIGHT.astimezone(UTC)))  # 14:59:30 UTC

    def test_month_refusal_is_given_only_inside_the_last_60_seconds_before_the_seoul_month_changes(self):
        self.assertEqual(T.month_end_refusal(LAST_DAY), WAIT)
        self.assertIsNone(T.month_end_refusal(MIDNIGHT))  # 달 중간 자정 직전은 17 과 상관없다
        self.assertIsNone(T.month_end_refusal(datetime(2026, 10, 31, 23, 58, 0, tzinfo=SEOUL)))
        self.assertIsNotNone(T.month_end_refusal(datetime(2026, 12, 31, 23, 59, 30, tzinfo=SEOUL)))  # 해가 바뀌는 달

    def test_now_seoul_follows_the_frozen_clock_and_can_be_patched(self):
        self.assertEqual(T.now_seoul(), FROZEN)
        with mock.patch.object(T, 'now_seoul', return_value=MIDNIGHT):
            self.assertEqual(T.now_seoul(), MIDNIGHT)

    def test_poll_07_and_16_end_blocked_before_any_write_just_before_midnight(self):
        self.freeze(MIDNIGHT)
        fake = self.server()
        for number in ('E-POLL-07', 'E-POLL-16'):
            self.assertEqual(self.case(number), ('blocked', WAIT), number)
        self.assertEqual([s for s in fake.sent if s['method'] != 'GET'], [])  # 계정도 안 만들었다

    def test_heart_17_ends_blocked_before_any_write_just_before_the_month_changes(self):
        self.freeze(LAST_DAY)
        fake = self.server()
        self.assertEqual(self.case('E-HEART-17'), ('blocked', WAIT))
        self.assertEqual([s for s in fake.sent if s['method'] != 'GET'], [])

    def test_the_guard_does_not_touch_other_hypotheses_or_a_mid_month_midnight(self):
        self.freeze(LAST_DAY)
        self.server()
        self.assertEqual(self.case('E-CARD-32')[0], 'pass')  # 자정 근처여도 시각에 안 걸린 가설은 돈다
        self.freeze(MIDNIGHT)  # 달 중간 자정 직전 — 17 은 돈다
        self.assertEqual(self.case('E-HEART-17')[0], 'pass')

    def test_the_guard_is_read_through_now_seoul_not_the_wall_clock(self):
        with mock.patch.object(T, 'now_seoul', return_value=MIDNIGHT):
            self.server()
            self.assertEqual(self.case('E-POLL-07'), ('blocked', WAIT))


class ClockHelpersTest(unittest.TestCase):
    def test_boundaries_are_seoul_calendar_boundaries(self):
        self.assertEqual(T.seoul_day_start(FROZEN), datetime(2026, 10, 6, tzinfo=SEOUL))
        self.assertEqual(T.seoul_week_start(FROZEN), datetime(2026, 10, 5, tzinfo=SEOUL))
        self.assertEqual(T.seoul_month_start(FROZEN), datetime(2026, 10, 1, tzinfo=SEOUL))
        self.assertEqual(T.seoul_week_start(datetime(2026, 10, 4, 23, 59, tzinfo=SEOUL)), datetime(2026, 9, 28, tzinfo=SEOUL))  # 일요일은 지난주
        self.assertEqual(T.seoul_day_start(datetime(2026, 10, 5, 16, 0, tzinfo=UTC)), datetime(2026, 10, 6, tzinfo=SEOUL))  # UTC 16시 = 서울 다음 날 01시

    def test_vote_slots_sit_before_today_so_only_the_weekly_rule_can_block(self):
        slots = T.vote_slots_this_week(FROZEN)
        self.assertEqual(slots, [datetime(2026, 10, 5, 0, 0, 10, tzinfo=SEOUL), datetime(2026, 10, 5, 0, 10, tzinfo=SEOUL),
                                 datetime(2026, 10, 5, 0, 20, tzinfo=SEOUL)])
        self.assertTrue(all(s < T.seoul_day_start(FROZEN) for s in slots))

    def test_on_monday_there_is_no_earlier_day_this_week(self):
        self.assertIsNone(T.vote_slots_this_week(MONDAY))

    def test_sunday_slot_is_last_weeks_23_59_and_the_others_stay_this_week_when_they_can(self):
        tuesday = T.vote_slots_with_sunday(FROZEN)
        self.assertEqual(tuesday[-1], datetime(2026, 10, 4, 23, 59, tzinfo=SEOUL))
        self.assertEqual(len([s for s in tuesday if s >= T.seoul_week_start(FROZEN)]), 2)
        monday = T.vote_slots_with_sunday(MONDAY)  # 월요일엔 이번 주 앞 날이 없어 셋 다 지난 일요일 밤
        self.assertEqual(monday[-1], datetime(2026, 10, 4, 23, 59, tzinfo=SEOUL))
        self.assertTrue(all(s < T.seoul_week_start(MONDAY) for s in monday))
        self.assertEqual(len(set(monday)), 3)


# ── 사다리 · 후보 시간 규칙 ─────────────────────────────────────────────────────────────────────────

class LadderCountTest(TimeBase):
    def test_10_counts_drop_by_two_when_one_pauses_and_one_goes_15_days_quiet(self):
        self.passes('E-CARD-10')

    def test_10_fails_when_the_ladder_still_counts_a_paused_person(self):
        self.fails('E-CARD-10', '줄어든 수 1', count_paused=True)

    def test_10_fails_when_the_ladder_window_is_longer_than_14_days(self):
        self.fails('E-CARD-10', active_days=16)

    def test_10_a_13_day_quiet_person_is_still_counted_so_the_window_is_not_shorter_than_14_days(self):
        self.fails('E-CARD-10', active_days=12)

    def test_10_fails_when_the_database_lets_an_active_account_lose_its_gender(self):
        self.fails('E-CARD-10', '23514', gender_check=False)

    def test_10_is_blocked_when_the_counts_cannot_be_read(self):
        fake = self.server()
        fake.override('POST', r'/rest/v1/rpc/region_active_counts', Reply(500, {'message': 'boom'}))
        result, memo = self.case('E-CARD-10')
        self.assertEqual(result, 'blocked', memo)
        self.assertIn('region_active_counts', memo)

    def test_10_calls_the_counts_function_with_the_service_key_and_reads_the_test_school_region(self):
        fake = self.server()
        self.case('E-CARD-10')
        calls = [s for s in fake.sent if s['path'] == '/rest/v1/rpc/region_active_counts']
        self.assertGreaterEqual(len(calls), 2)
        self.assertTrue(all(c['auth'] == 'svc' for c in calls))
        self.assertTrue(any(s['path'] == '/rest/v1/universities' and s['query'].get('select') == 'region_group' for s in fake.sent))

    def test_10_a_gender_less_active_account_is_refused_by_the_database(self):
        # profiles_active_requires_onboarding — 가짜 서버가 이 check 를 모르면 시험이 의미 없다. 가설이 보내는 값만 본다.
        fake = self.server()
        self.case('E-CARD-10')
        nulls = [s for s in fake.by('PATCH', '/rest/v1/profiles') if s['body'].get('gender', 'x') is None]
        self.assertEqual(len(nulls), 1)


class CandidateWindowTest(TimeBase):
    def test_32_15_days_1_minute_is_out_and_14_days_23_hours_is_in(self):
        self.passes('E-CARD-32')

    def test_32_fails_when_the_window_is_14_days(self):
        self.fails('E-CARD-32', candidate_days=14)

    def test_32_fails_when_the_window_is_16_days(self):
        self.fails('E-CARD-32', candidate_days=16)

    def test_32_moves_last_active_at_of_the_two_candidates_only(self):
        fake = self.server()
        self.case('E-CARD-32')
        moved = [(s['query']['id'], s['body']['last_active_at']) for s in fake.by('PATCH', '/rest/v1/profiles') if 'last_active_at' in s['body']]
        self.assertEqual([m[0] for m in moved], ['eq.id-2', 'eq.id-3'])  # id-1 은 오너 A — 시계를 안 옮긴다
        gaps = [FROZEN - at(m[1]) for m in moved]
        self.assertEqual(gaps, [timedelta(days=15, minutes=1), timedelta(days=14, hours=23)])

    def test_32_is_blocked_when_candidates_cannot_be_read(self):
        fake = self.server()
        fake.override('GET', r'/matching/candidates', Reply(500, {'detail': 'x'}))
        self.assertEqual(self.case('E-CARD-32')[0], 'blocked')


class RestingTest(TimeBase):
    """결정 90일 · 만료 14일 · 수락 응답 90일 · 매칭 영구."""

    def test_50_a_decision_89_days_ago_still_hides_the_person(self):
        self.passes('E-CARD-50')

    def test_50_fails_when_the_rest_is_shorter_than_90_days(self):
        self.fails('E-CARD-50', decided_days=80)

    def test_51_a_decision_90_days_and_1_minute_ago_lets_the_person_back(self):
        self.passes('E-CARD-51')

    def test_51_fails_when_the_decision_hides_longer_than_90_days(self):
        self.fails('E-CARD-51', decided_days=120)

    def test_50_and_51_move_the_decision_row_of_the_card_not_other_rows(self):
        fake = self.server()
        self.case('E-CARD-50')
        card = fake.rows('daily_cards')[0]['id']
        patches = fake.by('PATCH', '/rest/v1/card_decisions')
        self.assertEqual([p['query'] for p in patches], [{'card_id': f'eq.{card}'}])
        self.assertEqual(FROZEN.astimezone(UTC) - at(patches[0]['body']['decided_at']), timedelta(days=89))

    def test_52_expired_13_days_ago_hides_and_14_days_1_minute_ago_lets_back(self):
        self.passes('E-CARD-52')

    def test_52_fails_when_an_expired_card_hides_less_than_14_days(self):
        self.fails('E-CARD-52', expired_days=10)

    def test_52_fails_when_an_expired_card_hides_longer_than_14_days(self):
        self.fails('E-CARD-52', expired_days=20)

    def test_52_the_card_is_undecided_and_already_expired(self):
        fake = self.server()
        self.case('E-CARD-52')
        card = fake.rows('daily_cards')[0]
        self.assertEqual(fake.rows('card_decisions'), [])
        self.assertEqual(FROZEN.astimezone(UTC) - at(card['expires_at']), timedelta(days=14, minutes=1))  # 마지막으로 옮긴 값

    def test_53_an_answer_to_a_received_acceptance_rests_90_days_too(self):
        self.passes('E-CARD-53')

    def test_53_fails_when_the_answer_does_not_rest_the_person_at_all(self):
        self.fails('E-CARD-53', ar_clause=False)

    def test_53_fails_when_the_answer_rests_less_than_90_days(self):
        self.fails('E-CARD-53', ar_days=80)

    def test_53_fails_when_the_answer_rests_longer_than_90_days(self):
        self.fails('E-CARD-53', ar_days=120)

    def test_53_the_answer_row_is_moved_by_card_id(self):
        fake = self.server()
        self.case('E-CARD-53')
        card = fake.rows('daily_cards')[0]['id']
        self.assertEqual([p['query'] for p in fake.by('PATCH', '/rest/v1/acceptance_responses')],
                         [{'card_id': f'eq.{card}'}, {'card_id': f'eq.{card}'}])

    def test_54_a_matched_pair_never_comes_back_even_400_days_later(self):
        self.passes('E-CARD-54')

    def test_54_fails_when_matching_stops_hiding_the_pair(self):
        self.fails('E-CARD-54', matches_block=False)

    def test_54_fails_when_only_one_side_of_the_pair_is_hidden(self):
        self.fails('E-CARD-54', 'V 의 후보', matches_block='low_side_only')

    def test_54_moves_every_time_column_of_the_pair_to_400_days_ago(self):
        fake = self.server()
        self.case('E-CARD-54')
        tables = {'card_decisions', 'acceptance_responses', 'matches'}
        patched = {s['path'].rsplit('/', 1)[1]: s['body'] for s in fake.by('PATCH', '/rest/v1/') if s['path'].rsplit('/', 1)[1] in tables}
        self.assertEqual(set(patched), tables)
        for body in patched.values():
            self.assertEqual(FROZEN.astimezone(UTC) - at(next(iter(body.values()))), timedelta(days=400))

    def test_54_is_blocked_when_the_pair_cannot_be_matched(self):
        fake = self.server()
        fake.override('POST', r'/cards/acceptances/[^/]+', Reply(404, {'detail': 'x'}))
        self.assertEqual(self.case('E-CARD-54')[0], 'blocked')

    def test_50_is_blocked_when_the_pair_is_not_candidates_to_begin_with(self):
        fake = self.server()
        fake.override('GET', r'/matching/candidates', Reply(200, {'candidates': []}))
        self.assertEqual(self.case('E-CARD-50')[0], 'blocked')


class ActivityCoefficientTest(TimeBase):
    def test_68_scores_are_1_0_0_7_0_4_by_days_since_last_active(self):
        self.passes('E-CARD-68')

    def test_68_fails_naming_the_candidate_when_a_coefficient_is_off(self):
        self.fails('E-CARD-68', '0.8', coef={3: 1.0, 7: 0.8})

    def test_68_clones_are_moved_to_3d23h_5d_and_10d(self):
        fake = self.server()
        self.case('E-CARD-68')
        gaps = [FROZEN - at(s['body']['last_active_at']) for s in fake.by('PATCH', '/rest/v1/profiles') if 'last_active_at' in s['body']]
        self.assertEqual(gaps, [timedelta(days=3, hours=23), timedelta(days=5), timedelta(days=10)])

    def test_68_clones_are_female_copies_of_the_perfect_candidate(self):
        fake = self.server()
        self.case('E-CARD-68')
        profiles = [s['body'] for s in fake.by('PATCH', '/rest/v1/profiles') if 'gender' in s['body']]
        self.assertEqual([p['gender'] for p in profiles], ['male', 'female', 'female', 'female'])
        self.assertEqual(profiles[1]['interest_tags'], area2.TAGS['interest_tags'])


# ── 받은 수락 7일 · 카드 만료 ───────────────────────────────────────────────────────────────────────

class AcceptanceTtlTest(TimeBase):
    def test_80_list_carries_decided_at_plus_7_days_for_a_6d23h_old_acceptance(self):
        self.passes('E-CARD-80')

    def test_80_fails_when_the_list_already_hides_a_6d23h_acceptance(self):
        self.fails('E-CARD-80', ttl_days=5)

    def test_80_fails_when_the_expiry_is_not_decided_at_plus_7_days(self):
        self.fails('E-CARD-80', '시각', ttl_days=8)

    def test_81_after_7_days_the_list_is_empty_and_answering_is_410_with_no_match(self):
        self.passes('E-CARD-81')

    def test_81_fails_when_an_expired_acceptance_can_still_be_answered(self):
        self.fails('E-CARD-81', ttl_check=False)

    def test_84_an_expired_card_cannot_be_accepted_and_leaves_no_decision(self):
        self.passes('E-CARD-84')

    def test_84_fails_when_the_server_accepts_an_expired_card(self):
        self.fails('E-CARD-84', '409', expiry_check=False)

    def test_84_the_card_is_opened_before_it_expires(self):
        fake = self.server()
        self.case('E-CARD-84')
        steps = []
        for s in fake.sent:
            if s['method'] == 'GET' and re.fullmatch(r'/cards/[^/]+', s['path']):
                steps.append('열기')
            elif (s['method'], s['path']) == ('PATCH', '/rest/v1/daily_cards'):
                steps.append('만료로 옮김')
            elif s['path'].endswith('/decision'):
                steps.append('수락')
        self.assertEqual(steps, ['열기', '만료로 옮김', '수락'])


# ── 투표 하트 ───────────────────────────────────────────────────────────────────────────────────────

class PollTimeTest(TimeBase):
    def test_07_a_vote_after_seoul_midnight_pays_10_again(self):
        self.passes('E-POLL-07')

    def test_07_fails_when_the_day_is_a_rolling_24_hours(self):
        self.fails('E-POLL-07', day_window='rolling')

    def test_07_moves_the_ledger_row_to_yesterday_23_59_seoul(self):
        fake = self.server()
        self.case('E-POLL-07')
        patches = fake.by('PATCH', '/rest/v1/heart_transactions')
        self.assertEqual(len(patches), 1)
        self.assertEqual(at(patches[0]['body']['created_at']), datetime(2026, 10, 5, 23, 59, tzinfo=SEOUL))

    def test_ledger_moves_carry_the_account_filter_as_a_second_guard(self):
        fake = self.server()
        self.case('E-POLL-08')
        patches = fake.by('PATCH', '/rest/v1/heart_transactions')
        self.assertEqual(len(patches), 3)
        for patch in patches:
            self.assertEqual(set(patch['query']), {'id', 'profile_id'})
            self.assertEqual(patch['query']['profile_id'], 'eq.id-2')  # 투표자 = 두 번째로 만든 계정(작성자 id-1)

    def test_07_drops_the_polls_it_posted(self):
        fake = self.server()
        self.case('E-POLL-07')
        self.assertEqual(fake.rows('polls'), [])

    def test_08_a_full_week_of_30_pays_nothing_even_on_the_first_vote_of_the_day(self):
        self.passes('E-POLL-08')

    def test_08_fails_when_the_weekly_cap_is_40(self):
        self.fails('E-POLL-08', 'rewarded', weekly_cap=40)

    def test_08_seeds_three_ledger_rows_on_this_weeks_monday_through_the_ledger_function(self):
        fake = self.server()
        self.case('E-POLL-08')
        grants = [s for s in fake.sent if s['path'] == '/rest/v1/rpc/grant_hearts']
        self.assertEqual([g['body']['p_reason'] for g in grants], ['poll_vote'] * 3)  # 원장만이 아니라 잔액 캐시도 같이 간다
        moved = sorted(at(s['body']['created_at']) for s in fake.by('PATCH', '/rest/v1/heart_transactions'))
        self.assertEqual(moved, [datetime(2026, 10, 5, 0, 0, 10, tzinfo=SEOUL), datetime(2026, 10, 5, 0, 10, tzinfo=SEOUL),
                                 datetime(2026, 10, 5, 0, 20, tzinfo=SEOUL)])

    def test_08_on_monday_the_function_is_asked_as_of_last_wednesday_and_says_no(self):
        self.freeze(MONDAY)
        self.passes('E-POLL-08')

    def test_08_on_monday_fails_when_the_weekly_cap_is_40(self):
        self.freeze(MONDAY)
        self.fails('E-POLL-08', 'poll_vote_reward_due', weekly_cap=40)

    def test_08_on_monday_fails_when_the_server_function_ignores_p_now(self):
        self.freeze(MONDAY)  # p_now 를 무시하면 월요일 기준이라 지난주 줄이 안 세어져 true — 이 가설이 p_now 를 실제로 보낸다는 증거
        self.fails('E-POLL-08', 'rewarded', rpc_ignores_p_now=True)

    def test_08_on_monday_moves_three_rows_to_last_weeks_monday_monday_tuesday_and_asks_with_p_voter_and_p_now(self):
        self.freeze(MONDAY)
        fake = self.server()
        self.case('E-POLL-08')
        moved = sorted(at(s['body']['created_at']) for s in fake.by('PATCH', '/rest/v1/heart_transactions'))
        self.assertEqual(moved, [datetime(2026, 9, 28, 0, 0, 10, tzinfo=SEOUL), datetime(2026, 9, 28, 0, 10, tzinfo=SEOUL),
                                 datetime(2026, 9, 29, 0, 20, tzinfo=SEOUL)])
        asked = [s['body'] for s in fake.by('POST', '/rest/v1/rpc/poll_vote_reward_due')]
        self.assertEqual(asked[0], {'p_voter': 'id-1', 'p_now': datetime(2026, 9, 30, 12, 0, tzinfo=SEOUL).isoformat()})  # 지난주 수요일 낮
        self.assertEqual(len(asked), 1)
        self.assertEqual(fake.by('POST', '/community/polls'), [])  # 월요일 분기는 API 투표를 안 한다

    def test_08_on_monday_is_blocked_when_the_function_is_missing(self):
        self.freeze(MONDAY)
        fake = self.server()
        fake.override('POST', r'/rest/v1/rpc/poll_vote_reward_due', Reply(404, {'code': 'PGRST202'}))
        self.assertEqual(self.case('E-POLL-08')[0], 'blocked')

    def test_08_on_monday_rows_are_last_week_so_only_the_weekly_rule_can_say_no(self):
        slots = T.vote_slots_last_week(MONDAY)
        self.assertTrue(all(s < T.seoul_week_start(MONDAY) for s in slots))
        self.assertEqual(T.reward_check_time(MONDAY), datetime(2026, 9, 30, 12, 0, tzinfo=SEOUL))
        self.assertTrue(all(T.seoul_week_start(s) == T.seoul_week_start(T.reward_check_time(MONDAY)) for s in slots))  # 셋 다 그 수요일과 같은 주
        self.assertTrue(all(T.seoul_day_start(s) < T.seoul_day_start(T.reward_check_time(MONDAY)) for s in slots))  # 수요일 "오늘" 에 안 든다

    def test_09_a_sunday_23_59_row_does_not_count_this_week(self):
        self.passes('E-POLL-09')

    def test_09_fails_when_last_sundays_row_still_counts(self):
        self.fails('E-POLL-09', week_window='rolling')

    def test_09_on_monday_all_three_rows_are_last_week_and_it_still_runs(self):
        self.freeze(MONDAY)
        self.passes('E-POLL-09')

    def test_09_on_monday_fails_when_last_sundays_rows_still_count(self):
        self.freeze(MONDAY)
        self.fails('E-POLL-09', week_window='rolling')

    def test_16_the_11th_post_is_429_until_the_ten_move_to_yesterday_then_201(self):
        self.passes('E-POLL-16')

    def test_16_fails_when_the_daily_window_is_a_rolling_24_hours(self):
        self.fails('E-POLL-16', '429', poll_day_limit_window='rolling')

    def test_16_moves_only_the_authors_polls_and_drops_all_11_afterwards(self):
        fake = self.server()
        self.case('E-POLL-16')
        patches = fake.by('PATCH', '/rest/v1/polls')
        self.assertEqual([p['query'] for p in patches], [{'author_id': 'eq.id-1'}])
        self.assertEqual(at(patches[0]['body']['created_at']), datetime(2026, 10, 5, 23, 59, tzinfo=SEOUL))
        self.assertEqual(fake.rows('polls'), [])


# ── 무료 하트 한도 ──────────────────────────────────────────────────────────────────────────────────

class MonthTest(TimeBase):
    def test_17_last_months_approval_does_not_count_and_this_months_first_second_does(self):
        self.passes('E-HEART-17')

    def test_17_fails_when_the_month_is_a_rolling_30_days(self):
        self.fails('E-HEART-17', month_window='rolling')

    def test_17_inserts_approved_rows_with_reviewed_at_and_no_proof_file(self):
        fake = self.server()
        self.case('E-HEART-17')
        rows = fake.rows('heart_task_submissions')
        self.assertEqual({r['task'] for r in rows}, {'everytime_post', 'kakao_share'})
        by_task = {r['task']: r for r in rows}
        self.assertEqual(at(by_task['everytime_post']['created_at']), datetime(2026, 9, 30, 23, 59, 59, tzinfo=SEOUL))
        self.assertEqual(at(by_task['kakao_share']['created_at']), datetime(2026, 10, 1, 0, 0, 0, tzinfo=SEOUL))
        for row in rows:
            self.assertEqual((row['status'], row['reward_hearts']), ('approved', 50))
            self.assertIsNotNone(row['reviewed_at'])  # heart_task_submissions_reviewed_at check
            self.assertIsNone(row.get('storage_path'))  # 승인 줄은 파일 칸이 null 이어도 된다(60일 정리 뒤 모양)

    def test_18_a_submitted_row_from_last_month_still_reads_reviewing_and_blocks_a_new_one(self):
        self.passes('E-HEART-18')

    def test_18_fails_when_last_months_review_stops_blocking(self):
        self.fails('E-HEART-18', reviewing_any_month=False)

    def test_18_inserts_a_submitted_row_without_review_time_and_leaves_no_new_file(self):
        fake = self.server()
        self.case('E-HEART-18')
        rows = fake.rows('heart_task_submissions')
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]['status'], rows[0].get('reviewed_at')), ('submitted', None))
        self.assertLess(at(rows[0]['created_at']), T.seoul_month_start(FROZEN))
        self.assertTrue(rows[0]['storage_path'].startswith('id-1/'))

    def test_18_is_blocked_when_the_row_cannot_be_inserted(self):
        fake = self.server()
        fake.override('POST', r'/rest/v1/heart_task_submissions', Reply(400, {'code': '23514'}))
        self.assertEqual(self.case('E-HEART-18')[0], 'blocked')


# ── 마지막 접속 ─────────────────────────────────────────────────────────────────────────────────────

class LastActiveTest(TimeBase):
    def test_07_a_2_hour_old_last_active_is_set_to_now_when_home_opens(self):
        self.passes('E-HOME-07')

    def test_07_fails_when_the_interval_is_so_long_that_2_hours_is_not_refreshed(self):
        self.fails('E-HOME-07', touch_minutes=180)

    def test_08_a_30_minute_old_last_active_is_left_alone(self):
        self.passes('E-HOME-08')

    def test_08_fails_when_the_interval_is_so_short_that_30_minutes_is_refreshed(self):
        self.fails('E-HOME-08', touch_minutes=10)

    def test_07_08_call_the_home_summary_with_the_users_token_and_read_the_column_back(self):
        fake = self.server()
        self.case('E-HOME-07')
        self.assertEqual([(s['path'], s['auth']) for s in fake.sent if s['path'] == '/home/summary'], [('/home/summary', 'tok-1')])
        reads = [s for s in fake.by('GET', '/rest/v1/profiles') if s['query'].get('select') == 'last_active_at']
        self.assertGreaterEqual(len(reads), 2)

    def test_07_is_blocked_when_home_summary_fails_to_answer(self):
        fake = self.server()
        fake.override('GET', r'/home/summary', Reply(500, {'detail': 'x'}))
        result, memo = self.case('E-HOME-07')
        self.assertIn(result, ('fail', 'blocked'))


# ── 안전망 ──────────────────────────────────────────────────────────────────────────────────────────

class SafetyNetTest(TimeBase):
    def test_every_case_ends_as_fail_or_blocked_when_the_server_is_down(self):
        patcher = mock.patch.object(tools, 'call', lambda method, url, *a, **k: Reply(500, {'detail': '서버'}))
        patcher.start()
        self.addCleanup(patcher.stop)
        for number in T.CASES:
            result, memo = T.attempt(self.run, number)
            self.assertIn(result, ('fail', 'blocked'), number)
            self.assertIsInstance(memo, str, number)

    def test_every_case_ends_as_fail_or_blocked_when_every_write_is_refused(self):
        fake = self.server()
        for method in ('POST', 'PATCH', 'DELETE'):
            fake.override(method, r'/rest/v1/(?!rpc/region).*', Reply(400, {'code': 'x', 'message': 'refused'}))
        for number in T.CASES:
            result, memo = T.attempt(self.run, number)
            self.assertIn(result, ('fail', 'blocked'), number)
            self.assertIsInstance(memo, str, number)

    def test_unknown_columns_and_tables_are_400_like_postgrest(self):
        fake = Server()
        got = fake('GET', 'https://sb.test/rest/v1/card_decisions?select=id', {})
        self.assertEqual(got[0], 400)
        got = fake('PATCH', 'https://sb.test/rest/v1/profiles?id=eq.x', {}, {'no_such': 1})
        self.assertEqual(got[0], 400)
        got = fake('GET', 'https://sb.test/rest/v1/matches?or=(profile_a.eq.x,profile_b.eq.x)&select=id', {})
        self.assertEqual(got[0], 200)

    def test_every_case_passes_on_the_correct_server_with_known_columns_and_writes_stay_on_this_runs_accounts(self):
        fake = self.server()
        got = {n: self.case(n) for n in NUMBERS}  # 19 가설을 한 번만 돈다 — 계정 공장이 느려 시험을 나누면 몇 분이 걸린다
        self.assertEqual({n: r for n, (r, m) in got.items()}, {n: 'pass' for n in NUMBERS}, {n: m for n, (r, m) in got.items() if r != 'pass'})
        tables = {s['path'].rsplit('/', 1)[1] for s in fake.sent if s['path'].startswith('/rest/v1/') and '/rpc/' not in s['path']}
        self.assertTrue({'daily_cards', 'card_decisions', 'acceptance_responses', 'matches', 'polls', 'heart_transactions',
                         'heart_task_submissions', 'profiles'} <= tables)
        self.assertEqual(tables - set(SCHEMA), {'profile_vectors', 'universities', 'university_email_domains', 'profile_avatars',
                                             'school_email_claims'})  # 계정 공장 몫
        mine = area2._mine(self.run)
        ledger = {r['id']: r['profile_id'] for r in fake.rows('heart_transactions')}
        cards = {c['id']: {c['owner_id'], c['target_id']} for c in fake.rows('daily_cards')}
        for sent in fake.by('PATCH', '/rest/v1/'):
            table, query = sent['path'].rsplit('/', 1)[1], sent['query']
            if table == 'profiles':
                owners = {query['id'][3:]}
            elif table == 'polls':
                owners = {query['author_id'][3:]}
            elif table == 'heart_transactions':
                owners = {ledger[query['id'][3:]]}
            elif table == 'daily_cards':
                owners = cards[query['id'][3:]]
            elif table in ('card_decisions', 'acceptance_responses'):
                owners = cards[query['card_id'][3:]]
            else:  # matches — 카드를 거친 두 사람
                owners = {m['profile_a'] for m in fake.rows('matches') if m['id'] == query['id'][3:]}
            self.assertTrue(owners and owners <= mine, sent)
        for sent in fake.by('POST', '/rest/v1/'):
            for row in sent['body'] if isinstance(sent['body'], list) else [sent['body']]:
                for key in ('profile_id', 'owner_id', 'author_id'):
                    if key in row:
                        self.assertIn(row[key], mine, sent)

    def test_a_time_write_to_a_stranger_is_refused_by_the_helper_itself(self):
        fake = self.server()
        with self.assertRaises(tools.Blocked):
            T._move(self.run, 'card_decisions?card_id=eq.x', {'decided_at': 'x'}, 'someone-elses-id')
        self.assertEqual(fake.by('PATCH', '/rest/v1/'), [])

    def test_a_stranger_id_is_refused_before_any_write(self):
        fake = self.server()
        with mock.patch.object(area2, '_mine', return_value=set()):
            result, memo = self.case('E-CARD-32')
        self.assertEqual(result, 'blocked')
        self.assertIn('이번 실행이 만든 계정이 아니라', memo)
        self.assertEqual([s for s in fake.by('PATCH', '/rest/v1/profiles') if 'last_active_at' in s['body']], [])  # 계정 공장의 값 쓰기는 별개


class SentOnceTest(TimeBase):
    """두 번 적용되면 결과가 달라지는 요청은 끊겨도 다시 보내지 않는다(retry=False)."""

    def sent_options(self, number, method, piece):
        fake = self.server()
        self.case(number)
        got = [o for m, p, o in fake.options if m == method and piece in p]
        self.assertTrue(got, f'{number}: {method} {piece} 를 안 보냄')
        return got

    def test_votes_polls_decisions_responses_and_grants_are_sent_once(self):
        for number, method, piece in (('E-POLL-07', 'POST', '/votes'), ('E-POLL-16', 'POST', '/community/polls'),
                                      ('E-CARD-50', 'POST', '/decision'), ('E-CARD-53', 'POST', '/cards/acceptances/'),
                                      ('E-POLL-08', 'POST', 'rpc/grant_hearts'), ('E-HEART-18', 'POST', '/submissions')):
            with self.subTest(number):
                self.assertTrue(all(o == {'retry': False} for o in self.sent_options(number, method, piece)), number)

    def test_reads_and_time_patches_keep_the_default_retry(self):
        for number, method, piece in (('E-CARD-32', 'GET', '/matching/candidates'), ('E-HOME-07', 'GET', '/home/summary'),
                                      ('E-CARD-32', 'PATCH', '/rest/v1/profiles')):
            with self.subTest(number):
                self.assertTrue(all(o == {} for o in self.sent_options(number, method, piece)), number)


class AttemptTest(TimeBase):
    def test_a_connection_that_drops_twice_is_blocked_and_once_is_retried_from_the_start(self):
        calls = []
        real = Server()
        real.clock = lambda: self.when.astimezone(UTC)

        def flaky(method, url, *args, **kwargs):
            if method == 'GET' and '/matching/candidates' in url and not calls:
                calls.append(1)
                raise ConnectionResetError('reset')
            return real(method, url, *args, **kwargs)

        patcher = mock.patch.object(tools, 'call', flaky)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(self.case('E-CARD-32')[0], 'pass')  # 한 번 끊김 → 새 계정으로 처음부터

        def always(method, url, *args, **kwargs):
            raise ConnectionResetError('reset')

        with mock.patch.object(tools, 'call', always):
            result, memo = self.case('E-CARD-32')
        self.assertEqual(result, 'blocked')


if __name__ == '__main__':
    unittest.main()
