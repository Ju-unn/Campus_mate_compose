from datetime import datetime
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
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

    async def create_poll(self, author: UUID, question: str, option_a: str, option_b: str) -> str:
        response = await self._post("rpc/create_poll", json={
            "p_author": str(author), "p_question": question, "p_option_a": option_a, "p_option_b": option_b,
        })
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.POLL_DAILY_LIMIT)
        raise_for_status(response)
        return response.json()

    async def cast_vote(self, poll_id: UUID, voter: UUID, choice: str) -> bool:
        """투표 + 하루 첫 투표 보상을 DB 한 트랜잭션에서. 돌려주는 값 = 하트를 줬는가."""
        response = await self._post("rpc/cast_poll_vote", json={
            "p_poll_id": str(poll_id), "p_voter": str(voter), "p_choice": choice,
        })
        # CM404 = 투표 전 확인에서 없음. 23503 = 확인과 insert 사이에 글이 지워져 FK 가 깨짐 — 둘 다 "없는 글" 이다.
        # 23503 을 그냥 두면 raise_for_status 가 422 "입력한 값을 다시 확인해 주세요" 를 낸다.
        if error_code(response) in ("CM404", "23503"):
            raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
        raise_for_status(response, conflict_detail=errors.POLL_ALREADY_VOTED)
        return response.json()

    async def delete_poll(self, poll_id: UUID, author: UUID) -> bool:
        """본인 글이면 지우고 참. 투표는 cascade 로 같이 지워진다(사용자 결정 2)."""
        # 지워진 행을 돌려받아야 "없었다" 와 "지웠다" 를 가른다 — 부모 _delete 는 Prefer 를 받지 않는다.
        response = await self._client.delete(
            f"{self._postgrest_url}/polls",
            params={"id": f"eq.{poll_id}", "author_id": f"eq.{author}", "select": "id"},
            headers=self._with_prefer("return=representation"),
        )
        raise_for_status(response)
        return bool(response.json())
