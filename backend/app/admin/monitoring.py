"""관리자 서버 상태(설계 2026-11-17-admin-server-status)의 구글 모니터링 읽기 · 5분 칸 합치기 · 이상 판정.

화면을 열 때만 읽는다(주기 호출 없음). 판정은 응답을 만들 때 계산하고 저장하지 않는다 — 기준을 바꿀 때는 아래 상수만 고친다.
"""
import asyncio
import logging
import math
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal

import httpx

from app.core.google_adc import AdcToken

logger = logging.getLogger(__name__)

# shortcut: 저장본은 모듈 전역이라 Cloud Run 인스턴스마다 따로 든다 — 인스턴스가 늘어 구글 읽기가 많아지면 공용 저장소로.
CACHE_SECONDS = 60
SERVICE = "campus-mate-backend"
WINDOW_MINUTES = 180
BUCKET_MINUTES = 5
# 칸마다 이상 기준(대장 판단): 5xx ≥ 3건 / 요청 ≥ 20건이고 5xx 비율 ≥ 5% / 요청 ≥ 20건이고 중앙값 ≥ 1초.
ERRORS_MIN = 3
RATE_MIN_REQUESTS = 20
ERROR_RATE = 0.05
SLOW_P50_MS = 1000
# "지금" 숫자는 마지막 3칸(15분) — 구글 숫자가 1~3분 늦어 마지막 칸만 보면 비어 보인다.
NOW_BUCKETS = 3

_SCOPE = "https://www.googleapis.com/auth/monitoring.read"
_TIMEOUT_SECONDS = 10.0
_FILTER = f'resource.type="cloud_run_revision" AND resource.labels.service_name="{SERVICE}"'
_BUCKET = timedelta(minutes=BUCKET_MINUTES)
_COUNT = WINDOW_MINUTES // BUCKET_MINUTES  # 36칸

_adc = AdcToken(_SCOPE)
_cache: tuple[datetime, list["Bucket"]] | None = None


@dataclass(frozen=True)
class Bucket:
    start: datetime
    requests: int
    errors_5xx: int
    p50_ms: int | None
    p95_ms: int | None
    instances: int | None


@dataclass(frozen=True)
class Anomaly:
    at: datetime
    kind: Literal["errors", "error_rate", "slow"]
    value: float


def find_anomalies(buckets: list[Bucket]) -> list[Anomaly]:
    """칸마다 기준을 넘은 것, 최신 순. 한 칸이 여러 기준을 넘으면 각각 한 줄."""
    found = []
    for bucket in reversed(buckets):
        if bucket.errors_5xx >= ERRORS_MIN:
            found.append(Anomaly(bucket.start, "errors", bucket.errors_5xx))
        if bucket.requests >= RATE_MIN_REQUESTS:
            rate = bucket.errors_5xx / bucket.requests
            if rate >= ERROR_RATE:
                found.append(Anomaly(bucket.start, "error_rate", rate))
            if bucket.p50_ms is not None and bucket.p50_ms >= SLOW_P50_MS:
                found.append(Anomaly(bucket.start, "slow", bucket.p50_ms))
    return found


def _latest(values: list[int | None]) -> int | None:
    return next((value for value in reversed(values) if value is not None), None)


def summarize_now(buckets: list[Bucket]) -> dict:
    last = buckets[-NOW_BUCKETS:]
    requests = sum(b.requests for b in last)
    errors = sum(b.errors_5xx for b in last)
    return {
        "requests_per_min": round(requests / (len(last) * BUCKET_MINUTES), 1) if last else 0.0,
        "error_rate": errors / requests if requests else 0,
        "p50_ms": _latest([b.p50_ms for b in last]),
        "p95_ms": _latest([b.p95_ms for b in last]),
        "instances": _latest([b.instances for b in last]),
    }


async def _monitoring_token() -> str:
    """프로세스에 자격증명 하나(core/google_adc.py). 실패는 GoogleAuthError 로 올린다 — 경로가 503 으로 바꾼다."""
    return await _adc()


def _rfc3339(at: datetime) -> str:
    return at.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


class MonitoringShapeError(Exception):
    """구글이 200 을 줬지만 답 모양이 다르다(JSON 아님 · 칸 없음). 경로는 "지금 못 읽음" 503 으로 본다 — 우리 코드 실수와 가르려고 따로 둔다."""


def _number(point: dict) -> float:
    value = point["value"]
    number = float(value["doubleValue"]) if "doubleValue" in value else float(value.get("int64Value", 0))
    if not math.isfinite(number):  # 구글 JSON 은 NaN · Infinity 를 글자로 줄 수 있다 — _points 가 MonitoringShapeError 로 바꾼다
        raise ValueError("not finite")
    return number


def _points(response: httpx.Response) -> list[tuple[str | None, datetime, float]]:
    """timeSeries 답 → (응답 코드 묶음, 점의 interval.endTime, 값). 구글 답을 읽는 곳은 여기뿐이다."""
    try:
        return [(series.get("metric", {}).get("labels", {}).get("response_code_class"),
                 datetime.fromisoformat(point["interval"]["endTime"]), _number(point))
                for series in response.json().get("timeSeries", []) for point in series.get("points", [])]
    except (AttributeError, KeyError, TypeError, ValueError) as exc:
        raise MonitoringShapeError(type(exc).__name__) from None


class MonitoringReader:
    def __init__(self, client: httpx.AsyncClient, project: str,
                 access_token: Callable[[], Awaitable[str]] = _monitoring_token):
        self._client = client
        self._project = project
        self._access_token = access_token

    async def _series(self, start: datetime, end: datetime, metric: str, aligner: str, reducer: str,
                      group_by: str | None = None) -> list[tuple[str | None, datetime, float]]:
        params = {
            "filter": f'{_FILTER} AND metric.type="run.googleapis.com/{metric}"',
            "interval.startTime": _rfc3339(start), "interval.endTime": _rfc3339(end),
            "aggregation.alignmentPeriod": f"{BUCKET_MINUTES * 60}s",
            "aggregation.perSeriesAligner": aligner, "aggregation.crossSeriesReducer": reducer,
        }
        if group_by:
            params["aggregation.groupByFields"] = group_by
        # shortcut: nextPageToken 을 따라가지 않는다 — 묶은 시계열 몇 개 × 36점이라 한 쪽에 다 온다, 쪽이 나뉘면 따라가기로.
        response = await self._client.get(
            f"https://monitoring.googleapis.com/v3/projects/{self._project}/timeSeries", params=params,
            headers={"Authorization": f"Bearer {await self._access_token()}"}, timeout=_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return _points(response)

    async def fetch_buckets(self, end: datetime) -> list[Bucket]:
        """end 를 5분 단위로 내린 시각까지 36칸, 오래된 순. 점이 없는 칸은 요청 0 · 나머지 None."""
        end = end.astimezone(UTC)
        end = end.replace(minute=end.minute - end.minute % BUCKET_MINUTES, second=0, microsecond=0)
        start = end - _COUNT * _BUCKET
        counts, p50, p95, instances = await asyncio.gather(
            self._series(start, end, "request_count", "ALIGN_DELTA", "REDUCE_SUM", "metric.labels.response_code_class"),
            self._series(start, end, "request_latencies", "ALIGN_DELTA", "REDUCE_PERCENTILE_50"),
            self._series(start, end, "request_latencies", "ALIGN_DELTA", "REDUCE_PERCENTILE_95"),
            self._series(start, end, "container/instance_count", "ALIGN_MAX", "REDUCE_SUM"),
        )
        slots = {start + i * _BUCKET: {"requests": 0, "errors_5xx": 0, "p50_ms": None, "p95_ms": None, "instances": None}
                 for i in range(_COUNT)}

        def in_window(points: list[tuple[str | None, datetime, float]]):
            # 점의 interval.endTime 을 칸 끝으로 본다. 창 밖 점은 버린다.
            for code_class, point_end, value in points:
                slot = slots.get(point_end - _BUCKET)
                if slot is not None:
                    yield code_class, slot, value

        for code_class, slot, value in in_window(counts):
            slot["requests"] += int(value)
            if code_class == "5xx":
                slot["errors_5xx"] += int(value)
        for key, points in (("p50_ms", p50), ("p95_ms", p95), ("instances", instances)):
            for _, slot, value in in_window(points):
                slot[key] = round(value)
        return [Bucket(at, **values) for at, values in slots.items()]


async def read_buckets(reader: MonitoringReader, now: datetime) -> tuple[datetime, list[Bucket]]:
    """CACHE_SECONDS 안이면 저장본을 준다. 실패는 저장하지 않는다(예외가 그대로 올라간다)."""
    global _cache
    if _cache is not None and now - _cache[0] < timedelta(seconds=CACHE_SECONDS):
        return _cache
    _cache = (now, await reader.fetch_buckets(now))
    return _cache
