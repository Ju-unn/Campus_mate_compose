from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class HomeRepository(PostgrestRepository):
    """홈 09b 가 읽는 두 가지. 서비스 전체 집계는 DB 함수 한 번(`home_stats`), 내 완성도 재료는
    profiles 한 줄 + 사진 개수 embed 로 한 번 — 둘 다 읽기만 한다."""

    async def fetch_stats(self) -> dict:
        # 단일 행 테이블 함수라 PostgREST 는 한 행짜리 배열로 준다.
        response = await self._post("rpc/home_stats", json={})
        raise_for_status(response)
        return response.json()[0]

    async def fetch_completion_materials(self, profile_id: UUID) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}",
            "select": "mbti,preferred_height_min,preferred_height_max,interest_tags,profile_photos(count)",
        })
        raise_for_status(response)
        return response.json()[0]
