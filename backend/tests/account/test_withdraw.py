"""탈퇴 `POST /account/withdraw`(B3, 편차 3): DB 함수 한 번 + 뒤 단계 셋은 각각 best-effort."""
import json
import logging

from account_world import AUTH, EMAIL, ME
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
    # 이메일은 auth admin 에서 service_role 키로 읽는다.
    lookup = world.calls("GET", f"/auth/v1/admin/users/{ME}")[0]
    assert lookup.headers["authorization"] == "Bearer service-key"
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


def test_an_email_lookup_failure_is_500_before_the_db_function(client, world):
    world.fail = {f"GET /auth/v1/admin/users/{ME}"}

    assert client.post("/account/withdraw", headers=AUTH).status_code == 500
    assert world.withdraw_bodies == []


def test_a_suspended_or_unverified_account_can_still_withdraw(client, world):
    """로그인만 본다(get_caller) — 정지 중 탈퇴는 무기한 제한이 되고(DB 함수), 학생증 전인 사람도 나갈 수 있어야 한다."""
    world.profiles[ME].update(status="suspended", student_verification="none", department=None)

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
