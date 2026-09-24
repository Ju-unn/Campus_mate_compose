from unittest.mock import AsyncMock

import httpx
from openai import AsyncOpenAI

from app.profile_onboarding.avatars import AvatarGenerator, MAX_CONSECUTIVE_FAILURES

# student_id_content_type 이 매직바이트로 JPEG 라고 인정하는 최소 바이트열.
_JPEG_BYTES = b"\xff\xd8\xff" + b"0" * 32


def _image_part_headers(body: bytes) -> str:
    """multipart 본문에서 image 파트의 헤더 줄만 꺼낸다."""
    part = body.split(b'name="image"', 1)[1]
    return part.split(b"\r\n\r\n", 1)[0].decode("latin-1")


async def test_generate_sends_source_photo_with_its_own_mimetype():
    """맨 bytes 를 넘기면 SDK 가 application/octet-stream 으로 보내 OpenAI 가 400 을 낸다(2026-09-25 운영).

    목은 무엇을 보내든 받아 주므로, 진짜 SDK 에 가짜 전송 계층만 끼워 실제로 나가는 multipart 를 본다.
    """
    requests: list[httpx.Request] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={"created": 0, "data": [{"b64_json": "ZmFrZQ=="}]})

    openai_client = AsyncOpenAI(
        api_key="test-key",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    storage = AsyncMock()
    storage.upload.return_value = "profile-id/uuid.png"

    generator = AvatarGenerator(openai_client, storage, failure_counts={})
    result = await generator.generate("profile-id", _JPEG_BYTES)

    assert result.status == "ready"
    headers = _image_part_headers(requests[0].content)
    assert "Content-Type: image/jpeg" in headers
    assert 'filename="source.jpeg"' in headers


async def test_generate_returns_ready_on_first_success():
    openai_client = AsyncMock()
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]
    storage = AsyncMock()
    storage.upload.return_value = "profile-id/uuid.png"

    generator = AvatarGenerator(openai_client, storage, failure_counts={})
    result = await generator.generate("profile-id", _JPEG_BYTES)

    assert result.status == "ready"
    assert result.storage_path == "profile-id/uuid.png"


async def test_generate_fails_without_calling_openai_when_format_is_unknown():
    openai_client = AsyncMock()
    generator = AvatarGenerator(openai_client, AsyncMock(), failure_counts={})

    result = await generator.generate("profile-id", b"not-an-image")

    assert result.status == "failed"
    openai_client.images.edit.assert_not_awaited()


async def test_generate_counts_failures_independently_of_sdk_retries():
    # SDK 는 max_retries=0 이라 재시도하지 않는다 — 실패 카운트는 전부 이 클래스가 센다(2026-09-20 결정).
    openai_client = AsyncMock()
    openai_client.images.edit.side_effect = Exception("openai down")
    storage = AsyncMock()
    failure_counts: dict[str, int] = {}
    generator = AvatarGenerator(openai_client, storage, failure_counts)

    for _ in range(MAX_CONSECUTIVE_FAILURES - 1):
        result = await generator.generate("profile-id", _JPEG_BYTES)
        assert result.status == "failed"
        assert result.is_final_failure is False

    final = await generator.generate("profile-id", _JPEG_BYTES)
    assert final.status == "failed"
    assert final.is_final_failure is True  # 5번째부터 기본 아바타+하트10 트리거


async def test_generate_resets_failure_count_after_success():
    openai_client = AsyncMock()
    storage = AsyncMock()
    storage.upload.return_value = "path.png"
    failure_counts = {"profile-id": 3}
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]

    generator = AvatarGenerator(openai_client, storage, failure_counts)
    await generator.generate("profile-id", _JPEG_BYTES)

    assert failure_counts["profile-id"] == 0
