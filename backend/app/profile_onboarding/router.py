import logging
from datetime import datetime
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from google.cloud import vision
from openai import AsyncOpenAI

from app.core import errors
from app.core.deps import Caller, get_now, get_settings, get_verified_caller, get_vision_client
from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors
from app.profile_onboarding.avatar_tasks import AvatarTaskQueue
from app.profile_onboarding.avatars import (
    FALLBACK_COMPENSATION_HEARTS,
    MAX_CONSECUTIVE_FAILURES,
    STALE_PENDING_AFTER,
    apply_fallback_avatar,
    get_openai_client,
)
from app.profile_onboarding.encryption import set_encrypted_phone_number
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


def avatar_url(supabase_url: str, storage_path: str) -> str:
    """공개 `avatars` 버킷의 전체 주소. 카드(`cards/router.py`)·채팅과 **같은 모양**이다 —
    Dart 가 접두사를 손으로 붙이는 자리를 만들지 않는다(그런 자리는 버킷을 바꾸면 전부 깨진다)."""
    return f"{supabase_url}/storage/v1/object/public/avatars/{storage_path}"


@router.post("/profile-onboarding/avatar/generate")
async def generate_avatar(
    response: Response,
    caller: Caller = Depends(get_verified_caller),
    now: datetime = Depends(get_now),
) -> dict:
    """작업을 **등록만** 하고 바로 돌아온다(2026-09-25 사용자 결정 — 만드는 동안 다음 질문을 이어 간다).

    순서가 중요하다: 설정 검사 -> 기존 검사 -> 오래된 pending 정리 -> 5회 판정 -> insert -> 등록.
    """
    settings, client, profile_id = caller
    repo = _repo(settings, client)

    # (1) 못 부를 걸 알면서 행부터 남기지 않는다 — 남기면 10분 동안 다시 누를 수도 없다.
    if not (
        settings.avatar_tasks_queue
        and settings.avatar_worker_url
        and settings.avatar_tasks_service_account
    ):
        raise HTTPException(status_code=503, detail=errors.AVATAR_QUEUE_UNAVAILABLE)

    # (2) 무료 생성은 1회다 — 하트를 쓰는 재생성은 조각 7 에서 붙인다(2026-09-20 사용자 결정).
    #     5회 보상을 받은 사람도 ready 행이 있어 여기서 막힌다 = 하트가 두 번 나가지 않는다.
    if await repo.has_ready_avatar(profile_id):
        raise HTTPException(status_code=409, detail=errors.AVATAR_ALREADY_CREATED)
    if await repo.fetch_avatar_source_photo_path(profile_id) is None:
        raise HTTPException(status_code=409, detail=errors.AVATAR_SOURCE_REQUIRED)

    # (3) 죽은 작업을 먼저 치운다. **insert 전에** 해야 유니크 인덱스가 비고, 그 failed 가 아래 카운트에 들어간다.
    await repo.fail_stale_pending_avatars(profile_id, before=now - STALE_PENDING_AFTER)

    # (4) 정리 직후에 센다. 5회를 채웠으면 여기서 보상하고 끝낸다 — 큐가 아예 안 부르거나 워커가 매번
    #     죽어도 온보딩이 갇히지 않는 유일한 출구다. 5회 규칙은 "OpenAI 가 5번 거절했을 때"가 아니라
    #     "5번 해 봤을 때"의 약속이다(project_slice2_decisions_2026-09-19).
    if await repo.count_recent_consecutive_avatar_failures(profile_id) >= MAX_CONSECUTIVE_FAILURES:
        fallback_path = await apply_fallback_avatar(
            repo,
            AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client),
            settings,
            client,
            profile_id,
        )
        # 상태 조회와 **같은 함수로** 답한다 — 칸 이름도 개수도 갈라질 수 없다(앱은 파서 하나로 읽는다).
        return _avatar_status(
            "fallback",
            url=avatar_url(settings.supabase_url, fallback_path),
            hearts=FALLBACK_COMPENSATION_HEARTS,
        )

    # (5) 이미 만드는 중이면(부분 유니크 인덱스 23505) 그 행을 그대로 쓰고 작업도 다시 등록하지 않는다.
    #     중복 누름은 오류가 아니라 **조용히 같은 202** 다.
    attempt_id = await repo.insert_pending_avatar_attempt(profile_id)
    if attempt_id is None:
        response.status_code = 202
        return _avatar_status("pending")

    # (6) 등록이 실패하면 방금 만든 행을 지운다. `failed` 로 두지 않는다 — OpenAI 를 부르기도 전이라
    #     "사람이 시도한 이력" 이 아니고, 우리 인프라 사고로 무료 기회를 깎는 셈이 된다.
    try:
        await AvatarTaskQueue(
            settings.google_cloud_project,
            settings.avatar_tasks_queue,
            settings.avatar_worker_url,
            settings.avatar_tasks_service_account,
            client,
        ).enqueue(profile_id, attempt_id)
    except httpx.HTTPError:
        _logger.exception("아바타 작업 등록 실패 — 만들던 행을 되돌린다 profile_id=%s", profile_id)
        try:
            await repo.delete_avatar_attempt(attempt_id)
        except httpx.HTTPError:
            # 지우는 것마저 실패해도 갇히지 않는다 — 남은 pending 은 10분 뒤 (3) 이 치운다(최악 10분 대기).
            _logger.exception("만들던 행 되돌리기 실패 — 10분 정리에 맡긴다 attempt_id=%s", attempt_id)
        raise HTTPException(status_code=502, detail=errors.AVATAR_QUEUE_UNAVAILABLE) from None

    # (7) 원본 사진 다운로드도 OpenAI 호출도 여기서 사라졌다 — 워커(tasks_router.py)가 한다.
    response.status_code = 202
    return _avatar_status("pending")


@router.get("/profile-onboarding/avatar/status")
async def fetch_avatar_status(
    caller: Caller = Depends(get_verified_caller),
    now: datetime = Depends(get_now),
) -> dict:
    """결과 화면(05-12 계열)이 폴링한다. 로그인한 본인 것만 본다.

    `fallback` 이 **별도 상태값으로** 나가는 것이 중요하다 — `ready` 로 보내면 앱이 그냥 완성으로 읽어
    05-12d 보상 안내가 영영 안 뜬다(하트 10 은 나갔는데 사람은 왜 받았는지 모른다).
    """
    settings, client, profile_id = caller
    attempt = await _repo(settings, client).fetch_latest_avatar_attempt(profile_id)

    # 행이 하나도 없으면 none. **여기서 작업을 자동 등록하지 않는다** — 원본 사진만 고르고 앱을 닫은
    # 사람이 여기 온다. 앱은 none 을 failed 와 같게 다뤄 "다시 만들기" 를 띄운다.
    if attempt is None:
        return _avatar_status("none")

    if attempt["status"] == "ready":
        # ready 계열에는 그림 주소를 반드시 같이 싣는다 — 앱이 캐스트하는 칸은 계약이다(운영 00020).
        return _avatar_status(
            "fallback" if attempt["is_fallback"] else "ready",
            url=avatar_url(settings.supabase_url, attempt["storage_path"]),
            hearts=FALLBACK_COMPENSATION_HEARTS if attempt["is_fallback"] else None,
        )

    # 10분 넘게 만드는 중이면 실패로 **보여만 준다**(DB 는 안 고친다 — 고치는 건 POST 다).
    if attempt["status"] == "pending" and datetime.fromisoformat(attempt["created_at"]) < now - STALE_PENDING_AFTER:
        return _avatar_status("failed")
    return _avatar_status(attempt["status"])


def _avatar_status(status: str, url: str | None = None, hearts: int | None = None) -> dict:
    return {"status": status, "avatar_url": url, "compensation_hearts": hearts}


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
    from app.profile_onboarding.bio_draft import generate_bio_draft, survey_summary

    settings, client, profile_id = caller
    repo = _repo(settings, client)

    # 이미 만든 초안이 있으면 그것을 그대로 돌려준다(화면을 다시 열어도 빈 칸이 되지 않게).
    saved_draft = await repo.fetch_bio_draft(profile_id)
    if saved_draft is not None:
        return {"draft": saved_draft}

    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    summary = survey_summary(
        snapshot["survey_answers"], snapshot["mbti"], snapshot["religion"], snapshot["is_smoker"]
    )
    draft = await generate_bio_draft(
        openai_client,
        summary, snapshot["interest_tags"], snapshot["my_traits"],
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
