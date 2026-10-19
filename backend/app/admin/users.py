"""관리자 사용자 찾기 · 상세 · 메모(설계 10-18 §8-3, 화면 A5). 모든 경로는 get_admin_caller 뒤에 있다.

관리자 계정은 이 화면에서 존재하지 않는 것으로 본다(목록에서 빠지고 상세 · 메모는 404) — 설계 §6-5.
학교 메일은 요청 본문으로만 받아 해시로만 찾는다. 응답 · 로그 · 작업 기록 · 오류 본문에 되돌리지 않는다(설계 §14-3).
"""
import asyncio
import logging
import re
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from app.account.repository import SupabaseAdmin
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.reason import Reason
from app.admin.repository import NOT_FOUND
from app.admin.request_ip import request_ip
from app.admin.user_repository import NOTE_ACTION, AdminUserRepository
from app.chat.router import avatar_url
from app.core import errors
from app.signup_policy import bytea_literal, hash_email

router = APIRouter(prefix="/users")
logger = logging.getLogger(__name__)

# 상세에 싣는 최근 줄 수(하트 원장 · 구매 · 메모).
RECENT_ROWS = 20
# q 는 닉네임(2~5자) 또는 프로필 id(UUID 36자)다.
QUERY_MAX = 36
# 학교 메일 모양 검사. 틀리면 입력을 되돌리지 않는 422 다(FastAPI 기본 422 는 입력값을 싣는다 — 메일 원문이 새는 길).
_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
EMAIL_MAX = 254


class SearchBody(BaseModel):
    # 제약 없이 받는다 — 모양 검사는 핸들러가 직접 하고 오류에 입력을 싣지 않는다.
    school_email: str


class NoteBody(BaseModel):
    text: Reason  # 메모도 사유와 같은 1~500자(대장 결정 4)


def _repo(caller: AdminCaller) -> AdminUserRepository:
    return AdminUserRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _summary(row: dict, report_count: int) -> dict:
    """목록 한 줄(pen A5 찾기 표: 닉네임 · 프로필 id · 학교 · 상태 · 가입일 · 받은 신고)."""
    return {
        "id": row["id"], "nickname": row["nickname"], "university": (row["universities"] or {}).get("name"),
        "status": row["status"], "created_at": row["created_at"], "report_count": report_count,
    }


async def _summaries(repo: AdminUserRepository, rows: list[dict]) -> list[dict]:
    counts = await repo.count_reports_by_target([row["id"] for row in rows])
    return [_summary(row, counts.get(row["id"], 0)) for row in rows]


async def _login_providers(caller: AdminCaller, profile_id: UUID) -> list[str] | None:
    """auth 관리자 API 의 identities 에서 로그인 방식(kakao · google · apple)만. 로그인 메일 원문은 읽지도 싣지도 않는다.
    조회에 실패하면 None — 상세 전체가 500 이 되지 않는다."""
    try:
        user = await SupabaseAdmin(caller.settings, caller.client).fetch_user(profile_id)
        return [identity["provider"] for identity in user.get("identities") or []]
    except (httpx.HTTPError, KeyError, ValueError):
        logger.warning("로그인 방식 조회 실패 profile=%s", profile_id)  # 번호만
        return None


def _with_balance_after(ledger: list[dict], balance: int) -> list[dict]:
    """최근 순 원장에 줄마다 그 줄 직후 잔액을 붙인다 — 현재 잔액에서 거슬러 계산(원장 합 = 잔액이라는 ERD 불변식에 기댄다)."""
    rows = []
    for entry in ledger:
        rows.append({"id": entry["id"], "created_at": entry["created_at"], "amount": entry["amount"],
                     "reason": entry["reason"], "balance_after": balance})
        balance -= entry["amount"]
    return rows


def _purchase(row: dict) -> dict:
    return {
        "id": row["id"], "store": row["store"], "product_id": row["product_id"], "status": row["status"],
        "is_test": row["is_test"], "granted_hearts": row["heart_amount"] + row["bonus_hearts"],
        "bonus_hearts": row["bonus_hearts"], "clawed_back_hearts": row["clawed_back_hearts"],
        "purchased_at": row["purchased_at"],
    }


@router.get("")
async def list_users(
    q: str | None = Query(None, max_length=QUERY_MAX),
    limit: int = Query(50, ge=1, le=100),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """q 가 UUID 면 프로필 id, 아니면 닉네임 부분 일치. 없으면 가입 최근 순. 관리자 프로필은 빠진다."""
    repo = _repo(caller)
    admins = await repo.admin_ids()
    text = (q or "").strip()
    try:
        profile_id = str(UUID(text)) if text else None
    except ValueError:
        profile_id = None
    rows = await repo.list_users(nickname=None if profile_id else text or None, profile_id=profile_id,
                                 limit=limit, exclude_ids=admins)
    return {"items": await _summaries(repo, rows)}


@router.post("/search")
async def search_by_school_email(body: SearchBody, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """학교 메일로 찾기(탈퇴 대행 10일 기한 · 정지 문의에 필요). 원문이 아니라 해시로 정확히 일치하는 계정만 — 기록하지 않는다."""
    email = body.school_email.strip()
    if len(email) > EMAIL_MAX or not _EMAIL.fullmatch(email):
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    repo = _repo(caller)
    profile_id = await repo.find_profile_by_school_email(
        bytea_literal(hash_email(caller.settings.identity_hmac_key, email)))
    if profile_id is None:
        return {"items": []}
    rows = await repo.list_users(nickname=None, profile_id=profile_id, limit=1, exclude_ids=await repo.admin_ids())
    return {"items": await _summaries(repo, rows)}


@router.get("/{user_id}")
async def get_user(user_id: UUID, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    repo = _repo(caller)
    row = await repo.fetch_user_profile(user_id)
    if row is None or await repo.is_admin(user_id):
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    reports, blocks, balance, ledger, purchases, notes, providers = await asyncio.gather(
        repo.count_reports(user_id), repo.count_contact_blocks(user_id), repo.fetch_heart_balance(user_id),
        repo.list_heart_ledger(user_id, RECENT_ROWS), repo.list_purchases(user_id, RECENT_ROWS),
        repo.list_notes(user_id, RECENT_ROWS), _login_providers(caller, user_id),
    )
    return {
        **_summary(row, reports),
        "last_active_at": row["last_active_at"], "auto_hidden_at": row["auto_hidden_at"],
        "avatar_url": avatar_url(row, caller.settings.supabase_url),
        "school_email_verified": row["school_email_verified_at"] is not None,
        "login_providers": providers, "heart_balance": balance, "contact_block_count": blocks,
        "hearts": _with_balance_after(ledger, balance),
        "purchases": [_purchase(p) for p in purchases],
        "notes": [{"id": n["id"], "created_at": n["created_at"], "admin_user_id": n["admin_user_id"], "text": n["reason"]}
                  for n in notes],
    }


@router.post("/{user_id}/notes")
async def add_note(user_id: UUID, body: NoteBody, request: Request, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """조치 없이 기록만(작업 기록 profile_note 한 줄, 글자는 reason). 탈퇴한 계정에도 남길 수 있다(탈퇴 뒤 문의 응대)."""
    repo = _repo(caller)
    if await repo.fetch_profile_status(user_id) is None or await repo.is_admin(user_id):
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    await repo.record_action(caller.admin_user_id, NOTE_ACTION, target_type="profile", target_id=str(user_id),
                             reason=body.text, ip=request_ip(request))
    return {"saved": True}
