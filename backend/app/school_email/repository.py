from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.signup_policy import bytea_literal


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

    async def complete_verification(self, profile_id: UUID, email_hmac: bytes, university_id: str,
                                    provider: str) -> str:
        """SQL `complete_school_email_verification` 이 claim 기록과 프로필 표시를 한 트랜잭션에서 한다.

        'ok' · 'already_verified' · 'no_profile', 그 밖에는 이 학교 메일을 이미 쓰는 다른 계정의 provider.
        text 하나를 돌려주는 함수라 본문은 JSON 스칼라다."""
        response = await self._post("rpc/complete_school_email_verification", json={
            "p_profile": str(profile_id), "p_email_hmac": bytea_literal(email_hmac),
            "p_university": university_id, "p_provider": provider,
        })
        raise_for_status(response)
        return response.json()

    async def has_profile(self, user_id: str) -> bool:
        """그 auth 사용자에게 프로필 행이 있는지. 임시 이메일 계정에는 없다. 읽기 실패는 예외로 올린다."""
        response = await self._get("profiles", params={"id": f"eq.{user_id}", "select": "id"})
        raise_for_status(response)
        return bool(response.json())
