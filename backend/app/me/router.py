import logging
from datetime import datetime
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from google.cloud import vision
from openai import AsyncOpenAI

from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller, get_vision_client
from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors
from app.me.photo_layout import parse_layout
from app.me.repository import MeRepository
from app.me.schemas import ProfileUpdateRequest, nickname_changeable_at
from app.profile_onboarding.avatars import STALE_PENDING_AFTER, avatar_regen_cost
from app.profile_onboarding.photos import check_safe_search
from app.profile_onboarding.repository import ProfileOnboardingRepository
from app.profile_onboarding.router import avatar_url, enqueue_avatar_attempt, get_openai
from app.profile_onboarding.storage import ProfilePhotoStorage
from app.student_verification.image_validation import student_id_content_type

router = APIRouter()
_logger = logging.getLogger(__name__)

# 실사진 서명 URL 의 유효 시간. 채팅방(chat/router.py)과 같은 1시간이다.
PHOTO_URL_TTL_SECONDS = 3600


def _latest_avatar_url(profile: dict, supabase_url: str) -> str | None:
    # 채팅방 _avatar_url 과 같은 규칙 — ready 중 가장 늦게 만든 한 장, 없으면 None.
    ready = [a for a in profile["profile_avatars"] if a["status"] == "ready"]
    latest = max(ready, key=lambda a: a["created_at"], default=None)
    return avatar_url(supabase_url, latest["storage_path"]) if latest else None


@router.get("/me/profile")
async def get_my_profile(
    caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now),
) -> dict:
    """화면 15 내 프로필. 인증 전 게이트는 기존 /me/verification-status 가 맡고, 이 API 는 관문을
    통과한 사람만 닿으니 화면 15 배지는 늘 '인증 완료'다 — 그래서 인증 상태는 싣지 않는다."""
    settings, client, profile_id = caller
    key = settings.supabase_service_role_key
    profile = await MeRepository(settings.postgrest_url, key, client).fetch_profile(profile_id)
    photos = ProfilePhotoStorage(settings.storage_url, key, client)

    # embed 순서는 PostgREST 가 보장하지 않는다 — 대표 사진(0번)부터 여기서 줄 세운다.
    ordered = sorted(profile["profile_photos"], key=lambda p: p["position"])
    # 서명은 사진마다 한 번 — 옛 칸(photo_urls)과 새 칸(photos)이 같은 주소를 나눠 쓴다.
    urls = [await photos.create_signed_url(p["storage_path"], PHOTO_URL_TTL_SECONDS) for p in ordered]
    ready_count = sum(1 for a in profile["profile_avatars"] if a["status"] == "ready")
    changed_at = profile["nickname_changed_at"]
    changeable_at = nickname_changeable_at(changed_at and datetime.fromisoformat(changed_at), now)
    # 인증 관문은 온보딩 완료를 보지 않으니 출생연도가 아직 비었을 수 있다 — 그때 나이는 null.
    birth_year = profile["birth_year"]
    return {
        "nickname": profile["nickname"],
        # 화면은 "늑대, 24" 처럼 쓴다(pen `xew8J`). 조각 2 와 같은 계산식을 쓴다.
        "age": now.year - birth_year + 1 if birth_year is not None else None,
        "university": profile["universities"]["name"],
        "major": profile["major"],
        "height_cm": profile["height_cm"],
        "mbti": profile["mbti"],
        "avatar_url": _latest_avatar_url(profile, settings.supabase_url),
        # 옛 앱이 읽는 칸이라 남긴다(서버가 먼저 배포된다). 새 앱은 photos 를 읽는다.
        "photo_urls": urls,
        "preferred_age_min": profile["preferred_age_min"],
        "preferred_age_max": profile["preferred_age_max"],
        "preferred_height_min": profile["preferred_height_min"],
        "preferred_height_max": profile["preferred_height_max"],
        "bio": profile["bio"],
        # 15c 칩 · 태그 편집 · 06-1 편집을 서버 값으로 채운다.
        "interest_tags": profile["interest_tags"],
        "my_traits": profile["my_traits"],
        "ideal_traits": profile["ideal_traits"],
        "preferred_mbti_flags": profile["preferred_mbti_flags"],
        "preferred_animal_types": profile["preferred_animal_types"],
        "preferred_impression_types": profile["preferred_impression_types"],
        # 15e 사진 교체는 행 id 로 "남길 사진" 을 가리킨다(PUT /me/photos).
        "photos": [
            {"id": p["id"], "url": url, "is_avatar_source": p["is_avatar_source"]} for p, url in zip(ordered, urls)
        ],
        # entitlements 는 처음 하트를 받을 때 생긴다 — 1:1 embed 라 없으면 null 로 온다.
        "heart_balance": (profile["entitlements"] or {}).get("heart_balance", 0),
        "avatar_regen_cost": avatar_regen_cost(ready_count),
        # 앱 시계를 믿지 않는다 — PATCH 409 와 같은 함수로 판정해 15d-2 "M월 D일부터" 에 쓴다(C6).
        "nickname_changeable_at": changeable_at and changeable_at.isoformat(),
    }


@router.post("/me/avatar/regenerate")
async def regenerate_avatar(
    response: Response,
    caller: Caller = Depends(get_verified_caller),
    now: datetime = Depends(get_now),
) -> dict:
    """15b "만들기". 등록만 하고 202 로 돌아온다 — 결과는 기존 /profile-onboarding/avatar/status 로 묻는다.

    하트는 여기서 빼지 않는다(계획서 T2 — 워커가 완성을 적은 뒤에 뺀다). 5회 실패 보상 출구도 없다(T3)."""
    settings, client, profile_id = caller
    repo = ProfileOnboardingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    # 온보딩 POST 와 같은 앞문 순서다: 설정 → 기존 검사 → 오래된 pending 정리 → (하트) → 등록.
    if not (settings.avatar_tasks_queue and settings.avatar_worker_url and settings.avatar_tasks_service_account):
        raise HTTPException(status_code=503, detail=errors.AVATAR_QUEUE_UNAVAILABLE)
    ready_count = await repo.count_ready_avatars(profile_id)
    if ready_count == 0:
        # 첫 아바타는 온보딩 POST 몫이다 — 여기로 오면 5회 보상 출구 없이 무료로 돌아 버린다.
        raise HTTPException(status_code=409, detail=errors.AVATAR_NOT_CREATED)
    if await repo.fetch_avatar_source_photo_path(profile_id) is None:
        raise HTTPException(status_code=409, detail=errors.AVATAR_SOURCE_REQUIRED)

    await repo.fail_stale_pending_avatars(profile_id, before=now - STALE_PENDING_AFTER)

    # 못 낼 사람에게 유료 생성을 돌리지 않는 앞문일 뿐이다 — 실제 차감은 워커가 완성 뒤에 한다.
    cost = avatar_regen_cost(ready_count)
    if cost:
        me_repo = MeRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
        if await me_repo.fetch_heart_balance(profile_id) < cost:
            raise HTTPException(status_code=402, detail=errors.HEARTS_NOT_ENOUGH)

    return await enqueue_avatar_attempt(repo, settings, client, profile_id, response)


@router.put("/me/photos")
async def save_photos(
    layout: str = Form(),
    avatar_source: int = Form(),
    photos: list[UploadFile] = File(default=[]),
    caller: Caller = Depends(get_verified_caller),
    vision_client: vision.ImageAnnotatorAsyncClient = Depends(get_vision_client),
) -> dict[str, bool]:
    """실제 사진 교체(U2) — 남길 사진은 id, 새 사진은 파일. 순서는 계획서 2-2 ①~⑧, ④ 앞에서 막히면 아무것도 안 바뀐다."""
    settings, client, profile_id = caller
    # ① 배치부터 본다 — 틀린 요청에 DB 도 Vision 도 부르지 않는다.
    try:
        slots = parse_layout(layout, new_count=len(photos), avatar_source=avatar_source)
    except ValueError:
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT) from None

    # ② 남길 id 는 지금 내 사진이어야 한다 — 다른 기기에서 지웠거나 남의 id 면 화면을 다시 열게 한다.
    repo = MeRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    current = {row["id"]: row for row in await repo.fetch_photo_rows(profile_id)}
    if any(isinstance(slot, str) and slot not in current for slot in slots):
        raise HTTPException(status_code=409, detail=errors.PHOTOS_CHANGED)

    # ③ 전부 먼저 본다 — 셋째 장이 부적절하면 첫째 장도 올리지 않는다.
    checked: list[tuple[bytes, str]] = []
    for photo in photos:
        data = await photo.read()
        content_type = student_id_content_type(data)
        if content_type is None:
            raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)
        if not await check_safe_search(vision_client, data):
            raise HTTPException(status_code=422, detail=errors.PHOTO_NOT_SAFE)
        checked.append((data, content_type))

    # ④ 업로드. 여기서 실패하면 행은 그대로라 올라간 파일만 주인 없이 남는다(행을 바꾸기 전이다).
    storage = ProfilePhotoStorage(settings.storage_url, settings.supabase_service_role_key, client)
    uploaded = [await storage.upload(profile_id, data, content_type) for data, content_type in checked]

    kept_ids = {slot for slot in slots if isinstance(slot, str)}
    dropped = [row for row_id, row in current.items() if row_id not in kept_ids]
    # ponytail: ⑤~⑦ 이 세 요청이다. ⑦ 이 실패하면 빠진 행은 지워지고 남긴 행은 옛 자리 · 원본 없음으로 남는다
    # (앱은 다시 읽는다). 한 트랜잭션이 필요해지면 DB 함수로 옮긴다(마이그레이션).
    if dropped:
        await repo.delete_photo_rows(profile_id, [row["id"] for row in dropped])
    await repo.clear_avatar_source(profile_id)
    await repo.upsert_photo_rows([
        {
            "id": slot if isinstance(slot, str) else str(uuid4()),
            "profile_id": str(profile_id),
            "storage_path": current[slot]["storage_path"] if isinstance(slot, str) else uploaded[slot],
            "position": position,
            "is_avatar_source": position == avatar_source,
        }
        for position, slot in enumerate(slots)
    ])
    # ⑧ 행이 먼저 바뀐 뒤에 지운다 — 거꾸로면 잠깐 동안 없는 파일을 가리키는 행이 생긴다.
    # 저장(⑤~⑦)은 이미 끝났다 — 여기서 500 을 내면 성공한 저장이 실패로 보인다. 고아 파일은 로그로 손으로 치운다.
    for row in dropped:
        try:
            await storage.delete(row["storage_path"])
        except httpx.HTTPError:
            _logger.warning("사진 삭제 실패 — 고아 파일로 남는다 profile_id=%s", profile_id)
    return {"ok": True}


@router.patch("/me/profile")
async def update_my_profile(
    body: ProfileUpdateRequest,
    caller: Caller = Depends(get_verified_caller),
    now: datetime = Depends(get_now),
    # 온보딩 라우터의 제공자를 그대로 쓴다 — 테스트가 목을 끼우는 자리가 하나여야 한다(tasks_router 와 같은 이유).
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict[str, bool]:
    """15c · 15d 저장. 온보딩 /bio 를 다시 쓰지 않는 이유 — 그쪽은 저장할 때마다 status 를 active 로 쓴다(계획서 0절)."""
    settings, client, profile_id = caller
    repo = MeRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    fields = body.model_dump(include=body.model_fields_set)

    if "nickname" in fields:
        current = await repo.fetch_nickname_state(profile_id)
        if fields["nickname"] == current["nickname"]:
            # 키만 고친 15d 저장도 닉네임을 같이 보낸다 — 같으면 30일을 새로 세지 않는다.
            del fields["nickname"]
        else:
            changed_at = current["nickname_changed_at"]
            if nickname_changeable_at(changed_at and datetime.fromisoformat(changed_at), now):
                raise HTTPException(status_code=409, detail=errors.NICKNAME_CHANGE_TOO_SOON)
            fields["nickname_changed_at"] = "now()"

    if fields:
        await repo.update_profile(profile_id, fields)
    # 자기소개만 문장 재료다(matching/sentences.py) — 수정하면 바로 다시 만든다(spec 482줄, 2026-09-19).
    if "bio" in fields:
        await refresh_vectors(
            MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client),
            openai_client, profile_id,
        )
    return {"ok": True}
