"""알림함 90일 보관 정리 — 매시 chat-gate 배치가 한 번 부른다."""
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.main import app
from app.notifications.repository import NotificationRepository
from app.notifications.retention import purge_expired
from app.settings import Settings
from fake_inbox import ME, FakeInbox, row

NOW = datetime(2026, 10, 20, 12, 0, tzinfo=SEOUL)  # 90일 전 = 7월 22일 12시


def _repo(inbox: FakeInbox) -> NotificationRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(inbox.handle))
    return NotificationRepository("https://x.supabase.co/rest/v1", "service-key", client)


def _old_and_new() -> FakeInbox:
    return FakeInbox([
        row(1, created_at="2026-07-21T12:00:00+09:00"),  # 91일 — 지운다
        row(2, created_at="2026-07-22T12:00:01+09:00"),  # 89일 23시간 — 남긴다
        row(3, created_at="2026-07-01T00:00:00+00:00", read_at="2026-07-02T00:00:00+00:00"),  # 읽었어도 오래되면 지운다
    ])


async def test_rows_older_than_ninety_days_are_deleted_for_everyone():
    inbox = _old_and_new()

    deleted = await purge_expired(_repo(inbox), NOW)

    assert deleted == 2
    assert [r["id"] for r in inbox.rows] == [row(2)["id"]]


async def test_a_failing_purge_is_logged_not_raised(caplog):
    inbox = FakeInbox([row(1, created_at="2026-01-01T00:00:00+00:00")], fail_delete=True)

    assert await purge_expired(_repo(inbox), NOW) == 0
    assert len(inbox.rows) == 1
    assert "알림함 정리 실패" in caplog.text


# 배치 연결 --------------------------------------------------------------------------

AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"


@pytest.fixture
def batch_client(monkeypatch):
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        batch_audience=AUDIENCE, batch_service_account=SCHEDULER,
    )
    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token",
                        lambda token, request, audience: {"email": SCHEDULER, "email_verified": True})
    yield
    app.dependency_overrides.clear()


def _run_batch(inbox: FakeInbox):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/notifications"):
            return inbox.handle(request)
        return httpx.Response(200, json=[])  # 매칭 · 보류 알림은 비어 있다

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return TestClient(app).post("/batch/chat-gate", headers={"Authorization": "Bearer id-token"})


def test_the_hourly_chat_gate_batch_purges_old_notifications(batch_client):
    inbox = FakeInbox([row(1, created_at="2020-01-01T00:00:00+00:00"), row(2, created_at=datetime.now(SEOUL).isoformat())])

    response = _run_batch(inbox)

    assert response.status_code == 200
    assert response.json()["notifications_purged"] == 1
    assert [r["id"] for r in inbox.rows] == [row(2)["id"]]


def test_a_failing_purge_does_not_fail_the_batch(batch_client):
    inbox = FakeInbox([row(1, created_at="2020-01-01T00:00:00+00:00")], fail_delete=True)

    response = _run_batch(inbox)

    assert response.status_code == 200
    assert response.json() == {"reminded": 0, "closed": 0, "passed": 0, "deferred_sent": 0, "notifications_purged": 0}
