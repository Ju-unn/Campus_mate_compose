"""영역 5 경계 7개(묶음 area5-edge) — 폰 A: E-EDGE-01 · 11 · 15 · 19, B에뮬: E-EDGE-21 · 24 · 25(느린 망 · 패킷 버림은 에뮬에서만).
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 5-4 표의 그 줄을 지금 코드와 대조한 것이다. 앱 쪽은 frontend/integration_test/area5_edge.dart 의
같은 번호(area5.dart 가 묶는다). 돌릴 때: 폰 넷은 `--device A`, 에뮬 셋은 `--device B`(에뮬이 아니면 blocked) — 묶음 하나를 두 번 돌린다.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 홈 계정을 만들고 서비스 키 DB 로 준비하면, 앱이 화면을 열어 고치고 누르고 본 것을 Map 으로 말하고
(문구는 사람이 읽는 글자 그대로, 못 본 것은 None — 이 쪽은 `MISSING` 과 가른다), 판정은 여기서 한다. 쓰기는 이번 실행이 만든 계정에만(area2._guard).
멈춤이 여럿인 가설(01 · 21 · 24 · 25)은 앱이 `화면:일` 이름으로 멈추고(예: `15-6:edited`), PC 는 [_walk] 로 `end` 까지 일마다 정해진 손을 쓴다.

편집 다섯 화면(01 · 21) — 무엇을 고치고 어디로 돌아오나(앱 쪽 같은 순서):
  15-6  키 178 → 181(21 은 닉네임도 — 30일 잠금을 먼저 푼다)   → 15-5      PATCH /me/profile
  15c   자기소개를 새 글로                                        → 15-5      PATCH /me/profile           (임베딩 = 유료)
  06-1  "나이는 상관없어요" 를 켬(19~35)                          → 15-5      POST /profile-onboarding/ideal-conditions (임베딩 = 유료)
  태그  관심사 4개에 하나 더(술)                                  → 15c       POST /profile-onboarding/interests
  15-7  첫 · 둘째 칸을 맞바꿈(새 파일 없음 — Vision 0)            → 15-5      PUT /me/photos
그래서 01 · 21 은 area5_act 의 _paid_case 를 탄다(E2E_REAL_AI=1 이 아니면 계정도 요청도 없이 blocked, 앱이 켜진 뒤에는 한 번만).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-EDGE-01  비행기 모드는 앱이 값을 고친 채 `화면:edited` 에서 멈춘 사이 PC 가 켜고(notify.airplane), 저장이 막힌 뒤 `화면:failed` 에서 PC 가 DB 가 그대로인지
             보고 끈다. "버튼 위" 는 앱이 오류 글자의 아래 끝이 저장 버튼 위 끝보다 위인지로 본다(15-6 · 15c · 15-7 은 화면 오류 줄, 06-1 · 태그는 빨간 글).
  E-EDGE-11  "테스트 계정 C" 는 이번 실행의 홈 계정이다. PC 는 관리자 API 로 auth 사용자만 지운다(프로필 이하는 cascade, 파일은 뒷정리). A11 뒤 코드:
             401 → 토큰 새로 받기 → 실패 → 02 + "세션이 만료됐어요" — 10-04 의 "확인 필요(02 가 알림보다 먼저 그려질 수 있다)" 는 앱이 02 에 닿은 뒤
             2초 안에 알림이 뜨는지로 본다. "알림 토큰 정리가 실패해도 로그아웃은 끝까지(#232)" 는 02 도착으로 대신한다.
  E-EDGE-15  알림 둘은 상대가 API 로 만든다 — 채팅은 보내기(new_message), 지인 리뷰는 추천 연결(area3._link) 뒤 POST /friend-reviews(new_friend_review).
             앱을 죽이고(notify.kill_app) 알림을 눌러 콜드 스타트한 앱이 그 화면에서 멈추면 PC 가 시스템 뒤로를 보내고 맨 앞 화면이 우리 앱인지 본다.
             "화살표와 같은 곳" 은 코드의 _exit — 방은 대화 목록(13), 리뷰 목록(20c)은 나 탭(15)이다(chat_room_screen.dart · friend_review_list_frame.dart).
  E-EDGE-19  force-stop 은 쓰지 않는다(E-EDGE-20 과 같은 까닭) — 앱이 저장을 누르자마자 멈춤 말을 보내면 PC 가 0.3초를 채워 run-as kill -9 로 죽인다
             (area5_wd._kill_soon). 판이 둘(닉네임 · 사진 맞바꾸기) — 계정 둘, 앱 네 번. 다시 켠 앱은 저장된 세션 그대로 15 · 15-5 를 읽는다.
             사진은 요청이 한 번(PUT /me/photos)이지만 서버 안에서 세 단계로 나뉘어(me/router.py ponytail) 중간에 멈추면 원본 없음이 남을 수 있다 — 결과로 적는다.
  E-EDGE-21  "Cloud Run 요청 로그" 는 gcloud logging read 로 읽는다(로그가 들어오기를 LOG_SETTLE 초 기다린다). 화면마다 앱이 `화면:start` · `화면:done` 에서
             멈추면 PC 가 PC 시계로 창을 찍고, 그 창 안의 그 경로 요청을 센다(15-6 · 15c 는 같은 경로라 창으로 가른다 — PC · 서버 시계 차이가 그대로 섞인다).
             앱은 두 번째 누름이 로딩 중 버튼(AppButton isLoading → onPressed null)에 막혔는지도 말한다.
  E-EDGE-24  "새 사진 4장" 은 사진 세트의 얼굴 사진 한 장(face1.jpg)을 갤러리 훅으로 네 번 고른다(있던 칸은 앱이 removePhoto 로 비운다). Vision 4번.
  E-EDGE-25  패킷 버림은 에뮬을 adb root 로 올려 iptables 로 lo 밖 나가는 것을 버린다(우편함은 adb reverse = lo 라 그대로). root 가 남지 않게 묶음 맨 끝이다.
             "결과 기록" 가설이라 2분 뒤의 로딩 · 문구 · 화면은 무엇이든 pass 메모로 남기고, 앱이 2분을 다 기다리지 않았을 때만 fail 이다.

디스코드 — 7개 모두 0줄(신고 · 하트 인증 · 학생증 길을 안 부른다).
"""

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from urllib.parse import urlsplit

from e2e import area1, area2, emu, notify, tools
from e2e.area1 import Check, _app, _at, _find_user, _rows
from e2e.area1_b3 import _photos, _push
from e2e.area2 import _ONCE
from e2e.area2_phone3 import _wait_for
from e2e.area3 import _link, _match, _review_post, _send
from e2e.area3_phone import MISSING, _ok, _permitted, _person
from e2e.area3_phone3 import NOTICE_WAIT, TOKEN_WAIT
from e2e.area5_act import EXTRA, INTERESTS, _free_nickname, _new_bio, _paid_case, _profile, _set, _unlock
from e2e.area5_photo import FACE, _name, _photos_now
from e2e.area5_read import BACK, TITLES, _home, _saved
from e2e.area5_wd import EXPIRED, SETTLE, _Killed, _kill_soon
from e2e.tools import Blocked

NETWORK = '네트워크 연결을 확인해 주세요'  # common/failure.dart NetworkFailure
REVIEW_TITLE = '새 지인 리뷰가 도착했어요'  # friend_reviews/router.py new_friend_review
SCREENS = (('15-6', '15-5'), ('15c', '15-5'), ('06-1', '15-5'), ('tag', '15c'), ('15-7', '15-5'))  # (고친 화면, 저장 뒤 도착)
PATHS = {'15-6': ('PATCH', '/me/profile'), '15c': ('PATCH', '/me/profile'), '06-1': ('POST', '/profile-onboarding/ideal-conditions'),
         'tag': ('POST', '/profile-onboarding/interests'), '15-7': ('PUT', '/me/photos')}
OLD_HEIGHT, NEW_HEIGHT = 178, '181'
WHERE = {'chat': 'conversations', 'review': 'me'}  # 알림으로 연 화면의 시스템 뒤로 = 화살표(_exit) — 대화 목록(13) · 나 탭(15)
END = 'end'
APP_WAIT = 180  # 앱의 다음 말을 기다리는 초(Run.phone 기본값)
CUT_SETTLE = 2  # 비행기 모드를 켠 뒤 망이 정말 끊기기를 기다리는 초(E-EDGE-01)
DELAY_MS = 2000  # 시나리오 E-EDGE-21 "망 지연 2초"
LOG_SETTLE = 60  # Cloud Run 요청 로그가 logging 에 들어오기를 기다리는 초
LOG_LIMIT = 1000
WATCH = 120  # 시나리오 E-EDGE-25 "2분 기다림"
PHOTOS = 4


def _now():
    return datetime.now(timezone.utc)


# ── 공통 ────────────────────────────────────────────────────────────────────────────────────────────

def _walk(phone, hands):
    """멈춤 `화면:일` 마다 hands[일](화면) 을 부르고 앱을 보낸다 — [END] 멈춤에서 돌아간다(마지막 go 는 Run.phone 이 넣는다)."""
    def midway(said):
        while said.get('step') != END:
            screen, _, kind = (said.get('step') or '').rpartition(':')
            hand = hands.get(kind)
            if hand is None:
                raise Blocked(f"앱이 모르는 멈춤 {said.get('step')!r} 에서 섰다")
            hand(screen)
            phone.hub.go()
            said = phone.hub.wait(APP_WAIT)
            if said is None or 'result' in said:
                raise Blocked(f'앱이 끝 멈춤({END}) 전에 {"끝남" if said else "답하지 않음"} — {said.get("note") if said else ""}')
    return midway


def _prepare(run, account):
    """편집 다섯 화면의 처음 값 — 키 178 · 관심사 4개(하나 더 고를 자리) · 사진 2장 이상(맞바꿀 것). 처음 사진 순서를 돌려준다."""
    _set(run, account, f'키 {OLD_HEIGHT} · 관심사 4개', height_cm=OLD_HEIGHT, interest_tags=INTERESTS)
    photos = [r['id'] for r in _photos_now(run, account)]
    if len(photos) < 2:
        raise Blocked(f'준비: 사진 {len(photos)}장 — 맞바꿀 두 장이 없다')
    return photos


def _edited(check, run, account, photos, bio, label):
    """다섯 화면을 다 저장했다 — DB 의 키 · 자기소개 · 선호 나이 · 관심사 · 사진 순서."""
    db = _profile(run, account, 'height_cm,bio,preferred_age_min,preferred_age_max,interest_tags')
    check.that(db.get('height_cm') == int(NEW_HEIGHT), f"{label} 15-6: DB 키 {db.get('height_cm')!r}(기대 {NEW_HEIGHT})")
    check.that(db.get('bio') == bio, f"{label} 15c: DB 자기소개 {db.get('bio')!r}(기대 {bio!r})")
    ages = (db.get('preferred_age_min'), db.get('preferred_age_max'))
    check.that(ages == (19, 35), f'{label} 06-1: DB 선호 나이 {ages}(기대 (19, 35) — 상관없어요)')
    check.that(EXTRA in (db.get('interest_tags') or []), f"{label} 태그: DB 관심사 {db.get('interest_tags')}(기대 {EXTRA!r} 포함)")
    order = [r['id'] for r in _photos_now(run, account)]
    want = [photos[1], photos[0], *photos[2:]]
    check.that(order == want, f'{label} 15-7: DB 사진 순서 {order}(기대 첫 두 칸 맞바꿈 {want})')


# ── E-EDGE-01 끊긴 망에서 저장 ───────────────────────────────────────────────────────────────────────

def p_edge_01(run, phone, paid):
    check = Check()
    account, token = _home(run)
    photos = _prepare(run, account)
    bio, _ = _new_bio()
    seen = {}

    def edited(screen):  # 앱이 값을 고친 채 멈춤 — 그때 DB 를 찍고 망을 끊는다
        seen[screen] = _saved(run, account)
        notify.airplane(phone.serial, True)
        time.sleep(CUT_SETTLE)  # 켜자마자 앱이 저장을 누르면 망이 아직 살아 있어 첫 저장이 성공해 버린다(켤 때만 안 기다린다 — 끌 때는 notify 가 기다린다)

    def failed(screen):  # 끊긴 망에서 저장이 막힌 뒤 — DB 가 그대로인지 보고 망을 되돌린다
        check.that(_saved(run, account) == seen.get(screen), f'{screen}: 망이 끊긴 채 "저장" 했는데 DB 가 바뀜(기대 변화 0)')
        notify.airplane(phone.serial, False)

    paid()
    try:
        said = _app(check, phone(midway=_walk(phone, {'edited': edited, 'failed': failed}), token_hash=token, height=NEW_HEIGHT, bio=bio,
                                 extra=EXTRA))
    finally:
        notify.ensure_online(phone.serial)
    walks = {w.get('screen'): w for w in said.get('walks') or []}
    for screen, arrival in SCREENS:
        walk = walks.get(screen, {})
        check.that(walk.get('error', MISSING) == NETWORK, f"{screen}: 첫 저장 뒤 문구 {walk.get('error', MISSING)!r}(기대 {NETWORK!r})")
        check.that(walk.get('error_above') is True, f"{screen}: 문구가 저장 버튼 위 {walk.get('error_above', MISSING)}(기대 True)")
        check.that(walk.get('kept') is True, f"{screen}: 고친 값이 그대로 {walk.get('kept', MISSING)}(기대 True)")
        check.that(walk.get('stayed', MISSING) == TITLES[screen], f"{screen}: 첫 저장 뒤 화면 {walk.get('stayed', MISSING)!r}(기대 그대로 {TITLES[screen]!r})")
        check.that(walk.get('saved_title', MISSING) == TITLES[arrival],
                   f"{screen}: 망을 되돌린 뒤 저장하고 간 화면 {walk.get('saved_title', MISSING)!r}(기대 {TITLES[arrival]!r})")
    _edited(check, run, account, photos, bio, '두 번째 저장 뒤')
    return check.result('15c · 06-1 저장은 임베딩(유료)을 부른다 — E2E_REAL_AI=1 일 때만')


# ── E-EDGE-11 계정이 사라진 뒤 저장 ──────────────────────────────────────────────────────────────────

def p_edge_11(run, phone):
    check = Check()
    account, token = _home(run)
    _set(run, account, f'키 {OLD_HEIGHT}', height_cm=OLD_HEIGHT)
    gone = []

    def delete(said):  # 앱이 15-6 을 연 채 멈춘 사이 — auth 사용자를 지운다(관리자 API)
        area2._guard(run, account['id'])
        status, body = tools.admin(run.cfg, run.key, 'DELETE', f"users/{account['id']}")
        if status >= 300:
            raise Blocked(f'auth 사용자 지우기 {status} {body}')
        if _find_user(run, account['email']) is not None:
            raise Blocked('지운 auth 사용자가 관리자 목록에 남음')
        gone.append(True)

    said = _app(check, phone(midway=delete, token_hash=token, height=NEW_HEIGHT))
    check.that(bool(gone), '앱이 15-6 에서 멈추지 않고 끝남 — 계정을 지우지 못했다')
    check.that(said.get('login') is True, f"저장 뒤 02(로그인 화면) {said.get('login', MISSING)}(기대 닿음)")
    check.that(said.get('stayed') is False, f"저장 뒤 15-6 에 머묾 {said.get('stayed', MISSING)}(기대 아님)")
    check.that(said.get('notice', MISSING) == EXPIRED, f"02 알림 {said.get('notice', MISSING)!r}(기대 {EXPIRED!r})")
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select=height_cm")
    check.that(not rows or rows[0].get('height_cm') == OLD_HEIGHT, f'DB 키 {rows}(기대 바뀌지 않음 — 행이 없거나 {OLD_HEIGHT})')
    return check.result('auth 사용자 삭제 뒤 프로필 행은 cascade 로 사라진다 — "DB 변화 0" 은 새 키가 안 적힌 것으로 봤다')


# ── E-EDGE-15 알림으로 연 화면의 시스템 뒤로 ────────────────────────────────────────────────────────

def _back_from_tap(check, phone, kind):
    """알림으로 콜드 스타트한 앱이 그 화면에서 멈추면 시스템 뒤로 → 맨 앞 화면이 우리 앱인지 → 앱의 말(도착 화면)."""
    said = phone.hub.wait(APP_WAIT)
    if said is None or 'result' in said:
        _app(check, said, kind)
        check.that(False, f'{kind}: 알림으로 연 앱이 화면에서 멈추지 않음')
        return
    tools.adb(phone.serial, *BACK)
    time.sleep(1.5)  # 뒤로가 앱을 닫았다면 내려가는 시간
    top = phone.top()
    phone.hub.go()
    said = _app(check, phone.hub.result(APP_WAIT), kind)
    check.that(tools.PACKAGE in top, f'{kind}: 시스템 뒤로 뒤 앱이 닫힘(맨 앞 {top[:90]!r})')
    check.that(said.get('opened') is True, f"{kind}: 알림으로 그 화면이 열림 {said.get('opened', MISSING)}(기대 True)")
    check.that(said.get('where', MISSING) == WHERE[kind], f"{kind}: 시스템 뒤로 뒤 화면 {said.get('where', MISSING)!r}(기대 화살표와 같은 {WHERE[kind]!r})")


def p_edge_15(run, phone):
    notify.ensure_delivery(phone.serial)
    check = Check()
    me = _person(run)
    partner = _person(run)
    match_id = _match(run, me, partner)
    _link(run, partner, me)  # 추천 연결 — 상대가 나에게 지인 리뷰를 쓸 수 있는 사이
    _app(check, phone(token_hash=run.link(me['email']), phase='login'))
    if check.problems:
        return check.result()
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
    for kind, title, make in (('chat', partner['nickname'], lambda: _ok('상대가 보내기', _send(run, partner, match_id, 'E2E-EDGE-15'))),
                              ('review', REVIEW_TITLE, lambda: _ok('상대가 리뷰 남기기', _review_post(run, partner, me, **_ONCE)))):
        before = notify.read_notifications(phone.serial)
        notify.kill_app(phone.serial)
        make()
        new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT, match=lambda n, title=title: n.title == title)
        if not any(n.title == title for n in new):
            raise Blocked(f'{kind}: {NOTICE_WAIT}초 안에 알림 "{title}" 이 안 옴(새 알림 {len(new)}건) — 누를 것이 없다')
        phone.hub.tell({'case': phone.case, 'phase': kind, 'nickname': partner['nickname']})
        notify.tap_notification(phone.serial, title)
        _back_from_tap(check, phone, kind)
    return check.result('알림 둘은 상대가 API 로 만듦 — 도착 화면은 코드의 화살표(_exit) 길과 견줬다')


# ── E-EDGE-19 저장 직후 강제 종료 ────────────────────────────────────────────────────────────────────

def _killed_after_press(check, phone, part, **job):
    """앱이 저장을 누르자마자 멈춤 말 → PC 가 0.3초 뒤 죽인다 → kill 까지 ms. 죽일 때를 못 잡았으면 None."""
    try:
        said = phone(phase='press', part=part, midway=_kill_soon(phone), **job)
    except _Killed as killed:
        return killed.args[0]
    _app(check, said, part)
    check.that(False, f'{part}: 앱이 저장을 누른 뒤 멈추지 않고 끝남 — 죽일 때를 못 잡음')
    return None


def p_edge_19(run, phone):
    check = Check()
    notes = []
    # 닉네임
    account, token = _home(run)
    _unlock(run, account)
    old, new = _profile(run, account, 'nickname').get('nickname'), _free_nickname(run)
    ms = _killed_after_press(check, phone, 'nickname', token_hash=token, nickname=new)
    if ms is not None:
        time.sleep(SETTLE)
        db = _profile(run, account, 'nickname').get('nickname')
        said = _app(check, phone(phase='after', part='nickname'), '닉네임 다시 켬')
        check.that(db in (old, new), f'닉네임: DB {db!r}(기대 옛 {old!r} 또는 새 {new!r})')
        line = said.get('name_line', MISSING)
        # 15 히어로는 나이가 있으면 "닉네임, 나이", 없으면 닉네임만 그린다(profile_hero.dart) — 시작만 같은 더 긴 이름은 다른 이름이다
        check.that(isinstance(line, str) and (line == db or line.startswith(f'{db}, ')),
                   f'닉네임: 다시 켠 15 이름 줄 {line!r}(기대 DB 값 {db!r} 또는 "{db}, 나이")')
        notes.append(f"닉네임 {'저장됨' if db == new else '옛 값'}({ms}ms 에 kill)")
    # 사진 맞바꾸기
    account, token = _home(run)
    before = [r['id'] for r in _photos_now(run, account)]
    if len(before) < 2:
        raise Blocked(f'준비: 사진 {len(before)}장 — 맞바꿀 두 장이 없다')
    ms = _killed_after_press(check, phone, 'photo', token_hash=token)
    if ms is not None:
        time.sleep(SETTLE)
        rows = _photos_now(run, account)
        said = _app(check, phone(phase='after', part='photo'), '사진 다시 켬')
        names = [_name(r) for r in rows]
        check.that(2 <= len(rows) <= 4, f'사진: DB profile_photos {len(rows)}행(기대 2~4)')
        sources = [r for r in rows if r.get('is_avatar_source')]
        check.that(len(sources) == 1, f'사진: is_avatar_source {len(sources)}개(기대 정확히 1)')
        check.that(said.get('photos', MISSING) == names, f"사진: 다시 켠 15-5 사진 {said.get('photos', MISSING)}(기대 DB 순서 {names})")
        order = [r['id'] for r in rows]
        notes.append(f"사진 {'저장됨' if order != before else '옛 값'}({ms}ms 에 kill, {len(rows)}행)")
    return check.result(' · '.join(notes) + ' — 강제 종료 대신 run-as kill -9(E-EDGE-20 과 같다)')


# ── 에뮬 망 · Cloud Run 요청 로그 ──────────────────────────────────────────────────────────────────────

def _emu(serial, *words):
    """에뮬 콘솔(adb emu) — 에뮬이 아니면 blocked."""
    emu.require_emulator(serial)
    tools.adb(serial, 'emu', *words, check=False)


def _net_normal(serial):
    _emu(serial, 'network', 'speed', 'full')
    _emu(serial, 'network', 'delay', 'none')


def _stamp(at):
    return at.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')


def _requests(since, until):
    """Cloud Run 요청 로그 [(받은 시각, 메서드, 경로)] — gcloud logging read. 못 읽으면 blocked(요청 수는 이것 말고 볼 곳이 없다)."""
    query = f'resource.type="cloud_run_revision" AND httpRequest.requestMethod:* AND timestamp>="{_stamp(since)}" AND timestamp<="{_stamp(until)}"'
    command = ['gcloud', 'logging', 'read', query, '--format=json', f'--limit={LOG_LIMIT}']
    try:  # 윈도는 gcloud 가 .cmd 라 shell 로 부른다(목록을 cmd 규칙으로 따옴표 친다)
        out = subprocess.run(command, **tools.TEXT, check=True, shell=os.name == 'nt').stdout
        entries = json.loads(out or '[]')
    except (subprocess.CalledProcessError, OSError, ValueError) as e:
        raise Blocked(f'Cloud Run 요청 로그를 못 읽음({type(e).__name__}: {getattr(e, "stderr", "") or e}) — gcloud logging read 권한 확인') from e
    rows = []
    for entry in entries:
        request = entry.get('httpRequest') or {}
        rows.append((_at(entry['timestamp']), request.get('requestMethod'), urlsplit(request.get('requestUrl', '')).path))
    return rows


def _windows(phone):
    """앱이 `화면:start` · `화면:done` 에서 멈출 때 PC 시계로 창을 찍는 손 — {화면: [시작, 끝]}."""
    windows = {}
    return windows, {'start': lambda screen: windows.setdefault(screen, []).append(_now()),
                     'done': lambda screen: windows.setdefault(screen, []).append(_now())}


def _count_in(check, windows, screens):
    """창마다 그 화면 저장 경로의 요청 수 — 1건이어야 한다. 로그가 들어올 때까지 LOG_SETTLE 초 쉰 뒤 한 번 읽는다."""
    bounds = [w for w in windows.values() if len(w) == 2]
    if len(bounds) != len(screens):
        raise Blocked(f'창을 다 못 찍음({len(bounds)}/{len(screens)}) — 앱이 멈춤을 건너뛰었다')
    time.sleep(LOG_SETTLE)
    logs = _requests(min(w[0] for w in bounds), max(w[1] for w in bounds))
    counts = {}
    for screen in screens:
        start, end = windows[screen]
        method, path = PATHS[screen]
        counts[screen] = len([1 for at, m, p in logs if start <= at <= end and (m, p) == (method, path)])
        check.that(counts[screen] == 1, f'{screen}: {method} {path} 요청 {counts[screen]}건(기대 1건)')
    return counts


# ── E-EDGE-21 두 번 누르기 ────────────────────────────────────────────────────────────────────────────

def p_edge_21(run, phone, paid):
    emu.require_emulator(phone.serial)
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    photos = _prepare(run, account)
    nickname, (bio, _) = _free_nickname(run), _new_bio()
    windows, hands = _windows(phone)
    paid()
    _emu(phone.serial, 'network', 'delay', str(DELAY_MS))
    try:
        said = _app(check, phone(midway=_walk(phone, hands), token_hash=token, nickname=nickname, height=NEW_HEIGHT, bio=bio, extra=EXTRA))
    finally:
        _net_normal(phone.serial)
    walks = {w.get('screen'): w for w in said.get('walks') or []}
    for screen, arrival in SCREENS:
        walk = walks.get(screen, {})
        check.that(walk.get('second_blocked') is True, f"{screen}: 두 번째 누름이 로딩 중 버튼에 막힘 {walk.get('second_blocked', MISSING)}(기대 True)")
        check.that(walk.get('saved_title', MISSING) == TITLES[arrival], f"{screen}: 저장 뒤 화면 {walk.get('saved_title', MISSING)!r}(기대 {TITLES[arrival]!r})")
    counts = _count_in(check, windows, [s for s, _ in SCREENS])
    db = _profile(run, account, 'nickname,nickname_changed_at')
    check.that(db.get('nickname') == nickname, f"15-6: DB 닉네임 {db.get('nickname')!r}(기대 {nickname!r})")
    check.that(db.get('nickname_changed_at') is not None, '15-6: nickname_changed_at 이 안 바뀜(기대 한 번 바뀜)')
    _edited(check, run, account, photos, bio, '저장 뒤')
    return check.result(f'에뮬 망 지연 {DELAY_MS}ms · 화면별 요청 {counts}(PC 시계 창 — 서버 시계와의 차이가 섞인다)')


# ── E-EDGE-24 느린 망에서 사진 4장 ────────────────────────────────────────────────────────────────────

def p_edge_24(run, phone):
    emu.require_emulator(phone.serial)
    _photos(run, FACE)  # 계정을 만들기 전에 파일부터
    check = Check()
    account, token = _home(run)
    before = {r['id'] for r in _photos_now(run, account)}
    _push(phone, run, FACE)
    windows, hands = _windows(phone)
    _emu(phone.serial, 'network', 'speed', 'edge')
    _emu(phone.serial, 'network', 'delay', 'gprs')
    try:
        said = _app(check, phone(midway=_walk(phone, hands), token_hash=token, photo=FACE, count=PHOTOS))
    finally:
        _net_normal(phone.serial)
    check.that(said.get('loading_kept') is True, f"저장이 끝날 때까지 버튼 로딩 유지 {said.get('loading_kept', MISSING)}(기대 True)")
    check.that(said.get('extra_tap_blocked') is True, f"로딩 중 다시 누름 막힘 {said.get('extra_tap_blocked', MISSING)}(기대 True)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"끝난 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('photos', MISSING) == PHOTOS, f"15-5 사진 {said.get('photos', MISSING)}장(기대 {PHOTOS}장)")
    rows = _photos_now(run, account)
    check.that(len(rows) == PHOTOS, f'DB 사진 {len(rows)}장(기대 {PHOTOS}장)')
    check.that(not before & {r['id'] for r in rows}, '옛 사진 행이 남음(기대 새 사진 4장)')
    check.that(len([r for r in rows if r.get('is_avatar_source')]) == 1, '아바타 원본 표시가 한 개가 아님')
    counts = _count_in(check, windows, ['15-7'])
    return check.result(f"edge + gprs 지연 · 저장 요청 {counts['15-7']}건 · Vision {PHOTOS}번(새 사진마다)")


# ── E-EDGE-25 응답 없는 망 ────────────────────────────────────────────────────────────────────────────

_DROP = ('OUTPUT', '!', '-o', 'lo', '-j', 'DROP')


def _drop(serial):
    for table in ('iptables', 'ip6tables'):
        tools.adb(serial, 'shell', table, '-I', *_DROP[:1], '1', *_DROP[1:], check=False)


def _undrop(serial):
    for table in ('iptables', 'ip6tables'):
        tools.adb(serial, 'shell', table, '-D', *_DROP, check=False)


def p_edge_25(run, phone):
    serial = phone.serial
    emu.require_emulator(serial)
    emu.root(serial, getattr(phone, 'hub', None))
    check = Check()
    account, token = _home(run)
    _set(run, account, f'키 {OLD_HEIGHT}', height_cm=OLD_HEIGHT)

    def ready(screen):  # 앱이 값을 고친 채 멈춤 — 나가는 패킷을 버린다
        _drop(serial)
        if emu.online(serial):
            raise Blocked('패킷을 버렸는데 핑이 닿음 — iptables 가 안 먹었다(root 인가)')

    try:
        said = _app(check, phone(midway=_walk(phone, {'ready': ready, 'watched': lambda screen: _undrop(serial)}), token_hash=token,
                                 height=NEW_HEIGHT, watch=WATCH))
    finally:
        _undrop(serial)
    waited = said.get('waited_ms')
    check.that(isinstance(waited, int) and waited >= (WATCH - 1) * 1000, f'앱이 저장 뒤 기다린 시간 {waited}ms(기대 {WATCH}초)')
    if check.problems:
        return check.result()
    loading, error, title = said.get('loading_at_end', MISSING), said.get('error', MISSING), said.get('title', MISSING)
    height = _profile(run, account, 'height_cm').get('height_cm')
    return check.result(f'{WATCH}초 뒤 로딩 {loading} · 문구 {error!r} · 화면 {title!r} · 망을 되돌린 뒤 DB 키 {height} — '
                        '앱에 요청 시간 제한이 없다(frontend/lib 에 .timeout( 0건), 결과 기록')


PHONE = {
    'E-EDGE-01': _paid_case('E-EDGE-01', p_edge_01), 'E-EDGE-11': p_edge_11, 'E-EDGE-15': _permitted(p_edge_15), 'E-EDGE-19': p_edge_19,
    'E-EDGE-21': _paid_case('E-EDGE-21', p_edge_21), 'E-EDGE-24': p_edge_24, 'E-EDGE-25': p_edge_25,
}
EMULATOR = ['E-EDGE-21', 'E-EDGE-24', 'E-EDGE-25']  # --device B — 25 가 adb root 를 남기므로 맨 끝

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-edge'] = list(PHONE)
tools.CASE_LIMITS.update({
    'E-EDGE-01': 900,  # 다섯 화면 × (끊기 · 되돌리기 8초 기다림 · 저장 둘)
    'E-EDGE-11': 600,
    'E-EDGE-15': 900,  # 로그인 · 토큰 + 알림 둘(60초씩) · 눌러 열기
    'E-EDGE-19': 900,  # 계정 둘 · 앱 네 번
    'E-EDGE-21': 900 + LOG_SETTLE,  # 다섯 화면 × 2초 지연 + 로그 기다림
    'E-EDGE-24': 900 + LOG_SETTLE,  # 느린 망 사진 4장 + 로그 기다림
    'E-EDGE-25': WATCH + 2 * APP_WAIT + 300,
})
