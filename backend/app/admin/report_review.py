"""관리자 신고 검수(설계 10-18 §8-2, 화면 A4). 목록 · 한 건 · 채팅 앞뒤 보기. 모든 경로는 get_admin_caller 뒤에 있다.

목록은 PostgREST 한 번(사진 없음). 실사진은 한 건을 볼 때만 5분 서명 URL 로 내려간다. 응답에 storage 경로 원문은 싣지 않는다.
"같은 대상" 은 같은 target_profile_id(신고당한 사람)다 — 자동 가림이 세는 기준과 같다.
"""
import asyncio
import logging
from typing import Annotated, Literal
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, StringConstraints

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.heart_task_review import PHOTO_URL_TTL_SECONDS
from app.admin.reason import REASON_MAX, ReasonBody
from app.admin.repository import NOT_FOUND, AdminRepository
from app.admin.request_ip import request_ip
from app.profile_onboarding.storage import ProfilePhotoStorage
from app.safety.repository import SafetyRepository

router = APIRouter(prefix="/reports")
logger = logging.getLogger(__name__)

# 신고된 줄 앞뒤로 보여 줄 줄 수(설계 §8-2 D — 사적 대화라 좁게).
CHAT_CONTEXT_EACH_SIDE = 5
NOT_MESSAGE_REPORT = "not_message_report"
ReportStatus = Literal["open", "actioned", "dismissed"]
TargetType = Literal["profile", "message", "friend_review", "poll"]


class ResolveBody(BaseModel):
    outcome: Literal["actioned", "dismissed"]
    # 메모는 선택이다(작업 기록 reason 칸). 공백뿐이면 없는 것으로 보낸다.
    note: Annotated[str, StringConstraints(strip_whitespace=True, max_length=REASON_MAX)] | None = None
    # 같은 사람(target_profile_id)을 향한 다른 열린 신고도 같은 결과로 닫는다 — 상세의 other_reports 중 열린 것들이다.
    same_target: bool = False


def _repo(caller: AdminCaller) -> AdminRepository:
    return AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _target_id(row: dict) -> str | None:
    """신고당한 사람 id. 그 계정이 지워졌으면(on delete set null) None."""
    return (row["target_profile"] or {}).get("id")


def _summary(row: dict) -> dict:
    """목록 한 줄. 접수 뒤 지난 시간은 웹이 created_at 으로 그린다."""
    profile = row["target_profile"]
    return {
        "id": row["id"], "target_type": row["target_type"], "target_id": row["target_id"],
        "reason": row["reason"], "reason_note": row["reason_note"], "status": row["status"],
        "created_at": row["created_at"], "resolved_at": row["resolved_at"],
        "target_profile": None if profile is None else {
            "id": profile["id"], "nickname": profile["nickname"], "university": profile["universities"]["name"],
            "status": profile["status"], "auto_hidden_at": profile["auto_hidden_at"],
        },
    }


async def _signed_photo(photos: ProfilePhotoStorage, report_id: str, path: str) -> str | None:
    """대상이 탈퇴하고 30일 뒤 정리되면 파일이 없다(설계 §13-2) — 500 이 아니라 그 사진만 뺀다."""
    try:
        return await photos.create_signed_url(path, PHOTO_URL_TTL_SECONDS)
    except (httpx.HTTPError, KeyError, ValueError):
        # 경로는 남기지 않는다(번호만).
        logger.warning("신고 사본 사진 서명 실패 report=%s", report_id)
        return None


async def _snapshot(caller: AdminCaller, row: dict) -> dict:
    """프로필 사본의 경로 두 칸(avatar_path · photo_paths)을 URL 로 바꾼다. 메시지 · 리뷰 · 투표 사본은 글자 그대로다."""
    snapshot = row["target_snapshot"]
    if row["target_type"] != "profile":
        return snapshot
    photos = ProfilePhotoStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client)
    urls = await asyncio.gather(*(_signed_photo(photos, row["id"], p) for p in snapshot.get("photo_paths") or []))
    avatar = snapshot.get("avatar_path")
    return {
        **{key: value for key, value in snapshot.items() if key not in ("avatar_path", "photo_paths")},
        # 아바타는 공개 버킷이다(chat/router.py avatar_url 과 같은 주소).
        "avatar_url": f"{caller.settings.storage_url}/object/public/avatars/{avatar}" if avatar else None,
        "photo_urls": [url for url in urls if url],
    }


async def _open_reporters(caller: AdminCaller, target: str | None) -> int:
    if target is None:
        return 0
    safety = SafetyRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    return await safety.count_open_reporters(target)


async def _other_reports(repo: AdminRepository, target: str | None, report_id: str) -> list[dict]:
    return [] if target is None else await repo.fetch_other_reports(target, report_id)


async def detail(caller: AdminCaller, report_id: UUID) -> dict:
    """한 건 · 조치 뒤 응답. 요약 + 사본(사진은 서명 URL) + 글 상태 + 같은 대상의 신고자 수 · 다른 신고."""
    repo = _repo(caller)
    row = await repo.fetch_report(report_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    target = _target_id(row)
    snapshot, content_status, reporters, others = await asyncio.gather(
        _snapshot(caller, row),
        repo.fetch_content_status(row["target_type"], row["target_id"]),
        _open_reporters(caller, target),
        _other_reports(repo, target, row["id"]),
    )
    return {**_summary(row), "snapshot": snapshot, "content_status": content_status,
            "open_reporters": reporters, "other_reports": others}


@router.get("")
async def list_reports(
    status: ReportStatus = "open",
    target_type: TargetType | None = Query(None, alias="type"),
    limit: int = Query(50, ge=1, le=100),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """PostgREST 한 번으로 끝난다 — 사본 · 사진 · 다른 신고는 웹이 줄을 골라 한 건을 받을 때(GET /{id})."""
    return {"items": [_summary(row) for row in await _repo(caller).list_reports(status, target_type, limit)]}


@router.get("/{report_id}")
async def get_report(report_id: UUID, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """한 건. 디스코드 알림 링크로 열 때와, 서명 URL 이 만료돼 사진을 다시 받을 때 쓴다."""
    return await detail(caller, report_id)


@router.post("/{report_id}/chat-context")
async def chat_context(
    report_id: UUID, body: ReasonBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """신고된 채팅 앞뒤 보기(설계 §8-2 D). 메시지 신고에만, 글자만, 사유 필수. 서버는 대화를 저장하지 않고 바로 돌려준다.
    **기록을 먼저 남긴다** — 기록이 실패하면 대화를 읽지도 돌려주지도 않는다(기록 없는 열람 금지). 기록에는 열람 사실 ·
    사유만 있고 대화 본문 · 방 번호는 없다. 대화방이 지워졌으면 빈 목록이다(화면 "없음")."""
    repo = _repo(caller)
    row = await repo.fetch_report(report_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    if row["target_type"] != "message":
        raise HTTPException(status_code=422, detail=NOT_MESSAGE_REPORT)
    await repo.record_action(caller.admin_user_id, "report_chat_view", target_type="report", target_id=str(report_id),
                             reason=body.reason, ip=request_ip(request))
    snapshot, target = row["target_snapshot"], _target_id(row)
    lines = await repo.fetch_chat_context(snapshot["match_id"], snapshot["message_id"], snapshot["created_at"],
                                          CHAT_CONTEXT_EACH_SIDE)
    return {"messages": [
        {"id": m["id"], "kind": m["kind"], "body": m["body"], "created_at": m["created_at"],
         "from_target": m["sender_id"] == target, "reported": m["id"] == snapshot["message_id"]}
        for m in lines
    ]}


@router.post("/{report_id}/resolve")
async def resolve_report(
    report_id: UUID, body: ResolveBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """조치 완료 / 기각. 닫기와 기록은 DB 함수 한 번(이미 닫힌 신고는 409 already_done). 응답은 처리 뒤 한 건."""
    await _repo(caller).resolve_report(caller.admin_user_id, report_id, body.outcome, body.note or None,
                                       body.same_target, request_ip(request))
    return await detail(caller, report_id)
