import json
from uuid import UUID

import httpx
import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings
from app.student_verification.router import fetch_verification_status

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
JPEG = b"\xff\xd8\xff" + b"fake-student-id-bytes"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


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
    yield
    app.dependency_overrides.clear()


def _wire(gate_row: dict, reject_reason: str | None = None) -> list[httpx.Request]:
    """목 트랜스포트를 라우터에 주입하고, 나간 요청 목록을 돌려준다."""
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "/rest/v1/student_verification_attempts" in url and request.method == "GET":
            return httpx.Response(200, json=[{"reject_reason": reject_reason}])
        # 여기 테스트는 이번 판 동의를 마친 사용자다(동의 전은 tests/consents).
        if "/rest/v1/user_consents" in url and request.method == "GET":
            return httpx.Response(200, json=[{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)])
        if "/rest/v1/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[gate_row])
        return httpx.Response(200, json=[])

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return sent


# 소셜 로그인 전환: 여기 사람은 학교 메일 확인을 마쳤다(전은 school_email_verified_at=None 으로 따로 본다).
SCHOOL_EMAIL_VERIFIED_AT = "2026-10-01T00:00:00+00:00"


def _gate_row(status: str = "none", department: str | None = None,
              school_email_verified_at: str | None = SCHOOL_EMAIL_VERIFIED_AT) -> dict:
    return {"student_verification": status, "department": department, "universities": {"name": "서울대학교"},
            "school_email_verified_at": school_email_verified_at}


# 졸업생 인증(졸업증명서)이 더한 새 칸. 옛 앱은 읽지 않는다 — 플래그 꺼짐 · 방법 미선택이면 아래 기본값이다.
_GRADUATE_FIELDS = {"graduate_enabled": False, "verification_method": None, "graduate": None}


def _old_app_fields(response) -> dict:
    """옛 앱이 읽는 다섯 칸. 새 칸은 기본값으로 따로 확인한다(값 · 이름이 옛 서버와 같아야 옛 앱이 안 깨진다)."""
    body = response.json()
    assert {key: body[key] for key in _GRADUATE_FIELDS} == _GRADUATE_FIELDS
    return {key: value for key, value in body.items() if key not in _GRADUATE_FIELDS}


def _calls(sent: list[httpx.Request], method: str, fragment: str) -> list[httpx.Request]:
    return [r for r in sent if r.method == method and fragment in str(r.url)]


# --- POST /student-verification 은 없앴다(학생증 제거 10-17, 설계 결정 9) ---------------------------


def test_submitting_a_student_id_is_no_longer_a_route():
    sent = _wire(_gate_row("none"))

    response = TestClient(app).post(
        "/student-verification", files={"photo": ("student-id.jpg", JPEG, "application/octet-stream")},
        data={"real_name": "홍길동"}, headers=AUTH_HEADERS,
    )

    assert response.status_code in (404, 405)
    assert "/student-verification" not in {r.path for r in app.routes if isinstance(r, APIRoute)}
    assert _calls(sent, "POST", "/storage/v1/") == []


# --- GET /me/verification-status --------------------------------------------


def _fetch_status(headers: dict = AUTH_HEADERS):
    return TestClient(app).get("/me/verification-status", headers=headers)


def test_status_verified_with_school_info():
    sent = _wire(_gate_row("verified", department="컴퓨터공학과"))

    response = _fetch_status()

    assert response.status_code == 200
    assert _old_app_fields(response) == {"status": "verified", "has_school_info": True, "reject_reason": None,
                                         "consent": "current", "school_email_verified": True}
    assert _calls(sent, "GET", "/student_verification_attempts") == []


def test_status_verified_without_school_info():
    _wire(_gate_row("verified", department=None))

    response = _fetch_status()

    assert _old_app_fields(response) == {"status": "verified", "has_school_info": False, "reject_reason": None,
                                         "consent": "current", "school_email_verified": True}


@pytest.mark.parametrize("student_id", ["none", "pending", "verified", "rejected"])
def test_old_app_contract_five_fields_and_the_status_is_always_verified(student_id):
    """옛 앱(빌드 15 · TF 16 · vc8)은 이 응답의 다섯 칸을 읽고 status != verified 면 학생증 화면(3b)으로 보낸다
    (frontend/lib/auth/model/http_verification_gate_repository.dart). DB 값과 상관없이 늘 verified · 사유 없음이다."""
    sent = _wire(_gate_row(student_id), reject_reason="사진이 흐려요")

    response = _fetch_status()

    assert response.status_code == 200
    assert _old_app_fields(response) == {"status": "verified", "has_school_info": False, "reject_reason": None,
                                         "consent": "current", "school_email_verified": True}
    assert _calls(sent, "GET", "/student_verification_attempts") == []


def test_status_says_when_the_school_email_is_not_verified_yet():
    """소셜로 막 가입한 사람(학교 메일 전)도 이 응답에 닿는다 — 앱이 학교 메일 화면으로 보낸다."""
    _wire(_gate_row("none", school_email_verified_at=None))

    response = _fetch_status()

    assert response.status_code == 200
    assert response.json()["school_email_verified"] is False
    # 옛 응답을 쓰는 앱이 아직 있다 — 기존 필드는 그대로 나간다.
    assert {"status", "has_school_info", "reject_reason", "consent"} <= response.json().keys()


def test_the_gate_order_is_written_down_on_the_status_endpoint():
    """앱이 이 응답으로 다음 화면을 고른다 — 순서를 문서로 고정한다."""
    assert "정지 → 동의 → 학교 메일 → 학과와 학번" in fetch_verification_status.__doc__


def test_a_login_only_api_turns_a_withdrawn_account_away_with_401_and_the_header():
    """get_caller(로그인만) 쪽도 탈퇴 계정은 막는다 — 상태 한 번 조회로 가른다(편차 1)."""
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "withdrawn"})

    response = _fetch_status()

    assert response.status_code == 401
    assert response.json()["detail"] == "탈퇴한 계정이에요"
    assert response.headers["X-Account-Status"] == "withdrawn"


def test_a_login_only_api_still_answers_a_suspended_account():
    """정지는 get_caller 에서 막지 않는다(그대로) — 정지 안내 화면과 탈퇴가 이 문으로 들어온다."""
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "suspended"})

    assert _fetch_status().status_code == 200


def test_status_returns_401_without_authorization_header():
    sent = _wire(_gate_row("none"))

    response = _fetch_status(headers={})

    assert response.status_code == 401
    assert _calls(sent, "GET", "/rest/v1/profiles") == []


# --- POST /school-info -------------------------------------------------------


def _post_school_info(headers: dict = AUTH_HEADERS):
    return TestClient(app).post(
        "/school-info",
        json={"department": "컴퓨터공학과", "student_number": "2021123456"},
        headers=headers,
    )


@pytest.mark.parametrize("student_id", ["none", "pending", "verified", "rejected"])
def test_school_info_saves_whatever_the_student_id_state(student_id):
    sent = _wire(_gate_row(student_id))

    response = _post_school_info()

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    patch = _calls(sent, "PATCH", "/rest/v1/profiles")[0]
    assert json.loads(patch.content) == {"major": "컴퓨터공학과", "student_number": "2021123456"}
    assert dict(patch.url.params) == {"id": f"eq.{PROFILE_ID}"}


def test_school_info_is_403_with_the_status_header_for_a_suspended_account():
    # 결정 9(B6, 10-01): 정지 계정은 학과 · 학번을 저장하지 못한다. 앱은 헤더로 정지 안내 화면을 띄운다.
    sent = _wire({**_gate_row("verified"), "status": "suspended"})

    response = _post_school_info()

    assert response.status_code == 403
    assert response.json()["detail"] == errors.ACCOUNT_SUSPENDED
    assert response.headers["X-Account-Status"] == "suspended"
    assert _calls(sent, "PATCH", "/rest/v1/profiles") == []


@pytest.mark.parametrize("student_id", ["none", "verified"])
def test_school_info_is_403_before_the_school_email(student_id):
    sent = _wire(_gate_row(student_id, school_email_verified_at=None))

    response = _post_school_info()

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_REQUIRED
    assert _calls(sent, "PATCH", "/rest/v1/profiles") == []


def test_school_info_answers_a_suspended_account_before_the_school_email():
    _wire({**_gate_row("verified", school_email_verified_at=None), "status": "suspended"})

    assert _post_school_info().headers["X-Account-Status"] == "suspended"


def test_a_suspended_account_can_still_read_its_verification_status():
    # 결정 9: 인증 상태 조회는 열어 둔다 — 정지 안내 화면까지 가는 길이다.
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "suspended"})

    response = _fetch_status()

    assert response.status_code == 200
    assert response.json()["status"] == "verified"
