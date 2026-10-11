"""저장소 네 곳이 똑같이 들고 있던 PostgREST 배선(헤더·URL 조립)을 한 곳에 둔다.

응답 판정은 일부러 여기서 하지 않는다 — 제약 위반을 4xx 로 바꾸는 곳(core/http.raise_for_status)과
httpx 의 raise_for_status 를 그대로 쓰는 곳이 섞여 있어서, 판정은 저장소가 고르게 둔다.
"""
import logging

import httpx

from app.core.http import raise_for_status
from app.profile_onboarding.encryption import decrypt_profile_private

logger = logging.getLogger(__name__)


class PostgrestRepository:
    """service_role 키로 PostgREST 를 직접 부르는 저장소의 공통 부모.

    encryption_key 는 profile_private 의 실명 · 카카오톡 아이디를 복호화해 읽는 저장소만 넘긴다
    (settings.phone_encryption_key). 없으면 옛 평문 열만 읽는다."""

    def __init__(
        self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
        encryption_key: str | None = None,
    ):
        self._postgrest_url = postgrest_url
        self._service_role_key = service_role_key
        self._encryption_key = encryption_key
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    def _with_prefer(self, prefer: str | None) -> dict[str, str]:
        # Prefer 를 아예 안 보내는 것과 빈 값으로 보내는 것은 다르다 — 부르는 쪽이 준 그대로 보낸다.
        return self._headers if prefer is None else {**self._headers, "Prefer": prefer}

    async def _get(self, path: str, params: dict | None = None) -> httpx.Response:
        return await self._client.get(
            f"{self._postgrest_url}/{path}", params=params, headers=self._headers
        )

    async def _post(
        self, path: str, json: dict | list, params: dict | None = None, prefer: str | None = None
    ) -> httpx.Response:
        return await self._client.post(
            f"{self._postgrest_url}/{path}", params=params, json=json, headers=self._with_prefer(prefer)
        )

    async def _patch(
        self, path: str, params: dict | None = None, json: dict | None = None, prefer: str | None = None
    ) -> httpx.Response:
        return await self._client.patch(
            f"{self._postgrest_url}/{path}", params=params, json=json, headers=self._with_prefer(prefer)
        )

    async def _delete(self, path: str, params: dict | None = None) -> httpx.Response:
        return await self._client.delete(
            f"{self._postgrest_url}/{path}", params=params, headers=self._headers
        )

    async def _decrypt_private(self, profile_id, fields: tuple[str, ...]) -> dict[str, str | None]:
        """enc 열을 복호화한 값. 키가 없거나 복호화가 실패하면 전부 None 이다(요청을 죽이지 않는다).
        실패 로그에는 필드 이름만 남긴다."""
        if not self._encryption_key:
            return {field: None for field in fields}
        try:
            decrypted = await decrypt_profile_private(
                self._postgrest_url, self._service_role_key, self._client, profile_id, self._encryption_key
            )
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("profile_private 복호화 실패 → 평문 열로 폴백 fields=%s error=%s",
                           ",".join(fields), type(exc).__name__)
            return {field: None for field in fields}
        return {field: decrypted[field] for field in fields}

    async def _read_private(self, profile_id, fields: tuple[str, ...]) -> dict[str, str | None]:
        """profile_private 의 real_name · kakao_id 읽기 단일 지점(이중 쓰기 기간 — 서버 PR 2).

        enc 열을 복호화해 쓰고, 그 칸이 비었거나 복호화가 실패하면 옛 평문 열로 폴백한다. 둘 다 없으면 None.
        평문 열 읽기 실패는 예외로 올린다(옛 동작 그대로)."""
        result = await self._decrypt_private(profile_id, fields)
        missing = [field for field in fields if result[field] is None]
        if missing:
            response = await self._get("profile_private", params={
                "profile_id": f"eq.{profile_id}", "select": ",".join(missing),
            })
            raise_for_status(response)
            rows = response.json()
            if rows:
                result.update({field: rows[0].get(field) for field in missing})
        return result
