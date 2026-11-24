"""할 일 19 게시물 + 카테고리(설계 docs/superpowers/specs/2026-11-24-community-posts-design.md).

새 길(/community/feed · /community/items · /community/posts)과, 1.0.6 앱이 부르는 옛 길(/community/polls)의 모양을 함께 못박는다.
가짜 · 목 틀은 test_community_polls.py 와 같다."""
import json
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.community import comment_push
from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTHOR_ID = "99999999-9999-9999-9999-999999999999"
ITEM_ID = "22222222-2222-2222-2222-222222222222"
COMMENT_ID = "33333333-3333-3333-3333-333333333333"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
ITEM_KEYS = {"id", "kind", "category", "text", "created_at", "is_mine", "comment_count", "poll"}
POLL_PART_KEYS = {"option_a_label", "option_b_label", "a_count", "b_count", "my_choice"}
TABS = ["all", "popular", "mine", "voted", "free", "career", "love"]


def _feed_row(**overrides) -> dict:
    """community_feed 가 돌려주는 한 줄(투표)."""
    row = {
        "id": ITEM_ID, "kind": "poll", "category": "free", "text": "첫 데이트 더치페이",
        "option_a_label": "찬성", "option_b_label": "반대", "created_at": "2026-11-24T05:00:00+00:00",
        "a_count": 5, "b_count": 3, "my_choice": None, "is_mine": False, "comment_count": 4,
    }
    return {**row, **overrides}


def _post_row(**overrides) -> dict:
    return _feed_row(kind="post", category="love", text="오늘 고백했어요", option_a_label=None, option_b_label=None,
                     a_count=0, b_count=0, **overrides)


def _poll_row(**overrides) -> dict:
    """poll_feed(옛 길)가 돌려주는 한 줄 — 1.0.6 앱이 받는 열 칸."""
    row = {
        "id": ITEM_ID, "question": "첫 데이트 더치페이", "option_a_label": "찬성", "option_b_label": "반대",
        "created_at": "2026-09-27T05:00:00+00:00", "a_count": 5, "b_count": 3, "my_choice": None, "is_mine": False,
        "comment_count": 4,
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
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _routes(**responses: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    """rpc 이름 → 응답. DELETE /polls 는 키 'delete', 알림함(푸시 10분 묶음 확인)은 늘 빈 것."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "DELETE" and request.url.path.endswith("/polls"):
            return responses["delete"]
        if request.method == "GET" and request.url.path.endswith("/notifications"):
            return httpx.Response(200, json=[])
        # 상세가 피드에서 못 찾으면 공지인지 본다(할 일 21) — 이 시험들의 글은 공지가 아니다(없는 글).
        if request.method == "GET" and request.url.path.endswith("/polls"):
            return httpx.Response(200, json=[])
        name = request.url.path.rsplit("/rpc/", 1)[-1]
        if request.method == "POST" and name in responses:
            return responses[name]
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


# 옛 길(1.0.6) — 응답 모양 고정 ----------------------------------------------------------

def test_old_feed_keeps_the_1_0_6_shape_and_types():
    # 1.0.6 앱이 읽는 모양. 칸이 빠지거나 타입이 바뀌면 지금 스토어 앱이 깨진다(보안 기준 19-5).
    # DB 가 kind · category · author_id 를 실수로 줘도 옛 응답에는 실리지 않는다.
    rows = [_poll_row(my_choice="a", is_mine=True, kind="poll", category="love", author_id=AUTHOR_ID)]
    seen: list[httpx.Request] = []
    response = _wire(_routes(poll_feed=httpx.Response(200, json=rows)), seen).get(
        "/community/polls", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"polls", "has_more"}
    assert isinstance(body["has_more"], bool)
    (poll,) = body["polls"]
    assert {key: type(value) for key, value in poll.items()} == {
        "id": str, "question": str, "option_a_label": str, "option_b_label": str, "created_at": str,
        "a_count": int, "b_count": int, "my_choice": str, "is_mine": bool, "comment_count": int,
    }
    # 옛 길은 투표만 거르는 poll_feed 를 그대로 부른다.
    assert seen[0].url.path.endswith("/rpc/poll_feed")


def test_old_detail_keeps_the_1_0_6_shape():
    response = _wire(_routes(poll_feed=httpx.Response(200, json=[_poll_row(kind="poll", category="free")]))).get(
        f"/community/polls/{ITEM_ID}", headers=AUTH_HEADERS)
    assert set(response.json()) == {"poll"}
    assert set(response.json()["poll"]) == {"id", "question", "option_a_label", "option_b_label", "created_at",
                                            "a_count", "b_count", "my_choice", "is_mine", "comment_count"}


def test_old_create_without_category_is_a_free_poll():
    # 1.0.6 앱은 category 를 모른다 — 자유 게시판 투표로 들어간다(보안 기준 19-5).
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/polls", json={"question": "  짜장 vs 짬뽕  "}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert response.json() == {"id": ITEM_ID}
    assert json.loads(seen[0].content) == {
        "p_author": PROFILE_ID, "p_kind": "poll", "p_category": "free", "p_text": "짜장 vs 짬뽕",
        "p_option_a": "찬성", "p_option_b": "반대"}


def test_old_create_measures_the_question_after_trimming_like_posts_and_comments():
    # 투표 질문 · 게시물 본문 · 댓글은 같은 본문 검사(core/text.py body_text)를 길이만 달리해 쓴다 — 앞뒤 공백을 깎은 뒤 잰다.
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/polls", json={"question": "  " + "가" * 400 + "\n"}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert json.loads(seen[0].content)["p_text"] == "가" * 400


@pytest.mark.parametrize("question", ["​​", "널\x00", "방향‮"], ids=["0폭만", "널", "방향"])
def test_old_create_keeps_rejecting_bad_questions(question):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/polls", json={"question": question}, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


@pytest.mark.parametrize("category", ["free", "career", "love"])
def test_old_create_passes_a_chosen_category(category):
    seen: list[httpx.Request] = []
    _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/polls", json={"question": "질문", "category": category}, headers=AUTH_HEADERS)
    assert json.loads(seen[0].content)["p_category"] == category


@pytest.mark.parametrize("category", ["hot", "FREE", "", None])
def test_old_create_rejects_an_unknown_category_before_db(category):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/polls", json={"question": "질문", "category": category}, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_old_create_daily_limit_keeps_the_poll_message():
    response = _wire(_routes(create_community_item=httpx.Response(400, json={"code": "CM429", "message": "x"}))).post(
        "/community/polls", json={"question": "열한 번째"}, headers=AUTH_HEADERS)
    assert response.status_code == 429
    assert response.json()["detail"] == errors.POLL_DAILY_LIMIT


# 새 피드 ------------------------------------------------------------------------------

def test_feed_items_have_fixed_keys_and_never_author_id():
    # DB 가 실수로 author_id 를 돌려줘도 응답에는 실리지 않는다(익명, 보안 기준 19-1).
    rows = [_feed_row(author_id=AUTHOR_ID), _post_row(author_id=AUTHOR_ID)]
    response = _wire(_routes(community_feed=httpx.Response(200, json=rows))).get(
        "/community/feed", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"items", "has_more"}
    poll, post = body["items"]
    assert set(poll) == ITEM_KEYS
    assert set(post) == ITEM_KEYS
    assert set(poll["poll"]) == POLL_PART_KEYS
    assert "author_id" not in json.dumps(body)


def test_feed_poll_item_carries_the_poll_part():
    response = _wire(_routes(community_feed=httpx.Response(200, json=[_feed_row(my_choice="b")]))).get(
        "/community/feed", headers=AUTH_HEADERS)
    item = response.json()["items"][0]
    assert item == {
        "id": ITEM_ID, "kind": "poll", "category": "free", "text": "첫 데이트 더치페이",
        "created_at": "2026-11-24T05:00:00+00:00", "is_mine": False, "comment_count": 4,
        "poll": {"option_a_label": "찬성", "option_b_label": "반대", "a_count": 5, "b_count": 3, "my_choice": "b"},
    }


def test_feed_post_item_has_null_poll():
    response = _wire(_routes(community_feed=httpx.Response(200, json=[_post_row()]))).get(
        "/community/feed", headers=AUTH_HEADERS)
    item = response.json()["items"][0]
    assert item["kind"] == "post"
    assert item["category"] == "love"
    assert item["text"] == "오늘 고백했어요"
    assert item["poll"] is None


def test_feed_sends_viewer_cursor_page_size_and_tab():
    seen: list[httpx.Request] = []
    _wire(_routes(community_feed=httpx.Response(200, json=[])), seen).get(
        "/community/feed", params={"before": "2026-11-24T05:00:00+00:00", "before_id": ITEM_ID, "tab": "career"},
        headers=AUTH_HEADERS)
    assert seen[0].url.path.endswith("/rpc/community_feed")
    assert json.loads(seen[0].content) == {
        "p_viewer": PROFILE_ID, "p_item_id": None, "p_before": "2026-11-24T05:00:00+00:00",
        "p_before_id": ITEM_ID, "p_limit": 20, "p_tab": "career"}


@pytest.mark.parametrize("tab", TABS)
def test_feed_accepts_the_seven_tabs(tab):
    seen: list[httpx.Request] = []
    response = _wire(_routes(community_feed=httpx.Response(200, json=[])), seen).get(
        "/community/feed", params={"tab": tab}, headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert json.loads(seen[0].content)["p_tab"] == tab


@pytest.mark.parametrize("tab", ["hot", "ALL", "", "poll"])
def test_feed_rejects_an_unknown_tab_before_db(tab):
    seen: list[httpx.Request] = []
    response = _wire(_routes(community_feed=httpx.Response(200, json=[])), seen).get(
        "/community/feed", params={"tab": tab}, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


@pytest.mark.parametrize("params", [
    {"before": "2026-11-24T05:00:00+00:00"},
    {"before_id": ITEM_ID},
    {"tab": "popular", "before": "2026-11-24T05:00:00+00:00", "before_id": ITEM_ID},
], ids=["시각만", "id만", "인기+커서"])
def test_feed_rejects_a_bad_cursor_before_db(params):
    seen: list[httpx.Request] = []
    response = _wire(_routes(community_feed=httpx.Response(200, json=[])), seen).get(
        "/community/feed", params=params, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


@pytest.mark.parametrize(("tab", "count", "has_more"), [
    ("all", 20, True), ("all", 3, False), ("love", 20, True), ("popular", 20, False)])
def test_feed_has_more_only_on_a_full_cursor_page(tab, count, has_more):
    rows = [_feed_row(id=f"{i:08d}-2222-2222-2222-222222222222") for i in range(count)]
    response = _wire(_routes(community_feed=httpx.Response(200, json=rows))).get(
        "/community/feed", params={"tab": tab}, headers=AUTH_HEADERS)
    assert response.json()["has_more"] is has_more


# 상세 -------------------------------------------------------------------------------

def test_item_detail_returns_one_item_from_community_feed():
    seen: list[httpx.Request] = []
    response = _wire(_routes(community_feed=httpx.Response(200, json=[_post_row(is_mine=True)])), seen).get(
        f"/community/items/{ITEM_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert set(response.json()) == {"item"}
    # 할 일 21: 상세는 공지와 같은 모양이 되게 title · image_url 이 붙는다(투표 · 게시물은 null).
    assert set(response.json()["item"]) == ITEM_KEYS | {"title", "image_url"}
    assert (response.json()["item"]["title"], response.json()["item"]["image_url"]) == (None, None)
    assert response.json()["item"]["is_mine"] is True
    body = json.loads(seen[0].content)
    assert body["p_item_id"] == ITEM_ID
    assert body["p_limit"] == 1
    assert body["p_tab"] == "all"


def test_item_detail_404_when_hidden_or_missing():
    response = _wire(_routes(community_feed=httpx.Response(200, json=[]))).get(
        f"/community/items/{ITEM_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.COMMUNITY_ITEM_NOT_FOUND


# 게시물 올리기 -------------------------------------------------------------------------

def test_create_post_sends_a_trimmed_body_without_options():
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/posts", json={"category": "career", "body": "  첫 줄\n둘째 줄  "}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert response.json() == {"id": ITEM_ID}
    assert json.loads(seen[0].content) == {
        "p_author": PROFILE_ID, "p_kind": "post", "p_category": "career", "p_text": "첫 줄\n둘째 줄",
        "p_option_a": None, "p_option_b": None}


def test_create_post_accepts_exactly_500_characters():
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/posts", json={"category": "free", "body": "가" * 500}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert json.loads(seen[0].content)["p_text"] == "가" * 500


@pytest.mark.parametrize("body", [
    {"category": "free", "body": "가" * 501},
    {"category": "free", "body": "널\x00문자"},
    {"category": "free", "body": "종\x07소리"},
    {"category": "free", "body": "방향‮뒤집기"},
    {"category": "free", "body": "   \n\t "},
    {"category": "free", "body": ""},
    {"category": "free", "body": "​‍﻿"},
    {"category": "hot", "body": "글"},
    {"category": "Free", "body": "글"},
    {"body": "카테고리 없음"},
    {"category": "free"},
], ids=["501자", "널", "제어", "방향", "공백만", "빈", "0폭만", "모르는카테고리", "대문자", "카테고리없음", "본문없음"])
def test_create_post_rejects_bad_input_before_db(body):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_community_item=httpx.Response(200, json=ITEM_ID)), seen).post(
        "/community/posts", json=body, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_create_post_daily_limit_is_429_with_the_community_message():
    response = _wire(_routes(create_community_item=httpx.Response(400, json={"code": "CM429", "message": "x"}))).post(
        "/community/posts", json={"category": "free", "body": "열한 번째"}, headers=AUTH_HEADERS)
    assert response.status_code == 429
    assert response.json()["detail"] == errors.COMMUNITY_DAILY_LIMIT


# 삭제 · 댓글(기존 처리 함수에 새 길) ---------------------------------------------------------

def test_delete_own_item_filters_by_author():
    seen: list[httpx.Request] = []
    response = _wire(_routes(delete=httpx.Response(200, json=[{"id": ITEM_ID}])), seen).delete(
        f"/community/items/{ITEM_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 204
    assert seen[0].url.params["author_id"] == f"eq.{PROFILE_ID}"
    assert seen[0].url.params["id"] == f"eq.{ITEM_ID}"


def test_delete_others_item_is_404_not_403():
    response = _wire(_routes(delete=httpx.Response(200, json=[]))).delete(
        f"/community/items/{ITEM_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.COMMUNITY_ITEM_NOT_FOUND


def test_old_delete_keeps_the_poll_message():
    response = _wire(_routes(delete=httpx.Response(200, json=[]))).delete(
        f"/community/polls/{ITEM_ID}", headers=AUTH_HEADERS)
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_item_comments_list_uses_the_same_page_function():
    seen: list[httpx.Request] = []
    response = _wire(_routes(poll_comments_page=httpx.Response(200, json=[])), seen).get(
        f"/community/items/{ITEM_ID}/comments", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json() == {"items": [], "has_more": False}
    assert json.loads(seen[0].content)["p_poll_id"] == ITEM_ID


@pytest.mark.parametrize(("path", "detail"), [
    (f"/community/items/{ITEM_ID}/comments", errors.COMMUNITY_ITEM_NOT_FOUND),
    (f"/community/polls/{ITEM_ID}/comments", errors.POLL_NOT_FOUND),
], ids=["새 길", "옛 길"])
def test_comments_on_a_hidden_item_are_404_with_the_route_message(path, detail):
    handler = _routes(poll_comments_page=httpx.Response(400, json={"code": "CM404", "message": "x"}),
                      add_poll_comment=httpx.Response(400, json={"code": "CM404", "message": "x"}))
    client = _wire(handler)
    listed = client.get(path, headers=AUTH_HEADERS)
    added = client.post(path, json={"body": "댓글"}, headers=AUTH_HEADERS)
    assert (listed.status_code, listed.json()["detail"]) == (404, detail)
    assert (added.status_code, added.json()["detail"]) == (404, detail)


def _added(**overrides) -> dict:
    return {"id": COMMENT_ID, "body": "응원해요", "created_at": "2026-11-24T05:00:00+00:00", "alias_no": 1,
            "is_post_author": False, "is_mine": True, "can_delete": True,
            "poll_author_id": AUTHOR_ID, "poll_question": "오늘 고백했어요", **overrides}


@pytest.mark.parametrize(("path", "title"), [
    (f"/community/items/{ITEM_ID}/comments", "내 글에 새 댓글이 달렸어요"),
    (f"/community/polls/{ITEM_ID}/comments", "내 질문에 새 댓글이 달렸어요"),
], ids=["새 길", "옛 길"])
def test_comment_push_title_follows_the_route(pushes, path, title):
    # 사용자 결정(11-24): 새 길로 단 댓글은 투표 · 게시물 모두 "내 글", 옛 길(1.0.6)은 지금 제목 그대로.
    response = _wire(_routes(add_poll_comment=httpx.Response(200, json=[_added()]))).post(
        path, json={"body": "응원해요"}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert "poll_author_id" not in response.json()
    assert pushes == [(AUTHOR_ID, "poll_comment", title, "오늘 고백했어요", {"route": "poll", "poll_id": ITEM_ID})]
