"""졸업증명서 글자(Vision OCR) → 관리자 화면 미리 채우기 값. 자동 승인에는 쓰지 않는다 — 번호는 사람이 발급 기관에서 확인한다."""
import re
from collections.abc import Sequence
from typing import NamedTuple

from app.graduate_verification.hashing import normalize_document_number

# 라벨 뒤 같은 줄 또는 바로 다음 줄의 영숫자 덩어리(공백 · 하이픈으로 이어진 2자 이상 토막들).
# 한국 대학 · 정부24 양식의 번호 라벨. 서울대학교 양식은 "원본대조번호"다(제 ○○ 호 · 학위등록번호는 문서확인번호가 아니라 넣지 않는다).
# 라벨 글자 사이 공백은 허용한다(양식이 글자를 벌려 찍으면 OCR 이 그대로 읽는다).
_LABEL_WORDS = ("원본대조번호", "문서확인번호", "문서번호", "확인번호", "발급번호")
_LABEL = "(?:" + "|".join(r"\s*".join(word) for word in _LABEL_WORDS) + ")"
_NUMBER_AFTER_LABEL = re.compile(
    _LABEL + r"[ \t]*[:：]?[ \t]*\n?[ \t]*([A-Za-z0-9]{2,}(?:[ \t-][A-Za-z0-9]{2,})*)"
)


class CertificateReading(NamedTuple):
    document_number: str | None
    school_names: tuple[str, ...]


def read_certificate(text: str, university_names: Sequence[str]) -> CertificateReading:
    return CertificateReading(_document_number(text), _school_names(text, university_names))


def _document_number(text: str) -> str | None:
    for found in _NUMBER_AFTER_LABEL.finditer(text):
        number = normalize_document_number(found.group(1))
        if number is not None:
            return number
    return None


def _school_names(text: str, university_names: Sequence[str]) -> tuple[str, ...]:
    haystack = _normalize(text)
    found = [name for name in dict.fromkeys(university_names) if _normalize(name) and _normalize(name) in haystack]
    # 더 긴 학교 이름의 일부로만 잡힌 이름(서울대학교 ⊂ 서울대학교사범대)은 뺀다 — 가장 긴 일치만 남긴다.
    return tuple(name for name in found
                 if not any(name != other and _normalize(name) in _normalize(other) for other in found))


def _normalize(value: str) -> str:
    # student_verification/matching.py 의 같은 이름 함수와 같은 규칙이다(그쪽은 비공개라 복사한다).
    return "".join(value.lower().split())
