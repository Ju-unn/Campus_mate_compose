from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from app.settings import Settings
from app.student_verification.current_user import get_current_user_id

USER_ID = "11111111-1111-1111-1111-111111111111"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co",
        supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test",
        discord_webhook_url="https://discord.com/api/webhooks/test",
        google_cloud_project="campus-mate-test",
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
