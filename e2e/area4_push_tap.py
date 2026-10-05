"""영역 4 PUSH A2 — 알림을 눌러 그 화면이 열리는지 10개(묶음 area4-push-a2).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본). 앱 쪽은 frontend/integration_test/area4_push_tap.dart 의 같은 번호.

받는 사람(폰 계정)을 홈까지 켜 기기 토큰이 올라오기를 기다린 뒤, 상대(보내는 사람)는 계정 토큰으로 API 를 불러 알림을 만들고 알림창에서 그것을 눌러
도착한 화면을 앱이 본 대로 말한다. 판정은 여기서 한다. 알림 준비(계정 · 카드 · 매칭 · 알림 문구)는 A1(area4_push.py)과 같은 공장 · 상수를 쓴다.

두 가지 상태:
  뒤(11 · 19 · 27 · 38 · 50)    앱을 홈까지 켜 둔 채 HOME — 앱 프로세스가 살아 있다. 앱은 멈춰 기다리다(step) 눌린 뒤 화면을 본다.
  꺼짐(28 · 76 · 77 · 78 · 81)  로그인 판 → `notify.kill_app`(am kill — force-stop 은 FCM 이 안 온다) → 알림 누름 판(일감을 먼저 넣고 누르면 앱이 콜드 스타트해 받는다).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  "10초 안 그 화면"  꺼진 앱은 방 · 목록이 열리기를 30초까지 기다리고(앱 부팅 · 로그인 · 관문 조회 포함) 걸린 ms 를 메모에 남긴다 — 10초 판정은 안 한다(E-CHAT-32 와 같다).
  화면 읽는 법      시나리오는 uiautomator 화면 글자인데 구현은 integration_test 앱 안의 위젯 트리(받은 수락 줄 · 대화방 줄 · 앱바 닉네임 · 말풍선 · 받은 리뷰 카드)로 본다.
  78               시나리오의 "신뢰 수락 · 공개 알림" 중 상대가 먼저 수락했을 때 오는 알림(제목 = 상대 닉네임, 내용 = 공개 수락 문구)을 누른다.
  낮에만            서울 08~22시(notify.require_daytime).
  오래된 알림       알림창에 앞 가설의 같은 제목 알림(받은 수락 · 매칭 · 새 지인 리뷰는 제목이 고정)이 남아 있으면 그것이 눌릴 수 있다 — 경로가 같아 11 · 19 · 50 · 76 · 77 · 81 은
                   화면이 열려 "그 종류 알림으로 그 화면이 열렸다" 까지만 증명하고, 38 은 옛 방이 열려 거짓 fail 이 날 수 있다(제목이 닉네임인 27 · 28 · 78 은 안전). 알림을 비우는 방법은
                   기기마다 달라 못 넣었다 — 기기에서 알림을 지운 뒤 돌리면 가장 좋다.
  개수             "알림 1개 · 줄 1개" 는 세지 않고 닉네임이 보이는지만 본다(알림 개수는 A1 이 본다).
"""

import functools
import secrets
import time

from e2e import area1, area3_phone, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _app, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3_phone import MISSING, _permitted
from e2e.area3_phone3 import SCREEN_LABELS
from e2e.area4_push import (ACCEPT_TITLE, MATCH_TITLE, NOTICE_WAIT, PUBLIC_TITLE, REVIEW_TITLE, TOKEN_WAIT, TRUST_BODY, _matched, _public,
                            accept_body)
from e2e.tools import Blocked

APP_WAIT = 90  # 눌린 앱이 화면을 읽고 말하기를 기다리는 초(앱 안의 30 + 10 + 10초 기다림이 모두 끝나도 남는 여유)
CASE_LIMIT_SLOW = 600  # 로그인 · 토큰 30 · 알림 60 · 앱 90 이 겹쳐 기본 420초가 빠듯하다


def _setup(kind, run, me, partner):
    """(상대가 하는 행동, 기다릴 알림 (제목, 본문), 앱 일감에 더할 것). 앞 상태는 여기서 만든다 — 앱이 켜지기 전."""
    nick = partner['nickname']
    if kind == 'accept':
        card = factory.card(run, partner, me)
        return (lambda: factory.accept_card(run, partner, card)), (ACCEPT_TITLE, accept_body(nick)), {'dest': 'conversations', 'section': 'acceptance'}
    if kind == 'match':
        card = factory.card(run, me, partner)
        factory.accept_card(run, me, card)
        return (lambda: factory.accept_back(run, partner, card)), (MATCH_TITLE, _matched(nick)), {'dest': 'conversations', 'section': 'chat'}
    if kind == 'review':
        factory.link(run, partner, me)
        return (lambda: factory.review(run, partner, me)), (REVIEW_TITLE, f'{nick} 님이 리뷰를 남겼어요'), {'dest': 'reviews'}
    match_id = factory.match(run, me, partner)
    room = {'dest': 'room'}
    if kind == 'message':
        body = f'E2E-tap-{secrets.token_hex(3)}'
        return (lambda: factory.send(run, partner, match_id, body)), (nick, body), {**room, 'body': body}
    if kind == 'public':
        factory.trust(run, me, match_id)  # 폰 계정이 먼저 수락해 기다린다 — 상대가 마지막에 누르면 공개 알림이 온다
        return (lambda: factory.trust(run, partner, match_id)), (PUBLIC_TITLE, _public(nick)), room
    return (lambda: factory.trust(run, partner, match_id)), (nick, TRUST_BODY), room  # trust


def _screens(said):
    return ' · '.join(f'{name}({SCREEN_LABELS.get(name, "?")})' for name in said.get('screen') or []) or '없음'


def _judge(check, said, job):
    """앱이 본 것으로 판정 — 화면이 열렸나 · 그 사람이 보이나 · (메시지 알림이면) 방금 글이 보이나."""
    if not said:
        return
    check.that(said.get('dest') is True, f"도착 화면({job['dest']}) 안 열림({said.get('dest', MISSING)}) · 그때 화면 {_screens(said)}")
    if said.get('dest') is True:
        check.that(said.get('who') is True, f"{job['nickname']} 님이 그 화면에 안 보임({said.get('who', MISSING)})")
        if 'body' in job:
            check.that(said.get('body') is True, f"방금 메시지가 안 보임({said.get('body', MISSING)})")


def _run(run, phone, kind, state):
    notify.require_daytime()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    me = area3_phone._person(run)
    partner = area3_phone._person(run)
    act, want, extra = _setup(kind, run, me, partner)
    job = {'nickname': partner['nickname'], **extra}
    token = run.link(me['email'])
    seen = {}

    def token_arrives():
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')

    def make_and_tap(before):
        act()
        sent = time.monotonic()
        new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == want)
        seen['seconds'] = time.monotonic() - sent
        seen['arrived'] = any((n.title, n.text) == want for n in new)
        check.that(seen['arrived'], f'{NOTICE_WAIT}초 안에 알림 "{want[0]} / {want[1]}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
        return seen['arrived']

    if state == 'back':
        def hold(said):
            token_arrives()
            before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
            notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다
            if make_and_tap(before):
                notify.tap_notification(phone.serial, want[0])
                time.sleep(1)

        said = _app(check, phone(midway=hold, token_hash=token, phase='hold', **job))
        if seen.get('arrived'):
            _judge(check, said, job)
    else:
        _app(check, phone(token_hash=token, phase='login'))
        if check.problems:  # 홈에 못 닿았으면 토큰도 알림도 기대할 수 없다
            return check.result()
        token_arrives()
        before = notify.read_notifications(phone.serial)
        notify.kill_app(phone.serial)
        if make_and_tap(before):
            # 누르기 전에 일감을 넣는다 — 알림으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 이것을 가져간다(새 로그인을 하지 않는다)
            phone.hub.tell({'case': phone.case, 'phase': 'tap', **job})
            notify.tap_notification(phone.serial, want[0])
            said = _app(check, phone.hub.result(APP_WAIT))
            _judge(check, said, job)
    note = f"알림 도착까지 {seen['seconds']:.0f}초(2초마다 확인)" if seen.get('arrived') else ''
    if seen.get('arrived') and state == 'killed':
        note += f" · 앱이 화면을 연 시간 {said.get('ms', MISSING)}ms(일감 받은 뒤 — 앱 부팅 포함)"
    return check.result(note)


def _case(kind, state):
    @functools.wraps(_run)
    def case(run, phone):
        return _run(run, phone, kind, state)
    return _permitted(case)


KINDS = {
    '11': ('accept', 'back'), '19': ('match', 'back'), '27': ('message', 'back'), '38': ('public', 'back'), '50': ('review', 'back'),
    '28': ('message', 'killed'), '76': ('accept', 'killed'), '77': ('match', 'killed'), '78': ('trust', 'killed'), '81': ('review', 'killed'),
}
PHONE = {f'E-PUSH-{number}': _case(*spec) for number, spec in KINDS.items()}

tools.CASE_LIMITS.update({f'E-PUSH-{number}': CASE_LIMIT_SLOW for number, (_, state) in KINDS.items() if state == 'killed'})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-a2'] = list(PHONE)
