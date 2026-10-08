"""탈퇴 `POST /account/withdraw`(B3, 편차 3): DB 함수 한 번 + 뒤 단계 셋은 각각 best-effort."""
import json
import logging

import pytest

from account_world import AUTH, EMAIL, ME
from app.core import errors
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_email


def test_withdrawing_calls_the_db_function_with_the_email_hmac(client, world):
    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert world.withdraw_bodies == [{
        "p_profile_id": ME,
        "p_email_hmac": bytea_literal(hash_email("identity-key-test", EMAIL)),
        "p_key_version": IDENTITY_KEY_VERSION,
    }]
    # 해시는 학교 메일 인증 기록(school_email_claims)에서 service_role 키로 읽는다 — auth 의 email 은 더 읽지 않는다.
    lookup = world.calls("GET", "/rest/v1/school_email_claims")[0]
    assert lookup.headers["authorization"] == "Bearer service-key"
    assert lookup.url.params["profile_id"] == f"eq.{ME}"
    assert world.calls("GET", f"/auth/v1/admin/users/{ME}") == []
    assert world.profiles[ME]["status"] == "withdrawn"


def test_then_tokens_student_id_files_and_every_session_go(client, world):
    client.post("/account/withdraw", headers=AUTH)

    assert world.calls("DELETE", "/rest/v1/push_tokens")[0].url.params["profile_id"] == f"eq.{ME}"
    assert ME not in world.push_tokens
    assert world.files["student-id-temp"][ME] == []
    # 프로필 사진 · 아바타는 30일 정리 배치 몫이다.
    assert world.files["profile-photos"][ME] == ["a.png"]
    logout = world.calls("POST", "/auth/v1/logout")[0]
    assert logout.url.params["scope"] == "global"
    assert logout.headers["authorization"] == AUTH["Authorization"]
    assert logout.headers["apikey"] == "service-key"


def test_a_failing_later_step_neither_stops_the_others_nor_the_200(client, world, caplog):
    world.fail = {"DELETE /rest/v1/push_tokens", "DELETE /storage/v1/object/student-id-temp"}

    with caplog.at_level(logging.WARNING, logger="app.account.router"):
        response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert len(world.calls("POST", "/auth/v1/logout")) == 1
    assert ME in caplog.text


def test_a_db_failure_is_500_and_nothing_after_it_runs(client, world):
    """여기까지는 상태가 그대로라 앱이 다시 부르면 된다."""
    world.fail = {"POST /rest/v1/rpc/withdraw_account"}

    assert client.post("/account/withdraw", headers=AUTH).status_code == 500
    assert world.calls("DELETE", "/rest/v1/push_tokens") == []
    assert world.calls("POST", "/auth/v1/logout") == []


@pytest.mark.parametrize("trouble", ["500", "unreachable"])
def test_a_claims_read_failure_is_503_before_the_db_function(client, world, trouble):
    """해시를 못 읽은 채 NULL 로 탈퇴시키면 재가입 제한을 잃는다 — 진행하지 않는다(옛 '이메일 조회 실패 → 500' 자리)."""
    if trouble == "500":
        world.fail = {"GET /rest/v1/school_email_claims"}
    else:
        world.claims_unreachable = True

    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 503
    assert response.json()["detail"] == errors.AUTH_UNAVAILABLE
    assert world.withdraw_bodies == []
    assert world.profiles[ME]["status"] == "active"
    assert world.calls("POST", "/auth/v1/logout") == []
    assert world.kakao_unlinks == []


@pytest.mark.parametrize("auth_email", ["", None, "missing"])
def test_a_kakao_account_without_an_email_uses_the_claims_hash(client, world, auth_email):
    if auth_email == "missing":
        world.emails.pop(ME)
    else:
        world.emails[ME] = auth_email
    world.claims[ME] = {"school_email_hmac": bytea_literal(hash_email("identity-key-test", "kim@snu.ac.kr")),
                        "key_version": 2}

    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert world.withdraw_bodies == [{
        "p_profile_id": ME,
        "p_email_hmac": bytea_literal(hash_email("identity-key-test", "kim@snu.ac.kr")),
        "p_key_version": 2,
    }]


def test_an_account_before_the_school_email_withdraws_without_a_hash(client, world):
    world.claims.pop(ME)
    world.profiles[ME].update(school_email_verified_at=None)

    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    # 학교 메일을 쓴 적이 없으니 막을 메일도 없다 — DB 함수는 NULL 이면 signup_blocks 를 남기지 않는다.
    assert world.withdraw_bodies == [{"p_profile_id": ME, "p_email_hmac": None, "p_key_version": IDENTITY_KEY_VERSION}]
    assert world.profiles[ME]["status"] == "withdrawn"


def test_an_old_email_account_backfilled_into_claims_uses_the_claims_hash(client, world):
    """옛 학교 메일 OTP 가입자는 claims 에 provider=email 로 백필된다. auth 의 email 이 달라도 claims 해시를 쓴다."""
    world.emails[ME] = "Changed@Elsewhere.example"
    school = bytea_literal(hash_email("identity-key-test", EMAIL))

    client.post("/account/withdraw", headers=AUTH)

    assert world.withdraw_bodies[0]["p_email_hmac"] == school
    assert world.withdraw_bodies[0]["p_email_hmac"] != bytea_literal(
        hash_email("identity-key-test", "Changed@Elsewhere.example"))


def test_the_later_steps_still_run_for_an_account_without_claims(client, world):
    world.claims.pop(ME)
    world.settings_overrides = {"kakao_admin_key": "kakao-admin-test"}

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200
    assert ME not in world.push_tokens
    assert world.files["student-id-temp"][ME] == []
    assert len(world.kakao_unlinks) == 1
    assert len(world.calls("POST", "/auth/v1/logout")) == 1


def test_a_suspended_or_unverified_account_can_still_withdraw(client, world):
    """로그인만 본다(get_caller) — 정지 중 탈퇴는 무기한 제한이 되고(DB 함수), 학생증 전인 사람도 나갈 수 있어야 한다."""
    world.profiles[ME].update(status="suspended", student_verification="none", department=None)

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200


def test_an_account_before_the_school_email_can_still_withdraw(client, world):
    """소셜로 가입만 하고 학교 메일 전인 사람도 나갈 수 있어야 한다(학교 메일 관문은 get_verified_* 에만 있다)."""
    world.profiles[ME].update(school_email_verified_at=None, student_verification="none", department=None)

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200


def test_calling_again_after_withdrawal_is_401_with_the_header(client, world):
    client.post("/account/withdraw", headers=AUTH)

    again = client.post("/account/withdraw", headers=AUTH)

    assert again.status_code == 401
    assert again.headers["X-Account-Status"] == "withdrawn"
    assert len(world.withdraw_bodies) == 1


def test_the_email_and_its_hash_reach_neither_the_answer_nor_the_log(client, world, caplog):
    world.fail = {"DELETE /rest/v1/push_tokens", "POST /auth/v1/logout"}

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH)

    digest = hash_email("identity-key-test", EMAIL).hex()
    for text in (response.text, caplog.text):
        assert EMAIL.lower() not in text.lower()
        assert digest not in text
    # 원본 이메일은 DB 로도 가지 않는다 — 해시만 간다.
    assert EMAIL.lower() not in json.dumps(world.withdraw_bodies).lower()
