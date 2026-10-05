"""영역 4 PUSH A3 — 앱이 앞에 있을 때 알림은 안 뜨고 화면만 바뀌는지 7개(묶음 area4-push-a3).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본). 앱 쪽은 frontend/integration_test/area4_push_front.dart 의 같은 번호.

앱을 홈까지 켜 기기 토큰이 올라오기를 기다린 뒤(멈춤 1) 앱이 그 화면으로 가 앞에 머무는 동안(멈춤 2) 상대(보내는 사람)가 계정 토큰으로 API 를 불러 알림을 만들고,
PC 는 알림창에 알림이 하나도 안 뜨는지 지켜본다. 앱은 화면이 저절로 바뀌었는지 본 대로 말하고 판정은 여기서 한다(멈춤 3).
"안 뜬다" 를 믿으려면 같은 실행 안에서 길이 살아 있음을 봐야 한다 — 앞에서는 알림이 안 뜨는 게 정상이라, 지켜본 뒤 HOME 으로 내려 대조 메시지가 실제로 알림이 되는지 본다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  "알림 0개"     앱이 앞에 있어 0개가 정상이다 — 읽기가 깨진 것과 가르려고 대조 알림(HOME 뒤 메시지)이 와야 pass, 안 오면 blocked.
  29 "2초 안"   앱은 메시지 줄이 보이기를 10초까지 기다린다(실시간 자체는 채팅 영역이 본다). 걸린 시간은 상대 행동이 끝난 뒤부터라 의미가 없어 메모에 안 남긴다.
  30            서버가 알림을 보냈는지는 못 본다(FCM 보낸 건수가 없다) — 입장 후 31초 뒤에 보내 "서버가 보내도 앱이 앞이면 배너가 안 뜬다" 의 앱 쪽만 본다.
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
from e2e.area4_push import NOTICE_WAIT, TOKEN_WAIT
from e2e.tools import Blocked

IN_ROOM_WAIT = 32  # 방 입장 후 이만큼 지나면 서버의 "방에 있다" 30초 창이 닫힌다(시나리오 30 의 31초 + 여유)
FIRST_AT = 10  # 31: HOME 뒤 첫 메시지를 보내는 초
SECOND_AT = 40  # 31: 두 번째 메시지를 보내는 시점(HOME 뒤 초)
FIRST_WATCH = 25  # 31: 첫 메시지 뒤 알림이 안 뜨는지 지켜보는 초(서버는 보낼 때 창을 결정하므로 FCM 지연 여유)
SECOND_WAIT = 60  # 31: 두 번째 알림을 기다리는 초
CASE_LIMIT_SLOW = 900  # 앱 켜기 · 토큰 · 지켜보기 60 · 대조 30 이 겹쳐 기본 420초를 넘는다

SCREEN = {'14': 'conversations', '20': 'conversations', '29': 'room', '30': 'room', '31': 'room', '53': 'reviews', '82': 'today'}


def _setup(number, run, me, partner):
    """(상대가 하는 행동, 앱 일감에 더할 것, 방 id 또는 None). 앞 상태는 여기서 만든다 — 앱이 켜지기 전."""
    job = {'screen': SCREEN[number], 'nickname': partner['nickname']}
    if number == '14':
        card = factory.card(run, partner, me)
        return (lambda: factory.accept_card(run, partner, card)), {**job, 'expect': 'acceptance'}, None
    if number == '20':
        card = factory.card(run, me, partner)
        factory.accept_card(run, me, card)
        return (lambda: factory.accept_back(run, partner, card)), {**job, 'expect': 'chat'}, None
    if number == '53':
        factory.link(run, partner, me)
        return (lambda: factory.review(run, partner, me)), job, None
    match_id = factory.match(run, me, partner)  # 29 · 30 · 31 · 82 — DB 로 만든 방이라 폰 쪽 last_read_at 은 비어 있다
    body = f'E2E-front-{secrets.token_hex(3)}'
    if number in ('29', '30'):
        return (lambda: factory.send(run, partner, match_id, body)), {**job, 'body': body, 'match_id': match_id}, match_id
    room = {'match_id': match_id} if number == '31' else {}  # 앱이 방을 직접 연다(29 · 30 은 위에서 이미 돌려줬다)
    return (lambda: factory.send(run, partner, match_id, body)), {**job, **room}, match_id  # 82 · 31(31 은 보내기를 두 번 — home_then_two_sends 가 직접 부른다)


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


def _silent_then_control(run, phone, check, me, before):
    """앞에 있는 동안 알림이 0개여야 한다. 0개면 HOME 으로 내려 대조 메시지가 알림이 되는지 본다 — 안 되면 "안 뜬다" 를 못 믿으니 [Blocked]."""
    seen = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)
    check.that(not seen, f'앱이 앞에 있는데 알림이 {len(seen)}건 뜸(안 와야 할 알림): {notice_memo(seen)}')
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
    act, job, match_id = _setup(number, run, me, partner)
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
