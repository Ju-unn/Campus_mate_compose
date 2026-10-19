"""졸업생 인증(졸업증명서) 신청자 API: 인증 방법 고르기 · 신청. 상태는 GET /me/verification-status 의 새 칸이 맡는다.

관문 순서: 로그인(탈퇴 401) → 정지 → 동의 → 플래그 → (본문 검증) → 방법 → 인증됨 → 대기 중 → 시도 횟수 → 사진.
오류 응답은 {"detail": 문구, "code": 코드} — 앱은 code 로 가른다(messages.py). 정지 · 동의 전 403 은 기존 관문의 모양 그대로다.

사진 · 번호 · 이메일 · OCR 글자 · 사진 경로는 로그와 디스코드에 남기지 않는다 — 신청 id 와 profile_id 만(COMMON §3).
글자 인식 결과는 관리자 화면 미리 채우기용이다. 자동 승인에 쓰지 않는다."""
import asyncio
import logging
import re
from collections.abc import Callable
from datetime import datetime
from typing import Literal
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from google.cloud import vision
from pydantic import BaseModel

from app.consents.repository import require_current_consent
from app.core import errors
from app.core.deps import Caller, get_caller, get_now, get_vision_client_factory
from app.graduate_verification import messages
from app.graduate_verification.document_reader import read_certificate
from app.graduate_verification.hashing import hash_document_number
from app.graduate_verification.repository import GraduateRequestRepository, attempts_used
from app.graduate_verification.retention import delete_photo
from app.graduate_verification.settings import graduate_enabled
from app.graduate_verification.storage import GraduateCertStorage
from app.signup_policy import IDENTITY_KEY_VERSION
from app.student_verification.current_user import reject_suspended
from app.student_verification.discord_notifier import DiscordNotifier
from app.student_verification.image_validation import MAX_IMAGE_BYTES, student_id_content_type
from app.student_verification.ocr import VisionOcr
from app.student_verification.repository import StudentVerificationRepository

router = APIRouter()
logger = logging.getLogger(__name__)

# 형식만 본다(앞 · 뒤 공백을 뗀 뒤). + 별칭과 도메인은 검사하지 않는다 — 이 값은 읽기 전용 점검에만 쓰고 옛 학교가 어디든 받는다.
_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
_EMAIL_MAX = 254
# Vision 장애로 한정한다(넓게 잡으면 우리 코드 버그까지 "글자 인식 실패"로 묻힌다).
_VISION_FAILURES = (GoogleAPIError, RuntimeError, asyncio.TimeoutError, GoogleAuthError)


class MethodBody(BaseModel):
    method: Literal["school_email", "graduate_certificate"] | None


def _error(status_code: int, message: tuple[str, str]) -> JSONResponse:
    detail, code = message
    return JSONResponse(status_code=status_code, content={"detail": detail, "code": code})


def _repo(caller: Caller) -> GraduateRequestRepository:
    return GraduateRequestRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _storage(caller: Caller) -> GraduateCertStorage:
    return GraduateCertStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client)


async def _gate(caller: Caller) -> dict:
    """정지 → 동의. 프로필 줄(인증 여부 · 방법)을 돌려준다."""
    gate = await StudentVerificationRepository(
        caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client
    ).fetch_gate_status(caller.profile_id)
    # 동의 403 은 헤더가 없어서 정지보다 먼저 나가면 앱이 정지 안내 화면으로 못 간다.
    reject_suspended(gate.get("status"))
    await require_current_consent(caller.settings, caller.client, caller.profile_id)
    return gate


@router.put("/me/verification-method", response_model=None)
async def put_verification_method(
    body: MethodBody, caller: Caller = Depends(get_caller), now: datetime = Depends(get_now),
) -> dict | JSONResponse:
    """가입 때 고른 인증 길을 서버에 쓴다([다음] 을 눌렀을 때만 — 카드를 눌러 보는 것은 앱 안 선택일 뿐이다).
    null 은 방법 고르기로 돌아가는 뒤로가기다. 인증이 끝난 뒤에는 바꿀 수 없다.

    졸업생 길 밖으로 바꾸면 대기 신청이 있으면 취소(switched)하고 사진을 지운다 — 앱의 화살표 화면에는 대기가 없지만
    다른 기기 · 옛 앱이 만든 신청이 있을 수 있다. 취소가 먼저고 값 쓰기가 나중이라 중간에 실패해도 다시 누르면 같은 결과다."""
    gate = await _gate(caller)
    if body.method == "graduate_certificate" and not graduate_enabled():
        return _error(403, messages.GRADUATE_DISABLED)
    if gate.get("school_email_verified_at") is not None:
        return _error(409, messages.ALREADY_VERIFIED)

    repo = _repo(caller)
    cancelled = None
    if body.method != "graduate_certificate":
        cancelled = await repo.cancel_pending(caller.profile_id, "switched", now)
    await repo.set_method(caller.profile_id, body.method)
    if cancelled is not None:
        await delete_photo(repo, _storage(caller), cancelled["id"], cancelled["photo_path"])
    return {"verification_method": body.method, "cancelled_request": cancelled is not None}


@router.post("/graduate-verification", status_code=201, response_model=None)
async def apply_graduate_verification(
    photo: UploadFile = File(),
    agreed: str | None = Form(default=None),
    previous_school_email: str | None = Form(default=None),
    caller: Caller = Depends(get_caller),
    make_vision_client: Callable[[], vision.ImageAnnotatorAsyncClient] = Depends(get_vision_client_factory),
) -> dict | JSONResponse:
    gate = await _gate(caller)
    if not graduate_enabled():
        return _error(403, messages.GRADUATE_DISABLED)
    if (agreed or "").strip().lower() != "true":
        return _error(400, messages.CONSENT_REQUIRED)
    previous = (previous_school_email or "").strip().lower() or None
    if previous is not None and (len(previous) > _EMAIL_MAX or not _EMAIL.fullmatch(previous)):
        return _error(400, messages.PREVIOUS_EMAIL_INVALID)
    if gate.get("verification_method") != "graduate_certificate":
        return _error(403, messages.METHOD_MISMATCH)
    if gate.get("school_email_verified_at") is not None:
        return _error(409, messages.ALREADY_VERIFIED)

    repo = _repo(caller)
    history = await repo.fetch_history(caller.profile_id)
    if any(row["status"] == "pending" for row in history):
        return _error(409, messages.ALREADY_PENDING)
    used = attempts_used(history)
    if used >= messages.MAX_ATTEMPTS:
        return _error(429, messages.ATTEMPTS_EXHAUSTED)

    # 클라이언트가 보낸 Content-Type 은 믿지 않는다 — 매직바이트가 진짜 타입이고, 크기 검증과 판정을 한 번에 한다.
    data = await photo.read(MAX_IMAGE_BYTES + 1)
    content_type = student_id_content_type(data)
    if content_type is None:
        return _error(400, (errors.PHOTO_UNREADABLE, "photo_unreadable"))

    request_id = uuid4()
    hint = await _read_hint(caller, repo, make_vision_client, data)
    path = await _storage(caller).upload(caller.profile_id, request_id, data, content_type)
    try:
        await repo.insert_pending(
            request_id=request_id, profile_id=caller.profile_id, photo_path=path, ocr_state=hint.state,
            ocr_document_number=hint.document_number, ocr_school_text=hint.school_text, previous_school_email=previous,
            document_hmac=hint.document_hmac, key_version=IDENTITY_KEY_VERSION,
        )
    except Exception as exc:
        # 신청 줄이 없으면 아무도 이 사진을 지우지 않는다(매시 배치도 신청 줄을 보고 고른다) — 지금 지운다.
        # 지우기까지 실패하면 고아 파일이라 디스코드로 알린다(계정 id 만, 경로 없음).
        if not await _storage(caller).delete(path):
            logger.error("졸업생 인증 사진 삭제 실패 — 고아 파일 profile=%s", caller.profile_id)
            await DiscordNotifier(caller.settings.discord_webhook_url, caller.client).notify_graduate_orphaned_file(
                caller.profile_id)
        if isinstance(exc, HTTPException) and exc.status_code == 409:
            return _error(409, messages.ALREADY_PENDING)
        raise

    await DiscordNotifier(caller.settings.discord_webhook_url, caller.client).notify_graduate_request(
        request_id, caller.profile_id)
    return JSONResponse(status_code=201, content={"state": "pending", "attempts_left": max(0, messages.MAX_ATTEMPTS - used - 1)})


class _Hint:
    """글자 인식으로 미리 읽은 값. OCR 이 안 되면 모두 비어 있다."""

    def __init__(self, state: str, document_number: str | None = None, school_text: str | None = None,
                 document_hmac: bytes | None = None):
        self.state = state
        self.document_number = document_number
        self.school_text = school_text
        self.document_hmac = document_hmac


async def _read_hint(caller: Caller, repo: GraduateRequestRepository,
                     make_vision_client: Callable[[], vision.ImageAnnotatorAsyncClient], data: bytes) -> _Hint:
    try:
        text = await VisionOcr(make_vision_client()).extract_text(data)
    except _VISION_FAILURES as exc:
        # Vision 장애 · 할당량 초과로 신청을 막지 않는다 — 관리자가 사진을 보고 번호를 직접 읽는다. 오류 문구는 남기지 않는다.
        logger.warning("졸업생 인증 글자 인식 실패 profile=%s %s", caller.profile_id, type(exc).__name__)
        return _Hint("failed")
    if not text.strip():
        return _Hint("nothing_found")
    reading = read_certificate(text, [row["name"] for row in await repo.fetch_university_names()])
    if reading.document_number is None and not reading.school_names:
        return _Hint("nothing_found")
    return _Hint(
        "read", reading.document_number, " / ".join(reading.school_names) or None,
        None if reading.document_number is None
        else hash_document_number(caller.settings.identity_hmac_key, reading.document_number),
    )
