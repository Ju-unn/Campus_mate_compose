"""추천 코드 API(화면 20 · 홈탭 19). 검사 · 행 넣기 · 지급은 DB 함수가 하고 서버는 오류 코드만 HTTP 로 바꾼다."""
import json
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
REFERRER_ID = "22222222-2222-2222-2222-222222222222"
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


def _wire(handler, verification: str = "verified") -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "student_verification" in request.url.params.get("select", "") and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴퓨터공학과"}])
        return handler(request)

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def _rpc_error(code: str) -> httpx.Response:
    return httpx.Response(400, json={"code": code, "message": "x"})


def test_my_code_returns_own_code():
    seen = {}

    def handler(request):
        seen["params"] = dict(request.url.params)
        return httpx.Response(200, json=[{"referral_code": "K7QMX2"}])

    response = _wire(handler).get("/referral/my-code", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"code": "K7QMX2"}
    assert seen["params"]["id"] == f"eq.{PROFILE_ID}"
    assert seen["params"]["select"] == "referral_code"


def test_my_code_requires_verified_student():
    response = _wire(lambda r: httpx.Response(200, json=[]), verification="pending").get(
        "/referral/my-code", headers=AUTH_HEADERS)
    assert response.status_code == 403


def test_redeem_passes_raw_code_and_returns_referrer():
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["body"] = json.loads(request.read())
        return httpx.Response(200, json=REFERRER_ID)

    response = _wire(handler).post("/referral/redeem", headers=AUTH_HEADERS, json={"code": " k7qmx2 "})

    assert response.status_code == 200
    assert response.json() == {"referrer_id": REFERRER_ID}
    assert seen["url"].endswith("/rpc/redeem_referral")
    # 자르기 · 대문자는 DB 함수가 한다 — 서버가 따로 바꾸면 두 곳이 어긋날 수 있다.
    assert seen["body"] == {"p_referee_id": str(PROFILE_ID), "p_code": " k7qmx2 "}


@pytest.mark.parametrize(("code", "status", "detail"), [
    ("CM404", 404, errors.REFERRAL_CODE_NOT_FOUND),
    ("CM422", 422, errors.REFERRAL_CODE_NOT_ALLOWED),
    ("23505", 409, errors.REFERRAL_ALREADY_REDEEMED),
])
def test_redeem_maps_db_errors(code, status, detail):
    response = _wire(lambda r: _rpc_error(code)).post(
        "/referral/redeem", headers=AUTH_HEADERS, json={"code": "K7QMX2"})
    assert response.status_code == status
    assert response.json()["detail"] == detail


@pytest.mark.parametrize("code", ["", "   ", "A" * 21])
def test_redeem_rejects_blank_or_long_code_without_calling_db(code):
    called = []
    response = _wire(lambda r: called.append(r) or httpx.Response(200, json=REFERRER_ID)).post(
        "/referral/redeem", headers=AUTH_HEADERS, json={"code": code})
    assert response.status_code == 422
    assert called == []
