"""아바타 비동기 생성(Cloud Tasks) — POST 등록 · 워커 · 상태 조회.

계획서 docs/superpowers/plans/2026-09-25-avatar-async-cloud-tasks.md 의 테스트 표를 따른다.
로컬 스택에는 Cloud Tasks 가 없다 — 목으로 본다(우회로를 코드에 만들지 않는다).
"""
import base64
import json
from collections.abc import Callable
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

import app.profile_onboarding.router as router_module
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
ATTEMPT_ID = UUID("22222222-2222-2222-2222-222222222222")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
WORKER_URL = "https://api.example.com/tasks/avatar-generate"
SERVICE_ACCOUNT = "tasks@campus-mate-test.iam.gserviceaccount.com"
NOW = datetime(2026, 9, 26, 12, 0, tzinfo=SEOUL)
_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"0" * 32


def _settings(**overrides) -> Settings:
    values = {
        "supabase_url": "https://x.supabase.co",
        "supabase_service_role_key": "service-key",
        "auth_hook_signing_secret": "whsec_test",
        "discord_webhook_url": "https://discord.com/api/webhooks/test",
        "google_cloud_project": "campus-mate-test",
        "openai_api_key": "sk-test",
        "phone_encryption_key": "phone-key-test",
        "identity_hmac_key": "identity-key-test",
        "avatar_tasks_queue": "avatar-generate",
        "avatar_worker_url": WORKER_URL,
        "avatar_tasks_service_account": SERVICE_ACCOUNT,
    }
    return Settings(**{**values, **overrides})


@pytest.fixture(autouse=True)
def fake_google_credentials(monkeypatch):
    """테스트 환경에는 ADC 가 없다. **토큰 받아오는 자리만** 가짜로 두고, 요청 조립은 진짜 코드가 한다."""
    import google.auth

    credentials = SimpleNamespace(valid=True, token="access-token")
    monkeypatch.setattr(google.auth, "default", lambda scopes=None: (credentials, "campus-mate-test"))


@pytest.fixture(autouse=True)
def overrides():
    # 람다로 감싼다 — 함수를 그대로 넘기면 FastAPI 가 **overrides 를 필수 쿼리 인자로 읽는다.
    app.dependency_overrides[get_settings] = lambda: _settings()
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


class _Fake:
    """PostgREST · Storage · Cloud Tasks 를 한 손잡이로 흉내 낸다.

    행 하나짜리 가짜 DB 가 아니라 "이 요청에 이렇게 답한다" 수준이다 — 라우터가 **어떤 순서로 무엇을
    부르는지**가 보고 싶은 것이지 Postgres 를 다시 만들고 싶은 게 아니다.
    """

    def __init__(
        self,
        ready_rows: list | None = None,
        attempt_rows: list | None = None,
        source_path: str | None = "aa/source.png",
        pending_conflict: bool = False,
        latest_attempt: dict | None = None,
        enqueue_status: int = 200,
        stale_rows: list | None = None,
    ):
        self.ready_rows = ready_rows or []
        self.attempt_rows = attempt_rows or []
        self.source_path = source_path
        self.pending_conflict = pending_conflict
        self.latest_attempt = latest_attempt
        self.enqueue_status = enqueue_status
        self.stale_rows = stale_rows if stale_rows is not None else []
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        self.requests.append(request)

        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(
                200, json=[{"student_verification": "verified", "department": "컴퓨터공학과"}]
            )
        if "cloudtasks.googleapis.com" in url:
            return httpx.Response(self.enqueue_status, json={"name": "tasks/1"})
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(
                200, json=[{"storage_path": self.source_path}] if self.source_path else []
            )
        if "/storage/v1/object/profile-photos/" in url and request.method == "GET":
            return httpx.Response(200, content=_PNG_BYTES)
        if "/storage/v1/object/copy" in url:
            return httpx.Response(200, json={"Key": "avatars/aa/fallback.png"})
        if "/storage/v1/object/avatars/" in url:
            return httpx.Response(200, json={"Key": "avatars/aa/new.png"})
        if "/rest/v1/rpc/grant_hearts" in url:
            return httpx.Response(200)

        if "/rest/v1/profile_avatars" in url:
            # 문자열이 아니라 쿼리 **키**로 가른다 — `profile_id=eq.` 안에 `id=eq.` 가 들어 있어서
            # 부분 문자열로 나누면 카운트 조회가 한 줄 조회로 새어 간다.
            params = request.url.params
            if request.method == "GET":
                if params.get("status") == "eq.ready":
                    return httpx.Response(200, json=self.ready_rows)
                if "id" in params or params.get("limit") == "1":
                    return httpx.Response(
                        200, json=[self.latest_attempt] if self.latest_attempt else []
                    )
                return httpx.Response(200, json=self.attempt_rows)
            if request.method == "POST":
                if json.loads(request.content).get("status") == "pending" and self.pending_conflict:
                    return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
                return httpx.Response(201, json=[{"id": str(ATTEMPT_ID)}])
            if request.method == "PATCH":
                if "created_at" in params:
                    return httpx.Response(200, json=self.stale_rows)
                return httpx.Response(200, json=[{"id": str(ATTEMPT_ID)}])
            if request.method == "DELETE":
                return httpx.Response(204)

        return httpx.Response(200, json=[])

    # --- 나간 요청 훑어보기 -----------------------------------------------
    def calls(self, method: str, fragment: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and fragment in str(r.url)]

    @property
    def enqueued(self) -> list[httpx.Request]:
        return self.calls("POST", "cloudtasks.googleapis.com")

    @property
    def granted_hearts(self) -> list[httpx.Request]:
        return self.calls("POST", "/rest/v1/rpc/grant_hearts")

    @property
    def inserted_avatars(self) -> list[dict]:
        return [json.loads(r.content) for r in self.calls("POST", "/rest/v1/profile_avatars")]


def _client(fake: _Fake) -> TestClient:
    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(
        transport=httpx.MockTransport(fake)
    )
    return TestClient(app)


def _post(fake: _Fake) -> httpx.Response:
    return _client(fake).post("/profile-onboarding/avatar/generate", headers=AUTH_HEADERS)


def _failed(count: int) -> list[dict]:
    return [{"status": "failed"}] * count


# --- POST /profile-onboarding/avatar/generate --------------------------------


def test_post_enqueues_a_task_and_returns_202_without_calling_openai():
    """POST 는 등록만 한다 — 그림을 만드는 동안 사람은 다음 질문으로 넘어간다(2026-09-25 사용자 결정)."""
    fake = _Fake()

    response = _post(fake)

    assert response.status_code == 202
    # 상태 조회와 **칸이 같다** — 앱은 두 응답을 파서 하나로 읽는다.
    assert response.json() == {"status": "pending", "avatar_url": None, "compensation_hearts": None}
    assert len(fake.enqueued) == 1
    # 만드는 중 행이 먼저 생기고, 그 id 가 작업 본문에 실린다.
    assert fake.inserted_avatars == [
        {"profile_id": str(PROFILE_ID), "status": "pending", "storage_path": None}
    ]


def test_enqueued_task_carries_the_worker_url_body_and_oidc_audience():
    fake = _Fake()

    _post(fake)

    request = fake.enqueued[0]
    assert "/queues/avatar-generate/tasks" in str(request.url)
    assert "locations/asia-northeast3" in str(request.url)
    task = json.loads(request.content)["task"]
    assert task["httpRequest"]["url"] == WORKER_URL
    assert task["httpRequest"]["oidcToken"] == {
        "serviceAccountEmail": SERVICE_ACCOUNT,
        "audience": WORKER_URL,
    }
    assert task["dispatchDeadline"] == "240s"
    assert json.loads(base64.b64decode(task["httpRequest"]["body"])) == {
        "profile_id": str(PROFILE_ID),
        "attempt_id": str(ATTEMPT_ID),
    }


def test_post_cleans_up_stale_pending_rows_before_inserting():
    """정리가 insert 보다 먼저여야 유니크 인덱스가 비고, 그 failed 가 5회 카운트에 들어간다."""
    fake = _Fake(stale_rows=[{"id": str(uuid4())}])

    assert _post(fake).status_code == 202

    cleanup = fake.calls("PATCH", "created_at=lt.")
    assert len(cleanup) == 1
    assert json.loads(cleanup[0].content) == {"status": "failed"}
    # 남의 행은 건드리지 않는다 — profile_id 로 한정한다.
    assert f"profile_id=eq.{PROFILE_ID}" in str(cleanup[0].url)
    # 정리 -> insert 순서다.
    assert fake.requests.index(cleanup[0]) < fake.requests.index(
        fake.calls("POST", "/rest/v1/profile_avatars")[0]
    )


def test_post_uses_the_injected_now_for_the_ten_minute_line():
    fake = _Fake()

    _post(fake)

    cleanup = fake.calls("PATCH", "created_at=lt.")[0]
    # 시간대가 붙은 값이어야 한다 — naive 로 비교하면 9시간 어긋나 방금 만든 행까지 낡음이 된다.
    boundary = datetime.fromisoformat(cleanup.url.params["created_at"].removeprefix("lt."))
    assert boundary == NOW - timedelta(minutes=10)
    assert boundary.tzinfo is not None


def test_post_returns_the_same_202_when_the_button_is_pressed_twice():
    """두 번째 insert 는 23505 로 튕긴다. 409 "이미 등록된 정보예요" 가 아니라 **조용히 같은 202** 다."""
    fake = _Fake(pending_conflict=True)

    response = _post(fake)

    assert response.status_code == 202
    assert response.json() == {"status": "pending", "avatar_url": None, "compensation_hearts": None}
    # 작업을 다시 등록하지 않는다 — 이미 만드는 중이다.
    assert fake.enqueued == []


def test_post_pays_the_compensation_itself_after_five_failures():
    """워커가 한 번도 안 도는 배포에서 온보딩이 갇히지 않는 유일한 출구다."""
    fake = _Fake(attempt_rows=_failed(5))

    response = _post(fake)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "fallback"
    assert body["compensation_hearts"] == 10
    assert body["avatar_url"].startswith("https://x.supabase.co/storage/v1/object/public/avatars/")
    assert len(fake.granted_hearts) == 1
    # 보상으로 끝났으니 작업은 등록하지 않는다(무료 기회가 끝났다).
    assert fake.enqueued == []
    assert fake.inserted_avatars == [
        {
            "profile_id": str(PROFILE_ID),
            "status": "ready",
            "storage_path": f"{PROFILE_ID}/" + fake.inserted_avatars[0]["storage_path"].split("/")[1],
            "is_fallback": True,
        }
    ]


def test_post_still_reports_the_fallback_when_the_hearts_grant_fails():
    """기본 아바타 행은 이미 들어갔다 — 여기서 500 을 내면 사람은 409 로 다시 만들 수도 없다."""

    class _HeartsDown(_Fake):
        def __call__(self, request):
            if "/rest/v1/rpc/grant_hearts" in str(request.url):
                self.requests.append(request)
                return httpx.Response(500, json={"message": "boom"})
            return super().__call__(request)

    fake = _HeartsDown(attempt_rows=_failed(5))

    response = _post(fake)

    assert response.status_code == 200
    assert response.json()["status"] == "fallback"
    # 행은 남는다. 하트는 사람이 손으로 보정한다(로그의 profile_id 로 찾는다).
    assert [row["is_fallback"] for row in fake.inserted_avatars] == [True]


def test_post_counts_the_just_cleaned_pending_row_toward_five():
    """failed 4 + 방금 정리된 pending 1 = 5 다. 정리가 카운트보다 먼저라 이 줄이 성립한다."""
    fake = _Fake(attempt_rows=_failed(4) + [{"status": "failed"}], stale_rows=[{"id": str(uuid4())}])

    assert _post(fake).json()["status"] == "fallback"
    assert len(fake.granted_hearts) == 1


def test_post_rejects_a_second_avatar_even_after_the_compensation():
    """보상으로 받은 기본 아바타도 ready 행이다 — 다시 눌러도 안 만들어진다(하트 이중 지급 차단)."""
    fake = _Fake(ready_rows=[{"id": str(uuid4())}])

    response = _post(fake)

    assert response.status_code == 409
    assert fake.enqueued == []
    assert fake.inserted_avatars == []


def test_post_deletes_the_row_and_returns_502_when_the_queue_call_fails():
    """우리 인프라 사고가 사용자의 무료 기회를 깎으면 안 된다 — failed 로 남기지 않고 지운다."""
    fake = _Fake(enqueue_status=500)

    response = _post(fake)

    assert response.status_code == 502
    assert len(fake.calls("DELETE", "/rest/v1/profile_avatars")) == 1


def test_post_returns_503_before_creating_a_row_when_the_queue_is_not_configured():
    app.dependency_overrides[get_settings] = lambda: _settings(avatar_tasks_queue="")
    fake = _Fake()

    response = _post(fake)

    assert response.status_code == 503
    assert fake.inserted_avatars == []
    assert fake.enqueued == []


def test_post_returns_409_when_no_source_photo_is_picked():
    fake = _Fake(source_path=None)

    assert _post(fake).status_code == 409
    assert fake.inserted_avatars == []


# --- GET /profile-onboarding/avatar/status -----------------------------------


def _status(fake: _Fake) -> dict:
    response = _client(fake).get("/profile-onboarding/avatar/status", headers=AUTH_HEADERS)
    assert response.status_code == 200
    return response.json()


def test_status_says_none_when_nothing_was_ever_tried():
    fake = _Fake(latest_attempt=None)

    assert _status(fake) == {"status": "none", "avatar_url": None, "compensation_hearts": None}
    # 여기서 작업을 자동 등록하지 않는다 — 사진만 고르고 앱을 닫은 사람이 여기 온다.
    assert fake.enqueued == []


def test_status_says_pending_while_it_is_still_being_made():
    fake = _Fake(
        latest_attempt={
            "id": str(ATTEMPT_ID), "status": "pending", "storage_path": None,
            "is_fallback": False, "created_at": (NOW - timedelta(minutes=1)).isoformat(),
        }
    )

    assert _status(fake) == {"status": "pending", "avatar_url": None, "compensation_hearts": None}


def test_status_shows_a_stale_pending_as_failed_without_touching_the_row():
    """10분 넘으면 화면에는 실패로 보여 준다. DB 를 고치는 것은 POST 다."""
    fake = _Fake(
        latest_attempt={
            "id": str(ATTEMPT_ID), "status": "pending", "storage_path": None,
            "is_fallback": False, "created_at": (NOW - timedelta(minutes=11)).isoformat(),
        }
    )

    assert _status(fake)["status"] == "failed"
    assert fake.calls("PATCH", "/rest/v1/profile_avatars") == []


def test_status_carries_the_full_url_on_ready():
    fake = _Fake(
        latest_attempt={
            "id": str(ATTEMPT_ID), "status": "ready", "storage_path": "aa/avatar.png",
            "is_fallback": False, "created_at": NOW.isoformat(),
        }
    )

    assert _status(fake) == {
        "status": "ready",
        # 접두사는 서버가 붙인다 — Dart 가 손으로 붙이는 자리를 만들면 버킷을 바꿀 때 전부 깨진다.
        "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png",
        "compensation_hearts": None,
    }


def test_status_tells_a_fallback_apart_from_a_normal_ready():
    """ready 로 보내면 앱이 그냥 완성으로 읽어 보상 안내가 영영 안 뜬다 — 하트는 나갔는데 이유를 모른다."""
    fake = _Fake(
        latest_attempt={
            "id": str(ATTEMPT_ID), "status": "ready", "storage_path": "aa/fallback.png",
            "is_fallback": True, "created_at": NOW.isoformat(),
        }
    )

    assert _status(fake) == {
        "status": "fallback",
        "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/aa/fallback.png",
        "compensation_hearts": 10,
    }


def test_status_says_failed_after_a_failed_attempt():
    fake = _Fake(
        latest_attempt={
            "id": str(ATTEMPT_ID), "status": "failed", "storage_path": None,
            "is_fallback": False, "created_at": NOW.isoformat(),
        }
    )

    assert _status(fake) == {"status": "failed", "avatar_url": None, "compensation_hearts": None}


# --- POST /tasks/avatar-generate (워커) --------------------------------------


def _worker(fake: _Fake, openai: AsyncMock, authorized: bool = True) -> httpx.Response:
    app.dependency_overrides[router_module.get_openai] = lambda: openai
    headers = {"Authorization": "Bearer id-token"} if authorized else {}
    return _client(fake).post(
        "/tasks/avatar-generate",
        json={"profile_id": str(PROFILE_ID), "attempt_id": str(ATTEMPT_ID)},
        headers=headers,
    )


def _openai(succeeds: bool) -> AsyncMock:
    client = AsyncMock()
    if succeeds:
        client.images.edit.return_value = SimpleNamespace(
            data=[SimpleNamespace(b64_json=base64.b64encode(_PNG_BYTES).decode())]
        )
    else:
        client.images.edit.side_effect = Exception("openai down")
    return client


def _verifies(monkeypatch: pytest.MonkeyPatch, claims: dict | None = None) -> None:
    """구글 서명 확인만 가짜로 통과시킨다 — 발급자 확인은 진짜 코드가 그대로 한다."""
    import app.core.batch_auth as batch_auth

    def fake_verify(token, request, audience):
        # 워커가 **자기 주소를** audience 로 넘기는지 여기서 못 박는다 — 어긋나면 큐는 부르는데 401 이다.
        assert audience == WORKER_URL
        if claims is None:
            raise ValueError("bad token")
        return claims

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)


def _pending_attempt() -> dict:
    return {
        "id": str(ATTEMPT_ID), "profile_id": str(PROFILE_ID), "status": "pending",
        "storage_path": None, "is_fallback": False, "created_at": NOW.isoformat(),
    }


def test_worker_rejects_a_call_without_a_token():
    assert _worker(_Fake(), _openai(True), authorized=False).status_code == 401


def test_worker_rejects_a_token_from_another_service_account(monkeypatch):
    """audience 만 맞으면 그 URL 을 아는 다른 계정도 들어온다 — 발급자까지 본다."""
    _verifies(monkeypatch, {"email": "someone-else@evil.iam.gserviceaccount.com", "email_verified": True})

    assert _worker(_Fake(), _openai(True)).status_code == 401


def test_worker_rejects_a_token_whose_email_is_not_verified(monkeypatch):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": False})

    assert _worker(_Fake(), _openai(True)).status_code == 401


def test_worker_rejects_a_token_whose_signature_does_not_check_out(monkeypatch):
    _verifies(monkeypatch, None)

    assert _worker(_Fake(), _openai(True)).status_code == 401


def test_worker_rejects_everyone_when_the_service_account_is_not_configured(monkeypatch):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    app.dependency_overrides[get_settings] = lambda: _settings(avatar_tasks_service_account="")

    assert _worker(_Fake(), _openai(True)).status_code == 401


def test_worker_writes_the_result_into_the_pending_row(monkeypatch):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    fake = _Fake(latest_attempt=_pending_attempt())

    response = _worker(fake, _openai(True))

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
    patched = fake.calls("PATCH", "/rest/v1/profile_avatars")
    assert len(patched) == 1
    # 만드는 중인 행만 고친다 — 이 조건이 하트 이중 지급을 막는 관문이다.
    assert "status=eq.pending" in str(patched[0].url)
    # 작업 본문의 두 값이 짝이 안 맞아도 남의 행에는 닿지 않는다.
    assert patched[0].url.params["profile_id"] == f"eq.{PROFILE_ID}"
    body = json.loads(patched[0].content)
    assert body["status"] == "ready"
    assert body["storage_path"].startswith(f"{PROFILE_ID}/")


def test_worker_marks_a_failure_without_paying_the_compensation_yet(monkeypatch):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    # pending 1 + failed 3 — 이번 실패로 4회째다.
    fake = _Fake(latest_attempt=_pending_attempt(), attempt_rows=[{"status": "pending"}] + _failed(3))

    response = _worker(fake, _openai(False))

    assert response.json() == {"status": "failed"}
    assert fake.granted_hearts == []


def test_worker_pays_the_compensation_on_the_fifth_failure(monkeypatch):
    """pending 은 건너뛰고 세야 한다 — 최신 행이 pending 이라 거기서 멈추면 카운트가 늘 0 이다."""
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    fake = _Fake(latest_attempt=_pending_attempt(), attempt_rows=[{"status": "pending"}] + _failed(4))

    response = _worker(fake, _openai(False))

    assert response.json() == {"status": "fallback"}
    assert len(fake.granted_hearts) == 1
    # 마지막 실패는 update 로 남고, 보상 행은 insert 로 따로 들어간다(이력 두 줄).
    assert fake.inserted_avatars == [
        {
            "profile_id": str(PROFILE_ID),
            "status": "ready",
            "storage_path": fake.inserted_avatars[0]["storage_path"],
            "is_fallback": True,
        }
    ]


def test_worker_skips_a_row_that_is_no_longer_pending(monkeypatch):
    """240초에 끊겼다가 늦게 깨어난 워커가 이미 정리된 행을 되살리면 안 된다."""
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    fake = _Fake(latest_attempt={**_pending_attempt(), "status": "failed"})

    response = _worker(fake, _openai(True))

    assert response.json() == {"status": "skipped"}
    assert fake.calls("PATCH", "/rest/v1/profile_avatars") == []
    # 유료 호출도 아낀다 — 여기서 멈추는 이유의 절반이다.
    assert fake.granted_hearts == []


def test_worker_pays_nothing_when_the_post_already_compensated(monkeypatch, caplog):
    """생성하는 60초 사이에 POST 가 그 행을 정리하고 먼저 보상할 수 있다(`queues pause` 를 오래 걸면 흔하다).

    시작할 때 본 것(①)은 그 경합을 못 막는다 — **기록할 때 행 수가 0 인지**가 진짜 관문이다.
    """
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})

    class _RaceFake(_Fake):
        def __call__(self, request):
            url = str(request.url)
            if (
                request.method == "PATCH"
                and "/rest/v1/profile_avatars" in url
                and "id" in request.url.params
            ):
                self.requests.append(request)
                return httpx.Response(200, json=[])  # 그 사이 누군가 먼저 처리했다
            return super().__call__(request)

    fake = _RaceFake(latest_attempt=_pending_attempt(), attempt_rows=[{"status": "pending"}] + _failed(4))

    response = _worker(fake, _openai(False))

    assert response.status_code == 200
    assert response.json() == {"status": "skipped"}
    assert fake.granted_hearts == []
    assert fake.inserted_avatars == []


def test_worker_leaves_an_orphan_image_alone_and_says_so(monkeypatch, caplog):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})

    class _RaceFake(_Fake):
        def __call__(self, request):
            url = str(request.url)
            if (
                request.method == "PATCH"
                and "/rest/v1/profile_avatars" in url
                and "id" in request.url.params
            ):
                self.requests.append(request)
                return httpx.Response(200, json=[])
            return super().__call__(request)

    fake = _RaceFake(latest_attempt=_pending_attempt())

    with caplog.at_level("WARNING", logger="app.profile_onboarding.tasks_router"):
        assert _worker(fake, _openai(True)).json() == {"status": "skipped"}

    # 지우러 가지 않는다 — 드물고, 지우다 실패하면 워커만 복잡해진다. 사람이 찾을 수 있게 경로만 남긴다.
    assert any("고아" in r.getMessage() for r in caplog.records)
    assert fake.calls("DELETE", "/storage/v1/object/avatars/") == []


def test_worker_fails_the_row_when_the_source_photo_is_gone(monkeypatch):
    _verifies(monkeypatch, {"email": SERVICE_ACCOUNT, "email_verified": True})
    fake = _Fake(latest_attempt=_pending_attempt(), source_path=None)

    response = _worker(fake, _openai(True))

    assert response.json() == {"status": "failed"}
    assert json.loads(fake.calls("PATCH", "/rest/v1/profile_avatars")[0].content)["status"] == "failed"
