"""가입 동의(화면 02-c). 계획서 docs/superpowers/plans/2026-09-29-signup-consent.md Task 2."""
import json
from collections.abc import Callable
from datetime import datetime
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.consents.policy import CONSENT_VERSION
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
ALL = ["terms", "privacy"]
CURRENT_ROWS = [{"kind": k, "version": CONSENT_VERSION} for k in ALL]
NOW = datetime(2026, 9, 29, 21, 0, tzinfo=SEOUL)


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret="whsec_test",
            discord_webhook_url="https://discord.com/api/webhooks/test",
            google_cloud_project="campus-mate-test",
            openai_api_key="sk-test",
            phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


def _wire(
    consent_rows: list[dict],
    status: str | None = "pending",
    gate_row: dict | None = None,
) -> tuple[list[httpx.Request], TestClient]:
    """나간 요청 목록과 클라이언트를 돌려준다. user_consents 조회는 consent_rows 로 답한다."""
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "/rest/v1/user_consents" in url and request.method == "GET":
            return httpx.Response(200, json=consent_rows)
        if "/rest/v1/profiles" in url and request.method == "GET":
            select = request.url.params.get("select", "")
            if "student_verification" in select:
                return httpx.Response(200, json=[gate_row or {
                    "student_verification": "none", "department": None,
                    "universities": {"name": "서울대학교"}, "status": status}])
            return httpx.Response(200, json=[{"status": status}])
        return httpx.Response(201, json=[])

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return sent, TestClient(app)


def _writes(sent: list[httpx.Request], table: str) -> list[httpx.Request]:
    return [r for r in sent if f"/rest/v1/{table}" in str(r.url) and r.method != "GET"]


def test_submit_records_required_kinds_in_one_post_with_server_version():
    sent, client = _wire([])

    response = client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": ALL, "marketing": False})

    assert response.status_code == 200
    posts = _writes(sent, "user_consents")
    assert len(posts) == 1
    assert sorted(row["kind"] for row in json.loads(posts[0].content)) == sorted(ALL)
    assert {row["version"] for row in json.loads(posts[0].content)} == {CONSENT_VERSION}
    assert {row["profile_id"] for row in json.loads(posts[0].content)} == {str(PROFILE_ID)}
    # 빠르게 두 번 눌러도 같은 판은 한 번만 남는다(PK 충돌은 무시).
    assert posts[0].headers["Prefer"] == "resolution=ignore-duplicates"


def test_submit_missing_required_kind_is_400_without_writes():
    sent, client = _wire([])

    response = client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": ALL[:1], "marketing": True})

    assert response.status_code == 400
    assert response.json()["detail"] == errors.CONSENT_INCOMPLETE
    assert _writes(sent, "user_consents") == []
    assert _writes(sent, "notification_settings") == []


@pytest.mark.parametrize("kind", ["adult", "sensitive_religion", "overseas_transfer"])
def test_submit_unknown_or_retired_kind_is_422_without_writes(kind: str):
    # 종교 · 국외 이전은 09-29 결정으로 받지 않는다(enum 에만 남은 값).
    sent, client = _wire([])

    response = client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": [*ALL, kind], "marketing": False})

    assert response.status_code == 422
    assert _writes(sent, "user_consents") == []


def test_submit_with_marketing_turns_marketing_on_with_server_time():
    sent, client = _wire([])

    client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": ALL, "marketing": True})

    [write] = _writes(sent, "notification_settings")
    body = json.loads(write.content)
    assert body["profile_id"] == str(PROFILE_ID)
    assert body["marketing"] is True
    # 동의 시각은 서버가 적는다 — 앱이 보낸 값이 아니라 get_now.
    assert datetime.fromisoformat(body["marketing_consented_at"]) == NOW


def test_submit_without_marketing_leaves_existing_marketing_choice_alone():
    # 재동의에서 마케팅을 안 켰다고 이미 받은 수신 동의를 끄지 않는다(끄기는 16d).
    sent, client = _wire(CURRENT_ROWS)

    client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": ALL, "marketing": False})

    assert _writes(sent, "notification_settings") == []


def test_withdrawn_account_cannot_submit():
    sent, client = _wire([], status="withdrawn")

    response = client.post("/me/consents", headers=AUTH_HEADERS, json={"agreed": ALL, "marketing": False})

    assert response.status_code == 401
    assert _writes(sent, "user_consents") == []


@pytest.mark.parametrize(
    ("rows", "expected"),
    [([], "none"), ([{"kind": k, "version": "2000-01-01"} for k in ALL], "outdated"), (CURRENT_ROWS, "current")],
)
def test_verification_status_reports_consent_state(rows: list[dict], expected: str):
    _, client = _wire(rows)

    response = client.get("/me/verification-status", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json()["consent"] == expected


def test_student_verification_upload_is_403_before_consent():
    # 동의 전에는 실명 · 학생증 사진을 받지 않는다 — Storage · Vision 까지 가면 안 된다.
    sent, client = _wire([])

    response = client.post(
        "/student-verification",
        headers=AUTH_HEADERS,
        data={"real_name": "홍길동"},
        files={"photo": ("id.jpg", b"\xff\xd8\xff" + b"x" * 16, "image/jpeg")},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == errors.CONSENT_REQUIRED
    # 정지 안내 화면으로 오인되지 않게 계정 상태 헤더를 싣지 않는다.
    assert "x-account-status" not in response.headers
    assert not any("/storage/v1/" in str(r.url) for r in sent)


def test_next_step_is_403_before_consent():
    _, client = _wire([], gate_row={"student_verification": "verified", "department": "컴퓨터공학과",
                                    "universities": {"name": "서울대학교"}, "status": "active",
                                    # 학교 메일까지 마친 사람이 새 판 약관을 아직 안 받은 경우(재동의).
                                    "school_email_verified_at": "2026-10-01T00:00:00+00:00"})

    response = client.get("/profile-onboarding/next-step", headers=AUTH_HEADERS)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.CONSENT_REQUIRED
