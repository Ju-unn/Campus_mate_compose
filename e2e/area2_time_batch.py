"""영역 2 배치 가설 — daily-cards · cleanup 배치를 `area2._batch` 로 손으로 부르고, 결과를 PC 에서 DB · API 로 읽는다(묶음 area2-time-batch).
폰 · 알림 관찰은 없다(알림이 필요한 가설은 area2_phone3). 기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이되, 코드가 다르면 코드가 기준이다.

배치는 응답 본문을 못 읽고 끝도 기다려 주지 않는다 → DB 를 다시 읽는다. 읽기 전에 "배치가 돌았다는 증거"(앵커)를 기다린다 —
카드는 설정 행의 요일(행에 일부러 사다리가 낼 수 없는 값을 심어 두면 배치가 새로 적는다), 정리는 61일 된 인증샷 줄이 비워지는 것.
앵커가 없으면 "카드 0" · "파일 남음" 같은 음성 판정이 배치가 안 돈 탓일 수 있어 blocked 로 끝낸다.
쓰기는 이번 실행이 만든 계정 id([area2._guard]) 와 시험 지역(`e2e`) 설정 행(끝나면 원복)에만 한다. 배치는 모든 지역을 돌지만
다른 행은 읽기만 한다 — 서울 지급일(월요일) · 00:00~07:10 은 관문(batch_gate)이 막는다.
"""

import random
import time
from contextlib import contextmanager
from datetime import datetime, time as clock, timedelta

from e2e import area2, area2_phone3, batch_gate, tools
from e2e.area1 import TINY_JPEG, Check, _api, _at, _one, _patch, _rows, _test_university
from e2e.area2 import _ONCE, _candidates, _guard, _insert, _person
from e2e.area2_phone3 import EVERY_DAY, LADDER_ZERO, TEST_REGION, WEEKDAY_NAMES, region_set
from e2e.area2_time_device import future_monday
from e2e.tools import Blocked

# 사다리 5칸(backend/app/cards/ladder.py) — 이름은 칸, 값은 ISO 요일(1=월). 시나리오 E-CARD-08 의 차례.
STEPS = [('once', [1]), ('twice', [1, 4]), ('three', [1, 3, 5]), ('four', [1, 3, 5, 7]), ('daily', list(EVERY_DAY))]
RUNGS = ('ladder_twice_per_week_min', 'ladder_three_per_week_min', 'ladder_four_per_week_min', 'ladder_daily_min')
SENTINEL = [2]  # 사다리가 절대 못 내는 요일 목록(화요일만) — 행에 심어 두면 배치가 새로 적는 것이 "돌았다" 는 증거가 된다


# ── 순수 도우미 ─────────────────────────────────────────────────────────────────────────────────────

def thresholds_for(weekdays, count):
    """남녀 중 적은 쪽 활성 인원이 [count] 명일 때 사다리가 [weekdays] 칸을 내게 하는 임계값 4개.
    칸 k 는 "아래 칸 기준 이상 · 이 칸 기준 미만" 이라 k 번째 앞은 0, 나머지는 count+1 이다. 순서 check(twice ≤ three ≤ four ≤ daily)를 지킨다."""
    names = [w for _, w in STEPS]
    if list(weekdays) not in names:
        raise ValueError(f'{weekdays} — 사다리 칸이 아니다({names})')
    k = names.index(list(weekdays))
    return {column: (0 if i < k else count + 1) for i, column in enumerate(RUNGS)}


def step_for_today(weekday):
    """오늘(ISO 요일)이 든 가장 성긴 칸 — 오늘이 지급 요일이어야 배치가 카드를 낸다(issuing.py:35-36)."""
    return next(list(w) for _, w in STEPS if weekday in w)


def step_without_today(weekday):
    """오늘이 안 든 칸 — 지급 요일이 아닌 날(E-CARD-09). 월요일은 모든 칸에 있어 없다(관문이 월요일 배치를 막는다)."""
    for _, w in STEPS:
        if weekday not in w:
            return list(w)
    raise ValueError('모든 칸에 오늘이 든다(월요일)')


def expected_expiry(now, weekdays, issue_time):
    """무료 카드 expires_at = 오늘 다음(내일부터) 첫 지급 요일의 [issue_time](서울). backend/app/cards/ladder.py next_issue_at 과 같은 식.
    [now] 는 서울 시각."""
    for ahead in range(1, 8):
        day = (now + timedelta(days=ahead)).date()
        if day.isoweekday() in weekdays:
            return datetime.combine(day, issue_time, tzinfo=now.tzinfo)
    raise ValueError(f'지급 요일이 비어 있다: {weekdays!r}')


# ── 준비 · 읽기 ─────────────────────────────────────────────────────────────────────────────────────

FIRST_BATCH_WAIT = 120  # 첫 배치가 설정 행을 새로 적을 때까지(콜드 스타트 포함)
BATCH_WAIT = 60         # 이어지는 배치
CARD_WAIT = 90          # 앵커를 본 뒤 카드 행이 들어올 때까지


def _prepare(run):
    """모든 카드 가설의 첫 문 — 시각 · 지역을 계정을 만들기 전에 본다(금지 시각이면 운영에 아무것도 안 쓰고 blocked).
    `area2._batch` 가 한 번 더 보지만 그때는 이미 계정이 만들어진 뒤다. 돌려주는 값 = 시험 지역."""
    batch_gate.check('daily-cards')
    return _region(run)


def _region(run):
    school = _test_university(run)
    if not school:
        raise Blocked('시험대학 행을 못 찾음')
    region = _one(run, f'universities?id=eq.{school}&select=region_group').get('region_group')
    if region != TEST_REGION:
        raise Blocked(f'시험대학 지역이 {region!r} — {TEST_REGION!r} 이어야 한다(배치는 모든 지역을 도니 시험 지역 설정만 바꾼다)')
    return region


def _closed_school(run, region):
    """같은 지역에서 아직 안 열린(card_opens_at 이 미래인) 학교 id — 없으면 None. 시험 대학에 값을 넣으면 카드 시험 전체가 멈춰서 둘째 학교를 쓴다(시나리오 G2)."""
    now = area2._now()
    for row in _rows(run, f'universities?region_group=eq.{region}&select=id,name,card_opens_at'):
        if row['card_opens_at'] and _at(row['card_opens_at']) > now:
            return row['id']
    return None


COHORT_PREFIX = 'e2e-cohort-'  # 이 시험이 만드는 둘째 학교 이름 머리 — 실제 학교 이름과 섞이지 않는다


def _cohort_rows(run):
    """남아 있는 `e2e-cohort-` 학교 id — 이름 틀로 지우면 틀을 못 읽는 서버가 전부 지우므로 읽어서 이름을 파이썬에서 거른다."""
    return [r['id'] for r in _rows(run, 'universities?select=id,name') if r['name'].startswith(COHORT_PREFIX)]


def _drop_cohort(run, schools, home):
    """[schools] 에 든 계정을 시험대학([home])으로 돌려놓고 그 학교 행을 지운다 — profiles.university_id 가 on delete restrict 라 이 순서."""
    for school in schools:
        status, body = tools.rest(run.cfg, run.key, 'PATCH', f'profiles?university_id=eq.{school}', {'university_id': home})
        if status >= 300:
            raise Blocked(f'둘째 시험학교 {school} 의 계정을 못 돌려놓음 {status} {body} — 행이 남았다, 손으로 지울 것')
        status, body = tools.rest(run.cfg, run.key, 'DELETE', f'universities?id=eq.{school}')
        if status >= 300:
            raise Blocked(f'둘째 시험학교 행 {school} 을 못 지움 {status} {body} — 손으로 지울 것')


@contextmanager
def _cohort_school(run, region):
    """아직 안 열린 둘째 시험학교 id(시나리오 G2). 같은 지역에 이미 닫힌 학교가 있으면 그대로 쓰고(지우지 않는다),
    없으면 `e2e-cohort-…` 행(card_opens_at = 다음 월요일 07:00 서울)을 이 시험이 만들어 끝에 지운다 — 스키마는 그대로, 데이터 행 하나.
    시작에서 앞 실행이 죽어 남긴 `e2e-cohort-` 행부터 지운다."""
    home = _test_university(run)
    _drop_cohort(run, _cohort_rows(run), home)
    found = _closed_school(run, region)
    if found:
        yield found
        return
    school = area2._new_id()
    status, body = tools.rest(run.cfg, run.key, 'POST', 'universities',
                              [{'id': school, 'name': f'{COHORT_PREFIX}{school[:8]}', 'region_group': region,
                                'card_opens_at': future_monday(batch_gate.now_seoul()).isoformat()}])
    if status >= 300:
        raise Blocked(f'둘째 시험학교 행을 못 만듦 {status} {body}')
    try:
        yield school
    finally:
        _drop_cohort(run, [school], home)


def _counts(run, region):
    """{성별: 활성 인원} — 배치가 사다리에 넣는 값(region_active_counts)을 그대로 읽는다."""
    status, rows = tools.rest(run.cfg, run.key, 'POST', 'rpc/region_active_counts', {})
    if status != 200:
        raise Blocked(f'region_active_counts {status} {rows}')
    return {row['gender']: row['active_count'] for row in rows if row['region_group'] == region}


def _bottleneck(counts):
    return min(counts.get('male', 0), counts.get('female', 0))


def _saved(run, region):
    return _one(run, f'region_group_settings?region_group=eq.{region}&select=issue_weekdays').get('issue_weekdays')


def _cards(run, account):
    return _rows(run, f"daily_cards?owner_id=eq.{account['id']}&source=eq.daily&select=id,target_id,issued_at,expires_at&order=issued_at")


def _write(run, account, fields):
    _guard(run, account['id'])
    _patch(run, f"profiles?id=eq.{account['id']}", fields)


def _dated_card(run, owner, target, issued_ago, expires_in):
    """오늘이 아닌 시각에 나간 무료 카드 — 오늘 받은 사람 건너뜀과 섞이지 않게 [issued_ago] 만큼 전에 준 것으로 넣는다(daily_cards 에는 트리거가 없다)."""
    now, card_id = area2._now(), area2._new_id()
    _insert(run, 'daily_cards', [{'id': card_id, 'owner_id': owner['id'], 'target_id': target['id'], 'source': 'daily',
                                 'issued_at': (now - issued_ago).isoformat(), 'expires_at': (now + expires_in).isoformat()}],
            owner['id'], target['id'])
    return card_id


def _must_see(run, viewer, other, what):
    """"빠졌다" 를 보기 전에 "있었다" — 처음부터 없으면 아무것도 증명하지 못한다(준비가 틀린 것이라 blocked)."""
    if other['id'] not in _candidates(run, viewer):
        raise Blocked(f'{what} — 준비가 틀림(후보에 없음)')


def _still_today(today):
    if batch_gate.now_seoul().date() != today.date():
        raise Blocked('시험 중 자정을 넘겨 요일 · 오늘 받은 사람 판정을 못 믿는다 — 다시')


# ── 배치 ────────────────────────────────────────────────────────────────────────────────────────────

_PAID = {}   # (묶음 폴더, 가설) → (결과, 메모) — 배치를 이미 부른 가설의 첫 결과. 진행 프로그램은 fail 이면 가설을 한 번 더 부른다(__main__.run_case)
_FIRED = []  # 지금 도는 가설이 부른 배치 이름들
ALREADY = '배치를 이미 불러 다시 하지 않음'


def _batch(name):
    """`area2._batch` 앞에서 관문을 먼저 본 뒤(막히면 부르지 않았으니 기록하지 않는다) 부른 것을 적는다 —
    gcloud 호출이 끊겨도 나갔을 수 있어 부르기 전에 적는다."""
    batch_gate.check(name)
    _FIRED.append(name)
    area2._batch(name)


def _fire(run, region, wait):
    """daily-cards 를 부르고 설정 행의 요일이 사다리가 낸 값으로 새로 적히기를 기다린다 → 적힌 요일.
    행에 사다리가 못 내는 값([SENTINEL])을 심어 두었으므로 값이 바뀌면 배치가 설정을 읽고 사다리를 돈 것이다(앵커)."""
    _batch('daily-cards')
    if not area2_phone3._wait_for(lambda: _saved(run, region) != SENTINEL, wait):
        raise Blocked(f'배치를 불렀지만 {wait}초 안에 설정 행의 요일이 안 바뀜 — 배치가 안 돌았거나 실패(이 뒤의 "카드 0" 은 믿을 수 없다)')
    return _saved(run, region)


def _issue(run, region, weekdays, control=(), subjects=(), had=None):
    """사다리가 [weekdays] 칸을 내게 임계값을 맞추고 배치를 한 번 불러, 설정 행이 새로 적히면(앵커) 카드가 들어올 때까지 기다린 뒤
    판정 전에 한 번 더 쉰다(다른 사람 몫을 도는 중일 수 있다). 설정 행은 어떻게 끝나든 원래 값으로 되돌린다 → 사다리가 적은 요일.
    [control] 은 같은 배치를 받는 정상 계정 — 이들이 카드를 끝내 못 받으면 blocked(배치가 느리거나 안 돌았다 — 앵커가 보여도 앱 결함과 구분되지 않는다).
    [subjects] 는 카드가 나와야 하는 대상 — 못 받아도 여기서는 막지 않고 부른 쪽이 [_missing] 으로 fail 을 낸다(대조군이 받았으니 배치는 돌았다)."""
    fields = {'issue_weekdays': SENTINEL, **thresholds_for(weekdays, _bottleneck(_counts(run, region)))}
    with region_set(run, region, **fields):
        saved = _fire(run, region, FIRST_BATCH_WAIT)
        got = lambda accounts: all(len(_cards(run, a)) > (had or {}).get(a['id'], 0) for a in accounts)  # noqa: E731
        watched = [*control, *subjects]
        if watched and not area2_phone3._wait_for(lambda: got(watched), CARD_WAIT) and control and not got(control):
            raise Blocked(f'배치는 돌았지만 {CARD_WAIT}초 안에 카드가 안 보임(대조군도 못 받음) — 느린 배치인지 앱 결함인지 구분 못 함, 다시')
        time.sleep(area2.SETTLE_SECONDS)
    return saved


def _missing(check, run, subject, had=0):
    """대상이 카드를 못 받았으면(대조군은 [_issue] 가 받은 것을 확인했다) fail 로 닫는다 — 아니면 None."""
    if len(_cards(run, subject)) > had:
        return None
    check.problems.append('대조군은 카드를 받았는데 대상은 못 받음 — 대조군이 카드를 받아 배치가 돈 것이 확인된 뒤의 fail')
    return check.result()


def _control_man(run):
    """카드가 나와야 하는 가설의 대조군 — 대상과 같은 남자라 대상의 후보 풀(여자)에 못 들어가고, 후보가 될 여자는 가설이 이미 만들어 두었다."""
    return _person(run, 'male')


def _zero_note(control=True):
    """"카드 0" pass 의 한계 — 배치가 끝나는 시점은 못 보므로 고정 대기 뒤의 판정이다."""
    what = '대조군 카드가 나온 뒤' if control else '설정 행이 바뀐 뒤'
    return f'카드 0 은 {what} 고정 {area2.SETTLE_SECONDS}초 시점의 판정'


def _trio(run):
    """A(남) · B(여) · C(여) — A 의 후보는 B · C, C 는 대조군(후보 A 가 있어 반드시 카드를 받는다)."""
    return _person(run, 'male'), _person(run, 'female'), _person(run, 'female')


# ── daily-cards ────────────────────────────────────────────────────────────────────────────────────

def card_04(run):
    """같은 날 배치를 또 돌려도 하루 1장. 첫 배치 대신 오늘 받은 카드를 바로 넣고(거절까지) 배치 한 번으로 "이미 오늘 받은 사람 건너뜀" 을 본다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b, c = _trio(run)
    _must_see(run, a, c, 'A 에게 줄 후보 C 가 없다')  # 없으면 카드가 안 나가는 이유가 "후보 없음" 이 된다
    seed = area2._card(run, a, b)
    check.reply('A 의 거절', _api(run, 'POST', f'/cards/{seed}/decision', a['token'], {'decision': 'reject'}, **_ONCE), 200)
    _issue(run, region, list(EVERY_DAY), control=[c])
    _still_today(today)
    got = len(_cards(run, a))
    check.that(got == 1, f'A 의 오늘 무료 카드가 {got}장(기대 1 — 결정을 끝내도 오늘 두 번째 배치는 건너뛴다)')
    return check.result('오늘 받은 카드를 심어 배치 1회로 확인(첫 배치 + 거절 + 둘째 배치와 같은 결과). 응답 issued 는 못 읽음 — 카드 행 수로 확인. ' + _zero_note())


def card_05(run):
    """아직 결정 안 한 무료 카드가 살아 있으면(어제 받음 · 만료 전) 새 카드 0."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b, c = _trio(run)
    _must_see(run, a, c, 'A 에게 줄 후보 C 가 없다')
    _dated_card(run, a, b, timedelta(days=1), timedelta(days=2))
    _issue(run, region, list(EVERY_DAY), control=[c])
    _still_today(today)
    got = len(_cards(run, a))
    check.that(got == 1, f'A 의 무료 카드가 {got}장(기대 1 — 살아 있는 카드가 있으면 새 카드를 안 준다)')
    return check.result('카드를 어제 줬고 만료는 미래 — 오늘 받은 사람 건너뜀과 구분된다. ' + _zero_note())


def card_06(run):
    """만료된 무응답 카드는 오늘 탭에서 사라지고, 그 뒤 배치에서 새 카드를 받는다(시나리오의 앱 새로고침은 /cards/today 로 대신)."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b, c = _trio(run)
    _must_see(run, a, c, 'A 에게 줄 후보 C 가 없다')
    control = _control_man(run)
    old = _dated_card(run, a, b, timedelta(days=3), timedelta(hours=-1))
    first = _api(run, 'GET', '/cards/today', a['token'])
    check.reply('배치 전 오늘 탭', first, 200)
    check.that(not (first[1] or {}).get('cards'), '만료된 카드가 오늘 탭에 남음')
    _issue(run, region, list(EVERY_DAY), control=[control], subjects=[a], had={a['id']: 1})
    _still_today(today)
    if (stop := _missing(check, run, a, had=1)):
        return stop
    new = [row for row in _cards(run, a) if row['id'] != old]
    check.that(len(new) == 1, f'A 새 카드 {len(new)}장(기대 1 — 만료된 카드는 살아 있는 카드가 아니다)')
    check.that(all(row['target_id'] != b['id'] for row in new), '새 카드의 상대가 만료된 카드의 상대 B(14일은 쉰다)')
    last = _api(run, 'GET', '/cards/today', a['token'])
    check.reply('배치 후 오늘 탭', last, 200)
    shown = [card['card_id'] for card in (last[1] or {}).get('cards', [])]
    check.that(shown == [row['id'] for row in new], f'배치 후 오늘 탭 {shown}(기대 새 카드 하나)')
    return check.result('앱 새로고침 대신 /cards/today 를 배치 전 · 후로 읽음')


def card_07(run):
    """무료 카드의 만료 시각 = 오늘 다음 첫 지급 요일 07:00(서울). 오늘이 든 가장 성긴 칸으로 사다리를 맞춘다 —
    시나리오의 "[1,4] · 수요일" 은 오늘이 지급 요일이어야 카드가 나가므로(issuing.py:35-36) 그대로는 카드가 없다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b = _person(run, 'male'), _person(run, 'female')
    control = _control_man(run)
    step = step_for_today(today.isoweekday())
    at = clock.fromisoformat(_one(run, f'region_group_settings?region_group=eq.{region}&select=issue_time')['issue_time'])
    saved = _issue(run, region, step, control=[control], subjects=[a])
    _still_today(today)
    if (stop := _missing(check, run, a)):
        return stop
    check.that(saved == step, f'사다리가 {saved} 로 저장(기대 {step} — 사다리는 E-CARD-08)')
    got = _api(run, 'GET', '/cards/today', a['token'])
    check.reply('오늘 탭', got, 200)
    cards = (got[1] or {}).get('cards', [])
    check.that(len(cards) == 1, f'A 오늘 탭 카드 {len(cards)}장(기대 1)')
    want = expected_expiry(today, saved, at)
    if cards:
        shown = _at(cards[0]['expires_at'])
        check.that(shown == want, f'만료 {shown.isoformat()}(기대 {want.isoformat()} — 다음 지급 요일 {at:%H:%M} 서울)')
    note = f'오늘 {WEEKDAY_NAMES[today.weekday()]}요일 · 사다리 {step}'
    if (want.date() - today.date()).days == 1:  # 화 · 토 · 일 — 매일 칸이거나 내일이 월요일
        note += ' — 오늘 칸의 다음 지급이 내일이라 서버가 "내일 07:00" 으로 잘못 적어도 못 가려 변별력이 약하다(수 · 목 · 금에 보면 가려진다)'
    return check.result(note)


def card_08(run):
    """사다리 5칸을 임계값을 바꿔 가며 배치 5번 — 칸마다 저장된 요일을 읽는다. 저장값이 5가지라 배치를 줄일 수 없다.
    카드를 받는 사람이 되지 않게 계정은 벡터 없이 만든다(집계에는 들어간다)."""
    region, check = _prepare(run), Check()
    before = _counts(run, region)
    made = {'male': 2, 'female': 1}
    for gender, n in made.items():
        for _ in range(n):
            area2._home(run, gender)
    after = _counts(run, region)
    for _ in range(3):  # "적은 쪽" 을 가리려면 남자가 더 많아야 한다 — 이미 있는 계정이 여자 쪽으로 기울어 있으면 남자를 보탠다
        if after.get('male', 0) > after.get('female', 0):
            break
        area2._home(run, 'male')
        made['male'] += 1
        after = _counts(run, region)
    grew = {g: after.get(g, 0) - before.get(g, 0) for g in made}
    check.that(grew == made, f'활성 인원 집계가 만든 계정 수만큼 안 늘었다(늘어난 {grew}, 기대 {made})')
    count = _bottleneck(after)
    with region_set(run, region, issue_weekdays=list(EVERY_DAY), **LADDER_ZERO):  # 원복용 — 아래에서 단계마다 다시 바꾼다
        for i, (name, weekdays) in enumerate(STEPS[1:] + STEPS[:1]):
            _patch(run, f'region_group_settings?region_group=eq.{region}',
                   {'issue_weekdays': SENTINEL, **thresholds_for(weekdays, count)})
            got = _fire(run, region, FIRST_BATCH_WAIT if i == 0 else BATCH_WAIT)
            check.that(got == weekdays, f'{name}: 저장 {got}(기대 {weekdays}, 남녀 중 적은 쪽 {count}명)')
    return check.result(f'남 {after.get("male", 0)} · 여 {after.get("female", 0)} → 적은 쪽 {count}명, 배치 5회')


def card_09(run):
    """오늘이 그 지역 지급 요일이 아니면 지역 통째로 건너뛴다 — 배치가 사다리를 먼저 다시 계산하므로 오늘이 안 든 칸이 나오게 임계값을 맞춘다.
    응답 skipped_regions 는 못 읽는다 — 설정 행이 새로 적혔는데(배치가 돌았다) 카드가 0장인 것으로 본다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b = _person(run, 'male'), _person(run, 'female')
    _must_see(run, a, b, 'A 에게 줄 후보 B 가 없다')
    step = step_without_today(today.isoweekday())
    saved = _issue(run, region, step)
    _still_today(today)
    check.that(saved == step, f'사다리가 {saved} 로 저장(기대 {step})')
    for name, account in (('A', a), ('B', b)):
        got = len(_cards(run, account))
        check.that(got == 0, f'{name} 에게 카드가 {got}장 나갔다(기대 0 — 오늘은 지급 요일이 아니다)')
    return check.result(f'오늘 {WEEKDAY_NAMES[today.weekday()]}요일, 사다리 {step}. ' + _zero_note(control=False))


def _stale_at():
    """마지막 접속 14일 1분 전 — 14일 안(`last_active_at > now() - 14일`)이 아니다."""
    return (area2._now() - timedelta(days=14, minutes=1)).isoformat()


def card_11(run):
    """자격 6조건 하나씩 빠뜨린 6명은 카드 0, 대조군 1명은 1장. 6번째(학교 열림)는 둘째 시험학교(_cohort_school)가 맡는다 — 끝나면 지운다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    broken = []

    def man(label, fix):
        account = _person(run, 'male')
        fix(account)
        broken.append((label, account))

    def drop_vector(p):
        _guard(run, p['id'])
        _patch(run, f"profile_vectors?profile_id=eq.{p['id']}", {'want_embedding': None})

    with _cohort_school(run, region) as closed:
        man('active 아님(정지)', lambda p: area2._set_status(run, p, 'suspended'))
        man('일시중지', lambda p: _write(run, p, {'matching_paused': True}))
        man('14일 지남(마지막 접속 14일 1분 전)', lambda p: _write(run, p, {'last_active_at': _stale_at()}))
        man('벡터 없음(want_embedding null)', drop_vector)
        man('자동 가림', lambda p: _write(run, p, {'auto_hidden_at': area2._now().isoformat()}))
        man('학교 안 열림', lambda p: _write(run, p, {'university_id': closed}))
        control, woman = _person(run, 'male'), _person(run, 'female')
        _must_see(run, control, woman, '대조군에게 줄 후보가 없다')
        _issue(run, region, list(EVERY_DAY), control=[control])
        _still_today(today)
        for label, account in broken:
            got = len(_cards(run, account))
            check.that(got == 0, f'{label}: 카드가 {got}장 나갔다(기대 0)')
    return check.result('6조건 모두 카드 0 · 대조군 1장. ' + _zero_note())


def card_12(run):
    """14일 경계: 13일 23시간 전에 접속한 사람은 카드를 받는다(1시간 여유 — 접속 시각을 배치 직전에 쓴다)."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b = _person(run, 'male'), _person(run, 'female')
    control = _control_man(run)
    _must_see(run, a, b, 'A 에게 줄 후보 B 가 없다')
    _write(run, a, {'last_active_at': (area2._now() - timedelta(days=13, hours=23)).isoformat()})
    _issue(run, region, list(EVERY_DAY), control=[control], subjects=[a])
    _still_today(today)
    if (stop := _missing(check, run, a)):
        return stop
    got = len(_cards(run, a))
    check.that(got == 1, f'A 카드가 {got}장(기대 1 — 13일 23시간 전 접속은 14일 안이다)')
    return check.result()


def card_36(run):
    """자동 가림: B 는 후보 · A 의 오늘 탭 · A 의 수락함에서 사라지고, 새 카드도 못 받는다(화면은 API 로 대신).
    후보는 B 와 카드 관계가 없는 C 로 읽는다 — A 는 B 와 카드가 있어(살아 있는 카드는 후보에서 빠진다) 빠진 것이 가림 탓인지 알 수 없다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    a, b = _person(run, 'female'), _person(run, 'male')
    c, d = _person(run, 'female'), _person(run, 'male')  # C 는 후보를 보는 사람 · B 에게 줄 후보, D 는 대조군
    _must_see(run, c, b, '가리기 전에는 C 후보에 B 가 있어야 한다')
    sent = _dated_card(run, a, b, timedelta(days=1), timedelta(days=2))  # A 가 B 에게 준 카드 — 어제 준 것이라 오늘 받은 사람 건너뜀과 구분된다
    accepted = _dated_card(run, b, a, timedelta(days=1), timedelta(days=2))   # B 가 A 에게 보낸 수락 — A 의 수락함
    check.reply('B 의 수락', _api(run, 'POST', f'/cards/{accepted}/decision', b['token'], {'decision': 'accept'}, **_ONCE), 200)

    def seen():
        shown = (_api(run, 'GET', '/cards/today', a['token'])[1] or {}).get('cards', [])
        inbox = (_api(run, 'GET', '/cards/acceptances', a['token'])[1] or {}).get('acceptances', [])
        return [x['card_id'] for x in shown], [x['card_id'] for x in inbox]

    today_ids, inbox_ids = seen()
    if sent not in today_ids or accepted not in inbox_ids:
        raise Blocked(f'가리기 전에는 A 오늘 탭에 B 카드 · 수락함에 B 수락이 있어야 한다 — 준비가 틀림(오늘 탭 {len(today_ids)}장 · 수락함 {len(inbox_ids)}건)')
    _write(run, b, {'auto_hidden_at': area2._now().isoformat()})
    check.that(b['id'] not in _candidates(run, c), 'C 후보에 가려진 B 가 남음')
    today_ids, inbox_ids = seen()
    check.that(sent not in today_ids, 'A 오늘 탭에 가려진 B 의 카드가 남음')
    check.that(accepted not in inbox_ids, 'A 수락함에 가려진 B 의 수락이 남음')
    _issue(run, region, list(EVERY_DAY), control=[d])
    _still_today(today)
    new = len(_cards(run, b)) - 1
    check.that(new == 0, f'가려진 B 가 새 카드를 받음({new}장)')
    return check.result('A 화면은 /cards/today · /cards/acceptances 로 대신 읽음. ' + _zero_note())


def card_72(run):
    """배치는 점수 1등에게 카드를 준다. 문장 임베딩 축을 이번 실행에서 무작위로 골라(다른 묶음의 C0 는 0 번 축) 같은 점수 후보가 풀에 못 섞이게 한다."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    axis = random.randrange(1, area2.EMBEDDING_DIMENSIONS)
    owner = _person(run, 'male', embedding=axis, is_smoker=False, religion='none', mbti='ENFP', preferred_mbti_flags={'E': True},
                    preferred_height_min=170, preferred_height_max=180, preferred_age_min=22, preferred_age_max=24, **area2.TAGS)
    women = {name: _person(run, 'female', area2.CANDIDATES[name].get('survey', 1), axis,
                           **{'is_smoker': False, 'religion': 'none', **area2.TAGS, **area2.CANDIDATES[name].get('profile', {})})
             for name in ('C0', 'C4', 'C5')}  # 만점 · 흡연 감점 · 종교 감점
    control = _control_man(run)  # O 와 같은 남자 — O 의 후보 풀(여자 셋)을 바꾸지 않는다
    scores = _candidates(run, owner)
    top = women['C0']['id']
    if scores.get(top) is None or any(s >= scores[top] for pid, s in scores.items() if pid != top):
        raise Blocked(f'C0 가 풀에서 단독 1등이 아니다(같은 점수 후보가 있다 — 점수 {scores}) — 다른 묶음의 흔적이 있으면 뒷정리 뒤 다시')
    _issue(run, region, list(EVERY_DAY), control=[control], subjects=[owner])
    _still_today(today)
    if (stop := _missing(check, run, owner)):
        return stop
    rows = _cards(run, owner)
    check.that(len(rows) == 1 and rows[0]['target_id'] == top, f'O 카드 {[r["target_id"] for r in rows]}(기대 1등 C0 한 장 {top})')
    return check.result(f'후보 점수 {sorted(scores.values(), reverse=True)}')


def home_28(run):
    """열리기 전 학교 사람은 후보 · 사다리 집계 · 카드 받을 사람 모두에서 빠진다. 구매 카드는 시험하지 않는다(구매 경로 없음)."""
    region, today, check = _prepare(run), batch_gate.now_seoul(), Check()
    with _cohort_school(run, region) as closed:
        v, f, g = _person(run, 'male'), _person(run, 'female'), _person(run, 'male')  # V(닫힐 사람) · F(열린 학교 여) · G(대조군)
        _must_see(run, f, v, 'F 후보에 V 가 있어야 한다')
        _must_see(run, v, f, 'V 후보에 F 가 있어야 한다')
        before = _counts(run, region)
        _write(run, v, {'university_id': closed})
        after = _counts(run, region)
        check.that(after.get('male', 0) == before.get('male', 0) - 1,
                   f'사다리 집계(region_active_counts) 남 {before.get("male", 0)} → {after.get("male", 0)}(기대 1 감소 — 닫힌 학교 사람은 안 센다)')
        check.that(v['id'] not in _candidates(run, f), '열린 F 의 후보에 닫힌 학교 V 가 남음')
        own = _candidates(run, v)
        check.that(not own, f'닫힌 학교 V 의 후보가 {len(own)}명(기대 0)')
        _issue(run, region, list(EVERY_DAY), control=[g])
        _still_today(today)
        got = len(_cards(run, v))
        check.that(got == 0, f'닫힌 학교 V 가 카드를 {got}장 받음(기대 0)')
    return check.result('구매 카드 후보는 시험 안 함. ' + _zero_note())


# ── cleanup ────────────────────────────────────────────────────────────────────────────────────────

def _seed_reviewing(run, account, task, days):
    """검수 중(submitted) 인증샷 — 제출한 지 [days] 일 지났다. 트리거가 created_at 을 못 옮기게 해서 처음부터 과거로 넣는다."""
    _guard(run, account['id'])
    sid = area2._new_id()
    path = f"{account['id']}/{sid}.jpg"
    key = run.key
    uploaded = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/storage/v1/object/heart-task-proofs/{path}",
                          {'apikey': key, 'Authorization': f'Bearer {key}'}, raw=(TINY_JPEG, 'image/jpeg'))
    if uploaded[0] >= 300:
        raise Blocked(f'인증샷 파일 올리기 {uploaded[0]}')
    _insert(run, 'heart_task_submissions', [{'id': sid, 'profile_id': account['id'], 'task': task, 'storage_path': path, 'status': 'submitted',
                                            'reward_hearts': 50, 'created_at': (area2._now() - timedelta(days=days)).isoformat()}],
            account['id'])
    return sid, path


def _cleanup_scene(run):
    """정리 배치 한 번으로 E-HEART-22 · 23 이 같이 본다 — 61일 승인(앵커) · 59일 승인 · 61일 된 검수 중. 앞 가설이 만든 장면을 뒤 가설이 다시 쓴다."""
    scene = getattr(run, '_area2_cleanup', None)
    if scene is None:
        batch_gate.check('cleanup')
        account = area2._home(run)
        scene = {'account': account, 'old': area2._seed_proof(run, account, 'everytime_post', 61),
                 'fresh': area2._seed_proof(run, account, 'kakao_share', 59), 'review': _seed_reviewing(run, account, 'everytime_post', 61)}
        _batch('cleanup')
        scene['cleared'] = area2_phone3._wait_for(lambda: area2._proof_state(run, account, *scene['old'])[0] is None, FIRST_BATCH_WAIT)
        run._area2_cleanup = scene
    return scene


def heart_22(run):
    scene = _cleanup_scene(run)
    state = area2._proof_state(run, scene['account'], *scene['old'])
    check = Check()
    check.that(state == (None, False), f'검수 끝난 지 61일 된 줄 {state}(기대 경로 null · 파일 없음 — 61일 된 인증샷이 안 지워짐)')
    return check.result('deleted_heart_proofs 개수는 스케줄러 호출이라 못 읽음 — 줄 · 파일 상태로 확인')


def heart_23(run):
    scene = _cleanup_scene(run)
    if not scene['cleared']:
        raise Blocked('앵커(61일 된 줄)가 안 지워졌다 — 배치가 안 돌았다면 "남음" 은 아무것도 증명하지 못한다(E-HEART-22 를 본다)')
    check = Check()
    for label, key in (('검수 끝난 지 59일 된 줄', 'fresh'), ('60일 넘은 검수 중인 줄', 'review')):
        sid, path = scene[key]
        state = area2._proof_state(run, scene['account'], sid, path)
        check.that(state == (path, True), f'{label}이 지워짐 {state}(기대 경로 · 파일 그대로)')
    return check.result()


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

CASES = {
    'E-CARD-04': card_04, 'E-CARD-05': card_05, 'E-CARD-06': card_06, 'E-CARD-07': card_07, 'E-CARD-08': card_08,
    'E-CARD-09': card_09, 'E-CARD-11': card_11, 'E-CARD-12': card_12, 'E-CARD-36': card_36, 'E-CARD-72': card_72,
    'E-HOME-28': home_28, 'E-HEART-22': heart_22, 'E-HEART-23': heart_23,
}
BUNDLES = {'area2-time-batch': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked, 시험 쪽 예외도 blocked(앱 결함으로 세지 않는다).
    배치를 이미 부른 가설은 다시 부르면 배치가 또 나가므로(__main__.run_case 는 fail 이면 한 번 더 부른다) 첫 결과를 그대로 돌려준다 —
    fail 이면 이유 뒤에 [ALREADY] 를 붙인다. 배치 전의 끊김은 처음부터 한 번 더(계정은 매번 새로 만들고 쓰기는 이번 실행의 계정에만 한다),
    배치 뒤의 끊김은 다시 하지 않고 blocked."""
    key = (str(run.out), case)
    if key in _PAID:
        result, note = _PAID[key]
        return (result, f'{note} — {ALREADY}') if result == 'fail' else (result, note)
    for tries in (1, 2):
        _FIRED.clear()
        try:
            got = CASES[case](run)
        except Blocked as e:
            got = ('blocked', str(e))
        except tools.TRANSIENT as e:
            if _FIRED:
                got = ('blocked', f'연결이 끊김({type(e).__name__}) — {ALREADY}')
            elif tries == 2:
                got = ('blocked', f'연결이 두 번 끊김: {type(e).__name__} {e}')
            else:
                continue
        except Exception as e:  # 시험 쪽 버그 · 예상 밖 응답 모양 — 긴 실행이 한 가설 때문에 멈추지 않게
            got = ('blocked', f'진행 프로그램 예외 {type(e).__name__}: {e}')
        if _FIRED:
            _PAID[key] = got
        return got
