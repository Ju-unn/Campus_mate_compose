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
from app.student_verification.image_validation import MAX_IMAGE_BYTES

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
JPEG = b"\xff\xd8\xff" + b"0" * 64
# 옛 앱이 읽는 여섯 칸 — 이름 · 뜻을 바꾸지 않는다(하위 호환). 그 위에 새 앱이 읽는 세 칸이 더해진다.
OLD_TASK_KEYS = {"task", "reward_hearts", "state", "used", "limit", "reject_reason"}
TASK_KEYS = OLD_TASK_KEYS | {"can_submit", "max_photos", "pending"}
CREATED_AT = "2026-10-19T01:00:00+00:00"
SIGN_PREFIX = "https://x.supabase.co/storage/v1/object/sign/heart-task-proofs/"


def _pending_row(sid: str, task: str = "kakao_share", photos: int = 3) -> dict:
    return {"id": sid, "task": task, "created_at": CREATED_AT,
            "storage_paths": [f"{PROFILE_ID}/{sid}-{n}.jpg" for n in range(1, photos + 1)]}


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


def _settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


@pytest.fixture(autouse=True)
def overrides():
    # 람다로 감싼다 — **kwargs 함수를 그대로 넣으면 FastAPI 가 쿼리 인자로 읽는다(reference_backend_test_mock_traps ②).
    app.dependency_overrides[get_settings] = lambda: _settings()
    yield
    app.dependency_overrides.clear()


def _backend(statuses: list[list[dict]], submit: httpx.Response | None = None,
             discord: httpx.Response | None = None, pending: list[dict] | None = None,
             sign_failures: tuple[str, ...] = (),
             upload: Callable[[httpx.Request], httpx.Response] | None = None,
             ) -> Callable[[httpx.Request], httpx.Response]:
    """상태 RPC 는 부를 때마다 statuses 를 하나씩 꺼낸다(마지막 것은 계속). 나머지는 경로로 가른다.
    pending 은 검수 중 줄 읽기(status=eq.submitted), sign_failures 는 서명이 500 인 경로 조각, upload 는 업로드 응답."""
    calls = iter(statuses)
    last: list[list[dict]] = [statuses[-1]]

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/rpc/heart_task_status"):
            last[0] = next(calls, last[0])
            return httpx.Response(200, json=last[0])
        if path.endswith("/rpc/submit_heart_task"):
            return submit or httpx.Response(204)
        if request.method == "GET" and path.endswith("/heart_task_submissions"):
            assert request.url.params.get("status") == "eq.submitted"
            return httpx.Response(200, json=pending or [])
        if "/storage/v1/object/sign/heart-task-proofs/" in path:
            object_path = path.split("/object/sign/heart-task-proofs/")[1]
            if any(part in object_path for part in sign_failures):
                return httpx.Response(500, json={"message": "sign failed"})
            return httpx.Response(200, json={"signedURL": f"/object/sign/heart-task-proofs/{object_path}?token=t"})
        if "/storage/v1/object/heart-task-proofs" in path:
            return (upload(request) if upload and request.method == "POST" else httpx.Response(200, json={}))
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


def _post(client: TestClient, task: str = "everytime_post", data: bytes = JPEG, files=None):
    """files 가 없으면 옛 앱처럼 `photo` 한 장. 새 앱은 `photos` 여러 파트를 보낸다(_photos)."""
    files = files if files is not None else {"photo": ("proof.jpg", data)}
    return client.post(f"/heart-tasks/{task}/submissions", files=files, headers=AUTH_HEADERS)


def _photos(*datas: bytes) -> list:
    return [("photos", (f"proof{i}.jpg", data)) for i, data in enumerate(datas)]


def _storage_calls(seen: list[httpx.Request]) -> list[httpx.Request]:
    return [r for r in seen if "/storage/v1/object/heart-task-proofs" in r.url.path]


def test_list_gives_three_rows_in_fixed_order_with_old_six_keys_plus_new_three():
    rows = _status(everytime_post={"reviewing": True, "used": 1}, kakao_share={"used": 3}, poll_vote={"used": 1})
    response = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS)
    assert response.status_code == 200
    tasks = response.json()["tasks"]
    assert [t["task"] for t in tasks] == ["everytime_post", "kakao_share", "poll_vote"]
    assert all(set(t) == TASK_KEYS for t in tasks)
    assert all(OLD_TASK_KEYS <= set(t) for t in tasks)  # 옛 앱이 읽는 여섯 칸은 그대로 있다
    assert [t["state"] for t in tasks] == ["reviewing", "done", "open"]
    assert [t["reward_hearts"] for t in tasks] == [40, 25, 5]
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


def test_submit_reads_at_most_one_byte_past_the_size_limit(upload_read_sizes):
    """10MB 를 넘는 인증샷을 끝까지 메모리로 읽지 않는다 — 한도 + 1 바이트만 읽어 넘었는지만 안다(10-18 보안 점검)."""
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), data=JPEG + b"0" * MAX_IMAGE_BYTES)

    assert response.status_code == 400
    assert upload_read_sizes == [MAX_IMAGE_BYTES + 1]
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
    match = re.fullmatch(rf"{PROFILE_ID}/([0-9a-f-]{{36}})-1\.jpg", path)
    assert match, path
    assert upload.headers["Content-Type"] == "image/jpeg"

    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    body = json.loads(rpc.content)
    assert body == {"p_id": match.group(1), "p_profile": PROFILE_ID, "p_task": "everytime_post",
                    "p_paths": [path], "p_reward": 40}

    alert = json.loads(next(r for r in seen if r.url.host == "discord.com").content)["content"]
    assert match.group(1) in alert and PROFILE_ID in alert and "everytime_post" in alert
    # 경로 · 파일 이름은 싣지 않는다(Global Constraint 6).
    assert ".jpg" not in alert and "heart-task-proofs" not in alert
    # ADMIN_BASE_URL 이 없으면 관리자 웹이 없는 배포다 — 지금처럼 Supabase 대시보드로 안내한다.
    assert alert.endswith("Supabase 대시보드 heart_task_submissions 에서 확인해 주세요.")


def test_alert_links_the_admin_dashboard_when_its_address_is_set():
    app.dependency_overrides[get_settings] = lambda: _settings(admin_base_url="https://admin.example.com/")
    seen: list[httpx.Request] = []
    after = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted"})
    _post(_wire(_backend([_status(), after]), seen))

    alert = json.loads(next(r for r in seen if r.url.host == "discord.com").content)["content"]
    submission_id = json.loads(next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task")).content)["p_id"]
    # 끝의 '/' 는 떼고 붙인다 — 관리자 웹 /heart-tasks/{id} 가 그 건을 연다.
    assert alert.endswith(f"대시보드: https://admin.example.com/heart-tasks/{submission_id}")
    assert "Supabase" not in alert
    assert PROFILE_ID in alert and "everytime_post" in alert
    assert ".jpg" not in alert and "heart-task-proofs" not in alert


def test_kakao_promises_25():
    seen: list[httpx.Request] = []
    _post(_wire(_backend([_status()]), seen), task="kakao_share")
    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    assert json.loads(rpc.content)["p_reward"] == 25


@pytest.mark.parametrize(("code", "status", "detail"), [
    ("CM409", 409, errors.HEART_TASK_IN_REVIEW),
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


def test_submit_three_photos_uploads_each_and_records_one_row():
    seen: list[httpx.Request] = []
    after = _status(kakao_share={"reviewing": True, "used": 1, "last_status": "submitted"})
    response = _post(_wire(_backend([_status(), after]), seen), task="kakao_share", files=_photos(JPEG, JPEG, JPEG))

    assert response.status_code == 201
    uploads = [r for r in _storage_calls(seen) if r.method == "POST"]
    paths = [r.url.path.split("/object/heart-task-proofs/")[1] for r in uploads]
    assert len(paths) == 3
    submission_id = paths[0].split("/")[1].rsplit("-", 1)[0]
    assert paths == [f"{PROFILE_ID}/{submission_id}-{n}.jpg" for n in (1, 2, 3)]

    rpcs = [r for r in seen if r.url.path.endswith("/rpc/submit_heart_task")]
    assert len(rpcs) == 1
    body = json.loads(rpcs[0].content)
    assert body["p_paths"] == paths and "p_path" not in body
    alerts = [r for r in seen if r.url.host == "discord.com"]
    assert len(alerts) == 1
    content = json.loads(alerts[0].content)["content"]
    assert ".jpg" not in content and "heart-task-proofs" not in content


def test_submit_keeps_the_order_of_the_photos():
    first, second = JPEG + b"1", b"\x89PNG\r\n\x1a\n" + b"2"
    seen: list[httpx.Request] = []
    _post(_wire(_backend([_status()]), seen), files=_photos(first, second))
    uploads = [r for r in _storage_calls(seen) if r.method == "POST"]
    assert [(r.headers["Content-Type"], r.content) for r in uploads] == [("image/jpeg", first), ("image/png", second)]
    assert [r.url.path.rsplit(".", 1)[1] for r in uploads] == ["jpg", "png"]


def test_legacy_photo_field_still_works_and_answers_with_the_old_six_keys():
    after = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted"})
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status(), after]), seen))  # 옛 앱: 파트 이름 photo 한 장
    assert response.status_code == 201
    assert OLD_TASK_KEYS <= set(response.json()["task"])
    body = json.loads(next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task")).content)
    assert len(body["p_paths"]) == 1


@pytest.mark.parametrize("files", [[], _photos(JPEG, JPEG, JPEG, JPEG)])
def test_zero_or_four_photos_is_422_and_touches_nothing(files):
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), task="kakao_share", files=files or {"unrelated": ("x", b"x")})
    assert response.status_code == 422
    assert seen == []


def test_one_bad_photo_among_three_is_400_and_uploads_nothing():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), task="kakao_share",
                     files=_photos(JPEG, b"GIF89a" + b"0" * 64, JPEG))
    assert response.status_code == 400
    assert response.json()["detail"] == errors.PHOTO_UNREADABLE
    assert seen == []


def test_each_photo_is_read_at_most_one_byte_past_the_size_limit(upload_read_sizes):
    """셋째 사진이 한도를 넘어도 끝까지 읽지 않는다 — 사진마다 한도 + 1 바이트만 읽는다(10-18 보안 점검)."""
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), task="kakao_share",
                     files=_photos(JPEG, JPEG, JPEG + b"0" * MAX_IMAGE_BYTES))
    assert response.status_code == 400
    assert upload_read_sizes == [MAX_IMAGE_BYTES + 1] * 3
    assert seen == []


def test_kakao_submit_is_allowed_while_one_is_reviewing():
    seen: list[httpx.Request] = []
    rows = _status(kakao_share={"reviewing": True, "used": 1})
    response = _post(_wire(_backend([rows]), seen), task="kakao_share")
    assert response.status_code == 201
    assert len(_storage_calls(seen)) == 1 and any(r.url.path.endswith("/rpc/submit_heart_task") for r in seen)


@pytest.mark.parametrize(("reviewing", "status", "detail"), [
    (True, 409, errors.HEART_TASK_IN_REVIEW),
    (False, 429, errors.HEART_TASK_MONTHLY_LIMIT),
])
def test_submit_at_the_limit_is_409_with_a_pending_and_429_without(reviewing, status, detail):
    seen: list[httpx.Request] = []
    rows = _status(kakao_share={"reviewing": reviewing, "used": 3})
    response = _post(_wire(_backend([rows]), seen), task="kakao_share")
    assert (response.status_code, response.json()["detail"]) == (status, detail)
    assert _storage_calls(seen) == []


def test_second_upload_failing_removes_every_attempted_path_and_never_calls_the_db():
    seen: list[httpx.Request] = []

    def upload(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={}) if request.url.path.endswith("-2.jpg") else httpx.Response(200, json={})

    # 저장소 호출 실패는 main.py 의 처리기가 500 으로 바꾼다(경로가 담긴 예외 문구를 응답 · 로그에 내지 않으려고).
    response = _post(_wire(_backend([_status()], upload=upload), seen), task="kakao_share", files=_photos(JPEG, JPEG, JPEG))
    assert response.status_code == 500

    attempted = sorted(r.url.path.split("/object/heart-task-proofs/")[1] for r in _storage_calls(seen) if r.method == "POST")
    removal = next(r for r in _storage_calls(seen) if r.method == "DELETE")
    assert sorted(json.loads(removal.content)["prefixes"]) == attempted and len(attempted) == 3
    assert not any(r.url.path.endswith("/rpc/submit_heart_task") for r in seen)


def test_db_says_no_after_upload_removes_all_three_files():
    seen: list[httpx.Request] = []
    submit = httpx.Response(400, json={"code": "CM409", "message": "x"})
    response = _post(_wire(_backend([_status()], submit=submit), seen), task="kakao_share",
                     files=_photos(JPEG, JPEG, JPEG))
    assert response.status_code == 409
    uploaded = [r.url.path.split("/object/heart-task-proofs/")[1] for r in _storage_calls(seen) if r.method == "POST"]
    removal = next(r for r in _storage_calls(seen) if r.method == "DELETE")
    assert json.loads(removal.content) == {"prefixes": uploaded} and len(uploaded) == 3


def test_no_answer_from_db_keeps_all_three_files():
    seen: list[httpx.Request] = []
    backend = _backend([_status()])

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/rpc/submit_heart_task"):
            raise httpx.ReadTimeout("no answer", request=request)
        return backend(request)

    with pytest.raises(httpx.ReadTimeout):
        _post(_wire(handler, seen), task="kakao_share", files=_photos(JPEG, JPEG, JPEG))
    assert [r.method for r in _storage_calls(seen)] == ["POST", "POST", "POST"]


def test_can_submit_is_true_only_for_proof_tasks_under_the_limit():
    rows = _status(everytime_post={"used": 1}, kakao_share={"reviewing": True, "used": 2})
    tasks = {t["task"]: t for t in _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"]}
    assert [(tasks[n]["can_submit"], tasks[n]["max_photos"]) for n in ("everytime_post", "kakao_share", "poll_vote")] \
        == [(False, 3), (True, 3), (False, 0)]


def test_state_stays_reviewing_while_a_pending_exists_even_if_it_can_submit():
    rows = _status(kakao_share={"reviewing": True, "used": 1})
    tasks = {t["task"]: t for t in _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"]}
    assert (tasks["kakao_share"]["state"], tasks["kakao_share"]["can_submit"]) == ("reviewing", True)


def test_pending_lists_signed_urls_in_photo_order_and_null_for_a_failed_sign():
    rows = _status(kakao_share={"reviewing": True, "used": 2},
                   everytime_post={"reviewing": True, "used": 1})
    pending = [_pending_row("s1"), _pending_row("s2", task="kakao_share", photos=1),
               _pending_row("s3", task="everytime_post", photos=2)]
    response = _wire(_backend([rows], pending=pending, sign_failures=("s1-2.jpg",))).get(
        "/heart-tasks", headers=AUTH_HEADERS)
    tasks = {t["task"]: t for t in response.json()["tasks"]}

    assert tasks["kakao_share"]["pending"] == [
        {"id": "s1", "created_at": CREATED_AT,
         "photo_urls": [f"{SIGN_PREFIX}{PROFILE_ID}/s1-1.jpg?token=t", None, f"{SIGN_PREFIX}{PROFILE_ID}/s1-3.jpg?token=t"]},
        {"id": "s2", "created_at": CREATED_AT, "photo_urls": [f"{SIGN_PREFIX}{PROFILE_ID}/s2-1.jpg?token=t"]},
    ]
    assert [p["id"] for p in tasks["everytime_post"]["pending"]] == ["s3"]  # 항목별로 나뉜다
    assert tasks["poll_vote"]["pending"] == []
    assert "storage_path" not in response.text  # 경로 원문은 서명 URL 안에만 있다


def test_no_pending_means_an_empty_list_and_no_signing():
    seen: list[httpx.Request] = []
    tasks = _wire(_backend([_status()]), seen).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"]
    assert all(t["pending"] == [] for t in tasks)
    assert not any("/object/sign/" in r.url.path for r in seen)
