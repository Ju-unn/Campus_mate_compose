from collections.abc import Iterable
from uuid import UUID

import httpx
from fastapi import HTTPException

from app.consents.policy import consent_state
from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.settings import Settings


class ConsentRepository(PostgrestRepository):
    """가입 동의 기록(user_consents). 표는 FastAPI 전용이라 service_role 로만 읽고 쓴다."""

    async def fetch_rows(self, profile_id: UUID) -> list[dict]:
        response = await self._get(
            "user_consents", params={"profile_id": f"eq.{profile_id}", "select": "kind,version"}
        )
        raise_for_status(response)
        return response.json()

    async def record(self, profile_id: UUID, kinds: Iterable[str], version: str) -> None:
        # 두 번 눌러도 같은 판은 한 번만 남는다(PK 충돌 무시). 시각은 DB 기본값 now() — 앱 시각을 믿지 않는다.
        response = await self._post(
            "user_consents",
            json=[{"profile_id": str(profile_id), "kind": kind, "version": version} for kind in sorted(kinds)],
            prefer="resolution=ignore-duplicates",
        )
        raise_for_status(response)


async def require_current_consent(settings: Settings, client: httpx.AsyncClient, profile_id: UUID) -> None:
    """동의 전에는 실명 · 학생증(3b)도 온보딩도 받지 않는다(계획서 §0 "자리").
    X-Account-Status 를 싣지 않는다 — 앱이 정지 안내 화면으로 오인하지 않게."""
    repo = ConsentRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    if consent_state(await repo.fetch_rows(profile_id)) != "current":
        raise HTTPException(status_code=403, detail=errors.CONSENT_REQUIRED)
