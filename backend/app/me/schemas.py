from datetime import datetime, timedelta

from pydantic import BaseModel, Field, StrictBool, field_validator, model_validator

from app.matching.sentences import ANIMAL_LABELS, IMPRESSION_PHRASES
from app.profile_onboarding.schemas import NICKNAME_PATTERN, RELIGIONS

# DB check profiles_mbti_format 과 같다. 온보딩 /basic-info 는 이 검사가 없다(DB 가 막는다).
MBTI_PATTERN = r"^[EI][NS][TF][JP]$"

# 닉네임은 30일에 한 번(DESIGN §8.5 nickname-field). 잠금 판정(PATCH 409)과 15-6-2 잠금 문구(GET 의 풀리는 때)가 이 값 하나를 본다.
NICKNAME_CHANGE_INTERVAL = timedelta(days=30)


def nickname_changeable_at(changed_at: datetime | None, now: datetime) -> datetime | None:
    """닉네임 잠금이 풀리는 때. 지금 바꿀 수 있으면 None."""
    if changed_at is None:
        return None
    changeable_at = changed_at + NICKNAME_CHANGE_INTERVAL
    return changeable_at if changeable_at > now else None


class ProfileUpdateRequest(BaseModel):
    """15c(자기소개) · 15-6(닉네임 · 키 · MBTI · 종교 · 흡연 · 얼굴상 · 인상) 저장. **보낸 칸만** 고친다(model_fields_set) — 화면마다 따로 저장한다(U4)."""

    bio: str | None = None
    nickname: str | None = Field(default=None, pattern=NICKNAME_PATTERN)
    height_cm: int | None = None
    # mbti 만 null 이 뜻 있다 — "선택 안 함"(DB 컬럼도 null 허용). 나머지는 온보딩에서 전부 필수라 비울 수 없다.
    mbti: str | None = Field(default=None, pattern=MBTI_PATTERN)
    religion: str | None = None
    is_smoker: StrictBool | None = None   # "yes" · 1 같은 값이 True 로 둔갑하지 않게 JSON bool 만 받는다
    animal_type: str | None = None
    impression_type: str | None = None

    @field_validator("religion")
    @classmethod
    def _known_religion(cls, religion: str | None) -> str | None:
        if religion is not None and religion not in RELIGIONS:
            raise ValueError("알 수 없는 종교예요")
        return religion

    @field_validator("animal_type")
    @classmethod
    def _known_animal(cls, animal_type: str | None) -> str | None:
        if animal_type is not None and animal_type not in ANIMAL_LABELS:
            raise ValueError("알 수 없는 얼굴상이에요")
        return animal_type

    @field_validator("impression_type")
    @classmethod
    def _known_impression(cls, impression_type: str | None) -> str | None:
        if impression_type is not None and impression_type not in IMPRESSION_PHRASES:
            raise ValueError("알 수 없는 인상이에요")
        return impression_type

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
        # MBTI 말고는 null 로 비우는 화면이 없다. 보내면 온보딩 완료 check 가 뜻 모를 422 로 막으니 여기서 막는다.
        if any(getattr(self, name) is None for name in self.model_fields_set - {"mbti"}):
            raise ValueError("빈 값으로는 바꿀 수 없어요")
        # 얼굴상과 인상은 한 쌍이다 — 문장이 둘 다 있어야 만들어지고(matching/sentences.py), 한쪽만 바꾸면 짝이 어긋난다.
        if ("animal_type" in self.model_fields_set) != ("impression_type" in self.model_fields_set):
            raise ValueError("얼굴상과 인상은 함께 보내 주세요")
        return self
