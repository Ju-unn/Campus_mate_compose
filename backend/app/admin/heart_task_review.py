"""관리자 인증샷 검수(설계 10-18 §8-1, 화면 A3). 목록 · 한 건 · 승인 · 반려. 모든 경로는 get_admin_caller 뒤에 있다.

사진은 비공개 버킷의 5분 서명 URL 로만 내려간다. 응답에 storage_path 원문은 싣지 않는다.
"""
import asyncio
import logging
from typing import Literal
from uuid import UUID

from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.heart_task_notice import result_notice, send_result_notice
from app.admin.repository import NOT_FOUND, AdminRepository
from app.admin.request_ip import request_ip
from app.cards.push import FcmSender
from app.cards.router import get_sender
from app.core.deps import get_now
from app.heart_tasks.storage import HeartProofStorage

router = APIRouter(prefix="/heart-tasks")
logger = logging.getLogger(__name__)

PHOTO_URL_TTL_SECONDS = 300
Task = Literal["everytime_post", "kakao_share"]


class RejectBody(BaseModel):
    # 앱 frontend/lib/billing/model/heart_task.dart 의 세 사유와 같다(enum public.heart_task_reject_reason).
    reason: Literal["date_missing", "not_verified", "reused"]


def _repo(caller: AdminCaller) -> AdminRepository:
    return AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _storage(caller: AdminCaller) -> HeartProofStorage:
    return HeartProofStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client)


async def _signed_url(storage: HeartProofStorage, submission_id: str, path: str) -> str | None:
    """Storage 가 서명을 못 하면 그 한 장만 None — 500 이 아니라 "사진 없음" 이다."""
    try:
        return await storage.create_signed_url(path, PHOTO_URL_TTL_SECONDS)
    # 200 인데 signedURL 이 없거나(KeyError) 본문이 JSON 이 아닌(ValueError) 답도 그 사진만 없는 것으로 본다.
    except (httpx.HTTPError, KeyError, ValueError):
        # 경로는 남기지 않는다(번호만).
        logger.warning("인증샷 서명 URL 실패 submission=%s", submission_id)
        return None


async def _photo_urls(storage: HeartProofStorage, row: dict) -> list[str | None]:
    """한 제출의 사진 1~3장을 순서대로 서명한다. 60일 정리로 경로가 비었으면 `[]`, 서명에 실패한 장은 None(장수는 유지)."""
    return list(await asyncio.gather(*(_signed_url(storage, row["id"], path) for path in row["storage_paths"])))


def _summary(row: dict) -> dict:
    """목록 한 줄(pen A3 목록 줄: 닉네임 · 항목 · 학교 · 시각 · 배지). 사진 · 지난 제출은 싣지 않는다 — 고른 건만 받는다."""
    profile = row["profiles"]
    return {
        "id": row["id"], "task": row["task"], "status": row["status"], "reject_reason": row["reject_reason"],
        "reward_hearts": row["reward_hearts"], "created_at": row["created_at"], "reviewed_at": row["reviewed_at"],
        "profile": {"id": profile["id"], "nickname": profile["nickname"], "university": profile["universities"]["name"]},
    }


async def _item(repo: AdminRepository, storage: HeartProofStorage, row: dict) -> dict:
    """한 건 · 승인 · 반려 응답. 요약 + 5분 서명 사진(1~3장) + 같은 사람 · 같은 항목의 지난 제출(최대 5).
    `photo_urls` 가 새 칸이고 `photo_url`(= 첫 장)은 옛 칸이다 — 관리자 웹이 서버보다 먼저 · 늦게 나가도 읽히게 둘 다 싣는다."""
    previous = await repo.fetch_previous_heart_submissions(row["profiles"]["id"], row["task"], row["id"])
    photos, *previous_photos = await asyncio.gather(*(_photo_urls(storage, r) for r in (row, *previous)))
    return {
        **_summary(row),
        "photo_url": photos[0] if photos else None,
        "photo_urls": photos,
        "previous": [
            {"id": p["id"], "status": p["status"], "created_at": p["created_at"],
             "photo_url": urls[0] if urls else None, "photo_urls": urls}
            for p, urls in zip(previous, previous_photos)
        ],
    }


async def _one(caller: AdminCaller, submission_id: UUID) -> dict:
    repo = _repo(caller)
    row = await repo.fetch_heart_submission(submission_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    return await _item(repo, _storage(caller), row)


async def _review(caller: AdminCaller, request: Request, submission_id: UUID, status: str, reject_reason: str | None,
                  sender: FcmSender, now: datetime) -> dict:
    """검수 → 곧바로 결과 알림 → 응답. 줄은 검수 전에 읽어 둔다(없으면 404) — 검수 뒤 읽기가 실패해도 알림은 이미 갔다.
    알림은 DB 함수가 성공한 뒤에만 가고(409 · 404 · 422 는 위에서 올라온다), 실패해도 응답을 뒤집지 않는다."""
    repo = _repo(caller)
    row = await repo.fetch_heart_submission(submission_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    result = await repo.review_heart_task(caller.admin_user_id, submission_id, status, reject_reason, request_ip(request))
    notice = result_notice(row["task"], result["status"], result["reward_hearts"], result["reject_reason"])
    await send_result_notice(caller, sender, now, row["profiles"]["id"], notice)
    return await _one(caller, submission_id)


@router.get("")
async def list_heart_tasks(
    status: Literal["submitted", "approved", "rejected"] = "submitted",
    task: Task | None = None,
    limit: int = Query(50, ge=1, le=100),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """PostgREST 한 번으로 끝난다 — 서명 · 지난 제출 조회는 웹이 줄을 골라 한 건을 받을 때(GET /{id})."""
    return {"items": [_summary(row) for row in await _repo(caller).list_heart_submissions(status, task, limit)]}


@router.get("/{submission_id}")
async def get_heart_task(submission_id: UUID, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """한 건. 디스코드 알림 링크로 열 때와, 서명 URL 이 만료돼 사진을 다시 받을 때 쓴다."""
    return await _one(caller, submission_id)


@router.post("/{submission_id}/approve")
async def approve_heart_task(
    submission_id: UUID, request: Request, caller: AdminCaller = Depends(get_admin_caller),
    sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now),
) -> dict:
    """본문은 읽지 않는다 — 승인에는 사유가 없다."""
    return await _review(caller, request, submission_id, "approved", None, sender, now)


@router.post("/{submission_id}/reject")
async def reject_heart_task(
    submission_id: UUID, body: RejectBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
    sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now),
) -> dict:
    return await _review(caller, request, submission_id, "rejected", body.reason, sender, now)
