"""Supabase Storage 버킷 하나에 올리기 · 지우기(service_role). 버킷 이름을 받는 공용 틀.

ponytail: 같은 모양의 버킷 클래스가 이미 넷이다(heart_tasks · student_verification · graduate_verification ·
profile_onboarding 의 storage.py). 넷은 경로 규칙 · 서명 URL · 시험 가짜가 저마다 달라 이번(할 일 21)에 옮기지 않았다 —
새 버킷은 이 클래스를 쓰고, 넷은 그 기능을 고칠 때 하나씩 여기로 옮긴다.
"""
import httpx

from app.core.http import raise_for_status


def public_object_url(supabase_url: str, bucket: str, path: str) -> str:
    """공개 버킷 파일의 주소. 앱이 받는 그림 주소는 이 모양뿐이다(home/router.py 배너와 같은 모양)."""
    return f"{supabase_url}/storage/v1/object/public/{bucket}/{path}"


class BucketStorage:
    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient, bucket: str):
        self._storage_url = storage_url
        self._headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}
        self._client = client
        self._bucket = bucket

    async def upload(self, path: str, data: bytes, content_type: str) -> None:
        """content_type 은 서버가 정한 값이다 — 올린 사람이 보낸 값을 넘기지 않는다."""
        response = await self._client.post(
            f"{self._storage_url}/object/{self._bucket}/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        raise_for_status(response)

    async def delete(self, paths: list[str]) -> None:
        """여러 개를 한 번에 지운다(없는 파일은 오류가 아니다). 실패하면 예외."""
        response = await self._client.request(
            "DELETE", f"{self._storage_url}/object/{self._bucket}", json={"prefixes": paths}, headers=self._headers,
        )
        response.raise_for_status()
