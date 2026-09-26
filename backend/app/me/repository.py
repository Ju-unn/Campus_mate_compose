from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class MeRepository(PostgrestRepository):
    """화면 15 내 프로필이 읽는 내 행 하나. 아바타·실사진은 embed 로 같이 가져와 요청 한 번이다.
    profile_private(실명·전화·카카오톡)는 읽지 않는다."""

    async def fetch_profile(self, profile_id: UUID) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}",
            "select": "nickname,bio,birth_year,height_cm,mbti,major,universities(name),"
                      "preferred_age_min,preferred_age_max,"
                      "preferred_height_min,preferred_height_max,"
                      "profile_avatars(status,storage_path,created_at),profile_photos(storage_path,position)",
        })
        raise_for_status(response)
        return response.json()[0]
