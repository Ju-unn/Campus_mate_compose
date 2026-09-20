from unittest.mock import AsyncMock

from app.profile_onboarding.avatars import AvatarGenerator, MAX_CONSECUTIVE_FAILURES


async def test_generate_returns_ready_on_first_success():
    openai_client = AsyncMock()
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]
    storage = AsyncMock()
    storage.upload.return_value = "profile-id/uuid.png"

    generator = AvatarGenerator(openai_client, storage, failure_counts={})
    result = await generator.generate("profile-id", b"source-photo")

    assert result.status == "ready"
    assert result.storage_path == "profile-id/uuid.png"


async def test_generate_counts_failures_independently_of_sdk_retries():
    # SDK 는 max_retries=0 이라 재시도하지 않는다 — 실패 카운트는 전부 이 클래스가 센다(2026-09-20 결정).
    openai_client = AsyncMock()
    openai_client.images.edit.side_effect = Exception("openai down")
    storage = AsyncMock()
    failure_counts: dict[str, int] = {}
    generator = AvatarGenerator(openai_client, storage, failure_counts)

    for _ in range(MAX_CONSECUTIVE_FAILURES - 1):
        result = await generator.generate("profile-id", b"source-photo")
        assert result.status == "failed"
        assert result.is_final_failure is False

    final = await generator.generate("profile-id", b"source-photo")
    assert final.status == "failed"
    assert final.is_final_failure is True  # 5번째부터 기본 아바타+하트10 트리거


async def test_generate_resets_failure_count_after_success():
    openai_client = AsyncMock()
    storage = AsyncMock()
    storage.upload.return_value = "path.png"
    failure_counts = {"profile-id": 3}
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]

    generator = AvatarGenerator(openai_client, storage, failure_counts)
    await generator.generate("profile-id", b"source-photo")

    assert failure_counts["profile-id"] == 0
