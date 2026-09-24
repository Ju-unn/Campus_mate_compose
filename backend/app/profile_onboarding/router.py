import logging
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from google.cloud import vision
from openai import AsyncOpenAI

from app.core import errors
from app.core.deps import Caller, get_settings, get_verified_caller, get_vision_client
from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors
from app.profile_onboarding.avatars import AvatarGenerator, get_openai_client
from app.profile_onboarding.encryption import set_encrypted_phone_number
from app.profile_onboarding.hearts import grant_hearts
from app.profile_onboarding.onboarding_progress import next_step
from app.profile_onboarding.phone_number import to_e164
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
from app.student_verification.image_validation import student_id_content_type

router = APIRouter()
_logger = logging.getLogger(__name__)


# aio 클라이언트를 만드는 의존성은 `async def` 로 둔다(deps.get_vision_client 참고) —
# `def` 는 루프가 없는 AnyIO 워커 스레드에서 돌아 500 이 된다.
# AsyncOpenAI 는 만들 때 루프를 잡지 않아 지금은 터지지 않는다.
def get_openai(settings: Settings = Depends(get_settings)) -> AsyncOpenAI:
    """임베딩·아바타·자기소개 초안이 쓰는 OpenAI 클라이언트. 테스트는 이 자리에 목을 끼운다."""
    return get_openai_client(settings.openai_api_key)


def _repo(settings: Settings, client: httpx.AsyncClient) -> ProfileOnboardingRepository:
    return ProfileOnboardingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)


async def _refresh_vectors(
    settings: Settings, client: httpx.AsyncClient, openai_client: AsyncOpenAI, profile_id: UUID
) -> None:
    """문장·설문 재료가 바뀐 직후 매칭 벡터를 다시 만든다(설계 §6.3 "수정하면 즉시 재생성").

    태그 3종은 부르지 않는다 — 태그는 문장 재료가 아니고 자카드는 조회 시점 계산이다.
    실패는 refresh_vectors 안에서 삼킨다(사용자 저장은 이미 끝났다)."""
    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    await refresh_vectors(repo, openai_client, profile_id)


@router.get("/profile-onboarding/nickname-availability")
async def check_nickname_availability(
    nickname: str = Query(pattern=NICKNAME_PATTERN),
    caller: Caller = Depends(get_verified_caller),
) -> NicknameAvailabilityResponse:
    settings, client, profile_id = caller
    available = await _repo(settings, client).check_nickname_availability(profile_id, nickname)
    return NicknameAvailabilityResponse(available=available)


@router.post("/profile-onboarding/basic-info")
async def submit_basic_info(
    body: BasicInfoRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = _repo(settings, client)

    # 앱이 하이픈을 붙여 보내도 저장은 한 모양(E.164)이어야 한다 — 여기가 신뢰 경계다.
    phone_number = to_e164(body.phone_number)
    if phone_number is None:
        raise HTTPException(status_code=400, detail=errors.PHONE_NUMBER_INVALID)

    # 닉네임 중복(23505)은 repository 의 공통 변환이 409 로 바꿔 준다.
    await repo.update_basic_info(
        profile_id, body.nickname, body.birth_year, body.height_cm, body.gender, body.mbti
    )

    await repo.ensure_private_row(profile_id)
    await set_encrypted_phone_number(
        settings.postgrest_url, settings.supabase_service_role_key, client,
        profile_id, phone_number, settings.phone_encryption_key,
    )
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/kakao-id")
async def submit_kakao_id(
    body: KakaoIdRequest, caller: Caller = Depends(get_verified_caller)
) -> dict[str, bool]:
    settings, client, profile_id = caller
    await _repo(settings, client).update_kakao_id(profile_id, body.kakao_id)
    return {"ok": True}


@router.post("/profile-onboarding/photos")
async def upload_photo(
    photo: UploadFile = File(),
    # 자리는 0~3 이다(profile_photos_position_range). 여기서 막아야 체크 제약 위반이 500 으로 새지 않는다.
    position: int = Form(ge=0, le=3),
    is_avatar_source: bool = Form(default=False),
    caller: Caller = Depends(get_verified_caller),
    vision_client: vision.ImageAnnotatorAsyncClient = Depends(get_vision_client),
) -> dict[str, bool]:
    settings, client, profile_id = caller

    data = await photo.read()
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)

    is_safe = await check_safe_search(vision_client, data)
    if not is_safe:
        raise HTTPException(status_code=422, detail=errors.PHOTO_NOT_SAFE)

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
async def delete_photo(position: int, caller: Caller = Depends(get_verified_caller)) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = _repo(settings, client)

    storage_path = await repo.fetch_photo_path(profile_id, position)
    if storage_path is None:
        raise HTTPException(status_code=404, detail=errors.PHOTO_NOT_FOUND)

    await repo.delete_photo_row(profile_id, position)
    await ProfilePhotoStorage(
        settings.storage_url, settings.supabase_service_role_key, client
    ).delete(storage_path)
    return {"ok": True}


@router.post("/profile-onboarding/avatar/generate")
async def generate_avatar(
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict:
    settings, client, profile_id = caller
    repo = _repo(settings, client)

    # 무료 생성은 1회다 — 하트를 쓰는 재생성은 조각 7 에서 붙인다(2026-09-20 사용자 결정).
    if await repo.has_ready_avatar(profile_id):
        raise HTTPException(status_code=409, detail=errors.AVATAR_ALREADY_CREATED)

    source_path = await repo.fetch_avatar_source_photo_path(profile_id)
    if source_path is None:
        raise HTTPException(status_code=409, detail=errors.AVATAR_SOURCE_REQUIRED)
    source_photo = await ProfilePhotoStorage(
        settings.storage_url, settings.supabase_service_role_key, client
    ).download(source_path)

    recent_failures = await repo.count_recent_consecutive_avatar_failures(profile_id)
    generator = AvatarGenerator(
        openai_client,
        AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client),
        failure_counts={str(profile_id): recent_failures},
    )
    result = await generator.generate(str(profile_id), source_photo)

    if result.status == "ready":
        await repo.insert_avatar_attempt(profile_id, "ready", result.storage_path)
        # 앱은 ready 에서도 storage_path 를 읽는다 — 안 실어 보내 캐스트가 터졌다(운영 00020 무한 로딩).
        return {"status": "ready", "storage_path": result.storage_path}

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
    body: AppearanceTypeRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    await _repo(settings, client).update_appearance_type(profile_id, body.animal_type, body.impression_type)
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/interests")
async def submit_interests(body: TagsRequest, caller: Caller = Depends(get_verified_caller)) -> dict[str, bool]:
    return await _submit_tags(body, caller, INTEREST_TAGS, "update_interests")


@router.post("/profile-onboarding/my-traits")
async def submit_my_traits(body: TagsRequest, caller: Caller = Depends(get_verified_caller)) -> dict[str, bool]:
    return await _submit_tags(body, caller, MY_TRAITS, "update_my_traits")


@router.post("/profile-onboarding/ideal-traits")
async def submit_ideal_traits(body: TagsRequest, caller: Caller = Depends(get_verified_caller)) -> dict[str, bool]:
    return await _submit_tags(body, caller, IDEAL_TRAITS, "update_ideal_traits")


async def _submit_tags(
    body: TagsRequest, caller: Caller, pool: list[str], repo_method_name: str
) -> dict[str, bool]:
    # 누구인지·인증을 마쳤는지 먼저 본다 — 인증 안 한 사람에게 태그 목록이 맞는지 알려줄 이유가 없다.
    settings, client, profile_id = caller

    try:
        validate_tag_selection(pool, body.tags)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    repo = _repo(settings, client)
    await getattr(repo, repo_method_name)(profile_id, body.tags)
    return {"ok": True}


@router.post("/profile-onboarding/survey")
async def submit_survey(
    body: SurveyRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    await _repo(settings, client).insert_survey_answers(profile_id, body.answers, body.religion, body.is_smoker)
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/ideal-conditions")
async def submit_ideal_conditions(
    body: IdealConditionsRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    await _repo(settings, client).update_ideal_conditions(
        profile_id, body.preferred_age_min, body.preferred_age_max,
        body.preferred_height_min, body.preferred_height_max,
        body.preferred_mbti_flags, body.preferred_animal_types, body.preferred_impression_types,
    )
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/ideal-note")
async def submit_ideal_note(
    body: IdealNoteRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    await _repo(settings, client).update_ideal_note(profile_id, body.note)
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.post("/profile-onboarding/bio-draft")
async def generate_bio_draft_endpoint(
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, str]:
    from app.profile_onboarding.bio_draft import generate_bio_draft

    settings, client, profile_id = caller
    repo = _repo(settings, client)

    # 이미 만든 초안이 있으면 그것을 그대로 돌려준다(화면을 다시 열어도 빈 칸이 되지 않게).
    saved_draft = await repo.fetch_bio_draft(profile_id)
    if saved_draft is not None:
        return {"draft": saved_draft}

    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    survey_summary = f"religion={snapshot['religion']}, is_smoker={snapshot['is_smoker']}"
    draft = await generate_bio_draft(
        openai_client,
        survey_summary, snapshot["interest_tags"], snapshot["my_traits"],
    )
    await repo.save_bio_draft(profile_id, draft)
    return {"draft": draft}


@router.post("/profile-onboarding/bio")
async def submit_bio(
    body: BioRequest,
    caller: Caller = Depends(get_verified_caller),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = _repo(settings, client)

    await repo.update_bio(profile_id, body.bio)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    snapshot["bio"] = body.bio
    if next_step(snapshot) == "complete":
        await repo.activate_profile(profile_id)
    await _refresh_vectors(settings, client, openai_client, profile_id)
    return {"ok": True}


@router.get("/profile-onboarding/next-step")
async def get_next_step(caller: Caller = Depends(get_verified_caller)) -> NextStepResponse:
    settings, client, profile_id = caller
    repo = _repo(settings, client)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    return NextStepResponse(step=next_step(snapshot))
