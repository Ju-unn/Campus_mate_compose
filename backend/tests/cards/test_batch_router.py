from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"


def _settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: _settings(
        batch_audience=AUDIENCE, batch_service_account=SCHEDULER
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def test_batch_requires_a_scheduler_id_token():
    """토큰 없이는 들어오지 못한다. 옛 공유 열쇠 헤더는 이제 문이 아니다(OIDC 전환 5단계)."""
    # get_client 을 덮어쓰지 않는 테스트라 lifespan 을 켜둔다(`with`).
    with TestClient(app) as client:
        assert client.post("/batch/daily-cards").status_code == 401
        assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": "right"}).status_code == 401


def test_batch_with_a_scheduler_id_token_runs_the_issuing_pass(monkeypatch):
    """구글 ID 토큰이 맞으면 지급 배치 결과를 그대로 돌려준다. 지급 대상이 없어도 200 이다."""
    def fake_verify(token, request, audience):
        # 서버가 설정한 audience(경로 없는 서비스 URL)를 그대로 넘기는지 여기서 못 박는다.
        assert audience == AUDIENCE
        return {"email": SCHEDULER, "email_verified": True}

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)

    response = _wire(lambda request: httpx.Response(200, json=[])).post(
        "/batch/daily-cards", headers={"Authorization": "Bearer id-token"}
    )

    assert response.status_code == 200
    assert response.json() == {"issued": 0, "no_candidate": 0, "skipped_regions": [], "failed": 0}
