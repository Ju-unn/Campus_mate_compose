import hashlib
import io
from unittest.mock import AsyncMock

import httpx
import pytest
from openai import AsyncOpenAI
from PIL import Image

from app.profile_onboarding.avatars import (
    _STYLE_PROMPT,
    _STYLE_REFERENCE_BYTES,
    AvatarGenerator,
    MAX_CONSECUTIVE_FAILURES,
    avatar_regen_cost,
)

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


async def test_generate_sends_photo_and_style_reference_to_flare_without_input_fidelity():
    """2026-10-14 사용자 결정: gpt-image-2.5-flare 로 바꾼다. 사진 → 화풍 참고 그림 순서 2장은 그대로다.

    지시문 문구는 `test_generate_prompt_*` 가 따로 고정한다. 여기서는 전송 모양(이미지 순서·호출 인자)만 본다.
    """
    requests: list[httpx.Request] = []

    result = await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    assert result.status == "ready"
    body = requests[0].content
    headers = _image_part_headers(body)
    assert len(headers) == 2
    assert 'filename="source.jpeg"' in headers[0]
    assert 'filename="style-reference.jpg"' in headers[1]
    assert _form_value(body, "model") == "gpt-image-2.5-flare"
    # 새 모델은 input_fidelity 를 받지 않는다 — 값이 무엇이든 키가 실리면 400 invalid_input_fidelity_model 이다.
    assert b'name="input_fidelity"' not in body
    # 00019 에서 실제로 정사각으로 잘려 나왔다 — 표시용은 전부 세로다(DESIGN §5.2).
    assert _form_value(body, "size") == "1024x1536"
    assert _form_value(body, "quality") == "high"


async def test_generate_prompt_tells_which_image_is_photo_and_which_is_style_only():
    """둘째 그림의 장면(계단·벚꽃·건물)이 배경으로 새어 들던 것을 머리말이 막는다(v2-8, 시험 4장)."""
    requests: list[httpx.Request] = []

    await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    prompt = _form_value(requests[0].content, "prompt")
    preamble, found, _ = prompt.partition("Transform the provided photo")
    assert found, "본문 첫 문장이 머리말 뒤에 그대로 있어야 한다"
    assert "FIRST image" in preamble
    assert "SECOND image is a STYLE reference only" in preamble
    assert "NEVER use its content" in preamble
    assert "NEVER its scenery, background" in preamble
    assert "Recreate ONLY the FIRST image's own person" in preamble


# 시험을 거친 v2-8 프롬프트(머리말 + 본문, 2026-10-14 사용자 결정)의 지문이다. 시험 스크립트의 문자열을
# 그대로 옮겼다 — 일부러 고칠 때만 이 두 상수를 같이 바꾼다(다시 시험하고 사용자 결정을 받은 뒤에).
_PROMPT_SHA256 = "5d664d4820492fb9e16d2cccf556ce07573d2da8b6dda747474895b2e56c44b8"
_PROMPT_BYTES = 6641


def test_prompt_is_the_tested_v2_8_text_verbatim():
    encoded = _STYLE_PROMPT.encode()
    assert len(encoded) == _PROMPT_BYTES
    assert hashlib.sha256(encoded).hexdigest() == _PROMPT_SHA256


async def test_generate_prompt_draws_a_dot_and_line_face_without_the_old_watercolor_style():
    """2026-10-14 사용자 결정: 점·선 얼굴 + 선명한 디지털 화풍. 10-13 의 수채화 지시가 섞여 남으면 서로 모순된다."""
    requests: list[httpx.Request] = []

    await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    prompt = _form_value(requests[0].content, "prompt")
    assert prompt.index("FIRST image") < prompt.index("Transform the provided photo")
    assert "**1. Face: only dots and lines**" in prompt
    assert "**2. Keep the person recognizable**" in prompt
    assert "Recreate the FIRST photo's actual background" in prompt
    assert "**Negative constraints**" in prompt
    assert prompt.endswith("and no added text or logos that are not in the first photo.")
    assert "hand-drawn 2D watercolor illustration" not in prompt
    assert "reference male chibi illustration" not in prompt
    assert "Add visible fine paper grain" not in prompt
    assert "Simplify only the face" not in prompt


# 화풍 참고 그림 = frontend/assets/images/person-f1-blind-v1.png 를 1024x1280 JPEG(품질 90)로 줄인 파일.
# 시험 4장이 이 파일로 돌았다 — 다른 그림으로 바꾸면 다시 시험해야 한다.
_STYLE_REFERENCE_SHA256 = "2dd029c76b8c956114f2eb7163720f4355dde48d28e4dcbcf99d4601159cdf51"


def test_style_reference_is_the_tested_small_portrait_jpeg():
    image = Image.open(io.BytesIO(_STYLE_REFERENCE_BYTES))
    assert image.format == "JPEG"
    assert image.size == (1024, 1280)
    # 요청마다 같이 올라가는 파일이다 — 원본 PNG(약 2.4MB)를 그대로 넣으면 이 범위를 벗어난다.
    assert 200_000 < len(_STYLE_REFERENCE_BYTES) < 500_000
    assert hashlib.sha256(_STYLE_REFERENCE_BYTES).hexdigest() == _STYLE_REFERENCE_SHA256


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


@pytest.mark.parametrize(("ready_count", "cost"), [(0, 0), (1, 0), (2, 20), (5, 20)])
def test_avatar_regen_cost_is_free_once_after_the_first_avatar(ready_count, cost):
    # 0 = 온보딩 첫 생성, 1 = 다음 한 번 무료, 2 이상 = 20하트(2026-10-14 사용자 피드백 6, 종전 10 — ERD 12줄).
    assert avatar_regen_cost(ready_count) == cost
