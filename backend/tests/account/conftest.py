import httpx
import pytest
from fastapi.testclient import TestClient

from account_world import NOW, AccountWorld, settings
from app.core.deps import get_client, get_now, get_settings
from app.main import app


@pytest.fixture
def world() -> AccountWorld:
    return AccountWorld()


@pytest.fixture
def client(world: AccountWorld):
    """500 을 확인하는 테스트가 있어 서버 예외를 응답으로 받는다."""
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: settings(card_batch_secret="right")
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()
