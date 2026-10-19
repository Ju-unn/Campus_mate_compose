import httpx
import pytest
from fastapi.testclient import TestClient

from applicant_world import NOW, ApplicantWorld, settings
from app.core.deps import get_client, get_now, get_settings, get_vision_client_factory
from app.main import app


@pytest.fixture
def world(monkeypatch) -> ApplicantWorld:
    monkeypatch.setenv("GRADUATE_VERIFICATION_ENABLED", "true")
    return ApplicantWorld()


@pytest.fixture
def client(world: ApplicantWorld):
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = settings
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    # 제공자가 "만드는 함수"를 돌려주는 자리라 람다가 두 겹이다(core/deps.get_vision_client_factory).
    app.dependency_overrides[get_vision_client_factory] = lambda: lambda: world.vision
    yield TestClient(app)
    app.dependency_overrides.clear()
