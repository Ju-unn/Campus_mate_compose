"""영역 1 묶음 4 — 아바타(04-3 작업 등록 · 05-12 결과 화면 · 5회 실패 보상 · 중복 누름).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b4.dart 의 같은 번호.

운영 비용(Cloud Tasks · OpenAI)이 나가는 가설은 둘뿐이다 — E-ONB-24 · 41 이 실제 생성 한 번씩.
나머지는 아바타 행(만드는 중 · 실패)을 이 실행의 +e2e 계정에 DB 로 넣어 화면 · API 를 본다.
작업이 등록되는 가설(36 · 38 · 39 · 40)은 계정의 원본 사진 파일을 깨진 파일로 바꿔 둬 워커가 OpenAI 를 부르기 전에 형식 검사에서 실패하게 한다.
쓰기는 전부 이 실행이 만든 계정의 행 · 파일뿐이다(스키마 변경 0).
"""

import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from e2e import area1, tools
from e2e.area1 import Check, _api, _app, _one, _patch, _rows, _signed_in
from e2e.area1_b3 import _allow_notifications, _photos, _push
from e2e.tools import Blocked

ALREADY = '아바타는 한 번만 만들 수 있어요'  # errors.AVATAR_ALREADY_CREATED
GENERATE = '/profile-onboarding/avatar/generate'
BROKEN = b'E2E broken avatar source'  # 매직바이트가 없어 워커가 형식을 못 알아본다(avatars.py 의 student_id_content_type)
FALLBACK_SOURCE = 'defaults/fallback-avatar.png'  # storage.py _FALLBACK_AVATAR_SOURCE_PATH — avatars 버킷 안
FALLBACK_HEARTS = 10
WAIT_TURNS, WAIT_SECONDS = 30, 10  # 실제 생성은 1분쯤 — 5분까지 기다린다

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-ONB-33': '묶음 2 에 이미 있다(만드는 중 행을 완성으로 바꿔 "아바타가 완성됐어요" → 06-1)',
    'E-ONB-42': '사람 필요 — OpenAI 장애는 운영에서 못 낸다(E-ONB-38 의 깨진 파일 방식으로 대신 확인)',
}


def _fnv(data):
    """FNV-1a 32비트 — 앱(area1_b4.dart `_fnv`)과 같은 식. 올린 파일이 바뀌지 않고 저장됐는지 순서까지 대조한다."""
    h = 0x811C9DC5
    for byte in data:
        h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
    return f'{h:08x}'


def _download(run, bucket, path):
    request = urllib.request.Request(f"{run.cfg['SUPABASE_URL']}/storage/v1/object/{bucket}/{path}",
                                     headers={'apikey': run.key, 'Authorization': f'Bearer {run.key}'})
    with urllib.request.urlopen(request, timeout=30) as reply:
        return reply.read()


def _avatars(run, account_id):
    return _rows(run, f'profile_avatars?profile_id=eq.{account_id}&order=created_at&select=status,is_fallback')


def _bonus(run, account_id):
    """5회 실패 보상 하트(reason=admin_adjust)."""
    return [r['amount'] for r in _rows(run, f'heart_transactions?profile_id=eq.{account_id}&reason=eq.admin_adjust&select=amount')]


def _count(rows, status, fallback=None):
    return sum(r['status'] == status and (fallback is None or r['is_fallback'] == fallback) for r in rows)


# ── 계정 · 아바타 행 준비(이 실행의 계정만) ───────────────────────────────────────────────────────


def _pending(run, account, minutes_ago=0):
    """만드는 중 행 하나. [minutes_ago] 분 전에 만든 것으로 시각을 옮길 수 있다."""
    status, body = run._avatar(account, 'pending')
    if status >= 300:
        raise Blocked(f'아바타 만드는 중 행 넣기 {status} {body}')
    if minutes_ago:
        created = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
        _patch(run, f"profile_avatars?profile_id=eq.{account['id']}&status=eq.pending", {'created_at': created})


def _failed(run, account, count):
    status, body = tools.rest(run.cfg, run.key, 'POST', 'profile_avatars',
                              [{'profile_id': account['id'], 'status': 'failed', 'storage_path': None}] * count)
    if status >= 300:
        raise Blocked(f'아바타 실패 행 넣기 {status} {body}')


def _break_source(run, account):
    """원본 사진 파일을 깨진 파일로 바꾼다 — 워커가 OpenAI 를 부르기 전에 실패한다. 이 계정 폴더의 파일만."""
    path = _one(run, f"profile_photos?profile_id=eq.{account['id']}&is_avatar_source=eq.true&select=storage_path").get('storage_path')
    if not path or not path.startswith(f"{account['id']}/"):
        raise Blocked(f'원본 사진 경로를 못 찾음({path})')
    status, body = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/storage/v1/object/profile-photos/{path}",
                              {'apikey': run.key, 'Authorization': f'Bearer {run.key}', 'x-upsert': 'true'}, raw=(BROKEN, 'image/jpeg'))
    if status >= 300:
        raise Blocked(f'원본 사진 바꾸기 {status} {body}')


# ── 04-2 → 04-3 → 04-4 ──────────────────────────────────────────────────────────────────────────


def _register(run, phone, check, names):
    """04-2 계정이 [names] 를 골라 04-3 에서 아바타 만들기를 누른다(앱이 한다) → (계정, 앱이 한 말)."""
    _photos(run, *names)
    account = run.account('kakao')
    _push(phone, run, *names)
    said = _app(check, phone(token_hash=run.link(account['email']), photos=list(names)))
    return account, said


def p_onb_24(run, phone):
    check = Check()
    account, _ = _register(run, phone, check, ['face1.jpg', 'face2.jpg'])
    photos = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=position,is_avatar_source")
    check.that(len(photos) == 2 and sum(p['is_avatar_source'] for p in photos) == 1,
               f'profile_photos {photos} — 2행 · 원본 1행이어야 함')
    avatars = _avatars(run, account['id'])
    check.that(len(avatars) == 1 and avatars[0]['status'] in ('pending', 'ready'),
               f'아바타 행 {avatars} — 1행(만드는 중 또는 완성)이어야 함')
    return check.result()


def p_onb_25(run, phone):
    """3번째 사진을 첫 칸으로 끌면 저장된 position 0 이 그 사진이다(파일 해시로 대조). 앱이 아바타 작업을 막아 둬 비용이 없다."""
    check = Check()
    account, said = _register(run, phone, check, ['face1.jpg', 'face2.jpg', 'face3.jpg'])
    before, after = said.get('before') or [], said.get('hashes') or []
    check.that(len(before) == 3 and len(after) == 3 and after[0] == before[2] and after[2] == before[0],
               f'3번째를 첫 칸으로 끌었는데 앱의 순서가 {before} → {after}')
    photos = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&order=position&select=position,storage_path")
    check.that([p['position'] for p in photos] == [0, 1, 2], f'저장된 자리 {[p["position"] for p in photos]} — 0·1·2 여야 함')
    stored = [_fnv(_download(run, 'profile-photos', p['storage_path'])) for p in photos]
    check.that(stored == after, f'저장된 순서 {stored} ≠ 앱이 정한 순서 {after}')
    check.that(not _avatars(run, account['id']), '유료 아바타 작업이 등록됨(앱이 막아 둔 자리)')
    return check.result()


def _wait_ready(run, account_id, check):
    """워커가 만들어 ready 행이 생기기를 기다린다(5분까지). 실패 행이 생기면 거기서 멈춘다."""
    for turn in range(WAIT_TURNS):
        rows = _avatars(run, account_id)
        if _count(rows, 'ready'):
            return True
        if _count(rows, 'failed'):
            check.that(False, f'워커가 만들다 failed 로 끝남: {rows}')
            return False
        time.sleep(WAIT_SECONDS)
    check.that(False, f'{WAIT_TURNS * WAIT_SECONDS // 60}분이 지나도 완성(ready) 행이 안 생김')
    return False


def p_onb_41(run, phone):
    """만드는 도중 앱이 꺼져도 서버는 계속 만든다 — 앱이 04-4 에 닿은 뒤 PC 가 설문까지 API 로 끝내고 완성을 기다린 다음 앱을 다시 켠다.
    완성 행이 있으면 서버의 다음 단계가 이상형(06-1)이라(onboarding_progress.py 'avatar' 조건 = avatar_ready) 다시 켠 앱은 05-12 가 아니라
    06-1 로 바로 간다 — 시나리오의 "05-12 에서 바로 완성 화면" 과 어긋나는 자리다(PR 본문에 적음)."""
    check = Check()
    account, _ = _register(run, phone, check, ['face1.jpg', 'face2.jpg'])
    rows = _avatars(run, account['id'])
    check.that(len(rows) == 1, f'앱이 04-3 을 넘긴 뒤 아바타 행 {rows} — 1행이어야 함')
    for step in ('appearance', 'interests', 'my_traits', 'survey'):
        run._step(step, account, account['token'])
    if not check.problems and _wait_ready(run, account['id'], check):
        _app(check, phone(fresh=False, expect='06-1'), '다시 켠 뒤')
        rows = _avatars(run, account['id'])
        check.that(_count(rows, 'ready') == 1 and not _count(rows, 'pending'), f'다시 켠 뒤 아바타 행 {rows} — 완성 1 · 만드는 중 0 이어야 함')
    return check.result()


# ── 05-12 결과 화면 ─────────────────────────────────────────────────────────────────────────────


def _at_result(prepare, judge=None, step=None):
    """설문까지 끝낸 계정에 [prepare](run, account) 로 아바타 기록을 만들고 앱을 켠다 — 앱은 05-12 에서 시작한다.
    [step] 이 있으면 앱이 멈춘 사이 PC 가 그것을 부른다. [judge](run, account, check) 는 앱이 끝난 뒤 DB 를 본다."""
    def case(run, phone):
        check = Check()
        account, token = _signed_in(run, 'survey')
        _allow_notifications(phone)
        prepare(run, account)
        midway = (lambda said: step(run, account, check)) if step else None
        _app(check, phone(midway=midway, token_hash=token))
        if judge:
            judge(run, account, check)
        return check.result()
    return case


def _ready_now(run, account, check):
    """E-ONB-34 — PC 가 만드는 중 행을 완성으로 바꾼다(앱이 멈춰 있는 사이)."""
    _patch(run, f"profile_avatars?profile_id=eq.{account['id']}&status=eq.pending", {'status': 'ready'})


def _row_untouched(run, account, check):
    """E-ONB-35 — 상태 조회는 실패로 "보여만" 준다. DB 행은 그대로 만드는 중이어야 한다(고치는 건 POST 다)."""
    rows = _avatars(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['status'] == 'pending', f'결과 화면을 본 뒤 아바타 행 {rows} — 만드는 중 1행 그대로여야 함')


def _one_new_row(run, account, check):
    """E-ONB-36 — 아바타 행이 하나도 없던 계정이 "다시 만들기" 를 누르면 행이 정확히 1개 생긴다(만드는 중, 워커가 빨리 끝내면 실패)."""
    rows = _avatars(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['status'] in ('pending', 'failed'), f'다시 만들기 뒤 아바타 행 {rows} — 1행이어야 함')


def _paid_once(failed_rows):
    """E-ONB-37 · 38 — 실패 [failed_rows] 행 + 기본 아바타 1행, 보상 하트 +10 정확히 1행."""
    def judge(run, account, check):
        rows = _avatars(run, account['id'])
        check.that(_count(rows, 'ready', True) == 1, f'기본 아바타(is_fallback) 행 {_count(rows, "ready", True)}개 — 1개여야 함')
        check.that(_count(rows, 'failed') == failed_rows and not _count(rows, 'pending'), f'아바타 행 {rows} — 실패 {failed_rows} · 만드는 중 0 이어야 함')
        check.that(_bonus(run, account['id']) == [FALLBACK_HEARTS], f'보상 하트 {_bonus(run, account["id"])} — [+{FALLBACK_HEARTS}] 한 번이어야 함')
    return judge


def _registered_without_reward(run, account, check):
    """E-ONB-39 — 앱이 "다시 만들기" 를 누른 바로 뒤: 실패 4행 + 새 만드는 중 1행, 하트 변화 0.
    워커가 먼저 5번째 실패까지 적었으면(깨진 원본이라 빠르다) 그 시각을 놓친 것이라 판정 대신 blocked 다."""
    rows, bonus = _avatars(run, account['id']), _bonus(run, account['id'])
    if _count(rows, 'ready', True):
        raise Blocked(f'워커가 먼저 5번째 실패를 적음(보상 {bonus}) — 보기 전에 끝났다. 다시 돌려 주세요')
    check.that(not bonus, f'보상 하트 {bonus} — 4번 실패 뒤 새로 만들기엔 보상이 없어야 함')
    check.that(_count(rows, 'pending') == 1 and len(rows) == 5, f'다시 만들기 뒤 아바타 행 {rows} — 실패 4 + 만드는 중 1 이어야 함')


def _fallback_source_exists(run):
    """5번째 실패 보상은 avatars 버킷의 [FALLBACK_SOURCE] 를 복사하는 것으로 시작한다. 없으면 행 0개 · 하트 없음으로만 보여
    원인이 안 드러나므로 시작 전에 읽어 본다(읽기만)."""
    folder = FALLBACK_SOURCE.rsplit('/', 1)[0]
    try:
        return FALLBACK_SOURCE in tools.storage_paths(run.cfg, run.key, 'avatars', folder)
    except SystemExit as error:  # storage_paths 는 목록을 못 읽으면 SystemExit
        raise Blocked(f'avatars 버킷 목록을 못 읽어 기본 아바타 원본을 확인하지 못함: {error}') from None


def _needs_fallback_source(prepare):
    def checked(run, account):
        if not _fallback_source_exists(run):
            raise Blocked(f'기본 아바타 원본({FALLBACK_SOURCE})이 운영 버킷에 없음 — 결함 D-02. 5번째 실패 보상이 복사에서 멈춘다')
        prepare(run, account)
    return checked


def _prepare_four_failed_broken(run, account):
    _failed(run, account, 4)
    _break_source(run, account)


# ── 중복 누름 ───────────────────────────────────────────────────────────────────────────────────


def onb_40(run):
    """① 실패 1행 계정이 생성 API 를 동시에 3번 부르면 만드는 중 행은 1개(모두 202) ② 완성된 계정이 부르면 409 · 새 행 0."""
    check = Check()
    mine = run.account('survey')
    _failed(run, mine, 1)
    _break_source(run, mine)
    with ThreadPoolExecutor(3) as pool:
        replies = list(pool.map(lambda _: _api(run, 'POST', GENERATE, mine['token']), range(3)))
    for turn, reply in enumerate(replies, 1):
        check.reply(f'{turn}번째 누름', reply, 202)
    rows = _avatars(run, mine['id'])
    # 깨진 원본이라 워커가 빨리 실패하면 그 뒤 누름이 새 만드는 중 행을 하나 더 만들 수 있다 — 한 번에 만드는 중은 1개뿐이어야 한다.
    check.that(_count(rows, 'pending') == 1 and 2 <= len(rows) <= 4, f'3번 눌렀더니 아바타 행 {rows} — 만드는 중 정확히 1행이어야 함')
    done = run.account('avatar')
    check.reply('완성 뒤 생성', _api(run, 'POST', GENERATE, done['token']), 409, ALREADY)
    rows = _avatars(run, done['id'])
    check.that(len(rows) == 1, f'완성 뒤 눌렀더니 아바타 행 {rows} — 완성 1행 그대로여야 함')
    return check.result()


PHONE = {
    'E-ONB-24': p_onb_24,
    'E-ONB-25': p_onb_25,
    'E-ONB-34': _at_result(_pending, step=_ready_now),
    'E-ONB-35': _at_result(lambda run, account: _pending(run, account, minutes_ago=11), judge=_row_untouched),
    'E-ONB-36': _at_result(_break_source, judge=_one_new_row),
    'E-ONB-37': _at_result(_needs_fallback_source(lambda run, account: _failed(run, account, 5)), judge=_paid_once(5)),
    'E-ONB-38': _at_result(_needs_fallback_source(_prepare_four_failed_broken), judge=_paid_once(5)),
    'E-ONB-39': _at_result(_prepare_four_failed_broken, step=_registered_without_reward),
    'E-ONB-41': p_onb_41,
}
CASES = {'E-ONB-40': onb_40}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area1-b4'] = list(CASES) + list(PHONE)
