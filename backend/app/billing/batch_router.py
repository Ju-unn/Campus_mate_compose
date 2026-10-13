"""환불 회수 배치(결정 I-7: 매시 Voided Purchases 조회). 경로 이름에 refund 를 쓰지 않는다 — router.py 머리말."""
import logging
from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

from app.billing.play import PlayApi, PlayUnavailable, token_hash
from app.billing.repository import BillingRepository
from app.billing.router import play_api_dependency
from app.core.batch_auth import verify_oidc_token
from app.core.deps import get_client, get_now, get_settings
from app.settings import Settings

router = APIRouter()
logger = logging.getLogger(__name__)

# 매시 돈다. 배치가 며칠 실패해도 놓치지 않게 7일을 본다 — 처리가 멱등이라 겹쳐도 된다(구글은 최근 30일까지 준다).
VOIDED_LOOKBACK = timedelta(days=7)
# 결제 기록 보관 5년(ERD §11-14, 결정 I-2 — 법률 확인 뒤 기간만 바꾼다). 바꾸면 이 줄만.
# 윤일 보정 +2일 — 5년 안에 윤일이 최대 2번 끼어 365×5 로는 5년이 다 차기 전에 지운다.
PURCHASE_RETENTION = timedelta(days=5 * 365 + 2)


@router.post("/batch/billing-voided")
async def run_billing_voided(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    now: datetime = Depends(get_now),
    play_api: PlayApi = Depends(play_api_dependency),
) -> dict:
    """Cloud Scheduler 전용(카드 · 채팅 · 정리 배치와 같은 문). 구글이 무효로 바꾼 구매의 하트를 회수한다.

    구글이 답하지 못하면 503 이고 아무것도 바꾸지 않는다 — 다음 시각에 같은 7일을 다시 본다."""
    await verify_oidc_token(authorization, audience=settings.batch_audience,
                            service_account_email=settings.batch_service_account)
    try:
        voided = await play_api.voided_since(int((now - VOIDED_LOOKBACK).timestamp() * 1000))
    except PlayUnavailable as exc:
        logger.warning("구글 무효 구매 조회 실패 status=%s", exc.args[0] if exc.args else "transport")
        raise HTTPException(status_code=503) from None
    repo = BillingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    counts = {"refunded": 0, "already_refunded": 0, "unknown": 0}
    for item in voided:
        outcome = await repo.refund_store_purchase(token_hash(item["purchaseToken"]))
        counts[outcome["result"]] += 1
        if outcome.get("shortfall"):
            # 환불 전에 이미 쓴 하트(결정 I-1: 남은 만큼만 회수). 반복되면 운영자가 약관 제6조로 판단한다. 번호와 숫자만 남긴다.
            # ponytail: 경고 로그만. 환불이 실제로 생기기 시작하면 신고 채널(discord_report_webhook_url)에 붙인다.
            logger.warning("환불 회수 부족 profile=%s shortfall=%s", outcome.get("profile_id"), outcome["shortfall"])
    return {"voided": len(voided), **counts, "purged": await repo.purge(now - PURCHASE_RETENTION)}
