"""구글 플레이 개발자 API — 구매 조회 · 소비 · 무효(환불) 목록(인앱결제 계획서 3-1).

자격증명은 Cloud Run 서비스 계정(ADC)이다. 토큰 받는 방식은 cards/push.py FcmSender 와 같다 — 새 패키지 없음
(google-api-python-client 를 넣지 않고 REST 를 httpx 로 직접 부른다. Cloud Tasks 와 같은 이유).
**구매 토큰은 요청 주소에 들어간다.** 이 모듈과 부르는 쪽은 주소 · 응답 본문 · 예외 문구를 로그에 남기지 않는다.
"""
import asyncio
import hashlib
import logging
from collections.abc import Awaitable, Callable

import google.auth
import google.auth.exceptions
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

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


async def _adc_access_token() -> str:
    """프로세스에 자격증명 하나. 요청마다 ADC 를 다시 읽지 않는다(메타데이터 서버를 매번 부르지 않게)."""
    global _credentials
    if _credentials is None:
        _credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
    if not _credentials.valid:
        # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다(FcmSender 와 같다).
        await asyncio.to_thread(_credentials.refresh, GoogleAuthRequest())
    return _credentials.token


class PlayApi:
    def __init__(self, client: httpx.AsyncClient,
                 access_token: Callable[[], Awaitable[str]] = _adc_access_token):
        self._client = client
        self._access_token = access_token

    async def _call(self, method: str, url: str, params: dict | None = None) -> httpx.Response:
        try:
            response = await self._client.request(
                method, url, params=params, timeout=_TIMEOUT_SECONDS,
                headers={"Authorization": f"Bearer {await self._access_token()}"},
            )
        except (httpx.TransportError, google.auth.exceptions.GoogleAuthError):
            # from None — 원래 예외 문구에는 토큰이 든 주소가 있다. 트레이스백에 딸려 가지 않게 끊는다.
            raise PlayUnavailable() from None
        if response.status_code >= 500 or response.status_code in (401, 403, 429):
            raise PlayUnavailable(response.status_code)
        return response

    async def get_purchase(self, product_id: str, purchase_token: str) -> dict | None:
        """구글이 모르는 토큰 · 다른 상품 · 다른 앱의 토큰이면 None(400 · 404 · 410)."""
        response = await self._call("GET", f"{_PURCHASES}/products/{product_id}/tokens/{purchase_token}")
        return response.json() if response.is_success else None

    async def consume(self, product_id: str, purchase_token: str) -> bool:
        """소비(= 확인 처리 겸함, 구글 문서). 예외를 던지지 않는다 — 지급은 끝났고 앱이 다시 보내면 다시 한다."""
        try:
            response = await self._call("POST", f"{_PURCHASES}/products/{product_id}/tokens/{purchase_token}:consume")
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
            items += body.get("voidedPurchases", [])
            page = (body.get("tokenPagination") or {}).get("nextPageToken")
            if not page:
                return items
