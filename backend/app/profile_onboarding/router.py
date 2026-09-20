import logging
from functools import lru_cache

import httpx
from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile
from google.cloud import vision
from openai import AsyncOpenAI

from app.profile_onboarding.avatars import AvatarGenerator, get_openai_client
from app.profile_onboarding.encryption import set_encrypted_phone_number
from app.profile_onboarding.hearts import grant_hearts
from app.profile_onboarding.onboarding_progress import next_step
from app.profile_onboarding.photos import check_safe_search
from app.profile_onboarding.repository import ProfileOnboardingRepository
from app.profile_onboarding.schemas import (
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
from app.student_verification.current_user import get_current_user_id
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


@router.get("/profile-onboarding/nickname-availability")
async def check_nickname_availability(
    nickname: str, authorization: str | None = Header(default=None)
) -> NicknameAvailabilityResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    await get_current_user_id(settings, client, authorization)
    available = await _repo(settings, client).check_nickname_availability(nickname)
    return NicknameAvailabilityResponse(available=available)


@router.post("/profile-onboarding/basic-info")
async def submit_basic_info(
    body: BasicInfoRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    try:
        await repo.update_basic_info(
            profile_id, body.nickname, body.birth_year, body.height_cm, body.gender, body.mbti
        )
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error

    await set_encrypted_phone_number(
        settings.postgrest_url, settings.supabase_service_role_key, client,
        profile_id, body.phone_number, settings.phone_encryption_key,
    )
    return {"ok": True}


@router.post("/profile-onboarding/kakao-id")
async def submit_kakao_id(
    body: KakaoIdRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    await _repo(settings, client).update_kakao_id(profile_id, body.kakao_id)
    return {"ok": True}


@router.post("/profile-onboarding/photos")
async def upload_photo(
    photo: UploadFile = File(),
    position: int = Form(),
    is_avatar_source: bool = Form(default=False),
    authorization: str | None = Header(default=None),
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)

    data = await photo.read()
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail="사진을 다시 확인해 주세요")

    is_safe = await check_safe_search(_vision_client_override or get_vision_client(), data)
    if not is_safe:
        raise HTTPException(status_code=422, detail="부적절한 사진은 올릴 수 없어요")

    storage = ProfilePhotoStorage(settings.storage_url, settings.supabase_service_role_key, client)
    storage_path = await storage.upload(profile_id, data, content_type)
    await _repo(settings, client).insert_photo(profile_id, storage_path, position, is_avatar_source)
    return {"ok": True}


@router.post("/profile-onboarding/avatar/generate")
async def generate_avatar(authorization: str | None = Header(default=None)) -> dict:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)

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
    profile_id = await get_current_user_id(settings, client, authorization)
    await _repo(settings, client).update_appearance_type(profile_id, body.animal_type, body.impression_type)
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
    try:
        validate_tag_selection(pool, body.tags)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)
    await getattr(repo, repo_method_name)(profile_id, body.tags)
    return {"ok": True}


@router.post("/profile-onboarding/survey")
async def submit_survey(body: SurveyRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    await _repo(settings, client).insert_survey_answers(profile_id, body.answers, body.religion, body.is_smoker)
    return {"ok": True}


@router.post("/profile-onboarding/ideal-conditions")
async def submit_ideal_conditions(
    body: IdealConditionsRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    await _repo(settings, client).update_ideal_conditions(
        profile_id, body.preferred_age_min, body.preferred_age_max,
        body.preferred_height_min, body.preferred_height_max,
        body.preferred_mbti_flags, body.preferred_animal_types, body.preferred_impression_types,
    )
    return {"ok": True}


@router.post("/profile-onboarding/ideal-note")
async def submit_ideal_note(
    body: IdealNoteRequest, authorization: str | None = Header(default=None)
) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    await _repo(settings, client).update_ideal_note(profile_id, body.note)
    return {"ok": True}


@router.post("/profile-onboarding/bio-draft")
async def generate_bio_draft_endpoint(authorization: str | None = Header(default=None)) -> dict[str, str]:
    from app.profile_onboarding.bio_draft import generate_bio_draft

    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    if await repo.fetch_bio_draft_generated_at(profile_id) is not None:
        raise HTTPException(status_code=409, detail="자기소개 초안은 한 번만 만들 수 있어요")

    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    survey_summary = f"religion={snapshot['religion']}, is_smoker={snapshot['is_smoker']}"
    draft = await generate_bio_draft(
        _openai_client_override or get_openai_client(settings.openai_api_key),
        survey_summary, snapshot["interest_tags"], snapshot["my_traits"],
    )
    await repo.mark_bio_draft_generated(profile_id)
    return {"draft": draft}


@router.post("/profile-onboarding/bio")
async def submit_bio(body: BioRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)

    await repo.update_bio(profile_id, body.bio)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    snapshot["bio"] = body.bio
    if next_step(snapshot) == "complete":
        await repo.activate_profile(profile_id)
    return {"ok": True}


@router.get("/profile-onboarding/next-step")
async def get_next_step(authorization: str | None = Header(default=None)) -> NextStepResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = _repo(settings, client)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    return NextStepResponse(step=next_step(snapshot))
