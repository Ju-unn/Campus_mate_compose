import base64
import hashlib
import hmac
import json
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings
from app.signup_policy import hash_email


SECRET = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
IDENTITY_KEY = "identity-key-test"


def _sign(webhook_id: str, timestamp: str, body: bytes) -> str:
    key = base64.b64decode(SECRET.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    digest = hmac.new(key, signed_content, hashlib.sha256).digest()
    return f"v1,{base64.b64encode(digest).decode()}"


@pytest.fixture(autouse=True)
def settings_override():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co",
        supabase_service_role_key="service-key",
        auth_hook_signing_secret=SECRET,
        discord_webhook_url="https://discord.com/api/webhooks/test",
        google_cloud_project="campus-mate-test",
        openai_api_key="sk-test",
        phone_encryption_key="phone-key-test",
        identity_hmac_key=IDENTITY_KEY,
    )
    yield
    app.dependency_overrides.clear()


def _post_hook(client: TestClient, body: dict, mock_transport: httpx.MockTransport):
    raw_body = json.dumps(body).encode()
    timestamp = str(int(time.time()))
    headers = {
        "webhook-id": "msg_1",
        "webhook-timestamp": timestamp,
        "webhook-signature": _sign("msg_1", timestamp, raw_body),
    }
    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=mock_transport)
    return client.post("/hooks/before-user-created", content=raw_body, headers=headers)


def test_allows_known_domain():
    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        return httpx.Response(200, json=[])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.status_code == 200
    assert response.json() == {"decision": "continue", "message": None}


def test_rejects_unknown_domain():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@unknown.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.status_code == 200
    assert response.json()["decision"] == "reject"


def test_rejects_blocked_email():
    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00Z"}])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.json()["decision"] == "reject"


def test_blocked_email_hash_uses_identity_key():
    """재가입 차단 해시는 **신원 키**로 만든다(미결 41①).

    서명 키로 만들면 서명 키를 바꾸는 순간 저장된 해시가 전부 안 맞아 차단이 풀린다.
    """
    asked: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        asked.append(request.url.params.get("email_hmac", ""))
        return httpx.Response(200, json=[])

    client = TestClient(app)
    _post_hook(
        client,
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    expected = hash_email(IDENTITY_KEY, "hong@snu.ac.kr")
    assert asked == [f"eq.\\x{expected.hex()}"]
    assert hash_email(SECRET, "hong@snu.ac.kr") != expected


def test_invalid_signature_returns_401():
    # 서명에서 막히는 테스트라 get_client 을 덮어쓰지 않는다 — lifespan 을 켜둔다.
    with TestClient(app) as client:
        response = client.post(
            "/hooks/before-user-created",
            content=b'{"metadata":{"uuid":"11111111-1111-1111-1111-111111111111"},"user":{"email":"hong@snu.ac.kr"}}',
            headers={"webhook-id": "msg_1", "webhook-timestamp": "1700000000", "webhook-signature": "v1,invalid"},
        )

    assert response.status_code == 401
