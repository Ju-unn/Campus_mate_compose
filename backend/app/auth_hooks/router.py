from fastapi import APIRouter, Depends, HTTPException, Request

from app.auth_hooks.schemas import HookDecision
from app.core import errors
from app.core.deps import get_settings
from app.settings import Settings
from app.webhook_signature import verify_webhook_signature

router = APIRouter()


@router.post("/hooks/before-user-created", response_model_exclude_none=True)
async def before_user_created(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> HookDecision:
    """서명만 보고 항상 허용한다(소셜 로그인 전환).

    소셜 계정에는 학교 메일이 없다(카카오는 이메일조차 없다). 학교 도메인 · 재가입 제한 검사는
    가입 뒤 학교 메일 확인(POST /school-email/check · confirm)이 같은 해시로 한다."""
    body = await request.body()
    _verify_signature_or_raise(settings, request.headers, body)
    return HookDecision.allow()


def _verify_signature_or_raise(settings: Settings, headers, body: bytes) -> None:
    webhook_id = headers.get("webhook-id", "")
    timestamp = headers.get("webhook-timestamp", "")
    signature = headers.get("webhook-signature", "")
    valid = verify_webhook_signature(settings.auth_hook_signing_secret, webhook_id, timestamp, body, signature)
    if not valid:
        raise HTTPException(status_code=401, detail=errors.INVALID_SIGNATURE)
