"""관리자 인증샷 검수 API(설계 10-18 §8-1, 계획서 2026-10-18-admin-heart-task-review Task 2)."""
import asyncio
import json
import logging
import time
from datetime import datetime

import httpx
import pytest
from starlette.requests import Request

from admin_world import ADMIN, SIGN_PREFIX, STRANGER, bearer, submission
from app.admin import heart_task_notice
from app.admin.request_ip import request_ip
from app.cards.push import FcmSender
from app.cards.router import get_sender
from app.core.time import SEOUL
from app.main import app

S1 = "11111111-0000-0000-0000-000000000001"
S2 = "11111111-0000-0000-0000-000000000002"
OTHER = "11111111-0000-0000-0000-0000000000ff"
PROFILE = "cccccccc-0000-0000-0000-00000000000a"
STORAGE = "https://x.supabase.co/storage/v1"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
# photo_url 은 옛 칸(= photo_urls 의 첫 장) — 관리자 웹이 서버보다 먼저 · 늦게 나가도 읽히게 둘 다 싣는다.
ITEM_KEYS = {"id", "task", "status", "reject_reason", "reward_hearts", "created_at", "reviewed_at",
             "profile", "photo_url", "photo_urls", "previous"}
# 목록 줄은 사진 · 지난 제출이 없는 요약이다(pen A3 목록 줄). 한 건 · 승인 · 반려만 ITEM_KEYS 다.
SUMMARY_KEYS = ITEM_KEYS - {"photo_url", "photo_urls", "previous"}
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
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00",
         "storage_paths": [f"{PROFILE}/old-1.jpg", f"{PROFILE}/old-2.jpg"]},
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
    assert item["photo_url"] == _signed(f"{PROFILE}/{S1}-1.jpg")
    assert item["photo_urls"] == [_signed(f"{PROFILE}/{S1}-1.jpg")]
    (sign,) = world.calls("POST", f"{SIGN_PREFIX}{PROFILE}/{S1}-1.jpg")
    assert json.loads(sign.content) == {"expiresIn": 300}
    assert "storage_path" not in response.text


def test_three_photos_come_back_in_order_with_the_first_as_the_legacy_photo_url(client, world):
    paths = [f"{PROFILE}/{S1}-{n}.jpg" for n in (1, 2, 3)]
    world.submissions[S1] = submission(S1, paths=paths)

    item = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS).json()

    assert item["photo_urls"] == [_signed(p) for p in paths]
    assert item["photo_url"] == item["photo_urls"][0]
    assert len([r for r in world.requests if r.url.path.startswith(SIGN_PREFIX)]) == 3  # 장마다 서명한다


def test_one_unsignable_photo_among_three_is_null_and_the_rest_stay(client, world):
    paths = [f"{PROFILE}/{S1}-{n}.jpg" for n in (1, 2, 3)]
    world.submissions[S1] = submission(S1, paths=paths)
    world.unsignable.add(paths[1])

    response = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json()["photo_urls"] == [_signed(paths[0]), None, _signed(paths[2])]


def test_missing_or_unsignable_photo_is_null(client, world):
    # 60일 정리로 경로가 빈 건, 경로는 있는데 Storage 가 서명을 거절한 건 — 500 이 아니라 "사진 없음".
    world.submissions[S1] = submission(S1, paths=[])
    world.submissions[S2] = submission(S2)
    world.unsignable.add(f"{PROFILE}/{S2}-1.jpg")

    pathless = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)
    unsignable = client.get(f"/admin/heart-tasks/{S2}", headers=ADMIN_HEADERS)

    assert (pathless.status_code, pathless.json()["photo_url"], pathless.json()["photo_urls"]) == (200, None, [])
    assert (unsignable.status_code, unsignable.json()["photo_url"], unsignable.json()["photo_urls"]) == (200, None, [None])
    # 경로가 없는 건은 Storage 에 묻지도 않는다.
    assert [r.url.path for r in world.requests if r.url.path.startswith(SIGN_PREFIX)] == [f"{SIGN_PREFIX}{PROFILE}/{S2}-1.jpg"]


@pytest.mark.parametrize("reply", [httpx.Response(200, json={}), httpx.Response(200, text="not json")],
                         ids=["no signedURL", "not json"])
def test_a_sign_answer_without_a_url_is_a_missing_photo_not_a_500(client, world, reply):
    world.submissions[S1] = submission(S1)
    world.sign_replies[f"{PROFILE}/{S1}-1.jpg"] = reply

    response = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS)

    assert (response.status_code, response.json()["photo_url"]) == (200, None)


def test_previous_submissions_are_the_same_persons_same_task_with_photos_latest_five(client, world):
    world.submissions[S1] = submission(S1)
    world.previous[PROFILE] = [
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00",
         "storage_paths": [f"{PROFILE}/old-1.jpg", f"{PROFILE}/old-2.jpg"]},
    ]

    item = client.get(f"/admin/heart-tasks/{S1}", headers=ADMIN_HEADERS).json()

    assert item["previous"] == [
        {"id": OTHER, "status": "approved", "created_at": "2026-09-01T00:00:00+00:00",
         "photo_url": _signed(f"{PROFILE}/old-1.jpg"),
         "photo_urls": [_signed(f"{PROFILE}/old-1.jpg"), _signed(f"{PROFILE}/old-2.jpg")]},
    ]
    (query,) = [r for r in world.calls("GET", "/rest/v1/heart_task_submissions") if "profile_id" in r.url.params]
    params = query.url.params
    assert params["profile_id"] == f"eq.{PROFILE}"
    assert params["task"] == "eq.everytime_post"
    assert params["id"] == f"neq.{S1}"  # 자기 자신은 빼고
    assert params["select"] == "id,status,created_at,storage_paths"
    assert params["storage_paths"] == "not.eq.{}"  # 사진이 남은 것만
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


# 결과 알림(10-18 사용자 결정 "가") -----------------------------------------------------

REASON_TEXT = {"date_missing": "날짜가 안 보여요", "not_verified": "게시글·공유가 확인되지 않아요", "reused": "이미 쓴 캡처예요"}
NIGHT = datetime(2026, 10, 18, 23, 0, tzinfo=SEOUL)


class _Hanging(FcmSender):
    """FCM 이 안 끝나는 상황 — 보내기가 영원히 걸린다."""

    async def send(self, *args, **kwargs):
        await asyncio.sleep(30)


def test_approve_records_the_inbox_line_and_pushes_with_the_rpc_reward(client, world):
    world.submissions[S1] = submission(S1)

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    data = {"route": "heart_tasks", "task": "everytime_post"}
    assert world.notifications == [{
        "profile_id": PROFILE, "kind": "heart_task_approved", "title": "에브리타임 홍보 인증이 승인됐어요",
        "body": "하트 40개를 받았어요", "data": data}]
    (push,) = world.pushes
    assert push["notification"] == {"title": "에브리타임 홍보 인증이 승인됐어요", "body": "하트 40개를 받았어요"}
    assert push["data"] == data and push["token"] == "tok-1"


def test_the_hearts_in_the_notice_come_from_the_review_result(client, world):
    world.submissions[S1] = submission(S1, task="kakao_share")
    world.submissions[S1]["reward_hearts"] = 25

    client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert world.notifications[0]["title"] == "단톡방 공유 인증이 승인됐어요"
    assert world.notifications[0]["body"] == "하트 25개를 받았어요"


@pytest.mark.parametrize("reason", REASON_TEXT)
def test_reject_pushes_the_chosen_reason_and_the_retry_route(client, world, reason):
    world.submissions[S1] = submission(S1, task="kakao_share")

    response = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json={"reason": reason})

    assert response.status_code == 200
    (line,) = world.notifications
    assert (line["kind"], line["title"], line["body"]) == (
        "heart_task_rejected", "단톡방 공유 인증이 반려됐어요", f"{REASON_TEXT[reason]} · 다시 제출해 주세요")
    assert line["data"] == {"route": "heart_task_retry", "task": "kakao_share", "reason": reason}
    assert world.pushes[0]["data"] == line["data"]


def test_the_notice_never_carries_photo_admin_ip_or_nickname(client, world):
    world.submissions[S1] = submission(S1)

    client.post(f"/admin/heart-tasks/{S1}/reject", headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"},
                json={"reason": "reused"})

    sent = json.dumps([world.notifications, world.pushes], ensure_ascii=False)
    assert world.notifications and world.pushes
    for secret in (f"{PROFILE}/{S1}-1.jpg", ADMIN, "203.0.113.7", "하늘", "테스트대학교", "storage_path"):
        assert secret not in sent


@pytest.mark.parametrize("failure", [
    {"fcm_status": 500},
    {"fcm_raises": httpx.ConnectError("down")},
    {"notifications_status": 500},
    {"profile_status_http": 500},
])
def test_a_notice_failure_never_flips_the_review(client, world, failure):
    world.submissions[S1] = submission(S1)
    for name, value in failure.items():
        setattr(world, name, value)

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert (response.json()["status"], world.submissions[S1]["status"]) == ("approved", "approved")


def test_an_inbox_write_failure_still_lets_the_push_go(client, world):
    world.submissions[S1] = submission(S1)
    world.notifications_status = 500

    client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert world.notifications == [] and len(world.pushes) == 1


def test_a_slow_push_is_cut_off_and_the_review_still_answers_200(client, world, monkeypatch):
    monkeypatch.setattr(heart_task_notice, "NOTICE_TIMEOUT_SECONDS", 0.05)
    app.dependency_overrides[get_sender] = lambda: _Hanging("campus-mate-test", None)
    world.submissions[S1] = submission(S1)

    started = time.monotonic()
    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["status"] == "approved"
    assert time.monotonic() - started < 5


def test_a_timeout_logs_the_profile_and_kind_but_never_the_words(client, world, monkeypatch, caplog):
    monkeypatch.setattr(heart_task_notice, "NOTICE_TIMEOUT_SECONDS", 0.05)
    app.dependency_overrides[get_sender] = lambda: _Hanging("campus-mate-test", None)
    world.submissions[S1] = submission(S1)

    with caplog.at_level(logging.WARNING):
        client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert PROFILE in caplog.text and "heart_task_approved" in caplog.text
    assert "승인됐어요" not in caplog.text and "하트 40개" not in caplog.text


@pytest.mark.parametrize("first", ["approve", "reject"])
def test_a_second_review_sends_nothing_more(client, world, first):
    world.submissions[S1] = submission(S1)
    body = {"reason": "reused"} if first == "reject" else None
    assert client.post(f"/admin/heart-tasks/{S1}/{first}", headers=ADMIN_HEADERS, json=body).status_code == 200

    again = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)
    reject = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json={"reason": "reused"})

    assert (again.status_code, reject.status_code) == (409, 409)
    assert len(world.notifications) == 1 and len(world.pushes) == 1


def test_unknown_submission_and_invalid_reason_send_nothing(client, world):
    world.submissions[S1] = submission(S1)

    missing = client.post(f"/admin/heart-tasks/{OTHER}/approve", headers=ADMIN_HEADERS)
    invalid = client.post(f"/admin/heart-tasks/{S1}/reject", headers=ADMIN_HEADERS, json={"reason": "blurry"})
    world.review_error_code = "22023"
    refused = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert (missing.status_code, invalid.status_code, refused.status_code) == (404, 422, 422)
    assert world.notifications == [] and world.pushes == [] and world.pending == []


@pytest.mark.parametrize("status", ["suspended", "withdrawn"])
def test_a_suspended_or_withdrawn_person_gets_no_line_and_no_push_but_the_review_stands(client, world, status):
    world.submissions[S1] = submission(S1)
    world.profile_status = status

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["status"] == "approved"
    assert world.notifications == [] and world.pushes == [] and world.pending == []


def test_at_night_the_push_waits_in_pending_but_the_inbox_line_is_immediate(client, world):
    world.submissions[S1] = submission(S1)
    world.now = NIGHT

    client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert len(world.notifications) == 1 and world.pushes == []
    assert [p["kind"] for p in world.pending] == ["heart_task_approved"]


def test_the_notice_goes_out_right_after_the_db_function_even_if_the_follow_up_read_fails(client, world):
    world.submissions[S1] = submission(S1)
    world.fail_submission_reads_after = 1  # 첫 읽기(검수 전 줄)만 되고, 응답을 만드는 읽기는 500

    response = client.post(f"/admin/heart-tasks/{S1}/approve", headers=ADMIN_HEADERS)

    assert response.status_code == 500
    assert world.submissions[S1]["status"] == "approved"
    assert len(world.notifications) == 1 and len(world.pushes) == 1
