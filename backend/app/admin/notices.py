"""관리자 공지(할 일 21, 설계 docs/superpowers/specs/2026-11-24-community-notices-design.md "관리자").

만들기 = 제목 · 본문 · 그림 1장(선택). 그림은 서버가 받아 검사 · 다시 저장(community/notice_image)하고 경로 `{id}.jpg` ·
content-type image/jpeg 를 서버가 정한다. 순서: id → 그림 올리기 → DB(admin_create_notice) — DB 가 실패하면 올린 그림을 지운다.
지우기 = DB(admin_delete_notice) → 그림 지우기(실패는 로그만). 가림 · 해제는 기존 /admin/content/polls/{id}/{blind|unblind} 그대로.
"""
import asyncio
import logging
from datetime import datetime
from typing import Annotated
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import AfterValidator, StringConstraints

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.reason import ReasonBody
from app.admin.repository import AdminRepository
from app.admin.request_ip import request_ip
from app.community.notice_image import (
    CONTENT_TYPE, MAX_IMAGE_BYTES, NOTICE_BUCKET, ImageRejected, notice_image_path, notice_image_url, prepare_notice_image)
from app.core.cursor import check_cursor
from app.core.storage import BucketStorage
from app.core.text import SAFE_LINE, body_text, require_visible

logger = logging.getLogger(__name__)

router = APIRouter()

# DB polls_notice_title · polls_question_length check 와 같은 값이다.
TITLE_MAX_LENGTH = 40
BODY_MAX_LENGTH = 2000
PAGE_SIZE = 20

# 제목은 한 줄 칸(줄바꿈 · 제어 · 글 방향 문자 거절), 본문은 게시물 · 댓글과 같은 여러 줄 검사(core/text.py).
Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=TITLE_MAX_LENGTH), SAFE_LINE,
                  AfterValidator(require_visible)]
Body = body_text(BODY_MAX_LENGTH)


def _repo(caller: AdminCaller) -> AdminRepository:
    return AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _storage(caller: AdminCaller) -> BucketStorage:
    return BucketStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client,
                         NOTICE_BUCKET)


async def _remove_quietly(storage: BucketStorage, path: str, notice_id: UUID) -> None:
    try:
        await storage.delete([path])
    except Exception:
        # 공개 버킷에 주인 없는 그림이 남는다 — 공지 id 로 대시보드에서 찾아 지운다.
        logger.warning("공지 그림 지우기 실패(고아 파일) notice=%s", notice_id)


async def _read_image(image: UploadFile | None) -> bytes | None:
    if image is None:
        return None
    raw = await image.read(MAX_IMAGE_BYTES + 1)  # 한도를 넘었는지만 알면 된다 — 끝까지 읽지 않는다
    try:
        # 그림 풀기 · 다시 저장은 CPU 일이라 이벤트 루프 밖에서 한다.
        return await asyncio.to_thread(prepare_notice_image, raw)
    except ImageRejected as rejected:
        # 기계용 detail — 관리자 웹이 글자로 바꾼다(image_type · image_too_large).
        raise HTTPException(status_code=422, detail=rejected.reason) from None


def _view(row: dict, supabase_url: str) -> dict:
    return {"id": row["id"], "title": row["title"], "text": row["question"],
            "image_url": notice_image_url(supabase_url, row["image_path"]),
            "status": row["status"], "created_at": row["created_at"]}


@router.get("/notices")
async def list_notices(before: datetime | None = None, before_id: UUID | None = None,
                       caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """공지 목록(가린 것 포함, 최신순 20개). 더 보려면 맨 아래 줄의 `created_at` · `id` 를 before · before_id 로."""
    check_cursor(before, before_id)
    rows = await _repo(caller).list_notices(before=before, before_id=before_id, limit=PAGE_SIZE + 1)
    return {"items": [_view(row, caller.settings.supabase_url) for row in rows[:PAGE_SIZE]],
            "has_more": len(rows) > PAGE_SIZE}


@router.post("/notices", status_code=201)
async def create_notice(
    title: Annotated[Title, Form()], body: Annotated[Body, Form()], request: Request,
    image: UploadFile | None = File(default=None),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """multipart: title(1~40자) · body(1~2000자) · image(선택, jpeg · png · webp, 10MB). 그림 오류는 422 image_type · image_too_large."""
    data = await _read_image(image)
    notice_id = uuid4()
    path = None if data is None else notice_image_path(notice_id)
    storage = _storage(caller)
    if path is not None:
        await storage.upload(path, data, CONTENT_TYPE)
    try:
        await _repo(caller).create_notice(caller.admin_user_id, notice_id, title, body, path, request_ip(request))
    except (HTTPException, httpx.HTTPStatusError):
        # DB 가 오류로 답했다 = 공지가 들어가지 않았다(한 트랜잭션) — 올린 그림은 주인이 없으니 지운다.
        if path is not None:
            await _remove_quietly(storage, path, notice_id)
        raise
    except httpx.TransportError:
        # 시간 초과 · 끊김은 결과를 모른다 — 공지가 들어갔을 수 있어 그림을 지우면 깨진 주소가 남는다. 로그만 남긴다.
        if path is not None:
            logger.warning("공지 저장 결과를 모른다 — 그림을 남긴다(공지 목록에 없으면 고아 파일) notice=%s", notice_id)
        raise
    return {"id": str(notice_id)}


@router.delete("/notices/{notice_id}")
async def delete_notice(notice_id: UUID, body: ReasonBody, request: Request,
                        caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """공지 지우기(사유 필수). 댓글은 DB 에서 같이 지워지고, 그림은 그 뒤에 지운다. 없는 공지 · 공지가 아닌 글은 404 not_found."""
    deleted = await _repo(caller).delete_notice(caller.admin_user_id, notice_id, body.reason, request_ip(request))
    if deleted.get("image_path"):
        await _remove_quietly(_storage(caller), deleted["image_path"], notice_id)
    return {"id": str(notice_id)}
