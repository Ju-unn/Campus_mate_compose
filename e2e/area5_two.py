"""영역 5 두 기기(폰 A + 에뮬 B) 탈퇴 5개(묶음 area5-two) — E-WD-05 · 06 · 07 · 08 · 09. 기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md
5-2 표의 그 줄을 지금 코드와 대조한 것이다. 앱 쪽은 frontend/integration_test/area5_two.dart 의 `번호/A`(폰) · `번호/B`(에뮬)(area5.dart 가 묶는다).
돌릴 때: A폰 + B에뮬을 둘 다 연결하고 `python -m e2e run area5-two`(두 기기 가설은 늘 A=폰 · B=에뮬).

가설 하나 = `(run, two) -> (결과, 메모)`(e2e/twodev.py). A 는 늘 폰에서 나 탭 → 설정 → 탈퇴하기 → 영구 삭제 → "정말 영구 삭제" 를 실제로 누른다
(area5_wd.dart 의 _wdOpenFinal · _wdWithdraw 를 쓴다 — area5_two.dart 의 A 쪽만). 02 에 닿으면 `withdrawn` 에서 멈추고, PC 가 DB 로 탈퇴를 확인한 뒤
`a-out` 을 세운다. B 는 그 뒤에 움직인다 — 목록은 앱이 처음 읽을 때의 서버 상태로 굳으므로(area2_two_accept 머리말) 대부분 로그아웃한 채 `wait` 에서
멈췄다가 PC 가 go 에 실어 준 새 토큰으로 로그인한다(그게 시나리오의 "새로고침"이다). 1회용 토큰은 같은 계정이 새로 받으면 앞 것이 죽으므로 늦게 쓸 토큰은 그때 받는다.
PC 가 직접 본 어긋남은 [Check] 에 모아 두 기기 결과와 합친다(area2_two_accept._verdict — PC 가 찾은 것은 앱이 막혔어도 fail).
쓰기는 이번 실행이 만든 계정에만(area2._guard). 탈퇴는 되돌릴 수 없어 계정은 가설마다 새로 만든다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-WD-05  B 의 알림은 시나리오의 "탈퇴한 계정이에요" 가 아닐 수 있다 — A 의 탈퇴가 그 사람의 로그인을 모두 끊으면(logout scope=global) B 의 다음 요청은
           서버 관문(current_user.py)에서 탈퇴 표시 없는 401 이 되고, 앱은 토큰을 새로 받으려다 실패해 02 + "세션이 만료됐어요, 다시 로그인해 주세요"
           를 띄운다(E-WD-18 과 같은 까닭). PC 가 A 탈퇴 뒤 GoTrue /user 로 끊겼는지 보고 기대 알림을 B 에게 go 로 준다(메모에 어느 쪽인지 남긴다).
           "새로고침 토큰도 끊김" 은 B 앱이 로그인했을 때 들고 있던 refresh token 으로 02 에서 setSession 을 해 보고 거절되는지로 본다.
  E-WD-06  B 는 A 탈퇴 뒤 새로 로그인해 방을 연다. "API 직접 B 보내기 → 409" 와 "left_at null · 나가기 시스템 줄 0" 은 B 가 방을 연 채 멈춘 사이 PC 가 본다.
           카톡 아이디 · 실사진 카드(TrustRevealBubble)는 게이트 통과 방이라 탈퇴 전에는 있어야 한다 — 그 "있었음" 은 PC 가 DB(trust_passed_at)로 준비만 하고
           앱은 사라진 모습만 본다.
  E-WD-08  ⚠ 배치는 실제 daily-cards 를 시험 지역(e2e)에만 맞춰 부른다(area2_time_batch._issue — 관문 · 설정 원복 · 대조군). "테스트대학에 A · B 만 반대 성별"
           은 만들 수 없어(실제 학교) 응답의 no_candidate 는 못 읽는다 — 대신 B 의 후보(GET /matching/candidates)에 A 가 없고, 배치 뒤 B 의 무료 카드에
           A 가 0장인지 본다. 대조군 C(여)가 카드를 받아야 배치가 돈 것으로 친다. 배치를 부른 뒤의 fail 은 다시 안 돈다.
  E-WD-09  B 의 리뷰는 PC 가 DB 로 넣는다(area3._review — 추천 연결 없이). 20e 의 "A 줄 0" 은 B 앱이, API GET /friend-reviews/written 은 PC 가 본다.

유료 호출 — 0(계정 공장의 온보딩 · E-WD-08 의 배치가 부르는 것은 다른 카드 가설과 같다). 디스코드 — 0줄.
"""

from datetime import datetime, timezone

from e2e import area1, area2, area2_time_batch, tools, twodev
from e2e.area1 import Check, _api, _patch, _rows
from e2e.area2 import _ONCE, _candidates, _card, _person
from e2e.area2_phone3 import EVERY_DAY
from e2e.area2_two_accept import _accepted, _after, _nickname, _until, _verdict
from e2e.area3 import _count, _match, _messages, _review
from e2e.area3_phone5 import _single_shot
from e2e.area3_safe import _inbox
from e2e.area5_wd import EXPIRED, WITHDRAWN, _sessions_cut, _state
from e2e.tools import Blocked

PARTNER_LEFT = '상대가 대화를 나갔어요'  # core/errors.py CHAT_PARTNER_LEFT
CARD_GONE = '카드를 찾을 수 없어요'  # core/errors.py CARD_NOT_FOUND
MESSAGES = 5  # 시나리오 E-WD-06 "채팅 5건"
CASE_LIMIT = 1500  # 계정 둘 · 두 기기 · A 의 탈퇴 흐름(+ 08 의 배치)
LIMITS = {'side_timeout': {'A': 300, 'B': 600}, 'deadline': 1200}
BATCH_LIMITS = {'side_timeout': {'A': 600, 'B': 900}, 'deadline': 1400}  # 08 — A 가 멈춘 사이 배치 + 카드 기다림


# ── 공통 ────────────────────────────────────────────────────────────────────────────────────────────

def _pair(run, a_gender='female'):
    """A(폰, 탈퇴하는 쪽) · B(에뮬) — 서로 후보인 홈 계정 한 쌍. A 를 먼저 만든다(id 차례가 시험과 같게)."""
    other = 'male' if a_gender == 'female' else 'female'
    return _person(run, a_gender), _person(run, other)


def _out(run, check, a, then=None):
    """A 앱이 02 에 닿아 `withdrawn` 에서 멈춘 사이 — DB 로 탈퇴를 확인하고 [then](check 를 더 하는 일)을 한 뒤 `a-out` 을 세운다."""
    def handler(said, sync):
        landed = _until(lambda: _state(run, a).get('status') == 'withdrawn')
        check.that(landed, f"A 가 \"정말 영구 삭제\" 를 누른 뒤 status {_state(run, a).get('status')!r}(기대 withdrawn)")
        if landed and then:
            then()
        sync.set('a-out')
    return handler


def _login_after_out(run, b):
    """B 가 로그아웃한 채 `wait` 에서 멈춘 사이 — A 가 나간 뒤 B 의 새 토큰을 준다."""
    def handler(said, sync):
        _after(sync, 'a-out', 'A')
        return {'token_hash': run.link(b['email'])}
    return handler


def _a_job(run, a):
    return {'token_hash': run.link(a['email'])}


# ── E-WD-05 같은 계정을 두 기기에 ───────────────────────────────────────────────────────────────────

def two_05(run, two):
    """A 계정으로 A폰 · B에뮬 둘 다 로그인 → A폰에서 탈퇴 → B 가 아무 탭이나 누르면 02 + 알림, 그 뒤 B 의 refresh token 도 거절.
    근거: account/router.py(logout scope=global) · student_verification/current_user.py(끊긴 세션 → 401) · core/http/http_send.dart(401 → refresh → 실패면 로그아웃)."""
    check = Check()
    a = _person(run, 'female')
    seen = {}

    def a_home(said, sync):
        sync.set('a-home')

    def b_login(said, sync):  # 1회용 토큰은 A 가 쓴 뒤에 받는다 — 먼저 받으면 A 의 것이 죽는다
        _after(sync, 'a-home', 'A')
        return {'token_hash': run.link(a['email'])}

    def b_home(said, sync):
        sync.set('b-home')

    def a_ready(said, sync):
        _after(sync, 'b-home', 'B')

    def cut():
        seen['cut'] = _sessions_cut(run, a)

    def b_tap(said, sync):
        _after(sync, 'a-out', 'A')
        return {'notice': EXPIRED if seen.get('cut', True) else WITHDRAWN}

    result, memo = two({('A', 'home'): a_home, ('B', 'login'): b_login, ('B', 'home'): b_home, ('A', 'ready'): a_ready,
                        ('A', 'withdrawn'): _out(run, check, a, cut), ('B', 'tap'): b_tap}, a_job=_a_job(run, a), **LIMITS)
    why = ('A 탈퇴가 로그인을 모두 끊어(GoTrue /user 거절) B 는 세션 만료 알림이 맞다' if seen.get('cut')
           else 'A 탈퇴 뒤에도 로그인이 살아 있어(logout 실패) B 는 탈퇴 알림이 맞다') if 'cut' in seen else '로그인이 끊겼는지 못 봄'
    return _verdict(check, result, memo, f'{why}(시나리오는 탈퇴 알림)')


# ── E-WD-06 채팅 상대 ───────────────────────────────────────────────────────────────────────────────

def _passed(run, match_id):
    """신뢰 확인을 통과한 방 — 두 사람 다 accept, 도장(trust_passed_at)까지."""
    stamp = datetime.now(timezone.utc).isoformat()
    _patch(run, f'match_participants?match_id=eq.{match_id}', {'trust_response': 'accept', 'responded_at': stamp})
    _patch(run, f'matches?id=eq.{match_id}', {'trust_passed_at': stamp})
    row = (_rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at') or [{}])[0]
    if not row.get('trust_passed_at'):
        raise Blocked('준비: 신뢰 확인 통과 도장이 안 찍힘 — 카톡 · 실사진 카드가 사라졌는지 볼 수 없다')


def two_06(run, two):
    """A 탈퇴 → B 가 그 방을 열면 입력칸 대신 나간 방 안내 + "채팅방 나가기", 예전 5건 그대로, 카톡 · 실사진 카드 없음.
    API 로 B 가 보내면 409 "상대가 대화를 나갔어요", match_participants.left_at 은 null 그대로(나가기 시스템 줄 0).
    근거: chat/gate.py is_gone · chat/router.py _guard_writable · chat_room_screen.dart _PartnerGoneNotice · TrustRevealBubble(isPartnerGone 이면 안 그림)."""
    check = Check()
    a, b = _pair(run)
    area2._guard(run, a['id'], b['id'])
    match_id = _match(run, a, b)
    _messages(run, match_id, a, 3)
    _messages(run, match_id, b, MESSAGES - 3)
    _passed(run, match_id)

    def room(said, sync):
        check.reply('API B 보내기', _api(run, 'POST', f'/chat/matches/{match_id}/messages', b['token'], {'body': 'E2E-WD-06'}, **_ONCE), 409,
                    detail=PARTNER_LEFT)
        left = [p for p in _rows(run, f'match_participants?match_id=eq.{match_id}&select=profile_id,left_at') if p.get('left_at')]
        check.that(not left, f'match_participants.left_at 이 찍힘 {len(left)}행(기대 0 — 탈퇴는 나가기가 아니다)')
        lines = [m for m in _rows(run, f'messages?match_id=eq.{match_id}&select=kind') if m.get('kind') != 'text']
        check.that(not lines, f'나가기 시스템 줄 {len(lines)}건(기대 0 — "OO님이 나갔어요" 가 생기면 안 된다)')
        count = _count(run, f'messages?match_id=eq.{match_id}')
        check.that(count == MESSAGES, f'messages {count}행(기대 {MESSAGES} 그대로)')

    result, memo = two({('A', 'withdrawn'): _out(run, check, a), ('B', 'wait'): _login_after_out(run, b), ('B', 'room'): room},
                       a_job=_a_job(run, a), b_job={'nickname': _nickname(run, a), 'count': MESSAGES}, **LIMITS)
    return _verdict(check, result, memo, '카톡 · 실사진 카드는 탈퇴 뒤 사라진 모습만 봄(통과 도장은 PC 가 준비)')


# ── E-WD-07 오늘 카드 · 받은 수락 ────────────────────────────────────────────────────────────────────

def _today_cards(run, account):
    status, body = _api(run, 'GET', '/cards/today', account['token'])[:2]
    if status != 200:
        raise Blocked(f'오늘 카드 읽기 {status}')
    return {row['card_id'] for row in (body or {}).get('cards', [])}


def two_07(run, two):
    """B 에게 A 를 대상으로 한 오늘 카드 1장 + A 가 B 카드를 수락해 B 수락함에 1건 → A 탈퇴 → B 오늘 탭 · 받은 수락에서 A 0, 카드 상세는 404.
    근거: cards/router.py(오늘 · 수락함 · 상세가 탈퇴 · 정지 상대를 뺀다 — 상세는 404 CARD_NOT_FOUND)."""
    check = Check()
    a, b = _pair(run)
    card = _card(run, b, a)  # B 의 오늘 카드, 대상 A
    _accepted(run, a, b)  # A 가 B 를 수락 → B 수락함에 A
    if card not in _today_cards(run, b) or a['id'] not in _inbox(run, b):
        raise Blocked('준비: 탈퇴 전 B 의 오늘 카드 · 수락함에 A 가 없다 — "빠졌다" 가 증거가 못 된다')

    def gone():
        check.that(card not in _today_cards(run, b), 'A 탈퇴 뒤에도 B 의 오늘 카드(API)에 A 카드가 남음')
        check.that(a['id'] not in _inbox(run, b), 'A 탈퇴 뒤에도 B 의 받은 수락(API)에 A 가 남음')
        check.reply('API B 가 그 카드 상세', _api(run, 'GET', f'/cards/{card}', b['token']), 404, detail=CARD_GONE)

    result, memo = two({('A', 'withdrawn'): _out(run, check, a, gone), ('B', 'wait'): _login_after_out(run, b)},
                       a_job=_a_job(run, a), b_job={'nickname': _nickname(run, a)}, **LIMITS)
    return _verdict(check, result, memo, 'B 의 "새로고침" 은 A 탈퇴 뒤 새 로그인(목록은 처음 읽을 때 굳는다)')


# ── E-WD-08 새 카드 후보 ────────────────────────────────────────────────────────────────────────────

def _region(run):
    """시험 지역 — 관문(daily-cards)을 먼저 본다(금지 시각이면 계정을 만들기 전에 blocked)."""
    return area2_time_batch._prepare(run)


def _issue_cards(run, region, control):
    """daily-cards 한 번 — 시험 지역 설정을 매일 칸으로 맞추고, 대조군이 카드를 받을 때까지(설정은 끝나면 원복)."""
    area2_time_batch._issue(run, region, list(EVERY_DAY), control=control)


def two_08(run, two):
    """A 탈퇴 → 배치 → B 의 새 무료 카드에 A 0장, B 의 후보에도 A 가 없다(후보 SQL c.status='active').
    근거: supabase/migrations/20260928050000_add_university_card_opens_at.sql match_candidates."""
    region = _region(run)
    check = Check()
    a, b = _pair(run)
    control = _person(run, 'female')  # B 와 같은 지역의 여자 — 배치가 돌았다는 증거(후보 B 가 있어 반드시 카드를 받는다)
    if a['id'] not in _candidates(run, b):
        raise Blocked('준비: 탈퇴 전 B 의 후보에 A 가 없다 — "빠졌다" 가 증거가 못 된다')

    def batch():
        check.that(a['id'] not in _candidates(run, b), 'A 탈퇴 뒤에도 B 의 후보에 A 가 있음')
        _issue_cards(run, region, [control])
        mine = [row for row in area2_time_batch._cards(run, b) if row['target_id'] == a['id']]
        check.that(not mine, f'배치 뒤 B 의 무료 카드 중 A 대상 {len(mine)}장(기대 0)')

    result, memo = two({('A', 'withdrawn'): _out(run, check, a, batch), ('B', 'wait'): _login_after_out(run, b)},
                       a_job=_a_job(run, a), b_job={'nickname': _nickname(run, a)}, **BATCH_LIMITS)
    return _verdict(check, result, memo, '응답 no_candidate 는 gcloud 라 못 읽음 — B 후보 · 카드 행으로 봄(대조군이 카드를 받아 배치가 돈 것을 확인)')


# ── E-WD-09 내가 쓴 리뷰 ─────────────────────────────────────────────────────────────────────────────

def _written(run, account):
    status, body = _api(run, 'GET', '/friend-reviews/written', account['token'])[:2]
    if status != 200:
        raise Blocked(f'내가 쓴 리뷰 읽기 {status}')
    return [row['reviewee']['nickname'] for row in (body or {}).get('reviews', [])]


def two_09(run, two):
    """B 가 A 에게 리뷰 1건 → A 탈퇴 → B 의 20e("내가 쓴 리뷰")에 A 줄 0. 근거: friend_reviews/repository.py fetch_written(reviewee.status neq withdrawn)."""
    check = Check()
    a, b = _pair(run)
    area2._guard(run, a['id'], b['id'])
    _review(run, b, a)
    nick = _nickname(run, a)
    if nick not in _written(run, b):
        raise Blocked('준비: 탈퇴 전 B 의 내가 쓴 리뷰에 A 줄이 없다 — "사라졌다" 가 증거가 못 된다')

    def gone():
        check.that(nick not in _written(run, b), 'A 탈퇴 뒤에도 B 의 20e(API GET /friend-reviews/written)에 A 줄이 남음')

    result, memo = two({('A', 'withdrawn'): _out(run, check, a, gone), ('B', 'wait'): _login_after_out(run, b)},
                       a_job=_a_job(run, a), b_job={'nickname': nick}, **LIMITS)
    return _verdict(check, result, memo, '리뷰는 PC 가 DB 로 넣음(추천 연결 없이)')


# ── 등록 · 묶음 ─────────────────────────────────────────────────────────────────────────────────────

CASES = {'E-WD-05': two_05, 'E-WD-06': two_06, 'E-WD-07': two_07, 'E-WD-08': _single_shot(two_08, always=True), 'E-WD-09': two_09}


def _guarded(hypothesis):
    """준비가 안 되면 blocked, 예상 밖 예외도 blocked — area2.attempt_with 와 같은 규칙. 탈퇴는 되돌릴 수 없어 계정은 시도마다 새로 만든다."""
    return lambda run, two: area2.attempt_with(run, lambda run: hypothesis(run, two))


TWO = {case: _guarded(hypothesis) for case, hypothesis in CASES.items()}

twodev.TWO.update(TWO)
area1.BUNDLES['area5-two'] = list(CASES)
for _case in CASES:
    tools.CASE_LIMITS[_case] = CASE_LIMIT
