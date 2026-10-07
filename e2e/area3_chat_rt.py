"""영역 3 실시간 · 화면 10개(묶음 area3-chat-rt = 폰 한 대 8개, area3-chat-rt-two = 폰 + 에뮬 2개) — E-CHAT-01 · 02 · 03 · 07 · 22 · 23 · 24 · 58 · 61 · 72.
앱 쪽은 frontend/integration_test/area3_chat_rt.dart 의 같은 번호(두 기기는 `번호/A` · `번호/B`). 기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 그 줄이다.
가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`(두 기기는 `(run, two)` — e2e/twodev.py). PC 가 계정 · 매칭을 만들고 상대(A)의 보내기 · 나가기 · 수락은 API 로 하며,
앱은 화면(방 뷰모델 · 위젯)에서 본 것을 말하고 판정은 여기서 한다. 배치(chat-gate · daily-cards · cleanup)는 부르지 않는다. 알림 가설은 아니라 낮 관문(require_daytime)은 두지 않는다 — 글 보내기 · 수락은 서버가 푸시(_notify_message)를 일으키지만 new_message 는 야간 보류 예외(cards/push.py _QUIET_HOURS_EXEMPT)이고,
보류는 푸시만 막을 뿐 DB 와 화면 판정은 그대로다.

방식 — (가) 단일 폰: 폰 계정이 받는 쪽, 상대는 PC 가 API 로 맡는다. (나) 두 기기: 두 화면을 다 봐야 하는 둘만.
  E-CHAT-01 · 02 · 07 · 22 · 23 · 24 · 61 · 72  (가)
  E-CHAT-03  (나) — "두 화면의 줄 순서가 같다" 는 두 앱이 서로 보낸 글이 두 화면에 합쳐진 순서라 한 화면과 API 로는 못 본다(앱이 직접 보내는 글이 구독과 응답 두 길로 돌아오는 합치기까지 본다).
  E-CHAT-58  (나) — A 화면은 "⋯ → 채팅방 나가기 → 나가기" 를 실제로 눌러 목록으로 가는 것을, B 화면은 나감 줄이 2초 안에 뜨는 것을 본다. 둘 다 화면이 필요하다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-CHAT-01 · 02  "A 폰 + B 에뮬" 이 아니라 폰 한 대가 받는 쪽이다. 01 은 폰 계정이 B(matches 의 큰 id, profile_b), 02 는 A(작은 id, profile_a) — 보내는 쪽은 PC 가 API 로
                  3초 간격(첫 보내기 시각에서 칸을 맞춘다)으로 20번. "B 화면에 글자가 나타난 시각" 은 앱이 방 뷰모델에서 그 글을 처음 가진 앱 시계(UTC)이고, "A 가 보내기를 누른 시각" 은
                  서버가 찍은 messages.created_at 이라 폰 시계와 서버 시계의 차(시계 차)가 섞인다 — 음수는 판정에서 빼고 메모에 남긴다(E-CHAT-10 · 67 과 같은 규칙).
                  메모 표 = 글마다 `순번:초`, 최대 · 평균 · 95번째(올림 순위).
  E-CHAT-03  "A · B 가 0.5초 간격으로 번갈아" — 두 앱이 PC 가 함께 놓아 준 뒤 각자 1.0초 간격으로 입력칸에 쓰고 보내기를 눌러 보낸다(B 는 0.5초 늦게 시작). 기기마다 누르는 시간이
                  조금 어긋나 정확한 0.5초 엇갈림은 아니다 — 판정은 DB `(created_at, id)` 순서와 두 화면 순서의 일치이고, 줄마다 2.0초는 상대 기기가 그 글을 처음 본 앱 시계와 서버 시각의 차(음수는 뺀다).
  E-CHAT-07  "당겨서 새로고침" — 먼저 손가락 끌기(fling)를 하고 6초 안에 안 갱신되면 같은 새로고침 표시기를 직접 띄운다(E-SAFE-50 과 같은 길). 어느 쪽인지 메모에 `당기기`로 남긴다.
  E-CHAT-22 · 24 · 72  망은 `svc wifi/data` 가 아니라 비행기 모드(notify.airplane)로 끊는다(E-CHAT-25 와 같은 길 — 폰 USB 우편함은 안 끊긴다). 72 는 끊기 → 3건 → 5초 → 켜기 순서이고
                  켜는 쪽 기다림(settle)을 0 으로 해 "켠 뒤 10초" 를 켠 직후부터 센다.
  E-CHAT-23  HOME 은 notify.background, 돌아오기는 monkey LAUNCHER(area4_push_a4._front — 떠 있는 앱은 그대로 앞으로 온다). 시나리오는 걸린 시간만 "기록" 이라 하므로 숫자 판정은 없고,
                  돌아온 뒤 10초(RESUME_LIMIT)는 하네스 상한이다. 배경에 있는 동안 실시간으로 이미 온 글은 "돌아오기 전 도착" 으로 메모에 적는다.
  E-CHAT-24  두 판(left = A 나가기, passed = 둘 다 수락)을 앱을 두 번 켜서 돈다. 둘 다 수락의 B 수락도 PC 가 B 토큰으로 한다(B 폰은 그때 망이 없다 — PC 망은 산다).
                  배너가 안 떠 "다시 시도" 를 못 누르면 눌렀다고 치지 않고 자동 재연결 뒤의 화면으로 판정하며 메모에 남긴다.
  E-CHAT-58  "A: 대화 목록으로 이동 · 방 없음" 은 폰(A) 화면 + A 토큰으로 읽은 GET /chat/conversations 둘 다 본다.
  E-CHAT-61  시나리오는 "코드상 예상 실패(머리말을 다시 읽지 않아 입력창이 남음)" 라 했지만 지금 코드(chat_room_view_model.dart `_receive` — 나감 줄이 오면 머리말을 다시 읽는다, 결함 A12)는
              그 결함을 고쳐 둔 것으로 보인다. 기대값(나감 줄 뜬 뒤 2초 안에 입력창 → 안내 한 줄)을 그대로 판정하고, 어기면 fail 이다(하네스가 결함을 잡는 것). 입력창이 남으면 시나리오대로
              1건 보내 보고 화면 오류 문구를 메모에 남긴다.
"""

import math
import secrets
import time

from e2e import area1, area2, area3, area4, notify, tools, twodev
from e2e.area1 import Check, _api, _app, _rows
from e2e.area3 import _match, _send
from e2e.area3_phone import MISSING, _left_line, _permitted, _person
from e2e.area3_phone2 import _sent
from e2e.area2_two_accept import _after, _verdict
from e2e.area3_phone5 import LIVE_LIMIT, _at
from e2e.area4_push_a4 import _front as bring_front
from e2e.tools import Blocked

STREAM = 20  # E-CHAT-01 · 02 — 시나리오 "3초 간격으로 20번"
GAP = 3.0
OFFLINE_LINES = 5  # E-CHAT-22 — 끊긴 동안 5건
MISSED_LINES = 3  # E-CHAT-72 · 23 — 3건
CUT_SECONDS = 5  # E-CHAT-72 — 5초만 끊는다
RETURN_WAIT = 10  # E-CHAT-72 — "다시 켠 뒤 10초 안에"
RESUME_LIMIT = 10  # E-CHAT-23 — 하네스 상한(시나리오는 걸린 시간을 기록만 한다)
BG_SETTLE, BG_STAY = 2, 4  # E-CHAT-23 — HOME 뒤 앱이 배경에 들어가기까지 · 3건을 보낸 뒤 배경에 더 머무는 초
BANNER_WAIT, RETRY_WAIT = 60, 20  # 앱이 끊김 배너를 기다리는 · "다시 시도" 뒤 글이 찾아오기를 기다리는 상한(초)
VARIANTS = ('left', 'passed')  # E-CHAT-24 — 두 판
ALT = 20  # E-CHAT-03 — 한쪽이 보내는 글(두 기기 모두 40건)
ALT_GAP = 1.0  # 한 기기가 보내는 칸(초) — B 는 그 절반(0.5초) 늦게 시작해 두 기기가 0.5초 간격으로 엇갈린다
PEER = 240  # 두 기기가 서로 ready 를 기다리는 상한(초) — 에뮬이 늦게 떠도 넉넉히
LIMITS = {'side_timeout': {'A': 300, 'B': 300}, 'deadline': 600}  # twodev.two — 다음 말까지 기다리는 시간 · 전체 상한
PREP = 300  # 계정 둘 준비의 넉넉한 최악(초) — 계정 하나 150(가입 · 온보딩 · 로그인 429 대기 재시도까지, area5_two.PREP_ACCOUNT)
APP_OPEN = 90  # 앱 켜기 · 로그인 · 방 열기 · 방 읽기(15초) 의 넉넉한 최악
SEND_WORST = 10  # 보내기 한 건(서버가 푸시까지 하고 응답)의 최악
TAIL = 30  # 앱이 끝 글을 기다리는 10초 + 말풍선 · 결과 우편함 · 여유
STREAM_TIME = (STREAM - 1) * GAP + SEND_WORST  # 칸은 첫 보내기에서 세므로 보내기가 밀려도 마지막 글은 57초 + 보내기 한 건
PHONE_LIMITS = {  # 가설마다 줄 초 — 기본 420 은 계정 둘 준비(300) + 앱 켜기(90)만으로 거의 찬다
    'E-CHAT-01': PREP + APP_OPEN + STREAM_TIME + TAIL,
    'E-CHAT-02': PREP + APP_OPEN + STREAM_TIME + TAIL,
    'E-CHAT-07': PREP + APP_OPEN + 60 + 3 * SEND_WORST,  # PC 의 3건 보내기 최악 30 + 끌기 6 + 직접 새로고침 10 + 방 들어갔다 나오기 · 읽음 반영 40 안팎
    'E-CHAT-22': PREP + APP_OPEN + BANNER_WAIT + OFFLINE_LINES * SEND_WORST + notify.SETTLE_SECONDS + RETRY_WAIT + TAIL,
    'E-CHAT-23': PREP + APP_OPEN + BG_SETTLE + MISSED_LINES * SEND_WORST + BG_STAY + 15 + TAIL,
    'E-CHAT-24': len(VARIANTS) * (PREP + APP_OPEN + BANNER_WAIT + 2 * SEND_WORST + notify.SETTLE_SECONDS + RETRY_WAIT + TAIL),  # 판마다 계정 · 앱을 새로
    'E-CHAT-61': PREP + APP_OPEN + 15 + 8 + 3 + TAIL,  # 나감 줄 15 + 안내로 바뀜 8 + 보내 보기 3
    'E-CHAT-72': PREP + APP_OPEN + MISSED_LINES * SEND_WORST + CUT_SECONDS + RETURN_WAIT + TAIL,
}
TWO_LIMIT = LIMITS['deadline'] + 2 * 150  # 두 기기 — deadline 앞에 계정 둘 준비(계정 하나 150)가 더해진다
tools.CASE_LIMITS.update(PHONE_LIMITS)
tools.CASE_LIMITS.update({'E-CHAT-03': TWO_LIMIT, 'E-CHAT-58': TWO_LIMIT})


# ── 판정 도우미 ──────────────────────────────────────────────────────────────────────────────────────

def _bodies(tag, count):
    """이번 가설의 글 본문 — `E2E-<번호>-<순번>-<난수>` 로 매번 다르게."""
    mark = secrets.token_hex(2)
    return [f'E2E-{tag}-{i:02d}-{mark}' for i in range(1, count + 1)]


def _pair9(run, phone_is_a):
    """(폰 계정, 토큰, 상대, 매칭 id). matches 는 profile_a < profile_b 로만 저장되므로(area3._match) 작은 id 가 A — 폰이 A 인지 B 인지에 맞게 둘 중 고른다."""
    first, second = sorted((_person(run), _person(run)), key=lambda p: p['id'])
    me, partner = (first, second) if phone_is_a else (second, first)
    return me, run.link(me['email']), partner, _match(run, me, partner)


def _loaded(said):
    """앱이 방 읽기를 못 끝냈으면(구독 전에 보내면 가짜 실패) 글을 보내기 전에 멈춘다 — 실제 앱은 이때 step 을 부르지 않는다."""
    if said and said.get('loaded') is False:
        raise Blocked(f"방이 안 읽힘(loaded False · 오류 {said.get('error')!r}) — 글을 보내지 않았다. 로그인 · 방 확인")


def _stats(values):
    """(최대, 평균, 95번째) — 95번째는 올림 순위(20건이면 19번째로 큰 값)."""
    ordered = sorted(values)
    return ordered[-1], sum(ordered) / len(ordered), ordered[math.ceil(0.95 * len(ordered)) - 1]


def _missing(check, bodies, seen, label):
    """앱이 한 번도 못 본 글(뷰모델에 안 뜸)의 순번."""
    gone = [n for n, body in enumerate(bodies, start=1) if body not in (seen or {})]
    check.that(not gone, f'{label}: {" ".join(f"{n}번" for n in gone)} 글이 화면(뷰모델)에 안 뜸')


BUSY_WINDOW = 3.0  # 느린 글이 보이기 직전 이만큼(초) 안에 받는 기기도 자기 글을 보냈는지


def _busy_note(shown, busy):
    """느린 글이 [shown] 에 보이기 직전 [BUSY_WINDOW]초 안에 받는 기기가 자기 글을 보냈는지(앱 시계 [busy] 목록) — 원인 가설(받는 기기의 자기 보내기 부하)을 가르는 증거 문구.
    목록이 없거나 비었으면(옛 앱) 빈 문자열 — 판정은 건드리지 않는다."""
    times = [t for t in map(_at, busy or []) if t]
    if not times:
        return ''
    gaps = [(shown - t).total_seconds() for t in times if 0 <= (shown - t).total_seconds() <= BUSY_WINDOW]
    if gaps:
        return f' (그 글이 보이기 직전 {min(gaps):.1f}초 안에 받는 기기도 자기 글을 보냄)'
    return f' (그 글이 보이기 직전 {BUSY_WINDOW:.0f}초 안에 받는 기기의 보내기는 없었음)'


def _delays(check, run, match_id, bodies, seen, label, kind='text', busy=None):
    """글마다 (앱이 처음 본 시각 − 서버가 찍은 시각)을 재 판정하고 메모(표)를 돌려준다. 못 읽는 시각 · 2.0초 넘는 글은 problems.
    음수(앱 시계가 서버보다 느림)는 판정에서 빼고 메모에 센다 — 폰 시계가 느려 N초 늦은 표시도 가려질 수 있어서다.
    판정 가능한 글이 절반 미만이면 Blocked(다른 problems 가 이미 있으면 그 fail 이 먼저다).
    [busy] 는 받는 기기가 자기 글을 보내던 때(앱이 말한 `sent_at`) — 2.0초를 넘은 글의 fail 문구에 "그때 받는 기기도 보내는 중이었나" 만 덧붙인다(판정은 그대로)."""
    _missing(check, bodies, seen, label)
    rows = _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.{kind}&select=body,created_at')
    made = {r['body']: _at(r.get('created_at')) for r in rows}
    values, negative, table = [], [], []
    for number, body in enumerate(bodies, start=1):
        if body not in (seen or {}):
            continue
        shown, created = _at(seen[body]), made.get(body)
        if not (shown and created):
            check.problems.append(f'{label}: {number}번 글의 보낸 시각 또는 앱이 본 시각을 못 읽음')
            continue
        delay = (shown - created).total_seconds()
        if delay < 0:
            negative.append(number)
            continue
        values.append(delay)
        table.append(f'{number}:{delay:.2f}')
        if delay > LIVE_LIMIT:
            check.problems.append(f'{label}: {number}번 글이 {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})' + _busy_note(shown, busy))
    if len(values) * 2 < len(bodies) and not check.problems:  # 판정할 수 있는 글이 절반 미만이면 "2초 안" 도 "2초 넘음" 도 말할 수 없다
        raise Blocked(f'{label}: 시계 차로 판정 불가 — 판정 가능 {len(values)}건 / {len(bodies)}건(음수 {len(negative)}건: 앱이 본 시각이 서버가 찍은 시각보다 앞섬 — 폰 시계 확인)')
    note = []
    if values:
        top, mean, p95 = _stats(values)
        note.append(f'{len(values)}건 최대 {top:.2f}초 · 평균 {mean:.2f}초 · 95번째 {p95:.2f}초 [{" ".join(table)}]')
    else:
        note.append('지연 판정 불가 — 시계 차로 전부 음수이거나 읽을 시각이 없음')
    if negative:
        note.append(f'음수 {len(negative)}건({" ".join(map(str, negative))}번) — 앱이 본 시각이 서버가 찍은 시각보다 앞섬(폰 시계 차), 판정에서 뺌')
    return ' · '.join(note)


def _db_order(run, match_id, bodies, kind='text'):
    """DB `(created_at, id)` 순서로 센 [bodies] — 화면 순서의 기준(chat/repository.py 의 커서와 같다)."""
    rows = _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.{kind}&select=id,body,created_at')
    wanted = set(bodies)
    return [r['body'] for r in sorted((r for r in rows if r['body'] in wanted), key=lambda r: (_at(r.get('created_at')), r.get('id', '')))]


def _diff(got, want):
    """두 목록이 처음 갈리는 자리 — 메모가 글 40줄이 되지 않게."""
    got = got if isinstance(got, list) else [got]
    at = next((i for i, (a, b) in enumerate(zip(got, want)) if a != b), min(len(got), len(want)))
    return f'{at + 1}번째부터 다름 · 앱 {len(got)}줄 · DB {len(want)}줄'


def _lines(check, run, match_id, bodies, said, label):
    """DB 에 [bodies] 가 한 줄씩 있고, 화면 순서가 DB 순서이며(겹침 없음), 마지막 글 말풍선이 그려졌다. DB 순서를 돌려준다."""
    ordered = _db_order(run, match_id, bodies)
    check.that(sorted(ordered) == sorted(bodies), f'DB 글 {len(ordered)}행(기대 {len(bodies)}행 · 본문 그대로)')
    check.that(said.get('order') == ordered, f"{label}: 순서가 DB 순서와 다름({_diff(said.get('order', MISSING), ordered)})")
    check.that(said.get('bubble_last') is True, f"{label}: 마지막 글 말풍선 {said.get('bubble_last', MISSING)}(기대 True)")
    return ordered


def _send_all(run, sender, match_id, bodies, sent):
    """[bodies] 를 차례로 보낸다(칸 없이) — 답은 [sent] 에 쌓는다."""
    for body in bodies:
        sent.append(_send(run, sender, match_id, body, retry=False))


def _check_sent(check, sent, count, label='A 보내기'):
    bad = [(i, r[0]) for i, r in enumerate(sent, start=1) if r[0] != 201]
    check.that(len(sent) == count and not bad, f'{label} {len(sent)}건 · 실패 {bad}(기대 {count}건 전부 201)')


# ── E-CHAT-01 · 02 ───────────────────────────────────────────────────────────────────────────────────

def _stream(run, sender, match_id, bodies, sent):
    """[bodies] 를 [GAP]초 칸으로 보낸다 — 칸은 첫 보내기 시각에서 센다(보내기가 느려도 칸이 밀리지 않는다)."""
    started = time.monotonic()
    for i, body in enumerate(bodies):
        time.sleep(max(0.0, started + i * GAP - time.monotonic()))
        sent.append(_send(run, sender, match_id, body, retry=False))


def _live(tag, phone_is_a):
    """폰 계정이 방을 연 채 멈춘 사이 상대가 3초 간격으로 20건 보낸다 → 글마다 ≤ 2.0초(최대 · 평균 · 95번째를 메모 표로)."""
    def case(run, phone):
        check = Check()
        me, token, partner, match_id = _pair9(run, phone_is_a)
        bodies, sent = _bodies(tag, STREAM), []
        said = _app(check, phone(midway=lambda said: _stream(run, partner, match_id, bodies, sent), token_hash=token,
                                 nickname=partner['nickname'], bodies=bodies))
        _loaded(said)
        _check_sent(check, sent, STREAM)
        note = ''
        if said:
            check.that(said.get('loaded') is True, f"앱이 방 읽기를 끝냈다고 안 말함 {said.get('loaded', MISSING)}(기대 True)")
            _lines(check, run, match_id, bodies, said, 'B 화면')
            note = _delays(check, run, match_id, bodies, said.get('seen'), 'B 화면')
            if check.problems:
                check.problems.append(f'[{note}]')  # 어긋났어도 글마다 걸린 시간 표는 남긴다
        return check.result(note)
    return case


# ── E-CHAT-07 ────────────────────────────────────────────────────────────────────────────────────────

def p_chat_07(run, phone):
    """폰 계정(B)이 대화 목록을 연 채 멈춘 사이 A 가 3건 → 새로고침 → 목록 뱃지 3 · 아래 탭 뱃지 3 → 방에 들어갔다 나오면 둘 다 없음."""
    check = Check()
    me, token, partner, match_id = _pair9(run, phone_is_a=False)
    bodies, sent = _bodies('07', 3), []
    said = _app(check, phone(midway=lambda said: _send_all(run, partner, match_id, bodies, sent), token_hash=token, nickname=partner['nickname']))
    for i, reply in enumerate(sent, start=1):
        check.reply(f'A 보내기 {i}', reply, 201)
    check.that(len(sent) == 3, f'A 보내기 {len(sent)}건(기대 3건)')
    note = ''
    if said:
        for when, label, want in (('before', '들어가기 전', {'row': '3', 'nav': '3'}), ('after', '방에서 나온 뒤', {'row': None, 'nav': None})):
            got = said.get(when, MISSING)
            shown = {key: got.get(key, MISSING) for key in want} if isinstance(got, dict) else got
            check.that(shown == want, f'{label} 목록 뱃지 · 아래 탭 뱃지 {shown}(기대 {want})')
        note = '당기기: ' + ('손가락 끌기' if said.get('pulled') == 'drag'
                           else 'RefreshIndicatorState.show() — 손가락 끌기로는 안 새로고침(목록이 짧으면 스크롤이 안 돼 당겨지지 않을 수 있음)')
    return check.result(note)


# ── 망을 끊는 가설 · 앱을 HOME 으로 ──────────────────────────────────────────────────────────────────

def p_chat_22(run, phone):
    """B 방을 열어 둔 채 망 끔 → A 5건 → 망 켬 → 배너 "연결이 끊겼어요" 가 있고 "다시 시도" 뒤 5건이 모두 · DB 순서로 · 겹침 없이."""
    check = Check()
    me, token, partner, match_id = _pair9(run, phone_is_a=False)
    bodies, sent = _bodies('22', OFFLINE_LINES), []

    def deliver(said):  # 끊긴 채 앱이 배너를 띄운 뒤 — PC 망은 산다
        _send_all(run, partner, match_id, bodies, sent)
        notify.airplane(phone.serial, False)

    said = area4._offline(phone, check, area4._cut(phone), deliver, token_hash=token, nickname=partner['nickname'], bodies=bodies)
    _loaded(said)
    _check_sent(check, sent, OFFLINE_LINES)
    note = ''
    if said:
        check.that(said.get('banner') is True, f"배너 \"연결이 끊겼어요\" {said.get('banner', MISSING)}(기대 True)")
        _missing(check, bodies, said.get('seen'), 'B 화면')
        _lines(check, run, match_id, bodies, said, 'B 화면')
        note = f"끊김 배너까지 {said.get('banner_seconds', MISSING)}초 · \"다시 시도\" 눌림 {said.get('retried', MISSING)}"
    return check.result(note)


def p_chat_72(run, phone):
    """B 방을 열어 둔 채 망을 5초만 끊고 그 사이 A 3건 → 켠 뒤 10초 안에 (배너) 또는 (3건 모두 표시) 중 하나.
    시나리오 원문: "놓친 메시지가 사라지지 않는다 — 배너가 뜨거나, 안 뜨면 저절로 채워져야 한다". 그래서 10초가 끝났을 때 배너가 아직 떠 있으면 사용자가 "다시 시도" 로 찾을 수 있어 통과이고,
    배너가 한 번 켜졌다 꺼졌다면 통로가 다시 붙어 다시 읽었다는 뜻이라 3건이 있어야 통과다(없으면 놓친 글이 사라진 것 → fail)."""
    check = Check()
    me, token, partner, match_id = _pair9(run, phone_is_a=False)
    bodies, sent = _bodies('72', MISSED_LINES), []

    def blink(said):  # 끊기 → 3건 → 끊은 지 5초가 되도록 → 켜기(기다림 없이 — "켠 뒤 10초" 를 켠 직후부터 센다)
        notify.airplane(phone.serial, True)
        started = time.monotonic()
        _send_all(run, partner, match_id, bodies, sent)
        time.sleep(max(0.0, CUT_SECONDS - (time.monotonic() - started)))
        notify.airplane(phone.serial, False, settle=0)

    said = area4._offline(phone, check, blink, token_hash=token, nickname=partner['nickname'], bodies=bodies)
    _loaded(said)
    _check_sent(check, sent, MISSED_LINES)
    note = ''
    if said:
        banner, shown = said.get('banner') is True, said.get('shown', MISSING)  # banner = 끝 시각에 배너가 아직 떠 있다
        was = said.get('banner_was') is True  # 배너가 한 번이라도 켜졌다
        refilled = shown == MISSED_LINES
        if refilled:
            ordered = _db_order(run, match_id, bodies)
            check.that(said.get('order') == ordered, f"B 화면: 순서가 DB 순서와 다름({_diff(said.get('order', MISSING), ordered)})")
            refilled = said.get('order') == ordered
        if was and not banner and not refilled:
            check.problems.append(f'배너가 켜졌다 꺼졌는데 {MISSED_LINES}건이 안 채워짐(표시 {shown}건) — 통로가 다시 붙어 다시 읽었다는 뜻인데 놓친 글이 사라졌다')
        check.that(banner or refilled or was, f'다시 켠 {RETURN_WAIT}초 안에 배너도 안 뜨고 {MISSED_LINES}건도 안 채워짐(배너 {banner} · 표시 {shown}건) — '
                                       '실시간 통로가 오류 없이 다시 붙으면 앱이 다시 읽지 않는 구조(확인 필요 — message_stream.dart:48-55 · chat_room_view_model.dart:129-151)')
        note = f"{'배너 표시' if banner else '배너 없음'} · {'3건 모두 표시' if refilled else '3건 안 채워짐'} · 켠 뒤 {said.get('seconds', MISSING)}초"
    return check.result(note)


def p_chat_23(run, phone):
    """B 방을 열어 둔 채 HOME → A 3건 → 앱을 다시 앞으로 → 누르는 것 없이 3건이 모두 표시(걸린 시간은 기록)."""
    check = Check()
    me, token, partner, match_id = _pair9(run, phone_is_a=False)
    bodies, sent = _bodies('23', MISSED_LINES), []

    def away(said):
        notify.background(phone.serial)
        time.sleep(BG_SETTLE)
        _send_all(run, partner, match_id, bodies, sent)
        time.sleep(BG_STAY)
        bring_front(phone.serial)

    said = _app(check, phone(midway=away, token_hash=token, nickname=partner['nickname'], bodies=bodies))
    _loaded(said)
    _check_sent(check, sent, MISSED_LINES)
    note = ''
    if said:
        if said.get('paused') is not True:  # HOME 이 안 먹어 앱이 배경에 안 갔으면 "돌아온 뒤 저절로 붙는다" 를 본 것이 아니다
            raise Blocked(f"배경 진입 안 됨(paused {said.get('paused', MISSING)}) — HOME 키 뒤에도 앱이 배경으로 안 갔다. 글 {len(sent)}건은 이미 보냈다")
        _missing(check, bodies, said.get('seen'), 'B 화면')
        _lines(check, run, match_id, bodies, said, 'B 화면')
        resumed = _at(said.get('resumed_at'))
        if resumed is None:
            note = f"앱이 돌아옴(onResume)을 못 봄 — 걸린 시간은 앱이 앞으로 온 뒤 잰 값 {said.get('waited_ms', MISSING)}ms"
        else:
            lates = [(_at(t) - resumed).total_seconds() for t in (said.get('seen') or {}).values() if _at(t)]
            early, after = [d for d in lates if d < 0], [d for d in lates if d >= 0]
            if after:
                check.that(max(after) <= RESUME_LIMIT, f'돌아온 뒤 {max(after):.1f}초 뒤에야 다 표시(하네스 상한 {RESUME_LIMIT}초)')
            note = (f'돌아온 뒤 최대 {max(after, default=0):.2f}초(기록 — 시나리오는 숫자 기준 없음, 하네스 상한 {RESUME_LIMIT}초)'
                    + (f' · 배경에 있는 동안 이미 도착 {len(early)}건' if early else ''))
    return check.result(note)


# ── E-CHAT-24 ────────────────────────────────────────────────────────────────────────────────────────

def p_chat_24(run, phone):
    """판 둘 — left(끊긴 동안 A 나가기 → 입력창 자리에 안내 한 줄), passed(끊긴 동안 둘 다 수락 → "신뢰 확인 완료" 카드 + 상대 카카오톡 아이디). 판마다 계정 · 앱을 새로."""
    check = Check()
    notes = []
    rooms = {variant: _pair9(run, phone_is_a=False) for variant in VARIANTS}  # 두 판 계정을 먼저 — 아이디가 없으면 첫 앱을 켜기 전에 막는다
    kakao = area4._kakao(run, rooms['passed'][2]['id'])
    if not kakao:
        raise Blocked('상대 profile_private.kakao_id 가 비어 있음 — 카드에 보일 아이디가 없다(앱은 켜지 않았다)')
    for variant in VARIANTS:
        part = Check()
        me, token, partner, match_id = rooms[variant]
        job = {'token_hash': token, 'nickname': partner['nickname'], 'variant': variant}
        if variant == 'passed':
            job['kakao'] = kakao

        def changed(said, variant=variant, part=part, match_id=match_id, me=me, partner=partner):
            if variant == 'left':
                part.reply('A 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', partner['token']), 200)
            else:
                part.reply('A 수락', _api(run, 'POST', f'/chat/matches/{match_id}/trust', partner['token']), 200)
                part.reply('B 수락', _api(run, 'POST', f'/chat/matches/{match_id}/trust', me['token']), 200)
            notify.airplane(phone.serial, False)

        said = area4._offline(phone, part, area4._cut(phone), changed, **job)
        _loaded(said)
        if said:
            want = {'left': {'input': False, 'notice': True}, 'passed': {'input': True, 'card': True, 'kakao': True}}[variant]
            for key, value in want.items():
                part.that(said.get(key) is value, f'{key} {said.get(key, MISSING)}(기대 {value})')
            if said.get('banner') is not True:
                notes.append(f'{variant}: 끊긴 동안 배너가 안 떠 "다시 시도" 를 못 눌렀다 — 자동 재연결 뒤의 화면으로 판정')
        if variant == 'left':
            gone = _rows(run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{partner['id']}&select=left_at")
            part.that(bool(gone) and gone[0].get('left_at') is not None, f'A 의 left_at {gone}(기대 찍힘)')
        else:
            row = _rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at')
            part.that(bool(row) and row[0].get('trust_passed_at') is not None, f'trust_passed_at {row}(기대 찍힘)')
        check.problems += [f'{variant}: {p}' for p in part.problems]
    return check.result('; '.join(notes))


# ── E-CHAT-61 ────────────────────────────────────────────────────────────────────────────────────────

def p_chat_61(run, phone):
    """B 가 방을 열어 둔 채 A 가 나간다 → 나감 줄이 뜬 뒤 2초 안에 입력창이 안내 한 줄로 바뀐다. 시나리오는 "코드상 예상 실패" 라 했지만 기대값 그대로 판정한다(모듈 머리말)."""
    check = Check()
    me, token, partner, match_id = _pair9(run, phone_is_a=False)
    left = []
    said = _app(check, phone(midway=lambda said: left.append(_api(run, 'POST', f'/chat/matches/{match_id}/leave', partner['token'])),
                             token_hash=token, nickname=partner['nickname'], line=_left_line(partner), text='E2E-61'))
    _loaded(said)
    check.reply('A 나가기', left[0] if left else (0, '앱이 멈추기 전에 끝남'), 200)
    note = ''
    if said:
        if said.get('line') is not True:
            check.problems.append(f"나감 줄이 안 뜸(line {said.get('line', MISSING)}) — 줄이 안 뜨면 입력창이 바뀌는지는 못 본다")
        else:
            ms = said.get('switched_ms')
            if ms is None:
                check.problems.append(f"나감 줄이 뜬 뒤에도 입력창이 안내로 안 바뀜(입력창 {said.get('input', MISSING)} · 안내 {said.get('notice', MISSING)}) — "
                                      f"보내기를 시도하면 오류 문구 {said.get('send_error', MISSING)!r}")
            else:
                check.that(ms <= LIVE_LIMIT * 1000, f'입력창이 안내로 바뀐 때 나감 줄이 뜬 뒤 {ms / 1000:.1f}초(기대 ≤ {LIVE_LIMIT})')
                check.that(said.get('input') is False, f"입력창 {said.get('input', MISSING)}(기대 없음)")
                check.that(said.get('notice') is True, f"나감 안내 {said.get('notice', MISSING)}(기대 있음)")
                note = f'안내로 바뀐 때 나감 줄이 뜬 뒤 {ms / 1000:.2f}초'
        stored = _sent(run, me, match_id)
        check.that(not stored, f'나간 방에 폰 계정의 글이 저장됨 {stored}(기대 없음 — 서버가 막아야 한다)')
    return check.result(note)


# ── 두 기기(폰 A + 에뮬 B) ───────────────────────────────────────────────────────────────────────────

def _ab(run):
    """(A 폰, B 에뮬) — matches 는 profile_a < profile_b 로 저장되므로 작은 id 가 A. 두 기기 가설은 늘 A=폰 · B=에뮬."""
    a, b = sorted((_person(run), _person(run)), key=lambda p: p['id'])
    return a, b


def _ready(me, other):
    """이 쪽 앱이 방을 열었다고 말한 뒤 — 상대도 열 때까지 기다렸다가 둘이 함께 풀린다(그래야 번갈아 보내기 · 나가기가 같은 때 시작한다)."""
    def handler(said, sync):
        sync.set(f'{me}-ready')
        _after(sync, f'{other}-ready', other.upper(), PEER)
    return handler


def _keep(got, who):
    """앱이 step 에 실어 보낸 값을 판정 때까지 둔다."""
    def handler(said, sync):
        got[who] = said
    return handler


def two_03(run, two):
    """A · B 가 번갈아 20건씩(모두 40건) → 두 화면의 순서 = DB `(created_at, id)` 순서, 40줄 모두 있음, 같은 줄 0건, 상대 기기에서 줄마다 ≤ 2.0초."""
    check = Check()
    a, b = _ab(run)
    match_id = _match(run, a, b)
    mark = secrets.token_hex(2)
    a_lines = [f'E2E-03-A{i:02d}-{mark}' for i in range(1, ALT + 1)]
    b_lines = [f'E2E-03-B{i:02d}-{mark}' for i in range(1, ALT + 1)]
    got = {}
    plan = {('A', 'ready'): _ready('a', 'b'), ('B', 'ready'): _ready('b', 'a'), ('A', 'done'): _keep(got, 'A'), ('B', 'done'): _keep(got, 'B')}
    result, memo = two(plan, a_job={'token_hash': run.link(a['email']), 'nickname': b['nickname'], 'mine': a_lines, 'theirs': b_lines, 'offset': 0.0, 'gap': ALT_GAP},
                       b_job={'token_hash': run.link(b['email']), 'nickname': a['nickname'], 'mine': b_lines, 'theirs': a_lines, 'offset': ALT_GAP / 2, 'gap': ALT_GAP}, **LIMITS)
    order = _db_order(run, match_id, a_lines + b_lines)
    if result != 'pass' and not order:  # 앱이 막혀 아무 글도 안 쓰였다 — "DB 글 0행" 이 허위 fail 이 되면 진행 프로그램이 한 번 더 돈다
        return _verdict(check, result, memo)
    check.that(sorted(order) == sorted(a_lines + b_lines), f'DB 글 {len(order)}행(기대 {2 * ALT}행 · 본문 그대로)')
    notes = []
    for who, others in (('A', b_lines), ('B', a_lines)):
        said = got.get(who)
        if not said:
            continue  # 그 앱이 끝 값을 못 말했다 — 두 기기 결과(memo)가 blocked 로 말한다
        shown = said.get('order')
        check.that(shown == order, f"{who} 화면: 순서가 DB 순서와 다름({_diff(shown if shown is not None else MISSING, order)})")
        if isinstance(shown, list):
            doubled = sorted({x for x in shown if shown.count(x) > 1})
            check.that(not doubled, f'{who} 화면: 같은 줄이 겹침 {len(doubled)}건')
        notes.append(f'{who} 화면(상대 줄) ' + _delays(check, run, match_id, others, said.get('seen'), f'{who} 화면', busy=said.get('sent_at')))
    return _verdict(check, result, memo, ' / '.join(notes))


def two_58(run, two):
    """A 가 ⋯ → 채팅방 나가기 → 나가기 → A: 대화 목록으로 이동 · 방 없음. B: "{A 닉네임}님이 채팅방을 나갔어요" 줄이 ≤ 2.0초."""
    check = Check()
    a, b = _ab(run)
    match_id = _match(run, a, b)
    line = _left_line(a)
    got = {}
    plan = {('A', 'ready'): _ready('a', 'b'), ('B', 'ready'): _ready('b', 'a'), ('A', 'left'): _keep(got, 'A'), ('B', 'seen'): _keep(got, 'B')}
    result, memo = two(plan, a_job={'token_hash': run.link(a['email']), 'nickname': b['nickname']},
                       b_job={'token_hash': run.link(b['email']), 'nickname': a['nickname'], 'line': line}, **LIMITS)
    rows = _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.left&select=body')
    if result != 'pass' and not rows:  # 앱이 막혀 아무도 안 나갔다 — A 의 left_at · 목록 검사가 허위 fail 이 되지 않게
        return _verdict(check, result, memo)
    check.that(len(rows) == 1, f'나감 줄 {len(rows)}개(기대 1개)')
    check.that(len(rows) != 1 or rows[0]['body'] == line, f"나감 줄 문구 {rows[0]['body'] if rows else None!r}(기대 {line!r})")
    left = {r['profile_id']: r.get('left_at') for r in _rows(run, f'match_participants?match_id=eq.{match_id}&select=profile_id,left_at')}
    check.that(left.get(a['id']) is not None and left.get(b['id']) is None, f'match_participants.left_at {left}(기대 A 만 찍힘)')
    status, listed = _api(run, 'GET', '/chat/conversations', a['token'])
    ids = [c['match_id'] for c in (listed or {}).get('conversations', [])] if status == 200 else None
    check.that(ids is not None and match_id not in ids, f'A 의 GET /chat/conversations {status} {ids}(기대 200 · 그 방 없음)')
    note = ''
    said = got.get('A')
    if said:
        check.that(said.get('room_gone') is True, f"A 화면에 방이 그대로 {said.get('room_gone', MISSING)}(기대 방이 닫힘)")
        check.that(said.get('on_list') is True, f"A 가 대화 목록으로 이동 못 함(on_list {said.get('on_list', MISSING)})")
        check.that(said.get('row_gone') is True, f"A 의 대화 목록에 방이 목록에 남음(row_gone {said.get('row_gone', MISSING)})")
    said = got.get('B')
    if said:
        check.that(said.get('shown') is True, f"B 화면에 나감 줄이 안 뜸(shown {said.get('shown', MISSING)})")
        seen = {line: said['seen_at']} if said.get('seen_at') else {}
        note = 'B 화면 ' + _delays(check, run, match_id, [line], seen, 'B 화면', kind='left')
    return _verdict(check, result, memo, note)


CASES = {'E-CHAT-03': two_03, 'E-CHAT-58': two_58}


def _guarded(hypothesis):
    """준비가 안 되면 blocked, 예상 밖 예외도 blocked — area2.attempt_with 와 같은 규칙(area5_two._guarded)."""
    return lambda run, two: area2.attempt_with(run, lambda run: hypothesis(run, two))


TWO9 = {case: _guarded(hypothesis) for case, hypothesis in CASES.items()}


PHONE9 = {'E-CHAT-01': _live('01', phone_is_a=False), 'E-CHAT-02': _live('02', phone_is_a=True), 'E-CHAT-07': p_chat_07,
          'E-CHAT-22': p_chat_22, 'E-CHAT-23': p_chat_23, 'E-CHAT-24': p_chat_24, 'E-CHAT-61': p_chat_61, 'E-CHAT-72': p_chat_72}
PHONE9 = {name: _permitted(case) for name, case in PHONE9.items()}

area1.PHONE.update(PHONE9)
area3.BUNDLES['area3-chat-rt'] = list(PHONE9)
twodev.TWO.update(TWO9)
area1.BUNDLES['area3-chat-rt-two'] = list(CASES)
