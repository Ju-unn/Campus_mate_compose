from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, Field, field_validator

# 닉네임은 한글·영문 2~5자다(DESIGN.md 04-1, frontend BasicInfoUiState 와 같은 정규식).
# 서버도 같은 검사를 해야 `%`·`_` 가 PostgREST ilike 의 와일드카드로 들어가지 않는다.
NICKNAME_PATTERN = r"^[가-힣a-zA-Z]{2,5}$"

# 가입 나이 자격은 컬럼이 아니라 FastAPI 가 센다(ERD.md §"컬럼 없이 계산하는 값").
# 만 나이가 아니라 "올해 − 태어난 해" 이고, 서버 시계가 UTC 라도 한국 날짜로 해를 세야
# 12월 31일 밤에 기준이 하루 어긋나지 않는다.
# 한국은 서머타임이 없어 고정 +9 로 충분하다(zoneinfo 는 윈도우에서 tzdata 패키지를 더 요구한다).
SEOUL = timezone(timedelta(hours=9))
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
        if datetime.now(SEOUL).year - birth_year < MIN_AGE:
            raise ValueError(f"만 {MIN_AGE}세 이상만 가입할 수 있어요")
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


class IdealNoteRequest(BaseModel):
    note: str

    @field_validator("note")
    @classmethod
    def _not_blank(cls, note: str) -> str:
        """공백만 쓴 글은 안 쓴 것과 같다 — 자기소개와 같이 최소 길이 제한 없이 "비어 있지 알만" 본다."""
        stripped = note.strip()
        if not stripped:
            raise ValueError("어떤 사람이 좋은지 적어 주세요")
        return stripped


class BioRequest(BaseModel):
    bio: str


class NextStepResponse(BaseModel):
    step: str


class NicknameAvailabilityResponse(BaseModel):
    available: bool
