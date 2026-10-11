from uuid import UUID

import httpx
import pytest

from app.student_verification.storage import StudentIdStorage

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")


async def test_upload_success_returns_object_path():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = request.headers
        captured["content"] = request.content
        return httpx.Response(200, json={"Key": "ok"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    path = await storage.upload(PROFILE_ID, b"fake-jpeg-bytes", "image/jpeg")

    assert path.startswith(f"{PROFILE_ID}/")
    assert path.endswith(".jpg")
    assert captured["url"] == f"https://x.supabase.co/storage/v1/object/student-id-temp/{path}"
    assert captured["headers"]["apikey"] == "service-key"
    assert captured["headers"]["authorization"] == "Bearer service-key"
    assert captured["headers"]["content-type"] == "image/jpeg"
    assert captured["content"] == b"fake-jpeg-bytes"


async def test_upload_names_png_objects_with_png_extension():
    # 사람이 대시보드에서 내려받는 파일이라 확장자가 실제 형식과 달라선 안 된다.
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"Key": "ok"})))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    path = await storage.upload(PROFILE_ID, b"fake-png-bytes", "image/png")

    assert path.startswith(f"{PROFILE_ID}/")
    assert path.endswith(".png")


async def test_upload_failure_raises():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    with pytest.raises(httpx.HTTPStatusError):
        await storage.upload(PROFILE_ID, b"fake-jpeg-bytes", "image/jpeg")


async def test_delete_treats_an_already_missing_object_as_deleted():
    # 자동 통과 직후 훅이 같은 사진을 한 번 더 지우려 할 때처럼 이미 없는 파일 — 고아가 아니라 목표 상태다.
    client = httpx.AsyncClient(transport=httpx.MockTransport(
        lambda r: httpx.Response(404, json={"statusCode": "404", "error": "not_found"})))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    assert await storage.delete(f"{PROFILE_ID}/gone.jpg") is True


async def test_delete_still_reports_a_server_error_as_failed():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500, json={})))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    assert await storage.delete(f"{PROFILE_ID}/x.jpg") is False
