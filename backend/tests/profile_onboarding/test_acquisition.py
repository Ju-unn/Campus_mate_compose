"""20d 유입경로 저장. 기타가 아니면 note 는 저장하지 않는다."""
import json
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test",
        discord_webhook_url="https://discord.com/api/webhooks/test", google_cloud_project="campus-mate-test",
        openai_api_key="sk-test", phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "student_verification" in request.url.params.get("select", "") and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴퓨터공학과"}])
        return handler(request)

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


@pytest.mark.parametrize(("body", "saved"), [
    ({"channel": "instagram"}, {"acquisition_channel": "instagram", "acquisition_note": None}),
    ({"channel": "friend", "note": "무시됨"}, {"acquisition_channel": "friend", "acquisition_note": None}),
    ({"channel": "other", "note": "  학교 축제  "}, {"acquisition_channel": "other", "acquisition_note": "학교 축제"}),
    ({"channel": "other", "note": "가" * 30}, {"acquisition_channel": "other", "acquisition_note": "가" * 30}),
])
def test_acquisition_saves_channel_and_note(body, saved):
    seen = {}

    def handler(request):
        if request.method == "PATCH" and "/rest/v1/profiles" in str(request.url):
            seen["params"] = dict(request.url.params)
            seen["json"] = json.loads(request.read())
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/profile-onboarding/acquisition", headers=AUTH_HEADERS, json=body)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert seen["json"] == saved
    assert seen["params"]["id"] == f"eq.{PROFILE_ID}"


@pytest.mark.parametrize("body", [
    {"channel": "tiktok"},
    {"channel": "other"},
    {"channel": "other", "note": "   "},
    {"channel": "other", "note": "가" * 31},
])
def test_acquisition_rejects_bad_input_without_saving(body):
    called = []
    response = _wire(lambda r: called.append(r) or httpx.Response(200, json=[])).post(
        "/profile-onboarding/acquisition", headers=AUTH_HEADERS, json=body)
    assert response.status_code == 422
    assert called == []
