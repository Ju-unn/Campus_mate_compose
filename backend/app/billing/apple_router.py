"""아이폰 하트 구매(애플 인앱결제). 계획서 바탕화면 출시준비/애플_인앱결제_구현계획_초안.md 3절 · 2026-10-14 사용자 결정.

POST /billing/apple/verify — 앱이 준 거래 번호로 서버가 애플에 직접 묻는다(앱이 준 값을 믿지 않는다). 응답 모양 · 코드는
구글(router.py)과 같다 — 앱이 같은 코드로 가른다. 애플은 소비(consume) 호출이 없다 — 지급이 끝나면 앱이 거래를 끝낸다(finish).
POST /billing/apple/notifications — 애플이 보내는 알림(V2). 로그인 없는 공개 주소라 **서명 체인 검증만이 믿는 근거**다.
경로 이름 규칙은 router.py 머리말과 같다(refund · purchase · buy 를 쓰지 않는다).
거래 번호 · JWS · 키 · 우리 JWT 는 로그에 남기지 않는다(거래 번호는 앞 6자까지만). 알림 로그에는 profile_id 도 없다.
"""
import logging
from datetime import datetime, timezone

import httpx
from cryptography import x509
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.billing import apple
from app.billing.apple import AppleApi, AppleJwsInvalid, AppleUnavailable, is_account_token, verify_jws
from app.billing.play import token_hash
from app.billing.repository import APP_STORE, BillingRepository
from app.billing.router import ProductId, _error, _repo
from app.core import errors
from app.core.deps import Caller, get_client, get_now, get_settings, get_verified_caller
from app.core.logs import show_info
from app.settings import Settings

router = APIRouter()
logger = logging.getLogger(__name__)
# 알림 처리 결과(INFO)가 Cloud Run 로그에 보이게 한다 — core/logs.py.
show_info(logger)

# 거래 environment → is_test. 그 밖(Xcode · LocalTesting)은 우리 서버로 올 일이 없는 값이라 거절한다.
_ENVIRONMENTS = {"Production": False, "Sandbox": True}
# 하트를 회수하는 알림. REVOKE 는 가족 공유 취소 — 소모품에는 없지만 오면 같게 회수한다.
_CLAW_BACK = ("REFUND", "REVOKE")


class AppleVerifyRequest(BaseModel):
    product_id: ProductId
    # 애플 주소에 그대로 들어간다 — 거래 번호는 숫자 문자열이라 숫자만 받는다.
    transaction_id: str = Field(min_length=1, max_length=64, pattern=r"^[0-9]+$")


class AppleNotification(BaseModel):
    # 애플이 정한 이름(responseBodyV2). 인증서 셋이 실려 수 KB 다.
    signedPayload: str = Field(min_length=1, max_length=100_000)


def apple_root_ca() -> x509.Certificate:
    """믿는 루트. 시험은 이 의존성을 덮어 가짜 루트를 끼운다(운영은 내장한 애플 Root CA G3)."""
    return apple.APPLE_ROOT_CA_G3


def apple_api_dependency(settings: Settings = Depends(get_settings),
                         client: httpx.AsyncClient = Depends(get_client)) -> AppleApi | None:
    """키 셋 중 하나라도 비면 None — 확인은 503(apple_not_configured)이고 서버는 그대로 뜬다."""
    keys = (settings.apple_iap_key_id, settings.apple_iap_issuer_id, settings.apple_iap_private_key)
    return AppleApi(client, *keys) if all(keys) else None


def _vouches(transaction: dict, body: AppleVerifyRequest) -> bool:
    """애플이 서명한 거래가 '이 요청의 상품을 결제한 소모품 한 개'인가. 환불 여부(있으면 422 purchase_revoked) ·
    계정(다르면 409)은 따로 본다."""
    return (transaction.get("environment") in _ENVIRONMENTS
            and transaction.get("transactionId") == body.transaction_id
            and transaction.get("bundleId") == apple.BUNDLE_ID
            # 지급량은 요청의 상품으로 정한다 — 애플의 상품과 같아야 한다.
            and transaction.get("productId") == body.product_id
            and transaction.get("type") == "Consumable"
            and transaction.get("inAppOwnershipType") == "PURCHASED"
            and transaction.get("quantity", 1) == 1
            and isinstance(transaction.get("purchaseDate"), int))


@router.post("/billing/apple/verify", response_model=None)
async def verify_apple_purchase(
    body: AppleVerifyRequest,
    caller: Caller = Depends(get_verified_caller),
    apple_api: AppleApi | None = Depends(apple_api_dependency),
    root: x509.Certificate = Depends(apple_root_ca),
    now: datetime = Depends(get_now),
) -> dict | JSONResponse:
    """앱이 받은 애플 거래를 애플에 확인하고 하트를 준다. 같은 거래를 몇 번 보내도 하트는 한 번이다."""
    if apple_api is None:
        logger.warning("애플 인앱 구입 키 미설정 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(503, errors.BILLING_UNAVAILABLE, errors.CODE_APPLE_NOT_CONFIGURED)
    try:
        signed = await apple_api.signed_transaction(body.transaction_id, now)
        transaction = None if signed is None else verify_jws(signed, now, root)
    except AppleUnavailable as exc:
        logger.warning("애플 거래 조회 실패 profile=%s product=%s status=%s",
                       caller.profile_id, body.product_id, exc.args[0] if exc.args else "-")
        return _error(503, errors.BILLING_UNAVAILABLE, errors.CODE_BILLING_UNAVAILABLE)
    except AppleJwsInvalid as exc:
        # 애플 주소에서 받은 답이 서명 검증을 못 넘었다 — 우리 쪽(루트 교체 · 검증 코드) 문제일 가능성이 커서
        # 거절(422)하지 않고 503 으로 둔다. 앱은 거래를 끝내지 않고 나중에 다시 보낸다.
        logger.error("애플 거래 서명 검증 실패 profile=%s product=%s reason=%s", caller.profile_id, body.product_id, exc)
        return _error(503, errors.BILLING_UNAVAILABLE, errors.CODE_BILLING_UNAVAILABLE)
    if transaction is None or not _vouches(transaction, body):
        logger.warning("확인되지 않는 애플 거래 profile=%s product=%s found=%s",
                       caller.profile_id, body.product_id, transaction is not None)
        return _error(422, errors.PURCHASE_INVALID, errors.CODE_PURCHASE_INVALID)
    if transaction.get("revocationDate") is not None:
        # 환불된 거래 — 누구에게도 줄 하트가 없어 계정 대조보다 먼저 본다. 앱은 이 code 에서만 거래를 끝낸다(하트 없음).
        logger.warning("환불된 애플 거래 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(422, errors.PURCHASE_REVOKED, errors.CODE_PURCHASE_REVOKED)
    if not is_account_token(transaction.get("appAccountToken"), caller.profile_id):
        logger.warning("다른 계정의 애플 거래 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(409, errors.PURCHASE_OTHER_ACCOUNT, errors.CODE_PURCHASE_OTHER_ACCOUNT)

    purchased_at = datetime.fromtimestamp(transaction["purchaseDate"] / 1000, tz=timezone.utc)
    # 거래 번호는 비밀이 아니다(우리 키 없이는 조회 못 한다) — 문의 · 환불 번복 수동 처리 때 찾게 주문 번호 칸에 둔다.
    outcome = await _repo(caller).grant_store_purchase(
        caller.profile_id, body.product_id, token_hash(body.transaction_id), body.transaction_id, purchased_at,
        is_test=_ENVIRONMENTS[transaction["environment"]], store=APP_STORE,
    )
    result = outcome.get("result")
    if result == "token_used":
        logger.warning("다른 계정이 이미 받은 애플 거래 profile=%s product=%s", caller.profile_id, body.product_id)
        return _error(409, errors.PURCHASE_TOKEN_USED, errors.CODE_PURCHASE_TOKEN_USED)
    if result not in ("granted", "already_granted"):
        # 지급 여부를 모르면 성공이라 하지 않는다 — 앱은 500 을 받고 거래를 끝내지 않는다(다음에 다시 보낸다).
        raise RuntimeError(f"grant_store_purchase 가 계약 밖의 결과를 돌려줬다: {result!r}")
    return {key: outcome[key] for key in ("result", "hearts", "bonus_hearts", "heart_balance")}


def _rejected(reason) -> JSONResponse:
    logger.warning("애플 알림 거절 reason=%s", reason)
    return JSONResponse(status_code=400, content={"detail": "invalid notification"})


@router.post("/billing/apple/notifications", response_model=None)
async def receive_apple_notification(
    body: AppleNotification,
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    root: x509.Certificate = Depends(apple_root_ca),
    now: datetime = Depends(get_now),
) -> dict | JSONResponse:
    """App Store Server Notifications V2. 애플은 200 이 아니면 다시 보낸다.

    서명이 틀리면 400(애플이 보낸 게 아니다 — 아무것도 바꾸지 않는다). 환불(REFUND · REVOKE)은 회수하고, 이미 회수했거나
    우리가 지급한 적 없는 거래도 200(멱등). TEST · 그 밖의 알림은 로그만 남기고 200. 환불 번복은 되돌리지 않는다(결정 A-6)."""
    try:
        payload = verify_jws(body.signedPayload, now, root)
    except AppleJwsInvalid as exc:
        return _rejected(f"payload_{exc}")
    kind = payload.get("notificationType")
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    environment = data.get("environment")
    if data.get("bundleId") != apple.BUNDLE_ID:
        return _rejected("bundle")
    if kind not in _CLAW_BACK:
        if kind == "REFUND_REVERSED":
            # ponytail: 환불 번복은 하트를 되돌리지 않는다(사용자 미결 A-6). 자주 생기면 DB 함수(restore_store_purchase)를 더한다.
            logger.warning("애플 알림 REFUND_REVERSED — 하트를 되돌리지 않음, 운영자가 App Store Connect 에서 확인 environment=%s",
                           environment)
        logger.info("애플 알림 type=%s subtype=%s environment=%s — 할 일 없음", kind, payload.get("subtype"), environment)
        return {"result": "ignored"}

    signed_transaction = data.get("signedTransactionInfo")
    try:
        transaction = verify_jws(signed_transaction if isinstance(signed_transaction, str) else "", now, root)
    except AppleJwsInvalid as exc:
        return _rejected(f"transaction_{exc}")
    transaction_id = transaction.get("transactionId")
    if (transaction.get("bundleId") != apple.BUNDLE_ID or transaction.get("environment") != environment
            or not isinstance(transaction_id, str) or not transaction_id):
        return _rejected("transaction_mismatch")

    repo = BillingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    outcome = await repo.refund_store_purchase(token_hash(transaction_id), store=APP_STORE)
    logger.info("애플 알림 type=%s tx=%s environment=%s result=%s", kind, transaction_id[:6], environment,
                outcome.get("result"))
    if outcome.get("shortfall"):
        # 환불 전에 이미 쓴 하트(결정 I-1: 남은 만큼만 회수). 누구인지는 DB(purchases.clawed_back_hearts)에서 본다.
        logger.warning("애플 환불 회수 부족 tx=%s shortfall=%s", transaction_id[:6], outcome["shortfall"])
    return {"result": outcome.get("result")}
