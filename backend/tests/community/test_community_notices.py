"""할 일 21 공지 — 앱 길(설계 docs/superpowers/specs/2026-11-24-community-notices-design.md "서버 · 앱").

GET /community/notices · 상세 /community/items/{id} 의 공지 · 공지 댓글 푸시 없음 · 앱 글쓰기 요청의 extra 칸 거절(보안 기준 21-2).
가짜 · 목 틀은 test_community_items.py 와 같다."""
from collections.abc import Callable
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app.community import comment_push
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
NOTICE_ID = "44444444-4444-4444-4444-444444444444"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
NOW = datetime(2026, 11, 24, 12, 0, tzinfo=timezone.utc)
SUPABASE_URL = "https://x.supabase.co"
NOTICE_KEYS = {"id", "title", "text", "image_url", "created_at", "is_new", "comment_count"}


def _notice_row(**overrides) -> dict:
    """notice_list 가 돌려주는 한 줄."""
    row = {
        "id": NOTICE_ID, "title": "서비스 점검 안내", "text": "점검 본문", "image_path": f"{NOTICE_ID}.jpg",
        "created_at": "2026-11-24T05:00:00+00:00", "comment_count": 2,
    }
    return {**row, **overrides}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url=SUPABASE_URL, supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def pushes(monkeypatch) -> list[tuple]:
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
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _routes(polls_kind: str | None = None, **responses: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    """rpc 이름 → 응답. GET /polls(select=kind)는 polls_kind 한 줄(None 이면 빈 것), DELETE /polls 는 지운 것 없음."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/polls"):
            if request.method == "DELETE":
                return httpx.Response(200, json=[])
            assert request.url.params["select"] == "kind"
            return httpx.Response(200, json=[{"kind": polls_kind}] if polls_kind else [])
        name = request.url.path.rsplit("/rpc/", 1)[-1]
        if request.method == "POST" and name in responses:
            return responses[name]
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


# 목록 ---------------------------------------------------------------------------

def test_notice_list_shape_has_no_author_and_builds_our_bucket_url():
    seen: list[httpx.Request] = []
    rows = [_notice_row(author_id="99999999-9999-9999-9999-999999999999", status="visible")]
    response = _wire(_routes(notice_list=httpx.Response(200, json=rows)), seen).get(
        "/community/notices", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"items", "has_more"}
    (item,) = body["items"]
    assert set(item) == NOTICE_KEYS
    # 그림 주소는 서버가 우리 공개 버킷 경로로만 만든다(보안 기준 21-4).
    assert item["image_url"] == f"{SUPABASE_URL}/storage/v1/object/public/community-notices/{NOTICE_ID}.jpg"
    assert item["title"] == "서비스 점검 안내"
    assert item["text"] == "점검 본문"
    assert item["comment_count"] == 2
    assert body["has_more"] is False
    assert seen[0].url.path.endswith("/rpc/notice_list")


def test_notice_without_an_image_has_a_null_url():
    response = _wire(_routes(notice_list=httpx.Response(200, json=[_notice_row(image_path=None)]))).get(
        "/community/notices", headers=AUTH_HEADERS)

    assert response.json()["items"][0]["image_url"] is None


@pytest.mark.parametrize(("age", "is_new"), [
    (timedelta(0), True),
    (timedelta(days=7) - timedelta(seconds=1), True),
    (timedelta(days=7), False),
    (timedelta(days=8), False),
], ids=["방금", "7일 1초 전", "딱 7일", "8일"])
def test_is_new_means_within_seven_days_of_the_server_clock(age, is_new):
    created_at = (NOW - age).isoformat()
    response = _wire(_routes(notice_list=httpx.Response(200, json=[_notice_row(created_at=created_at)]))).get(
        "/community/notices", headers=AUTH_HEADERS)

    assert response.json()["items"][0]["is_new"] is is_new


def test_a_full_page_says_there_may_be_more_and_the_cursor_reaches_the_db():
    seen: list[httpx.Request] = []
    rows = [_notice_row(id=f"44444444-4444-4444-4444-{i:012d}") for i in range(20)]
    response = _wire(_routes(notice_list=httpx.Response(200, json=rows)), seen).get(
        "/community/notices", params={"before": "2026-11-24T05:00:00+00:00", "before_id": NOTICE_ID},
        headers=AUTH_HEADERS)

    assert response.json()["has_more"] is True
    sent = seen[0].read().decode()
    assert '"p_before_id": "' + NOTICE_ID + '"' in sent or f'"p_before_id":"{NOTICE_ID}"' in sent
    assert '"p_limit": 20' in sent or '"p_limit":20' in sent


def test_a_half_cursor_is_422():
    response = _wire(_routes()).get("/community/notices", params={"before": "2026-11-24T05:00:00+00:00"},
                                     headers=AUTH_HEADERS)

    assert response.status_code == 422


# 상세 ---------------------------------------------------------------------------

def test_item_detail_returns_a_notice_with_title_and_image_url():
    handler = _routes(polls_kind="notice", community_feed=httpx.Response(200, json=[]),
                      notice_list=httpx.Response(200, json=[_notice_row()]))
    response = _wire(handler).get(f"/community/items/{NOTICE_ID}", headers=AUTH_HEADERS)

    assert response.status_code == 200
    item = response.json()["item"]
    assert item["kind"] == "notice"
    assert item["title"] == "서비스 점검 안내"
    assert item["image_url"] == f"{SUPABASE_URL}/storage/v1/object/public/community-notices/{NOTICE_ID}.jpg"
    assert item["poll"] is None
    assert item["is_mine"] is False
    assert "author_id" not in item


def test_item_detail_of_a_post_has_null_title_and_image_url():
    row = {"id": NOTICE_ID, "kind": "post", "category": "love", "text": "글", "option_a_label": None,
           "option_b_label": None, "created_at": "2026-11-24T05:00:00+00:00", "a_count": 0, "b_count": 0,
           "my_choice": None, "is_mine": False, "comment_count": 0}
    response = _wire(_routes(community_feed=httpx.Response(200, json=[row]))).get(
        f"/community/items/{NOTICE_ID}", headers=AUTH_HEADERS)

    item = response.json()["item"]
    assert (item["title"], item["image_url"]) == (None, None)


def test_a_hidden_notice_is_404_with_the_notice_wording():
    handler = _routes(polls_kind="notice", community_feed=httpx.Response(200, json=[]),
                      notice_list=httpx.Response(200, json=[]))
    response = _wire(handler).get(f"/community/items/{NOTICE_ID}", headers=AUTH_HEADERS)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.COMMUNITY_NOTICE_NOT_FOUND == "공지를 찾을 수 없어요"


def test_a_missing_item_is_still_404_with_the_item_wording():
    response = _wire(_routes(community_feed=httpx.Response(200, json=[]))).get(
        f"/community/items/{NOTICE_ID}", headers=AUTH_HEADERS)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.COMMUNITY_ITEM_NOT_FOUND


def test_a_user_cannot_delete_a_notice():
    # 공지는 주인이 없다 — 지우기는 author_id=나 조건이라 지운 줄이 없어 404.
    seen: list[httpx.Request] = []
    response = _wire(_routes(), seen).delete(f"/community/items/{NOTICE_ID}", headers=AUTH_HEADERS)

    assert response.status_code == 404
    (delete,) = [r for r in seen if r.method == "DELETE"]
    assert delete.url.params["author_id"] == f"eq.{PROFILE_ID}"


# 공지 댓글 ------------------------------------------------------------------------

def test_a_notice_comment_sends_no_push(pushes):
    seen: list[httpx.Request] = []
    row = {"id": "33333333-3333-3333-3333-333333333333", "body": "확인했어요", "created_at": "2026-11-24T05:00:00+00:00",
           "alias_no": 1, "is_post_author": False, "is_mine": True, "can_delete": True,
           "poll_author_id": None, "poll_question": "점검 본문"}
    response = _wire(_routes(add_poll_comment=httpx.Response(200, json=[row])), seen).post(
        f"/community/items/{NOTICE_ID}/comments", json={"body": "확인했어요"}, headers=AUTH_HEADERS)

    assert response.status_code == 201
    assert response.json()["alias_no"] == 1
    assert pushes == []
    # 알림함(10분 묶음)도 보러 가지 않는다.
    assert [r for r in seen if r.url.path.endswith("/notifications")] == []


# 앱 글쓰기는 운영자 글 칸을 받지 않는다(보안 기준 21-2) ---------------------------------

@pytest.mark.parametrize("extra", [{"kind": "notice"}, {"title": "제목"}, {"image": "x.jpg"}, {"image_path": "x.jpg"},
                                   {"author_id": None}])
def test_post_request_with_an_extra_field_is_422(extra):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=NOTICE_ID)), seen).post(
        "/community/posts", json={"category": "free", "body": "글", **extra}, headers=AUTH_HEADERS)

    assert response.status_code == 422
    assert [r for r in seen if r.url.path.endswith("/rpc/create_community_item")] == []


@pytest.mark.parametrize("extra", [{"kind": "notice"}, {"title": "제목"}, {"image_path": "x.jpg"}])
def test_poll_request_with_an_extra_field_is_422(extra):
    response = _wire(_routes(create_community_item=httpx.Response(200, json=NOTICE_ID))).post(
        "/community/polls", json={"question": "질문", **extra}, headers=AUTH_HEADERS)

    assert response.status_code == 422


def test_the_1_0_6_poll_request_shape_still_passes():
    # 1.0.6 앱은 question · option_a_label · option_b_label 셋만 보낸다 — extra 금지가 옛 앱을 막지 않는다.
    response = _wire(_routes(create_community_item=httpx.Response(200, json=NOTICE_ID))).post(
        "/community/polls", json={"question": "질문", "option_a_label": "찬성", "option_b_label": "반대"},
        headers=AUTH_HEADERS)

    assert response.status_code == 201
