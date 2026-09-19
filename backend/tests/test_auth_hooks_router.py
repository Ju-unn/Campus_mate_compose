import base64
import hashlib
import hmac
import json
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.settings import Settings
import app.auth_hooks.router as router_module


SECRET = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()


def _sign(webhook_id: str, timestamp: str, body: bytes) -> str:
    key = base64.b64decode(SECRET.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    digest = hmac.new(key, signed_content, hashlib.sha256).digest()
    return f"v1,{base64.b64encode(digest).decode()}"


@pytest.fixture(autouse=True)
def settings_override(monkeypatch):
    monkeypatch.setattr(
        router_module,
        "get_settings",
        lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret=SECRET,
        ),
    )


def _post_hook(client: TestClient, body: dict, mock_transport: httpx.MockTransport):
    raw_body = json.dumps(body).encode()
    timestamp = str(int(time.time()))
    headers = {
        "webhook-id": "msg_1",
        "webhook-timestamp": timestamp,
        "webhook-signature": _sign("msg_1", timestamp, raw_body),
    }
    router_module._client_override = httpx.AsyncClient(transport=mock_transport)
    return client.post("/hooks/before-user-created", content=raw_body, headers=headers)


def test_allows_known_domain():
    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        return httpx.Response(200, json=[])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@snu.ac.kr"}},
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
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@unknown.ac.kr"}},
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
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.json()["decision"] == "reject"


def test_invalid_signature_returns_401():
    client = TestClient(app)
    response = client.post(
        "/hooks/before-user-created",
        content=b'{"user_id":"11111111-1111-1111-1111-111111111111","user":{"email":"hong@snu.ac.kr"}}',
        headers={"webhook-id": "msg_1", "webhook-timestamp": "1700000000", "webhook-signature": "v1,invalid"},
    )

    assert response.status_code == 401
