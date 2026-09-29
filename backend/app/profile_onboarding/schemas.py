from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.time import SEOUL

# 닉네임은 한글·영문 2~5자다(DESIGN.md 04-1, frontend BasicInfoUiState 와 같은 정규식).
# 서버도 같은 검사를 해야 `%`·`_` 가 PostgREST ilike 의 와일드카드로 들어가지 않는다.
NICKNAME_PATTERN = r"^[가-힣a-zA-Z]{2,5}$"

# 가입 나이 자격은 컬럼이 아니라 FastAPI 가 센다(ERD.md §"컬럼 없이 계산하는 값").
# 만 나이가 아니라 "올해 − 태어난 해" 이고, 해는 한국 날짜로 센다(core/time.py 의 SEOUL).
# 청소년보호법 "만 19세가 되는 해 1월 1일" 기준과 같아 문구도 "○○년생부터" 다(사용자 결정 2026-09-29).
MIN_AGE = 19


class BasicInfoRequest(BaseModel):
    nickname: str = Field(pattern=NICKNAME_PATTERN)
    birth_year: int
    height_cm: int
    phone_number: str
    gender: str
    mbti: str | None = None

    @field_validator("birth_year")
    @classmethod
    def _old_enough(cls, birth_year: int) -> int:
        this_year = datetime.now(SEOUL).year
        if this_year - birth_year < MIN_AGE:
            raise ValueError(f"{this_year - MIN_AGE}년생부터 가입할 수 있어요")
        return birth_year


class KakaoIdRequest(BaseModel):
    kakao_id: str


class AppearanceTypeRequest(BaseModel):
    animal_type: str
    impression_type: str


class TagsRequest(BaseModel):
    tags: list[str]


class SurveyRequest(BaseModel):
    answers: dict[int, float]  # axis -> value
    religion: str
    is_smoker: bool


class IdealConditionsRequest(BaseModel):
    preferred_age_min: int
    preferred_age_max: int
    preferred_height_min: int | None = None
    preferred_height_max: int | None = None
    preferred_mbti_flags: dict[str, bool] = {}
    # 선호 얼굴상·인상은 각 1~3개 필수다(2026-09-20 사용자 결정 "온보딩 입력은 전부 필수").
    preferred_animal_types: list[str] = Field(min_length=1, max_length=3)
    preferred_impression_types: list[str] = Field(min_length=1, max_length=3)


IDEAL_NOTE_MIN_LENGTH = 10


class IdealNoteRequest(BaseModel):
    note: str

    @field_validator("note")
    @classmethod
    def _long_enough(cls, note: str) -> str:
        """앞뒤 공백을 뗀 길이로 최소 10자를 본다(2026-09-21 사용자 결정).
        이 글은 "원해" 문장 임베딩의 재료라 한두 글자면 매칭 점수가 의미를 잃는다.
        자기소개(bio)는 최소 길이가 없다 — 그쪽은 초안 생성이 따로 돕는다."""
        stripped = note.strip()
        if len(stripped) < IDEAL_NOTE_MIN_LENGTH:
            raise ValueError(f"{IDEAL_NOTE_MIN_LENGTH}자 이상 입력해 주세요")
        return stripped


class BioRequest(BaseModel):
    bio: str


ACQUISITION_NOTE_MAX_LENGTH = 30  # pen 값이 다르면 여기와 앱 acquisitionNoteMaxLength 를 같이 바꾼다


class AcquisitionRequest(BaseModel):
    """20d 유입경로. 칩 값은 DB enum acquisition_channel 과 같은 다섯 개다."""

    channel: Literal["everytime", "instagram", "friend", "community", "other"]
    note: str | None = None

    @model_validator(mode="after")
    def _note_only_for_other(self) -> "AcquisitionRequest":
        if self.channel != "other":
            self.note = None
            return self
        note = (self.note or "").strip()
        if not note or len(note) > ACQUISITION_NOTE_MAX_LENGTH:
            raise ValueError("기타는 한 줄로 적어 주세요")
        self.note = note
        return self


class NextStepResponse(BaseModel):
    step: str


class NicknameAvailabilityResponse(BaseModel):
    available: bool
