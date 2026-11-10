"""POST /phone-verification/verify — 가장 최근 번호만 · 3분 · 5번 틀리면 잠금 · 비교는 compare_digest."""
import re

import pytest

import app.phone_verification.router as router_module
from app.signup_policy import bytea_literal, hash_phone
from phone_world import ME, USER_AUTH

PHONE = "010-0135-2468"
SEND = "/phone-verification/send"
VERIFY = "/phone-verification/verify"


def _send(client, sms) -> str:
    client.post(SEND, headers=USER_AUTH, json={"phone_number": PHONE})
    return re.search(r"\[(\d{6})\]", sms.sent[-1][1])[1]


def _wrong(code: str) -> str:
    return f"{(int(code) + 1) % 1_000_000:06d}"


def test_the_right_code_verifies_and_marks_that_row(client, world, sms):
    code = _send(client, sms)

    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert response.status_code == 200
    assert response.json() == {"verified": True}
    assert world.rows[0]["verified"] is True
    body = world.rpc_bodies("attempt_phone_verification")[0]
    assert body == {"p_profile_id": ME, "p_phone_hmac": bytea_literal(hash_phone("identity-key-test", "+821001352468")),
                    "p_phone_hmac_key_version": 1}


def test_a_wrong_code_tells_how_many_tries_are_left(client, world, sms):
    code = _send(client, sms)

    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": _wrong(code)})

    assert response.status_code == 400
    assert response.json() == {"detail": "인증번호가 맞지 않아요", "code": "phone_code_mismatch", "remaining_attempts": 4}
    assert world.rows[0]["verified"] is False


def test_five_wrong_codes_lock_until_a_new_code_is_sent(client, world, sms):
    code = _send(client, sms)
    replies = [client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": _wrong(code)})
               for _ in range(5)]
    after = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert [r.json().get("remaining_attempts") for r in replies[:4]] == [4, 3, 2, 1]
    locked = {"detail": "5번 틀렸어요, 인증번호를 다시 받아 주세요", "code": "phone_code_locked"}
    assert (replies[4].status_code, replies[4].json()) == (400, locked)
    assert (after.status_code, after.json()) == (400, locked)


def test_a_new_code_makes_the_old_one_useless(client, world, sms):
    old = _send(client, sms)
    world.cooldown_passes()
    new = _send(client, sms)
    stale_code = old if old != new else _wrong(new)  # 백만 분의 일로 같은 숫자가 나와도 시험이 흔들리지 않게

    stale = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": stale_code})
    fresh = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": new})

    assert stale.json()["code"] == "phone_code_mismatch"
    assert fresh.json() == {"verified": True}
    assert [r["verified"] for r in world.rows] == [False, True]


def test_an_expired_code_must_be_sent_again(client, world, sms):
    code = _send(client, sms)
    world.expire_all()

    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert response.status_code == 400
    assert response.json() == {"detail": "인증번호를 다시 받아 주세요", "code": "phone_code_expired"}


def test_verifying_without_any_code_sent_is_expired(client, world):
    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": "123456"})

    assert response.json()["code"] == "phone_code_expired"


def test_verifying_twice_stays_verified(client, world, sms):
    code = _send(client, sms)
    client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    again = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert (again.status_code, again.json()) == (200, {"verified": True})


def test_the_comparison_is_constant_time(client, world, sms, monkeypatch):
    seen = []
    real = router_module.hmac.compare_digest

    def spy(a, b):
        seen.append((type(a), type(b)))
        return real(a, b)

    monkeypatch.setattr(router_module.hmac, "compare_digest", spy)
    code = _send(client, sms)

    client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert seen == [(bytes, bytes)]


@pytest.mark.parametrize("code", ["12345", "1234567", "12345a", "", "１２３４５６"])
def test_a_code_that_is_not_six_ascii_digits_is_422_and_uses_no_try(client, world, code):
    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": PHONE, "code": code})

    assert response.status_code == 422
    assert world.calls("POST", "/rest/v1/rpc/attempt_phone_verification") == []


def test_verify_refuses_a_number_that_is_not_010(client, world):
    response = client.post(VERIFY, headers=USER_AUTH, json={"phone_number": "+1 415 555 0100", "code": "123456"})

    assert response.status_code == 400
    assert response.json()["code"] == "phone_number_invalid"
