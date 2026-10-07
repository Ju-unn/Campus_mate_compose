"""영역 3 신뢰 확인 6개 — E-CHAT-37 · 38 · 40 · 41(폰 한 대, 묶음 area3-phone-11) + 39 · 44(폰 + 에뮬 두 기기, 묶음 area1.BUNDLES['area3-two-11']).
기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 그 줄이다. 앱 쪽은 frontend/integration_test/area3_b11.dart 의 같은 번호(두 기기는 `번호/A` · `번호/B`).
배치(chat-gate)는 부르지 않는다 — 48시간 기한을 기다리는 것이 아니라 두 번째 수락이 그 자리에서 통과시키는 것을 본다(chat/router.py:312-340).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-CHAT-37  폰 계정이 B(방을 열고 기다리는 쪽), A 의 수락은 PC 가 API 로 한다 — "B 줄 ≤ 2.0초" 는 서버가 찍은 수락 줄 시각 ~ 앱이 본 시각(E-CHAT-10 과 같은 방식,
             폰 시계와 서버 시계의 차가 섞인다). A 화면의 "수락했어요. 상대의 응답을 기다리고 있어요" 배너는 못 본다 — 그 배너를 고르는 값(머리말 gate.my_response=accept ·
             passed=false)을 A 토큰으로 읽는 것으로 대신하고, A 가 배너 "수락하기" → 확인 창 "수락" 을 누르는 길은 E-CHAT-43 · 39 · 44 가 본다.
  E-CHAT-38  폰 계정이 B(HOME), A 의 수락은 API. 판 둘(새 메시지 켬 · 끔)을 한 가설에서 돈다. 끈 판의 "0건" 은 같은 판에서 다른 알림(카드 수락)이 오는지로 길이 살아 있음을 보인다.
             알림 종류 new_message 는 조용한 시간 예외(cards/push.py `_QUIET_HOURS_EXEMPT`)지만 끈 판의 대조 알림(acceptance_received)은 예외가 아니라 낮(08~22시)에만 돈다.
  E-CHAT-39  A 는 PC 가 API 로 미리 수락해 둔다("E-CHAT-37 뒤"). 두 기기 — A(폰)는 기다림 배너를 단 채 방에서 기다리고, B(에뮬)가 배너 "수락하기" → 확인 창 "수락" 을 누른다.
             A 의 "카드까지 ≤ 2.0초" 는 앱 안의 시계로 잰다(A 뷰모델이 상대 수락 줄을 받은 때 → 14b 카드가 그려진 때, 50ms 간격이라 ±50ms). 보이는 카카오톡 아이디는 상대의 profile_private
             값과, 머리 사진 주소는 상대 첫 사진(profile_photos 의 가장 앞)의 서명 주소 경로(`/object/sign/profile-photos/<경로>`)와 맞춘다 — 서명 토큰은 부를 때마다 달라 경로만 본다.
  E-CHAT-40  폰 계정이 먼저 수락하고 HOME 에서 기다리고, 상대가 마지막으로 수락한다(E-PUSH-37 과 같은 일). 마지막에 누른 쪽의 알림(defer=False)은 기기가 하나라 못 본다 — 도장(trust_passed_at)으로 대신.
             match_made 는 조용한 시간 예외가 아니라(cards/push.py) 낮에만 돈다(notify.require_daytime).
  E-CHAT-41  폰 계정이 먼저 수락하고 "매칭 성립" 을 끈 뒤 상대가 마지막으로 수락한다(E-PUSH-39 와 같은 일). "알림 0건" 이 도장이 안 찍혀서가 아님을 trust_passed_at 으로 보이고,
             길이 살아 있음은 같은 순간 오는 상대의 수락 알림("새 메시지" — 끄지 않은 다른 칸)으로 보인다.
  E-CHAT-44  두 기기가 같은 순간에 누른다 — 두 앱이 확인 창을 연 채 `armed` 에서 서고, PC 가 둘 다 선 것을 보고 거의 동시에 go 를 보낸다(±50ms 는 보장 못 함). 실제 편차는 서버가 받은
             두 수락 시각(match_participants.responded_at)의 차와 PC 가 go 를 보낸 시각 차로 메모에 남긴다. "사람마다 통과 알림 ≤ 1건" 은 서버가 알림을 기록하지 않아 못 센다 —
             통과 알림은 도장을 찍은 쪽만 보내므로(router.py:330 `if not stamped: return`) 도장 1회가 곧 사람마다 ≤ 1건이다(알림창은 안 읽음).
             ⚠ 두 요청이 서로의 수락을 보기 전에 읽으면(router.py:302 fetch_match → :309 save_trust_accept → :315 상대 응답을 읽은 값으로 판정) 둘 다 "상대 미응답" 이라 도장이 안 찍힌다.
             그때는 fail 이 아니라 blocked("결함 후보")로 끝내고 메모에 남긴다 — 시나리오가 "다음 매시 배치까지 기다림 배너에 머물 수 있다(확인 필요)" 라고 적은 자리다.
"""

from e2e import area1, area2, area3, tools, twodev
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app, _one, _rows
from e2e.area2_two_accept import _after, _verdict
from e2e.area3 import _match
from e2e.area3_phone import MISSING, _permitted, _person
from e2e.area3_phone2 import _room
from e2e.area3_phone5 import LIVE_LIMIT, _at
from e2e.area4_push import PUBLIC_TITLE, TRUST_BODY, _case, _public, _Scene
from e2e.tools import Blocked

ACCOUNT = 150  # 계정 하나 준비의 넉넉한 최악(초) — 가입 · 온보딩 · 로그인 429 대기 재시도까지(area5_two.PREP_ACCOUNT 와 같은 추정)
LIMITS = {'side_timeout': {'A': 300, 'B': 300}, 'deadline': 720}  # 두 기기: 다음 말까지 기다리는 시간 · 전체 상한(twodev.two). 에뮬이 느려도 넉넉히

WAITING = '수락했어요. 상대의 응답을 기다리고 있어요'  # chat_room_screen.dart:408 — 수락한 쪽의 14g 배너
ACCEPT_LINE = '{}님이 카카오톡 아이디·실사진 공개를 수락했어요'  # chat/router.py:323 — 수락 줄(kind=trust_accept)


def _trust(run, account, match_id):
    """신뢰 수락 — 두 번 가면 두 번째가 409 라 다시 보내지 않는다(연결이 끊겨도 처음부터 다시 하지 않고 blocked)."""
    return _api(run, 'POST', f'/chat/matches/{match_id}/trust', account['token'], retry=False)


def _participants(run, match_id):
    return {r['profile_id']: r for r in _rows(run, f'match_participants?match_id=eq.{match_id}&select=profile_id,trust_response,responded_at')}


def _lines(run, match_id):
    return _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.trust_accept&select=sender_id,body,created_at')


# ── E-CHAT-37 ───────────────────────────────────────────────────────────────────────────────────────

def p_chat_37(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)  # 폰 계정 = B, 상대 = A
    line = ACCEPT_LINE.format(partner['nickname'])
    sent = []
    said = _app(check, phone(midway=lambda said: sent.append(_trust(run, partner, match_id)), token_hash=token,
                             nickname=partner['nickname'], line=line))
    if said and said.get('loaded') is False:  # 방 읽기 · 실시간 구독 전에 수락하면 줄이 안 와 가짜 실패
        raise Blocked(f"B 방이 안 읽힘(loaded False · 오류 {said.get('error')!r}) — A 의 수락을 보내지 않았다. 로그인 · 방 확인")
    check.reply('A 수락', sent[0] if sent else (0, '앱이 멈추기 전에 끝남'), 200)
    rows = _participants(run, match_id)
    got = {pid: row.get('trust_response') for pid, row in rows.items()}
    check.that(got == {me['id']: None, partner['id']: 'accept'}, f'trust_response {got}(기대 A accept · B 없음)')
    lines = _lines(run, match_id)
    check.that([row['body'] for row in lines] == [line], f'수락 줄 {[row["body"] for row in lines]}(기대 {[line]} 한 줄)')
    status, room = _api(run, 'GET', f'/chat/matches/{match_id}', partner['token'])
    gate = (room or {}).get('gate') or {}
    check.that(status == 200 and (gate.get('my_response'), gate.get('passed')) == ('accept', False),
               f'A 쪽 기다림 배너 재료 {status} {gate}(기대 200 · my_response accept · passed False)')
    note = ''
    if said:
        check.that(line in (said.get('lines') or []), f"B 화면 수락 줄 {said.get('lines', MISSING)}(기대 {line!r})")
        note = _delay(check, said.get('seen_at'), (lines or [{}])[0].get('created_at'), 'B 화면에')
    return check.result(note)


def _delay(check, seen_text, created_text, where):
    """서버가 찍은 시각 ~ 앱이 본 시각 ≤ [LIVE_LIMIT]. 앱 시각이 앞이면 폰 시계가 느린 것이라 판정하지 않는다(E-CHAT-10 과 같다). → 메모."""
    created, seen = _at(created_text), _at(seen_text)
    if not (created and seen):
        check.problems.append('수락 줄 시각 또는 앱이 본 시각(seen_at)을 못 읽음')
        return ''
    delay = (seen - created).total_seconds()
    if delay < 0:
        return f'지연 판정 불가 — 앱이 본 시각이 서버가 찍은 시각보다 {-delay:.2f}초 앞섬(폰 시계 차). 줄이 보인 것만 판정'
    check.that(delay <= LIVE_LIMIT, f'{where} {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})')
    return f'지연 {delay:.2f}초(앱 시계 − 서버가 찍은 수락 줄 시각)'


# ── E-CHAT-38 · 40 · 41 알림 ─────────────────────────────────────────────────────────────────────────

def _stamped(s, match_id):
    """통과 도장(trust_passed_at)이 찍혔는가 — 알림이 "안 온 것" 이 도장이 안 찍혀서가 아님을 보인다."""
    rows = _rows(s.run, f'matches?id=eq.{match_id}&select=trust_passed_at')
    s.check.that(rows and rows[0].get('trust_passed_at'), f'trust_passed_at {rows}(찍혀야 함)')


def _first_accepts(s):
    """폰 계정이 먼저 수락하고 HOME 에서 기다린다 → 방 id."""
    match_id = factory.match(s.run, s.me, s.partner)
    factory.trust(s.run, s.me, match_id)
    return match_id


def p_chat_38(run, phone):
    check, notes = Check(), []
    for label, off in (('새 메시지 켬', False), ('새 메시지 끔', True)):
        s = _Scene(run, phone)  # 낮에만 — 끈 판의 대조 알림(카드 수락)이 조용한 시간 예외가 아니다
        if s.ready:
            if off:
                factory.switches(s.run, s.me, new_message=False)
            match_id = factory.match(s.run, s.me, s.partner)
            before = s.before()
            factory.trust(s.run, s.partner, match_id)
            if off:
                s.silent(before, only=lambda n: n.title == s.nick, control='accept')
            else:
                s.arrives(before, s.nick, TRUST_BODY, once=True)
        check.problems += [f'{label}: {p}' for p in s.check.problems]
        notes += s.notes
        if not s.ready:
            break
    return check.result('; '.join(notes))


@_case
def p_chat_40(s):
    match_id = _first_accepts(s)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)  # 마지막 수락 — 이 계정은 앱 밖(HOME)에 있다
    s.arrives(before, PUBLIC_TITLE, _public(s.nick), once=True)
    _stamped(s, match_id)
    s.notes.append('마지막에 누른 쪽(상대)의 공개 알림 1개는 폰이 하나라 못 봄 — trust_passed_at 으로 대신')


@_case
def p_chat_41(s):
    match_id = _first_accepts(s)
    factory.switches(s.run, s.me, match_made=False)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.proof(before, s.nick, TRUST_BODY)  # 새 메시지 알림(다른 칸)은 온다 — 길이 살아 있다는 증거를 겸한다
    s.silent(before, only=lambda n: n.title == PUBLIC_TITLE, control=None)
    _stamped(s, match_id)
    s.notes.append('상대(마지막에 누른 쪽)는 받는다는 것은 폰이 하나라 못 봄 — E-CHAT-40 의 같은 경로가 본다')


# ── 두 기기 — E-CHAT-39 · 44 ─────────────────────────────────────────────────────────────────────────

def _pair(run):
    """A(폰) · B(에뮬) — 홈까지 끝낸 계정 둘과 그 방(방금 만든 방이라 미리 수락 배너 단계). 방 시각은 안 옮긴다."""
    a, b = _person(run), _person(run)
    return a, b, _match(run, a, b)


def _facts(run, account):
    """화면에 나와야 할 [account] 의 카카오톡 아이디와 첫(position 이 가장 앞) 실사진 경로 — 없으면 화면을 맞출 기준이 없다."""
    kakao = _one(run, f"profile_private?profile_id=eq.{account['id']}&select=kakao_id").get('kakao_id')
    photos = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=storage_path,position")
    if not kakao or not photos:
        raise Blocked(f"준비: {account['nickname']} 의 카카오톡 아이디({kakao!r}) 또는 실사진({len(photos)}장)이 없음 — 공개 화면을 맞출 기준이 없다")
    return kakao, min(photos, key=lambda row: row.get('position') or 0)['storage_path']


def _is_photo(url, path):
    """서명 주소(`…/object/sign/profile-photos/<경로>?token=…`)가 그 사진인가 — 토큰은 부를 때마다 달라 경로만 본다."""
    return bool(url) and str(url).split('?')[0].endswith(f'/object/sign/profile-photos/{path}')


def _screen(check, who, said, kakao, path):
    """[who] 화면이 "신뢰 확인 완료" 카드 · 상대 카카오톡 아이디 · 실사진 머리 사진을 보였는가."""
    if said.get('card') is not True:
        check.problems.append(f'{who} 신뢰 확인 완료 카드가 {said.get("card", MISSING)}(기대 True — 기다림 배너에 머묾)')
        return
    first = (said.get('photos') or [None])[0]
    check.that(said.get('kakao_id') == kakao, f'{who} 카카오톡 아이디 {said.get("kakao_id", MISSING)!r}(기대 DB 값 {kakao!r})')
    check.that(said.get('kakao_shown') is True, f'{who} 카카오톡 아이디가 카드에 안 보임 {said.get("kakao_shown", MISSING)}')
    check.that(_is_photo(said.get('header_photo'), path), f'{who} 머리 사진 {said.get("header_photo", MISSING)!r}(기대 실사진 …/profile-photos/{path})')
    check.that(_is_photo(first, path), f'{who} 방 머리말의 첫 사진 {first!r}(기대 실사진 …/profile-photos/{path})')


def _loaded(side, said):
    """앱이 방을 못 읽었다고 하면(확인 창을 못 열었다) 그 자리에서 blocked — 상대가 상한까지 기다리지 않게 twodev 가 상대를 푼다."""
    if said.get('loaded') is False:
        raise Blocked(f"{side} 방이 안 읽힘(오류 {said.get('error')!r}) — 확인 창을 못 열어 누르지 않았다. 로그인 · 방 확인")


def _both_reported(got):
    """두 앱이 `report` 까지 갔는가 — 안 갔으면 앱 쪽이 막힌 것이라 DB 를 읽어 fail 을 만들지 않는다. 방을 못 읽었다고 하면 blocked."""
    if not all(side in got for side in 'AB'):
        return False
    for side in 'AB':
        if got[side].get('loaded') is False:
            raise Blocked(f"{side} 방이 안 읽힘(오류 {got[side].get('error')!r}) — 로그인 · 방 확인")
    return True


def _room_end(check, run, match_id, a, b):
    """서버에 남은 것 — 둘 다 accept · 수락 줄 2개. → (도장, 참가자 행)."""
    rows = _participants(run, match_id)
    answers = {pid: row.get('trust_response') for pid, row in rows.items()}
    check.that(answers == {a['id']: 'accept', b['id']: 'accept'}, f'trust_response {answers}(기대 둘 다 accept)')
    lines = _lines(run, match_id)
    check.that(len(lines) == 2, f'수락 줄 {len(lines)}개(기대 2 — 사람마다 한 줄)')
    stamp = (_rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at') or [{}])[0].get('trust_passed_at')
    return stamp, rows


def _ms(said):
    return f"{said.get('card_ms')}ms" if said.get('card_ms') is not None else '카드 없음'


def two_39(run, two):
    check = Check()
    a, b, match_id = _pair(run)
    (a_kakao, a_photo), (b_kakao, b_photo) = _facts(run, a), _facts(run, b)
    reply = _trust(run, a, match_id)  # "E-CHAT-37 뒤" — A 가 먼저 수락해 둔다(앱이 켜지기 전)
    if reply[0] != 200:
        raise Blocked(f'준비: A 의 먼저 수락 {reply[0]} {reply[1]}')
    got = {}

    def a_ready(said, sync):
        _loaded('A', said)
        got['ready'] = said
        sync.set('a-ready')  # A 의 수락 줄 구독이 선 뒤에야 B 가 누른다

    def b_armed(said, sync):
        _loaded('B', said)
        _after(sync, 'a-ready', 'A')

    def report(side):
        def handler(said, sync):
            got[side] = said
        return handler

    result, memo = two({('A', 'ready'): a_ready, ('B', 'armed'): b_armed, ('A', 'report'): report('A'), ('B', 'report'): report('B')},
                       a_job={'token_hash': run.link(a['email']), 'nickname': b['nickname']},
                       b_job={'token_hash': run.link(b['email']), 'nickname': a['nickname']}, **LIMITS)
    if not (_both_reported(got) and 'ready' in got):
        return result, memo
    banners = got['ready'].get('banners') or []
    check.that(WAITING in banners, f'B 가 누르기 전 A 화면 배너 {banners}(기대 기다림 배너 {WAITING!r})')
    _screen(check, 'A 화면', got['A'], b_kakao, b_photo)
    _screen(check, 'B 화면', got['B'], a_kakao, a_photo)
    if got['A'].get('card') is True:
        ms = got['A'].get('card_ms')
        check.that(ms is not None, 'A 화면이 상대 수락 줄을 받은 때를 말하지 않음(수락 줄 도착 → 카드 시간을 못 잼)')
        check.that(ms is None or ms <= LIVE_LIMIT * 1000, f'A 화면 카드까지 {(ms or 0) / 1000:.1f}초(기대 ≤ {LIVE_LIMIT})')
    stamp, _ = _room_end(check, run, match_id, a, b)
    check.that(stamp, 'matches.trust_passed_at 이 안 채워짐(기대 채워짐)')
    return _verdict(check, result, memo, f"A 화면 카드까지 {_ms(got['A'])}(앱 시계: 상대 수락 줄 도착 → 카드) · B 화면 카드까지 {_ms(got['B'])}(누른 뒤)",
                    'A 의 먼저 수락은 PC 가 API 로(화면으로 누르는 길은 E-CHAT-43 · 44 와 B 쪽이 본다)')


def two_44(run, two):
    check = Check()
    a, b, match_id = _pair(run)
    (a_kakao, a_photo), (b_kakao, b_photo) = _facts(run, a), _facts(run, b)
    got, released = {}, {}

    def armed(side, other):
        def handler(said, sync):
            _loaded(side.upper(), said)
            sync.set(f'{side}-armed')
            _after(sync, f'{other}-armed', other.upper())  # 둘 다 확인 창을 연 채 설 때까지 — 먼저 선 쪽이 기다린다
            released[side] = sync.now()  # 이 핸들러가 돌아오면 twodev 가 곧바로 go 를 보낸다
        return handler

    def report(side):
        def handler(said, sync):
            got[side] = said
        return handler

    result, memo = two({('A', 'armed'): armed('a', 'b'), ('B', 'armed'): armed('b', 'a'), ('A', 'report'): report('A'), ('B', 'report'): report('B')},
                       a_job={'token_hash': run.link(a['email']), 'nickname': b['nickname']},
                       b_job={'token_hash': run.link(b['email']), 'nickname': a['nickname']}, **LIMITS)
    if not _both_reported(got):
        return result, memo
    stamp, rows = _room_end(check, run, match_id, a, b)
    at = {pid: _at(row.get('responded_at')) for pid, row in rows.items()}
    server = abs((at[a['id']] - at[b['id']]).total_seconds()) * 1000 if at.get(a['id']) and at.get(b['id']) else None
    skew = (f'서버가 받은 두 수락 시각 차 {server:.0f}ms' if server is not None else '서버가 받은 두 수락 시각을 못 읽음')
    if len(released) == 2:
        skew += f' · PC 가 두 기기를 푼 시각 차 {abs(released["a"] - released["b"]) * 1000:.0f}ms'
    skew += '(±50ms 는 보장 못 함)'
    if stamp:
        _screen(check, 'A 화면', got['A'], b_kakao, b_photo)
        _screen(check, 'B 화면', got['B'], a_kakao, a_photo)
    seen = f"두 화면이 공개되기까지: A {_ms(got['A'])} · B {_ms(got['B'])}(각자 누른 뒤)"
    if not check.problems and not stamp:
        return 'blocked', (f'결함 후보 — 두 사람이 같은 순간에 수락했는데 matches.trust_passed_at 이 안 찍힘: 두 요청이 서로의 수락을 보기 전에 읽어 둘 다 "상대 미응답" 으로 '
                           f'판정한 경우일 수 있다(chat/router.py:302 읽기 → :309 저장 → :315 읽은 값으로 판정). 다음 매시 chat-gate 배치가 찍을 때까지 두 화면이 기다림 배너에 머문다'
                           f'(시나리오 ⚠ 확인 필요). {skew} · {seen}')
    return _verdict(check, result, memo, f'{skew} · {seen}', '통과 알림은 도장을 찍은 쪽만 보내므로(router.py:330) 도장 1회 = 사람마다 ≤ 1건 — 알림창은 안 읽음')


CASES = {'E-CHAT-39': two_39, 'E-CHAT-44': two_44}


def _guarded(hypothesis):
    """준비가 안 되면 blocked, 연결 끊김은 처음부터 한 번 더(계정은 매번 새로 만든다), 예상 밖 예외도 blocked — area2.attempt_with 와 같은 규칙."""
    return lambda run, two: area2.attempt_with(run, lambda run: hypothesis(run, two))


# ── 등록 · 묶음 · 시간 상한 ───────────────────────────────────────────────────────────────────────────

PHONE11 = {'E-CHAT-37': _permitted(p_chat_37), 'E-CHAT-38': _permitted(p_chat_38), 'E-CHAT-40': p_chat_40, 'E-CHAT-41': p_chat_41}
TWO11 = {case: _guarded(hypothesis) for case, hypothesis in CASES.items()}
# 가설마다 계산한 상한(초) — 계정은 [ACCOUNT] 씩 + 앱 · 기다림:
#  37       계정 2 + 앱(로그인 · 방 · 멈춤 180) = 480 → 600
#  38       계정 5(두 판: 폰 · 상대 · 폰 · 상대 · 대조) + 앱 2번(120) + 켠 판 알림(60 + 20) + 끈 판 지켜보기 60 + 대조(30) = 1040 → 1200
#  40 · 41  계정 2 + 앱 60 + 알림 60 + 20 + 대조 30 = 470 → 900(E-PUSH-39 와 같다)
#  39 · 44  계정 2 + 전체 상한 720([LIMITS]) = 1020 → 1200
tools.CASE_LIMITS.update({'E-CHAT-37': 600, 'E-CHAT-38': 1200, 'E-CHAT-40': 900, 'E-CHAT-41': 900, 'E-CHAT-39': 1200, 'E-CHAT-44': 1200})

area1.PHONE.update(PHONE11)
area3.BUNDLES['area3-phone-11'] = list(PHONE11)
twodev.TWO.update(TWO11)
area1.BUNDLES['area3-two-11'] = list(CASES)
