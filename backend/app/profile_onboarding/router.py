import logging
from functools import lru_cache
from uuid import UUID

import httpx
from fastapi import APIRouter, File, Form, Header, HTTPException, Query, UploadFile
from google.cloud import vision
from openai import AsyncOpenAI

from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors
from app.profile_onboarding.avatars import AvatarGenerator, get_openai_client
from app.profile_onboarding.encryption import set_encrypted_phone_number
from app.profile_onboarding.hearts import grant_hearts
from app.profile_onboarding.onboarding_progress import next_step
from app.profile_onboarding.photos import check_safe_search
from app.profile_onboarding.repository import ProfileOnboardingRepository
from app.profile_onboarding.schemas import (
    NICKNAME_PATTERN,
    AppearanceTypeRequest,
    BasicInfoRequest,
    BioRequest,
    IdealConditionsRequest,
    IdealNoteRequest,
    KakaoIdRequest,
    NextStepResponse,
    NicknameAvailabilityResponse,
    SurveyRequest,
    TagsRequest,
)
from app.profile_onboarding.storage import AvatarStorage, ProfilePhotoStorage
from app.profile_onboarding.tags import IDEAL_TRAITS, INTEREST_TAGS, MY_TRAITS, validate_tag_selection
from app.settings import Settings
from app.student_verification.current_user import get_verified_user_id
from app.student_verification.image_validation import student_id_content_type

router = APIRouter()
_logger = logging.getLogger(__name__)

# 테스트가 실제 Supabase·OpenAI·Vision 대신 목을 주입할 수 있게 하는 훅(조각1b student_verification 패턴).
_client_override: httpx.AsyncClient | None = None
_vision_client_override: vision.ImageAnnotatorAsyncClient | None = None
_openai_client_override: AsyncOpenAI | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_vision_client() -> vision.ImageAnnotatorAsyncClient:
    return vision.ImageAnnotatorAsyncClient()


def _repo(settings: Settings, client: httpx.AsyncClient) -> ProfileOnboardingRepository:
    return ProfileOnboardingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)


async def _refresh_vectors(settings: Settings, client: httpx.AsyncClient, profile_id: UUID) -> None:
    """문장·설문 재료가 바뀐 직후 매칭 벡터를 다시 만든다(설계 §6.3 "수정하면 즉시 재생성").

    태그 3종은 부르지 않는다 — 태그는 문장 재료가 아니고 자카드는 조회 시점 계산이다.
    실패는 refresh_vectors 안에서 삼킨다(사용자 저장은 이미 끝났다)."""
    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    openai_client = _openai_client_override or get_openai_client(settings.openai_api_key)
    await refresh_vectors(repo, openai_client, profile_id)


@router.get("/profile-onboarding/nickname-availability")
async def check_nickname_availability(
    nickname: str = Query(pattern=NICKNAME_PATTERN),
    authorization: str | None = Header(default=None),
) -> NicknameAvailabilityResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    await get_verified_user_id(settings, client, authorization)
    available = await _repo(settings, client).check_nickname_availability(nickname)
    return NicknameAvailabilityResponse(available=available)


@router.post("/profile-onboarding/basic-info")
async def submit_basic_info(
    body: BasicInfoRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    # 닉네임 중복(23505)은 repository 의 공통 변환이 409 로 바꿔 준다.
    await repo.update_basic_info(
        profile_id, body.nickname, body.birth_year, body.height_cm, body.gender, body.mbti
    )

    await set_encrypted_phone_number(
        settings.postgrest_url, settings.supabase_service_role_key, client,
        profile_id, body.phone_number, settings.phone_encryption_key,
    )
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/kakao-id")
async def submit_kakao_id(
    body: KakaoIdRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    await _repo(settings, client).update_kakao_id(profile_id, body.kakao_id)
    return {"ok": True}


@router.post("/profile-onboarding/photos")
async def upload_photo(
    photo: UploadFile = File(),
    # 자리는 0~3 이다(profile_photos_position_range). 여기서 막아야 체크 제약 위반이 500 으로 새지 않는다.
    position: int = Form(ge=0, le=3),
    is_avatar_source: bool = Form(default=False),
    authorization: str | None = Header(default=None),
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)

    data = await photo.read()
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail="사진을 다시 확인해 주세요")

    is_safe = await check_safe_search(_vision_client_override or get_vision_client(), data)
    if not is_safe:
        raise HTTPException(status_code=422, detail="부적절한 사진은 올릴 수 없어요")

    storage = ProfilePhotoStorage(settings.storage_url, settings.supabase_service_role_key, client)
    storage_path = await storage.upload(profile_id, data, content_type)
    replaced_path = await _repo(settings, client).save_photo(
        profile_id, storage_path, position, is_avatar_source
    )
    # 같은 자리를 덮어썼으면 밀려난 파일은 아무도 가리키지 않으니 버킷에서도 지운다.
    if replaced_path is not None:
        await storage.delete(replaced_path)
    return {"ok": True}


@router.delete("/profile-onboarding/photos/{position}")
async def delete_photo(position: int, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    storage_path = await repo.fetch_photo_path(profile_id, position)
    if storage_path is None:
        raise HTTPException(status_code=404, detail="지울 사진이 없어요")

    await repo.delete_photo_row(profile_id, position)
    await ProfilePhotoStorage(
        settings.storage_url, settings.supabase_service_role_key, client
    ).delete(storage_path)
    return {"ok": True}


@router.post("/profile-onboarding/avatar/generate")
async def generate_avatar(authorization: str | None = Header(default=None)) -> dict:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    # 무료 생성은 1회다 — 하트를 쓰는 재생성은 조각 7 에서 붙인다(2026-09-20 사용자 결정).
    if await repo.has_ready_avatar(profile_id):
        raise HTTPException(status_code=409, detail="아바타는 한 번만 만들 수 있어요")

    source_path = await repo.fetch_avatar_source_photo_path(profile_id)
    if source_path is None:
        raise HTTPException(status_code=409, detail="아바타 원본 사진을 먼저 골라 주세요")
    source_photo = await ProfilePhotoStorage(
        settings.storage_url, settings.supabase_service_role_key, client
    ).download(source_path)

    recent_failures = await repo.count_recent_consecutive_avatar_failures(profile_id)
    generator = AvatarGenerator(
        _openai_client_override or get_openai_client(settings.openai_api_key),
        AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client),
        failure_counts={str(profile_id): recent_failures},
    )
    result = await generator.generate(str(profile_id), source_photo)

    if result.status == "ready":
        await repo.insert_avatar_attempt(profile_id, "ready", result.storage_path)
        return {"status": "ready"}

    await repo.insert_avatar_attempt(profile_id, "failed", None)
    if result.is_final_failure:
        fallback_path = await AvatarStorage(
            settings.storage_url, settings.supabase_service_role_key, client
        ).copy_fallback_avatar(profile_id)
        await repo.insert_avatar_attempt(profile_id, "ready", fallback_path)
        await grant_hearts(
            settings.postgrest_url, settings.supabase_service_role_key, client,
            profile_id=profile_id, amount=10, reason="admin_adjust",
        )
        return {"status": "fallback", "storage_path": fallback_path, "compensation_hearts": 10}
    return {"status": "failed"}


@router.post("/profile-onboarding/appearance-type")
async def submit_appearance_type(
    body: AppearanceTypeRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    await _repo(settings, client).update_appearance_type(profile_id, body.animal_type, body.impression_type)
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/interests")
async def submit_interests(body: TagsRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    return await _submit_tags(body, authorization, INTEREST_TAGS, "update_interests")


@router.post("/profile-onboarding/my-traits")
async def submit_my_traits(body: TagsRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    return await _submit_tags(body, authorization, MY_TRAITS, "update_my_traits")


@router.post("/profile-onboarding/ideal-traits")
async def submit_ideal_traits(body: TagsRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    return await _submit_tags(body, authorization, IDEAL_TRAITS, "update_ideal_traits")


async def _submit_tags(
    body: TagsRequest, authorization: str | None, pool: list[str], repo_method_name: str
) -> dict[str, bool]:
    # 누구인지·인증을 마쳤는지 먼저 본다 — 인증 안 한 사람에게 태그 목록이 맞는지 알려줄 이유가 없다.
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)

    try:
        validate_tag_selection(pool, body.tags)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    repo = _repo(settings, client)
    await getattr(repo, repo_method_name)(profile_id, body.tags)
    return {"ok": True}


@router.post("/profile-onboarding/survey")
async def submit_survey(body: SurveyRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    await _repo(settings, client).insert_survey_answers(profile_id, body.answers, body.religion, body.is_smoker)
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/ideal-conditions")
async def submit_ideal_conditions(
    body: IdealConditionsRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    await _repo(settings, client).update_ideal_conditions(
        profile_id, body.preferred_age_min, body.preferred_age_max,
        body.preferred_height_min, body.preferred_height_max,
        body.preferred_mbti_flags, body.preferred_animal_types, body.preferred_impression_types,
    )
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/ideal-note")
async def submit_ideal_note(
    body: IdealNoteRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    await _repo(settings, client).update_ideal_note(profile_id, body.note)
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/bio-draft")
async def generate_bio_draft_endpoint(authorization: str | None = Header(default=None)) -> dict[str, str]:
    from app.profile_onboarding.bio_draft import generate_bio_draft

    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    # 이미 만든 초안이 있으면 그것을 그대로 돌려준다(화면을 다시 열어도 빈 칸이 되지 않게).
    saved_draft = await repo.fetch_bio_draft(profile_id)
    if saved_draft is not None:
        return {"draft": saved_draft}

    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    survey_summary = f"religion={snapshot['religion']}, is_smoker={snapshot['is_smoker']}"
    draft = await generate_bio_draft(
        _openai_client_override or get_openai_client(settings.openai_api_key),
        survey_summary, snapshot["interest_tags"], snapshot["my_traits"],
    )
    await repo.save_bio_draft(profile_id, draft)
    return {"draft": draft}


@router.post("/profile-onboarding/bio")
async def submit_bio(body: BioRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    await repo.update_bio(profile_id, body.bio)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    snapshot["bio"] = body.bio
    if next_step(snapshot) == "complete":
        await repo.activate_profile(profile_id)
    await _refresh_vectors(settings, client, profile_id)
    return {"ok": True}


@router.get("/profile-onboarding/next-step")
async def get_next_step(authorization: str | None = Header(default=None)) -> NextStepResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = _repo(settings, client)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    return NextStepResponse(step=next_step(snapshot))
