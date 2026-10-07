"""영역 3 안전 폰 한 대 — 신고 · 차단 · 정지 중 앱이 누르고 화면을 읽는 27개(묶음 area3-safe-phone).
기대값은 바탕화면 E2E_시나리오_조각/3_채팅_리뷰_안전.md 의 E-SAFE 줄이다. 앱 쪽은 frontend/integration_test/area3_safe.dart 의 같은 번호.
(연락처 차단 35~46 은 이번 묶음이 아니다.)
두 기기 줄의 02 · 03 · 04 · 06 · 22 · 25 · 32 · 53 · 55 는 폰 한 대 + PC 가 상대 역할(신고 · 차단 · 나가기 · 보내기 · 정지를 서버에 보내는 일)을 API · 서비스 키로 맡는다 —
상대 화면이 정말 필요한 줄(B 방 줄이 ≤ 2.0초에 뜨는지 · B 폰 알림 0건)만 못 보고 메모에 한계로 둔다.

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
  E-SAFE-02            시나리오 그대로(A 의 방 ⋯ 신고) — E-SAFE-18 과 같은 앱 흐름이고, PC 가 방의 글 4건이 그대로 남고 나감 줄이 1개인지 더 본다.
  E-SAFE-03            폰 = 신고당하는 B. 방을 열어 둔 채 step 에서 멈추면 PC 가 A 로 B 를 신고하고, 다른 방(C)에서 C 가 보통 나가기를 한다. 앱이 두 방의 시스템 줄 · 입력창 자리 안내 ·
                       "신고 · 차단" 글자 유무를 읽고, PC 가 두 줄의 DB 꼴 · B 토큰으로 읽은 방 머리말 키 모양이 같은지 본다. B 알림 0건은 폰 알림 목록이 필요해 이번에 못 본다(영역 4 몫).
  E-SAFE-04            말풍선 길게 누르기 → "이 메시지 신고" 는 기존 `_menuOnLongPress`(메뉴를 닫아 버림)와 달리 눌러서 시트까지 간다. 스냅샷 본문 · target_id 는 PC 가 B 의 글 id 와 대조.
  E-SAFE-06            "방이 닫혔다" 쪽은 닫힌 방이 대화 목록에서 빠져 앱이 열 수 없다 — 두 번째 방을 만들어 chat_closed_at 을 찍고 API 로 신고(201 · reports 1 · blocks 1)만 본다.
                       상대가 나간 방은 앱이 연다(입력창 대신 나감 안내 — `_openReportSheet` 의 입력창 기다림을 쓰지 않는다).
  E-SAFE-22            신고자 3명(PC, API)이 B 를 자동 가림(auto_hidden_at 이 안 채워지면 blocked). 폰 A 는 방을 연 뒤 step 에서 멈추고 PC 가 B 로 글을 보낸다 — 앱이 ≤ 2.0초에 그리는지,
                       이어 A 가 입력해 보낸 글이 DB · B 토큰 읽기에 있는지, 14c 가 열리는지. 음수 지연(폰 시계가 앞섬)은 "판정 불가" 메모.
  E-SAFE-25            시나리오 그대로. PC 가 B 방에 나감 줄 1개(보낸이 A) · B 방 머리말 partner_left 를 읽는다. "≤ 2.0초" · B 알림 0건은 B 화면 · 알림이 필요해 못 본다.
  E-SAFE-32            25 의 결과 상태를 PC 가 API(POST /blocks)로 먼저 만들고, 앱이 차단 목록에서 B 를 해제한다. 해제 뒤 left_at · 방 목록 · B 의 보내기(409)는 PC 가 본다.
  E-SAFE-53            폰 = 정지당하는 A. e2e/area3_phone5.py 의 알림 배치 길(`_start` · `_park` · `_gated_batch`)을 그대로 쓴다 — 정지 전 B 의 메시지 1건이 폰에 도착함을 먼저 보고(대조),
                       정지 뒤 B 의 메시지 · 리뷰는 서버가 막고(409 · 404), 리마인드 창에 둔 방을 chat-gate 가 건너뛰는 동안 폰 알림이 0건이다. 같은 시 chat-gate 는 한 번이라
                       chat-gate 를 부르는 E-CHAT-50 · 51 · 52 · 55 · 57 · 65 · 66 · 67 · E-SAFE-56 과 한 시간에 하나만 돈다.
  E-SAFE-55            폰 = B. A·B 를 신뢰 확인 통과 방(카톡 공개)으로 만들고 A 를 정지 → 앱이 방(입력창 대신 나감 안내 · 공개 카드 · 카톡 아이디 없음) · 14c(토스트) · 화면 글자의 "정지" 0회를 읽는다.
                       step('release') 에서 PC 가 정지 중의 방 머리말 · 보내기 시도(409)를 보고 A 를 active 로 → 앱이 방을 다시 열어 입력창 · 카드 · 카톡이 돌아오고 글을 보낸다.
  E-SAFE-60 · 61       망은 영역 4 와 같은 길(비행기 모드, area4._offline)이다. 60 은 첫 시도 때 서버에 신고가 안 닿았음을 PC 가 두 번째 단계 앞에서 본다.
"""

import json
import secrets
import uuid
from datetime import timedelta

from e2e import area1, area2, area3, area4, notify, tools
from e2e.area1 import Check, _api, _app, _patch, _rows
from e2e.area2_phone3 import notice_memo
from e2e.area3 import PROFILE_GONE, _count, _insert, _link, _match, _messages, _review_post, _send
from e2e.area3_phone import MISSING, _left_line, _me, _ok, _permitted, _person
from e2e.area3_phone2 import _paste, _room, _sent
from e2e.area3_phone3 import NOTICE_WAIT
from e2e.area3_phone5 import LIVE_LIMIT, REMIND_AGE, _at, _closed, _gated_batch, _own, _park, _sentinel, _single_shot, _start
from e2e.area3_safe import _hidden_at, _message_ids, _open_reporters, _report, _reporters, _suspend, _target
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
TARGET = 'E2E-신고대상'  # E-SAFE-04 에서 B 가 보내는 글
LEFT_NOTICE = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'  # chat_room_screen.dart _PartnerGoneNotice
PARTNER_LEFT = '상대가 대화를 나갔어요'  # errors.CHAT_PARTNER_LEFT — 나간 · 정지 · 탈퇴 상대에게 보낼 때
CASE_LIMIT = 900  # 알림 배치(E-SAFE-53)는 area3_phone5 와 같은 배치 기다림 · 알림 기다림이 든다
CASE_LIMIT_MID = 600  # 계정 다섯 + 앱 한 번(E-SAFE-22) · 방 둘(E-SAFE-55)
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


def _has_left(run, match_id, account):
    left = _left_at(run, match_id, account)
    return bool(left) and left != MISSING


def _left_lines(run, match_id):
    return _rows(run, f'messages?match_id=eq.{match_id}&kind=eq.left&select=sender_id,body')


def _room_head(run, account, match_id):
    """[account] 가 읽는 방 머리말 — (상태, 본문)."""
    return _api(run, 'GET', f'/chat/matches/{match_id}', account['token'])


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


def _reported_as_profile(run, check, said, me, partner, match_id, reason, note=None, message=None):
    """채팅방 ⋯ · 14c · 자동 가림 판이 같이 보는 "신고 = 신고 1행 + 차단 1행 + 나감, 앱은 대화 목록으로".
    [message] = (id, 본문) 이면 말풍선 신고(E-SAFE-04) — target_type message · target_id = 그 글 · 스냅샷 본문이 그 글이다."""
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
        if message:
            want.update(target_type='message', target_id=message[0])
        check.that(got == want, f'reports {got}(기대 {want})')
        snap = row.get('target_snapshot') or {}
        if message:
            check.that(snap.get('body') == message[1] and snap.get('message_id') == message[0],
                       f"스냅샷 {sorted(snap)} 본문 {snap.get('body')!r}(기대 {message[1]!r} · 그 글의 id)")
        else:
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


# ── 방 안 신고 · 신고당한 쪽 · 말풍선 · 나간 방 · 자동 가림 · 차단 · 해제 · 정지 상대(02 · 03 · 04 · 06 · 22 · 25 · 32 · 55) ─────────────────

@_case
def p_safe_02(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    _messages(run, match_id, me, 2)
    _messages(run, match_id, partner, 2)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    _reported_as_profile(run, check, said, me, partner, match_id, 'spam')
    kept = _count(run, f'messages?match_id=eq.{match_id}&kind=eq.text')
    check.that(kept == 4, f'방의 글 {kept}건(기대 4 그대로 — 신고가 글을 지우지 않는다)')
    lines = _left_lines(run, match_id)
    check.that([l['sender_id'] for l in lines] == [me['id']], f'나감 줄 {len(lines)}개(기대 폰 계정이 낸 1개)')
    return '시나리오 그대로 — E-SAFE-18 과 같은 앱 흐름(방 ⋯ → 신고하기 → 광고 · 스팸 → 신고하기)'


def _shape(room):
    """방 머리말의 모양 — 값이 아니라 키(닉네임 · 시각은 방마다 다르다)."""
    return {'keys': sorted(room), 'partner': sorted(room.get('partner') or {}), 'gate': sorted(room.get('gate') or {})}


@_case
def p_safe_03(run, phone, check, made):
    me, token = _me(run)  # 폰 계정 = 신고당하는 B
    a, c = _person(run), _person(run)  # A = 신고하는 쪽, C = 보통 나가는 쪽(비교용 방)
    made += [me, a, c]
    room_a, room_c = _match(run, me, a), _match(run, me, c)

    def reported(step):  # B 가 두 방을 열어 둔 채 멈춘 사이
        _ok('A 가 B 를 신고', _report(run, a, 'profile', me['id']))
        _ok('C 의 보통 나가기', _api(run, 'POST', f'/chat/matches/{room_c}/leave', c['token']))

    said = _app(check, phone(midway=reported, token_hash=token, nickname=a['nickname'], other=c['nickname']))
    for key, who, label in (('', a, '신고당한 방'), ('other_', c, '보통 나간 방')):
        check.that(said.get(f'{key}lines', MISSING) == [_left_line(who)], f"{label} 시스템 줄 {said.get(f'{key}lines', MISSING)}(기대 [{_left_line(who)!r}])")
        check.that(said.get(f'{key}notice') is True, f"{label} 입력창 자리의 나감 안내 {said.get(f'{key}notice', MISSING)}(기대 보임)")
        check.that(said.get(f'{key}words') == 0, f"{label} 화면의 \"신고\" · \"차단\" 글자 {said.get(f'{key}words', MISSING)}곳(기대 0)")
    heads, forms = {}, []
    for label, who, match_id in (('신고당한 방', a, room_a), ('보통 나간 방', c, room_c)):
        lines = _left_lines(run, match_id)
        check.that([l['sender_id'] for l in lines] == [who['id']], f'{label} 나감 줄 {len(lines)}개(기대 나간 쪽이 낸 1개)')
        forms += [l['body'].replace(who['nickname'], '{}') for l in lines]
        check.that(not _has_left(run, match_id, me), f'{label} 폰 계정(B) left_at 이 채워짐(기대 비어 있음 — 신고당해도 B 는 나가지 않는다)')
        status, room = _room_head(run, me, match_id)
        check.that(status == 200, f'{label} 방 머리말 {status}(기대 200)')
        if status == 200:
            heads[label] = room
            check.that((room.get('gate') or {}).get('partner_left') is True, f"{label} partner_left {(room.get('gate') or {}).get('partner_left')}(기대 True)")
            text = json.dumps(room, ensure_ascii=False).lower()
            check.that(not any(word in text for word in ('report', 'block', '신고', '차단')), f'{label} 방 머리말에 신고 · 차단 글자가 있음')
    check.that(len(forms) == 2 and forms[0] == forms[1], f'나감 줄 꼴이 다름 {forms}(기대 둘 다 "{{}}님이 채팅방을 나갔어요")')
    if len(heads) == 2:
        shapes = list(map(_shape, heads.values()))
        check.that(shapes[0] == shapes[1], f'방 머리말 모양이 다름 {shapes}')
    check.that(len(_reports_by(run, a)) == 1, 'A 의 신고 행이 1이 아님(준비 실패)')
    return 'B 알림 0건은 폰 알림 목록이 필요해 못 봄(영역 4 몫) · 두 방의 글자 · 머리말 모양은 같음을 PC 가 DB · B 토큰으로 읽어 본다'


@_case
def p_safe_04(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    _ok('B 가 글 보내기', _send(run, partner, match_id, TARGET))
    ids = _message_ids(run, match_id, partner)
    if len(ids) != 1:
        raise Blocked(f'준비: B 의 글 {len(ids)}건(기대 1)')
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], theirs=TARGET))
    _reported_as_profile(run, check, said, me, partner, match_id, 'abuse', message=(ids[0], TARGET))
    return '말풍선 길게 누르기 → "이 메시지 신고" 는 기존 _menuOnLongPress(메뉴를 닫아 버림)가 아니라 눌러서 시트까지 간다'


@_case
def p_safe_06(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    _messages(run, match_id, partner, 2)
    _ok('B 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', partner['token']))
    if not _has_left(run, match_id, partner) or _has_left(run, match_id, me):
        raise Blocked('준비: B 만 나간 방이 아님(B left_at 채워짐 · 폰 계정 left_at 비어 있음이어야 한다)')
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('gone_notice') is True, f"입력창 자리의 나감 안내 {said.get('gone_notice', MISSING)}(기대 보임)")
    check.that(said.get('input_bar') is False, f"입력창 {said.get('input_bar', MISSING)}(기대 없음)")
    _reported_as_profile(run, check, said, me, partner, match_id, 'spam')
    # 닫힌 방 — 대화 목록에서 빠져 앱이 열 수 없다. 서버가 과거 매칭으로 받는지만 API 로 본다(safety/router.py:103-117).
    me2, _, partner2, closed = _scene(run, made)
    _patch(run, f'matches?id=eq.{closed}', {'chat_closed_at': area2._now().isoformat()})
    if not _closed(run, closed):
        raise Blocked('준비: 닫힌 방(chat_closed_at)이 안 만들어짐')
    check.reply('닫힌 방 신고', _report(run, me2, 'profile', partner2['id']), 201)
    reports = _reports_by(run, me2)
    check.that(len(reports) == 1 and reports[0]['target_profile_id'] == partner2['id'], f'닫힌 방 신고 reports {len(reports)}행(기대 상대 1행)')
    check.that(_blocks_by(run, me2) == [partner2['id']], f'닫힌 방 신고 blocks {_blocks_by(run, me2)}(기대 [상대] 1행)')
    return '"방이 닫혔다" 쪽은 닫힌 방이 목록에서 빠져 앱으로 열 수 없어 API 로만 봄(201 · reports 1 · blocks 1) — 나간 방은 앱이 연다'


@_case
def p_safe_22(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)  # 폰 계정 A(신고하지 않은 쪽) · 대상 B(홈 활성)
    reporters = _reporters(run, partner, 3)
    made += [r for r, _ in reporters]
    for i, (reporter, _) in enumerate(reporters, 1):
        _ok(f'신고자 {i}', _report(run, reporter, 'profile', partner['id']))
    if _hidden_at(run, partner) is None:
        raise Blocked('준비: 서로 다른 신고자 3명에도 B 가 가려지지 않음(E-SAFE-18) — 가려진 뒤의 채팅을 볼 수 없다')
    body, text, sent = f'E2E-22-{secrets.token_hex(3)}', f'E2E-22-내글-{secrets.token_hex(3)}', []
    said = _app(check, phone(midway=lambda said: sent.append(_send(run, partner, match_id, body, retry=False)), token_hash=token,
                             nickname=partner['nickname'], profile_id=partner['id'], body=body, text=text))
    if said.get('loaded') is False:  # 방 읽기를 못 끝내 글을 보내기 전에 멈췄다 — 구독 전에 보내면 가짜 실패
        raise Blocked(f"A 방이 안 읽힘(loaded False · 오류 {said.get('error')!r}) — 글을 보내지 않았다. 로그인 · 방 확인")
    check.that(said.get('loaded') is True, f"앱이 방 읽기를 끝냈다고 안 말함 {said.get('loaded', MISSING)}(기대 True)")
    check.reply('B 보내기', sent[0] if sent else (0, '앱이 멈추기 전에 끝남'), 201)
    check.that(said.get('bubble') is True, f"가려진 B 의 글이 A 화면에 {said.get('bubble', MISSING)}(기대 True)")
    note = ''
    created = _at((_rows(run, f'messages?match_id=eq.{match_id}&body=eq.{body}&select=created_at') or [{}])[0].get('created_at'))
    seen = _at(said.get('seen_at'))
    if created and seen:
        delay = (seen - created).total_seconds()
        if delay < 0:  # 앱이 본 시각이 서버가 찍은 시각보다 앞 — 폰 시계 차라 늦은 표시도 가려질 수 있어 판정하지 않는다
            note = f'지연 판정 불가 — 앱이 본 시각이 서버가 찍은 보낸 시각보다 {-delay:.2f}초 앞섬(폰 시계 차). 말풍선 표시만 판정'
        else:
            check.that(delay <= LIVE_LIMIT, f'A 화면에 {delay:.1f}초 뒤 표시(기대 ≤ {LIVE_LIMIT})')
            note = f'지연 {delay:.2f}초(앱 시계 − 서버가 찍은 보낸 시각)'
    elif said.get('bubble') is True:
        check.problems.append('보낸 시각 또는 앱이 본 시각(seen_at)을 못 읽음')
    check.that(said.get('mine') is True, f"A 가 보낸 글이 A 화면에 {said.get('mine', MISSING)}(기대 True)")
    got = _sent(run, me, match_id)
    check.that(got == [text], f'A 가 보낸 messages {got}(기대 [{text!r}] 1행)')
    status, room = _api(run, 'GET', f'/chat/matches/{match_id}/messages', partner['token'])
    shown = [m.get('body') for m in (room or {}).get('messages', [])] if status == 200 else None
    check.that(shown is not None and text in shown, f'B 가 읽은 방 글 {status} {shown}(기대 A 의 글 포함 — B 화면 대신)')
    check.that(said.get('profile') is True, f"B 의 14c(상대 프로필) {said.get('profile', MISSING)}(기대 열림)")
    check.that(_hidden_at(run, partner) is not None, '끝에서 B.auto_hidden_at 이 비어 있음')
    return (note + ' · ' if note else '') + '신고자 수는 DB 로 셈 — 가려진 뒤에도 진행 중 채팅 · 14c 는 그대로(safety/router.py:250)'


@_case
def p_safe_25(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    check.that(said.get('on_list') is True, f"대화 목록으로 안 감 {said.get('on_list', MISSING)}")
    check.that(said.get('room_listed') is False, f"목록에 방이 남음 {said.get('room_listed', MISSING)}(기대 사라짐)")
    check.that(_blocks_by(run, me) == [partner['id']], f'blocks {_blocks_by(run, me)}(기대 [상대] 1행)')
    check.that(_has_left(run, match_id, me), f'폰 계정 left_at {_left_at(run, match_id, me)!r}(기대 채워짐)')
    check.that(not _reports_by(run, me), f'reports {len(_reports_by(run, me))}행(기대 0 — 차단은 신고가 아니다)')
    lines = _left_lines(run, match_id)
    check.that([l['sender_id'] for l in lines] == [me['id']], f'B 방의 나감 줄 {len(lines)}개(기대 폰 계정이 낸 1개)')
    check.that(all(l['body'] == _left_line(me) for l in lines), f"나감 줄 글자 {[l['body'] for l in lines]}(기대 {_left_line(me)!r})")
    status, room = _room_head(run, partner, match_id)
    check.that(status == 200 and (room.get('gate') or {}).get('partner_left') is True, f'B 의 방 머리말 {status} partner_left(기대 200 · True)')
    check.that(not _has_left(run, match_id, partner), 'B left_at 이 채워짐(기대 비어 있음)')
    return 'B 방의 나감 줄 "≤ 2.0초" · B 알림 0건은 B 화면 · 알림이 필요해 못 봄(줄은 DB, 머리말은 B 토큰으로 읽음)'


@_case
def p_safe_32(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)
    other = _person(run)
    made.append(other)
    control = _match(run, partner, other)
    _ok('A 가 B 를 차단', _api(run, 'POST', f"/blocks/{partner['id']}", me['token']))  # E-SAFE-25 의 결과 상태
    if _blocks_by(run, me) != [partner['id']] or not _has_left(run, match_id, me):
        raise Blocked('준비: 차단 뒤 blocks 1행 · A left_at 채워짐이 아님')
    _ok('대조(B 가 다른 방에서 보내기)', _send(run, partner, control, 'E2E-32-대조'))  # 막힌 방의 409 가 "B 는 원래 못 보낸다" 가 아님을 보인다
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    for key, want, label in (('sheet', True, '해제 확인 시트'), ('row_before', True, '해제 전 차단 목록의 B 줄'),
                             ('row_after', False, '해제 뒤 B 줄'), ('empty', True, '해제 뒤 빈 화면 문구')):
        check.that(said.get(key, MISSING) is want, f'{label} {said.get(key, MISSING)}(기대 {want})')
    check.that(not _blocks_by(run, me), f'blocks {_blocks_by(run, me)}(기대 0)')
    check.that(_has_left(run, match_id, me), f'A left_at {_left_at(run, match_id, me)!r}(기대 채워진 채 — 해제가 left_at 을 지우지 않는다)')
    status, body = _api(run, 'GET', '/chat/conversations', me['token'])
    ids = [c['match_id'] for c in (body or {}).get('conversations', [])] if status == 200 else None
    check.that(ids is not None and match_id not in ids, f'A 대화 목록 {status} {ids}(기대 200 · 그 방 없음)')
    status, room = _room_head(run, partner, match_id)
    check.that(status == 200 and (room.get('gate') or {}).get('partner_left') is True, f'B 의 방 머리말 {status} partner_left(기대 200 · True 그대로)')
    check.reply('B 의 보내기', _send(run, partner, match_id, 'E2E-32-막힘'), 409, PARTNER_LEFT)
    n = _count(run, f'messages?match_id=eq.{match_id}&kind=eq.text')
    check.that(n == 0, f'막힌 방의 글 {n}건(기대 0)')
    return '시나리오의 "B 방 입력창 잠김" 은 B 화면 대신 서버 응답(방 머리말 partner_left · 보내기 409)으로 봄'


@_case
def p_safe_55(run, phone, check, made):
    me, token, partner, match_id = _scene(run, made)  # 폰 계정 B · 정지당하는 A
    now = area2._now().isoformat()
    _patch(run, f'match_participants?match_id=eq.{match_id}', {'trust_response': 'accept', 'responded_at': now})
    _patch(run, f'matches?id=eq.{match_id}', {'trust_passed_at': now})
    _messages(run, match_id, partner, 1)
    status, room = _room_head(run, me, match_id)
    kakao = (room or {}).get('kakao_id') if status == 200 else None
    if not kakao or (room.get('gate') or {}).get('partner_left') is not False:
        raise Blocked(f'준비: 정지 전 방 머리말에 상대의 카톡 아이디가 안 보임({status}) — 신뢰 확인 통과 · 카톡 공개를 못 만들었다')
    _suspend(run, partner)

    def release(step):  # 앱이 정지 중의 방 · 14c 를 읽은 뒤
        status, room = _room_head(run, me, match_id)
        gate = (room or {}).get('gate') or {}
        check.that(status == 200 and gate.get('partner_left') is True and 'kakao_id' not in room,
                   f"정지 중 방 머리말 {status} partner_left {gate.get('partner_left')} kakao_id {'kakao_id' in (room or {})}(기대 200 · True · 없음)")
        check.reply('정지 중 보내기', _send(run, me, match_id, 'E2E-55-막힘'), 409, PARTNER_LEFT)
        check.that(not _has_left(run, match_id, partner), '정지 중 A left_at 이 채워짐(기대 비어 있음 — 정지는 left_at 을 찍지 않는다)')
        _patch(run, f"profiles?id=eq.{partner['id']}", {'status': 'active'})

    text = f'E2E-55-{secrets.token_hex(3)}'
    said = _app(check, phone(midway=release, token_hash=token, nickname=partner['nickname'], profile_id=partner['id'], text=text, kakao=kakao))
    for key, want, label in (('gone_notice', True, '정지 중 입력창 자리의 나감 안내'), ('input_during', False, '정지 중 입력창'),
                             ('card_during', False, '정지 중 공개 카드'), ('kakao_during', False, '정지 중 카톡 아이디'),
                             ('words_during', 0, '정지 중 방 화면의 "정지" 글자'), ('profile_open', False, '14c 가 열린 채'),
                             ('words_after_toast', 0, '14c 토스트 뒤 화면의 "정지" 글자'), ('input_after', True, '해제 뒤 입력창'),
                             ('card_after', True, '해제 뒤 공개 카드'), ('kakao_after', True, '해제 뒤 카톡 아이디'), ('bubble', True, '해제 뒤 보낸 글 말풍선')):
        check.that(said.get(key, MISSING) == want, f'{label} {said.get(key, MISSING)}(기대 {want})')
    check.that(said.get('toast', MISSING) == PROFILE_GONE, f"14c 토스트 {said.get('toast', MISSING)!r}(기대 {PROFILE_GONE!r})")
    got = _sent(run, me, match_id)
    check.that(got == [text], f'messages {got}(기대 [{text!r}] 1행 — 정지 중 PC 의 보내기 시도는 행을 못 만든다)')
    for who, label in ((me, '폰 계정'), (partner, '상대')):
        check.that(not _has_left(run, match_id, who), f'{label} left_at 이 채워짐(기대 정지 중에도 해제 뒤에도 비어 있음)')
    status = _rows(run, f"profiles?id=eq.{partner['id']}&select=status")[0]['status']
    check.that(status == 'active', f'profiles.status {status}(기대 active)')
    return '정지 중 14c 는 앱이 라우터로 연다(방 머리말은 눌리지 않음) · 정지 사실이 화면 글자에 없음은 Text 위젯 전부에서 "정지" 를 센 값'


# ── 정지 계정에는 알림이 안 간다(E-SAFE-53) — 알림 배치 ───────────────────────────────────────────────────

def p_safe_53(run, phone):
    _start(daytime=True)  # 준비 전에 — 낮 10~20시 · chat-gate 관문(지금 · 준비가 끝날 즈음)
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다
    check = Check()
    me, token = _me(run)  # 폰 계정 = 정지당하는 A
    partner = _person(run)  # B
    _own(run, me, partner)
    sentinel = _sentinel(run)
    _link(run, me, partner)  # 추천으로 이어진 사이 — 정지만 아니면 B 가 A 에게 리뷰를 쓸 수 있다
    match_id = _match(run, me, partner)
    before = _park(check, run, phone, me, token)  # 홈까지 로그인 → 기기 토큰이 올라옴 → 알림 목록을 읽고 앱 프로세스를 죽임
    if before is None:
        return check.result()
    control = f'E2E-53-{secrets.token_hex(3)}'  # 대조 — 정지 전에는 B 의 메시지가 폰에 도착한다. 안 오면 "0건" 은 아무것도 증명하지 못한다
    _ok('정지 전 B 의 메시지', _send(run, partner, match_id, control))
    got = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == (partner['nickname'], control))
    if not any((n.title, n.text) == (partner['nickname'], control) for n in got):
        raise Blocked(f'대조 알림 "{partner["nickname"]} / {control}" 이 {NOTICE_WAIT}초 안에 안 옴(새 알림 {len(got)}건: {notice_memo(got)}) — '
                      '알림 길(토큰 · FCM · 알림 목록 읽기)이 살아 있는지 몰라 "0건" 을 믿을 수 없음')
    before = notify.read_notifications(phone.serial)  # 대조 알림은 앞 알림으로 — 이 뒤에 새로 생긴 것만 본다
    status = (_rows(run, f"profiles?id=eq.{me['id']}&select=status") or [{}])[0].get('status')
    if status != 'active':  # 정지 뒤 리뷰 404 · 메시지 409 가 "정지 때문" 이라는 증거가 되려면 정지 전에 active 여야 한다
        raise Blocked(f'준비: 폰 계정이 정지 전에 active 가 아님(status {status!r}) — 정지 뒤 404 · 409 가 정지 때문인지 알 수 없다')
    _suspend(run, me)
    refused = _send(run, partner, match_id, f'E2E-53-정지-{secrets.token_hex(3)}')
    check.that(refused[0] in (404, 409), f'정지된 사람에게 메시지 {refused[0]}(기대 404/409 — 서버가 받지 않는다)')
    review = _review_post(run, partner, me)
    check.that(review[0] in (404, 409), f'정지된 사람에게 리뷰 {review[0]}(기대 404/409)')
    check.that(_count(run, f"friend_reviews?reviewee_id=eq.{me['id']}") == 0, 'friend_reviews 새 행이 생김')
    _gated_batch(run, [me, partner], [(match_id, REMIND_AGE)], sentinel)  # 정지만 아니면 리마인드가 갈 방(24시간 5분, A 미수락)
    new = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)
    check.that(not new, f'정지 계정에 알림이 {len(new)}건 옴(기대 0): {notice_memo(new)}')
    texts = _count(run, f'messages?match_id=eq.{match_id}&sender_id=eq.{partner["id"]}&kind=eq.text')
    check.that(texts == 1, f'B 의 글 {texts}건(기대 대조 1건뿐 — 정지 뒤 글은 서버가 막는다)')
    return check.result('대조: 정지 전 B 의 메시지 1건이 폰에 도착 · 정지 뒤 메시지(409) · 리뷰(404)는 서버가 이미 막아 알림 코드(cards/push.py:88 정지 한 줄)까지 가지 않음 — '
                        '그래서 이 pass 는 푸시의 정지 차단 한 줄을 따로 증명하지 않는다(직접 확인 못 함) · '
            '리마인드는 정지 방을 배치가 건너뜀. 배치가 돈 증거는 같은 나이의 확인용 방이 닫힘. chat-gate 는 같은 시 한 번 — chat-gate 를 부르는 E-CHAT-50 · 51 · 52 · 55 · 57 · '
            '65 · 66 · 67 · E-SAFE-56 과 한 시간에 하나만 돈다(묶음을 한꺼번에 돌리면 나머지는 "XX:06 에 다시" blocked)')


SAFE_PHONE = {
    'E-SAFE-01': p_safe_01, 'E-SAFE-02': p_safe_02, 'E-SAFE-03': p_safe_03, 'E-SAFE-04': p_safe_04, 'E-SAFE-05': p_safe_05,
    'E-SAFE-06': p_safe_06, 'E-SAFE-07': p_safe_07, 'E-SAFE-08': p_safe_08, 'E-SAFE-09': p_safe_09, 'E-SAFE-11': p_safe_11,
    'E-SAFE-13': p_safe_13, 'E-SAFE-15': p_safe_15, 'E-SAFE-18': p_safe_18, 'E-SAFE-22': p_safe_22, 'E-SAFE-25': p_safe_25,
    'E-SAFE-26': p_safe_26, 'E-SAFE-27': p_safe_27, 'E-SAFE-28': p_safe_28, 'E-SAFE-30': p_safe_30, 'E-SAFE-31': p_safe_31,
    'E-SAFE-32': p_safe_32, 'E-SAFE-50': p_safe_50,
    'E-SAFE-53': _permitted(_single_shot(p_safe_53)),  # 알림 권한을 주고 · 배치를 부른 뒤의 fail 은 다시 안 돈다(같은 시 두 번째 chat-gate 는 관문이 막는다)
    'E-SAFE-55': p_safe_55, 'E-SAFE-57': p_safe_57, 'E-SAFE-60': p_safe_60, 'E-SAFE-61': p_safe_61,
}
tools.CASE_LIMITS.update({'E-SAFE-03': CASE_LIMIT_MID, 'E-SAFE-06': CASE_LIMIT_MID, 'E-SAFE-22': CASE_LIMIT_MID,
                          'E-SAFE-55': CASE_LIMIT_MID, 'E-SAFE-53': CASE_LIMIT})

area1.PHONE.update(SAFE_PHONE)
area3.BUNDLES['area3-safe-phone'] = list(SAFE_PHONE)
