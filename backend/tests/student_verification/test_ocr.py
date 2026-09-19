from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.student_verification.ocr import VisionOcr


def make_response(descriptions: list[str], error_message: str = "") -> SimpleNamespace:
    annotations = [SimpleNamespace(description=d) for d in descriptions]
    return SimpleNamespace(
        error=SimpleNamespace(message=error_message),
        text_annotations=annotations,
    )


async def test_extract_text_returns_first_annotation_description():
    client = AsyncMock()
    client.text_detection.return_value = make_response(["학생증 홍길동 2024학년도", "학생증"])
    ocr = VisionOcr(client)

    result = await ocr.extract_text(b"fake-image-bytes")

    assert result == "학생증 홍길동 2024학년도"


async def test_extract_text_returns_empty_string_when_no_annotations():
    client = AsyncMock()
    client.text_detection.return_value = make_response([])
    ocr = VisionOcr(client)

    result = await ocr.extract_text(b"fake-image-bytes")

    assert result == ""


async def test_extract_text_raises_on_vision_error():
    client = AsyncMock()
    client.text_detection.return_value = make_response([], error_message="429 quota exceeded")
    ocr = VisionOcr(client)

    with pytest.raises(RuntimeError, match="429 quota exceeded"):
        await ocr.extract_text(b"fake-image-bytes")
