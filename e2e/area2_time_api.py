"""영역 2 시간 API 가설 — 배치를 부르지 않고 DB 의 시각 칸만 옮겨 API · RPC 로 본다(묶음 area2-time-api, 폰 없음).

서버 시계는 못 옮긴다. 그래서 "N일 지나면" 규칙은 이번 실행이 만든 계정의 시각 칸을 과거로 옮겨(서비스 키 PATCH, [area2._guard] 필수) 본다.
트리거가 막는 칸(`heart_task_submissions.created_at` — 20260928030100 의 guard)은 옮길 수 없어 처음부터 과거 시각 행을 insert 한다.
옮길 수 있는 칸은 마이그레이션에서 트리거 · check 를 읽어 확인했다:
  profiles.last_active_at · daily_cards.expires_at · card_decisions.decided_at · acceptance_responses.decided_at · matches.created_at ·
  polls.created_at · heart_transactions.created_at 에는 시각을 막는 트리거가 없다(service_role 은 update 권한 있음).
가설 기대값은 시나리오가 아니라 코드가 기준이다(근거 파일 · 줄은 가설마다 메모). 화면 · 앱 재시작 줄은 보지 않았다 — 보고의 분류표 참고.
"""

from datetime import timedelta

from e2e import area2, tools
from e2e.area1 import SEOUL, Check, _api, _at, _detail, _patch, _rows, _test_university
from e2e.area2 import _ONCE, TAGS, _candidates, _card, _drop_polls, _grant, _guard, _home, _insert, _ledger, _person, _poll, _submit
from e2e.tools import Blocked

STALE_DAYS = 15  # match_candidates: last_active_at > now() − 15 days (20260928050000:94)
DECIDED_REST_DAYS = 90  # 결정 · 수락 응답 뒤 쉬는 날(:113 · :126)
EXPIRED_REST_DAYS = 14  # 무응답 만료 뒤 쉬는 날(:114-115)
ACCEPTANCE_DAYS = 7  # cards/router.py ACCEPTANCE_TTL_DAYS
IN_REVIEW = '이미 확인 중이에요, 결과를 기다려 주세요'  # errors.HEART_TASK_IN_REVIEW — heart_07 과 같은 문구
OWNER = {'is_smoker': False, 'religion': 'none', 'mbti': 'ENFP', 'preferred_mbti_flags': {'E': True}, 'preferred_height_min': 170,
         'preferred_height_max': 180, 'preferred_age_min': 22, 'preferred_age_max': 24, **TAGS}  # area2._world 의 오너와 같다
CLONE = {'is_smoker': False, 'religion': 'none', **TAGS}  # area2 의 C0(만점 상대)와 같다


# ── 시계 ────────────────────────────────────────────────────────────────────────────────────────────
# 하루 · 주 · 달은 서울 달력으로 센다(DB 함수가 `at time zone 'Asia/Seoul'` — create_poll_functions · create_heart_task_functions).

def _now():
    return area2._now()  # 시험이 area2._now 를 얼려도 따라가게 이름이 아니라 모듈 속성으로 부른다


def now_seoul():
    """서울 시각 — batch_gate.now_seoul 처럼 시험이 바꿔 끼울 수 있게 함수로 둔다. 기본은 얼린 area2._now 를 따른다."""
    return _now().astimezone(SEOUL)


def _ago(**span):
    return (_now() - timedelta(**span)).isoformat()


def seoul_day_start(now):
    return now.astimezone(SEOUL).replace(hour=0, minute=0, second=0, microsecond=0)


def seoul_week_start(now):
    start = seoul_day_start(now)
    return start - timedelta(days=start.weekday())  # date_trunc('week') 는 월요일 0시


def seoul_month_start(now):
    return seoul_day_start(now).replace(day=1)


def yesterday_2359(now):
    return seoul_day_start(now) - timedelta(minutes=1)


def _midnight_wait(now, boundary):
    """[boundary] 까지 60초 미만이면 "지금은 실행 금지 시간 — 자정 직후(HH:MM)에 다시"(batch_gate 와 같은 모양), 아니면 None.
    가설이 계정을 만들고 시각을 옮기는 몇 초 사이에 하루 · 달이 바뀌면 "어제 23:59" 같은 값이 오늘이 되어 판정이 뒤집힌다."""
    if timedelta(0) < boundary - now.astimezone(SEOUL) < timedelta(seconds=60):
        return f'지금은 실행 금지 시간 — 자정 직후({(boundary + timedelta(minutes=1)):%H:%M})에 다시'
    return None


def midnight_refusal(now):
    """E-POLL-07 · 16 — 서울 자정까지 60초 미만이면 거절 문구."""
    return _midnight_wait(now, seoul_day_start(now) + timedelta(days=1))


def month_end_refusal(now):
    """E-HEART-17 — 서울 달이 바뀌기 60초 미만 전이면 거절 문구(달 중간의 자정은 상관없다)."""
    start = seoul_month_start(now)
    return _midnight_wait(now, (start + timedelta(days=32)).replace(day=1))


def _refuse_near(refusal):
    if refusal:
        raise Blocked(refusal)


def vote_slots_this_week(now):
    """이번 주 월요일 00:00:10 · 00:10 · 00:20 — 오늘이 월요일이면 이 시각들이 오늘이라 "하루 한 번" 규칙이 먼저 막아 주간 한도를 따로 못 본다 → None."""
    if now.astimezone(SEOUL).weekday() == 0:
        return None
    start = seoul_week_start(now)
    return [start + timedelta(seconds=10), start + timedelta(minutes=10), start + timedelta(minutes=20)]


def vote_slots_last_week(now):
    """지난주 월요일 00:00:10 · 00:10 · 화요일 00:20 — 월요일에 주간 한도를 RPC 로 볼 때 쓴다(셋 다 [reward_check_time] 의 같은 주, 그날 이전)."""
    start = seoul_week_start(now) - timedelta(days=7)
    return [start + timedelta(seconds=10), start + timedelta(minutes=10), start + timedelta(days=1, minutes=20)]


def reward_check_time(now):
    """지난주 수요일 낮(서울) — poll_vote_reward_due 의 p_now. 이 시각 "오늘" 에는 적립이 없고 그 주(월~)에는 30 이 쌓여 있다."""
    return seoul_week_start(now) - timedelta(days=7) + timedelta(days=2, hours=12)


def vote_slots_with_sunday(now):
    """지난 일요일 23:59 한 줄 + 나머지 둘. 월요일이 아니면 나머지는 이번 주 월요일 새벽, 월요일이면 같은 일요일 밤 23:57 · 23:58."""
    sunday = seoul_week_start(now) - timedelta(minutes=1)
    early = vote_slots_this_week(now)
    return (early[:2] if early else [sunday - timedelta(minutes=2), sunday - timedelta(minutes=1)]) + [sunday]


# ── 준비 도우미 ─────────────────────────────────────────────────────────────────────────────────────

def _move(run, path, fields, *owners):
    """이번 실행이 만든 계정의 행만 시각을 옮긴다(_guard)."""
    _guard(run, *owners)
    _patch(run, path, fields)


def _prepared(reply, label):
    if reply[0] != 200:
        raise Blocked(f'준비: {label} {reply[0]} {_detail(reply[1])}')
    return reply[1]


def _decide(run, owner, card, decision):
    return _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': decision}, **_ONCE)


def _respond(run, who, card, decision):
    return _api(run, 'POST', f'/cards/acceptances/{card}', who['token'], {'decision': decision}, **_ONCE)


def _pair(run):
    """A(남) · V(여) — 처음에는 V 가 A 의 후보여야 시각 규칙이 따로 보인다."""
    a, v = _person(run, 'male'), _person(run, 'female')
    if v['id'] not in _candidates(run, a):
        raise Blocked('준비: 처음부터 V 가 A 의 후보가 아니다(시험대학 region_group 이 e2e 인지 확인)')
    return a, v


def _seed_votes(run, account, count):
    """투표 하트 원장 [count] 줄 — 원장만 넣으면 잔액 캐시와 어긋나(E-HEART-40) grant_hearts 로 둘 다 쓴다."""
    for _ in range(count):
        status, body = _grant(run, account, 10, 'poll_vote')
        if status >= 300:
            raise Blocked(f'투표 하트 지급 {status} {body}')


def _move_votes(run, account, whens):
    ids = [r['id'] for r in _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.poll_vote&select=id&order=created_at.asc")]
    if len(ids) != len(whens):
        raise Blocked(f'준비: 투표 하트 원장 {len(ids)}줄(기대 {len(whens)})')
    for row, when in zip(ids, whens):
        # 시각을 막는 트리거 없음. id 로 한 줄만 고르지만 계정 필터도 한 겹 더 단다 — id 를 잘못 읽어도 남의 원장은 못 건드린다
        _move(run, f"heart_transactions?id=eq.{row}&profile_id=eq.{account['id']}", {'created_at': when.isoformat()}, account['id'])


def _vote(run, voter, poll):
    reply = _api(run, 'POST', f'/community/polls/{poll}/votes', voter['token'], {'choice': 'a'}, **_ONCE)
    return reply, (reply[1].get('rewarded') if reply[0] == 200 and isinstance(reply[1], dict) else None)


def _heart_task(run, account, name):
    reply = _api(run, 'GET', '/heart-tasks', account['token'])
    if reply[0] != 200:
        raise Blocked(f'GET /heart-tasks {reply[0]} {_detail(reply[1])}')
    return next(t for t in reply[1]['tasks'] if t['task'] == name)


def _last_active(run, account):
    return _rows(run, f"profiles?id=eq.{account['id']}&select=last_active_at")[0]['last_active_at']


# ── 사다리 · 후보 시간 규칙 ─────────────────────────────────────────────────────────────────────────

def _active_counts(run, region):
    status, rows = tools.rest(run.cfg, run.key, 'POST', 'rpc/region_active_counts', {})
    if status >= 300:
        raise Blocked(f'region_active_counts {status} {rows}')
    return {r['gender']: r['active_count'] for r in rows if r['region_group'] == region}


def card_10(run):
    """사다리 인원: 일시중지 · 15일 미접속은 빠지고, 13일 미접속은 남는다(region_active_counts — 20260928050000:210-225).
    다른 줄(성별 없음 · 안 열린 학교)은 이 묶음이 못 만든다 — 성별 없는 active 는 profiles_active_requires_onboarding check 가 막고(DB 가 거절하는지만 본다),
    안 열린 학교는 학교 행을 써야 해 이번 실행 계정만 쓴다는 규칙에 걸린다."""
    check = Check()
    school = _test_university(run)
    if not school:
        raise Blocked('시험대학 행을 못 찾음')
    region = _rows(run, f'universities?id=eq.{school}&select=region_group')[0]['region_group']
    base = _active_counts(run, region).get('female', 0)
    fresh, paused, quiet = _home(run, 'female'), _home(run, 'female'), _home(run, 'female')
    _home(run, 'female', last_active_at=_ago(days=13))  # 14일 안이라 세어야 하는 대조
    before = _active_counts(run, region).get('female', 0)
    check.that(before - base == 4, f'준비가 틀림: 여자 4명을 만들었는데 {region} 여자 수가 {before - base}명 늘었다(13일 미접속은 세어야 한다)')
    _prepared(_api(run, 'PATCH', '/cards/matching-paused', paused['token'], {'paused': True}), '일시중지')
    _move(run, f"profiles?id=eq.{quiet['id']}", {'last_active_at': _ago(days=STALE_DAYS)}, quiet['id'])
    dropped = before - _active_counts(run, region).get('female', 0)
    check.that(dropped == 2, f'줄어든 수 {dropped}(기대 2 — 일시중지 1 + 15일 미접속 1)')
    _guard(run, fresh['id'])
    status, body = tools.rest(run.cfg, run.key, 'PATCH', f"profiles?id=eq.{fresh['id']}", {'gender': None})
    check.that(status >= 400 and '23514' in str(body), f'성별 없는 active 가 {status} {_detail(body)}(기대 23514 — 그래서 사다리에 못 들어온다)')
    return check.result(f'{region} 여자 {base} → {before} → {before - dropped}')


def card_32(run):
    """후보 하드 필터 `last_active_at > now() − 15 days`(:94). 15일 1분 전은 빠지고 14일 23시간 전은 남는다."""
    check = Check()
    me = _person(run, 'male')
    stale = _person(run, 'female', last_active_at=_ago(days=STALE_DAYS, minutes=1))
    fresh = _person(run, 'female', last_active_at=_ago(days=14, hours=23))
    got = _candidates(run, me)
    check.that(stale['id'] not in got, '15일 1분 안 들어온 V1 이 후보다')
    check.that(fresh['id'] in got, '14일 23시간 전에 들어온 V2 가 후보에서 빠짐')
    return check.result()


def _rest_after_decision(run, ago, back):
    """A 가 V 카드를 거절한 뒤 결정 시각을 [ago] 만큼 과거로 — 후보로 돌아왔는가가 [back] 이어야 한다(:113)."""
    check = Check()
    a, v = _pair(run)
    card = _card(run, a, v)
    _prepared(_decide(run, a, card, 'reject'), '거절')
    check.that(v['id'] not in _candidates(run, a), '결정한 직후에는 후보에서 빠져 있어야 한다(준비가 틀림)')
    _move(run, f'card_decisions?card_id=eq.{card}', {'decided_at': _ago(**ago)}, a['id'], v['id'])
    back_now = v['id'] in _candidates(run, a)
    check.that(back_now == back, '90일 1분 지난 상대가 아직 후보가 아니다' if back else '89일 전에 결정한 상대가 벌써 후보로 돌아옴')
    return check.result()


def card_50(run):
    return _rest_after_decision(run, {'days': DECIDED_REST_DAYS - 1}, back=False)


def card_51(run):
    return _rest_after_decision(run, {'days': DECIDED_REST_DAYS, 'minutes': 1}, back=True)


def card_52(run):
    """결정 없이 만료된 카드 — 만료 뒤 14일은 쉬고(:114) 14일 1분이 지나면 후보다. 만료는 expires_at 으로만 판정한다(행을 안 쓴다)."""
    check = Check()
    a, v = _pair(run)
    card = _card(run, a, v, days=-(EXPIRED_REST_DAYS - 1))
    check.that(v['id'] not in _candidates(run, a), '13일 전에 만료된 카드의 상대가 벌써 후보다')
    _move(run, f'daily_cards?id=eq.{card}', {'expires_at': _ago(days=EXPIRED_REST_DAYS, minutes=1)}, a['id'], v['id'])
    check.that(v['id'] in _candidates(run, a), '14일 1분 전에 만료된 카드의 상대가 아직 후보가 아니다')
    return check.result()


def card_53(run):
    """V→A 카드를 V 가 수락 → A 가 거절로 답하면 응답 시각 + 90일 쉰다(:118-127). 후보가 안 되는 이유가 이 줄뿐이게 A 쪽 카드는 두지 않는다."""
    check = Check()
    a, v = _pair(run)
    card = _card(run, v, a)
    _prepared(_decide(run, v, card, 'accept'), 'V 의 수락')
    check.that(v['id'] in _candidates(run, a), '답하기 전에는 V 가 후보여야 한다(준비가 틀림)')
    _prepared(_respond(run, a, card, 'reject'), 'A 의 거절 응답')
    check.that(v['id'] not in _candidates(run, a), '답한 직후에는 후보에서 빠져 있어야 한다(준비가 틀림)')
    move = lambda **ago: _move(run, f'acceptance_responses?card_id=eq.{card}', {'decided_at': _ago(**ago)}, a['id'], v['id'])  # noqa: E731
    move(days=DECIDED_REST_DAYS - 1)
    check.that(v['id'] not in _candidates(run, a), '89일 전에 답한 상대가 벌써 후보로 돌아옴')
    move(days=DECIDED_REST_DAYS, minutes=1)
    check.that(v['id'] in _candidates(run, a), '90일 1분 전에 답한 상대가 아직 후보가 아니다')
    return check.result()


def card_54(run):
    """쌍방 수락으로 매칭된 둘은 기간 없이 영원히 서로 안 나온다(:128-134). 결정 · 응답 · 매칭 시각을 400일 전으로 보내 다른 줄이 막는 게 아니게 한다."""
    check = Check()
    a, v = _pair(run)
    check.that(a['id'] in _candidates(run, v), '처음에는 A 도 V 의 후보여야 한다(준비가 틀림)')
    card = _card(run, a, v)
    _prepared(_decide(run, a, card, 'accept'), 'A 의 수락')
    match = _prepared(_respond(run, v, card, 'accept'), 'V 의 수락 응답')
    if not match.get('matched'):
        raise Blocked(f'준비: 매칭이 안 됨 {match}')
    old = _ago(days=400)
    for path, column in ((f'card_decisions?card_id=eq.{card}', 'decided_at'), (f'acceptance_responses?card_id=eq.{card}', 'decided_at'),
                         (f"matches?id=eq.{match['match_id']}", 'created_at')):
        _move(run, path, {column: old}, a['id'], v['id'])
    check.that(v['id'] not in _candidates(run, a), '400일이 지난 매칭 상대 V 가 A 의 후보로 나옴')
    check.that(a['id'] not in _candidates(run, v), '400일이 지난 매칭 상대 A 가 V 의 후보로 나옴')
    return check.result()


def card_68(run):
    """활동성 계수(scoring.py:57-66): 마지막 접속 0~3일 ×1.0 · 4~7일 ×0.7 · 8~14일 ×0.4 — "일" 은 경과 시간의 정수 일수(timedelta.days)다.
    만점 복제 셋(C0 와 같은 값)의 점수가 곧 계수다. 3일 23시간은 3일이라 1.0."""
    check = Check()
    owner = _person(run, 'male', **OWNER)
    plan = ((dict(days=3, hours=23), 1.0), (dict(days=5), 0.7), (dict(days=10), 0.4))
    clones = [(_person(run, 'female', 1, 0, last_active_at=_ago(**ago), **CLONE), want) for ago, want in plan]
    got = _candidates(run, owner)
    for (clone, want), label in zip(clones, ('3일 23시간', '5일', '10일')):
        score = got.get(clone['id'])
        check.that(score is not None, f'{label} 전 복제가 후보에 없음')
        check.that(score is None or abs(score - want) <= area2.SCORE_TOLERANCE, f'{label} 전 복제 점수 {score}(기대 {want})')
    return check.result()


# ── 받은 수락 7일 · 카드 만료 ───────────────────────────────────────────────────────────────────────

def _accepted(run):
    """O 가 T 에게 카드를 수락 → (O, T, 카드). 수락함은 받는 쪽(T)이 본다."""
    owner, target = _home(run, 'male'), _home(run, 'female')
    card = _card(run, owner, target)
    _prepared(_decide(run, owner, card, 'accept'), '수락')
    return owner, target, card


def _acceptance_ids(run, target):
    reply = _api(run, 'GET', '/cards/acceptances', target['token'])
    if reply[0] != 200:
        raise Blocked(f'GET /cards/acceptances {reply[0]} {_detail(reply[1])}')
    return reply[1]['acceptances']


def card_80(run):
    """cards/router.py:188-209 — 수락 후 7일(decided_at + 7일) 동안 목록에 있고 `expires_at` 이 그 시각이다. 화면(대화 탭 줄)은 안 봤다."""
    check = Check()
    owner, target, card = _accepted(run)
    moved = _now() - timedelta(days=6, hours=23)
    _move(run, f'card_decisions?card_id=eq.{card}', {'decided_at': moved.isoformat()}, owner['id'], target['id'])
    rows = _acceptance_ids(run, target)
    check.that([r['card_id'] for r in rows] == [card], f'받은 수락 {[r["card_id"] for r in rows]}(기대 [{card[:8]}…] 하나)')
    if rows:
        want = moved + timedelta(days=ACCEPTANCE_DAYS)
        check.that(abs(_at(rows[0]['expires_at']) - want) <= timedelta(seconds=1), f'만료 시각 {rows[0]["expires_at"]} ≠ 수락 시각 + 7일 {want.isoformat()}')
    return check.result('화면의 대화 탭 줄은 안 봄')


def card_81(run):
    """router.py:230-232 — 7일 1분이 지나면 목록에서 사라지고, 열어 둔 화면에서 수락해도 410 "기한이 지났어요", 매칭 0."""
    check = Check()
    owner, target, card = _accepted(run)
    check.that(len(_acceptance_ids(run, target)) == 1, '처음에는 수락이 하나 보여야 한다(준비가 틀림)')
    _move(run, f'card_decisions?card_id=eq.{card}', {'decided_at': _ago(days=ACCEPTANCE_DAYS, minutes=1)}, owner['id'], target['id'])
    check.reply('열어 둔 화면에서 수락', _respond(run, target, card, 'accept'), 410, '기한이 지났어요')
    check.that(not _acceptance_ids(run, target), '목록에 7일 지난 수락이 남음')
    check.that(not _rows(run, f"matches?or=(profile_a.eq.{owner['id']},profile_b.eq.{owner['id']})&select=id"), 'matches 에 행이 생김')
    check.that(not _rows(run, f'acceptance_responses?card_id=eq.{card}&select=card_id'), 'acceptance_responses 에 행이 생김')
    return check.result('화면의 오류 글 표시는 안 봄 — 서버 410 과 문구까지')


def card_84(run):
    """router.py:175-176 — 상세를 열어 둔 사이 expires_at 이 지나면 수락해도 409 "지난 카드예요", 결정 0행."""
    check = Check()
    owner, target = _home(run, 'male'), _home(run, 'female')
    card = _card(run, owner, target)
    check.reply('상세 열기', _api(run, 'GET', f'/cards/{card}', owner['token']), 200)
    _move(run, f'daily_cards?id=eq.{card}', {'expires_at': _ago(minutes=1)}, owner['id'], target['id'])
    check.reply('수락하기', _decide(run, owner, card, 'accept'), 409, '지난 카드예요')
    check.that(not _rows(run, f'card_decisions?card_id=eq.{card}&select=card_id'), '결정 행이 생김')
    return check.result('화면의 상세 열림 · 오류 글은 안 봄')


# ── 투표 하트 ───────────────────────────────────────────────────────────────────────────────────────

def poll_07(run):
    _refuse_near(midnight_refusal(now_seoul()))
    author, voter = _home(run), _home(run)
    try:
        return _poll_07(run, author, voter)
    finally:
        _drop_polls(run, author)


def _poll_07(run, author, voter):
    """create_poll_functions.sql:90-97 — 하루는 서울 0시. 오늘 받은 원장 줄을 어제 23:59 로 옮기면 오늘 첫 투표가 다시 10하트."""
    check = Check()
    first, second, third = (_poll(run, author, f'자정 {i}') for i in (1, 2, 3))
    check.that(_vote(run, voter, first)[1] is True, '오늘 첫 투표가 하트를 안 줌(준비가 틀림)')
    check.that(_vote(run, voter, second)[1] is False, '오늘 두 번째 투표가 하트를 줌(준비가 틀림)')
    _move_votes(run, voter, [yesterday_2359(_now())])
    reply, rewarded = _vote(run, voter, third)
    check.reply('자정 뒤 투표', reply, 200)
    check.that(rewarded is True, f'rewarded={rewarded}(기대 true — 어제 23:59 적립은 오늘 몫이 아니다)')
    check.that(_ledger(run, voter, 'poll_vote') == [10, 10], f'원장 {_ledger(run, voter, "poll_vote")}(기대 [10, 10])')
    return check.result()


def poll_08(run):
    slots = vote_slots_this_week(_now())
    if slots is None:  # 월요일 새벽 슬롯은 오늘이라 하루 규칙이 먼저 막는다 — 주간 한도만 보려면 지난주로 가서 RPC 에 p_now 를 준다
        return _poll_08_monday(run)
    author, voter = _home(run), _home(run)
    try:
        return _poll_08(run, author, voter, slots)
    finally:
        _drop_polls(run, author)


def _poll_08_monday(run):
    """월요일에는 API 투표로 주간 한도만 따로 못 본다(이번 주 앞 날이 없다). 대신 원장 3줄을 지난주 월 · 월 · 화로 옮기고
    poll_vote_reward_due(p_voter, p_now)(20260927020100, service_role)를 지난주 수요일 낮 p_now 로 불러 false(주 한도 30)여야 한다.
    API 경로(투표 · 18a 줄)는 안 거치므로 서버 시계가 아니라 SQL 규칙만 본다."""
    check = Check()
    voter = _home(run)
    _seed_votes(run, voter, 3)
    _move_votes(run, voter, vote_slots_last_week(_now()))
    asked = reward_check_time(_now())
    status, got = tools.rest(run.cfg, run.key, 'POST', 'rpc/poll_vote_reward_due', {'p_voter': voter['id'], 'p_now': asked.isoformat()})
    if status >= 300:
        raise Blocked(f'poll_vote_reward_due {status} {got}')
    check.that(got is False, f'rewarded 판정(poll_vote_reward_due)={got}(기대 false — {asked:%m-%d %H:%M} 기준 그 주 이미 30)')
    check.that(_ledger(run, voter, 'poll_vote') == [10, 10, 10], f'원장 {_ledger(run, voter, "poll_vote")}(기대 3줄 그대로)')
    return check.result('월요일이라 API 투표 대신 RPC 에 p_now = 지난주 수요일 낮을 줌 — 투표 API · 18a 줄은 안 봄')


def _poll_08(run, author, voter, slots):
    """:98-101 — 이번 주(월 0시 서울~) poll_vote 합이 30 이면 오늘 첫 투표라도 보상 없음. 18a 투표 줄의 used 도 같은 세기로 3."""
    check = Check()
    _seed_votes(run, voter, 3)
    _move_votes(run, voter, slots)
    task = _heart_task(run, voter, 'poll_vote')
    check.that(task['used'] == 3, f'18a 투표 줄 used {task["used"]}(기대 3)')
    reply, rewarded = _vote(run, voter, _poll(run, author, '주간 한도'))
    check.reply('투표', reply, 200)
    check.that(rewarded is False, f'rewarded={rewarded}(기대 false — 이번 주 이미 30)')
    check.that(_ledger(run, voter, 'poll_vote') == [10, 10, 10], f'원장 {_ledger(run, voter, "poll_vote")}(기대 3줄 그대로)')
    return check.result()


def poll_09(run):
    author, voter = _home(run), _home(run)
    try:
        return _poll_09(run, author, voter)
    finally:
        _drop_polls(run, author)


def _poll_09(run, author, voter):
    """:92,101 — 지난 일요일 23:59 적립은 이번 주(월요일 0시~)에 안 센다. 월요일이면 셋 다 지난 일요일 밤이라 "월요일 새벽 두 줄" 부분은 못 본다."""
    check = Check()
    slots = vote_slots_with_sunday(_now())
    _seed_votes(run, voter, 3)
    _move_votes(run, voter, slots)
    this_week = len([s for s in slots if s >= seoul_week_start(_now())])
    task = _heart_task(run, voter, 'poll_vote')
    check.that(task['used'] == this_week, f'18a 투표 줄 used {task["used"]}(기대 {this_week} — 지난 일요일 줄은 안 센다)')
    reply, rewarded = _vote(run, voter, _poll(run, author, '일요일 경계'))
    check.reply('투표', reply, 200)
    check.that(rewarded is True, f'rewarded={rewarded}(기대 true — 지난주 일요일 적립은 이번 주에 안 센다)')
    check.that(_ledger(run, voter, 'poll_vote') == [10, 10, 10, 10], f'원장 {_ledger(run, voter, "poll_vote")}(기대 4줄)')
    return check.result('월요일이라 이번 주 적립 0줄로 본 날' if this_week == 0 else '')


def poll_16(run):
    _refuse_near(midnight_refusal(now_seoul()))
    author = _home(run)
    try:
        return _poll_16(run, author)
    finally:
        _drop_polls(run, author)


def _poll_16(run, author):
    """create_poll_functions.sql:66-68 — 하루 10개는 서울 0시부터 센다. 열 개를 어제 23:59 로 옮기면 새 글이 201. 옮기기 전 11번째는 429(한도가 실제로 있다는 대조)."""
    check = Check()
    for i in range(10):
        _poll(run, author, f'어제 {i + 1}')
    post = lambda: _api(run, 'POST', '/community/polls', author['token'], {'question': '[E2E] 자정 뒤 새 글'}, **_ONCE)  # noqa: E731
    check.reply('11번째(옮기기 전)', post(), 429)
    _move(run, f"polls?author_id=eq.{author['id']}", {'created_at': yesterday_2359(_now()).isoformat()}, author['id'])
    check.reply('새 글(어제로 옮긴 뒤)', post(), 201)
    return check.result()


# ── 무료 하트 한도 ──────────────────────────────────────────────────────────────────────────────────

def _past_submission(run, account, task, created_at, status, **extra):
    """과거 시각 제출 행을 처음부터 insert — created_at 은 트리거(heart_task_submissions_guard)가 못 바꾸게 막는다. 승인 줄은 insert 라 지급 트리거(update)가 안 돈다."""
    sid = area2._new_id()
    row = {'id': sid, 'profile_id': account['id'], 'task': task, 'status': status, 'reward_hearts': 50,
           'created_at': created_at.isoformat(), **extra}
    _insert(run, 'heart_task_submissions', [row], account['id'])
    return sid


def heart_17(run):
    """heart_task_status 의 이번 달 = 서울 1일 0시~(:16-17,35-44). 지난달 말일 23:59:59 승인은 안 세고, 이번 달 1일 0시 승인은 센다(대조)."""
    _refuse_near(month_end_refusal(now_seoul()))
    check = Check()
    account = _home(run)
    start = seoul_month_start(_now())
    _past_submission(run, account, 'everytime_post', start - timedelta(seconds=1), 'approved', reviewed_at=(start - timedelta(seconds=1)).isoformat())
    _past_submission(run, account, 'kakao_share', start, 'approved', reviewed_at=start.isoformat())
    everytime, kakao = _heart_task(run, account, 'everytime_post'), _heart_task(run, account, 'kakao_share')
    check.that((everytime['used'], everytime['state']) == (0, 'open'), f'에브리타임 used {everytime["used"]} state {everytime["state"]}(기대 0 · open)')
    check.that(kakao['used'] == 1, f'단톡방 used {kakao["used"]}(기대 1 — 이번 달 1일 0시 승인은 센다)')
    return check.result()


def heart_18(run):
    """검수 중은 달과 상관없이 본다(:19,46-47). 지난달에 낸 제출이 아직 submitted 면 이번 달에도 reviewing 이고 새 제출은 409."""
    check = Check()
    account = _home(run)
    sid = area2._new_id()
    when = seoul_month_start(_now()) - timedelta(days=1)
    _past_submission(run, account, 'everytime_post', when, 'submitted', storage_path=f"{account['id']}/{sid}.jpg")
    task = _heart_task(run, account, 'everytime_post')
    check.that((task['state'], task['used']) == ('reviewing', 0), f'state {task["state"]} used {task["used"]}(기대 reviewing · 0)')
    check.reply('새 제출', _submit(run, account), 409, IN_REVIEW)
    check.that(len(area2._submission_rows(run, account)) == 1, '제출 행이 늘어남')
    check.that(area2._proofs(run, account) == 0, f'버킷 파일 {area2._proofs(run, account)}개(기대 0)')
    return check.result()


# ── 마지막 접속 ─────────────────────────────────────────────────────────────────────────────────────
# 시나리오는 A폰 앱 재시작이지만 앱이 메인을 열 때 부르는 GET /home/summary(home/router.py:22-27)를 직접 부른다 — 앱 실제 재시작은 안 본다.

def home_07(run):
    """home/repository.py:42-51 — 마지막 접속이 1시간 넘게 지났으면(2시간 전) 지금으로 바꾼다."""
    check = Check()
    account = _home(run)
    _move(run, f"profiles?id=eq.{account['id']}", {'last_active_at': _ago(hours=2)}, account['id'])
    before = _last_active(run, account)
    check.reply('홈 요약', _api(run, 'GET', '/home/summary', account['token']), 200)
    after = _last_active(run, account)
    check.that(abs(_at(after) - _now()) <= timedelta(minutes=1), f'last_active_at {before} → {after}(기대 지금 ±1분)')
    return check.result('앱 실제 재시작은 안 봄 — GET /home/summary 직접 호출')


def home_08(run):
    """같은 곳 — 30분 전이면 필터(lt now−1h)에 안 걸려 0행 갱신이다. 값이 1초도 안 바뀐다."""
    check = Check()
    account = _home(run)
    _move(run, f"profiles?id=eq.{account['id']}", {'last_active_at': _ago(minutes=30)}, account['id'])
    before = _last_active(run, account)
    check.reply('홈 요약', _api(run, 'GET', '/home/summary', account['token']), 200)
    after = _last_active(run, account)
    check.that(after == before, f'last_active_at 이 {before} → {after} 로 바뀜')
    return check.result('앱 실제 재시작은 안 봄 — GET /home/summary 직접 호출')


CASES = {
    'E-CARD-10': card_10, 'E-CARD-32': card_32, 'E-CARD-50': card_50, 'E-CARD-51': card_51, 'E-CARD-52': card_52,
    'E-CARD-53': card_53, 'E-CARD-54': card_54, 'E-CARD-68': card_68,
    'E-CARD-80': card_80, 'E-CARD-81': card_81, 'E-CARD-84': card_84,
    'E-POLL-07': poll_07, 'E-POLL-08': poll_08, 'E-POLL-09': poll_09, 'E-POLL-16': poll_16,
    'E-HEART-17': heart_17, 'E-HEART-18': heart_18,
    'E-HOME-07': home_07, 'E-HOME-08': home_08,
}
BUNDLES = {'area2-time-api': list(CASES)}


def attempt(run, case):
    """가설 하나 — 준비가 안 되면 blocked, 끊김은 처음부터 한 번 더(area2.attempt_with)."""
    return area2.attempt_with(run, CASES[case])
