"""졸업생 인증 사진 보관 한도: 14일 넘은 대기 신청 만료 · 이미 인증된 사람의 대기 신청 닫기 · 결정된 줄에 남은 사진 삭제."""
import json
import logging
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.graduate_verification.repository import GraduateRequestRepository
from app.graduate_verification.retention import PENDING_LIMIT, purge_graduate_photos
from app.graduate_verification.storage import GraduateCertStorage
from app.main import app
from app.settings import Settings

NOW = datetime(2026, 11, 20, 12, 0, tzinfo=SEOUL)
P1 = "11111111-1111-1111-1111-111111111111"
P2 = "22222222-2222-2222-2222-222222222222"
P3 = "33333333-3333-3333-3333-333333333333"
ZERO = {"photos_deleted": 0, "pending_expired": 0, "verified_cancelled": 0}


def row(rid: str, profile: str, *, status: str = "pending", age: timedelta = timedelta(days=1),
        photo: bool = True, reason: str | None = None) -> dict:
    return {"id": rid, "profile_id": profile, "status": status, "reason": reason,
            "created_at": (NOW - age).isoformat(), "photo_path": f"{profile}/{rid}.jpg" if photo else None,
            "ocr_document_number": "AB12CD34" if status == "pending" else None,
            "ocr_school_text": None, "previous_school_email": "old@prev.ac.kr" if status == "pending" else None}


class World:
    """신청 줄 · 인증된 프로필 · 버킷을 메모리에 들고 PostgREST · Storage 요청을 흉내 낸다."""

    def __init__(self, rows: list[dict], *, verified: set[str] = frozenset(), fail_delete: set[str] = frozenset(),
                 fail_reads: bool = False, fail_storage: bool = False):
        self.rows = rows
        self.verified = set(verified)
        self.photos = {r["photo_path"] for r in rows if r["photo_path"]}
        self.fail_delete = set(fail_delete)
        self.fail_reads = fail_reads
        self.fail_storage = fail_storage
        self.requests: list[httpx.Request] = []

    def parts(self) -> tuple[GraduateRequestRepository, GraduateCertStorage]:
        client = httpx.AsyncClient(transport=httpx.MockTransport(self.handle))
        return (GraduateRequestRepository("https://x.supabase.co/rest/v1", "service-key", client),
                GraduateCertStorage("https://x.supabase.co/storage/v1", "service-key", client))

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params = request.url.path, request.url.params
        if "/object/graduate-cert-temp/" in path:
            target = path.split("/object/graduate-cert-temp/", 1)[1]
            if self.fail_storage or target in self.fail_delete:
                return httpx.Response(500, json={"message": "boom"})
            self.photos.discard(target)
            return httpx.Response(200, json=[])
        assert path.endswith("/graduate_verification_requests"), path
        if request.method == "GET":
            return self._read(params)
        body = json.loads(request.content)
        if "profile_id" in params:  # 대기 신청 취소(한 번의 PATCH)
            hit = [r for r in self.rows if r["profile_id"] == params["profile_id"][3:] and r["status"] == "pending"]
            for r in hit:
                r.update(body)
            return httpx.Response(200, json=[{"id": r["id"], "photo_path": r["photo_path"]} for r in hit])
        for r in self.rows:  # 사진 경로 비우기
            if r["id"] == params["id"][3:] and r["status"] != "pending":
                r.update(body)
        return httpx.Response(204)

    def _read(self, params) -> httpx.Response:
        if self.fail_reads:
            return httpx.Response(500, json={"message": "boom"})
        limit = int(params["limit"])
        if "profiles.school_email_verified_at" in params:  # 이미 인증된 사람의 대기 신청
            assert params["status"] == "eq.pending"
            hit = [r for r in self.rows if r["status"] == "pending" and r["profile_id"] in self.verified]
        elif "created_at" in params:  # 14일 넘은 대기 신청
            assert params["status"] == "eq.pending"
            cutoff = datetime.fromisoformat(params["created_at"].removeprefix("lte."))
            hit = [r for r in self.rows if r["status"] == "pending" and datetime.fromisoformat(r["created_at"]) <= cutoff]
        else:  # 결정이 났는데 사진 경로가 남은 줄
            assert params["status"] == "neq.pending" and params["photo_path"] == "not.is.null"
            hit = [r for r in self.rows if r["status"] != "pending" and r["photo_path"]]
        return httpx.Response(200, json=[{k: r[k] for k in ("id", "profile_id", "photo_path")} for r in hit[:limit]])

    def row(self, rid: str) -> dict:
        return next(r for r in self.rows if r["id"] == rid)


async def run(world: World) -> dict[str, int]:
    return await purge_graduate_photos(*world.parts(), NOW)


async def test_pending_for_13_days_is_kept_14_days_expires():
    world = World([row("a", P1, age=timedelta(days=13, hours=23)), row("b", P2, age=PENDING_LIMIT)])

    assert PENDING_LIMIT == timedelta(days=14)
    assert await run(world) == {"photos_deleted": 1, "pending_expired": 1, "verified_cancelled": 0}
    assert world.row("a")["status"] == "pending" and world.row("a")["photo_path"] is not None
    expired = world.row("b")
    assert (expired["status"], expired["reason"]) == ("cancelled", "expired")
    assert expired["ocr_document_number"] is None and expired["previous_school_email"] is None
    assert expired["photo_path"] is None and world.photos == {f"{P1}/a.jpg"}


async def test_batch_deletes_photo_of_decided_row_left_behind():
    world = World([row("a", P1, status="approved"), row("b", P2, status="rejected", reason="unreadable"),
                   row("c", P3, status="cancelled", reason="switched")], fail_delete={f"{P1}/a.jpg"})

    # 한 사람 실패가 다음 사람을 막지 않는다.
    assert await run(world) == {"photos_deleted": 2, "pending_expired": 0, "verified_cancelled": 0}
    assert world.row("a")["photo_path"] is not None and world.photos == {f"{P1}/a.jpg"}
    assert world.row("b")["photo_path"] is None and world.row("c")["photo_path"] is None

    # 다음 시각이 다시 시도한다.
    world.fail_delete.clear()
    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0, "verified_cancelled": 0}
    assert world.photos == set() and world.row("a")["photo_path"] is None


async def test_expired_whose_photo_delete_failed_is_cleaned_up_as_a_decided_leftover_next_time():
    # 상태를 먼저 닫고 사진을 지운다 — 삭제가 실패해도 다음에 "결정됐는데 남은 사진"으로 걸려 지워진다.
    world = World([row("a", P1, age=timedelta(days=15))], fail_delete={f"{P1}/a.jpg"})

    assert await run(world) == {"photos_deleted": 0, "pending_expired": 1, "verified_cancelled": 0}
    assert world.row("a")["status"] == "cancelled" and world.row("a")["photo_path"] is not None

    world.fail_delete.clear()
    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0, "verified_cancelled": 0}


async def test_pending_of_verified_profile_is_cancelled():
    world = World([row("a", P1), row("b", P2)], verified={P1})

    assert await run(world) == {"photos_deleted": 1, "pending_expired": 0, "verified_cancelled": 1}
    done = world.row("a")
    assert (done["status"], done["reason"], done["photo_path"]) == ("cancelled", "verified_otherwise", None)
    assert done["previous_school_email"] is None
    assert world.row("b")["status"] == "pending"


async def test_purge_is_idempotent_and_never_raises():
    world = World([row("a", P1, status="approved"), row("b", P2, age=timedelta(days=20))])

    assert await run(world) == {"photos_deleted": 2, "pending_expired": 1, "verified_cancelled": 0}
    assert await run(world) == ZERO

    # 목록 조회 실패 · 저장소 장애에도 예외 없이 0건
    assert await run(World([row("c", P3, status="approved")], fail_reads=True)) == ZERO
    assert await run(World([row("c", P3, status="approved")], fail_storage=True)) == ZERO


async def test_purge_logs_ids_only(caplog):
    world = World([row("a", P1, status="approved")], fail_delete={f"{P1}/a.jpg"})

    with caplog.at_level(logging.DEBUG, logger="app"):
        await run(world)

    assert "request=a" in caplog.text
    for secret in (P1, ".jpg", "service-key", "AB12CD34", "old@prev.ac.kr"):
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
        if request.url.path.endswith("/graduate_verification_requests") or "/object/graduate-cert-temp/" in request.url.path:
            return world.handle(request)
        return httpx.Response(200, json=[])  # 매칭 · 보류 알림 · 알림함 · 학생증은 비어 있다

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return TestClient(app).post("/batch/chat-gate", headers={"Authorization": "Bearer id-token"})


def test_hourly_chat_gate_batch_runs_graduate_purge(batch_client):
    # 배치는 진짜 지금(datetime.now)을 쓴다 — 15일 전을 지금 기준으로 다시 잡는다.
    stale = row("b", P2)
    stale["created_at"] = (datetime.now(SEOUL) - timedelta(days=15)).isoformat()
    world = World([row("a", P1, status="approved"), stale])

    response = _run_batch(world)

    assert response.status_code == 200
    body = response.json()
    assert (body["graduate_photos_deleted"], body["graduate_pending_expired"], body["graduate_verified_cancelled"]) == (2, 1, 0)
    # 옛 학생증 정리 키는 그대로다.
    assert (body["photos_deleted"], body["pending_expired"]) == (0, 0)


def test_graduate_purge_failure_does_not_lose_the_other_batch_results(batch_client, monkeypatch):
    async def explode(*args, **kwargs):
        raise RuntimeError("boom")

    monkeypatch.setattr("app.chat.batch_router.purge_graduate_photos", explode)

    response = _run_batch(World([]))

    assert response.status_code == 200
    body = response.json()
    assert (body["graduate_photos_deleted"], body["graduate_pending_expired"], body["graduate_verified_cancelled"]) == (0, 0, 0)
    assert "deferred_sent" in body and "notifications_purged" in body
