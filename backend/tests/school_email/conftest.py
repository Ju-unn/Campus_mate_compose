import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_now, get_settings
from app.main import app
from school_email_world import NOW, SchoolEmailWorld, settings


@pytest.fixture
def world() -> SchoolEmailWorld:
    return SchoolEmailWorld()


@pytest.fixture
def client(world: SchoolEmailWorld):
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    # settings(**kwargs) 를 그대로 넣으면 FastAPI 가 kwargs 를 쿼리로 읽어 422 다 — 람다로 감싼다.
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app)
    app.dependency_overrides.clear()
