"""`POST /school-email/verify` — 임시 이메일 계정 토큰으로 학교 메일을 인증한다(지시문 05).

학교 메일의 증거는 오직 임시 계정 토큰의 이메일이다. 소셜 계정의 email_confirmed_at · 이메일은 보지 않는다.
옛 check · confirm 의 도메인 · 재가입 제한 · 다른 계정 검사(그 전에는 가입 직전 훅의 거절 시험)는 이 파일로 옮겼다.
"""
import logging

import httpx
import pytest

from app.account.repository import SupabaseAdmin
from app.core import errors
from app.signup_policy import bytea_literal, hash_email
from verify_world import AUTH, IDENTITY_KEY, ME, OTHER, OTHER_TOKEN, SNU, TEMP, TEMP_TOKEN, settings, temp_email_user

HMAC = bytea_literal(hash_email(IDENTITY_KEY, "hong@snu.ac.kr"))


def _verify(client, token: str = TEMP_TOKEN):
    return client.post("/school-email/verify", headers=AUTH, json={"temp_access_token": token})


# 성공 ------------------------------------------------------------------------------

def test_a_confirmed_temp_school_account_verifies_the_caller(client, world):
    response = _verify(client)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert world.rpc_bodies == [{"p_profile": ME, "p_email_hmac": HMAC, "p_university": SNU, "p_provider": "kakao"}]
    assert world.profiles[ME]["university_id"] == SNU
    # 임시 계정은 관리자 API(service key)로 지운다. 호출한 사람은 절대 지우지 않는다.
    assert world.deleted_users == [TEMP]


def test_the_temp_account_is_read_with_its_own_token(client, world):
    _verify(client)

    [read] = world.temp_reads()
    assert read.headers["authorization"] == f"Bearer {TEMP_TOKEN}"
    assert read.headers["apikey"] == "service-key"


@pytest.mark.parametrize("provider", ["kakao", "google", "apple"])
def test_the_callers_social_provider_goes_to_the_db_function(client, world, provider):
    world.tokens["user-token"]["app_metadata"]["provider"] = provider

    assert _verify(client).status_code == 200
    assert world.rpc_bodies[0]["p_provider"] == provider


def test_case_and_spaces_in_the_school_email_give_the_same_hash(client, world):
    world.tokens[TEMP_TOKEN] = temp_email_user("  Hong@SNU.ac.kr ")

    assert _verify(client).status_code == 200
    assert world.calls("GET", "/rest/v1/university_email_domains")[0].url.params["domain"] == "eq.snu.ac.kr"
    assert world.rpc_bodies[0]["p_email_hmac"] == HMAC


@pytest.mark.parametrize("body", [{}, {"temp_access_token": ""}, {"temp_access_token": "   "}])
def test_a_missing_or_empty_temp_token_is_422(client, world, body):
    response = client.post("/school-email/verify", headers=AUTH, json=body)

    assert response.status_code == 422
    assert world.rpc_bodies == []


# 관문 1~4: 정지 → 동의 → 이미 인증 → 소셜 계정만 ------------------------------------------

def test_signed_out_is_401(client, world):
    assert client.post("/school-email/verify", json={"temp_access_token": TEMP_TOKEN}).status_code == 401


def test_a_withdrawn_account_is_401(client, world):
    world.profiles[ME]["status"] = "withdrawn"

    response = _verify(client)

    assert response.status_code == 401
    assert response.headers["X-Account-Status"] == "withdrawn"


def test_a_suspended_account_is_403_with_the_status_header_before_anything_else(client, world):
    world.profiles[ME].update(status="suspended", school_email_verified_at="2026-10-01T00:00:00+00:00")
    world.consented = False

    response = _verify(client)

    assert response.status_code == 403
    assert response.headers["X-Account-Status"] == "suspended"
    assert world.temp_reads() == []
    assert world.deleted_users == []


def test_before_consent_is_403_without_the_status_header(client, world):
    world.consented = False
    world.profiles[ME]["school_email_verified_at"] = "2026-10-01T00:00:00+00:00"

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.CONSENT_REQUIRED
    assert "x-account-status" not in response.headers
    assert world.temp_reads() == []


def test_an_already_verified_account_is_403(client, world):
    world.profiles[ME]["school_email_verified_at"] = "2026-10-01T00:00:00+00:00"

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_ALREADY_VERIFIED == "이미 학교 메일 인증이 끝났어요"
    assert world.temp_reads() == []
    assert world.deleted_users == []


@pytest.mark.parametrize("app_metadata", [{"provider": "email"}, {}, {"provider": "github"}])
def test_only_a_social_login_can_call_it(client, world, app_metadata):
    """임시 이메일 계정(provider=email) 자신은 이 API 를 못 쓴다. 수단을 못 읽어도 막는다."""
    world.tokens["user-token"]["app_metadata"] = app_metadata

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_SOCIAL_ONLY
    assert world.temp_reads() == []
    assert world.deleted_users == []


def test_sending_the_same_request_twice_is_already_verified_not_unconfirmed(client, world):
    """두 번째는 임시 계정이 이미 없어 토큰이 거절되지만, 이미 인증 관문(3번)이 먼저 걸린다."""
    assert _verify(client).status_code == 200

    again = _verify(client)

    assert again.status_code == 403
    assert again.json()["detail"] == errors.SCHOOL_EMAIL_ALREADY_VERIFIED
    assert len(world.rpc_bodies) == 1


# 5: 임시 토큰 읽기 -----------------------------------------------------------------------

@pytest.mark.parametrize("status", [401, 403])
def test_a_refused_temp_token_is_403_not_confirmed(client, world, status):
    world.auth_trouble[TEMP_TOKEN] = status

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_CONFIRMED == "학교 메일 인증이 끝나지 않았어요"
    assert world.deleted_users == []


def test_an_unknown_temp_token_is_403(client, world):
    assert _verify(client, "made-up-token").status_code == 403
    assert world.deleted_users == []


@pytest.mark.parametrize("trouble", [500, 502, 503, 429, "unreachable"])
def test_auth_trouble_on_the_temp_token_is_503(client, world, trouble):
    world.auth_trouble[TEMP_TOKEN] = trouble

    response = _verify(client)

    assert response.status_code == 503
    assert response.json()["detail"] == errors.AUTH_UNAVAILABLE
    assert world.deleted_users == []


# 6: 임시 계정 검사 — 어긋나면 403, 그리고 **지우지 않는다**(남의 계정일 수 있다) ----------------------

def test_a_social_token_in_the_temp_slot_is_refused_and_not_deleted(client, world):
    """다른 소셜 계정의 토큰을 임시 자리에 넣는 공격. 그 계정의 email_confirmed_at 은 채워져 있다."""
    response = _verify(client, OTHER_TOKEN)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_CONFIRMED
    assert world.deleted_users == []
    assert OTHER not in world.deleted_users


def test_the_callers_own_token_in_the_temp_slot_is_refused_and_not_deleted(client, world):
    # 호출한 사람이 이메일 identity 하나뿐인 계정처럼 보여도 id 가 같으면 거절이다.
    world.tokens["user-token"]["identities"] = [{"provider": "email", "identity_data": {}}]
    world.tokens["user-token"]["email"] = "hong@snu.ac.kr"

    response = _verify(client, "user-token")

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_CONFIRMED
    assert world.deleted_users == []
    assert world.rpc_bodies == []


@pytest.mark.parametrize("change", [
    {"identities": [{"provider": "email"}, {"provider": "kakao"}]},
    {"identities": [{"provider": "kakao"}]},
    {"identities": []},
    {"email_confirmed_at": None},
    {"email": ""},
    {"email": None},
])
def test_a_temp_account_that_is_not_exactly_a_confirmed_email_account_is_refused(client, world, change):
    world.tokens[TEMP_TOKEN].update(change)

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_CONFIRMED
    assert world.deleted_users == []
    assert world.rpc_bodies == []


# 7~8: 도메인 · 재가입 제한(옛 훅 → check 에서 옮겨 온 검사) — 결과가 정해졌으니 임시 계정은 지운다 ---------

def test_an_unregistered_domain_is_422_and_the_temp_account_goes(client, world):
    world.tokens[TEMP_TOKEN] = temp_email_user("hong@unknown.ac.kr")

    response = _verify(client)

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN == "등록되지 않은 학교 메일이에요"
    # 도메인에서 멈춘다 — 뒤 검사는 부르지 않는다.
    assert world.calls("GET", "/rest/v1/signup_blocks") == []
    assert world.rpc_bodies == []
    assert world.deleted_users == [TEMP]


def test_a_blocked_email_is_422_and_the_temp_account_goes(client, world):
    world.blocked_hmacs.add(HMAC)

    response = _verify(client)

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_BLOCKED == "재가입이 제한된 메일이에요"
    assert world.rpc_bodies == []
    assert world.deleted_users == [TEMP]


def test_the_block_hash_uses_the_identity_key(client, world):
    """재가입 차단 해시는 **신원 키**로 만든다(미결 41①).

    서명 키로 만들면 서명 키를 바꾸는 순간 저장된 해시가 전부 안 맞아 차단이 풀린다."""
    _verify(client)

    expected = hash_email(IDENTITY_KEY, "hong@snu.ac.kr")
    asked = [r.url.params["email_hmac"] for r in world.calls("GET", "/rest/v1/signup_blocks")]
    assert asked == [f"eq.\\x{expected.hex()}"]
    assert hash_email("whsec_test", "hong@snu.ac.kr") != expected


# 9: DB 함수 결과 ----------------------------------------------------------------------

@pytest.mark.parametrize("provider, label", [("kakao", "카카오"), ("google", "구글"), ("apple", "애플")])
def test_an_email_used_by_another_account_is_409_with_the_provider(client, world, provider, label):
    world.claims[HMAC] = (OTHER, provider)

    response = _verify(client)

    assert response.status_code == 409
    # 앱은 문구가 아니라 provider 로 가른다(문구는 디자인에서 바뀐다).
    assert response.json()["provider"] == provider
    assert response.json()["detail"] == f"이 메일은 {label}로 가입돼 있어요"
    assert world.deleted_users == [TEMP]


def test_an_email_account_from_before_social_login_is_409_too(client, world):
    """옛 학교 메일 OTP 가입 계정이 이미 그 메일을 쓰면 DB 함수가 'email' 을 돌려줄 수 있다(계약 밖, 대비)."""
    world.claims[HMAC] = (OTHER, "email")

    response = _verify(client)

    assert response.status_code == 409
    assert response.json()["provider"] == "email"


def test_the_callers_own_claim_does_not_count_as_another_account(client, world):
    world.claims[HMAC] = (ME, "kakao")

    assert _verify(client).status_code == 200


def test_already_verified_from_the_db_is_403(client, world):
    world.rpc_result = "already_verified"

    response = _verify(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_ALREADY_VERIFIED
    assert world.deleted_users == [TEMP]


def test_no_profile_from_the_db_is_404(client, world):
    world.rpc_result = "no_profile"

    response = _verify(client)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND
    assert world.deleted_users == [TEMP]


def test_a_db_failure_is_500_and_keeps_the_temp_account_for_a_retry(client, world):
    world.rpc_status = 500

    assert _verify(client).status_code == 500
    assert world.deleted_users == []


# 임시 계정 삭제 -------------------------------------------------------------------------

def test_a_failed_temp_delete_still_answers_200_and_logs_no_email_or_token(client, world, caplog):
    world.admin_delete_status = 500

    with caplog.at_level(logging.DEBUG):
        response = _verify(client)

    assert response.status_code == 200
    assert any(r.levelno == logging.WARNING for r in caplog.records)
    assert "hong@snu.ac.kr" not in caplog.text.lower()
    assert TEMP_TOKEN not in caplog.text


async def test_the_delete_helper_never_deletes_the_caller():
    """6번 검사를 지나도 삭제 직전에 한 번 더 본다 — 호출한 사람의 id 면 부르지 않는다."""
    from app.school_email.router import delete_temp_account

    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={})

    admin = SupabaseAdmin(settings(), httpx.AsyncClient(transport=httpx.MockTransport(handler)))

    await delete_temp_account(admin, temp_id=ME, caller_id=ME)
    assert seen == []

    await delete_temp_account(admin, temp_id=TEMP, caller_id=ME)
    assert [r.url.path for r in seen] == [f"/auth/v1/admin/users/{TEMP}"]
