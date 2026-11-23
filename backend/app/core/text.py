"""사람이 적는 글 칸의 공용 검사(11-18 검토: 널 문자 500 · 0폭 문자 · 제어 문자).

- SafeText(여러 줄 칸): 제어 문자 중 탭 · 줄바꿈(\\t \\n \\r)만 받는다. 널 문자는 Postgres text 가 못 담아 저장에서 500 이 났다.
- SafeLine(한 줄 칸): 제어 문자를 모두(탭 · 줄바꿈 포함) 거절한다.
- 둘 다 글 방향을 뒤집는 문자(U+202A–202E, U+2066–2069)를 거절한다 — 화면에 보이는 글과 실제 글이 달라진다.
- visible(): 0폭 문자(U+200B · 200C · 200D · 2060 · FEFF)와 앞뒤 공백을 뺀 값. 빈 값 · 최소 길이를 잴 때만 쓴다(저장 값은 그대로).
"""
import unicodedata
from typing import Annotated

from pydantic import AfterValidator, StringConstraints

ZERO_WIDTH = frozenset(map(chr, (0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF)))
_BIDI = frozenset(map(chr, (*range(0x202A, 0x202F), *range(0x2066, 0x206A))))
_LINE_BREAKS = frozenset("\t\n\r")


def visible(text: str) -> str:
    return "".join(ch for ch in text if ch not in ZERO_WIDTH).strip()


def has_bad_char(text: str, *, multiline: bool) -> bool:
    allowed = _LINE_BREAKS if multiline else frozenset()
    return any(ch in _BIDI or (unicodedata.category(ch) == "Cc" and ch not in allowed) for ch in text)


def _safe_text(text: str) -> str:
    if has_bad_char(text, multiline=True):
        raise ValueError("쓸 수 없는 문자가 있어요")
    return text


def _safe_line(text: str) -> str:
    if has_bad_char(text, multiline=False):
        raise ValueError("한 줄로 적어 주세요")
    return text


def require_visible(text: str) -> str:
    """0폭 문자 · 공백만인 글은 빈 글이다."""
    if not visible(text):
        raise ValueError("내용을 입력해 주세요")
    return text


# StringConstraints 와 같이 쓸 때는 검사기를 **뒤에** 둔다: Annotated[str, StringConstraints(...), SAFE_TEXT].
# 앞에 두면(Annotated[SafeText, StringConstraints(...)]) strip_whitespace 뒤의 min_length 를 pydantic 이 건너뛰어 공백만인 값이 통과한다.
SAFE_TEXT = AfterValidator(_safe_text)
SAFE_LINE = AfterValidator(_safe_line)
SafeText = Annotated[str, SAFE_TEXT]
SafeLine = Annotated[str, SAFE_LINE]


def body_text(max_length: int):
    """사람이 쓰는 여러 줄 본문 칸 하나의 검사 — 투표 질문 · 게시물 본문 · 댓글이 길이만 달리해 같이 쓴다.
    앞뒤 공백을 깎은 뒤 1~max_length 자, 널 · 제어 · 글 방향 문자 거절, 0폭 문자 · 공백만이면 빈 글."""
    return Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=max_length), SAFE_TEXT,
                     AfterValidator(require_visible)]
