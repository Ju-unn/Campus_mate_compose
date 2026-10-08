import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_now, get_settings
from app.main import app
from verify_world import NOW, VerifyWorld, settings


@pytest.fixture
def world() -> VerifyWorld:
    return VerifyWorld()


@pytest.fixture
def client(world: VerifyWorld):
    """500 을 확인하는 시험이 있어 서버 예외를 응답으로 받는다."""
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    # settings(**kwargs) 를 그대로 넣으면 FastAPI 가 kwargs 를 쿼리로 읽어 422 다 — 람다로 감싼다.
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()
