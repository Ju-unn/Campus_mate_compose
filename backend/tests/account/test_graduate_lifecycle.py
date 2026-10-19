"""졸업생 인증이 탈퇴 · 14일 정리와 만나는 곳: 신청 중인 졸업생은 지워지지 않고, 탈퇴하면 신청 · 사진이 남지 않고,
졸업생 탈퇴의 재가입 제한은 학번 해시로 걸린다."""
import logging

import pytest

from account_world import AUTH, BUCKETS, ME
from app.core import errors
from app.signup_policy import IDENTITY_KEY_VERSION

SCHEDULER_TOKEN = {"Authorization": "Bearer id-token"}
UNVERIFIED = "44444444-4444-4444-4444-444444444444"
STUDENT_HMAC = "\\x" + "ab" * 32


def _pending(profile_id: str, rid: str = "req-1") -> dict:
    return {"id": rid, "profile_id": profile_id, "status": "pending", "reason": None, "student_hmac": None,
            "key_version": 1, "photo_path": f"{profile_id}/{rid}.jpg", "ocr_document_number": "AB12CD34",
            "ocr_school_text": "서울대학교", "previous_school_email": "old@prev.ac.kr"}


def _approved(profile_id: str, student_hmac: str | None = STUDENT_HMAC, key_version: int = 1) -> dict:
    return {"id": "req-ok", "profile_id": profile_id, "status": "approved", "reason": None, "student_hmac": student_hmac,
            "key_version": key_version, "photo_path": None}


# 14일 정리 ------------------------------------------------------------------------------

def test_cleanup_keeps_accounts_with_open_graduate_request(client, world):
    # SQL 후보 목록이 거르지만(Task 1) 후보를 고른 뒤 신청이 들어오는 경쟁이 있다 — 지우기 직전 재확인이 건너뛴다.
    world.unverified(UNVERIFIED, days_ago=20)
    world.graduate_requests.append(_pending(UNVERIFIED))

    result = client.post("/batch/cleanup", headers=SCHEDULER_TOKEN).json()

    assert result["deleted_unverified"] == 0
    assert result["skipped_accounts"] == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED}") == []
    for bucket in BUCKETS:
        assert world.files[bucket][UNVERIFIED] == ["u.jpg"]


def test_cleanup_still_deletes_an_unverified_account_without_a_request(client, world):
    world.unverified(UNVERIFIED, days_ago=20)

    result = client.post("/batch/cleanup", headers=SCHEDULER_TOKEN).json()

    assert result["deleted_unverified"] == 1
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED}")) == 1


def test_cleanup_empties_the_graduate_bucket_too(client, world):
    world.unverified(UNVERIFIED, days_ago=20)

    client.post("/batch/cleanup", headers=SCHEDULER_TOKEN)

    assert len(BUCKETS) == 5 and "graduate-cert-temp" in BUCKETS
    assert world.files["graduate-cert-temp"][UNVERIFIED] == []
    listed = {r.url.path.rsplit("/", 1)[1] for r in world.requests if r.url.path.startswith("/storage/v1/object/list/")}
    assert "graduate-cert-temp" in listed


# 탈퇴 -----------------------------------------------------------------------------------

def test_withdraw_cancels_open_request_and_empties_bucket(client, world):
    world.graduate_requests.append(_pending(ME))
    world.files["graduate-cert-temp"][ME] = ["req-1.jpg"]

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200

    request = world.graduate_requests[0]
    assert (request["status"], request["reason"]) == ("cancelled", "account_withdrawn")
    assert request["ocr_document_number"] is None and request["ocr_school_text"] is None
    assert request["previous_school_email"] is None
    assert world.files["graduate-cert-temp"][ME] == []


def test_withdraw_without_a_request_changes_nothing_in_the_graduate_table(client, world):
    # 취소는 status=eq.pending 조건의 한 번짜리 PATCH 라 대기가 없으면 아무 줄도 건드리지 않는다.
    world.graduate_requests.append(_approved(ME, student_hmac=None))

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200

    assert world.graduate_requests == [_approved(ME, student_hmac=None)]


def test_withdraw_of_graduate_passes_student_hash_to_signup_blocks(client, world):
    del world.claims[ME]  # 졸업생은 학교 메일 claims 가 없다
    world.graduate_requests.append(_approved(ME, key_version=1))

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200

    assert world.withdraw_bodies == [{"p_profile_id": ME, "p_email_hmac": STUDENT_HMAC, "p_key_version": 1}]


def test_withdraw_without_any_hash_has_no_rejoin_limit(client, world):
    # 학번을 안 넣고 승인된 졸업생(해시 없음) — 기존 동작: 제한 없음(null).
    del world.claims[ME]
    world.graduate_requests.append(_approved(ME, student_hmac=None))

    client.post("/account/withdraw", headers=AUTH)

    assert world.withdraw_bodies == [{"p_profile_id": ME, "p_email_hmac": None, "p_key_version": IDENTITY_KEY_VERSION}]


def test_withdraw_prefers_the_school_email_claim(client, world):
    world.graduate_requests.append(_approved(ME))

    client.post("/account/withdraw", headers=AUTH)

    assert world.withdraw_bodies[0]["p_email_hmac"] == world.claims[ME]["school_email_hmac"]
    assert world.calls("GET", "/rest/v1/graduate_verification_requests") == []


def test_withdraw_reading_graduate_claim_failure_is_503(client, world):
    # null 로 탈퇴시키면 학번 해시 재가입 제한을 잃는다 — 학교 메일 claims 읽기 실패와 같게 멈춘다.
    del world.claims[ME]
    world.fail = {"GET /rest/v1/graduate_verification_requests"}

    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 503
    assert response.json()["detail"] == errors.AUTH_UNAVAILABLE
    assert world.withdraw_bodies == []
    assert world.profiles[ME]["status"] == "active"


def test_withdraw_cancel_failure_neither_blocks_nor_fails_the_withdrawal(client, world, caplog):
    world.graduate_requests.append(_pending(ME))
    world.fail = {"PATCH /rest/v1/graduate_verification_requests"}

    with caplog.at_level(logging.WARNING, logger="app.account.router"):
        response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert world.profiles[ME]["status"] == "withdrawn"
    assert len(world.calls("POST", "/auth/v1/logout")) == 1
    assert "graduate_request" in caplog.text
    for secret in ("AB12CD34", "old@prev.ac.kr", ".jpg"):
        assert secret not in caplog.text
