"""영역 3 알림 10개(E-CHAT-17 · 26 · 27 · 28 · 29 · 30 · 31 · 33 · 35 · 59, 묶음 area3-chat-nt). 앱 쪽은 frontend/integration_test/area3_chat_nt.dart 의 같은 번호.
기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 그 줄이다.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. 받는 쪽 B 는 폰 계정이고 보내는 쪽 A 는 PC 가 상대 계정 토큰으로 API 를 불러 대신한다(단일 폰 — 두 기기 없음).
알림은 PC 가 `dumpsys notification` 으로 읽고, 앱은 화면에서 본 것(방 · 목록 · 스위치)만 말한다. 판정은 여기서 한다.
알림 길(읽기 · 토큰 · FCM)이 죽은 폰에서 서버 규칙이 틀렸다는 허위 fail 이 나지 않게 대조를 둔다. 대조는 새 상대가 새 방에서 보낸 메시지 1건이다(폰 계정의 읽음 시각 창 · 스위치와
무관한 방 — 같은 방으로 보내면 서버가 막아 길이 죽은 것으로 오해한다):
  "알림 0건" 이 기대값인 28 · 30 · 35 · 59   대조가 안 오면 fail 이 아니라 blocked(28 은 창이 닫힌 뒤 같은 상대의 메시지, 35 는 권한을 켜고 다시 로그인한 뒤의 새 방 메시지).
  "알림 1건" 이 기대값인 29 · 33   기대한 알림(둘째 · 켠 뒤)이 안 오면 곧바로 fail 하지 않고 새 방 대조를 보낸다 — 그것도 안 오면 blocked("알림 길이 죽음"), 그것만 오면 fail(서버 규칙 어긋남).
  33 은 서버의 스위치 값이 켜진 채일 때만 대조한다(꺼진 채면 대조도 막히므로 서버 값 어긋남으로 바로 fail).
  26 · 27 · 17 · 31   오는 알림 자체가 증거라 대조가 없다(안 오면 fail).

낮 제한은 걸지 않는다 — new_message 는 backend cards/push.py 의 `_QUIET_HOURS_EXEMPT` 에 들어 있어 방해 금지 시간(22~08시)에도 간다(E-CHAT-34 · E-PUSH-33 이 본다).
푸시 연결 점검(notify.ensure_delivery)은 가설마다 시작에 한 번.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  A 폰 + B 에뮬 → 폰 한 대   받는 쪽 B 가 폰 계정, 보내는 쪽 A 는 PC 가 API 로 보낸다(A 쪽 화면 · 알림은 안 본다).
  E-CHAT-17  "B: 앱 밖(HOME)" 알림 본문 "첫줄 둘째줄" 은 앱 밖에서 읽고(서버가 줄바꿈을 공백으로 바꿈 — chat/router.py:264), "B 방 화면 2줄" 은 알림을 눌러 연 방이 아니라 앱을 새로
             켜(1회용 토큰으로 다시 로그인) 목록 → 방으로 들어가 읽는다. 2줄은 말풍선 글이 줄바꿈 그대로(`\n`)인지와, 그 글을 그려진 폭으로 다시 짜 본 줄 수로 본다. 서버가 저장한
             글에 줄바꿈이 남았는지는 DB 로 따로 본다.
  E-CHAT-26  "도착까지 시간" 은 2초마다 읽는 근사 · 기준 없음(메모에만). 알림이 한 번만 왔는지 SETTLE(20초) 더 본다 — 시나리오에 없는 추가 확인.
  E-CHAT-27  50자 글 = 영문 12 + 한글 38. 서버는 파이썬 슬라이스(코드포인트)로 자르는데 한글은 BMP 라 UTF-16 칸 수와 같다 — 둘이 갈리는 이모지 경계는 이번에 안 본다.
  E-CHAT-28  "들어간 지 10초" 의 시계 — 서버가 "방에 있다" 를 아는 것은 앱이 방에 들어올 때 찍는 last_read_at(30초 창, chat/router.py:129-134)뿐이다. PC 는 그 시각이 DB 에 찍힌 것을
             보고 HOME → 보낸 뒤, 서버가 찍은 두 값(보낸 글의 created_at − last_read_at)의 차를 읽는다. 0~25초(서버 창 30초 − 여유 5초)를 벗어나면 서버 창을 못 믿어 blocked, 10초를 넘으면 메모에 적는다. 방 화면인 채로 HOME 이라 방 화면 · 앱
             프로세스는 살아 있다. "0건" 은 60초 지켜보고, 창이 닫힌 뒤 같은 상대의 메시지가 알림이 되는지로 길을 확인한다.
  E-CHAT-29  "A: 10초 뒤 1건 → 40초 뒤 1건 더" 의 40초는 방에서 나와 HOME 한 때부터다(첫 건 뒤 25초 지켜보고 5초 더 기다려 맞춘다 — 서버 창 30초를 넘기려고). 알려진 한계(서버 눈대중)를
             확인하는 판이지 바람직하다는 판정이 아니다. 두 번째 알림은 60초까지, 정확히 1건(20초 더 봄). 첫 메시지의 알림이 뒤늦게 와도 fail.
  E-CHAT-30  앱이 대화 목록에서 멈춘 사이 PC 가 보내고, 앱이 30초까지 목록 마지막 줄 · 뱃지를 지켜본다(새로고침 안 누름). 서버가 실제로 FCM 을 보냈는지는 못 본다(보낸 건수 없음) —
             목록이 저절로 바뀐 것이 푸시가 앱에 닿았다는 증거다. 앞에 있어 "알림 0건" 이 정상이라, 지켜본 뒤 HOME 으로 내려 대조 메시지가 알림이 되는지 본다(area4_push_front 와 같은 길).
             "앞에 머물렀다" 는 앱이 목록이 바뀐 것을 본 그 순간(PC 가 HOME 으로 내리기 전)에 잰 화면(list_front)과 앱 생명주기(resumed)로 본다.
  E-CHAT-31  앱을 HOME 으로 내린 채(프로세스 살아 있음) 알림을 누른다 — 꺼진 앱(콜드 스타트)은 E-CHAT-32 의 몫. 시나리오의 `uiautomator dump` 화면 글자가 아니라 앱 안의 위젯 트리(앱바 닉네임 ·
             말풍선)로 읽고, 방이 열리기를 30초 · 닉네임 · 글을 10초까지 기다린다(10초 판정은 아님).
  E-CHAT-33  앱이 16d 에서 "새 메시지" 스위치를 직접 누른다. 서버 값은 notification_settings 를 읽어 확인한다. 끈 동안은 HOME → 상대 보내기 → 60초 0건, 켠 뒤는 HOME → 보내기 → 1건
             (켠 뒤 오는 알림이 끈 동안 "0건" 의 대조를 겸한다. 그것이 안 오면 새 방 대조로 길을 확인해 blocked/fail 을 가른다). 끈 뒤 앱을 monkey 로 다시 앞으로 가져와 2초 기다린다.
  E-CHAT-35  시나리오는 에뮬 `pm revoke` 뒤 로그인 — 폰에서도 같다. `_permitted`(권한을 먼저 주는 래퍼)를 쓰지 않는 유일한 가설이라 끝에 권한을 거둔 채로 돌려놓는다. 로그인 뒤 뜨는 첫 권한
             창은 "허용 안 함" 을 누르고(안 뜨는 폰이면 메모) 권한이 꺼진 채인지 `dumpsys package` 로 확인한다(못 읽거나 켜져 있으면 blocked). "방 안 ≤ 2.0초" 는 E-CHAT-10 · 67 과 같은
             판정(앱 시계 − 서버가 찍은 보낸 시각, 시계 차로 음수면 표시만 판정). 대조: 끝에 권한을 켜고 다시 로그인한 뒤 새 상대가 새 방에서 보낸 메시지가 알림이 되는지(같은 방은 방금 입장한 읽음 시각 창에 걸릴 수 있다). 권한이 꺼졌는데 push_tokens 에 행이 있는지는 메모만
             (push_registrar.dart:31-35 는 E-PUSH-59 가 판정한다).
  E-CHAT-59  나가기 API 를 부른 뒤 나감 줄(kind=left) 1개를 DB 로 확인해 "나갔다" 를 증명하고, 60초 0건 + 대조 메시지로 판정한다.
  영역 4 와 겹침  E-PUSH-24 · 25 · 26 · 27 · 31 · 32 · 34 가 같은 길의 가까운 판이다(별칭이 아니다 — 방 · 목록 · 앱 설정을 직접 읽는 점이 다르다).
"""

import functools
import re
import secrets
import time

from e2e import area1, area3, area3_phone, area4, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3 import _count, _send
from e2e.area3_phone import MISSING, _me, _ok, _permitted, _person
from e2e.area3_phone3 import SEEN, _screens
from e2e.area3_phone5 import LIVE_LIMIT, _at
from e2e.area4 import stepper
from e2e.area4_push import SETTLE, _Scene
from e2e.area4_push_a4 import DIALOG_WAIT, GONE_WAIT, _front, _granted, _is_deny, _tap_node, _tokens
from e2e.area4_push_front import _silent_then_control
from e2e.tools import Blocked

HELLO = '안녕하세요'
LINES = '첫줄\n둘째줄'
LINES_PREVIEW = '첫줄 둘째줄'  # chat/router.py:264 가 줄바꿈을 공백으로 바꾼다
PREVIEW_LENGTH = 40  # chat/router.py:22-23 PUSH_PREVIEW_LENGTH
TOKEN_WAIT = 30  # 기기 토큰이 서버에 올라오기를 기다리는 초(area3_phone3 와 같다)
CONTROL_WAIT = 30  # 대조 알림을 기다리는 초
STAMP_WAIT = 15  # 방에 들어오거나 나올 때 앱이 찍는 읽음 시각(last_read_at)이 서버에 보이기를 기다리는 초
SERVER_WINDOW = 30  # chat/router.py:21 IN_ROOM_WINDOW — 읽음 시각이 이보다 새로우면 서버는 알림을 안 보낸다
IN_ROOM_LIMIT = 25  # 28: 읽음 시각을 본 뒤 이 안에 보내야 서버 창(30초) 안이라 믿는다(시계 · 요청 지연 여유)
IN_ROOM_SCENARIO = 10  # 28: 시나리오가 말한 "들어간 지 10초 안"
FIRST_AT = 10  # 29: 방에서 나와 HOME 한 뒤 첫 메시지를 보내는 초
SECOND_AT = 40  # 29: 두 번째 메시지를 보내는 시점(HOME 뒤 초) — 서버 창 30초를 넘긴 뒤
FIRST_WATCH = 25  # 29: 첫 메시지 뒤 알림이 안 뜨는지 지켜보는 초
SECOND_WAIT = 60  # 29: 두 번째 알림을 기다리는 초
SWITCH_SAVE = 10  # 33: 앱이 스위치를 누른 뒤 서버(notification_settings)에 값이 쓰이기를 기다리는 초
FRONT_SETTLE = 2  # 33 · 35: monkey 로 앱을 앞으로 가져온 뒤 프레임이 다시 돌기를 기다리는 초(곧바로 go 를 넣으면 앱이 아직 뒤에 있다)

# 가설 하나에 줄 시간(초) — 기다림이 전부 최대로 걸릴 때의 합 + MARGIN 을 60 단위로 올린다. 기본(tools.CASE_LIMIT 420)에 들면 따로 안 올린다.
BOOT = 90  # 앱 켜기 → 로그인 → 홈까지
CONNECT = notify.DELIVERY_WAIT + 15  # 푸시 연결 점검(notify.ensure_delivery — Wi-Fi 껐다 켜기)
SETUP = 30  # 계정 · 방 준비 API
ROOM = 40  # 방을 열고 읽기를 끝낼 때까지(앱 안의 15초 + 여유)
TAP = 60  # notify.tap_notification(세 번 눌러 보기까지)
TAP_APP = 90  # 눌린 앱이 방을 읽고 말하기를 기다리는 초(area3_phone3.APP_WAIT)
NOTICE = notify.NOTICE_WAIT
MARGIN = 120
WORST = {
    'E-CHAT-17': CONNECT + SETUP + BOOT + TOKEN_WAIT + NOTICE + SETTLE + BOOT + ROOM,  # 알림 → 앱을 새로 켜 방 열기
    'E-CHAT-26': CONNECT + SETUP + BOOT + TOKEN_WAIT + NOTICE + SETTLE,
    'E-CHAT-27': CONNECT + SETUP + BOOT + TOKEN_WAIT + NOTICE + SETTLE,
    'E-CHAT-28': CONNECT + SETUP + BOOT + TOKEN_WAIT + ROOM + STAMP_WAIT + NOTICE + CONTROL_WAIT,
    'E-CHAT-29': CONNECT + SETUP + BOOT + TOKEN_WAIT + ROOM + STAMP_WAIT + SECOND_AT + SECOND_WAIT + SETTLE,
    'E-CHAT-30': CONNECT + SETUP + BOOT + TOKEN_WAIT + ROOM + 30 + NOTICE + CONTROL_WAIT,  # 30: 목록이 저절로 바뀌기를 기다리는 30초
    'E-CHAT-31': CONNECT + SETUP + BOOT + TOKEN_WAIT + NOTICE + TAP + TAP_APP,
    'E-CHAT-33': CONNECT + SETUP + BOOT + TOKEN_WAIT + 60 + 2 * SWITCH_SAVE + 2 * NOTICE + 15 + 20 + SETTLE,  # 60: 16d 까지 · 15: 앞으로 · 20: 두 번째 누름
    'E-CHAT-35': CONNECT + SETUP + BOOT + DIALOG_WAIT + GONE_WAIT + NOTICE + 15 + ROOM + 10 + BOOT + TOKEN_WAIT + CONTROL_WAIT,  # 15: 앞으로 · 10: 방 안 실시간
    'E-CHAT-59': CONNECT + SETUP + BOOT + TOKEN_WAIT + NOTICE + CONTROL_WAIT,
}


def _say(run, partner, match_id, body):
    """상대(A)가 API 로 보낸다 — 두 번 가면 "1건" 이 깨지므로 다시 시도하지 않는다."""
    _ok('상대가 보내기', _send(run, partner, match_id, body, retry=False))


def _scene(case):
    """받는 사람(폰 계정)을 홈까지 켜 토큰이 올라온 뒤 HOME 에 내려 둔 장면에서 [case] 를 돈다. 낮 제한은 없다 — new_message 는 조용한 시간 예외."""
    @functools.wraps(case)
    def wrapped(run, phone):
        scene = _Scene(run, phone, daytime=False)
        if scene.ready:
            case(scene)
        return scene.check.result('; '.join(scene.notes))
    return _permitted(wrapped)


def _arrival(scene, before, title, text=None):
    """알림이 올 때까지의 초(2초마다 읽는 근사)와 온 알림들. [text] 가 없으면 제목만 본다. 도착 뒤 SETTLE 초 더 봐 같은 알림이 또 오면 fail."""
    sent = time.monotonic()
    new = notify.wait_new(scene.phone.serial, before, seconds=notify.NOTICE_WAIT,
                          match=lambda n: n.title == title and (text is None or n.text == text))
    seconds = time.monotonic() - sent
    got = [n for n in new if n.title == title and (text is None or n.text == text)]
    scene.check.that(got, f'{notify.NOTICE_WAIT}초 안에 알림 "{title} / {text}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
    if got:  # 한 번 읽을 때 둘이 같이 와 있을 수도 있으니 got 도 센다
        more = [n for n in notify.expect_none(scene.phone.serial, [*before, *got], seconds=SETTLE) if n.title == title]
        scene.check.that(len(got) + len(more) == 1, f'같은 알림이 {len(got) + len(more)}건(기대 1): {notice_memo([*got, *more])}')
    return seconds, got


@_scene
def chat_26(scene):
    match_id = factory.match(scene.run, scene.me, scene.partner)
    before = scene.before()
    _say(scene.run, scene.partner, match_id, HELLO)
    seconds, got = _arrival(scene, before, scene.nick, HELLO)
    if got:
        scene.notes.append(f'알림 도착까지 {seconds:.0f}초(2초마다 확인 — 문서에 기준 없음)')


@_scene
def chat_27(scene):
    text = f'E2E27-{secrets.token_hex(3)}' + ('가나다라마바사아자차카타파하' * 3)[:38]  # 영문 12 + 한글 38 = 50자. 한글은 BMP 라 코드포인트 수 = UTF-16 칸 수
    assert len(text) == 50
    match_id = factory.match(scene.run, scene.me, scene.partner)
    before = scene.before()
    _say(scene.run, scene.partner, match_id, text)
    _, got = _arrival(scene, before, scene.nick)
    if got:
        shown = got[0].text
        scene.check.that(len(shown) == PREVIEW_LENGTH, f'알림 본문 {len(shown)}자(기대 정확히 {PREVIEW_LENGTH}): {shown!r}')
        scene.check.that(shown == text[:PREVIEW_LENGTH], f'알림 본문이 글의 앞 {PREVIEW_LENGTH}자가 아님: {shown!r}')


@_scene
def chat_17(scene):
    match_id = factory.match(scene.run, scene.me, scene.partner)
    before = scene.before()
    _say(scene.run, scene.partner, match_id, LINES)
    stored = [row.get('body') for row in _rows(scene.run, f'messages?match_id=eq.{match_id}&select=body')]
    scene.check.that(stored == [LINES], f'서버에 저장된 글 {stored!r}(기대 줄바꿈 그대로 {[LINES]!r})')
    _, got = _arrival(scene, before, scene.nick, LINES_PREVIEW)
    if not got:
        return
    said = _app(scene.check, scene.phone(token_hash=scene.run.link(scene.me['email']), phase='room', nickname=scene.nick, body=LINES), 'B 방 화면')
    if said:
        scene.check.that(said.get('shown') is True, f"방에 줄바꿈 그대로의 말풍선이 없음(보인 말풍선 {said.get('bodies', '?')})")
        scene.check.that(said.get('lines') == 2, f"방 화면 {said.get('lines', '?')}줄(기대 2)")


@_scene
def chat_59(scene):
    match_id = factory.match(scene.run, scene.me, scene.partner)
    before = scene.before()
    scene.reply('상대 나가기', _api(scene.run, 'POST', f'/chat/matches/{match_id}/leave', scene.partner['token']), 200)
    lines = _count(scene.run, f'messages?match_id=eq.{match_id}&kind=eq.left')
    scene.check.that(lines == 1, f'나감 줄 {lines}개(기대 1) — 나가기가 안 됐으면 "알림 0건" 은 아무것도 증명하지 못한다')
    scene.silent(before)


# ── 앱이 방 · 목록 · 설정을 열어 두고 PC 가 그사이 알림을 지켜보는 판 ─────────────────────────────────

class _Rig:
    """폰 계정 [me](받는 쪽 B) · 상대 [partner](보내는 쪽 A) · 둘의 방. 방은 DB 로 만들어 알림이 안 간다 — 폰 계정의 읽음 시각은 비어 있다."""

    def __init__(self, run, phone):
        notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
        self.run, self.phone, self.check = run, phone, Check()
        self.me, self.token = _me(run)
        self.partner = _person(run)
        self.match_id = factory.match(run, self.me, self.partner)
        self.nick = self.partner['nickname']

    @property
    def serial(self):
        return self.phone.serial

    def job(self, **more):
        return {'token_hash': self.token, 'nickname': self.nick, **more}

    def token_arrives(self, said=None):
        if not _wait_for(lambda: _rows(self.run, f"push_tokens?profile_id=eq.{self.me['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')

    def before(self):
        """앞에 남은 알림과 섞이지 않게 — 이 뒤에 새로 생긴 것만 본다."""
        return notify.read_notifications(self.serial)

    def say(self, body):
        _say(self.run, self.partner, self.match_id, body)

    def stamp(self):
        """서버가 아는 폰 계정의 읽음 시각(방에 들어오거나 나올 때 앱이 찍는다). 아직 없으면 None."""
        rows = _rows(self.run, f"match_participants?match_id=eq.{self.match_id}&profile_id=eq.{self.me['id']}&select=last_read_at")
        return rows[0].get('last_read_at') if rows else None

    def stamped(self, what):
        if not _wait_for(self.stamp, STAMP_WAIT):
            raise Blocked(f'{what}는데 {STAMP_WAIT}초 안에 읽음 시각(last_read_at)이 안 찍힘 — 서버가 "방에 있다" 를 알 수 없어 결과가 뜻이 없음')

    def server_gap(self, body):
        """방에 들어올 때 서버가 찍은 읽음 시각(last_read_at)에서 [body] 를 서버가 찍은 보낸 시각(created_at)까지의 초 — 서버가 "방에 있다" 를 결정하는 바로 그 두 값.
        둘 다 서버 쪽 시계라 PC 가 stamp 를 알아챈 때(POLL 5초 오차)부터 재는 것보다 정확하다."""
        rows = _rows(self.run, f'messages?match_id=eq.{self.match_id}&body=eq.{body}&select=created_at')
        created, stamped = _at((rows or [{}])[0].get('created_at')), _at(self.stamp())
        if not (created and stamped):
            raise Blocked('보낸 시각(created_at) 또는 읽음 시각(last_read_at)을 못 읽음 — 서버 창을 잴 수 없음')
        return (created - stamped).total_seconds()

    def path_alive(self, seconds=CONTROL_WAIT):
        """알림 길 대조 — 새 상대가 새 방에서 보낸 메시지 1건이 알림이 되는가. 폰 계정의 읽음 시각 창 · 알림 스위치와 무관한 방이라
        "기대한 알림이 안 왔다" 가 서버 규칙 탓인지 FCM · 토큰 · 읽기가 죽은 탓인지를 가린다(area4_push_front._silent_then_control 과 같은 방식). 앱은 밖(HOME)에 있어야 한다."""
        ctl = _person(self.run)
        body = _fresh_text('ctl')
        before = self.before()
        _say(self.run, ctl, factory.match(self.run, self.me, ctl), body)
        new = notify.wait_new(self.serial, before, seconds=seconds, match=lambda n: (n.title, n.text) == (ctl['nickname'], body))
        return any((n.title, n.text) == (ctl['nickname'], body) for n in new)

    def need_path(self, what):
        """[what] 이 안 와서 fail 하기 전에 — 길이 죽었으면 [Blocked]. 살아 있으면 돌아와 호출한 쪽이 fail 로 적는다."""
        if not self.path_alive():
            raise Blocked(f'{what} 이 안 왔는데 새 상대 · 새 방의 대조 알림도 {CONTROL_WAIT}초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 죽어 서버 규칙을 판정할 수 없음')

    def arrived(self, before, body, seconds):
        """상대의 [body] 가 알림이 될 때까지(최대 [seconds] 초) — 온 그 알림들과 새 알림 전부."""
        new = notify.wait_new(self.serial, before, seconds=seconds, match=lambda n: (n.title, n.text) == (self.nick, body))
        return [n for n in new if (n.title, n.text) == (self.nick, body)], new


def _fresh_text(code):
    return f'E2E-{code}-{secrets.token_hex(3)}'


def p_chat_28(run, phone):
    rig = _Rig(run, phone)
    first, control = _fresh_text('28'), _fresh_text('28c')
    state = {}

    def ready(said):
        rig.token_arrives()
        state['before'] = rig.before()

    def in_room(said):
        rig.stamped('방을 열고 뷰모델이 읽기를 끝냈')
        notify.background(rig.serial)  # 방 화면인 채로 바로 HOME
        rig.say(first)
        # 서버가 찍은 읽음 시각 → 보낸 시각. 서버 창(30초)에서 시계 · 요청 지연 여유 5초를 뺀 IN_ROOM_LIMIT 안이어야 "방에 있다" 규칙을 본 것이다.
        state['gap'] = rig.server_gap(first)
        if not 0 <= state['gap'] <= IN_ROOM_LIMIT:
            raise Blocked(f"읽음 시각 → 보낸 시각이 {state['gap']:.0f}초 — 서버 창({SERVER_WINDOW}초) 안(0~{IN_ROOM_LIMIT}초)이 아니라 \"방에 있다\" 규칙을 볼 수 없음")
        seen = notify.expect_none(rig.serial, state['before'], seconds=notify.NOTICE_WAIT)
        rig.check.that(not seen, f'방 안에 있는데 알림이 {len(seen)}건 옴(기대 0): {notice_memo(seen)}')
        # 대조 — 서버 창이 닫힌 뒤(위 지켜보기가 창보다 길다)의 같은 상대 메시지는 알림이 된다. 안 되면 "0건" 은 길이 죽은 것일 수 있다.
        rig.say(control)
        got, _ = rig.arrived(state['before'], control, CONTROL_WAIT)
        if not got:
            raise Blocked(f'대조 알림(창이 닫힌 뒤 같은 상대의 메시지)이 {CONTROL_WAIT}초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 살아 있는지 몰라 "방 안이면 0건" 을 믿을 수 없음')

    _app(rig.check, phone(midway=stepper(phone, ready, in_room), **rig.job()))
    gap = state.get('gap')
    late = f' — 시나리오의 {IN_ROOM_SCENARIO}초보다 늦음' if gap is not None and gap > IN_ROOM_SCENARIO else ''
    return rig.check.result(f'방에 들어간 지 {gap:.1f}초 만에 보냄(서버가 찍은 last_read_at → created_at 의 차, 서버 창 {SERVER_WINDOW}초){late}' if gap is not None else '')


def p_chat_29(run, phone):
    rig = _Rig(run, phone)
    first, second = _fresh_text('29a'), _fresh_text('29b')
    state = {}

    def ready(said):
        rig.token_arrives()
        state['before'] = rig.before()

    def left(said):
        rig.stamped('방에 들어갔다 나왔')
        before = state['before']
        notify.background(rig.serial)  # 방에서 나온 직후 HOME — 나갈 때 읽음 시각이 찍혔다
        time.sleep(FIRST_AT)
        rig.say(first)
        quiet = [n for n in notify.expect_none(rig.serial, before, seconds=FIRST_WATCH) if n.text == first]
        rig.check.that(not quiet, f'나온 지 {FIRST_AT}초 만에 보낸 첫 메시지가 알림이 됨(서버 창 {SERVER_WINDOW}초 안 — 알림이 없어야 함): {notice_memo(quiet)}')
        time.sleep(max(0, SECOND_AT - FIRST_AT - FIRST_WATCH))
        rig.say(second)
        arrived, new = rig.arrived(before, second, SECOND_WAIT)
        if not arrived:
            rig.need_path(f'나온 지 {SECOND_AT}초 뒤 두 번째 메시지 알림')  # 길이 죽었으면 blocked — 살아 있을 때만 서버 규칙 어긋남(fail)
        rig.check.that(arrived, f'나온 지 {SECOND_AT}초 뒤 두 번째 메시지 알림이 {SECOND_WAIT}초 안에 안 옴(새 알림 {len(new)}건: {notice_memo(new)}) — 새 방 대조는 옴')
        late = [n for n in new if n.text == first]
        rig.check.that(not late, f'첫 메시지의 알림이 뒤늦게 옴: {notice_memo(late)}')
        if arrived:
            more = [n for n in notify.expect_none(rig.serial, [*before, *arrived], seconds=SETTLE) if n.text == second]
            rig.check.that(len(arrived) + len(more) == 1, f'두 번째 메시지 알림이 {len(arrived) + len(more)}건(기대 1)')

    _app(rig.check, phone(midway=stepper(phone, ready, left), **rig.job()))
    return rig.check.result(f'첫 건 HOME 뒤 {FIRST_AT}초 · 둘째 {SECOND_AT}초(PC 가 잠잔 시간 기준, 서버 창 {SERVER_WINDOW}초)')


def _badge(text):
    """목록 줄 뱃지 글자 → 개수(없음 = 0, "99+" = 99). 읽을 수 없으면 None."""
    if text is None:
        return 0
    found = re.fullmatch(r'(\d+)\+?', str(text))
    return int(found.group(1)) if found else None


def p_chat_30(run, phone):
    rig = _Rig(run, phone)
    body = _fresh_text('30')
    state = {}

    def act(said):
        state['before'] = rig.before()  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
        rig.say(body)  # 앱은 대화 목록 앞에 있다 — HOME 으로 내리지 않는다

    def watch(said):
        _silent_then_control(run, phone, rig.check, rig.me, state['before'])  # 앞에 있는 동안 0건 → HOME 으로 내려 대조 메시지가 알림이 되는지

    said = _app(rig.check, phone(midway=stepper(phone, rig.token_arrives, act, watch), **rig.job(body=body)))
    if not said:
        return rig.check.result()
    # 증거는 앱이 목록이 바뀐 것을 본 그 순간(PC 가 HOME 으로 내리기 전)에 잰 값이다 — 지켜보는 60초 동안 앞에 있었다는 근거
    rig.check.that(said.get('list_front') is True, f"앱이 대화 목록 화면에 머물지 못함(list_front={said.get('list_front', MISSING)})")
    rig.check.that(said.get('resumed') is True, f"앱이 앞(resumed)에 있지 않았음(resumed={said.get('resumed', MISSING)}) — 앞에 있어서 알림이 안 뜬 것이 아닐 수 있다")
    rig.check.that(said.get('last') == body,
                   f"목록 마지막 줄 {said.get('last', MISSING)!r}(기대 {body!r}) — 새로고침 없이 저절로 바뀌어야 함(앞 줄 {said.get('last_before', MISSING)!r})")
    before, after = _badge(said.get('badge_before')), _badge(said.get('badge'))
    rig.check.that(None not in (before, after) and after == before + 1, f"목록 뱃지 {said.get('badge_before')!r} → {said.get('badge')!r}(기대 +1)")
    return rig.check.result(f"목록이 저절로 바뀐 때까지 {said.get('ms', MISSING)}ms(상대가 보낸 뒤 앱 시계) · 아래 탭 뱃지 {said.get('nav_badge', MISSING)!r}")


def p_chat_31(run, phone):
    rig = _Rig(run, phone)
    body = _fresh_text('31')
    seen = {}

    def hold(said):
        rig.token_arrives()
        before = rig.before()
        notify.background(rig.serial)  # 앱이 밖(뒤)에 있다 — 프로세스는 살아 있다(꺼진 앱은 E-CHAT-32)
        rig.say(body)
        sent = time.monotonic()
        got, new = rig.arrived(before, body, notify.NOTICE_WAIT)
        seen['seconds'] = time.monotonic() - sent
        rig.check.that(got, f'{notify.NOTICE_WAIT}초 안에 알림 "{rig.nick} / {body}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
        if got:
            seen['arrived'] = True
            notify.tap_notification(rig.serial, rig.nick, body)  # 본문까지 줘 그 글이 든 줄만 누른다
            time.sleep(1)

    said = _app(rig.check, phone(midway=hold, **rig.job(body=body, phase='hold')))
    if not (seen.get('arrived') and said):
        return rig.check.result()
    for key, label in SEEN:
        rig.check.that(said.get(key) is True, f'{label}({key}) {said.get(key, MISSING)}(기대 True)')
    if not all(said.get(key) is True for key, _ in SEEN):
        rig.check.problems.append(f'그때 보인 화면 {_screens(said)}')
    return rig.check.result(f"알림 도착까지 {seen['seconds']:.0f}초(2초마다 확인) · 앱이 방을 연 시각 {said.get('opened_at', MISSING)}"
                            f"(앱 시계, 일감 받은 뒤 {said.get('room_ms', MISSING)}ms)")


def p_chat_33(run, phone):
    rig = _Rig(run, phone)
    off, on = _fresh_text('33a'), _fresh_text('33b')

    def server_value():
        return area4._settings(run, rig.me['id']).get('new_message')  # 행이 없으면(= 기본 켜짐) None

    def turned_off(said):
        _wait_for(lambda: server_value() is False, SWITCH_SAVE)
        rig.check.that(server_value() is False, f'앱이 "새 메시지" 를 껐는데 서버 new_message {server_value()!r}(기대 False)')
        before = rig.before()
        notify.background(rig.serial)
        rig.say(off)
        seen = notify.expect_none(rig.serial, before, seconds=notify.NOTICE_WAIT)
        rig.check.that(not seen, f'"새 메시지" 를 끈 동안 알림이 {len(seen)}건 옴(기대 0): {notice_memo(seen)}')
        _front(rig.serial)  # 앱을 다시 앞으로 — 앱이 스위치를 다시 켠다
        time.sleep(FRONT_SETTLE)  # monkey 가 앱을 앞으로 가져와 프레임이 다시 돌 시간 — 곧바로 go 를 넣으면 앱이 아직 뒤라 누르기가 헛돈다

    def turned_on(said):
        _wait_for(lambda: server_value() is True, SWITCH_SAVE)
        rig.check.that(server_value() is True, f'앱이 "새 메시지" 를 다시 켰는데 서버 new_message {server_value()!r}(기대 True)')
        before = rig.before()
        notify.background(rig.serial)
        rig.say(on)
        arrived, new = rig.arrived(before, on, notify.NOTICE_WAIT)
        if not arrived and server_value() is True:  # 서버 값이 꺼진 채면 대조 메시지도 막혀 길이 죽은 것처럼 보인다 — 서버 값 어긋남으로 바로 fail
            rig.need_path('다시 켠 뒤 알림')  # 길이 죽었으면 blocked — 살아 있을 때만 fail
        rig.check.that(arrived, f'다시 켠 뒤 알림 "{rig.nick} / {on}" 이 {notify.NOTICE_WAIT}초 안에 안 옴(새 알림 {len(new)}건: {notice_memo(new)}) — 끈 동안의 0건도 믿을 수 없음')
        if arrived:
            more = [n for n in notify.expect_none(rig.serial, [*before, *arrived], seconds=SETTLE) if n.text == on]
            rig.check.that(len(arrived) + len(more) == 1, f'켠 뒤 알림이 {len(arrived) + len(more)}건(기대 1)')

    _app(rig.check, phone(midway=stepper(phone, rig.token_arrives, turned_off, turned_on), **rig.job()))
    return rig.check.result()


def _dismiss_permission_dialog(serial):
    """로그인 뒤 첫 알림 권한 창이 뜨면 "허용 안 함" 을 누른다 → 눌렀는지. 안 뜨면(이미 거부로 정해진 폰) False — 이 가설은 어느 쪽이든 권한이 꺼진 채다."""
    deadline = time.monotonic() + DIALOG_WAIT
    while True:
        if _tap_node(serial, _is_deny):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(1)


def p_chat_35(run, phone):
    """`_permitted`(권한을 먼저 주고 끝에 거둠)를 쓰지 않는다 — 이 가설은 권한이 꺼진 채 로그인해야 한다. 끝에 거두는 것만 같다."""
    rig = _Rig(run, phone)
    first, live = _fresh_text('35a'), _fresh_text('35b')
    state = {}
    notify.revoke_notifications(rig.serial)  # 앱 프로세스도 같이 죽는다 — 앱을 켜기 전에
    try:
        granted = _granted(rig.serial)
        if granted is not False:
            raise Blocked('알림 권한을 끌 수 없거나 상태를 못 읽음(안드로이드 13 이상에서만 도는 가설)' + ('' if granted is None else ' — pm revoke 뒤에도 허용으로 남음'))

        def signed_in(said):
            state['dialog'] = _dismiss_permission_dialog(rig.serial)  # 권한을 거부한 사람이 로그인한 것과 같게
            state['registered'] = _wait_for(lambda: _tokens(run, rig.me['id']), GONE_WAIT)
            before = rig.before()
            notify.background(rig.serial)
            rig.say(first)
            seen = notify.expect_none(rig.serial, before, seconds=notify.NOTICE_WAIT)
            rig.check.that(not seen, f'알림 권한이 꺼진 기기에 알림이 {len(seen)}건 옴(기대 0): {notice_memo(seen)}')
            _front(rig.serial)  # 앱을 다시 앞으로 — 방을 연다
            time.sleep(FRONT_SETTLE)

        def ready(said):
            rig.say(live)

        said = _app(rig.check, phone(midway=stepper(phone, signed_in, ready), **rig.job(body=live)))
        state['delay'] = _live_delay(rig, said, live)
        # 대조 — 같은 기기 · 같은 앱에서 권한을 켜고 다시 로그인하면 알림이 온다. 안 오면 위의 "0건" 은 알림 길이 죽어서일 수 있다.
        notify.grant_notifications(rig.serial)
        _app(rig.check, phone(token_hash=run.link(rig.me['email']), nickname=rig.nick, phase='again'), '권한을 켠 뒤 다시 로그인')
        rig.token_arrives()
        notify.background(rig.serial)
        # 새 상대 · 새 방 — 방금 입장한 방(읽음 시각 30초 창 안일 수 있다)으로 보내면 서버가 안 보내 길이 죽은 것으로 오해한다
        if not rig.path_alive():
            raise Blocked(f'대조 알림(권한을 켜고 다시 로그인한 뒤 새 상대 · 새 방의 메시지)이 {CONTROL_WAIT}초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 살아 있는지 몰라 "권한이 꺼져서 0건" 을 믿을 수 없음')
    finally:
        notify.revoke_notifications(rig.serial)
    notes = [state['delay'], '' if state['dialog'] else '권한 창이 안 뜸(이미 거부로 정해진 폰) — 권한은 꺼진 채라 판정은 같다',
             'push_tokens 에 기기 토큰이 등록됨(권한이 꺼졌는데 — 알림은 안 떠 판정은 같다)' if state['registered'] else '']
    return rig.check.result(' · '.join(note for note in notes if note))


def _live_delay(rig, said, body):
    """방 안에서 [body] 가 ≤ LIVE_LIMIT 초에 보였는지(E-CHAT-10 · 67 과 같은 판정) → 메모. 시계 차로 음수면 판정하지 않는다."""
    if not said:
        return ''
    rig.check.that(said.get('loaded') is True, f"앱이 방 읽기를 끝냈다고 안 말함 {said.get('loaded', MISSING)}(기대 True)")
    rig.check.that(said.get('bubble') is True, f"방 안 말풍선 {said.get('bubble', MISSING)}(기대 True — 실시간은 그대로)")
    rows = _rows(rig.run, f'messages?match_id=eq.{rig.match_id}&body=eq.{body}&select=created_at')
    created, seen = _at((rows or [{}])[0].get('created_at')), _at(said.get('seen_at'))
    if not (created and seen):
        rig.check.problems.append('보낸 시각 또는 앱이 본 시각(seen_at)을 못 읽음')
        return ''
    delay = (seen - created).total_seconds()
    if delay < 0:  # 폰 시계가 서버보다 느려 N초 늦은 표시도 가려질 수 있다 — 판정하지 않는다
        return f'지연 판정 불가 — 앱이 본 시각이 서버가 찍은 보낸 시각보다 {-delay:.2f}초 앞섬(폰 시계 차). 말풍선 표시만 판정'
    rig.check.that(delay <= LIVE_LIMIT, f'방 안에서 {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})')
    return f'지연 {delay:.2f}초(앱 시계 − 서버가 찍은 보낸 시각)'


PHONE_NT = {'E-CHAT-17': chat_17, 'E-CHAT-26': chat_26, 'E-CHAT-27': chat_27, 'E-CHAT-28': _permitted(p_chat_28),
           'E-CHAT-29': _permitted(p_chat_29), 'E-CHAT-30': _permitted(p_chat_30), 'E-CHAT-31': _permitted(p_chat_31),
           'E-CHAT-33': _permitted(p_chat_33), 'E-CHAT-35': p_chat_35, 'E-CHAT-59': chat_59}
tools.CASE_LIMITS.update({case: -(-(worst + MARGIN) // 60) * 60 for case, worst in WORST.items() if worst + MARGIN > tools.CASE_LIMIT})

area1.PHONE.update(PHONE_NT)
area3.BUNDLES['area3-chat-nt'] = list(PHONE_NT)
