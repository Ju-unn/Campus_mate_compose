from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


class StudentVerificationRepository(PostgrestRepository):
    """학생증 인증 상태를 PostgREST 로 읽고 쓴다 (설계 §7.4). service_role 키로 직접 호출한다."""

    async def fetch_gate_status(self, profile_id: UUID) -> dict:
        response = await self._get(
            "profiles",
            # 학과는 온보딩이 이미 채우는 profiles.major 를 그대로 쓴다. API·클라이언트가 아는 이름은
            # department 라서 PostgREST 별칭으로 돌려준다(alias:column). status 는 조각 6 정지 관문이 본다.
            # school_email_verified_at 은 학교 메일 관문(소셜 로그인 전환)이 본다 — NULL 이면 확인 전.
            # verification_method · graduate_verified_at 은 졸업생 인증 길(GET /me/verification-status 의 새 칸)이 본다.
            params={"id": f"eq.{profile_id}",
                    "select": "student_verification,department:major,universities(name),status,"
                              "school_email_verified_at,verification_method,graduate_verified_at"},
        )
        raise_for_status(response)
        rows = response.json()
        if not rows:
            raise ValueError(f"프로필 행이 없다: {profile_id}")
        return rows[0]

    async def fetch_status(self, profile_id: UUID) -> str | None:
        """로그인만 보는 관문의 탈퇴 확인. 행이나 칸이 없으면 None(= 막지 않는다, 정지 관문과 같은 규칙)."""
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": "status"})
        raise_for_status(response)
        rows = response.json()
        return rows[0].get("status") if rows else None

    async def fetch_reject_reason(self, profile_id: UUID) -> str | None:
        response = await self._get(
            "student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "order": "submitted_at.desc", "limit": "1", "select": "reject_reason"},
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0]["reject_reason"] if rows else None

    async def record_attempt(self, profile_id: UUID, file_path: str, result: str) -> None:
        response = await self._post(
            "student_verification_attempts",
            json={"profile_id": str(profile_id), "file_path": file_path, "result": result},
        )
        raise_for_status(response)

    async def update_attempt_result(self, profile_id: UUID, file_path: str, result: str) -> None:
        # 자동 통과한 시도는 여기서 확정한다 — 그래야 result='pending' 행이 사람이 볼 재검토 대기열로만 남는다.
        response = await self._patch(
            "student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "file_path": f"eq.{file_path}"},
            # reviewed_at 은 "대조·재검토가 끝난 시각"이라 확정과 같은 요청에서 채운다(마이그레이션 주석).
            json={"result": result, "reviewed_at": "now()"},
        )
        raise_for_status(response)

    async def update_verification_status(self, profile_id: UUID, status: str) -> None:
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}"},
            json={"student_verification": status},
        )
        raise_for_status(response)

    async def save_school_info(self, profile_id: UUID, department: str, student_number: str) -> None:
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}"},
            # 컬럼 이름은 major 다 — department 는 API·클라이언트 쪽 이름이라 여기서만 바꿔 준다.
            json={"major": department, "student_number": student_number},
        )
        raise_for_status(response)

    async def fetch_latest_attempt(self, profile_id: UUID) -> dict | None:
        """가장 최근 제출 한 줄(id · file_path · reject_reason · result). 인증이 끝날 때까지 새 제출이 막혀 있어 이 줄이 지금 심사 대상이다."""
        response = await self._get(
            "student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "order": "submitted_at.desc", "limit": "1",
                    "select": "id,file_path,reject_reason,result"},
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def fetch_attempt_by_path(self, file_path: str) -> dict | None:
        response = await self._get(
            "student_verification_attempts",
            params={"file_path": f"eq.{file_path}", "select": "id,result", "limit": "1"},
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def fetch_pending_attempts_submitted_by(self, cutoff: datetime, limit: int) -> list[dict]:
        """cutoff 이전에 내서 아직 대기 중인 시도(오래된 것부터). 기한 만료 정리가 쓴다."""
        response = await self._get(
            "student_verification_attempts",
            params={"result": "eq.pending", "submitted_at": f"lte.{cutoff.isoformat()}",
                    "order": "submitted_at", "limit": str(limit), "select": "id,profile_id,file_path"},
        )
        raise_for_status(response)
        return response.json()

    async def close_attempt(self, attempt_id: int, reason: str, now: datetime) -> None:
        """대기 중인 시도를 반려로 닫는다. result=pending 조건이 붙어 있어 이미 확정된 행은 건드리지 않는다."""
        response = await self._patch(
            "student_verification_attempts",
            params={"id": f"eq.{attempt_id}", "result": "eq.pending"},
            json={"result": "rejected", "reject_reason": reason, "reviewed_at": now.isoformat()},
        )
        raise_for_status(response)

    async def reopen_attempt(self, attempt_id: int) -> None:
        """close_attempt 를 되돌린다(프로필을 못 바꿨을 때). 내일 배치가 다시 고른다. 반려 상태인 행만 되돌린다."""
        response = await self._patch(
            "student_verification_attempts",
            params={"id": f"eq.{attempt_id}", "result": "eq.rejected"},
            json={"result": "pending", "reject_reason": None, "reviewed_at": None},
        )
        raise_for_status(response)

    async def reject_profile_if_pending(self, profile_id: UUID) -> None:
        """사람이 이미 확정한 프로필(verified 등)은 덮어쓰지 않는다."""
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}", "student_verification": "eq.pending"},
            json={"student_verification": "rejected"},
        )
        raise_for_status(response)
