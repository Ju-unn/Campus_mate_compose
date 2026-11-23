"""(created_at, id) 커서 짝 검사 — 커뮤니티 피드 · 댓글 · 공지 목록 · 관리자 공지 목록이 같이 쓴다."""
from datetime import datetime
from uuid import UUID

from fastapi import HTTPException

from app.core import errors


def check_cursor(at: datetime | None, at_id: UUID | None) -> None:
    """시각과 id 는 함께 오거나 함께 없어야 한다. 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼
    빈 쪽이 "끝" 으로 읽힌다 — 422."""
    if (at is None) != (at_id is None):
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
