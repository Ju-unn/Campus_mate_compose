import logging
from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from app.account.social_unlink import unlink_kakao
from app.core import errors
from app.settings import Settings
from app.student_verification.current_user import fetch_auth_user, get_current_user_id, get_verified_user_id

USER_ID = "11111111-1111-1111-1111-111111111111"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co",
        supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test",
        discord_webhook_url="https://discord.com/api/webhooks/test",
        google_cloud_project="campus-mate-test",
        openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )


async def test_valid_token_returns_user_id():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = request.headers
        return httpx.Response(200, json={"id": USER_ID})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    user_id = await get_current_user_id(_settings(), client, authorization="Bearer valid-token")

    assert user_id == UUID(USER_ID)
    assert captured["url"] == "https://x.supabase.co/auth/v1/user"
    assert captured["headers"]["authorization"] == "Bearer valid-token"
    assert captured["headers"]["apikey"] == "service-key"


async def test_missing_authorization_header_returns_401():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200)))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization=None)

    assert exc_info.value.status_code == 401


@pytest.mark.parametrize("status", [400, 401, 403, 404])
async def test_supabase_refusing_the_token_is_401(status):
    # 만료 · 끊긴 세션 · 지워진 계정 — 앱은 토큰을 새로 받아 보고, 그래도 401 이면 로그인 화면으로 간다(A11).
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status)))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization="Bearer expired-token")

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == errors.SESSION_EXPIRED


@pytest.mark.parametrize("status", [429, 500, 502, 503, 504])
async def test_supabase_auth_trouble_is_503_not_a_sign_out(status):
    # Supabase 인증이 잠깐 못 받는 것은 이 로그인의 잘못이 아니다 — 401 이면 앱이 로그아웃시킨다(A11).
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status)))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == errors.AUTH_UNAVAILABLE


async def test_supabase_auth_unreachable_is_503():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("연결 실패")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.status_code == 503


@pytest.mark.parametrize("status", [429, 503])
async def test_auth_trouble_leaves_a_warning_with_the_status_but_not_the_token(status, caplog):
    # 503 은 앱이 조용히 다시 시도해서 사용자 신고로는 안 보인다 — 장애가 얼마나 잦았는지 로그로만 안다.
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status)))

    with caplog.at_level(logging.WARNING, logger="app.student_verification.current_user"):
        with pytest.raises(HTTPException):
            await get_current_user_id(_settings(), client, authorization="Bearer secret-token")

    assert [r.levelno for r in caplog.records] == [logging.WARNING]
    assert str(status) in caplog.text
    assert "secret-token" not in caplog.text


async def test_auth_unreachable_leaves_a_warning_with_the_error_kind(caplog):
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("연결 실패")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    with caplog.at_level(logging.WARNING, logger="app.student_verification.current_user"):
        with pytest.raises(HTTPException):
            await get_current_user_id(_settings(), client, authorization="Bearer secret-token")

    assert [r.levelno for r in caplog.records] == [logging.WARNING]
    assert "ConnectError" in caplog.text
    assert "secret-token" not in caplog.text


async def test_a_refused_token_is_not_logged_as_trouble(caplog):
    # 4xx 는 장애가 아니라 만료 — 매일 수없이 생긴다. 로그를 남기면 진짜 장애가 묻힌다.
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(401)))

    with caplog.at_level(logging.WARNING, logger="app.student_verification.current_user"):
        with pytest.raises(HTTPException):
            await get_current_user_id(_settings(), client, authorization="Bearer expired-token")

    assert caplog.records == []


# 조각 6: 정지 관문 ----------------------------------------------------------------

def _gate_client(gate_row: dict) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": USER_ID})
        return httpx.Response(200, json=[gate_row])

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_a_suspended_account_is_403_with_a_status_header():
    """403 은 학생증 · 학과 관문도 쓴다 — 앱이 문구를 비교하지 않고 정지를 가르게 헤더를 싣는다."""
    client = _gate_client({"student_verification": "verified", "department": "컴공", "status": "suspended"})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "이용이 제한된 계정이에요"
    assert exc_info.value.headers == {"X-Account-Status": "suspended"}


async def test_suspension_is_checked_before_the_student_id_gate():
    client = _gate_client({"student_verification": "pending", "department": None, "status": "suspended"})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == "이용이 제한된 계정이에요"


# 소셜 로그인 전환: 학교 메일 확인을 마친 사람(전은 아래 학교 메일 관문 시험이 본다).
VERIFIED_AT = "2026-10-01T00:00:00+00:00"


async def test_an_active_or_unknown_status_passes_the_gate():
    for row in ({"student_verification": "verified", "department": "컴공", "status": "active",
                 "school_email_verified_at": VERIFIED_AT},
                {"student_verification": "verified", "department": "컴공", "school_email_verified_at": VERIFIED_AT}):
        assert await get_verified_user_id(_settings(), _gate_client(row),
                                          authorization="Bearer valid-token") == UUID(USER_ID)


# 학교 메일 관문(소셜 로그인 전환) — 순서: 정지 → 동의 → 학교 메일 → 학생증 → 학과와 학번 ------------------

async def test_before_the_school_email_is_403_without_a_status_header():
    client = _gate_client({"student_verification": "verified", "department": "컴공", "status": "active",
                           "school_email_verified_at": None})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == errors.SCHOOL_EMAIL_REQUIRED
    assert not exc_info.value.headers


async def test_a_missing_school_email_column_is_treated_as_not_verified():
    """칸이 안 오면 확인 전으로 본다 — 열린 문이 되지 않게(정지 칸이 없을 때와 반대 규칙)."""
    client = _gate_client({"student_verification": "verified", "department": "컴공", "status": "active"})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == errors.SCHOOL_EMAIL_REQUIRED


async def test_suspension_is_checked_before_the_school_email():
    client = _gate_client({"student_verification": "verified", "department": "컴공", "status": "suspended",
                           "school_email_verified_at": None})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == errors.ACCOUNT_SUSPENDED


async def test_the_school_email_is_checked_before_the_student_id_and_the_department():
    client = _gate_client({"student_verification": "pending", "department": None, "status": "active",
                           "school_email_verified_at": None})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == errors.SCHOOL_EMAIL_REQUIRED


async def test_after_the_school_email_the_student_id_gate_answers():
    client = _gate_client({"student_verification": "pending", "department": None, "status": "active",
                           "school_email_verified_at": VERIFIED_AT})

    with pytest.raises(HTTPException) as exc_info:
        await get_verified_user_id(_settings(), client, authorization="Bearer valid-token")

    assert exc_info.value.detail == errors.STUDENT_VERIFICATION_REQUIRED


# fetch_auth_user(카카오 연결 끊기 · 학교 메일 verify 가 씀) — 인증 서비스 장애는 500 이 아니라 503 ---------------

@pytest.mark.parametrize("status", [429, 500, 502, 503, 504])
async def test_fetch_auth_user_turns_auth_trouble_into_503(status):
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status)))

    with pytest.raises(HTTPException) as exc_info:
        await fetch_auth_user(_settings(), client, "Bearer valid-token")

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == errors.AUTH_UNAVAILABLE


async def test_fetch_auth_user_turns_an_unreachable_auth_into_503():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("연결 실패")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    with pytest.raises(HTTPException) as exc_info:
        await fetch_auth_user(_settings(), client, "Bearer valid-token")

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == errors.AUTH_UNAVAILABLE


@pytest.mark.parametrize("status", [400, 401, 403, 404])
async def test_fetch_auth_user_leaves_other_4xx_as_a_status_error(status):
    """그 밖의 4xx 는 지금처럼 httpx 의 상태 오류다 — 부르는 쪽이 뜻을 정한다(verify 는 403, 탈퇴는 경고)."""
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status)))

    with pytest.raises(httpx.HTTPStatusError):
        await fetch_auth_user(_settings(), client, "Bearer refused-token")


async def test_fetch_auth_user_returns_the_user_and_sends_the_given_token():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"id": USER_ID, "identities": []})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    assert await fetch_auth_user(_settings(), client, "Bearer some-token") == {"id": USER_ID, "identities": []}
    assert str(seen[0].url) == "https://x.supabase.co/auth/v1/user"
    assert seen[0].headers["authorization"] == "Bearer some-token"
    assert seen[0].headers["apikey"] == "service-key"


async def test_the_kakao_unlink_step_gets_a_503_not_a_bare_http_error():
    """탈퇴의 카카오 단계가 인증 장애를 만나면 503 으로 올린다 — 탈퇴는 best-effort 단계라 그대로 끝난다."""
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(503)))
    settings = _settings().model_copy(update={"kakao_admin_key": "kakao-admin-test"})

    with pytest.raises(HTTPException) as exc_info:
        await unlink_kakao(settings, client, "Bearer valid-token")

    assert exc_info.value.status_code == 503
