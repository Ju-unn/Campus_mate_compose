"""홈 종 알림함 API(설계 §7). 앱은 이 API 로만 읽는다 — 표는 RLS 정책이 없어 클라이언트가 직접 못 읽는다."""
import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings
from fake_inbox import ME, OTHER, FakeInbox, row

AUTH = {"Authorization": "Bearer valid-token"}


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


def _wire(inbox: FakeInbox) -> TestClient:
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": ME})
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if request.url.path.endswith("/notifications"):
            return inbox.handle(request)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {url}"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


# 3(안 읽음) 2 1(읽음) 은 내 것, 남의 것은 4 · 5.
def _inbox() -> FakeInbox:
    return FakeInbox([
        row(1, read_at="2026-10-02T00:00:00+00:00"), row(2), row(3),
        row(4, profile_id=OTHER), row(5, profile_id=OTHER),
    ])


def test_the_list_is_newest_first_with_the_app_shape():
    body = _wire(_inbox()).get("/notifications", headers=AUTH).json()

    assert [item["id"][-1] for item in body["items"]] == ["3", "2", "1"]
    assert body["items"][0] == {
        "id": row(3)["id"], "kind": "chat_request", "title": "제목3", "body": "본문3",
        "data": {"route": "acceptances"}, "created_at": "2026-10-03T12:00:00+00:00", "read": False,
    }
    assert body["items"][2]["read"] is True
    assert body["next_before"] is None


def test_the_unread_count_is_mine_only_and_whole_not_per_page():
    body = _wire(_inbox()).get("/notifications?limit=1", headers=AUTH).json()

    assert len(body["items"]) == 1
    assert body["unread_count"] == 2  # 내 안 읽음 2 · 3. 남의 안 읽음 4 · 5 와 읽은 1 은 빠진다.


def test_pages_chain_through_next_before_and_the_last_page_has_none():
    client = _wire(_inbox())

    first = client.get("/notifications?limit=2", headers=AUTH).json()
    assert [i["id"][-1] for i in first["items"]] == ["3", "2"]
    assert first["next_before"] == "2026-10-02T12:00:00+00:00"  # 이 쪽의 마지막 줄 시각

    second = client.get("/notifications", params={"limit": 2, "before": first["next_before"]}, headers=AUTH).json()
    assert [i["id"][-1] for i in second["items"]] == ["1"]
    assert second["next_before"] is None


def test_a_page_that_exactly_fits_has_no_next_page():
    body = _wire(_inbox()).get("/notifications?limit=3", headers=AUTH).json()

    assert len(body["items"]) == 3 and body["next_before"] is None


def test_a_before_whose_plus_was_decoded_to_a_space_still_works():
    """`+09:00` 을 인코딩 없이 붙이면 서버는 공백으로 받는다 — 앱 실수 한 번에 422 로 목록이 멈추면 안 된다."""
    response = _wire(_inbox()).get("/notifications?before=2026-10-03T12:00:00 00:00", headers=AUTH)

    assert response.status_code == 200
    assert [i["id"][-1] for i in response.json()["items"]] == ["2", "1"]


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "before=어제"])
def test_bad_paging_input_is_rejected(query):
    assert _wire(_inbox()).get(f"/notifications?{query}", headers=AUTH).status_code == 422


def test_unread_count_is_light_and_counts_only_mine():
    inbox = _inbox()
    response = _wire(inbox).get("/notifications/unread-count", headers=AUTH)

    assert response.json() == {"unread_count": 2}
    # 가볍다 = 행 내용을 내려받지 않는다.
    assert all(r.url.params["limit"] == "1" for r in inbox.requests if r.url.path.endswith("/notifications"))


def test_marking_one_read_stamps_it_and_leaves_the_rest():
    inbox = _inbox()
    response = _wire(inbox).post(f"/notifications/{row(3)['id']}/read", headers=AUTH)

    assert response.status_code == 200 and response.json() == {"read": True}
    assert inbox.by_id(3)["read_at"] is not None
    assert inbox.by_id(2)["read_at"] is None


def test_marking_someone_elses_notification_is_a_404_and_changes_nothing():
    inbox = _inbox()
    response = _wire(inbox).post(f"/notifications/{row(4)['id']}/read", headers=AUTH)

    assert response.status_code == 404
    assert inbox.by_id(4)["read_at"] is None


def test_marking_a_missing_notification_is_a_404():
    assert _wire(_inbox()).post(f"/notifications/{row(9)['id']}/read", headers=AUTH).status_code == 404


def test_marking_an_already_read_one_is_ok_and_keeps_the_first_read_time():
    inbox = _inbox()
    response = _wire(inbox).post(f"/notifications/{row(1)['id']}/read", headers=AUTH)

    assert response.status_code == 200 and response.json() == {"read": True}
    assert inbox.by_id(1)["read_at"] == "2026-10-02T00:00:00+00:00"


def test_read_all_marks_only_my_unread_ones():
    inbox = _inbox()
    response = _wire(inbox).post("/notifications/read-all", headers=AUTH)

    assert response.status_code == 200 and response.json() == {"unread_count": 0}
    assert inbox.by_id(2)["read_at"] is not None and inbox.by_id(3)["read_at"] is not None
    assert inbox.by_id(1)["read_at"] == "2026-10-02T00:00:00+00:00"  # 이미 읽은 것의 시각은 그대로
    assert inbox.by_id(4)["read_at"] is None and inbox.by_id(5)["read_at"] is None


def test_every_request_to_the_table_is_pinned_to_the_caller():
    """service_role 이라 RLS 가 없다 — 소유자 조건이 빠진 요청이 하나라도 있으면 남의 알림이 보인다."""
    inbox = _inbox()
    client = _wire(inbox)
    client.get("/notifications", headers=AUTH)
    client.get("/notifications/unread-count", headers=AUTH)
    client.post(f"/notifications/{row(2)['id']}/read", headers=AUTH)
    client.post("/notifications/read-all", headers=AUTH)

    sent = [r for r in inbox.requests if r.url.path.endswith("/notifications")]
    assert len(sent) >= 4
    assert all(r.url.params["profile_id"] == f"eq.{ME}" for r in sent)


@pytest.mark.parametrize("method, path", [
    ("get", "/notifications"), ("get", "/notifications/unread-count"),
    ("post", f"/notifications/{row(1)['id']}/read"), ("post", "/notifications/read-all"),
])
def test_every_endpoint_needs_a_login(method, path):
    assert getattr(_wire(_inbox()), method)(path).status_code == 401
