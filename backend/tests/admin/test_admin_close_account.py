"""관리자 탈퇴 대행 close-account(설계 10-18 §8-3, 계획서 2026-10-18-admin-users-billing Task 5)."""
import json
import logging
from urllib.parse import parse_qs

import pytest

from admin_world import ADMIN, STRANGER, bearer, user_profile

U1 = "11111111-0000-0000-0000-000000000001"
URL = f"/admin/users/{U1}/close-account"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
BODY = {"reason": "본인 탈퇴 요청", "verified_by": "가입 메일로 답장을 받아 확인"}
HMAC = "\\x" + "ab" * 32
KAKAO_MEMBER = "4242424242"
KEY = "kakao-admin-test"
CLOSED = {"id": U1, "was_status": "active", "status": "withdrawn", "rejoin_blocked": "two_months"}
PUSH = ("DELETE", "/rest/v1/push_tokens")
FILES = ("POST", "/storage/v1/object/list/student-id-temp")
KAKAO = ("POST", "/v1/user/unlink")
CLOSE = ("POST", "/rest/v1/rpc/admin_close_account")
CLAIM = ("GET", "/rest/v1/school_email_claims")


def _world(world, *, kakao: bool = True) -> None:
    world.user_profiles[U1] = user_profile(U1, "닉네임A")
    world.claims = [{"profile_id": U1, "school_email_hmac": HMAC, "key_version": 1}]
    world.rpc_results["admin_close_account"] = CLOSED
    world.auth_users[U1] = {"id": U1, "email": "secret@gmail.com", "identities": [
        {"provider": "kakao" if kakao else "google", "identity_data": {"sub": KAKAO_MEMBER}}]}
    world.settings_overrides = {"kakao_admin_key": KEY}


def _order(world) -> list[tuple[str, str]]:
    return [(r.method, r.url.path) for r in world.requests]


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_close_account_is_behind_the_admin_gate(client, world, who, headers, status, detail):
    _world(world)
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.post(URL, headers=headers, json=BODY)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == [] and world.kakao_unlinks == []


# 순서: DB 함수가 바깥 호출보다 먼저 -----------------------------------------------------

def test_close_account_runs_the_db_function_before_any_outside_call(client, world):
    _world(world)

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.status_code == 200
    order = _order(world)
    assert order.index(CLAIM) < order.index(CLOSE) < min(order.index(PUSH), order.index(FILES), order.index(KAKAO))
    assert order[-1] == ("POST", "/rest/v1/admin_actions")  # 바깥 정리 결과 기록이 맨 마지막


def test_close_account_sends_the_claim_hash_and_trimmed_fields_to_the_db_function(client, world):
    _world(world)

    client.post(URL, headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"},
                json={"reason": "  본인 탈퇴 요청  ", "verified_by": "  닉네임 확인  "})

    assert world.rpcs == [("admin_close_account", {
        "p_admin": ADMIN, "p_profile": U1, "p_email_hmac": HMAC, "p_key_version": 1, "p_reason": "본인 탈퇴 요청",
        "p_verified_by": "닉네임 확인", "p_ip": "203.0.113.7"})]


def test_close_account_without_a_school_email_claim_sends_null_and_the_current_key_version(client, world):
    _world(world)
    world.claims = []

    client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert world.rpcs[0][1]["p_email_hmac"] is None and world.rpcs[0][1]["p_key_version"] == 1


def test_close_account_claim_read_failure_is_503_and_changes_nothing(client, world):
    _world(world)
    world.table_status["/rest/v1/school_email_claims"] = 500

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.status_code == 503
    assert world.rpcs == [] and world.kakao_unlinks == [] and world.actions == []
    assert PUSH not in _order(world) and FILES not in _order(world)


# 입력 -----------------------------------------------------------------------------

def test_verified_by_with_an_at_sign_is_422(client, world, caplog):
    caplog.set_level(logging.DEBUG)
    _world(world)

    response = client.post(URL, headers=ADMIN_HEADERS, json={**BODY, "verified_by": "alice@campus.ac.kr 로 확인"})

    assert response.status_code == 422
    assert "alice" not in response.text and "alice" not in caplog.text  # 입력을 되돌리지 않는다
    assert world.rpcs == [] and world.actions == []


@pytest.mark.parametrize("body", [
    {"reason": "사유"}, {"reason": "사유", "verified_by": ""}, {"reason": "사유", "verified_by": "   "},
    {"reason": "사유", "verified_by": "가" * 201},
    {"verified_by": "확인"}, {"reason": "", "verified_by": "확인"}, {"reason": "   ", "verified_by": "확인"},
    {"reason": "가" * 501, "verified_by": "확인"},
])
def test_reason_and_verified_by_are_required(client, world, body):
    _world(world)

    assert client.post(URL, headers=ADMIN_HEADERS, json=body).status_code == 422
    assert world.rpcs == []


def test_verified_by_accepts_exactly_two_hundred_characters(client, world):
    _world(world)

    assert client.post(URL, headers=ADMIN_HEADERS, json={**BODY, "verified_by": "가" * 200}).status_code == 200


# DB 함수의 거절 ---------------------------------------------------------------------

@pytest.mark.parametrize(("code", "message", "status", "detail"), [
    ("CM409", "profile withdrawn", 409, "account_withdrawn"),
    ("CM404", "profile not found", 404, "not_found"),
    ("42501", "not admin", 403, "not_admin"),
])
def test_db_refusals_stop_before_any_outside_call(client, world, code, message, status, detail):
    _world(world)
    world.rpc_error_code, world.rpc_error_message = code, message

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.status_code == status and response.json()["detail"] == detail
    assert world.kakao_unlinks == [] and world.actions == []
    assert PUSH not in _order(world) and FILES not in _order(world)


def test_a_suspended_account_says_the_rejoin_block_is_forever(client, world):
    _world(world)
    world.rpc_results["admin_close_account"] = {**CLOSED, "was_status": "suspended", "rejoin_blocked": "forever"}

    body = client.post(URL, headers=ADMIN_HEADERS, json=BODY).json()

    assert body["was_status"] == "suspended" and body["rejoin_blocked"] == "forever"


# 바깥 정리 --------------------------------------------------------------------------

def test_a_clean_close_reports_every_step_and_what_cannot_be_done(client, world):
    _world(world)

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.json() == {
        **CLOSED, "cleanup": {"push_tokens": "ok", "student_id_files": "ok", "kakao_unlink": "ok"},
        "not_done": ["apple_revoke", "logout_everywhere"],
    }
    [unlink] = world.kakao_unlinks
    assert unlink.headers["authorization"] == f"KakaoAK {KEY}"
    assert parse_qs(unlink.content.decode()) == {"target_id_type": ["user_id"], "target_id": [KAKAO_MEMBER]}
    # 푸시 토큰은 그 사람 것만 지운다.
    assert world.calls("DELETE", "/rest/v1/push_tokens")[0].url.params["profile_id"] == f"eq.{U1}"
    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "account_close_cleanup", "target_type": "profile", "target_id": U1,
        "before": None, "after": {"push_tokens": "ok", "student_id_files": "ok", "kakao_unlink": "ok"},
        "reason": None, "ip": None,
    }]


def test_outside_cleanup_failure_still_closes_and_is_recorded(client, world, caplog):
    caplog.set_level(logging.DEBUG)
    _world(world)
    world.table_status["/rest/v1/push_tokens"] = 500
    world.table_status["/v1/user/unlink"] = 500

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.status_code == 200
    cleanup = {"push_tokens": "failed", "student_id_files": "ok", "kakao_unlink": "failed"}
    assert response.json()["cleanup"] == cleanup
    assert world.actions[-1]["action"] == "account_close_cleanup" and world.actions[-1]["after"] == cleanup
    for secret in (KAKAO_MEMBER, KEY, "secret@gmail.com"):
        assert secret not in response.text and secret not in json.dumps(world.actions) and secret not in caplog.text


@pytest.mark.parametrize(("kakao_account", "key", "expected"), [(False, KEY, "skipped"), (True, "", "skipped")])
def test_kakao_is_skipped_for_other_providers_or_without_the_key(client, world, kakao_account, key, expected):
    _world(world, kakao=kakao_account)
    world.settings_overrides = {"kakao_admin_key": key}

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.json()["cleanup"]["kakao_unlink"] == expected and world.kakao_unlinks == []


def test_a_failed_cleanup_record_still_returns_200(client, world):
    _world(world)
    world.action_insert_status = 500

    response = client.post(URL, headers=ADMIN_HEADERS, json=BODY)

    assert response.status_code == 200 and response.json()["status"] == "withdrawn"
