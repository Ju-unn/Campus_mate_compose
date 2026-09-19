import logging
from functools import lru_cache

import httpx
from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile
from google.cloud import vision

from app.settings import Settings
from app.student_verification.current_user import get_current_user_id
from app.student_verification.discord_notifier import DiscordNotifier
from app.student_verification.image_validation import is_valid_student_id_photo
from app.student_verification.matching import matches_school_and_name
from app.student_verification.ocr import VisionOcr
from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.schemas import SchoolInfoRequest, VerificationStatusResponse
from app.student_verification.storage import StudentIdStorage

router = APIRouter()
_logger = logging.getLogger(__name__)

# 테스트가 실제 Supabase·Vision 대신 목을 주입할 수 있게 하는 훅(1a auth_hooks/router.py 와 같은 패턴).
_client_override: httpx.AsyncClient | None = None
_vision_client_override: vision.ImageAnnotatorAsyncClient | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_vision_client() -> vision.ImageAnnotatorAsyncClient:
    # ADC 로 인증하므로 인자가 없다. 만드는 값이 비싸 프로세스당 하나만 둔다.
    return vision.ImageAnnotatorAsyncClient()


@router.post("/student-verification")
async def submit_student_verification(
    real_name: str = Form(),
    photo: UploadFile = File(),
    authorization: str | None = Header(default=None),
) -> dict[str, str]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    if gate["student_verification"] == "pending":
        raise HTTPException(status_code=409, detail="이미 검토 중이에요, 결과를 기다려 주세요")

    # 앱의 RealName 이 이미 막지만 여기가 신뢰 경계다 — 빈 실명은 OCR 대조에서 무조건 통과해 버린다.
    name = real_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="실명을 입력해 주세요")

    data = await photo.read()
    if not is_valid_student_id_photo(data):
        raise HTTPException(status_code=400, detail="사진을 다시 확인해 주세요")

    storage = StudentIdStorage(settings.storage_url, settings.supabase_service_role_key, client)
    file_path = await storage.upload(profile_id, data, photo.content_type or "image/jpeg")

    await repo.upsert_real_name(profile_id, name)
    # 결과가 어느 쪽이든 먼저 pending 으로 남긴다 — 삭제 트리거가 "pending → verified/rejected" 전이만 보기 때문이다.
    await repo.record_attempt(profile_id, file_path, "pending")
    await repo.update_verification_status(profile_id, "pending")

    try:
        ocr_text = await VisionOcr(_vision_client_override or get_vision_client()).extract_text(data)
    except Exception:
        # Vision 장애·할당량 초과로 500 을 내면 상태가 pending 에 갇혀 재제출이 409 로 막힌다.
        # 자동 대조 실패로 보고 사람 재검토로 넘긴다(그게 pending 의 뜻이다).
        _logger.exception("Vision OCR 실패 — 사람 재검토로 넘긴다")
        ocr_text = ""

    if not matches_school_and_name(ocr_text, gate["universities"]["name"], name):
        await DiscordNotifier(settings.discord_webhook_url, client).notify_pending_review()
        return {"status": "pending"}

    await repo.update_verification_status(profile_id, "verified")
    return {"status": "verified"}


@router.get("/me/verification-status")
async def fetch_verification_status(authorization: str | None = Header(default=None)) -> VerificationStatusResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    status = gate["student_verification"]
    return VerificationStatusResponse(
        status=status,
        has_school_info=gate["department"] is not None,
        reject_reason=await repo.fetch_reject_reason(profile_id) if status == "rejected" else None,
    )


@router.post("/school-info")
async def save_school_info(body: SchoolInfoRequest, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail="학생증 인증을 먼저 끝내 주세요")

    await repo.save_school_info(profile_id, body.department, body.student_number)
    return {"ok": True}
