import json
from datetime import datetime
from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from app.core.time import SEOUL
from app.graduate_verification.repository import GraduateRequestRepository, attempts_used

PROFILE = UUID("11111111-1111-1111-1111-111111111111")
REQUEST = UUID("22222222-2222-2222-2222-222222222222")
URL = "https://x.supabase.co/rest/v1"
NOW = datetime(2026, 10, 25, 12, 0, tzinfo=SEOUL)


def _repo(handler) -> GraduateRequestRepository:
    return GraduateRequestRepository(URL, "service-key", httpx.AsyncClient(transport=httpx.MockTransport(handler)))


async def test_fetch_history_is_one_read_keyed_by_profile_id_newest_first():
    # profile_id=eq.… 가 id=eq.… 분기에 걸리지 않는지(메모 reference_backend_test_mock_traps ①).
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        params = request.url.params
        if "id" in params:
            return httpx.Response(200, json=[{"status": "wrong-branch"}])
        return httpx.Response(200, json=[{"status": "pending", "reason": None}])

    history = await _repo(handler).fetch_history(PROFILE)

    assert history == [{"status": "pending", "reason": None}]
    assert len(seen) == 1
    params = seen[0].url.params
    assert params["profile_id"] == f"eq.{PROFILE}"
    assert params["order"] == "created_at.desc"
    assert params["select"] == "id,status,reason,created_at"


def test_attempts_used_skips_only_expired_cancellations():
    history = [
        {"status": "rejected", "reason": "unreadable"},
        {"status": "cancelled", "reason": "expired"},
        {"status": "cancelled", "reason": "switched"},
        {"status": "pending", "reason": None},
    ]

    assert attempts_used(history) == 3
    assert attempts_used([]) == 0


async def test_insert_pending_sends_hint_columns_and_hash_literal():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(201)

    await _repo(handler).insert_pending(
        request_id=REQUEST, profile_id=PROFILE, photo_path=f"{PROFILE}/{REQUEST}.jpg", ocr_state="read",
        ocr_document_number="AB12CD34", ocr_school_text="서울대학교", previous_school_email="a@b.ac.kr",
        document_hmac=b"\x0f\x01", key_version=1)

    body = json.loads(seen[0].content)
    assert seen[0].method == "POST" and seen[0].url.path.endswith("/graduate_verification_requests")
    assert body == {
        "id": str(REQUEST), "profile_id": str(PROFILE), "photo_path": f"{PROFILE}/{REQUEST}.jpg", "ocr_state": "read",
        "ocr_document_number": "AB12CD34", "ocr_school_text": "서울대학교", "previous_school_email": "a@b.ac.kr",
        "document_hmac": "\\x0f01", "key_version": 1,
    }


async def test_insert_pending_turns_a_second_pending_into_409():
    repo = _repo(lambda r: httpx.Response(409, json={"code": "23505", "message": "duplicate"}))

    with pytest.raises(HTTPException) as caught:
        await repo.insert_pending(
            request_id=REQUEST, profile_id=PROFILE, photo_path="p", ocr_state="failed", ocr_document_number=None,
            ocr_school_text=None, previous_school_email=None, document_hmac=None, key_version=1)

    assert caught.value.status_code == 409


async def test_cancel_pending_nulls_plaintext_in_one_patch():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": str(REQUEST), "photo_path": "p/r.jpg"}])

    row = await _repo(handler).cancel_pending(PROFILE, "switched", NOW)

    assert len(seen) == 1 and seen[0].method == "PATCH"
    params = seen[0].url.params
    assert params["profile_id"] == f"eq.{PROFILE}"
    assert params["status"] == "eq.pending"
    assert "return=representation" in seen[0].headers["prefer"]
    body = json.loads(seen[0].content)
    assert body == {
        "status": "cancelled", "reason": "switched", "decided_at": NOW.isoformat(),
        "ocr_document_number": None, "ocr_school_text": None, "previous_school_email": None,
    }
    assert row == {"id": str(REQUEST), "photo_path": "p/r.jpg"}


async def test_cancel_pending_returns_none_when_nothing_was_pending():
    assert await _repo(lambda r: httpx.Response(200, json=[])).cancel_pending(PROFILE, "switched", NOW) is None


async def test_clear_photo_path_only_touches_decided_rows():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    await _repo(handler).clear_photo_path(REQUEST)

    params = seen[0].url.params
    assert params["id"] == f"eq.{REQUEST}" and params["status"] == "neq.pending"
    assert json.loads(seen[0].content) == {"photo_path": None}


async def test_fetch_pending_older_than_and_decided_with_photo_filters():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[])

    repo = _repo(handler)
    await repo.fetch_pending_older_than(NOW, 50)
    await repo.fetch_decided_with_photo(40)

    old, decided = seen[0].url.params, seen[1].url.params
    assert old["status"] == "eq.pending" and old["created_at"] == f"lte.{NOW.isoformat()}" and old["limit"] == "50"
    assert decided["status"] == "neq.pending" and decided["photo_path"] == "not.is.null" and decided["limit"] == "40"


async def test_set_method_writes_only_while_the_person_is_still_unverified():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    await _repo(handler).set_method(PROFILE, None)

    params = seen[0].url.params
    assert seen[0].method == "PATCH" and json.loads(seen[0].content) == {"verification_method": None}
    assert params["id"] == f"eq.{PROFILE}"
    # 그 사이 인증이 끝난 사람(학교 메일 · 졸업생)의 방법 값은 덮지 않는다.
    assert params["school_email_verified_at"] == "is.null" and params["graduate_verified_at"] == "is.null"


async def test_fetch_university_names():
    repo = _repo(lambda r: httpx.Response(200, json=[{"id": "u1", "name": "서울대학교"}]))

    assert await repo.fetch_university_names() == [{"id": "u1", "name": "서울대학교"}]


async def test_fetch_pending_of_verified_joins_the_profile_and_filters_on_its_verified_column():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[])

    await _repo(handler).fetch_pending_of_verified(30)

    params = seen[0].url.params
    assert params["status"] == "eq.pending"
    assert params["profiles.school_email_verified_at"] == "not.is.null"
    assert "profiles!inner(school_email_verified_at)" in params["select"] and params["limit"] == "30"
