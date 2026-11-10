"""휴대폰 문자 인증(계획서 문자인증_솔라피_계획_11-10 §1 · §4-2-1). 가입 기본 정보 화면이 부른다.

보내기: 010 번호만 → DB 함수가 한도 · 이미 보냄 · 다른 계정 번호를 판정하고 줄을 넣는다 → issued 일 때만 문자 한 통.
확인: 가장 최근 번호만, 3분, 5번 틀리면 잠금. 맞힌 인증은 기본 정보 저장이 30분 안에 한 번 쓴다(profile_onboarding/router.py).
관문은 기본 정보 저장과 같은 get_verified_caller(학교 메일 · 학과까지) — 그 앞의 계정은 문자를 보낼 일이 없다.
"""
import hashlib
import hmac
import logging
import secrets
from uuid import UUID

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.core import errors
from app.core.deps import Caller, get_verified_caller
from app.phone_verification.repository import PhoneVerificationRepository
from app.phone_verification.sms import VERIFICATION_TEXT, SmsSender, get_sms_sender
from app.profile_onboarding.phone_number import to_signup_e164
from app.settings import Settings
from app.signup_policy import hash_phone
from app.student_verification.discord_notifier import DiscordNotifier

logger = logging.getLogger(__name__)
router = APIRouter()

_RATE_LIMITS = {"number_cooldown", "number_daily_limit", "account_daily_limit", "global_daily_limit"}


class SendRequest(BaseModel):
    phone_number: str = Field(max_length=30)


class VerifyRequest(BaseModel):
    phone_number: str = Field(max_length=30)
    # ASCII 숫자 6자리만(\d 는 전각 숫자도 받는다).
    code: str = Field(pattern=r"^[0-9]{6}$")


def hash_code(secret: str, phone_e164: str, code: str) -> bytes:
    """인증번호 HMAC(신원 키). 원문은 저장하지 않는다 — 6자리라 키 없는 해시는 표가 새면 바로 풀린다."""
    return hmac.new(secret.encode(), f"phone-code:{phone_e164}:{code}".encode(), hashlib.sha256).digest()


def _error(status: int, detail: str, code: str, **extra) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": detail, "code": code, **extra})


def _invalid_number() -> JSONResponse:
    return _error(400, errors.PHONE_NUMBER_INVALID, errors.CODE_PHONE_NUMBER_INVALID)


def _repo(settings: Settings, client) -> PhoneVerificationRepository:
    return PhoneVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)


@router.post("/phone-verification/send", response_model=None)
async def send_code(
    body: SendRequest,
    caller: Caller = Depends(get_verified_caller),
    sender: SmsSender | None = Depends(get_sms_sender),
) -> dict | JSONResponse:
    settings, client, profile_id = caller
    # 국내 010 만 — 해외 번호로 비싼 문자를 대량으로 보내게 하는 공격(SMS 펌핑)을 막는다. 가짜 번호 규칙도 같이 본다.
    phone = to_signup_e164(body.phone_number)
    if phone is None:
        return _invalid_number()
    if sender is None:
        return _error(503, errors.SMS_UNAVAILABLE, errors.CODE_SMS_UNAVAILABLE)

    code = f"{secrets.randbelow(1_000_000):06d}"
    repo = _repo(settings, client)
    issued = await repo.issue(profile_id, hash_phone(settings.identity_hmac_key, phone),
                              hash_code(settings.identity_hmac_key, phone, code), settings.sms_daily_global_limit)
    result = issued["result"]
    if result == "already_sent":
        return {"resend_after_seconds": issued["retry_after_seconds"],
                "expires_in_seconds": issued["expires_in_seconds"], "already_sent": True}
    if result == "in_use":
        return _error(409, errors.PHONE_NUMBER_IN_USE, errors.CODE_PHONE_NUMBER_IN_USE)
    if result in _RATE_LIMITS:
        seconds = issued["retry_after_seconds"]
        response = _error(429, errors.PHONE_VERIFICATION_RATE_LIMITED, errors.CODE_PHONE_VERIFICATION_RATE_LIMITED,
                          retry_after_seconds=seconds)
        response.headers["Retry-After"] = str(seconds)
        return response
    if result != "issued":
        raise RuntimeError(f"모르는 보내기 결과 {result}")

    if not await sender.send(phone, VERIFICATION_TEXT.format(code=code)):
        await _forget(repo, issued["verification_id"], profile_id)
        return _error(503, errors.SMS_UNAVAILABLE, errors.CODE_SMS_UNAVAILABLE)
    if issued["global_limit_reached"]:
        await DiscordNotifier(settings.discord_webhook_url, client).notify_sms_daily_limit(settings.sms_daily_global_limit)
    return {"resend_after_seconds": issued["retry_after_seconds"],
            "expires_in_seconds": issued["expires_in_seconds"], "already_sent": False}


async def _forget(repo: PhoneVerificationRepository, verification_id: str, profile_id: UUID) -> None:
    """못 보낸 줄은 지운다 — 남기면 그 사람의 한도(1분 · 하루)를 먹는다. 지우기 실패는 로그만(응답은 그대로 503)."""
    try:
        await repo.delete(verification_id)
    except Exception as exc:
        logger.warning("못 보낸 인증 줄 지우기 실패 profile=%s %s", profile_id, type(exc).__name__)


@router.post("/phone-verification/verify", response_model=None)
async def verify_code(body: VerifyRequest, caller: Caller = Depends(get_verified_caller)) -> dict | JSONResponse:
    settings, client, profile_id = caller
    phone = to_signup_e164(body.phone_number)
    if phone is None:
        return _invalid_number()

    repo = _repo(settings, client)
    attempt = await repo.attempt(profile_id, hash_phone(settings.identity_hmac_key, phone))
    result = attempt["result"]
    if result == "verified":
        return {"verified": True}
    if result == "expired":
        return _error(400, errors.PHONE_CODE_EXPIRED, errors.CODE_PHONE_CODE_EXPIRED)
    if result == "locked":
        return _error(400, errors.PHONE_CODE_LOCKED, errors.CODE_PHONE_CODE_LOCKED)

    # result == check: 시도 한 칸은 DB 가 이미 썼다. 비교는 시간 차이로 정답을 알 수 없게.
    stored = bytes.fromhex(attempt["code_hash"].removeprefix("\\x"))
    if hmac.compare_digest(stored, hash_code(settings.identity_hmac_key, phone, body.code)):
        await repo.mark_verified(attempt["verification_id"])
        return {"verified": True}
    if attempt["attempts_left"] == 0:
        return _error(400, errors.PHONE_CODE_LOCKED, errors.CODE_PHONE_CODE_LOCKED)
    return _error(400, errors.PHONE_CODE_MISMATCH, errors.CODE_PHONE_CODE_MISMATCH,
                  remaining_attempts=attempt["attempts_left"])
