"""O/X 글 댓글(GET · POST /community/polls/{id}/comments, DELETE /community/comments/{id}). 읽기 · 쓰기 · 지우기는 DB 함수(RPC)다."""
import json
from collections.abc import Callable
from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app.community import comment_push
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTHOR_ID = "99999999-9999-9999-9999-999999999999"
POLL_ID = "22222222-2222-2222-2222-222222222222"
COMMENT_ID = "33333333-3333-3333-3333-333333333333"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
COMMENT_KEYS = {"id", "body", "created_at", "alias_no", "is_post_author", "is_mine", "can_delete"}
NOW = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)


def _comment(**overrides) -> dict:
    row = {
        "id": COMMENT_ID, "body": "저는 학식이요", "created_at": "2026-11-10T05:00:00.123456+00:00",
        "alias_no": 1, "is_post_author": False, "is_mine": False, "can_delete": False,
    }
    return {**row, **overrides}


def _added(**overrides) -> dict:
    """add_poll_comment 가 돌려주는 줄 — 댓글 한 줄 + 푸시에 쓸 글쓴이 id · 질문."""
    return _comment(is_mine=True, can_delete=True, poll_author_id=AUTHOR_ID, poll_question="학식 vs 편의점", **overrides)


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


@pytest.fixture(autouse=True)
def pushes(monkeypatch) -> list[tuple]:
    """푸시 본체(notify)는 여기서 부르지 않고 무엇을 보내려 했는지만 본다. 규칙 자체는 test_poll_comment_push.py."""
    calls: list[tuple] = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, title, body, data))
        return 1

    monkeypatch.setattr(comment_push, "notify", fake_notify)
    return calls


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
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
        # 푸시 묶기 확인(notifications 읽기)은 비어 있는 것으로 둔다.
        if request.method == "GET" and request.url.path.endswith("/notifications"):
            return httpx.Response(200, json=[])
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def _db_error(code: str, status: int = 400) -> httpx.Response:
    return httpx.Response(status, json={"code": code, "message": "x", "details": None, "hint": None})


# 목록 -----------------------------------------------------------------------

def test_list_gives_seven_keys_and_never_author_id():
    # DB 함수가 실수로 author_id 를 돌려줘도 응답에는 실리지 않아야 한다(익명).
    leaked = _comment(author_id=AUTHOR_ID)
    response = _wire(_rpc("poll_comments_page", httpx.Response(200, json=[leaked]))).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert set(response.json()["items"][0]) == COMMENT_KEYS


def test_list_passes_labels_through():
    rows = [_comment(alias_no=3), _comment(alias_no=None, is_post_author=True), _comment(is_mine=True, can_delete=True)]
    items = _wire(_rpc("poll_comments_page", httpx.Response(200, json=rows))).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS).json()["items"]
    assert [(i["alias_no"], i["is_post_author"], i["is_mine"], i["can_delete"]) for i in items] == [
        (3, False, False, False), (None, True, False, False), (1, False, True, True)]


def test_list_asks_for_one_extra_row_and_sends_viewer_poll_and_cursor():
    seen: list[httpx.Request] = []
    _wire(_rpc("poll_comments_page", httpx.Response(200, json=[])), seen).get(
        f"/community/polls/{POLL_ID}/comments",
        params={"after": "2026-11-10T05:00:00.123456+00:00", "after_id": COMMENT_ID}, headers=AUTH_HEADERS)
    body = json.loads(seen[0].content)
    assert body == {"p_viewer": PROFILE_ID, "p_poll_id": POLL_ID, "p_after": "2026-11-10T05:00:00.123456+00:00",
                    "p_after_id": COMMENT_ID, "p_limit": 11}


def test_first_page_sends_no_cursor():
    seen: list[httpx.Request] = []
    _wire(_rpc("poll_comments_page", httpx.Response(200, json=[])), seen).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS)
    body = json.loads(seen[0].content)
    assert (body["p_after"], body["p_after_id"]) == (None, None)


def test_eleven_rows_mean_more_and_only_ten_are_returned():
    rows = [_comment(id=f"{i:08d}-3333-3333-3333-333333333333") for i in range(11)]
    body = _wire(_rpc("poll_comments_page", httpx.Response(200, json=rows))).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS).json()
    assert body["has_more"] is True
    assert [item["id"] for item in body["items"]] == [row["id"] for row in rows[:10]]


def test_exactly_ten_rows_mean_no_more():
    # 한 쪽이 딱 꽉 찼어도 다음 쪽이 없을 수 있다 — limit + 1 줄로 정확히 안다.
    rows = [_comment(id=f"{i:08d}-3333-3333-3333-333333333333") for i in range(10)]
    body = _wire(_rpc("poll_comments_page", httpx.Response(200, json=rows))).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS).json()
    assert (len(body["items"]), body["has_more"]) == (10, False)


@pytest.mark.parametrize("params", [{"after": "2026-11-10T05:00:00+00:00"}, {"after_id": COMMENT_ID}])
def test_cursor_needs_both_halves_before_db(params):
    # 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼 빈 쪽이 "끝" 으로 읽힌다.
    seen: list[httpx.Request] = []
    response = _wire(_rpc("poll_comments_page", httpx.Response(200, json=[])), seen).get(
        f"/community/polls/{POLL_ID}/comments", params=params, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_list_of_a_missing_or_blinded_poll_is_404():
    response = _wire(_rpc("poll_comments_page", _db_error("CM404"))).get(
        f"/community/polls/{POLL_ID}/comments", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


# 쓰기 -----------------------------------------------------------------------

def _post(client: TestClient, body: dict | None = None):
    return client.post(f"/community/polls/{POLL_ID}/comments", json={"body": "저는 학식이요"} if body is None else body, headers=AUTH_HEADERS)


def test_post_is_201_with_one_comment_line_and_no_push_fields():
    response = _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()]))))
    assert response.status_code == 201
    assert set(response.json()) == COMMENT_KEYS
    assert response.json()["is_mine"] is True and response.json()["can_delete"] is True


def test_post_sends_author_poll_and_trimmed_body():
    seen: list[httpx.Request] = []
    _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()])), seen), {"body": "  저는 학식이요  "})
    assert json.loads(seen[0].content) == {"p_author": PROFILE_ID, "p_poll_id": POLL_ID, "p_body": "저는 학식이요"}


def test_post_accepts_exactly_200_characters():
    assert _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()]))), {"body": "가" * 200}).status_code == 201


@pytest.mark.parametrize("body", [{"body": ""}, {"body": "   "}, {"body": "가" * 201}, {}, {"body": 5}],
                         ids=["빈 글", "공백뿐", "201자", "칸 없음", "숫자"])
def test_post_rejects_bad_body_before_db(body):
    seen: list[httpx.Request] = []
    response = _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()])), seen), body)
    assert response.status_code == 422
    assert seen == []


def test_post_over_the_daily_limit_is_429():
    response = _post(_wire(_rpc("add_poll_comment", _db_error("CM429"))))
    assert response.status_code == 429
    assert response.json()["detail"] == errors.POLL_COMMENT_DAILY_LIMIT


@pytest.mark.parametrize("code", ["CM404", "23503"])
def test_post_to_a_missing_blinded_or_just_deleted_poll_is_404(code):
    response = _post(_wire(_rpc("add_poll_comment", _db_error(code, 404 if code == "CM404" else 409))))
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


# 푸시(규칙 본체는 test_poll_comment_push.py) --------------------------------------

def test_post_pushes_the_poll_author_with_the_poll_route(pushes):
    _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()]))))
    assert pushes == [(AUTHOR_ID, "poll_comment", "내 질문에 새 댓글이 달렸어요", "학식 vs 편의점",
                       {"route": "poll", "poll_id": POLL_ID})]


def test_post_does_not_push_the_comment_text_or_commenter(pushes):
    _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added(body="비밀 댓글")]))), {"body": "비밀 댓글"})
    (_, _, title, body, data), = pushes
    assert "비밀 댓글" not in f"{title}{body}{json.dumps(data)}"
    assert PROFILE_ID not in f"{title}{body}{json.dumps(data)}"


def test_post_still_201_when_the_push_blows_up(monkeypatch, caplog):
    async def failing(*args, **kwargs):
        raise RuntimeError("fcm down")

    monkeypatch.setattr(comment_push, "notify", failing)
    with caplog.at_level("ERROR"):
        response = _post(_wire(_rpc("add_poll_comment", httpx.Response(200, json=[_added()]))))
    assert response.status_code == 201
    assert "댓글 푸시 실패" in caplog.text


# 지우기 ---------------------------------------------------------------------

def test_delete_is_204_when_the_function_deleted_a_row():
    seen: list[httpx.Request] = []
    response = _wire(_rpc("delete_poll_comment", httpx.Response(200, json=[COMMENT_ID])), seen).delete(
        f"/community/comments/{COMMENT_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 204
    assert json.loads(seen[0].content) == {"p_viewer": PROFILE_ID, "p_comment_id": COMMENT_ID}


def test_delete_without_permission_is_404_like_a_missing_comment():
    # 남의 댓글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 댓글이라는 게 샌다.
    response = _wire(_rpc("delete_poll_comment", httpx.Response(200, json=[]))).delete(
        f"/community/comments/{COMMENT_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_COMMENT_NOT_FOUND
