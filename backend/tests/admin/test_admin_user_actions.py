"""관리자 하트 조정 · 전화/카톡 열람(설계 10-18 §8-3, 계획서 2026-10-18-admin-users-billing Task 4)."""
import json
import logging

import pytest

from admin_world import ADMIN, STRANGER, bearer, user_profile

U1 = "11111111-0000-0000-0000-000000000001"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
PHONE = "01012345678"
KAKAO = "kakao_secret_id"
PHONE_KEY = "phone-key-test"
ROUTES = [
    (f"/admin/users/{U1}/hearts", {"amount": 50, "reason": "오류 보상"}),
    (f"/admin/users/{U1}/private", {"reason": "신고 대응"}),
]


def _world(world, status: str = "active") -> None:
    world.user_profiles[U1] = user_profile(U1, "닉네임A", status=status)
    world.rpc_results["admin_adjust_hearts"] = {"id": U1, "amount": 50, "heart_balance": 60, "action_id": "a1"}
    world.phone, world.kakao_id = PHONE, KAKAO


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_hearts_and_private_are_behind_the_admin_gate(client, world, url, body, who, headers, status, detail):
    _world(world)
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.post(url, headers=headers, json=body)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == [] and world.actions == []
    assert world.calls("POST", "/rest/v1/rpc/decrypt_phone_number") == []


# 하트 조정 ------------------------------------------------------------------------

def test_hearts_sends_the_signed_amount_reason_and_ip_to_one_db_function(client, world):
    _world(world)

    response = client.post(f"/admin/users/{U1}/hearts", json={"amount": -20, "reason": "  잘못 지급  "},
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    assert response.status_code == 200
    assert response.json() == {"id": U1, "amount": 50, "heart_balance": 60, "action_id": "a1"}  # DB 함수 결과 그대로
    assert world.rpcs == [("admin_adjust_hearts", {
        "p_admin": ADMIN, "p_profile": U1, "p_amount": -20, "p_reason": "잘못 지급", "p_ip": "203.0.113.7"})]
    # 서버가 원장 · 잔액 · 작업 기록을 따로 쓰지 않는다(한 트랜잭션은 DB 함수 안).
    assert [r for r in world.requests if r.method in ("PATCH", "DELETE")] == [] and world.actions == []
    assert world.calls("POST", "/rest/v1/heart_transactions") == [] and world.calls("POST", "/rest/v1/entitlements") == []


@pytest.mark.parametrize("amount", [0, 1001, -1001, "50", 5.5, None, True])
def test_hearts_amount_must_be_a_nonzero_integer_within_the_limit(client, world, amount):
    _world(world)

    assert client.post(f"/admin/users/{U1}/hearts", json={"amount": amount, "reason": "사유"}, headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


def test_hearts_accepts_exactly_the_limit_both_ways(client, world):
    _world(world)

    assert client.post(f"/admin/users/{U1}/hearts", json={"amount": 1000, "reason": "사유"}, headers=ADMIN_HEADERS).status_code == 200
    assert client.post(f"/admin/users/{U1}/hearts", json={"amount": -1000, "reason": "사유"}, headers=ADMIN_HEADERS).status_code == 200


@pytest.mark.parametrize("reason", [None, "", "   ", "가" * 501])
def test_hearts_reason_is_required(client, world, reason):
    _world(world)

    body = {"amount": 5} if reason is None else {"amount": 5, "reason": reason}
    assert client.post(f"/admin/users/{U1}/hearts", json=body, headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


@pytest.mark.parametrize(("code", "message", "status", "detail"), [
    ("CM409", "insufficient hearts", 409, "insufficient_hearts"),
    ("CM409", "profile withdrawn", 409, "account_withdrawn"),
    ("CM404", "profile not found", 404, "not_found"),
    ("22023", "invalid heart adjustment", 422, None),
    ("42501", "not admin", 403, "not_admin"),
])
def test_hearts_maps_the_db_function_errors(client, world, code, message, status, detail):
    _world(world)
    world.rpc_error_code, world.rpc_error_message = code, message

    response = client.post(f"/admin/users/{U1}/hearts", json={"amount": 50, "reason": "사유"}, headers=ADMIN_HEADERS)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail


# 전화 · 카톡 열람 -----------------------------------------------------------------

def test_private_view_records_first_and_never_stores_values(client, world, caplog):
    caplog.set_level(logging.DEBUG)
    _world(world)

    response = client.post(f"/admin/users/{U1}/private", json={"reason": "  신고 대응  "},
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    assert response.status_code == 200
    assert response.json() == {"phone_number": PHONE, "kakao_id": KAKAO}
    # 열람 기록이 복호화보다 먼저다 — 기록 없는 열람은 없다.
    order = [(r.method, r.url.path) for r in world.requests]
    assert order.index(("POST", "/rest/v1/admin_actions")) < order.index(("POST", "/rest/v1/rpc/decrypt_phone_number"))
    assert order.index(("POST", "/rest/v1/admin_actions")) < order.index(("POST", "/rest/v1/rpc/decrypt_profile_private"))
    # 기록에는 "열람했다" 와 사유 · ip 뿐이다.
    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "profile_private_view", "target_type": "profile", "target_id": U1,
        "before": None, "after": None, "reason": "신고 대응", "ip": "203.0.113.7",
    }]
    for secret in (PHONE, KAKAO, PHONE_KEY):
        assert secret not in json.dumps(world.actions) and secret not in caplog.text
        assert not any(secret in str(r.url) for r in world.requests)  # 키 · 값은 URL(접근 로그)에 없다
    # 복호화 키는 JSON 본문으로만 DB 에 간다.
    decrypt = world.calls("POST", "/rest/v1/rpc/decrypt_phone_number")[0]
    assert json.loads(decrypt.content) == {"p_profile_id": U1, "p_key": PHONE_KEY}


def test_private_view_response_must_not_be_cached(client, world):
    _world(world)

    response = client.post(f"/admin/users/{U1}/private", json={"reason": "신고 대응"}, headers=ADMIN_HEADERS)

    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"


def test_private_view_reads_nothing_when_the_record_fails(client, world):
    _world(world)
    world.action_insert_status = 500

    response = client.post(f"/admin/users/{U1}/private", json={"reason": "신고 대응"}, headers=ADMIN_HEADERS)

    assert response.status_code == 500 and PHONE not in response.text
    assert world.calls("POST", "/rest/v1/rpc/decrypt_phone_number") == []
    assert world.calls("POST", "/rest/v1/rpc/decrypt_profile_private") == []


def test_private_view_of_a_withdrawn_account_is_409_without_a_decrypt(client, world):
    _world(world, status="withdrawn")

    response = client.post(f"/admin/users/{U1}/private", json={"reason": "신고 대응"}, headers=ADMIN_HEADERS)

    assert response.status_code == 409 and response.json()["detail"] == "account_withdrawn"
    assert world.calls("POST", "/rest/v1/rpc/decrypt_phone_number") == [] and world.actions == []


def test_private_view_of_an_admin_or_a_missing_user_is_404_and_unrecorded(client, world):
    _world(world)
    world.user_profiles[ADMIN] = user_profile(ADMIN, "관리자")

    assert client.post(f"/admin/users/{ADMIN}/private", json={"reason": "x"}, headers=ADMIN_HEADERS).status_code == 404
    assert client.post("/admin/users/11111111-0000-0000-0000-0000000000ff/private", json={"reason": "x"},
                       headers=ADMIN_HEADERS).status_code == 404
    assert world.actions == [] and world.calls("POST", "/rest/v1/rpc/decrypt_phone_number") == []


def test_private_view_with_nothing_stored_is_still_200(client, world):
    _world(world)
    world.phone, world.kakao_id = None, None

    response = client.post(f"/admin/users/{U1}/private", json={"reason": "신고 대응"}, headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json() == {"phone_number": None, "kakao_id": None}


@pytest.mark.parametrize("reason", [None, "", "   ", "가" * 501])
def test_private_view_reason_is_required(client, world, reason):
    _world(world)

    body = {} if reason is None else {"reason": reason}
    assert client.post(f"/admin/users/{U1}/private", json=body, headers=ADMIN_HEADERS).status_code == 422
    assert world.actions == []


def test_viewing_twice_records_twice(client, world):
    _world(world)

    for _ in range(2):
        client.post(f"/admin/users/{U1}/private", json={"reason": "신고 대응"}, headers=ADMIN_HEADERS)

    assert [a["action"] for a in world.actions] == ["profile_private_view"] * 2
