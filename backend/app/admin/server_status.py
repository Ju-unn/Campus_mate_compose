"""관리자 서버 상태 GET /admin/server-status(설계 2026-11-17-admin-server-status). 최근 3시간 5분 칸 · 지금 숫자 · 이상 목록.

구글이 답하지 못하면 503(AUTH_UNAVAILABLE). 로그에는 예외 이름과 구글 상태 코드만 남긴다 — 주소 · 토큰 · 구글 본문은 남기지 않는다.
"""
import logging
from datetime import datetime

import google.auth.exceptions
import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.monitoring import (
    BUCKET_MINUTES, MonitoringReader, MonitoringShapeError, find_anomalies, read_buckets, summarize_now,
)
from app.core import errors
from app.core.deps import get_now

logger = logging.getLogger(__name__)
router = APIRouter()


def get_monitoring_reader(caller: AdminCaller = Depends(get_admin_caller)) -> MonitoringReader:
    return MonitoringReader(caller.client, caller.settings.google_cloud_project)


@router.get("/server-status")
async def get_server_status(
    caller: AdminCaller = Depends(get_admin_caller),  # 시험이 reader 를 바꿔 끼워도 관문은 남게 경로가 직접 거친다
    reader: MonitoringReader = Depends(get_monitoring_reader),
    now: datetime = Depends(get_now),
) -> dict:
    try:
        checked_at, buckets = await read_buckets(reader, now)
    # 우리 코드 실수(KeyError 등)는 잡지 않는다 — 500 으로 드러나야 한다. 구글 답 모양이 다른 것만 MonitoringShapeError 로 온다.
    except (httpx.HTTPError, google.auth.exceptions.GoogleAuthError, MonitoringShapeError) as exc:
        # 모양 오류는 원래 예외 이름(args[0]), 구글 오류는 HTTP 상태 코드(429 등)도 남긴다 — 주소 · 토큰 · 본문은 아니다.
        if isinstance(exc, MonitoringShapeError):
            detail = exc.args[0]
        elif isinstance(exc, httpx.HTTPStatusError):
            detail = exc.response.status_code
        else:
            detail = ""
        logger.warning("구글 모니터링 읽기 실패 %s %s", type(exc).__name__, detail)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE) from None
    return {
        "checked_at": checked_at.isoformat(),
        "bucket_minutes": BUCKET_MINUTES,
        "buckets": [{"start": b.start.isoformat(), "requests": b.requests, "errors_5xx": b.errors_5xx,
                     "p50_ms": b.p50_ms, "p95_ms": b.p95_ms, "instances": b.instances} for b in buckets],
        "now": summarize_now(buckets),
        "anomalies": [{"at": a.at.isoformat(), "kind": a.kind, "value": a.value} for a in find_anomalies(buckets)],
    }
