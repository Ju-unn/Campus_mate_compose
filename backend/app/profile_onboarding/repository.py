from uuid import UUID

import httpx


class ProfileOnboardingRepository:
    """온보딩 화면들이 쓰는 profiles·profile_private·profile_photos·profile_avatars·survey_answers 를
    PostgREST 로 읽고 쓴다(조각1b StudentVerificationRepository 와 같은 패턴). service_role 키로 직접 호출한다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def check_nickname_availability(self, nickname: str) -> bool:
        # 유니크 인덱스가 lower(nickname) 이라 ilike(와일드카드 없이)로 대소문자 무시 비교한다.
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"nickname": f"ilike.{nickname}", "select": "id"},
            headers=self._headers,
        )
        response.raise_for_status()
        return len(response.json()) == 0

    async def update_basic_info(
        self, profile_id: UUID, nickname: str, birth_year: int, height_cm: int, gender: str, mbti: str | None
    ) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={
                "nickname": nickname, "birth_year": birth_year, "height_cm": height_cm,
                "gender": gender, "mbti": mbti, "nickname_changed_at": "now()",
            },
            headers=self._headers,
        )
        if response.status_code == 409:
            raise ValueError("이미 있는 닉네임이에요")
        response.raise_for_status()

    async def update_kakao_id(self, profile_id: UUID, kakao_id: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profile_private",
            params={"profile_id": f"eq.{profile_id}"},
            json={"kakao_id": kakao_id, "updated_at": "now()"},
            headers=self._headers,
        )
        response.raise_for_status()

    async def insert_photo(self, profile_id: UUID, storage_path: str, position: int, is_avatar_source: bool) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/profile_photos",
            json={
                "profile_id": str(profile_id), "storage_path": storage_path,
                "position": position, "is_avatar_source": is_avatar_source,
            },
            headers=self._headers,
        )
        response.raise_for_status()

    async def fetch_avatar_source_photo_path(self, profile_id: UUID) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/profile_photos",
            params={"profile_id": f"eq.{profile_id}", "is_avatar_source": "eq.true", "select": "storage_path"},
            headers=self._headers,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["storage_path"] if rows else None

    async def insert_avatar_attempt(self, profile_id: UUID, status: str, storage_path: str | None) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/profile_avatars",
            json={"profile_id": str(profile_id), "status": status, "storage_path": storage_path},
            headers=self._headers,
        )
        response.raise_for_status()

    async def count_recent_consecutive_avatar_failures(self, profile_id: UUID) -> int:
        response = await self._client.get(
            f"{self._postgrest_url}/profile_avatars",
            params={"profile_id": f"eq.{profile_id}", "order": "created_at.desc", "select": "status"},
            headers=self._headers,
        )
        response.raise_for_status()
        count = 0
        for row in response.json():
            if row["status"] != "failed":
                break
            count += 1
        return count

    async def update_appearance_type(self, profile_id: UUID, animal_type: str, impression_type: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"animal_type": animal_type, "impression_type": impression_type},
            headers=self._headers,
        )
        response.raise_for_status()

    async def update_interests(self, profile_id: UUID, tags: list[str]) -> None:
        await self._patch_profile(profile_id, {"interest_tags": tags})

    async def update_my_traits(self, profile_id: UUID, tags: list[str]) -> None:
        await self._patch_profile(profile_id, {"my_traits": tags})

    async def update_ideal_traits(self, profile_id: UUID, tags: list[str]) -> None:
        await self._patch_profile(profile_id, {"ideal_traits": tags})

    async def insert_survey_answers(
        self, profile_id: UUID, answers: dict[int, float], religion: str, is_smoker: bool
    ) -> None:
        rows = [{"profile_id": str(profile_id), "axis": axis, "value": value} for axis, value in answers.items()]
        response = await self._client.post(
            f"{self._postgrest_url}/survey_answers",
            json=rows,
            headers={**self._headers, "Prefer": "resolution=merge-duplicates"},
        )
        response.raise_for_status()
        await self._patch_profile(profile_id, {"religion": religion, "is_smoker": is_smoker})

    async def update_ideal_conditions(
        self,
        profile_id: UUID,
        preferred_age_min: int,
        preferred_age_max: int,
        preferred_height_min: int | None,
        preferred_height_max: int | None,
        preferred_mbti_flags: dict[str, bool],
        preferred_animal_types: list[str],
        preferred_impression_types: list[str],
    ) -> None:
        await self._patch_profile(profile_id, {
            "preferred_age_min": preferred_age_min,
            "preferred_age_max": preferred_age_max,
            "preferred_height_min": preferred_height_min,
            "preferred_height_max": preferred_height_max,
            "preferred_mbti_flags": preferred_mbti_flags,
            "preferred_animal_types": preferred_animal_types,
            "preferred_impression_types": preferred_impression_types,
        })

    async def update_ideal_note(self, profile_id: UUID, note: str | None) -> None:
        # 건너뛰어도 빈 문자열로 저장한다 — null 은 "아직 이 화면에 온 적 없다"와 구분이 안 되기 때문이다
        # (profiles.ideal_note_seen 컬럼을 새로 만들지 않고 이 컬럼 하나로 두 상태를 나눈다, 2026-09-20 결정).
        await self._patch_profile(profile_id, {"ideal_note": note or ""})

    async def mark_bio_draft_generated(self, profile_id: UUID) -> None:
        await self._patch_profile(profile_id, {"bio_draft_generated_at": "now()"})

    async def fetch_bio_draft_generated_at(self, profile_id: UUID) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": "bio_draft_generated_at"},
            headers=self._headers,
        )
        response.raise_for_status()
        return response.json()[0]["bio_draft_generated_at"]

    async def update_bio(self, profile_id: UUID, bio: str) -> None:
        await self._patch_profile(profile_id, {"bio": bio})

    async def activate_profile(self, profile_id: UUID) -> None:
        await self._patch_profile(profile_id, {"status": "active"})

    async def fetch_onboarding_snapshot(self, profile_id: UUID) -> dict:
        profile_response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={
                "id": f"eq.{profile_id}",
                "select": "nickname,gender,animal_type,impression_type,interest_tags,my_traits,religion,"
                          "is_smoker,preferred_age_min,preferred_animal_types,preferred_impression_types,"
                          "ideal_traits,ideal_note,bio",
            },
            headers=self._headers,
        )
        profile_response.raise_for_status()
        profile = profile_response.json()[0]

        private_response = await self._client.get(
            f"{self._postgrest_url}/profile_private",
            params={"profile_id": f"eq.{profile_id}", "select": "phone_number,kakao_id"},
            headers=self._headers,
        )
        private_response.raise_for_status()
        private_rows = private_response.json()
        private = private_rows[0] if private_rows else {"phone_number": None, "kakao_id": None}

        photos_response = await self._client.get(
            f"{self._postgrest_url}/profile_photos",
            params={"profile_id": f"eq.{profile_id}", "select": "is_avatar_source"},
            headers=self._headers,
        )
        photos_response.raise_for_status()
        photos = photos_response.json()

        avatars_response = await self._client.get(
            f"{self._postgrest_url}/profile_avatars",
            params={"profile_id": f"eq.{profile_id}", "status": "eq.ready", "select": "id", "limit": "1"},
            headers=self._headers,
        )
        avatars_response.raise_for_status()

        survey_response = await self._client.get(
            f"{self._postgrest_url}/survey_answers",
            params={"profile_id": f"eq.{profile_id}", "select": "axis"},
            headers=self._headers,
        )
        survey_response.raise_for_status()

        return {
            "nickname": profile["nickname"],
            "phone_set": private["phone_number"] is not None,
            "kakao_id_set": private["kakao_id"] is not None,
            "photo_count": len(photos),
            "has_avatar_source": any(p["is_avatar_source"] for p in photos),
            "avatar_ready": len(avatars_response.json()) > 0,
            "animal_type": profile["animal_type"],
            "impression_type": profile["impression_type"],
            "interest_tags": profile["interest_tags"],
            "my_traits": profile["my_traits"],
            "survey_answer_count": len(survey_response.json()),
            "religion": profile["religion"],
            "is_smoker": profile["is_smoker"],
            "preferred_age_min": profile["preferred_age_min"],
            "preferred_animal_types": profile["preferred_animal_types"],
            "preferred_impression_types": profile["preferred_impression_types"],
            "ideal_traits": profile["ideal_traits"],
            "ideal_note_seen": profile["ideal_note"] is not None,
            "bio": profile["bio"],
            "_gender": profile["gender"],
        }

    async def _patch_profile(self, profile_id: UUID, fields: dict) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json=fields,
            headers=self._headers,
        )
        response.raise_for_status()
