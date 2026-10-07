"""영역 2 배치 가설(daily-cards · cleanup) 시험 — 운영 없이 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area2_time_batch`.

가짜 서버([World])는 표를 메모리에 들고, `area2._batch` 대신 호출되는 배치 흉내가 서버 규칙(backend/app/cards/issuing.py ·
ladder.py · heart_tasks/cleanup.py · 20260928050000 의 SQL)을 그대로 옮겨 DB 를 바꾼다. 올바른 서버면 pass, 규칙 하나를 어긴 서버
([World.rules] 를 한 군데 바꿈)면 fail 이어야 한다. 표 · 열 이름은 supabase/migrations 에서 읽은 실제 열과 대조한다.
"""

import re
import unittest
import uuid
from datetime import datetime, time, timedelta, timezone
from functools import lru_cache
from unittest import mock

from e2e import area2, area2_phone3, area2_time_batch as tb, batch_gate, tools
from e2e import test_area1 as t1
from e2e.area1 import SEOUL
from e2e.test_area3 import Fake as Store
from e2e.tools import ROOT, Blocked, Reply, Run

# 2026-10-05 가 월요일 — 요일마다 정오(서울)
WEEK = {name: datetime(2026, 10, 5 + i, 12, 0, tzinfo=SEOUL) for i, name in enumerate('월화수목금토일')}


def ladder(count, twice, three, four, daily):
    """backend/app/cards/ladder.py ladder_weekdays 의 사본 — 시험이 임계값 만들기를 서버 식으로 되짚는다."""
    if count >= daily:
        return [1, 2, 3, 4, 5, 6, 7]
    if count >= four:
        return [1, 3, 5, 7]
    if count >= three:
        return [1, 3, 5]
    if count >= twice:
        return [1, 4]
    return [1]


class PureTest(unittest.TestCase):
    def test_thresholds_make_every_step_come_out_of_the_server_ladder_for_any_head_count(self):
        # thresholds_for 가 칸 하나라도 어긋나면(예: 비교를 > 로) 서버 사다리가 다른 칸을 낸다
        for count in range(0, 6):
            for _, weekdays in tb.STEPS:
                got = ladder(count, *tb.thresholds_for(weekdays, count).values())
                self.assertEqual(got, weekdays, f'인원 {count}')

    def test_thresholds_never_break_the_ladder_order_check(self):
        # region_group_settings_ladder_order: twice <= three <= four <= daily (20261003020000)
        for count in range(0, 6):
            for _, weekdays in tb.STEPS:
                values = list(tb.thresholds_for(weekdays, count).values())
                self.assertEqual(values, sorted(values))

    def test_threshold_names_are_the_four_setting_columns_in_ladder_order(self):
        self.assertEqual(list(tb.thresholds_for([1], 3)), ['ladder_twice_per_week_min', 'ladder_three_per_week_min',
                                                         'ladder_four_per_week_min', 'ladder_daily_min'])

    def test_a_list_that_is_no_step_is_refused(self):
        with self.assertRaises(ValueError):
            tb.thresholds_for([1, 2], 3)

    def test_step_for_today_is_the_sparsest_step_that_contains_the_weekday(self):
        got = {name: tb.step_for_today(day.isoweekday()) for name, day in WEEK.items()}
        self.assertEqual(got, {'월': [1], '화': [1, 2, 3, 4, 5, 6, 7], '수': [1, 3, 5], '목': [1, 4], '금': [1, 3, 5],
                               '토': [1, 2, 3, 4, 5, 6, 7], '일': [1, 3, 5, 7]})

    def test_a_step_that_skips_today_is_the_once_a_week_step_except_on_monday(self):
        for name, day in WEEK.items():
            if name == '월':  # 월요일은 모든 칸에 있다 — 배치 관문이 월요일을 막는다
                with self.assertRaises(ValueError):
                    tb.step_without_today(day.isoweekday())
                continue
            self.assertEqual(tb.step_without_today(day.isoweekday()), [1], name)

    def test_expiry_is_the_next_issue_weekday_at_the_issue_time_in_seoul(self):
        seven = time(7, 0)
        want = {('수', (1, 3, 5)): ('금', 9), ('목', (1, 4)): ('월', 12), ('일', (1, 3, 5, 7)): ('월', 5 + 7), ('화', tuple(range(1, 8))): ('수', 7)}
        for (name, weekdays), (_, day) in want.items():
            got = tb.expected_expiry(WEEK[name], list(weekdays), seven)
            self.assertEqual((got.month, got.day, got.hour, got.minute, got.utcoffset()), (10, day, 7, 0, timedelta(hours=9)), name)

    def test_expiry_never_lands_on_today_even_when_today_is_an_issue_day(self):
        # 오늘 07:00 은 이미 지났다 — 서버 next_issue_at 은 내일부터 찾는다(ladder.py:next_issue_at)
        got = tb.expected_expiry(WEEK['수'], [1, 3, 5], time(7, 0))
        self.assertGreater(got.date(), WEEK['수'].date())

    def test_a_week_without_issue_days_is_refused(self):
        with self.assertRaises(ValueError):
            tb.expected_expiry(WEEK['수'], [], time(7, 0))


# ── 가짜 서버 ───────────────────────────────────────────────────────────────────────────────────────

def server_next_issue_at(now, weekdays, issue_time):
    """backend/app/cards/ladder.py next_issue_at 의 사본(가짜 서버가 쓴다 — 시험 대상 코드와 따로 써야 서로를 검증한다)."""
    for ahead in range(1, 8):
        day = (now + timedelta(days=ahead)).date()
        if day.isoweekday() in weekdays:
            return datetime.combine(day, issue_time, tzinfo=now.tzinfo)
    raise ValueError(weekdays)


@lru_cache(maxsize=1)
def migration_schema():
    """supabase/migrations 에서 표 → 열, 함수 이름을 읽는다 — 가설이 고른 표 · 열 · RPC 가 진짜 있는지 대조하는 기준."""
    tables, functions = {}, set()
    for path in sorted((ROOT / 'supabase' / 'migrations').glob('*.sql')):
        text = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
        for m in re.finditer(r'create table (?:if not exists )?public\.(\w+)\s*\(', text):
            depth, i = 1, m.end()
            while depth:
                depth += {'(': 1, ')': -1}.get(text[i], 0)
                i += 1
            items, level, current = [], 0, ''
            for ch in text[m.end():i - 1]:
                level += {'(': 1, '[': 1, ')': -1, ']': -1}.get(ch, 0)
                if ch == ',' and level == 0:
                    items.append(current)
                    current = ''
                else:
                    current += ch
            items.append(current)
            got = tables.setdefault(m.group(1), set())
            got |= {w[0].strip('"') for w in (x.split(None, 1) for x in items if x.strip())
                    if w[0].lower() not in ('constraint', 'primary', 'unique', 'check', 'foreign', 'like')}
        for m in re.finditer(r'alter table (?:only )?public\.(\w+)(.*?);', text, re.S | re.I):
            got = tables.setdefault(m.group(1), set())
            got |= set(re.findall(r'add column (?:if not exists )?(\w+)', m.group(2), re.I))
            got -= set(re.findall(r'drop column (?:if exists )?(\w+)', m.group(2), re.I))
        functions |= set(re.findall(r'create (?:or replace )?function public\.(\w+)', text, re.I))
    return tables, functions


# 열 · 필터 이름까지 대조하는 표 — 가설이 직접 읽고 쓰는 것. 나머지 표는 이름만 본다.
CHECKED = {'daily_cards', 'card_decisions', 'region_group_settings', 'universities', 'profiles', 'profile_vectors',
           'heart_task_submissions'}
RULES = dict(
    batch_runs=True, same_day_guard=True, live_blocks=True, save_ladder=True, ignore_weekday=False, bottleneck='min',
    pick='first', expiry='next', stale_days=14, hidden_gets_card=False, closed_gets_card=False, paused_gets_card=False,
    suspended_gets_card=False, novec_gets_card=False, closed_candidate=False, closed_counts=False, closed_owner_sees=False,
    hidden_candidate=False, hidden_today=False, hidden_accept=False, today_expired=False, cleanup_days=60,
    cleanup_unreviewed=False, cleanup_runs=True, expired_blocks=False, issues=True, starve=frozenset())


class World(Store):
    """표 저장소 + 서버 규칙. 계정은 만든 순서대로 id-1 · tok-1 …, 프로필은 첫 PATCH 에서 active 로 생긴다. [rules] 를 바꿔 어긋난 서버를 만든다."""

    def __init__(self, **rules):
        super().__init__()
        self.rules = {**RULES, **rules}
        self.files = set()
        self.batches = []
        self.tables['universities'] = [{'id': 'U', 'name': '테스트대학', 'region_group': 'e2e', 'card_opens_at': None}]
        self.tables['region_group_settings'] = [{
            'region_group': 'e2e', 'issue_weekdays': [1, 4], 'issue_time': '07:00:00', 'ladder_twice_per_week_min': 50,
            'ladder_three_per_week_min': 500, 'ladder_four_per_week_min': 1000, 'ladder_daily_min': 2000}]
        for method, pattern, handler in (
                ('POST', r'/rest/v1/rpc/region_active_counts', self._counts), ('GET', r'/matching/candidates', self._candidates_api),
                ('GET', r'/cards/today', self._today), ('GET', r'/cards/acceptances', self._acceptances),
                ('POST', r'/cards/[^/]+/decision', self._decide),
                ('POST', r'/storage/v1/object/heart-task-proofs/.+', self._upload),
                ('POST', r'/storage/v1/object/list/heart-task-proofs', self._list)):
            self.on(method, pattern, handler)

    # ── 표 ──
    def rows(self, name):
        return self.tables.setdefault(name, [])

    def profile(self, pid):
        row = next((r for r in self.rows('profiles') if r['id'] == pid), None)
        if row is None:
            row = {'id': pid, 'gender': None, 'status': 'active', 'matching_paused': False, 'auto_hidden_at': None,
                   'university_id': 'U', 'last_active_at': area2._now().isoformat()}
            self.rows('profiles').append(row)
        return row

    def _table(self, method, name, sent):
        tables, _ = migration_schema()
        if name not in tables:
            return Reply(404, {'code': '42P01', 'message': f'relation "public.{name}" does not exist'})
        if name in CHECKED:
            select = sent['query'].get('select', '*')
            asked = set() if select == '*' else set(select.split(','))
            asked |= {k for k in sent['query'] if k not in ('select', 'order', 'limit', 'offset')}
            for row in sent['body'] if isinstance(sent['body'], list) else [sent['body'] or {}]:
                asked |= set(row)
            unknown = sorted(asked - tables[name])
            if unknown:
                return Reply(400, {'code': '42703', 'message': f'column {name}.{unknown[0]} does not exist'})
        if name == 'profiles' and method == 'PATCH' and 'id' in sent['query']:
            self.profile(sent['query']['id'][3:])
        if name == 'daily_cards' and method == 'POST':
            for row in sent['body'] if isinstance(sent['body'], list) else [sent['body']]:
                row.setdefault('issued_at', area2._now().isoformat())
        return super()._table(method, name, sent)

    def writes(self):
        return [s for s in self.sent if s['path'].startswith('/rest/v1/') and not s['path'].startswith('/rest/v1/rpc/')
                and s['method'] in ('POST', 'PATCH', 'DELETE')]  # rpc 는 읽기 함수(region_active_counts) — 쓰기가 아니다

    # ── 규칙 ──
    @staticmethod
    def when(text):
        return datetime.fromisoformat(text.replace('Z', '+00:00'))

    def university(self, uid):
        return next(u for u in self.rows('universities') if u['id'] == uid)

    def open(self, uid):
        opens = self.university(uid)['card_opens_at']
        return opens is None or self.when(opens) <= area2._now()

    def region(self, p):
        return self.university(p['university_id'])['region_group']

    def decision(self, card_id):
        return next((d for d in self.rows('card_decisions') if d['card_id'] == card_id), None)

    def has_vectors(self, pid):
        row = next((v for v in self.rows('profile_vectors') if v['profile_id'] == pid), None)
        return bool(row) and all(row.get(k) is not None for k in ('self_survey', 'self_embedding', 'want_embedding'))

    @staticmethod
    def hidden(p):
        return p['status'] != 'active' or bool(p['auto_hidden_at'])

    def counts(self):
        """region_active_counts() — 열린 학교의 active · 일시중지 아님 · 14일 안 접속 · 성별 있음."""
        now, out = area2._now(), {}
        for p in self.rows('profiles'):
            if p['status'] == 'active' and not p['matching_paused'] and p['gender'] \
                    and self.when(p['last_active_at']) > now - timedelta(days=14) \
                    and (self.open(p['university_id']) or self.rules['closed_counts']):
                bucket = out.setdefault(self.region(p), {})
                bucket[p['gender']] = bucket.get(p['gender'], 0) + 1
        return out

    def _counts(self, sent):
        return Reply(200, [{'region_group': r, 'gender': g, 'active_count': n} for r, c in self.counts().items() for g, n in c.items()])

    def score(self, me, c):
        """간단한 점수 — 문장 · 태그가 같으면 만점, 흡연 · 종교가 다르면 감점(scoring.py 와 같은 곱셈)."""
        mine = {v['profile_id']: v for v in self.rows('profile_vectors')}
        text = 1.0 if mine.get(me['id'], {}).get('self_embedding') == mine.get(c['id'], {}).get('self_embedding') else 0.0
        tags = 1.0 if me.get('interest_tags') == c.get('interest_tags') else 0.0
        smoking = 0.5 if me.get('is_smoker') is False and c.get('is_smoker') is True else 1.0
        religion = 0.8 if me.get('religion') != c.get('religion') else 1.0
        return round((0.3 + 0.2 * tags + 0.5 * text) * smoking * religion, 4)

    def candidates(self, me_id):
        """match_candidates SQL(20260928050000) — 반대 성별 · 같은 지역 · 열린 학교 · active · 15일 · 벡터 · 일시중지 · 카드 · 가림."""
        me, now, out = self.profile(me_id), area2._now(), []
        if not (self.open(me['university_id']) or self.rules['closed_owner_sees']) \
                or not (self.has_vectors(me_id) or self.rules['novec_gets_card']):
            return out
        for c in self.rows('profiles'):
            if c['id'] == me_id or c['gender'] == me['gender'] or self.region(c) != self.region(me) or c['status'] != 'active':
                continue
            if (not self.open(c['university_id']) and not self.rules['closed_candidate']) or c['matching_paused']:
                continue
            if self.when(c['last_active_at']) <= now - timedelta(days=15) or not self.has_vectors(c['id']):
                continue
            if c['auto_hidden_at'] and not self.rules['hidden_candidate']:
                continue
            if self._card_between(me_id, c['id'], now):
                continue
            out.append((c['id'], self.score(me, c)))
        return sorted(out, key=lambda x: -x[1])

    def _card_between(self, owner, target, now):
        for dc in self.rows('daily_cards'):
            if dc['owner_id'] != owner or dc['target_id'] != target:
                continue
            decided = self.decision(dc['id'])
            expires = self.when(dc['expires_at']) if dc['expires_at'] else None
            if decided and self.when(decided['decided_at']) > now - timedelta(days=90):
                return True
            if not decided and (expires is None or expires > now - timedelta(days=14)):
                return True
        return False

    def _candidates_api(self, sent):
        return Reply(200, {'candidates': [{'profile_id': pid, 'score': s} for pid, s in self.candidates(f"id-{sent['auth'][4:]}")]})

    def live_cards(self, pid):
        now = area2._now()
        return [c for c in self.rows('daily_cards') if c['owner_id'] == pid and not self.decision(c['id'])
                and (c['expires_at'] is None or self.when(c['expires_at']) > now or self.rules['today_expired'])]

    def _today(self, sent):
        me = f"id-{sent['auth'][4:]}"
        cards = [c for c in self.live_cards(me) if not self.hidden(self.profile(c['target_id'])) or self.rules['hidden_today']]
        return Reply(200, {'cards': [{'card_id': c['id'], 'source': c['source'], 'expires_at': c['expires_at'],
                                      'profile': {'profile_id': c['target_id']}} for c in cards], 'next_issue_at': None})

    def _acceptances(self, sent):
        me = f"id-{sent['auth'][4:]}"
        rows = [c for c in self.rows('daily_cards') if c['target_id'] == me and (self.decision(c['id']) or {}).get('decision') == 'accept'
                and (not self.hidden(self.profile(c['owner_id'])) or self.rules['hidden_accept'])]
        return Reply(200, {'acceptances': [{'card_id': c['id'], 'profile': {'profile_id': c['owner_id']}} for c in rows]})

    def _decide(self, sent):
        me, card_id = f"id-{sent['auth'][4:]}", sent['path'].split('/')[2]
        card = next((c for c in self.rows('daily_cards') if c['id'] == card_id and c['owner_id'] == me), None)
        if card is None:
            return Reply(404, {'detail': '카드를 찾을 수 없어요'})
        if self.decision(card_id):
            return Reply(409, {'detail': '이미 결정한 카드예요'})
        if self.when(card['expires_at']) <= area2._now():
            return Reply(409, {'detail': '만료된 카드예요'})
        self.rows('card_decisions').append({'card_id': card_id, 'decision': sent['body']['decision'],
                                            'decided_at': area2._now().isoformat()})
        return Reply(200, {'ok': True})

    def _upload(self, sent):
        self.files.add(sent['path'].split('/object/heart-task-proofs/')[1])
        return Reply(200, {'Key': 'x'})

    def _list(self, sent):
        prefix = sent['body']['prefix'] + '/'
        return Reply(200, [{'id': 'f', 'name': f[len(prefix):]} for f in sorted(self.files) if f.startswith(prefix)])

    # ── 배치 ──
    def on_batch(self, name):
        self.batches.append(name)
        if name == 'daily-cards' and self.rules['batch_runs']:
            self.daily_cards()
        elif name == 'cleanup' and self.rules['cleanup_runs']:
            self.cleanup()

    def eligible(self, p, now):
        r = self.rules
        stale = timedelta(days=r['stale_days'])
        return (p['id'] not in r['starve'] and (p['status'] == 'active' or r['suspended_gets_card']) and (not p['matching_paused'] or r['paused_gets_card'])
                and self.when(p['last_active_at']) > now - stale
                and (self.has_vectors(p['id']) or r['novec_gets_card'])
                and (not p['auto_hidden_at'] or r['hidden_gets_card'])
                and (self.open(p['university_id']) or r['closed_gets_card'])
                and not (r['live_blocks'] and any(c['source'] == 'daily' and c['expires_at'] and self.when(c['expires_at']) > now
                                                  for c in self.live_cards(p['id'])))
                and not (r['expired_blocks'] and any(c['owner_id'] == p['id'] and c['source'] == 'daily' and not self.decision(c['id'])
                                                     for c in self.rows('daily_cards'))))

    def daily_cards(self):
        """issuing.py issue_daily_cards — 사다리 → 설정 행 저장 → 지급 요일 아닌 지역은 건너뜀 → 오늘 받은 사람 건너뜀 → 점수 1등에게."""
        now, today = area2._now(), batch_gate.now_seoul()
        counts, by_region = self.counts(), {}
        for row in self.rows('region_group_settings'):
            c = counts.get(row['region_group'], {})
            count = (max if self.rules['bottleneck'] == 'max' else min)(c.get('male', 0), c.get('female', 0))
            weekdays = ladder(count, row['ladder_twice_per_week_min'], row['ladder_three_per_week_min'],
                              row['ladder_four_per_week_min'], row['ladder_daily_min'])
            if self.rules['save_ladder'] and weekdays != row['issue_weekdays']:
                row['issue_weekdays'] = weekdays
            by_region[row['region_group']] = weekdays
        if not self.rules['issues']:  # 설정은 읽고 사다리는 돌았지만 카드는 한 장도 안 나가는 서버
            return
        since = today.replace(hour=0, minute=0, second=0, microsecond=0)
        issued_today = {c['owner_id'] for c in self.rows('daily_cards') if c['source'] == 'daily' and self.when(c['issued_at']) >= since}
        for p in list(self.rows('profiles')):
            weekdays = by_region.get(self.region(p))
            if weekdays is None or (today.isoweekday() not in weekdays and not self.rules['ignore_weekday']) \
                    or not self.eligible(p, now) or (p['id'] in issued_today and self.rules['same_day_guard']):
                continue
            ranked = self.candidates(p['id'])
            if not ranked:
                continue
            row = next(r for r in self.rows('region_group_settings') if r['region_group'] == self.region(p))
            at = time.fromisoformat(row['issue_time'])
            expires = server_next_issue_at(today, weekdays, at) if self.rules['expiry'] == 'next' \
                else datetime.combine((today + timedelta(days=1)).date(), at, tzinfo=today.tzinfo)
            pick = ranked[-1] if self.rules['pick'] == 'last' else ranked[0]
            self.rows('daily_cards').append({'id': str(uuid.uuid4()), 'owner_id': p['id'], 'target_id': pick[0], 'source': 'daily',
                                             'issued_at': now.isoformat(), 'expires_at': expires.isoformat()})

    def cleanup(self):
        """heart_tasks/cleanup.py — 검수 끝나고 60일 지난 줄의 파일을 지우고 경로를 비운다(하루 100장까지)."""
        edge = area2._now() - timedelta(days=self.rules['cleanup_days'])
        hits = [r for r in self.rows('heart_task_submissions') if r['storage_path']
                and ((r.get('reviewed_at') and self.when(r['reviewed_at']) < edge)
                     or (self.rules['cleanup_unreviewed'] and self.when(r['created_at']) < edge))][:100]
        for r in hits:
            self.files.discard(r['storage_path'])
            r['storage_path'] = None


# ── 시험 바탕 ───────────────────────────────────────────────────────────────────────────────────────

class Base(t1.Base):
    """가짜 시계(요일 [DAY] 정오 서울) · 가짜 서버 · 가짜 배치. 기다림은 0초 — 가짜 배치는 바로 끝난다."""
    DAY = '화'
    RULES = {}

    def setUp(self):
        super().setUp()
        self.run = Run(self.root / 'area2-time-batch', 'b', cfg=t1.CFG, key='svc')
        self.world = World(**self.RULES)
        self.original_region = self.region_row()
        self.at(WEEK[self.DAY])
        for target, name, value in ((area2_phone3, 'POLL', 0), (area2, 'SETTLE_SECONDS', 0), (tb, 'FIRST_BATCH_WAIT', 0),
                                    (tb, 'BATCH_WAIT', 0), (tb, 'CARD_WAIT', 0)):
            patcher = mock.patch.object(target, name, value, create=True)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(tools, 'call', self.world)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = mock.patch.object(area2, '_batch', side_effect=self.world.on_batch)
        self.batch = patcher.start()
        self.addCleanup(patcher.stop)

    def at(self, now):
        for target, name, value in ((batch_gate, 'now_seoul', lambda: now), (area2, '_now', lambda: now.astimezone(timezone.utc))):
            patcher = mock.patch.object(target, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def go(self, case):
        got = tb.attempt(self.run, case)
        self.assertEqual(self.region_row(), self.original_region, '설정 행이 원래대로 돌아오지 않았다')  # 어떻게 끝나든 원복
        return got

    def passes(self, case):
        result, note = self.go(case)
        self.assertEqual(result, 'pass', note)
        return note

    def fails(self, case, *words):
        result, note = self.go(case)
        self.assertEqual(result, 'fail', note)
        for word in words:
            self.assertIn(word, note)
        return note

    def blocked(self, case, *words):
        result, note = self.go(case)
        self.assertEqual(result, 'blocked', note)
        for word in words:
            self.assertIn(word, note)
        return note

    def cards_of(self, pid):
        return [c for c in self.world.rows('daily_cards') if c['owner_id'] == pid and c['source'] == 'daily']

    def closed_school(self):
        self.world.rows('universities').append({'id': 'U2', 'name': '테스트대학2(코호트용)', 'region_group': 'e2e',
                                                'card_opens_at': datetime(2026, 10, 12, 7, 0, tzinfo=SEOUL).isoformat()})

    def region_row(self):
        return dict(self.world.rows('region_group_settings')[0])


# ── 공통 약속 ───────────────────────────────────────────────────────────────────────────────────────

class GateTest(Base):
    """모든 카드 가설이 계정을 만들기 전에 시각 · 지역을 본다 — 금지 시각이면 운영에 아무것도 안 쓴다."""
    CARD_CASES = ['E-CARD-04', 'E-CARD-05', 'E-CARD-06', 'E-CARD-07', 'E-CARD-08', 'E-CARD-09', 'E-CARD-11', 'E-CARD-12',
                  'E-CARD-36', 'E-CARD-72', 'E-HOME-28']

    def test_on_monday_no_card_case_creates_an_account_or_calls_the_batch(self):
        self.at(WEEK['월'])
        for case in self.CARD_CASES:
            self.blocked(case, '실행 금지')
        self.assertEqual((self.world.users, self.batch.call_count), ([], 0))

    def test_before_the_morning_issue_run_is_over_it_is_blocked_too(self):
        self.at(datetime(2026, 10, 6, 7, 10, tzinfo=SEOUL))
        self.blocked('E-CARD-12', '07:11')
        self.assertEqual(self.world.users, [])

    def test_a_test_school_outside_the_e2e_region_is_blocked_before_any_account(self):
        self.world.university('U')['region_group'] = 'seoul'
        for case in self.CARD_CASES:
            if case != 'E-HOME-28':  # 이 가설은 둘째 학교부터 본다 — 아래 따로
                self.blocked(case, "'seoul'")
        self.assertEqual(self.world.users, [])

    def test_the_cleanup_cases_wait_out_the_four_oclock_window_before_any_account(self):
        self.at(datetime(2026, 10, 6, 4, 0, tzinfo=SEOUL))
        self.blocked('E-HEART-22', '실행 금지')
        self.blocked('E-HEART-23', '실행 금지')
        self.assertEqual(self.world.users, [])


# ── E-CARD-04 ──────────────────────────────────────────────────────────────────────────────────────

class Card04Test(Base):
    def test_a_second_run_the_same_day_leaves_one_card_for_someone_who_already_decided(self):
        self.passes('E-CARD-04')
        a, b, c = 'id-1', 'id-2', 'id-3'  # A(남) 거절까지 끝냄 · B(그 카드의 상대) · C(여 — 후보로 남은 사람 · 대조군)
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])
        self.assertEqual([len(self.cards_of(x)) for x in (a, c)], [1, 1])  # A 는 심은 카드 하나뿐, 대조군 C 는 오늘 몫을 받았다
        self.assertEqual(self.world.rows('card_decisions')[0]['decision'], 'reject')
        decision = [s for s in self.world.sent if s['path'].endswith('/decision')]
        self.assertEqual([(s['auth'], s['body']) for s in decision], [('tok-1', {'decision': 'reject'})])  # A 의 토큰으로

    def test_a_server_without_the_same_day_guard_hands_out_a_second_card(self):
        self.world.rules['same_day_guard'] = False
        self.fails('E-CARD-04', '2장')

    def test_a_batch_that_never_ran_is_blocked_not_a_pass_on_an_empty_result(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-04', '배치')

    def test_without_a_candidate_left_for_a_the_result_would_mean_nothing(self):
        original = self.world.candidates
        self.world.candidates = lambda me: [] if me == 'id-1' else original(me)  # A 는 카드를 줄 후보가 없다
        self.blocked('E-CARD-04', '후보')


# ── E-CARD-05 ──────────────────────────────────────────────────────────────────────────────────────

class Card05Test(Base):
    def test_a_live_undecided_card_from_yesterday_blocks_a_new_one(self):
        self.passes('E-CARD-05')
        a = 'id-1'
        (seed,) = self.cards_of(a)
        self.assertLess(self.world.when(seed['issued_at']), batch_gate.now_seoul().replace(hour=0))  # 어제 — 오늘 받은 사람 건너뜀과 구분
        self.assertGreater(self.world.when(seed['expires_at']), area2._now())  # 아직 안 만료
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])

    def test_a_server_that_ignores_live_cards_gives_a_second_one(self):
        self.world.rules['live_blocks'] = False
        self.fails('E-CARD-05', '2장')

    def test_the_control_who_got_a_card_proves_the_batch_ran(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-05', '배치')


# ── E-CARD-06 ──────────────────────────────────────────────────────────────────────────────────────

class Card06Test(Base):
    def test_an_expired_unanswered_card_disappears_and_the_batch_gives_a_new_one_to_someone_else(self):
        self.passes('E-CARD-06')
        a, b = 'id-1', 'id-2'
        old, new = sorted(self.cards_of(a), key=lambda c: c['issued_at'])
        self.assertLess(self.world.when(old['expires_at']), area2._now())
        self.assertNotEqual(new['target_id'], b)  # 무응답 만료 + 14일은 쉰다
        today = [s for s in self.world.sent if s['path'] == '/cards/today']
        self.assertEqual([s['auth'] for s in today], ['tok-1', 'tok-1'])  # 배치 전 · 후 둘 다 A 의 오늘 탭

    def test_an_expired_card_still_listed_on_the_today_tab_is_a_fail(self):
        self.world.rules['today_expired'] = True
        self.fails('E-CARD-06', '만료')

    def test_a_batch_that_never_replaces_the_expired_card_is_a_fail_because_the_control_got_one(self):
        self.world.rules['expired_blocks'] = True
        self.fails('E-CARD-06', '대조군은 카드를 받았는데 대상은 못 받음')

    def test_no_batch_means_blocked(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-06', '배치')


# ── E-CARD-07 ──────────────────────────────────────────────────────────────────────────────────────

class Card07Wednesday(Base):
    DAY, SAVED, EXPIRES, WEAK = '수', [1, 3, 5], datetime(2026, 10, 9, 7, 0, tzinfo=SEOUL), False

    def test_expiry_is_the_next_issue_weekday_at_seven_in_seoul(self):
        self.passes('E-CARD-07')
        (card,) = self.cards_of('id-1')
        self.assertEqual(self.world.when(card['expires_at']), self.EXPIRES)
        self.assertEqual(self.region_row()['issue_weekdays'], [1, 4])  # 끝나면 원복(Base.go 가 한 번 더 본다)
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])
        patches = [s['body'] for s in self.world.sent if s['method'] == 'PATCH' and 'region_group_settings' in s['path']]
        self.assertIn({'issue_weekdays': [2], **tb.thresholds_for(self.SAVED, 1)}, patches)  # 오늘이 든 가장 성긴 칸 + 심은 값

    def test_a_server_that_expires_tomorrow_instead_is_a_fail(self):
        self.world.rules['expiry'] = 'tomorrow'
        self.fails('E-CARD-07', '만료')

    def test_the_memo_admits_weak_power_only_when_the_next_issue_is_tomorrow(self):
        note = self.passes('E-CARD-07')
        self.assertEqual('변별력이 약하다' in note, self.WEAK, note)

    def test_a_batch_that_did_not_save_the_step_is_blocked(self):
        self.world.rules['save_ladder'] = False
        self.blocked('E-CARD-07', '배치')


class Card07Thursday(Card07Wednesday):
    DAY, SAVED, EXPIRES, WEAK = '목', [1, 4], datetime(2026, 10, 12, 7, 0, tzinfo=SEOUL), False  # 월 · 목 칸 — 다음 지급은 월요일


class Card07Sunday(Card07Wednesday):
    DAY, SAVED, EXPIRES, WEAK = '일', [1, 3, 5, 7], datetime(2026, 10, 12, 7, 0, tzinfo=SEOUL), True  # 내일(월) 이 곧 다음 지급

    def test_a_server_that_expires_tomorrow_instead_is_a_fail(self):
        self.skipTest('일요일은 내일 07:00 이 곧 다음 지급(월) — 이 날은 서버 오류를 못 가린다(수 · 목 요일이 가림)')


class Card07Tuesday(Card07Wednesday):
    DAY, SAVED, EXPIRES, WEAK = '화', list(range(1, 8)), datetime(2026, 10, 7, 7, 0, tzinfo=SEOUL), True  # 매일 칸뿐 — 내일 07:00

    def test_a_server_that_expires_tomorrow_instead_is_a_fail(self):
        self.skipTest('매일 칸에서는 내일 07:00 이 곧 다음 지급 — 이 날은 서버 오류를 못 가린다(수 · 목 요일이 가림)')


# ── E-CARD-08 ──────────────────────────────────────────────────────────────────────────────────────

class Card08Test(Base):
    def test_five_batches_save_each_ladder_step_and_the_row_is_put_back(self):
        self.passes('E-CARD-08')
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')] * 5)
        patches = [s['body'] for s in self.world.sent if s['method'] == 'PATCH' and 'region_group_settings' in s['path']]
        steps = [p for p in patches if p.get('issue_weekdays') == [2]]  # 매번 사다리가 못 내는 값을 심는다
        counts = self.world.counts()['e2e']
        m = min(counts['male'], counts['female'])
        self.assertEqual([{k: v for k, v in p.items() if k != 'issue_weekdays'} for p in steps],
                         [tb.thresholds_for(w, m) for w in ([1, 4], [1, 3, 5], [1, 3, 5, 7], list(range(1, 8)), [1])])  # 시나리오 차례
        self.assertEqual(len(self.world.rows('profile_vectors')), 0)  # 카드를 받는 사람이 되지 않게 벡터는 안 넣는다

    def test_more_men_than_women_so_the_smaller_side_is_what_counts(self):
        self.passes('E-CARD-08')
        counts = self.world.counts()['e2e']
        self.assertGreater(counts['male'], counts['female'])

    def test_a_server_that_uses_the_bigger_side_lands_on_the_wrong_step(self):
        self.world.rules['bottleneck'] = 'max'
        self.fails('E-CARD-08', '[1, 4]')

    def test_a_batch_that_never_saves_is_blocked_and_the_row_is_still_restored(self):
        self.world.rules['save_ladder'] = False
        self.blocked('E-CARD-08', '배치')

    def test_a_count_that_does_not_grow_with_the_accounts_made_is_a_fail(self):
        original = self.world.counts
        self.world.counts = lambda: {r: {g: 0 for g in c} for r, c in original().items()}  # 집계가 새 계정을 못 센다
        self.fails('E-CARD-08', '집계')


# ── E-CARD-09 ──────────────────────────────────────────────────────────────────────────────────────

class Card09Test(Base):
    DAY = '수'

    def test_on_a_day_that_is_not_an_issue_day_the_whole_region_is_skipped(self):
        self.passes('E-CARD-09')
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])
        self.assertEqual([len(self.cards_of(x)) for x in ('id-1', 'id-2')], [0, 0])

    def test_a_server_that_ignores_the_weekday_hands_out_cards(self):
        self.world.rules['ignore_weekday'] = True
        self.fails('E-CARD-09', '카드')

    def test_a_batch_that_did_not_run_is_blocked_because_zero_cards_would_prove_nothing(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-09', '배치')


# ── E-CARD-11 ──────────────────────────────────────────────────────────────────────────────────────

class Card11Test(Base):
    # 어긋난 서버 하나 → 메모에 그 조건 이름이 나와야 한다. 닫힌 학교는 후보 SQL 도 같이 뚫려야 카드가 나간다(서버는 두 겹으로 막는다).
    LEAKS = [({'suspended_gets_card': True}, 'active'), ({'paused_gets_card': True}, '일시중지'), ({'stale_days': 15}, '14일'),
             ({'novec_gets_card': True}, '벡터'), ({'hidden_gets_card': True}, '자동 가림'),
             ({'closed_gets_card': True, 'closed_owner_sees': True}, '학교')]

    def setUp(self):
        super().setUp()
        self.closed_school()

    def test_each_missing_condition_blocks_the_card_and_the_control_gets_one(self):
        self.passes('E-CARD-11')
        men = [f'id-{i}' for i in range(1, 8)]  # 조건 하나씩 빠뜨린 6명 + 대조군(마지막 남자)
        self.assertEqual([len(self.cards_of(x)) for x in men], [0, 0, 0, 0, 0, 0, 1])
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])
        sets = {s['body'].get('university_id') for s in self.world.sent if s['method'] == 'PATCH' and 'university_id' in (s['body'] or {})}
        self.assertEqual(sets, {'U2'})

    def test_a_server_that_lets_one_missing_condition_through_is_a_fail_that_names_it(self):
        for rules, word in self.LEAKS:
            with self.subTest(word):
                self.setUp()
                self.world.rules.update(rules)
                result, note = self.go('E-CARD-11')
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_stale_account_is_exactly_fourteen_days_and_a_minute(self):
        self.passes('E-CARD-11')
        stale = [s['body']['last_active_at'] for s in self.world.sent if s['method'] == 'PATCH' and 'last_active_at' in (s['body'] or {})]
        self.assertEqual(stale, [(area2._now() - timedelta(days=14, minutes=1)).isoformat()])

    def test_the_vector_condition_empties_one_of_the_three_vectors(self):
        self.passes('E-CARD-11')
        patches = [s['body'] for s in self.world.sent if s['method'] == 'PATCH' and 'profile_vectors' in s['path']]
        self.assertEqual(patches, [{'want_embedding': None}])

    def test_without_a_closed_school_the_case_makes_its_own_and_removes_it_at_the_end(self):
        self.world.rows('universities').pop()  # 둘째 학교 없음 — 시험이 e2e-cohort 행을 만든다
        self.passes('E-CARD-11')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U'])  # 행도 지워지고
        self.assertEqual({p['university_id'] for p in self.world.rows('profiles')}, {'U'})  # 계정도 시험대학으로 돌아옴
        made = [s['body'][0] for s in self.world.sent if s['method'] == 'POST' and s['path'].endswith('/universities')]
        self.assertEqual(len(made), 1)
        self.assertTrue(made[0]['name'].startswith('e2e-cohort-'))
        self.assertEqual(made[0]['region_group'], 'e2e')

    def test_without_the_closed_school_a_real_violation_is_still_a_fail(self):
        self.world.rows('universities').pop()
        self.world.rules['paused_gets_card'] = True
        self.fails('E-CARD-11', '일시중지')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U'])  # 실패여도 행은 남지 않는다


# ── E-CARD-12 ──────────────────────────────────────────────────────────────────────────────────────

class Card12Test(Base):
    def test_someone_last_seen_thirteen_days_and_twenty_three_hours_ago_still_gets_a_card(self):
        self.passes('E-CARD-12')
        self.assertEqual(len(self.cards_of('id-1')), 1)
        stale = [s['body']['last_active_at'] for s in self.world.sent if s['method'] == 'PATCH' and 'last_active_at' in (s['body'] or {})]
        self.assertEqual(stale, [(area2._now() - timedelta(days=13, hours=23)).isoformat()])

    def test_a_card_that_never_shows_up_while_the_control_got_one_is_a_fail(self):
        self.world.rules['stale_days'] = 13  # 13일 경계가 틀린 서버 — 대조군(방금 접속한 사람)은 카드를 받는다
        self.fails('E-CARD-12', '대조군은 카드를 받았는데 대상은 못 받음', '배치가 돈 것이 확인된 뒤')

    def test_no_batch_means_blocked(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-12', '배치')


# ── E-CARD-36 ──────────────────────────────────────────────────────────────────────────────────────

class Card36Test(Base):
    def test_a_hidden_person_leaves_candidates_cards_and_inbox_and_gets_no_new_card(self):
        self.passes('E-CARD-36')
        a, b, d = 'id-1', 'id-2', 'id-4'  # A(여) 후보를 보는 사람 · B(남) 가려지는 사람 · C(여) · D(남 — 대조군)
        self.assertEqual(self.world.profile(b)['auto_hidden_at'], area2._now().isoformat())
        self.assertEqual(len(self.cards_of(b)), 1)  # 어제 준 카드 하나뿐 — 오늘 새 카드 0
        self.assertEqual(len(self.cards_of(d)), 1)
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])
        accepted = [s['auth'] for s in self.world.sent if s['path'].endswith('/decision')]
        self.assertEqual(accepted, ['tok-2'])  # B 가 A 에게 보낸 카드를 B 의 토큰으로 수락

    def test_candidates_are_read_by_c_who_has_no_card_with_b_because_a_live_card_alone_hides_a_candidate(self):
        self.passes('E-CARD-36')
        who = [s['auth'] for s in self.world.sent if s['path'] == '/matching/candidates']
        self.assertEqual(who, ['tok-3', 'tok-3'])  # 가리기 전 · 후 모두 C(id-3) — A(tok-1) 는 B 와 카드가 있다

    def test_the_seeded_card_of_b_is_from_yesterday_so_the_same_day_guard_cannot_explain_the_result(self):
        self.passes('E-CARD-36')
        (seed,) = self.cards_of('id-2')
        self.assertLess(self.world.when(seed['issued_at']), batch_gate.now_seoul().replace(hour=0))

    def test_each_leak_is_a_fail_that_names_where(self):
        for rule, word in (('hidden_candidate', '후보'), ('hidden_gets_card', '새 카드'), ('hidden_today', '오늘'),
                           ('hidden_accept', '수락함')):
            with self.subTest(rule):
                self.setUp()
                self.world.rules[rule] = True
                result, note = self.go('E-CARD-36')
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_when_b_was_never_a_candidate_before_hiding_the_check_is_blocked(self):
        original = self.world.candidates
        self.world.candidates = lambda me: [x for x in original(me) if x[0] != 'id-2']
        self.blocked('E-CARD-36', '준비')


# ── E-CARD-72 ──────────────────────────────────────────────────────────────────────────────────────

class Card72Test(Base):
    def test_the_batch_gives_the_owner_the_top_scored_candidate(self):
        with mock.patch.object(tb.random, 'randrange', return_value=7):
            self.passes('E-CARD-72')
        o, c0 = 'id-1', 'id-2'  # O 와 후보 C0 · C4 · C5
        (card,) = self.cards_of(o)
        self.assertEqual(card['target_id'], c0)
        score = lambda x: self.world.score(self.world.profile(o), self.world.profile(x))  # noqa: E731
        self.assertEqual([score('id-2'), score('id-3'), score('id-4')], [1.0, 0.5, 0.8])  # C0 · C4(흡연) · C5(종교)

    def test_the_sentence_axis_is_random_so_other_runs_leftovers_cannot_tie_with_c0(self):
        self.passes('E-CARD-72')
        axis = {v['profile_id']: v['self_embedding'] for v in self.world.rows('profile_vectors')}
        self.assertNotEqual(axis['id-1'], area2._unit(0))  # 다른 묶음의 C0 는 0 번 축 — 같은 축을 쓰면 점수가 같아진다
        self.assertEqual({axis['id-1']}, {axis[f'id-{i}'] for i in (2, 3, 4)})  # O · C0 · C4 · C5 는 같은 축

    def test_a_server_that_gives_the_last_ranked_is_a_fail(self):
        self.world.rules['pick'] = 'last'
        self.fails('E-CARD-72', '1등')

    def test_a_leftover_with_the_same_score_makes_the_check_blocked(self):
        with mock.patch.object(tb.random, 'randrange', return_value=7):
            row = self.world.profile('stranger')
            row.update(gender='female', interest_tags=area2.TAGS['interest_tags'], is_smoker=False, religion='none')
            self.world.rows('profile_vectors').append({'profile_id': 'stranger', 'self_survey': '[1]', 'want_embedding': area2._unit(7),
                                                       'self_embedding': area2._unit(7)})
            self.blocked('E-CARD-72', '같은 점수')

    def test_no_batch_means_blocked(self):
        self.world.rules['batch_runs'] = False
        self.blocked('E-CARD-72', '배치')


# ── E-HOME-28 ──────────────────────────────────────────────────────────────────────────────────────

class Home28Test(Base):
    def setUp(self):
        super().setUp()
        self.closed_school()

    def test_a_person_in_a_school_that_has_not_opened_is_in_no_pool_and_gets_no_card(self):
        self.passes('E-HOME-28')
        v, f, g = 'id-1', 'id-2', 'id-3'  # V(남 · 닫힌 학교) · F(여 · 열린 학교) · G(남 — 대조군)
        self.assertEqual(self.world.profile(v)['university_id'], 'U2')
        self.assertEqual([len(self.cards_of(x)) for x in (v, f, g)], [0, 1, 1])
        self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])

    def test_each_leak_is_a_fail_that_names_where(self):
        for rules, word in (({'closed_counts': True}, '집계'), ({'closed_candidate': True}, '후보'),
                            ({'closed_gets_card': True, 'closed_owner_sees': True}, '카드'), ({'closed_owner_sees': True}, '후보')):
            with self.subTest(word):
                self.setUp()
                self.closed_school()
                self.world.rules.update(rules)
                result, note = self.go('E-HOME-28')
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_without_a_second_school_it_makes_its_own_and_removes_it_at_the_end(self):
        self.world.rows('universities').pop()
        self.passes('E-HOME-28')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U'])
        self.assertEqual({p['university_id'] for p in self.world.rows('profiles')}, {'U'})

    def test_a_school_whose_opening_has_passed_is_not_a_closed_school_so_its_own_is_made(self):
        self.world.rows('universities')[-1]['card_opens_at'] = datetime(2026, 10, 5, 7, 0, tzinfo=SEOUL).isoformat()
        self.passes('E-HOME-28')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U', 'U2'])  # 남의 행은 건드리지 않는다

    def test_a_closed_school_of_another_region_is_not_used(self):
        self.world.rows('universities')[-1]['region_group'] = 'seoul'
        self.passes('E-HOME-28')
        self.assertEqual({p['university_id'] for p in self.world.rows('profiles')}, {'U'})
        self.assertEqual(self.world.rows('universities')[-1]['id'], 'U2')


class CohortSchoolTest(Base):
    """둘째 시험학교 행 — 시작에서 앞 실행이 남긴 e2e-cohort 행부터 지우고, 끝(예외여도)에는 계정을 돌려놓고 지운다."""

    def left_over(self, who=()):
        self.world.rows('universities').append({'id': 'OLD', 'name': 'e2e-cohort-deadbeef', 'region_group': 'e2e',
                                                'card_opens_at': datetime(2026, 10, 12, 7, 0, tzinfo=SEOUL).isoformat()})
        for pid in who:
            self.world.profile(pid)['university_id'] = 'OLD'

    def test_a_row_left_by_a_dead_run_is_removed_first_and_its_people_go_home(self):
        self.left_over(['id-9'])
        self.passes('E-HOME-28')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U'])
        self.assertEqual(self.world.profile('id-9')['university_id'], 'U')
        first = next(s for s in self.world.sent if s['method'] == 'DELETE' and s['path'].endswith('/universities'))
        self.assertEqual(first['query'], {'id': 'eq.OLD'})  # 이름 틀이 아니라 id 하나씩

    def test_a_hand_made_school_without_the_prefix_is_never_deleted(self):
        self.closed_school()
        self.passes('E-HOME-28')
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U', 'U2'])
        self.assertEqual([s for s in self.world.sent if s['method'] == 'DELETE' and s['path'].endswith('/universities')], [])

    def test_the_row_is_removed_even_when_the_case_dies_in_the_middle(self):
        with mock.patch.object(tb, '_issue', side_effect=RuntimeError('중간에 죽음')):
            result, note = self.go('E-HOME-28')
        self.assertEqual(result, 'blocked', note)
        self.assertEqual([u['id'] for u in self.world.rows('universities')], ['U'])
        self.assertEqual({p['university_id'] for p in self.world.rows('profiles')}, {'U'})

    def test_accounts_are_moved_home_before_the_row_is_deleted(self):
        self.passes('E-HOME-28')
        writes = [(s['method'], s['path'].rsplit('/', 1)[1]) for s in self.world.writes()
                  if s['path'].endswith(('/universities', '/profiles')) and s['method'] != 'POST']
        self.assertEqual(writes[-2:], [('PATCH', 'profiles'), ('DELETE', 'universities')])

    def test_a_row_that_cannot_be_created_is_blocked_before_any_account(self):
        self.world.on('POST', r'/rest/v1/universities', Reply(403, {'message': 'denied'}))
        self.blocked('E-HOME-28', '둘째 시험학교', '403')
        self.assertEqual(self.world.users, [])

    def test_the_row_has_a_monday_0700_seoul_opening_in_the_future(self):
        self.passes('E-HOME-28')
        row = next(s['body'][0] for s in self.world.sent if s['method'] == 'POST' and s['path'].endswith('/universities'))
        opens = datetime.fromisoformat(row['card_opens_at']).astimezone(SEOUL)
        self.assertEqual((opens.isoweekday(), opens.hour, opens.minute, opens.second), (1, 7, 0, 0))
        self.assertGreater(opens, area2._now())


# ── E-HEART-22 · 23 ────────────────────────────────────────────────────────────────────────────────

class CleanupTest(Base):
    def test_both_cases_share_one_cleanup_batch(self):
        self.passes('E-HEART-22')
        self.passes('E-HEART-23')
        self.assertEqual(self.batch.call_args_list, [mock.call('cleanup')])
        self.assertEqual(len(self.world.users), 1)  # 계정도 하나만 — 장면을 다시 만들지 않는다

    def test_the_seeds_are_61_days_approved_59_days_approved_and_61_days_still_reviewing(self):
        self.passes('E-HEART-23')
        rows = self.world.rows('heart_task_submissions')
        days = sorted((round((area2._now() - self.world.when(r['created_at'])).days), r['status'], r.get('reviewed_at') is None) for r in rows)
        self.assertEqual(days, [(59, 'approved', False), (61, 'approved', False), (61, 'submitted', True)])

    def test_61_days_loses_the_path_and_the_file_while_59_days_and_reviewing_keep_both(self):
        self.passes('E-HEART-22')
        rows = self.world.rows('heart_task_submissions')
        age = lambda r: (area2._now() - self.world.when(r['created_at'])).days  # noqa: E731
        self.assertEqual(sorted((age(r), r['status'], r['storage_path'] is None) for r in rows),
                         [(59, 'approved', False), (61, 'approved', True), (61, 'submitted', False)])
        self.assertEqual(len(self.world.files), 2)  # 지운 파일 하나만 사라졌다

    def test_a_server_that_never_cleans_fails_22_and_leaves_23_blocked_because_keeping_proves_nothing(self):
        self.world.rules['cleanup_runs'] = False
        self.fails('E-HEART-22', '61일')
        self.blocked('E-HEART-23', '앵커')

    def test_a_server_that_cuts_at_58_days_also_deletes_the_59_day_proof(self):
        self.world.rules['cleanup_days'] = 58
        self.passes('E-HEART-22')
        self.fails('E-HEART-23', '59일')

    def test_a_server_that_also_cleans_reviewing_proofs_fails_23(self):
        self.world.rules['cleanup_unreviewed'] = True
        self.passes('E-HEART-22')
        self.fails('E-HEART-23', '검수 중')

    def test_the_memo_says_the_deleted_count_cannot_be_read(self):
        self.assertIn('deleted_heart_proofs', self.passes('E-HEART-22'))


# ── 등록 · 쓰기 범위 · 서버 장애 ─────────────────────────────────────────────────────────────────────

CASES = ('E-CARD-04 E-CARD-05 E-CARD-06 E-CARD-07 E-CARD-08 E-CARD-09 E-CARD-11 E-CARD-12 E-CARD-36 E-CARD-72 '
         'E-HOME-28 E-HEART-22 E-HEART-23').split()


class RegistryTest(unittest.TestCase):
    def test_the_bundle_is_exactly_the_thirteen_hypotheses(self):
        self.assertEqual(sorted(tb.CASES), sorted(CASES))
        self.assertEqual(tb.BUNDLES, {'area2-time-batch': list(tb.CASES)})

    def test_the_command_line_knows_the_bundle_and_routes_each_case_here(self):
        from e2e import __main__ as cli
        self.assertEqual(cli.BUNDLES['area2-time-batch'], list(tb.CASES))
        for case in tb.CASES:
            self.assertIs(cli.API_CASES[case], tb, case)

    def test_no_case_number_is_also_registered_by_another_module(self):
        from e2e import __main__ as cli
        from e2e import area2 as a2, area3, area3_safe
        for other in (a2.CASES, area3.CASES, area3_safe.CASES, cli.area1.CASES, cli.area1.PHONE):
            self.assertEqual(set(other) & set(tb.CASES), set())

    def test_every_case_number_is_in_the_scenario_file_when_it_exists(self):
        from e2e import __main__ as cli
        if not cli.SCENARIO.exists():
            self.skipTest('시나리오 파일이 없다')
        text = cli.SCENARIO.read_text(encoding='utf-8')
        for case in tb.CASES:
            self.assertIn(f'| {case} |', text)


class SchemaTest(Base):
    """가짜 서버가 진짜 열 이름만 받는다 — E-CARD-35 는 없는 id 열을 골라 운영에서만 400 이 났다."""

    def test_the_world_refuses_a_column_the_table_does_not_have(self):
        reply = self.world('GET', 'https://sb.test/rest/v1/card_decisions?select=id', {}, None)
        self.assertEqual((reply[0], reply[1]['code']), (400, '42703'))
        reply = self.world('GET', 'https://sb.test/rest/v1/daily_cards?owner=eq.x&select=id', {}, None)  # 없는 필터 열
        self.assertEqual(reply[0], 400)
        self.assertEqual(self.world('GET', 'https://sb.test/rest/v1/no_such_table?select=id', {}, None)[0], 404)

    def test_the_migrations_have_the_columns_and_rpc_the_cases_rely_on(self):
        tables, functions = migration_schema()
        self.assertTrue({'issue_weekdays', 'ladder_daily_min', 'issue_time'} <= tables['region_group_settings'])
        self.assertTrue({'card_opens_at', 'region_group'} <= tables['universities'])
        self.assertTrue({'auto_hidden_at', 'matching_paused', 'last_active_at'} <= tables['profiles'])
        self.assertIn('region_active_counts', functions)

    def test_every_case_only_touches_real_tables_and_columns(self):
        for case in ('E-CARD-04', 'E-CARD-06', 'E-CARD-11', 'E-CARD-36', 'E-HOME-28', 'E-HEART-23'):
            if case in ('E-CARD-11', 'E-HOME-28'):
                self.closed_school()
            result, note = self.go(case)
            self.assertEqual(result, 'pass', f'{case} {note}')  # 없는 열을 읽으면 400 → blocked 로 끝났을 것


class WritesStayInsideThisRunTest(Base):
    def test_batches_only_go_through_area2_batch_and_cost_fifteen_card_runs_and_one_cleanup(self):
        from collections import Counter
        self.closed_school()
        with mock.patch.object(tools, 'batch') as gcloud:  # 가설이 관문(area2._batch)을 건너뛰고 gcloud 를 직접 부르면 여기서 걸린다
            for case in tb.CASES:
                self.go(case)
        self.assertEqual(gcloud.call_count, 0)
        self.assertEqual(Counter(c.args[0] for c in self.batch.call_args_list), {'daily-cards': 15, 'cleanup': 1})

    def test_every_database_write_targets_this_runs_accounts_or_the_e2e_settings_row(self):
        self.closed_school()
        for case in tb.CASES:
            self.go(case)
        mine = area2._mine(self.run)
        self.assertGreater(len(mine), 10)
        for s in self.world.writes():
            table = s['path'].rsplit('/', 1)[1]
            if table == 'region_group_settings':
                self.assertEqual(s['query'], {'region_group': 'eq.e2e'}, s)
                continue
            if table == 'universities':  # 둘째 시험학교 — 이 시험이 만든 e2e-cohort 행만 넣고 id 로 지운다
                if s['method'] == 'POST':
                    self.assertTrue(all(r['name'].startswith('e2e-cohort-') and r['region_group'] == 'e2e' for r in s['body']), s)
                else:
                    self.assertEqual((s['method'], list(s['query'])), ('DELETE', ['id']), s)
                continue
            if table == 'profiles' and list(s['query']) == ['university_id']:  # 둘째 학교에 든 계정을 시험대학으로 돌려놓는 쓰기
                self.assertEqual(s['body'], {'university_id': 'U'}, s)
                continue
            owners = {v[3:] for k, v in s['query'].items() if k in ('id', 'profile_id', 'owner_id') and v.startswith('eq.')}
            for row in s['body'] if isinstance(s['body'], list) else [s['body']]:
                owners |= {row[k] for k in ('id', 'profile_id', 'owner_id') if k in row and table not in ('daily_cards', 'heart_task_submissions')}
                owners |= {row[k] for k in ('owner_id', 'profile_id', 'target_id') if k in row and table in ('daily_cards', 'heart_task_submissions')}
            self.assertTrue(owners and owners <= mine, f'{s["method"]} {table} {s["query"]} {owners - mine}')


class NoCardsIssuedTest(Base):
    """배치가 설정은 읽고 카드는 한 장도 안 내는 서버 — 앵커(설정 행)는 보이지만 대조군이 비어 있어 "카드 0" 을 믿을 수 없다."""
    RULES = {'issues': False}

    def test_cases_that_need_a_control_are_blocked_not_passed_on_an_empty_result(self):
        for case in ('E-CARD-04', 'E-CARD-05', 'E-CARD-11', 'E-CARD-36'):
            with self.subTest(case):
                self.setUp()
                self.blocked(case, '카드가 안 보임')

    def test_the_closed_school_case_is_blocked_the_same_way(self):
        self.closed_school()
        self.blocked('E-HOME-28', '카드가 안 보임')

    def test_cases_whose_subject_should_get_a_card_are_blocked_when_none_shows_up(self):
        for case in ('E-CARD-06', 'E-CARD-07', 'E-CARD-12', 'E-CARD-72'):
            with self.subTest(case):
                self.setUp()
                self.blocked(case, '카드가 안 보임', '다시')

    def test_the_not_an_issue_day_case_still_passes_because_the_settings_row_proves_the_batch_ran(self):
        self.passes('E-CARD-09')  # 카드가 안 나가는 것이 정답 — 앵커(설정 행이 새로 적힘)가 배치가 돌았다는 증거


class PositiveControlTest(Base):
    """카드가 나와야 하는 가설(06 · 07 · 12 · 72)은 같은 배치를 받는 대조군 남자를 하나 더 둔다 — 대조군은 받았는데 대상만 못 받으면 fail,
    둘 다 못 받으면 blocked(배치가 느리거나 안 돎). 대조군은 대상과 같은 성별이라 대상의 후보 풀에 못 들어가고, 배치 횟수는 그대로다."""
    CASES = {'E-CARD-06': 'id-4', 'E-CARD-07': 'id-3', 'E-CARD-12': 'id-3', 'E-CARD-72': 'id-5'}  # 대상 id-1 · 대조군 id(맨 마지막에 만든다)

    def test_the_control_got_a_card_but_the_subject_did_not_is_a_fail_that_says_so(self):
        for case in self.CASES:
            with self.subTest(case):
                self.setUp()
                self.world.rules['starve'] = frozenset({'id-1'})
                self.fails(case, '대조군은 카드를 받았는데 대상은 못 받음', '대조군이 카드를 받아 배치가 돈 것이 확인된 뒤의 fail')

    def test_nobody_got_a_card_is_blocked(self):
        for case in self.CASES:
            with self.subTest(case):
                self.setUp()
                self.world.rules['issues'] = False
                self.blocked(case, '카드가 안 보임', '구분 못 함')

    def test_only_the_control_missing_is_blocked_because_the_batch_cannot_be_trusted(self):
        for case, control in self.CASES.items():
            with self.subTest(case):
                self.setUp()
                self.world.rules['starve'] = frozenset({control})
                self.blocked(case, '카드가 안 보임')

    def test_both_got_cards_goes_the_old_way_and_the_control_is_a_man_outside_the_subjects_pool(self):
        for case, control in self.CASES.items():
            with self.subTest(case):
                self.setUp()
                with mock.patch.object(tb.random, 'randrange', return_value=7):
                    self.passes(case)
                self.assertEqual((self.world.profile('id-1')['gender'], self.world.profile(control)['gender']), ('male', 'male'))
                self.assertEqual(self.cards_of(control) and len(self.cards_of(control)), 1)  # 대조군은 정확히 한 장
                self.assertEqual(self.batch.call_args_list, [mock.call('daily-cards')])  # 대조군이 배치를 늘리지 않는다

    def test_the_pool_of_72_is_exactly_the_three_women_so_the_control_does_not_shake_the_top_pick(self):
        seen, real = [], self.world.candidates

        def watching(me):
            got = real(me)
            if me == 'id-1':  # O 의 후보를 읽을 때마다 적는다
                seen.append({pid for pid, _ in got})
            return got

        self.world.candidates = watching
        with mock.patch.object(tb.random, 'randrange', return_value=7):
            self.passes('E-CARD-72')
        self.assertEqual(seen[0], {'id-2', 'id-3', 'id-4'})  # C0 · C4 · C5 뿐 — 대조군(id-5)은 없다

    def test_a_server_that_gives_the_last_ranked_still_fails_72_with_the_control_present(self):
        self.world.rules['pick'] = 'last'
        with mock.patch.object(tb.random, 'randrange', return_value=7):
            self.fails('E-CARD-72', '1등')


class NegativeMemoTest(Base):
    """음성 판정(카드 0)이 pass 로 끝나면 메모가 그 판정의 한계를 말한다."""

    def test_zero_cards_are_called_a_judgement_at_a_fixed_wait_after_the_control_card(self):
        self.closed_school()
        for case in ('E-CARD-04', 'E-CARD-05', 'E-CARD-11', 'E-CARD-36', 'E-HOME-28'):
            with self.subTest(case):
                self.assertIn('카드 0 은 대조군 카드가 나온 뒤 고정', self.passes(case))

    def test_the_skipped_region_case_has_no_control_so_it_says_after_the_settings_row_changed(self):
        self.assertIn('카드 0 은 설정 행이 바뀐 뒤 고정', self.passes('E-CARD-09'))


class RetryOnceTest(Base):
    """__main__.run_case 는 fail 이면 가설을 한 번 더 부른다 — 배치를 이미 부른 가설은 배치를 또 부르지 않고 첫 결과를 돌려준다."""
    DAY = '수'

    def test_a_fail_comes_back_unchanged_with_a_reason_and_without_a_second_batch_or_new_accounts(self):
        self.world.rules['same_day_guard'] = False
        first = self.go('E-CARD-04')
        users = len(self.world.users)
        again = self.go('E-CARD-04')
        self.assertEqual(first[0], 'fail')
        self.assertEqual(again[0], 'fail')
        self.assertTrue(again[1].startswith(first[1]), again)
        self.assertIn('배치를 이미 불러 다시 하지 않음', again[1])
        self.assertEqual((self.batch.call_count, len(self.world.users)), (1, users))

    def test_a_pass_and_a_blocked_after_the_batch_are_kept_as_they_were(self):
        first = self.go('E-CARD-12')
        self.assertEqual(self.go('E-CARD-12'), first)
        self.assertEqual(first[0], 'pass')
        self.world.rules['batch_runs'] = False
        stuck = self.go('E-CARD-05')
        self.assertEqual(stuck[0], 'blocked')
        self.assertEqual(self.go('E-CARD-05'), stuck)
        self.assertEqual(self.batch.call_count, 2)  # 가설마다 한 번씩

    def test_a_block_before_the_batch_is_not_kept_so_the_retry_really_runs(self):
        self.at(WEEK['월'])
        self.blocked('E-CARD-12', '실행 금지')
        self.assertEqual(self.batch.call_count, 0)
        self.at(WEEK['수'])
        self.passes('E-CARD-12')
        self.assertEqual(self.batch.call_count, 1)

    def test_a_gate_that_closes_between_preparing_and_calling_leaves_nothing_kept(self):
        real = self.world

        def closing(method, url, *args, **kwargs):
            if url.endswith('rpc/region_active_counts'):  # 배치를 부르기 직전 — 그 사이 월요일이 됐다
                self.at(WEEK['월'])
            return real(method, url, *args, **kwargs)

        with mock.patch.object(tools, 'call', closing):
            self.blocked('E-CARD-12', '실행 금지')
        self.assertEqual(self.batch.call_count, 0)
        self.at(WEEK['수'])
        with mock.patch.object(tools, 'call', real):
            self.passes('E-CARD-12')  # 부르지 않았으니 기록이 없고, 다시 하면 실제로 돈다
        self.assertEqual(self.batch.call_count, 1)

    def test_a_drop_after_the_batch_was_called_is_not_retried(self):
        self.batch.side_effect = ConnectionResetError('끊김')
        result, note = self.go('E-CARD-12')
        self.assertEqual(result, 'blocked')
        self.assertIn('배치를 이미 불러 다시 하지 않음', note)
        self.assertEqual(self.batch.call_count, 1)
        self.assertEqual(self.go('E-CARD-12'), (result, note))
        self.assertEqual(self.batch.call_count, 1)

    def test_a_drop_before_the_batch_is_retried_from_the_start(self):
        drops = []
        real = self.world

        def flaky(*args, **kwargs):
            if not drops:
                drops.append(1)
                raise ConnectionResetError('끊김')
            return real(*args, **kwargs)

        with mock.patch.object(tools, 'call', flaky):
            self.passes('E-CARD-12')
        self.assertEqual(self.batch.call_count, 1)

    def test_another_run_gets_its_own_attempt(self):
        self.passes('E-CARD-12')
        self.run = Run(self.root / 'another-bundle-run', 'b', cfg=t1.CFG, key='svc')
        self.passes('E-CARD-12')
        self.assertEqual(self.batch.call_count, 2)

    def test_cleanup_cases_share_the_scene_and_a_retry_never_fires_the_batch_again(self):
        self.world.rules['cleanup_runs'] = False
        first = self.go('E-HEART-22')
        self.assertEqual(first[0], 'fail')
        again = self.go('E-HEART-22')
        self.assertIn('배치를 이미 불러 다시 하지 않음', again[1])
        second = self.go('E-HEART-23')  # 장면 캐시를 쓰므로 배치를 또 부르지 않는다
        self.assertEqual(second[0], 'blocked')
        self.assertEqual(self.go('E-HEART-23'), second)
        self.assertEqual(self.batch.call_args_list, [mock.call('cleanup')])

    def test_when_23_fires_the_scene_first_22_reuses_it_and_a_retry_adds_no_batch(self):
        self.world.rules['cleanup_days'] = 58
        self.assertEqual(self.go('E-HEART-23')[0], 'fail')
        self.go('E-HEART-22')
        self.go('E-HEART-22')
        self.go('E-HEART-23')
        self.assertEqual(self.batch.call_args_list, [mock.call('cleanup')])


class MidnightTest(Base):
    def test_a_batch_that_crosses_midnight_is_blocked_because_today_changed(self):
        def over_midnight(name):
            self.world.on_batch(name)
            self.at(WEEK['수'])  # 배치가 도는 사이 서울 날짜가 넘어갔다

        self.batch.side_effect = over_midnight
        self.blocked('E-CARD-12', '자정')


class SafetyNetTest(Base):
    def test_every_case_ends_as_fail_or_blocked_when_the_server_is_down(self):
        down = Store()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down), mock.patch.object(area2, '_batch'):
            for case in tb.CASES:
                result, note = self.go(case)
                self.assertIn(result, ('fail', 'blocked'), case)
                self.assertIsInstance(note, str, case)

    def test_a_failed_scheduler_call_is_blocked_with_the_reason(self):
        self.batch.side_effect = Blocked('배치 daily-cards 호출 실패: CalledProcessError')
        self.blocked('E-CARD-12', '호출 실패')

    def test_a_connection_that_drops_twice_before_any_batch_is_blocked_not_a_crash(self):
        with mock.patch.object(tools, 'call', side_effect=ConnectionResetError('끊김')):
            self.blocked('E-CARD-12', '두 번 끊김')
        self.assertEqual(self.batch.call_count, 0)

    def test_a_bug_in_the_test_itself_is_blocked_so_a_long_run_does_not_stop(self):
        self.batch.side_effect = KeyError('x')
        self.blocked('E-CARD-12', '예외')


class RegionRestoreTest(Base):
    def test_the_settings_row_comes_back_even_when_the_case_raises_in_the_middle(self):
        before = self.region_row()
        self.batch.side_effect = KeyError('x')
        self.go('E-CARD-08')
        self.assertEqual(self.region_row(), before)


if __name__ == '__main__':
    unittest.main()
