"""하트 구매(구글 플레이 인앱결제)와 상점 상태. 계획서 바탕화면 출시준비/인앱결제_구현계획_초안.md 3-3 · 5-1.
아이폰(애플) 확인 · 환불 알림은 apple_router.py.

경로 이름에 refund · purchase · buy 등을 쓰지 않는다 — E2E 하네스 E-HEART-49 · 51(e2e/area4_extra.py)이
그런 이름의 경로를 유료 카드 하나만 허용한다.
"""
import logging
from datetime import datetime, timezone
from typing import Literal

import httpx
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.billing import play
from app.billing.apple import apple_account_token
from app.billing.play import PlayApi, PlayUnavailable, account_token, token_hash
from app.billing.repository import BillingRepository
from app.core import errors
from app.core.deps import Caller, get_client, get_verified_caller

router = APIRouter()
logger = logging.getLogger(__name__)

# 화면에 보여 줄 값만(첫 구매 보너스, 2026-10-13 사용자 확정). 실제 지급은 DB 함수 grant_store_purchase 의 상수다 —
# 유료 카드 가격과 같은 방식. 바꿀 때 둘을 같이 바꾼다.
FIRST_PURCHASE_BONUS = 50
BONUS_MIN_PRODUCT_HEARTS = 100
# 두 스토어에 같은 이름으로 등록한 상품 5종(지급량 · 가격은 DB 함수 grant_store_purchase).
ProductId = Literal["heart_50", "heart_100", "heart_200", "heart_400", "heart_800"]


class GoogleVerifyRequest(BaseModel):
    product_id: ProductId
    # 구글 주소에 그대로 들어간다 — 영문 · 숫자 · . _ - 만 받는다(/ · 공백 금지, 첫 글자는 영문 · 숫자).
    purchase_token: str = Field(min_length=1, max_length=1000, pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def play_api_dependency(client: httpx.AsyncClient = Depends(get_client)) -> PlayApi:
    """테스트는 이 의존성을 덮어 고정 토큰 · 가짜 구글을 끼운다."""
    return PlayApi(client)


def _repo(caller: Caller) -> BillingRepository:
    return BillingRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _error(status_code: int, detail: str, code: str) -> JSONResponse:
    # 유료 카드 구매 오류와 같은 모양 — 앱은 code 로 가른다(ServerRejectedFailure.hasCode).
    return JSONResponse(status_code=status_code, content={"detail": detail, "code": code})


@router.get("/billing/status")
async def billing_status(caller: Caller = Depends(get_verified_caller)) -> dict:
    """상점(15e)이 열릴 때. 구매 창에 실을 계정 표시(구글 · 애플)와 첫 구매 자격. 자격 판정은 지급 때 DB 가 다시 한다."""
    bought = await _repo(caller).has_purchase(caller.profile_id)
    bonus = None if bought else {"hearts": FIRST_PURCHASE_BONUS, "min_product_hearts": BONUS_MIN_PRODUCT_HEARTS}
    return {"account_token": account_token(caller.profile_id),
            "apple_account_token": apple_account_token(caller.profile_id), "first_purchase_bonus": bonus}


@router.post("/billing/google/verify", response_model=None)
async def verify_google_purchase(
    body: GoogleVerifyRequest,
    caller: Caller = Depends(get_verified_caller),
    play_api: PlayApi = Depends(play_api_dependency),
) -> dict | JSONResponse:
    """앱이 받은 구글 구매를 확인하고 하트를 준다(설계 §7.6). 같은 토큰을 몇 번 보내도 하트는 한 번이다.

    구매 토큰 · 주문 번호는 로그에 남기지 않는다 — profile_id · 상품 · 결과 · 상태 코드만."""
    try:
        purchase = await play_api.get_purchase(body.product_id, body.purchase_token)
    except PlayUnavailable as exc:
        logger.warning("구글 구매 조회 실패 profile=%s product=%s status=%s",
                       caller.profile_id, body.product_id, exc.args[0] if exc.args else "transport")
        return _error(503, errors.BILLING_UNAVAILABLE, errors.CODE_BILLING_UNAVAILABLE)
    state = purchase.get("purchaseState") if purchase else None
    if state == play.PENDING:
        return JSONResponse(status_code=202, content={"result": "pending"})
    # 구글이 상품을 알려 주면 주소의 상품과 같아야 한다 — 지급량은 body 의 상품으로 정해서다.
    if (state != play.PURCHASED or purchase.get("quantity", 1) != 1
            or purchase.get("productId", body.product_id) != body.product_id):
        logger.warning("확인되지 않는 구매 profile=%s product=%s state=%s", caller.profile_id, body.product_id, state)
        return _error(422, errors.PURCHASE_INVALID, errors.CODE_PURCHASE_INVALID)
    if purchase.get("obfuscatedExternalAccountId") != account_token(caller.profile_id):
        # 소비하지 않는다 — 원래 계정으로 로그인하면 이어서 받고, 3일 안에 안 오면 구글이 돈을 돌려준다.
        logger.warning("다른 계정의 구매 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(409, errors.PURCHASE_OTHER_ACCOUNT, errors.CODE_PURCHASE_OTHER_ACCOUNT)

    purchased_at = datetime.fromtimestamp(int(purchase["purchaseTimeMillis"]) / 1000, tz=timezone.utc)
    outcome = await _repo(caller).grant_store_purchase(
        caller.profile_id, body.product_id, token_hash(body.purchase_token), purchase.get("orderId"),
        purchased_at, is_test=purchase.get("purchaseType") == play.TEST_PURCHASE,
    )
    result = outcome.get("result")
    if result == "token_used":
        logger.warning("다른 계정이 이미 받은 구매 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(409, errors.PURCHASE_TOKEN_USED, errors.CODE_PURCHASE_TOKEN_USED)
    if result not in ("granted", "already_granted"):
        # 지급 여부를 모르면 소비하지 않는다(반쪽 성공 금지). 앱은 500 을 받고 구매를 끝내지 않는다.
        raise RuntimeError(f"grant_store_purchase 가 계약 밖의 결과를 돌려줬다: {result!r}")

    if purchase.get("consumptionState") == play.NOT_CONSUMED:
        if not await play_api.consume(body.product_id, body.purchase_token):
            logger.warning("구글 소비 실패 — 앱이 다시 보내면 다시 소비 profile=%s product=%s",
                           caller.profile_id, body.product_id)
    return {key: outcome[key] for key in ("result", "hearts", "bonus_hearts", "heart_balance")}
