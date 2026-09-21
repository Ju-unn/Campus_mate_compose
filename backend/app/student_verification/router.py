import asyncio
import logging
from collections.abc import Callable

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from google.cloud import vision

from app.core import errors
from app.core.deps import Caller, get_caller, get_vision_client_factory
from app.student_verification.discord_notifier import DiscordNotifier
from app.student_verification.image_validation import student_id_content_type
from app.student_verification.matching import matches_school_and_name
from app.student_verification.ocr import VisionOcr
from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.schemas import SchoolInfoRequest, VerificationStatusResponse
from app.student_verification.storage import StudentIdStorage

router = APIRouter()
_logger = logging.getLogger(__name__)


@router.post("/student-verification")
async def submit_student_verification(
    # 1글자 실명은 matching.py 의 부분문자열 대조를 사실상 무력화한다(2026-09-20 분석담당 리뷰) — 최소 2자.
    # 상한은 frontend RealName 값 객체(frontend/lib/auth/model/real_name.dart)와 맞춘다.
    real_name: str = Form(min_length=2, max_length=30),
    photo: UploadFile = File(),
    caller: Caller = Depends(get_caller),
    make_vision_client: Callable[[], vision.ImageAnnotatorAsyncClient] = Depends(get_vision_client_factory),
) -> dict[str, str]:
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    status = gate["student_verification"]
    if status == "pending":
        raise HTTPException(status_code=409, detail=errors.VERIFICATION_IN_REVIEW)
    # 끝난 인증을 다시 제출하면 pending 으로 되돌아가 삭제 트리거의 "pending → verified/rejected" 전이가 꼬인다.
    if status == "verified":
        raise HTTPException(status_code=409, detail=errors.VERIFICATION_ALREADY_DONE)

    # 앱의 RealName 이 이미 막지만 여기가 신뢰 경계다 — 빈 실명은 OCR 대조에서 무조건 통과해 버린다.
    name = real_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail=errors.REAL_NAME_REQUIRED)

    data = await photo.read()
    # 클라이언트가 보낸 Content-Type 은 믿지 않는다 — 실제 Flutter 앱은 application/octet-stream 을 보내는데
    # 버킷의 mime 허용목록은 jpeg·png 뿐이다. 매직바이트가 진짜 타입이고, 검증과 판정을 한 번에 한다.
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)

    storage = StudentIdStorage(settings.storage_url, settings.supabase_service_role_key, client)
    file_path = await storage.upload(profile_id, data, content_type)

    await repo.upsert_real_name(profile_id, name)
    # 결과가 어느 쪽이든 먼저 pending 으로 남긴다 — 삭제 트리거가 "pending → verified/rejected" 전이만 보기 때문이다.
    await repo.record_attempt(profile_id, file_path, "pending")
    await repo.update_verification_status(profile_id, "pending")

    try:
        ocr_text = await VisionOcr(make_vision_client()).extract_text(data)
    except (GoogleAPIError, RuntimeError, asyncio.TimeoutError, GoogleAuthError):
        # Vision 장애·할당량 초과로 500 을 내면 상태가 pending 에 갇혀 재제출이 409 로 막힌다.
        # 자동 대조 실패로 보고 사람 재검토로 넘긴다(그게 pending 의 뜻이다).
        # 잡는 범위는 진짜 Vision 장애로 한정한다 — 넓게 잡으면 우리 코드 버그까지 "대조 실패"로 묻힌다.
        _logger.exception("Vision OCR 실패 — 사람 재검토로 넘긴다")
        ocr_text = ""

    if matches_school_and_name(ocr_text, gate["universities"]["name"], name):
        try:
            # 시도 행을 먼저 확정하고(2026-09-20 분석담당 리뷰 — 제안3, 종전엔 profiles 가 먼저였다),
            # 남에게 보이는 최종 상태인 profiles 를 나중에 바꾼다.
            await repo.update_attempt_result(profile_id, file_path, "verified")
            await repo.update_verification_status(profile_id, "verified")
            # SQL 트리거가 아니라 여기서 직접 지운다 — `delete from storage.objects`는 메타 행만 지우고
            # 실제 파일은 고아로 남는다(Supabase storage/management 문서, 2026-09-20 분석담당 리뷰).
            # 삭제 실패는 인증 결과를 실패시키지 않고 디스코드로만 알린다(고아 파일 수동 정리용).
            if not await storage.delete(file_path):
                _logger.error("학생증 사진 삭제 실패 — 고아 파일, profile_id=%s file_path=%s", profile_id, file_path)
                await DiscordNotifier(settings.discord_webhook_url, client).notify_orphaned_file(file_path)
            return {"status": "verified"}
        except httpx.HTTPError:
            # 확정을 못 쓰면 상태가 pending 에 갇혀 재제출이 409 로 막힌다 — OCR 실패와 같게 사람 재검토로 넘긴다.
            _logger.exception("학생증 인증 확정 실패 — 사람 재검토로 넘긴다")

    await DiscordNotifier(settings.discord_webhook_url, client).notify_pending_review()
    return {"status": "pending"}


@router.get("/me/verification-status")
async def fetch_verification_status(caller: Caller = Depends(get_caller)) -> VerificationStatusResponse:
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    status = gate["student_verification"]
    return VerificationStatusResponse(
        status=status,
        has_school_info=gate["department"] is not None,
        reject_reason=await repo.fetch_reject_reason(profile_id) if status == "rejected" else None,
    )


@router.post("/school-info")
async def save_school_info(body: SchoolInfoRequest, caller: Caller = Depends(get_caller)) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    if gate["student_verification"] != "verified":
        raise HTTPException(status_code=403, detail=errors.STUDENT_VERIFICATION_REQUIRED)

    await repo.save_school_info(profile_id, body.department, body.student_number)
    return {"ok": True}
