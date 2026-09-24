import json
from collections.abc import Callable
from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
# 동의 시각을 서버가 적는지 보려면 그 "서버 시각" 이 무엇인지 알아야 한다 — 끼워서 고정한다.
NOW = datetime(2026, 9, 22, 14, 0, tzinfo=SEOUL)


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def _recorder(rows=None):
    """PostgREST 로 나간 요청을 모아 두는 핸들러."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=rows if rows is not None else [])

    return handler, seen


def test_push_token_is_upserted_with_the_platform():
    handler, seen = _recorder()
    response = _wire(handler).post("/cards/push-tokens", headers=AUTH_HEADERS,
                                   json={"token": "tok-1", "platform": "android"})

    assert response.status_code == 200
    body = json.loads(seen[-1].content)
    assert body["token"] == "tok-1"
    assert body["platform"] == "android"
    assert body["profile_id"] == PROFILE_ID
    # 같은 기기가 다시 등록해도 행이 하나로 합쳐져야 한다.
    assert seen[-1].headers["Prefer"] == "resolution=merge-duplicates"


def test_unknown_platform_is_refused():
    """platform 은 device_platform enum 이다 — 아무 문자열이나 DB 로 보내지 않는다."""
    response = _wire(_recorder()[0]).post("/cards/push-tokens", headers=AUTH_HEADERS,
                                          json={"token": "tok-1", "platform": "windows"})
    assert response.status_code == 422


def test_push_token_is_deleted_on_logout():
    handler, seen = _recorder()
    response = _wire(handler).delete("/cards/push-tokens/tok-1", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert seen[-1].method == "DELETE"
    assert seen[-1].url.params["token"] == "eq.tok-1"


def test_deleting_a_push_token_is_scoped_to_the_owner():
    """토큰 값만 보고 지우면 남의 토큰 값을 아는 사람이 남의 알림을 꺼버릴 수 있다."""
    handler, seen = _recorder()
    _wire(handler).delete("/cards/push-tokens/남의-토큰", headers=AUTH_HEADERS)

    assert seen[-1].url.params["profile_id"] == f"eq.{PROFILE_ID}"


def test_settings_row_missing_returns_defaults():
    """한 번도 저장한 적 없는 사람은 전부 켜짐(마케팅만 꺼짐)으로 본다 — 화면이 빈 스위치를 그리지 않는다."""
    body = _wire(_recorder()[0]).get("/cards/notification-settings", headers=AUTH_HEADERS).json()

    assert body["card_arrived"] is True
    assert body["quiet_hours"] is True
    assert body["marketing"] is False


def test_marketing_opt_in_records_the_server_time():
    """동의 시각은 서버가 적는다 — 법적 근거가 되는 값이라 앱이 보낸 시각을 믿지 않는다."""
    handler, seen = _recorder()
    response = _wire(handler).patch("/cards/notification-settings", headers=AUTH_HEADERS,
                                    json={"marketing": True})

    assert response.status_code == 200
    body = json.loads(seen[-1].content)
    assert body["marketing"] is True
    consented = datetime.fromisoformat(body["marketing_consented_at"])
    # 앱이 보낸 값이 아니라 서버 시계 그 시각이다 — "1분 안" 어림 대신 정확히 맞춘다.
    assert consented == NOW.astimezone(timezone.utc)


def test_marketing_opt_out_clears_the_consent_time():
    handler, seen = _recorder()
    _wire(handler).patch("/cards/notification-settings", headers=AUTH_HEADERS,
                         json={"marketing": False})

    body = json.loads(seen[-1].content)
    assert body["marketing"] is False
    assert body["marketing_consented_at"] is None


def test_unknown_switch_name_is_refused():
    """스위치 이름을 그대로 컬럼으로 쓰기 때문에 아는 이름만 받는다."""
    response = _wire(_recorder()[0]).patch("/cards/notification-settings", headers=AUTH_HEADERS,
                                           json={"drop_table": True})
    assert response.status_code == 422


def test_pausing_matching_updates_the_profile():
    handler, seen = _recorder()
    response = _wire(handler).patch("/cards/matching-paused", headers=AUTH_HEADERS,
                                    json={"paused": True})

    assert response.status_code == 200
    assert seen[-1].method == "PATCH"
    assert seen[-1].url.params["id"] == f"eq.{PROFILE_ID}"
    assert json.loads(seen[-1].content) == {"matching_paused": True}
