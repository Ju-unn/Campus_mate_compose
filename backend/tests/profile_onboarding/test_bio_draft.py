from types import SimpleNamespace
from unittest.mock import AsyncMock

from app.profile_onboarding.bio_draft import generate_bio_draft, survey_summary


def _client(*contents: str | None) -> AsyncMock:
    """부를 때마다 contents 를 차례로 돌려주는 가짜 OpenAI 클라이언트."""
    openai_client = AsyncMock()
    openai_client.chat.completions.create.side_effect = [
        SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=content))]) for content in contents
    ]
    return openai_client


async def _draft(openai_client, mbti=None, summary="밖이 좋아요", tags=("여행", "카페가기"), traits=("다정한",)):
    return await generate_bio_draft(openai_client, mbti, summary, list(tags), list(traits))


def _messages(openai_client, call=0) -> list[dict]:
    return openai_client.chat.completions.create.call_args_list[call].kwargs["messages"]


async def test_generate_bio_draft_returns_completion_text():
    draft = await _draft(_client("안녕하세요. 여행을 좋아해요."))
    assert draft == "안녕하세요. 여행을 좋아해요."


async def test_generate_bio_draft_uses_gpt_4o_mini_with_a_calm_temperature_and_a_length_cap():
    openai_client = _client("초안")
    await _draft(openai_client)
    kwargs = openai_client.chat.completions.create.call_args.kwargs
    assert (kwargs["model"], kwargs["temperature"], kwargs["max_tokens"]) == ("gpt-4o-mini", 0.7, 300)


async def test_the_system_prompt_asks_for_korean_only_paragraphs_and_no_religion_or_smoking():
    openai_client = _client("초안")
    await _draft(openai_client)
    system = _messages(openai_client)[0]["content"]
    for rule in ("한국어로만", "MBTI 네 글자", "줄바꿈 한 번", "2~3문장", "존댓말", "이모지", "종교와 흡연"):
        assert rule in system, rule


async def test_mbti_leads_the_user_prompt_and_says_none_when_not_chosen():
    chosen, unknown = _client("초안"), _client("초안")
    await _draft(chosen, mbti="ENFP", summary="밖이 좋아요, 금방 친해져요")
    await _draft(unknown, mbti=None, summary="")
    assert _messages(chosen)[1]["content"] == (
        "MBTI: ENFP\n성향: 밖이 좋아요, 금방 친해져요\n관심사: 여행, 카페가기\n나의 특징: 다정한"
    )
    assert _messages(unknown)[1]["content"].startswith("MBTI: 없음\n성향: 없음\n")


def test_survey_summary_leaves_out_religion_smoking_and_the_middle():
    assert survey_summary({1: 1, 2: -0.5, 3: 0}) == "밖이 좋아요, 낯을 많이 가려요"


async def test_an_english_word_is_made_again_only_once():
    openai_client = _client("저는 outgoing한 편이에요.", "저는 밖에 나가는 걸 좋아해요.")
    assert await _draft(openai_client) == "저는 밖에 나가는 걸 좋아해요."
    assert openai_client.chat.completions.create.await_count == 2


async def test_english_left_after_the_second_try_keeps_the_last_draft():
    openai_client = _client("vibe 가 좋아요.", "chill 한 편이에요.", "쓰이면 안 되는 세 번째")
    assert await _draft(openai_client) == "chill 한 편이에요."
    assert openai_client.chat.completions.create.await_count == 2


async def test_my_mbti_and_an_english_interest_tag_are_not_english_words():
    openai_client = _client("ENFP라서 IT 이야기를 좋아해요.")
    assert await _draft(openai_client, mbti="ENFP", tags=("IT", "여행")) == "ENFP라서 IT 이야기를 좋아해요."
    assert openai_client.chat.completions.create.await_count == 1


async def test_another_mbti_is_an_english_word():
    openai_client = _client("INTJ랑 잘 맞아요.", "저와 잘 맞는 분을 찾아요.")
    assert await _draft(openai_client, mbti="ENFP") == "저와 잘 맞는 분을 찾아요."


async def test_blank_lines_between_paragraphs_become_one_line_break():
    openai_client = _client("\n첫 문단이에요.\n\n\n둘째 문단이에요.\n \n셋째 문단이에요.\n")
    assert await _draft(openai_client) == "첫 문단이에요.\n둘째 문단이에요.\n셋째 문단이에요."


async def test_an_empty_answer_is_made_again_within_the_same_one_retry():
    """OpenAI 가 거부하면 content 가 None 이다 — 영어가 남았을 때와 같은 한 번의 다시 만들기 안에서 다시 묻는다."""
    for empty in (None, "", " \n "):
        openai_client = _client(empty, "저는 여행을 좋아해요.")
        assert await _draft(openai_client) == "저는 여행을 좋아해요.", empty
        assert openai_client.chat.completions.create.await_count == 2


async def test_two_empty_answers_give_an_empty_draft():
    openai_client = _client(None, None, "쓰이면 안 되는 세 번째")
    assert await _draft(openai_client) == ""
    assert openai_client.chat.completions.create.await_count == 2


async def test_an_empty_retry_keeps_the_first_draft_even_with_english():
    """다시 만든 답이 비면 앞의 초안(영어가 남았어도)을 쓴다 — 빈 칸보다 고쳐 쓸 글이 낫다."""
    assert await _draft(_client("vibe 가 좋아요.", None)) == "vibe 가 좋아요."
