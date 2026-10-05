"""영역 2 두 기기(폰 A + 에뮬 B) 카드 수락 6개 — E-CARD-33 · 42 · 47 · 49 · 85 · 87(묶음 area2-two-accept).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이되, 코드가 다르면 코드가 기준이다. 앱 쪽은 frontend/integration_test/area2_two_accept.dart 의
같은 번호(`번호/A` · `번호/B`). 돌릴 때: A폰 + B에뮬을 둘 다 연결하고 `python -m e2e run area2-two-accept`(두 기기 가설은 늘 A=폰 · B=에뮬).

가설 하나 = `(run, two) -> (결과, 메모)`. 계정 · 카드 · 서버 상태는 PC 가 준비하고 화면 판정은 앱이 한다. 두 기기를 잇는 순서는 twodev.Sync 이름표다 —
"A 가 누른다 → PC 가 DB 를 본다(a-rejected) → B 가 로그인해 수락함을 연다" 처럼 한쪽이 끝나야 다른 쪽이 움직인다.

수락함 · 대화 목록은 앱이 처음 읽을 때의 서버 상태로 굳는다(provider 는 로그아웃 때만 비워진다 — core/auth/session_scope.dart · 푸시를 받아야 새로 읽는다).
그래서 서버 쪽 일이 끝난 뒤의 모습을 보는 기기는 로그아웃한 채 기다렸다가 PC 가 go 에 실어 준 새 토큰으로 로그인한다. 1회용 토큰은 같은 계정이 새로 받으면
앞 것이 죽으므로(area3_safe_phone) 늦게 쓸 토큰은 그때 받는다.

PC 가 직접 본 어긋남은 [Check] 에 모아 두 기기 결과와 합친다 — 앱 쪽이 막혀 있어도 PC 가 찾은 어긋남은 확정된 fail 이다.
푸시 알림은 이번 묶음이 아니다(마지막 묶음) — 42 "B 60초 알림 0" · 49 "A 알림 0" · 85 "알림 1건" · 87 "알림 A 1 · B 1" 의 알림 쪽은 안 보고 메모에 밝힌다.
쓰기는 이번 실행이 만든 계정(area2._guard)에만 — 학교 설정 · 하루 한도 · 사다리 · 배치는 건드리지 않는다(바꾸는 것은 앱이 B 계정의 "매칭 활성화" 하나뿐).
"""

import time

from e2e import area1, area2, tools, twodev
from e2e.area1 import Check, _api, _detail, _one, _rows
from e2e.area2 import _ONCE, _candidates, _card, _person
from e2e.area3_safe import _inbox, _issue_owner
from e2e.tools import Blocked

POLL = 1  # 앱이 서버에 남긴 것을 다시 읽기까지(초)
SAVED = 30  # 앱이 누른 것이 서버에 저장되기를 기다리는 상한(초)
PEER = 420  # 상대 기기가 일을 끝내기를 기다리는 상한(초) — 에뮬이 느려도 넉넉히
CASE_LIMIT = 1200  # 가설 하나 상한(초) — 계정 둘 준비 + 두 기기(tools.CASE_LIMITS)
LIMITS = {'side_timeout': {'A': 180, 'B': 240}, 'deadline': 720}  # 다음 말까지 기다리는 시간 · 전체 상한(twodev.two)
NOTIFY = '알림 확인은 알림 줄 묶음 몫(여기는 DB · 화면만)'


# ── 읽기 · 기다리기 ─────────────────────────────────────────────────────────────────────────────────

def _until(read, seconds=None):
    """[read] 가 참 값을 돌려줄 때까지 [seconds](기본 SAVED)초 — 시간이 끝나면 마지막으로 읽은 값."""
    deadline = time.monotonic() + (SAVED if seconds is None else seconds)
    while True:
        got = read()
        if got or time.monotonic() >= deadline:
            return got
        time.sleep(POLL)


def _after(sync, name, who):
    """상대 기기가 [name] 을 세울 때까지 — 안 서면 이 가설은 막힌 것(상대가 먼저 실패하면 twodev.Aborted 로 풀린다)."""
    if not sync.wait(name, PEER):
        raise Blocked(f'{who} 가 {PEER}초 안에 끝내지 않음')


def _decisions(run, card):
    return [r['decision'] for r in _rows(run, f'card_decisions?card_id=eq.{card}&select=decision')]


def _responses(run, card):
    return [r['decision'] for r in _rows(run, f'acceptance_responses?card_id=eq.{card}&select=decision')]


def _rooms(run, x, y):
    low, high = sorted((x['id'], y['id']))  # matches_pair_order check(profile_a < profile_b)
    return _rows(run, f'matches?profile_a=eq.{low}&profile_b=eq.{high}&select=id')


def _members(run, room):
    return _rows(run, f'match_participants?match_id=eq.{room}&select=profile_id')


def _paused(run, account):
    return _one(run, f"profiles?id=eq.{account['id']}&select=matching_paused").get('matching_paused')


def _nickname(run, account):
    nickname = _one(run, f"profiles?id=eq.{account['id']}&select=nickname").get('nickname')
    if not nickname:
        raise Blocked('준비: 닉네임을 못 읽음')
    return nickname


# ── 준비 ────────────────────────────────────────────────────────────────────────────────────────────

def _pair(run):
    """A(남 · 폰) · B(여 · 에뮬) — 서로 후보인 한 쌍(홈 계정 + 벡터)."""
    return _person(run, 'male'), _person(run, 'female')


def _accepted(run, owner, target):
    """[owner] 가 [target] 에게 낸 카드를 수락한 상태 → 카드 id. 수락은 앱이 누르는 것과 같은 API 이고 다시 보내지 않는다(결정은 한 번)."""
    card = _card(run, owner, target)
    reply = _api(run, 'POST', f'/cards/{card}/decision', owner['token'], {'decision': 'accept'}, **_ONCE)
    if reply[0] != 200:
        raise Blocked(f'준비: 카드 수락 {reply[0]} {_detail(reply[1])}')
    return card


def _verdict(check, result, memo, *notes):
    """두 기기 결과([memo])에 PC 가 직접 본 어긋남을 합친다 — PC 가 찾은 것은 앱이 막혔어도(blocked) 확정된 fail 이다."""
    if check.problems:
        return 'fail', '; '.join(check.problems) + f' [{memo}]'
    return result, ' | '.join([memo, *notes]) if result == 'pass' else memo


# ── 33 일시중지 ─────────────────────────────────────────────────────────────────────────────────────

def two_33(run, two):
    """B 가 16 에서 "매칭 활성화" 를 끄면 A 의 후보에서도 카드 대상에서도 빠지고, 앱을 다시 켜 16 을 열어도 꺼짐 그대로, 다시 켜면 돌아온다.
    근거: GET /cards/matching-paused(cards/router.py:317-320) · 후보 SQL `not c.matching_paused` · card_issue_owners `not p.matching_paused`
    (20260928050000_add_university_card_opens_at.sql). "B 카드 0" 은 배치를 부르지 않고 배치가 고르는 대상 함수로 본다.
    "앱을 다시 켠다" 는 프로세스 재시작이 아니라 로그아웃 → 로그인(상태 저장소가 새로 만들어져 서버 값을 처음부터 다시 읽는다)."""
    check = Check()
    a, b = _pair(run)
    if b['id'] not in _candidates(run, a):  # 끄기 전에 후보가 아니면 "빠졌다" 가 아무것도 증명하지 못한다
        raise Blocked('준비가 틀림: 끄기 전에 B 가 A 의 후보가 아님')
    if not _issue_owner(run, b):
        raise Blocked('준비가 틀림: 끄기 전에 B 가 카드 대상(card_issue_owners)이 아님')

    def off(said, sync):
        check.that(_until(lambda: _paused(run, b) is True), 'B 가 끈 스위치가 서버(matching_paused)에 저장되지 않음')
        check.that(b['id'] not in _candidates(run, a), 'B 가 끈 뒤에도 A 의 후보에 있음')
        check.that(not _issue_owner(run, b), 'B 가 끈 뒤에도 카드 대상(card_issue_owners)임')
        return {'token_hash': run.link(b['email'])}

    def on(said, sync):
        check.that(_until(lambda: _paused(run, b) is False), 'B 가 다시 켠 스위치가 서버(matching_paused)에 저장되지 않음')
        check.that(b['id'] in _candidates(run, a), 'B 가 다시 켠 뒤에도 A 의 후보에 없음')
        check.that(_issue_owner(run, b), 'B 가 다시 켠 뒤에도 카드 대상(card_issue_owners)이 아님')

    result, memo = two({('B', 'paused'): off, ('B', 'resumed'): on},
                       a_job={'token_hash': run.link(a['email'])}, b_job={'token_hash': run.link(b['email'])}, **LIMITS)
    return _verdict(check, result, memo, '카드 0 은 배치를 부르지 않고 배치의 대상 함수(card_issue_owners)로 봄 · "앱을 다시 켬" 은 로그아웃 → 로그인')


# ── 42 거절은 조용하다 ──────────────────────────────────────────────────────────────────────────────

def two_42(run, two):
    """A 가 B 카드를 거절하면 card_decisions 는 reject 한 행이고 B 수락함에는 줄이 안 생긴다(알림 쪽은 알림 줄).
    근거: backend/app/cards/router.py:199-206(수락일 때만 notify) · 수락함은 accept 결정만 읽는다(repository.py fetch_pending_acceptances)."""
    check = Check()
    a, b = _pair(run)
    card = _card(run, a, b)

    def rejected(said, sync):
        check.that(_until(lambda: _decisions(run, card)), 'A 의 거절이 서버(card_decisions)에 저장되지 않음')
        got = _decisions(run, card)
        check.that(got == ['reject'], f'card_decisions {got}(기대 [reject])')
        check.that(not _inbox(run, b), 'B 수락함에 줄이 생김(거절은 조용해야 함)')
        sync.set('a-rejected')

    def wait(said, sync):
        _after(sync, 'a-rejected', 'A')
        return {'token_hash': run.link(b['email'])}

    result, memo = two({('A', 'rejected'): rejected, ('B', 'wait'): wait}, a_job={'token_hash': run.link(a['email'])}, **LIMITS)
    return _verdict(check, result, memo, f'B 60초 알림 0 은 안 봄 — {NOTIFY}')


# ── 47 매칭 뒤 대화 탭 ──────────────────────────────────────────────────────────────────────────────

def two_47(run, two):
    """A 가 수락한 카드를 B 가 수락함에서 받아 매칭되면 방이 한 개(참가자 둘)이고, 두 기기 대화 탭 "대화 중" 에 서로가 한 줄씩 있고 방에 미리 수락 배너가 하나다.
    근거: cards/router.py:261-274 · conversations_screen.dart:118(대화 중) · chat_room_screen.dart:385(배너). A 는 방이 생긴 뒤 로그인한다 —
    'match' 푸시는 수락함만 새로 읽고 대화 목록은 안 읽어(main.dart:154-158) 켜 둔 앱은 새 방이 안 보일 수 있다(그 부분은 이 가설이 안 본다)."""
    check = Check()
    a, b = _pair(run)
    _accepted(run, a, b)  # E-CARD-45 직전의 모습 — B 수락함에 A 한 줄
    nick_a, nick_b = _nickname(run, a), _nickname(run, b)

    def matched(said, sync):
        rooms = _until(lambda: _rooms(run, a, b))
        check.that(len(rooms) == 1, f'matches {len(rooms)}행(기대 1)')
        if rooms:
            members = _members(run, rooms[0]['id'])
            check.that(len(members) == 2, f'match_participants {len(members)}행(기대 2)')
        sync.set('b-matched')

    def open_(said, sync):
        _after(sync, 'b-matched', 'B')
        return {'token_hash': run.link(a['email'])}

    result, memo = two({('B', 'matched'): matched, ('A', 'open'): open_}, a_job={'nickname': nick_b},
                       b_job={'token_hash': run.link(b['email']), 'nickname': nick_a}, **LIMITS)
    return _verdict(check, result, memo, 'A 는 매칭 뒤 로그인 — 켜 둔 앱이 매칭 푸시를 받는 경로는 안 봄')


# ── 49 수락함에서 거절 ──────────────────────────────────────────────────────────────────────────────

def two_49(run, two):
    """B 가 수락함에서 거절하면 acceptance_responses 는 reject 한 행, 매칭 없음, B 수락함에서 줄이 사라지고, A 의 대화 탭에는 아무것도 안 생긴다(알림 쪽은 알림 줄).
    근거: cards/router.py:257-259(거절이면 {matched: false}, 알림 없음) · fetch_pending_acceptances(응답 있는 카드는 뺀다)."""
    check = Check()
    a, b = _pair(run)
    card = _accepted(run, a, b)  # E-CARD-41 상태 — B 수락함에 A 한 줄
    nick_a = _nickname(run, a)

    def rejected(said, sync):
        check.that(_until(lambda: _responses(run, card)), 'B 의 거절이 서버(acceptance_responses)에 저장되지 않음')
        got = _responses(run, card)
        check.that(got == ['reject'], f'acceptance_responses {got}(기대 [reject])')
        check.that(not _rooms(run, a, b), '거절했는데 matches 가 생김')
        check.that(not _inbox(run, b), 'B 수락함에서 그 줄이 안 사라짐')
        sync.set('b-rejected')

    def wait(said, sync):
        _after(sync, 'b-rejected', 'B')
        return {'token_hash': run.link(a['email'])}

    result, memo = two({('B', 'rejected'): rejected, ('A', 'wait'): wait},
                       b_job={'token_hash': run.link(b['email']), 'nickname': nick_a}, **LIMITS)
    return _verdict(check, result, memo, f'응답 matched=false 는 앱이 받은 값이라 DB(reject · matches 0)로 대신 봄 · A 알림 0 은 안 봄 — {NOTIFY}')


# ── 85 수락 연타 ────────────────────────────────────────────────────────────────────────────────────

def two_85(run, two):
    """A 가 "수락하기" 를 0.1초 간격으로 두 번 눌러도 card_decisions 는 accept 한 행이고 B 수락함에 A 가 한 줄이다(알림 쪽은 알림 줄).
    근거: card_detail_view_model.dart:38-43(처리 중 · 결정 뒤 다시 누름 무시). 서버도 PK · 409 로 막으므로 DB 로는 앱이 두 번 보냈는지 못 가린다 —
    앱은 두 번째 눌림이 닿았는지(너무 빨리 끝나 못 닿았으면 blocked)와 화면이 정상으로 돌아왔는지를 본다."""
    check = Check()
    a, b = _pair(run)
    card = _card(run, a, b)
    nick_a = _nickname(run, a)

    def accepted(said, sync):
        check.that(_until(lambda: _decisions(run, card)), 'A 의 수락이 서버(card_decisions)에 저장되지 않음')
        got = _decisions(run, card)
        check.that(got == ['accept'], f'card_decisions {len(got)}행 {got}(기대 accept 1행)')
        inbox = _inbox(run, b)
        check.that(inbox == {a['id']}, f'B 수락함 {len(inbox)}명(기대 A 한 명)')
        sync.set('a-accepted')

    def wait(said, sync):
        _after(sync, 'a-accepted', 'A')
        return {'token_hash': run.link(b['email'])}

    result, memo = two({('A', 'accepted'): accepted, ('B', 'wait'): wait},
                       a_job={'token_hash': run.link(a['email'])}, b_job={'nickname': nick_a}, **LIMITS)
    return _verdict(check, result, memo, f'화면의 중복 전송 방어 둘(버튼 비활성화 · VM 가드) 중 하나만 있어도 통과함 — 실제 두 번 보냈는지는 서버 로그 몫 · B 알림 1건은 안 봄 — {NOTIFY}')


# ── 87 이미 매칭된 사람 ─────────────────────────────────────────────────────────────────────────────

def two_87(run, two):
    """A→B · B→A 카드를 둘 다 수락하고 A 가 수락함에서 수락해 매칭되면 B 수락함에서 A 줄이 빠지고(이미 매칭된 사람은 안 나옴), 남은 카드(A→B)에
    B 가 API 로 응답해도 같은 방(match_id 같음 · matches 한 행)이다(알림 쪽은 알림 줄). 근거: cards/router.py:219-223 · repository.py fetch_match_partner_ids ·
    create_match(on conflict do nothing → is_new false 면 알림 안 보냄, router.py:264-273)."""
    check = Check()
    a, b = _pair(run)
    card_ab = _accepted(run, a, b)  # A→B 를 A 가 수락 → B 수락함에 A
    card_ba = _accepted(run, b, a)  # B→A 를 B 가 수락 → A 수락함에 B
    nick_a, nick_b = _nickname(run, a), _nickname(run, b)

    def matched(said, sync):
        check.that(_until(lambda: _responses(run, card_ba)), 'A 의 수락 응답이 서버(acceptance_responses)에 저장되지 않음')
        rooms = _until(lambda: _rooms(run, a, b))
        check.that(len(rooms) == 1, f'A 가 수락한 뒤 matches {len(rooms)}행(기대 1)')
        check.that(not _inbox(run, b), '매칭된 뒤에도 B 수락함에 A 줄이 남음(이미 매칭된 사람은 목록에 안 나와야 함)')
        sync.set('a-matched')

    def wait(said, sync):
        _after(sync, 'a-matched', 'A')
        return {'token_hash': run.link(b['email'])}

    def opened(said, sync):
        before = _rooms(run, a, b)
        reply = _api(run, 'POST', f'/cards/acceptances/{card_ab}', b['token'], {'decision': 'accept'}, **_ONCE)
        check.reply('남은 카드에 API 응답(B)', reply, 200)
        got = reply[1] if isinstance(reply[1], dict) else {}
        rooms = _rooms(run, a, b)
        check.that(len(rooms) == 1, f'늦은 응답 뒤 matches {len(rooms)}행(기대 1 — 같은 방)')
        known = before[0]['id'] if before else None
        check.that(known is not None and got.get('match_id') == known, f'응답 match_id {got.get("match_id")} 가 기존 방 {known} 과 다름')
        check.that(not _inbox(run, a) and not _inbox(run, b), '늦은 응답 뒤에도 수락함에 줄이 남음')

    result, memo = two({('A', 'matched'): matched, ('B', 'wait'): wait, ('B', 'opened'): opened},
                       a_job={'token_hash': run.link(a['email']), 'nickname': nick_b}, b_job={'nickname': nick_a}, **LIMITS)
    return _verdict(check, result, memo, f'알림 A 1 · B 1(총 2) 은 안 봄 — {NOTIFY}')


# ── 등록 · 묶음 ─────────────────────────────────────────────────────────────────────────────────────

CASES = {'E-CARD-33': two_33, 'E-CARD-42': two_42, 'E-CARD-47': two_47, 'E-CARD-49': two_49, 'E-CARD-85': two_85,
         'E-CARD-87': two_87}


def _guarded(hypothesis):
    """준비가 안 되면 blocked, 연결 끊김은 처음부터 한 번 더(계정은 매번 새로 만든다), 예상 밖 예외도 blocked — area2.attempt_with 와 같은 규칙."""
    return lambda run, two: area2.attempt_with(run, lambda run: hypothesis(run, two))


TWO = {case: _guarded(hypothesis) for case, hypothesis in CASES.items()}

twodev.TWO.update(TWO)
area1.BUNDLES['area2-two-accept'] = list(CASES)
for _case in CASES:
    tools.CASE_LIMITS[_case] = CASE_LIMIT
