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

    async def delete(self, path: str) -> None:
        """행을 지울 때 파일도 같이 지운다 — profile_photos 는 cascade 로 지워져도 Storage 파일은
        남기 때문이다(ERD §3, 파일 삭제는 FastAPI 몫)."""
        response = await self._client.delete(
            f"{self._storage_url}/object/profile-photos/{path}",
            headers=self._headers,
        )
        response.raise_for_status()

    async def download(self, path: str) -> bytes:
        response = await self._client.get(
            f"{self._storage_url}/object/profile-photos/{path}",
            headers=self._headers,
        )
        response.raise_for_status()
        return response.content

    async def create_signed_url(self, path: str, expires_in: int) -> str:
        """비공개 버킷의 사진을 정해진 시간 동안만 볼 수 있는 URL 로 바꾼다.
        조각 5 에서 신뢰 확인을 통과한 상대의 실사진을 내려보낼 때 쓴다(설계 §2.5)."""
        response = await self._client.post(
            f"{self._storage_url}/object/sign/profile-photos/{path}",
            json={"expiresIn": expires_in},
            headers={**self._headers, "Content-Type": "application/json"},
        )
        response.raise_for_status()
        # 응답은 "/object/sign/..." 같은 상대 경로라 앞에 Storage 주소를 붙여야 열린다.
        return f"{self._storage_url}{response.json()['signedURL']}"
