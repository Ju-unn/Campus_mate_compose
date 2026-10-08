from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class SchoolEmailRepository(PostgrestRepository):
    """profiles 의 학교 메일 확인 칸(university_id · school_email_verified_at). service_role 로만 읽고 쓴다."""

    async def fetch_state(self, profile_id: UUID) -> dict:
        """정지 관문이 볼 status 와 이미 확인했는지(school_email_verified_at). 행이 없으면 빈 dict(= 막지 않는다)."""
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}", "select": "status,school_email_verified_at",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else {}

    async def record_verified(self, profile_id: UUID, university_id: str, verified_at: datetime) -> None:
        """학교와 확인 시각을 쓴다. `school_email_verified_at is null` 조건을 요청에 걸어 먼저 쓴 값을 덮지 않는다."""
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}", "school_email_verified_at": "is.null"},
            json={"university_id": university_id, "school_email_verified_at": verified_at.isoformat()},
        )
        raise_for_status(response)

