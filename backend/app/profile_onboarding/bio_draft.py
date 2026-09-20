from openai import AsyncOpenAI

# 재료는 성향 설문 + 관심사 태그(04-5) + 나의 특징(04-6)뿐이다 — 이상형 답변은 자기소개 재료에서 제외한다
# (자기소개는 나에 대한 글이라서, 설계 §13-72).
_SYSTEM_PROMPT = (
    "너는 대학생 소개팅 앱의 자기소개 초안을 써주는 도우미야. "
    "2~3문장, 담백하고 과하지 않은 톤으로, 존댓말로 써줘. 이모지는 쓰지 마."
)


async def generate_bio_draft(
    openai_client: AsyncOpenAI, survey_summary: str, interest_tags: list[str], my_traits: list[str]
) -> str:
    user_prompt = (
        f"성향: {survey_summary}\n관심사: {', '.join(interest_tags)}\n나의 특징: {', '.join(my_traits)}"
    )
    response = await openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )
    return response.choices[0].message.content
