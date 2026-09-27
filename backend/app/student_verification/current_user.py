from uuid import UUID

import httpx
from fastapi import HTTPException

from app.core import errors
from app.settings import Settings
from app.student_verification.repository import StudentVerificationRepository


async def get_current_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = None,
) -> UUID:
    if authorization is None:
        raise HTTPException(status_code=401, detail=errors.LOGIN_REQUIRED)
    response = await client.get(
        f"{settings.auth_url}/user",
        headers={"Authorization": authorization, "apikey": settings.supabase_service_role_key},
    )
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail=errors.SESSION_EXPIRED)
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
    if gate.get("status") == "suspended":
        # 학생증 · 학과보다 먼저 본다. 403 은 그 두 관문도 쓰고 있어서 앱(정지 안내 화면)이 문구를
        # 비교하지 않고 가를 수 있게 헤더를 싣는다(Ruling 8). 로그인 자체는 살려 둔다 — 안내를 띄워야 한다.
        raise HTTPException(status_code=403, detail=errors.ACCOUNT_SUSPENDED,
                            headers={"X-Account-Status": "suspended"})
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail=errors.STUDENT_VERIFICATION_REQUIRED)
    if gate["department"] is None:
        raise HTTPException(status_code=403, detail=errors.DEPARTMENT_REQUIRED)
    return profile_id
