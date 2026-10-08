"""학교 메일 확인(소셜 로그인 전환). 순서: 소셜 로그인 → 약관 동의 → **학교 메일** → 학생증 → 학과와 학번.

인증번호는 서버가 만들거나 보내지 않는다. 앱이 소셜 연결과 따로 둔 저장 없는 Supabase 연결로 학교 메일 OTP 를
받아 provider=email 인 임시 계정을 만들고, 서버(POST /school-email/verify)는 그 임시 토큰을 검사한 뒤 지운다.
옛 check · confirm(소셜 계정에 updateUser(email) 로 이메일을 붙이는 방식)은 폐기했다(지시문 05).
"""
import logging

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from app.account.repository import SupabaseAdmin
from app.consents.repository import require_current_consent
from app.core import errors
from app.core.deps import Caller, get_caller
from app.school_email.repository import SchoolEmailRepository
from app.signup_policy import SignupPolicy, hash_email
from app.student_verification.current_user import fetch_auth_user, reject_suspended

router = APIRouter()
logger = logging.getLogger(__name__)

SOCIAL_PROVIDERS = frozenset({"kakao", "google", "apple"})


def _taken_response(provider: str) -> JSONResponse:
    """409. `detail` 은 다른 오류와 같은 자리의 문구, `provider` 는 앱이 가르는 기계용 값이다."""
    label = errors.SCHOOL_EMAIL_PROVIDER_LABELS.get(provider, provider)
    return JSONResponse(status_code=409, content={
        "detail": errors.SCHOOL_EMAIL_TAKEN.format(provider=label), "provider": provider,
    })


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def _gate(caller: Caller) -> dict:
    """정지 → 동의. 정지 응답이 먼저 나가야 앱이 정지 안내 화면으로 간다. 탈퇴는 get_caller 가 이미 막았다."""
    settings, client, profile_id = caller
    state = await SchoolEmailRepository(settings.postgrest_url, settings.supabase_service_role_key, client
                                        ).fetch_state(profile_id)
    reject_suspended(state.get("status"))
    await require_current_consent(settings, client, profile_id)
    return state


# POST /school-email/verify (지시문 05) -------------------------------------------------------------
#
# 앱은 소셜 연결과 따로 둔 저장 없는 Supabase 연결로 학교 메일에 OTP 를 받아 확인한다. 그러면 provider=email 인
# **임시 계정**이 생긴다. 앱은 소셜 토큰(Authorization)과 그 임시 계정의 access_token 을 같이 보낸다.
# 학교 메일의 증거는 오직 임시 계정 토큰의 이메일이다 — 소셜 계정의 email_confirmed_at · 이메일은 보지 않는다
# (소셜 계정은 가입 순간 email_confirmed_at 이 채워진다. 카카오는 이메일이 없는데도).


class VerifyRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    temp_access_token: str = Field(min_length=1)


def _caller_provider(auth_user: dict) -> str | None:
    """호출한 사람의 주 로그인 수단(app_metadata.provider). 소셜 셋 중 하나가 아니면 None — 못 읽어도 None."""
    provider = (auth_user.get("app_metadata") or {}).get("provider")
    return provider if provider in SOCIAL_PROVIDERS else None


def confirmed_temp_email(temp_user: dict, caller_id: str) -> str | None:
    """임시 이메일 계정이면 그 이메일(소문자 · 공백 제거), 아니면 None.

    identities 가 정확히 email 하나, email_confirmed_at 있음, email 있음, id 가 호출한 사람과 다름 —
    소셜 토큰(남의 것이든 본인 것이든)을 임시 자리에 넣는 공격을 여기서 막는다."""
    identities = temp_user.get("identities") or []
    if [identity.get("provider") for identity in identities] != ["email"]:
        return None
    if not temp_user.get("email_confirmed_at"):
        return None
    email = normalize_email(temp_user.get("email") or "")
    if not email or not temp_user.get("id") or str(temp_user["id"]) == caller_id:
        return None
    return email


async def delete_temp_account(admin: SupabaseAdmin, temp_id: str, caller_id: str) -> None:
    """임시 이메일 계정을 관리자 API 로 지운다(최선만). 실패는 경고만 — 정리 배치가 하루 뒤 지운다.
    이메일 · 토큰은 로그에 남기지 않는다. **호출한 사람의 id 면 절대 부르지 않는다**(삭제 직전 한 번 더)."""
    if str(temp_id) == str(caller_id):
        logger.error("임시 계정 삭제를 멈춤 — 호출한 사람과 같은 id profile=%s", caller_id)
        return
    try:
        await admin.delete_user(temp_id)
    except Exception as exc:
        logger.warning("임시 이메일 계정 삭제 실패 — 정리 배치가 지운다 %s", type(exc).__name__)


@router.post("/school-email/verify")
async def verify(
    body: VerifyRequest,
    caller: Caller = Depends(get_caller),
    authorization: str | None = Header(default=None),
) -> dict[str, bool]:
    """정지 → 동의 → 이미 인증 → 소셜 계정만 → 임시 토큰 읽기 → 임시 계정 검사 → 도메인 → 재가입 제한 → DB 함수.

    앞에서 걸리면 거기서 끝이다. 도메인 검사까지 와서 결과가 정해지면 임시 계정을 지운다(422 · 409 포함).
    같은 요청을 두 번 보내면 두 번째는 '이미 인증'(3번)이 임시 토큰 거절(5번)보다 먼저 걸린다."""
    settings, client, profile_id = caller
    caller_id = str(profile_id)

    state = await _gate(caller)  # 1 정지 · 2 동의
    if state.get("school_email_verified_at") is not None:  # 3
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_ALREADY_VERIFIED)

    try:
        caller_user = await fetch_auth_user(settings, client, authorization)
    except httpx.HTTPStatusError:
        raise HTTPException(status_code=401, detail=errors.SESSION_EXPIRED)
    provider = _caller_provider(caller_user)
    if provider is None:  # 4
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_SOCIAL_ONLY)

    try:  # 5 — 장애(5xx · 429 · 연결 실패)는 fetch_auth_user 가 503 으로 올린다
        temp_user = await fetch_auth_user(settings, client, f"Bearer {body.temp_access_token}")
    except httpx.HTTPStatusError:
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_NOT_CONFIRMED)
    email = confirmed_temp_email(temp_user, caller_id)
    if email is None:  # 6 — 남의 계정일 수 있어 지우지 않는다
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_NOT_CONFIRMED)

    outcome = await _decide(caller, email, provider)
    await delete_temp_account(SupabaseAdmin(settings, client), temp_user["id"], caller_id)
    return outcome


def _refusal(status_code: int, detail: str) -> JSONResponse:
    """HTTPException 과 같은 모양({"detail": ...}). 결과가 정해진 거절이라 예외 대신 돌려준다 — 임시 계정을 지운 뒤 낸다."""
    return JSONResponse(status_code=status_code, content={"detail": detail})


async def _decide(caller: Caller, email: str, provider: str):
    """7 도메인 → 8 재가입 제한 → 9 DB 함수. 결과가 정해지면 응답을 **돌려준다**(부르는 쪽이 임시 계정을 지운다).
    DB 함수 자체가 실패하면 예외로 올린다 — 결과가 안 정해졌으니 임시 계정을 남겨 앱이 다시 부를 수 있게 한다."""
    settings, client, profile_id = caller
    policy = SignupPolicy(settings.postgrest_url, settings.supabase_service_role_key, client)
    university_id = await policy.find_university_id(email.rsplit("@", 1)[-1])
    if university_id is None:
        return _refusal(422, errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN)
    email_hmac = hash_email(settings.identity_hmac_key, email)
    if await policy.is_blocked(email_hmac):
        return _refusal(422, errors.SCHOOL_EMAIL_BLOCKED)

    repo = SchoolEmailRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    result = await repo.complete_verification(profile_id, email_hmac, university_id, provider)
    if result == "ok":
        return {"ok": True}
    if result == "already_verified":
        return _refusal(403, errors.SCHOOL_EMAIL_ALREADY_VERIFIED)
    if result == "no_profile":
        return _refusal(404, errors.PROFILE_NOT_FOUND)
    return _taken_response(result)
