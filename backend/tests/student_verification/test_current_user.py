from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from app.settings import Settings
from app.student_verification.current_user import get_current_user_id, get_verified_user_id

USER_ID = "11111111-1111-1111-1111-111111111111"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co",
        supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test",
        discord_webhook_url="https://discord.com/api/webhooks/test",
        google_cloud_project="campus-mate-test",
        openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )


async def test_valid_token_returns_user_id():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = request.headers
        return httpx.Response(200, json={"id": USER_ID})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    user_id = await get_current_user_id(_settings(), client, authorization="Bearer valid-token")

    assert user_id == UUID(USER_ID)
    assert captured["url"] == "https://x.supabase.co/auth/v1/user"
    assert captured["headers"]["authorization"] == "Bearer valid-token"
    assert captured["headers"]["apikey"] == "service-key"


async def test_missing_authorization_header_returns_401():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200)))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization=None)

    assert exc_info.value.status_code == 401


async def test_supabase_401_is_passed_through():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(401)))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization="Bearer expired-token")

    assert exc_info.value.status_code == 401


# 조각 6: 정지 관문 ----------------------------------------------------------------

def _gate_client(gate_row: dict) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": USER_ID})
        return httpx.Response(200, json=[gate_row])

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_a_suspended_account_is_403_with_a_status_header():
    """403 은 학생증 · 학과 관문도 쓴다 — 앱이 문구를 비교하지 않고 정지를 가르게 헤더를 싣는다."""
    client = _gate_client({"student_verification": "verified", "department": "컴공", "status": "suspended"})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "이용이 제한된 계정이에요"
    assert exc_info.value.headers == {"X-Account-Status": "suspended"}


async def test_suspension_is_checked_before_the_student_id_gate():
    client = _gate_client({"student_verification": "pending", "department": None, "status": "suspended"})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == "이용이 제한된 계정이에요"


async def test_an_active_or_unknown_status_passes_the_gate():
    for row in ({"student_verification": "verified", "department": "컴공", "status": "active"},
                {"student_verification": "verified", "department": "컴공"}):
        assert await get_verified_user_id(_settings(), _gate_client(row),
                                          authorization="Bearer valid-token") == UUID(USER_ID)
