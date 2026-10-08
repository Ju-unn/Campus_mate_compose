"""영역 5 폰 A 한 대 — 탈퇴 흐름 9개(묶음 area5-wd): E-WD-02 · 04 · 12 · 13 · 14 · 15 · 16 · 18, E-EDGE-20.
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 5-2 · 5-4 표의 그 줄을 지금 코드와 대조한 것이다. 앱 쪽은
frontend/integration_test/area5_wd.dart 의 같은 번호(area5.dart 가 묶는다). E-WD-12 는 앱이 없는 API 가설(area1.CASES)이다.

소셜 로그인 전환(20261008) 뒤: 아래와 메모의 "02(로그인 화면)" 은 로그아웃하면 닿는 시작 화면(앱 쪽 screen('start'))을 뜻한다 — 02 는 이제
로그인한 계정의 학교 메일 인증 화면이다. 탈퇴한 메일로 02 에서 다시 가입하는 E-WD-14 · 15 는 막아 두었다(REJOIN_ON_02_BLOCKED).
공장 계정은 school_email_claims 가 없어 탈퇴가 재가입 제한 행을 남기지 않는다 — 새 제한 행을 보는 04 · 16 · EDGE-20 은 기기에서 먼저 확인한다.

가설 하나 = 함수 하나. PC 가 계정을 만들고 서비스 키 DB 로 준비하면, 앱이 화면을 열어 누르고 본 것을 Map 으로 말하고(문구는 사람이 읽는 글자 그대로,
못 본 것은 None — `MISSING` 과 가른다), 판정은 여기서 한다. 탈퇴는 되돌릴 수 없어 계정은 가설마다 새로 만든다.
쓰기는 이번 실행이 만든 계정에만 한다(area2._guard) — 앱이 "정말 영구 삭제" 를 누르는 넷(04 · 16 · 18 · EDGE-20)은 area5_read._home 이
앱을 켜기 전에 가드를 지난다. PC 가 보내는 탈퇴(POST /account/withdraw)는 한 번만(retry=False — 끊겨 다시 보내면 401 이 와 blocked 로 읽힌다).

영역 1(area1_b2 의 E-AUTH-07 ~ 12)과의 겹침 — 별칭 0개. WD 줄이 모두 AUTH 줄보다 더 본다. 헬퍼는 가져다 쓴다(_blocks · _new_block · _two_months_after ·
REJOIN_BLOCKED). area1_b2._withdrawn_and_cleaned · _withdraw 는 탈퇴를 retry 로 보내고 배치 호출을 세지 않아(다시 돌기 막기 불가) 같은 순서의 _cleaned_away 를 둔다.
  E-WD-02  AUTH 없음(같은 동작은 E-SET-69) — PC 가 먼저 matching_paused=false 를 보장하고 판정을 PC 로
  E-WD-04  ≈ E-AUTH-07(+ E-SET-70) — 02 까지 시간 · 알림 한 번(다시 들어가도 안 뜸) · withdrawn_at · push_tokens 0 · student-id-temp 0 을 더 본다
  E-WD-12  AUTH 없음(E-BATCH-20 의 절반) — 29일 계정을 정리 배치가 안 지운다
  E-WD-13  ≈ E-AUTH-09 — "홈 화면 0번" 을 더 본다(앱이 프레임마다 홈을 찾는다)
  E-WD-14  ≈ E-AUTH-10 — 거절 문구가 02 화면에 뜨는지(AUTH-10 은 API 응답만)
  E-WD-15  ≈ E-AUTH-11 + 12 — ① 을 앱으로(03 도착) ② 실제 탈퇴로 생긴 행을 정리 배치가 지운다(AUTH-12 는 가짜 행)
  E-WD-16  ≈ E-AUTH-08 + 12 — 앱이 정지를 모르는 경합 길(일반 최종 시트) + 그 무기한 행이 실제 정리 배치 뒤에도 남는다
  E-WD-18 · E-EDGE-20  AUTH 없음

정리 배치(cleanup)는 운영 전체에 돈다 — 탈퇴 30일 지난 모든 계정 · 끝난 재가입 제한 · 1년 지난 처리된 신고 · 60일 지난 하트 인증샷을 지운다.
새벽 04:00 예약 실행이 할 일을 앞당길 뿐이다(시나리오 ⚠ 9번 ③). 부르는 넷(12 · 14 · 15 · 16)은 준비 전에 batch_gate.peek(04:00 ± 5분 금지)를 보고,
area3_phone5._batch(관문 → gcloud, 부른 횟수를 센다)로 부른다. 부른 뒤의 fail 은 다시 안 돈다(area3_phone5._single_shot — 운영 배치를 또 부르지 않게).
gcloud 는 결과 칸(deleted_accounts 등)을 보여 주지 않아 DB 로 본다. "안 지웠다" 를 보는 12 · 16 은 배치가 돈 증거가 필요해, 어제 끝난 확인용 재가입 제한 행
(무작위 HMAC)을 넣고 그 행이 지워지기를 기다린다(run_cleanup 은 계정 정리 ① 뒤에 제한 정리 ③ 을 하므로 그 행이 지워지면 ① 도 끝났다). 확인용 행은 어떻게
끝나든 지운다. 가설끼리 간섭: 29일 계정(12)은 실행이 하루를 넘기지 않는 한 다른 가설의 정리 배치에도 남는다. 15 의 끝난 행은 다른 정리 배치가 먼저 지울 수 있어
앱이 물은 뒤 그 행이 있는지 보고, 없으면 blocked. 16 의 무기한 행은 어느 배치에도 남는다. 탈퇴로 생긴 제한 행은 시작 스냅샷 밖이라 tools.cleanup 이 지운다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-WD-04  "3초 안에 02" 는 로그아웃 뒤 다시 그려지는 스플래시를 임시로 2초 붙잡는 장치(splash_hold.dart) 때문에 지킬 수 없다 — 5초(3 + 2, area1.dart
           _arriveAt 과 같은 셈)로 본다. "02 에 다시 들어오면 안 뜸" 은 앱이 로그아웃 상태에서 한 번 더 로그아웃해(SessionScope 가 화면 트리를 새로 만든다 —
           로그아웃 뒤 02 가 처음 그려지는 길과 같다) 새 02 에 알림이 없는지로 본다. 푸시 토큰은 PC 가 가짜 토큰 행을, 학생증 임시 파일은 그림 한 장을 넣는다.
  E-WD-12 · 14 · 15  계정은 홈까지가 아니라 basic(04-1 까지 — 사진 · 임베딩 없음, 유료 0)이다. 탈퇴 · 재가입 규칙은 단계와 상관없다.
           12 의 "파일 그대로" 는 탈퇴 뒤 버킷 넷에 그림을 한 장씩 넣고 본다(탈퇴가 student-id-temp 를 비우므로 뒤에 넣는다).
  E-WD-13  준비의 탈퇴는 PC 가 API 로(E-AUTH-09 와 같은 길), 앱은 새 로그인만 한다 — "정말 영구 삭제" 를 누르지 않는다(14 · 15 도 같다).
  E-WD-16  지시서의 "정지 화면 글자 버튼(A5)" 이 아니라 시나리오대로 설정 → 최종 시트를 연 뒤 PC 가 정지를 건다. 서버 탈퇴 관문은 로그인만 본다(get_caller)
           — 정지여도 받아 무기한으로 막는다. 앱은 성공(200)이라 02 + "탈퇴한 계정이에요".
  E-WD-18  시나리오는 "02 + 탈퇴한 계정이에요" 인데 코드로는 그 알림이 안 나온다 — PC 의 첫 탈퇴가 그 사람의 로그인을 모두 끊고(logout scope=global),
           앱의 두 번째 요청은 서버 관문(current_user.py)에서 GoTrue /user 가 끊긴 세션을 거절해 탈퇴 표시 없는 401(세션 만료)이 된다. 앱은 토큰을 새로 받으려다
           실패해 로그아웃하고 02 에 "세션이 만료됐어요, 다시 로그인해 주세요" 를 띄운다. withdraw_view_model 의 "이미 탈퇴됨 = 성공" 은 401 + withdrawn 표시가
           와야 타는 길이라 로그아웃이 실패했을 때만 닿는다. 그래서 PC 가 첫 탈퇴 뒤 GoTrue /user 를 직접 물어 끊겼으면 세션 만료 알림을, 살아 있으면
           탈퇴 알림을 기대값으로 쓴다(어느 쪽이었는지 메모에 남긴다). 재가입 제한 행 · withdrawn_at 은 두 경우 다 첫 값 그대로다.
  E-EDGE-20  force-stop 은 쓰지 않는다(앱을 "멈춘 앱" 으로 만들어 FCM 이 끊긴다 — tools.Run.phone 주석). 앱이 누른 직후 기다리지 않는 멈춤 말(step)을 보내면
           PC 가 pidof 로 프로세스를 찾고 0.3초를 채운 뒤 `run-as … kill -9`(debug 빌드)로 죽인다. Run.phone 은 midway 뒤에 앱의 결과를 기다리므로(죽은 앱은
           답이 없다) 죽인 뒤 _Killed 를 던져 그 기다림을 건너뛴다 — 하네스 · 앱 lib 은 고치지 않는다. 그다음 SETTLE 초 쉬고 서버 상태를 읽어 앱을 저장된
           세션 그대로 다시 켠다(phase=after). 판정: withdrawn 이면 02 · 홈 0번 · 재가입 제한 새 행 1, 알림은 E-WD-18 과 같은 이유로 로그인이 끊겼으면
           "세션이 만료됐어요…", 살아 있으면 "탈퇴한 계정이에요" — 또는 없음(앱이 응답을 받고 스스로 로그아웃까지 한 뒤 죽었으면 알림은 프로세스와 같이
           사라진다). active 면 홈 · 02 0번 · 알림 없음 · 새 제한 행 0. 다시 켠 앱이 답한 뒤 상태를 한 번 더 읽어 바뀌었으면(늦게 닿은 탈퇴) blocked.
           0.3초는 "누름 말을 PC 가 받은 때" 부터 잰다 — 앱이 누른 때와는 우편함 왕복(수십 ms)만큼 다르다. 실제 kill 까지 걸린 ms 를 메모에 남긴다.

유료 호출(OpenAI · Vision) — 9개 모두 0. 탈퇴(account/router.py) · 정리 배치(account/batch_router.py · heart_tasks/cleanup.py) · 재가입 훅
(auth_hooks/router.py · signup_policy.py) · 로그인 관문(student_verification/current_user.py) · 일시중지(cards/router.py) 어디에도 없다
(test_area5_wd.PaidFactsTest 가 고정). 계정 공장의 홈 계정 온보딩(사진 Vision 2 · 임베딩)은 02 · 04 · 13 · 16 · 18 · EDGE-20 이 같고 이 문으로 막지 않는다.
디스코드 — 9개 모두 0줄. 세 길(POST /reports · /heart-tasks/{task}/submissions · /student-verification)을 부르지 않는다.
"""

import functools
import random
import time
import urllib.parse
import uuid
from datetime import datetime, timedelta, timezone

from e2e import area1, area2, tools
from e2e.area1 import Check, _api, _app, _at, _detail, _find_user, _no_user, _one, _rows, _signed_up
from e2e.area1_b2 import REJOIN_BLOCKED, _blocks, _new_block, _two_months_after
from e2e.area2_phone3 import _wait_for
from e2e.area3_phone import MISSING
from e2e.area3_phone5 import _batch, _single_shot, _start
from e2e.area5_act import _set, _write
from e2e.area5_read import _home, _signup_blocks, _unchanged
from e2e.tools import Blocked

WITHDRAWN = '탈퇴한 계정이에요'  # core/errors.py ACCOUNT_WITHDRAWN · failure.dart WithdrawnFailure
EXPIRED = '세션이 만료됐어요, 다시 로그인해 주세요'  # core/errors.py SESSION_EXPIRED · failure.dart SessionExpiredFailure
LOGIN_MS = 5000  # 누른 뒤 02 까지 — 시나리오 3초 + 로그아웃 뒤 스플래시를 붙잡는 2초(splash_hold.dart)
TOLERANCE = timedelta(seconds=60)  # 시나리오 ±1분. 누른 시각은 폰 시계다(E-AUTH-07 과 같다)
KEPT_AGE = timedelta(days=29)  # E-WD-12 — 30일(batch_router.py WITHDRAWN_RETENTION) 하루 전
GONE_AGE = timedelta(days=31)  # E-WD-11 상태(14 · 15 의 준비) — 30일 하루 뒤
APP_WAIT = 180  # Run.phone 이 앱의 말 하나를 기다리는 초(기본값)
BATCH_WAIT = 120  # 정리 배치가 돌기를 DB 로 기다리는 초 — area1_b2 · area3_phone5 와 같은 "2분"
PAUSE_WAIT = 10  # 앱 토글은 서버 응답 전에 먼저 바뀐다 — 저장이 끝나기를 기다리는 초(area4_set2 GONE_WAIT 와 같다)
KILL_AFTER = 0.3  # 시나리오 EDGE-20 "0.3초 뒤"
SETTLE = 5  # 죽인 뒤 서버가 받은 탈퇴를 마칠 시간 — 그 뒤 상태를 읽는다
ROOM = 300  # 시간 상한의 준비 몫(계정 · 링크 · 앱 켜기 앞뒤 · gcloud) — area2_time_device 와 같은 값


def _now():
    return datetime.now(timezone.utc)


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _withdraw_once(run, account):
    """PC 가 API 로 탈퇴 — 이번 실행이 만든 계정만, 한 번만."""
    area2._guard(run, account['id'])
    reply = _api(run, 'POST', '/account/withdraw', account['token'], **area2._ONCE)
    if reply[0] >= 300:
        raise Blocked(f'탈퇴 {reply[0]} {_detail(reply[1])}')


def _state(run, account):
    return _one(run, f"profiles?id=eq.{account['id']}&select=status,withdrawn_at,matching_paused")


def _tokens(run, account):
    return _rows(run, f"push_tokens?profile_id=eq.{account['id']}&select=token")


def _files(run, bucket, account):
    """[bucket] 의 `{id}/` 아래 파일 — 목록을 못 읽으면 blocked(storage_paths 는 SystemExit 라 그대로 두면 묶음 전체가 멈춘다)."""
    try:
        return sorted(tools.storage_paths(run.cfg, run.key, bucket, account['id']))
    except SystemExit as error:
        raise Blocked(f'{bucket} 목록을 못 읽음: {error}') from None


def _plant_file(run, account, bucket):
    """[bucket] 의 `{id}/` 아래 그림 한 장(서비스 키) — 뒷정리가 `{id}/` 를 비운다."""
    area2._guard(run, account['id'])
    path = f"{account['id']}/e2e-wd-{uuid.uuid4().hex}.png"
    key = {'apikey': run.key, 'Authorization': f'Bearer {run.key}'}
    sent = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/storage/v1/object/{bucket}/{path}", key, raw=(tools.PHOTO.read_bytes(), 'image/png'))
    if sent[0] >= 300:
        raise Blocked(f'준비: {bucket} 에 그림 넣기 {sent[0]} {sent[1]}')
    return path


def _plant_token(run, account):
    """가짜 기기 토큰 한 행 — 탈퇴가 지우는지 본다(기기 알림 권한 없이도 행이 있다)."""
    area2._insert(run, 'push_tokens', [{'token': f'e2e-wd-{uuid.uuid4().hex}', 'profile_id': account['id'], 'platform': 'android'}],
                  account['id'])


def _block_path(email_hmac):
    return f"signup_blocks?email_hmac=eq.{urllib.parse.quote(email_hmac)}"


def _block_row(run, email_hmac):
    rows = _rows(run, f'{_block_path(email_hmac)}&select=blocked_until')
    return rows[0] if rows else None


def _expire(run, account, email_hmac):
    """[account] 의 탈퇴로 생긴 재가입 제한을 어제 끝난 것으로 옮긴다(시간 조작은 DB 시각 칸만)."""
    area2._guard(run, account['id'])
    yesterday = _now() - timedelta(days=1)
    status, body = tools.rest(run.cfg, run.key, 'PATCH', _block_path(email_hmac), {'blocked_until': yesterday.isoformat()})
    if status >= 300:
        raise Blocked(f'준비: 재가입 제한 옮기기 {status} {body}')
    row = _block_row(run, email_hmac)
    if not row or row['blocked_until'] == 'infinity' or _at(row['blocked_until']) > _now():
        raise Blocked(f'준비: 재가입 제한을 어제로 못 옮김 — 읽은 값 {row}')


def _cleanup_ran(run):
    """확인용 재가입 제한 행(어제 끝남 · 무작위 HMAC — 실제 행과 겹칠 수 없다)을 넣고 정리 배치를 부른 뒤 그 행이 지워지기를 기다린다.
    넣은 행이 안 보이면 배치를 부르기 전에, 안 지워지면 배치가 안 돈 것이라 blocked. 확인용 행은 어떻게 끝나든 지운다 — 넣기도 try 안이다
    (행은 들어갔는데 답이 끊겨 재전송이 409 거나 끊김이 그대로 올라와도 지운다)."""
    sentinel = f'\\x{random.getrandbits(256):064x}'
    try:
        status, body = tools.rest(run.cfg, run.key, 'POST', 'signup_blocks',
                                  [{'email_hmac': sentinel, 'blocked_until': (_now() - timedelta(days=1)).isoformat(), 'key_version': 1}])
        if status >= 300:
            raise Blocked(f'확인용 재가입 제한 행 넣기 {status} {body}')
        if _block_row(run, sentinel) is None:
            raise Blocked('넣은 확인용 재가입 제한 행이 안 보인다 — "지워졌다" 가 배치가 돈 증거가 못 된다')
        _batch('cleanup')
        if not _wait_for(lambda: _block_row(run, sentinel) is None, BATCH_WAIT):
            raise Blocked(f'정리 배치 뒤 {BATCH_WAIT}초가 지나도 확인용 재가입 제한 행이 남음 — 배치가 안 돌았거나 늦음')
    finally:
        tools.rest(run.cfg, run.key, 'DELETE', _block_path(sentinel))


def _cleaned_away(run):
    """E-WD-11 을 마친 메일 — 탈퇴(API 한 번) → withdrawn_at 31일 전 → 정리 배치 → auth 사용자가 사라질 때까지. → (계정, 그 메일의 재가입 제한 행)."""
    account = run.account('basic')
    before = _blocks(run)
    _withdraw_once(run, account)
    block, added = _new_block(run, before)
    if block is None:
        raise Blocked(f'준비: 탈퇴로 생긴 재가입 제한 행을 못 가림({added}행)')
    _write(run, account, {'withdrawn_at': (_now() - GONE_AGE).isoformat()})
    _batch('cleanup')
    if not _wait_for(lambda: _find_user(run, account['email']) is None, BATCH_WAIT):
        raise Blocked(f'정리 배치 뒤 {BATCH_WAIT}초가 지나도 31일 전 탈퇴한 계정의 auth 사용자가 남음 — 배치가 안 돌았거나 늦음')
    return account, block


def _sessions_cut(run, account):
    """탈퇴가 이 사람의 로그인을 모두 끊었는지(account/router.py ③ logout scope=global) — 서버 관문(current_user.py)이 묻는 GoTrue /user 를 PC 토큰으로
    똑같이 묻는다. 200 이 아니면 끊긴 것이고, 그 세션의 요청은 탈퇴 표시 없는 401(세션 만료)이 된다."""
    status = tools.call('GET', f"{run.cfg['SUPABASE_URL']}/auth/v1/user",
                        {'apikey': run.cfg['SUPABASE_ANON_KEY'], 'Authorization': f"Bearer {account['token']}"})[0]
    if status >= 500 or status == 429:
        raise Blocked(f'GoTrue /user {status} — 로그인이 끊겼는지 모른다')
    return status != 200


# ── 판정 ─────────────────────────────────────────────────────────────────────────────────────────────

def _notice(check, said, want):
    got = said.get('notice', MISSING)
    check.that(got == want, f'02 알림 {got!r}(기대 {want!r})')


def _reached_login(check, said, limit=None):
    ms = said.get('login_ms')
    if limit is None:
        check.that(isinstance(ms, int), f'누른 뒤 02(로그인 화면) 도착 {ms}(기대 닿음)')
    else:
        check.that(isinstance(ms, int) and ms <= limit, f'누른 뒤 02 까지 {ms}ms(기대 {limit}ms 안 — 시나리오 3초 + 스플래시 2초)')


def _tapped(check, said):
    at = said.get('tapped_at')
    check.that(isinstance(at, str), f'앱이 누른 시각 tapped_at {said.get("tapped_at", MISSING)}(기대 UTC 시각)')
    return _at(at) if isinstance(at, str) else None


def _withdrawn(check, run, account, before, tapped, forever=False):
    """탈퇴됐다 — status · withdrawn_at(누른 시각 ±1분) · 새 재가입 제한 한 행(누른 시각 + 2개월 ±1분, 정지 중이면 infinity). 그 행을 돌려준다."""
    row = _state(run, account)
    check.that(row.get('status') == 'withdrawn', f"status {row.get('status')!r}(기대 withdrawn)")
    at = row.get('withdrawn_at')
    if tapped and at:
        gap = abs((_at(at) - tapped).total_seconds())
        check.that(gap <= TOLERANCE.total_seconds(), f'withdrawn_at {at} — 누른 시각과 {gap:.0f}초 차이(기대 ±60초)')
    block, added = _new_block(run, before)
    check.that(block is not None, f'새 재가입 제한 {added}행(기대 1행)')
    if block and forever:
        check.that(block['blocked_until'] == 'infinity', f"blocked_until {block['blocked_until']}(기대 infinity — 정지 중 탈퇴)")
    elif block and tapped:
        until = block['blocked_until']
        gap = abs((_at(until) - _two_months_after(tapped)).total_seconds()) if until != 'infinity' else float('inf')
        check.that(gap <= TOLERANCE.total_seconds(), f'blocked_until {until} — 누른 시각 + 2개월과 {gap:.0f}초 차이(기대 ±60초)')
    return block


# ── E-WD-02 일시중지 ─────────────────────────────────────────────────────────────────────────────────

def p_wd_02(run, phone):
    check = Check()
    account, token = _home(run)
    if _state(run, account).get('matching_paused') is not False:
        _set(run, account, '매칭 켜 두기(matching_paused=false)', matching_paused=False)
    blocks = _signup_blocks(run)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('sheet_closed') is True, f"\"일시중지\" 뒤 1차 시트 닫힘 {said.get('sheet_closed', MISSING)}(기대 True)")
    check.that(said.get('toggle_on') is False, f"설정의 \"매칭 활성화\" 토글 {said.get('toggle_on', MISSING)}(기대 꺼짐 False)")
    paused = _wait_for(lambda: _state(run, account).get('matching_paused') is True, PAUSE_WAIT)
    check.that(paused, f'DB matching_paused {_state(run, account).get("matching_paused")!r}(기대 true)')
    _unchanged(run, account, check, blocks, '일시중지')
    return check.result()


# ── E-WD-04 영구 삭제 ────────────────────────────────────────────────────────────────────────────────

def p_wd_04(run, phone):
    check = Check()
    account, token = _home(run)
    _plant_token(run, account)
    _plant_file(run, account, 'student-id-temp')
    if not _tokens(run, account) or not _files(run, 'student-id-temp', account):
        raise Blocked('준비: 넣은 푸시 토큰 · 학생증 임시 파일이 안 보인다 — "0개가 됐다" 가 증거가 못 된다')
    before = _blocks(run)
    said = _app(check, phone(token_hash=token))
    _notice(check, said, WITHDRAWN)
    _reached_login(check, said, LOGIN_MS)
    check.that(said.get('notice_gone') is True, f"알림이 3초 뒤 사라짐 {said.get('notice_gone', MISSING)}(기대 True — 한 번만)")
    check.that(said.get('reentered') is True, f"02 에 다시 들어가기 {said.get('reentered', MISSING)}(기대 True — 못 들어가면 \"안 뜸\" 이 증거가 못 된다)")
    again = said.get('notice_again', MISSING)
    check.that(again is None, f'다시 들어간 02 의 알림 {again!r}(기대 없음)')
    _withdrawn(check, run, account, before, _tapped(check, said))
    tokens = _tokens(run, account)
    check.that(not tokens, f'push_tokens {len(tokens)}행(기대 0)')
    files = _files(run, 'student-id-temp', account)
    check.that(not files, f'student-id-temp/{{id}}/ 파일 {len(files)}개(기대 0)')
    return check.result(f"02 까지 {said.get('login_ms')}ms(시나리오 3초 + 스플래시 2초까지 허용)")


# ── E-WD-12 29일째 ───────────────────────────────────────────────────────────────────────────────────

def wd_12(run):
    _start(job='cleanup')
    check = Check()
    account = run.account('basic')
    _withdraw_once(run, account)
    _write(run, account, {'withdrawn_at': (_now() - KEPT_AGE).isoformat()})
    at = _state(run, account).get('withdrawn_at')
    if not at or abs(_at(at) - (_now() - KEPT_AGE)) > timedelta(minutes=1):
        raise Blocked(f'준비: withdrawn_at 을 29일 전으로 못 옮김 — 읽은 값 {at}')
    for bucket in tools.BUCKETS:
        _plant_file(run, account, bucket)
    before = {bucket: _files(run, bucket, account) for bucket in tools.BUCKETS}
    if not all(before.values()):
        raise Blocked(f'준비: 넣은 파일이 안 보이는 버킷 {[b for b, f in before.items() if not f]}')
    _cleanup_ran(run)
    check.that(_find_user(run, account['email']) is not None, '29일째인데 auth 사용자가 지워짐(기대 남음)')
    row = _state(run, account)
    check.that(row.get('status') == 'withdrawn', f"profiles 행 {row or '없음'}(기대 탈퇴 상태로 남음)")
    for bucket in tools.BUCKETS:
        after = _files(run, bucket, account)
        check.that(after == before[bucket], f'{bucket}/{{id}}/ 파일 {len(before[bucket])}→{len(after)}개(기대 그대로)')
    return check.result('deleted_accounts 는 스케줄러 호출이라 못 읽음 — 확인용 제한 행이 지워진 것으로 배치가 돈 것을 보고 auth 사용자 · 행 · 파일을 봤다')


# ── E-WD-13 탈퇴 뒤 로그인 ───────────────────────────────────────────────────────────────────────────

def p_wd_13(run, phone):
    check = Check()
    account = run.account('home')
    _withdraw_once(run, account)
    if _state(run, account).get('status') != 'withdrawn' or _find_user(run, account['email']) is None:
        raise Blocked('준비: 탈퇴 상태 + auth 사용자 남음이 아니다')
    said = _app(check, phone(token_hash=run.link(account['email'])))  # 탈퇴 뒤 새 로그인 — 첫 탈퇴가 끊은 세션과 다른 새 세션
    _notice(check, said, WITHDRAWN)
    check.that(said.get('login_seen') is True, f"02(로그인 화면) {said.get('login_seen', MISSING)}(기대 닿음)")
    check.that(said.get('home_seen') is False, f"홈 화면이 보인 적 {said.get('home_seen', MISSING)}(기대 0번)")
    return check.result(f"로그인 뒤 알림까지 {said.get('notice_ms')}ms")


# ── E-WD-14 · 15 재가입 ───────────────────────────────────────────────────────────────────────────────

def p_wd_14(run, phone):
    _start(job='cleanup')
    check = Check()
    account, _ = _cleaned_away(run)
    said = _app(check, phone(email=account['email']))
    error = said.get('error', MISSING)
    check.that(error == REJOIN_BLOCKED, f'02 의 거절 문구 {error!r}(기대 {REJOIN_BLOCKED!r})')
    check.that(said.get('code_screen') is False, f"03(코드 화면) {said.get('code_screen', MISSING)}(기대 안 감)")
    _no_user(run, account['email'], check)  # 생겼으면 문제로 적고 바로 지운다
    return check.result()


def p_wd_15(run, phone):
    _start(job='cleanup')
    check = Check()
    account, block = _cleaned_away(run)
    _expire(run, account, block['email_hmac'])
    said = _app(check, phone(email=account['email']))
    if _block_row(run, block['email_hmac']) is None:
        raise Blocked('앱이 묻기 전 · 묻는 사이에 끝난 제한 행이 먼저 지워짐(예약 정리 배치?) — ① 을 판정 못 함')
    check.that(said.get('code_screen') is True, f"① 03(코드 화면) {said.get('code_screen', MISSING)}(기대 감 — 끝난 제한은 막지 않는다)")
    error = said.get('error', MISSING)
    check.that(error is None, f'① 02 칸 아래 빨간 글자 {error!r}(기대 없음)')
    user = _signed_up(run, account['n'], account['email'], check)  # 새 auth 사용자 — 뒷정리 목록에 적는다
    check.that(not user or user['id'] != account['id'], '① 새 auth 사용자가 지워진 사람과 같은 id')
    if check.problems:
        return check.result()  # ① 이 안 되면 ② 를 위해 운영 배치를 또 부르지 않는다
    _batch('cleanup')
    gone = _wait_for(lambda: _block_row(run, block['email_hmac']) is None, BATCH_WAIT)
    check.that(gone, f'② 정리 배치 뒤 {BATCH_WAIT}초가 지나도 끝난 재가입 제한 행이 남음(기대 0행)')
    return check.result('deleted_signup_blocks 는 스케줄러 호출이라 못 읽음 — 그 행이 지워진 것으로 봤다. ① 에 실제 메일 1통이 나간다(읽지 않음)')


# ── E-WD-16 · 18 최종 시트에서 멈춘 사이 ──────────────────────────────────────────────────────────────

def p_wd_16(run, phone):
    _start(job='cleanup')
    check = Check()
    account, token = _home(run)
    before = _blocks(run)
    suspended = []

    def suspend(said):
        """앱이 최종 시트를 연 채 멈춘 사이 — 앱은 모르는 정지."""
        _set(run, account, '정지(status=suspended)', status='suspended')
        suspended.append(True)
    said = _app(check, phone(token_hash=token, midway=suspend))
    check.that(bool(suspended), '앱이 최종 시트에서 멈추지 않고 끝남 — 정지를 못 걸었다')
    _notice(check, said, WITHDRAWN)
    _reached_login(check, said)
    check.that(said.get('normal_sheet') is True, f"앱이 연 최종 시트가 일반 \"정말 삭제할까요?\" {said.get('normal_sheet', MISSING)}(기대 True — 정지를 모른다)")
    block = _withdrawn(check, run, account, before, _tapped(check, said), forever=True)
    if not block or block['blocked_until'] != 'infinity':
        return check.result()  # 무기한 행이 없으면 정리 배치에서 볼 것이 없다 — 운영 배치를 부르지 않는다
    _cleanup_ran(run)
    left = _block_row(run, block['email_hmac'])
    check.that(left == {'blocked_until': 'infinity'}, f'정리 배치 뒤 무기한 제한 행 {left}(기대 infinity 그대로)')
    return check.result()


def p_wd_18(run, phone):
    check = Check()
    account, token = _home(run)
    before = _blocks(run)
    first = {}

    def withdraw_first(said):
        """앱이 최종 시트를 연 채 멈춘 사이 — PC 가 같은 계정으로 먼저 탈퇴(첫 응답을 앱이 못 받은 것과 같다)."""
        _withdraw_once(run, account)
        first.update(blocks=_blocks(run), state=_state(run, account), cut=_sessions_cut(run, account))
    said = _app(check, phone(token_hash=token, midway=withdraw_first))
    if not first:
        check.that(False, '앱이 최종 시트에서 멈추지 않고 끝남 — PC 가 먼저 탈퇴하지 못했다')
        return check.result()
    added = [key for key in first['blocks'] if key not in before]
    if len(added) != 1 or first['state'].get('status') != 'withdrawn':
        raise Blocked(f"준비: PC 의 첫 탈퇴 — 새 제한 {len(added)}행 · status {first['state'].get('status')!r}")
    _notice(check, said, EXPIRED if first['cut'] else WITHDRAWN)
    _reached_login(check, said)
    check.that(_blocks(run) == first['blocks'], '두 번째 누름 뒤 signup_blocks 행 수 · blocked_until 이 첫 값과 다름(기대 그대로)')
    now_state = _state(run, account)
    check.that(now_state == first['state'], f"두 번째 누름 뒤 status · withdrawn_at {now_state}(기대 첫 값 {first['state']})")
    why = ('첫 탈퇴가 로그인을 모두 끊어(GoTrue /user 거절) 두 번째 누름은 탈퇴 표시 없는 401 — 세션 만료 알림이 맞다' if first['cut']
           else '첫 탈퇴 뒤에도 로그인이 살아 있어(logout 실패) 두 번째 누름은 401 + withdrawn — 탈퇴 알림이 맞다')
    return check.result(f"{why}(시나리오는 탈퇴 알림). 앱 알림 {said.get('notice')!r}")


# ── E-EDGE-20 누른 직후 강제 종료 ────────────────────────────────────────────────────────────────────

class _Killed(Exception):
    """앱 프로세스를 죽였다 — Run.phone 은 midway 뒤에 앱의 결과를 기다리는데 죽은 앱은 답이 없다. 그 기다림을 건너뛰려고 던지고
    가설이 받는다(하네스를 고치지 않는다). args[0] = 누름 말을 받고 kill 을 보낼 때까지 걸린 ms."""


def _kill_soon(phone, after=KILL_AFTER):
    """앱이 누른 직후 보낸 멈춤 말(답을 안 기다린다)에 — pidof 를 읽고 [after]초(기본 0.3)를 채운 뒤 run-as kill -9(debug 빌드). force-stop 은 쓰지 않는다."""
    def kill(said):
        start = time.monotonic()
        pid = tools.adb(phone.serial, 'shell', 'pidof', tools.PACKAGE, check=False).strip()
        if not pid:
            raise Blocked('누른 뒤 앱 프로세스를 못 찾음(pidof) — 죽일 수 없다')
        time.sleep(max(0.0, after - (time.monotonic() - start)))
        for _ in range(10):
            tools.adb(phone.serial, 'shell', 'run-as', tools.PACKAGE, 'kill', '-9', pid, check=False)
            killed = round((time.monotonic() - start) * 1000)
            pid = tools.adb(phone.serial, 'shell', 'pidof', tools.PACKAGE, check=False).strip()
            if not pid:
                raise _Killed(killed)
            time.sleep(0.5)
        raise Blocked('앱 프로세스가 안 죽음(run-as kill — debug 빌드인가)')
    return kill


def p_edge_20(run, phone):
    check = Check()
    account, token = _home(run)
    before = _blocks(run)
    try:
        said = phone(token_hash=token, phase='press', midway=_kill_soon(phone))
    except _Killed as killed:
        ms = killed.args[0]
    else:
        _app(check, said)
        check.that(False, '앱이 누른 뒤 멈추지 않고 끝남 — 죽일 때를 못 잡음')
        return check.result()
    time.sleep(SETTLE)
    status = _state(run, account).get('status')
    if status not in ('active', 'withdrawn'):
        raise Blocked(f'죽인 뒤 계정 상태 {status!r} — active · withdrawn 이 아니다')
    cut = status == 'withdrawn' and _sessions_cut(run, account)
    said = _app(check, phone(phase='after'))
    if _state(run, account).get('status') != status:
        raise Blocked(f'다시 켠 앱을 보는 사이 서버 상태가 바뀜({status} → 다른 값) — 늦게 닿은 탈퇴라 판정 못 함')
    block, added = _new_block(run, before)
    notice = said.get('notice', MISSING)
    if status == 'withdrawn':
        check.that(block is not None, f'탈퇴됐는데 새 재가입 제한 {added}행(기대 1행)')
        check.that(said.get('login_seen') is True, f"다시 켠 앱의 02 {said.get('login_seen', MISSING)}(기대 닿음)")
        check.that(said.get('home_seen') is False, f"다시 켠 앱에 홈이 보인 적 {said.get('home_seen', MISSING)}(기대 0번)")
        allowed = [EXPIRED if cut else WITHDRAWN, None]
        check.that(notice in allowed, f'다시 켠 02 의 알림 {notice!r}(기대 {allowed[0]!r} 또는 없음)')
    else:
        check.that(added == 0, f'탈퇴 안 됐는데 새 재가입 제한 {added}행(기대 0)')
        check.that(said.get('home_seen') is True, f"다시 켠 앱의 홈 {said.get('home_seen', MISSING)}(기대 닿음)")
        check.that(said.get('login_seen') is False, f"다시 켠 앱에 02 가 보인 적 {said.get('login_seen', MISSING)}(기대 0번)")
        check.that(notice is None, f'다시 켠 앱의 알림 {notice!r}(기대 없음)')
    login = f" · 로그인 {'끊김' if cut else '살아 있음'}" if status == 'withdrawn' else ''
    return check.result(f'누름 말을 받고 {ms}ms 에 kill · 서버 {status}{login} · 알림 {notice!r}')


# 소셜 로그인 전환(20261008)으로 14 · 15 의 전제가 둘 다 깨졌다 — 지우지 않고 막아 둔다(번호 그대로, 판정은 남겨 둔다).
REJOIN_ON_02_BLOCKED = ('소셜 로그인 전환으로 의미 변경, 대체 가설 필요 — 02 는 이제 로그인한 계정의 학교 메일 인증이라 로그아웃 상태에서 '
                        '탈퇴한 메일을 넣을 수 없고, 공장 계정(email 방식 + 프로필 직접 생성)은 school_email_claims 가 없어 탈퇴가 '
                        '재가입 제한 행을 남기지 않는다(account/router.py withdraw)')
REJOIN_ON_02 = False  # 대체 가설(claims 있는 계정 · 02 로 보내는 needs_school_email 계정)이 생기면 켠다


def _rejoin_on_02(case):
    """막혀 있으면 계정 · 탈퇴 · 운영 정리 배치 · 앱 모두 전에 blocked."""
    @functools.wraps(case)
    def guarded(run, *args):
        if not REJOIN_ON_02:
            raise Blocked(REJOIN_ON_02_BLOCKED)
        return case(run, *args)
    return guarded


PHONE = {
    'E-WD-02': p_wd_02, 'E-WD-04': p_wd_04, 'E-WD-13': p_wd_13,
    'E-WD-14': _rejoin_on_02(_single_shot(p_wd_14)), 'E-WD-15': _rejoin_on_02(_single_shot(p_wd_15)),
    'E-WD-16': _single_shot(p_wd_16), 'E-WD-18': p_wd_18, 'E-EDGE-20': p_edge_20,
}
CASES = {'E-WD-12': _single_shot(wd_12)}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area5-wd'] = ['E-WD-02', 'E-WD-04', 'E-WD-12', 'E-WD-13', 'E-WD-14', 'E-WD-15', 'E-WD-16', 'E-WD-18', 'E-EDGE-20']
# 시간 상한 = 최악 대기(앱의 말 하나 APP_WAIT · 배치 기다림 BATCH_WAIT) + 준비 몫 ROOM. 02 · 04 · 13 은 앱 한 번이라 기본 420초.
tools.CASE_LIMITS.update({
    'E-WD-14': BATCH_WAIT + APP_WAIT + ROOM,  # 정리 배치 → 앱
    'E-WD-15': 2 * BATCH_WAIT + APP_WAIT + ROOM,  # 정리 배치 → 앱 → 정리 배치
    'E-WD-16': 2 * APP_WAIT + BATCH_WAIT + ROOM,  # 멈춤 · 결과 → 정리 배치
    'E-WD-18': 2 * APP_WAIT + ROOM,  # 멈춤 · 결과
    'E-EDGE-20': 2 * APP_WAIT + SETTLE + ROOM,  # 누름(죽임) → 다시 켬
})
