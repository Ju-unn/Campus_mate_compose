from pydantic import BaseModel


class BasicInfoRequest(BaseModel):
    nickname: str
    birth_year: int
    height_cm: int
    phone_number: str
    gender: str
    mbti: str | None = None


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
    preferred_animal_types: list[str] = []
    preferred_impression_types: list[str] = []


class IdealNoteRequest(BaseModel):
    note: str | None = None


class BioRequest(BaseModel):
    bio: str


class NextStepResponse(BaseModel):
    step: str


class NicknameAvailabilityResponse(BaseModel):
    available: bool
