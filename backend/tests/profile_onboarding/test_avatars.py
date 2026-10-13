import hashlib
from unittest.mock import AsyncMock

import httpx
import pytest
from openai import AsyncOpenAI

from app.profile_onboarding.avatars import _STYLE_PROMPT_MAIN, AvatarGenerator, MAX_CONSECUTIVE_FAILURES, avatar_regen_cost

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
    """지시문만으로는 화풍이 나오지 않아 기준 그림 1장을 같이 보낸다(2026-09-25 결정 B, 순서: 사진 → 기준 그림).

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
    # 원본의 구도·옷·머리를 유지하는 유일한 손잡이다. 빠지면 모델이 사진을 자유롭게 다시 그린다.
    assert _form_value(body, "input_fidelity") == "high"
    # 00019 에서 실제로 정사각으로 잘려 나왔다 — 표시용은 전부 세로다(DESIGN §5.2).
    assert _form_value(body, "size") == "1024x1536"
    # 프롬프트만 바꾸는 작업이다 — 이 둘이 움직이면 비용(장당 약 $0.37 추정)이 바뀐다.
    assert _form_value(body, "model") == "gpt-image-1"
    assert _form_value(body, "quality") == "high"


async def test_generate_prompt_tells_which_image_is_photo_and_which_is_style_only():
    """새 프롬프트의 'the reference male chibi illustration' 은 두 번째 그림을 가리킨다 — 머리말이 앞에서 못박는다."""
    requests: list[httpx.Request] = []

    await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    prompt = _form_value(requests[0].content, "prompt")
    preamble, found, _ = prompt.partition("Transform the provided photo")
    assert found, "본문 첫 문장이 머리말 뒤에 그대로 있어야 한다"
    assert "FIRST image" in preamble
    assert "SECOND image" in preamble
    assert "style reference only" in preamble
    assert "never copy" in preamble


# 사용자가 붙여넣은 프롬프트 본문(2026-10-13)의 지문이다. 본문은 한 글자도 고치지 않기로 했다 —
# 일부러 고칠 때만 이 두 상수를 같이 바꾼다(사용자 결정을 다시 받은 뒤에).
_PROMPT_MAIN_SHA256 = "f06d9256e053bddbad996371ecec8fd6788c2132927b1138888125dc225ecbe3"
_PROMPT_MAIN_BYTES = 4207


def test_prompt_main_is_the_user_pasted_text_verbatim():
    encoded = _STYLE_PROMPT_MAIN.encode()
    assert len(encoded) == _PROMPT_MAIN_BYTES
    assert hashlib.sha256(encoded).hexdigest() == _PROMPT_MAIN_SHA256


async def test_generate_prompt_keeps_recognizable_face_of_the_original_person():
    """2026-10-13 사용자 결정: 블라인드(얼굴만 단순화) 대신 알아볼 수 있는 얼굴 특징을 유지하는 화풍이다."""
    requests: list[httpx.Request] = []

    await _generator_recording_requests(requests).generate("profile-id", _JPEG_BYTES)

    prompt = _form_value(requests[0].content, "prompt")
    assert prompt.index("FIRST image") < prompt.index("Transform the provided photo")
    assert "Preserve the original person's gender, recognizable facial features" in prompt
    assert "matching the exact visual style of the reference male chibi illustration" in prompt
    assert "**Negative constraints**" in prompt
    assert "no extra people, no text, and no logos." in prompt
    # 옛 블라인드 화풍 지시가 새 프롬프트와 섞여 남으면 서로 모순된다.
    assert "Simplify only the face" not in prompt
    assert "two tall black oval dots" not in prompt


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


@pytest.mark.parametrize(("ready_count", "cost"), [(0, 0), (1, 0), (2, 10), (5, 10)])
def test_avatar_regen_cost_is_free_once_after_the_first_avatar(ready_count, cost):
    # 0 = 온보딩 첫 생성, 1 = 다음 한 번 무료, 2 이상 = 10하트(ERD 12줄, spec 93줄).
    assert avatar_regen_cost(ready_count) == cost
