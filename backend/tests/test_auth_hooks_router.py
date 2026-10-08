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

    # GoTrue 는 200 본문에 `error` 가 없으면 통과시킨다 — 빈 객체 + JSON Content-Type 이 문서의 "허용" 모양.
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    assert response.json() == {}


def _no_db_calls(seen: list[httpx.Request]):
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
    return httpx.MockTransport(handler)


# 소셜 로그인 전환: 소셜 계정에는 학교 메일이 없어(카카오는 이메일조차 없다) 훅은 서명만 보고 항상 허용한다.
# 도메인 · 재가입 제한 거절 시험은 tests/school_email/test_school_email_check.py 로 옮겼다(같은 내용).

@pytest.mark.parametrize("email", ["hong@unknown.ac.kr", "hong@gmail.com", ""])
def test_any_email_is_allowed_without_asking_the_db(email):
    seen: list[httpx.Request] = []

    response = _post_hook(
        TestClient(app),
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": email}},
        _no_db_calls(seen),
    )

    assert response.status_code == 200
    assert response.json() == {}
    # 도메인 · 재가입 제한은 이제 /school-email/check · confirm 이 본다 — 훅은 PostgREST 를 부르지 않는다.
    assert seen == []


def test_a_blocked_email_is_no_longer_refused_here():
    """재가입 제한 해시가 걸려 있어도 훅은 통과시킨다 — 학교 메일 확인(1 · 2번)이 같은 해시로 막는다."""
    seen: list[httpx.Request] = []

    response = _post_hook(
        TestClient(app),
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr"}},
        _no_db_calls(seen),
    )

    assert response.json() == {}
    assert [r for r in seen if r.url.path == "/rest/v1/signup_blocks"] == []


def test_a_kakao_signup_without_any_email_is_allowed():
    """카카오는 이메일 권한 없이 가입하면 user.email 이 아예 없다."""
    seen: list[httpx.Request] = []

    response = _post_hook(
        TestClient(app),
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {}},
        _no_db_calls(seen),
    )

    assert response.status_code == 200
    assert response.json() == {}


def test_invalid_signature_returns_401():
    # 서명에서 막히는 테스트라 get_client 을 덮어쓰지 않는다 — lifespan 을 켜둔다.
    with TestClient(app) as client:
        response = client.post(
            "/hooks/before-user-created",
            content=b'{"metadata":{"uuid":"11111111-1111-1111-1111-111111111111"},"user":{"email":"hong@snu.ac.kr"}}',
            headers={"webhook-id": "msg_1", "webhook-timestamp": "1700000000", "webhook-signature": "v1,invalid"},
        )

    assert response.status_code == 401
