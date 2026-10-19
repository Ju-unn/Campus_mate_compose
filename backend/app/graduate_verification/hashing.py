"""졸업생 중복 가입 방지용 해시(D5). 학교 메일 해시(signup_policy.hash_email)와 같은 키(identity_hmac_key)를 쓰되
입력 앞에 이름공간 접두사를 붙여 서로 겹치지 않게 한다. 평문은 저장하지 않는다 — 해시만 DB 로 간다."""
import hashlib
import hmac
import re

_DOCUMENT_PREFIX = "graduate-document|"
_STUDENT_PREFIX = "graduate-student|"
_DOCUMENT = re.compile(r"[A-Z0-9]{4,40}")
_STUDENT = re.compile(r"[A-Z0-9]{1,20}")


def _squash(raw: str) -> str:
    return re.sub(r"[\s-]", "", raw).upper()


def normalize_document_number(raw: str) -> str | None:
    """공백 · 하이픈을 떼고 대문자로. 영숫자 4~40자가 아니면 None(한글이 섞이면 OCR 이 엉뚱한 글자를 읽은 것이다)."""
    text = _squash(raw)
    return text if _DOCUMENT.fullmatch(text) else None


def normalize_student_number(raw: str) -> str | None:
    """공백 · 하이픈을 떼고 대문자로. 영숫자 1~20자가 아니면 None(관리자 입력 상한 20자와 같다)."""
    text = _squash(raw)
    return text if _STUDENT.fullmatch(text) else None


def _hmac(secret: str, message: str) -> bytes:
    return hmac.new(secret.encode(), message.encode(), hashlib.sha256).digest()


def hash_document_number(secret: str, number: str) -> bytes:
    """같은 증명서를 두 계정에 쓰는 것을 막는 해시. 입력은 정규화되는 값이라 표기가 달라도 같다. 정규화할 수 없으면 ValueError."""
    normalized = normalize_document_number(number)
    if normalized is None:
        raise ValueError("문서확인번호 형식이 아니다")
    return _hmac(secret, f"{_DOCUMENT_PREFIX}{normalized}")


def hash_student_number(secret: str, university_id: str, student_number: str) -> bytes:
    """같은 사람이 새 증명서로 두 계정을 만드는 것 · 탈퇴 뒤 재가입을 막는 해시. 학교마다 학번 공간이 달라 학교 id 를 넣는다."""
    normalized = normalize_student_number(student_number)
    if normalized is None:
        raise ValueError("학번 형식이 아니다")
    return _hmac(secret, f"{_STUDENT_PREFIX}{university_id}|{normalized}")
