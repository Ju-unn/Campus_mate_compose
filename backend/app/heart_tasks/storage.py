from uuid import UUID

import httpx

from app.core.http import raise_for_status

BUCKET = "heart-task-proofs"


class HeartProofStorage:
    """`heart-task-proofs` 비공개 버킷. 올리기 · 지우기 모두 서버가 service_role 로 한다(ERD §9).

    ponytail: student_verification/storage.py 와 모양이 같다. 같은 모양의 버킷 클래스가 셋이 되면
    버킷 이름을 받는 클래스 하나로 합친다."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}
        self._client = client

    async def upload(self, profile_id: UUID, submission_id: UUID, data: bytes, content_type: str) -> str:
        # 운영자가 대시보드에서 내려받아 여는 파일이라 확장자가 실제 형식과 맞아야 한다.
        extension = "png" if content_type == "image/png" else "jpg"
        # `{profile_id}/` 한 층 — 탈퇴 정리 배치가 폴더째 지운다(account/batch_router.py STORAGE_BUCKETS).
        path = f"{profile_id}/{submission_id}.{extension}"
        response = await self._client.post(
            f"{self._storage_url}/object/{BUCKET}/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        raise_for_status(response)
        return path

    async def delete(self, paths: list[str]) -> None:
        """여러 개를 한 번에 지운다. 실패하면 예외 — 부른 쪽이 경로를 비우지 않고 다음에 다시 지운다."""
        response = await self._client.request(
            "DELETE", f"{self._storage_url}/object/{BUCKET}", json={"prefixes": paths}, headers=self._headers,
        )
        response.raise_for_status()
