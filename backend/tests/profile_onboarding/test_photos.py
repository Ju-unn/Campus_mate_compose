from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from google.cloud import vision

from app.profile_onboarding.photos import check_safe_search


def make_client(adult: int, violence: int, error_message: str = "") -> AsyncMock:
    """batch_annotate_images 의 응답 모양 — 이미지 하나당 responses 한 칸.

    spec 을 주지 않으면 없는 메서드까지 만들어 내서 오타·API 불일치를 테스트가 못 잡는다
    (2026-09-25 운영: 비동기 클라이언트에 없는 safe_search_detection 을 불러 500).
    """
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.return_value = SimpleNamespace(
        responses=[
            SimpleNamespace(
                error=SimpleNamespace(message=error_message),
                safe_search_annotation=SimpleNamespace(adult=adult, violence=violence),
            )
        ]
    )
    return client


async def test_check_safe_search_rejects_likely_adult_content():
    result = await check_safe_search(make_client(adult=4, violence=1), b"fake-image-bytes")  # LIKELY
    assert result is False


async def test_check_safe_search_rejects_likely_violent_content():
    result = await check_safe_search(make_client(adult=1, violence=5), b"fake-image-bytes")  # VERY_LIKELY
    assert result is False


async def test_check_safe_search_accepts_clean_photo():
    client = make_client(adult=1, violence=1)  # VERY_UNLIKELY

    result = await check_safe_search(client, b"fake-image-bytes")

    assert result is True
    client.batch_annotate_images.assert_awaited_once()


async def test_check_safe_search_raises_on_vision_error():
    # 응답이 비어도 판정 필드는 0(UNKNOWN)이라 그냥 두면 실패한 검사가 "안전"으로 통과한다.
    client = make_client(adult=0, violence=0, error_message="429 quota exceeded")

    with pytest.raises(RuntimeError, match="429 quota exceeded"):
        await check_safe_search(client, b"fake-image-bytes")
