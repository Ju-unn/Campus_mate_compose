from datetime import datetime, timedelta

from pydantic import BaseModel, Field, field_validator, model_validator

from app.profile_onboarding.schemas import NICKNAME_PATTERN

# 닉네임은 30일에 한 번(DESIGN §8.5 nickname-field). 잠금 판정(PATCH 409)과 15-6-2 잠금 문구(GET 의 풀리는 때)가 이 값 하나를 본다.
NICKNAME_CHANGE_INTERVAL = timedelta(days=30)


def nickname_changeable_at(changed_at: datetime | None, now: datetime) -> datetime | None:
    """닉네임 잠금이 풀리는 때. 지금 바꿀 수 있으면 None."""
    if changed_at is None:
        return None
    changeable_at = changed_at + NICKNAME_CHANGE_INTERVAL
    return changeable_at if changeable_at > now else None


class ProfileUpdateRequest(BaseModel):
    """15c(자기소개) · 15-6(닉네임 · 키) 저장. **보낸 칸만** 고친다(model_fields_set) — 화면마다 따로 저장한다(U4)."""

    bio: str | None = None
    nickname: str | None = Field(default=None, pattern=NICKNAME_PATTERN)
    height_cm: int | None = None

    @field_validator("bio")
    @classmethod
    def _bio_not_blank(cls, bio: str | None) -> str | None:
        # 06-3 앱 규칙(bio.trim().isNotEmpty)과 같다. 온보딩 /bio 는 이 검사가 없다.
        if bio is not None and not bio.strip():
            raise ValueError("자기소개를 입력해 주세요")
        return bio.strip() if bio is not None else None

    @model_validator(mode="after")
    def _something_to_change(self) -> "ProfileUpdateRequest":
        if not self.model_fields_set:
            raise ValueError("고칠 칸이 없어요")
        # 닉네임 · 키 · 자기소개를 null 로 비우는 화면은 없다. 보내면 온보딩 완료 check 가 뜻 모를 422 로 막으니 여기서 막는다.
        if any(getattr(self, name) is None for name in self.model_fields_set):
            raise ValueError("빈 값으로는 바꿀 수 없어요")
        return self
