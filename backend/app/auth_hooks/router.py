import httpx
from fastapi import APIRouter, Depends, HTTPException, Request

from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision
from app.core import errors
from app.core.deps import get_client, get_settings
from app.settings import Settings
from app.signup_policy import SignupPolicy, hash_email
from app.webhook_signature import verify_webhook_signature

router = APIRouter()

SOCIAL_PROVIDERS = frozenset({"kakao", "google", "apple"})


@router.post("/hooks/before-user-created", response_model_exclude_none=True)
async def before_user_created(
    request: Request,
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> HookDecision:
    """소셜(kakao · google · apple)은 검사 없이 허용, 이메일 방식만 학교 도메인 · 재가입 제한을 본다.

    이메일 방식 계정은 이제 학교 메일 인증용 임시 계정이다(POST /school-email/verify 가 검사 뒤 지운다).
    가입 수단을 못 읽거나 모르는 값이면 거절한다 — 실패하면 열지 않는다."""
    body = await request.body()
    _verify_signature_or_raise(settings, request.headers, body)

    payload = BeforeUserCreatedPayload.model_validate_json(body)
    provider = payload.provider
    if provider in SOCIAL_PROVIDERS:
        return HookDecision.allow()
    if provider != "email" or not payload.email:
        return HookDecision.reject(errors.HOOK_UNKNOWN_PROVIDER)

    policy = SignupPolicy(settings.postgrest_url, settings.supabase_service_role_key, client)
    university_id = await policy.find_university_id(payload.email_domain)
    if university_id is None:
        return HookDecision.reject(errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN)

    email_hmac = hash_email(settings.identity_hmac_key, payload.email)
    if await policy.is_blocked(email_hmac):
        return HookDecision.reject(errors.SCHOOL_EMAIL_BLOCKED)

    return HookDecision.allow()


def _verify_signature_or_raise(settings: Settings, headers, body: bytes) -> None:
    webhook_id = headers.get("webhook-id", "")
    timestamp = headers.get("webhook-timestamp", "")
    signature = headers.get("webhook-signature", "")
    valid = verify_webhook_signature(settings.auth_hook_signing_secret, webhook_id, timestamp, body, signature)
    if not valid:
        raise HTTPException(status_code=401, detail=errors.INVALID_SIGNATURE)
