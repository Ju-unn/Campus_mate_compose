import json
from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from app.student_verification.repository import StudentVerificationRepository

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
POSTGREST_URL = "https://x.supabase.co/rest/v1"


def _repo(handler):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return StudentVerificationRepository(POSTGREST_URL, "service-key", client)


async def test_fetch_gate_status_returns_first_row():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url.copy_with(query=None))
        captured["params"] = dict(request.url.params)
        captured["headers"] = request.headers
        return httpx.Response(
            200,
            json=[{"student_verification": "pending", "department": None, "universities": {"name": "서울대학교"}}],
        )

    repo = _repo(handler)

    result = await repo.fetch_gate_status(PROFILE_ID)

    assert captured["url"] == f"{POSTGREST_URL}/profiles"
    assert captured["params"] == {
        "id": f"eq.{PROFILE_ID}",
        # 실제 컬럼은 major, 응답 키는 별칭 department 로 돌아온다.
        "select": "student_verification,department:major,universities(name)",
    }
    assert captured["headers"]["apikey"] == "service-key"
    assert captured["headers"]["authorization"] == "Bearer service-key"
    assert result == {"student_verification": "pending", "department": None, "universities": {"name": "서울대학교"}}


async def test_fetch_gate_status_raises_clear_error_when_profile_row_missing():
    repo = _repo(lambda request: httpx.Response(200, json=[]))

    with pytest.raises(ValueError, match=str(PROFILE_ID)):
        await repo.fetch_gate_status(PROFILE_ID)


async def test_fetch_reject_reason_returns_reason_when_row_exists():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url.copy_with(query=None))
        captured["params"] = dict(request.url.params)
        return httpx.Response(200, json=[{"reject_reason": "사진이 흐림"}])

    repo = _repo(handler)

    result = await repo.fetch_reject_reason(PROFILE_ID)

    assert captured["url"] == f"{POSTGREST_URL}/student_verification_attempts"
    assert captured["params"] == {
        "profile_id": f"eq.{PROFILE_ID}",
        "order": "submitted_at.desc",
        "limit": "1",
        "select": "reject_reason",
    }
    assert result == "사진이 흐림"


async def test_fetch_reject_reason_returns_none_when_no_rows():
    handler = lambda request: httpx.Response(200, json=[])
    repo = _repo(handler)

    result = await repo.fetch_reject_reason(PROFILE_ID)

    assert result is None


async def test_upsert_real_name_sends_merge_duplicates():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["json"] = json.loads(request.content)
        captured["headers"] = request.headers
        return httpx.Response(201, json=[])

    repo = _repo(handler)

    await repo.upsert_real_name(PROFILE_ID, "홍길동")

    assert captured["url"] == f"{POSTGREST_URL}/profile_private"
    assert captured["json"] == {"profile_id": str(PROFILE_ID), "real_name": "홍길동", "updated_at": "now()"}
    assert captured["headers"]["prefer"] == "resolution=merge-duplicates"
    assert captured["headers"]["apikey"] == "service-key"
    assert captured["headers"]["authorization"] == "Bearer service-key"
    assert captured["headers"]["content-type"] == "application/json"


async def test_upsert_real_name_raises_on_error():
    repo = _repo(lambda request: httpx.Response(500))

    with pytest.raises(httpx.HTTPStatusError):
        await repo.upsert_real_name(PROFILE_ID, "홍길동")


async def test_record_attempt_posts_attempt_row():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["json"] = json.loads(request.content)
        captured["headers"] = request.headers
        return httpx.Response(201, json=[])

    repo = _repo(handler)

    await repo.record_attempt(PROFILE_ID, "11111111-1111-1111-1111-111111111111/abc.jpg", "rejected")

    assert captured["url"] == f"{POSTGREST_URL}/student_verification_attempts"
    assert captured["json"] == {
        "profile_id": str(PROFILE_ID),
        "file_path": "11111111-1111-1111-1111-111111111111/abc.jpg",
        "result": "rejected",
    }
    assert captured["headers"]["apikey"] == "service-key"
    assert captured["headers"]["authorization"] == "Bearer service-key"


async def test_record_attempt_raises_on_error():
    repo = _repo(lambda request: httpx.Response(500))

    with pytest.raises(httpx.HTTPStatusError):
        await repo.record_attempt(PROFILE_ID, "path.jpg", "approved")


async def test_update_attempt_result_patches_the_matching_attempt_row():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url.copy_with(query=None))
        captured["params"] = dict(request.url.params)
        captured["json"] = json.loads(request.content)
        captured["method"] = request.method
        return httpx.Response(200, json=[])

    repo = _repo(handler)

    await repo.update_attempt_result(PROFILE_ID, f"{PROFILE_ID}/abc.jpg", "verified")

    assert captured["method"] == "PATCH"
    assert captured["url"] == f"{POSTGREST_URL}/student_verification_attempts"
    assert captured["params"] == {"profile_id": f"eq.{PROFILE_ID}", "file_path": f"eq.{PROFILE_ID}/abc.jpg"}
    # reviewed_at 은 대조가 끝난 시각이라 확정과 같은 요청에서 채워야 null 로 남지 않는다.
    assert captured["json"] == {"result": "verified", "reviewed_at": "now()"}


async def test_update_attempt_result_raises_on_error():
    repo = _repo(lambda request: httpx.Response(500))

    with pytest.raises(httpx.HTTPStatusError):
        await repo.update_attempt_result(PROFILE_ID, "path.jpg", "verified")


async def test_update_verification_status_patches_profiles():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url.copy_with(query=None))
        captured["params"] = dict(request.url.params)
        captured["json"] = json.loads(request.content)
        captured["method"] = request.method
        return httpx.Response(200, json=[])

    repo = _repo(handler)

    await repo.update_verification_status(PROFILE_ID, "approved")

    assert captured["method"] == "PATCH"
    assert captured["url"] == f"{POSTGREST_URL}/profiles"
    assert captured["params"] == {"id": f"eq.{PROFILE_ID}"}
    assert captured["json"] == {"student_verification": "approved"}


async def test_update_verification_status_raises_on_error():
    repo = _repo(lambda request: httpx.Response(500))

    with pytest.raises(httpx.HTTPStatusError):
        await repo.update_verification_status(PROFILE_ID, "approved")


async def test_save_school_info_patches_department_and_student_number():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url.copy_with(query=None))
        captured["params"] = dict(request.url.params)
        captured["json"] = json.loads(request.content)
        captured["method"] = request.method
        return httpx.Response(200, json=[])

    repo = _repo(handler)

    await repo.save_school_info(PROFILE_ID, "컴퓨터공학과", "2021123456")

    assert captured["method"] == "PATCH"
    assert captured["url"] == f"{POSTGREST_URL}/profiles"
    assert captured["params"] == {"id": f"eq.{PROFILE_ID}"}
    assert captured["json"] == {"major": "컴퓨터공학과", "student_number": "2021123456"}


async def test_save_school_info_raises_on_error():
    repo = _repo(lambda request: httpx.Response(500))

    with pytest.raises(httpx.HTTPStatusError):
        await repo.save_school_info(PROFILE_ID, "컴퓨터공학과", "2021123456")


async def test_db_constraint_violations_come_back_as_4xx_not_500():
    """생 raise_for_status 는 제약 위반을 500 으로 흘려보냈다. core/http 를 거치면 422 다."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"code": "23502", "message": "null value"})

    with pytest.raises(HTTPException) as caught:
        await _repo(handler).record_attempt(PROFILE_ID, "path.jpg", "pending")

    assert caught.value.status_code == 422
