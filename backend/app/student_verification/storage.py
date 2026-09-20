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

    async def delete(self, path: str) -> bool:
        """확정(verified) 직후 FastAPI가 직접 지운다 — SQL `delete from storage.objects`는 메타 행만 지우고
        실제 파일은 고아로 남는다(Supabase storage/management 문서, 2026-09-20 분석담당 리뷰). 실패해도
        예외를 던지지 않는다 — 인증 자체는 이미 끝났으니 삭제 실패로 응답을 실패시키지 않고, 호출부가
        고아 파일 알림만 보내게 bool 로 알려준다."""
        try:
            response = await self._client.delete(
                f"{self._storage_url}/object/student-id-temp/{path}",
                headers=self._headers,
            )
        except httpx.HTTPError:
            return False
        return response.status_code < 400
