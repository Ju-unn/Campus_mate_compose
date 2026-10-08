"""학교 메일 확인(소셜 로그인 전환). 순서: 소셜 로그인 → 약관 동의 → **학교 메일** → 학생증 → 학과와 학번.

인증코드는 서버가 만들거나 보내지 않는다 — 앱이 Supabase 계정 이메일 바꾸기(`updateUser(email)` →
메일 속 6자리 → `verifyOTP(type: emailChange)`)를 직접 한다. 서버는 그 앞(check)과 뒤(confirm)에서 검사만 한다.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.consents.repository import require_current_consent
from app.core import errors
from app.core.deps import Caller, get_caller, get_now
from app.school_email.repository import SchoolEmailRepository, fetch_auth_user
from app.signup_policy import SignupPolicy, hash_email
from app.student_verification.current_user import reject_suspended

router = APIRouter()


class SchoolEmailRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class _TakenByOtherAccount(Exception):
    def __init__(self, provider: str):
        self.provider = provider


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


async def check_school_email(caller: Caller, email: str) -> str:
    """도메인 → 재가입 제한 → 다른 계정. 통과하면 그 도메인의 university_id 를 돌려준다.

    check(코드 보내기 전)와 confirm(인증 끝난 뒤)이 같은 검사를 한다."""
    settings, client, profile_id = caller
    policy = SignupPolicy(settings.postgrest_url, settings.supabase_service_role_key, client)

    university_id = await policy.find_university_id(email.rsplit("@", 1)[-1])
    if university_id is None:
        raise HTTPException(status_code=422, detail=errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN)
    if await policy.is_blocked(hash_email(settings.identity_hmac_key, email)):
        raise HTTPException(status_code=422, detail=errors.SCHOOL_EMAIL_BLOCKED)
    provider = await policy.find_other_account_provider(email, str(profile_id))
    if provider is not None:
        raise _TakenByOtherAccount(provider)
    return university_id


@router.post("/school-email/check")
async def check(body: SchoolEmailRequest, caller: Caller = Depends(get_caller)) -> dict[str, bool]:
    """인증코드를 **보내기 전** 확인. 로그인만 본다(학교 메일 관문 앞이다)."""
    await _gate(caller)
    try:
        await check_school_email(caller, normalize_email(body.email))
    except _TakenByOtherAccount as taken:
        return _taken_response(taken.provider)
    return {"ok": True}


def verified_school_email(auth_user: dict) -> str | None:
    """앱이 verifyOTP(emailChange) 까지 끝낸 계정의 이메일(소문자), 아니면 None.

    email_confirmed_at 은 보지 않는다 — 소셜 계정은 가입하는 순간 채워진다(카카오는 이메일이 없는데도).
    provider `email` identity 가 붙어 있어야 한다. 학교 도메인인지는 check_school_email 이 이어서 본다."""
    providers = {identity.get("provider") for identity in auth_user.get("identities") or []}
    email = normalize_email(auth_user.get("email") or "")
    return email if "email" in providers and email else None


@router.post("/school-email/confirm")
async def confirm(
    caller: Caller = Depends(get_caller),
    authorization: str | None = Header(default=None),
    now: datetime = Depends(get_now),
) -> dict[str, bool]:
    """앱이 verifyOTP 성공 **뒤** 부른다 — 앱을 거치지 않은 updateUser 우회를 막는 두 번째 검사.

    이미 기록돼 있으면 건드리지 않고 200 이다(여러 번 불러도 같다)."""
    settings, client, profile_id = caller
    state = await _gate(caller)
    if state.get("school_email_verified_at") is not None:
        return {"ok": True}

    email = verified_school_email(await fetch_auth_user(settings, client, authorization))
    if email is None:
        raise HTTPException(status_code=403, detail=errors.SCHOOL_EMAIL_NOT_VERIFIED)
    try:
        university_id = await check_school_email(caller, email)
    except _TakenByOtherAccount as taken:
        return _taken_response(taken.provider)

    repo = SchoolEmailRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    await repo.record_verified(profile_id, university_id, now.astimezone(timezone.utc))
    return {"ok": True}
