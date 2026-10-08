"""`POST /school-email/check` — 앱이 인증코드를 **보내기 전에** 부르는 확인(소셜 로그인 전환).

학교 도메인 · 재가입 제한 검사는 원래 가입 직전 훅(tests/test_auth_hooks_router.py)에 있었다.
소셜 계정에는 학교 메일이 없어 훅에서 빼고 여기로 옮겼다 — 같은 내용을 이 자리에서 지킨다.
"""
import pytest

from app.core import errors
from app.signup_policy import bytea_literal, hash_email
from school_email_world import AUTH, IDENTITY_KEY, ME, OTHER


def _check(client, email: str = "hong@snu.ac.kr"):
    return client.post("/school-email/check", headers=AUTH, json={"email": email})


def test_a_registered_school_email_passes(client, world):
    response = _check(client)

    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_the_email_is_trimmed_and_lowercased_before_every_check(client, world):
    _check(client, "  Hong@SNU.ac.kr ")

    domain = world.calls("GET", "/rest/v1/university_email_domains")[0]
    assert domain.url.params["domain"] == "eq.snu.ac.kr"
    assert world.provider_lookups == [{"p_email": "hong@snu.ac.kr", "p_caller": ME}]


# 훅에서 옮겨 온 검사(옛 test_rejects_unknown_domain · test_rejects_blocked_email ·
# test_blocked_email_hash_uses_identity_key) -------------------------------------------------

def test_an_unregistered_domain_is_422(client, world):
    response = _check(client, "hong@unknown.ac.kr")

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN == "등록되지 않은 학교 메일이에요"
    # 도메인에서 멈춘다 — 뒤 검사는 부르지 않는다.
    assert world.calls("GET", "/rest/v1/signup_blocks") == []
    assert world.provider_lookups == []


def test_a_blocked_email_is_422(client, world):
    world.blocked_hmacs.add(bytea_literal(hash_email(IDENTITY_KEY, "hong@snu.ac.kr")))

    response = _check(client)

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_BLOCKED == "재가입이 제한된 메일이에요"
    assert world.provider_lookups == []


def test_the_block_hash_uses_the_identity_key(client, world):
    """재가입 차단 해시는 **신원 키**로 만든다(미결 41①).

    서명 키로 만들면 서명 키를 바꾸는 순간 저장된 해시가 전부 안 맞아 차단이 풀린다."""
    _check(client)

    expected = hash_email(IDENTITY_KEY, "hong@snu.ac.kr")
    asked = [r.url.params["email_hmac"] for r in world.calls("GET", "/rest/v1/signup_blocks")]
    assert asked == [f"eq.\\x{expected.hex()}"]
    assert hash_email("whsec_test", "hong@snu.ac.kr") != expected


# 다른 계정이 쓰는 메일 ------------------------------------------------------------------

@pytest.mark.parametrize("provider, label", [("kakao", "카카오"), ("google", "구글"), ("apple", "애플")])
def test_an_email_used_by_another_account_is_409_with_the_provider(client, world, provider, label):
    world.accounts["hong@snu.ac.kr"] = (OTHER, provider)

    response = _check(client)

    assert response.status_code == 409
    # 앱은 문구가 아니라 provider 로 가른다(문구는 디자인에서 바뀐다).
    assert response.json()["provider"] == provider
    assert response.json()["detail"] == f"이 메일은 {label}로 가입돼 있어요"


def test_an_email_account_from_before_social_login_is_409_too(client, world):
    world.accounts["hong@snu.ac.kr"] = (OTHER, "email")

    response = _check(client)

    assert response.status_code == 409
    assert response.json()["provider"] == "email"


def test_the_callers_own_account_does_not_count(client, world):
    world.accounts["hong@snu.ac.kr"] = (ME, "kakao")

    assert _check(client).status_code == 200


# 관문 ------------------------------------------------------------------------------

def test_signed_out_is_401(client, world):
    assert client.post("/school-email/check", json={"email": "hong@snu.ac.kr"}).status_code == 401


def test_a_suspended_account_is_403_with_the_status_header_before_any_check(client, world):
    world.profile["status"] = "suspended"

    response = _check(client, "hong@unknown.ac.kr")

    assert response.status_code == 403
    assert response.headers["X-Account-Status"] == "suspended"
    assert world.calls("GET", "/rest/v1/university_email_domains") == []


def test_before_consent_is_403_without_the_status_header(client, world):
    world.consented = False

    response = _check(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.CONSENT_REQUIRED
    assert "x-account-status" not in response.headers
    assert world.calls("GET", "/rest/v1/university_email_domains") == []


def test_a_withdrawn_account_is_401(client, world):
    world.profile["status"] = "withdrawn"

    response = _check(client)

    assert response.status_code == 401
    assert response.headers["X-Account-Status"] == "withdrawn"
