from uuid import UUID

import httpx

from app.core.http import raise_for_status

BUCKET = "graduate-cert-temp"


class GraduateCertStorage:
    """`graduate-cert-temp` 비공개 버킷. 올리기 · 지우기 모두 서버가 service_role 로 한다.
    사진은 결정(승인 · 반려 · 취소 · 만료) 즉시 지운다. 모양은 student_verification/storage.py · heart_tasks/storage.py 와 같다."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}
        self._client = client

    async def upload(self, profile_id: UUID, request_id: UUID, data: bytes, content_type: str) -> str:
        # 관리자가 내려받아 여는 파일이라 확장자가 실제 형식과 맞아야 한다. `{profile_id}/` 한 층은 탈퇴 정리가 폴더째 지운다.
        extension = "png" if content_type == "image/png" else "jpg"
        path = f"{profile_id}/{request_id}.{extension}"
        response = await self._client.post(
            f"{self._storage_url}/object/{BUCKET}/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        raise_for_status(response)
        return path

    async def delete(self, path: str) -> bool:
        """지웠으면(이미 없어도) True. 실패해도 예외를 던지지 않는다 — 결정은 이미 끝났으니 호출부가 photo_path 를 남겨
        매시 배치가 다시 지우게 한다."""
        try:
            response = await self._client.delete(f"{self._storage_url}/object/{BUCKET}/{path}", headers=self._headers)
        except httpx.HTTPError:
            return False
        # 404 = 이미 없다. 목표 상태라 실패가 아니다.
        return response.status_code < 400 or response.status_code == 404

    async def create_signed_url(self, path: str, expires_in: int) -> str:
        """관리자 검수 화면이 사진을 정해진 시간 동안만 보게 하는 URL."""
        response = await self._client.post(
            f"{self._storage_url}/object/sign/{BUCKET}/{path}",
            json={"expiresIn": expires_in},
            headers={**self._headers, "Content-Type": "application/json"},
        )
        response.raise_for_status()
        # 응답은 "/object/sign/..." 같은 상대 경로라 앞에 Storage 주소를 붙여야 열린다.
        return f"{self._storage_url}{response.json()['signedURL']}"
