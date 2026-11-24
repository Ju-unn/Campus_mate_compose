import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.core.junk_text import has_letter_run
from app.core.text import has_bad_char, visible
from app.profile_onboarding.schemas import AcademicStatus


class GraduateState(BaseModel):
    """졸업생 길을 고르고 아직 인증 전인 사람의 신청 상태. 대기(pending) 또는 반려(rejected)일 때만 있다 —
    신청이 없거나 취소된 사람은 graduate 가 null 이고 앱은 신청 폼을 보인다(횟수가 없으면 신청 때 429)."""

    state: Literal["pending", "rejected"]
    reject_reason: str | None = None
    attempts_left: int
    submitted_at: str | None = None


class VerificationStatusResponse(BaseModel):
    status: str
    has_school_info: bool
    reject_reason: str | None = None
    # 가입 동의(02-c)가 첫 관문이라 인증 전에도 닿는 이 응답에 싣는다. outdated = 옛 판만 있음(재동의).
    consent: Literal["none", "outdated", "current"]
    # 소셜 로그인 전환: 학교 메일 확인(POST /school-email/verify)을 마쳤는지. 옛 앱은 이 칸을 모른다 — 더하기만 한다.
    school_email_verified: bool
    # 졸업생 인증(졸업증명서) 길. 아래 세 칸은 기본값이 있어 옛 서버 응답과 호환되고, 옛 앱은 읽지 않는다.
    # graduate_enabled 가 false 면 새 앱도 방법 고르기를 숨기고 지금 관문(학교 메일)을 쓴다.
    graduate_enabled: bool = False
    # null = 아직 안 골랐다(= 학교 메일로 간주).
    verification_method: Literal["school_email", "graduate_certificate"] | None = None
    graduate: GraduateState | None = None


class SchoolInfoRequest(BaseModel):
    # 프론트 Department·StudentNumber 값 객체(frontend/lib/auth/school_info/model/data/department.dart·student_number.dart,
    # 2026-09-20 분석담당 리뷰)와 상한을 맞춘다 — department 30자, student_number 20자.
    department: str = Field(min_length=1, max_length=30)
    student_number: str = Field(min_length=1, max_length=20)
    # compat(1.0.6): 옛 앱은 신분을 안 보냄(칸 없음 = 안 씀, null 그대로) — MIN_APP_VERSION 1.0.7 뒤 삭제하고 필수로
    academic_status: AcademicStatus | None = None

    @field_validator("academic_status")
    @classmethod
    def _no_null_status(cls, status: str | None) -> str | None:
        # 칸을 빼는 것(옛 앱)만 허락한다. null 을 실어 보내는 앱은 없다 — 오면 앱 버그다.
        if status is None:
            raise ValueError("신분을 골라 주세요")
        return status

    def has_valid_student_number(self) -> bool:
        # compat(1.0.6): 3c 학번 1~3자리 허용(옛 앱 입력) — MIN_APP_VERSION 1.0.7 뒤 삭제하고 me/schemas.py is_valid_student_number(2자리) 하나로 합친다
        # 학번은 숫자 1~3자리(10-29 사용자 결정, 예: 21). [0-9] 로 쓴다 — \d 는 전각 숫자(２１)도 받는다.
        # pattern 으로 걸면 422 detail 이 목록이라 앱이 "알 수 없는 오류"를 띄워 라우터에서 문자열로 거절한다.
        return re.fullmatch(r"[0-9]{1,3}", self.student_number) is not None


def is_valid_department(department: str) -> bool:
    """학과 규칙 한 곳 — 학과 제출(POST /school-info)과 3c 다시 띄우기(GET /me/verification-status 의 has_school_info)가 같이 쓴다.

    운영에 학과 "." 가 들어왔다(11-18). 앞뒤 공백을 뺀 2~30자, 완성 한글 · 영문이 하나는 있고(숫자 · 기호만은 안 됨),
    자음 · 모음 낱자(옛 자모 포함 U+3130–318F) · 제어 문자(줄바꿈 · 탭)가 없고, 같은 글자 3번 연속이 아니어야 한다.
    제어 문자는 strip 전에 본다 — "컴공" 끝의 줄바꿈이 strip 에 사라진다."""
    text = department.strip()
    return (
        # 하한은 0폭 문자를 뺀 길이로 잰다("가" + U+200B 는 1자다). 상한은 앱 칸 30자와 같다.
        2 <= len(visible(text)) and len(text) <= 30
        # 제어 문자(줄바꿈 · 탭 포함) · 글 방향 문자는 한 줄 칸 규칙(core/text.py)으로 원문에서 본다.
        and not has_bad_char(department, multiline=False)
        and re.search(r"[가-힣a-zA-Z]", text) is not None
        and re.search(r"[\u3130-\u318f]", text) is None
        and not has_letter_run(text, alphabet_order=False)  # 학과는 같은 글자 3번만(알파벳 순서는 실제 학과가 걸린다, 11-18 사용자 ②)
    )
