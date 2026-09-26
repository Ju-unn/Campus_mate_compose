from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

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
