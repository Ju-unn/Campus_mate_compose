"""영역 5 폰 A 한 대 — 나 탭에서 아바타를 다시 만들고(E-ME-12 · 13 · 14) 15-7 로 사진을 고쳐 저장하는(38 · 39 · 41 · 42 · 44) 8개(묶음 area5-photo).
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 5-1 표의 그 줄을 지금 코드와 대조한 것이다.
앱 쪽은 frontend/integration_test/area5_photo.dart 의 같은 번호(area5.dart 가 묶는다). 앞의 15개는 area5_act, 화면 읽기 16개는 area5_read 다.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 홈 계정을 만들고 서비스 키 DB 로 준비하면, 앱이 화면을 열어 누르고 본 것을 Map 으로 말하고
(문구는 사람이 읽는 글자 그대로, 못 본 것은 None — 이 쪽은 `MISSING` 과 가른다), 판정은 여기서 한다. 계정은 가설마다 새로 만든다.
쓰기는 이번 실행이 만든 계정에만 한다(`area2._guard`). 탈퇴 · 영구 삭제 버튼은 어디서도 누르지 않는다.

유료 호출 표(서버 코드 근거 — 이 모양이 바뀌면 test_area5_photo.PaidFactsTest 가 걸린다)
  ME-12  OpenAI 0 · Vision 0 · 게이트 없음. 시트의 "하트 충전하기" 는 시트를 닫고 하트 스토어(18, `/hearts/store`)로 간다(my_profile_screen.dart
         `_openRegenSheet` 의 chargeHearts — 예전엔 "곧 열려요" 토스트) — 서버 요청이 없다(스토어가 읽는 하트 과제 목록 GET 은 쓰기가 아니다). 앱이 뷰모델 상태(idle)를, PC 가 DB(아바타 행 · 하트 · 원장 그대로)를 본다.
  ME-13  OpenAI 0 · Vision 0 · 게이트 없음(E-HEART-44 와 같은 402 가설). POST /me/avatar/regenerate 가 402 로 끝나 큐에 안 넣는다(me/router.py:133-137,
         큐 등록은 139). 하트 계산이 어긋나 202 가 되면 그 요청이 곧 유료 호출이라, 새 아바타 행이 생기면 fail 메모에 "유료" 를 적는다.
  ME-14  OpenAI 최대 1 · Vision 0 · 게이트 E2E_REAL_AI=1 + _PAID(없으면 계정도 요청도 없이 blocked, 한 번 나간 뒤에는 다시 안 돎).
         "10 쓰고 만들기" 는 큐에 등록하고(me/router.py:139 → profile_onboarding/router.py:243-249 Cloud Tasks) 워커(tasks_router.py:83 AvatarGenerator)가
         OpenAI 이미지를 부른다. 워커는 행이 pending 이 아니면 부르기 전에 건너뛴다(:61-63). PC 가 새 pending 행을 FLIP_POLL 초마다 보다가 바로 failed 로
         바꾼다 — 워커가 그 전에 행을 읽었다면 1번 나가고(끝에 :93 에서 0행이라 skipped, 하트도 안 빼고 그림도 안 적는다), 워커가 끝까지 먼저면 ready 라 blocked.
  ME-38  OpenAI 0 · Vision 1(새 사진 1장에 한 번, me/router.py:166-171) · 게이트 없음(area1_b3 의 사진 가설도 Vision 에 게이트가 없다).
  ME-39  OpenAI 0 · Vision 0 — 새 파일이 없는 저장은 반복문이 비어 있다.
  ME-41  OpenAI 0 · Vision 0 — 저장 버튼을 안 누른다. 서버 경계 확인 두 번(1칸 · 5칸)은 ①에서 422(:154)라 Vision 앞에서 끝나고 새 파일도 없다.
  ME-42  OpenAI 0 · Vision 0 — 얼굴 판정은 기기 안(ML Kit)이고 저장 버튼을 안 누른다.
  ME-44  OpenAI 0 · Vision 0 — 409(:162)가 Vision 앞에서 끝난다.
  (계정 공장의 온보딩은 사진 2장에 Vision 2번, 임베딩에 OpenAI 를 부른다 — 모든 가설이 같고 이 문으로 막지 않는다.)
디스코드: 이 8개가 부르는 서버 길(GET /me/profile · POST /me/avatar/regenerate · GET avatar/status · PUT /me/photos · 워커)에는 신고(/reports) ·
무료 하트 인증(/heart-tasks/…/submissions) · 학생증(/student-verification) 이 없다 — 가설마다 0줄.

시나리오와 다르게 도는 것(보고의 "확인 필요")
  E-ME-12 · 13 · 14  시나리오의 "ready 2장" 은 계정 공장의 1장에 DB 로 1장을 더한다(area2_phone3._add_avatar — 1장이면 무료 시트, avatar_regen_cost).
                하트는 처음 있던 잔액을 읽어 목표 값(5 · 37)이 되도록 더하거나(free_task) 뺀다(admin_adjust — avatar_regen 원장 0행을 지켜야 해서 이유를 다르게 쓴다).
  E-ME-13       "화면은 37" 은 앱이 나 탭을 연 뒤 `step` 에서 멈추면 PC 가 5로 낮춘다. 시트는 처음 읽은 37 을 들고 있어 "10 쓰고 만들기" 가 나온다.
                앱이 누른 요청은 402 로 끝나고, 앱은 15 의 토스트 "하트가 모자라요"(서버 문구)와 뷰모델 상태(failed · 서버 문구)를 말한다.
  E-ME-14       PC 가 "새 pending 행이 생기면 즉시 failed" 를 하는 방식은 워커와 경쟁이다 — 위 표. 앱은 누르기 직전에 `ready` 에서 멈추고 PC 가 지켜보기를 시작한다.
                15-3 토스트는 서버 문구가 없는 실패(상태 조회가 failed)라 기본 안내 "아바타를 만들지 못했어요.\\n하트는 차감되지 않았어요." 이고, 서버 문구가
                있으면(402 등) 그 문구가 대신 뜬다 — 앱은 뷰모델의 오류 글자도 말해 둘을 가른다. 결과 안내는 상태 조회(5초 주기)가 failed 를 읽은 뒤 뜬다.
  E-ME-38 · 42  15-7 의 갤러리 훅은 04-2 의 photosViewModelProvider 가 아니라 15-7 의 myPhotosViewModelProvider.notifier.pickFromGallery 다(MyPhotosScreen 이
                그 공급자를 쓴다). 얼굴 판정은 기기 안 ML Kit 이라 얼굴 사진은 사진 세트(E2E_결과/사진/face1.jpg · scenery.jpg)를 폰 앱 캐시로 옮겨 쓴다
                (area1_b3 와 같은 방식). 사진 세트가 없으면 계정을 만들기 전에 blocked.
  E-ME-38       "A 사진 4장" 은 계정 공장의 2장에 DB 로 2장을 더한다(Vision · AI 안 부름, 파일은 profile-photos 버킷 `{id}/` 아래라 뒷정리가 지운다).
                저장소 확인은 서비스 키로 `{id}/` 폴더만 읽는다: 행의 파일 경로 집합 == 폴더의 파일 집합(뺀 파일이 남지도, 새 파일이 빠지지도 않음).
  E-ME-39       길게 눌러 끌기는 앱이 실제 터치 제스처(LongPressDraggable)로 먼저 해 보고, 순서가 안 바뀌면 swapPhotos 를 직접 불러(대체) 메모에 적는다.
                끌기 자체(손가락 · 놓는 자리)는 실기기에서 사람이 본다. 끌기는 두 칸을 맞바꾼다(swapPhotos) — 3번째를 첫 칸으로 끌면 [3번째, 2번째, 1번째] 다.
  E-ME-41       4장에서 "추가" 는 빈 칸이 없어 화면으로 누를 곳이 없다 — 그 칸이 부르는 addPhoto 를 직접 부른다(area1_b3 E-ONB-21 과 같다). 4장에서 한 장씩 빼며
                3 · 2 · 1장의 저장 버튼을 본다(1장이면 꺼짐). 서버 경계(1칸 · 5칸 → 422)는 PC 가 새 파일 없이 직접 보낸다(retry=False, Vision 앞에서 끝난다).
  E-ME-44       PC 가 지운 사진은 마지막 칸(4번째)이고, 앱은 1 · 2번째 칸을 맞바꿔(끌기, 안 되면 대체) 저장한다. 지운 행의 파일은 저장소에 남는다(PC 는 행만 지운다 —
                뒷정리가 `{id}/` 를 비운다).
"""

import json
import threading
import uuid

from e2e import area1, area2, tools
from e2e.area1 import Check, _app, _one, _patch, _rows
from e2e.area1_b3 import _files, _photos, _push
from e2e.area2_phone3 import _add_avatar, _balance, _slow, offline
from e2e.area3_phone import MISSING
from e2e.area4 import _restore
from e2e.area5_act import _cut_settled, _paid_case
from e2e.area5_read import TITLES, _avatar_rows, _home, _photos_to, _ready_avatars
from e2e.tools import Blocked

HEARTS, LOW, COST = 37, 5, 10  # 시나리오 ME-13 · 12 — 화면이 본 잔액 · 낮춘 잔액 · 다시 만들기 값
FLIP_POLL = 0.2  # 새 pending 행을 보는 간격(초) — 워커가 행을 읽기 전에 바꾸려고 짧게
LOW_TITLE = '하트가 모자라요'  # 시트 제목이자 서버 HEARTS_NOT_ENOUGH
LOW_BODY = f'하트 {COST}개가 필요해요. 지금 보유한 하트는 {LOW}개예요.'
PAID_TITLE = '아바타를 다시 만들까요?'
CHANGED = '사진이 바뀌었어요, 다시 열어 주세요'  # 서버 PHOTOS_CHANGED
INVALID = '입력한 값을 다시 확인해 주세요'  # 서버 INVALID_INPUT
MAX_NOTICE = '사진은 최대 4장까지 올릴 수 있어요'
NONE_KEPT = '얼굴이 보이는 사진을 골라 주세요'
ONE_DROPPED = '1장은 얼굴이 보이지 않아 빠졌어요'
FACE, SCENERY, UNSAFE = 'face1.jpg', 'scenery.jpg', 'unsafe.jpg'  # 사진 세트(area1_b3.PHOTO_SET) — unsafe 는 얼굴이 있되 SafeSearch 에 걸린다(E-ONB-23 과 같다)
NOT_SAFE = '부적절한 사진은 올릴 수 없어요'  # 서버 PHOTO_NOT_SAFE(422)
TITLE_15_7 = TITLES['15-7']
FREE_BODY = '첫 번째 다시 만들기는 무료예요. 새 아바타는 바로 프로필에 반영돼요.'
FREE_CTA = '무료로 만들기'
HEART_LINE = '지금 보유한 하트는'  # 보유 하트 줄 — 무료 시트에는 없다
WORKER_WAIT = 900  # 앱이 워커를 기다리는 시간(초) — 앱은 11분까지 본다
WORKER_MS = 600_000  # 서버 · 앱 폴링 상한 10분(시나리오 "10분 안에")


def _paid_body(balance):
    return f'하트 {COST}개가 차감돼요. 지금 보유한 하트는 {balance}개예요. 새 아바타는 바로 프로필에 반영돼요.'


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _hearts_to(run, account, want):
    """하트를 정확히 [want] 로 — 처음 있던 잔액을 읽어 모자라면 더하고(free_task) 넘치면 뺀다(admin_adjust: avatar_regen 원장 0행을 지켜야 한다)."""
    area2._guard(run, account['id'])
    have = _balance(run, account)
    if have != want:
        status, got = area2._grant(run, account, want - have, 'free_task' if want > have else 'admin_adjust')
        if status >= 300:
            raise Blocked(f'준비: 하트 {want - have:+d} 쓰기 {status} {got}')
    if (now := _balance(run, account)) != want:
        raise Blocked(f'준비: 하트 {now}(기대 {want})')


def _two_ready(run, account):
    """ready 아바타 2장 — 1장이면 15b 가 무료 시트라 하트 줄도 "10 쓰고 만들기" 도 없다."""
    _add_avatar(run, account)
    ready = _ready_avatars(run, account)
    if len(ready) != 2:
        raise Blocked(f'준비: ready 아바타 {len(ready)}장 — 기대 2장(다시 만들기 값이 {COST} 이 되는 조건)')


def _ready_photos(run, account, want):
    """사진을 [want] 장으로 — 모자라면 DB 로 더한다(Vision 안 부름). 파일을 올리기 전에 가드부터(area5_read._add_photo 의 가드는 올린 뒤다)."""
    area2._guard(run, account['id'])
    _photos_to(run, account, want)


def _photos_now(run, account):
    """사진 행 — 위치 순서대로."""
    return _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=id,position,is_avatar_source,storage_path&order=position")


def _name(row):
    return row['storage_path'].rsplit('/', 1)[-1]


def _state(run, account):
    """저장될 수 있는 것 — 사진 행과 profile-photos 의 파일."""
    return {'photos': [(r['id'], r['position'], r['is_avatar_source'], r['storage_path']) for r in _photos_now(run, account)],
            'files': sorted(_files(run, 'profile-photos', account['id']))}


def _unchanged(check, run, account, before):
    check.that(_state(run, account) == before, 'DB 사진 · 저장소 파일이 바뀜(기대 저장 버튼을 안 눌렀으니 그대로)')


def _storage_matches(check, rows, files):
    """저장소 `{id}/` 의 파일 집합 == 행의 파일 경로 집합 — 뺀 파일이 남지도, 새 파일이 빠지지도 않았다."""
    paths = {r['storage_path'] for r in rows}
    left, missing = sorted(set(files) - paths), sorted(paths - set(files))
    check.that(not left, f'저장소에 행 없는 파일이 남음 {left}')
    check.that(not missing, f'저장소에 파일이 없는 행 {missing}')


def _drop_photo(run, account, row):
    """사진 행 하나를 지운다(다른 기기에서 지운 것처럼) — 파일은 저장소에 남는다."""
    area2._guard(run, account['id'])
    status, got = tools.rest(run.cfg, run.key, 'DELETE', f"profile_photos?id=eq.{row['id']}&profile_id=eq.{account['id']}")
    if status >= 300:
        raise Blocked(f'준비: 사진 행 지우기 {status} {got}')
    if _rows(run, f"profile_photos?id=eq.{row['id']}&select=id"):
        raise Blocked('준비: 사진 행이 안 지워짐 — "서버 사진이 바뀌었다" 를 만들 수 없다')


def _snapshot(run, account):
    """아바타 행 · 하트 · 원장 — 시트를 열고 닫기만 한 뒤에도 같아야 하는 것."""
    return {'avatars': _avatar_rows(run, account), 'balance': _balance(run, account),
            'ledger': sorted((r['amount'], r['reason']) for r in _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&select=amount,reason"))}


def _not_spent(check, run, account, before):
    now = _snapshot(run, account)
    check.that(now['avatars'] == before['avatars'], f"아바타 행이 바뀜 {len(before['avatars'])}행 → {len(now['avatars'])}행(기대 그대로 — 다시 만들기 요청이 가면 안 된다)")
    check.that(now['balance'] == before['balance'], f"하트 {now['balance']}(기대 {before['balance']} 그대로)")
    check.that(now['ledger'] == before['ledger'], f"하트 원장이 바뀜 {now['ledger']}(기대 {before['ledger']} 그대로)")


def _no_charge(check, run, account, want):
    """하트가 [want] 그대로이고 avatar_regen 원장 0행 — 하트는 만들기가 끝난 뒤에만 빠진다."""
    have = _balance(run, account)
    check.that(have == want, f'하트 {have}(기대 {want} 그대로)')
    ledger = area2._ledger(run, account, 'avatar_regen')
    check.that(not ledger, f'avatar_regen 원장 {ledger}(기대 0행)')


def _via(check, said):
    """끌기가 어떻게 됐나 → 메모. 대체로 넘어갔다면 그 사실을, 끌기가 엉뚱한 칸을 옮겼다면 fail 을 적는다."""
    via = said.get('via', MISSING)
    check.that(via in ('drag', 'swap-call'), f'끌기 결과 {via!r}(기대 drag 또는 swap-call — 끌었는데 엉뚱한 칸이 옮겨졌거나 말이 없음)')
    if via == 'swap-call':
        return '끌기 제스처가 순서를 못 바꿔 swapPhotos 를 직접 불렀다(대체) — 끌기 자체(길게 눌러 놓는 자리)는 실기기에서 사람이 본다'
    return ''


def _result(check, note):
    """check.result 는 fail 이면 메모를 버린다 — 끌기 대신 쓴 대체(swap-call)처럼 판정을 읽는 데 필요한 사실은 fail 메모에도 덧붙인다."""
    result, memo = check.result(note)
    return (result, f'{memo} ({note})' if result == 'fail' and note else memo)


# ── 새 아바타 행 지켜보기(E-ME-14) ──────────────────────────────────────────────────────────────────

class _Watcher:
    """앱이 "10 쓰고 만들기" 를 누르면 생기는 새 아바타 행을 [FLIP_POLL] 초마다 보다가, pending 이면 바로 failed 로 바꾼다(백그라운드).
    워커와의 경쟁이다 — 바꿀 때 `status=eq.pending` 조건을 걸어 이미 ready 가 된 행을 되돌려 쓰지 않고, 바꾼 뒤 다시 읽어 [seen] 에 남긴다
    (`first` = 처음 본 상태, `final` = 바꾼 뒤 읽은 상태). 앱이 끝나면 [finish] 로 한 번 더 보고 멈춘다."""

    def __init__(self, run, account, known):
        area2._guard(run, account['id'])  # 시작하기 전에 — 줄기 안에서 막히면 아무도 모른다
        self.run, self.account, self.known = run, account, known
        self.seen, self.error = {}, None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)

    def start(self):
        self._thread.start()

    def _look(self):
        rows = _rows(self.run, f"profile_avatars?profile_id=eq.{self.account['id']}&select=id,status")
        new = [r for r in rows if r['id'] not in self.known]
        if not new:
            return False
        row = new[0]
        self.seen = {'id': row['id'], 'first': row['status']}
        if row['status'] == 'pending':
            _patch(self.run, f"profile_avatars?id=eq.{row['id']}&status=eq.pending", {'status': 'failed'})
        self.seen['final'] = _one(self.run, f"profile_avatars?id=eq.{row['id']}&select=status").get('status')
        return True

    def _loop(self):
        try:
            while not self._stop.is_set() and not self._look():
                self._stop.wait(FLIP_POLL)
        except Exception as error:  # noqa: BLE001 — 줄기 안의 일은 앱이 끝난 뒤 가설이 읽는다
            self.error = error

    def finish(self):
        self._stop.set()
        if self._thread.is_alive():
            self._thread.join(30)
        if not self.seen and not self.error:
            try:
                self._look()  # 앱이 끝날 때까지 한 번도 못 봤어도 지금 한 번은 본다
            except Exception as error:  # noqa: BLE001
                self.error = error


# ── E-ME-12 · 13 · 14 아바타 다시 만들기 ─────────────────────────────────────────────────────────────

def p_me_12(run, phone):
    check = Check()
    account, token = _home(run)
    _two_ready(run, account)
    _hearts_to(run, account, LOW)
    before = _snapshot(run, account)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('sheet_title', MISSING) == LOW_TITLE, f"시트 제목 {said.get('sheet_title', MISSING)!r}(기대 {LOW_TITLE!r})")
    check.that(said.get('sheet_body', MISSING) == LOW_BODY, f"시트 글 {said.get('sheet_body', MISSING)!r}(기대 {LOW_BODY!r})")
    check.that(said.get('sheet_closed') is True, f"\"하트 충전하기\" 뒤 시트 닫힘 {said.get('sheet_closed', MISSING)}(기대 True)")
    check.that(said.get('store_seen') is True, f"하트 스토어 섹션 \"구매하기\" {said.get('store_seen', MISSING)}(기대 보임)")
    check.that(said.get('store_title') == 1, f"하트 스토어 앱바 제목 \"하트\" {said.get('store_title', MISSING)}개(기대 1)")
    check.that(said.get('regen_state', MISSING) == 'idle',
               f"다시 만들기를 불렀다 — 뷰모델 상태 {said.get('regen_state', MISSING)!r}(기대 idle — 시트의 충전 버튼은 서버를 부르지 않는다)")
    _not_spent(check, run, account, before)
    return check.result('서버 요청 0 은 앱의 뷰모델 상태(idle — 다시 만들기를 부르면 generating · failed 가 된다)와 DB(아바타 행 · 하트 · 원장 그대로)로 본다')


def p_me_13(run, phone):
    check = Check()
    account, token = _home(run)
    _two_ready(run, account)
    _hearts_to(run, account, HEARTS)
    before = _avatar_rows(run, account)

    def lower(said):
        """앱이 나 탭을 연 채 멈춘 사이 — 다른 곳에서 쓴 것처럼 하트를 낮춘다. 못 낮췄으면 앱이 누르기 전에 막는다."""
        _hearts_to(run, account, LOW)
    said = _app(check, phone(midway=lower, token_hash=token))
    check.that(said.get('sheet_title', MISSING) == PAID_TITLE, f"시트 제목 {said.get('sheet_title', MISSING)!r}(기대 {PAID_TITLE!r})")
    check.that(said.get('sheet_body', MISSING) == _paid_body(HEARTS),
               f"시트 글 {said.get('sheet_body', MISSING)!r}(기대 낡은 잔액 {HEARTS} 을 그대로 든 {_paid_body(HEARTS)!r})")
    check.that(said.get('toast_seen') is True, f"토스트 \"{LOW_TITLE}\" {said.get('toast_seen', MISSING)}(기대 보임)")
    check.that(said.get('regen_state', MISSING) == 'failed', f"다시 만들기 상태 {said.get('regen_state', MISSING)!r}(기대 failed — 402 로 끝나야 한다)")
    check.that(said.get('regen_error', MISSING) == LOW_TITLE, f"서버 문구 {said.get('regen_error', MISSING)!r}(기대 {LOW_TITLE!r})")
    new = [r for r in _avatar_rows(run, account) if r not in before]
    check.that(not new, f'새 아바타 행 {[r[1] for r in new]} — 서버가 402 로 막지 않고 큐에 넣었다(202). 유료 AI 호출이 나갔을 수 있다')
    _no_charge(check, run, account, LOW)
    return check.result()


def p_me_14(run, phone, paid):
    check = Check()
    account, token = _home(run)
    _two_ready(run, account)
    _hearts_to(run, account, HEARTS)
    known = {r[0] for r in _avatar_rows(run, account)}
    watcher = _Watcher(run, account, known)
    paid()  # 여기부터는 큐 등록 · OpenAI 이미지 생성(유료)이 나갈 수 있다
    try:
        said = _app(check, phone(midway=lambda step: watcher.start(), token_hash=token))
    finally:
        watcher.finish()
    if watcher.error:
        raise Blocked(f'새 아바타 행 지켜보기가 멈춤 — {type(watcher.error).__name__}: {watcher.error}. 행이 pending 으로 남았으면 워커가 OpenAI 를 부를 수 있다')
    seen = watcher.seen
    if seen and seen['final'] == 'ready':
        raise Blocked(f"워커가 먼저 끝냈다(새 행 {seen['first']} → {seen['final']}) — 판정 못 함. 유료 호출(OpenAI 이미지 생성)이 1번 나갔고 하트가 빠졌을 수 있다")
    if seen and seen['final'] != 'failed':
        raise Blocked(f"새 행을 failed 로 바꾸지 못했다(처음 {seen['first']} → 읽은 상태 {seen['final']}) — pending 이 남았으면 워커가 곧 OpenAI 를 부른다")
    check.that(bool(seen), '새 아바타 행이 안 생겼다 — 앱의 "10 쓰고 만들기" 요청이 큐에 등록되지 않았다')
    check.that(said.get('sheet_body', MISSING) == _paid_body(HEARTS), f"시트 글 {said.get('sheet_body', MISSING)!r}(기대 {_paid_body(HEARTS)!r})")
    check.that(said.get('toast_seen') is True, f"15-3 토스트 \"아바타를 만들지 못했어요.\\n하트는 차감되지 않았어요.\" {said.get('toast_seen', MISSING)}(기대 보임)")
    check.that(said.get('pill_enabled') is True, f"알약 \"다시 만들기 · 10\" 켜짐 {said.get('pill_enabled', MISSING)}(기대 다시 켜짐)")
    check.that(said.get('generating_gone') is True, f"\"아바타로 변환 중이에요\" 안내가 사라짐 {said.get('generating_gone', MISSING)}(기대 True)")
    check.that(said.get('regen_state', MISSING) == 'failed', f"다시 만들기 상태 {said.get('regen_state', MISSING)!r}(기대 failed)")
    check.that(said.get('regen_error', MISSING) is None,
               f"서버 문구 {said.get('regen_error', MISSING)!r}(기대 없음 — 서버 거절이 아니라 만들기 실패라 15-3 기본 안내여야 한다)")
    now = _avatar_rows(run, account)
    new = [r for r in now if r[0] not in known]
    check.that(len(new) == 1 and new[0][1] == 'failed', f'새 아바타 행 {[r[1] for r in new]}(기대 failed 1개)')
    ready = [r for r in now if r[1] == 'ready']
    check.that(len(ready) == 2, f'완성 아바타 {len(ready)}장(기대 2장 그대로)')
    _no_charge(check, run, account, HEARTS)
    return check.result('유료 호출: 큐 등록 1번, OpenAI 이미지 생성은 워커가 행을 읽기 전에 바꿨으면 0번(건너뜀), 먼저 읽었으면 1번(끝에 0행이라 skipped)')


# ── E-ME-10 · 11 · 16 워커가 새 아바타를 만든다(유료 AI) ──────────────────────────────────────────

def _regen_ui(check, said):
    """다시 만들기가 변환 중 안내를 거쳐 새 그림으로 끝났나 — 10 · 11 · 16 이 같이 본다."""
    for label, got in (('"아바타로 변환 중이에요" 안내', said.get('generating_seen', MISSING)),
                       ('히어로 그림이 새 그림으로 바뀜', said.get('avatar_changed', MISSING)),
                       ('변환 중 안내가 사라짐', said.get('generating_gone', MISSING))):
        check.that(got is True, f'{label} {got}(기대 True)')
    check.that(said.get('regen_state', MISSING) == 'ready', f"다시 만들기 상태 {said.get('regen_state', MISSING)!r}(기대 ready)")
    ms = said.get('waited_ms')
    check.that(isinstance(ms, int) and ms <= WORKER_MS, f'새 아바타까지 {ms}ms(기대 10분 {WORKER_MS}ms 이내)')


def _one_new_ready(check, run, account, ready_before):
    """워커가 새 한 장을 완성했고 pending · failed 가 남지 않았나. 아바타 행들을 돌려준다."""
    rows = _avatar_rows(run, account)
    ready = [r for r in rows if r[1] == 'ready']
    check.that(len(ready) == ready_before + 1, f'완성 아바타 {len(ready)}장(기대 {ready_before + 1}장 — 워커가 새 한 장을 완성)')
    other = [r[1] for r in rows if r[1] != 'ready']
    check.that(not other, f'완성이 아닌 아바타 행 {other}(기대 없음)')
    return rows


def _new_ready_id(rows, known):
    new = [r[0] for r in rows if r[1] == 'ready' and r[0] not in known]
    return new[0] if len(new) == 1 else None


def p_me_10(run, phone, paid):
    check = Check()
    account, token = _home(run)
    ready = len(_ready_avatars(run, account))
    if ready != 1:
        raise Blocked(f'준비: ready 아바타 {ready}장 — 기대 1장(첫 다시 만들기가 무료인 조건)')
    before = _snapshot(run, account)
    paid()  # 여기부터는 큐 등록 · OpenAI 이미지 생성(유료)이 나갈 수 있다
    said = _app(check, _slow(phone, WORKER_WAIT)(token_hash=token))
    check.that(said.get('sheet_title', MISSING) == PAID_TITLE, f"시트 제목 {said.get('sheet_title', MISSING)!r}(기대 {PAID_TITLE!r})")
    texts = said.get('sheet_texts') or []
    check.that(FREE_BODY in texts and FREE_CTA in texts, f'시트 글 {texts}(기대 무료 안내 {FREE_BODY!r} 와 {FREE_CTA!r} 버튼)')
    check.that(not any(HEART_LINE in t for t in texts), f'시트에 보유 하트 줄이 있다 {texts}(기대 없음 — 무료 시트)')
    _regen_ui(check, said)
    _one_new_ready(check, run, account, ready)
    now = _snapshot(run, account)
    check.that(now['balance'] == before['balance'], f"하트 {now['balance']}(기대 {before['balance']} 그대로 — 첫 다시 만들기는 무료)")
    ledger = area2._ledger(run, account, 'avatar_regen')
    check.that(not ledger, f'avatar_regen 원장 {ledger}(기대 0행)')
    return check.result('유료 호출: 큐 등록 1번 · 워커의 OpenAI 이미지 생성 1번(하트는 안 빠진다)')


def p_me_11(run, phone, paid):
    check = Check()
    account, token = _home(run)
    _two_ready(run, account)
    _hearts_to(run, account, HEARTS)
    known = {r[0] for r in _avatar_rows(run, account)}
    paid()
    said = _app(check, _slow(phone, WORKER_WAIT)(token_hash=token))
    check.that(said.get('sheet_title', MISSING) == PAID_TITLE, f"시트 제목 {said.get('sheet_title', MISSING)!r}(기대 {PAID_TITLE!r})")
    check.that(said.get('sheet_body', MISSING) == _paid_body(HEARTS),
               f"시트 글 {said.get('sheet_body', MISSING)!r}(기대 {_paid_body(HEARTS)!r})")
    _regen_ui(check, said)
    rows = _one_new_ready(check, run, account, 2)
    have = _balance(run, account)
    check.that(have == HEARTS - COST, f'하트 {have}(기대 {HEARTS} → {HEARTS - COST} — 완성된 뒤에 {COST}개)')
    ledger = _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.avatar_regen&select=amount,ref_id")
    check.that([r['amount'] for r in ledger] == [-COST], f"avatar_regen 원장 {[r['amount'] for r in ledger]}(기대 [{-COST}] 한 줄)")
    new_id = _new_ready_id(rows, known)
    refs = [r.get('ref_id') for r in ledger]
    check.that(bool(refs) and all(refs), f'원장의 ref_id {refs}(기대 비어 있지 않음)')
    check.that(new_id is not None and refs == [new_id], f'원장의 ref_id {refs}(기대 새 아바타 행 {new_id})')
    return check.result(f'유료 호출: 큐 등록 1번 · 워커의 OpenAI 이미지 생성 1번(하트 {COST}개)')


def p_me_16(run, phone, paid):
    check = Check()
    account, token = _home(run)
    ready = len(_ready_avatars(run, account))
    if ready != 1:
        raise Blocked(f'준비: ready 아바타 {ready}장 — 기대 1장(무료로 만들어 하트를 안 쓴다)')
    paid()
    said = _app(check, _slow(phone, WORKER_WAIT)(token_hash=token))
    check.that(said.get('generating_after_return', MISSING) is True,
               f"오늘 탭에서 나 탭으로 돌아온 뒤 변환 중 안내 {said.get('generating_after_return', MISSING)}(기대 True — 폴링을 다시 잇는다)")
    _regen_ui(check, said)
    _one_new_ready(check, run, account, ready)
    return check.result('유료 호출: 큐 등록 1번 · 워커의 OpenAI 이미지 생성 1번(무료 차례라 하트는 안 빠진다)')


# ── E-ME-38 · 39 15-7 저장 ──────────────────────────────────────────────────────────────────────────

def p_me_38(run, phone):
    check = Check()
    _photos(run, FACE)  # 계정을 만들기 전에 파일부터
    account, token = _home(run)
    _ready_photos(run, account, 4)
    before = _photos_now(run, account)
    ids = [r['id'] for r in before]
    removed = ids[:1] + ids[2:]
    _push(phone, run, FACE)
    said = _app(check, phone(token_hash=token, photo=FACE))
    check.that(said.get('ids_open', MISSING) == ids, f"15-7 을 열었을 때 칸 {said.get('ids_open', MISSING)}(기대 DB 사진 순서 {ids})")
    check.that(said.get('ids_removed', MISSING) == removed, f"두 번째 칸을 뺀 뒤 {said.get('ids_removed', MISSING)}(기대 {removed})")
    check.that(said.get('ids_added', MISSING) == removed + [None], f"새 사진을 넣은 뒤 {said.get('ids_added', MISSING)}(기대 남은 칸 + id 없는 새 사진 {removed + [None]})")
    check.that(said.get('asked', MISSING) == [1], f"갤러리에 물은 남은 칸 {said.get('asked', MISSING)}(기대 [1])")
    check.that(said.get('message', MISSING) is None, f"사진 고르기 안내 {said.get('message', MISSING)!r}(기대 없음 — 얼굴 사진 1장이 들어가야 한다)")
    check.that(said.get('save_enabled') is True, f"저장 버튼 {said.get('save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    now = _photos_now(run, account)
    check.that(len(now) == 4, f'DB 사진 {len(now)}장(기대 4장)')
    check.that([r['position'] for r in now] == [0, 1, 2, 3], f"DB 위치 {[r['position'] for r in now]}(기대 [0, 1, 2, 3])")
    new = [r for r in now if r['id'] not in ids]
    check.that(len(new) == 1, f'새 사진 행 {len(new)}개(기대 1)')
    want = removed + [new[0]['id'] if new else None]
    check.that([r['id'] for r in now] == want, f"DB 순서 {[r['id'] for r in now]}(기대 {want})")
    check.that(ids[1] not in {r['id'] for r in now}, f'뺀 사진 행 {ids[1]} 이 남음')
    sources = [r for r in now if r['is_avatar_source']]
    check.that(len(sources) == 1, f'아바타 원본 표시 {len(sources)}개(기대 1개)')
    _storage_matches(check, now, _files(run, 'profile-photos', account['id']))
    check.that(said.get('names_before', MISSING) == [_name(r) for r in before], f"15-5 저장 전 사진 {said.get('names_before', MISSING)}(기대 DB 파일 이름)")
    check.that(said.get('names_after', MISSING) == [_name(r) for r in now], f"15-5 저장 뒤 사진 {said.get('names_after', MISSING)}(기대 DB 파일 이름 {[_name(r) for r in now]})")
    return check.result('Vision SafeSearch 1번(새 사진 1장)')


def p_me_39(run, phone):
    check = Check()
    account, token = _home(run)
    _ready_photos(run, account, 3)
    before = _photos_now(run, account)
    ids = [r['id'] for r in before]
    swapped = [ids[2], ids[1], ids[0]]
    said = _app(check, phone(token_hash=token, drag=[2, 0]))
    note = _via(check, said)
    check.that(said.get('ids_open', MISSING) == ids, f"15-7 을 열었을 때 칸 {said.get('ids_open', MISSING)}(기대 DB 사진 순서 {ids})")
    check.that(said.get('ids_dragged', MISSING) == swapped, f"끈 뒤 칸 {said.get('ids_dragged', MISSING)}(기대 {swapped})")
    check.that(said.get('save_enabled') is True, f"저장 버튼 {said.get('save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    now = _photos_now(run, account)
    order = [r['id'] for r in now]
    check.that([r['position'] for r in now] == [0, 1, 2], f"DB 위치 {[r['position'] for r in now]}(기대 [0, 1, 2])")
    check.that(bool(order) and order[0] == ids[2], f'DB 맨 앞(위치 0) 사진 {order[:1]}(기대 3번째였던 {ids[2]})')
    check.that(order == swapped, f'DB 순서 {order}(기대 끌기는 두 칸을 맞바꾼다 — 맞바꾸기 {swapped})')
    check.that(len([r for r in now if r['is_avatar_source']]) == 1, '아바타 원본 표시가 한 개가 아님')
    _storage_matches(check, now, _files(run, 'profile-photos', account['id']))
    check.that(said.get('names_after', MISSING) == [_name(r) for r in now],
               f"15-5 저장 뒤 사진 {said.get('names_after', MISSING)}(기대 DB 파일 이름, 첫 사진 {_name(now[0]) if now else None!r})")
    check.that(said.get('names_before', MISSING) == [_name(r) for r in before], f"15-5 저장 전 사진 {said.get('names_before', MISSING)}(기대 DB 파일 이름)")
    return _result(check, note)


# ── E-ME-41 · 42 개수 · 얼굴 ────────────────────────────────────────────────────────────────────────

def _put_layout(run, token, slots, source):
    """PUT /me/photos 를 새 파일 없이 보낸다 — 칸 규칙(①)에서 막히면 DB 도 Vision 도 안 부른다. 두 번 적용돼도 되지만 한 번만(retry=False)."""
    boundary = uuid.uuid4().hex
    fields = {'layout': json.dumps(slots), 'avatar_source': source}
    body = b''.join(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in fields.items())
    body += f'--{boundary}--\r\n'.encode()
    return tools.call('PUT', f"{run.cfg['API_BASE_URL']}/me/photos", {'Authorization': f'Bearer {token}'},
                      raw=(body, f'multipart/form-data; boundary={boundary}'), **area2._ONCE)


def p_me_41(run, phone):
    check = Check()
    account, token = _home(run)
    _ready_photos(run, account, 4)
    ids = [r['id'] for r in _photos_now(run, account)]
    before = _state(run, account)
    said = _app(check, phone(token_hash=token))
    steps = said.get('steps') or []
    check.that([row.get('count') for row in steps] == [4, 3, 2, 1], f"칸 수 {[row.get('count') for row in steps]}(기대 4장에서 한 장씩 빼 [4, 3, 2, 1])")
    for row in steps:
        on = isinstance(row.get('count'), int) and 2 <= row['count'] <= 4
        check.that(row.get('save_enabled') is on, f"{row.get('count')}장일 때 저장 버튼 {row.get('save_enabled')}(기대 {'켜짐' if on else '꺼짐'} — 2~4장만)")
    check.that(said.get('plus_at_four', MISSING) == 0, f"4장일 때 추가 칸 {said.get('plus_at_four', MISSING)}개(기대 0)")
    check.that(said.get('max_toast') is True, f"4장에서 추가하면 \"{MAX_NOTICE}\" 토스트 {said.get('max_toast', MISSING)}(기대 보임)")
    check.that(said.get('tiles_after_max', MISSING) == 4, f"4장에서 추가한 뒤 칸 {said.get('tiles_after_max', MISSING)}개(기대 4개 그대로)")
    check.that(said.get('gallery_asked', MISSING) == 0, f"갤러리에 물은 횟수 {said.get('gallery_asked', MISSING)}(기대 0 — 4장이면 고르기 전에 막힌다)")
    for label, keeps in (('1칸', ids[:1]), ('5칸', ids + [str(uuid.uuid4())])):
        slots = [{'keep': i} for i in keeps]  # 모양은 맞고 개수만 틀리다 — 모양이 틀려서 422 가 나면 이 가설이 보려는 것이 아니다
        check.reply(f'API PUT /me/photos {label}', _put_layout(run, account['token'], slots, 0), 422, detail=INVALID)
    _unchanged(check, run, account, before)
    return check.result('Vision 0번 — 저장 버튼을 안 누르고, 서버 경계 두 번은 칸 규칙에서 막혀 새 파일이 없다')


def p_me_42(run, phone):
    check = Check()
    _photos(run, FACE, SCENERY)
    account, token = _home(run)
    _ready_photos(run, account, 2)
    before = _state(run, account)
    _push(phone, run, FACE, SCENERY)
    said = _app(check, phone(token_hash=token, alone=SCENERY, mixed=[FACE, SCENERY]))
    for label, row, after, message in (('풍경 혼자', said.get('alone') or {}, 2, NONE_KEPT), ('얼굴 + 풍경 섞어', said.get('mixed') or {}, 3, ONE_DROPPED)):
        check.that(row.get('before') == 2, f"{label}: 넣기 전 칸 {row.get('before', MISSING)}개(기대 2개)")
        check.that(row.get('after') == after, f"{label}: 넣은 뒤 칸 {row.get('after', MISSING)}개(기대 {after}개)")
        check.that(row.get('message') == message, f"{label}: 안내 {row.get('message', MISSING)!r}(기대 {message!r})")
        check.that(row.get('toast') is True, f"{label}: 토스트 {row.get('toast', MISSING)}(기대 보임)")
    _unchanged(check, run, account, before)
    return check.result('Vision 0번 — 얼굴 판정은 기기 안(ML Kit)이고 저장 버튼을 안 누른다')


def p_me_40(run, phone, paid):
    check = Check()
    account, token = _home(run)
    _ready_photos(run, account, 3)
    rows = _photos_now(run, account)
    ids = [r['id'] for r in rows]
    ready = len(_ready_avatars(run, account))
    if ready != 1 or not rows[0]['is_avatar_source']:
        raise Blocked(f"준비: ready 아바타 {ready}장(기대 1장) · 첫 칸이 원본 {rows[0]['is_avatar_source']}(기대 True) — 원본을 빼는 조건이 아니다")
    avatars = _avatar_rows(run, account)
    paid()  # 여기부터는 큐 등록 · OpenAI 이미지 생성(유료)이 나갈 수 있다
    said = _app(check, _slow(phone, WORKER_WAIT)(token_hash=token))
    check.that(said.get('ids_open', MISSING) == ids, f"15-7 을 열었을 때 칸 {said.get('ids_open', MISSING)}(기대 DB 사진 순서 {ids})")
    check.that(said.get('ids_removed', MISSING) == ids[1:], f"첫 칸(원본)을 뺀 뒤 {said.get('ids_removed', MISSING)}(기대 {ids[1:]})")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    now = _photos_now(run, account)
    check.that([r['id'] for r in now] == ids[1:], f"DB 순서 {[r['id'] for r in now]}(기대 원본을 뺀 {ids[1:]})")
    check.that([r['position'] for r in now] == [0, 1], f"DB 위치 {[r['position'] for r in now]}(기대 [0, 1])")
    sources = [r['id'] for r in now if r['is_avatar_source']]
    check.that(sources == ids[1:2], f'아바타 원본 표시 {sources}(기대 새 첫 칸 {ids[1:2]} 한 개)')
    _storage_matches(check, now, _files(run, 'profile-photos', account['id']))
    before_url = said.get('avatar_before', MISSING)
    check.that(before_url is not None and before_url == said.get('avatar_after', MISSING),
               f"사진 저장 전 아바타 그림 {before_url!r} · 뒤 {said.get('avatar_after', MISSING)!r}(기대 같은 그림 — 지금 아바타는 그대로)")
    _regen_ui(check, said)
    after = _one_new_ready(check, run, account, ready)
    check.that(set(avatars) <= set(after), f'기존 아바타 행이 바뀜 {sorted(set(avatars) - set(after))}(기대 그대로 — 사진 저장은 아바타를 안 건드린다)')
    return check.result('다음 다시 만들기가 새 원본으로 돈다는 것은 서버가 원본 행(is_avatar_source)을 읽어 만든다는 코드 사실과 완성(409 없이)으로 본다 — '
                        '워커가 어느 사진을 썼는지는 PC 가 못 본다. 유료 호출: 큐 등록 1번 · 워커의 OpenAI 이미지 생성 1번')


def p_me_43(run, phone):
    check = Check()
    _photos(run, FACE, UNSAFE)  # 계정을 만들기 전에 파일부터
    account, token = _home(run)
    _ready_photos(run, account, 2)
    before = _state(run, account)
    _push(phone, run, FACE, UNSAFE)
    said = _app(check, phone(token_hash=token, photo=FACE, unsafe=UNSAFE))
    check.that(said.get('tiles_before', MISSING) == 2, f"넣기 전 칸 {said.get('tiles_before', MISSING)}개(기대 2개)")
    check.that(said.get('tiles_after', MISSING) == 4, f"넣은 뒤 칸 {said.get('tiles_after', MISSING)}개(기대 4개 — 기기 얼굴 검사를 둘 다 통과)")
    check.that(said.get('error') is True, f"오류 줄 {said.get('error', MISSING)}(기대 보임)")
    check.that(said.get('error_text', MISSING) == NOT_SAFE, f"오류 글 {said.get('error_text', MISSING)!r}(기대 {NOT_SAFE!r})")
    check.that(said.get('title_after_error', MISSING) == TITLE_15_7, f"422 뒤 화면 {said.get('title_after_error', MISSING)!r}(15-7 {TITLE_15_7!r} 에 머물러야 한다)")
    _unchanged(check, run, account, before)
    return check.result('Vision SafeSearch 1~2번(새 사진마다, 부적절한 쪽에서 멈춘다) — 사진 세트의 unsafe.jpg 가 실제로 걸리는 사진이어야 한다')


# ── E-ME-44 열어 둔 사이 서버 사진이 바뀜 ───────────────────────────────────────────────────────────

def p_me_44(run, phone):
    check = Check()
    account, token = _home(run)
    _ready_photos(run, account, 4)
    rows = _photos_now(run, account)
    ids = [r['id'] for r in rows]
    swapped = [ids[1], ids[0], ids[2], ids[3]]
    mid = {}

    def delete(said):
        """앱이 15-7 을 연 채 멈춘 사이 — 마지막 칸의 사진 행을 지운다(다른 기기에서 지운 것처럼)."""
        _drop_photo(run, account, rows[3])
        mid['state'] = _state(run, account)
    said = _app(check, phone(midway=delete, token_hash=token, swap=[0, 1], left=3))
    note = _via(check, said)
    left = ids[:3]
    check.that(said.get('ids_open', MISSING) == ids, f"15-7 을 열었을 때 칸 {said.get('ids_open', MISSING)}(기대 DB 사진 순서 {ids})")
    check.that(said.get('ids_swapped', MISSING) == swapped, f"바꾼 뒤 칸 순서 {said.get('ids_swapped', MISSING)}(기대 {swapped} — 지운 사진 칸은 그대로)")
    check.that(said.get('error') is True, f"오류 줄 {said.get('error', MISSING)}(기대 보임)")
    check.that(said.get('error_text', MISSING) == CHANGED, f"오류 글 {said.get('error_text', MISSING)!r}(기대 {CHANGED!r})")
    check.that(said.get('title_after_error', MISSING) == TITLE_15_7, f"409 뒤 화면 {said.get('title_after_error', MISSING)!r}(15-7 {TITLE_15_7!r} 에 머물러야 한다)")
    check.that(said.get('reopened_tiles', MISSING) == len(left), f"다시 열면 칸 {said.get('reopened_tiles', MISSING)}개(기대 서버 사진 수 {len(left)}개)")
    check.that(said.get('reopened_ids', MISSING) == left, f"다시 열면 칸 {said.get('reopened_ids', MISSING)}(기대 서버 사진 순서 {left})")
    check.that(bool(mid) and _state(run, account) == mid['state'], 'DB 사진 · 저장소 파일이 PC 가 지운 뒤와 다름(기대 409 라 저장되지 않아 그대로)')
    return _result(check, note)


def p_edge_03(run, phone):
    """E-EDGE-03 — 끊긴 저장은 칸을 남기고, 복구 뒤 저장만 서버에 반영."""
    check = Check()
    _photos(run, FACE)
    account, token = _home(run)
    _ready_photos(run, account, 2)
    before = _photos_now(run, account)
    files = _files(run, 'profile-photos', account['id'])
    _push(phone, run, FACE)

    def restore(said):
        # 두 번째 멈춤 = 끊긴 채 저장을 누른 뒤(망 복구 · 두 번째 저장 전) — 이때 서버가 그대로여야 한다
        check.that(_photos_now(run, account) == before and _files(run, 'profile-photos', account['id']) == files,
                   '끊긴 저장 뒤 DB 사진 · 저장소 파일이 바뀜')
        _restore(phone)(said)

    said = offline(phone, check, _cut_settled(phone), restore, token_hash=token, photo=FACE)
    check.that(said.get('off_error', MISSING) == '네트워크 연결을 확인해 주세요',
               f"끊긴 저장 네트워크 안내 {said.get('off_error', MISSING)!r}(기대 네트워크 연결을 확인해 주세요)")
    check.that(said.get('off_title', MISSING) == TITLE_15_7, f"끊긴 저장 뒤 화면 {said.get('off_title', MISSING)!r}(기대 15-7)")
    check.that(said.get('off_tiles', MISSING) == 3, f"끊긴 저장 뒤 칸 {said.get('off_tiles', MISSING)}(기대 3개 유지)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"복구 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5)")
    now = _photos_now(run, account)
    check.that(len(now) == 3 and [r['position'] for r in now] == [0, 1, 2], f'DB 사진 {len(now)}장 · 위치(기대 3장 연속)')
    check.that([r['id'] for r in now[:2]] == [r['id'] for r in before] and len({r['id'] for r in now} - {r['id'] for r in before}) == 1,
               'DB 새 사진 행(기대 원래 2장 + 새 1장)')
    _storage_matches(check, now, _files(run, 'profile-photos', account['id']))
    check.that(said.get('names_after', MISSING) == [_name(r) for r in now], f"15-5 사진 {said.get('names_after', MISSING)}(기대 DB 사진)")
    return check.result('Vision SafeSearch 1번(복구 뒤 새 사진 저장)')


PHONE = {
    'E-ME-10': _paid_case('E-ME-10', p_me_10), 'E-ME-11': _paid_case('E-ME-11', p_me_11),
    'E-ME-12': p_me_12, 'E-ME-13': p_me_13, 'E-ME-14': _paid_case('E-ME-14', p_me_14), 'E-ME-16': _paid_case('E-ME-16', p_me_16),
    'E-ME-38': p_me_38, 'E-ME-39': p_me_39, 'E-ME-40': _paid_case('E-ME-40', p_me_40), 'E-ME-41': p_me_41, 'E-ME-42': p_me_42,
    'E-ME-43': p_me_43, 'E-ME-44': p_me_44, 'E-EDGE-03': p_edge_03,
}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-photo'] = list(PHONE)
tools.CASE_LIMITS.update({'E-ME-40': 1200, 'E-ME-10': 1200, 'E-ME-11': 1200, 'E-ME-16': 1200, 'E-ME-14': 600, 'E-ME-38': 600, 'E-ME-39': 600, 'E-ME-42': 600, 'E-ME-44': 600, 'E-EDGE-03': 600})  # 유료 대기 · 사진 옮기기 · 끌기
