"""관리자 인증샷 검수 API(설계 10-18 §8-1, 계획서 2026-10-18-admin-heart-task-review Task 2)."""
import json

import httpx
import pytest
from starlette.requests import Request

from admin_world import ADMIN, SIGN_PREFIX, STRANGER, bearer, submission
from app.admin.request_ip import request_ip

S1 = "11111111-0000-0000-0000-000000000001"
S2 = "11111111-0000-0000-0000-000000000002"
OTHER = "11111111-0000-0000-0000-0000000000ff"
PROFILE = "cccccccc-0000-0000-0000-00000000000a"
STORAGE = "https://x.supabase.co/storage/v1"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
ITEM_KEYS = {"id", "task", "status", "reject_reason", "reward_hearts", "created_at", "reviewed_at",
             "profile", "photo_url", "previous"}
# 목록 줄은 사진 · 지난 제출이 없는 요약이다(pen A3 목록 줄). 한 건 · 승인 · 반려만 ITEM_KEYS 다.
SUMMARY_KEYS = ITEM_KEYS - {"photo_url", "previous"}
ROUTES = [
    ("GET", "/admin/heart-tasks", None),
    ("GET", f"/admin/heart-tasks/{S1}", None),
    ("POST", f"/admin/heart-tasks/{S1}/approve", None),
    ("POST", f"/admin/heart-tasks/{S1}/reject", {"reason": "reused"}),
]


def _signed(path: str) -> str:
    return f"{STORAGE}/object/sign/heart-task-proofs/{path}?token=t"


def _list_requests(world):
    return [r for r in world.calls("GET", "/rest/v1/heart_task_submissions") if "status" in r.url.params]


def _rpc_bodies(world) -> list[dict]:
    return [json.loads(r.content) for r in world.calls("POST", "/rest/v1/rpc/admin_review_heart_task")]


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("method", "url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_heart_task_route_is_behind_the_admin_gate(client, world, method, url, body, who, headers, status, detail):
    world.submissions[S1] = submission(S1)
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.request(method, url, headers=headers, json=body)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.calls("GET", "/rest/v1/heart_task_submissions") == []
    assert world.calls("POST", "/rest/v1/rpc/admin_review_heart_task") == []


# 목록 ---------------------------------------------------------------------------

def test_list_asks_for_waiting_submissions_oldest_first_with_nickname_and_school(client, world):
    world.submissions[S1] = submission(S1)

    response = client.get("/admin/heart-tasks", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    (query,) = _list_requests(world)
    params = query.url.params
    assert params["status"] == "eq.submitted"
    assert params["order"] == "created_at.asc"
    assert params["limit"] == "50"
    assert "task" not in params
    assert "profiles(id,nickname,universities(name))" in params["select"]


def test_list_filters_by_task_and_status_and_takes_a_limit(client, world):
    response = client.get("/admin/heart-tasks?task=kakao_share&status=rejected&limit=100", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"items": []}
    params = _list_requests(world)[0].url.params
    assert (params["task"], params["status"], params["limit"]) == ("eq.kakao_share", "eq.rejected", "100")


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "task=poll_vote", "status=pending"])
def test_list_rejects_out_of_range_query_before_reading(client, world, query):
    response = client.get(f"/admin/heart-tasks?{query}", headers=ADMIN_HEADERS)

    assert response.status_code == 422
    assert world.calls("GET", "/rest/v1/heart_task_submissions") == []


def test_list_is_one_read_with_a_summary_per_row_and_no_photos(client, world):
    # pen A3 목록 줄에는 사진이 없다(닉네임 · 항목 · 학교 · 시각 · 배지). 사진 · 지난 제출은 한 건을 고를 때 받는다.
    world.submissions[S1] = submission(S1)
    world.submissions[S2] = submission(S2)
    world.previous[PROFILE] = [
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00", "storage_path": f"{PROFILE}/old.jpg"},
    ]

    items = client.get("/admin/heart-tasks", headers=ADMIN_HEADERS).json()["items"]

    assert [set(i) for i in items] == [SUMMARY_KEYS, SUMMARY_KEYS]
    assert items[0]["profile"] == {"id": PROFILE, "nickname": "하늘", "university": "테스트대학교"}
    assert (items[0]["id"], items[0]["task"], items[0]["status"], items[0]["reward_hearts"]) == (
        S1, "everytime_post", "submitted", 40)
    # 관문(로그인 · 명단) 뒤로는 PostgREST 한 번뿐 — 서명 · 지난 제출 조회는 하나도 없다.
    data = [r for r in world.requests if r.url.path not in ("/auth/v1/user", "/rest/v1/admin_users")]
    assert [(r.method, r.url.path) for r in data] == [("GET", "/rest/v1/heart_task_submissions")]


# 한 건 --------------------------------------------------------------------------

def test_one_submission_has_a_five_minute_photo_url_and_no_raw_path(client, world):
    world.submissions[S1] = submission(S1)

    response = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    item = response.json()
    assert set(item) == ITEM_KEYS
    assert item["profile"] == {"id": PROFILE, "nickname": "하늘", "university": "테스트대학교"}
    assert item["photo_url"] == _signed(f"{PROFILE}/{S1}.jpg")
    (sign,) = world.calls("POST", f"{SIGN_PREFIX}{PROFILE}/{S1}.jpg")
    assert json.loads(sign.content) == {"expiresIn": 300}


def test_missing_or_unsignable_photo_is_null(client, world):
    # 60일 정리로 경로가 빈 건, 경로는 있는데 Storage 가 서명을 거절한 건 — 500 이 아니라 "사진 없음".
    world.submissions[S1] = submission(S1, path=None)
    world.submissions[S2] = submission(S2)
    world.unsignable.add(f"{PROFILE}/{S2}.jpg")

    pathless = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)
    unsignable = client.get(f"/admin/heart-tasks/{S2}", headers=ADMIN_HEADERS)

    assert (pathless.status_code, pathless.json()["photo_url"]) == (200, None)
    assert (unsignable.status_code, unsignable.json()["photo_url"]) == (200, None)
    # 경로가 없는 건은 Storage 에 묻지도 않는다.
    assert [r.url.path for r in world.requests if r.url.path.startswith(SIGN_PREFIX)] == [f"{SIGN_PREFIX}{PROFILE}/{S2}.jpg"]


@pytest.mark.parametrize("reply", [httpx.Response(200, json={}), httpx.Response(200, text="not json")],
                         ids=["no signedURL", "not json"])
def test_a_sign_answer_without_a_url_is_a_missing_photo_not_a_500(client, world, reply):
    world.submissions[S1] = submission(S1)
    world.sign_replies[f"{PROFILE}/{S1}.jpg"] = reply

    response = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)

    assert (response.status_code, response.json()["photo_url"]) == (200, None)


def test_previous_submissions_are_the_same_persons_same_task_with_photos_latest_five(client, world):
    world.submissions[S1] = submission(S1)
    world.previous[PROFILE] = [
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00", "storage_path": f"{PROFILE}/old.jpg"},
    ]

    item = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS).json()

    assert item["previous"] == [
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00", "photo_url": _signed(f"{PROFILE}/old.jpg")},
    ]
    (query,) = [r for r in world.calls("GET", "/rest/v1/heart_task_submissions") if "profile_id" in r.url.params]
    params = query.url.params
    assert params["profile_id"] == f"eq.{PROFILE}"
    assert params["task"] == "eq.everytime_post"
    assert params["id"] == f"neq.{S1}"  # 자기 자신은 빼고
    assert params["storage_path"] == "not.is.null"  # 사진이 남은 것만
    assert (params["order"], params["limit"]) == ("created_at.desc", "5")


@pytest.mark.parametrize(("method", "url", "body"), ROUTES[1:])
def test_unknown_submission_is_404(client, world, method, url, body):
    response = client.request(method, url, headers=ADMIN_HEADERS, json=body)

    assert response.status_code == 404
    assert response.json()["detail"] == "not_found"


def test_a_malformed_id_is_422_before_reading(client, world):
    response = client.get("/admin/heart-tasks/not-a-uuid", headers=ADMIN_HEADERS)

    assert response.status_code == 422
    assert world.calls("GET", "/rest/v1/heart_task_submissions") == []


# 승인 · 반려 ----------------------------------------------------------------------

def test_approve_sends_the_admin_and_ip_and_returns_the_reviewed_item(client, world):
    world.submissions[S1] = submission(S1)

    response = client.post(f"/admin/heart-tasks/{S1}/approve",
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7, 10.0.0.1"})

    assert response.status_code == 200
    assert _rpc_bodies(world) == [{"p_admin": ADMIN, "p_submission": S1, "p_status": "approved",
                                   "p_reject_reason": None, "p_ip": "203.0.113.7"}]
    item = response.json()
    assert (item["status"], item["reject_reason"], item["reviewed_at"]) == ("approved", None, "2026-10-18T02:00:00+00:00")
    assert set(item) == ITEM_KEYS


def test_approve_ignores_a_reason_in_the_body(client, world):
    world.submissions[S1] = submission(S1)

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS, json={"reason": "reused"})

    assert response.status_code == 200
    assert _rpc_bodies(world)[0]["p_reject_reason"] is None


def test_reject_sends_the_chosen_reason(client, world):
    world.submissions[S1] = submission(S1)

    response = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json={"reason": "date_missing"})

    assert response.status_code == 200
    body = _rpc_bodies(world)[0]
    assert (body["p_status"], body["p_reject_reason"], body["p_admin"]) == ("rejected", "date_missing", ADMIN)
    assert (response.json()["status"], response.json()["reject_reason"]) == ("rejected", "date_missing")
    assert set(response.json()) == ITEM_KEYS


@pytest.mark.parametrize("body", [None, {}, {"reason": "blurry"}, {"reason": None}])
def test_reject_without_one_of_the_three_reasons_is_422(client, world, body):
    world.submissions[S1] = submission(S1)

    response = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json=body)

    assert response.status_code == 422
    assert _rpc_bodies(world) == []


def test_second_review_is_409(client, world):
    # 두 탭에서 같은 건을 승인했다 — 두 번째는 DB 함수가 CM409 로 막는다(하트는 한 번만, pgTAP 이 본다).
    world.submissions[S1] = submission(S1)
    client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    again = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)
    reject = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json={"reason": "reused"})

    assert (again.status_code, again.json()) == (409, {"detail": "already_reviewed"})
    assert (reject.status_code, reject.json()) == (409, {"detail": "already_reviewed"})


def test_a_review_the_db_function_calls_invalid_is_422(client, world):
    world.submissions[S1] = submission(S1)
    world.review_error_code = "22023"

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 422


# 요청 IP --------------------------------------------------------------------------

def _request(forwarded: str | None = None, client_host: str | None = None) -> Request:
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded is not None else []
    scope = {"type": "http", "headers": headers}
    if client_host is not None:
        scope["client"] = (client_host, 5000)
    return Request(scope)


@pytest.mark.parametrize(("forwarded", "client_host", "expected"), [
    ("203.0.113.7, 10.0.0.1", "198.51.100.2", "203.0.113.7"),
    (" 2001:db8::1 ", None, "2001:db8::1"),
    ("unknown", "198.51.100.2", "198.51.100.2"),  # 첫 값이 IP 가 아니면 바로 앞 연결
    (None, "198.51.100.2", "198.51.100.2"),
    (None, "testclient", None),  # inet 칸에 못 들어가는 값은 싣지 않는다 — 넣으면 검수가 22P02 로 실패한다
    (None, None, None),
])
def test_request_ip(forwarded, client_host, expected):
    assert request_ip(_request(forwarded, client_host)) == expected
