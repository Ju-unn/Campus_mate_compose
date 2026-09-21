"""저장소 네 곳이 똑같이 들고 있던 PostgREST 배선(헤더·URL 조립)을 한 곳에 둔다.

응답 판정은 일부러 여기서 하지 않는다 — 제약 위반을 4xx 로 바꾸는 곳(core/http.raise_for_status)과
httpx 의 raise_for_status 를 그대로 쓰는 곳이 섞여 있어서, 판정은 저장소가 고르게 둔다.
"""
import httpx


class PostgrestRepository:
    """service_role 키로 PostgREST 를 직접 부르는 저장소의 공통 부모."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
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
