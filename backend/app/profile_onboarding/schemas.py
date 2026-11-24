from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, BeforeValidator, Field, StrictBool, field_validator, model_validator

from app.core.text import ZERO_WIDTH, SafeLine, SafeText, has_bad_char, require_visible, visible
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


KAKAO_ID_MIN_LENGTH = 2


class KakaoIdRequest(BaseModel):
    # 모양은 라우터가 is_valid_kakao_id 로 본다 — pydantic 검사로 걸면 detail 이 목록이라 앱(05)이 "알 수 없는 오류" 를 띄운다.
    # 여기 상한은 터무니없이 긴 본문만 막는 안전판이다.
    kakao_id: str = Field(max_length=1000)


def is_valid_kakao_id(kakao_id: str) -> bool:
    """앞뒤 공백을 뺀 2~64자, 안쪽 공백 · 줄바꿈 · 제어 문자 · 글 방향 문자 · 0폭 문자 · 한글 자음 · 모음 낱자(U+3130–318F)
    없음(11-18 검토). 같은 글자 3번은 막지 않는다 — 실제 아이디에 있을 수 있다. 카카오 형식(영문 · 숫자 · ._- 4~20자)은 사용자 결정 전이라 안 넣었다."""
    text = kakao_id.strip()
    return (
        KAKAO_ID_MIN_LENGTH <= len(text) <= KAKAO_ID_MAX_LENGTH
        and not any(ch.isspace() or ch in ZERO_WIDTH for ch in text)
        and not has_bad_char(text, multiline=False)
        and not any(0x3130 <= ord(ch) <= 0x318F for ch in text)
    )


class AppearanceTypeRequest(BaseModel):
    animal_type: str
    impression_type: str


class TagsRequest(BaseModel):
    tags: list[str]


# DB 가 막는 값과 같다(enum religion · survey_answers_axis_range · survey_answers_value_scale).
# 저장이 두 번(답 insert → 프로필 PATCH)이라, DB 에만 맡기면 뒤쪽이 실패할 때 앞쪽 답만 남는다(E2E D-01).
RELIGIONS = frozenset({"none", "protestant", "catholic", "buddhist"})
# 신분(1.0.7 1-1, 사용자 결정 11-24). DB check profiles_academic_status_check 와 같다. null = 아직 안 고름(= "학교 인증" 배지).
AcademicStatus = Literal["undergraduate", "graduate_student", "alumni"]
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


# 이상형 MBTI 는 극 여덟 개 키만 받는다(앱 ideal_conditions_ui_state.dart mbtiPoles, 매칭 scoring._AXES). 다른 키는 매칭이
# 읽지도 않고 jsonb 로 쌓이기만 한다(10-18 보안 점검).
MbtiPole = Literal["E", "I", "N", "S", "T", "F", "J", "P"]
MBTI_POLE_COUNT = 8


def _at_most_eight_poles(value: object) -> object:
    """키 수부터 본다 — 큰 dict 면 키마다 오류 한 줄씩 수천 줄짜리 422 가 나간다(pydantic 은 dict 에 fail_fast 가 없다)."""
    if isinstance(value, dict) and len(value) > MBTI_POLE_COUNT:
        raise ValueError(f"MBTI 는 {MBTI_POLE_COUNT}글자만 받아요")
    return value


class IdealConditionsRequest(BaseModel):
    preferred_age_min: int
    preferred_age_max: int
    preferred_height_min: int | None = None
    preferred_height_max: int | None = None
    preferred_mbti_flags: Annotated[dict[MbtiPole, bool], BeforeValidator(_at_most_eight_poles)] = {}
    # 선호 얼굴상·인상은 각 1~3개 필수다(2026-09-20 사용자 결정 "온보딩 입력은 전부 필수").
    preferred_animal_types: list[str] = Field(min_length=1, max_length=3)
    preferred_impression_types: list[str] = Field(min_length=1, max_length=3)
    # "흡연하는 사람" 칸(1.0.2 A6): true = 상관없어요, false = 싫어요, null = 내 흡연 여부를 따른다. JSON bool 만 받는다("yes" · 1 불가).
    accepts_smoker: StrictBool | None = None

    def sent_optional_fields(self) -> dict:
        """옛 앱(1.0.0 · 1.0.1)은 accepts_smoker 를 안 보낸다 — 키가 없으면 DB 값을 건드리지 않고, 보낸 null 은 null 로 되돌린다."""
        return self.model_dump(include=self.model_fields_set & {"accepts_smoker"})


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


# 자기소개(온보딩 /bio · PATCH /me/profile)와 이상형 글이 같이 쓴다. SafeText = 널 문자 · 제어 문자 · 글 방향 문자 거절(core/text.py).
FreeText = Annotated[
    SafeText, BeforeValidator(_unify_line_breaks), Field(max_length=FREE_TEXT_MAX_LENGTH), AfterValidator(_within_line_cap)
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
        # 0폭 문자(core/text.py)는 세지 않는다 — 보이지 않는 글자로 10자를 채우지 못하게. 저장 값은 그대로다.
        if len(visible(stripped)) < IDEAL_NOTE_MIN_LENGTH:
            raise ValueError(f"{IDEAL_NOTE_MIN_LENGTH}자 이상 입력해 주세요")
        return stripped


class BioRequest(BaseModel):
    # 06-3 앱 규칙(bio.trim().isNotEmpty)과 같다 — 공백 · 0폭 문자만인 소개는 빈 소개다(11-18 검토, PATCH /me/profile 과 같게).
    bio: Annotated[FreeText, AfterValidator(require_visible)]


ACQUISITION_NOTE_MAX_LENGTH = 30  # pen 값이 다르면 여기와 앱 acquisitionNoteMaxLength 를 같이 바꾼다


class AcquisitionRequest(BaseModel):
    """20d 유입경로. 칩 값은 DB enum acquisition_channel 과 같은 다섯 개다."""

    channel: Literal["everytime", "instagram", "friend", "community", "other"]
    note: SafeLine | None = None  # 한 줄 칸 — 제어 문자(줄바꿈 · 탭 · 널 문자) 거절

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
