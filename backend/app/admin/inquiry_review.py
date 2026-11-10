"""관리자 문의 관리(화면: 문의함). 목록 · 상태 / 메모 바꾸기. 모든 경로는 get_admin_caller 뒤에 있다.

답장은 이 서버가 보내지 않는다 — 운영자가 알림 메일의 '답장'(Reply-To = 사용자가 적은 메일)으로 회신하고, 여기서는 상태와 메모만 관리한다.
쪽 나누기는 (created_at, id) 커서: 다음 쪽은 마지막 줄의 created_at · id 를 before · before_id 로 보낸다.
"""
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, StringConstraints, model_validator

from app.admin import cursor
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.repository import NOT_FOUND, AdminRepository
from app.admin.request_ip import request_ip
from app.core.deps import get_now
from app.inquiries.reasons import MEMO_MAX, Status
from app.inquiries.repository import InquiryRepository

router = APIRouter(prefix="/inquiries")

DEFAULT_LIMIT = 50  # 설계 §12 의 기본 쪽 크기


class InquiryPatch(BaseModel):
    """바꿀 칸만 보낸다. status 는 null 로 보낼 수 없다(칸을 빼면 그대로). admin_memo 는 null · 빈 글이면 메모를 지운다."""

    status: Status | None = None
    admin_memo: Annotated[str, StringConstraints(strip_whitespace=True, max_length=MEMO_MAX)] | None = None

    @model_validator(mode="after")
    def _something_to_change(self) -> "InquiryPatch":
        if not self.model_fields_set or (self.model_fields_set == {"status"} and self.status is None) \
                or ("status" in self.model_fields_set and self.status is None):
            raise ValueError("status 는 null 일 수 없고, 바꿀 칸이 하나는 있어야 한다")
        return self


def _item(row: dict) -> dict:
    profile = row["profile"]
    return {
        **{key: row[key] for key in ("id", "reason", "body", "reply_email", "status", "admin_memo",
                                     "created_at", "updated_at", "answered_at")},
        "profile": None if profile is None else {
            "id": profile["id"], "nickname": profile["nickname"],
            "university": (profile["universities"] or {}).get("name"),
        },
    }


@router.get("")
async def list_inquiries(
    status: Status | None = None,
    before: str | None = None,
    before_id: UUID | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=100),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """최근 순. has_more 는 한 줄 더 달라고 해서 정확히 안다(limit 줄이 딱 맞으면 false)."""
    if (before is None) != (before_id is None):
        raise cursor.bad()
    cursor_pair = None if before is None else cursor.parse(f"{before}|{before_id}")
    repo = InquiryRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    rows = await repo.list_page(status, cursor_pair, limit + 1)
    return {"items": [_item(row) for row in rows[:limit]], "has_more": len(rows) > limit}


@router.patch("/{inquiry_id}")
async def update_inquiry(
    inquiry_id: UUID, body: InquiryPatch, request: Request,
    caller: AdminCaller = Depends(get_admin_caller), now: datetime = Depends(get_now),
) -> dict:
    """상태 · 메모 바꾸기. answered 가 되면 answered_at 을 찍고(1년 보관의 기준), answered 를 벗어나면 비운다 — DB check 가 둘을 묶는다.
    **기록을 먼저 남긴다** — 기록이 실패하면 바꾸지 않는다. 기록에는 상태만 있고 메모 글은 없다."""
    repo = InquiryRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    current = await repo.fetch(inquiry_id)
    if current is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)

    changes: dict = {"updated_at": now.isoformat()}
    status_after = current["status"]
    if body.status is not None:
        status_after = body.status
        changes["status"] = body.status
        changes["answered_at"] = (current["answered_at"] or now.isoformat()) if body.status == "answered" else None
    memo_changed = "admin_memo" in body.model_fields_set
    if memo_changed:
        changes["admin_memo"] = body.admin_memo or None

    admin = AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    await admin.record_action(
        caller.admin_user_id, "inquiry_update", target_type="inquiry", target_id=str(inquiry_id),
        before={"status": current["status"]}, after={"status": status_after, "memo_changed": memo_changed},
        ip=request_ip(request))
    updated = await repo.update(inquiry_id, changes)
    if updated is None:  # 읽은 뒤 1년 정리가 지운 드문 경우
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    return _item(updated)
