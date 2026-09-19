from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from google.cloud import vision

from app.student_verification.ocr import VisionOcr


def make_response(descriptions: list[str], error_message: str = "") -> SimpleNamespace:
    """batch_annotate_images 의 응답 모양 — 이미지 하나당 responses 한 칸."""
    annotations = [SimpleNamespace(description=d) for d in descriptions]
    return SimpleNamespace(
        responses=[
            SimpleNamespace(
                error=SimpleNamespace(message=error_message),
                text_annotations=annotations,
            )
        ]
    )


def make_client(descriptions: list[str], error_message: str = "") -> AsyncMock:
    # spec 을 주지 않으면 없는 메서드까지 만들어 내서 오타·API 불일치를 테스트가 못 잡는다.
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.return_value = make_response(descriptions, error_message)
    return client


async def test_extract_text_returns_first_annotation_description():
    client = make_client(["학생증 홍길동 2024학년도", "학생증"])
    ocr = VisionOcr(client)

    result = await ocr.extract_text(b"fake-image-bytes")

    assert result == "학생증 홍길동 2024학년도"
    client.batch_annotate_images.assert_awaited_once()


async def test_extract_text_returns_empty_string_when_no_annotations():
    ocr = VisionOcr(make_client([]))

    result = await ocr.extract_text(b"fake-image-bytes")

    assert result == ""


async def test_extract_text_raises_on_vision_error():
    ocr = VisionOcr(make_client([], error_message="429 quota exceeded"))

    with pytest.raises(RuntimeError, match="429 quota exceeded"):
        await ocr.extract_text(b"fake-image-bytes")
