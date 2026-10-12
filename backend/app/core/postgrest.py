"""저장소 네 곳이 똑같이 들고 있던 PostgREST 배선(헤더·URL 조립)을 한 곳에 둔다.

응답 판정은 일부러 여기서 하지 않는다 — 제약 위반을 4xx 로 바꾸는 곳(core/http.raise_for_status)과
httpx 의 raise_for_status 를 그대로 쓰는 곳이 섞여 있어서, 판정은 저장소가 고르게 둔다.
"""
import logging

import httpx

from app.profile_onboarding.encryption import decrypt_profile_private

logger = logging.getLogger(__name__)


class PostgrestRepository:
    """service_role 키로 PostgREST 를 직접 부르는 저장소의 공통 부모.

    encryption_key 는 profile_private 의 실명 · 카카오톡 아이디를 복호화해 읽는 저장소만 넘긴다
    (settings.phone_encryption_key). 없으면 그 둘을 읽지 못한다(_read_private)."""

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

    async def _read_private(self, profile_id, fields: tuple[str, ...]) -> dict[str, str | None]:
        """profile_private 의 real_name · kakao_id 읽기 단일 지점. 암호문 열을 복호화해서만 읽는다(M2 — 평문 열은 없다).

        값이 없으면 None. 복호화 실패는 예외로 올린다 — None 으로 삼키면 "아직 안 냈다" 로 보여 이미 낸 사람을
        다시 입력 화면으로 보내거나 상대에게 아이디가 없는 것처럼 보인다. 키 없이 만든 저장소는 읽을 수 없다(배선 실수)."""
        if not self._encryption_key:
            raise RuntimeError("profile_private 를 읽으려면 encryption_key 를 넘겨야 한다")
        try:
            decrypted = await decrypt_profile_private(
                self._postgrest_url, self._service_role_key, self._client, profile_id, self._encryption_key
            )
        except httpx.HTTPStatusError as exc:
            # 키 버전 불일치 같은 운영 사고를 찾을 한 줄. str(exc) 에는 URL 이 들어 있어 쓰지 않는다 — profile_id · 상태 코드만.
            logger.error("profile_private 복호화 실패 profile_id=%s status=%s", profile_id, exc.response.status_code)
            raise
        return {field: decrypted[field] for field in fields}
