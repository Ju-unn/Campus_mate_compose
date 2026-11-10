"""문의하기 `POST /inquiries`. 저장이 기준이다 — 메일 알림은 덤이라 실패해도 201 이다."""
import json

import pytest

from app.core import errors
from inquiry_world import ME, STRANGER, USER_AUTH, row

GOOD = {"reason": "bug", "body": "앱이 멈춰요", "reply_email": "me@example.com"}


def _post(client, **overrides):
    return client.post("/inquiries", json={**GOOD, **overrides}, headers=USER_AUTH)


def test_a_valid_inquiry_is_stored_as_new_and_returns_201_with_its_number(client, world):
    response = _post(client)

    assert response.status_code == 201
    stored = world.inquiries[0]
    assert response.json() == {"ok": True, "id": stored["id"]}
    assert (stored["profile_id"], stored["reason"], stored["body"], stored["reply_email"]) == (
        ME, "bug", "앱이 멈춰요", "me@example.com")
    # 상태 · 시각은 DB 기본값(new · now())이 채운다 — 서버가 보내지 않는다.
    assert set(json.loads(world.calls("POST", "/rest/v1/inquiries")[0].content)) == {
        "profile_id", "reason", "body", "reply_email"}


def test_the_body_and_email_are_stored_trimmed(client, world):
    _post(client, body="  앱이 멈춰요 \n", reply_email="  me@example.com ")

    assert world.inquiries[0]["body"] == "앱이 멈춰요"
    assert world.inquiries[0]["reply_email"] == "me@example.com"


def test_a_body_may_keep_its_inner_line_breaks(client, world):
    assert _post(client, body="첫 줄\n둘째 줄").status_code == 201
    assert world.inquiries[0]["body"] == "첫 줄\n둘째 줄"


def test_without_a_token_it_is_401(client, world):
    response = client.post("/inquiries", json=GOOD)

    assert response.status_code == 401
    assert response.json()["detail"] == errors.LOGIN_REQUIRED
    assert world.inquiries == []


def test_a_suspended_person_can_still_write_to_us(client, world):
    world.status = "suspended"

    assert _post(client).status_code == 201


def test_a_person_still_signing_up_can_write_to_us(client, world):
    """학교 메일 · 학과 관문을 거치지 않는다 — 관문 칸이 비어 있는 가입 중 계정도 문의할 수 있다."""
    world.status = "pending"

    assert _post(client).status_code == 201


def test_a_withdrawn_account_is_401_like_every_other_api(client, world):
    world.status = "withdrawn"

    assert _post(client).status_code == 401
    assert world.inquiries == []


def test_a_person_without_a_profile_row_is_stored_with_null_profile_id(client, world):
    """FK 실패로 500 이 나지 않는다 — profile_id 만 비워 저장한다(계정 번호는 메일 본문에 있다)."""
    world.profile_ids.discard(ME)

    response = _post(client)

    assert response.status_code == 201
    assert world.inquiries[0]["profile_id"] is None
    assert len(world.calls("POST", "/rest/v1/inquiries")) == 2  # FK 실패 → 비워서 한 번 더


# 하루 5건 ---------------------------------------------------------------------

def test_the_sixth_inquiry_of_the_day_is_429(client, world):
    for _ in range(5):
        assert _post(client).status_code == 201

    response = _post(client)

    assert response.status_code == 429
    assert response.json()["detail"] == errors.INQUIRY_DAILY_LIMIT
    assert len(world.inquiries) == 5


def test_the_day_starts_at_midnight_korean_time(client, world):
    """어제 밤 11시 59분(한국)에 보낸 5건은 오늘 몫이 아니다. 오늘 0시 이후 것만 센다."""
    world.inquiries = [row(f"00000000-0000-0000-0000-00000000000{i}", created_at="2026-11-09T14:59:00+00:00")
                       for i in range(5)]   # = 한국 11/09 23:59

    assert _post(client).status_code == 201
    count = world.calls("GET", "/rest/v1/inquiries")[0]
    assert count.url.params["created_at"] == "gte.2026-11-10T00:00:00+09:00"


def test_the_limit_is_per_person(client, world):
    world.inquiries = [row(f"00000000-0000-0000-0000-00000000000{i}", created_at="2026-11-10T01:00:00+09:00",
                           profile_id=STRANGER) for i in range(5)]

    assert _post(client).status_code == 201


def test_a_blocked_attempt_does_not_store_or_mail(client, world, smtp, password_settings):
    for _ in range(5):
        _post(client)
    smtp.sent.clear()

    assert _post(client).status_code == 429
    assert smtp.sent == []


# 입력 검증 ---------------------------------------------------------------------

@pytest.mark.parametrize("overrides", [
    {"reason": "nope"},
    {"reason": ""},
    {"body": ""},
    {"body": "   \n "},
    {"body": "가" * 1001},
    {"reply_email": ""},
    {"reply_email": "no-at-sign"},
    {"reply_email": "a@b"},
    {"reply_email": "a b@example.com"},
    {"reply_email": "me@example.com\nBcc: evil@example.com"},
    {"reply_email": "me@example.com\r\nBcc: evil@example.com"},
    {"reply_email": "me@example.com, evil@example.com"},
    {"reply_email": "<me@example.com>"},
    {"reply_email": "a" * 250 + "@b.cc"},
])
def test_bad_input_is_422_and_nothing_is_stored(client, world, overrides):
    response = _post(client, **overrides)

    assert response.status_code == 422
    assert world.inquiries == []
    assert world.calls("POST", "/rest/v1/inquiries") == []


def test_a_missing_field_is_422(client, world):
    assert client.post("/inquiries", json={"reason": "bug"}, headers=USER_AUTH).status_code == 422


def test_exactly_1000_characters_is_accepted(client, world):
    assert _post(client, body="가" * 1000).status_code == 201


def test_every_reason_is_accepted(client, world):
    for reason in ("account", "payment", "matching", "safety", "bug", "other"):
        world.inquiries.clear()
        assert _post(client, reason=reason).status_code == 201


def test_a_database_check_violation_is_422_not_500(client, world):
    world.insert_status, world.insert_code = 400, "23514"

    assert _post(client).status_code == 422
    assert len(world.calls("POST", "/rest/v1/inquiries")) == 1   # 23503(FK)가 아니면 다시 보내지 않는다


def test_a_non_ascii_reply_email_is_422(client, world):
    """re.ASCII 만으로는 [^...] 꼴 칸이 한글을 통과시킨다 — 비ASCII 는 따로 막아야 한다."""
    assert _post(client, reply_email="한글@예시.한국").status_code == 422
    assert world.inquiries == []


def test_a_nul_character_in_the_body_is_422_not_a_database_500(client, world):
    assert _post(client, body="앞\u0000뒤").status_code == 422
    assert world.calls("POST", "/rest/v1/inquiries") == []


def test_a_nul_character_in_the_reply_email_is_422(client, world):
    assert _post(client, reply_email="me\u0000@example.com").status_code == 422
    assert world.calls("POST", "/rest/v1/inquiries") == []
