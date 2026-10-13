"""구글 플레이 개발자 API — 구매 조회 · 소비 · 무효(환불) 목록(인앱결제 계획서 3-1).

자격증명은 Cloud Run 서비스 계정(ADC)이다. 토큰 받는 방식은 cards/push.py FcmSender 와 같다 — 새 패키지 없음
(google-api-python-client 를 넣지 않고 REST 를 httpx 로 직접 부른다. Cloud Tasks 와 같은 이유).
**구매 토큰은 요청 주소에 들어간다.** 이 모듈과 부르는 쪽은 주소 · 예외 문구를 로그에 남기지 않는다.
401/403 때만 구글 본문의 원인(code · status · reason · message)을 토큰을 지운 채 한 줄 남긴다.
"""
import asyncio
import hashlib
import json
import logging
from collections.abc import Awaitable, Callable

import google.auth
import google.auth.exceptions
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

from app.core.logs import show_info

logger = logging.getLogger(__name__)
# 무효 목록 응답 모양(INFO)이 Cloud Run 로그에 보이게 한다 — core/logs.py.
show_info(logger)
# httpx 는 INFO 에서 요청 주소를 찍는다 — 주소에 구매 토큰이 있다. 지금 루트 수준(WARNING)에서도 안 찍히지만,
# 누가 INFO 를 켜도 새지 않게 못박는다.
logging.getLogger("httpx").setLevel(logging.WARNING)

_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
# frontend/android/app/build.gradle.kts applicationId. 바뀌지 않는 값이라 설정으로 만들지 않는다.
PACKAGE_NAME = "io.github.juunn.campusmate"
_PURCHASES = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE_NAME}/purchases"
_TIMEOUT_SECONDS = 10.0
# purchases.products 값(구글 문서): purchaseState 0 결제됨 · 1 취소 · 2 대기, consumptionState 0 미소비,
# purchaseType 0 = 라이선스 테스터(시험 결제).
PURCHASED, CANCELED, PENDING = 0, 1, 2
NOT_CONSUMED = 0
TEST_PURCHASE = 0

_credentials = None


class PlayUnavailable(Exception):
    """구글이 지금 답하지 못한다(5xx · 429 · 시간 초과 · 401/403 = 우리 권한 설정). 부르는 쪽은 503 — 앱이 다시 보낸다."""


def account_token(profile_id) -> str:
    """구매 창에 싣는 계정 표시(obfuscatedAccountId, 64자). profile_id 를 그대로 구글에 보내지 않는다(유료약관 3-2)."""
    return hashlib.sha256(f"campusmate-play:{profile_id}".encode()).hexdigest()


def token_hash(purchase_token: str) -> str:
    """DB 에는 토큰 대신 이것만 둔다 — 토큰은 서비스 계정과 함께면 그 구매를 조회 · 소비할 수 있는 값이다."""
    return hashlib.sha256(purchase_token.encode()).hexdigest()


def _google_error(text: str, secrets: tuple = ()) -> str:
    """구글 오류 본문 → 원인 한 줄. 본문이 주소나 토큰을 되울릴 수 있어 secrets 를 먼저 <token> 으로 지운다."""
    for secret in secrets:
        if secret:
            text = text.replace(secret, "<token>")
    try:
        error = json.loads(text).get("error")
    except (ValueError, AttributeError):
        error = None
    if not isinstance(error, dict):
        return f"body={text[:100]!r}"
    # 플레이 API 는 errors[].reason, IAM 같은 새 API 는 details[].reason 에 둔다.
    items = error.get("errors") or error.get("details")
    first = items[0] if isinstance(items, list) and items and isinstance(items[0], dict) else {}
    return (f"code={error.get('code')} error_status={error.get('status')} reason={first.get('reason')} "
            f"message={str(error.get('message', ''))[:200]!r}")


async def _adc_access_token() -> str:
    """프로세스에 자격증명 하나. 요청마다 ADC 를 다시 읽지 않는다(메타데이터 서버를 매번 부르지 않게).

    만들기나 refresh 가 실패하면 원인을 남기고 다시 던진다 — _call 이 PlayUnavailable 로 바꾼다."""
    global _credentials
    try:
        if _credentials is None:
            _credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
        if not _credentials.valid:
            # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다(FcmSender 와 같다).
            await asyncio.to_thread(_credentials.refresh, GoogleAuthRequest())
    except google.auth.exceptions.GoogleAuthError as exc:
        # RefreshError 는 마지막 인자에 원인(응답 본문 · 하위 예외)을 싣는다.
        detail = exc.args[-1] if exc.args else ""
        logger.warning("구글 플레이 자격 만들기 실패 error=%s %s", type(exc).__name__, _google_error(str(detail)))
        raise
    return _credentials.token


class PlayApi:
    def __init__(self, client: httpx.AsyncClient,
                 access_token: Callable[[], Awaitable[str]] = _adc_access_token):
        self._client = client
        self._access_token = access_token

    async def _call(self, method: str, url: str, params: dict | None = None,
                    purchase_token: str | None = None) -> httpx.Response:
        try:
            access_token = await self._access_token()
            response = await self._client.request(
                method, url, params=params, timeout=_TIMEOUT_SECONDS,
                headers={"Authorization": f"Bearer {access_token}"},
            )
        except (httpx.TransportError, google.auth.exceptions.GoogleAuthError):
            # from None — 원래 예외 문구에는 토큰이 든 주소가 있다. 트레이스백에 딸려 가지 않게 끊는다.
            raise PlayUnavailable() from None
        if response.status_code in (401, 403):
            # 우리 쪽 권한 문제다(플레이 콘솔 권한 · 토큰 범위 · 인증). 원인은 구글 본문에만 있다.
            logger.warning("구글 플레이 API 거절 status=%s %s", response.status_code,
                           _google_error(response.text, (purchase_token, access_token)))
        if response.status_code >= 500 or response.status_code in (401, 403, 429):
            raise PlayUnavailable(response.status_code)
        return response

    async def get_purchase(self, product_id: str, purchase_token: str) -> dict | None:
        """구글이 모르는 토큰 · 다른 상품 · 다른 앱의 토큰이면 None(400 · 404 · 410)."""
        response = await self._call("GET", f"{_PURCHASES}/products/{product_id}/tokens/{purchase_token}",
                                    purchase_token=purchase_token)
        return response.json() if response.is_success else None

    async def consume(self, product_id: str, purchase_token: str) -> bool:
        """소비(= 확인 처리 겸함, 구글 문서). 예외를 던지지 않는다 — 지급은 끝났고 앱이 다시 보내면 다시 한다."""
        try:
            response = await self._call("POST", f"{_PURCHASES}/products/{product_id}/tokens/{purchase_token}:consume",
                                        purchase_token=purchase_token)
        except PlayUnavailable:
            return False
        return response.is_success

    async def voided_since(self, start_millis: int) -> list[dict]:
        """그 시각 이후 무효(환불 · 차지백 · 3일 미확인 자동 환불)가 된 일회성 구매 전부. 쪽마다 최대 1000."""
        items: list[dict] = []
        page: str | None = None
        while True:
            params = {"startTime": str(start_millis), "type": "0"}
            if page:
                params["token"] = page
            response = await self._call("GET", f"{_PURCHASES}/voidedpurchases", params=params)
            if not response.is_success:
                raise PlayUnavailable(response.status_code)
            body = response.json()
            # 키 이름만 남긴다(값에는 구매 토큰이 있다). 항목 없이 쪽 정보만 오는 등 다른 모양의 답을 가려낸다.
            logger.info("구글 무효 목록 응답 keys=%s voidedPurchases=%d",
                        sorted(body), len(body.get("voidedPurchases", [])))
            items += body.get("voidedPurchases", [])
            page = (body.get("tokenPagination") or {}).get("nextPageToken")
            if not page:
                return items
