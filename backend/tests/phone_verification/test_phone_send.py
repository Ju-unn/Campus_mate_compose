"""POST /phone-verification/send — 문자는 DB 함수가 issued 를 준 때에만 한 통 나간다(계획서 §4-2-1)."""
import asyncio
import hashlib
import hmac
import logging
import re

import httpx
import pytest

from app.core.deps import get_client, get_settings
from app.main import app
from app.phone_verification.sms import get_sms_sender
from app.signup_policy import bytea_literal, hash_phone
from phone_world import ME, PRODUCTION_URL, USER_AUTH, settings

PHONE = "010-0135-2468"
E164 = "+821001352468"
SEND = "/phone-verification/send"


def _code_of(text: str) -> str:
    return re.fullmatch(r"\[CampusMate\] 인증번호 \[(\d{6})\]을 입력해 주세요\.", text)[1]


def test_send_texts_one_six_digit_code_to_the_number(client, world, sms):
    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert response.status_code == 200
    assert response.json() == {"resend_after_seconds": 60, "expires_in_seconds": 180, "already_sent": False}
    assert len(sms.sent) == 1
    to, text = sms.sent[0]
    assert to == E164
    assert _code_of(text)


def test_send_stores_only_hashes_never_the_code(client, world, sms):
    client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    body = world.rpc_bodies("issue_phone_verification")[0]
    code = _code_of(sms.sent[0][1])
    assert body["p_profile_id"] == ME
    assert body["p_phone_hmac"] == bytea_literal(hash_phone("identity-key-test", E164))
    assert body["p_phone_hmac_key_version"] == 1
    expected = hmac.new(b"identity-key-test", f"phone-code:{E164}:{code}".encode(), hashlib.sha256).digest()
    assert body["p_code_hash"] == bytea_literal(expected)
    assert code not in str(body)


def test_send_passes_the_global_daily_limit_from_settings(client, world):
    app.dependency_overrides[get_settings] = lambda: settings(sms_daily_global_limit=7)

    client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert world.rpc_bodies("issue_phone_verification")[0]["p_daily_global_limit"] == 7


def test_global_daily_limit_defaults_to_three_hundred():
    assert settings().sms_daily_global_limit == 300


def test_codes_are_random_each_time(client, world, sms):
    for _ in range(5):
        client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})
        world.cooldown_passes()

    codes = {_code_of(text) for _, text in sms.sent}
    assert len(sms.sent) == 5 and len(codes) > 1


@pytest.mark.parametrize("phone_number", [
    "+1 415 555 0100",   # 해외 번호 — SMS 펌핑
    "+44 7700 900123",
    "011-123-4567",      # 옛 10자리 — 가입은 010 만
    "010-1234-5678",     # 한 줄 순서(가짜 번호)
    "010-1",
    "",
])
def test_send_refuses_anything_but_a_real_korean_010_number(client, world, sms, phone_number):
    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": phone_number})

    assert response.status_code == 400
    assert response.json() == {"detail": "올바른 휴대폰 번호를 입력해 주세요", "code": "phone_number_invalid"}
    assert world.calls("POST", "/rest/v1/rpc/issue_phone_verification") == []
    assert sms.sent == []


def test_send_accepts_the_contacts_app_plus82_form(client, sms):
    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": "+82 10-0135-2468"})

    assert response.status_code == 200
    assert sms.sent[0][0] == E164


def test_second_send_within_a_minute_is_already_sent_without_a_text(client, world, sms):
    client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})
    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert response.status_code == 200
    assert response.json() == {"resend_after_seconds": 42, "expires_in_seconds": 162, "already_sent": True}
    assert len(sms.sent) == 1


async def test_two_concurrent_sends_text_once(world, sms, http):
    """버튼 연타 · 두 기기 — DB 함수가 줄을 세워 두 번째는 already_sent 를 받고 문자는 한 통이다."""
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_sms_sender] = lambda: sms
    try:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as api:
            first, second = await asyncio.gather(
                api.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE}),
                api.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE}),
            )
    finally:
        app.dependency_overrides.clear()

    assert sorted(r.json()["already_sent"] for r in (first, second)) == [False, True]
    assert len(sms.sent) == 1


def test_number_in_use_by_another_account_is_409_without_a_text(client, world, sms):
    world.issue_result = {"result": "in_use", "verification_id": None, "retry_after_seconds": None,
                          "expires_in_seconds": None, "global_limit_reached": False}

    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 다른 계정에서 쓰는 번호예요", "code": "phone_number_in_use"}
    assert sms.sent == []


@pytest.mark.parametrize("limit", ["number_cooldown", "number_daily_limit", "account_daily_limit", "global_daily_limit"])
def test_every_limit_is_429_with_retry_after_and_no_text(client, world, sms, limit):
    world.issue_result = {"result": limit, "verification_id": None, "retry_after_seconds": 3600,
                          "expires_in_seconds": None, "global_limit_reached": False}

    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert response.status_code == 429
    assert response.json() == {"detail": "인증번호를 너무 많이 요청했어요, 잠시 후 다시 시도해 주세요",
                               "code": "phone_verification_rate_limited", "retry_after_seconds": 3600}
    assert response.headers["Retry-After"] == "3600"
    assert sms.sent == []


def test_a_failed_text_is_503_and_the_row_is_removed_so_it_does_not_eat_the_quota(world, http):
    class BrokenSender:
        async def send(self, to: str, text: str) -> bool:
            return False

    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_sms_sender] = lambda: BrokenSender()
    try:
        from fastapi.testclient import TestClient
        response = TestClient(app).post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json() == {"detail": "잠시 후 다시 시도해 주세요", "code": "sms_unavailable"}
    assert world.rows == []
    deleted = world.calls("DELETE", "/rest/v1/phone_verifications")
    assert len(deleted) == 1 and deleted[0].url.params["id"] == "eq.00000000-0000-0000-0000-000000000001"


def test_the_send_that_uses_the_last_global_slot_alerts_discord_once(client, world, sms):
    world.issue_result = {"result": "issued", "verification_id": "00000000-0000-0000-0000-000000000009",
                          "retry_after_seconds": 60, "expires_in_seconds": 180, "global_limit_reached": True}

    response = client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert response.status_code == 200
    assert len(sms.sent) == 1
    assert len(world.discord) == 1
    assert "300" in world.discord[0]
    # 디스코드에는 번호 · 인증번호를 싣지 않는다(COMMON §3).
    assert "0135" not in world.discord[0] and _code_of(sms.sent[0][1]) not in world.discord[0]


def test_an_ordinary_send_does_not_alert_discord(client, world):
    client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})

    assert world.discord == []


def test_the_fake_sender_is_refused_in_production(world, http, caplog):
    """운영 주소에서 SMS_PROVIDER=fake 면 문자도 줄도 없이 503 — 가짜 길로 누구도 인증하지 못한다."""
    app.dependency_overrides[get_settings] = lambda: settings(supabase_url=PRODUCTION_URL)
    app.dependency_overrides[get_client] = lambda: http
    try:
        from fastapi.testclient import TestClient
        with caplog.at_level(logging.ERROR):
            response = TestClient(app).post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["code"] == "sms_unavailable"
    assert world.calls("POST", "/rest/v1/rpc/issue_phone_verification") == []
    assert any("SMS_PROVIDER" in record.getMessage() for record in caplog.records)


def test_send_needs_a_signed_in_school_verified_account(client, world):
    response = client.post(SEND, json={"phone_number": PHONE})

    assert response.status_code == 401
    assert world.calls("POST", "/rest/v1/rpc/issue_phone_verification") == []
