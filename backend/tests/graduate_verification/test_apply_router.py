import hashlib
import hmac
import json
import logging

import pytest
from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError

from applicant_world import AUTH, JPEG, PNG, PROFILE, request_row

URL = "/graduate-verification"
CERT_TEXT = "서울대학교 졸업증명서\n문서확인번호 : 1234-5678-9012-3456\n발급일 2024.02.20"
DOCUMENT_HMAC = hmac.new(b"identity-key-test", b"graduate-document|1234567890123456", hashlib.sha256).digest()


def _apply(client, *, photo=JPEG, agreed: str | None = "true", previous: str | None = None):
    data = {}
    if agreed is not None:
        data["agreed"] = agreed
    if previous is not None:
        data["previous_school_email"] = previous
    return client.post(URL, files={"photo": ("cert.jpg", photo, "application/octet-stream")}, data=data, headers=AUTH)


def _inserted(world) -> dict:
    return json.loads(world.calls("POST", "graduate_verification_requests")[0].content)


def test_apply_requires_login(client, world):
    assert client.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"}).status_code == 401


def test_apply_happy_path_runs_ocr_stores_hint_and_notifies_discord(client, world):
    world.set_ocr(CERT_TEXT)

    response = _apply(client)

    assert response.status_code == 201
    assert response.json() == {"state": "pending", "attempts_left": 2}
    body = _inserted(world)
    assert body["photo_path"] == f"{PROFILE}/{body['id']}.jpg"
    assert world.objects == {f"{PROFILE}/{body['id']}.jpg": JPEG}
    assert body["profile_id"] == PROFILE
    assert body["ocr_state"] == "read"
    assert body["ocr_document_number"] == "1234567890123456"
    assert body["ocr_school_text"] == "서울대학교"
    assert body["document_hmac"] == "\\x" + DOCUMENT_HMAC.hex()
    assert body["previous_school_email"] is None
    assert body["key_version"] == 1
    # 디스코드는 한 번, 본문에는 신청 id 와 profile_id 만.
    assert len(world.discord) == 1
    content = world.discord[0]["content"]
    assert PROFILE in content and body["id"] in content
    assert "1234567890123456" not in content and "서울대학교" not in content


def test_apply_stores_png_with_png_extension(client, world):
    assert _apply(client, photo=PNG).status_code == 201

    assert list(world.objects)[0].endswith(".png")


def test_apply_nothing_found_when_ocr_text_is_empty(client, world):
    assert _apply(client).status_code == 201

    body = _inserted(world)
    assert body["ocr_state"] == "nothing_found"
    assert body["ocr_document_number"] is None and body["ocr_school_text"] is None
    assert body["document_hmac"] is None


def test_apply_reads_school_but_no_number(client, world):
    world.set_ocr("서울대학교 졸업증명서")

    _apply(client)

    body = _inserted(world)
    assert (body["ocr_state"], body["ocr_document_number"], body["ocr_school_text"], body["document_hmac"]) == (
        "read", None, "서울대학교", None)


@pytest.mark.parametrize("scenario,status,code", [
    ("suspended", 403, None),
    ("no_consent", 403, None),
    ("flag_off", 403, "graduate_disabled"),
    ("no_agreed", 400, "consent_required"),
    ("agreed_false", 400, "consent_required"),
    ("bad_email", 400, "previous_email_invalid"),
    ("wrong_method", 403, "method_mismatch"),
    ("no_method", 403, "method_mismatch"),
    ("verified", 409, "already_verified"),
    ("pending", 409, "already_pending"),
    ("exhausted", 429, "attempts_exhausted"),
    ("not_a_photo", 400, "photo_unreadable"),
    ("too_big", 400, "photo_unreadable"),
])
def test_apply_validates_before_uploading(client, world, monkeypatch, scenario, status, code):
    photo, agreed, previous = JPEG, "true", None
    if scenario == "suspended":
        world.profile["status"] = "suspended"
    elif scenario == "no_consent":
        world.consented = False
    elif scenario == "flag_off":
        monkeypatch.delenv("GRADUATE_VERIFICATION_ENABLED")
    elif scenario == "no_agreed":
        agreed = None
    elif scenario == "agreed_false":
        agreed = "false"
    elif scenario == "bad_email":
        previous = "not-an-email"
    elif scenario == "wrong_method":
        world.profile["verification_method"] = "school_email"
    elif scenario == "no_method":
        world.profile["verification_method"] = None
    elif scenario == "verified":
        world.profile["school_email_verified_at"] = "2026-10-01T00:00:00+00:00"
    elif scenario == "pending":
        world.rows.append(request_row("pending", rid="p"))
    elif scenario == "exhausted":
        world.rows += [request_row("rejected", "unreadable", rid=f"r{i}", created_at=f"2026-10-2{i}T00:00:00+00:00")
                       for i in range(3)]
    elif scenario == "not_a_photo":
        photo = b"%PDF-1.7 not a photo"
    elif scenario == "too_big":
        photo = JPEG + b"x" * (10 * 1024 * 1024)

    response = _apply(client, photo=photo, agreed=agreed, previous=previous)

    assert response.status_code == status
    if code:
        assert response.json()["code"] == code
    assert world.objects == {} and world.calls("POST", "graduate_verification_requests") == []
    assert world.vision.batch_annotate_images.await_count == 0
    assert world.discord == []


def test_attempts_left_counts_this_new_pending_request(client, world):
    world.rows += [request_row("rejected", "unreadable", rid="a", created_at="2026-10-20T00:00:00+00:00"),
                   request_row("cancelled", "expired", rid="b", created_at="2026-10-10T00:00:00+00:00")]

    assert _apply(client).json() == {"state": "pending", "attempts_left": 1}


def test_apply_accepts_a_previous_email_without_checking_alias_or_domain(client, world):
    response = _apply(client, previous="  Old.Name+tag@Some-Unknown.example  ")

    assert response.status_code == 201
    assert _inserted(world)["previous_school_email"] == "old.name+tag@some-unknown.example"


def test_apply_treats_a_blank_previous_email_as_absent(client, world):
    assert _apply(client, previous="   ").status_code == 201

    assert _inserted(world)["previous_school_email"] is None


@pytest.mark.parametrize("error", [GoogleAPIError("quota"), RuntimeError("429"), TimeoutError(), GoogleAuthError("adc")])
def test_apply_survives_vision_failure(client, world, error):
    world.vision.batch_annotate_images.side_effect = error

    response = _apply(client)

    assert response.status_code == 201
    body = _inserted(world)
    assert body["ocr_state"] == "failed" and body["ocr_document_number"] is None and body["document_hmac"] is None
    assert len(world.objects) == 1


def test_apply_lets_our_own_bugs_surface_as_500_without_leaving_a_photo(world, client):
    world.vision.batch_annotate_images.side_effect = KeyError("bug")
    crashing = type(client)(client.app, raise_server_exceptions=False)

    response = crashing.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"}, headers=AUTH)

    assert response.status_code == 500
    assert world.objects == {} and world.calls("POST", "graduate_verification_requests") == []


def test_apply_rolls_back_photo_when_row_write_fails(world, client):
    world.fail_insert = True
    crashing = type(client)(client.app, raise_server_exceptions=False)

    response = crashing.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"}, headers=AUTH)

    assert response.status_code == 500
    assert world.objects == {}
    assert world.discord == []


def test_row_write_failure_with_failed_photo_delete_reports_the_orphan(world, client, caplog):
    world.fail_insert = True
    world.fail_delete = True
    crashing = type(client)(client.app, raise_server_exceptions=False)

    with caplog.at_level(logging.DEBUG):
        response = crashing.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"}, headers=AUTH)

    assert response.status_code == 500  # 응답은 기존 오류 그대로
    (notice,) = world.discord
    assert PROFILE in notice["content"] and "graduate-cert-temp" in notice["content"]
    assert ".jpg" not in notice["content"] and f"{PROFILE}/" not in notice["content"]
    assert ".jpg" not in caplog.text


def test_double_submit_race_with_failed_photo_delete_reports_the_orphan_and_keeps_409(client, world):
    world.insert_conflict = True
    world.fail_delete = True

    response = _apply(client)

    assert response.status_code == 409 and response.json()["code"] == "already_pending"
    assert len(world.discord) == 1 and PROFILE in world.discord[0]["content"]


def test_a_successful_rollback_sends_no_orphan_notice(world, client):
    world.fail_insert = True
    crashing = type(client)(client.app, raise_server_exceptions=False)

    crashing.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"}, headers=AUTH)

    assert world.discord == []


def test_double_submit_race_is_409(client, world):
    world.insert_conflict = True

    response = _apply(client)

    assert response.status_code == 409
    assert response.json()["code"] == "already_pending"
    assert world.objects == {}
    assert world.discord == []


def test_apply_upload_failure_is_not_recorded(world, client):
    world.fail_upload = True
    crashing = type(client)(client.app, raise_server_exceptions=False)

    assert crashing.post(URL, files={"photo": ("c.jpg", JPEG, "image/jpeg")}, data={"agreed": "true"},
                         headers=AUTH).status_code == 500
    assert world.calls("POST", "graduate_verification_requests") == []


def test_previous_email_never_written_and_response_is_identical(client, world):
    # 제출 시점에는 중복 점검을 하지 않는다 — 이전 메일이 이미 다른 계정 것이어도 응답이 같다.
    first = _apply(client, previous="taken@old-school.ac.kr")
    world.rows.clear()
    world.objects.clear()
    second = _apply(client, previous="free@old-school.ac.kr")

    assert (first.status_code, first.json()) == (second.status_code, second.json())
    assert world.touched("school_email_claims") == [] and world.touched("signup_blocks") == []


def test_logs_carry_ids_only(client, world, caplog):
    world.set_ocr(CERT_TEXT)
    world.vision.batch_annotate_images.side_effect = None

    with caplog.at_level(logging.DEBUG):
        _apply(client, previous="old@prev.ac.kr")
        world.rows.clear()
        world.vision.batch_annotate_images.side_effect = RuntimeError("1234567890123456 quota")
        world.fail_delete = True
        _apply(client)

    text = caplog.text
    assert "글자 인식 실패" in text  # 로그가 실제로 잡혔다(아래 부재 확인이 헛돌지 않는다)
    for secret in ("1234567890123456", "old@prev.ac.kr", "서울대학교", ".jpg", "graduate-cert-temp"):
        assert secret not in text
