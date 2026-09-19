from uuid import UUID, uuid4

import httpx


class StudentIdStorage:
    """`student-id-temp` 비공개 버킷에 업로드한다(설계 §7.4). 삭제는 이 클래스가 하지 않는다 —
    profiles.student_verification 이 확정되는 순간 Postgres 트리거가 대신 지운다(2026-09-19 설계)."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def upload(self, profile_id: UUID, data: bytes, content_type: str) -> str:
        # 사람이 대시보드에서 내려받아 여는 파일이라 확장자가 실제 형식과 맞아야 한다.
        extension = "png" if content_type == "image/png" else "jpg"
        path = f"{profile_id}/{uuid4()}.{extension}"
        response = await self._client.post(
            f"{self._storage_url}/object/student-id-temp/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        response.raise_for_status()
        return path
