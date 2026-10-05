"""영역 4 PUSH 채팅 게이트 배치(chat-gate) 11개 — 40~48 · 79 · 80(묶음 area4-push-gate). 받는 사람 폰 한 대 + 상대·배치는 PC.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본) — 그러나 **문구·시각은 코드가 기준**이다
(backend/app/chat/gate.py · batch_router.py: 리마인드는 매칭 24시간 뒤 한 시간짜리 창, 22~8시면 다음 아침 8시로 밀림, 48시간이 지나면 알림 없이 닫힘).

가설 하나 = 함수 하나 `(scene)`. 폰 계정(me, 알림 받는 쪽)과 상대(partner)를 만들고 둘의 매칭을 DB 로 만든 뒤, **배치를 부르기 직전에** 매칭의
created_at 을 지금 기준으로 옮기고 `area2._batch('chat-gate')` 를 한 번 부른다. 배치 응답(reminded · closed · passed)은 gcloud 호출이라 PC 가 못 읽으니
판정은 폰 알림창과 DB 로 한다. **배치가 돌았다는 증거(앵커)**: 새 계정 둘의 매칭에 양쪽 trust_response=accept 를 넣어 두면 배치가 trust_passed_at 도장을
찍는다 — 안 오는 것이 "배치가 안 돌아서" 인지 "서버가 안 보내서" 인지는 이 도장으로 가른다. 도장이 안 찍히면 fail 이 아니라 blocked.

안전(정직하게): 손으로 부르는 chat-gate 는 **열린 매칭 전부**를 처리한다 — 실사용자의 리마인드(정각 예약 실행이 이미 보낸 사람에게는 중복)·48시간 마감·통과 도장도
같이 처리한다. 하네스가 `ensure_no_real_users` 로 실사용자 0 일 때만 돌려 실제 위험은 막혀 있다. 같은 시(時)에 두 번 부르면 리마인드가 두 번 가므로(gate.py
needs_reminder ponytail 주석) 같은 시 두 번째 호출은 batch_gate 가 막는다(예약 실행과 겹친다 — batch_gate.py 맨 위 설명).

시각 규칙(가장 중요): chat-gate 는 정각 ±5분 금지 · 같은 시(時) 두 번 금지(`area2._batch` 가 관문)이고, 게다가 예약 실행이 매시 정각에 돈다.
리마인드 창이 한 시간이라 항상 정각 하나를 품는다. 그래서 시작은 서울 **08:06~21:48 의 hh:06~hh:48 분**에만(관측 60+30초가 다음 정각 전에 끝나고, 창이 조용한
시간에 안 걸리게 낮) — 밖이면 계정·앱 만들기 전에 blocked("HH:MM 에 다시"), 폰 준비 뒤 배치 직전에 한 번 더 본다.
**45 만 09:06 부터**: created_at 이 now−25h1m 이라 08시대에 시작하면 created_at+24h 가 07시대 → reminder_at 이 08:00 으로 밀어 창이 [08:00, 09:00) 이 되고,
now 가 그 안이라 서버는 정상으로 리마인드를 보낸다(가설은 "안 온다" 라 서버가 멀쩡한데 FAIL). 09시 이후엔 창이 now−1분에 끝난다(시험이 격자로 backend gate.py 와 대조).
가설마다 배치를 한 번 부르니 **가설 하나 = 시계의 시 하나**다(11개 = 11개 시). 같은 시의 두 번째 가설은 관문이 막아 blocked("13:06 에 다시") — 정상이다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  재시도        진행 프로그램은 fail 이면 같은 가설을 한 번 더 돈다. 배치를 부른 뒤의 fail 은 기억해 두고 다시 불리면 그대로 돌려준다(`_FAILED`, 앱 · 계정 · 배치를 또
                안 만든다) — 안 그러면 같은 시 관문(46 · 44 는 한 시간짜리)에 막혀 진짜 fail 이 blocked 로 덮인다. 배치 전의 fail · blocked 는 그대로 다시 돈다.
  A·B 두 사람   폰이 하나라 폰 계정(me) 쪽 알림만 본다. 상대(B) 쪽 알림 1개 · 배치 응답 `reminded 2` 는 못 봄 — 메모에 적는다.
  "안 온다"     같은 실행 안에서 대조 message 하나가 실제로 오는 것까지 보고서야 pass(A1 의 silent/control). 앵커 도장 확인이 먼저다.
  46            시나리오는 "배치 2번"인데 같은 시 손 호출은 관문이 막는다 → **손 호출 1번 + 다음 정각 예약 실행 1번**으로 같은 시간 안 두 번을 만든다.
                2개 → pass(알려진 한계 확인) · 1개뿐 → blocked(예약 실행이 안 온 것과 한계가 없는 것을 못 가름) · 3개 이상 → fail.
                created_at 은 다른 가설의 −5분이 아니라 **−2분**: 창이 [now−2분, now+58분) 이라 분이 6 이상이면 다음 정각이 4분 넘게 여유 있게 창 안이다(−5분이면 1분).
                시작은 20:48 까지(그 이상이면 다음 정각이 22시 — 조용한 시간이라 예약 실행이 리마인드를 안 보낸다).
  44            시나리오는 "07시대에도 한 번, 08시대에 배치" — 07:06~07:48 시작, 07시 손 호출 1번 → 07시대 0개(앵커 · 대조 포함) → 08:00 예약 실행을 08:03 까지 기다림 →
                알림이 있으면 pass, 없으면 08:06~08:48 에 손 호출 1번 더. 예약+손 호출이 겹쳐 2개여도 개수는 사유가 아님(메모). 이 가설만 낮 검사를 안 한다(07시).
                한 시간 가까이 걸린다(CASE_LIMITS 4500).
  42 · 80       시나리오는 B에뮬 — 폰 한 대로 돈다. 42 는 앱이 살아 있는 채(뒤) 누르므로 앱이 `step` 에서 멈춘 사이 PC 가 일한다(midway). 79 는 앱을 죽이고 누르는
                콜드 스타트(E-CHAT-32 방식, phase login → kill → phase tap). 80 은 앱을 대화 탭에 둔 채 배치 → 60초 0개 → HOME → 대조 → 다시 앞.
  80            "대화 목록만 다시 읽는다" 는 앱 안 일이라 목록과 상대 줄이 그대로인지만 본다. 서버가 정말 보냈는지(reminded 에 폰 계정 포함)는 응답을 못 읽는다 —
                앵커로 배치가 돈 것까지만 확인.
  79            앱이 방을 연 시각은 앱이 말한 ms(일감을 받은 뒤, 앱 부팅 포함)를 메모하고 30초 안이면 pass(시나리오 10초는 메모로만).
  48            "알림 없이" — 리마인드뿐 아니라 새 알림 전부 0개를 본다. 배치는 매칭을 하나씩 훑어 앵커 도장이 chat_closed_at 보다 먼저 찍힐 수 있어, 앵커를 본 뒤에도
                SETTLE 초까지 chat_closed_at 을 기다린 다음에야 안 닫혔다고(FAIL) 본다.
"""

import functools
import time
from datetime import timedelta, timezone

from e2e import area1, area2, area3_phone, batch_gate, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _app, _patch, _rows
from e2e.area2_phone3 import _wait_for
from e2e.area3_phone import _permitted
from e2e.area3_phone3 import _screens
from e2e.area4_push import CASE_LIMIT_SLOW, SETTLE, TOKEN_WAIT, _Scene
from e2e.area4_push_a4 import _front
from e2e.tools import Blocked

REMINDER_TITLE = '신뢰 확인이 기다리고 있어요'  # backend/app/chat/batch_router.py run_chat_gate
REMINDER_BODY = '카카오톡 아이디를 공유할지 정해 주세요'
ANCHOR_WAIT = 90  # 배치 뒤 앵커 도장이 찍히기를 기다리는 초(스케줄러 호출은 끝을 알려 주지 않는다)
POLL = 10  # 44 · 46 이 한 시간 가까이 알림창을 읽는 간격(초)
APP_WAIT = 90  # 눌린 앱이 방을 열고 말하기를 기다리는 초(area3_phone3 와 같다)
CASE_LIMIT_HOUR = 4500  # 다음 정각 · 아침 8시까지 기다리는 가설(44 · 46)의 상한
FIRST_START_HOUR = 8  # 시작해도 되는 첫 시(08:06)
EXPIRED_FIRST_HOUR = 9  # 45 는 09:06 부터 — 08시대는 reminder_at 이 08:00 으로 밀어 창이 [08:00, 09:00) 이라 서버가 정상으로 보낸다
LAST_START_HOUR = 21  # 시작해도 되는 마지막 시(21:48)
DUE = timedelta(hours=24, minutes=5)  # 리마인드 창이 지금−5분에 시작
DUE_FOR_TWICE = timedelta(hours=24, minutes=2)  # 46 — 다음 정각 예약 실행이 창 안에 여유 있게 들어가게
EXPIRED = timedelta(hours=25, minutes=1)  # 창이 1분 전에 끝남
CLOSED = timedelta(hours=49)  # 48시간 기한을 넘김
SEEN = (('room', '방 화면'), ('nickname', '앱바 닉네임'))


# ── 배치를 부른 뒤의 fail 은 다시 안 돈다 ───────────────────────────────────────────────────────────

_FAILED = {}  # (묶음 폴더, 가설 함수 이름) → 배치를 부른 뒤 fail 이었던 결과
_CALLS = [0]  # 지금까지 배치(gcloud)를 부른 횟수


def _batch(name):
    """area2._batch(관문 → gcloud) 를 부르고 센다 — 관문에서 막히거나 gcloud 가 안 불렸으면 세지 않는다."""
    area2._batch(name)
    _CALLS[0] += 1


# ── 시각 창(순수 함수) ──────────────────────────────────────────────────────────────────────────────

def now_seoul():
    return batch_gate.now_seoul()


def _open(t, last_hour, first_hour=FIRST_START_HOUR):
    return first_hour <= t.hour <= last_hour and 6 <= t.minute <= 48


def _refusal(open_at, now, ran):
    """[open_at](t) 가 참인 분에만 시작할 수 있다. [ran] 은 chat-gate 를 앞서 부른 서울 시각들 — 그 시(時)는 닫힌 것으로 본다(같은 시 두 번 금지).
    닫혔으면 "지금은 실행 금지 시간 — HH:MM 에 다시"(날이 다르면 요일까지), 열렸으면 None."""
    def shut(t):
        return not open_at(t) or any((r.date(), r.hour) == (t.date(), t.hour) for r in ran)

    if not shut(now):
        return None
    t = now.replace(second=0, microsecond=0)
    for _ in range(3 * 24 * 60):
        t += timedelta(minutes=1)
        if not shut(t):
            break
    when = f'{t:%H:%M}' if t.date() == now.date() else f'{batch_gate.WEEKDAY_NAMES[t.weekday()]}요일 {t:%H:%M}'
    return f'지금은 실행 금지 시간 — {when} 에 다시'


def gate_window_refusal(now, last_hour=LAST_START_HOUR, ran=(), first_hour=FIRST_START_HOUR):
    """[now] 가 서울 [first_hour]:06~[last_hour]:48 의 hh:06~hh:48 분(이고 [ran] 에 없는 시)이면 None, 아니면 "지금은 실행 금지 시간 — HH:MM 에 다시"."""
    return _refusal(lambda t: _open(t, last_hour, first_hour), now, ran)


def expired_refusal(now, ran=()):
    """45 — 서울 09:06~21:48. 08시대에 시작하면 서버가 정상으로 리마인드를 보낸다(EXPIRED_FIRST_HOUR 설명)."""
    return gate_window_refusal(now, ran=ran, first_hour=EXPIRED_FIRST_HOUR)


def morning_refusal(now, ran=()):
    """44 — 서울 07:06~07:48 에 시작해야 07시 손 호출(정각 ±5분 밖)과 08:00 예약 실행을 모두 볼 수 있다."""
    return _refusal(lambda t: 7 * 60 + 6 <= t.hour * 60 + t.minute <= 7 * 60 + 48, now, ran)


def twice_refusal(now, ran=()):
    """46 — 시작은 20:48 까지. 다음 정각 예약 실행이 22시(조용한 시간)면 리마인드를 안 보내 "한계가 없다" 와 구별이 안 된다."""
    return gate_window_refusal(now, last_hour=LAST_START_HOUR - 1, ran=ran)


# ── 장면 ────────────────────────────────────────────────────────────────────────────────────────────

class _LiveScene(_Scene):
    """앱이 살아 있는 채 PC 가 일하는 가설(42 · 80)의 장면 — 부모와 달리 앱을 먼저 켜지 않는다(앱은 가설이 midway 로 켜고 `step` 에서 PC 를 기다린다)."""

    def __init__(self, run, phone, daytime=True):
        if daytime:
            notify.require_daytime()
        notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 부모 장면과 같이 시작 때 한 번 점검
        self.run, self.phone, self.check, self.notes = run, phone, Check(), []
        self.me = area3_phone._person(run)
        self.partner = area3_phone._person(run)
        self.ready = True


def _gate_case(window=gate_window_refusal, daytime=True, live=False):
    """시각 창을 **계정 · 앱을 만들기 전에** 본다(밖이면 blocked + "HH:MM 에 다시"). 안이면 알림 권한을 주고 장면을 만들어 가설을 돈다."""
    scene_class = _LiveScene if live else _Scene

    def decorate(fn):
        def play(run, phone):
            scene = scene_class(run, phone, daytime=daytime)
            if scene.ready:
                fn(scene)
            return scene.check.result('; '.join(scene.notes))

        play = _permitted(play)

        @functools.wraps(fn)
        def wrapped(run, phone):
            """진행 프로그램(run_case)은 fail 이면 같은 가설을 한 번 더 돈다. 배치를 이미 부른 뒤의 fail 은 다시 돌면 관문이 막아(같은 시 두 번째 chat-gate) 진짜 결과가
            blocked 로 덮이므로 기억했다가 다시 불리면 그대로 돌려준다(앱도 계정도 안 만든다). 배치 전의 fail · blocked 는 그대로 다시 돈다."""
            key = (str(run.out), fn.__name__)
            if key in _FAILED:
                return _FAILED.pop(key)
            said = window(now_seoul(), ran=batch_gate._ran())  # 같은 시 두 번째 가설은 계정을 만들기 전에 여기서 막힌다
            if said:
                raise Blocked(said)
            before = _CALLS[0]
            result = play(run, phone)
            if result[0] == 'fail' and _CALLS[0] > before:
                _FAILED[key] = result
            return result
        return wrapped
    return decorate


# ── DB · 배치 도우미 ────────────────────────────────────────────────────────────────────────────────

def _iso(moment):
    return moment.astimezone(timezone.utc).isoformat()


def _set_created(s, match_id, moment):
    area2._guard(s.run, s.me['id'], s.partner['id'])
    _patch(s.run, f'matches?id=eq.{match_id}', {'created_at': _iso(moment)})


def _anchor(s):
    """배치가 돌았다는 DB 증거 — 새 계정 둘의 매칭에 양쪽 accept. trust_passed_at 은 비워 둬, 배치가 돌면 도장이 찍힌다."""
    match_id = factory.match(s.run, s.run.account('home'), s.run.account('home'))
    _patch(s.run, f'match_participants?match_id=eq.{match_id}', {'trust_response': 'accept'})
    return match_id


def _setup(s, state=None):
    """(앵커 매칭, 폰 계정 · 상대 매칭). [state](match_id)는 그 매칭의 DB 모양을 만든다."""
    anchor = _anchor(s)
    match_id = factory.match(s.run, s.me, s.partner)
    if state:
        state(match_id)
    return anchor, match_id


def _stamps(s, match_id):
    rows = _rows(s.run, f'matches?id=eq.{match_id}&select=trust_passed_at,chat_closed_at')
    return rows[0] if rows else {}


def _confirm_ran(s, anchor, also=None):
    """배치가 돌았다는 증거(앵커 도장, 또는 [also])를 기다린다. 안 찍히면 [Blocked] — 알림이 없는 것이 배치가 안 돈 탓일 수 있다."""
    if not _wait_for(lambda: _stamps(s, anchor).get('trust_passed_at') or (also and also()), ANCHOR_WAIT):
        raise Blocked(f'배치가 돈 것 같지 않아 알림이 없다는 것을 믿을 수 없음 — 앵커 매칭에 trust_passed_at 이 {ANCHOR_WAIT}초 안에 안 찍힘(gcloud 호출 · 서버 로그 확인)')


def _fire(s, ages=(), refusal=gate_window_refusal):
    """시각을 한 번 더 본 뒤(준비가 길어 창을 넘었으면 blocked) 매칭 created_at 을 **지금 기준으로** 옮기고 chat-gate 를 한 번 부른다."""
    said = refusal(now_seoul())
    if said:
        raise Blocked(said)
    for match_id, delta in ages:
        _set_created(s, match_id, now_seoul() - delta)
    _batch('chat-gate')


def _is_reminder(notice):
    return notice.title == REMINDER_TITLE


def _reminders(s, before):
    seen = {n.key for n in before}
    return [n for n in notify.read_notifications(s.phone.serial) if n.key not in seen and (n.title, n.text) == (REMINDER_TITLE, REMINDER_BODY)]


def _watch(s, before, until, done=lambda got: False):
    """[until] 서울 시각까지(또는 [done] 이 참이 될 때까지) [POLL] 초마다 알림창을 읽어 리마인드를 모은다."""
    while True:
        got = _reminders(s, before)
        if done(got) or now_seoul() >= until:
            return got
        time.sleep(POLL)


def _wait_until(moment):
    while now_seoul() < moment:
        time.sleep(POLL)


def _need_token(s):
    if not _wait_for(lambda: _rows(s.run, f"push_tokens?profile_id=eq.{s.me['id']}&select=token"), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')


def _judge_room(s, said):
    for key, label in SEEN:
        s.check.that(said.get(key) is True, f'{label}({key}) {said.get(key, "?")}(기대 True)')
    if not all(said.get(key) is True for key, _ in SEEN):
        s.check.problems.append(f'그때 보인 화면 {_screens(said)}')


def _silent(s, delta, state=None, only=_is_reminder, refusal=gate_window_refusal):
    """"안 온다" 한 판 — 매칭을 만들어 [delta] 만큼 늙히고 배치 한 번 → 앵커 도장 → [only] 알림 0개 → 대조 message."""
    anchor, match_id = _setup(s, state)
    before = s.before()
    _fire(s, [(match_id, delta)], refusal=refusal)
    _confirm_ran(s, anchor)
    s.silent(before, only=only)


# ── 가설 ────────────────────────────────────────────────────────────────────────────────────────────

@_gate_case()
def push_40(s):
    anchor, match_id = _setup(s)
    before = s.before()
    _fire(s, [(match_id, DUE)])
    if not s.arrives(before, REMINDER_TITLE, REMINDER_BODY, once=True):
        _confirm_ran(s, anchor)  # 안 왔는데 배치가 안 돈 것이면 fail 이 아니라 blocked
    s.notes.append('상대(B) 쪽 알림 1개 · 배치 응답 reminded 2 는 폰이 하나라 못 봄 — 폰 계정 쪽 1개만 확인')


@_gate_case()
def push_41(s):
    def accepted(match_id):
        _patch(s.run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{s.me['id']}", {'trust_response': 'accept'})

    _silent(s, DUE, accepted)
    s.notes.append('상대(B)가 받는 1개 · 배치 응답 reminded 1 은 폰이 하나라 못 봄')


@_gate_case(live=True)
def push_42(s):
    anchor, match_id = _setup(s)
    token = s.run.link(s.me['email'])

    def reminded(said):  # 앱이 홈에서 멈춘 사이 — 뒤로 보내고 배치를 불러 알림이 오면 누른다
        _need_token(s)
        notify.background(s.phone.serial)
        before = s.before()
        _fire(s, [(match_id, DUE)])
        if not s.arrives(before, REMINDER_TITLE, REMINDER_BODY):
            _confirm_ran(s, anchor)
            return {'tapped': False}
        notify.tap_notification(s.phone.serial, REMINDER_TITLE)
        return {'tapped': True}

    said = _app(s.check, s.phone(midway=reminded, token_hash=token, nickname=s.nick))
    if said and not said.get('skipped'):
        _judge_room(s, said)


@_gate_case()
def push_43(s):
    _silent(s, DUE, lambda match_id: factory.switches(s.run, s.me, trust_reminder=False))
    s.notes.append('상대(A)의 1개 · reminded 1 은 폰이 하나라 못 봄(스위치는 폰 계정만 껐다)')


@_gate_case(window=morning_refusal, daytime=False)
def push_44(s):
    anchor, match_id = _setup(s)
    first = now_seoul()
    _set_created(s, match_id, (first - timedelta(days=1)).replace(hour=2, minute=0, second=0, microsecond=0))  # 어제 02:00 → 리마인드는 오늘 08:00
    before = s.before()
    _fire(s, refusal=morning_refusal)  # 07시대 손 호출 한 번
    _confirm_ran(s, anchor)  # 앵커는 07시 호출 뒤에 본다
    s.silent(before, only=_is_reminder)  # 07시대 0개 + 대조
    if s.check.problems:  # 07시대에 왔으면 거기서 끝 — 아침을 한 시간 더 기다릴 이유가 없다
        return
    before = s.before()
    eight = now_seoul().replace(hour=8, minute=0, second=0, microsecond=0)
    got = _watch(s, before, eight + timedelta(minutes=3), done=bool)  # 08:00 예약 실행이 오게 두고 08:03 까지
    if not got:
        _wait_until(eight + timedelta(minutes=6))
        _fire(s, refusal=gate_window_refusal)  # 08:06~08:48 손 호출 — created_at 은 어제 02:00 그대로
        s.notes.append('08:00 예약 실행의 알림이 08:03 까지 안 와 08시대에 손 호출 1번으로 확인')
        got = s.arrives(before, REMINDER_TITLE, REMINDER_BODY)
    s.notes.append(f'08시대 알림 {len(got)}개(예약 실행과 손 호출이 겹치면 2개일 수 있음 — 개수는 판정 사유가 아님) · 상대(B) 쪽은 못 봄')


@_gate_case(window=expired_refusal)
def push_45(s):
    _silent(s, EXPIRED, refusal=expired_refusal)
    s.notes.append('상대(B) 쪽 0개 · reminded 0 은 폰이 하나라 못 봄')


@_gate_case(window=twice_refusal)
def push_46(s):
    anchor, match_id = _setup(s)
    before = s.before()
    _fire(s, [(match_id, DUE_FOR_TWICE)], refusal=twice_refusal)
    if not s.arrives(before, REMINDER_TITLE, REMINDER_BODY):  # 손 호출 1번의 알림
        _confirm_ran(s, anchor)
        return
    next_hour = now_seoul().replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
    count = len(_watch(s, before, next_hour + timedelta(minutes=3), done=lambda got: len(got) >= 3))  # 정각 예약 실행 + 3분
    if count >= 3:
        s.check.that(False, f'같은 시간 안 리마인드가 {count}개 — 손 호출 1번 + 정각 예약 실행 1번이면 2개가 한계')
    elif count == 1:
        raise Blocked('정각 예약 실행의 알림이 안 옴 — 예약 실행이 안 온 것과 한계가 없는 것(알려진 한계 gate.py ponytail 주석)을 가를 수 없음')
    else:
        s.notes.append('알려진 한계 확인 — 같은 시간 안 손 호출 1번 + 정각 예약 실행 1번에 리마인드 2개(gate.py needs_reminder ponytail 주석). 상대(B) 쪽은 못 봄')


@_gate_case()
def push_47(s):
    def partner_left(match_id):  # 나간 쪽은 반드시 상대 — 폰 계정이 나간 쪽이면 관측할 수 없다
        _patch(s.run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{s.partner['id']}", {'left_at': _iso(now_seoul())})

    _silent(s, DUE, partner_left)
    s.notes.append('나간 사람은 상대(B) — 폰 계정 쪽 0개만 확인')


@_gate_case()
def push_48(s):
    anchor, match_id = _setup(s)
    before = s.before()
    _fire(s, [(match_id, CLOSED)])
    _confirm_ran(s, anchor, also=lambda: _stamps(s, match_id).get('chat_closed_at'))
    _wait_for(lambda: _stamps(s, match_id).get('chat_closed_at'), SETTLE)  # 배치가 앵커를 먼저 찍고 이 매칭을 몇 초 뒤 닫을 수 있다 — 기다린 뒤에야 안 닫혔다고 본다
    s.check.that(_stamps(s, match_id).get('chat_closed_at'), '49시간 지난 매칭에 chat_closed_at 이 안 찍힘(앵커 도장은 찍혀 배치는 돌았음)')
    s.silent(before)  # 새 알림 전부 0개 + 대조


@_gate_case()
def push_79(s):
    anchor, match_id = _setup(s)
    before = s.before()
    notify.kill_app(s.phone.serial)
    _fire(s, [(match_id, DUE)])
    if not s.arrives(before, REMINDER_TITLE, REMINDER_BODY):
        _confirm_ran(s, anchor)
        return
    # 누르기 전에 일감을 넣는다 — 알림으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 이것을 가져간다
    s.phone.hub.tell({'case': s.phone.case, 'phase': 'tap', 'nickname': s.nick})
    notify.tap_notification(s.phone.serial, REMINDER_TITLE)
    said = _app(s.check, s.phone.hub.result(APP_WAIT))
    if said:
        _judge_room(s, said)
        s.notes.append(f"앱이 방을 연 데 {said.get('room_ms', '?')}ms(일감을 받은 뒤 · 앱 부팅 포함, 시나리오 10초) · 상대(B) 쪽 알림과 방은 폰이 하나라 못 봄")


@_gate_case(live=True)
def push_80(s):
    anchor, match_id = _setup(s)
    token = s.run.link(s.me['email'])

    def reminded(said):  # 앱이 대화 목록을 앞에 두고 멈춘 사이
        _need_token(s)
        before = s.before()
        _fire(s, [(match_id, DUE)])
        _confirm_ran(s, anchor)
        s.silent(before, only=_is_reminder, control=None)  # 앞에서는 배너가 없다
        notify.background(s.phone.serial)
        s.control('message')  # 뒤로 간 폰에는 오는 알림 — 읽는 길이 살아 있다는 증거
        _front(s.phone.serial)

    said = _app(s.check, s.phone(midway=reminded, token_hash=token, nickname=s.nick))
    if said:
        s.check.that(said.get('list') is True, f"대화 목록 화면이 사라짐 — 그때 보인 화면 {_screens(said)}")
        s.check.that(said.get('row') is True, f'대화 목록에서 {s.nick} 줄이 사라짐')
    s.notes.append('앞에서는 배너가 없다는 것만 확인 — 서버 발송 여부(reminded 에 폰 계정 포함)는 응답을 못 읽음 · 앵커로 배치가 돈 것까지만')


PHONE = {'E-PUSH-40': push_40, 'E-PUSH-41': push_41, 'E-PUSH-42': push_42, 'E-PUSH-43': push_43, 'E-PUSH-44': push_44, 'E-PUSH-45': push_45,
         'E-PUSH-46': push_46, 'E-PUSH-47': push_47, 'E-PUSH-48': push_48, 'E-PUSH-79': push_79, 'E-PUSH-80': push_80}

tools.CASE_LIMITS.update({case: CASE_LIMIT_SLOW for case in PHONE})
tools.CASE_LIMITS.update({'E-PUSH-44': CASE_LIMIT_HOUR, 'E-PUSH-46': CASE_LIMIT_HOUR})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-gate'] = list(PHONE)
