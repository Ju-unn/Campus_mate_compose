from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 차단 목록(16f)은 한 번에 다 준다. PostgREST db-max-rows 에 조용히 잘리지 않게 상한을 우리가 정한다
# (chat `_CONVERSATION_LIMIT` 과 같은 이유).
BLOCK_LIST_LIMIT = 200


class SafetyRepository(PostgrestRepository):
    """조각 6 의 두 테이블(blocks · reports)의 출입구. 둘 다 클라이언트는 읽지도 못한다(설계 §7.2)."""

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    # 차단 -------------------------------------------------------------------
    async def insert_block(self, blocker_id: UUID | str, blocked_id: UUID | str) -> None:
        """이미 있으면 조용히 성공(on conflict do nothing) — 재시도와 '신고 = 차단' 이 두 번 불러도 안전하다."""
        response = await self._post(
            "blocks", json={"blocker_id": str(blocker_id), "blocked_id": str(blocked_id)},
            params={"on_conflict": "blocker_id,blocked_id"},
            prefer="resolution=ignore-duplicates,return=minimal",
        )
        raise_for_status(response)

    async def delete_block(self, blocker_id: UUID | str, blocked_id: UUID | str) -> None:
        """없어도 성공이다. 대화는 복구하지 않는다(16f) — left_at 은 건드리지 않는다."""
        response = await self._delete("blocks", params={
            "blocker_id": f"eq.{blocker_id}", "blocked_id": f"eq.{blocked_id}",
        })
        raise_for_status(response)

    async def fetch_blocks(self, blocker_id: UUID | str) -> list[dict]:
        """내가 막은 사람 + 닉네임 · 아바타. blocks 는 profiles 를 두 번 가리켜서(blocker · blocked)
        어느 쪽을 붙일지 FK 칸 이름으로 짚어 준다. 실사진은 가져오지 않는다."""
        return await self._rows("blocks", {
            "blocker_id": f"eq.{blocker_id}",
            "select": "blocked_id,created_at,"
                      "profile:profiles!blocked_id(nickname,profile_avatars(storage_path,status,created_at))",
            "order": "created_at.desc",
            "limit": BLOCK_LIST_LIMIT,
        })
