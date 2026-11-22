"""관리자 문의 목록 `GET /admin/inquiries` · 처리 `PATCH /admin/inquiries/{id}`. 관문은 신고 검수와 같다."""
import json

import pytest

from inquiry_world import ADMIN, NOW, STRANGER, admin_auth, row

A = "00000000-0000-0000-0000-00000000000a"
B = "00000000-0000-0000-0000-00000000000b"
C = "00000000-0000-0000-0000-00000000000c"
ADMIN_AUTH = admin_auth()


@pytest.fixture(autouse=True)
def signed_in_as_admin(world):
    world.caller = ADMIN


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize("method,path", [("GET", "/admin/inquiries"), ("PATCH", f"/admin/inquiries/{A}")])
def test_both_routes_are_behind_the_admin_gate(client, world, method, path):
    world.inquiries = [row(A)]

    assert client.request(method, path, json={"status": "answered"}).status_code == 401
    world.caller = STRANGER
    assert client.request(method, path, json={"status": "answered"}, headers=admin_auth()).status_code == 403
    world.caller = ADMIN
    no_second_factor = client.request(method, path, json={"status": "answered"}, headers=admin_auth(aal="aal1"))
    assert (no_second_factor.status_code, no_second_factor.json()["detail"]) == (403, "mfa_required")
    assert world.inquiries[0]["status"] == "new"


# 목록 ---------------------------------------------------------------------------

def test_the_list_is_newest_first_with_every_column_and_the_writer(client, world):
    world.inquiries = [
        row(A, created_at="2026-11-10T01:00:00+00:00"),
        row(B, created_at="2026-11-10T03:00:00+00:00", profile_id=None, admin_memo="전화 예정"),
    ]

    response = client.get("/admin/inquiries", headers=ADMIN_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert [i["id"] for i in body["items"]] == [B, A]
    assert (body["total"], body["page"], body["size"]) == (2, 1, 20)
    assert body["items"][1] == {
        "id": A, "reason": "bug", "body": "앱이 멈춰요", "reply_email": "me@example.com", "status": "new",
        "admin_memo": None, "created_at": "2026-11-10T01:00:00+00:00", "updated_at": "2026-11-10T01:00:00+00:00",
        "answered_at": None,
        "profile": {"id": "11111111-1111-1111-1111-111111111111", "nickname": "하늘", "university": "테스트대학교"},
    }
    assert body["items"][0]["profile"] is None      # 탈퇴한 사람의 문의는 남는다


def test_pages_reach_every_inquiry_with_the_total(client, world):
    world.inquiries = [row(f"00000000-0000-0000-0000-{i:012d}", created_at=f"2026-11-10T{i % 24:02d}:00:00+00:00")
                       for i in range(1, 24)]

    first = client.get("/admin/inquiries", headers=ADMIN_AUTH).json()
    second = client.get("/admin/inquiries?page=2", headers=ADMIN_AUTH).json()
    past = client.get("/admin/inquiries?page=3", headers=ADMIN_AUTH).json()

    assert (len(first["items"]), len(second["items"]), first["total"], second["total"]) == (20, 3, 23, 23)
    assert len({i["id"] for i in first["items"] + second["items"]}) == 23
    assert (past["items"], past["total"]) == ([], 23)
    sent = world.calls("GET", "/rest/v1/inquiries")[1]
    assert (sent.url.params["offset"], sent.url.params["limit"], sent.headers["prefer"]) == ("20", "20", "count=exact")


def test_rows_sharing_a_timestamp_split_across_pages_without_skipping(client, world):
    same = "2026-11-10T01:00:00+00:00"
    world.inquiries = [row(A, created_at=same), row(B, created_at=same), row(C, created_at=same)]

    first = client.get("/admin/inquiries?size=2", headers=ADMIN_AUTH).json()
    second = client.get("/admin/inquiries?size=2&page=2", headers=ADMIN_AUTH).json()

    assert [i["id"] for i in first["items"]] == [C, B] and [i["id"] for i in second["items"]] == [A]
    assert world.calls("GET", "/rest/v1/inquiries")[-1].url.params["order"] == "created_at.desc,id.desc"


def test_the_status_filter_is_an_exact_postgrest_filter(client, world):
    world.inquiries = [row(A, status="new"), row(B, status="answered", answered_at="2026-11-10T02:00:00+00:00")]

    items = client.get("/admin/inquiries?status=answered", headers=ADMIN_AUTH).json()["items"]

    assert [i["id"] for i in items] == [B]
    assert world.calls("GET", "/rest/v1/inquiries")[-1].url.params["status"] == "eq.answered"
    assert client.get("/admin/inquiries?status=answered", headers=ADMIN_AUTH).json()["total"] == 1


@pytest.mark.parametrize("query", [
    "status=bogus", "page=0", "size=0", "size=101", "page=x",
])
def test_bad_query_is_422_without_touching_the_database(client, world, query):
    assert client.get(f"/admin/inquiries?{query}", headers=ADMIN_AUTH).status_code == 422
    assert world.calls("GET", "/rest/v1/inquiries") == []


def test_listing_writes_nothing(client, world):
    world.inquiries = [row(A)]

    client.get("/admin/inquiries", headers=ADMIN_AUTH)

    assert [r.method for r in world.requests if r.url.path.startswith("/rest/v1/inquiries")] == ["GET"]
    assert world.actions == []


# 처리 ---------------------------------------------------------------------------

def _patch(client, inquiry_id=A, **body):
    return client.patch(f"/admin/inquiries/{inquiry_id}", json=body, headers=ADMIN_AUTH)


def test_answering_records_answered_at_and_the_action(client, world):
    world.inquiries = [row(A)]

    response = _patch(client, status="answered")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == A and body["status"] == "answered"
    assert body["answered_at"] == NOW.isoformat() and body["updated_at"] == NOW.isoformat()
    assert body["profile"]["nickname"] == "하늘"
    assert world.inquiries[0]["answered_at"] == NOW.isoformat()
    (action,) = world.actions
    assert (action["action"], action["target_type"], action["target_id"]) == ("inquiry_update", "inquiry", A)
    assert action["admin_user_id"] == ADMIN
    assert action["before"] == {"status": "new"} and action["after"] == {"status": "answered", "memo_changed": False}


def test_the_action_log_never_carries_the_memo_text(client, world):
    world.inquiries = [row(A)]

    _patch(client, admin_memo="비밀 메모 내용")

    assert "비밀 메모 내용" not in json.dumps(world.actions, ensure_ascii=False)
    assert world.actions[0]["after"]["memo_changed"] is True


def test_the_memo_alone_changes_nothing_else(client, world):
    world.inquiries = [row(A, status="in_progress")]

    body = _patch(client, admin_memo="  전화 드림  ").json()

    assert body["admin_memo"] == "전화 드림" and body["status"] == "in_progress" and body["answered_at"] is None
    sent = json.loads(world.calls("PATCH", "/rest/v1/inquiries")[0].content)
    assert set(sent) == {"admin_memo", "updated_at"}


def test_an_empty_memo_clears_it(client, world):
    world.inquiries = [row(A, admin_memo="예전 메모")]

    assert _patch(client, admin_memo="   ").json()["admin_memo"] is None
    world.inquiries[0]["admin_memo"] = "또 메모"
    assert _patch(client, admin_memo=None).json()["admin_memo"] is None


def test_answering_again_keeps_the_first_answered_time(client, world):
    first = "2026-11-01T00:00:00+00:00"
    world.inquiries = [row(A, status="answered", answered_at=first)]

    body = _patch(client, status="answered", admin_memo="추가 메모").json()

    assert body["answered_at"] == first


def test_leaving_answered_clears_answered_at(client, world):
    """DB 가 (status = 'answered') = (answered_at 있음) 을 지킨다 — 1년 보관의 기준 시각이 남아 있으면 안 된다."""
    world.inquiries = [row(A, status="answered", answered_at="2026-11-01T00:00:00+00:00")]

    body = _patch(client, status="in_progress").json()

    assert body["status"] == "in_progress" and body["answered_at"] is None
    assert json.loads(world.calls("PATCH", "/rest/v1/inquiries")[0].content)["answered_at"] is None


@pytest.mark.parametrize("body", [
    {}, {"status": "bogus"}, {"admin_memo": "가" * 1001}, {"status": None},
])
def test_bad_patch_is_422_and_nothing_changes(client, world, body):
    world.inquiries = [row(A)]

    assert client.patch(f"/admin/inquiries/{A}", json=body, headers=ADMIN_AUTH).status_code == 422
    assert world.calls("PATCH", "/rest/v1/inquiries") == [] and world.actions == []


def test_a_1000_character_memo_is_accepted(client, world):
    world.inquiries = [row(A)]

    assert _patch(client, admin_memo="가" * 1000).status_code == 200


def test_an_unknown_inquiry_is_404_not_found(client, world):
    response = _patch(client, B, status="answered")

    assert (response.status_code, response.json()["detail"]) == (404, "not_found")
    assert world.actions == []


def test_a_failed_action_log_stops_the_change(client, world):
    """기록 없는 조치를 남기지 않는다 — 기록이 실패하면 문의도 바뀌지 않는다."""
    world.inquiries = [row(A)]
    world.action_insert_status = 500

    assert _patch(client, status="answered").status_code == 500
    assert world.inquiries[0]["status"] == "new"
