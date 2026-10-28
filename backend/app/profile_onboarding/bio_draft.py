import re

from openai import AsyncOpenAI

# 재료는 성향 설문 + 관심사 태그(04-5) + 나의 특징(04-6)뿐이다 — 이상형 답변은 자기소개 재료에서 제외한다
# (자기소개는 나에 대한 글이라서, 설계 §13-72). 종교 · 흡연도 뺀다 — 민감정보이고 상세 화면 정보 칸에 이미 보인다.
# 프롬프트 원본: 바탕화면 출시준비/GPT_소개글_프롬프트.md §5 + 2026-10-15 대장 지시(§7 전부 A 채택, 2~3문장).
# 2026-10-28: 성향 설문은 성향 점수(30%)가 이미 비교한다 — 글에 옮기면 글 점수(50%)가 같은 정보를 다시 센다(재검증 H9).
#   설문은 말투 · 분위기 재료로만 넘기고, 글은 태그 목록이 못 담는 구체적인 모습을 쓰게 한다.
# 2026-10-28: MBTI 도 뺀다 — 매칭은 MBTI 계수로 따로 비교한다. 글에 들어가면 글 점수가 같은 정보를 다시 센다.
# 초안은 사람마다 한 번 만들어 저장하므로(router bio-draft) 여기를 고쳐도 이미 받은 초안은 그대로다.
_SYSTEM_PROMPT = """너는 대학생 소개팅 앱에서 사용자의 자기소개 초안을 대신 써 주는 도우미야.
아래 규칙을 반드시 지켜.

[언어]
- 한국어로만 써. 영어 단어, 영어 문장, 로마자를 쓰지 마.
- 예외는 딱 하나: 관심사 이름에 원래 있는 영문(예: IT)은 그대로 써도 돼.

[내용]
- 사용자가 직접 쓴 것처럼 1인칭("저는")으로, 자연스럽고 담백한 존댓말(~해요체)로 써.
- MBTI 이야기는 하지 마.
- 관심사와 나의 특징 중에서 3~4가지를 골라, 그걸로 보내는 하루나 주말 모습처럼 이야기로 엮어. 목록을 그대로 나열하지 마.
- 성향 설문 답을 문장으로 옮기지 마(낯가림, 연락 빈도, 관계 속도, 술자리, 계획성, 집이 편한지 같은 것). 성향은 말투와 분위기에만 담아.
- 주어진 정보에 없는 사실(전공, 직업, 사는 곳, 키, 나이, 학교, 가족 등)을 지어내지 마.

[형식]
- 전체 2~3문장 안팎으로 쓰고, 2~3개 문단으로 나눠.
- 문단과 문단 사이는 줄바꿈 한 번(\\n)으로만 나눠. 빈 줄을 넣지 마.
- 전체 120~220자.
- 제목, 따옴표, 머리말("자기소개:" 같은 것), 해시태그, 목록 기호, 이모지, 특수문자 장식을 쓰지 마.

[금지]
- 실명, 닉네임, 학교 이름, 학과, 학번, 전화번호, 카카오톡 아이디, SNS 아이디, 사는 곳을 쓰지 마.
- 종교와 흡연 여부는 쓰지 마.
- 외모 자랑, 신체 부위, 성적인 표현, 연봉 · 재산 이야기를 쓰지 마.
- "AI가 썼어요" 같은 말이나 설명을 붙이지 마. 소개글 본문만 출력해."""

# 설문 9축 양 끝 문구 — 앱 화면(frontend survey_screen.dart `_axes`)의 left·right 를 질문 없이도 읽히게
# 풀어 썼다(4·6·7·8축). 값은 -1~1, 0 은 가운데라 뺀다.
_AXIS_ENDS = {
    1: ("집이 편해요", "밖이 좋아요"), 2: ("낯을 많이 가려요", "금방 친해져요"),
    3: ("즉흥적이에요", "계획적이에요"), 4: ("필요할 때만 연락해요", "자주 연락해요"),
    5: ("담백해요", "표현이 풍부해요"), 6: ("술은 거의 안 마셔요", "술자리를 자주 즐겨요"),
    7: ("운동엔 관심 없어요", "운동을 꾸준히 해요"), 8: ("관계는 천천히요", "관계는 빠르게요"),
    9: ("익숙한 게 편해요", "새로운 걸 찾아요"),
}
# 프롬프트만으로는 영어가 100% 빠지지 않는다 — 남으면 한 번만 다시 만들고, 그래도 남으면 마지막 것을 쓴다.
# 빈 답이면 다시 묻고 앞 초안을 유지한다 — 두 번 다 비면 빈 값("")을 돌려준다.
_ATTEMPTS = 2
_LATIN_WORD = re.compile(r"[A-Za-z]+")


def survey_summary(answers: dict[int, float]) -> str:
    """학교·학과·키는 넣지 않는다 — 자기소개가 신상 소개로 흐르지 않게(2026-09-26 실기기 e)."""
    return ", ".join(
        _AXIS_ENDS[axis][value > 0] for axis, value in sorted(answers.items()) if value and axis in _AXIS_ENDS
    )


def _tidy(draft: str) -> str:
    """빈 줄은 줄바꿈 한 번으로 줄이고 앞뒤 공백을 자른다 — 앱 입력칸(8줄)에 문단이 그대로 들어가게."""
    return re.sub(r"\n\s*\n", "\n", draft).strip()


def _has_stray_english(draft: str, allowed: set[str]) -> bool:
    return any(word.upper() not in allowed for word in _LATIN_WORD.findall(draft))


async def generate_bio_draft(
    openai_client: AsyncOpenAI, survey_summary: str, interest_tags: list[str], my_traits: list[str]
) -> str:
    user_prompt = (
        f"성향: {survey_summary or '없음'}\n"
        f"관심사: {', '.join(interest_tags)}\n나의 특징: {', '.join(my_traits)}"
    )
    # 관심사 이름에 원래 있는 영문(지금은 'IT' 하나)만 영어로 치지 않는다 — MBTI 가 나오면 다시 만든다.
    allowed = {word.upper() for word in _LATIN_WORD.findall(" ".join(interest_tags))}
    draft = ""  # 두 번 다 비면 "" — 부른 쪽(router bio-draft)이 생성 실패로 다룬다
    for _ in range(_ATTEMPTS):
        response = await openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.7,
            max_tokens=300,
        )
        # 거부 등으로 content 가 None 이거나 비면 영어가 남았을 때처럼 다시 묻고, 앞의 초안을 지우지 않는다.
        made = _tidy(response.choices[0].message.content or "")
        draft = made or draft
        if made and not _has_stray_english(made, allowed):
            break
    return draft
