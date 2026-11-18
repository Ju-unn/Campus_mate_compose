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
