"""`POST /school-email/verify` — 임시 이메일 계정 토큰으로 학교 메일을 인증한다(지시문 05).

학교 메일의 증거는 오직 임시 계정 토큰의 이메일이다. 소셜 계정의 email_confirmed_at · 이메일은 보지 않는다.
옛 check · confirm 의 도메인 · 재가입 제한 · 다른 계정 검사(그 전에는 가입 직전 훅의 거절 시험)는 이 파일로 옮겼다.
"""
import logging

import httpx
import pytest

from app.core import errors
from app.signup_policy import bytea_literal, hash_email
from verify_world import (AUTH, IDENTITY_KEY, ME, NOW, OTHER, OTHER_TOKEN, SNU, TEMP, TEMP_TOKEN, VerifyWorld, settings,
                          temp_email_user)

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
    """옛 학교 메일 OTP 가입 계정이 이미 그 메일을 쓰면 DB 함수가 'email' 을 돌려준다(지시문 10 · DB PR 계약)."""
    world.claims[HMAC] = (OTHER, "email")

    response = _verify(client)

    assert response.status_code == 409
    assert response.json()["provider"] == "email"
    assert response.json()["detail"] == "이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요"


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


async def _run_delete_helper(world: VerifyWorld, temp_id: str = TEMP, caller_id: str = ME) -> None:
    from app.school_email.router import delete_temp_account

    client = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    await delete_temp_account(settings(), client, temp_id=temp_id, caller_id=caller_id, now=NOW)


async def test_the_delete_helper_deletes_a_fresh_profileless_temp_account():
    world = VerifyWorld()

    await _run_delete_helper(world)

    assert world.deleted_users == [TEMP]


async def test_the_delete_helper_never_deletes_the_caller():
    """① 6번 검사를 지나도 삭제 직전에 한 번 더 본다 — 호출한 사람의 id 면 부르지 않는다."""
    world = VerifyWorld()

    await _run_delete_helper(world, temp_id=ME, caller_id=ME)

    assert world.deleted_users == []
    assert world.calls("DELETE", f"/auth/v1/admin/users/{ME}") == []


async def test_the_caller_check_alone_stops_the_delete_even_for_a_temp_looking_caller():
    """① 만 단독으로 잡는다(지시문 14-3): 호출자가 방금 만든 프로필 없는 email 계정처럼 보여서 ② · ③ 은 통과해도,
    id 가 호출자와 같으면 지우지 않는다."""
    world = VerifyWorld()
    world.tokens["user-token"] = temp_email_user(user_id=ME)
    world.profiles.pop(ME)

    await _run_delete_helper(world, temp_id=ME, caller_id=ME)

    assert world.deleted_users == []
    assert world.calls("DELETE", f"/auth/v1/admin/users/{ME}") == []


@pytest.mark.parametrize("identities", [[{"provider": "email"}, {"provider": "kakao"}], [{"provider": "kakao"}], []])
async def test_the_delete_helper_rechecks_the_identities(identities):
    """② 삭제 직전에 관리자 API 로 다시 읽어 identities 가 정확히 email 하나인지 본다."""
    world = VerifyWorld()
    world.tokens[TEMP_TOKEN]["identities"] = identities

    await _run_delete_helper(world)

    assert world.deleted_users == []


@pytest.mark.parametrize("created_at", ["2026-10-08T02:00:00Z", None, "어제"])
async def test_the_delete_helper_rechecks_that_it_was_created_just_now(created_at):
    """③ 30분보다 오래됐거나 생성 시각을 못 읽으면 임시 계정이 아니다."""
    world = VerifyWorld()
    world.tokens[TEMP_TOKEN]["created_at"] = created_at

    await _run_delete_helper(world)

    assert world.deleted_users == []


async def test_the_delete_helper_rechecks_that_there_is_no_profile():
    world = VerifyWorld()
    world.profiles[TEMP] = {"status": "active", "school_email_verified_at": None}

    await _run_delete_helper(world)

    assert world.deleted_users == []


@pytest.mark.parametrize("trouble", ["admin", "profile"])
async def test_the_delete_helper_does_not_delete_when_a_recheck_cannot_be_read(trouble, caplog):
    world = VerifyWorld()
    if trouble == "admin":
        world.admin_get_status = 500
    else:
        world.unreadable_profiles = {TEMP}

    with caplog.at_level(logging.DEBUG):
        await _run_delete_helper(world)

    assert world.deleted_users == []
    assert "hong@snu.ac.kr" not in caplog.text.lower()


# 임시 계정이 아닌 실제 계정의 토큰(지시문 10 · 12) -------------------------------------------------
#
# 임시 연결로 signInWithOtp 를 한 학교 메일이 이미 있는 옛 이메일 가입 계정의 메일이면, 그 토큰의 주인은 새 임시 계정이
# 아니라 그 실제 계정이다(프로필 있음, 오래전 생성). DB 함수는 claims 행이 없는 기존 가입자를 막지 못하므로
# 서버가 여기서 막지 않으면 호출자가 남의 학교 메일로 인증되고, 그 실제 계정까지 지워진다.

OLD_EMAIL_USER = "99999999-9999-9999-9999-999999999999"
OLD_TOKEN = "old-email-account-token"


def _old_email_account(world: VerifyWorld, created_at: str = "2026-03-02T00:00:00Z", with_profile: bool = True) -> None:
    world.tokens[OLD_TOKEN] = temp_email_user(user_id=OLD_EMAIL_USER, created_at=created_at)
    if with_profile:
        world.profiles[OLD_EMAIL_USER] = {"status": "active", "university_id": SNU,
                                          "school_email_verified_at": "2026-03-02T00:00:00+00:00"}


def _assert_taken_by_an_email_account_and_untouched(response, world: VerifyWorld) -> None:
    assert response.status_code == 409
    assert response.json()["provider"] == "email"
    assert world.rpc_bodies == []
    assert world.calls("DELETE", f"/auth/v1/admin/users/{OLD_EMAIL_USER}") == []
    assert world.deleted_users == []


def test_a_real_old_email_account_token_is_409_and_never_deleted(client, world):
    _old_email_account(world)

    _assert_taken_by_an_email_account_and_untouched(_verify(client, OLD_TOKEN), world)


def test_a_temp_token_whose_owner_has_a_profile_is_409_even_if_new(client, world):
    _old_email_account(world, created_at="2026-10-08T02:58:00Z")

    _assert_taken_by_an_email_account_and_untouched(_verify(client, OLD_TOKEN), world)


def test_an_unreadable_profile_check_counts_as_a_profile(client, world):
    _old_email_account(world, created_at="2026-10-08T02:58:00Z", with_profile=False)
    world.unreadable_profiles = {OLD_EMAIL_USER}

    _assert_taken_by_an_email_account_and_untouched(_verify(client, OLD_TOKEN), world)


@pytest.mark.parametrize("created_at", ["2026-10-08T02:00:00Z", "2026-10-08T02:29:00Z", None, "모름"])
def test_an_email_account_older_than_30_minutes_is_409_and_never_deleted(client, world, created_at):
    _old_email_account(world, created_at=created_at, with_profile=False)

    _assert_taken_by_an_email_account_and_untouched(_verify(client, OLD_TOKEN), world)


def test_a_fresh_temp_account_still_verifies_and_is_deleted_once(client, world):
    assert _verify(client).status_code == 200
    assert world.deleted_users == [TEMP]
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{TEMP}")) == 1


def test_a_profile_appearing_right_before_the_delete_stops_it(client, world):
    """경쟁: DB 함수를 부른 뒤 임시 id 로 프로필이 막 생겼다면 지우지 않는다(삭제 직전 재확인)."""
    world.profile_appears_on_rpc = TEMP

    response = _verify(client)

    assert response.status_code == 200
    assert world.deleted_users == []


# 오류 응답의 기계용 code(앱 PR 과의 맞춤, 지시문 12-5) ------------------------------------------------------
#
# 앱은 문구가 아니라 code 로 가른다. 모양: {"detail": <문구>, "code": <코드>} (409 만 "provider" 가 더 붙는다).

def _expect(response, status_code: int, detail: str, code: str, **extra) -> None:
    assert response.status_code == status_code
    assert response.json() == {"detail": detail, "code": code, **extra}


def test_code_not_confirmed_for_a_refused_temp_token(client, world):
    world.auth_trouble[TEMP_TOKEN] = 401

    _expect(_verify(client), 403, "학교 메일 인증이 끝나지 않았어요", "SCHOOL_EMAIL_NOT_CONFIRMED")


def test_code_not_confirmed_for_a_social_token_in_the_temp_slot(client, world):
    _expect(_verify(client, OTHER_TOKEN), 403, "학교 메일 인증이 끝나지 않았어요", "SCHOOL_EMAIL_NOT_CONFIRMED")


def test_code_already_verified_from_the_profile(client, world):
    world.profiles[ME]["school_email_verified_at"] = "2026-10-01T00:00:00+00:00"

    _expect(_verify(client), 403, "이미 학교 메일 인증이 끝났어요", "SCHOOL_EMAIL_ALREADY_VERIFIED")


def test_code_already_verified_from_the_db(client, world):
    world.rpc_result = "already_verified"

    _expect(_verify(client), 403, "이미 학교 메일 인증이 끝났어요", "SCHOOL_EMAIL_ALREADY_VERIFIED")


def test_code_social_only(client, world):
    world.tokens["user-token"]["app_metadata"] = {"provider": "email"}

    _expect(_verify(client), 403, errors.SCHOOL_EMAIL_SOCIAL_ONLY, "SCHOOL_EMAIL_SOCIAL_ONLY")


def test_code_domain_not_allowed(client, world):
    world.tokens[TEMP_TOKEN] = temp_email_user("hong@unknown.ac.kr")

    _expect(_verify(client), 422, "등록되지 않은 학교 메일이에요", "SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED")


def test_code_rejoin_blocked(client, world):
    world.blocked_hmacs.add(HMAC)

    _expect(_verify(client), 422, "재가입이 제한된 메일이에요", "SCHOOL_EMAIL_REJOIN_BLOCKED")


@pytest.mark.parametrize("provider, label", [("kakao", "카카오"), ("google", "구글"), ("apple", "애플")])
def test_code_taken_by_a_social_account(client, world, provider, label):
    world.claims[HMAC] = (OTHER, provider)

    _expect(_verify(client), 409, f"이 메일은 {label}로 가입돼 있어요", "SCHOOL_EMAIL_TAKEN", provider=provider)


def test_code_taken_by_an_old_email_account_from_the_db(client, world):
    world.claims[HMAC] = (OTHER, "email")

    _expect(_verify(client), 409, "이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요", "SCHOOL_EMAIL_TAKEN",
            provider="email")


def test_code_taken_by_a_real_old_email_account_token(client, world):
    _old_email_account(world)

    _expect(_verify(client, OLD_TOKEN), 409, "이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요",
            "SCHOOL_EMAIL_TAKEN", provider="email")


def test_code_profile_not_found(client, world):
    world.rpc_result = "no_profile"

    _expect(_verify(client), 404, "프로필을 찾을 수 없어요", "PROFILE_NOT_FOUND")


@pytest.mark.parametrize("trouble", [503, 429, "unreachable"])
def test_code_auth_unavailable_on_the_temp_token(client, world, trouble):
    world.auth_trouble[TEMP_TOKEN] = trouble

    _expect(_verify(client), 503, "잠시 뒤 다시 시도해 주세요", "AUTH_UNAVAILABLE")


def test_code_auth_unavailable_while_reading_the_callers_provider(client, world):
    # 로그인 관문(get_current_user_id)은 지나고, verify 가 호출자 수단을 읽는 두 번째 호출에서 장애가 난 경우.
    calls = {"n": 0}
    original = world._auth_user

    def flaky(request):
        if request.headers.get("authorization") == AUTH["Authorization"]:
            calls["n"] += 1
            if calls["n"] == 2:
                return httpx.Response(503, json={"msg": "trouble"})
        return original(request)

    world._auth_user = flaky

    _expect(_verify(client), 503, "잠시 뒤 다시 시도해 주세요", "AUTH_UNAVAILABLE")
