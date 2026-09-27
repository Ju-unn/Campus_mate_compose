import logging
from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, Header

from app.cards.issuing import issue_daily_cards
from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.core.batch_auth import verify_batch_caller
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.matching.repository import MatchingRepository
from app.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/batch/daily-cards")
async def run_daily_cards(
    x_batch_secret: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> dict:
    """Cloud Scheduler 전용. Cloud Run 이 --allow-unauthenticated 라 이 엔드포인트는 스스로를 지킨다
    (조각 1a 의 auth hook 이 서명으로 자기를 지키는 것과 같은 이유)."""
    method = await verify_batch_caller(
        authorization=authorization, x_batch_secret=x_batch_secret,
        batch_secret=settings.card_batch_secret, audience=settings.batch_audience,
        service_account_email=settings.batch_service_account,
    )
    # 운영에 로깅 설정이 없어 INFO 는 안 보인다. 전환 확인용이고 5단계 PR 에서 이 줄째 지운다.
    logger.warning("batch %s auth=%s", "/batch/daily-cards", method)

    card_repo = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    matching_repo = MatchingRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    sender = FcmSender(settings.google_cloud_project, client)
    return await issue_daily_cards(card_repo, matching_repo, sender, now=datetime.now(SEOUL))
