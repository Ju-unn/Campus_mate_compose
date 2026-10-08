"""영역 3 배치(chat-gate · cleanup)를 실제로 부르는 가설 9개 — 폰 8개(묶음 area3-phone-5) + API 1개(E-CHAT-69). 앱 쪽은 frontend/integration_test/area3_b5.dart.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본). 이 묶음이 안 하는 것: E-CHAT-53(07시대 · 08시대 실제 시각 두 번) · 54("같은 한 시간
배치 두 번" 은 관문이 막는다 — 항상 blocked) · 34 · 42 · E-REV-18(밤 실행).

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`(E-CHAT-69 는 `(run)`). 폰 계정은 늘 받는 쪽 B 이고, 상대 A 의 행동(수락 · 나가기 · 보내기)은 API 로 대신한다.
운영 배치는 실사용자 전체에 도는 실제 호출이다 — 그래서 아래를 모두 지킨다.
  시각 관문   배치는 `area2._batch` 로만 부른다(안에서 batch_gate.check 를 먼저 지난다). tools.batch · gcloud 직접 호출 없음. 준비(계정 · 앱 · 알림) **전에**
              batch_gate.peek 로 "지금 · 준비가 끝날 즈음(PREP_MINUTES 분 뒤)" 이 금지 시간인지 기록 없이 먼저 본다 — 준비를 다 하고서야 막히면 시간이 낭비된다.
              낮 10~20시가 필요한 가설(50 · 51 · 52)은 notify.require_daytime(08~22)이 아니라 [_midday](시나리오가 말한 10~20)를 관문 앞에서 본다.
  시각 확정   matches.created_at 은 관문을 통과한 직후 gcloud 를 부르기 바로 앞(`_batch(before=…)`)에서 PC 가 마지막으로 옮긴다. 준비 중에 옮기면 리마인드 창(한 시간) ·
              48시간 경계가 준비 시간만큼 밀리고, 관문에서 막히면 아무 방도 옮겨지지 않은 채 남는다.
  판정 범위   배치는 열린 방 전부를 훑지만, 판정은 이번 실행이 만든 방 · 계정(area2._guard)만 본다. 다른 실제 매칭은 읽지도 바꾸지도 않는다.
  배치 증거   gcloud 호출은 끝을 알려 주지 않는다. 그래서 같은 실행이 만든 "확인용 방"(sentinel — 48시간 5분 지난 방 하나)이 닫히기를 BATCH_WAIT(시나리오 "1~2분")초
              까지 DB 로 기다리고, 닫히면 SETTLE 초 더 기다려 나머지 방까지 훑게 둔 뒤 판정한다. 안 닫히면 blocked — "알림 0건 · 방 그대로" 같은 안 바뀜 가설이
              배치가 안 돈 것을 모르고 헛통과하지 않는다.

한 시간에 한 가설  chat-gate 를 부르는 것은 폰 8개(50 · 51 · 52 · 55 · 57 · 65 · 66 · 67 — 모두 `_gated_batch`)다. 관문이 같은 시 두 번째 chat-gate 를 막으므로 이 8개는 한 시간에 하나만
              돌 수 있다 — 묶음 전체를 한 번에 돌리면 첫 가설 외에는 "XX:06 에 다시" 로 blocked 되고, 다 끝내려면 여덟 시간이 걸린다. E-CHAT-69 는 cleanup 이라 이 제한이 없다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-CHAT-50  "둘 다 HOME · A 0건" — 폰 한 대라 A 쪽 알림은 못 본다(A 는 기기 토큰이 없어 서버가 보낼 곳도 없다). B 는 앱을 HOME 이 아니라 프로세스를 죽인 채
             기다린다(알림을 눌러 콜드 스타트로 방이 열려야 하는 E-CHAT-32 와 같은 길). 알림이 한 번만 왔는지는 도착 뒤 WATCH_MORE 초 더 본다.
             눌러서 열릴 방에 보일 글 한 줄은 상대가 DB 로 넣는다(푸시가 안 간다).
  E-CHAT-55  "둘 다 목록 새로고침" — A 의 목록은 API(GET /chat/conversations), B 의 목록은 배치 뒤 앱을 새로 켜서 본다. 앱 목록이 아직 안 그려졌을 때 "방 없음" 으로
             헛통과하지 않게, 닫히지 않는 다른 방 하나(control)가 그려질 때까지 기다린 뒤 본다.
  E-CHAT-57  "A 가 방을 연 상태" — 방을 만든 그대로(젊은 방) 앱이 열고 step 에서 멈춘 사이에 PC 가 방을 48시간 5분 지난 것으로 옮기고 배치를 돈다. 앱 방은 옛 상태(젊은 방)
             그대로라 14f 시트가 안 가린다. 문구는 처음 뜬 오류(시트 · 방 다시 읽기가 오류 줄을 지울 수 있다)로 본다.
  E-CHAT-65  "B: HOME → 목록" — 알림은 로그인 판 + 프로세스 죽임으로 지켜보고, 목록은 배치 뒤 앱을 새로 켜서 본다(55 와 같은 control).
  E-CHAT-66  "둘 다 방 열기" — B 는 앱 방의 "신뢰 확인 완료" 카드, A 는 API 방 머리말의 gate.passed(그 값이 카드를 그린다). A 화면 자체는 못 본다.
  E-CHAT-67  "B ≤ 2.0초 표시" — 보낸 시각은 서버가 messages.created_at 에 찍은 값, 본 시각은 앱이 방 뷰모델에서 그 글을 처음 본 앱 시계(UTC)다. 폰 시계와 서버 시계의
             차(시계 차)가 그대로 섞인다 — 음수가 나오면 메모에 남기고 0 으로 친다. 말풍선이 안 떴으면(fail) 메모에 앱 진단 옆으로 서버 진단(DB 행 · B 토큰으로 읽기 ·
             참가자 · 방 상태)과, 앱이 방을 다시 읽어 본 결과의 '추정:' 해석을 붙인다 — fail 이면 같은 번들에서 다시 안 돌리니 한 번에 원인을 가를 증거를 남기려는 것이고 판정은 그대로다.
  E-CHAT-69  cleanup 은 탈퇴 30일 지난 모든 계정(실사용자 포함)을 지우는 하루 한 번 job 이다 — 이번 실행이 만든 계정만 쓰지만 배치 자체는 전부에 돈다(예약 실행과 같은 일).
"""

import functools
import secrets
import time
from datetime import datetime, timedelta, timezone

from e2e import area1, area2, area3, batch_gate, notify, notify_factory, tools
from e2e.area1 import Check, _api, _app, _find_user, _patch, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3 import _as_user, _count, _match, _messages, _send
from e2e.area3_phone import MISSING, _me, _ok, _permitted, _person
from e2e.area3_phone3 import APP_WAIT, NOTICE_WAIT, SEEN, TOKEN_WAIT, _screens
from e2e.tools import Blocked

TITLE, BODY = '신뢰 확인이 기다리고 있어요', '카카오톡 아이디를 공유할지 정해 주세요'  # chat/batch_router.py:60-61
GATE_OVER = '응답 기한이 지나 이 대화는 종료됐어요'  # chat_errors.dart:11
ROOM_LINE = 'E2E-0'  # area3._messages 의 첫 본문 — 알림을 눌러 열린 방에서 앱이 찾는 글
REMIND_AGE = timedelta(hours=24, minutes=5)  # 리마인드 창(24~25시간) 안
MISSED_AGE = timedelta(hours=25, minutes=5)  # 리마인드 창을 지남
CLOSE_AGE = timedelta(hours=48, minutes=5)  # 48시간 기한을 지남
PASS_AGE = timedelta(hours=50)
OLD_AGE = timedelta(hours=72)
WITHDRAWN_AGE = timedelta(days=31)
DAY = (10, 20)  # 시나리오 "낮 10~20시" — 방해 금지(22~08시)에 리마인드가 걸리지 않게
PREP_MINUTES = 8  # 준비(계정 · 앱 · 알림)에 드는 시간의 넉넉한 값 — 이만큼 뒤에도 관문이 열려 있어야 시작한다
BATCH_WAIT = 120  # 시나리오 "1~2분 기다린다"
SETTLE = 20  # 확인용 방이 닫힌 뒤 나머지 방까지 훑을 시간
WATCH_MORE = 10  # 알림이 한 번만 왔는지 보려고 도착 뒤 더 보는 초
LIVE_LIMIT = 2.0  # 시나리오 "B ≤ 2.0초 표시"
CASE_LIMIT = 900  # 폰 가설 하나에 줄 초 — 기본 420 은 배치 기다림(120 + 20)에 알림(60 + 10) · 눌러 열기(90) · 토큰(30) · 계정 준비를 더하면 모자란다


# ── 배치를 부른 뒤의 fail 은 다시 안 돈다 ────────────────────────────────────────────────────────────

_FAILED = {}  # 함수 이름 → 배치를 부른 뒤 fail 이었던 결과
_CALLS = [0]  # 지금까지 배치(gcloud)를 부른 횟수


def _batch(name, before=None):
    """area2._batch(관문 → [before] → gcloud) 를 부르고 센다 — 관문에서 막히거나 gcloud 가 안 불렸으면 세지 않는다."""
    area2._batch(name, before=before)
    _CALLS[0] += 1


def _single_shot(case, always=False):
    """진행 프로그램(run_case)은 fail 이면 같은 가설을 한 번 더 돈다. 배치를 이미 부른 뒤의 fail 은 다시 돌면 관문이 막아(같은 시 두 번째 chat-gate) 진짜 결과가
    blocked 로 덮이거나, cleanup 이면 운영 배치를 또 부른다 — 그래서 그 결과를 기억했다가 다시 불리면 그대로 돌려준다(앱도 계정도 안 만든다).
    배치를 부르기 전의 fail · blocked 는 그대로 다시 돈다. [always] 이면 배치와 상관없이 **모든** fail 을 기억한다 — 시작 시각 창이 있는 시계 가설(E-HOME-24 · 25)은
    첫 시도가 25분쯤 걸려 둘째 시도가 창 밖에서 "지금은 실행 금지 시간" blocked 로 진짜 fail 을 덮기 때문이다(blocked · pass 는 기억하지 않는다)."""
    @functools.wraps(case)
    def wrapped(run, *args):
        if case.__name__ in _FAILED:
            return _FAILED.pop(case.__name__)
        before = _CALLS[0]
        result = case(run, *args)
        if result[0] == 'fail' and (always or _CALLS[0] > before):
            _FAILED[case.__name__] = result
        return result
    return wrapped


# ── 준비 · 배치 공통 ─────────────────────────────────────────────────────────────────────────────────

def _midday(now):
    if not DAY[0] <= now.hour < DAY[1]:
        raise Blocked(f'서울 시각 {now:%H:%M} — 이 가설은 낮 {DAY[0]}:00~{DAY[1] - 1}:59 에만(방해 금지 22~08시에 리마인드가 걸리지 않게)')


def _start(daytime=False, job='chat-gate'):
    """준비 **전에** 부른다. [daytime] 이면 지금 · 준비가 끝날 즈음이 낮 10~20시인지, 그리고 관문이 지금 · 그때 열려 있는지(기록 없이)."""
    now = batch_gate.now_seoul()
    if daytime:
        for later in (0, PREP_MINUTES):
            _midday(now + timedelta(minutes=later))
    batch_gate.peek(job, ahead=PREP_MINUTES)


def _own(run, *accounts):
    area2._guard(run, *(a['id'] for a in accounts))


def _sentinel(run):
    """배치가 돌았다는 증거 — 이번 실행이 만든 두 계정 사이의 방 하나. 배치가 닫으면(48시간 5분 지남) 돈 것이다."""
    return area3._pair(run)


def _ages(run, aged):
    """[(매칭 id, 나이)] 의 created_at 을 지금 − 나이 로. 관문을 지난 직후에 한 번에 — 오래 걸리면 창 경계가 밀린다."""
    now = datetime.now(timezone.utc)
    for match_id, age in aged:
        _patch(run, f'matches?id=eq.{match_id}', {'created_at': (now - age).isoformat()})


def _closed(run, match_id):
    rows = _rows(run, f'matches?id=eq.{match_id}&select=chat_closed_at')
    return bool(rows) and rows[0].get('chat_closed_at') is not None


def _open(run, match_id):
    """방 행이 **있고** chat_closed_at 이 null 인가 — "안 닫혔다" 를 `not _closed` 로 읽으면 방 행이 사라져도 통과한다."""
    rows = _rows(run, f'matches?id=eq.{match_id}&select=chat_closed_at')
    return bool(rows) and rows[0].get('chat_closed_at') is None


def _gated_batch(run, accounts, aged, sentinel):
    """관문 → (통과하면) 방 시각 확정 → chat-gate 한 번 → 확인용 방이 닫히길 기다림 → 나머지 방을 훑을 시간."""
    a, b, sentinel_id = sentinel
    _own(run, *accounts, a, b)
    _batch('chat-gate', before=lambda: _ages(run, [*aged, (sentinel_id, CLOSE_AGE)]))
    if not _wait_for(lambda: _closed(run, sentinel_id), BATCH_WAIT):
        raise Blocked(f'배치를 부른 뒤 {BATCH_WAIT}초 안에 확인용 방(이번 실행이 만든 48시간 지난 방)이 안 닫힘 — 배치가 안 돌았거나 늦음(gcloud 로그에서 200 확인)')
    time.sleep(SETTLE)


def _park(check, run, phone, me, token):
    """폰 계정을 홈까지 로그인시켜 기기 토큰이 올라오게 하고 앱 프로세스를 죽인다(알림이 도착할 상태). 죽이기 전 알림 목록을 돌려준다 —
    로그인 판이 홈에 못 닿았으면 None(알림도 기대할 수 없다)."""
    _app(check, phone(token_hash=token, phase='login'))
    if check.problems:
        return None
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
    before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
    notify.kill_app(phone.serial)
    return before


def _none_came(check, phone, before):
    new = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)
    check.that(not new, f'B 알림이 {len(new)}건 옴(기대 0): {notice_memo(new)}')


def _list_said(check, said, nickname, present):
    """앱이 말한 목록 — control 방이 그려졌을 때만 믿는다(안 그려졌으면 판정을 못 하니 blocked)."""
    if not said:
        return
    if said.get('waited') is not True:
        raise Blocked(f"B 목록이 안 그려짐(열린 다른 방 줄이 {said.get('waited', MISSING)}) — 목록 · 로그인 확인")
    shown = nickname in (said.get('rows') or [])
    check.that(shown == present, f"B 목록에 그 방이 {'없음(기대 있음)' if present else '남아 있음(기대 없음)'}")


# ── 리마인드(24시간) ─────────────────────────────────────────────────────────────────────────────────

def _remind(run, phone, age, accepts, switch_off, arrives):
    """E-CHAT-50 · 51 · 52 — 폰 계정 B 가 홈까지 켠 뒤 프로세스를 죽이고, 배치를 한 번 돌려 B 알림이 [arrives] 면 1건(눌러 방 열기까지) 아니면 0건."""
    _start(daytime=True)
    check = Check()
    me, token = _me(run)
    partner = _person(run)
    _own(run, me, partner)
    sentinel = _sentinel(run)
    if switch_off:
        notify_factory.switches(run, me, trust_reminder=False)  # 앱 16d 와 같은 길 — B 의 스위치만
    match_id = _match(run, me, partner)
    if accepts:
        notify_factory.trust(run, partner, match_id)  # A 만 수락해 둔다
        _messages(run, match_id, partner, 1)  # 눌러서 열릴 방에 보일 글(DB 로 직접 — 푸시가 안 간다)
    before = _park(check, run, phone, me, token)
    if before is None:
        return check.result()
    _gated_batch(run, [me, partner], [(match_id, age)], sentinel)
    if not arrives:
        _none_came(check, phone, before)
        return check.result()
    want = (TITLE, BODY)
    new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == want)
    if any((n.title, n.text) == want for n in new):  # 한 번만 왔는지(24시간 창은 한 시간짜리인데 두 번 가는 한계가 있다) — 도착 뒤 더 지켜본다
        new = notify.wait_new(phone.serial, before, count=999, seconds=WATCH_MORE)
    arrived = [n for n in new if (n.title, n.text) == want]
    check.that(len(arrived) == 1, f'B 알림 "{TITLE} / {BODY}" {len(arrived)}건(기대 1) — 새 알림 {len(new)}건: {notice_memo(new)}')
    if check.problems:
        return check.result()
    # 누르기 전에 일감을 넣는다 — 알림으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 이것을 가져간다
    phone.hub.tell({'case': phone.case, 'phase': 'tap', 'nickname': partner['nickname'], 'body': ROOM_LINE})
    notify.tap_notification(phone.serial, TITLE)
    said = _app(check, phone.hub.result(APP_WAIT))
    if said:
        for key, label in SEEN:
            check.that(said.get(key) is True, f'{label}({key}) {said.get(key, MISSING)}(기대 True)')
        if not all(said.get(key) is True for key, _ in SEEN):
            check.problems.append(f'그때 보인 화면 {_screens(said)}')
    return check.result('A 쪽 알림 0건은 못 봄(기기 없음 — A 는 이미 수락해서 서버도 안 보낸다)')


def p_chat_50(run, phone):
    return _remind(run, phone, REMIND_AGE, accepts=True, switch_off=False, arrives=True)


def p_chat_51(run, phone):
    return _remind(run, phone, MISSED_AGE, accepts=False, switch_off=False, arrives=False)


def p_chat_52(run, phone):
    return _remind(run, phone, REMIND_AGE, accepts=True, switch_off=True, arrives=False)


# ── 닫기 · 통과 · 건너뛰기(48시간) ───────────────────────────────────────────────────────────────────

def p_chat_55(run, phone):
    _start()
    check = Check()
    me, partner, other = _person(run), _person(run), _person(run)
    _own(run, me, partner, other)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)
    _messages(run, match_id, partner, 10)
    _match(run, me, other)  # control — 닫히지 않는 다른 방. B 목록이 그려졌다는 증거
    _gated_batch(run, [me, partner, other], [(match_id, CLOSE_AGE)], sentinel)
    check.that(_closed(run, match_id), 'matches.chat_closed_at 이 안 채워짐(기대 채워짐)')
    rows = _count(run, f'messages?match_id=eq.{match_id}')
    check.that(rows == 10, f'messages {rows}행(기대 10행 그대로)')
    status, body = _api(run, 'GET', '/chat/conversations', partner['token'])
    ids = [c['match_id'] for c in (body or {}).get('conversations', [])] if status == 200 else None
    check.that(ids is not None and match_id not in ids, f'A 목록 {status} {ids}(기대 200 · 그 방 없음)')
    said = _app(check, phone(token_hash=run.link(me['email']), control=other['nickname']))
    _list_said(check, said, partner['nickname'], present=False)
    return check.result()


def p_chat_57(run, phone):
    _start()
    check = Check()
    me, token = _me(run)
    partner = _person(run)
    _own(run, me, partner)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)
    _messages(run, match_id, partner, 10)

    def close_while_open(said):  # 앱이 방을 연 채 step 에서 멈춘 사이 — 방이 48시간 5분 지난 것이 되고 배치가 닫는다
        _gated_batch(run, [me, partner], [(match_id, CLOSE_AGE)], sentinel)
        check.that(_closed(run, match_id), 'matches.chat_closed_at 이 안 채워짐 — 배치가 방을 안 닫음')

    said = _app(check, phone(midway=close_while_open, token_hash=token, nickname=partner['nickname'], text='E2E-57'))
    note = ''
    if said:
        first, last = said.get('error', MISSING), said.get('error_now', MISSING)
        check.that(first == GATE_OVER, f'오류 문구 {first!r}(기대 {GATE_OVER!r})')
        if first == GATE_OVER and last != first:
            note = f'끝 값 {last!r} — 오류 줄이 지워짐(시트 · 방 다시 읽기 copyWith 규칙, 처음 값으로 판정)'
    rows = _count(run, f'messages?match_id=eq.{match_id}')
    check.that(rows == 10, f'messages {rows}행(기대 10행 그대로 — 새 행 0)')
    return check.result(note)


def p_chat_65(run, phone):
    _start()
    check = Check()
    me, token = _me(run)
    partner, other = _person(run), _person(run)
    _own(run, me, partner, other)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)
    _ok('상대 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', partner['token']))  # A 가 나간다 — left_at 이 찍힌다
    _match(run, me, other)  # control
    before = _park(check, run, phone, me, token)
    if before is None:
        return check.result()
    _gated_batch(run, [me, partner, other], [(match_id, CLOSE_AGE)], sentinel)
    _none_came(check, phone, before)
    check.that(_open(run, match_id), 'matches 행이 없거나 chat_closed_at 이 채워짐 — 한쪽이 나간 방을 배치가 닫음(기대: 행이 있고 null — 행이 없으면 "안 닫힘" 을 읽을 수 없다)')
    said = _app(check, phone(token_hash=run.link(me['email']), phase='list', control=other['nickname']))
    _list_said(check, said, partner['nickname'], present=True)
    return check.result()


def p_chat_66(run, phone):
    _start()
    check = Check()
    me, partner = _person(run), _person(run)
    _own(run, me, partner)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)
    _patch(run, f'match_participants?match_id=eq.{match_id}', {'trust_response': 'accept', 'responded_at': datetime.now(timezone.utc).isoformat()})
    _gated_batch(run, [me, partner], [(match_id, PASS_AGE)], sentinel)
    row = (_rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at,chat_closed_at') or [{}])[0]
    check.that(row.get('trust_passed_at') is not None, 'matches.trust_passed_at 이 안 채워짐(기대 채워짐)')
    check.that(row.get('chat_closed_at') is None, 'matches.chat_closed_at 이 채워짐(기대 null)')
    status, room = _api(run, 'GET', f'/chat/matches/{match_id}', partner['token'])
    passed = ((room or {}).get('gate') or {}).get('passed') if status == 200 else None
    check.that(passed is True, f'A 쪽 방 머리말 {status} passed {passed}(기대 200 · True)')
    said = _app(check, phone(token_hash=run.link(me['email']), nickname=partner['nickname']))
    if said:
        check.that(said.get('card') is True, f"신뢰 확인 완료 카드 {said.get('card', MISSING)}(기대 True)")
    return check.result('A 화면은 못 봄 — 방 머리말의 gate.passed 로 대신(그 값이 카드를 그린다)')


def _at(text):
    """앱이 말한 시각(Dart toUtc().toIso8601String()) — 못 읽으면 None."""
    try:
        at = datetime.fromisoformat(text.replace('Z', '+00:00'))
    except (AttributeError, ValueError):
        return None
    return at if at.tzinfo else at.replace(tzinfo=timezone.utc)


def _live_diagnosis(said):
    """말풍선이 안 떴을 때 앱이 본 것 — 방 읽기 · 통과 도장 · 뷰모델 글 · 화면 글 · 오류(구독 전에 글이 들어갔는지, 구독은 됐는데 못 그렸는지 가른다).
    seen_at 이 없던 앱은 판정 뒤에 방을 다시 읽어 본다(area3_b5.dart _batchLiveBubble) — 그 전의 통로 상태와 다시 읽은 결과도 붙인다."""
    text = (f"앱 진단 loaded {said.get('loaded', MISSING)} · gate passed {said.get('passed', MISSING)} · 뷰모델 글 {said.get('vm_count', MISSING)}건 "
            f"{said.get('vm_bodies', MISSING)} · 화면 말풍선 {said.get('screen_bodies', MISSING)} · 오류 {said.get('error', MISSING)!r}")
    if 'channels_before' in said:
        text += (f" · 재연결 전 isDisconnected {said.get('disconnected_before', MISSING)} · 소켓 {said.get('socket_before', MISSING)} · "
                 f"실시간 토큰이 세션 토큰과 같음 {said.get('rt_token_is_session', MISSING)} · 채널 {said.get('channels_before')}")
    again = said.get('after_reconnect')
    if isinstance(again, dict):
        text += (f" · 재연결 뒤 찾음 {again.get('found', MISSING)} · 재연결 뒤 뷰모델 글 {again.get('vm_count', MISSING)}건 {again.get('vm_bodies', MISSING)} · "
                 f"다시 읽기 끝남 {again.get('finished', MISSING)} · 다시 읽기 오류 {again.get('error', MISSING)!r}")
    return text


def _system_events_note(events):
    """앱이 방 채널에서 받은 system 이벤트를 한 토막으로 — 개수 · 첫 ok 시각 · (최대 4건의) 모양. 모양을 같이 남기는 이유: 서버가 보내는 system 이벤트의
    실제 값은 아직 못 봤다(area3_b5.dart _RoomChannelWatch) — 이번 실행이 `isPostgresReady` 가 맞는 모양을 보고 있었는지 가른다. 어떤 모양이 와도 던지지 않는다."""
    if not isinstance(events, list):
        return f'system 보고 모양 이상({type(events).__name__})'
    shown = [e for e in events if isinstance(e, dict)]
    first_ok = next((e.get('ms') for e in shown if e.get('status') == 'ok'), None)
    head = f"system {len(shown)}건({f'첫 ok {first_ok}ms' if first_ok is not None else 'ok 없음'})"
    shapes = ', '.join(f"{e.get('ms')}ms {e.get('extension')}/{e.get('status')} {e.get('message')!r}" for e in shown[:4])
    return f'{head} [{shapes}]' if shapes else head


def _channel_note(said):
    """앱이 잰 방 채널 사실 한 구절 — 채널이 방 읽기 뒤 몇 ms 에 처음 joined 로 보였는지 · 글을 보내기 직전에 joined 였는지 · system 이벤트.
    pass 든 fail 이든 메모에 붙는다(E-CHAT-67 의 "채널 준비 전에 보낸 글" 가설을 다음 실기기 실행이 확정 / 기각하게). 앱이 말한 키만 옮기므로 서버 호출은 없고,
    키가 하나도 없으면(옛 앱) ''. 값이 이상해도 던지지 않는다(진단은 판정을 바꾸지 않는다)."""
    parts = []
    if 'joined_ms' in said:
        joined = said['joined_ms']
        parts.append(f'채널 joined {joined}ms' if joined is not None else '채널 joined 못 봄')
    if 'joined_at_send' in said:
        parts.append(f"보낼 때 joined={said['joined_at_send']}")
    if 'system_events' in said:
        parts.append(_system_events_note(said['system_events']))
    return ' · '.join(parts)


def _read(read):
    """진단 읽기 하나 → (값, 못 읽은 사유). 진단 때문에 fail 이 blocked 로 바뀌면 안 되니 여기서 다 잡는다. Blocked 의 글은 시험이 쓴 것(경로 · 상태)이라 그대로,
    그 밖(끊김)은 예외 글에 주소가 들 수 있어 종류만 적는다. 읽는 것은 모두 행 목록이다 — 목록이 아닌 200 은 못 읽은 것으로 친다."""
    try:
        got = read()
        if not isinstance(got, list):
            raise Blocked('응답이 행 목록이 아님')
        return got, None
    except Blocked as e:
        return None, str(e)
    except Exception as e:  # noqa: BLE001 — 진단은 판정을 바꾸지 않는다
        return None, type(e).__name__


def _as_b(run, me, path):
    """B 의 토큰으로(공개 키 + 사용자 토큰 — RLS 를 거친다) 읽은 행. 200 이 아니면 읽지 못한 것이다(상태가 사유)."""
    status, rows = _as_user(run, me, 'GET', path)
    if status != 200:
        raise Blocked(f'상태 {status}')
    return rows


def _server_diagnosis(run, me, partner, match_id, body, said):
    """말풍선이 **안 떴을 때만** 부른다(떴으면 DB 를 더 읽지 않는다). 앱 진단 문장 옆에 붙는 서버 쪽 사실 — 글 행이 DB 에 있는지(서비스 키) · B 의 권한(RLS)으로 읽히는지 ·
    B 의 참가자 행 · 방 상태. 앱이 다시 읽기를 말했으면 그 해석을 '추정:' 으로 사실과 가려 덧붙인다."""
    path = f'messages?match_id=eq.{match_id}&body=eq.{body}&select=id,sender_id,kind,created_at'
    stored, why_stored = _read(lambda: _rows(run, path))
    seen, why_seen = _read(lambda: _as_b(run, me, path))
    parts, why_parts = _read(lambda: _rows(run, f'match_participants?match_id=eq.{match_id}&select=profile_id,left_at,last_read_at'))
    room, why_room = _read(lambda: _rows(run, f'matches?id=eq.{match_id}&select=created_at,trust_passed_at,chat_closed_at'))
    mine = next((p for p in parts or [] if p.get('profile_id') == me['id']), None)
    facts = [
        f"DB 행 {len(stored)}건(A 가 보낸 것 {sum(r.get('sender_id') == partner['id'] for r in stored)}건 · kind {sorted({r.get('kind') for r in stored})})"
        if stored is not None else f'DB 행 읽지 못함({why_stored})',
        f'B 토큰으로 읽기 200 · 보이는 행 {len(seen)}건' if seen is not None else f'B 토큰으로 읽기 읽지 못함({why_seen})',
        (f"참가자 {len(parts)}행 · " + (f"B left_at {mine.get('left_at')} · B last_read_at {mine.get('last_read_at')}" if mine else 'B 행 없음'))
        if parts is not None else f'참가자 읽지 못함({why_parts})',
        (f"방 created_at {room[0].get('created_at')} · trust_passed_at {room[0].get('trust_passed_at')} · chat_closed_at {room[0].get('chat_closed_at')}"
         if room else '방 행 없음') if room is not None else f'방 읽지 못함({why_room})',
    ]
    text = '서버 진단 ' + '; '.join(facts)
    again = said.get('after_reconnect')
    if isinstance(again, dict):
        text += f' · 추정: {_reconnect_guess(again, stored, seen)}'
    return text


def _reconnect_guess(again, stored, seen):
    """다시 읽기(reconnect) 결과의 해석 — 가설이다. 사실이 먼저 갈린다: DB 에 없음 → B 토큰이 못 봄 → 앱의 다시 읽기가 못 끝남 → 보임 → 못 찾음.
    [stored] · [seen] 이 None 이면 그 읽기를 못 한 것이라 "정상" 이라 말하지 않는다."""
    if stored == []:
        return '서버가 201 을 줬는데 행이 없음'
    if seen == []:
        return 'B 토큰으로 안 읽힘 — RLS/참가자 쪽'
    sound = bool(stored) and bool(seen)
    if again.get('found') is True:
        return '다시 읽으면 보임 — 실시간 채널만 글을 못 받음' + ('(서버 저장·RLS 는 정상)' if sound else '')
    if again.get('finished') is False or again.get('error'):
        return '앱의 다시 읽기가 제시간에 안 끝나거나 오류로 끝나 가르지 못함'
    return 'DB·RLS 정상인데 앱이 다시 읽어도 못 가져옴' if sound else '다시 읽어도 안 보이지만 읽지 못한 진단이 있어 원인을 못 가름'


def p_chat_67(run, phone):
    _start()
    check = Check()
    me, partner = _person(run), _person(run)
    _own(run, me, partner)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)
    _patch(run, f'matches?id=eq.{match_id}', {'trust_passed_at': datetime.now(timezone.utc).isoformat()})
    _gated_batch(run, [me, partner], [(match_id, OLD_AGE)], sentinel)
    check.that(_open(run, match_id), 'matches 행이 없거나 chat_closed_at 이 채워짐 — 통과한 방을 배치가 닫음(기대: 행이 있고 null — 행이 없으면 "안 닫힘" 을 읽을 수 없다)')
    body = f'E2E-67-{secrets.token_hex(4)}'
    sent = []
    said = _app(check, phone(midway=lambda said: sent.append(_send(run, partner, match_id, body)), token_hash=run.link(me['email']),
                             nickname=partner['nickname'], body=body))  # B 가 방을 연 채 멈춘 사이 A 가 보낸다
    if said and said.get('loaded') is False:  # 앱이 방 읽기를 못 끝내 글을 보내기 전에 멈췄다 — 구독 전에 보내면 가짜 실패(E-CHAT-10 과 같다)
        raise Blocked(f"B 방이 안 읽힘(loaded False · 오류 {said.get('error')!r}) — 글을 보내지 않았다. 로그인 · 방 확인")
    check.reply('A 보내기', sent[0] if sent else (0, '앱이 멈추기 전에 끝남'), 201)
    note, channel = '', ''
    if said:
        channel = _channel_note(said)
        shown = said.get('bubble') is True
        why = '' if shown else f' · {_server_diagnosis(run, me, partner, match_id, body, said)}'  # 안 떴을 때만 DB 를 더 읽는다
        check.that(shown, f"B 말풍선 {said.get('bubble', MISSING)}(기대 True) · 앱이 글을 본 시각 seen_at {said.get('seen_at', MISSING)} · {_live_diagnosis(said)}{why}")
        created = _at((_rows(run, f'messages?match_id=eq.{match_id}&body=eq.{body}&select=created_at') or [{}])[0].get('created_at'))
        seen = _at(said.get('seen_at'))
        if created and seen:
            delay = (seen - created).total_seconds()
            check.that(delay <= LIVE_LIMIT, f'B 화면에 {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})')
            note = f'지연 {delay:.2f}초(앱 시계 − 서버가 찍은 보낸 시각)' + (' — 음수는 폰 시계가 서버보다 앞선 시계 차' if delay < 0 else '')
        elif said.get('bubble') is True:
            check.problems.append('앱이 본 시각(seen_at)을 말하지 않음')
    if channel and check.problems:  # fail 은 메모가 문제 목록뿐이다 — 채널 측정도 거기 붙인다
        check.problems.append(channel)
    return check.result(' · '.join(part for part in (note, channel) if part))


PHONE5 ={'E-CHAT-50': p_chat_50, 'E-CHAT-51': p_chat_51, 'E-CHAT-52': p_chat_52, 'E-CHAT-55': p_chat_55, 'E-CHAT-57': p_chat_57,
          'E-CHAT-65': p_chat_65, 'E-CHAT-66': p_chat_66, 'E-CHAT-67': p_chat_67}
PHONE5 = {name: _permitted(_single_shot(case)) for name, case in PHONE5.items()}
tools.CASE_LIMITS.update({name: CASE_LIMIT for name in PHONE5})


# ── 정리 배치(cleanup) — 폰 없음 ─────────────────────────────────────────────────────────────────────

def _withdraw(run, account):
    """탈퇴 상태 + withdrawn_at = 31일 전. 탈퇴 상태와 withdrawn_at 은 짝(profiles_withdrawn_pair)이라 한 번에 쓴다."""
    area2._guard(run, account['id'])
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'withdrawn', 'withdrawn_at': (datetime.now(timezone.utc) - WITHDRAWN_AGE).isoformat()})


def chat_69(run):
    _start(job='cleanup')
    check = Check()
    a, b = run.account('basic'), run.account('basic')  # a 는 남는 쪽, b 가 탈퇴
    _own(run, a, b)
    match_id = _match(run, a, b)
    _messages(run, match_id, a, 2)
    _messages(run, match_id, b, 1)
    _withdraw(run, b)
    _batch('cleanup')
    if not _wait_for(lambda: _find_user(run, b['email']) is None, BATCH_WAIT):
        raise Blocked(f'정리 배치 뒤 {BATCH_WAIT}초가 지나도 탈퇴 계정의 auth 사용자가 남아 있음 — 배치가 안 돌았거나 늦음')
    check.that(not _rows(run, f"profiles?id=eq.{b['id']}&select=id"), 'profiles 행이 남음(기대 없음)')
    for table, path in (('matches', f'matches?id=eq.{match_id}'), ('messages', f'messages?match_id=eq.{match_id}')):
        left = _count(run, path)
        check.that(left == 0, f'{table} {left}행이 남음(기대 0 — cascade)')
    alive = bool(_rows(run, f"profiles?id=eq.{a['id']}&select=id")) and _find_user(run, a['email']) is not None
    check.that(alive, '산 계정(A)까지 지워짐')
    return check.result('deleted_accounts 개수는 스케줄러 호출이라 못 읽음 — 계정 · 행 상태로 확인')


CASES = {'E-CHAT-69': _single_shot(chat_69)}

area1.PHONE.update(PHONE5)
area3.BUNDLES['area3-phone-5'] = [*PHONE5, *CASES]


def attempt(run, case):
    """API 가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
