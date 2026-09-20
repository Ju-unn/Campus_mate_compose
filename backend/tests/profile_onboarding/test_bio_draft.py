from unittest.mock import AsyncMock

from app.profile_onboarding.bio_draft import generate_bio_draft


async def test_generate_bio_draft_returns_completion_text():
    openai_client = AsyncMock()
    openai_client.chat.completions.create.return_value.choices = [
        AsyncMock(message=AsyncMock(content="안녕하세요! 활발하고 여행을 좋아해요."))
    ]
    draft = await generate_bio_draft(
        openai_client, survey_summary="외향적", interest_tags=["여행", "카페"], my_traits=["유머있는"]
    )
    assert draft == "안녕하세요! 활발하고 여행을 좋아해요."


async def test_generate_bio_draft_uses_gpt_4o_mini():
    openai_client = AsyncMock()
    openai_client.chat.completions.create.return_value.choices = [
        AsyncMock(message=AsyncMock(content="초안"))
    ]
    await generate_bio_draft(openai_client, survey_summary="", interest_tags=[], my_traits=[])
    _, kwargs = openai_client.chat.completions.create.call_args
    assert kwargs["model"] == "gpt-4o-mini"
