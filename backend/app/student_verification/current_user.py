import logging
from uuid import UUID

import httpx
from fastapi import HTTPException

from app.core import errors
from app.settings import Settings
from app.student_verification.repository import StudentVerificationRepository

logger = logging.getLogger(__name__)


async def get_current_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = None,
) -> UUID:
    if authorization is None:
        raise HTTPException(status_code=401, detail=errors.LOGIN_REQUIRED)
    # 401 이면 앱이 토큰을 새로 받아 보고, 그래도 401 이면 로그인 화면으로 보낸다(A11). 그래서 이 로그인을
    # 거절한 것(4xx)만 401 이고, Supabase 인증이 잠깐 못 받는 것(5xx · 429 · 연결 실패)은 503 이다.
    try:
        response = await client.get(
            f"{settings.auth_url}/user",
            headers={"Authorization": authorization, "apikey": settings.supabase_service_role_key},
        )
    except httpx.HTTPError as exc:
        # 앱이 조용히 다시 시도하니 장애 빈도는 이 로그로만 안다. 토큰은 남기지 않는다.
        logger.warning("Supabase 인증 연결 실패 → 503 %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE)
    if response.status_code >= 500 or response.status_code == 429:
        logger.warning("Supabase 인증 장애 → 503 status=%d", response.status_code)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE)
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail=errors.SESSION_EXPIRED)
    return UUID(response.json()["id"])


def _reject_withdrawn(status: str | None) -> None:
    """탈퇴 계정은 모든 인증 API 에서 401 이다. 정지(403)와 같은 헤더로 앱이 문구 비교 없이 가른다(편차 1).
    auth 사용자는 30일 정리 배치가 지울 때까지 남아 있어서, 토큰이 살아 있으면 여기까지 들어온다."""
    if status == "withdrawn":
        raise HTTPException(status_code=401, detail=errors.ACCOUNT_WITHDRAWN,
                            headers={"X-Account-Status": "withdrawn"})


def reject_suspended(status: str | None) -> None:
    """정지 계정은 403. 403 은 학생증 · 학과 관문도 쓰고 있어서 앱(정지 안내 화면)이 문구를 비교하지 않고
    가를 수 있게 헤더를 싣는다(Ruling 8). 로그인 자체는 살려 둔다 — 안내를 띄워야 한다."""
    if status == "suspended":
        raise HTTPException(status_code=403, detail=errors.ACCOUNT_SUSPENDED,
                            headers={"X-Account-Status": "suspended"})


async def get_signed_in_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = None,
) -> UUID:
    """로그인만 확인하는 관문(get_caller). 학생증 · 정지는 보지 않고 탈퇴만 막는다 — 상태를 한 번 읽는다."""
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    _reject_withdrawn(await repo.fetch_status(profile_id))
    return profile_id


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
    _reject_withdrawn(gate.get("status"))
    reject_suspended(gate.get("status"))  # 학생증 · 학과보다 먼저 본다.
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail=errors.STUDENT_VERIFICATION_REQUIRED)
    if gate["department"] is None:
        raise HTTPException(status_code=403, detail=errors.DEPARTMENT_REQUIRED)
    return profile_id
