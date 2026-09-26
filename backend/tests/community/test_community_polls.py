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


def _routes(**responses: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    """rpc 이름 → 응답. DELETE 는 키 'delete' 로 준다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "DELETE" and request.url.path.endswith("/polls"):
            return responses["delete"]
        name = request.url.path.rsplit("/rpc/", 1)[-1]
        if request.method == "POST" and name in responses:
            return responses[name]
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_create_trims_and_defaults_labels():
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_poll=httpx.Response(200, json=POLL_ID)), seen).post(
        "/community/polls", json={"question": "  짜장 vs 짬뽕  "}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert response.json() == {"id": POLL_ID}
    assert json.loads(seen[0].content) == {
        "p_author": PROFILE_ID, "p_question": "짜장 vs 짬뽕", "p_option_a": "찬성", "p_option_b": "반대"}


@pytest.mark.parametrize("body", [
    {"question": "   "},
    {"question": "가" * 81},
    {"question": "질문", "option_a_label": "가" * 7},
    {"question": "질문", "option_a_label": "좋아", "option_b_label": "좋아"},
    {"question": "질문", "option_b_label": "  "},
])
def test_create_rejects_bad_input_before_db(body):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_poll=httpx.Response(200, json=POLL_ID)), seen).post(
        "/community/polls", json=body, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_create_daily_limit_is_429():
    response = _wire(_routes(create_poll=httpx.Response(400, json={"code": "CM429", "message": "poll daily limit"}))).post(
        "/community/polls", json={"question": "열한 번째"}, headers=AUTH_HEADERS)
    assert response.status_code == 429
    assert response.json()["detail"] == errors.POLL_DAILY_LIMIT


def test_vote_returns_fresh_poll_and_reward():
    seen: list[httpx.Request] = []
    handler = _routes(cast_poll_vote=httpx.Response(200, json=True),
                      poll_feed=httpx.Response(200, json=[_row(my_choice="a", a_count=6)]))
    response = _wire(handler, seen).post(
        f"/community/polls/{POLL_ID}/votes", json={"choice": "a"}, headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json()["rewarded"] is True
    assert set(response.json()["poll"]) == POLL_KEYS
    assert response.json()["poll"]["a_count"] == 6
    assert json.loads(seen[0].content) == {"p_poll_id": POLL_ID, "p_voter": PROFILE_ID, "p_choice": "a"}


def test_vote_twice_is_409():
    handler = _routes(cast_poll_vote=httpx.Response(409, json={"code": "23505", "message": "duplicate key"}))
    response = _wire(handler).post(f"/community/polls/{POLL_ID}/votes", json={"choice": "b"}, headers=AUTH_HEADERS)
    assert response.status_code == 409
    assert response.json()["detail"] == errors.POLL_ALREADY_VOTED


@pytest.mark.parametrize("db_error", [
    httpx.Response(400, json={"code": "CM404", "message": "poll not found"}),
    # 확인과 insert 사이에 글이 지워짐 — PostgREST 는 FK 위반을 409 로 보낸다.
    httpx.Response(409, json={"code": "23503", "message": "violates foreign key constraint"}),
])
def test_vote_on_missing_or_hidden_poll_is_404(db_error):
    handler = _routes(cast_poll_vote=db_error)
    response = _wire(handler).post(f"/community/polls/{POLL_ID}/votes", json={"choice": "a"}, headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_vote_rejects_unknown_choice():
    seen: list[httpx.Request] = []
    response = _wire(_routes(cast_poll_vote=httpx.Response(200, json=True)), seen).post(
        f"/community/polls/{POLL_ID}/votes", json={"choice": "c"}, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_delete_own_poll_filters_by_author():
    seen: list[httpx.Request] = []
    response = _wire(_routes(delete=httpx.Response(200, json=[{"id": POLL_ID}])), seen).delete(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 204
    # author_id 조건이 빠지면 남의 글 id 로 지울 수 있다.
    assert seen[0].url.params["author_id"] == f"eq.{PROFILE_ID}"
    assert seen[0].url.params["id"] == f"eq.{POLL_ID}"
    assert seen[0].headers["Prefer"] == "return=representation"


def test_delete_others_poll_is_404_not_403():
    response = _wire(_routes(delete=httpx.Response(200, json=[]))).delete(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND
