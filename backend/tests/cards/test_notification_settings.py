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
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
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


def test_a_token_longer_than_4096_is_refused_before_the_db():
    """FCM 등록 토큰은 수백 자다. 상한이 없으면 아무 길이나 기본 키(text)로 들어간다(10-18 보안 점검)."""
    handler, seen = _recorder()
    response = _wire(handler).post("/cards/push-tokens", headers=AUTH_HEADERS,
                                   json={"token": "t" * 4097, "platform": "android"})

    assert response.status_code == 422
    assert [r for r in seen if r.url.path == "/rest/v1/push_tokens"] == []
    assert _wire(handler).post("/cards/push-tokens", headers=AUTH_HEADERS,
                               json={"token": "t" * 4096, "platform": "android"}).status_code == 200


def test_registering_keeps_only_the_newest_five_tokens_per_person():
    """기기 · 재설치마다 토큰이 쌓이면 알림 한 건이 그만큼 FCM 호출이 된다 — 새 토큰 + 최근 4개만 남긴다(10-18 보안 점검).
    지우는 것은 내 것만(profile_id), 새로 등록하는 토큰은 빼고 센다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.method == "GET" and request.url.path == "/rest/v1/push_tokens":
            return httpx.Response(200, json=[{"token": "old-5"}, {"token": "old-6"}])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/push-tokens", headers=AUTH_HEADERS,
                                   json={"token": "new-tok", "platform": "ios"})

    assert response.status_code == 200
    [older] = [r for r in seen if r.method == "GET" and r.url.path == "/rest/v1/push_tokens"]
    assert older.url.params["profile_id"] == f"eq.{PROFILE_ID}"
    assert older.url.params["token"] == "neq.new-tok"
    assert older.url.params["order"] == "updated_at.desc"
    assert older.url.params["offset"] == "4"
    deleted = [r for r in seen if r.method == "DELETE"]
    assert [(r.url.params["token"], r.url.params["profile_id"]) for r in deleted] == [
        ("eq.old-5", f"eq.{PROFILE_ID}"), ("eq.old-6", f"eq.{PROFILE_ID}")]
    # 등록(upsert)은 그대로 마지막에 나간다.
    assert seen[-1].method == "POST"
    assert json.loads(seen[-1].content)["token"] == "new-tok"


@pytest.mark.parametrize("method, path", [("POST", "/cards/push-tokens"), ("DELETE", "/cards/push-tokens/tok-1")])
def test_push_token_works_before_student_verification(method, path):
    """검토를 기다리는 사람도 토큰이 있어야 검토 결과 알림(A7)을 받는다 — 학생증 관문을 보지 않는다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "pending", "department": None, "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        seen.append(request)
        return httpx.Response(200, json=[])

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    body = {"token": "tok-1", "platform": "android"} if method == "POST" else None
    response = TestClient(app).request(method, path, headers=AUTH_HEADERS, json=body)

    assert response.status_code == 200
    assert seen[-1].method == method
    assert seen[-1].url.path.endswith("/push_tokens")


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
    """한 번도 저장한 적 없는 사람은 전부 켜짐(마케팅 · 방해 금지 시간만 꺼짐)으로 본다 — 화면이 빈 스위치를 그리지 않는다.
    방해 금지 시간은 2026-10-19 사용자 결정으로 처음에 꺼 둔다(기존 사용자는 마이그레이션이 행을 채워 켜진 채 둔다)."""
    body = _wire(_recorder()[0]).get("/cards/notification-settings", headers=AUTH_HEADERS).json()

    assert body["card_arrived"] is True
    assert body["quiet_hours"] is False
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


def test_matching_paused_is_read_from_the_profile():
    """화면 16 토글은 서버 값으로 그린다 — 안 읽으면 일시중지해 둔 사람도 다시 열 때 "켜짐"으로 보인다(A14)."""
    handler, seen = _recorder(rows=[{"matching_paused": True}])
    response = _wire(handler).get("/cards/matching-paused", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"paused": True}
    assert seen[-1].url.params["id"] == f"eq.{PROFILE_ID}"


def test_matching_paused_is_false_without_a_profile_row():
    body = _wire(_recorder()[0]).get("/cards/matching-paused", headers=AUTH_HEADERS).json()

    assert body == {"paused": False}
