import httpx
from fastapi import APIRouter, Depends, HTTPException, Request

from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision
from app.core import errors
from app.core.deps import get_client, get_settings
from app.settings import Settings
from app.signup_policy import SignupPolicy, hash_email
from app.webhook_signature import verify_webhook_signature

router = APIRouter()


@router.post("/hooks/before-user-created")
async def before_user_created(
    request: Request,
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> HookDecision:
    body = await request.body()
    _verify_signature_or_raise(settings, request.headers, body)

    payload = BeforeUserCreatedPayload.model_validate_json(body)
    policy = SignupPolicy(settings.postgrest_url, settings.supabase_service_role_key, client)

    university_id = await policy.find_university_id(payload.email_domain)
    if university_id is None:
        return HookDecision.reject("허용되지 않은 학교 이메일이에요")

    email_hmac = hash_email(settings.auth_hook_signing_secret, payload.email)
    if await policy.is_blocked(email_hmac):
        return HookDecision.reject("재가입이 제한된 이메일이에요")

    return HookDecision.allow()


def _verify_signature_or_raise(settings: Settings, headers, body: bytes) -> None:
    webhook_id = headers.get("webhook-id", "")
    timestamp = headers.get("webhook-timestamp", "")
    signature = headers.get("webhook-signature", "")
    valid = verify_webhook_signature(settings.auth_hook_signing_secret, webhook_id, timestamp, body, signature)
    if not valid:
        raise HTTPException(status_code=401, detail=errors.INVALID_SIGNATURE)
