import re
from typing import Literal

from pydantic import BaseModel, Field


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
    # 프론트 Department·StudentNumber 값 객체(frontend/lib/auth/model/department.dart·student_number.dart,
    # 2026-09-20 분석담당 리뷰)와 상한을 맞춘다 — department 30자, student_number 20자.
    department: str = Field(min_length=1, max_length=30)
    student_number: str = Field(min_length=1, max_length=20)

    def has_valid_student_number(self) -> bool:
        # 학번은 숫자 1~3자리(10-29 사용자 결정, 예: 21). [0-9] 로 쓴다 — \d 는 전각 숫자(２１)도 받는다.
        # pattern 으로 걸면 422 detail 이 목록이라 앱이 "알 수 없는 오류"를 띄워 라우터에서 문자열로 거절한다.
        return re.fullmatch(r"[0-9]{1,3}", self.student_number) is not None
