import logging
from uuid import UUID

import httpx
from fastapi import HTTPException

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

_logger = logging.getLogger(__name__)

_MATERIAL_COLUMNS = (
    "major,major_field,mbti,animal_type,impression_type,bio,"
    "preferred_animal_types,preferred_impression_types,ideal_note"
)
_OWNER_COLUMNS = (
    "id,status,gender,mbti,preferred_mbti_flags,height_cm,preferred_height_min,preferred_height_max,"
    "birth_year,preferred_age_min,preferred_age_max,is_smoker,religion,"
    "animal_type,impression_type,preferred_animal_types,preferred_impression_types,"
    "profile_vectors(self_facets,want_facets)"
)


class MatchingRepository(PostgrestRepository):
    """매칭 벡터·후보 조회를 PostgREST 로 한다(ProfileOnboardingRepository 와 같은 패턴).
    설계 §6.8 의 "카드 생성은 MatchingRepository 인터페이스 뒤에 둔다"가 이 클래스다."""

    async def fetch_vector_materials(self, profile_id: UUID | str) -> dict:
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": _MATERIAL_COLUMNS})
        raise_for_status(response)
        rows = response.json()
        profile = rows[0] if rows else {}

        answers_response = await self._get(
            "survey_answers",
            params={"profile_id": f"eq.{profile_id}", "select": "axis,value"},
        )
        raise_for_status(answers_response)
        profile["survey_answers"] = {r["axis"]: float(r["value"]) for r in answers_response.json()}
        return profile

    async def save_vectors(self, profile_id: UUID | str, **fields) -> None:
        """한 행 upsert. PostgREST 는 PK 충돌 시 merge-duplicates 로 갱신한다."""
        response = await self._post(
            "profile_vectors",
            json={"profile_id": str(profile_id), "updated_at": "now()", **fields},
            prefer="resolution=merge-duplicates",
        )
        raise_for_status(response)

    async def fetch_owner(self, profile_id: UUID | str) -> dict:
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": _OWNER_COLUMNS})
        raise_for_status(response)
        rows = response.json()
        if not rows:
            # 토큰은 살아 있는데 프로필이 지워졌을 때다 — 500 대신 404 로 말해준다.
            raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
        # 글 정리는 벡터 행에 있다 — 1:1 embed 라 행이 없으면 null 로 온다. scoring 이 profiles 칸처럼 읽게 펼친다.
        owner = rows[0]
        facets = owner.pop("profile_vectors", None) or {}
        return {**owner, "self_facets": facets.get("self_facets"), "want_facets": facets.get("want_facets")}

    async def has_vectors(self, profile_id: UUID | str) -> bool:
        """세 벡터가 다 있어야 match_candidates 가 점수를 낸다 — 없으면 RPC 를 부르지 않는다."""
        response = await self._get(
            "profile_vectors",
            params={
                "profile_id": f"eq.{profile_id}", "select": "profile_id",
                "self_survey": "not.is.null", "self_embedding": "not.is.null",
                "want_embedding": "not.is.null",
            },
        )
        raise_for_status(response)
        return bool(response.json())

    async def fetch_candidates(self, profile_id: UUID | str) -> list[dict]:
        """match_candidates 결과에 후보마다 `taste_clash: bool`(글 속 취향 부딪힘, scoring.TASTE_CLASH_PENALTY)을 붙인다."""
        response = await self._post("rpc/match_candidates", json={"p_owner": str(profile_id)})
        raise_for_status(response)
        candidates = response.json()
        if not candidates:
            return candidates
        clashing = await self._fetch_taste_clashes(profile_id)
        return [{**c, "taste_clash": str(c["candidate_id"]) in clashing} for c in candidates]

    async def _fetch_taste_clashes(self, profile_id: UUID | str) -> set[str]:
        """나와 글 속 취향이 부딪히는 사람의 id. 부딪힘 감점은 덤이라 이 RPC 가 실패하면 로그만 남기고 아무도 안 부딪힌 것으로 본다 —
        카드 지급이 멈추면 안 된다(감점이 빠진 순위로 한 번 나갈 뿐이다)."""
        try:
            response = await self._post("rpc/taste_clash_candidates", json={"p_owner": str(profile_id)})
            raise_for_status(response)
            ids = response.json()
            if not isinstance(ids, list):
                raise ValueError("부딪힘 목록이 배열이 아니다")
            return {str(i) for i in ids}
        except Exception as exc:  # noqa: BLE001 — 위 이유. 응답 내용은 남기지 않는다
            _logger.warning("글 속 취향 부딪힘 조회 실패: profile_id=%s %s", profile_id, type(exc).__name__)
            return set()

    async def fetch_taste_word_ids(self, words: list[str]) -> dict[str, int]:
        """사전(taste_words)에서 단어의 번호를 읽는다. 없는 단어는 결과에 없다."""
        quoted = ",".join(_in_value(w) for w in words)
        response = await self._get("taste_words", params={"select": "id,word", "word": f"in.({quoted})"})
        raise_for_status(response)
        return {row["word"]: row["id"] for row in response.json()}

    async def add_taste_words(self, embeddings: dict[str, list[float]]) -> None:
        """사전에 새 단어를 넣는다. 동시에 같은 단어를 넣은 쪽이 있으면 무시한다(on conflict do nothing) — 넣은 뒤 번호를 다시 읽는다."""
        response = await self._post(
            "taste_words",
            json=[{"word": word, "embedding": embedding} for word, embedding in embeddings.items()],
            params={"on_conflict": "word"}, prefer="resolution=ignore-duplicates,return=minimal",
        )
        raise_for_status(response)


def _in_value(value: str) -> str:
    """PostgREST in.(...) 안의 값. 쉼표 · 괄호 · 점이 있어도 안 깨지게 항상 큰따옴표로 감싸고 안의 백슬래시 · 큰따옴표를 이스케이프한다."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
