from unittest.mock import AsyncMock

from app.profile_onboarding.photos import check_safe_search


async def test_check_safe_search_rejects_likely_adult_content():
    vision_client = AsyncMock()
    vision_client.safe_search_detection.return_value.safe_search_annotation.adult = 4  # LIKELY
    vision_client.safe_search_detection.return_value.safe_search_annotation.violence = 1
    result = await check_safe_search(vision_client, b"fake-image-bytes")
    assert result is False


async def test_check_safe_search_rejects_likely_violent_content():
    vision_client = AsyncMock()
    vision_client.safe_search_detection.return_value.safe_search_annotation.adult = 1
    vision_client.safe_search_detection.return_value.safe_search_annotation.violence = 5  # VERY_LIKELY
    result = await check_safe_search(vision_client, b"fake-image-bytes")
    assert result is False


async def test_check_safe_search_accepts_clean_photo():
    vision_client = AsyncMock()
    vision_client.safe_search_detection.return_value.safe_search_annotation.adult = 1  # VERY_UNLIKELY
    vision_client.safe_search_detection.return_value.safe_search_annotation.violence = 1
    result = await check_safe_search(vision_client, b"fake-image-bytes")
    assert result is True
