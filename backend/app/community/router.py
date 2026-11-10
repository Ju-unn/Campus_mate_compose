import logging
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, StringConstraints, field_validator, model_validator

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.cards.router import get_sender
from app.community.comment_push import notify_post_author
from app.community.repository import COMMENT_PAGE_SIZE, POLL_PAGE_SIZE, CommunityRepository, PollTab
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller

logger = logging.getLogger(__name__)

router = APIRouter()

# 응답에 싣는 칸. DB 함수가 author_id 를 주지 않지만 칸이 늘어도 새지 않게 여기서 한 번 더 고른다(익명).
_POLL_KEYS = ("id", "question", "option_a_label", "option_b_label", "created_at",
              "a_count", "b_count", "my_choice", "is_mine", "comment_count")
# 댓글 한 줄. 작성자 id 는 어디에도 없고, 누구인지는 alias_no(익명N) · is_post_author(글쓴이) · is_mine 으로만 알린다.
# add_poll_comment 가 푸시용으로 함께 주는 poll_author_id · poll_question 도 여기서 걸러져 앱 응답에 나가지 않는다.
_COMMENT_KEYS = ("id", "body", "created_at", "alias_no", "is_post_author", "is_mine", "can_delete")


def _card(row: dict) -> dict:
    return {key: row[key] for key in _POLL_KEYS}


def _comment(row: dict) -> dict:
    return {key: row[key] for key in _COMMENT_KEYS}


def _repo(caller: Caller) -> CommunityRepository:
    return CommunityRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.get("/community/polls")
async def list_polls(before: datetime | None = None, before_id: UUID | None = None, tab: PollTab = "all",
                     caller: Caller = Depends(get_verified_caller)) -> dict:
    """15d 피드. 최신 글부터 20개, 전체 학교(사용자 결정 1). 더 내리면 화면 맨 아래 글의
    `created_at` · `id` 를 그대로 보낸다 — 채팅 메시지와 같은 커서다.
    `tab` 은 전체 · 인기 · 내 질문 · 내 투표. 인기는 참여 수 순 한 쪽뿐이라 커서가 없고 "더 없음" 으로 답한다."""
    if (before is None) != (before_id is None):
        # 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼 빈 페이지가 "끝" 으로 읽힌다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    if tab == "popular" and before is not None:
        # 시각 커서로 참여 수 순서를 자르면 엉뚱한 글이 섞인다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    rows = await _repo(caller).fetch_polls(caller.profile_id, before=before, before_id=before_id, tab=tab)
    has_more = tab != "popular" and len(rows) == POLL_PAGE_SIZE
    return {"polls": [_card(row) for row in rows], "has_more": has_more}


@router.get("/community/polls/{poll_id}")
async def get_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17c 상세. 가려진 글 · 떠난 사람의 글은 피드처럼 없다."""
    rows = await _repo(caller).fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0])}


# 앱 pollQuestionMaxLength · pollOptionMaxLength, DB polls_* check 와 같은 값이다.
QUESTION_MAX_LENGTH = 80
OPTION_MAX_LENGTH = 6


class PollRequest(BaseModel):
    question: str = Field(min_length=1, max_length=QUESTION_MAX_LENGTH)
    option_a_label: str = Field(default="찬성", min_length=1, max_length=OPTION_MAX_LENGTH)
    option_b_label: str = Field(default="반대", min_length=1, max_length=OPTION_MAX_LENGTH)

    @field_validator("question", "option_a_label", "option_b_label")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("빈칸뿐인 값은 올릴 수 없다")
        return stripped

    @model_validator(mode="after")
    def _options_differ(self) -> "PollRequest":
        if self.option_a_label == self.option_b_label:
            raise ValueError("두 선택지가 같다")
        return self


class VoteRequest(BaseModel):
    choice: Literal["a", "b"]


@router.post("/community/polls", status_code=201)
async def create_poll(body: PollRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17b. 한국 시간 하루 10개(사용자 결정 3) — 넘으면 429."""
    poll_id = await _repo(caller).create_poll(
        caller.profile_id, body.question, body.option_a_label, body.option_b_label)
    return {"id": poll_id}


@router.post("/community/polls/{poll_id}/votes")
async def vote(poll_id: UUID, body: VoteRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """투표는 되돌릴 수 없다. 하루 첫 투표면 5하트(주 15 상한) — `rewarded` 로 알려 앱이 토스트를 띄운다."""
    repo = _repo(caller)
    rewarded = await repo.cast_vote(poll_id, caller.profile_id, body.choice)
    rows = await repo.fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        # 투표와 다시 읽기 사이에 글이 지워졌다. 투표도 cascade 로 사라졌으니 없는 글과 같게 답한다.
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0]), "rewarded": rewarded}


@router.delete("/community/polls/{poll_id}", status_code=204)
async def delete_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller)) -> Response:
    if not await _repo(caller).delete_poll(poll_id, caller.profile_id):
        # 남의 글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 글이라는 게 샌다.
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return Response(status_code=204)


# DB poll_comments_body_length check 와 같은 값이다. 앱 commentMaxLength 도 같다.
COMMENT_MAX_LENGTH = 200


class CommentRequest(BaseModel):
    body: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=COMMENT_MAX_LENGTH)]


@router.get("/community/polls/{poll_id}/comments")
async def list_comments(poll_id: UUID, after: datetime | None = None, after_id: UUID | None = None,
                        caller: Caller = Depends(get_verified_caller)) -> dict:
    """17c 상세의 댓글. 오래된 순 10개. 더 보려면 마지막 댓글의 `created_at` · `id` 를 `after` · `after_id` 로 그대로 보낸다.
    가려진 글 · 떠난 사람의 글은 404 다."""
    if (after is None) != (after_id is None):
        # 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼 빈 쪽이 "끝" 으로 읽힌다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    # 한 줄 더 받아 다음 쪽이 있는지 정확히 안다 — 딱 10개로 끝나는 글에서 빈 쪽을 한 번 더 부르지 않는다.
    rows = await _repo(caller).fetch_comments(caller.profile_id, poll_id, after=after, after_id=after_id,
                                              limit=COMMENT_PAGE_SIZE + 1)
    return {"items": [_comment(row) for row in rows[:COMMENT_PAGE_SIZE]], "has_more": len(rows) > COMMENT_PAGE_SIZE}


@router.post("/community/polls/{poll_id}/comments", status_code=201)
async def add_comment(poll_id: UUID, body: CommentRequest, caller: Caller = Depends(get_verified_caller),
                      sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now)) -> dict:
    """댓글 쓰기. 한국 시간 하루 50개 — 넘으면 429. 처음 쓰는 사람은 이 글 안의 익명 번호를 받는다.
    글쓴이에게 푸시가 가지만(본인 댓글 · 10분 안 같은 글 · 스위치 꺼짐은 제외) 푸시가 실패해도 댓글은 201 이다."""
    repo = _repo(caller)
    row = await repo.add_comment(caller.profile_id, poll_id, body.body)
    try:
        cards = CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
        await notify_post_author(repo, cards, sender, poll_id=poll_id, poll_author_id=row["poll_author_id"],
                                 question=row["poll_question"], commenter_id=caller.profile_id, now=now)
    except Exception:
        # 댓글은 이미 저장됐다 — 알림 한 건 때문에 201 을 놓치면 앱이 다시 보내 같은 댓글이 두 줄이 된다.
        logger.exception("댓글 푸시 실패 poll=%s comment=%s", poll_id, row["id"])
    return _comment(row)


@router.delete("/community/comments/{comment_id}", status_code=204)
async def delete_comment(comment_id: UUID, caller: Caller = Depends(get_verified_caller)) -> Response:
    """내 댓글, 또는 내 글에 달린 댓글을 지운다(행 삭제)."""
    if not await _repo(caller).delete_comment(caller.profile_id, comment_id):
        # 남의 댓글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 댓글이라는 게 샌다.
        raise HTTPException(status_code=404, detail=errors.POLL_COMMENT_NOT_FOUND)
    return Response(status_code=204)
