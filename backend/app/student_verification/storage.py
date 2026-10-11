from uuid import UUID, uuid4

import httpx

from app.core.http import raise_for_status


class StudentIdStorage:
    """`student-id-temp` 비공개 버킷에 올리고 지운다(설계 §7.4). 지우는 때는 세 곳이다 — 자동 통과 직후(router),
    사람이 재검토해 확정한 직후(review_hook), 남은 사진을 치우는 매시 배치(retention)."""

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
        raise_for_status(response)
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
        # 404 = 이미 없다. 지우려던 목표 상태라 실패가 아니다(자동 통과 직후 훅이 한 번 더 지울 때 고아 알림 오탐을 막는다).
        return response.status_code < 400 or response.status_code == 404

    async def list_paths(self) -> list[str]:
        """버킷에 남은 사진 경로 전부(`{profile_id}/{파일}`). 어느 요청이든 실패하면 예외다.

        사진이 있는 사람 폴더만 돈다 — 확정되면 지우는 버킷이라 평소엔 거의 비어 있다.
        ponytail: 폴더 1000개·폴더당 1000장을 넘으면 남는다 — 넘으면 offset 으로 돈다."""
        paths: list[str] = []
        for folder in await self._list(""):
            if folder.get("id") is None:  # 파일은 id 가 있고 폴더는 없다
                paths += [f"{folder['name']}/{entry['name']}" for entry in await self._list(f"{folder['name']}/")]
        return paths

    async def _list(self, prefix: str) -> list[dict]:
        response = await self._client.post(
            f"{self._storage_url}/object/list/student-id-temp",
            json={"prefix": prefix, "limit": 1000, "offset": 0},
            headers=self._headers,
        )
        raise_for_status(response)
        return response.json()
