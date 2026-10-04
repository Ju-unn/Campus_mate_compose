"""영역 3 폰 A 한 대 1차 — 채팅 · 지인 리뷰 중 화면을 읽기만 하는 19개(묶음 area3-phone-1).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본). 앱 쪽은 frontend/integration_test/area3.dart 의 같은 번호.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 계정(전부 홈까지) · 매칭 · 메시지 · 추천 연결 · 리뷰를 서비스 키와 API 로
준비하고, 앱은 화면에서 본 것(개수 · 순서 · 문구 · 버튼 유무)을 말한다 — 판정은 여기서 한다. 시나리오에서 B에뮬 판(받는 사람)도
폰 한 대로 돌린다: 폰 계정이 그 판의 B 가 된다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-REV-29 · 30  "B 방 → 머리말 → 14c" — 방 머리말은 눌리지 않고, 14c 로 가는 화면 길은 신뢰 확인을 통과한 방의 14b
                 "상대 프로필 보기" 뿐이다(chat_room_screen.dart:175-177 · 473-475). 앱이 라우터로 14c 를 바로 연다.
  E-CHAT-08      "A: 3건 보내고" — PC 가 폰 계정 토큰으로 같은 API 를 부른다(방을 열면 나갈 때 읽음이 찍혀 규칙이 가려진다).
  E-CHAT-19      "첫 응답 50건 · has_more=true, 두 번째 응답 0건" — 응답은 앱에서 못 본다. 위로 올려 다음 쪽을 부른 횟수
                 (뷰모델 isLoadingMore)와 화면 줄 수로 본다.
"""

from datetime import datetime, timezone

from e2e import area1, area3
from e2e.area1 import Check, _api, _app
from e2e.area3 import _count, _link, _match, _messages, _patch, _review, _review_post, _send
from e2e.tools import Blocked

ALREADY = '이미 리뷰를 남겼어요'  # friend_review_errors.dart _alreadyWritten · 서버 FRIEND_REVIEW_ALREADY_WRITTEN
EARLY_BANNER = '카카오톡 아이디를 먼저 공유해도 돼요'  # chat_room_screen.dart:385
THREE_TAGS = ['약속을 잘 지켜요', '대화가 편해요', '성실해요']  # 고른 순서(E-REV-02 판)
MISSING = '?'  # 앱이 그 값을 말하지 않음 — None(뱃지 없음 등)과 가른다


def _person(run):
    """홈까지 끝낸 계정. 닉네임을 정해 둔다 — 앱이 화면에서 그 이름으로 줄을 찾는다."""
    nickname = area1._nickname()
    return {**run.account('home', nickname=nickname), 'nickname': nickname}


def _me(run):
    """폰 계정과 앱이 로그인할 1회용 토큰."""
    me = _person(run)
    return me, run.link(me['email'])


def _ok(label, reply):
    if reply[0] >= 300:
        raise Blocked(f'{label} {reply[0]} {reply[1]}')


def _bodies(count):
    return {f'E2E-{i}' for i in range(count)}


def _left_line(person):
    return f"{person['nickname']}님이 채팅방을 나갔어요"  # chat/repository.py:183


# ── 채팅 ─────────────────────────────────────────────────────────────────────────────────────────────

def p_chat_06(run, phone):
    check = Check()
    me, token = _me(run)
    rooms = [(p, _match(run, me, p)) for p in [_person(run) for _ in range(3)]]
    for i in (2, 0):  # 방3 → 방1 순으로 한 건씩
        _ok(f'방{i + 1} 보내기', _send(run, me, rooms[i][1], f'E2E-방{i + 1}'))
    said = _app(check, phone(token_hash=token, nicknames=[p['nickname'] for p, _ in rooms]))
    want = [rooms[i][0]['nickname'] for i in (0, 2, 1)]
    check.that(said.get('order') == want, f"목록 순서 {said.get('order')}(기대 방1 · 방3 · 방2 {want})")
    return check.result()


def _badges(mine, count, badge):
    """[mine] 이면 폰 계정이 API 로 [count] 건, 아니면 상대가 DB 로 [count] 건 — 목록 줄 · 아래 탭 뱃지가 [badge](None = 없음)."""
    def case(run, phone):
        check = Check()
        me, token = _me(run)
        partner = _person(run)
        match_id = _match(run, me, partner)
        if mine:
            for i in range(count):
                _ok('보내기', _send(run, me, match_id, f'E2E-{i}'))
        else:
            _messages(run, match_id, partner, count)  # 폰 계정의 last_read_at 은 비어 있다 — 전부 안 읽음
        said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
        for key, label in (('row_badge', '목록 뱃지'), ('nav_badge', '아래 탭 뱃지')):
            check.that(said.get(key, MISSING) == badge, f'{label} {said.get(key, MISSING)!r}(기대 {badge!r})')
        return check.result()
    return case


def _paging(count, stages, requests, same_time=False):
    """한 방에 [count] 건을 심고 앱이 맨 위까지 올린다. 앱은 맨 위에 닿을 때마다 화면에 나온 서로 다른 줄 수(stages),
    다음 쪽을 부른 횟수(requests), 본 본문 전부(seen), 한 화면에 같은 본문이 겹친 수(overlap)를 말한다."""
    def case(run, phone):
        check = Check()
        me, token = _me(run)
        partner = _person(run)
        match_id = _match(run, me, partner)
        _messages(run, match_id, partner, count, at=datetime.now(timezone.utc) if same_time else None)
        said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
        check.that(said.get('stages') == stages, f"맨 위마다 줄 수 {said.get('stages')}(기대 {stages})")
        check.that(said.get('requests') == requests, f"다음 쪽 요청 {said.get('requests')}번(기대 {requests})")
        seen = set(said.get('seen') or [])
        missing, extra = _bodies(count) - seen, seen - _bodies(count)
        check.that(not missing and not extra, f'빠진 줄 {len(missing)} · 모르는 줄 {len(extra)}')
        check.that(said.get('overlap') == 0, f"겹친 줄 {said.get('overlap')}")
        return check.result()
    return case


def p_chat_36(run, phone):
    check = Check()
    me, token = _me(run)
    partner = _person(run)
    _match(run, me, partner)  # created_at = 지금(DB 기본값)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('banners') == [EARLY_BANNER], f"배너 {said.get('banners')}(기대 [{EARLY_BANNER}])")
    check.that(said.get('sheet') is False, f"14f 시트 {said.get('sheet', MISSING)}")
    return check.result()


def _partner_left(run):
    """폰 계정(B)과 상대(A)의 방에 상대가 3건 쓰고 나갔다(E-CHAT-58 뒤)."""
    me, token = _me(run)
    partner = _person(run)
    match_id = _match(run, me, partner)
    _messages(run, match_id, partner, 3)
    _ok('상대 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', partner['token']))
    return token, partner


def p_chat_60(run, phone):
    check = Check()
    token, partner = _partner_left(run)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('input') is False, f"입력창 {said.get('input', MISSING)}(기대 없음)")
    check.that(said.get('notice') is True, f"나감 안내 {said.get('notice', MISSING)}")
    check.that(said.get('leave_button') is True, f"채팅방 나가기 버튼 {said.get('leave_button', MISSING)}")
    check.that(set(said.get('bodies') or []) == _bodies(3), f"지난 대화 {said.get('bodies')}")
    check.that(said.get('system') == [_left_line(partner)], f"시스템 줄 {said.get('system')}")
    check.that(said.get('banners') == [] and said.get('sheet') is False,
               f"게이트 배너 {said.get('banners')} · 시트 {said.get('sheet', MISSING)}")
    return check.result()


def p_chat_62(run, phone):
    check = Check()
    token, partner = _partner_left(run)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('preview') == _left_line(partner), f"미리보기 {said.get('preview')!r}")
    return check.result()


# ── 지인 리뷰 ────────────────────────────────────────────────────────────────────────────────────────

def _refused(check, said, toast):
    """[20b 열기] 가 시트 대신 토스트로 끝났는가."""
    check.that(said.get('toast') == toast, f"토스트 {said.get('toast')!r}(기대 {toast!r})")
    check.that(said.get('form') is False, f"시트 {said.get('form', MISSING)}(기대 안 뜸)")


def p_rev_10(run, phone):
    check = Check()
    me, token = _me(run)
    b = _person(run)
    _link(run, me, b)
    _review(run, me, b)  # E-REV-01 뒤
    said = _app(check, phone(token_hash=token, profile_id=b['id']))
    _refused(check, said, ALREADY)
    rows = _count(run, f"friend_reviews?reviewer_id=eq.{me['id']}&reviewee_id=eq.{b['id']}")
    check.that(rows == 1, f'friend_reviews {rows}행(기대 1 그대로)')
    return check.result()


def p_rev_12(run, phone):
    check = Check()
    me, token = _me(run)
    c = _person(run)  # 추천 연결 없음
    said = _app(check, phone(token_hash=token, profile_id=c['id']))
    _refused(check, said, area3.PROFILE_GONE)
    check.reply('API 쓰기', _review_post(run, me, c), 404, area3.PROFILE_GONE)
    rows = _count(run, f"friend_reviews?reviewer_id=eq.{me['id']}")
    check.that(rows == 0, f'friend_reviews {rows}행')
    return check.result()


def _listed(check, said, cards, received):
    """20c(received) · 20e(written) 화면 — 카드(닉네임 · 태그 · 한마디), 안내, 빈 문구, 휴지통 · 깃발 · 기다리는 친구 칸."""
    got = said.get('cards')
    shown = [{k: c.get(k) for k in ('nickname', 'tags', 'comment')} for c in got or []]
    check.that(got is not None and shown == cards, f'카드 {shown}(기대 {cards})')
    check.that(all(c.get('school') for c in got or []), '학교 배지 없는 카드')
    check.that(said.get('relations') == len(cards), f"관계 줄 {said.get('relations')}개")
    check.that(said.get('notice') is True, f"안내 {said.get('notice', MISSING)}")
    check.that(said.get('empty') is (not cards), f"빈 문구 {said.get('empty', MISSING)}")
    want = (0, len(cards)) if received else (len(cards), 0)
    check.that((said.get('trash'), said.get('flags')) == want, f"휴지통 {said.get('trash')} · 깃발 {said.get('flags')}(기대 {want})")
    check.that(said.get('waiting') is False, f"리뷰를 기다리는 친구 칸 {said.get('waiting', MISSING)}")


def _card(person, tags=('대화가 편해요',), comment=None):
    return {'nickname': person['nickname'], 'tags': list(tags), 'comment': comment}


def p_rev_19(run, phone):
    check = Check()
    me, token = _me(run)
    a = _person(run)
    _link(run, a, me)
    _review(run, a, me, tags=THREE_TAGS, comment='가' * 100)  # E-REV-02 뒤
    said = _app(check, phone(token_hash=token, list='received'))
    _listed(check, said, [_card(a, THREE_TAGS, '가' * 100)], received=True)
    return check.result()


def p_rev_21(run, phone):
    check = Check()
    _, token = _me(run)
    _listed(check, _app(check, phone(token_hash=token, list='received')), [], received=True)
    return check.result()


def p_rev_22(run, phone):
    check = Check()
    me, token = _me(run)
    b = _person(run)
    _link(run, me, b)
    _review(run, me, b)  # E-REV-01 뒤 — 추천으로 이어진 다른 친구는 없다
    _listed(check, _app(check, phone(token_hash=token, list='written')), [_card(b)], received=False)
    return check.result()


def p_rev_23(run, phone):
    check = Check()
    _, token = _me(run)  # 쓴 리뷰 0 · 추천 연결 0
    _listed(check, _app(check, phone(token_hash=token, list='written')), [], received=False)
    return check.result()


def _withdraw(run, person):
    # profiles_withdrawn_at_check — 탈퇴 상태와 withdrawn_at 은 함께 채운다
    _patch(run, f"profiles?id=eq.{person['id']}", {'status': 'withdrawn', 'withdrawn_at': datetime.now(timezone.utc).isoformat()})


def p_rev_32(run, phone):
    check = Check()
    me, token = _me(run)
    a = _person(run)
    _link(run, a, me)
    _review(run, a, me)
    _withdraw(run, a)
    _listed(check, _app(check, phone(token_hash=token, list='received')), [], received=True)
    rows = _count(run, f"friend_reviews?reviewer_id=eq.{a['id']}&reviewee_id=eq.{me['id']}")
    check.that(rows == 1, f'friend_reviews {rows}행(숨김이지 지움이 아니다)')
    return check.result()


def p_rev_33(run, phone):
    """판 둘 — 받은 사람이 탈퇴면 0장, 정지면 1장. 판마다 계정을 새로 만들어 앱을 한 번씩 켠다."""
    check = Check()
    for variant in ('withdrawn', 'suspended'):
        me, token = _me(run)
        b = _person(run)
        _link(run, me, b)
        _review(run, me, b)
        if variant == 'withdrawn':
            _withdraw(run, b)
        else:
            _patch(run, f"profiles?id=eq.{b['id']}", {'status': 'suspended'})
        cards = [] if variant == 'withdrawn' else [_card(b)]
        part = Check()
        _listed(part, _app(part, phone(token_hash=token, list='written', variant=variant), variant), cards, received=False)
        check.problems += [f'{variant}: {p}' for p in part.problems]
    return check.result()


def _partner_reviews(count):
    """폰 계정(A)과 매칭된 B 가 받은 리뷰 [count] 개 — B 와 추천으로 이어진 사람들이 API 로 썼다. 앱은 14c(와 3개 이상이면 14d)를 읽는다."""
    def case(run, phone):
        check = Check()
        me, token = _me(run)
        b = _person(run)
        _match(run, me, b)
        for _ in range(count):
            writer = _person(run)
            _link(run, b, writer)
            _ok('리뷰 쓰기', _review_post(run, writer, b))
        more = count > 2
        said = _app(check, phone(token_hash=token, profile_id=b['id'], nickname=b['nickname'], open_sheet=more))
        check.that(said.get('cards') == 2, f"14c 카드 {said.get('cards')}장(기대 2)")
        link = f'{count}개 모두 보기' if more else None
        check.that(said.get('link', MISSING) == link, f"링크 {said.get('link', MISSING)!r}(기대 {link!r})")
        if more:
            check.that(said.get('sheet') == count, f"14d 카드 {said.get('sheet')}장(기대 {count})")
        check.that(said.get('flags') == 0, f"신고 깃발 {said.get('flags')}개")
        return check.result()
    return case


PHONE = {
    'E-CHAT-06': p_chat_06, 'E-CHAT-08': _badges(True, 3, None), 'E-CHAT-09': _badges(False, 100, '99+'),
    'E-CHAT-18': _paging(120, [50, 100, 120], 2), 'E-CHAT-19': _paging(50, [50], 1),
    'E-CHAT-20': _paging(120, [50, 100, 120], 2, same_time=True), 'E-CHAT-36': p_chat_36, 'E-CHAT-60': p_chat_60,
    'E-CHAT-62': p_chat_62,
    'E-REV-10': p_rev_10, 'E-REV-12': p_rev_12, 'E-REV-19': p_rev_19, 'E-REV-21': p_rev_21, 'E-REV-22': p_rev_22,
    'E-REV-23': p_rev_23, 'E-REV-29': _partner_reviews(3), 'E-REV-30': _partner_reviews(2), 'E-REV-32': p_rev_32,
    'E-REV-33': p_rev_33,
}

area1.PHONE.update(PHONE)
area3.BUNDLES['area3-phone-1'] = list(PHONE)
