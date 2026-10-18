"""관리자 인증샷 검수(설계 10-18 §8-1, 화면 A3). 목록 · 한 건 · 승인 · 반려. 모든 경로는 get_admin_caller 뒤에 있다.

사진은 비공개 버킷의 5분 서명 URL 로만 내려간다. 응답에 storage_path 원문은 싣지 않는다.
"""
import asyncio
import logging
from typing import Literal
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.repository import NOT_FOUND, AdminRepository
from app.admin.request_ip import request_ip
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


async def _photo_url(storage: HeartProofStorage, row: dict) -> str | None:
    """60일 정리로 경로가 비었거나 Storage 가 서명을 못 하면 None — 500 이 아니라 "사진 없음" 이다."""
    if not row["storage_path"]:
        return None
    try:
        return await storage.create_signed_url(row["storage_path"], PHOTO_URL_TTL_SECONDS)
    # 200 인데 signedURL 이 없거나(KeyError) 본문이 JSON 이 아닌(ValueError) 답도 그 사진만 없는 것으로 본다.
    except (httpx.HTTPError, KeyError, ValueError):
        # 경로는 남기지 않는다(번호만).
        logger.warning("인증샷 서명 URL 실패 submission=%s", row["id"])
        return None


def _summary(row: dict) -> dict:
    """목록 한 줄(pen A3 목록 줄: 닉네임 · 항목 · 학교 · 시각 · 배지). 사진 · 지난 제출은 싣지 않는다 — 고른 건만 받는다."""
    profile = row["profiles"]
    return {
        "id": row["id"], "task": row["task"], "status": row["status"], "reject_reason": row["reject_reason"],
        "reward_hearts": row["reward_hearts"], "created_at": row["created_at"], "reviewed_at": row["reviewed_at"],
        "profile": {"id": profile["id"], "nickname": profile["nickname"], "university": profile["universities"]["name"]},
    }


async def _item(repo: AdminRepository, storage: HeartProofStorage, row: dict) -> dict:
    """한 건 · 승인 · 반려 응답. 요약 + 5분 서명 사진 + 같은 사람 · 같은 항목의 지난 제출(최대 5)."""
    previous = await repo.fetch_previous_heart_submissions(row["profiles"]["id"], row["task"], row["id"])
    photo, *previous_photos = await asyncio.gather(*(_photo_url(storage, r) for r in (row, *previous)))
    return {
        **_summary(row),
        "photo_url": photo,
        "previous": [
            {"id": p["id"], "status": p["status"], "created_at": p["created_at"], "photo_url": url}
            for p, url in zip(previous, previous_photos)
        ],
    }


async def _one(caller: AdminCaller, submission_id: UUID) -> dict:
    repo = _repo(caller)
    row = await repo.fetch_heart_submission(submission_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    return await _item(repo, _storage(caller), row)


async def _review(caller: AdminCaller, request: Request, submission_id: UUID,
                  status: str, reject_reason: str | None) -> dict:
    await _repo(caller).review_heart_task(caller.admin_user_id, submission_id, status, reject_reason, request_ip(request))
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
) -> dict:
    """본문은 읽지 않는다 — 승인에는 사유가 없다."""
    return await _review(caller, request, submission_id, "approved", None)


@router.post("/{submission_id}/reject")
async def reject_heart_task(
    submission_id: UUID, body: RejectBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    return await _review(caller, request, submission_id, "rejected", body.reason)
