"""영역 3 폰 A 한 대 3차 — 꺼진 앱에서 알림을 눌러 그 방이 열리는지 1개(E-CHAT-32, 묶음 area3-phone-3).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본). 앱 쪽은 frontend/integration_test/area3_b3.dart 의 같은 번호.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 폰 계정 · 상대 · 매칭을 만들고 앱을 홈까지 켠 뒤(phase 'login'), 앱을 죽이고
상대가 API 로 한 건 보내 알림을 기다리고, 일감(phase 'tap')을 우편함에 먼저 넣은 다음 알림을 눌러 앱을 콜드 스타트시킨다. 앱은 열린 방에서 본 것만
말하고 판정은 여기서 한다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  B에뮬 → 폰 한 대   폰 계정이 받는 쪽 B, 보내는 쪽 A 는 상대 계정이 API 로 보낸다(앱이 보내는 판이 아니다).
  `am force-stop`     쓰지 않는다 — 안드로이드가 "멈춘 앱" 으로 표시해 FCM 이 안 온다. notify.kill_app(HOME → am kill → run-as kill)으로 프로세스만 죽인다.
  "10초까지 기다림"   앱은 방(ChatRoomScreen)이 열리기를 30초까지(로그인 · 관문 조회 · 라우터가 눌러 둔 경로를 받아 주는 시간) 기다리고, 방이 열린
                     뒤 닉네임 · 메시지를 10초까지 기다린다. 방이 안 열린 채 약관 · 온보딩에 머물면 그 화면 이름이 메모에 남는다.
  알림 도착 시각      notify.wait_new 가 2초마다 읽으므로 "알림 도착까지 N초" 는 2초 단위 근사다.
  화면 읽는 방법      시나리오는 integration_test 밖 + `uiautomator dump` 화면 글자인데, 구현은 integration_test 앱 안에서 위젯 트리(앱바 닉네임 ·
                     말풍선 본문)로 본다. 밤에도 돈다 — new_message 는 조용한 시간 예외(backend cards/push.py _QUIET_HOURS_EXEMPT)다.
"""

import secrets
import time

from e2e import area1, area3, notify
from e2e.area1 import Check, _app, _rows
from e2e.area2_phone3 import _wait_for
from e2e.area3 import _match, _send
from e2e.area3_phone import MISSING, _me, _ok, _permitted, _person
from e2e.tools import Blocked

TOKEN_WAIT = 30  # 기기 토큰이 서버에 올라오기를 기다리는 초(area2_phone3 p_card_02 와 같다)
NOTICE_WAIT = 60  # 알림이 오기를 기다리는 초(시나리오 4-1 의 T)
APP_WAIT = 90  # 눌린 앱이 방을 읽고 말하기를 기다리는 초(앱 안의 30 + 10 + 10초 기다림이 모두 끝나도 남는 여유)
SEEN = (('room', '방 화면'), ('nickname', '앱바 닉네임'), ('message', '방금 메시지'))
SCREEN_LABELS = {'login': '로그인', 'consent': '약관 동의', 'consent-renew': '약관 갱신', '3b': '학생 인증', '3c': '학교 정보',
                 '04-1': '온보딩 기본 정보', 'home': '홈', 'conversations': '대화 목록'}  # area3_b3.dart _screensNow 의 이름


def _screens(said):
    return ' · '.join(f'{name}({SCREEN_LABELS.get(name, "?")})' for name in said.get('screen') or []) or '없음'


def p_chat_32(run, phone):
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    me, token = _me(run)
    partner = _person(run)
    match_id = _match(run, me, partner)
    _app(check, phone(token_hash=token, phase='login'))
    if check.problems:  # 홈에 못 닿았으면 토큰도 알림도 기대할 수 없다
        return check.result()
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
    before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
    notify.kill_app(phone.serial)
    body = f'E2E-32-{secrets.token_hex(4)}'
    _ok('상대가 보내기', _send(run, partner, match_id, body))
    sent = time.monotonic()
    new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT)
    arrived = time.monotonic() - sent
    check.that(any((n.title, n.text) == (partner['nickname'], body) for n in new),
               f'{NOTICE_WAIT}초 안에 알림 "{partner["nickname"]} / {body}" 없음(새 알림 {len(new)}건)')
    if check.problems:
        return check.result()
    # 누르기 전에 일감을 넣는다 — 알림으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 이것을 가져간다(phone() 의 monkey 시작이 아니다)
    phone.hub.tell({'case': phone.case, 'phase': 'tap', 'nickname': partner['nickname'], 'body': body})
    notify.tap_notification(phone.serial, partner['nickname'])
    said = _app(check, phone.hub.result(APP_WAIT))
    if said:
        for key, label in SEEN:
            check.that(said.get(key) is True, f'{label}({key}) {said.get(key, MISSING)}(기대 True)')
        if not all(said.get(key) is True for key, _ in SEEN):
            check.problems.append(f'그때 보인 화면 {_screens(said)}')
    return check.result(f"알림 도착까지 {arrived:.0f}초(2초마다 확인) · 앱이 방을 연 시각 {said.get('opened_at', MISSING)}(앱 시계, "
                        f"일감 받은 뒤 {said.get('room_ms', MISSING)}ms — 앱 부팅 시간 포함)")


PHONE3 = {'E-CHAT-32': _permitted(p_chat_32)}

area1.PHONE.update(PHONE3)
area3.BUNDLES['area3-phone-3'] = list(PHONE3)
