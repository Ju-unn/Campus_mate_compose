"""사람이 적는 글 칸의 공용 검사(11-18 검토, 사용자 「일단 서버로 막자」).

- 널 문자: Postgres text 가 못 담아 저장에서 500 이 났다 → 모델 검사에서 422.
- 0폭 문자만: 빈 글처럼 보이는 글 → 빈 값 · 최소 길이를 0폭 문자를 뺀 값으로 잰다.
- 한 줄 칸은 줄바꿈 · 탭도 거절, 여러 줄 칸은 받는다.
모델 검사 실패(ValidationError)는 FastAPI 가 늘 422 로 답한다.
"""
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.admin.inquiry_review import InquiryPatch
from app.admin.reason import ReasonBody
from app.admin.report_review import ResolveBody
from app.admin.users import NoteBody
from app.cards.router import PushTokenRequest
from app.chat.router import MessageRequest
from app.community.router import CommentRequest, PollRequest
from app.friend_reviews.router import TAGS, CodeLookupRequest, ReviewRequest
from app.inquiries.router import InquiryRequest
from app.me.schemas import ProfileUpdateRequest
from app.profile_onboarding.schemas import AcquisitionRequest, BioRequest, IdealNoteRequest
from app.referral.router import RedeemRequest
from app.safety.router import ContactBlocksRequest, ReportRequest

NUL = "\x00"
ZW = "\u200b\u200c\u200d\u2060\ufeff"
RLO = "\u202e"  # 글 방향 뒤집기

# (이름, 모델, 값을 넣은 본문을 만드는 함수, 정상 값)
_TAG = TAGS[0] if isinstance(TAGS[0], str) else next(iter(TAGS[0]))
MULTILINE = [
    ("onboarding_bio", BioRequest, lambda v: {"bio": v}, "안녕하세요\n반가워요"),
    ("ideal_note", IdealNoteRequest, lambda v: {"note": v}, "다정하고 대화가 잘 통하는 사람"),
    ("me_bio", ProfileUpdateRequest, lambda v: {"bio": v}, "안녕하세요\n반가워요"),
    ("chat", MessageRequest, lambda v: {"body": v}, "ㅋㅋㅋ"),
    ("poll_question", PollRequest, lambda v: {"question": v}, "짜장면\n짬뽕?"),
    ("comment", CommentRequest, lambda v: {"body": v}, "저도요\n좋아요"),
    ("friend_review", ReviewRequest, lambda v: {"reviewee_id": str(uuid4()), "tags": [_TAG], "comment": v}, "좋은 친구"),
    ("report_note", ReportRequest,
     lambda v: {"target_type": "profile", "target_id": str(uuid4()), "reason": "other", "reason_note": v}, "이상한 말"),
    ("inquiry", InquiryRequest, lambda v: {"reason": "other", "body": v, "reply_email": "a@b.co"}, "결제가 안 돼요\n확인 부탁"),
]
SINGLE_LINE = [
    ("poll_option", PollRequest, lambda v: {"question": "짜장 짬뽕", "option_a_label": v}, "짜장"),
    ("acquisition_note", AcquisitionRequest, lambda v: {"channel": "other", "note": v}, "학교 게시판"),
    ("push_token", PushTokenRequest, lambda v: {"token": v, "platform": "android"}, "fcm:token-1_A"),
]
# 코드 속 공백 · 탭 · 줄바꿈은 서버가 지운다(기존 test_lookup_ignores_case_and_spaces) — 널 문자 등만 막는다.
CODES = [
    ("referral_code", RedeemRequest, lambda v: {"code": v}, "ABCD12"),
    ("friend_code", CodeLookupRequest, lambda v: {"code": v}, "ABCD12"),
]
ADMIN = [
    ("admin_reason", ReasonBody, lambda v: {"reason": v}, "신고 3건\n확인함"),
    ("admin_note", NoteBody, lambda v: {"text": v}, "메모"),
    ("report_note_admin", ResolveBody, lambda v: {"outcome": "dismissed", "note": v}, "문제 없음"),
    ("inquiry_memo", InquiryPatch, lambda v: {"admin_memo": v}, "답장함"),
]
ALL = MULTILINE + SINGLE_LINE + CODES + ADMIN
# 비었는지 · 최소 길이를 보는 칸(지시 2): 0폭 문자만이면 거절한다.
NOT_EMPTY = MULTILINE + [case for case in SINGLE_LINE if case[0] == "poll_option"]


def _ids(cases):
    return [case[0] for case in cases]


@pytest.mark.parametrize(("name", "model", "body", "ok"), ALL, ids=_ids(ALL))
def test_a_normal_value_passes(name, model, body, ok):
    model.model_validate(body(ok))


@pytest.mark.parametrize(("name", "model", "body", "ok"), ALL, ids=_ids(ALL))
def test_a_nul_character_is_refused_before_the_database(name, model, body, ok):
    with pytest.raises(ValidationError):
        model.model_validate(body(ok[:1] + NUL + ok[1:]))


@pytest.mark.parametrize(("name", "model", "body", "ok"), MULTILINE + ADMIN, ids=_ids(MULTILINE + ADMIN))
def test_a_direction_override_is_refused(name, model, body, ok):
    with pytest.raises(ValidationError):
        model.model_validate(body(ok[:1] + RLO + ok[1:]))


@pytest.mark.parametrize(("name", "model", "body", "ok"), NOT_EMPTY, ids=_ids(NOT_EMPTY))
def test_only_zero_width_characters_count_as_empty(name, model, body, ok):
    with pytest.raises(ValidationError):
        model.model_validate(body(ZW))


@pytest.mark.parametrize(("name", "model", "body", "ok"), SINGLE_LINE, ids=_ids(SINGLE_LINE))
@pytest.mark.parametrize("control", ["\n", "\t"])
def test_a_one_line_field_refuses_line_breaks_and_tabs(name, model, body, ok, control):
    with pytest.raises(ValidationError):
        model.model_validate(body(ok[:1] + control + ok[1:]))


@pytest.mark.parametrize("text", ["", "   ", "\t\n"])
def test_a_trimmed_admin_reason_still_needs_one_character(text):
    """검사기를 StringConstraints 앞에 두면 공백만인 사유가 통과했다(전체 시험에서 잡힘)."""
    with pytest.raises(ValidationError):
        ReasonBody(reason=text)
    with pytest.raises(ValidationError):
        CommentRequest(body=text)


def test_the_ideal_note_counts_ten_characters_without_zero_width_ones():
    with pytest.raises(ValidationError):
        IdealNoteRequest(note="다정한사람" + ZW + ZW)


def test_the_onboarding_bio_must_not_be_blank():
    with pytest.raises(ValidationError):
        BioRequest(bio="   \n ")


def test_a_friend_review_comment_takes_five_lines_but_not_six():
    review = {"reviewee_id": str(uuid4()), "tags": [_TAG]}
    ReviewRequest(**review, comment="\n".join("가" * 5))
    with pytest.raises(ValidationError):
        ReviewRequest(**review, comment="\n".join("가" * 6))


@pytest.mark.parametrize("token", ["", "fcm token"])
def test_a_push_token_is_one_word(token):
    with pytest.raises(ValidationError):
        PushTokenRequest(token=token, platform="android")


def test_a_long_contact_block_number_is_not_a_validation_error():
    """긴 항목은 라우터가 그 자리만 null 로 답한다(11-18 사용자 ②, tests/safety/test_contact_blocks.py)."""
    ContactBlocksRequest(numbers=["0" * 31])
