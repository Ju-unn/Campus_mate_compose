"""영역 5 아바타를 만드는 중 앱을 죽이는 가설 둘 — E-EDGE-17 · 18(묶음 area5-kill). 폰 A 한 대, 둘 다 유료(워커의 OpenAI 이미지 생성 1번).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 5 의 그 줄이되, 코드가 다르면 코드가 기준이다. 앱 쪽은 frontend/integration_test/area5_kill.dart 의 같은 번호.

준비는 둘 다 같다 — ready 아바타 2장(다시 만들기 값 10) · 하트 37. 앱이 15b 시트에서 "10 쓰고 만들기" 를 누르자마자 답을 안 기다리는 멈춤 말(`pressed`)을 보내면
PC 가 [KILL_AFTER]초 뒤 앱 프로세스를 죽인다(E-EDGE-20 과 같은 `_kill_soon`).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  force-stop 대신 run-as kill -9  앱을 "멈춘 앱" 으로 만들면 FCM 이 끊긴다(E-EDGE-20 과 같은 까닭 — tools.Run.phone 주석). 서버 쪽 작업이 앱과 상관없이 도는 것을 보는 목적은 같다.
  E-EDGE-17  "3분 뒤 앱 실행" 은 3분을 고정으로 기다리지 않고 서버가 새 그림을 완성할 때까지(최대 [WORKER_WAIT]초) 기다린 뒤 [SETTLE]초 쉬고 켠다.
             죽인 직후 새 행이 서버에 하나도 없으면(요청이 안 닿았다) fail 이 아니라 blocked 다. 워커가 실패(AI 쪽)하면 blocked.
  E-EDGE-18  "서버 202" 는 앱이 HTTP 코드를 말하지 않아 직접 못 본다 — 같은 202(작업을 또 만들지 않음)면 새 행이 하나이고 완성 뒤 하트가 한 번만 빠지는 것으로 본다.
             다시 켠 앱이 15 를 연 뒤 멈추면(`opened`) PC 가 그 순간 pending 행이 아직 있는지 본다 — 이미 끝났으면(워커가 빨랐다) 두 번째 누름이 새 시도가 되어
             판정이 안 되니 blocked. 앱 실행은 죽인 뒤 [LATE]초 뒤다.
유료 호출: 큐 등록 1번 · 워커의 OpenAI 이미지 생성 1번(하트 10개). 18 에서 두 번째 누름이 같은 202 면 더 늘지 않는다.
"""

import time

from e2e import area1, tools
from e2e.area1 import Check, _app, _rows
from e2e.area2_phone3 import _balance, _slow, _wait_for
from e2e.area3_phone import MISSING
from e2e.area5_act import _paid_case
from e2e.area5_photo import COST, HEARTS, WORKER_MS, WORKER_WAIT, _hearts_to, _paid_body, _regen_ui, _two_ready
from e2e.area5_read import _avatar_rows, _home
from e2e.area5_wd import SETTLE, _Killed, _kill_soon
from e2e.tools import Blocked

KILL_AFTER = 2.0  # 시나리오 "누른 뒤 2초" — 요청이 서버에 닿을 시간
LATE = 10.0  # 시나리오 E-EDGE-18 "앱 실행을 10초 뒤로"
ATTEMPT_WAIT = 30  # 죽인 뒤 서버에 새 시도 행이 보이기를 기다리는 초
CASE_LIMIT = 1500


def _ledger_rows(run, account):
    return _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.avatar_regen&select=amount,ref_id")


def _newest_ready_file(run, account):
    """가장 늦게 만들어진 ready 아바타의 파일 이름 · id."""
    rows = [r for r in _rows(run, f"profile_avatars?profile_id=eq.{account['id']}&select=id,status,storage_path,created_at") if r['status'] == 'ready']
    if not rows:
        return None, None
    newest = max(rows, key=lambda r: r['created_at'])
    return newest['storage_path'].rsplit('/', 1)[-1], newest['id']


def _start(run, phone, paid):
    """준비 → 앱이 누른 직후 죽이기. (check, account, token, known 행 id 집합, 죽이기까지 ms)."""
    check = Check()
    account, token = _home(run)
    _two_ready(run, account)
    _hearts_to(run, account, HEARTS)
    known = {r[0] for r in _avatar_rows(run, account)}
    paid()  # 여기부터는 큐 등록 · OpenAI 이미지 생성(유료)이 나갈 수 있다
    try:
        said = phone(token_hash=token, phase='press', midway=_kill_soon(phone, KILL_AFTER))
    except _Killed as killed:
        return check, account, token, known, killed.args[0]
    _app(check, said)
    check.that(False, '앱이 누른 뒤 멈추지 않고 끝남 — 죽일 때를 못 잡음')
    raise Blocked('누른 뒤 앱을 못 죽임: ' + '; '.join(check.problems))


def _new_rows(run, account, known):
    return [r for r in _avatar_rows(run, account) if r[0] not in known]


def _reached_server(run, account, known):
    """죽인 뒤 서버에 새 시도 행이 생겼나 — 없으면 요청이 안 닿은 것이라 판정할 수 없다."""
    if not _wait_for(lambda: _new_rows(run, account, known), ATTEMPT_WAIT):
        raise Blocked(f'죽인 뒤 {ATTEMPT_WAIT}초가 지나도 새 아바타 행이 서버에 없음 — 요청이 안 닿았다(2초가 짧았나), 판정 못 함')


def _one_charge(check, run, account, known, balance_want):
    """새 행은 완성 하나뿐이고, 하트는 한 번(-COST)만 빠졌고, 원장이 그 행을 가리킨다. 새 ready 의 id 를 돌려준다."""
    new = _new_rows(run, account, known)
    check.that([r[1] for r in new] == ['ready'], f'새 아바타 행 {[r[1] for r in new]}(기대 [ready] 한 행 — 작업이 하나만 돌았다)')
    have = _balance(run, account)
    check.that(have == balance_want, f'하트 {have}(기대 {HEARTS} → {balance_want} — 완성된 뒤 한 번만)')
    ledger = _ledger_rows(run, account)
    check.that([r['amount'] for r in ledger] == [-COST], f"avatar_regen 원장 {[r['amount'] for r in ledger]}(기대 [{-COST}] 한 줄 — 두 번 안 빠짐)")
    new_id = new[0][0] if len(new) == 1 else None
    refs = [r.get('ref_id') for r in ledger]
    check.that(new_id is not None and refs == [new_id], f'원장의 ref_id {refs}(기대 새 아바타 행 {new_id})')
    return new_id


def p_edge_17(run, phone, paid):
    check, account, token, known, ms = _start(run, phone, paid)
    _reached_server(run, account, known)
    if not _wait_for(lambda: all(r[1] != 'pending' for r in _new_rows(run, account, known)), WORKER_WAIT):
        raise Blocked(f'워커가 {WORKER_WAIT}초 안에 안 끝남(새 행 {[r[1] for r in _new_rows(run, account, known)]}) — 판정 못 함')
    if 'failed' in [r[1] for r in _new_rows(run, account, known)]:
        raise Blocked(f'아바타 생성이 실패(AI 쪽) — 앱 결함으로 세지 않는다(새 행 {[r[1] for r in _new_rows(run, account, known)]})')
    time.sleep(SETTLE)
    said = _app(check, phone(phase='after'))
    _one_charge(check, run, account, known, HEARTS - COST)
    file, _ = _newest_ready_file(run, account)
    check.that(file is not None and said.get('avatar_file', MISSING) == file,
               f"다시 켠 앱의 히어로 그림 {said.get('avatar_file', MISSING)!r}(기대 가장 늦게 만든 ready {file!r})")
    check.that(said.get('sheet_body', MISSING) == _paid_body(HEARTS - COST),
               f"다시 켠 앱의 15b 글 {said.get('sheet_body', MISSING)!r}(기대 {_paid_body(HEARTS - COST)!r} — 줄어든 하트)")
    return check.result(f'누른 뒤 {ms}ms 에 kill · 다시 켠 앱이 새 그림과 하트 {HEARTS - COST} 를 봄. 유료 호출: 큐 등록 1번 · OpenAI 이미지 1번(하트 {COST}개)')


def p_edge_18(run, phone, paid):
    check, account, token, known, ms = _start(run, phone, paid)
    killed_at = time.monotonic()
    _reached_server(run, account, known)
    time.sleep(max(0.0, LATE - (time.monotonic() - killed_at)))
    seen = {}

    def opened(said):  # 다시 켠 앱이 15 를 연 채 멈춤 — 그 순간 첫 시도가 아직 만드는 중이어야 두 번째 누름이 같은 202 가 된다
        statuses = [r[1] for r in _new_rows(run, account, known)]
        seen['statuses'] = statuses
        if statuses != ['pending']:
            raise Blocked(f'다시 켠 앱이 15 를 연 때 새 행 {statuses}(기대 [pending] — 이미 끝났거나 실패해 두 번째 누름이 새 시도가 된다), 판정 못 함')
    said = _app(check, _slow(phone, WORKER_WAIT)(phase='after', midway=opened))
    new = _new_rows(run, account, known)
    if 'failed' in [r[1] for r in new]:
        raise Blocked(f'아바타 생성이 실패(AI 쪽) — 앱 결함으로 세지 않는다(새 행 {[r[1] for r in new]})')
    _regen_ui(check, said)
    _one_charge(check, run, account, known, HEARTS - COST)
    return check.result(f"누른 뒤 {ms}ms 에 kill · 앱 실행 {LATE:.0f}초 뒤 새 행 {seen.get('statuses')} 에서 다시 누름 · 새 행 하나 · 하트 한 번. "
                        '"서버 202" 는 앱이 코드를 안 말해 새 행 · 원장으로 대신 봄. 유료 호출: 큐 등록 1번 · OpenAI 이미지 1번')


PHONE = {'E-EDGE-17': _paid_case('E-EDGE-17', p_edge_17), 'E-EDGE-18': _paid_case('E-EDGE-18', p_edge_18)}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-kill'] = list(PHONE)
tools.CASE_LIMITS.update({case: CASE_LIMIT for case in PHONE})
