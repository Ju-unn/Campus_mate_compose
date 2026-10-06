"""영역 3 폰 A 한 대 8차 — 채팅 · 지인 리뷰 8개 + API 1개(묶음 area3-phone-8). 앱 쪽은 frontend/integration_test/area3_b8.dart 의 같은 번호.
기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 그 줄이다. 1 · 2차(area3_phone · area3_phone2)와 같은 모양 —
가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`(E-CHAT-68 은 `(run)`). PC 가 계정 · 매칭 · 추천 연결 · 리뷰를 서비스 키와 API 로 준비하고
앱은 화면에서 본 것을 말하며, 판정은 여기서 한다. 운영 배치(chat-gate · cleanup)는 부르지 않는다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-CHAT-10  "B 화면 ≤ 2.0초" — 폰 계정이 B(받는 쪽)이고 A 의 보내기는 PC 가 API 로 한다. 시계 차는 E-CHAT-67 과 같이 섞인다.
  E-CHAT-16  "B 화면 안녕" — 폰 계정이 A(보내는 쪽). B 화면은 B 토큰으로 같은 방 글을 읽은 API 응답으로 대신한다. 앱이 먼저 앞뒤 공백을
             깎아 보낼 수 있어 서버 깎기(router.py:34)는 PC 가 API 로 공백 그대로 한 번 더 보내 따로 본다.
  E-CHAT-68  "E-CHAT-55 · 58 끝난 뒤" — 배치를 안 부른다. 닫힘은 matches.chat_closed_at 도장을 DB 에 직접 찍고, 나감은 API 로 한다.
  E-REV-20   두 기기 대신 폰 계정 하나가 받은 리뷰 2 · 쓴 리뷰 1 을 다 갖는다(개수가 서로 달라 헷갈리면 잡힌다).
  E-REV-24   "B 화면" 은 B 토큰으로 받은 리뷰를 읽는 API 로 대신한다.
  E-REV-27   "B 알림 1건 더" 는 이번에 안 본다(알림 확인은 영역 4 몫) — 201 · 새 행 · 새 id 까지.
  E-REV-31 · 34 · 35  앱을 켜는 계정이 가설마다 둘 이상(작성자 · 받은 사람 · 보는 사람)이라 상태마다 로그인을 새로 한다.
"""

from datetime import datetime, timezone

from e2e import area1, area3, tools
from e2e.area1 import Check, _api, _app, _rows
from e2e.area3 import _count, _link, _match, _messages, _pair, _patch, _review, _send
from e2e.area3_phone import MISSING, _me, _permitted, _person
from e2e.area3_phone2 import HANGUL, LIMIT, ONE_TAG, SUBMITTED, _paste, _room, _sent, _text, _writer
from e2e.area3_phone5 import LIVE_LIMIT, _at
from e2e.tools import Blocked

TRIM = '  안녕  '
TRIMMED = '안녕'
RECEIVED, WRITTEN = '받은 리뷰', '쓴 리뷰'  # my_friend_reviews_section.dart:40 · 47 — "받은 리뷰 2개"
DELETED = '리뷰를 지웠어요'  # written_reviews_screen.dart:26
CASE_LIMIT = 900  # 앱을 서너 번 켜는 가설 — 기본 420 은 모자란다


def _ask(run, check, phone, account, label, **job):
    """[account] 로 앱을 한 번 켜고 본 것을 돌려준다(못 받으면 {}). 1회용 토큰이라 켤 때마다 새로 받는다."""
    return _app(check, phone(token_hash=run.link(account['email']), **job), label) or {}


def _n(said):
    """앱이 말한 카드 수 — 목록이면 길이, 숫자면 그대로, 말 안 했으면 MISSING."""
    got = said.get('cards', MISSING)
    return len(got) if isinstance(got, list) else got


def _expect(check, label, said, want):
    check.that(_n(said) == want, f'{label} {_n(said)}장(기대 {want})')


def _loaded(check, label, said):
    """14c 는 0개면 자리가 없어 카드가 0 인 것만으로는 "다 읽었다" 를 모른다 — 앱이 뷰모델이 읽기를 끝냈다고 말해야 한다."""
    check.that(said.get('loaded') is True and said.get('error') is None,
               f"{label} 읽기 끝 {said.get('loaded', MISSING)} · 오류 {said.get('error', MISSING)!r}(기대 True · 없음)")


def _hidden_list(check, label, said):
    """20c · 20e 목록이 비었고 "아직 …리뷰가 없어요" 가 그려졌다 — 읽기 전 빈 화면이 아니다."""
    _expect(check, label, said, 0)
    check.that(said.get('empty') is True, f"{label} 빈 문구 {said.get('empty', MISSING)}(기대 True)")


# ── 채팅 ─────────────────────────────────────────────────────────────────────────────────────────────

def p_chat_10(run, phone):
    """폰 계정 B 가 방을 열고 멈춘 사이 A 가 한글 1,000자를 보낸다. DB 1,000자 · B 화면에 같은 글, 서버가 찍은 시각 ~ 앱이 본 시각 ≤ 2.0초."""
    check = Check()
    me, token, partner, match_id = _room(run)
    body, sent = _text(HANGUL, LIMIT), []
    said = _app(check, phone(midway=lambda said: sent.append(_send(run, partner, match_id, body, retry=False)), token_hash=token,
                             nickname=partner['nickname'], body=body))
    if said and said.get('loaded') is False:  # 앱이 방 읽기 · 실시간 구독을 못 끝내 글을 보내기 전에 멈췄다 — 구독 전에 보내면 가짜 실패
        raise Blocked(f"B 방이 안 읽힘(loaded False · 오류 {said.get('error')!r}) — 글을 보내지 않았다. 로그인 · 방 확인")
    if said:
        check.that(said.get('loaded') is True, f"앱이 방 읽기를 끝냈다고 안 말함 {said.get('loaded', MISSING)}(기대 True)")
    check.reply('A 보내기', sent[0] if sent else (0, '앱이 멈추기 전에 끝남'), 201)
    got = _sent(run, partner, match_id)
    check.that(got == [body], f'DB body {[len(b) for b in got]}자 {len(got)}행(기대 [{LIMIT}]자 1행)')
    note = ''
    if said:
        check.that(said.get('bubble') is True, f"B 말풍선 {said.get('bubble', MISSING)}(기대 True — 같은 1,000자)")
        rows = _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.text&select=created_at')
        created, seen = _at((rows or [{}])[0].get('created_at')), _at(said.get('seen_at'))
        if created and seen:
            delay = (seen - created).total_seconds()
            if delay < 0:  # 앱이 본 시각이 서버가 찍은 시각보다 앞 — 폰 시계가 느려 N초 늦은 표시도 가려질 수 있어 판정하지 않는다
                note = f'지연 판정 불가 — 앱이 본 시각이 서버가 찍은 보낸 시각보다 {-delay:.2f}초 앞섬(폰 시계 차). 말풍선 표시만 판정'
            else:
                check.that(delay <= LIVE_LIMIT, f'B 화면에 {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})')
                note = f'지연 {delay:.2f}초(앱 시계 − 서버가 찍은 보낸 시각)'
        else:
            check.problems.append('보낸 시각 또는 앱이 본 시각(seen_at)을 못 읽음')
    return check.result(note)


def p_chat_16(run, phone):
    """폰 계정 A 가 "  안녕  " 을 붙여 넣고 보낸다 → 내 화면 · DB 모두 "안녕". 이어서 PC 가 같은 글을 API 로 보내 서버 깎기도 본다."""
    check = Check()
    me, token, partner, match_id = _room(run)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], paste=_paste(list(map(ord, TRIM)), 1)))
    if said:
        check.that(said.get('bubbles') == [TRIMMED], f"내 화면 말풍선 {said.get('bubbles', MISSING)}(기대 [{TRIMMED!r}])")
        check.that(said.get('error', MISSING) is None, f"화면 오류 문구 {said.get('error', MISSING)!r}(기대 없음)")
    check.that(_sent(run, me, match_id) == [TRIMMED], f'앱이 보낸 글 {_sent(run, me, match_id)}(기대 [{TRIMMED!r}])')
    check.reply('API 앞뒤 공백', _send(run, me, match_id, TRIM, retry=False), 201)
    check.that(_sent(run, me, match_id) == [TRIMMED, TRIMMED], f'DB body {_sent(run, me, match_id)}(기대 둘 다 {TRIMMED!r})')
    status, body = _api(run, 'GET', f'/chat/matches/{match_id}/messages', partner['token'])
    check.that(status == 200, f'B 가 방 글 읽기: {status}')
    shown = [m['body'] for m in (body or {}).get('messages', []) if m.get('kind') == 'text'] if status == 200 else None
    check.that(shown is None or shown == [TRIMMED, TRIMMED], f'B 화면에 보일 글 {shown}(기대 둘 다 {TRIMMED!r})')
    return check.result()


def chat_68(run):
    """닫힌 방 · 나간 방 모두 글이 그대로 남는다. 닫힌 방은 행 수 그대로, 나간 방은 나감 줄 하나만 +1."""
    check = Check()
    closed_a, closed_b, closed = _pair(run)
    left_a, left_b, left = _pair(run)
    for a, b, match_id in ((closed_a, closed_b, closed), (left_a, left_b, left)):
        _messages(run, match_id, a, 2)
        _messages(run, match_id, b, 1)
    before = {match_id: _count(run, f'messages?match_id=eq.{match_id}') for match_id in (closed, left)}
    check.that(set(before.values()) == {3}, f'준비한 글 {before}(기대 방마다 3행)')
    _patch(run, f'matches?id=eq.{closed}', {'chat_closed_at': datetime.now(timezone.utc).isoformat()})
    check.reply('나가기', _api(run, 'POST', f'/chat/matches/{left}/leave', left_a['token']), 200)
    after = {match_id: _count(run, f'messages?match_id=eq.{match_id}') for match_id in (closed, left)}
    check.that(after[closed] == before[closed], f'닫힌 방 {before[closed]} → {after[closed]}행(기대 그대로)')
    check.that(after[left] == before[left] + 1, f'나간 방 {before[left]} → {after[left]}행(기대 +1)')
    lines = _count(run, f'messages?match_id=eq.{left}&kind=eq.left')
    check.that(lines == 1, f'나간 방 나감 줄 {lines}개(기대 1)')
    for label, account, match_id, want in (('닫힌 방 읽기', closed_a, closed, 3), ('나간 방 상대 읽기', left_b, left, 4)):
        status, body = _api(run, 'GET', f'/chat/matches/{match_id}/messages', account['token'])
        got = len((body or {}).get('messages', [])) if status == 200 else None
        check.that(status == 200 and got == want, f'{label}: {status} {got}건(기대 200 · {want}건)')
    return check.result('닫힘은 배치가 아니라 chat_closed_at 을 DB 에 직접 찍은 것 — 배치로 닫히는 쪽은 E-CHAT-55')


# ── 지인 리뷰 ────────────────────────────────────────────────────────────────────────────────────────

def p_rev_20(run, phone):
    """폰 계정이 받은 리뷰 2개 · 쓴 리뷰 1개 — 나 탭 칸이 "받은 리뷰 2개" · "쓴 리뷰 1개"."""
    check = Check()
    me, token = _me(run)
    for _ in range(2):
        writer = _person(run)
        _link(run, me, writer)
        _review(run, writer, me)
    friend = _person(run)
    _link(run, me, friend)
    _review(run, me, friend)
    said = _app(check, phone(token_hash=token)) or {}
    check.that(said.get('received') == f'{RECEIVED} 2개', f"받은 리뷰 칸 {said.get('received', MISSING)!r}(기대 '{RECEIVED} 2개')")
    check.that(said.get('written') == f'{WRITTEN} 1개', f"쓴 리뷰 칸 {said.get('written', MISSING)!r}(기대 '{WRITTEN} 1개')")
    return check.result()


def p_rev_24(run, phone):
    """폰 계정(A)이 쓴 리뷰를 휴지통 → 시트 → "지우기". 카드 · 토스트 · 나 탭 개수 · DB · B 의 받은 리뷰가 모두 0."""
    check = Check()
    me, token, b = _writer(run)
    _review(run, me, b)
    said = _app(check, phone(token_hash=token)) or {}
    check.that(said.get('toast') == DELETED, f"토스트 {said.get('toast', MISSING)!r}(기대 {DELETED!r})")
    check.that(said.get('cards') == 0, f"카드 {said.get('cards', MISSING)}장(기대 0)")
    check.that(said.get('written') == f'{WRITTEN} 0개', f"나 탭 쓴 리뷰 칸 {said.get('written', MISSING)!r}(기대 '{WRITTEN} 0개')")
    rows = _count(run, f"friend_reviews?reviewer_id=eq.{me['id']}&reviewee_id=eq.{b['id']}")
    check.that(rows == 0, f'friend_reviews {rows}행(기대 0)')
    status, body = _api(run, 'GET', '/friend-reviews/received', b['token'])
    check.that(status == 200 and (body or {}).get('reviews') == [], f'B 의 받은 리뷰: {status} {body}(기대 200 · 빈 목록)')
    return check.result()


def p_rev_27(run, phone):
    """쓰고 지운 같은 사람에게 앱으로 다시 쓴다 → 토스트 · DB 새 행 1 · 새 id."""
    check = Check()
    me, token, b = _writer(run)
    status, first = _api(run, 'POST', '/friend-reviews', me['token'], {'reviewee_id': b['id'], 'tags': ONE_TAG})
    check.that(status == 201 and bool((first or {}).get('id')), f'첫 작성: {status} {first}')
    first_id = (first or {}).get('id')
    if first_id:
        check.reply('지우기', _api(run, 'DELETE', f'/friend-reviews/{first_id}', me['token']), 204)
    said = _app(check, phone(token_hash=token, profile_id=b['id'], tags=ONE_TAG)) or {}
    check.that(said.get('toast') == SUBMITTED, f"토스트 {said.get('toast', MISSING)!r}(기대 {SUBMITTED!r})")
    check.that(said.get('closed') is True, f"시트 닫힘 {said.get('closed', MISSING)}")
    rows = _rows(run, f"friend_reviews?reviewer_id=eq.{me['id']}&reviewee_id=eq.{b['id']}&select=id")
    check.that(len(rows) == 1 and rows[0]['id'] != first_id, f'friend_reviews {rows}(기대 새 id 1행, 지운 것 {first_id})')
    return check.result('B 알림 1건 더는 안 봄(영역 4 알림 확인 몫)')


def p_rev_31(run, phone):
    """작성자 A 를 정지시키면 그 리뷰가 받은 목록 · 14c 에서 0장, active 로 되돌리면 1장."""
    check = Check()
    me, a, x = _person(run), _person(run), _person(run)
    _link(run, me, a)
    _review(run, a, me)  # A → 폰 계정(받은 목록)
    _match(run, me, x)
    _link(run, a, x)
    _review(run, a, x)  # A → X(폰 계정이 X 의 14c 를 본다)
    try:
        for state, want in (('suspended', 0), ('active', 1)):
            _patch(run, f"profiles?id=eq.{a['id']}", {'status': state})
            part = Check()
            listed = _ask(run, part, phone, me, f'{state} 받은 목록', list='received')
            _expect(part, '받은 목록', listed, want)
            if want == 0:
                part.that(listed.get('empty') is True, f"받은 목록 빈 문구 {listed.get('empty', MISSING)}(기대 True)")
            about = _ask(run, part, phone, me, f'{state} 14c', about=x['id'], nickname=x['nickname'])
            _loaded(part, '14c', about)
            _expect(part, '14c', about, want)
            check.problems += [f'{state}: {p}' for p in part.problems]
    finally:
        _patch(run, f"profiles?id=eq.{a['id']}", {'status': 'active'})
    return check.result()


def p_rev_34(run, phone):
    """리뷰를 blinded 로 가리면 쓴 목록 · 받은 목록 · 14c 모두 0장이고, 작성자가 지우려 해도 404. 행은 지워지지 않는다."""
    check = Check()
    a, b = _person(run), _person(run)
    _link(run, a, b)
    _match(run, a, b)
    review = _review(run, a, b)
    _patch(run, f'friend_reviews?id=eq.{review}', {'status': 'blinded'})
    _hidden_list(check, '쓴 목록(A)', _ask(run, check, phone, a, 'A 쓴 목록', list='written'))
    _hidden_list(check, '받은 목록(B)', _ask(run, check, phone, b, 'B 받은 목록', list='received'))
    about = _ask(run, check, phone, a, 'A 가 본 B 의 14c', about=b['id'], nickname=b['nickname'])
    _loaded(check, '14c', about)
    _expect(check, '14c', about, 0)
    check.reply('작성자 지우기', _api(run, 'DELETE', f'/friend-reviews/{review}', a['token']), 404, area3.REVIEW_GONE)
    rows = _count(run, f'friend_reviews?id=eq.{review}')
    check.that(rows == 1, f'friend_reviews {rows}행(기대 1 — 가렸을 뿐 지우지 않는다)')
    return check.result()


def p_rev_35(run, phone):
    """A 가 작성자 C 를 차단하면 A 가 보는 B 의 14c 에서 C 의 리뷰만 사라진다 — B 의 받은 목록에는 그대로 1장."""
    check = Check()
    a, b, c = _person(run), _person(run), _person(run)
    _link(run, b, c)
    _review(run, c, b)
    _match(run, a, b)
    _match(run, a, c)
    before = _ask(run, check, phone, a, '차단 전 14c', about=b['id'], nickname=b['nickname'])  # 대조군 — 안 가려졌을 때는 보인다
    _loaded(check, '차단 전 14c', before)
    _expect(check, '차단 전 14c', before, 1)
    check.reply('A 가 C 차단', _api(run, 'POST', f"/blocks/{c['id']}", a['token']), 200)
    after = _ask(run, check, phone, a, '차단 뒤 14c', about=b['id'], nickname=b['nickname'])
    _loaded(check, '차단 뒤 14c', after)
    _expect(check, '차단 뒤 14c(A)', after, 0)
    _expect(check, '받은 목록(B)', _ask(run, check, phone, b, 'B 받은 목록', list='received'), 1)
    return check.result()


PHONE8 = {
    'E-CHAT-10': p_chat_10, 'E-CHAT-16': p_chat_16, 'E-REV-20': p_rev_20, 'E-REV-24': p_rev_24, 'E-REV-27': p_rev_27,
    'E-REV-31': p_rev_31, 'E-REV-34': p_rev_34, 'E-REV-35': p_rev_35,
}
PHONE8 = {name: _permitted(case) for name, case in PHONE8.items()}
tools.CASE_LIMITS.update({name: CASE_LIMIT for name in ('E-REV-31', 'E-REV-34', 'E-REV-35')})

CASES = {'E-CHAT-68': chat_68}

area1.PHONE.update(PHONE8)
area3.BUNDLES['area3-phone-8'] = [*PHONE8, *CASES]


def attempt(run, case):
    """API 가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
