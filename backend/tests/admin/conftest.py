import httpx
import pytest
from fastapi.testclient import TestClient

from admin_world import AdminWorld, settings
from app.cards.push import FcmSender
from app.cards.router import get_sender
from app.core.deps import get_client, get_now, get_settings
from app.main import app


class _Credentials:
    valid = True
    token = "ya29.test"


@pytest.fixture
def world() -> AdminWorld:
    return AdminWorld()


@pytest.fixture
def client(world: AdminWorld):
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: settings(**world.settings_overrides)
    app.dependency_overrides[get_client] = lambda: http
    # 인증샷 결과 알림(10-18): 진짜 구글 자격증명을 찾지 않게 가짜 자격증명 발송기 + 고정한 "지금"(조용한 시간 때문).
    app.dependency_overrides[get_sender] = lambda: FcmSender("campus-mate-test", http, credentials=_Credentials())
    app.dependency_overrides[get_now] = lambda: world.now
    yield TestClient(app)
    app.dependency_overrides.clear()
