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
            params={"id": f"eq.{profile_id}",
                    "select": "student_verification,department:major,universities(name),status"},
        )
        raise_for_status(response)
        rows = response.json()
        if not rows:
            raise ValueError(f"프로필 행이 없다: {profile_id}")
        return rows[0]

    async def fetch_reject_reason(self, profile_id: UUID) -> str | None:
        response = await self._get(
            "student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "order": "submitted_at.desc", "limit": "1", "select": "reject_reason"},
        )
        raise_for_status(response)
        rows = response.json()
        return rows[0]["reject_reason"] if rows else None

    async def upsert_real_name(self, profile_id: UUID, real_name: str) -> None:
        response = await self._post(
            "profile_private",
            json={"profile_id": str(profile_id), "real_name": real_name, "updated_at": "now()"},
            prefer="resolution=merge-duplicates",
        )
        raise_for_status(response)

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
