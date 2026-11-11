import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.main import app
from app.phone_verification.sms import FakeSmsSender, get_sms_sender
from phone_world import PhoneWorld, settings


@pytest.fixture
def world() -> PhoneWorld:
    return PhoneWorld()


@pytest.fixture
def sms() -> FakeSmsSender:
    """보낸 문자를 모으는 가짜 발송기(운영 코드의 그것 — 로컬 · 시험 전용)."""
    return FakeSmsSender()


@pytest.fixture
def http(world: PhoneWorld) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(world.handle))


@pytest.fixture
def client(http: httpx.AsyncClient, sms: FakeSmsSender):
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_sms_sender] = lambda: sms
    yield TestClient(app)
    app.dependency_overrides.clear()
