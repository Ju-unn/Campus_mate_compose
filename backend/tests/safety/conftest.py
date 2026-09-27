import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_now, get_settings
from app.main import app
from fake_supabase import NOW, FakeSupabase, settings


@pytest.fixture
def world() -> FakeSupabase:
    return FakeSupabase()


@pytest.fixture
def client(world: FakeSupabase):
    """신고 웹훅이 비어 있는 기본 설정으로 앱을 띄운다. 웹훅이 필요한 테스트는 get_settings 를 다시 덮는다."""
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app)
    app.dependency_overrides.clear()
