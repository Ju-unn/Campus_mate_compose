"""영역 2 API 가설 — 진행만, 폰 없음(묶음 area2-api). 기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이다.

가설 하나 = 함수 하나 `(run) -> (결과, 메모)`. 계정은 `run.account('home')`(나탭2 #243 의 홈 계정)으로 그때그때
새로 만든다. 쓰기는 이번 실행이 만든 계정 id 에만 한다([_guard]) — 시험대학 행(E-HOME-27)만 예외이고 거기는 원복한다.
배치는 [_batch] 자리만 부르고 실제 호출은 대장이 한다(Run.batch).
"""

import json
import math
import random
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from e2e import batch_gate, tools
from e2e.area1 import SEOUL, SV_REQUIRED, TINY_JPEG, Check, _api, _detail, _form, _patch, _rows, _test_university
from e2e.tools import Blocked

PHOTO_UNREADABLE = '사진을 다시 확인해 주세요'
CODE_NOT_ALLOWED = '이 코드는 쓸 수 없어요'
CODE_NOT_FOUND = '없는 코드예요, 다시 확인해 주세요'
CODE_ALREADY = '추천 코드는 한 번만 입력할 수 있어요'
EMBEDDING_DIMENSIONS = 512  # profile_vectors.self_embedding · want_embedding
SCORE_TOLERANCE = 0.0001  # 점수는 서버가 소수 4자리로 돌려준다
# 두 번 적용되면 결과가 달라지는 요청(결정 · 투표 · 글 · 제출 · 코드 입력 · 하트 증감 · 동시성 가설의 같은 요청 2건)은 끊겨도 다시 보내지 않는다 —
# 끊김은 attempt 가 새 계정으로 가설을 처음부터 한 번 더 한다. tools.call 의 retry=False.
_ONCE = {'retry': False}


def _now():
    return datetime.now(timezone.utc)


# ── 계정 · 쓰기 가드 ────────────────────────────────────────────────────────────────────────────────

def _mine(run):
    path = run.out / 'accounts.json'
    return {a['id'] for a in json.loads(path.read_text(encoding='utf-8'))} if path.exists() else set()


def _guard(run, *ids):
    """이번 실행이 만든 계정 id 만 쓴다 — 시각 · 상태 · 차단 · 벡터 쓰기마다 부른다. 아니면 쓰지 않고 멈춘다."""
    strangers = [i for i in ids if i not in _mine(run)]
    if strangers:
        raise Blocked(f'이번 실행이 만든 계정이 아니라 쓰지 않는다: {strangers}')


def _phone():
    return f'010-{random.randint(0, 9999):04d}-{random.randint(0, 9999):04d}'


def _home(run, gender='male', phone=None, **profile):
    """홈 계정(`Run.account('home')` — 온보딩 끝 · 활성) + 프로필 값 한 번에. 전화번호는 계정 공장의 04-1 저장에 그대로 넣는다."""
    account = run.account('home', **({'phone_number': phone} if phone else {}))
    account['phone'] = phone
    _guard(run, account['id'])
    _patch(run, f"profiles?id=eq.{account['id']}", {'gender': gender, **profile})
    return account


def _vector(values):
    return '[' + ','.join(str(v) for v in values) + ']'


def _unit(axis):
    return _vector([1 if i == axis else 0 for i in range(EMBEDDING_DIMENSIONS)])


def _vectors(run, account, survey=1, embedding=0):
    """설문 8축은 모두 [survey](±1 — 정반대 거리 최대 5.657), 문장 임베딩은 [embedding] 축 단위벡터(서로 다른 축 = 코사인 0)."""
    _guard(run, account['id'])
    body = {'profile_id': account['id'], 'self_survey': _vector([survey] * 8),
            'self_embedding': _unit(embedding), 'want_embedding': _unit(embedding)}
    status, got = tools.rest(run.cfg, run.key, 'POST', 'profile_vectors', body)
    if status == 409:  # 계정을 만들 때 서버가 이미 한 행을 넣었다
        status, got = tools.rest(run.cfg, run.key, 'PATCH', f"profile_vectors?profile_id=eq.{account['id']}",
                                 {k: v for k, v in body.items() if k != 'profile_id'})
    if status >= 300:
        raise Blocked(f'벡터 쓰기 {status} {got}')


def _person(run, gender='male', survey=1, embedding=0, phone=None, **profile):
    account = _home(run, gender, phone, **profile)
    _vectors(run, account, survey, embedding)
    return account


def _candidates(run, account):
    """GET /matching/candidates — {후보 id: 점수}. 못 읽으면 준비 실패(blocked)."""
    status, body = _api(run, 'GET', '/matching/candidates?limit=100', account['token'])[:2]
    if status != 200:
        raise Blocked(f'후보 조회 {status} {_detail(body)}')
    return {c['profile_id']: c['score'] for c in body['candidates']}


def _insert(run, table, rows, *owners):
    _guard(run, *owners)
    status, got = tools.rest(run.cfg, run.key, 'POST', table, rows)
    if status >= 300:
        raise Blocked(f'{table} 넣기 {status} {got}')


def _card(run, owner, target, days=3):
    """살아 있는(결정 전 · 만료 전) 무료 카드 한 장 — id 는 이쪽에서 정한다(넣고 다시 읽지 않으려고)."""
    card_id = _new_id()  # 두 번 가면 23505(Blocked) — 판정은 안 바뀌고 끊김은 그대로 다시 보내는 쪽이 더 많이 살려서 기본(재시도)
    _insert(run, 'daily_cards', [{'id': card_id, 'owner_id': owner['id'], 'target_id': target['id'], 'source': 'daily',
                                 'expires_at': (_now() + timedelta(days=days)).isoformat()}], owner['id'], target['id'])
    return card_id


def _ledger(run, account, reason):
    return [r['amount'] for r in _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.{reason}&select=amount")]


def _grant(run, account, amount, reason='free_task'):
    _guard(run, account['id'])
    return tools.rest(run.cfg, run.key, 'POST', 'rpc/grant_hearts',
                      {'p_profile_id': account['id'], 'p_amount': amount, 'p_reason': reason, 'p_ref_id': None}, **_ONCE)


def _parallel(*calls):
    """같은 순간에 출발한다(Barrier) — 동시성 가설용. 결과는 부른 순서대로."""
    gate = threading.Barrier(len(calls))

    def go(call):
        gate.wait()
        return call()

    with ThreadPoolExecutor(len(calls)) as pool:
        return [f.result() for f in [pool.submit(go, c) for c in calls]]


def _new_id():
    return str(uuid.uuid4())


def _batch(name):
    """Cloud Scheduler job 을 지금 한 번 돌린다(tools.batch = gcloud). 응답 본문은 못 읽고 끝도 기다려 주지 않는다 —
    그래서 가설은 DB · 저장소를 다시 읽어 결과를 본다. 실제 호출이라 대장이 시각을 정해 돌린다 —
    실행 금지 시간(batch_gate)이면 gcloud 를 부르지 않고 blocked."""
    batch_gate.check(name)
    try:
        tools.batch(name)
    except (subprocess.CalledProcessError, OSError) as e:
        raise Blocked(f'배치 {name} 호출 실패: {type(e).__name__} {getattr(e, "stderr", "") or e}') from e


def _set_status(run, account, status):
    """profiles.status 바꾸기. 탈퇴는 짝 칸(withdrawn_at)을 같이 채워야 한다 — profiles_withdrawn_pair
    check((status = 'withdrawn') = (withdrawn_at is not null)), 20260927010100:12-14."""
    _guard(run, account['id'])
    fields = {'status': status}
    if status == 'withdrawn':
        fields['withdrawn_at'] = _now().isoformat()
    _patch(run, f"profiles?id=eq.{account['id']}", fields)


def _leaks(node, path='$'):
    """응답 안의 실명 · 번호 · 카카오 키와 실사진 경로 — 어디에 있는지 돌려준다."""
    found = []
    if isinstance(node, dict):
        for key, value in node.items():
            if any(word in key.lower() for word in ('real_name', 'phone', 'kakao')):
                found.append(f'{path}.{key}')
            found += _leaks(value, f'{path}.{key}')
    elif isinstance(node, list):
        for i, value in enumerate(node):
            found += _leaks(value, f'{path}[{i}]')
    elif isinstance(node, str) and 'profile-photos' in node:
        found.append(f'{path}={node[:60]}')
    return found


# ── 홈 ──────────────────────────────────────────────────────────────────────────────────────────────

def home_27(run):
    """여는 시각은 월요일 07:00(서울)만. 시험대학 행에 네 값을 넣어 보고 하나라도 받아들여지면 바로 원복한다."""
    check = Check()
    school = _test_university(run)
    if not school:
        raise Blocked('시험대학 행을 못 찾음')
    original = _rows(run, f'universities?id=eq.{school}&select=card_opens_at')[0]['card_opens_at']
    values = ['2026-10-06T07:00:00+09:00',  # 화요일
              '2026-10-05T16:00:00+09:00',  # 월요일 16시
              '2026-10-05 07:00',           # 시간대 없음 → UTC 로 읽혀 서울 16시
              'infinity']
    changed = False
    for value in values:
        status, body = tools.rest(run.cfg, run.key, 'PATCH', f'universities?id=eq.{school}', {'card_opens_at': value})
        if status < 300:
            changed = True
            check.problems.append(f'{value} 가 받아들여졌다({status})')
        elif '23514' not in str(body):
            check.problems.append(f'{value}: {status} {_detail(body)}(23514 아님)')
    if changed:  # 운영 시험대학 행을 처음 값으로 되돌린다
        tools.rest(run.cfg, run.key, 'PATCH', f'universities?id=eq.{school}', {'card_opens_at': original})
    after = _rows(run, f'universities?id=eq.{school}&select=card_opens_at')[0]['card_opens_at']
    check.that(after == original, f'card_opens_at 이 {original!r} → {after!r} 로 바뀜')
    return check.result()


# ── 카드: 후보(하드 필터) ───────────────────────────────────────────────────────────────────────────

def card_30(run):
    check = Check()
    me, same, other = _person(run, 'male'), _person(run, 'male'), _person(run, 'female')
    got = _candidates(run, me)
    check.that(same['id'] not in got, '같은 성별이 후보로 나옴')
    check.that(other['id'] in got, '반대 성별이 후보에 없음')
    return check.result()


def card_31(run):
    check = Check()
    me, other = _person(run, 'male'), _person(run, 'female')
    check.that(other['id'] in _candidates(run, me), '옮기기 전에는 후보여야 한다(준비가 틀림)')
    seoul = _rows(run, 'universities?region_group=eq.seoul&select=id&limit=1')
    if not seoul:
        raise Blocked('region_group=seoul 학교가 없다')
    _guard(run, other['id'])
    _patch(run, f"profiles?id=eq.{other['id']}", {'university_id': seoul[0]['id']})
    try:
        check.that(other['id'] not in _candidates(run, me), '다른 지역그룹 사람이 아직 후보다(시험대학 region_group 이 e2e 인지 확인)')
    finally:  # 서울 학교에 둔 채 끝나면 실제 서울 사용자의 카드 후보가 된다
        _patch(run, f"profiles?id=eq.{other['id']}", {'university_id': _test_university(run)})
    return check.result()


def card_34(run):
    check = Check()
    me, mine, theirs = _person(run, 'male'), _person(run, 'female'), _person(run, 'female')
    got = _candidates(run, me)
    check.that(mine['id'] in got and theirs['id'] in got, '차단 전에는 둘 다 후보여야 한다(준비가 틀림)')
    _insert(run, 'blocks', [{'blocker_id': me['id'], 'blocked_id': mine['id']},
                            {'blocker_id': theirs['id'], 'blocked_id': me['id']}], me['id'], mine['id'], theirs['id'])
    got = _candidates(run, me)
    check.that(mine['id'] not in got, '내가 차단한 사람이 후보다')
    check.that(theirs['id'] not in got, '나를 차단한 사람이 후보다')
    return check.result()


def _contact_block(run, owner, *numbers):
    reply = _api(run, 'POST', '/contact-blocks', owner['token'], {'numbers': list(numbers)})
    if reply[0] != 200:
        raise Blocked(f'지인 차단 {reply[0]} {_detail(reply[1])}')


def card_37(run):
    """지인 차단: 서로 후보에서 빠지고(W), 미리 받은 카드 · 수락도 사라진다(V)."""
    check = Check()
    me = _person(run, 'male')
    sent, wide = _person(run, 'female', phone=_phone()), _person(run, 'female', phone=_phone())
    check.that(wide['id'] in _candidates(run, me) and me['id'] in _candidates(run, wide), '차단 전에는 서로 후보여야 한다(준비가 틀림)')
    out_card, in_card = _card(run, me, sent), _card(run, sent, me)
    check.reply('V 의 수락', _api(run, 'POST', f'/cards/{in_card}/decision', sent['token'], {'decision': 'accept'}, **_ONCE), 200)
    today = _api(run, 'GET', '/cards/today', me['token'])
    inbox = _api(run, 'GET', '/cards/acceptances', me['token'])
    check.that(len((today[1] or {}).get('cards', [])) == 1, f'차단 전 오늘 카드 {today[0]}')
    check.that(len((inbox[1] or {}).get('acceptances', [])) == 1, f'차단 전 수락함 {inbox[0]}')
    _contact_block(run, me, sent['phone'], wide['phone'])
    check.that(wide['id'] not in _candidates(run, me), 'A 후보에 지인 차단한 사람이 있다')
    check.that(me['id'] not in _candidates(run, wide), '지인 차단한 사람의 후보에 A 가 있다')
    check.that(not (_api(run, 'GET', '/cards/today', me['token'])[1] or {}).get('cards'), '미리 둔 카드가 오늘 탭에 남음')
    check.that(not (_api(run, 'GET', '/cards/acceptances', me['token'])[1] or {}).get('acceptances'), '미리 받은 수락이 수락함에 남음')
    check.reply('숨은 카드 결정', _api(run, 'POST', f'/cards/{out_card}/decision', me['token'], {'decision': 'reject'}, **_ONCE), 404)
    check.reply('숨은 수락 응답', _api(run, 'POST', f'/cards/acceptances/{in_card}', me['token'], {'decision': 'reject'}, **_ONCE), 404)
    return check.result()


def card_38(run):
    """번호 해시가 없는 계정은 번호를 막아도 걸리지 않는다."""
    check = Check()
    me, other = _person(run, 'male'), _person(run, 'female', phone=_phone())
    _guard(run, other['id'])
    _patch(run, f"profile_private?profile_id=eq.{other['id']}", {'phone_hmac': None})
    _contact_block(run, me, other['phone'])
    check.that(other['id'] in _candidates(run, me), '해시 없는 계정이 후보에서 빠짐')
    return check.result()


def card_39(run):
    check = Check()
    me, suspended, withdrawn = _person(run, 'male'), _person(run, 'female'), _person(run, 'female')
    got = _candidates(run, me)
    check.that(suspended['id'] in got and withdrawn['id'] in got, '바꾸기 전에는 둘 다 후보여야 한다(준비가 틀림)')
    _set_status(run, suspended, 'suspended')
    _set_status(run, withdrawn, 'withdrawn')
    got = _candidates(run, me)
    check.that(suspended['id'] not in got, '정지 계정이 후보다')
    check.that(withdrawn['id'] not in got, '탈퇴 계정이 후보다')
    return check.result()


def card_55(run):
    check = Check()
    me, other = _person(run, 'male'), _person(run, 'female')
    check.that(other['id'] in _candidates(run, me), '카드 전에는 후보여야 한다(준비가 틀림)')
    _card(run, me, other)
    check.that(other['id'] not in _candidates(run, me), '살아 있는 카드의 상대가 또 후보로 나옴')
    return check.result()


# ── 카드: 점수 ──────────────────────────────────────────────────────────────────────────────────────
# 후보 열 명이 오너 O 한 명에게 같이 보이므로 한 번만 만들고(캐시) 가설마다 자기 후보 점수만 본다.
# 모든 계정은 키 170 · 나이 22(홈 계정 기본)이라 O 의 선호(키 170~180 · 나이 22~24)와 겹쳐도 감점이 없다.

# 태그 점수 = (관심사 자카드 + (O.나는↔C.원해 + C.나는↔O.원해) / 2) / 2 (match_candidates SQL). 1.0 이 되려면 교차 두 항도 겹쳐야 하므로
# 나는(my_traits) = 원해(ideal_traits) 로 둔다. OTHER_TAGS 는 세 칸 모두 안 겹쳐 0.
TAGS = {'interest_tags': ['등산'], 'my_traits': ['다정한'], 'ideal_traits': ['다정한']}
OTHER_TAGS = {'interest_tags': ['독서'], 'my_traits': ['활발한'], 'ideal_traits': ['활발한']}
TARGET_YEAR = lambda: datetime.now(SEOUL).year  # noqa: E731  서버 나이 = 올해 − 태어난 해(core/time.py)
CANDIDATES = {
    'C0': {},                                          # 만점 상대
    'C1': {'survey': -1},                              # 설문이 정반대 → 성향 몫 0
    'C2': {'profile': OTHER_TAGS},                     # 태그가 하나도 안 겹침
    'C3': {'embedding': 1},                            # 문장 임베딩이 직교
    'C4': {'profile': {'is_smoker': True}},            # 내가 비흡연 · 상대 흡연
    'C5': {'profile': {'religion': 'catholic'}},       # 종교 다름
    'C6': {'profile': {'is_smoker': True, 'religion': 'catholic'}},
    'C7': {'profile': {'mbti': 'INTJ'}},               # O 는 E 만 켬
    'C8': {'profile': {'height_cm': 184}},             # O 의 선호 170~180 에서 4cm 밖
    'C9': {'profile': lambda: {'birth_year': TARGET_YEAR() - 27}},  # O 의 선호 22~24 에서 3살 밖
}


def _world(run):
    world = getattr(run, '_area2_world', None)
    if world is None:
        owner = _person(run, 'male', is_smoker=False, religion='none', mbti='ENFP', preferred_mbti_flags={'E': True},
                        preferred_height_min=170, preferred_height_max=180, preferred_age_min=22, preferred_age_max=24, **TAGS)
        world = {'O': owner}
        for name, spec in CANDIDATES.items():
            extra = spec.get('profile', {})
            extra = extra() if callable(extra) else extra
            world[name] = _person(run, 'female', spec.get('survey', 1), spec.get('embedding', 0),
                                  **{'is_smoker': False, 'religion': 'none', **TAGS, **extra})
        run._area2_world = world
    return world


def _score(run, name, expected):
    check = Check()
    world = _world(run)
    got = _candidates(run, world['O']).get(world[name]['id'])
    check.that(got is not None, f'{name} 가 후보에 없음')
    check.that(got is None or abs(got - expected) <= SCORE_TOLERANCE, f'{name} 점수 {got}(기대 {round(expected, 4)})')
    return check.result(f'{name} = {got}')


def card_60(run):
    return _score(run, 'C0', 1.0)


def card_61(run):
    return _score(run, 'C1', 0.7)


def card_62(run):
    return _score(run, 'C2', 0.8)


def card_63(run):
    return _score(run, 'C3', 0.5)


def card_64(run):
    return _score(run, 'C4', 0.5)


def card_65(run):
    """흡연은 한 방향 — 내가 흡연자인 오너에게는 비흡연 상대가 감점 없이 1.0."""
    check = Check()
    world = _world(run)  # 후보 C0 가 이미 있다
    smoker = _person(run, 'male', is_smoker=True, religion='none', **TAGS)
    got = _candidates(run, smoker).get(world['C0']['id'])
    check.that(got is not None and abs(got - 1.0) <= SCORE_TOLERANCE, f'C0 점수 {got}(기대 1.0)')
    return check.result(f'C0 = {got}')


def card_66(run):
    return _score(run, 'C5', 0.8)


def card_67(run):
    return _score(run, 'C6', 0.4)


def card_69(run):
    return _score(run, 'C7', 0.6 + 0.4 * math.sqrt(0.75))


def card_70(run):
    return _score(run, 'C8', math.sqrt(0.85))


def card_71(run):
    return _score(run, 'C9', math.sqrt(0.70))


# ── 카드: 결정 · 수락 · 응답 모양 ───────────────────────────────────────────────────────────────────

def card_82(run):
    check = Check()
    owner, target = _person(run, 'male'), _person(run, 'female')
    card = _card(run, owner, target)
    check.reply('수락', _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': 'accept'}, **_ONCE), 200)
    check.reply('첫 응답', _api(run, 'POST', f'/cards/acceptances/{card}', target['token'], {'decision': 'reject'}, **_ONCE), 200)
    check.reply('두 번째 응답', _api(run, 'POST', f'/cards/acceptances/{card}', target['token'], {'decision': 'reject'}, **_ONCE), 409,
                '이미 답한 수락이에요')
    rows = _rows(run, f'acceptance_responses?card_id=eq.{card}&select=card_id')
    check.that(len(rows) == 1, f'acceptance_responses {len(rows)}행')
    return check.result()


def card_83(run):
    check = Check()
    owner, target = _person(run, 'male'), _person(run, 'female')
    card = _card(run, owner, target)
    check.reply('첫 결정', _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': 'reject'}, **_ONCE), 200)
    check.reply('반대 결정', _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': 'accept'}, **_ONCE), 409,
                '이미 결정한 카드예요')
    rows = _rows(run, f'card_decisions?card_id=eq.{card}&select=decision')
    check.that(rows == [{'decision': 'reject'}], f'card_decisions {rows}')
    return check.result()


def card_88(run):
    check = Check()
    owner, target = _person(run, 'male'), _person(run, 'female')
    card = _card(run, owner, target)
    check.reply('수락', _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': 'accept'}, **_ONCE), 200)
    # 오늘 카드 · 카드 상세는 받는 사람(target)이 주인인 카드로 본다 — 수락함은 위 수락이 만든다.
    other_card = _card(run, target, owner)
    for label, reply in (('오늘 카드', _api(run, 'GET', '/cards/today', target['token'])),
                         ('카드 상세', _api(run, 'GET', f'/cards/{other_card}', target['token'])),
                         ('수락함', _api(run, 'GET', '/cards/acceptances', target['token']))):
        check.that(reply[0] == 200, f'{label} {reply[0]} {_detail(reply[1])}')
        for leak in _leaks(reply[1]):
            check.problems.append(f'{label}: {leak}')
    return check.result()


def card_89(run):
    check = Check()
    owner, stranger = _person(run, 'male'), _person(run, 'female')
    card = _card(run, owner, stranger)
    check.reply('남의 카드 상세', _api(run, 'GET', f'/cards/{card}', stranger['token']), 404, '카드를 찾을 수 없어요')
    check.reply('남의 카드 결정', _api(run, 'POST', f'/cards/{card}/decision', stranger['token'], {'decision': 'reject'}, **_ONCE), 404,
                '카드를 찾을 수 없어요')
    check.that(not _rows(run, f'card_decisions?card_id=eq.{card}&select=card_id'), '남이 낸 결정이 저장됨')
    return check.result()


# ── 투표 ────────────────────────────────────────────────────────────────────────────────────────────

POLL_KEYS = {'id', 'question', 'option_a_label', 'option_b_label', 'created_at', 'a_count', 'b_count', 'my_choice', 'is_mine'}


def _poll(run, account, text):
    reply = _api(run, 'POST', '/community/polls', account['token'], {'question': f'[E2E] {text}'}, **_ONCE)
    if reply[0] != 201:
        raise Blocked(f'글 올리기 {reply[0]} {_detail(reply[1])}')
    return reply[1]['id']


def _drop_polls(run, account):
    """시험 글은 피드에 실사용자에게도 보인다(시나리오 ⚠6) — 가설이 끝나면 작성자가 지운다."""
    for row in _rows(run, f"polls?author_id=eq.{account['id']}&select=id"):
        _api(run, 'DELETE', f"/community/polls/{row['id']}", account['token'])


def poll_03(run):
    check = Check()
    author, reader = _home(run), _home(run)
    try:
        return _poll_03(run, check, author, reader)
    finally:
        _drop_polls(run, author)


def _poll_03(run, check, author, reader):
    _poll(run, author, '익명 확인')
    reply = _api(run, 'GET', '/community/polls', reader['token'])
    check.reply('피드', reply, 200)
    polls = (reply[1] or {}).get('polls', []) if reply[0] == 200 else []
    check.that(bool(polls), '글이 하나도 안 보임')
    for poll in polls:
        check.that(set(poll) == POLL_KEYS, f'키 {sorted(set(poll) ^ POLL_KEYS)} 가 다르다')
    return check.result()


def poll_10(run):
    author, voter = _home(run), _home(run)
    try:
        return _poll_10(run, author, voter)
    finally:
        _drop_polls(run, author)


def _poll_10(run, author, voter):
    check = Check()
    first, second = _poll(run, author, '동시 1'), _poll(run, author, '동시 2')
    replies = _parallel(*[lambda p=p: _api(run, 'POST', f'/community/polls/{p}/votes', voter['token'], {'choice': 'a'}, **_ONCE)
                          for p in (first, second)])
    for i, reply in enumerate(replies, 1):
        check.reply(f'투표 {i}', reply, 200)
    rewarded = [r[1].get('rewarded') for r in replies if r[0] == 200 and isinstance(r[1], dict)]
    check.that(rewarded.count(True) == 1, f'rewarded {rewarded} — true 가 정확히 1건이어야 한다')
    check.that(_ledger(run, voter, 'poll_vote') == [10], f'원장 {_ledger(run, voter, "poll_vote")}')
    return check.result()


def poll_17(run):
    author = _home(run)
    try:
        return _poll_17(run, author)
    finally:
        _drop_polls(run, author)


def _poll_17(run, author):
    check = Check()
    for i in range(9):
        _poll(run, author, f'하루 한도 {i + 1}')
    replies = _parallel(*[lambda i=i: _api(run, 'POST', '/community/polls', author['token'], {'question': f'[E2E] 동시 {i}'}, **_ONCE)
                          for i in (1, 2)])
    check.that(sorted(r[0] for r in replies) == [201, 429], f'상태 {[r[0] for r in replies]}(기대 201 · 429)')
    rows = _rows(run, f"polls?author_id=eq.{author['id']}&select=id")
    check.that(len(rows) == 10, f'오늘 글 {len(rows)}행(기대 10)')
    return check.result()


def poll_24(run):
    author, leaver, other = _home(run), _home(run), _home(run)
    try:
        return _poll_24(run, author, leaver, other)
    finally:
        _drop_polls(run, author)


def _poll_24(run, author, leaver, other):
    check = Check()
    poll = _poll(run, author, '표 빠짐')
    for voter in (leaver, other):
        check.reply('투표', _api(run, 'POST', f'/community/polls/{poll}/votes', voter['token'], {'choice': 'a'}, **_ONCE), 200)

    def total():
        got = _api(run, 'GET', f'/community/polls/{poll}', author['token'])
        return got[1]['poll']['a_count'] + got[1]['poll']['b_count'] if got[0] == 200 else None

    before = total()
    _guard(run, leaver['id'])
    _patch(run, f"profiles?id=eq.{leaver['id']}", {'status': 'suspended'})
    after = total()
    check.that(before == 2 and after == 1, f'참여 수 {before} → {after}(기대 2 → 1)')
    return check.result()


# ── 무료 하트 모으기 ────────────────────────────────────────────────────────────────────────────────

def _submit(run, account, task='everytime_post', data=TINY_JPEG):
    return _form(run, f'/heart-tasks/{task}/submissions', account['token'], {}, ('photo', 'proof.jpg', data), **_ONCE)


def _proofs(run, account):
    return len(list(tools.storage_paths(run.cfg, run.key, 'heart-task-proofs', account['id'])))


def _submission_rows(run, account, task=None):
    extra = f'&task=eq.{task}' if task else ''
    return _rows(run, f"heart_task_submissions?profile_id=eq.{account['id']}{extra}&select=id,status,task")


def _review(run, account, submission, **fields):
    """운영자 검수 흉내 — 상태 · 사유 · 검수 시각을 한 번에 저장한다(check 제약 때문에 따로는 못 한다)."""
    _guard(run, account['id'])
    return tools.rest(run.cfg, run.key, 'PATCH', f'heart_task_submissions?id=eq.{submission}',
                      {'reviewed_at': _now().isoformat(), **fields}, **_ONCE)  # 다시 보내면 DB 가 이미 찍은 reviewed_at 과 달라 가드 트리거가 거절한다


def heart_07(run):
    check = Check()
    account = _home(run)
    check.reply('첫 제출', _submit(run, account), 201)
    files = _proofs(run, account)
    check.reply('같은 항목 다시', _submit(run, account), 409, '이미 확인 중이에요, 결과를 기다려 주세요')
    check.that(len(_submission_rows(run, account)) == 1, '행이 1이 아님')
    check.that(_proofs(run, account) == files, f'버킷 파일 {files} → {_proofs(run, account)}')
    return check.result()


def heart_08(run):
    check = Check()
    account = _home(run)
    replies = _parallel(lambda: _submit(run, account), lambda: _submit(run, account))
    check.that(sorted(r[0] for r in replies) == [201, 409], f'상태 {[r[0] for r in replies]}(기대 201 · 409)')
    check.that(len(_submission_rows(run, account)) == 1, '행이 1이 아님')
    check.that(_proofs(run, account) == 1, f'버킷 파일 {_proofs(run, account)}(기대 1 — 진 쪽 파일은 지워진다)')
    return check.result()


def heart_10(run):
    check = Check()
    account = _home(run)
    check.reply('제출', _submit(run, account), 201)
    sid = _submission_rows(run, account)[0]['id']
    status, body = _review(run, account, sid, status='approved')
    check.that(status < 300, f'승인 저장 {status} {_detail(body)}')
    check.that(_ledger(run, account, 'free_task') == [50], f'승인 뒤 원장 {_ledger(run, account, "free_task")}(기대 [50])')
    _review(run, account, sid, status='approved')  # 같은 값으로 한 번 더 — 거절돼도 되고, 하트만 다시 안 나가면 된다
    check.that(_ledger(run, account, 'free_task') == [50], f'다시 저장 뒤 원장 {_ledger(run, account, "free_task")}(기대 [50])')
    return check.result()


def heart_11(run):
    check = Check()
    account = _home(run)
    check.reply('에브리타임 제출', _submit(run, account, 'everytime_post'), 201)
    check.reply('단톡방 제출', _submit(run, account, 'kakao_share'), 201)
    approved = _submission_rows(run, account, 'everytime_post')[0]['id']
    rejected = _submission_rows(run, account, 'kakao_share')[0]['id']
    _review(run, account, approved, status='approved')
    _review(run, account, rejected, status='rejected', reject_reason='date_missing')
    to_rejected = _review(run, account, approved, status='rejected', reject_reason='date_missing')
    to_approved = _review(run, account, rejected, status='approved', reject_reason=None)
    check.that(to_rejected[0] >= 400, f'승인 → 반려가 {to_rejected[0]} 로 받아들여짐')
    check.that(to_approved[0] >= 400, f'반려 → 승인이 {to_approved[0]} 로 받아들여짐')
    check.that(_ledger(run, account, 'free_task') == [50], f'원장 {_ledger(run, account, "free_task")}(기대 [50] — 변화 0)')
    return check.result(f'거절 코드 {_detail(to_rejected[1])} / {_detail(to_approved[1])}')


def heart_15(run):
    check = Check()
    account = _home(run)
    check.reply('제출', _submit(run, account), 201)
    row = _submission_rows(run, account)[0]
    status, body = tools.rest(run.cfg, run.key, 'PATCH', f"heart_task_submissions?id=eq.{row['id']}", {'status': 'rejected'})
    check.that(status >= 400 and '23514' in str(body), f'사유 없는 반려 {status} {_detail(body)}(기대 23514)')
    check.that(_submission_rows(run, account)[0]['status'] == 'submitted', '행이 submitted 에서 바뀜')
    return check.result()


def heart_19(run):
    check = Check()
    account = _home(run)
    too_big = b'\xff\xd8\xff' + bytes(11 * 1024 * 1024)
    for label, data in (('텍스트 파일', b'not a photo'), ('11MB 사진', too_big)):
        check.reply(label, _submit(run, account, data=data), 400, PHOTO_UNREADABLE)
    check.that(not _submission_rows(run, account), '행이 생김')
    check.that(_proofs(run, account) == 0, f'버킷 파일 {_proofs(run, account)}개')
    return check.result()


def heart_20(run):
    check = Check()
    account = _home(run)
    check.reply('없는 항목', _submit(run, account, 'poll_vote'), 422)
    return check.result()


SETTLE_SECONDS = 30  # 두 번째 배치 뒤 DB 를 다시 읽기 전에 기다리는 시간 — 스케줄러 호출은 끝을 알려 주지 않는다
POLL_SECONDS = 5
FIRST_BATCH_WAIT = 120  # 첫 배치가 오래된 인증샷을 지울 때까지


def _seed_proof(run, account, task, days):
    """검수가 [days] 일 전에 끝난 인증샷 한 줄 + 파일. 제출 줄은 시각을 옮길 수 없어(트리거) 처음부터 과거로 넣는다(시나리오 G7)."""
    _guard(run, account['id'])
    sid = _new_id()
    path = f"{account['id']}/{sid}.jpg"
    key = run.key
    uploaded = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/storage/v1/object/heart-task-proofs/{path}",
                          {'apikey': key, 'Authorization': f'Bearer {key}'}, raw=(TINY_JPEG, 'image/jpeg'))
    if uploaded[0] >= 300:
        raise Blocked(f'인증샷 파일 올리기 {uploaded[0]} {_detail(uploaded[1])}')
    past = (_now() - timedelta(days=days)).isoformat()
    _insert(run, 'heart_task_submissions', [{'id': sid, 'profile_id': account['id'], 'task': task, 'storage_path': path,
                                            'status': 'approved', 'reward_hearts': 50, 'created_at': past,
                                            'reviewed_at': past}], account['id'])
    return sid, path


def _proof_state(run, account, sid, path):
    """(DB 경로 칸, 파일이 버킷에 남았는지)."""
    row = _rows(run, f'heart_task_submissions?id=eq.{sid}&select=storage_path')
    files = set(tools.storage_paths(run.cfg, run.key, 'heart-task-proofs', account['id']))
    return (row[0]['storage_path'] if row else 'ROW-GONE'), path in files


def heart_24(run):
    """정리 배치를 두 번 — 첫 배치는 검수 끝난 지 60일 넘은 인증샷을 지우고, 두 번째는 더 지울 것이 없다(멱등).
    스케줄러 호출이라 응답의 deleted_heart_proofs 는 못 읽는다 — 61일 · 59일 두 줄의 DB · 파일 상태로 같은 것을 본다."""
    check = Check()
    account = _home(run)
    old, old_path = _seed_proof(run, account, 'everytime_post', 61)
    fresh, fresh_path = _seed_proof(run, account, 'kakao_share', 59)
    _batch('cleanup')
    deadline = time.monotonic() + FIRST_BATCH_WAIT
    while _proof_state(run, account, old, old_path)[0] is not None and time.monotonic() < deadline:
        time.sleep(POLL_SECONDS)
    check.that(_proof_state(run, account, old, old_path) == (None, False), f'첫 배치 뒤 61일 된 줄 {_proof_state(run, account, old, old_path)}(기대 경로 null · 파일 없음)')
    check.that(_proof_state(run, account, fresh, fresh_path) == (fresh_path, True), '59일 된 줄이 첫 배치에서 지워짐')
    _batch('cleanup')
    time.sleep(SETTLE_SECONDS)
    check.that(_proof_state(run, account, old, old_path) == (None, False), '두 번째 배치 뒤 61일 된 줄이 달라짐')
    check.that(_proof_state(run, account, fresh, fresh_path) == (fresh_path, True), '두 번째 배치가 59일 된 줄을 지움(멱등이 아님)')
    return check.result('deleted_heart_proofs 개수는 스케줄러 호출이라 못 읽음 — 줄 · 파일 상태로 확인')


def heart_25(run):
    check = Check()
    mine, theirs = _home(run), _home(run)
    check.reply('내 제출', _submit(run, mine, 'kakao_share'), 201)
    check.reply('남의 제출', _submit(run, theirs, 'kakao_share'), 201)
    status, rows = tools.rest(run.cfg, run.cfg['SUPABASE_ANON_KEY'], 'GET', 'heart_task_submissions?select=profile_id',
                              token=mine['token'])
    check.that(status == 200, f'내 토큰 조회 {status}')
    owners = {r['profile_id'] for r in rows} if status == 200 else set()
    check.that(theirs['id'] not in owners, '남의 제출 행이 보인다')
    check.that(mine['id'] in owners, '내 행도 안 보인다(조회가 막힌 것 — 시험이 의미 없음)')
    return check.result()


def heart_40(run):
    """이 묶음이 만든 모든 계정에서 잔액 캐시 = 원장 합계."""
    check = Check()
    ids = sorted(_mine(run))
    if not ids:
        raise Blocked('시험 계정이 없다 — 다른 가설을 먼저 돌린다')
    for pid in ids:
        balance = _rows(run, f'entitlements?profile_id=eq.{pid}&select=heart_balance')
        total = sum(r['amount'] for r in _rows(run, f'heart_transactions?profile_id=eq.{pid}&select=amount'))
        have = balance[0]['heart_balance'] if balance else 0
        check.that(have == total, f'{pid[:8]} 잔액 {have} ≠ 원장 {total}')
    return check.result(f'계정 {len(ids)}개')


def heart_41(run):
    check = Check()
    account = _home(run)
    status, body = _grant(run, account, 5)
    check.that(status < 300, f'+5 지급 {status} {_detail(body)}')
    status, body = _grant(run, account, -10, 'avatar_regen')
    check.that(status >= 400 and '23514' in str(body), f'−10 이 {status} {_detail(body)}(기대 23514)')
    check.that(len(_rows(run, f"heart_transactions?profile_id=eq.{account['id']}&select=amount")) == 1, '원장 줄 수가 1이 아님')
    held = _rows(run, f"entitlements?profile_id=eq.{account['id']}&select=heart_balance")
    check.that(held == [{'heart_balance': 5}], f'잔액 {held}(기대 5)')
    return check.result()


def heart_48(run):
    check = Check()
    mine, theirs = _home(run), _home(run)
    for account in (mine, theirs):
        _grant(run, account, 10)
    for table, column in (('heart_transactions', 'profile_id'), ('entitlements', 'profile_id')):
        status, rows = tools.rest(run.cfg, run.cfg['SUPABASE_ANON_KEY'], 'GET', f'{table}?select={column}', token=mine['token'])
        check.that(status == 200, f'{table} 조회 {status}')
        owners = {r[column] for r in rows} if status == 200 else set()
        check.that(theirs['id'] not in owners, f'{table}: 남의 행이 보인다')
        check.that(mine['id'] in owners, f'{table}: 내 행도 안 보인다(시험이 의미 없음)')
    return check.result()


# ── 친구 초대 ───────────────────────────────────────────────────────────────────────────────────────

def _code(run, account):
    return _rows(run, f"profiles?id=eq.{account['id']}&select=referral_code")[0]['referral_code']


def _redeem(run, who, code):
    return _api(run, 'POST', '/referral/redeem', who['token'], {'code': code}, **_ONCE)


def ref_09(run):
    check = Check()
    account = _home(run)
    code = _api(run, 'GET', '/referral/my-code', account['token'])
    check.reply('내 코드 조회', code, 200)
    check.reply('내 코드 입력', _redeem(run, account, (code[1] or {}).get('code', '')), 422, CODE_NOT_ALLOWED)
    check.that(not _ledger(run, account, 'referral'), '원장이 생김')
    return check.result()


def ref_10(run):
    check = Check()
    me, first, second = _home(run), _home(run), _home(run)
    check.reply('첫 입력', _redeem(run, me, _code(run, first)), 200)
    check.reply('두 번째 입력', _redeem(run, me, _code(run, second)), 409, CODE_ALREADY)
    check.that(_ledger(run, me, 'referral') == [50], f'원장 {_ledger(run, me, "referral")}(기대 [50] — 변화 0)')
    return check.result()


def ref_11(run):
    check = Check()
    me, suspended, withdrawn = _home(run), _home(run), _home(run)
    codes = [_code(run, suspended), _code(run, withdrawn)]
    _set_status(run, suspended, 'suspended')
    _set_status(run, withdrawn, 'withdrawn')
    for label, code in zip(('정지', '탈퇴'), codes):
        check.reply(f'{label} 계정 코드', _redeem(run, me, code), 404, CODE_NOT_FOUND)
    return check.result()


def ref_12(run):
    check = Check()
    number = _phone()
    referrer, me = _home(run, phone=number), _home(run, phone=number)
    check.reply('같은 번호', _redeem(run, me, _code(run, referrer)), 422, CODE_NOT_ALLOWED)
    return check.result()


def ref_13(run):
    check = Check()
    number = _phone()
    first, second, third = _home(run, phone=number), _home(run, phone=number), _home(run)
    check.reply('첫 계정 입력', _redeem(run, first, _code(run, third)), 200)
    check.reply('같은 번호 두 번째 계정', _redeem(run, second, _code(run, third)), 422, CODE_NOT_ALLOWED)
    return check.result()


def ref_14(run):
    check = Check()
    referrer, me = _home(run), _home(run)
    _guard(run, me['id'])
    _patch(run, f"profile_private?profile_id=eq.{me['id']}", {'phone_hmac': None})
    check.reply('해시 없는 계정', _redeem(run, me, _code(run, referrer)), 200)
    check.that(_ledger(run, me, 'referral') == [50], f'내 원장 {_ledger(run, me, "referral")}(기대 [50])')
    check.that(_ledger(run, referrer, 'referral') == [50], f'추천인 원장 {_ledger(run, referrer, "referral")}(기대 [50])')
    return check.result()


def ref_15(run):
    check = Check()
    referrer, me = _home(run), _home(run)
    code = _code(run, referrer)
    replies = _parallel(lambda: _redeem(run, me, code), lambda: _redeem(run, me, code))
    check.that(sorted(r[0] for r in replies) == [200, 409], f'상태 {[r[0] for r in replies]}(기대 200 · 409)')
    check.that(_ledger(run, me, 'referral') == [50], f'내 원장 {_ledger(run, me, "referral")}(기대 [50])')
    check.that(_ledger(run, referrer, 'referral') == [50], f'추천인 원장 {_ledger(run, referrer, "referral")}(기대 [50])')
    return check.result()


def ref_16(run):
    check = Check()
    account = run.account('consented')  # 학생증 인증 · 학과 입력 전
    check.reply('추천 코드 입력', _redeem(run, account, 'ABCDEF'), 403, SV_REQUIRED)
    return check.result()


def ref_19(run):
    check = Check()
    referrer, me = _home(run), _home(run)
    check.reply('코드 입력', _redeem(run, me, _code(run, referrer)), 200)
    reply = _api(run, 'GET', f"/friend-reviews/targets/{referrer['id']}", me['token'])
    check.reply('리뷰 대상', reply, 200)
    check.that(reply[0] != 200 or reply[1].get('profile_id') == referrer['id'], f'대상 {reply[1]}')
    return check.result()


# ── 등록 · 묶음 ─────────────────────────────────────────────────────────────────────────────────────

CASES = {
    'E-HOME-27': home_27,
    'E-CARD-30': card_30, 'E-CARD-31': card_31, 'E-CARD-34': card_34, 'E-CARD-37': card_37, 'E-CARD-38': card_38,
    'E-CARD-39': card_39, 'E-CARD-55': card_55,
    'E-CARD-60': card_60, 'E-CARD-61': card_61, 'E-CARD-62': card_62, 'E-CARD-63': card_63, 'E-CARD-64': card_64,
    'E-CARD-65': card_65, 'E-CARD-66': card_66, 'E-CARD-67': card_67, 'E-CARD-69': card_69, 'E-CARD-70': card_70,
    'E-CARD-71': card_71,
    'E-CARD-82': card_82, 'E-CARD-83': card_83, 'E-CARD-88': card_88, 'E-CARD-89': card_89,
    'E-POLL-03': poll_03, 'E-POLL-10': poll_10, 'E-POLL-17': poll_17, 'E-POLL-24': poll_24,
    'E-HEART-07': heart_07, 'E-HEART-08': heart_08, 'E-HEART-10': heart_10, 'E-HEART-11': heart_11, 'E-HEART-15': heart_15,
    'E-HEART-19': heart_19, 'E-HEART-20': heart_20, 'E-HEART-24': heart_24, 'E-HEART-25': heart_25, 'E-HEART-40': heart_40,
    'E-HEART-41': heart_41, 'E-HEART-48': heart_48,
    'E-REF-09': ref_09, 'E-REF-10': ref_10, 'E-REF-11': ref_11, 'E-REF-12': ref_12, 'E-REF-13': ref_13, 'E-REF-14': ref_14,
    'E-REF-15': ref_15, 'E-REF-16': ref_16, 'E-REF-19': ref_19,
}
# 시나리오 API만 50 중 이 묶음에서 안 쓰는 둘 — 이유를 남긴다.
SKIPPED = {
    'E-CARD-73': '사진 교체는 profile_photos 행(최소 2장 · 저장소 파일)과 /me/photos 가 얽혀 API 만으로 깔끔히 못 한다 — 사진은 점수를 안 읽는다는 코드(scoring.py)로 대신하고 폰 · 사진 세트 묶음에서',
    'E-HEART-46': '아바타 다시 만들기는 실제 AI 호출이 끝나길 기다려야 하고 그 사이 잔액을 빼야 해서 진행이 타이밍을 못 잡는다 — 아바타 가설 묶음(실제 AI)에서',
}
BUNDLES = {'area2-api': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked, 시험 쪽 예외도 blocked(앱 결함으로 세지 않는다).
    연결이 끊긴 것(운영 실행에서 가끔 — ConnectionResetError · SSL · http.client 끊김, tools.TRANSIENT)은 가설을 처음부터 한 번 더 한다 — 계정은 매번 새로 만들고
    쓰기는 이번 실행의 계정에만 하므로 다시 해도 안전하다. 두 번째에도 끊기면 blocked."""
    for tries in (1, 2):
        try:
            return CASES[case](run)
        except Blocked as e:
            return 'blocked', str(e)
        except tools.TRANSIENT as e:  # tools.call 이 한 번만 보내는 요청(_ONCE)의 끊김까지 여기서 받는다
            if tries == 2:
                return 'blocked', f'연결이 두 번 끊김: {type(e).__name__} {e}'
        except Exception as e:  # 시험 쪽 버그 · 예상 밖 응답 모양 — 긴 실행이 한 가설 때문에 멈추지 않게
            return 'blocked', f'진행 프로그램 예외 {type(e).__name__}: {e}'
