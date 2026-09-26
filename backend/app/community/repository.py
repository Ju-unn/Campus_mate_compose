from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 한 번에 내려주는 질문 수. 앱 pollPageSize 와 같은 값이다.
POLL_PAGE_SIZE = 20


class CommunityRepository(PostgrestRepository):
    """커뮤니티 질문 · 투표. 읽기와 쓰기가 DB 함수(RPC)를 거친다 — 집계 · 작성자 숨기기 · 하루 한도 ·
    투표 보상이 DB 한 곳에 있다(마이그레이션 20260927020100). 삭제만 PostgREST 로 바로 한다."""

    async def fetch_polls(self, viewer: UUID, *, poll_id: UUID | None = None,
                          before: datetime | None = None, before_id: UUID | None = None,
                          limit: int = POLL_PAGE_SIZE) -> list[dict]:
        response = await self._post("rpc/poll_feed", json={
            "p_viewer": str(viewer),
            "p_poll_id": str(poll_id) if poll_id else None,
            "p_before": before.isoformat() if before else None,
            "p_before_id": str(before_id) if before_id else None,
            "p_limit": limit,
        })
        raise_for_status(response)
        return response.json()
