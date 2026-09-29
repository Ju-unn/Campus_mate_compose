"""지인 리뷰 API(20b · 20c · 14c 섹션 · 14d). 기대값: docs/superpowers/plans/2026-09-28-friend-review.md Task B1 · B2."""
import asyncio
import json
import logging
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.cards.push import FcmSender
from app.core import errors
from app.core.deps import get_client, get_settings
from app.friend_reviews import router as router_module
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
PARTNER = "22222222-2222-2222-2222-222222222222"
FRIEND = "33333333-3333-3333-3333-333333333333"
REVIEW_ID = "44444444-4444-4444-4444-444444444444"
MATCH_ID = "55555555-5555-5555-5555-555555555555"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
ITEM_KEYS = {"id", "reviewer", "tags", "comment", "created_at"}


def _review_row(**overrides) -> dict:
    row = {
        "id": REVIEW_ID, "reviewer_id": FRIEND, "tags": ["약속을 잘 지켜요"], "comment": "믿음직해요",
        "created_at": "2026-09-28T05:00:00+00:00",
        "reviewer": {"nickname": "달빛", "status": "active", "universities": {"name": "테스트대학교"},
                     "profile_avatars": [{"storage_path": "f/a.png", "status": "ready",
                                          "created_at": "2026-09-01T00:00:00+00:00"}]},
    }
    return {**row, **overrides}


class _FakeCredentials:
    token = "fake-access-token"
    valid = True

    def refresh(self, _request) -> None:
        pass


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


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": ME})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _table(request: httpx.Request) -> str:
    return request.url.path.rsplit("/", 1)[-1]


# 읽기(B1) -------------------------------------------------------------------

def _received_handler(rows: list[dict], blocked: list[dict] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "friend_reviews":
            return httpx.Response(200, json=rows)
        if _table(request) == "blocks":
            return httpx.Response(200, json=blocked or [])
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def test_received_gives_item_keys_and_never_reviewer_id():
    response = _wire(_received_handler([_review_row()])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.status_code == 200
    item = response.json()["reviews"][0]
    assert set(item) == ITEM_KEYS
    assert item["reviewer"] == {"nickname": "달빛", "university": "테스트대학교",
                                "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/f/a.png"}


def test_received_asks_only_visible_rows_about_me_by_active_reviewers():
    seen: list[httpx.Request] = []
    _wire(_received_handler([]), seen).get("/friend-reviews/received", headers=AUTH_HEADERS)
    query = next(r for r in seen if _table(r) == "friend_reviews").url.params
    assert query["reviewee_id"] == f"eq.{ME}"
    assert query["status"] == "eq.visible"
    assert query["reviewer.status"] == "eq.active"
    assert "!inner" in query["select"]
    assert query["order"] == "created_at.desc"


def test_hides_reviews_by_inactive_reviewer():
    # DB 가 embed 필터를 무시하고 돌려줘도(목 서버) 서버가 한 번 더 거른다 — Review Focus 1.
    gone = _review_row(reviewer={**_review_row()["reviewer"], "status": "withdrawn"})
    response = _wire(_received_handler([gone])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json() == {"reviews": []}


@pytest.mark.parametrize("blocked", [
    [{"blocker_id": FRIEND, "blocked_id": ME}],
    [{"blocker_id": ME, "blocked_id": FRIEND}],
], ids=["reviewer_blocked_me", "i_blocked_reviewer"])
def test_hides_reviews_by_blocked_reviewer(blocked):
    # Review Focus 2 — 어느 방향이든(내가 막았든 상대가 막았든).
    response = _wire(_received_handler([_review_row()], blocked)).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json() == {"reviews": []}


def test_empty_comment_stays_null():
    response = _wire(_received_handler([_review_row(comment=None)])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json()["reviews"][0]["comment"] is None


def _about_handler(*, match: list[dict], status: str = "active", rows: list[dict] | None = None,
                   blocked: list[dict] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        table = _table(request)
        if table == "matches":
            return httpx.Response(200, json=match)
        if table == "profiles":
            return httpx.Response(200, json=[{"status": status}])
        if table == "blocks":
            return httpx.Response(200, json=blocked or [])
        if table == "friend_reviews":
            return httpx.Response(200, json=rows or [])
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def _match(left_at: str | None = None) -> list[dict]:
    return [{"id": MATCH_ID, "chat_closed_at": None, "trust_passed_at": None, "match_participants": [
        {"profile_id": ME, "left_at": None}, {"profile_id": PARTNER, "left_at": left_at}]}]


def test_about_lists_partner_reviews():
    response = _wire(_about_handler(match=_match(), rows=[_review_row()])).get(
        f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert len(response.json()["reviews"]) == 1


def test_about_asks_blocks_once():
    # _visible 과 404 판정이 각자 fetch_block_partner_ids 를 불렀었다 — 요청마다 한 번만 읽는다.
    seen: list[httpx.Request] = []
    _wire(_about_handler(match=_match(), rows=[_review_row()]), seen).get(
        f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert sum(1 for r in seen if _table(r) == "blocks") == 1


def test_about_requires_match():
    # Review Focus 5 — 매칭 이력 없는 사람의 리뷰는 읽을 수 없다. 14c 와 같은 404.
    response = _wire(_about_handler(match=[])).get(f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


@pytest.mark.parametrize("kwargs", [
    {"match": _match("2026-09-28T00:00:00+00:00")},
    {"match": _match(), "status": "suspended"},
    {"match": _match(), "blocked": [{"blocker_id": PARTNER, "blocked_id": ME}]},
], ids=["left", "inactive", "blocked"])
def test_about_follows_14c_404_rules(kwargs):
    response = _wire(_about_handler(**kwargs)).get(f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


# 쓰기(B2) -------------------------------------------------------------------

def _write_handler(*, linked=True, status="active", written=False, blocked=None, insert: httpx.Response | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        table = _table(request)
        if table == "referrals":
            return httpx.Response(200, json=[{"referee_id": ME}] if linked else [])
        if table == "profiles":
            return httpx.Response(200, json=[{"id": FRIEND, "nickname": "달빛", "status": status,
                                              "profile_avatars": []}])
        if table == "blocks":
            return httpx.Response(200, json=blocked or [])
        if table == "friend_reviews" and request.method == "GET":
            return httpx.Response(200, json=[{"id": REVIEW_ID}] if written else [])
        if table == "friend_reviews" and request.method == "POST":
            return insert or httpx.Response(201, json=[{"id": REVIEW_ID}])
        # 푸시 쪽(알림 설정 · 토큰 · FCM)은 빈 값으로 흘려보낸다.
        return httpx.Response(200, json=[])
    return handler


def test_target_gives_header_fields():
    response = _wire(_write_handler()).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json() == {"profile_id": FRIEND, "nickname": "달빛", "avatar_url": None}


def test_target_asks_referrals_both_ways():
    # 추천은 어느 방향이든 자격이다(결정 1) — 내가 추천했든 추천받았든.
    seen: list[httpx.Request] = []
    _wire(_write_handler(), seen).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    query = next(r for r in seen if _table(r) == "referrals").url.params
    assert query["or"] == (f"(and(referee_id.eq.{ME},referrer_id.eq.{FRIEND}),"
                           f"and(referee_id.eq.{FRIEND},referrer_id.eq.{ME}))")


def test_unlinked_target_is_404():
    # Review Focus 5
    response = _wire(_write_handler(linked=False)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


@pytest.mark.parametrize("kwargs", [{"status": "suspended"}, {"status": "withdrawn"},
                                    {"blocked": [{"blocker_id": ME, "blocked_id": FRIEND}]}])
def test_target_inactive_or_blocked_is_404(kwargs):
    response = _wire(_write_handler(**kwargs)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


def test_target_self_is_404():
    response = _wire(_write_handler()).get(f"/friend-reviews/targets/{ME}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


def test_target_already_written_is_409():
    response = _wire(_write_handler(written=True)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN


def _post(client: TestClient, **body):
    payload = {"reviewee_id": FRIEND, "tags": ["약속을 잘 지켜요"], "comment": None, **body}
    return client.post("/friend-reviews", json=payload, headers=AUTH_HEADERS)


def _inserted(seen: list[httpx.Request]) -> dict:
    return json.loads(next(r for r in seen if _table(r) == "friend_reviews" and r.method == "POST").content)


def test_create_inserts_trimmed_row():
    seen: list[httpx.Request] = []
    response = _post(_wire(_write_handler(), seen), tags=["성실해요", "다정해요"], comment="  믿음직해요 ")
    assert response.status_code == 201
    assert response.json() == {"id": REVIEW_ID}
    assert _inserted(seen) == {"reviewer_id": ME, "reviewee_id": FRIEND,
                               "tags": ["성실해요", "다정해요"], "comment": "믿음직해요"}


def test_blank_comment_becomes_null():
    seen: list[httpx.Request] = []
    _post(_wire(_write_handler(), seen), comment="   ")
    assert _inserted(seen)["comment"] is None


def test_comment_length_counts_after_trim():
    # 100자 뒤에 공백이 붙어 와도 깎은 뒤 100자라 받는다(Global Constraints "앞뒤 공백을 깎아 1~100자").
    seen: list[httpx.Request] = []
    assert _post(_wire(_write_handler(), seen), comment=" " + "가" * 100 + " ").status_code == 201
    assert _inserted(seen)["comment"] == "가" * 100


@pytest.mark.parametrize("tags", [[], ["성실해요", "솔직해요", "다정해요", "차분해요"], ["잘생겼어요"], ["성실해요", "성실해요"]])
def test_bad_tags_are_422(tags):
    assert _post(_wire(_write_handler()), tags=tags).status_code == 422


def test_comment_over_100_is_422():
    assert _post(_wire(_write_handler()), comment="가" * 101).status_code == 422


def test_second_review_is_409():
    # 확인과 insert 사이에 다른 요청이 먼저 넣었다 — unique 가 막는다(Review Focus 3).
    conflict = httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
    response = _post(_wire(_write_handler(insert=conflict)))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN


def test_create_already_written_is_409_and_inserts_nothing():
    seen: list[httpx.Request] = []
    assert _post(_wire(_write_handler(written=True), seen)).status_code == 409
    assert not any(_table(r) == "friend_reviews" and r.method == "POST" for r in seen)


def test_create_unlinked_is_404_and_inserts_nothing():
    seen: list[httpx.Request] = []
    response = _post(_wire(_write_handler(linked=False), seen))
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND
    assert not any(_table(r) == "friend_reviews" and r.method == "POST" for r in seen)


def test_create_pushes_reviewee_with_new_friend_review(monkeypatch):
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, data))
        return 1

    monkeypatch.setattr(router_module, "notify", fake_notify)
    _post(_wire(_write_handler()))
    assert calls == [(FRIEND, "new_friend_review", {"route": "friend_reviews"})]


def test_review_request_push_goes_to_referrer_with_write_route(monkeypatch):
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, data))
        return 1

    class _Cards:
        async def fetch_card_profile(self, profile_id):
            return {"nickname": "새싹"}

    monkeypatch.setattr(router_module, "notify", fake_notify)
    asyncio.run(router_module.notify_review_request(_Cards(), None, FRIEND, ME, None))
    assert calls == [(FRIEND, "new_friend_review", {"route": "friend_review_write", "profile_id": ME})]


def test_create_returns_201_even_if_push_fails(monkeypatch, caplog):
    # 리뷰는 이미 저장됐다 — 닉네임 조회나 푸시가 죽어도 201 을 놓치면 안 된다(cards/issuing.py 와 같은 자리).
    async def failing_notify(*args, **kwargs):
        raise RuntimeError("fcm down")

    monkeypatch.setattr(router_module, "notify", failing_notify)
    with caplog.at_level(logging.ERROR):
        response = _post(_wire(_write_handler()), comment="진짜 든든해요")
    assert response.status_code == 201
    assert response.json() == {"id": REVIEW_ID}
    # 로그에는 id 만 남는다 — 닉네임 · 한마디는 남지 않는다.
    log_text = " ".join(record.getMessage() for record in caplog.records)
    assert "달빛" not in log_text
    assert "진짜 든든해요" not in log_text
    assert REVIEW_ID in log_text


def test_review_request_push_failure_does_not_raise(caplog, monkeypatch):
    # redeem 경로가 이 함수를 부른다 — 푸시 한 건 때문에 추천 보상 지급이 실패하면 안 된다.
    async def failing_notify(*args, **kwargs):
        raise RuntimeError("fcm down")

    class _Cards:
        async def fetch_card_profile(self, profile_id):
            return {"nickname": "새싹"}

    monkeypatch.setattr(router_module, "notify", failing_notify)
    with caplog.at_level(logging.ERROR):
        asyncio.run(router_module.notify_review_request(_Cards(), None, FRIEND, ME, None))
    log_text = " ".join(record.getMessage() for record in caplog.records)
    assert "새싹" not in log_text
    assert ME in log_text


# 내가 쓴 리뷰 읽기 · 지우기(B5). 기대값: docs/superpowers/plans/2026-09-29-friend-review-delete.md Task B5 ---

WRITTEN_KEYS = {"id", "reviewee", "tags", "comment", "created_at"}


def _written_row(**overrides) -> dict:
    row = {
        "id": REVIEW_ID, "reviewer_id": ME, "reviewee_id": FRIEND, "tags": ["약속을 잘 지켜요"],
        "comment": "믿음직해요", "created_at": "2026-09-28T05:00:00+00:00",
        "reviewee": {"nickname": "새싹", "status": "active", "universities": {"name": "테스트대학교"},
                     "profile_avatars": [{"storage_path": "n/a.png", "status": "ready",
                                          "created_at": "2026-09-01T00:00:00+00:00"}]},
    }
    return {**row, **overrides}


def _written_handler(rows: list[dict]):
    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "friend_reviews" and request.method == "GET":
            return httpx.Response(200, json=rows)
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def test_written_lists_my_visible_reviews_newest_first():
    seen: list[httpx.Request] = []
    response = _wire(_written_handler([_written_row()]), seen).get("/friend-reviews/written", headers=AUTH_HEADERS)
    assert response.status_code == 200
    item = response.json()["reviews"][0]
    assert set(item) == WRITTEN_KEYS
    assert item["reviewee"] == {"nickname": "새싹", "university": "테스트대학교",
                                "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/n/a.png"}
    query = next(r for r in seen if _table(r) == "friend_reviews").url.params
    assert query["reviewer_id"] == f"eq.{ME}"
    assert query["status"] == "eq.visible"
    assert query["order"] == "created_at.desc"
    assert "friend_reviews_reviewee_id_fkey!inner" in query["select"]
    assert query["reviewee.status"] == "neq.withdrawn"


def test_written_never_carries_ids_of_people():
    body = _wire(_written_handler([_written_row()])).get("/friend-reviews/written", headers=AUTH_HEADERS).text
    assert "reviewer_id" not in body
    assert "reviewee_id" not in body


def test_written_hides_withdrawn_reviewee_but_keeps_suspended():
    # 탈퇴 행은 30일 뒤에야 지워진다 — 그동안 embed 필터가 틀려도 새지 않게 라우터도 거른다. 정지는 내 글이라 남는다.
    rows = [_written_row(id="a", reviewee={**_written_row()["reviewee"], "status": "withdrawn"}),
            _written_row(id="b", reviewee={**_written_row()["reviewee"], "status": "suspended"})]
    response = _wire(_written_handler(rows)).get("/friend-reviews/written", headers=AUTH_HEADERS)
    assert [r["id"] for r in response.json()["reviews"]] == ["b"]
    assert "status" not in response.json()["reviews"][0]["reviewee"]


def test_written_empty_is_empty_list():
    response = _wire(_written_handler([])).get("/friend-reviews/written", headers=AUTH_HEADERS)
    assert response.json() == {"reviews": []}


def _delete_handler(deleted: list[dict]):
    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "friend_reviews" and request.method == "DELETE":
            return httpx.Response(200, json=deleted)
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def test_delete_own_review_is_204_and_scopes_to_me_and_visible():
    seen: list[httpx.Request] = []
    response = _wire(_delete_handler([{"id": REVIEW_ID}]), seen).delete(
        f"/friend-reviews/{REVIEW_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 204
    request = next(r for r in seen if r.method == "DELETE")
    assert _table(request) == "friend_reviews"
    assert request.url.params["id"] == f"eq.{REVIEW_ID}"
    assert request.url.params["reviewer_id"] == f"eq.{ME}"
    assert request.url.params["status"] == "eq.visible"
    assert request.url.params["select"] == "id"
    assert request.headers["Prefer"] == "return=representation"


def test_delete_when_no_row_is_deleted_is_404():
    # 지운 행이 없으면(남의 것 · 없음 · 가려짐 · 이미 지움) PostgREST 가 [] 를 돌려주고 전부 같은 404.
    response = _wire(_delete_handler([])).delete(f"/friend-reviews/{REVIEW_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.FRIEND_REVIEW_NOT_FOUND


def test_delete_postgrest_error_is_not_204():
    # raise_for_status 를 빼면 500 응답 본문(오류 JSON)이 "지운 행" 으로 읽혀 204 가 나간다.
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"message": "boom"})

    _wire(handler)
    response = TestClient(app, raise_server_exceptions=False).delete(
        f"/friend-reviews/{REVIEW_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 500


def test_delete_bad_uuid_is_422():
    assert _wire(_delete_handler([])).delete("/friend-reviews/not-a-uuid", headers=AUTH_HEADERS).status_code == 422


def test_delete_sends_no_push(monkeypatch):
    calls = []

    async def fake_notify(*args, **kwargs):
        calls.append(args)
        return 1

    monkeypatch.setattr(router_module, "notify", fake_notify)
    seen: list[httpx.Request] = []
    _wire(_delete_handler([{"id": REVIEW_ID}]), seen).delete(f"/friend-reviews/{REVIEW_ID}", headers=AUTH_HEADERS)
    assert calls == []
    assert {_table(r) for r in seen} == {"friend_reviews"}


def test_written_and_delete_need_verified_caller():
    client = _wire(_delete_handler([{"id": REVIEW_ID}]))
    assert client.get("/friend-reviews/written").status_code in (401, 403)
    assert client.delete(f"/friend-reviews/{REVIEW_ID}").status_code in (401, 403)
