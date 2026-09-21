from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings


def _settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", **overrides,
    )


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="right")
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def test_batch_requires_the_shared_secret():
    client = TestClient(app)
    assert client.post("/batch/daily-cards").status_code == 401
    assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": "wrong"}).status_code == 401


def test_batch_with_the_secret_runs_the_issuing_pass():
    """비밀이 맞으면 지급 배치 결과를 그대로 돌려준다. 지급 대상이 없어도 200 이다."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/batch/daily-cards", headers={"X-Batch-Secret": "right"})

    assert response.status_code == 200
    assert response.json() == {"issued": 0, "no_candidate": 0, "skipped_regions": []}


def test_batch_is_closed_when_the_secret_is_not_configured():
    """시크릿을 안 넣고 배포하면 엔드포인트가 열린 채로 남는다 — 그때는 아무도 못 부르게 한다."""
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="")

    assert TestClient(app).post(
        "/batch/daily-cards", headers={"X-Batch-Secret": ""}
    ).status_code == 401
