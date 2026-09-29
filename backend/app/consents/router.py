"""가입 동의(화면 02-c). 계획서 docs/superpowers/plans/2026-09-29-signup-consent.md Task 2."""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.cards.repository import CardRepository
from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.consents.repository import ConsentRepository
from app.core import errors
from app.core.deps import Caller, get_caller, get_now

router = APIRouter()


class ConsentRequest(BaseModel):
    agreed: list[Literal["terms", "privacy", "sensitive_religion", "overseas_transfer"]]
    marketing: bool = False


@router.post("/me/consents")
async def submit_consents(
    body: ConsentRequest, caller: Caller = Depends(get_caller), now: datetime = Depends(get_now)
) -> dict[str, bool]:
    """필수 4항목은 이번 판으로 쌓는다. 학생증 관문 앞이라 get_caller 다(탈퇴만 막힌다)."""
    settings, client, profile_id = caller
    if set(body.agreed) != REQUIRED_KINDS:
        raise HTTPException(status_code=400, detail=errors.CONSENT_INCOMPLETE)
    key = settings.supabase_service_role_key
    await ConsentRepository(settings.postgrest_url, key, client).record(profile_id, body.agreed, CONSENT_VERSION)
    if body.marketing:
        # 켤 때만 쓴다 — 재동의에서 안 켰다고 이미 받은 수신 동의를 끄지 않는다(끄기는 16d).
        # 동의 시각은 16d 와 같이 서버가 적는다(cards/router.py update_notification_settings).
        await CardRepository(settings.postgrest_url, key, client).update_notification_settings(
            profile_id, marketing=True, marketing_consented_at=now.astimezone(timezone.utc).isoformat()
        )
    return {"ok": True}
