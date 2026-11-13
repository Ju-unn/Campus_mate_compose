"""구글 환불 회수 — 매시 배치(결정 I-7: Voided Purchases 조회)와 실시간 알림(RTDN, 2026-11-14 사용자 결정).

알림이 몇 초 안에 회수하고, 배치는 알림을 놓쳤을 때의 안전망으로 그대로 돈다. 둘 다 같은 문(Cloud Scheduler 와 같은
서비스 계정 · audience 의 ID 토큰)으로 들어온다. 경로 이름에 refund 를 쓰지 않는다 — router.py 머리말.
"""
import base64
import json
import logging
from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request

from app.billing.play import PACKAGE_NAME, PlayApi, PlayUnavailable, token_hash
from app.billing.repository import BillingRepository
from app.billing.router import play_api_dependency
from app.core.batch_auth import verify_oidc_token
from app.core.deps import get_client, get_now, get_settings
from app.core.logs import show_info
from app.core.time import SEOUL
from app.settings import Settings

router = APIRouter()
logger = logging.getLogger(__name__)
# 회수 요약 · 항목(INFO)이 Cloud Run 로그에 보이게 한다 — core/logs.py.
show_info(logger)
# 진단 로그에 한 줄씩 남기는 항목 수. 요약 줄은 전부를 센다.
_LOGGED_ITEMS = 10

# 매시 돈다. 배치가 며칠 실패해도 놓치지 않게 7일을 본다 — 처리가 멱등이라 겹쳐도 된다(구글은 최근 30일까지 준다).
VOIDED_LOOKBACK = timedelta(days=7)
# 결제 기록 보관 5년(ERD §11-14, 결정 I-2 — 법률 확인 뒤 기간만 바꾼다). 바꾸면 이 줄만.
# 윤일 보정 +2일 — 5년 안에 윤일이 최대 2번 끼어 365×5 로는 5년이 다 차기 전에 지운다.
PURCHASE_RETENTION = timedelta(days=5 * 365 + 2)


def _seoul_time(millis) -> str:
    """구글 밀리초 문자열 → 한국 시각. 없거나 이상하면 '-' — 진단 로그 때문에 배치가 멈추지 않게."""
    try:
        return datetime.fromtimestamp(int(millis) / 1000, tz=SEOUL).isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return "-"


def _warn_shortfall(outcome: dict) -> None:
    if outcome.get("shortfall"):
        # 환불 전에 이미 쓴 하트(결정 I-1: 남은 만큼만 회수). 반복되면 운영자가 약관 제6조로 판단한다. 번호와 숫자만 남긴다.
        # ponytail: 경고 로그만. 환불이 실제로 생기기 시작하면 신고 채널(discord_report_webhook_url)에 붙인다.
        logger.warning("환불 회수 부족 profile=%s shortfall=%s", outcome.get("profile_id"), outcome["shortfall"])


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
    start = now - VOIDED_LOOKBACK
    try:
        voided = await play_api.voided_since(int(start.timestamp() * 1000))
    except PlayUnavailable as exc:
        logger.warning("구글 무효 구매 조회 실패 status=%s", exc.args[0] if exc.args else "transport")
        raise HTTPException(status_code=503) from None
    repo = BillingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    counts = {"refunded": 0, "already_refunded": 0, "unknown": 0}
    for index, item in enumerate(voided):
        outcome = await repo.refund_store_purchase(token_hash(item["purchaseToken"]))
        counts[outcome["result"]] += 1
        if index < _LOGGED_ITEMS:
            # 토큰 · 토큰 해시 · profile_id 는 남기지 않는다. 주문 번호는 콘솔 주문과 맞춰 볼 만큼 앞 12자만.
            # voidedSource 0 사용자 · 1 개발자 · 2 구글 / voidedReason 은 구글 VoidedPurchase 문서의 번호.
            logger.info("환불 회수 항목 orderId=%s voidedTime=%s purchaseTime=%s voidedSource=%s voidedReason=%s "
                        "result=%s", str(item.get("orderId") or "-")[:12], _seoul_time(item.get("voidedTimeMillis")),
                        _seoul_time(item.get("purchaseTimeMillis")), item.get("voidedSource"),
                        item.get("voidedReason"), outcome["result"])
        _warn_shortfall(outcome)
    # matched = DB 에 그 영수증이 있었다(회수 · 이미 회수). skipped = 할 일이 없었다(이미 회수 · DB 에 없음).
    logger.info("환불 회수 배치 voided=%d matched=%d refunded=%d skipped=%d startTime=%s", len(voided),
                counts["refunded"] + counts["already_refunded"], counts["refunded"],
                counts["already_refunded"] + counts["unknown"], start.isoformat())
    return {"voided": len(voided), **counts, "purged": await repo.purge(now - PURCHASE_RETENTION)}


# voidedPurchaseNotification 값(구글 RTDN 문서): productType 1 정기 결제 · 2 일회성, refundType 1 전액 · 2 수량 일부.
_ONE_TIME_PRODUCT, _FULL_REFUND = 2, 1
_IGNORED = {"result": "ignored"}


def _developer_notification(raw: bytes) -> dict | None:
    """Pub/Sub push 봉투 {"message": {"data": <base64 JSON>}} → 구글 알림(DeveloperNotification). 풀 수 없으면 None."""
    try:
        notification = json.loads(base64.b64decode(json.loads(raw)["message"]["data"], validate=True))
    # binascii.Error · UnicodeDecodeError 도 ValueError 다. RecursionError = 깊게 중첩된 JSON(봉투 · data 둘 다).
    except (ValueError, KeyError, TypeError, RecursionError):
        return None
    return notification if isinstance(notification, dict) else None


@router.post("/billing/play/notifications")
async def receive_play_notification(
    request: Request,
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> dict:
    """구글 플레이 실시간 알림(Pub/Sub push). 일회성 상품의 전액 무효 알림이면 그 구매의 하트를 바로 회수한다.

    Pub/Sub 은 2xx 가 아니면 다시 보낸다. 풀 수 없는 봉투 · 다른 앱 · 할 일 없는 알림은 다시 받아도 같아서 로그만 남기고 200.
    DB 실패는 5xx 로 둔다(다시 보내 주는 게 맞다 — 회수 함수가 멱등이라 중복 배달은 already_refunded 로 끝난다)."""
    await verify_oidc_token(authorization, audience=settings.batch_audience,
                            service_account_email=settings.batch_service_account)
    notification = _developer_notification(await request.body())
    if notification is None:
        logger.warning("구글 알림 봉투를 풀 수 없음 — 할 일 없음")
        return _IGNORED
    if notification.get("packageName") != PACKAGE_NAME:
        logger.warning("다른 앱의 구글 알림 packageName=%s — 할 일 없음", str(notification.get("packageName"))[:100])
        return _IGNORED
    voided = notification.get("voidedPurchaseNotification")
    if not isinstance(voided, dict):
        kinds = sorted(key for key in notification if key.endswith("Notification"))
        logger.info("구글 알림 kinds=%s — 할 일 없음", kinds)
        return _IGNORED
    # 토큰 · 토큰 해시는 남기지 않는다. 주문 번호는 배치처럼 앞 12자만.
    order, token = str(voided.get("orderId") or "-")[:12], voided.get("purchaseToken")
    product_type, refund_type = voided.get("productType"), voided.get("refundType")
    # ASCII 만 — 짝 없는 서로게이트는 token_hash 의 .encode() 에서 500 이 된다(구글 토큰은 영문 · 숫자 · . _ -).
    usable_token = isinstance(token, str) and bool(token) and token.isascii()
    if product_type != _ONE_TIME_PRODUCT or refund_type != _FULL_REFUND or not usable_token:
        # 우리 상품은 수량 1 의 일회성뿐이라 오지 않을 알림이다. 회수하지 않고 운영자가 플레이 콘솔에서 본다.
        # %r — "2" 와 2 를 가른다. 토큰은 원문 없이 "비어 있지 않은 문자열인가" 만.
        logger.warning("구글 무효 알림 회수 안 함 orderId=%s productType=%r refundType=%r token=%s", order,
                       product_type, refund_type, isinstance(token, str) and bool(token))
        return _IGNORED

    repo = BillingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    outcome = await repo.refund_store_purchase(token_hash(token))
    logger.info("구글 무효 알림 orderId=%s productType=%s refundType=%s result=%s", order, product_type, refund_type,
                outcome.get("result"))
    _warn_shortfall(outcome)
    return {"result": outcome.get("result")}
