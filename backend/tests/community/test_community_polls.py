import json
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
POLL_ID = "22222222-2222-2222-2222-222222222222"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
POLL_KEYS = {"id", "question", "option_a_label", "option_b_label", "created_at",
             "a_count", "b_count", "my_choice", "is_mine"}


def _row(**overrides) -> dict:
    row = {
        "id": POLL_ID, "question": "첫 데이트 더치페이", "option_a_label": "찬성", "option_b_label": "반대",
        "created_at": "2026-09-27T05:00:00+00:00", "a_count": 5, "b_count": 3, "my_choice": None, "is_mine": False,
    }
    return {**row, **overrides}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None,
          verification: str = "verified") -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴공"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _rpc(name: str, response: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST" and request.url.path.endswith(f"/rpc/{name}"):
            return response
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_feed_gives_nine_keys_and_never_author_id():
    # DB 함수가 실수로 author_id 를 돌려줘도 응답에는 실리지 않아야 한다(익명, Global Constraint 1).
    leaked = _row(author_id=PROFILE_ID)
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[leaked]))).get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert set(response.json()["polls"][0]) == POLL_KEYS


def test_feed_sends_viewer_cursor_and_page_size():
    seen: list[httpx.Request] = []
    _wire(_rpc("poll_feed", httpx.Response(200, json=[])), seen).get(
        "/community/polls", params={"before": "2026-09-27T05:00:00+00:00", "before_id": POLL_ID},
        headers=AUTH_HEADERS)
    body = json.loads(seen[0].content)
    assert body["p_viewer"] == PROFILE_ID
    assert body["p_poll_id"] is None
    assert body["p_before"] == "2026-09-27T05:00:00+00:00"
    assert body["p_before_id"] == POLL_ID
    assert body["p_limit"] == 20


@pytest.mark.parametrize("params", [{"before": "2026-09-27T05:00:00+00:00"}, {"before_id": POLL_ID}])
def test_feed_rejects_half_cursor(params):
    # 하나만 오면 DB 커서 비교가 null 이 돼 빈 페이지가 "끝" 으로 읽힌다.
    seen: list[httpx.Request] = []
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[])), seen).get(
        "/community/polls", params=params, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


@pytest.mark.parametrize(("count", "has_more"), [(20, True), (3, False)])
def test_feed_has_more_only_when_page_is_full(count, has_more):
    rows = [_row(id=f"{i:08d}-2222-2222-2222-222222222222") for i in range(count)]
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=rows))).get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.json()["has_more"] is has_more


def test_detail_returns_one_poll():
    seen: list[httpx.Request] = []
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[_row(my_choice="a")])), seen).get(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json()["poll"]["my_choice"] == "a"
    body = json.loads(seen[0].content)
    assert body["p_poll_id"] == POLL_ID
    assert body["p_limit"] == 1


def test_detail_404_when_hidden_or_missing():
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[]))).get(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_feed_requires_student_verification():
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[])), verification="pending").get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.status_code == 403

