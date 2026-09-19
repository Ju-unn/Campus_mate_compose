from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel


class _HookUser(BaseModel):
    # 이 이메일은 Supabase 가 가입 절차에서 이미 형식을 검증한 뒤 훅으로 보낸다
    # (EmailStr 은 email-validator 라는 새 의존성이 필요해 안 쓴다 — YAGNI).
    email: str


class BeforeUserCreatedPayload(BaseModel):
    user_id: UUID
    user: _HookUser

    @property
    def email(self) -> str:
        return self.user.email.lower()

    @property
    def email_domain(self) -> str:
        return self.email.rsplit("@", 1)[-1]


class HookDecision(BaseModel):
    decision: Literal["continue", "reject"]
    message: str | None = None

    @classmethod
    def allow(cls) -> "HookDecision":
        return cls(decision="continue")

    @classmethod
    def reject(cls, message: str) -> "HookDecision":
        return cls(decision="reject", message=message)
