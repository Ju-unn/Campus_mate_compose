import logging
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
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="right")
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def test_batch_requires_the_shared_secret():
    # get_client 을 덮어쓰지 않는 테스트라 lifespan 을 켜둔다(`with`).
    with TestClient(app) as client:
        assert client.post("/batch/daily-cards").status_code == 401
        assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": "wrong"}).status_code == 401


def test_batch_with_the_secret_runs_the_issuing_pass(caplog):
    """비밀이 맞으면 지급 배치 결과를 그대로 돌려준다. 지급 대상이 없어도 200 이다."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    with caplog.at_level(logging.WARNING, logger="app.cards.batch_router"):
        response = _wire(handler).post("/batch/daily-cards", headers={"X-Batch-Secret": "right"})

    assert response.status_code == 200
    assert response.json() == {"issued": 0, "no_candidate": 0, "skipped_regions": []}
    # OIDC 전환 중 운영자는 이 줄로 job 이 어느 문으로 들어왔는지 본다(DEPLOY.md). 운영 root 로거는
    # WARNING 문턱이라(로깅 설정 없음) 그 문턱에서 잡혀야 Cloud Run 로그에 남는다.
    assert "batch /batch/daily-cards auth=secret" in caplog.text


def _oidc_configured() -> None:
    app.dependency_overrides[get_settings] = lambda: _settings(
        card_batch_secret="right", batch_audience=AUDIENCE, batch_service_account=SCHEDULER
    )


def test_batch_with_a_scheduler_id_token_runs_the_issuing_pass(monkeypatch, caplog):
    """조각 6 OIDC 전환 — 헤더 없이 구글 ID 토큰만 달고 와도 같은 배치가 돈다."""
    _oidc_configured()

    def fake_verify(token, request, audience):
        # 서버가 설정한 audience(경로 없는 서비스 URL)를 그대로 넘기는지 여기서 못 박는다.
        assert audience == AUDIENCE
        return {"email": SCHEDULER, "email_verified": True}

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)

    with caplog.at_level(logging.WARNING, logger="app.cards.batch_router"):
        response = _wire(lambda request: httpx.Response(200, json=[])).post(
            "/batch/daily-cards", headers={"Authorization": "Bearer id-token"}
        )

    assert response.status_code == 200
    assert response.json() == {"issued": 0, "no_candidate": 0, "skipped_regions": []}
    assert "batch /batch/daily-cards auth=oidc" in caplog.text


def test_batch_turns_away_a_call_without_either_even_with_oidc_configured():
    """OIDC 문을 연 뒤에도 헤더도 토큰도 없거나 헤더만 틀린 호출은 들어오지 못한다."""
    _oidc_configured()

    with TestClient(app) as client:
        assert client.post("/batch/daily-cards").status_code == 401
        assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": "wrong"}).status_code == 401


def test_batch_is_closed_when_the_secret_is_not_configured():
    """시크릿을 안 넣고 배포하면 엔드포인트가 열린 채로 남는다 — 그때는 아무도 못 부르게 한다."""
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="")

    with TestClient(app) as client:
        assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": ""}).status_code == 401
