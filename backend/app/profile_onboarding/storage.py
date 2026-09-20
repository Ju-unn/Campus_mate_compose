from uuid import UUID, uuid4

import httpx

# 기본(폴백) 아바타 그림 8종. 성별 무관 공용 마스코트 하나를 쓴다(동물상 8종과는 별개, 사람 그림이 아니다).
_FALLBACK_AVATAR_SOURCE_PATH = "defaults/fallback-avatar.png"


class AvatarStorage:
    """공개 `avatars` 버킷에 업로드한다(2026-09-20 사용자 결정 — 아바타는 항상 노출되는 그림이라
    서명 URL이 필요 없다). 경로는 AvatarGenerator 가 `{profile_id}/{uuid4()}.png` 로 미리 짓는다."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def upload(self, path: str, data: bytes, content_type: str) -> str:
        response = await self._client.post(
            f"{self._storage_url}/object/avatars/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        response.raise_for_status()
        return path

    async def copy_fallback_avatar(self, profile_id: UUID) -> str:
        """5회 연속 실패 시 기본 아바타로 대체한다(project_slice2_decisions_2026-09-19). 매번 새로
        업로드하지 않고 버킷 안에 미리 둔 공용 원본을 Storage API 로 복사한다."""
        destination = f"{profile_id}/{uuid4()}.png"
        response = await self._client.post(
            f"{self._storage_url}/object/copy",
            json={
                "bucketId": "avatars",
                "sourceKey": _FALLBACK_AVATAR_SOURCE_PATH,
                "destinationKey": destination,
            },
            headers={**self._headers, "Content-Type": "application/json"},
        )
        response.raise_for_status()
        return destination


class ProfilePhotoStorage:
    """비공개 `profile-photos` 버킷에 실사진을 올린다(조각0, 서명 URL 로만 조회). FastAPI 가 멀티파트로
    받아 대신 올린다(조각1b `StudentIdStorage` 와 같은 프록시 업로드 패턴)."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def upload(self, profile_id: UUID, data: bytes, content_type: str) -> str:
        extension = "png" if content_type == "image/png" else "jpg"
        path = f"{profile_id}/{uuid4()}.{extension}"
        response = await self._client.post(
            f"{self._storage_url}/object/profile-photos/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        response.raise_for_status()
        return path

    async def download(self, path: str) -> bytes:
        response = await self._client.get(
            f"{self._storage_url}/object/profile-photos/{path}",
            headers=self._headers,
        )
        response.raise_for_status()
        return response.content
