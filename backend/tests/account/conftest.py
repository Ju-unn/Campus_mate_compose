import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from account_world import NOW, AccountWorld, settings
from app.core.deps import get_client, get_now, get_settings
from app.main import app


@pytest.fixture
def world() -> AccountWorld:
    return AccountWorld()


AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"


def _google_signs(token, request, audience):
    """구글 서명 확인만 가짜로 한다 — 서버가 넘긴 audience 로 발급된 스케줄러 토큰이라고 친다."""
    if audience != AUDIENCE:
        raise ValueError("Token has wrong audience")
    return {"email": SCHEDULER, "email_verified": True}


@pytest.fixture
def client(world: AccountWorld, monkeypatch: pytest.MonkeyPatch):
    """500 을 확인하는 테스트가 있어 서버 예외를 응답으로 받는다. 배치는 스케줄러 ID 토큰으로 부른다."""
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", _google_signs)
    app.dependency_overrides[get_settings] = lambda: settings(
        batch_audience=AUDIENCE, batch_service_account=SCHEDULER
    )
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()
