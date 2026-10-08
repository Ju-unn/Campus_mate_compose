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


SNU = "22222222-2222-2222-2222-222222222222"


def _user(email: str | None = "hong@snu.ac.kr", provider: str | None = "email") -> dict:
    """GoTrue 가 보내는 본문 모양. provider 는 user.app_metadata.provider 에 온다(None 이면 칸을 아예 뺀다)."""
    user: dict = {} if email is None else {"email": email}
    if provider is not None:
        user["app_metadata"] = {"provider": provider, "providers": [provider]}
    return {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": user}


def _db(seen: list[httpx.Request], domains: dict[str, str] | None = None, blocked: bool = False):
    """PostgREST 가짜. 경로로 가르고(부분 문자열 금지), 나간 요청을 seen 에 쌓는다."""
    domains = {"snu.ac.kr": SNU} if domains is None else domains

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path == "/rest/v1/university_email_domains":
            university = domains.get(request.url.params["domain"].removeprefix("eq."))
            return httpx.Response(200, json=[{"university_id": university}] if university else [])
        if request.url.path == "/rest/v1/signup_blocks":
            return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00Z"}] if blocked else [])
        raise AssertionError(f"예상하지 못한 요청 {request.url}")

    return httpx.MockTransport(handler)


# 이메일 방식(provider=email — 학교 메일 인증용 임시 계정)만 학교 도메인 · 재가입 제한을 본다(옛 동작 그대로) ---------

def test_allows_known_domain():
    seen: list[httpx.Request] = []

    response = _post_hook(TestClient(app), _user("hong@snu.ac.kr"), _db(seen))

    # GoTrue 는 200 본문에 `error` 가 없으면 통과시킨다 — 빈 객체 + JSON Content-Type 이 문서의 "허용" 모양.
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    assert response.json() == {}
    assert [r.url.path for r in seen] == ["/rest/v1/university_email_domains", "/rest/v1/signup_blocks"]


def test_rejects_unknown_domain():
    response = _post_hook(TestClient(app), _user("hong@unknown.ac.kr"), _db([]))

    # GoTrue 는 4xx 상태 본문을 읽지 않고 500 으로 바꾼다 — 거절은 200 + `error` 객체여야 메시지가 앱까지 간다.
    # http_code 422 는 앱이 "가입 거절" 로 읽는 값(supabase_auth_repository.dart `_toFailure`).
    assert response.status_code == 200
    assert response.json() == {"error": {"http_code": 422, "message": "허용되지 않은 학교 이메일이에요"}}


def test_rejects_blocked_email():
    response = _post_hook(TestClient(app), _user("hong@snu.ac.kr"), _db([], blocked=True))

    assert response.status_code == 200
    assert response.json() == {"error": {"http_code": 422, "message": "재가입이 제한된 이메일이에요"}}


def test_blocked_email_hash_uses_identity_key():
    """재가입 차단 해시는 **신원 키**로 만든다(미결 41①).

    서명 키로 만들면 서명 키를 바꾸는 순간 저장된 해시가 전부 안 맞아 차단이 풀린다.
    """
    seen: list[httpx.Request] = []

    _post_hook(TestClient(app), _user("Hong@SNU.ac.kr"), _db(seen))

    expected = hash_email(IDENTITY_KEY, "hong@snu.ac.kr")
    asked = [r.url.params["email_hmac"] for r in seen if r.url.path == "/rest/v1/signup_blocks"]
    assert asked == [f"eq.\\x{expected.hex()}"]
    assert hash_email(SECRET, "hong@snu.ac.kr") != expected


def test_an_email_signup_without_an_email_is_rejected():
    response = _post_hook(TestClient(app), _user(email=None), _db([]))

    assert response.json()["error"]["http_code"] == 422


# 소셜(kakao · google · apple)은 검사 없이 허용 — 소셜 계정에는 학교 메일이 없다(카카오는 이메일조차 없다) ---------

@pytest.mark.parametrize("provider", ["kakao", "google", "apple"])
@pytest.mark.parametrize("email", ["hong@gmail.com", "hong@unknown.ac.kr", None])
def test_a_social_signup_is_allowed_without_asking_the_db(provider, email):
    seen: list[httpx.Request] = []

    response = _post_hook(TestClient(app), _user(email, provider), _db(seen))

    assert response.status_code == 200
    assert response.json() == {}
    assert seen == []


# provider 를 못 읽으면 거절한다 — 실패하면 열지 않는다 -------------------------------------------------

@pytest.mark.parametrize("payload", [
    _user(provider=None),
    {"metadata": {"name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr", "app_metadata": {}}},
    {"metadata": {"name": "before-user-created"}, "user": {"email": "hong@snu.ac.kr", "app_metadata": None}},
    _user(provider="github"),
])
def test_an_unreadable_or_unknown_provider_is_rejected(payload):
    seen: list[httpx.Request] = []

    response = _post_hook(TestClient(app), payload, _db(seen))

    assert response.status_code == 200
    assert response.json() == {"error": {"http_code": 422, "message": "가입할 수 없는 계정이에요"}}
    assert seen == []


def test_invalid_signature_returns_401():
    # 서명에서 막히는 테스트라 get_client 을 덮어쓰지 않는다 — lifespan 을 켜둔다.
    with TestClient(app) as client:
        response = client.post(
            "/hooks/before-user-created",
            content=b'{"metadata":{"uuid":"11111111-1111-1111-1111-111111111111"},"user":{"email":"hong@snu.ac.kr"}}',
            headers={"webhook-id": "msg_1", "webhook-timestamp": "1700000000", "webhook-signature": "v1,invalid"},
        )

    assert response.status_code == 401
