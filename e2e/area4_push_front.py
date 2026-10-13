"""영역 4 PUSH A3 — 앱이 앞에 있을 때 알림과 화면 7개(묶음 area4-push-a3).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본)이되, 앞 화면 알림은 #503(2026-10-13 사용자 요청) 뒤의 앱이 기준이다:
안드로이드 앱은 앞에 있어도 받은 푸시를 시스템 알림으로 직접 띄우고, **지금 열린 채팅방**의 알림만 건너뛴다(core/push/foreground_push.dart).
앱 쪽은 frontend/integration_test/area4_push_front.dart 의 같은 번호.

앱을 홈까지 켜 기기 토큰이 올라오기를 기다린 뒤(멈춤 1) 앱이 그 화면으로 가 앞에 머무는 동안(멈춤 2) 상대(보내는 사람)가 계정 토큰으로 API 를 불러 알림을 만든다.
앱은 화면이 저절로 바뀌었는지 본 대로 말하고(멈춤 3), PC 는 그동안 알림창을 본다. 판정은 여기서 한다.
  14 · 20 · 53 · 82   열린 방이 아닌 화면 — 앞에 있어도 그 알림(제목 · 본문)이 정확히 1개 떠야 pass. 온 알림이 길(읽기 · 토큰 · FCM)이 살아 있다는 증거라 대조가 없다.
  29 · 30             열린 방 안 — 알림 0개여야 하고, "안 뜬다" 를 믿으려고 지켜본 뒤 HOME 으로 내려 대조 메시지가 실제로 알림이 되는지 본다(안 오면 blocked).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  "알림 0개"     시나리오의 14 · 20 · 53 · 82 "앞이면 0개" 는 #503 으로 뒤집혔다 — 지금은 1개. 29 · 30 의 0개는 그대로다.
  "1개"          알림이 온 뒤 SETTLE(20초) 더 지켜봐 같은 알림이 또 오면 fail(앱이 띄운 것과 FCM 이 띄운 것이 겹치는 회귀를 잡는다).
  29 "2초 안"   앱은 메시지 줄이 보이기를 10초까지 기다린다(실시간 자체는 채팅 영역이 본다). 걸린 시간은 상대 행동이 끝난 뒤부터라 의미가 없어 메모에 안 남긴다.
  30            서버가 알림을 보냈는지는 못 본다(FCM 보낸 건수가 없다) — 입장 후 31초 뒤에 보내 "서버가 보내도 앱이 지금 그 방이면 안 띄운다" 의 앱 쪽만 본다(안드로이드 기준).
  31            HOME 뒤 10초 · 40초에 보낸다. 첫 메시지는 지켜보는 동안 0개, 두 번째는 알림 1개여야 한다(나갈 때 읽음이 찍혀 30초 창이 서 있는 경계, ⚠ 목록 14).
  20            이전엔 ⚠ 결함 후보였다(코드가 매칭 알림에 받은 수락만 다시 읽음). #310(push_refresh.dart)이 대화 목록도 다시 읽게 고쳐 지금은 줄이 생겨야 한다 — 안 생기면 회귀로 fail.
  낮에만         서울 08~22시(notify.require_daytime).
"""

import functools
import secrets
import time

from e2e import area1, area3_phone, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _app, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3_phone import MISSING, _permitted
from e2e.area4 import stepper
from e2e.area4_push import ACCEPT_TITLE, MATCH_TITLE, NOTICE_WAIT, REVIEW_TITLE, SETTLE, TOKEN_WAIT, _matched, accept_body
from e2e.tools import Blocked

IN_ROOM_WAIT = 32  # 방 입장 후 이만큼 지나면 서버의 "방에 있다" 30초 창이 닫힌다(시나리오 30 의 31초 + 여유)
FIRST_AT = 10  # 31: HOME 뒤 첫 메시지를 보내는 초
SECOND_AT = 40  # 31: 두 번째 메시지를 보내는 시점(HOME 뒤 초)
FIRST_WATCH = 25  # 31: 첫 메시지 뒤 알림이 안 뜨는지 지켜보는 초(서버는 보낼 때 창을 결정하므로 FCM 지연 여유)
SECOND_WAIT = 60  # 31: 두 번째 알림을 기다리는 초
CASE_LIMIT_SLOW = 900  # 앱 켜기 · 토큰 · 지켜보기 60 · 대조 30 이 겹쳐 기본 420초를 넘는다

SCREEN = {'14': 'conversations', '20': 'conversations', '29': 'room', '30': 'room', '31': 'room', '53': 'reviews', '82': 'today'}


def _setup(number, run, me, partner):
    """(상대가 하는 행동, 앱 일감에 더할 것, 방 id 또는 None, 앞에서 떠야 할 알림 (제목, 본문) 또는 None). 앞 상태는 여기서 만든다 — 앱이 켜지기 전.
    떠야 할 알림이 None 인 29 · 30 · 31 은 열린 방(또는 방에서 막 나온) 판이다. 문구는 area4_push 의 같은 길(10 · 17 · 49 · 24)과 같다."""
    nick = partner['nickname']
    job = {'screen': SCREEN[number], 'nickname': nick}
    if number == '14':
        card = factory.card(run, partner, me)
        return (lambda: factory.accept_card(run, partner, card)), {**job, 'expect': 'acceptance'}, None, (ACCEPT_TITLE, accept_body(nick))
    if number == '20':
        card = factory.card(run, me, partner)
        factory.accept_card(run, me, card)
        return (lambda: factory.accept_back(run, partner, card)), {**job, 'expect': 'chat'}, None, (MATCH_TITLE, _matched(nick))
    if number == '53':
        factory.link(run, partner, me)
        return (lambda: factory.review(run, partner, me)), job, None, (REVIEW_TITLE, f'{nick} 님이 리뷰를 남겼어요')
    match_id = factory.match(run, me, partner)  # 29 · 30 · 31 · 82 — DB 로 만든 방이라 폰 쪽 last_read_at 은 비어 있다
    body = f'E2E-front-{secrets.token_hex(3)}'
    if number in ('29', '30'):
        return (lambda: factory.send(run, partner, match_id, body)), {**job, 'body': body, 'match_id': match_id}, match_id, None
    room = {'match_id': match_id} if number == '31' else {}  # 앱이 방을 직접 연다(29 · 30 은 위에서 이미 돌려줬다)
    want = (nick, body) if number == '82' else None  # 82 는 오늘 탭 — 열린 방이 아니라 앞에서도 뜬다
    return (lambda: factory.send(run, partner, match_id, body)), {**job, **room}, match_id, want  # 82 · 31(31 은 보내기를 두 번 — home_then_two_sends 가 직접 부른다)


def _judge(check, number, said):
    if not said:
        return
    check.that(said.get('front') is True, f'앱이 그 화면({SCREEN[number]}) 앞에 머물지 못함({said.get("front", MISSING)})')
    wants = {'14': ('row', '받은 수락 줄'), '20': ('row', '새 대화방 줄'), '29': ('body', '방금 메시지 줄'), '82': ('badge', '"대화" 안 읽음 숫자')}
    if number in wants:
        key, label = wants[number]
        check.that(said.get(key) is True, f'{label} 이 저절로 안 생김({key}={said.get(key, MISSING)})' + (' — 회귀(#310 이 대화 목록도 다시 읽게 고쳤다)' if number == '20' else ''))
    if number == '53':
        check.that(said.get('absent') is True, f'앞에서 리뷰 줄이 저절로 생김(absent={said.get("absent", MISSING)}) — 화면 갱신이 없어야 함')
        check.that(said.get('present') is True, f'화면에 다시 들어가도 리뷰 줄이 없음(present={said.get("present", MISSING)})')


def _arrives_in_front(serial, check, before, want):
    """앱이 앞에 있어도 [want](제목, 본문) 알림이 정확히 1개 — #503 뒤 안드로이드 앱은 떠 있어도 받은 푸시를 시스템 알림으로 직접 띄운다(지금 열린 방만 건너뜀).
    온 알림이 길(읽기 · 토큰 · FCM)이 살아 있다는 증거라 대조가 없다. 온 뒤 [SETTLE] 초 더 봐 같은 알림이 또 오면 fail."""
    new = notify.wait_new(serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == want)
    got = [n for n in new if (n.title, n.text) == want]
    check.that(got, f'앱이 앞에 있는데 {NOTICE_WAIT}초 안에 알림 "{want[0]} / {want[1]}" 없음 — 앞에서도 떠야 함(#503)(새 알림 {len(new)}건: {notice_memo(new)})')
    if got:
        more = [n for n in notify.expect_none(serial, [*before, *got], seconds=SETTLE) if (n.title, n.text) == want]
        check.that(len(got) + len(more) == 1, f'같은 알림이 {len(got) + len(more)}개(기대 1)')


def _silent_then_control(run, phone, check, me, before):
    """열린 방 안(29 · 30)에 있는 동안 알림이 0개여야 한다. 0개면 HOME 으로 내려 대조 메시지가 알림이 되는지 본다 — 안 되면 "안 뜬다" 를 못 믿으니 [Blocked]."""
    seen = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)
    check.that(not seen, f'열린 방 안에 있는데 알림이 {len(seen)}건 뜸(안 와야 할 알림): {notice_memo(seen)}')
    if seen:
        return
    notify.background(phone.serial)
    ctl = area3_phone._person(run)
    after = notify.read_notifications(phone.serial)
    body = f'E2E-ctl-{secrets.token_hex(3)}'
    factory.send(run, ctl, factory.match(run, me, ctl), body)
    got = notify.wait_new(phone.serial, after, seconds=30, match=lambda n: (n.title, n.text) == (ctl['nickname'], body))
    if not any((n.title, n.text) == (ctl['nickname'], body) for n in got):
        raise Blocked('대조 알림(HOME 뒤 메시지)이 30초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 살아 있는지 몰라 "앞이면 안 뜬다" 를 믿을 수 없음')


def _run(run, phone, number):
    notify.require_daytime()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    me = area3_phone._person(run)
    partner = area3_phone._person(run)
    act, job, match_id, want = _setup(number, run, me, partner)
    token = run.link(me['email'])
    state = {}

    def token_arrives(said):
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')

    def act_in_front(said):
        state['before'] = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
        if number == '30':
            time.sleep(IN_ROOM_WAIT)  # 서버의 "방에 있다" 30초 창이 닫힌 뒤 — 서버는 알림을 보낸다
        act()

    def watch(said):
        if want:
            _arrives_in_front(phone.serial, check, state['before'], want)
        else:
            _silent_then_control(run, phone, check, me, state['before'])

    def home_then_two_sends(said):
        before = notify.read_notifications(phone.serial)
        notify.background(phone.serial)  # 방에서 나온 직후 HOME — 나갈 때 읽음이 찍힌다
        time.sleep(FIRST_AT)
        first = f'E2E-front-1-{secrets.token_hex(3)}'
        factory.send(run, partner, match_id, first)
        quiet = [n for n in notify.expect_none(phone.serial, before, seconds=FIRST_WATCH) if n.text == first]
        check.that(not quiet, f'나온 지 {FIRST_AT}초 안에 온 첫 메시지가 알림이 됨(30초 창 안 — 알림이 없어야 함)')
        time.sleep(max(0, SECOND_AT - FIRST_AT - FIRST_WATCH))
        second = f'E2E-front-2-{secrets.token_hex(3)}'
        factory.send(run, partner, match_id, second)
        got = notify.wait_new(phone.serial, before, seconds=SECOND_WAIT, match=lambda n: (n.title, n.text) == (partner['nickname'], second))
        check.that(any((n.title, n.text) == (partner['nickname'], second) for n in got),
                   f'{SECOND_AT}초 뒤 두 번째 메시지 알림이 {SECOND_WAIT}초 안에 안 옴(새 알림 {len(got)}건: {notice_memo(got)})')

    handlers = (token_arrives, home_then_two_sends) if number == '31' else (token_arrives, act_in_front, watch)
    said = _app(check, phone(midway=stepper(phone, *handlers), token_hash=token, **job))
    if number != '31':
        _judge(check, number, said)
    return check.result()


def _case(number):
    @functools.wraps(_run)
    def case(run, phone):
        return _run(run, phone, number)
    return _permitted(case)


PHONE = {f'E-PUSH-{number}': _case(number) for number in SCREEN}

tools.CASE_LIMITS.update({f'E-PUSH-{number}': CASE_LIMIT_SLOW for number in ('29', '30', '31')})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-a3'] = list(PHONE)
