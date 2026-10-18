import httpx
import pytest
from fastapi.testclient import TestClient

from admin_world import AdminWorld, settings
from app.core.deps import get_client, get_settings
from app.main import app


@pytest.fixture
def world() -> AdminWorld:
    return AdminWorld()


@pytest.fixture
def client(world: AdminWorld):
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: settings(**world.settings_overrides)
    app.dependency_overrides[get_client] = lambda: http
    yield TestClient(app)
    app.dependency_overrides.clear()
