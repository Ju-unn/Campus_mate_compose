from collections.abc import Callable
from unittest.mock import AsyncMock
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

import app.profile_onboarding.router as router_module
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    monkeypatch.setattr(
        router_module,
        "get_settings",
        lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret="whsec_test",
            discord_webhook_url="https://discord.com/api/webhooks/test",
            google_cloud_project="campus-mate-test",
            openai_api_key="sk-test",
            phone_encryption_key="phone-key-test",
        ),
    )
    yield
    router_module._client_override = None
    router_module._openai_client_override = None


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def test_basic_info_rejects_duplicate_nickname_with_409():
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            return httpx.Response(409, json={"message": "duplicate key"})
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": "01012345678", "gender": "male",
        },
    )

    assert response.status_code == 409
    assert "닉네임" in response.json()["detail"]


def test_interests_rejects_fewer_than_three_tags_with_422():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.post(
        "/profile-onboarding/interests",
        headers=AUTH_HEADERS,
        json={"tags": ["카페가기", "자전거"]},
    )

    assert response.status_code == 422
    assert "최소 3개" in response.json()["detail"]


def test_avatar_generate_grants_ten_hearts_on_fifth_consecutive_failure():
    hearts_requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[{"storage_path": "aa/source.png"}])
        if "/storage/v1/object/profile-photos/" in url and request.method == "GET":
            return httpx.Response(200, content=b"source-photo-bytes")
        if "/rest/v1/profile_avatars" in url and request.method == "GET":
            return httpx.Response(200, json=[{"status": "failed"}] * 4)
        if "/rest/v1/profile_avatars" in url and request.method == "POST":
            return httpx.Response(201, json=[])
        if "/storage/v1/object/copy" in url:
            return httpx.Response(200, json={"Key": "avatars/aa/fallback.png"})
        if "/rest/v1/rpc/grant_hearts" in url:
            hearts_requests.append(request)
            return httpx.Response(200)
        return httpx.Response(200, json=[])

    router_module._openai_client_override = AsyncMock()
    router_module._openai_client_override.images.edit.side_effect = Exception("openai down")

    client = _wire(handler)
    response = client.post("/profile-onboarding/avatar/generate", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "fallback"
    assert body["compensation_hearts"] == 10
    assert len(hearts_requests) == 1
