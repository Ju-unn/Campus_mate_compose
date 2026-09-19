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


async def test_upload_failure_raises():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    storage = StudentIdStorage("https://x.supabase.co/storage/v1", "service-key", client)

    with pytest.raises(httpx.HTTPStatusError):
        await storage.upload(PROFILE_ID, b"fake-jpeg-bytes", "image/jpeg")
