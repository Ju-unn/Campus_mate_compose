"""관리자 정지 · 해제 · 자동 가림 해제 · 투표 글과 지인 리뷰 가림(설계 10-18 §8-2, 화면 A4 의 단추들).

바꾸기와 작업 기록은 DB 함수 한 번(한 트랜잭션, 마이그레이션 20261018030000)이다 — 서버는 표를 직접 PATCH 하지 않는다.
사유는 모두 필수다. 없음 404 not_found · 이미 그 상태 409 already_done · 규칙 위반 422.
"""
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.reason import ReasonBody
from app.admin.repository import AdminRepository
from app.admin.request_ip import request_ip

router = APIRouter()

# 경로 이름 → DB 의 report_target 값. 경로에는 하이픈, DB 에는 밑줄이다.
_CONTENT_KINDS = {"polls": "poll", "friend-reviews": "friend_review"}
_CONTENT_STATUS = {"blind": "blinded", "unblind": "visible"}


def _repo(caller: AdminCaller) -> AdminRepository:
    return AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.post("/profiles/{profile_id}/{action}")
async def act_on_profile(
    profile_id: UUID, action: Literal["suspend", "unsuspend", "unhide"], body: ReasonBody, request: Request,
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """정지(직전 상태를 기록) · 해제(직전 상태로, 기록이 없으면 온보딩 체크로) · 가림 해제(그 사람의 열린 신고도 기각)."""
    return await _repo(caller).act_on_profile(action, caller.admin_user_id, profile_id, body.reason, request_ip(request))


@router.post("/content/{kind}/{content_id}/{action}")
async def set_content_status(
    kind: Literal["polls", "friend-reviews"], content_id: UUID, action: Literal["blind", "unblind"],
    body: ReasonBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """투표 글 · 지인 리뷰 가림 / 해제(content_status). 신고를 닫는 것은 따로다(POST /admin/reports/{id}/resolve)."""
    return await _repo(caller).set_content_status(caller.admin_user_id, _CONTENT_KINDS[kind], content_id,
                                                  _CONTENT_STATUS[action], body.reason, request_ip(request))
