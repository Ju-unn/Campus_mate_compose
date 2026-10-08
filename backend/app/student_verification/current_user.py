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
    response = await _get_auth_user(settings, client, authorization)
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail=errors.SESSION_EXPIRED)
    return UUID(response.json()["id"])


async def _get_auth_user(settings: Settings, client: httpx.AsyncClient, authorization: str) -> httpx.Response:
    """`GET {auth_url}/user`. Supabase 인증이 잠깐 못 받는 것(5xx · 429 · 연결 실패)은 여기서 503 이다."""
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
    return response


async def fetch_auth_user(settings: Settings, client: httpx.AsyncClient, authorization: str) -> dict:
    """그 토큰 주인의 Supabase 인증 정보(email · identities · app_metadata). 카카오 연결 끊기 · 학교 메일 verify 가 쓴다.

    장애는 get_current_user_id 와 같이 503 이다. 그 밖의 4xx 는 httpx.HTTPStatusError 로 올린다 — 뜻은
    부르는 쪽이 정한다(verify 의 임시 토큰은 403, 탈퇴의 카카오 단계는 경고만)."""
    response = await _get_auth_user(settings, client, authorization)
    response.raise_for_status()
    return response.json()


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


def require_school_email(gate: dict) -> None:
    """학교 메일 확인 전(school_email_verified_at 이 NULL)이면 403. 동의 관문처럼 X-Account-Status 를 싣지 않는다.

    칸이 아예 없어도 확인 전으로 본다 — 정지 칸이 없을 때(막지 않는다)와 반대다. 이 관문은 열린 문이 되면 안 된다.
    email_confirmed_at 은 보지 않는다 — 소셜 계정은 가입 순간 채워진다(school_email/router.py)."""
    if gate.get("school_email_verified_at") is None:
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_REQUIRED)


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
    조각1 의 `fetch_gate_status` 를 그대로 재사용한다(2026-09-20 리뷰 필수 1).

    순서: 탈퇴(401) → 정지 → 학교 메일 → 학생증 → 학과. 동의는 학생증 제출(3b)이 앞에서 막는다 —
    전체 관문 순서는 정지 → 동의 → 학교 메일 → 학생증 → 학과와 학번 이다(GET /me/verification-status)."""
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    gate = await repo.fetch_gate_status(profile_id)
    _reject_withdrawn(gate.get("status"))
    reject_suspended(gate.get("status"))  # 학생증 · 학과보다 먼저 본다.
    require_school_email(gate)
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail=errors.STUDENT_VERIFICATION_REQUIRED)
    if gate["department"] is None:
        raise HTTPException(status_code=403, detail=errors.DEPARTMENT_REQUIRED)
    return profile_id
