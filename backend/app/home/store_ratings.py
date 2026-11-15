"""홈 리뷰 띠의 실제 스토어 별점(2026-11-16 사용자 결정 — 실제 스토어 값만, 손으로 넣는 숫자 없음, 못 읽으면 0명 상태).

- 아이폰: 애플 공개 조회(`itunes.apple.com/lookup`)의 `averageUserRating` · `userRatingCount`. 인증 없음.
- 안드로이드: 플레이 콘솔이 Cloud Storage 에 쌓는 별점 보고서 CSV(UTF-16)의 마지막 빈 칸 아닌 `Total Average Rating`.
  보고서에 평가 수 열이 없어 count 는 None 이다(앱이 "(N명 평가)" 를 숨긴다). 버킷은 env `PLAY_REPORTS_BUCKET`, 비면 0명 상태.
  인증은 서버 ADC(billing/play.py 와 같은 길) + `devstorage.read_only`. 새 의존성 없이 httpx 로 JSON API 를 부른다.

값은 프로세스 안에 캐시한다(성공 몇 시간 · 실패는 잠깐) — 홈 요약마다 밖으로 나가지 않게. 바깥 호출은 짧은 시간 제한 안에서만 한다.
"""
import asyncio
import csv
import gzip
import io
import logging
import time
from collections.abc import Awaitable, Callable
from datetime import date
from urllib.parse import quote

import google.auth
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest
from pydantic_settings import BaseSettings

from app.billing.play import PACKAGE_NAME

logger = logging.getLogger(__name__)

# 못 읽었을 때 · 평가가 없을 때. 앱은 count 0 이면 "CampusMate 가 마음에 드셨나요?" 상태다.
EMPTY = {"rating": 0.0, "count": 0}

APPLE_APP_ID = "6821955396"  # frontend/lib/core/app_update/store_listing.dart 와 같은 앱 번호
_APPLE_LOOKUP = "https://itunes.apple.com/lookup"
_GCS_OBJECT = "https://storage.googleapis.com/storage/v1/b/{bucket}/o/{name}"
_GCS_SCOPE = "https://www.googleapis.com/auth/devstorage.read_only"
# 머리 글자는 strip().lower() 로 견준다 — 보고서마다 대소문자 · 앞뒤 공백이 다를 수 있다.
_RATING_COLUMN = "total average rating"

# 성공은 몇 시간 둔다 — 스토어 별점은 하루에 한 번 남짓 바뀐다. 실패는 잠깐만 기억해 다음 요청 몇 개가 또 기다리지 않게 한다.
SUCCESS_TTL_SECONDS = 3 * 60 * 60
FAILURE_TTL_SECONDS = 10 * 60
# 홈 요약을 늦추지 않는 시간 제한(호출 하나 · 전체).
_CALL_TIMEOUT_SECONDS = 2.0
_TOTAL_TIMEOUT_SECONDS = 3.0


class StoreRatingSettings(BaseSettings):
    """공용 Settings(app/settings.py)와 따로 둔다 — 이 값 하나만 읽는다(AdminWebSettings 와 같은 모양)."""

    # 플레이 콘솔 보고서 버킷 이름(`pubsite_prod_…`, 값은 문서에 적지 않는다). 비면 안드로이드는 0명 상태.
    play_reports_bucket: str = ""


_credentials = None


async def _adc_access_token() -> str:
    """Cloud Storage 읽기 전용 토큰. 프로세스에 자격 하나(billing/play.py `_adc_access_token` 과 같은 길, 범위만 다르다)."""
    global _credentials
    if _credentials is None:
        _credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_GCS_SCOPE])
    if not _credentials.valid:
        await asyncio.to_thread(_credentials.refresh, GoogleAuthRequest())
    return _credentials.token


def _months(today: date) -> list[str]:
    """이번 달 · 지난달 보고서 이름의 yyyyMM. 이번 달 파일은 달이 바뀐 직후 아직 없을 수 있다."""
    last = date(today.year - 1, 12, 1) if today.month == 1 else date(today.year, today.month - 1, 1)
    return [today.strftime("%Y%m"), last.strftime("%Y%m")]


class _NoRatingColumn(Exception):
    """보고서는 받았는데 Total Average Rating 열이 없다. args[0] = 머리 이름 목록(경로 · 버킷은 싣지 않는다)."""


def _number(value: str) -> float | None:
    try:
        return float(value)
    except ValueError:
        return None  # "NA" 같은 빈 표시


def _last_total_rating(data: bytes) -> float | None:
    """보고서의 마지막 숫자로 읽히는 Total Average Rating. 플레이 보고서는 UTF-16(BOM)이다 — BOM 이 없으면 UTF-8 로 읽는다.
    Cloud Storage 가 gzip 그대로(Content-Encoding 없이) 줄 수 있어 몸통이 gzip 이면 먼저 푼다."""
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    text = data.decode("utf-16") if data[:2] in (b"\xff\xfe", b"\xfe\xff") else data.decode("utf-8-sig")
    reader = csv.reader(io.StringIO(text))
    header = [name.strip().lower() for name in next(reader, [])]
    if _RATING_COLUMN not in header:
        raise _NoRatingColumn(header)
    column = header.index(_RATING_COLUMN)
    numbers = [_number(row[column].strip()) for row in reader if len(row) > column]
    ratings = [n for n in numbers if n is not None]
    if not ratings:
        return None
    return ratings[-1] if 1 <= ratings[-1] <= 5 else None


class StoreRatings:
    """두 스토어 값을 캐시해 내준다. 시험이 토큰 · 날짜 · 시계를 바꿔 끼운다."""

    def __init__(self, access_token: Callable[[], Awaitable[str]] = _adc_access_token,
                 today: Callable[[], date] = date.today, monotonic: Callable[[], float] = time.monotonic):
        self._access_token = access_token
        self._today = today
        self._monotonic = monotonic
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = asyncio.Lock()

    async def get(self, client: httpx.AsyncClient, bucket: str) -> dict:
        async with self._lock:  # 동시에 들어온 요청이 같은 값을 여러 번 받으러 나가지 않게
            # 두 스토어를 함께 받는다 — 최악도 한 쪽 시간 제한(3초)만큼만 기다린다.
            ios, android = await asyncio.gather(
                self._cached("ios", lambda: self._ios(client)),
                self._cached("android", lambda: self._android(client, bucket)),
            )
        return {"ios": ios, "android": android}

    async def _cached(self, store: str, fetch: Callable[[], Awaitable[dict | None]]) -> dict:
        now = self._monotonic()
        hit = self._cache.get(store)
        if hit is not None and hit[0] > now:
            return hit[1]
        try:
            value = await asyncio.wait_for(fetch(), _TOTAL_TIMEOUT_SECONDS)
        except Exception as exc:  # 바깥 · 인증 · 형식 어느 실패든 홈은 그려야 한다
            logger.warning("스토어 별점 읽기 실패 store=%s error=%s", store, type(exc).__name__)
            value = None
        ttl = FAILURE_TTL_SECONDS if value is None else SUCCESS_TTL_SECONDS
        result = value or EMPTY
        self._cache[store] = (now + ttl, result)
        return result

    async def _ios(self, client: httpx.AsyncClient) -> dict | None:
        response = await client.get(_APPLE_LOOKUP, params={"id": APPLE_APP_ID, "country": "kr"},
                                    timeout=_CALL_TIMEOUT_SECONDS)
        response.raise_for_status()
        results = response.json().get("results") or []
        if not results or "userRatingCount" not in results[0]:
            return None  # 평가가 아직 없는 앱은 칸이 없다
        count = int(results[0]["userRatingCount"])
        rating = float(results[0].get("averageUserRating", 0))
        if count <= 0 or not 1 <= rating <= 5:
            return None
        return {"rating": rating, "count": count}

    async def _android(self, client: httpx.AsyncClient, bucket: str) -> dict | None:
        if not bucket:
            return None
        token = await self._access_token()
        for month in _months(self._today()):
            name = quote(f"stats/ratings/ratings_{PACKAGE_NAME}_{month}_overview.csv", safe="")
            response = await client.get(_GCS_OBJECT.format(bucket=bucket, name=name), params={"alt": "media"},
                                        headers={"Authorization": f"Bearer {token}"}, timeout=_CALL_TIMEOUT_SECONDS)
            if response.status_code == 404:
                continue  # 이번 달 파일이 아직 없다 — 지난달
            response.raise_for_status()
            try:
                rating = _last_total_rating(response.content)
            except _NoRatingColumn as missing:
                # 열 이름이 바뀐 보고서 — 지난달도 같은 모양이라 더 보지 않는다. 버킷 · 경로는 남기지 않는다.
                logger.warning("스토어 별점 보고서에 평점 열이 없음 store=android 열=%s", missing.args[0])
                return None
            if rating is not None:
                return {"rating": rating, "count": None}
            # 달 초에는 이번 달 칸이 아직 비어 있을 수 있다 — 지난달 값을 본다.
        return None
