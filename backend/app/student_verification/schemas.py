from typing import Literal

from pydantic import BaseModel, Field


class VerificationStatusResponse(BaseModel):
    status: str
    has_school_info: bool
    reject_reason: str | None = None
    # 가입 동의(02-c)가 첫 관문이라 인증 전에도 닿는 이 응답에 싣는다. outdated = 옛 판만 있음(재동의).
    consent: Literal["none", "outdated", "current"]
    # 소셜 로그인 전환: 학교 메일 확인(POST /school-email/verify)을 마쳤는지. 옛 앱은 이 칸을 모른다 — 더하기만 한다.
    school_email_verified: bool


class SchoolInfoRequest(BaseModel):
    # 프론트 Department·StudentNumber 값 객체(frontend/lib/auth/model/department.dart·student_number.dart,
    # 2026-09-20 분석담당 리뷰)와 상한을 맞춘다 — department 30자, student_number 20자.
    department: str = Field(min_length=1, max_length=30)
    student_number: str = Field(min_length=1, max_length=20)
