from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.signup_policy import bytea_literal

_TABLE = "graduate_verification_requests"
# 결정과 함께 비우는 평문 세 칸. DB check 도 결정된 줄에는 이 칸이 비어 있을 것을 요구한다.
_PLAINTEXT_CLEARED = {"ocr_document_number": None, "ocr_school_text": None, "previous_school_email": None}


def attempts_used(history: list[dict]) -> int:
    """재신청 횟수에 드는 신청 수(D3) — 만료로 닫힌 것(cancelled · expired)만 뺀다. fetch_history 의 줄을 받는다."""
    return sum(1 for row in history if not (row["status"] == "cancelled" and row["reason"] == "expired"))


class GraduateRequestRepository(PostgrestRepository):
    """졸업생 인증 신청(graduate_verification_requests)과 프로필의 인증 방법 칸. service_role 키로 PostgREST 를 직접 부른다."""

    async def insert_pending(
        self, *, request_id: UUID, profile_id: UUID, photo_path: str, ocr_state: str,
        ocr_document_number: str | None, ocr_school_text: str | None, previous_school_email: str | None,
        document_hmac: bytes | None, key_version: int,
    ) -> None:
        """대기 신청 한 줄. 프로필에 이미 대기가 있으면(유일 인덱스 23505) 409 다 — 거의 동시에 두 번 눌렀을 때."""
        response = await self._post(_TABLE, json={
            "id": str(request_id), "profile_id": str(profile_id), "photo_path": photo_path, "ocr_state": ocr_state,
            "ocr_document_number": ocr_document_number, "ocr_school_text": ocr_school_text,
            "previous_school_email": previous_school_email,
            "document_hmac": None if document_hmac is None else bytea_literal(document_hmac),
            "key_version": key_version,
        })
        raise_for_status(response)

    async def fetch_history(self, profile_id: UUID) -> list[dict]:
        """그 사람의 신청 전부(id · status · reason · created_at), 최근 순 — 읽기 한 번으로 상태 · 대기 여부 · 횟수를 다 안다.
        ponytail: 100줄까지. 만료는 14일에 한 번이라 한 사람이 100줄을 넘기려면 3년이 걸린다."""
        return await self._rows({
            "profile_id": f"eq.{profile_id}", "select": "id,status,reason,created_at",
            "order": "created_at.desc", "limit": "100",
        })

    async def cancel_pending(self, profile_id: UUID, reason: str, now: datetime) -> dict | None:
        """대기 신청을 한 번의 PATCH 로 취소하고 평문 세 칸을 비운다. 돌려주는 행에 photo_path 가 있어 부른 쪽이 사진을 지운다.
        대기가 없으면 None. status=eq.pending 조건이라 이미 결정된 줄은 건드리지 않는다."""
        response = await self._patch(
            _TABLE,
            params={"profile_id": f"eq.{profile_id}", "status": "eq.pending", "select": "id,photo_path"},
            json={"status": "cancelled", "reason": reason, "decided_at": now.isoformat(), **_PLAINTEXT_CLEARED},
            prefer="return=representation",
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def clear_photo_path(self, request_id: UUID | str) -> None:
        """사진을 지운 뒤 경로를 비운다. 대기 줄은 사진이 있어야 해서(DB check) 결정된 줄만 건드린다."""
        response = await self._patch(
            _TABLE, params={"id": f"eq.{request_id}", "status": "neq.pending"}, json={"photo_path": None})
        raise_for_status(response)

    async def fetch_pending_older_than(self, cutoff: datetime, limit: int) -> list[dict]:
        """cutoff 이전에 낸 대기 신청, 오래된 순. 14일 만료 배치가 쓴다."""
        return await self._rows({
            "status": "eq.pending", "created_at": f"lte.{cutoff.isoformat()}",
            "select": "id,profile_id,photo_path", "order": "created_at.asc", "limit": str(limit),
        })

    async def fetch_pending_of_verified(self, limit: int) -> list[dict]:
        """학교 메일 인증 등으로 이미 통과한 사람의 대기 신청. 다른 길로 통과했으니 이 신청은 닫는다."""
        return await self._rows({
            "status": "eq.pending", "profiles.school_email_verified_at": "not.is.null",
            "select": "id,profile_id,photo_path,profiles!inner(school_email_verified_at)",
            "order": "created_at.asc", "limit": str(limit),
        })

    async def fetch_decided_with_photo(self, limit: int) -> list[dict]:
        """결정이 났는데 사진 경로가 남은 줄(삭제 실패 · 서버 중단). 매시 배치가 다시 지운다."""
        return await self._rows({
            "status": "neq.pending", "photo_path": "not.is.null",
            "select": "id,photo_path", "order": "created_at.asc", "limit": str(limit),
        })

    async def set_method(self, profile_id: UUID, method: str | None) -> None:
        """인증 길 값 쓰기. 아직 인증 전인 사람만 바뀐다 — 앞 관문 검사와 이 쓰기 사이에 학교 메일 · 졸업생 인증이 끝난 사람의 값은
        덮지 않는다(조건에 안 맞으면 0줄이 바뀌고 오류는 아니다)."""
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}", "school_email_verified_at": "is.null", "graduate_verified_at": "is.null"},
            json={"verification_method": method},
        )
        raise_for_status(response)

    async def fetch_university_names(self) -> list[dict]:
        response = await self._get("universities", params={"select": "id,name"})
        raise_for_status(response)
        return response.json()

    async def _rows(self, params: dict) -> list[dict]:
        response = await self._get(_TABLE, params=params)
        raise_for_status(response)
        return response.json()
