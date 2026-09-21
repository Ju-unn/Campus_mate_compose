from uuid import UUID

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class ProfileOnboardingRepository(PostgrestRepository):
    """온보딩 화면들이 쓰는 profiles·profile_private·profile_photos·profile_avatars·survey_answers 를
    PostgREST 로 읽고 쓴다(조각1b StudentVerificationRepository 와 같은 패턴). service_role 키로 직접 호출한다."""

    async def check_nickname_availability(self, nickname: str) -> bool:
        # 유니크 인덱스가 lower(nickname) 이라 ilike(와일드카드 없이)로 대소문자 무시 비교한다.
        response = await self._get("profiles", params={"nickname": f"ilike.{nickname}", "select": "id"})
        raise_for_status(response)
        return len(response.json()) == 0

    async def update_basic_info(
        self, profile_id: UUID, nickname: str, birth_year: int, height_cm: int, gender: str, mbti: str | None
    ) -> None:
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}"},
            json={
                "nickname": nickname, "birth_year": birth_year, "height_cm": height_cm,
                "gender": gender, "mbti": mbti, "nickname_changed_at": "now()",
            },
        )
        raise_for_status(response, conflict_detail=errors.NICKNAME_TAKEN)

    async def update_kakao_id(self, profile_id: UUID, kakao_id: str) -> None:
        response = await self._patch(
            "profile_private",
            params={"profile_id": f"eq.{profile_id}"},
            json={"kakao_id": kakao_id, "updated_at": "now()"},
        )
        raise_for_status(response)

    async def save_photo(
        self, profile_id: UUID, storage_path: str, position: int, is_avatar_source: bool
    ) -> str | None:
        """같은 자리에 다시 올리면 먼저 있던 행을 지우고 새로 넣는다. (profile_id, position) 유니크 제약이
        `deferrable initially deferred` 라서 PostgREST upsert 의 중재자로 쓸 수 없다 — Postgres 가
        "ON CONFLICT does not support deferrable unique constraints" 로 거부한다(로컬 DB 확인, 2026-09-20).
        지워진 행이 가리키던 Storage 경로를 돌려주니 라우터가 그 파일도 같이 지운다."""
        replaced_path = await self.fetch_photo_path(profile_id, position)
        if replaced_path is not None:
            await self.delete_photo_row(profile_id, position)
        if is_avatar_source:
            await self._clear_avatar_source(profile_id)

        response = await self._post(
            "profile_photos",
            json={
                "profile_id": str(profile_id), "storage_path": storage_path,
                "position": position, "is_avatar_source": is_avatar_source,
            },
        )
        raise_for_status(response)
        return replaced_path

    async def _clear_avatar_source(self, profile_id: UUID) -> None:
        """`profile_photos_one_avatar_source` 부분 유니크 인덱스 때문에 새 원본을 넣기 전에 내려야 한다."""
        response = await self._patch(
            "profile_photos",
            params={"profile_id": f"eq.{profile_id}", "is_avatar_source": "eq.true"},
            json={"is_avatar_source": False},
        )
        raise_for_status(response)

    async def fetch_photo_path(self, profile_id: UUID, position: int) -> str | None:
        response = await self._get(
            "profile_photos",
            params={
                "profile_id": f"eq.{profile_id}", "position": f"eq.{position}", "select": "storage_path",
            },
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0]["storage_path"] if rows else None

    async def delete_photo_row(self, profile_id: UUID, position: int) -> None:
        response = await self._delete(
            "profile_photos",
            params={"profile_id": f"eq.{profile_id}", "position": f"eq.{position}"},
        )
        raise_for_status(response)

    async def fetch_avatar_source_photo_path(self, profile_id: UUID) -> str | None:
        response = await self._get(
            "profile_photos",
            params={"profile_id": f"eq.{profile_id}", "is_avatar_source": "eq.true", "select": "storage_path"},
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0]["storage_path"] if rows else None

    async def insert_avatar_attempt(self, profile_id: UUID, status: str, storage_path: str | None) -> None:
        response = await self._post(
            "profile_avatars",
            json={"profile_id": str(profile_id), "status": status, "storage_path": storage_path},
        )
        raise_for_status(response)

    async def has_ready_avatar(self, profile_id: UUID) -> bool:
        """아바타는 한 번만 만든다(2026-09-20 사용자 결정, 하트 차감 재생성은 조각 7).
        `profile_avatars` 주석의 "무료 재생성 횟수는 ready 행 개수로 센다"를 그대로 따른다."""
        response = await self._get(
            "profile_avatars",
            params={
                "profile_id": f"eq.{profile_id}", "status": "eq.ready", "select": "id", "limit": "1",
            },
        )
        raise_for_status(response)
        return len(response.json()) > 0

    async def count_recent_consecutive_avatar_failures(self, profile_id: UUID) -> int:
        response = await self._get(
            "profile_avatars",
            params={"profile_id": f"eq.{profile_id}", "order": "created_at.desc", "select": "status"},
        )
        raise_for_status(response)
        count = 0
        for row in response.json():
            if row["status"] != "failed":
                break
            count += 1
        return count

    async def update_appearance_type(self, profile_id: UUID, animal_type: str, impression_type: str) -> None:
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}"},
            json={"animal_type": animal_type, "impression_type": impression_type},
        )
        raise_for_status(response)

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
        response = await self._post("survey_answers", json=rows, prefer="resolution=merge-duplicates")
        raise_for_status(response)
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

    async def update_ideal_note(self, profile_id: UUID, note: str) -> None:
        # 필수 입력이다(2026-09-20 사용자 결정) — 공백만 쓴 글은 스키마가 422 로 막는다.
        await self._patch_profile(profile_id, {"ideal_note": note.strip()})

    async def save_bio_draft(self, profile_id: UUID, draft: str) -> None:
        await self._patch_profile(profile_id, {"bio_draft": draft, "bio_draft_generated_at": "now()"})

    async def fetch_bio_draft(self, profile_id: UUID) -> str | None:
        """이미 만든 초안이 있으면 본문을 그대로 돌려준다 — 화면을 다시 열었을 때 빈 칸이 되지 않게 한다
        (2026-09-20 리뷰 필수 4). 초안을 새로 만드는 것은 여전히 1회뿐이다."""
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": "bio_draft"})
        raise_for_status(response)
        rows = response.json()
        # 프로필 행이 없을 일은 없지만, 없더라도 500 대신 "초안 없음"으로 본다.
        return rows[0]["bio_draft"] if rows else None

    async def update_bio(self, profile_id: UUID, bio: str) -> None:
        await self._patch_profile(profile_id, {"bio": bio})

    async def activate_profile(self, profile_id: UUID) -> None:
        await self._patch_profile(profile_id, {"status": "active"})

    async def fetch_onboarding_snapshot(self, profile_id: UUID) -> dict:
        profile_response = await self._get(
            "profiles",
            params={
                "id": f"eq.{profile_id}",
                "select": "nickname,gender,animal_type,impression_type,interest_tags,my_traits,religion,"
                          "is_smoker,preferred_age_min,preferred_animal_types,preferred_impression_types,"
                          "ideal_traits,ideal_note,bio",
            },
        )
        raise_for_status(profile_response)
        profile = profile_response.json()[0]

        private_response = await self._get(
            "profile_private",
            params={"profile_id": f"eq.{profile_id}", "select": "phone_number,kakao_id"},
        )
        raise_for_status(private_response)
        private_rows = private_response.json()
        private = private_rows[0] if private_rows else {"phone_number": None, "kakao_id": None}

        photos_response = await self._get(
            "profile_photos",
            params={"profile_id": f"eq.{profile_id}", "select": "is_avatar_source"},
        )
        raise_for_status(photos_response)
        photos = photos_response.json()

        avatars_response = await self._get(
            "profile_avatars",
            params={"profile_id": f"eq.{profile_id}", "status": "eq.ready", "select": "id", "limit": "1"},
        )
        raise_for_status(avatars_response)

        survey_response = await self._get(
            "survey_answers",
            params={"profile_id": f"eq.{profile_id}", "select": "axis"},
        )
        raise_for_status(survey_response)

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
            "ideal_note": (profile["ideal_note"] or "").strip(),
            "bio": profile["bio"],
            "_gender": profile["gender"],
        }

    async def _patch_profile(self, profile_id: UUID, fields: dict) -> None:
        response = await self._patch("profiles", params={"id": f"eq.{profile_id}"}, json=fields)
        raise_for_status(response)
