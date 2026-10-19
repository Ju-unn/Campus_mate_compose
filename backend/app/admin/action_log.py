"""관리자 작업 기록 보기(설계 10-18 §8-5, 화면 A7). 읽기만 한다 — 읽는 일은 기록하지 않는다. 기록은 고치거나 지울 수 없다(DB 트리거).

쪽 나누기는 (created_at, id) 커서다: 같은 DB 함수 안에서 쓴 줄들은 created_at 이 같아(now()) 시각만으로 자르면 줄을 놓친다.
"""
import asyncio
import logging
import re
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Query

from app.account.repository import SupabaseAdmin
from app.admin import cursor
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.repository import AdminRepository

router = APIRouter(prefix="/actions")
logger = logging.getLogger(__name__)

DEFAULT_LIMIT = 50  # 설계 §12 의 기본 쪽 크기
# target_id · target_type 은 정확 일치. 글자를 좁혀 PostgREST 필터 문법(쉼표 · 괄호)이 끼어들 틈을 없앤다.
_TARGET = re.compile(r"[A-Za-z0-9._:-]{1,64}")
_TYPE = re.compile(r"[a-z_]{1,32}")


def _repo(caller: AdminCaller) -> AdminRepository:
    return AdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


async def _admin_email(caller: AdminCaller, admin_id: str) -> str | None:
    """그 관리자의 로그인 메일(관리자 본인 정보 — 화면 A7 의 "관리자" 칸). 못 읽으면 None, 기록 보기는 계속된다."""
    try:
        return (await SupabaseAdmin(caller.settings, caller.client).fetch_user(admin_id)).get("email")
    except (httpx.HTTPError, ValueError):
        logger.warning("작업 기록의 관리자 메일 조회 실패 admin=%s", admin_id)  # 번호만
        return None


@router.get("")
async def list_actions(
    admin: UUID | None = None,
    target: str | None = None,
    type: str | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=100),
    before: str | None = None,
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    target = None if target is None else target.strip()
    if (target is not None and not _TARGET.fullmatch(target)) or (type is not None and not _TYPE.fullmatch(type)):
        raise cursor.bad()
    repo = _repo(caller)
    rows = await repo.list_actions(admin=None if admin is None else str(admin), target=target, target_type=type,
                                   before=None if before is None else cursor.parse(before), limit=limit + 1)
    more = len(rows) > limit
    rows = rows[:limit]
    admin_ids = sorted({row["admin_user_id"] for row in rows})
    profile_ids = sorted({row["target_id"] for row in rows if row["target_type"] == "profile"})
    emails, nicknames = await asyncio.gather(
        asyncio.gather(*(_admin_email(caller, admin_id) for admin_id in admin_ids)), repo.profile_nicknames(profile_ids))
    email_of = dict(zip(admin_ids, emails))
    return {
        "items": [{
            **{key: row[key] for key in ("id", "created_at", "admin_user_id")},
            "admin_email": email_of[row["admin_user_id"]],
            **{key: row[key] for key in ("action", "target_type", "target_id")},
            "target_nickname": nicknames.get(row["target_id"]) if row["target_type"] == "profile" else None,
            **{key: row[key] for key in ("before", "after", "reason", "ip")},
        } for row in rows],
        "next_before": f"{rows[-1]['created_at']}|{rows[-1]['id']}" if more else None,
    }
