"""학생증 사진 정리 배치(사용자 결정 2026-10-11): 사람이 재검토한 시도의 남은 사진을 치우고,
검토 대기 30일이 지난 시도는 사진을 지운 뒤 반려(사유: 기한 만료)로 닫는다. 매시 chat-gate 배치가 부른다.
학생증 제거(10-17) 뒤로는 시도 행만 닫고 프로필(student_verification)은 건드리지 않는다."""
import logging
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings
from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.retention import EXPIRED_REASON, purge_student_id_photos
from app.student_verification.storage import StudentIdStorage

NOW = datetime(2026, 11, 20, 12, 0, tzinfo=SEOUL)
P1 = "11111111-1111-1111-1111-111111111111"
P2 = "22222222-2222-2222-2222-222222222222"
P3 = "33333333-3333-3333-3333-333333333333"


def _ago(**delta) -> str:
    return (NOW - timedelta(**delta)).isoformat()


def attempt(attempt_id: int, profile_id: str, *, result: str = "pending", age: dict | None = None) -> dict:
    return {"id": attempt_id, "profile_id": profile_id, "file_path": f"{profile_id}/photo-{attempt_id}.jpg",
            "result": result, "submitted_at": _ago(**(age or {"days": 1})), "reject_reason": None, "reviewed_at": None}


class World:
    """attempts · profiles · Storage 버킷을 메모리에 들고 PostgREST · Storage 요청을 흉내 낸다.
    사진은 시도의 file_path 마다 하나씩 버킷에 들어 있다(`photos=False` 면 이미 지워진 시도)."""

    def __init__(self, attempts: list[dict], profile_status: dict[str, str] | None = None, *,
                 photos: list[str] | None = None, fail_delete: set[str] = frozenset(),
                 fail_profile_patch: set[str] = frozenset(), fail_list: bool = False):
        self.attempts = attempts
        self.profiles = profile_status or {a["profile_id"]: a["result"] for a in attempts}
        self.photos = set(photos if photos is not None else [a["file_path"] for a in attempts])
        self.fail_delete = set(fail_delete)
        self.fail_profile_patch = set(fail_profile_patch)
        self.fail_list = fail_list
        self.requests: list[httpx.Request] = []

    def parts(self) -> tuple[StudentVerificationRepository, StudentIdStorage]:
        client = httpx.AsyncClient(transport=httpx.MockTransport(self.handle))
        return (StudentVerificationRepository("https://x.supabase.co/rest/v1", "service-key", client),
                StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client))

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params = request.url.path, request.url.params
        if request.method == "POST" and path.endswith("/object/list/student-id-temp"):
            return self._list(request)
        if request.method == "DELETE" and "/object/student-id-temp/" in path:
            target = path.split("/object/student-id-temp/", 1)[1]
            if target in self.fail_delete:
                return httpx.Response(500, json={"message": "boom"})
            self.photos.discard(target)
            return httpx.Response(200, json=[])
        if path.endswith("/student_verification_attempts"):
            return self._attempts(request, params)
        if path.endswith("/profiles") and request.method == "PATCH":
            return self._profiles(request, params)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})

    def _list(self, request: httpx.Request) -> httpx.Response:
        if self.fail_list:
            return httpx.Response(500, json={"message": "boom"})
        import json
        prefix = json.loads(request.content)["prefix"]
        if prefix == "":
            folders = sorted({p.split("/")[0] for p in self.photos})
            return httpx.Response(200, json=[{"name": f, "id": None} for f in folders])
        return httpx.Response(200, json=[{"name": p[len(prefix):], "id": "obj"} for p in sorted(self.photos)
                                         if p.startswith(prefix)])

    def _attempts(self, request: httpx.Request, params) -> httpx.Response:
        import json
        if request.method == "GET" and params.get("file_path", "").startswith("eq."):
            rows = [a for a in self.attempts if a["file_path"] == params["file_path"][3:]]
            return httpx.Response(200, json=[{"id": a["id"], "result": a["result"]} for a in rows[:1]])
        if request.method == "GET" and params.get("profile_id", "").startswith("eq."):  # 그 사람의 최근 시도
            rows = sorted((a for a in self.attempts if a["profile_id"] == params["profile_id"][3:]),
                          key=lambda a: a["submitted_at"], reverse=True)
            return httpx.Response(200, json=[{k: a[k] for k in ("id", "file_path", "reject_reason", "result")}
                                             for a in rows[:1]])
        if request.method == "GET":  # 30일 지난 대기 시도 목록
            assert params["result"] == "eq.pending"
            cutoff = datetime.fromisoformat(params["submitted_at"].removeprefix("lte."))
            rows = [a for a in self.attempts
                    if a["result"] == "pending" and datetime.fromisoformat(a["submitted_at"]) <= cutoff]
            rows.sort(key=lambda a: a["submitted_at"])
            return httpx.Response(200, json=[{k: a[k] for k in ("id", "profile_id", "file_path")}
                                             for a in rows[:int(params["limit"])]])
        assert request.method == "PATCH"
        wanted = int(params["id"].removeprefix("eq."))
        for a in self.attempts:
            if a["id"] == wanted and ("result" not in params or params["result"] == f"eq.{a['result']}"):
                a.update(json.loads(request.content))
        return httpx.Response(204)

    def _profiles(self, request: httpx.Request, params) -> httpx.Response:
        import json
        profile_id = params["id"].removeprefix("eq.")
        if profile_id in self.fail_profile_patch:
            return httpx.Response(500, json={"message": "boom"})
        guard = params.get("student_verification")
        if guard is None or guard == f"eq.{self.profiles[profile_id]}":
            self.profiles[profile_id] = json.loads(request.content)["student_verification"]
        return httpx.Response(204)

    def attempt(self, attempt_id: int) -> dict:
        return next(a for a in self.attempts if a["id"] == attempt_id)


async def run(world: World) -> dict[str, int]:
    return await purge_student_id_photos(*world.parts(), NOW)


# (a) 검토가 끝났는데 남은 사진 ----------------------------------------------------------

async def test_photos_of_reviewed_attempts_are_deleted_and_states_are_untouched():
    world = World([attempt(1, P1, result="verified"), attempt(2, P2, result="rejected")])

    assert await run(world) == {"photos_deleted": 2, "pending_expired": 0}
    assert world.photos == set()
    assert (world.attempt(1)["result"], world.attempt(2)["result"]) == ("verified", "rejected")
    assert world.profiles == {P1: "verified", P2: "rejected"}


async def test_a_photo_without_an_attempt_row_is_left_alone():
    # 업로드 직후 시도 행을 쓰기 전일 수 있다 — 지우면 방금 낸 학생증이 사라진다.
    world = World([], photos=[f"{P1}/just-uploaded.jpg"])

    assert await run(world) == {"photos_deleted": 0, "pending_expired": 0}
    assert world.photos == {f"{P1}/just-uploaded.jpg"}


# (b) 검토 대기 30일 --------------------------------------------------------------------

async def test_pending_for_29_days_is_kept():
    world = World([attempt(1, P1, age={"days": 29, "hours": 23})])

    assert await run(world) == {"photos_deleted": 0, "pending_expired": 0}
    assert world.photos == {f"{P1}/photo-1.jpg"}
    assert (world.attempt(1)["result"], world.profiles[P1]) == ("pending", "pending")


async def test_pending_for_30_days_closes_the_attempt_and_deletes_its_photo_but_leaves_the_profile():
    # 학생증 제거(10-17): 프로필을 rejected 로 바꾸면 DB 트리거가 "학생 인증을 다시 해 주세요" 푸시를 보낸다 — 시도만 닫는다.
    world = World([attempt(1, P1, age={"days": 30})])

    assert await run(world) == {"photos_deleted": 1, "pending_expired": 1}
    assert world.photos == set()
    expired = world.attempt(1)
    assert (expired["result"], expired["reject_reason"]) == ("rejected", EXPIRED_REASON)
    assert expired["reviewed_at"] == NOW.isoformat()
    assert world.profiles[P1] == "pending"


async def test_an_old_attempt_that_is_not_pending_is_not_expired():
    world = World([attempt(1, P1, result="verified", age={"days": 90})], photos=[])

    assert await run(world) == {"photos_deleted": 0, "pending_expired": 0}
    assert (world.attempt(1)["result"], world.attempt(1)["reject_reason"]) == ("verified", None)
    assert world.profiles[P1] == "verified"


async def test_expiring_does_not_overwrite_a_profile_a_human_already_settled():
    # 사람이 profiles 만 verified 로 바꾸고 attempts 를 놓친 경우 — 프로필은 그대로 두고 시도만 닫는다.
    world = World([attempt(1, P1, age={"days": 31})], {P1: "verified"})

    await run(world)

    assert world.profiles[P1] == "verified"
    assert world.attempt(1)["result"] == "rejected"
    assert world.photos == set()


async def test_an_old_pending_attempt_is_closed_but_the_profile_follows_the_newest_attempt():
    # 새로 낸 시도가 심사를 기다리는 중이면 프로필(pending)을 건드리지 않는다 — 옛 시도만 닫고 그 사진만 지운다.
    old = attempt(1, P1, age={"days": 40})
    new = attempt(2, P1, age={"days": 2})
    world = World([old, new])

    assert await run(world) == {"photos_deleted": 1, "pending_expired": 1}
    assert (world.attempt(1)["result"], world.attempt(1)["reject_reason"]) == ("rejected", EXPIRED_REASON)
    assert (world.attempt(2)["result"], world.attempt(2)["reject_reason"]) == ("pending", None)
    assert world.profiles[P1] == "pending"
    assert world.photos == {f"{P1}/photo-2.jpg"}


async def test_expiry_never_writes_the_profile_so_the_review_push_trigger_never_fires():
    # profiles.student_verification 을 바꾸는 쓰기가 곧 검토 결과 푸시(on_student_verification_reviewed)다 — 하나도 없어야 한다.
    world = World([attempt(1, P1, age={"days": 31}), attempt(2, P2, age={"days": 45})])

    await run(world)

    writes = [(r.url.path.rsplit("/", 1)[-1], r.method) for r in world.requests if r.method == "PATCH"]
    assert writes == [("student_verification_attempts", "PATCH")] * 2
    assert world.profiles == {P1: "pending", P2: "pending"}


# 저장소의 조건: 이미 확정된 행은 건드리지 않는다 ---------------------------------------------

async def test_closing_never_overwrites_an_attempt_that_is_no_longer_pending():
    world = World([attempt(1, P1, result="verified")])
    repo, _ = world.parts()

    await repo.close_attempt(1, EXPIRED_REASON, NOW)

    assert (world.attempt(1)["result"], world.attempt(1)["reject_reason"]) == ("verified", None)


async def test_reopening_only_undoes_a_rejected_attempt():
    world = World([attempt(1, P1, result="verified")])
    repo, _ = world.parts()

    await repo.reopen_attempt(1)

    assert world.attempt(1)["result"] == "verified"


# 반복 · 실패 ----------------------------------------------------------------------------

async def test_running_again_changes_nothing():
    world = World([attempt(1, P1, result="verified"), attempt(2, P2, age={"days": 40})])

    assert await run(world) == {"photos_deleted": 2, "pending_expired": 1}
    assert await run(world) == {"photos_deleted": 0, "pending_expired": 0}


async def test_one_failed_delete_does_not_stop_the_next_person_and_is_retried_next_time():
    world = World([attempt(1, P1, result="verified"), attempt(2, P2, result="rejected")],
                  fail_delete={f"{P1}/photo-1.jpg"})

    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0}
    assert world.photos == {f"{P1}/photo-1.jpg"}

    world.fail_delete.clear()
    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0}
    assert world.photos == set()


async def test_expired_whose_photo_delete_failed_is_cleaned_up_as_a_reviewed_leftover_next_time():
    # 상태를 먼저 닫고 사진을 지운다 — 삭제가 실패해도 다음 번에 "검토 끝났는데 남은 사진"으로 걸려 지워진다.
    world = World([attempt(1, P1, age={"days": 31})], fail_delete={f"{P1}/photo-1.jpg"})

    assert await run(world) == {"photos_deleted": 0, "pending_expired": 1}
    assert world.attempt(1)["result"] == "rejected"

    world.fail_delete.clear()
    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0}
    assert world.photos == set()


async def test_a_broken_profile_table_does_not_stop_expiry():
    # 프로필을 쓰지 않으니 프로필 쓰기 장애와 상관없이 둘 다 닫히고 사진도 지워진다.
    world = World([attempt(1, P1, age={"days": 31}), attempt(2, P2, age={"days": 32})],
                  fail_profile_patch={P1, P2})

    assert await run(world) == {"photos_deleted": 2, "pending_expired": 2}
    assert (world.attempt(1)["result"], world.attempt(2)["result"]) == ("rejected", "rejected")
    assert world.photos == set()


async def test_a_failing_bucket_listing_does_not_block_expiry():
    world = World([attempt(1, P1, age={"days": 31})], fail_list=True)

    assert await run(world) == {"photos_deleted": 1, "pending_expired": 1}


async def test_logs_name_attempts_by_id_only(caplog):
    world = World([attempt(7, P1, result="verified"), attempt(8, P2, age={"days": 31})],
                  fail_delete={f"{P1}/photo-7.jpg", f"{P2}/photo-8.jpg"}, fail_list=False)
    with caplog.at_level(logging.DEBUG, logger="app"):
        await run(world)

    assert "attempt=7" in caplog.text and "attempt=8" in caplog.text
    for secret in (P1, P2, "photo-7", "photo-8", ".jpg", "service-key", EXPIRED_REASON):
        assert secret not in caplog.text


# 배치 연결 ------------------------------------------------------------------------------

AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"


@pytest.fixture
def batch_client(monkeypatch):
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        batch_audience=AUDIENCE, batch_service_account=SCHEDULER,
    )
    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token",
                        lambda token, request, audience: {"email": SCHEDULER, "email_verified": True})
    yield
    app.dependency_overrides.clear()


def _run_batch(world: World):
    def handler(request: httpx.Request) -> httpx.Response:
        if "/object/" in request.url.path or request.url.path.endswith(("/student_verification_attempts", "/profiles")):
            return world.handle(request)
        return httpx.Response(200, json=[])  # 매칭 · 보류 알림 · 알림함은 비어 있다

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return TestClient(app).post("/batch/chat-gate", headers={"Authorization": "Bearer id-token"})


def test_the_hourly_chat_gate_batch_cleans_student_id_photos(batch_client):
    # 배치는 진짜 지금(datetime.now)을 쓴다 — 31일 전을 지금 기준으로 다시 잡는다.
    long_waiting = {**attempt(2, P2), "submitted_at": (datetime.now(SEOUL) - timedelta(days=31)).isoformat()}
    world = World([attempt(1, P1, result="verified"), long_waiting])

    response = _run_batch(world)

    assert response.status_code == 200
    body = response.json()
    assert (body["photos_deleted"], body["pending_expired"]) == (2, 1)
    assert world.photos == set()


def test_an_unexpected_error_in_the_photo_cleanup_does_not_fail_the_batch(batch_client, monkeypatch):
    async def explode(*_args):
        raise RuntimeError("boom")

    monkeypatch.setattr("app.chat.batch_router.purge_student_id_photos", explode)
    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json=[])))

    response = TestClient(app).post("/batch/chat-gate", headers={"Authorization": "Bearer id-token"})

    assert response.status_code == 200
    assert response.json()["notifications_purged"] == 0  # 앞 작업 결과가 그대로 실린다
    assert (response.json()["photos_deleted"], response.json()["pending_expired"]) == (0, 0)


def test_a_failing_photo_cleanup_does_not_fail_the_batch(batch_client):
    world = World([attempt(1, P1, result="verified")], fail_list=True)

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/student_verification_attempts"):
            return httpx.Response(500, json={"message": "boom"})
        return world.handle(request) if "/object/" in request.url.path else httpx.Response(200, json=[])

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    response = TestClient(app).post("/batch/chat-gate", headers={"Authorization": "Bearer id-token"})

    assert response.status_code == 200
    assert (response.json()["photos_deleted"], response.json()["pending_expired"]) == (0, 0)
