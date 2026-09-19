from uuid import UUID

import httpx


class StudentVerificationRepository:
    """학생증 인증 상태를 PostgREST 로 읽고 쓴다 (설계 §7.4). service_role 키로 직접 호출한다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def fetch_gate_status(self, profile_id: UUID) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": "student_verification,department,universities(name)"},
            headers=self._headers,
        )
        response.raise_for_status()
        return response.json()[0]

    async def fetch_reject_reason(self, profile_id: UUID) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "order": "submitted_at.desc", "limit": "1", "select": "reject_reason"},
            headers=self._headers,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["reject_reason"] if rows else None

    async def upsert_real_name(self, profile_id: UUID, real_name: str) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/profile_private",
            json={"profile_id": str(profile_id), "real_name": real_name, "updated_at": "now()"},
            headers={**self._headers, "Prefer": "resolution=merge-duplicates"},
        )
        response.raise_for_status()

    async def record_attempt(self, profile_id: UUID, file_path: str, result: str) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/student_verification_attempts",
            json={"profile_id": str(profile_id), "file_path": file_path, "result": result},
            headers=self._headers,
        )
        response.raise_for_status()

    async def update_attempt_result(self, profile_id: UUID, file_path: str, result: str) -> None:
        # 자동 통과한 시도는 여기서 확정한다 — 그래야 result='pending' 행이 사람이 볼 재검토 대기열로만 남는다.
        response = await self._client.patch(
            f"{self._postgrest_url}/student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "file_path": f"eq.{file_path}"},
            json={"result": result},
            headers=self._headers,
        )
        response.raise_for_status()

    async def update_verification_status(self, profile_id: UUID, status: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"student_verification": status},
            headers=self._headers,
        )
        response.raise_for_status()

    async def save_school_info(self, profile_id: UUID, department: str, student_number: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"department": department, "student_number": student_number},
            headers=self._headers,
        )
        response.raise_for_status()
