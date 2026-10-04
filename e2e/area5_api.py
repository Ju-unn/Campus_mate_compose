"""영역 5 API 가설 4개 — E-ME-17 · E-ME-37 · E-ME-45 · E-EDGE-22 (묶음 area5-api, 기기 없이 토큰 · 서비스 키로만).
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 의 그 줄(ME-17 · 37 · 45 는 5-1 표, EDGE-22 는 5-4 표)을 지금 코드와 대조한 것이다.

가설 하나 = 함수 하나 `(run) -> (결과, 메모)`. 계정은 가설마다 `run.account('home')` 으로 새로 만든다. 쓰기는 이번 실행이 만든 계정 id 에만 한다([_guard]).
판정은 PC 쪽 — 상태 코드 · 문구 · DB 행을 보고, 값이 비어 읽히면 "그대로" 가 증거가 못 되니 blocked 로 둔다.

시나리오와 다르게 도는 것
- E-EDGE-22: 시나리오(와 지시서)는 환경변수가 없을 때 "202 두 개 · pending 1개까지만" 보라고 하지만, 202 한 번이 곧 워커 작업 등록
  (= 유료 AI 호출)이라 `E2E_REAL_AI=1` 이 아니면 요청을 한 번도 보내지 않고 blocked 로 둔다(area2_phone3 의 같은 규칙 — real_ai_gate · _PAID).
  `_PAID` 는 그대로 쓰되, run_case 가 fail 을 한 번 더 부르면 첫 fail 을 그대로 돌려준다(blocked 로 덮이면 동시성 결함이 보고서에서 사라진다).
  완성 기다림은 최대 10분(WAIT). 근거 줄은 옮겨졌다 — 하트 차감은 tasks_router.py:108-109 · 113~ , 중복 누름은 profile_onboarding/router.py:227-238.
- E-ME-37: 422 본문은 FastAPI 기본 목록(`detail: [{msg: 'Value error, …'}]`)이라 문구 전체가 아니라 이유 문장(`빈 값으로는 바꿀 수 없어요` ·
  `고칠 칸이 없어요`, me/schemas.py:35-41)이 들어 있는지 본다 — 다른 이유의 422 를 통과시키지 않으려고.
- E-ME-17: 두 경우를 한 계정으로 차례로 본다(원본 사진 표시를 끄고 아바타 행을 지워 ready 0 → 다시 한 장 넣어 원본 없음). 서버는 ready 검사를 먼저 하므로
  (me/router.py:123-128) 첫째 경우는 원본 표시가 꺼진 채여도 "아바타를 먼저 만들어 주세요" 409 다. 순서를 이렇게 둔 이유는 비용이다 — ready 검사를 잃은 서버가
  202 를 내도 워커가 원본이 없어 failed 로 끝내 유료 AI 호출 0 이고, 그 서버는 첫째 경우에서 "원본 사진" 문구로 fail 이 난다. 시나리오의 첫째 경우("ready 0")는
  원본 표시가 있는 채 보라는 뜻이 아니라 ready 검사만 본다는 뜻이다. 둘째 경우의 준비(ready 한 장 되살리기)는 그대로다.
"""

import json
import time

from e2e import tools
from e2e.area1 import INVALID_INPUT, Check, _api, _patch, _rows
from e2e.area2 import PHOTO_UNREADABLE, _ONCE, _guard, _parallel
from e2e.area2_phone3 import POLL, _PAID, _add_avatar, _avatars, _balance, _give, _wait_for, real_ai_gate
from e2e.tools import Blocked

AVATAR_NOT_CREATED = '아바타를 먼저 만들어 주세요'
AVATAR_SOURCE_REQUIRED = '아바타 원본 사진을 먼저 골라 주세요'
NULL_REASON = '빈 값으로는 바꿀 수 없어요'
EMPTY_REASON = '고칠 칸이 없어요'
PROFILE_FIELDS = ('nickname', 'height_cm', 'bio')
WAIT = 600  # 아바타 한 장이 완성되기를 기다리는 시간(초) — 10분
START_HEARTS, REGEN_COST = 37, 10  # 완성된 아바타가 2장이면 다시 만들기 값은 10하트
EDGE_22 = 'E-EDGE-22'
_FAILED = {}  # 유료 호출 뒤 fail 로 끝난 가설의 결과 — 다시 불려도 같은 비용을 두 번 내지 않고 이 값을 돌려준다


def _regenerate(run, account):
    """다시 만들기 요청 — 서버에 닿았는지 모호해도 다시 보내지 않는다(작업이 두 번 등록되면 안 된다)."""
    return _api(run, 'POST', '/me/avatar/regenerate', account['token'], **_ONCE)


def _ready(rows):
    return [r for r in rows if r['status'] == 'ready']


def _pending(rows):
    return [r for r in rows if r['status'] == 'pending']


# ── E-ME-17 ──────────────────────────────────────────────────────────────────────────────────────────

def me_17(run):
    check = Check()
    account = run.account('home')
    _guard(run, account['id'])
    photos = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=id,is_avatar_source")
    if len(_ready(_avatars(run, account))) != 1 or not any(p['is_avatar_source'] for p in photos):
        raise Blocked('준비: 처음부터 ready 아바타 1장 · 원본 사진 표시가 없다 — 409 가 규칙 때문인지 모른다')

    _patch(run, f"profile_photos?profile_id=eq.{account['id']}", {'is_avatar_source': False})  # 첫째 경우 전에 — 비용 안전장치(위 docstring)
    status, got = tools.rest(run.cfg, run.key, 'DELETE', f"profile_avatars?profile_id=eq.{account['id']}")
    if status >= 300:
        raise Blocked(f'아바타 행 지우기 {status} {got}')
    if _avatars(run, account):
        raise Blocked('준비: 아바타 행이 안 지워짐')
    check.reply('ready 0장', _regenerate(run, account), 409, AVATAR_NOT_CREATED)
    rows = _avatars(run, account)
    check.that(not rows, f'ready 0장 뒤 아바타 행 {len(rows)}개(기대 0 — pending {len(_pending(rows))}개)')

    reply = run._avatar(account)  # ready 한 장을 되살린다 — 원본 사진 표시는 위에서 이미 꺼져 있다
    if reply[0] >= 300:
        raise Blocked(f'아바타 행 넣기 {reply[0]} {reply[1]}')
    check.reply('원본 사진 표시 없음', _regenerate(run, account), 409, AVATAR_SOURCE_REQUIRED)
    rows = _avatars(run, account)
    check.that(len(rows) == 1 and not _pending(rows), f'원본 사진 표시 없음 뒤 아바타 행 {len(rows)}개 · pending {len(_pending(rows))}개(기대 1개 · 0개)')
    return check.result()


# ── E-ME-37 ──────────────────────────────────────────────────────────────────────────────────────────

def _profile(run, account):
    """닉네임 · 키 · 자기소개. 한 행이 아니거나 칸이 안 읽히면 "그대로" 를 증명할 수 없다 — blocked."""
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select={','.join(PROFILE_FIELDS)}")
    if len(rows) != 1 or any(k not in rows[0] for k in PROFILE_FIELDS):
        raise Blocked(f'준비: 프로필 한 행의 {" · ".join(PROFILE_FIELDS)} 를 못 읽음({len(rows)}행)')
    return {k: rows[0][k] for k in PROFILE_FIELDS}


def me_37(run):
    check = Check()
    account = run.account('home')
    before = _profile(run, account)
    empty = [k for k, v in before.items() if v is None]
    if empty:
        raise Blocked(f'준비: {" · ".join(empty)} 가 처음부터 비어 있어 "그대로" 가 증거가 못 된다')
    for label, body, reason in (('키 null', {'height_cm': None}, NULL_REASON), ('빈 본문', {}, EMPTY_REASON)):
        check.reply(label, _api(run, 'PATCH', '/me/profile', account['token'], body), 422, contains=reason)
        after = _profile(run, account)
        changed = [k for k in PROFILE_FIELDS if after[k] != before[k]]
        check.that(not changed, f'{label} 뒤 DB 가 바뀜: {changed}')
    return check.result()


# ── E-ME-45 ──────────────────────────────────────────────────────────────────────────────────────────

def _photo_rows(run, account):
    rows = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=id,storage_path,position,is_avatar_source")
    return sorted(rows, key=lambda r: r['position'])


def _photo_files(run, account):
    """profile-photos 버킷의 `{id}/` 아래 파일 경로. 목록을 못 읽으면 SystemExit 라 blocked 로 바꾼다 — 진행 전체가 멈추지 않게."""
    try:
        return sorted(tools.storage_paths(run.cfg, run.key, 'profile-photos', account['id']))
    except SystemExit as e:
        raise Blocked(f'profile-photos 목록을 못 읽음: {e}') from e


def me_45(run):
    check = Check()
    account = run.account('home')
    rows, files = _photo_rows(run, account), _photo_files(run, account)
    if len(rows) < 2 or len(files) < len(rows):
        raise Blocked(f'준비: 저장된 사진 행 {len(rows)}개 · 파일 {len(files)}개 — 2개 이상 있어야 "그대로" 가 증거다')
    keep = rows[0]['id']
    text = ('photos', 'note.txt', b'hello', 'text/plain')
    for label, layout, file, status, detail in (
            ('칸 1개', [{'keep': keep}], None, 422, INVALID_INPUT),
            ('같은 id 두 번', [{'keep': keep}, {'keep': keep}], None, 422, INVALID_INPUT),
            ('텍스트 파일', [{'keep': keep}, {'new': 0}], text, 400, PHOTO_UNREADABLE)):
        reply = tools.form(f"{run.cfg['API_BASE_URL']}/me/photos", account['token'],
                           {'layout': json.dumps(layout), 'avatar_source': 0}, file, method='PUT')
        check.reply(label, reply, status, detail)
        check.that(_photo_rows(run, account) == rows, f'{label} 뒤 profile_photos 가 바뀜')
        check.that(_photo_files(run, account) == files, f'{label} 뒤 profile-photos 버킷 파일이 바뀜')
    return check.result()


# ── E-EDGE-22 (유료 AI) ──────────────────────────────────────────────────────────────────────────────

def _body_status(reply):
    return reply[1].get('status') if isinstance(reply[1], dict) else None


def _twice_and_wait(run, account, known, check):
    """두 요청을 한 순간에 보내고, 만들어진 한 장이 끝나기를 기다려 하트를 본다."""
    replies = _parallel(lambda: _regenerate(run, account), lambda: _regenerate(run, account))
    for number, reply in enumerate(replies, 1):
        check.reply(f'요청 {number}', reply, 202)
        check.that(_body_status(reply) == 'pending', f'요청 {number}: 본문 status {_body_status(reply)!r}(기대 pending)')
    new = [r for r in _avatars(run, account) if r['id'] not in known]
    if len(new) != 1:
        check.that(False, f'새 아바타 행 {len(new)}개(기대 1)')
        return  # 작업이 둘이면 더 기다릴 것이 없다 — 바로 판정
    made = new[0]
    moved = set()
    deadline = time.monotonic() + WAIT
    while True:
        during = _balance(run, account)  # 잔액을 먼저 읽는다 — 그다음 읽은 행이 아직 pending 이면 이 값은 차감 전이다
        now = next((r for r in _avatars(run, account) if r['id'] == made['id']), None)
        if now is None:
            raise Blocked('만들던 아바타 행이 사라짐')
        if now['status'] == 'failed':
            raise Blocked('아바타 생성이 실패(AI 쪽) — 서버 결함으로 세지 않는다')
        if now['status'] == 'ready':
            break
        if during != START_HEARTS:
            moved.add(during)
        if time.monotonic() >= deadline:
            raise Blocked(f'{WAIT}초 안에 새 아바타가 안 끝남')
        time.sleep(POLL)
    check.that(not moved, f'만드는 중 잔액 {sorted(moved)}(기대 {START_HEARTS} — 하트는 완성 뒤에 빠진다)')
    _wait_for(lambda: _balance(run, account) != START_HEARTS, 60)  # 차감은 완성을 적은 뒤에 나간다
    time.sleep(POLL)  # 한 번 더 빠지는지 보려고 한 박자
    want = START_HEARTS - REGEN_COST
    check.that(_balance(run, account) == want, f'완성 뒤 잔액 {_balance(run, account)}(기대 {want})')
    ledger = _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.avatar_regen&select=amount,ref_id")
    check.that([r['amount'] for r in ledger] == [-REGEN_COST], f'avatar_regen 원장 {[r["amount"] for r in ledger]}(기대 [{-REGEN_COST}])')
    check.that(all(r.get('ref_id') == made['id'] for r in ledger), '원장 ref_id 가 새 아바타 행 id 와 다름')
    rows = _avatars(run, account)
    check.that(len(rows) == 3 and len(_ready(rows)) == 3, f'끝난 뒤 아바타 행 {[r["status"] for r in rows]}(기대 ready 3개)')


def edge_22(run):
    real_ai_gate()  # 202 한 번이 곧 유료 AI 호출이다 — 환경변수가 없으면 요청을 한 번도 보내지 않는다
    if EDGE_22 in _PAID:
        return _FAILED.get(EDGE_22) or ('blocked', '이미 한 번 유료 호출 — 재시도 안 함')
    check = Check()
    account = run.account('home')
    _add_avatar(run, account)  # 홈 계정의 첫 장에 한 장 더 — 완성 2장
    _give(run, account, START_HEARTS)
    known = {r['id'] for r in _avatars(run, account)}
    balance = _balance(run, account)
    if len(known) != 2 or len(_ready(_avatars(run, account))) != 2 or balance != START_HEARTS:
        raise Blocked(f'준비: 아바타 행 {len(known)}개 · 하트 {balance}(기대 ready 2장 · {START_HEARTS})')
    _PAID.add(EDGE_22)  # 여기부터는 비용이 나간다
    _twice_and_wait(run, account, known, check)
    result = check.result(f'AI 1장 완성 · 하트 −{REGEN_COST} 한 번({START_HEARTS}→{START_HEARTS - REGEN_COST})')
    if result[0] == 'fail':
        _FAILED[EDGE_22] = result
    return result


CASES = {'E-ME-17': me_17, 'E-ME-37': me_37, 'E-ME-45': me_45, EDGE_22: edge_22}
BUNDLES = {'area5-api': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
