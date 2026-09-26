from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, field_validator, model_validator

from app.community.repository import POLL_PAGE_SIZE, CommunityRepository
from app.core import errors
from app.core.deps import Caller, get_verified_caller

router = APIRouter()

# 응답에 싣는 칸. DB 함수가 author_id 를 주지 않지만 칸이 늘어도 새지 않게 여기서 한 번 더 고른다(익명).
_POLL_KEYS = ("id", "question", "option_a_label", "option_b_label", "created_at",
              "a_count", "b_count", "my_choice", "is_mine")


def _card(row: dict) -> dict:
    return {key: row[key] for key in _POLL_KEYS}


def _repo(caller: Caller) -> CommunityRepository:
    return CommunityRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.get("/community/polls")
async def list_polls(before: datetime | None = None, before_id: UUID | None = None,
                     caller: Caller = Depends(get_verified_caller)) -> dict:
    """15d 피드. 최신 글부터 20개, 전체 학교(사용자 결정 1). 더 내리면 화면 맨 아래 글의
    `created_at` · `id` 를 그대로 보낸다 — 채팅 메시지와 같은 커서다."""
    if (before is None) != (before_id is None):
        # 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼 빈 페이지가 "끝" 으로 읽힌다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    rows = await _repo(caller).fetch_polls(caller.profile_id, before=before, before_id=before_id)
    return {"polls": [_card(row) for row in rows], "has_more": len(rows) == POLL_PAGE_SIZE}


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
    """투표는 되돌릴 수 없다. 하루 첫 투표면 10하트(주 30 상한) — `rewarded` 로 알려 앱이 토스트를 띄운다."""
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
