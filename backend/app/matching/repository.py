from uuid import UUID

import httpx

from app.profile_onboarding.repository import _raise_for_status

_MATERIAL_COLUMNS = (
    "major,major_field,mbti,animal_type,impression_type,bio,"
    "preferred_animal_types,preferred_impression_types,ideal_note"
)
_OWNER_COLUMNS = (
    "id,gender,mbti,preferred_mbti_flags,height_cm,preferred_height_min,preferred_height_max,"
    "birth_year,preferred_age_min,preferred_age_max,is_smoker,religion"
)


class MatchingRepository:
    """매칭 벡터·후보 조회를 PostgREST 로 한다(ProfileOnboardingRepository 와 같은 패턴).
    설계 §6.8 의 "카드 생성은 MatchingRepository 인터페이스 뒤에 둔다"가 이 클래스다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def fetch_vector_materials(self, profile_id: UUID | str) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": _MATERIAL_COLUMNS},
            headers=self._headers,
        )
        _raise_for_status(response)
        rows = response.json()
        profile = rows[0] if rows else {}

        answers_response = await self._client.get(
            f"{self._postgrest_url}/survey_answers",
            params={"profile_id": f"eq.{profile_id}", "select": "axis,value"},
            headers=self._headers,
        )
        _raise_for_status(answers_response)
        profile["survey_answers"] = {r["axis"]: float(r["value"]) for r in answers_response.json()}
        return profile

    async def save_vectors(self, profile_id: UUID | str, **fields) -> None:
        """한 행 upsert. PostgREST 는 PK 충돌 시 merge-duplicates 로 갱신한다."""
        response = await self._client.post(
            f"{self._postgrest_url}/profile_vectors",
            json={"profile_id": str(profile_id), "updated_at": "now()", **fields},
            headers={**self._headers, "Prefer": "resolution=merge-duplicates"},
        )
        _raise_for_status(response)

    async def fetch_owner(self, profile_id: UUID | str) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": _OWNER_COLUMNS},
            headers=self._headers,
        )
        _raise_for_status(response)
        return response.json()[0]

    async def fetch_candidates(self, profile_id: UUID | str) -> list[dict]:
        response = await self._client.post(
            f"{self._postgrest_url}/rpc/match_candidates",
            json={"p_owner": str(profile_id)},
            headers=self._headers,
        )
        _raise_for_status(response)
        return response.json()
