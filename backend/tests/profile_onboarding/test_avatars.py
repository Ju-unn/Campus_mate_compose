from unittest.mock import AsyncMock

import httpx
from openai import AsyncOpenAI

from app.profile_onboarding.avatars import AvatarGenerator, MAX_CONSECUTIVE_FAILURES

# student_id_content_type 이 매직바이트로 JPEG 라고 인정하는 최소 바이트열.
_JPEG_BYTES = b"\xff\xd8\xff" + b"0" * 32


def _image_part_headers(body: bytes) -> list[str]:
    """multipart 본문에서 image 파트들의 헤더 줄만 보낸 순서대로 꺼낸다."""
    return [part.split(b"\r\n\r\n", 1)[0].decode("latin-1") for part in body.split(b'name="image')[1:]]


def _form_value(body: bytes, name: str) -> str:
    """multipart 본문에서 파일이 아닌 필드 하나의 값을 꺼낸다."""
    part = body.split(f'name="{name}"'.encode(), 1)[1]
    return part.split(b"\r\n\r\n", 1)[1].split(b"\r\n--", 1)[0].decode("utf-8")


def _generator_recording_requests(requests: list[httpx.Request]) -> AvatarGenerator:
    """목은 무엇을 보내든 받아 주므로, 진짜 SDK 에 가짜 전송 계층만 끼워 실제로 나가는 multipart 를 본다."""

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
    return AvatarGenerator(openai_client, storage, failure_counts={})


async def test_generate_sends_source_photo_with_its_own_mimetype():
    """맨 bytes 를 넘기면 SDK 가 application/octet-stream 으로 보내 OpenAI 가 400 을 낸다(2026-09-25 운영)."""
    requests: list[httpx.Request] = []

    result = await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    assert result.status == "ready"
    source_headers = _image_part_headers(requests[0].content)[0]
    assert "Content-Type: image/jpeg" in source_headers
    assert 'filename="source.jpeg"' in source_headers


async def test_generate_sends_style_reference_as_second_image_at_high_fidelity():
    """지시문 한 줄로는 블라인드 아바타 화풍이 나오지 않아 기준 그림 1장을 같이 보낸다(2026-09-25 결정 B).

    지시문 문구 자체는 단정하지 않는다 — 화풍을 다듬을 때마다 깨질 이유가 없다.
    """
    requests: list[httpx.Request] = []

    result = await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    assert result.status == "ready"
    body = requests[0].content
    headers = _image_part_headers(body)
    assert len(headers) == 2
    assert 'filename="source.jpeg"' in headers[0]
    assert 'filename="style-reference.jpg"' in headers[1]
    # 원본의 구도·옷·머리를 유지하는 유일한 손잡이다. 빠지면 모델이 사진을 자유롭게 다시 그린다.
    assert _form_value(body, "input_fidelity") == "high"
    # 00019 에서 실제로 정사각으로 잘려 나왔다 — 표시용은 전부 세로다(DESIGN §5.2).
    assert _form_value(body, "size") == "1024x1536"


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
