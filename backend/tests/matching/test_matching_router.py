from collections.abc import Callable
from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.matching.router as router_module
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    monkeypatch.setattr(router_module, "get_settings", lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test",
    ))
    yield
    router_module._client_override = None


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def test_candidates_are_sorted_by_score_and_cut_to_limit():
    now = datetime.now(timezone.utc).isoformat()
    owner = {
        "id": PROFILE_ID, "gender": "male", "mbti": None, "preferred_mbti_flags": {},
        "height_cm": 180, "preferred_height_min": None, "preferred_height_max": None,
        "birth_year": 2002, "preferred_age_min": None, "preferred_age_max": None,
        "is_smoker": True, "religion": "none",
    }
    candidate = {
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True,
        "religion": "none", "last_active_at": now, "tag_score": 0, "text_score": 0,
    }

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rpc/match_candidates" in url:
            return httpx.Response(200, json=[
                {**candidate, "candidate_id": "low", "trait_score": 0.1},
                {**candidate, "candidate_id": "high", "trait_score": 0.9},
            ])
        if "/profiles" in url:
            return httpx.Response(200, json=[owner])
        return httpx.Response(200, json=[])

    response = _wire(handler).get("/matching/candidates", headers=AUTH_HEADERS, params={"limit": 1})

    assert response.status_code == 200
    body = response.json()
    assert [c["profile_id"] for c in body["candidates"]] == ["high"]
    assert body["candidates"][0]["score"] > 0


def test_candidates_requires_verified_student():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    def unverified(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url:
            return httpx.Response(200, json=[{"student_verification": "pending", "department": None}])
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(unverified))
    response = TestClient(app).get("/matching/candidates", headers=AUTH_HEADERS)

    assert response.status_code == 403
