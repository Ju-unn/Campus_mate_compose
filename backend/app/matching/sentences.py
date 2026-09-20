"""매칭 문장 2종을 서버 템플릿으로 조립한다(설계 §6.3·§6.7 — LLM 을 쓰지 않는다).

앞부분(학과·계열·MBTI·얼굴상)만 템플릿이 만들고, 자기소개와 "이런 사람이 좋아요" 글은 사용자가 쓴
원문을 그대로 이어붙인다. 재료가 없는 자리는 문장째로 뺀다 — 빈칸이 들어간 문장을 임베딩하면
"MBTI는 다" 같은 잡음이 벡터에 섞인다."""

# 화면 라벨(frontend profile_enums.dart)과 같은 문구다.
ANIMAL_LABELS = {
    "dog": "강아지상", "cat": "고양이상", "fox": "여우상", "bear": "곰상",
    "rabbit": "토끼상", "deer": "사슴상", "wolf": "늑대상", "hamster": "햄스터상",
}

# 인상은 화면 라벨("선한상")을 그대로 쓰면 "선한상 인상이다" 가 돼 어색하다 — 문장용 표현을 따로 둔다
# (설계 §6.7 예시의 "부드러운 인상"이 이 자리다).
IMPRESSION_PHRASES = {
    "arab": "이국적인", "tofu": "부드러운", "kind": "선한", "chic": "시크한", "innocent": "청순한",
}

MAJOR_FIELD_LABELS = {
    "humanities": "인문", "social": "사회", "business": "상경", "engineering": "공대",
    "natural_science": "자연과학", "medical": "의약", "arts_sports": "예체능", "education": "교육",
}


def _has_final_consonant(word: str) -> bool:
    """마지막 글자에 받침이 있으면 "이나", 없으면 "나" 를 붙인다(한글 음절 = 0xAC00 + 28 × n + 받침)."""
    last = word[-1]
    return "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 != 0


def _join_or(words: list[str]) -> str:
    joined = words[0]
    for word in words[1:]:
        joined += ("이나 " if _has_final_consonant(joined) else "나 ") + word
    return joined


def self_sentence(profile: dict) -> str:
    parts: list[str] = []

    major, field = profile.get("major"), MAJOR_FIELD_LABELS.get(profile.get("major_field") or "")
    if major and field:
        parts.append(f"나는 {major}, {field} 계열 학생이다.")
    elif major:
        parts.append(f"나는 {major} 학생이다.")

    if profile.get("mbti"):
        parts.append(f"MBTI는 {profile['mbti']}다.")

    animal = ANIMAL_LABELS.get(profile.get("animal_type") or "")
    impression = IMPRESSION_PHRASES.get(profile.get("impression_type") or "")
    if animal and impression:
        parts.append(f"얼굴은 {animal}이고 {impression} 인상이다.")

    if (profile.get("bio") or "").strip():
        parts.append(profile["bio"].strip())

    return " ".join(parts)


def want_sentence(profile: dict) -> str:
    parts: list[str] = []

    animals = [ANIMAL_LABELS[a] for a in profile.get("preferred_animal_types") or [] if a in ANIMAL_LABELS]
    impressions = [
        IMPRESSION_PHRASES[i] for i in profile.get("preferred_impression_types") or []
        if i in IMPRESSION_PHRASES
    ]
    wanted = []
    if animals:
        wanted.append(_join_or(animals))
    if impressions:
        wanted.append(f"{_join_or(impressions)} 인상")
    if wanted:
        parts.append(f"{', '.join(wanted)}이 좋다.")

    if (profile.get("ideal_note") or "").strip():
        parts.append(profile["ideal_note"].strip())

    return " ".join(parts)
