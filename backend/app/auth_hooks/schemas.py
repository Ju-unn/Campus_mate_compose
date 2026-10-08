from __future__ import annotations

from pydantic import BaseModel


class _HookUser(BaseModel):
    # 이 이메일은 Supabase 가 가입 절차에서 이미 형식을 검증한 뒤 훅으로 보낸다
    # (EmailStr 은 email-validator 라는 새 의존성이 필요해 안 쓴다 — YAGNI).
    # 소셜(카카오)은 이메일 없이 가입할 수 있어 비어 올 수 있다.
    email: str = ""
    # 가입 수단은 GoTrue 사용자 객체의 app_metadata.provider 에 온다(email · kakao · google · apple ...).
    app_metadata: dict | None = None


class BeforeUserCreatedPayload(BaseModel):
    # Supabase 가 실제로 보내는 본문은 {"metadata": {...}, "user": {...}} 다.
    # 최상위 `user_id` 를 필수로 두는 바람에 훅이 500 으로 죽었다 (2026-09-22 실기기 테스트).
    # 쓰는 곳이 없는 필드라 되살리지 않고 지운다. `metadata` 는 pydantic 이 알아서 흘린다.
    user: _HookUser

    @property
    def provider(self) -> str | None:
        """못 읽으면 None — 훅은 None 을 거절한다(실패하면 열지 않는다)."""
        provider = (self.user.app_metadata or {}).get("provider")
        return provider if isinstance(provider, str) and provider else None

    @property
    def email(self) -> str:
        return self.user.email.lower()

    @property
    def email_domain(self) -> str:
        return self.email.rsplit("@", 1)[-1]


class _HookError(BaseModel):
    http_code: int
    message: str


class HookDecision(BaseModel):
    # GoTrue 의 before-user-created 출력은 빈 구조체라 `decision` 을 읽지 않는다 — 옛 {"decision": "reject"}
    # 는 통과로 읽혀 재가입 제한이 뚫렸다(2026-10-03). 거절은 200 본문의 `error` 객체로만 읽힌다
    # (4xx 상태면 본문을 안 읽고 500 으로 바꾼다 — supabase/auth internal/hooks/hookshttp).
    # 422 는 앱이 "가입 거절" 로 읽는 값이다(supabase_auth_repository.dart `_toFailure`).
    error: _HookError | None = None

    @classmethod
    def allow(cls) -> "HookDecision":
        return cls()

    @classmethod
    def reject(cls, message: str) -> "HookDecision":
        return cls(error=_HookError(http_code=422, message=message))
