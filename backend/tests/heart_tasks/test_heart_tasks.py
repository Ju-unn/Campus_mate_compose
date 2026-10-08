import json
import re
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
JPEG = b"\xff\xd8\xff" + b"0" * 64
TASK_KEYS = {"task", "reward_hearts", "state", "used", "limit", "reject_reason"}


def _status(**overrides: dict) -> list[dict]:
    rows = {
        "everytime_post": {"used": 0, "task_limit": 1, "reviewing": False, "last_status": None, "last_reject_reason": None},
        "kakao_share": {"used": 0, "task_limit": 3, "reviewing": False, "last_status": None, "last_reject_reason": None},
        "poll_vote": {"used": 0, "task_limit": 3, "reviewing": False, "last_status": None, "last_reject_reason": None},
    }
    for name, changed in overrides.items():
        rows[name] = {**rows[name], **changed}
    # DB 는 순서를 약속하지 않는다(union all) — 일부러 섞어서 준다.
    return [{"task": name, **rows[name]} for name in ("poll_vote", "kakao_share", "everytime_post")]


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


def _backend(statuses: list[list[dict]], submit: httpx.Response | None = None,
             discord: httpx.Response | None = None) -> Callable[[httpx.Request], httpx.Response]:
    """상태 RPC 는 부를 때마다 statuses 를 하나씩 꺼낸다(마지막 것은 계속). 나머지는 경로로 가른다."""
    calls = iter(statuses)
    last: list[list[dict]] = [statuses[-1]]

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/rpc/heart_task_status"):
            last[0] = next(calls, last[0])
            return httpx.Response(200, json=last[0])
        if path.endswith("/rpc/submit_heart_task"):
            return submit or httpx.Response(204)
        if "/storage/v1/object/heart-task-proofs" in path:
            return httpx.Response(200, json={})
        if request.url.host == "discord.com":
            return discord or httpx.Response(204)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


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


def _post(client: TestClient, task: str = "everytime_post", data: bytes = JPEG):
    return client.post(f"/heart-tasks/{task}/submissions", files={"photo": ("proof.jpg", data)},
                       headers=AUTH_HEADERS)


def _storage_calls(seen: list[httpx.Request]) -> list[httpx.Request]:
    return [r for r in seen if "/storage/v1/object/heart-task-proofs" in r.url.path]


def test_list_gives_three_rows_in_fixed_order_with_six_keys():
    rows = _status(everytime_post={"reviewing": True, "used": 1}, kakao_share={"used": 3}, poll_vote={"used": 1})
    response = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS)
    assert response.status_code == 200
    tasks = response.json()["tasks"]
    assert [t["task"] for t in tasks] == ["everytime_post", "kakao_share", "poll_vote"]
    assert all(set(t) == TASK_KEYS for t in tasks)
    assert [t["state"] for t in tasks] == ["reviewing", "done", "open"]
    assert [t["reward_hearts"] for t in tasks] == [50, 25, 10]
    assert [(t["used"], t["limit"]) for t in tasks] == [(1, 1), (3, 3), (1, 3)]


def test_reject_reason_only_on_rejected_row():
    rows = _status(everytime_post={"last_status": "rejected", "last_reject_reason": "date_missing"},
                   kakao_share={"used": 1, "last_status": "approved"})
    tasks = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"]
    assert (tasks[0]["state"], tasks[0]["reject_reason"]) == ("rejected", "date_missing")
    # 한 번 승인되고 한도가 남은 단톡방은 다시 "인증하기" 다.
    assert (tasks[1]["state"], tasks[1]["reject_reason"]) == ("open", None)


def test_resubmitted_after_reject_shows_reviewing_without_old_reason():
    rows = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted",
                                   "last_reject_reason": "date_missing"})
    task = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"][0]
    assert (task["state"], task["reject_reason"]) == ("reviewing", None)


def test_submit_rejects_non_image_before_touching_anything():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), data=b"GIF89a" + b"0" * 64)
    assert response.status_code == 400
    assert response.json()["detail"] == errors.PHOTO_UNREADABLE
    assert seen == []


def test_submit_while_reviewing_is_409_without_upload():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status(everytime_post={"reviewing": True, "used": 1})]), seen))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.HEART_TASK_IN_REVIEW
    assert _storage_calls(seen) == []


def test_submit_at_monthly_limit_is_429_without_upload():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status(kakao_share={"used": 3})]), seen), task="kakao_share")
    assert response.status_code == 429
    assert response.json()["detail"] == errors.HEART_TASK_MONTHLY_LIMIT
    assert _storage_calls(seen) == []


def test_submit_uploads_records_and_alerts_with_ids_only():
    seen: list[httpx.Request] = []
    after = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted"})
    response = _post(_wire(_backend([_status(), after]), seen))

    assert response.status_code == 201
    assert response.json()["task"]["state"] == "reviewing"

    upload = _storage_calls(seen)[0]
    path = upload.url.path.split("/object/heart-task-proofs/")[1]
    match = re.fullmatch(rf"{PROFILE_ID}/([0-9a-f-]{{36}})\.jpg", path)
    assert match, path
    assert upload.headers["Content-Type"] == "image/jpeg"

    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    body = json.loads(rpc.content)
    assert body == {"p_id": match.group(1), "p_profile": PROFILE_ID, "p_task": "everytime_post",
                    "p_path": path, "p_reward": 50}

    alert = json.loads(next(r for r in seen if r.url.host == "discord.com").content)["content"]
    assert match.group(1) in alert and PROFILE_ID in alert and "everytime_post" in alert
    # 경로 · 파일 이름은 싣지 않는다(Global Constraint 6).
    assert ".jpg" not in alert and "heart-task-proofs" not in alert


def test_kakao_promises_25():
    seen: list[httpx.Request] = []
    _post(_wire(_backend([_status()]), seen), task="kakao_share")
    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    assert json.loads(rpc.content)["p_reward"] == 25


@pytest.mark.parametrize(("code", "status", "detail"), [
    ("CM409", 409, errors.HEART_TASK_IN_REVIEW),
    ("23505", 409, errors.HEART_TASK_IN_REVIEW),
    ("CM429", 429, errors.HEART_TASK_MONTHLY_LIMIT),
])
def test_db_says_no_after_upload_then_file_is_removed(code, status, detail):
    # 먼저 본 상태는 "낼 수 있음" 인데 그사이 다른 기기가 냈다 — 올린 파일을 지워야 고아가 안 남는다.
    seen: list[httpx.Request] = []
    submit = httpx.Response(400 if code.startswith("CM") else 409, json={"code": code, "message": "x"})
    response = _post(_wire(_backend([_status()], submit=submit), seen))
    assert response.status_code == status
    assert response.json()["detail"] == detail

    upload, removal = _storage_calls(seen)
    uploaded = upload.url.path.split("/object/heart-task-proofs/")[1]
    assert removal.method == "DELETE"
    assert json.loads(removal.content) == {"prefixes": [uploaded]}


def test_discord_failure_still_201():
    after = _status(everytime_post={"reviewing": True, "used": 1})
    response = _post(_wire(_backend([_status(), after], discord=httpx.Response(500))))
    assert response.status_code == 201


def test_no_answer_from_db_keeps_the_file():
    # 답을 못 받았으면 줄이 이미 생겼을 수 있다 — 파일을 지우면 사진 없는 "검수 중" 줄에 사용자가 막힌다.
    seen: list[httpx.Request] = []
    backend = _backend([_status()])

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/rpc/submit_heart_task"):
            raise httpx.ReadTimeout("no answer", request=request)
        return backend(request)

    with pytest.raises(httpx.ReadTimeout):
        _post(_wire(handler, seen))
    assert [r.method for r in _storage_calls(seen)] == ["POST"]


def test_poll_vote_is_not_submittable():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), task="poll_vote")
    assert response.status_code == 422
    assert seen == []
