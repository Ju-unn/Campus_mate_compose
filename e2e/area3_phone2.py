"""영역 3 폰 A 한 대 2차 — 채팅 · 지인 리뷰 중 앱이 입력 · 누르기를 하는 19개(묶음 area3-phone-2).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본). 앱 쪽은 frontend/integration_test/area3_b2.dart 의 같은 번호.
1차(area3_phone.py)와 같은 모양 — 가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 계정(전부 홈까지) · 매칭 · 추천 연결 · 리뷰를
준비하고, 앱이 입력 · 누르기를 해서 화면에서 본 것을 말하면, 보낸 글 · 쓴 리뷰 · 신고는 PC 가 DB 에서 센다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-REV-11  "[20b 열기] + 같은 순간 [API] 로 POST" — 같은 순간을 만들 수 없다. 앱이 시트에서 태그를 고르고 step 에서 멈춘 사이 PC 가
            API 로 먼저 쓰고(201), 앱이 그다음 "리뷰 남기기" 를 눌러 409 를 읽는다. "앱이 이기는" 쪽 경합은 안 본다.
  E-REV-37  시나리오 토스트 "이미 신고한 사용자예요" 는 옛 문구 — 지금 앱은 서버 문구 "이미 신고를 완료했어요"(safety_errors.dart:5)를 띄운다.
            첫 신고는 앱이 아니라 PC 가 API 로 넣는다(E-REV-36 을 앞에서 돌렸는지와 상관없이 혼자 돈다).
  E-CHAT-25 망은 `svc wifi/data` 가 아니라 비행기 모드(notify.airplane)로 끊는다 — 영역 4 의 망 끊기 가설과 같은 길이고, 폰 USB 를 타는
            우편함은 끊기지 않는다.
  E-CHAT-43 "배너 · 시트 둘 다" 는 방 상태 둘(`variant`)이다 — banner = 방금 만든 방의 "수락하기" 배너 → 확인 창 "수락",
            sheet = 25시간 지난 방의 14f 시트 "수락하고 공유하기"(시트는 확인 창이 없다).
            배너 판은 확인 창이 닫히는 중이라 두 번째 누름이 요청으로 나가지 않을 수 있다 — 폰에서 두 번째 요청이 나갔는지 눈으로 본다.
"""

from datetime import datetime, timedelta, timezone

from e2e import area1, area3, area4, tools
from e2e.area1 import Check, _api, _app, _rows
from e2e.area3 import _count, _link, _match, _patch, _review, _review_post, _send
from e2e.area3_phone import ALREADY, MISSING, THREE_TAGS, _me, _ok, _permitted, _person

LIMIT = 1000  # 채팅 글 상한(코드포인트) — chat_input_bar.dart messageMaxLength
COMMENT_LIMIT = 100  # 리뷰 한마디 상한 — friend_review_tags.dart friendReviewCommentMaxLength
SUBMITTED = '리뷰를 남겼어요'  # friend_review_compose_sheet.dart:22
REPORTED = '신고했어요. 운영팀이 확인할게요'  # received_reviews_screen.dart:12
ALREADY_REPORTED = '이미 신고를 완료했어요'  # safety_errors.dart:5 · 서버 errors.py ALREADY_REPORTED
NETWORK = '네트워크 연결을 확인해 주세요'  # common/failure.dart:16
ONE_TAG = ['대화가 편해요']
FOUR_TAGS = THREE_TAGS + ['배려가 깊어요']
SMILE, SPACE, HANGUL = [0x1F600], [0x20], [0xAC00]
FAMILY = [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]  # 👨‍👩‍👧 = 코드포인트 5개
COMMENT, REVIEW_TAGS = '고마웠어요', ['대화가 편해요', '성실해요']


def _paste(runes, count):
    """앱이 입력칸에 한 번에 붙여 넣을 글 — 코드포인트 목록 × 횟수(이모지를 JSON · Dart 문자열 리터럴로 건너지 않으려고)."""
    return {'runes': runes, 'count': count}


def _text(runes, count):
    return ''.join(map(chr, runes)) * count


# ── 채팅 ─────────────────────────────────────────────────────────────────────────────────────────────

def _room(run):
    """(폰 계정, 토큰, 상대, 매칭 id) — 방금 만든 방."""
    me, token = _me(run)
    partner = _person(run)
    return me, token, partner, _match(run, me, partner)


def _sent(run, me, match_id, kind='text'):
    """폰 계정이 이 방에 보낸 [kind] 줄의 본문들."""
    return [r['body'] for r in _rows(run, f"messages?match_id=eq.{match_id}&sender_id=eq.{me['id']}&kind=eq.{kind}&select=body")]


def p_chat_04(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], text='E2E-04'))
    check.that(said.get('lines') == 1, f"내 화면 그 본문 {said.get('lines', MISSING)}줄(기대 1)")
    got = _sent(run, me, match_id)
    check.that(got == ['E2E-04'], f'messages {got}(기대 [E2E-04] 1행)')
    return check.result()


def p_chat_05(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)
    _app(check, phone(token_hash=token, nickname=partner['nickname'], text='연타'))
    got = _sent(run, me, match_id)
    check.that(got == ['연타'], f'messages {len(got)}행 {got}(기대 1행)')
    return check.result()


def _long(runes, count):
    """[runes] × [count] 를 붙여 넣고 보낸다 — 입력칸도 DB 본문도 앞 [LIMIT] 코드포인트만 남아야 한다."""
    def case(run, phone):
        check = Check()
        me, token, partner, match_id = _room(run)
        said = _app(check, phone(token_hash=token, nickname=partner['nickname'], paste=_paste(runes, count)))
        check.that(said.get('input_len') == LIMIT, f"입력칸 {said.get('input_len', MISSING)}자(기대 {LIMIT})")
        check.that(said.get('error', MISSING) is None, f"화면 오류 문구 {said.get('error', MISSING)!r}(기대 없음)")
        want = _text(runes, count)[:LIMIT]
        got = _sent(run, me, match_id)
        check.that(got == [want], f'DB body {[len(b) for b in got]}자 {len(got)}행(기대 [{LIMIT}]자 1행)')
        return check.result()
    return case


def p_chat_15(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], paste=_paste(SPACE, 5)))
    check.that(said.get('send_enabled') is False, f"보내기 버튼 켜짐 {said.get('send_enabled', MISSING)}(기대 꺼짐)")
    check.reply('API 공백 · 줄바꿈', _send(run, me, match_id, '   \n '), 422)
    rows = _count(run, f'messages?match_id=eq.{match_id}')
    check.that(rows == 0, f'messages {rows}행(기대 새 행 0)')
    return check.result()


def p_chat_25(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)
    said = area4._offline(phone, check, area4._cut(phone), token_hash=token, nickname=partner['nickname'], text='테스트')
    check.that(said.get('error') == NETWORK, f"문구 {said.get('error', MISSING)!r}(기대 {NETWORK!r})")
    check.that(said.get('input') == '테스트', f"입력칸 {said.get('input', MISSING)!r}(기대 되돌아온 '테스트')")
    got = _sent(run, me, match_id)
    check.that(got == [], f'messages {got}(기대 새 행 0)')
    # 판정은 처음 잡힌 문구다 — Realtime 이 끊기면 copyWith 가 오류 줄을 지워 끝 값은 None 일 수 있다
    return check.result(f"오류 줄은 Realtime 끊김이 지우는지: {said.get('error_cleared', MISSING)}, 끊김 배너 {said.get('disconnected', MISSING)}"
                        ' — copyWith 규칙(chat_room_ui_state.dart:106) 때문에 몇 초 뒤 사라질 수 있음(결함 후보 낮음)')


def p_chat_43(run, phone):
    """판 둘 — banner(방금 만든 방) · sheet(25시간 지난 방). 판마다 계정을 새로 만들어 앱을 한 번씩 켠다."""
    check = Check()
    notes = []
    for variant in ('banner', 'sheet'):
        me, token, partner, match_id = _room(run)
        if variant == 'sheet':  # 24시간 뒤부터 시트, 48시간 안이라 아직 수락할 수 있다
            _patch(run, f'matches?id=eq.{match_id}', {'created_at': (datetime.now(timezone.utc) - timedelta(hours=25)).isoformat()})
        part = Check()
        said = _app(part, phone(token_hash=token, nickname=partner['nickname'], variant=variant), variant)
        part.that(said.get('error', MISSING) is None, f"화면 오류 문구 {said.get('error', MISSING)!r}(기대 없음)")
        lines = _sent(run, me, match_id, 'trust_accept')
        part.that(len(lines) == 1, f'수락 줄 {len(lines)}개(기대 1)')
        mine = _rows(run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{me['id']}&select=trust_response")
        part.that([r.get('trust_response') for r in mine] == ['accept'], f'trust_response {mine}(기대 accept 한 줄)')
        if 'room_open' in said:  # 두 번 누르면 pop 이 두 번 불려 방이 닫힐 수 있다 — 판정엔 안 넣고 적기만
            notes.append(f"{variant}: 방 열림 {said['room_open']}")
        check.problems += [f'{variant}: {p}' for p in part.problems]
    return check.result('; '.join(notes))


# ── 지인 리뷰 쓰기 ───────────────────────────────────────────────────────────────────────────────────

def _writer(run):
    """(폰 계정, 토큰, 상대) — 추천으로 이어진 active 상대에게 폰 계정이 쓴다(20b 열기 전 준비)."""
    me, token = _me(run)
    b = _person(run)
    _link(run, me, b)
    return me, token, b


def _mine(run, me, b):
    rows = _rows(run, f"friend_reviews?reviewer_id=eq.{me['id']}&reviewee_id=eq.{b['id']}&select=tags,comment")
    return [{'tags': r['tags'], 'comment': r.get('comment')} for r in rows]


def _compose(tags, comment, want_tags, want_comment, selected=None):
    """[tags] 를 고르고 [comment](붙여 넣기)를 쓴 뒤 남긴다 — 시트가 닫히고 토스트가 뜨며 DB 에 [want_tags] · [want_comment] 한 줄.
    [selected] 가 있으면 앱이 말한 고른 수 · 선택 표시 수가 그 값이어야 한다."""
    def case(run, phone):
        check = Check()
        me, token, b = _writer(run)
        job = {'token_hash': token, 'profile_id': b['id'], 'tags': tags}
        if comment is not None:
            job['paste'] = _paste(*comment)
        said = _app(check, phone(**job))
        check.that(said.get('toast') == SUBMITTED, f"토스트 {said.get('toast', MISSING)!r}(기대 {SUBMITTED!r})")
        check.that(said.get('closed') is True, f"시트 닫힘 {said.get('closed', MISSING)}")
        if selected is not None:
            check.that((said.get('selected'), said.get('marks')) == (selected, selected),
                       f"고른 수 {said.get('selected', MISSING)} · 선택 표시 {said.get('marks', MISSING)}(기대 {selected})")
        rows = _mine(run, me, b)
        want = [{'tags': want_tags, 'comment': want_comment}]
        check.that(rows == want, f'friend_reviews {rows}(기대 {want})')
        return check.result()
    return case


def p_rev_03(run, phone):
    check = Check()
    me, token, b = _writer(run)
    said = _app(check, phone(token_hash=token, profile_id=b['id'], paste=_paste(HANGUL, 5)))
    check.that(said.get('submit_enabled') is False, f"리뷰 남기기 켜짐 {said.get('submit_enabled', MISSING)}(기대 꺼짐)")
    check.that(said.get('selected') == 0, f"고른 태그 {said.get('selected', MISSING)}개(기대 0)")
    rows = _mine(run, me, b)
    check.that(rows == [], f'friend_reviews {rows}(기대 새 행 0 — 서버 요청 0)')
    return check.result()


def p_rev_05(run, phone):
    check = Check()
    me, token, b = _writer(run)
    said = _app(check, phone(token_hash=token, profile_id=b['id'], tags=ONE_TAG, paste=_paste(HANGUL, COMMENT_LIMIT + 1)))
    check.that(said.get('input_len') == COMMENT_LIMIT, f"입력칸 {said.get('input_len', MISSING)}자(기대 {COMMENT_LIMIT})")
    want = f'{COMMENT_LIMIT} / {COMMENT_LIMIT}'
    check.that(said.get('counter') == want, f"카운터 {said.get('counter', MISSING)!r}(기대 {want!r})")
    rows = _mine(run, me, b)
    check.that(rows == [], f'friend_reviews {rows}(쓰기만 하고 남기지 않았다)')
    return check.result()


def p_rev_11(run, phone):
    """앱이 태그를 고르고 멈춘 사이 PC 가 API 로 먼저 쓴다 → 앱이 남기기를 눌러 409 "이미 리뷰를 남겼어요" 를 읽는다."""
    check = Check()
    me, token, b = _writer(run)
    wrote = []

    def api_first(said):
        _ok('API 먼저 쓰기', _review_post(run, me, b))
        wrote.append(True)

    said = _app(check, phone(midway=api_first, token_hash=token, profile_id=b['id'], tags=ONE_TAG))
    check.that(wrote, 'API 쓰기가 앱이 멈춘 사이에 안 돌았음')
    check.that(said.get('toast') == ALREADY, f"토스트 {said.get('toast', MISSING)!r}(기대 {ALREADY!r})")
    rows = _mine(run, me, b)
    check.that(len(rows) == 1, f'friend_reviews {len(rows)}행(기대 1)')
    return check.result('같은 순간 경합은 못 만든다 — API 가 먼저 쓴 뒤 앱이 눌러 409 를 읽는다(앱이 이기는 쪽은 안 봄)')


def p_rev_25(run, phone):
    check = Check()
    me, token, b = _writer(run)
    _review(run, me, b)  # E-REV-01 뒤
    said = _app(check, phone(token_hash=token))
    check.that(said.get('cards') == 1, f"카드 {said.get('cards', MISSING)}장(기대 1 그대로)")
    check.that(said.get('confirm_open') is False, f"지우기 확인 시트 {said.get('confirm_open', MISSING)}(기대 닫힘)")
    check.that(said.get('toast', MISSING) is None, f"토스트 {said.get('toast', MISSING)!r}(기대 없음)")
    rows = _mine(run, me, b)
    check.that(len(rows) == 1, f'friend_reviews {len(rows)}행(기대 1 그대로)')
    return check.result()


# ── 받은 리뷰 신고 ───────────────────────────────────────────────────────────────────────────────────

def _clear_reports(run, review, check):
    """reports 는 계정을 지워도 cascade 로 안 지워진다(set null) — 시험이 만든 신고는 pass 여도 PC 가 지운다."""
    status, got = tools.rest(run.cfg, run.key, 'DELETE', f'reports?target_id=eq.{review}')
    check.that(status < 300, f'reports 지우기 {status} {got} — 시험이 만든 신고가 남았을 수 있음')


def _reported(first_by_api):
    """폰 계정(받은 사람)이 받은 리뷰를 신고한다. [first_by_api] 면 첫 신고는 PC 가 API 로 넣고 앱은 두 번째(E-REV-37)."""
    def case(run, phone):
        check = Check()
        me, token = _me(run)
        a = _person(run)
        _link(run, a, me)
        review = _review(run, a, me, tags=REVIEW_TAGS, comment=COMMENT)
        try:
            if first_by_api:
                _ok('첫 신고(API)', _api(run, 'POST', '/reports', me['token'],
                                        {'target_type': 'friend_review', 'target_id': review, 'reason': 'abuse'}))
            said = _app(check, phone(token_hash=token))
            toast = ALREADY_REPORTED if first_by_api else REPORTED
            check.that(said.get('toast') == toast, f"토스트 {said.get('toast', MISSING)!r}(기대 {toast!r})")
            check.that(said.get('cards') == 1, f"카드 {said.get('cards', MISSING)}장(기대 1 그대로)")
            check.that(said.get('sheet_open') is False, f"신고 시트 {said.get('sheet_open', MISSING)}(기대 닫힘)")
            rows = _rows(run, f'reports?target_id=eq.{review}&select=*')
            check.that(len(rows) == 1, f'reports {len(rows)}행(기대 1)')
            if len(rows) == 1 and not first_by_api:
                row, snap = rows[0], rows[0].get('target_snapshot') or {}
                check.that((row.get('reporter_id'), row.get('target_type'), row.get('reason')) == (me['id'], 'friend_review', 'abuse'),
                           f"신고 {row.get('reporter_id')} · {row.get('target_type')} · {row.get('reason')}")
                check.that((snap.get('tags'), snap.get('comment')) == (REVIEW_TAGS, COMMENT) and bool(snap.get('created_at')),
                           f'스냅샷 {snap}(기대 태그 · 한마디 · 작성 시각)')
            blocks = _count(run, f"blocks?blocker_id=eq.{me['id']}")
            check.that(blocks == 0, f'blocks {blocks}행(기대 0 — 리뷰 신고는 차단하지 않는다)')
        finally:
            _clear_reports(run, review, check)
        return check.result()
    return case


PHONE2 = {
    'E-CHAT-04': p_chat_04, 'E-CHAT-05': p_chat_05, 'E-CHAT-11': _long(HANGUL, LIMIT + 1),
    'E-CHAT-12': _long(SMILE, LIMIT + 1), 'E-CHAT-13': _long(FAMILY, LIMIT // len(FAMILY) + 1), 'E-CHAT-15': p_chat_15,
    'E-CHAT-25': p_chat_25, 'E-CHAT-43': p_chat_43,
    'E-REV-01': _compose(ONE_TAG, None, ONE_TAG, None),
    'E-REV-02': _compose(THREE_TAGS, (HANGUL, COMMENT_LIMIT), THREE_TAGS, _text(HANGUL, COMMENT_LIMIT)),
    'E-REV-03': p_rev_03,
    'E-REV-04': _compose(FOUR_TAGS, None, THREE_TAGS, None, selected=3),
    'E-REV-05': p_rev_05,
    'E-REV-06': _compose(ONE_TAG, (SMILE, COMMENT_LIMIT), ONE_TAG, _text(SMILE, COMMENT_LIMIT)),
    'E-REV-07': _compose(ONE_TAG, (SPACE, 5), ONE_TAG, None),
    'E-REV-11': p_rev_11, 'E-REV-25': p_rev_25, 'E-REV-36': _reported(False), 'E-REV-37': _reported(True),
}
PHONE2 = {name: _permitted(case) for name, case in PHONE2.items()}

area1.PHONE.update(PHONE2)
area3.BUNDLES['area3-phone-2'] = list(PHONE2)
