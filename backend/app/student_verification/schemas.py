from pydantic import BaseModel, Field


class VerificationStatusResponse(BaseModel):
    status: str
    has_school_info: bool
    reject_reason: str | None = None


class SchoolInfoRequest(BaseModel):
    # 프론트 Department·StudentNumber 값 객체(frontend/lib/auth/model/department.dart·student_number.dart,
    # 2026-09-20 분석담당 리뷰)와 상한을 맞춘다 — department 30자, student_number 20자.
    department: str = Field(min_length=1, max_length=30)
    student_number: str = Field(min_length=1, max_length=20)
