"""영역 2 B에뮬 단독 가설 11 — 수락함 3(CARD-41 · 45 · 86) · 투표 5(POLL-02 · 04 · 05 · 06 · 28) · 추천 코드 3(REF-07 · 08 · 17).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area2_emu_b.dart 의 같은 번호.

`python -m e2e run area2-emu-b --device B`. 계정은 `run.account('home')`(온보딩 끝 · active)이고 판정은 앱이 하며 DB · 서버 값은 여기서 본다.
폰 계정은 B(앱을 켠다), 상대 · 글쓴이 · 투표자는 API 로 움직이는 새 계정이다. 쓰기는 이번 실행이 만든 계정 id 에만(area2._guard).
실폰(--device A)에서는 전부 blocked — 계정도 만들기 전에 막는다. 비멱등 호출(수락 · 투표 · 글 올리기)은 끊겨도 다시 보내지 않는다(area2._ONCE).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-POLL-02          "다른 기기" 를 API 계정으로 — 글을 올리는 쪽(A)은 익명이라 서버에는 다른 계정이 올린 글일 뿐이다. 앱은 B 한 대(당기는 쪽)다.
                     피드가 비면 당겨서 새로 고침 자리(RefreshIndicator)가 없어(community_feed_screen.dart _body) 바탕 글 한 개를 먼저 올려 둔다.
  E-POLL-06          "E-POLL-05 직후" 상태 = B 가 API 로 먼저 한 번 투표해 하트를 받은 날. 앱의 첫 투표 토스트에 기대지 않는다.
  E-POLL-28          "이번 주 원장 2건" 은 grant_hearts(poll_vote)로 넣는다(하루 한 번이라 진짜 투표로는 2건을 못 만든다 — E-HEART-21 과 같다).
  E-CARD-41          알림이 안 오는 에뮬(FCM 토큰 · 알림 없음)이면 blocked. 알림 도착 자체는 E-CARD-40 이 판정한다.
  E-REF-07 · 08 · 17 영역 1 의 E-ONB-62 · 64 · 70 · 71 과 같은 화면 동작이라 그 앱 쪽을 그대로 쓴다(에뮬에서만 돈다는 점만 다르다).
"""

import functools
import random
import time
from datetime import datetime

from e2e import area1, area1_b2, notify
from e2e.area1 import SEOUL, Check, _api, _app, _detail, _one, _rows, _signed_in
from e2e.area1_emu import _emulator
from e2e.area2 import _ONCE, _card, _grant, _home, _ledger, _poll, _set_status
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area2_phone_b import PREFIX, _balance, _cleaned
from e2e.area3_phone import _ok
from e2e.tools import Blocked

ACCEPT_TITLE = '나를 수락한 사람이 있어요'  # backend cards/router.py decide_card
ACCEPT_NOT_FOUND = '수락을 찾을 수 없어요'  # backend core/errors.py ACCEPTANCE_NOT_FOUND
TOKEN_WAIT = 30  # 기기 토큰이 서버에 올라오기를 기다리는 초(area2_phone3 p_card_02 와 같다)
NOTICE_WAIT = 30  # 수락 알림이 오기를 기다리는 초(시나리오 E-CARD-40 의 "30초 안")


def _on_emulator(case):
    """에뮬이 아니면 계정도 만들기 전에 blocked. 에뮬이면 알림 권한을 미리 준다(첫 로그인의 권한 창이 가설 도중 앱을 가리지 않게)."""
    @functools.wraps(case)
    def wrapped(run, phone):
        _emulator(phone)
        return case(run, phone)
    return wrapped


# ── 수락함 3 ────────────────────────────────────────────────────────────────────────────────────────

def _nickname(run, account):
    return _one(run, f"profiles?id=eq.{account['id']}&select=nickname").get('nickname') or ''


def _senders_card(run):
    """A(수락을 보낼 API 계정) · B(앱을 켤 폰 계정) · A 가 주인이고 B 가 대상인 카드 → (A, B, A 의 닉네임, B 가 로그인할 토큰, 카드 id)."""
    a, b = _home(run), _home(run)
    return a, b, _nickname(run, a), run.link(b['email']), _card(run, a, b)


def _accept(run, a, card):
    _ok('A 의 수락', _api(run, 'POST', f'/cards/{card}/decision', a['token'], {'decision': 'accept'}, **_ONCE))


def _matches(run, a, b):
    """A · B 사이의 매칭 행 id — matches 는 profile_a < profile_b 로만 저장된다(matches_pair_order)."""
    low, high = sorted((a['id'], b['id']))
    return [r['id'] for r in _rows(run, f'matches?profile_a=eq.{low}&profile_b=eq.{high}&select=id')]


def p_card_41(run, phone):
    """B 앱을 홈에 켜 둔 채 HOME → A 가 카드를 수락 → B 의 알림을 눌러 대화 탭이 열린다(앱이 "수락 대기 1명" · A 줄 · 두 버튼을 본다).
    acceptance_received 는 조용한 시간에 아침으로 보류되므로(push.py _DEFERRED) 낮 08~22시에만."""
    notify.require_daytime()
    check = Check()
    a, b, nickname, token, card = _senders_card(run)
    body = f'{nickname} 님이 대화를 하고 싶어 해요'  # decide_card 의 알림 본문

    def accept_and_tap(said):
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{b['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 이 에뮬이 FCM 토큰을 못 받는다(구글 로그인 · Play 서비스가 없는 이미지는 알림이 안 온다)')
        before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다(시나리오 G4)
        _accept(run, a, card)
        new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == (ACCEPT_TITLE, body))
        if not any((n.title, n.text) == (ACCEPT_TITLE, body) for n in new):
            raise Blocked(f'{NOTICE_WAIT}초 안에 알림 "{ACCEPT_TITLE} / {body}" 이 안 옴(새 알림 {len(new)}건: {notice_memo(new)}) — '
                          '알림 도착은 E-CARD-40 이 판정한다, 누를 알림이 없어 41 은 못 본다')
        # 제목이 아니라 본문(A 의 닉네임이 든 글)으로 누른다 — 앞 실행이 남긴 같은 제목 알림을 누르지 않게
        notify.tap_notification(phone.serial, body)
        time.sleep(1)

    _app(check, phone(midway=accept_and_tap, token_hash=token, nickname=nickname))
    return check.result()


def p_card_45(run, phone):
    """B 가 대화 탭의 수락함에서 "수락하고 대화 시작" → 12 화면. 매칭 1행 · 당사자 2행은 여기서 본다(앱은 푸시를 안 쓴다 — A 의 수락은 앱을 켜기 전에 이미 있다)."""
    check = Check()
    a, b, nickname, token, card = _senders_card(run)
    _accept(run, a, card)
    _app(check, phone(token_hash=token, nickname=nickname))
    matches = _matches(run, a, b)
    check.that(len(matches) == 1, f'matches {len(matches)}행(기대 1)')
    if matches:
        people = sorted(r['profile_id'] for r in _rows(run, f'match_participants?match_id=eq.{matches[0]}&select=profile_id'))
        check.that(people == sorted((a['id'], b['id'])), f'match_participants {people}(기대 A · B 두 행)')
    return check.result()


def p_card_86(run, phone):
    """수락 대기를 띄운 뒤 A 를 정지 → "수락하고 대화 시작" → "수락을 찾을 수 없어요". 차단 · 자동 가림도 서버는 같은 판정(_hidden_from_cards)이라 정지만 본다."""
    check = Check()
    a, b, nickname, token, card = _senders_card(run)
    _accept(run, a, card)
    _app(check, phone(midway=lambda said: _set_status(run, a, 'suspended'), token_hash=token, nickname=nickname))
    check.that(not _matches(run, a, b), 'matches 에 행이 생김(정지한 사람의 수락으로 매칭이 만들어짐)')
    check.that(not _rows(run, f'acceptance_responses?card_id=eq.{card}&select=card_id'), 'acceptance_responses 에 행이 생김')
    inbox = _api(run, 'GET', '/cards/acceptances', b['token'])
    check.that(inbox[0] == 200 and not (inbox[1] or {}).get('acceptances'), f'정지한 뒤에도 수락함 목록에 남음 {inbox}')
    check.reply('수락 응답(API)', _api(run, 'POST', f'/cards/acceptances/{card}', b['token'], {'decision': 'accept'}, **_ONCE), 404, ACCEPT_NOT_FOUND)
    return check.result()


# ── 투표 5 ──────────────────────────────────────────────────────────────────────────────────────────
# 투표 글은 피드에 실사용자에게도 보여(시나리오 ⚠6) 가설이 끝나면 — 앱이 막혀도 — 글쓴이가 지운다(area2_phone_b._cleaned).

def _post(run, author, text):
    """[E2E] 글 하나를 API 로 올린다 → (글 id, 화면에 보일 질문). 같은 글이 겹치지 않게 끝에 숫자를 붙인다."""
    text = f'{text} {random.randint(1000, 9999)}'
    return _poll(run, author, text), f'{PREFIX}{text}'


def _vote(run, who, poll, choice='a'):
    return _api(run, 'POST', f'/community/polls/{poll}/votes', who['token'], {'choice': choice}, **_ONCE)


def _seoul_today():
    return datetime.now(SEOUL).date()


def _vote_hearts(run, account):
    """이 계정의 poll_vote 원장 → [(금액, ref_id)]."""
    return [(r['amount'], r['ref_id']) for r in _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.poll_vote&select=amount,ref_id")]


def p_poll_02(run, phone):
    """바탕 글(피드가 비면 당겨서 새로 고침 자리가 없다) 하나가 있는 피드를 B 가 연 채 멈춘 사이 다른 계정이 새 글을 올린다 → 새로 고침 전 0 → 당긴 뒤 1."""
    check = Check()
    author = _home(run)
    _, token = _signed_in(run, 'home')
    with _cleaned(run, author):
        _, anchor = _post(run, author, '피드 바탕')
        text = f'당겨서 새로 고침 {random.randint(1000, 9999)}'
        _app(check, phone(midway=lambda said: _poll(run, author, text), token_hash=token, anchor=anchor, question=f'{PREFIX}{text}'))
    return check.result()


def p_poll_04(run, phone):
    """V 가 찬성 1표를 던진 글 → B: 누르기 전 "찬성 100% · 반대 0% · 1명 참여", O 를 누르면 도넛 + "2명 참여". 두 표는 DB 에서 본다."""
    check = Check()
    author, voter = _home(run), _home(run)
    me, token = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _post(run, author, '결과 한 줄')
        _ok('V 의 찬성 표', _vote(run, voter, poll))
        _app(check, phone(token_hash=token, question=question))
        votes = {v['voter_id']: v['choice'] for v in _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id,choice')}
        check.that(votes == {voter['id']: 'a', me['id']: 'a'}, f'poll_votes {votes}(기대 V · B 둘 다 찬성)')
    return check.result()


def p_poll_05(run, phone):
    """B 의 오늘 poll_vote 원장 0(새 계정) → 아무 글에 투표 → 토스트 1(앱), 원장 +10(reason=poll_vote · ref=글 id) · 잔액 +10(여기)."""
    check = Check()
    author = _home(run)
    me, token = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _post(run, author, '첫 투표')
        before = _balance(run, me)
        _app(check, phone(token_hash=token, question=question))
        got = _vote_hearts(run, me)
        check.that(got == [(10, poll)], f'poll_vote 원장 {got}(기대 [(10, 글 id)])')
        check.that(_balance(run, me) == before + 10, f'잔액 {before} → {_balance(run, me)}(기대 +10)')
    return check.result()


def p_poll_06(run, phone):
    """B 가 API 로 먼저 한 글에 투표해 오늘 하트를 받은 뒤(= E-POLL-05 직후) 앱에서 다른 글에 투표 → 토스트 0(앱), 원장 · 잔액 그대로(여기)."""
    check = Check()
    author = _home(run)
    me, token = _signed_in(run, 'home')
    with _cleaned(run, author):
        first, _ = _post(run, author, '먼저 한 표')
        second, question = _post(run, author, '두 번째 표')
        today = _seoul_today()
        reply = _vote(run, me, first)
        if reply[0] != 200 or not (reply[1] or {}).get('rewarded'):
            raise Blocked(f'준비: 오늘 첫 투표(API)가 하트를 안 줌 {reply[0]} {_detail(reply[1])} — E-POLL-05 쪽 문제')
        ledger, balance = _vote_hearts(run, me), _balance(run, me)
        _app(check, phone(token_hash=token, question=question))
        if _seoul_today() != today:
            raise Blocked('시험 중 서울 자정을 넘겨 "같은 날 두 번째 투표" 가 아니다')
        check.that(_vote_hearts(run, me) == ledger, f'poll_vote 원장 {ledger} → {_vote_hearts(run, me)}(기대 변화 0)')
        check.that(_balance(run, me) == balance, f'잔액 {balance} → {_balance(run, me)}(기대 변화 0)')
        voted = _rows(run, f"poll_votes?poll_id=eq.{second}&voter_id=eq.{me['id']}&select=choice")
        check.that(len(voted) == 1, f'poll_votes {len(voted)}행(기대 1 — 앱이 두 번째 글에 투표하지 않았다)')
    return check.result()


def p_poll_28(run, phone):
    """이번 주 poll_vote 원장 2건 → 서버 18a 투표 줄 used 2 · open → 앱이 설정 → "무료로 하트 모으기" 에서 같은 값을 읽고 "참여"."""
    check = Check()
    me, token = _signed_in(run, 'home')
    for _ in range(2):
        status, body = _grant(run, me, 10, 'poll_vote')
        if status >= 300:
            raise Blocked(f'투표 적립 준비 {status} {body}')
    ledger = _ledger(run, me, 'poll_vote')
    reply = _api(run, 'GET', '/heart-tasks', me['token'])
    row = next((t for t in (reply[1] or {}).get('tasks', []) if t.get('task') == 'poll_vote'), {}) if reply[0] == 200 else {}
    got = (row.get('used'), row.get('state'), row.get('limit'))
    check.that(got == (len(ledger), 'open', 3), f'서버 18a 투표 줄 (used, state, limit) {got}(기대 ({len(ledger)}, open, 3) — 원장 {len(ledger)}건)')
    _app(check, phone(token_hash=token, used=len(ledger), limit=3))
    return check.result()


# ── 추천 코드 3 ─────────────────────────────────────────────────────────────────────────────────────

def p_ref_17(run, phone):
    """계정 하나로 20 → "건너뛰기" → 20d(앱이 그 뒤 06-4 · 홈까지 E-ONB-70 과 같이 간다) · 하트 0 · referrals 0,
    다른 계정으로 20 에 닿은 뒤 앱을 죽였다 다시 켜면 20 · 20d · 06-4 없이 홈(E-ONB-71 과 같다)."""
    check = Check()
    skipper, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token, phase='skip'), '건너뛰기')
    check.that(not area1_b2._hearts(run, skipper['id']), '건너뛰었는데 추천 하트가 생김')
    check.that(not _rows(run, f"referrals?referee_id=eq.{skipper['id']}&select=referrer_id"), '건너뛰었는데 referrals 가 생김')
    _, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token), '20 도착')
    _app(check, phone(fresh=False, expect='home'), '다시 켬')
    return check.result()


CASES = {
    'E-CARD-41': p_card_41, 'E-CARD-45': p_card_45, 'E-CARD-86': p_card_86,
    'E-POLL-02': p_poll_02, 'E-POLL-04': p_poll_04, 'E-POLL-05': p_poll_05, 'E-POLL-06': p_poll_06, 'E-POLL-28': p_poll_28,
    'E-REF-07': area1_b2.p_onb_62, 'E-REF-08': area1_b2.p_onb_64, 'E-REF-17': p_ref_17,
}
PHONE_B = {case: _on_emulator(run_case) for case, run_case in CASES.items()}

area1.PHONE.update(PHONE_B)
area1.BUNDLES['area2-emu-b'] = list(PHONE_B)
