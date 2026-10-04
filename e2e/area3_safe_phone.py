"""영역 3 안전 폰 A 한 대 — 신고 · 차단 · 정지 중 앱이 누르고 화면을 읽는 18개(묶음 area3-safe-phone).
기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 E-SAFE 줄이다. 앱 쪽은 frontend/integration_test/area3_safe.dart 의 같은 번호.
(연락처 차단 35~46 은 이번 묶음이 아니다.)

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 계정(전부 홈까지) · 매칭 · 메시지 · 차단 · 정지를 서비스 키와 API 로
준비하고, 앱이 누르고 화면에서 본 것을 Map 으로 말하면, 신고 · 차단 · 나감 행은 PC 가 DB 에서 센다. 신고 · 차단 대상은 모두 active
(홈) 계정이다 — basic 단계는 status 가 pending 이라 신고 · 차단 · 14c 가 막힌다(영역 3 검토 10-04). 가설마다 새 계정을 만든다.
신고 행은 계정을 지워도 안 지워지니(set null) 신고를 만드는 가설은 pass 여도 PC 가 끝에서 지운다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-SAFE-07 · 27 · 28  "방 머리말 → 14c" — 방 머리말은 눌리지 않아(chat_room_screen.dart:175-177) 앱이 라우터로 14c 를 바로 연다
                       (E-REV-29 · 30 과 같은 길). 28 은 B에뮬 판이지만 폰 한 대로 — 폰 계정이 "차단당한 쪽", 상대가 API 로 폰 계정을 막는다.
  E-SAFE-11            시나리오는 "앱에 신고 입구 없음 + API 422" 인데 지금 코드는 남의 투표 글에 신고 입구가 있고(poll_card.dart
                       onReport · 글쓴이는 익명이라 차단 없음, A16) 서버도 poll 을 받는다(safety/router.py `_poll_target`). 지금 동작으로 옮겼다:
                       남의 글에는 "신고하기" 가 있고 내 글에는 없다(… 메뉴), 앱 신고는 토스트 "신고했어요. 운영팀이 확인할게요" · 카드 그대로 · blocks 0,
                       API 는 내 글 404 "질문을 찾을 수 없어요" · 없는 종류 422. 시나리오의 "결정 필요" 는 코드가 이미 정했다.
  E-SAFE-13            시나리오 토스트 "이미 신고한 사용자예요" 는 옛 문구 — 지금은 서버 문구 "이미 신고를 완료했어요"(safety_errors.dart:5).
                       첫 신고는 앱이 방을 연 뒤 PC 가 API 로 넣는다(방을 먼저 열어 둬야 하고, 신고하면 방이 목록에서 사라진다).
  E-SAFE-15            "다른 대상 10건" 은 DB 로 넣는다 — reports 는 대상 칸에 FK 가 없고 target_profile_id 가 비어도 되어 계정 열 개를 안 만든다
                       (로그인 429 위험). 토스트는 지금 코드 문구 "오늘은 더 신고할 수 없어요"(safety_errors.dart reportLimitedMessage).
  E-SAFE-18            대상 T 의 닉네임은 DB 에서 읽는다. 디스코드 줄(신고 3 + 자동 가림 1)은 읽을 길이 없어 안 센다 — 서버 코드 표는 PR 본문에.
  E-SAFE-50            정지 화면에는 AppButton "로그아웃" 1개 외에 글자 버튼 "탈퇴하기" 가 하나 더 있다(account_suspended_screen.dart A5) —
                       "버튼 1개" 는 AppButton 기준으로 본다. "당겨서 새로고침" 은 손가락 끌기를 먼저 해 보고, 안 되면 RefreshIndicator 를
                       직접 띄운다(앱이 어느 쪽으로 됐는지 `pulled` 로 말한다).
  E-SAFE-57            "50 뒤" 의 이어달리기가 아니라 독립이다: 정지된 채 로그인(앱이 정지 화면에 닿음) → PC 가 정지를 풀고 새 토큰을 받아
                       `step` 의 답으로 넘김 → 앱이 같은 프로세스에서 로그아웃 → 그 토큰으로 다시 로그인 → 홈 → 방에서 글 보내기.
  E-SAFE-60 · 61       망은 영역 4 와 같은 길(비행기 모드, area4._offline)이다. 60 은 첫 시도 때 서버에 신고가 안 닿았음을 PC 가 두 번째 단계 앞에서 본다.
"""

import uuid
from datetime import timedelta

from e2e import area1, area2, area3, area4
from e2e.area1 import Check, _api, _app, _patch, _rows
from e2e.area3 import PROFILE_GONE, _insert, _match
from e2e.area3_phone import MISSING, _me, _ok, _person
from e2e.area3_phone2 import _paste, _room, _sent
from e2e.area3_safe import _hidden_at, _open_reporters, _report, _reporters, _suspend, _target
from e2e.tools import Blocked, rest

REPORT_TITLE = '무엇을 신고할까요?'  # report_sheet.dart
REASONS = ['욕설·비방·혐오', '성적 불쾌감', '광고·스팸', '사칭·허위', '기타']  # report_reason.dart — 시트에 보이는 위에서 아래 순서
REPORTED = '신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요.'  # report_ui_state.dart reportedMessage
POLL_REPORTED = '신고했어요. 운영팀이 확인할게요'  # poll_sheets.dart
ALREADY_REPORTED = '이미 신고를 완료했어요'  # safety_errors.dart:5
LIMITED = '오늘은 더 신고할 수 없어요'  # safety_errors.dart reportLimitedMessage
MESSAGE_GONE = '메시지를 찾을 수 없어요'  # safety_errors.dart
POLL_GONE = '질문을 찾을 수 없어요'
DAILY_LIMIT = 10  # safety/reasons.py DAILY_REPORT_LIMIT
NOTE = '불편했어요'
NOTE_LIMIT = 200  # report_reason.dart reportNoteMaxLength
BUTTONS = ['로그아웃']  # 정지 화면의 AppButton
SEND_TEXT = 'E2E-57'
MINE, THEIRS, SYSTEM = 'E2E-내말', 'E2E-상대', 'E2E-수락 줄'


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _scene(run, made):
    """(폰 계정, 토큰, 상대, 매칭 id) — 방금 만든 방. 만든 계정은 [made] 에 적는다(끝 정리용)."""
    me, token, partner, match_id = _room(run)
    made += [me, partner]
    return me, token, partner, match_id


def _reports_by(run, account):
    return _rows(run, f"reports?reporter_id=eq.{account['id']}&select=*")


def _blocks_by(run, account):
    return [r['blocked_id'] for r in _rows(run, f"blocks?blocker_id=eq.{account['id']}&select=blocked_id")]


def _left_at(run, match_id, account):
    rows = _rows(run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{account['id']}&select=left_at")
    return rows[0].get('left_at') if rows else MISSING


def _purge(run, check, *accounts):
    """reports 는 계정을 지워도 cascade 로 안 지워진다(set null) — 시험이 만든 신고는 pass 여도 PC 가 지운다."""
    for account in accounts:
        for column in ('reporter_id', 'target_profile_id'):
            status, got = rest(run.cfg, run.key, 'DELETE', f"reports?{column}=eq.{account['id']}")
            check.that(status < 300, f'reports 지우기 {status} {got} — 시험이 만든 신고가 남았을 수 있음')


def _case(body):
    """가설 하나의 틀 — [body](run, phone, check, made) 가 끝나면(통과 · 실패 · 막힘 · 오류 어느 쪽이든) 만든 신고를 지운다.
    body 가 글자를 돌려주면 그것이 메모다."""
    def case(run, phone):
        check, made = Check(), []
        try:
            note = body(run, phone, check, made) or ''
        finally:
            _purge(run, check, *made)
        return check.result(note)
    case.__doc__ = body.__doc__
    return case


def _nothing_sent(run, check, me):
    reports, blocks = _reports_by(run, me), _blocks_by(run, me)
    check.that(not reports, f'reports {len(reports)}행(기대 0 — 신고를 보내지 않았다)')
    check.that(not blocks, f'blocks {len(blocks)}행(기대 0)')


def _reported_as_profile(run, check, said, me, partner, match_id, reason, note=None):
    """채팅방 ⋯ · 14c · 자동 가림 판이 같이 보는 "신고 = 신고 1행 + 차단 1행 + 나감, 앱은 대화 목록으로"."""
    check.that(said.get('toast', MISSING) == REPORTED, f"토스트 {said.get('toast', MISSING)!r}(기대 {REPORTED!r})")
    check.that(said.get('on_list') is True, f"대화 목록으로 안 감 {said.get('on_list', MISSING)}")
    check.that(said.get('room_listed') is False, f"목록에 방이 남음 {said.get('room_listed', MISSING)}(기대 사라짐)")
    rows = _reports_by(run, me)
    check.that(len(rows) == 1, f'reports {len(rows)}행(기대 1)')
    if len(rows) == 1:
        row = rows[0]
        keys = ('target_type', 'target_id', 'target_profile_id', 'reason', 'reason_note')
        got = {k: row.get(k) for k in keys}
        want = dict(zip(keys, ('profile', partner['id'], partner['id'], reason, note)))
        check.that(got == want, f'reports {got}(기대 {want})')
        snap = row.get('target_snapshot') or {}
        check.that(snap.get('nickname') == partner['nickname'] and {'bio', 'avatar_path', 'photo_paths'} <= set(snap),
                   f"스냅샷 {sorted(snap)} 닉네임 {snap.get('nickname')!r}(기대 닉네임 · bio · avatar_path · photo_paths)")
    blocks = _blocks_by(run, me)
    check.that(blocks == [partner['id']], f'blocks {blocks}(기대 [상대] 1행)')
    left = _left_at(run, match_id, me)
    check.that(bool(left) and left != MISSING, f'폰 계정 left_at {left!r}(기대 채워짐)')


# ── 신고 시트 ────────────────────────────────────────────────────────────────────────────────────────

@_case
def p_safe_01(run, phone, check, made):
    me, token, partner, _ = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('title', MISSING) == REPORT_TITLE, f"제목 {said.get('title', MISSING)!r}(기대 {REPORT_TITLE!r})")
    check.that(said.get('reasons', MISSING) == REASONS, f"사유 순서 {said.get('reasons', MISSING)}(기대 {REASONS})")
    check.that(said.get('rows') == len(REASONS), f"라디오 줄 {said.get('rows', MISSING)}개(기대 {len(REASONS)})")
    check.that(said.get('submit_before') is False, f"고르기 전 신고하기 켜짐 {said.get('submit_before', MISSING)}(기대 꺼짐)")
    check.that(said.get('submit_after') is True, f"사유를 고른 뒤 신고하기 켜짐 {said.get('submit_after', MISSING)}(기대 켜짐 — 꺼진 채라면 버튼이 안 켜지는 것)")
    _nothing_sent(run, check, me)


@_case
def p_safe_05(run, phone, check, made):
    """내 말풍선 · 시스템 줄은 길게 눌러도 메뉴가 없고(상대 말풍선은 있다 — 대조군), 서버도 그 두 id 를 404 로 막는다."""
    me, token, partner, match_id = _scene(run, made)
    mine, system, theirs = (str(uuid.uuid4()) for _ in range(3))
    # 배열로 넣을 때 행마다 키가 같아야 한다(PostgREST PGRST102) — 그래서 kind 를 세 행 다 적는다
    _insert(run, 'messages', [{'id': mine, 'match_id': match_id, 'sender_id': me['id'], 'kind': 'text', 'body': MINE},
                              {'id': system, 'match_id': match_id, 'sender_id': me['id'], 'kind': 'trust_accept', 'body': SYSTEM},
                              {'id': theirs, 'match_id': match_id, 'sender_id': partner['id'], 'kind': 'text', 'body': THEIRS}])
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], mine=MINE, system=SYSTEM, theirs=THEIRS))
    check.that(said.get('menu_on_mine') is False, f"내 말풍선에 메뉴 {said.get('menu_on_mine', MISSING)}(기대 없음)")
    check.that(said.get('menu_on_system') is False, f"시스템 줄에 메뉴 {said.get('menu_on_system', MISSING)}(기대 없음)")
    check.that(said.get('menu_on_theirs') is True, f"상대 말풍선 메뉴 {said.get('menu_on_theirs', MISSING)}(기대 뜸 — 안 뜨면 위 둘의 '없음' 은 증거가 못 된다)")
    check.reply('API 내 말풍선', _report(run, me, 'message', mine), 404, MESSAGE_GONE)
    check.reply('API 시스템 줄', _report(run, me, 'message', system), 404, MESSAGE_GONE)
    _nothing_sent(run, check, me)


@_case
def p_safe_07(run, phone, check, made):
    """14c(상대 프로필)의 신고 링크 → 사유 → 신고하기 — 결과는 채팅방에서 한 것과 같다."""
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], profile_id=partner['id']))
    _reported_as_profile(run, check, said, me, partner, match_id, 'spam')


@_case
def p_safe_08(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], note=NOTE))
    for key, want, label in (('note_box_before', False, '사유를 고르기 전 메모 칸'), ('note_box', True, '"기타" 를 고른 뒤 메모 칸'),
                             ('submit_empty', False, '빈 칸일 때 신고하기'), ('submit_blank', False, '공백만 있을 때 신고하기'),
                             ('submit_filled', True, '한 글자 이상일 때 신고하기')):
        check.that(said.get(key, MISSING) is want, f'{label} {said.get(key, MISSING)}(기대 {want})')
    _reported_as_profile(run, check, said, me, partner, match_id, 'other', note=NOTE)


@_case
def p_safe_09(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], paste=_paste([0xAC00], NOTE_LIMIT + 1)))
    check.that(said.get('input_len') == NOTE_LIMIT, f"입력칸 {said.get('input_len', MISSING)}자(기대 {NOTE_LIMIT})")
    want = f'{NOTE_LIMIT} / {NOTE_LIMIT}'
    check.that(said.get('counter', MISSING) == want, f"카운터 {said.get('counter', MISSING)!r}(기대 {want!r})")
    _reported_as_profile(run, check, said, me, partner, match_id, 'other', note='가' * NOTE_LIMIT)


# ── 투표 글 · 중복 · 하루 상한 · 자동 가림 ───────────────────────────────────────────────────────────

@_case
def p_safe_11(run, phone, check, made):
    me, token = _me(run)
    author = _person(run)
    made += [me, author]
    question, own = f"[E2E] 신고 {author['n']}", f"[E2E] 내 글 {me['n']}"
    try:
        poll = area2._poll(run, author, f"신고 {author['n']}")
        mine = area2._poll(run, me, f"내 글 {me['n']}")
        said = _app(check, phone(token_hash=token, question=question, own=own))
        check.that(said.get('entry') is True, f"남의 투표 글 신고 입구 {said.get('entry', MISSING)}(기대 있음)")
        check.that(said.get('own_entry') is False, f"내 글 신고 입구 {said.get('own_entry', MISSING)}(기대 없음)")
        check.that(said.get('own_more') is True, f"내 글 … 메뉴 {said.get('own_more', MISSING)}(기대 있음)")
        check.that(said.get('toast', MISSING) == POLL_REPORTED, f"토스트 {said.get('toast', MISSING)!r}(기대 {POLL_REPORTED!r})")
        check.that(said.get('card') is True, f"신고 뒤 카드 {said.get('card', MISSING)}(기대 그대로)")
        rows = _reports_by(run, me)
        check.that(len(rows) == 1, f'reports {len(rows)}행(기대 1)')
        if len(rows) == 1:
            row = rows[0]
            got = (row['target_type'], row['target_id'], row['target_profile_id'], row['reason'])
            want = ('poll', poll, author['id'], 'abuse')
            check.that(got == want, f'reports {got}(기대 {want})')
            check.that((row.get('target_snapshot') or {}).get('question') == question, f"스냅샷 {row.get('target_snapshot')}")
        blocks = _blocks_by(run, me)
        check.that(not blocks, f'blocks {blocks}(기대 0 — 투표 글쓴이는 익명이라 차단하지 않는다)')
        check.reply('API 내 글 신고', _report(run, me, 'poll', mine), 404, POLL_GONE)
        check.reply('API 없는 종류', _report(run, me, 'poll_option', poll), 422)
    finally:
        area2._drop_polls(run, author)
        area2._drop_polls(run, me)
    return '시나리오(입구 없음 · API 422)와 다르다 — 코드가 이미 투표 글 신고를 받는다(A16)'


@_case
def p_safe_13(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)

    def api_first(said):
        _ok('API 먼저 신고', _report(run, me, 'profile', partner['id']))

    said = _app(check, phone(midway=api_first, token_hash=token, nickname=partner['nickname']))
    check.that(said.get('toast', MISSING) == ALREADY_REPORTED, f"토스트 {said.get('toast', MISSING)!r}(기대 {ALREADY_REPORTED!r})")
    check.that(said.get('on_list') is True, f"대화 목록으로 안 감 {said.get('on_list', MISSING)}")
    rows = _reports_by(run, me)
    check.that(len(rows) == 1, f'reports {len(rows)}행(기대 1 — PC 의 첫 신고뿐)')
    check.that(_blocks_by(run, me) == [partner['id']], f'blocks {_blocks_by(run, me)}(기대 [상대] 1행)')
    return '토스트는 지금 서버 문구 — 시나리오의 "이미 신고한 사용자예요" 는 옛 문구'


@_case
def p_safe_15(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    hour_ago = (area2._now() - timedelta(hours=1)).isoformat()
    _insert(run, 'reports', [{'reporter_id': me['id'], 'target_type': 'profile', 'target_id': str(uuid.uuid4()), 'target_profile_id': None,
                              'target_snapshot': {}, 'reason': 'spam', 'created_at': hour_ago} for _ in range(DAILY_LIMIT)])
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('toast', MISSING) == LIMITED, f"토스트 {said.get('toast', MISSING)!r}(기대 {LIMITED!r})")
    check.that(said.get('in_room') is True, f"방에 그대로 {said.get('in_room', MISSING)}(기대 그대로)")
    reports = _reports_by(run, me)
    check.that(len(reports) == DAILY_LIMIT, f'reports {len(reports)}행(기대 시드 {DAILY_LIMIT} 그대로 — 새 행 0)')
    check.that(not any(r['target_id'] == partner['id'] for r in reports), 'reports 에 상대에 대한 새 신고 행이 생김')
    blocks = _blocks_by(run, me)
    check.that(not blocks, f'blocks {blocks}(기대 0)')
    left = _left_at(run, match_id, me)
    check.that(left is None, f'폰 계정 left_at {left!r}(기대 비어 있음 — 방에 그대로)')


@_case
def p_safe_18(run, phone, check, made):
    t, f = _target(run, viewer=True)  # 가려지기 전에 F 의 후보에 T 가 있다 — 아니면 blocked
    me, token = _me(run)
    made += [t, f, me]
    match_id = _match(run, me, t)
    reporters = _reporters(run, t, 2)
    made += [r for r, _ in reporters]
    for i, (reporter, _) in enumerate(reporters, 1):
        _ok(f'C · D 신고 {i}', _report(run, reporter, 'profile', t['id']))
    if _hidden_at(run, t) is not None:
        raise Blocked('준비: 신고자 2명에 이미 가려져 있음')
    nickname = _rows(run, f"profiles?id=eq.{t['id']}&select=nickname")[0]['nickname']
    said = _app(check, phone(token_hash=token, nickname=nickname))
    _reported_as_profile(run, check, said, me, {**t, 'nickname': nickname}, match_id, 'spam')
    check.that(_hidden_at(run, t) is not None, 'T.auto_hidden_at 이 비어 있음(기대 세 번째 신고에 채워짐)')
    check.that((n := _open_reporters(run, t)) == 3, f'열린 신고의 신고자 {n}명(기대 3)')
    check.that(t['id'] not in area2._candidates(run, f), 'F 의 후보에 가려진 T 가 남음')
    return '신고자 수는 DB 로 셈 · 디스코드 줄(신고 3 + 가림 1)은 못 읽는다'


# ── 차단 ─────────────────────────────────────────────────────────────────────────────────────────────

@_case
def p_safe_26(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    for key, want, label in (('sheet_seen', True, '차단 확인 시트'), ('sheet_closed', True, '취소 뒤 시트 닫힘'),
                             ('in_room', True, '방에 그대로'), ('on_list', False, '대화 목록으로 감')):
        check.that(said.get(key, MISSING) is want, f'{label} {said.get(key, MISSING)}(기대 {want})')
    blocks = _blocks_by(run, me)
    check.that(not blocks, f'blocks {blocks}(기대 0)')
    left = _left_at(run, match_id, me)
    check.that(left is None, f'폰 계정 left_at {left!r}(기대 비어 있음)')


@_case
def p_safe_27(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], profile_id=partner['id']))
    check.that(said.get('on_list') is True, f"대화 목록으로 안 감 {said.get('on_list', MISSING)}")
    check.that(said.get('room_listed') is False, f"목록에 방이 남음 {said.get('room_listed', MISSING)}(기대 사라짐)")
    check.that(_blocks_by(run, me) == [partner['id']], f'blocks {_blocks_by(run, me)}(기대 [상대] 1행)')
    left = _left_at(run, match_id, me)
    check.that(bool(left) and left != MISSING, f'폰 계정 left_at {left!r}(기대 채워짐)')
    reports = _reports_by(run, me)
    check.that(not reports, f'reports {len(reports)}행(기대 0 — 차단만 했다)')


@_case
def p_safe_28(run, phone, check, made):
    me, token, partner, _ = _scene(run, made)
    _ok('상대가 폰 계정을 차단', _api(run, 'POST', f"/blocks/{me['id']}", partner['token']))
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], profile_id=partner['id']))
    check.that(said.get('toast', MISSING) == PROFILE_GONE, f"토스트 {said.get('toast', MISSING)!r}(기대 {PROFILE_GONE!r})")
    check.that(said.get('profile_open') is False, f"14c 가 열린 채 {said.get('profile_open', MISSING)}(기대 닫힘)")
    check.that(said.get('on_home') is True, f"이전 화면(홈)으로 안 돌아옴 {said.get('on_home', MISSING)}")
    check.that(not _blocks_by(run, me), f'blocks(폰 계정이 낸 것) {_blocks_by(run, me)}(기대 0)')
    check.that(_blocks_by(run, partner) == [me['id']], f'blocks(상대가 낸 것) {_blocks_by(run, partner)}(기대 [폰 계정])')


@_case
def p_safe_30(run, phone, check, made):
    me, token = _me(run)
    b, c = _person(run), _person(run)
    made += [me, b, c]
    _match(run, me, b)
    _match(run, me, c)
    _ok('B 직접 차단', _api(run, 'POST', f"/blocks/{b['id']}", me['token']))
    _ok('C 신고(=차단)', _report(run, me, 'profile', c['id']))  # 나중 것이 위에
    said = _app(check, phone(token_hash=token))
    rows = said.get('rows') or []
    dates = [f'{d} 차단' for d in area4._today()]
    check.that([r.get('nickname') for r in rows] == [c['nickname'], b['nickname']],
               f"줄 순서 {[r.get('nickname') for r in rows]}(기대 최신순 [C {c['nickname']}, B {b['nickname']}])")
    check.that(all(r.get('date') in dates for r in rows), f"날짜 {[r.get('date') for r in rows]}(기대 {dates} 중 하나)")
    check.that(all(r.get('button') == '해제' for r in rows), f"줄 오른쪽 버튼 {[r.get('button') for r in rows]}(기대 해제)")
    check.that(said.get('avatars') == 2, f"아바타 {said.get('avatars', MISSING)}개(기대 2)")
    check.that(said.get('notice') is True, f"연락처 차단 안내 {said.get('notice', MISSING)}(기대 있음)")
    check.that(said.get('reason_words') is False, f"신고 · 사유 글 {said.get('reason_words', MISSING)}(기대 없음 — 사유는 적지 않는다)")
    return '아바타는 칸에 그림 위젯이 있는지만 본다(내려받기 성공은 안 봄)'


@_case
def p_safe_31(run, phone, check, made):
    me, token = _me(run)
    made.append(me)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('empty') is True, f"빈 화면 문구 {said.get('empty', MISSING)}(기대 있음)")
    check.that(said.get('sub') is True, f"빈 화면 설명 {said.get('sub', MISSING)}(기대 있음)")
    check.that(said.get('rows') == 0, f"차단 줄 {said.get('rows', MISSING)}개(기대 0)")
    check.that(not _blocks_by(run, me), 'blocks 행이 있음')


# ── 정지 ─────────────────────────────────────────────────────────────────────────────────────────────

@_case
def p_safe_50(run, phone, check, made):
    me, token, partner, _ = _scene(run, made)
    said = _app(check, phone(midway=lambda step: _suspend(run, me), token_hash=token, nickname=partner['nickname']))
    check.that(said.get('title') is True, f"정지 안내 제목 {said.get('title', MISSING)}(기대 보임)")
    check.that(said.get('support') is True, f"문의 메일 {said.get('support', MISSING)}(기대 보임)")
    check.that(said.get('buttons', MISSING) == BUTTONS, f"버튼 {said.get('buttons', MISSING)}(기대 {BUTTONS})")
    check.that(said.get('stays') == {'/home': True, '/conversations': True},
               f"다른 경로로 가면 {said.get('stays', MISSING)}(기대 둘 다 정지 화면으로 되돌아옴)")
    status = _rows(run, f"profiles?id=eq.{me['id']}&select=status")[0]['status']
    check.that(status == 'suspended', f'profiles.status {status}(기대 suspended 그대로)')
    return f"새로고침은 {said.get('pulled', '?')} 로 — 정지 화면에 \"탈퇴하기\" 글자 버튼이 하나 더 있다(A5)"


@_case
def p_safe_57(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    _suspend(run, me)

    def release(step):
        _patch(run, f"profiles?id=eq.{me['id']}", {'status': 'active'})
        return {'token_hash': run.link(me['email'])}  # 첫 토큰은 앱이 썼다 — 새로 받으면 앞 것이 죽는다

    said = _app(check, phone(midway=release, token_hash=token, nickname=partner['nickname'], text=SEND_TEXT))
    check.that(said.get('suspended_first') is True, f"처음엔 정지 화면 {said.get('suspended_first', MISSING)}(기대 보임)")
    check.that(said.get('home_after') is True, f"다시 로그인한 뒤 홈 {said.get('home_after', MISSING)}(기대 보임)")
    got = _sent(run, me, match_id)
    check.that(got == [SEND_TEXT], f'messages {got}(기대 [{SEND_TEXT}] 1행)')
    status = _rows(run, f"profiles?id=eq.{me['id']}&select=status")[0]['status']
    check.that(status == 'active', f'profiles.status {status}(기대 active)')


# ── 망 끊기 ──────────────────────────────────────────────────────────────────────────────────────────

@_case
def p_safe_60(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)

    def restore_after_the_first_try(step):
        reports = _reports_by(run, me)
        check.that(not reports, f'망이 없는데 reports {len(reports)}행이 생김')
        area4._restore(phone)(step)

    said = area4._offline(phone, check, area4._cut(phone), restore_after_the_first_try, token_hash=token, nickname=partner['nickname'])
    first, second = said.get('first') or {}, said.get('second') or {}
    for key, want, label in (('error', True, '첫 시도 네트워크 문구'), ('sheet_open', True, '첫 시도 뒤 시트'), ('in_room', True, '첫 시도 뒤 방')):
        check.that(first.get(key, MISSING) is want, f'{label} {first.get(key, MISSING)}(기대 {want})')
    check.that(first.get('toast', MISSING) is None, f"첫 시도 토스트 {first.get('toast', MISSING)!r}(기대 없음)")
    _reported_as_profile(run, check, second, me, partner, match_id, 'spam')


@_case
def p_safe_61(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = area4._offline(phone, check, area4._cut(phone), token_hash=token, nickname=partner['nickname'])
    for key, label in (('error', '입력창 위 네트워크 문구'), ('in_room', '방에 그대로'), ('confirm_closed', '확인 시트 닫힘'),
                       ('above_input', '문구가 입력창 위')):
        check.that(said.get(key, MISSING) is True, f'{label} {said.get(key, MISSING)}(기대 True)')
    blocks = _blocks_by(run, me)
    check.that(not blocks, f'blocks {blocks}(기대 0)')
    left = _left_at(run, match_id, me)
    check.that(left is None, f'폰 계정 left_at {left!r}(기대 비어 있음)')


SAFE_PHONE = {
    'E-SAFE-01': p_safe_01, 'E-SAFE-05': p_safe_05, 'E-SAFE-07': p_safe_07, 'E-SAFE-08': p_safe_08,
    'E-SAFE-09': p_safe_09, 'E-SAFE-11': p_safe_11, 'E-SAFE-13': p_safe_13, 'E-SAFE-15': p_safe_15, 'E-SAFE-18': p_safe_18,
    'E-SAFE-26': p_safe_26, 'E-SAFE-27': p_safe_27, 'E-SAFE-28': p_safe_28, 'E-SAFE-30': p_safe_30, 'E-SAFE-31': p_safe_31,
    'E-SAFE-50': p_safe_50, 'E-SAFE-57': p_safe_57, 'E-SAFE-60': p_safe_60, 'E-SAFE-61': p_safe_61,
}

area1.PHONE.update(SAFE_PHONE)
area3.BUNDLES['area3-safe-phone'] = list(SAFE_PHONE)
