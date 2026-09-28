from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 카드 자격(14일) · 후보(15일)는 일 단위라 한 시간 정밀도면 충분하다.
_TOUCH_INTERVAL = timedelta(hours=1)


class HomeRepository(PostgrestRepository):
    """홈 09b 가 읽는 두 가지. 서비스 전체 집계는 DB 함수 한 번(`home_stats`), 내 완성도 재료는
    profiles 한 줄 + 사진 개수 embed 로 한 번. 쓰기는 활동 시각 하나뿐이다."""

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

    async def touch_last_active(self, profile_id: UUID) -> None:
        """활동 시각이 한 시간보다 오래됐을 때만 지금으로 바꾼다. 조건을 PostgREST 필터에 걸어
        읽고-비교하고-쓰는 사이 경쟁이 없고, 한 시간 안에 다시 열면 0행 갱신이라 쓰기가 거의 없다."""
        now = datetime.now(timezone.utc)
        response = await self._patch("profiles", params={
            "id": f"eq.{profile_id}",
            "last_active_at": f"lt.{(now - _TOUCH_INTERVAL).isoformat()}",
        }, json={"last_active_at": now.isoformat()}, prefer="return=minimal")
        raise_for_status(response)
