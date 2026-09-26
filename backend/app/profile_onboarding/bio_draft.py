from openai import AsyncOpenAI

# 재료는 성향 설문·MBTI·종교·흡연 + 관심사 태그(04-5) + 나의 특징(04-6)뿐이다 — 이상형 답변은 자기소개 재료에서 제외한다
# (자기소개는 나에 대한 글이라서, 설계 §13-72).
_SYSTEM_PROMPT = (
    "너는 대학생 소개팅 앱의 자기소개 초안을 써주는 도우미야. "
    "2~3문장, 담백하고 과하지 않은 톤으로, 존댓말로 써줘. 이모지는 쓰지 마."
)

# 설문 9축 양 끝 문구 — 앱 화면(frontend survey_screen.dart `_axes`)의 left·right 를 질문 없이도 읽히게
# 풀어 썼다(4·6·7·8축). 값은 -1~1, 0 은 가운데라 뺀다.
_AXIS_ENDS = {
    1: ("집이 편해요", "밖이 좋아요"), 2: ("낯을 많이 가려요", "금방 친해져요"),
    3: ("즉흥적이에요", "계획적이에요"), 4: ("필요할 때만 연락해요", "자주 연락해요"),
    5: ("담백해요", "표현이 풍부해요"), 6: ("술은 거의 안 마셔요", "술자리를 자주 즐겨요"),
    7: ("운동엔 관심 없어요", "운동을 꾸준히 해요"), 8: ("관계는 천천히요", "관계는 빠르게요"),
    9: ("익숙한 게 편해요", "새로운 걸 찾아요"),
}
# 화면 라벨(frontend profile_enums.dart ReligionLabel)과 같은 문구다.
_RELIGION_LABELS = {"none": "무교", "protestant": "기독교", "catholic": "천주교", "buddhist": "불교"}


def survey_summary(
    answers: dict[int, float], mbti: str | None, religion: str | None, is_smoker: bool | None
) -> str:
    """학교·학과·키는 넣지 않는다 — 자기소개가 신상 소개로 흐르지 않게(2026-09-26 실기기 e)."""
    parts = [_AXIS_ENDS[axis][value > 0] for axis, value in sorted(answers.items()) if value and axis in _AXIS_ENDS]
    if mbti:
        parts.append(f"MBTI {mbti}")
    if religion in _RELIGION_LABELS:
        parts.append(f"종교 {_RELIGION_LABELS[religion]}")
    if is_smoker is not None:
        parts.append("흡연" if is_smoker else "비흡연")
    return ", ".join(parts)


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
