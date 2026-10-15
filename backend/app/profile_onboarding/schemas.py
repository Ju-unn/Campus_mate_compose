from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, BeforeValidator, Field, field_validator, model_validator

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
    gender: Literal["male", "female"]  # DB enum gender 와 같다
    mbti: str | None = None

    @field_validator("birth_year")
    @classmethod
    def _old_enough(cls, birth_year: int) -> int:
        this_year = datetime.now(SEOUL).year
        if this_year - birth_year < MIN_AGE:
            raise ValueError(f"{this_year - MIN_AGE}년생부터 가입할 수 있어요")
        return birth_year


# 카카오톡 아이디 입력 상한. 실제 카카오톡 아이디(영문·숫자·._-, 4~20자 안팎)보다 넉넉한 안전 상한이다 —
# 상한이 없으면 아무 길이나 암호화 RPC 와 DB 로 흘러간다.
KAKAO_ID_MAX_LENGTH = 64


class KakaoIdRequest(BaseModel):
    kakao_id: str = Field(max_length=KAKAO_ID_MAX_LENGTH)


class AppearanceTypeRequest(BaseModel):
    animal_type: str
    impression_type: str


class TagsRequest(BaseModel):
    tags: list[str]


# DB 가 막는 값과 같다(enum religion · survey_answers_axis_range · survey_answers_value_scale).
# 저장이 두 번(답 insert → 프로필 PATCH)이라, DB 에만 맡기면 뒤쪽이 실패할 때 앞쪽 답만 남는다(E2E D-01).
RELIGIONS = frozenset({"none", "protestant", "catholic", "buddhist"})
SURVEY_AXES = range(1, 10)
SURVEY_VALUES = frozenset({-1, -0.5, 0, 0.5, 1})


class SurveyRequest(BaseModel):
    answers: dict[int, float]  # axis -> value
    religion: str
    is_smoker: bool

    def is_storable(self) -> bool:
        # 9축 전부 필수다 — 앱은 처음부터 9축을 다 채워 한 번에 보낸다("온보딩 입력은 전부 필수").
        return (
            self.religion in RELIGIONS
            and set(self.answers) == set(SURVEY_AXES)
            and all(value in SURVEY_VALUES for value in self.answers.values())
        )


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
# 자유 글(자기소개 · 이상형 글) 상한. 채팅 한 통과 같은 1000자다 — 상한이 없으면 아무 길이나 DB 와 임베딩(유료)으로
# 흘러간다(2026-10-12 보안 점검 #11). DB check 는 없다. 앱은 2026-10-14 부터 300자로 막지만(사용자 결정 "추천대로")
# 여기는 1000 그대로다 — 그 전에 쓴 긴 소개를 고쳐 저장할 때 막히지 않게.
FREE_TEXT_MAX_LENGTH = 1000
# 줄 수 상한(1000자 ÷ 25 = 40줄). 앱(06-3 · 15c 8줄, 06-2a 6줄)보다 훨씬 넉넉하다 — 옛 앱 · 직접 호출이
# 줄 바꿈만 잔뜩 넣어 카드를 끝없이 늘이는 것만 막는다.
FREE_TEXT_MAX_LINES = FREE_TEXT_MAX_LENGTH // 25


def _unify_line_breaks(value: object) -> object:
    """`\\r\\n` · `\\r` 을 `\\n` 으로 줄인다(앱 입력칸과 같은 규칙). 글자 수를 재기 전에 해야 Windows 줄 끝이 2자로 잡히지 않는다."""
    return value.replace("\r\n", "\n").replace("\r", "\n") if isinstance(value, str) else value


def _within_line_cap(value: str) -> str:
    if value.count("\n") >= FREE_TEXT_MAX_LINES:
        raise ValueError(f"줄 바꿈은 {FREE_TEXT_MAX_LINES}줄까지만 쓸 수 있어요")
    return value


# 자기소개(온보딩 /bio · PATCH /me/profile)와 이상형 글이 같이 쓴다.
FreeText = Annotated[
    str, BeforeValidator(_unify_line_breaks), Field(max_length=FREE_TEXT_MAX_LENGTH), AfterValidator(_within_line_cap)
]


class IdealNoteRequest(BaseModel):
    note: FreeText

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
    bio: FreeText


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
