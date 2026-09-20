from uuid import UUID

import httpx
from fastapi import HTTPException

from app.settings import Settings
from app.student_verification.repository import StudentVerificationRepository


async def get_current_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = None,
) -> UUID:
    if authorization is None:
        raise HTTPException(status_code=401, detail="로그인이 필요해요")
    response = await client.get(
        f"{settings.auth_url}/user",
        headers={"Authorization": authorization, "apikey": settings.supabase_service_role_key},
    )
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="세션이 만료됐어요, 다시 로그인해 주세요")
    return UUID(response.json()["id"])


async def get_verified_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = None,
) -> UUID:
    """학생증 인증을 마친 사용자만 통과시킨다. 온보딩 엔드포인트가 공통으로 쓰는 관문이라
    조각1 의 `fetch_gate_status` 를 그대로 재사용한다(2026-09-20 리뷰 필수 1)."""
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    gate = await repo.fetch_gate_status(profile_id)
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail="학생증 인증을 먼저 끝내 주세요")
    return profile_id
