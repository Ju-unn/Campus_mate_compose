"""닉네임 · 학과의 장난 입력 판정(11-18 사용자: 운영에 닉네임 "aaa" · 학과 "." 가 들어왔다).

새로 쓰는 값만 막는다 — DB 제약은 그대로라 예전에 들어온 값은 남는다.
"""
from string import ascii_lowercase


def has_letter_run(text: str, *, alphabet_order: bool = True) -> bool:
    """같은 글자 3번 연속("aaa" · "가가가") 또는 알파벳 순서 3글자("abc" · "cba"), 대소문자 무시.
    2번 반복("진진" · "땅땅이")은 실제 이름에 있어 둔다.
    학과는 alphabet_order=False — "Korean Studies"(stu) · "Defense"(def) 같은 실제 학과가 걸려서다(11-18 사용자 ②)."""
    lowered = text.lower()
    for a, b, c in zip(lowered, lowered[1:], lowered[2:]):
        if a == b == c:
            return True
        step = ord(b) - ord(a)
        if alphabet_order and {a, b, c} <= set(ascii_lowercase) and step in (1, -1) and ord(c) - ord(b) == step:
            return True
    return False


# 운영진 사칭 · 비속어(11-20 사용자 결정 목록). 5글자 넘는 말은 지금 닉네임 규칙(2~5자)에 안 걸리지만 길이가 바뀔 때를 위해 둔다.
BANNED_WORDS = (
    "운영", "관리", "개발", "매니저", "공식", "고객센터", "캠퍼스", "캠메", "시스템", "마스터", "어드민", "스태프",
    "admin", "master", "staff", "official", "system", "support", "campus",
    "시발", "씨발", "씨빨", "병신", "븅신", "좆", "존나", "개새", "새끼", "섹스", "느금", "애미",
    "sex", "fuck", "shit", "bitch",
)


# 닉네임 전체가 이 말일 때만 막는다 — "하니미" 같은 평범한 이름에 들어 있어서다(11-20 사용자 「"니미"만 단어로」).
BANNED_EXACT_WORDS = ("니미",)


def has_banned_word(text: str) -> bool:
    """금지어가 어디든 들어 있거나(BANNED_WORDS) 닉네임 전체가 단어 금지어면(BANNED_EXACT_WORDS) True, 대소문자 무시."""
    lowered = text.lower()
    return lowered in BANNED_EXACT_WORDS or any(word in lowered for word in BANNED_WORDS)
