from uuid import UUID

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class MeRepository(PostgrestRepository):
    """화면 15 내 프로필이 읽는 내 행 하나. 아바타·실사진·하트 잔액은 embed 로 같이 가져와 요청 한 번이다.
    profile_private(실명·전화·카카오톡)는 읽지 않는다."""

    async def fetch_profile(self, profile_id: UUID) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}",
            "select": "nickname,nickname_changed_at,bio,birth_year,height_cm,mbti,religion,is_smoker,animal_type,impression_type,major,universities(name),"
                      "preferred_age_min,preferred_age_max,"
                      "preferred_height_min,preferred_height_max,"
                      "interest_tags,my_traits,ideal_traits,"
                      "preferred_mbti_flags,preferred_animal_types,preferred_impression_types,"
                      "entitlements(heart_balance),"
                      "profile_avatars(status,storage_path,created_at),"
                      "profile_photos(id,storage_path,position,is_avatar_source)",
        })
        raise_for_status(response)
        return response.json()[0]

    async def fetch_heart_balance(self, profile_id: UUID) -> int:
        """하트 잔액. entitlements 행은 처음 하트를 받을 때 생긴다 — 없으면 0 이다."""
        response = await self._get("entitlements", params={"profile_id": f"eq.{profile_id}", "select": "heart_balance"})
        raise_for_status(response)
        rows = response.json()
        return rows[0]["heart_balance"] if rows else 0

    async def fetch_photo_rows(self, profile_id: UUID) -> list[dict]:
        response = await self._get("profile_photos", params={
            "profile_id": f"eq.{profile_id}", "select": "id,storage_path,position",
        })
        raise_for_status(response)
        return response.json()

    async def delete_photo_rows(self, profile_id: UUID, ids: list[str]) -> None:
        # profile_id 까지 건다 — id 만으로도 되지만 남의 행에 닿지 않는 한 겹을 더 둔다.
        response = await self._delete("profile_photos", params={
            "profile_id": f"eq.{profile_id}", "id": f"in.({','.join(ids)})",
        })
        raise_for_status(response)

    async def clear_avatar_source(self, profile_id: UUID) -> None:
        """원본 표시는 부분 유니크 인덱스(즉시 검사)라 upsert 한 문장 안에서도 옮기다 부딪힌다 — 먼저 전부 내린다."""
        response = await self._patch("profile_photos", params={
            "profile_id": f"eq.{profile_id}", "is_avatar_source": "eq.true",
        }, json={"is_avatar_source": False})
        raise_for_status(response)

    async def upsert_photo_rows(self, rows: list[dict]) -> None:
        """최종 배치를 **한 문장**으로 쓴다. (profile_id, position) 유니크가 deferred 라 자리 맞바꿈이 커밋 때
        한 번만 검사된다(supabase/tests/me_edit_test.sql). 중재자는 id 다 — deferred 제약은 중재자가 될 수 없다."""
        response = await self._post(
            "profile_photos", json=rows, params={"on_conflict": "id"}, prefer="resolution=merge-duplicates",
        )
        raise_for_status(response)

    async def fetch_nickname_state(self, profile_id: UUID) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}", "select": "nickname,nickname_changed_at",
        })
        raise_for_status(response)
        return response.json()[0]

    async def update_profile(self, profile_id: UUID, fields: dict) -> None:
        response = await self._patch("profiles", params={"id": f"eq.{profile_id}"}, json=fields)
        # 닉네임 유니크(lower) 위반 23505 는 중복 닉네임이다.
        raise_for_status(response, conflict_detail=errors.NICKNAME_TAKEN)
