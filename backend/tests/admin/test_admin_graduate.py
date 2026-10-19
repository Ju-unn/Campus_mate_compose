"""관리자 졸업생 인증 검수 API(계획서 2026-10-19-graduate-verification Task 5)."""
import hashlib
import hmac
import json
import logging

import httpx
import pytest

from admin_world import ADMIN, STRANGER, bearer
from app.admin.graduate_notice import REASON_TEXT, result_notice
from app.signup_policy import bytea_literal, hash_email
from graduate_admin_world import (
    APPLICANT, KAIST, OTHER_PERSON, R1, R2, R3, RPC, SIGN_PATH, SNU, TABLE, GraduateAdminWorld, request_row,
)

STORAGE = "https://x.supabase.co/storage/v1"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
SECRET = b"identity-key-test"
DOCUMENT_HASH = hmac.new(SECRET, b"graduate-document|ABCD12345678", hashlib.sha256).digest()
STUDENT_HASH = hmac.new(SECRET, f"graduate-student|{SNU}|2019123456".encode(), hashlib.sha256).digest()
PREVIOUS_HASH = hash_email("identity-key-test", "old@snu.ac.kr")
ROUTES = [
    ("GET", "/admin/graduate-requests", None),
    ("GET", f"/admin/graduate-requests/{R1}", None),
    ("POST", f"/admin/graduate-requests/{R1}/approve",
     {"university_id": SNU, "document_number": "ABCD12345678", "student_number": None}),
    ("POST", f"/admin/graduate-requests/{R1}/reject", {"reason": "unreadable"}),
]
APPROVE = {"university_id": SNU, "document_number": "abcd-1234 5678", "student_number": " 2019-123456 "}


@pytest.fixture
def world() -> GraduateAdminWorld:
    return GraduateAdminWorld()


def _approve(client, rid: str = R1, body: dict | None = None):
    return client.post(f"/admin/graduate-requests/{rid}/approve", headers=ADMIN_HEADERS, json=body or APPROVE)


def _reject(client, reason: str = "unreadable", rid: str = R1):
    return client.post(f"/admin/graduate-requests/{rid}/reject", headers=ADMIN_HEADERS, json={"reason": reason})


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("method", "url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_graduate_route_is_behind_the_admin_gate(client, world, method, url, body, who, headers, status, detail):
    world.add(request_row())
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.request(method, url, headers=headers, json=body)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.touched(TABLE) == [] and world.touched(RPC) == []


# 목록 ---------------------------------------------------------------------------

def test_list_is_oldest_first_and_has_no_photo_or_plaintext(client, world):
    world.add(request_row(R2, OTHER_PERSON, created_at="2026-10-25T05:00:00+00:00"))
    world.add(request_row(R1, APPLICANT, created_at="2026-10-25T01:00:00+00:00"))
    world.add(request_row(R3, OTHER_PERSON, status="approved", created_at="2026-10-20T00:00:00+00:00"))

    response = client.get("/admin/graduate-requests", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    (query,) = world.touched(TABLE)  # 읽기 한 번
    assert query.url.params["status"] == "eq.pending"
    assert query.url.params["order"] == "created_at.asc" and query.url.params["limit"] == "50"
    items = response.json()["items"]
    assert [i["id"] for i in items] == [R1, R2]
    assert set(items[0]) == {"id", "status", "reason", "created_at", "decided_at", "attempt_no", "profile_id",
                             "nickname", "university_name"}
    text = response.text
    for forbidden in ("photo", "ocr", "previous", "old@snu.ac.kr", "AB12CD34", "hmac", "feedface"):
        assert forbidden not in text
    # 같은 사람(OTHER_PERSON)의 첫 신청은 승인 줄(R3, 더 옛날)이라 R2 는 두 번째다.
    assert [i["attempt_no"] for i in items] == [1, 2]


def test_list_filters_by_status_and_limits(client, world):
    world.add(request_row(R3, OTHER_PERSON, status="rejected", reason="unreadable"))

    response = client.get("/admin/graduate-requests?status=rejected&limit=10", headers=ADMIN_HEADERS)

    assert [i["id"] for i in response.json()["items"]] == [R3]
    assert world.touched(TABLE)[0].url.params["limit"] == "10"
    assert client.get("/admin/graduate-requests?status=whatever", headers=ADMIN_HEADERS).status_code == 422
    assert client.get("/admin/graduate-requests?limit=101", headers=ADMIN_HEADERS).status_code == 422


# 상세 ---------------------------------------------------------------------------

def test_unknown_request_is_404(client, world):
    assert client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).status_code == 404


def test_detail_has_five_minute_signed_url_and_no_raw_path_or_hash(client, world):
    world.add(request_row())

    response = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS)

    body = response.json()
    assert body["photo_url"] == f"{STORAGE}/object/sign/graduate-cert-temp/{APPLICANT}/{R1}.jpg?token=t"
    sign = world.touched(f"{SIGN_PATH}{APPLICANT}/{R1}.jpg", "POST")[0]
    assert json.loads(sign.content) == {"expiresIn": 300}
    for forbidden in ("photo_path", "storage_path", "hmac", "feedface", f"{APPLICANT}/{R1}.jpg\""):
        assert forbidden not in response.text
    assert set(body) == {"id", "status", "reason", "created_at", "decided_at", "attempt_no", "profile_id",
                         "nickname", "university_name", "photo_url",
                         "ocr", "previous_school_email", "warnings", "history"}


def test_signing_failure_gives_a_null_photo_url_not_a_500(client, world):
    world.add(request_row())
    world.unsignable.add(f"{APPLICANT}/{R1}.jpg")

    response = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["photo_url"] is None


def test_detail_prefills_ocr_and_suggests_universities_from_text_and_email_domain(client, world):
    world.add(request_row(school="서울대학교", previous="old@kaist.ac.kr"))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert body["ocr"] == {"state": "read", "document_number": "AB12CD34", "school_text": "서울대학교",
                           "suggested_university_ids": [SNU, KAIST]}
    assert body["previous_school_email"] == "old@kaist.ac.kr"


def test_suggestions_are_deduplicated(client, world):
    world.add(request_row(school="서울대학교", previous="old@snu.ac.kr"))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert body["ocr"]["suggested_university_ids"] == [SNU]


def test_detail_without_ocr_or_previous_email_still_works(client, world):
    world.add(request_row(ocr_state="failed", number=None, school=None, previous=None, document_hmac=None))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert body["ocr"] == {"state": "failed", "document_number": None, "school_text": None, "suggested_university_ids": []}
    assert body["previous_school_email"] is None and body["warnings"] == []


def test_warning_school_email_in_use_is_read_only(client, world):
    world.add(request_row())
    world.claims.append({"profile_id": OTHER_PERSON, "school_email_hmac": bytea_literal(PREVIOUS_HASH), "key_version": 1})
    world.claim_owner_status = "suspended"

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert {"code": "school_email_in_use", "profile_id": OTHER_PERSON, "profile_status": "suspended"} in body["warnings"]
    # 학교 메일 claims · 재가입 제한 표로 나간 호출은 읽기뿐이다.
    for path in ("/rest/v1/school_email_claims", "/rest/v1/signup_blocks"):
        assert world.touched(path) and {r.method for r in world.touched(path)} == {"GET"}
    assert bytea_literal(PREVIOUS_HASH) not in json.dumps(body, ensure_ascii=False)


def test_warning_rejoin_blocked_and_document_seen(client, world):
    world.add(request_row())
    world.add(request_row(R2, OTHER_PERSON, status="approved", document_hmac=request_row()["document_hmac"]))
    world.blocks.append(bytea_literal(PREVIOUS_HASH))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert {"code": "school_email_rejoin_blocked"} in body["warnings"]
    assert {"code": "document_seen", "profile_id": OTHER_PERSON} in body["warnings"]
    assert not any(w["code"] == "school_email_in_use" for w in body["warnings"])


def test_detail_history_lists_other_requests_of_the_same_person(client, world):
    world.add(request_row())
    world.add(request_row(R2, APPLICANT, status="rejected", reason="unreadable", created_at="2026-10-20T00:00:00+00:00"))
    world.add(request_row(R3, OTHER_PERSON, status="rejected", reason="unverifiable"))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert body["history"] == [{"status": "rejected", "reason": "unreadable", "decided_at": "2026-10-26T00:00:00+00:00"}]
    assert body["attempt_no"] == 2


def test_a_decided_request_has_no_photo_ocr_email_or_warnings(client, world):
    world.add(request_row(status="rejected", reason="unreadable", photo="default"))
    world.claims.append({"profile_id": OTHER_PERSON, "school_email_hmac": bytea_literal(PREVIOUS_HASH), "key_version": 1})

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert (body["photo_url"], body["ocr"], body["previous_school_email"], body["warnings"]) == (None, None, None, [])
    assert world.touched("/rest/v1/school_email_claims") == []


def test_even_a_decided_row_with_leftover_plaintext_never_shows_it(client, world):
    # DB check 가 막아 생기지 않는 모양이지만, 서버도 결정된 줄의 평문을 응답에 싣지 않는다(방어 한 겹 더).
    world.add({**request_row(status="rejected", reason="unreadable"), "previous_school_email": "leak@x.kr",
               "ocr_document_number": "LEAK1234", "ocr_school_text": "서울대학교"})

    response = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS)

    assert "leak@x.kr" not in response.text and "LEAK1234" not in response.text
    assert response.json()["ocr"] is None


def test_list_and_detail_carry_nickname_and_university_name_from_the_same_read(client, world):
    world.add(request_row())

    item = client.get("/admin/graduate-requests", headers=ADMIN_HEADERS).json()["items"][0]
    detail = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert (item["nickname"], item["university_name"]) == ("하늘", "서울대학교")
    assert (detail["nickname"], detail["university_name"]) == ("하늘", "서울대학교")
    # 닉네임 · 학교는 신청 줄을 읽을 때 임베드로 같이 온다 — 프로필 표를 따로 읽지 않는다(N+1 없음).
    assert world.touched("/rest/v1/profiles", "GET") == [] or all(
        r.url.params.get("select") == "status" for r in world.touched("/rest/v1/profiles", "GET"))
    select = world.touched(TABLE)[0].url.params["select"]
    assert "nickname" in select and "universities(name)" in select
    for personal in ("email", "phone", "kakao", "real_name", "birth"):
        assert personal not in select


def test_nickname_and_university_are_null_when_unknown_or_the_account_is_withdrawn(client, world):
    world.add(request_row(R1, APPLICANT, status="rejected", reason="unreadable"))
    world.add(request_row(R2, OTHER_PERSON))
    world.people[APPLICANT]["status"] = "withdrawn"
    world.people[OTHER_PERSON] = {"status": "active", "nickname": None, "universities": None}

    withdrawn = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()
    pending = client.get(f"/admin/graduate-requests/{R2}", headers=ADMIN_HEADERS).json()
    listed = client.get("/admin/graduate-requests?status=rejected", headers=ADMIN_HEADERS).json()["items"][0]

    assert (withdrawn["nickname"], withdrawn["university_name"]) == (None, None)
    assert (listed["nickname"], listed["university_name"]) == (None, None)
    assert (pending["nickname"], pending["university_name"]) == (None, None)


def test_a_decided_request_still_shows_nickname_and_university(client, world):
    world.add(request_row(status="approved"))

    body = client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS).json()

    assert (body["nickname"], body["university_name"]) == ("하늘", "서울대학교")
    assert (body["photo_url"], body["ocr"], body["previous_school_email"]) == (None, None, None)


def test_reject_reason_texts_are_the_confirmed_d10_wording():
    assert REASON_TEXT == {
        "unreadable": "사진이 잘 안 보여요",
        "not_certificate": "졸업증명서가 아니에요",
        "unverifiable": "확인할 수 없는 번호예요",
        "school_unsupported": "아직 지원하지 않는 학교예요",
    }
    assert result_notice("rejected", "unverifiable").body == "확인할 수 없는 번호예요 · 다시 신청해 주세요"


# 승인 ---------------------------------------------------------------------------

def test_approve_hashes_admin_values_and_calls_rpc_once(client, world):
    world.add(request_row())

    response = _approve(client)

    assert response.status_code == 200
    (call,) = world.rpc_calls
    assert call == {
        "p_admin": ADMIN, "p_request": R1, "p_status": "approved", "p_reason": None, "p_university": SNU,
        "p_document_hmac": bytea_literal(DOCUMENT_HASH), "p_student_hmac": bytea_literal(STUDENT_HASH),
        "p_key_version": 1, "p_ip": call["p_ip"],
    }
    # 평문 번호 · 학번은 어떤 요청 본문에도 없다.
    for request in world.requests:
        for plain in (b"ABCD12345678", b"abcd-1234", b"2019123456", b"2019-123456"):
            assert plain not in request.content


def test_approve_without_student_number_sends_null_student_hash(client, world):
    world.add(request_row())

    assert _approve(client, body={"university_id": SNU, "document_number": "ABCD12345678"}).status_code == 200

    assert world.rpc_calls[0]["p_student_hmac"] is None


@pytest.mark.parametrize("body", [
    {"university_id": SNU, "document_number": "12"},
    {"university_id": SNU, "document_number": "12한글34567"},
    {"university_id": SNU, "document_number": "ABCD12345678", "student_number": ""},
    {"university_id": SNU, "document_number": "ABCD12345678", "student_number": "   "},
    {"university_id": SNU, "document_number": "ABCD12345678", "student_number": "x" * 21},
    {"university_id": "not-a-uuid", "document_number": "ABCD12345678"},
    {"document_number": "ABCD12345678"},
])
def test_approve_validates_input_before_rpc(client, world, body):
    world.add(request_row())

    assert _approve(client, body=body).status_code == 422
    assert world.rpc_calls == []


def test_approve_then_deletes_photo_pushes_and_returns_decided_detail(client, world):
    world.add(request_row())

    response = _approve(client)

    assert response.status_code == 200
    assert world.events == ["rpc", "delete_photo", "clear_path", "notice", "push"]
    body = response.json()
    assert (body["status"], body["photo_url"], body["ocr"], body["previous_school_email"]) == ("approved", None, None, None)
    assert world.objects == {} and world.rows[R1]["photo_path"] is None
    assert world.notifications == [{
        "profile_id": APPLICANT, "kind": "verification_result", "title": "졸업생 인증이 끝났어요",
        "body": "학과 정보를 입력하고 시작해 보세요", "data": {"route": "graduate_verification", "state": "approved"}}]


def test_photo_delete_failure_does_not_flip_the_decision(client, world, caplog):
    world.add(request_row())
    world.fail_delete = True

    with caplog.at_level(logging.DEBUG):
        response = _approve(client)

    assert response.status_code == 200 and response.json()["status"] == "approved"
    assert world.rows[R1]["photo_path"] is not None  # 경로가 남아 매시 배치가 다시 지운다
    assert f"request={R1}" in caplog.text
    assert f"{APPLICANT}/{R1}" not in caplog.text


# 반려 ---------------------------------------------------------------------------

@pytest.mark.parametrize("reason", list(REASON_TEXT))
def test_reject_with_each_reason_pushes_reason_code(client, world, reason):
    world.add(request_row())

    response = _reject(client, reason)

    assert response.status_code == 200
    assert response.json()["status"] == "rejected" and response.json()["reason"] == reason
    call = world.rpc_calls[0]
    assert (call["p_status"], call["p_reason"], call["p_university"], call["p_document_hmac"]) == ("rejected", reason, None, None)
    assert world.notifications[0]["data"] == {"route": "graduate_verification", "state": "rejected", "reason": reason}
    assert world.notifications[0]["body"] == f"{REASON_TEXT[reason]} · 다시 신청해 주세요"
    assert world.events[:3] == ["rpc", "delete_photo", "clear_path"]


def test_reject_rejects_unknown_reason_before_rpc(client, world):
    world.add(request_row())

    assert _reject(client, "whatever").status_code == 422
    assert client.post(f"/admin/graduate-requests/{R1}/reject", headers=ADMIN_HEADERS, json={}).status_code == 422
    assert world.rpc_calls == []


# 충돌 · 실패 ----------------------------------------------------------------------

@pytest.mark.parametrize("message", ["already_reviewed", "already_verified", "account_withdrawn", "document_reused",
                                     "student_reused", "rejoin_blocked"])
def test_409_codes_map_from_db_messages(client, world, message):
    world.add(request_row())
    world.rpc_error = ("CM409", message)

    response = _approve(client)

    assert response.status_code == 409 and response.json()["detail"] == message
    assert world.notifications == [] and world.events.count("push") == 0 and world.events.count("delete_photo") == 0
    assert world.rows[R1]["photo_path"] is not None


def test_rpc_not_found_and_rule_violation_map_to_404_and_422(client, world):
    world.add(request_row())
    world.rpc_error = ("CM404", "x")
    assert _reject(client).status_code == 404
    world.rpc_error = ("22023", "x")
    assert _reject(client).status_code == 422
    world.rpc_error = ("23503", "x")
    assert _approve(client).status_code == 422


@pytest.mark.parametrize("trouble", [{"fcm_status": 500}, {"fcm_raises": httpx.ConnectError("down")},
                                     {"notifications_status": 500}])
def test_notice_failure_never_flips_the_decision(client, world, trouble):
    world.add(request_row())
    for key, value in trouble.items():
        setattr(world, key, value)

    response = _approve(client)

    assert response.status_code == 200 and response.json()["status"] == "approved"


def test_reason_codes_are_the_same_in_the_db_check_the_notice_and_the_server():
    from typing import get_args
    from app.admin.graduate_review import RejectReason
    from app.graduate_verification.messages import REJECT_REASONS

    assert set(REASON_TEXT) == set(get_args(RejectReason)) == REJECT_REASONS


def test_notice_data_never_carries_photo_email_number_or_nickname():
    for status, reason in (("approved", None), *(("rejected", r) for r in REASON_TEXT), ("rejected", "bogus"), ("rejected", None)):
        notice = result_notice(status, reason)
        assert set(notice.data) <= {"route", "state", "reason"}
        assert notice.kind == "verification_result"


def test_logs_carry_ids_only(client, world, caplog):
    world.add(request_row())
    world.claims.append({"profile_id": OTHER_PERSON, "school_email_hmac": bytea_literal(PREVIOUS_HASH), "key_version": 1})
    world.fail_delete = True

    with caplog.at_level(logging.DEBUG):
        client.get(f"/admin/graduate-requests/{R1}", headers=ADMIN_HEADERS)
        _approve(client)

    for secret in ("AB12CD34", "ABCD12345678", "2019123456", "old@snu.ac.kr", "feedface", ".jpg", "서울대학교"):
        assert secret not in caplog.text
