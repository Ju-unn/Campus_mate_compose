import hmac
from datetime import datetime

import httpx
from fastapi import APIRouter, Header, HTTPException

from app.cards.issuing import issue_daily_cards
from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.core import errors
from app.core.deps import get_settings
from app.core.time import SEOUL
from app.matching.repository import MatchingRepository

router = APIRouter()

_client_override: httpx.AsyncClient | None = None


@router.post("/batch/daily-cards")
async def run_daily_cards(x_batch_secret: str | None = Header(default=None)) -> dict:
    """Cloud Scheduler 전용. Cloud Run 이 --allow-unauthenticated 라 이 엔드포인트는 스스로를 지킨다
    (조각 1a 의 auth hook 이 서명으로 자기를 지키는 것과 같은 이유)."""
    settings = get_settings()
    if not settings.card_batch_secret or not x_batch_secret or not hmac.compare_digest(
        x_batch_secret, settings.card_batch_secret
    ):
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)

    client = _client_override or httpx.AsyncClient()
    card_repo = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    matching_repo = MatchingRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    sender = FcmSender(settings.google_cloud_project, client)
    return await issue_daily_cards(card_repo, matching_repo, sender, now=datetime.now(SEOUL))
