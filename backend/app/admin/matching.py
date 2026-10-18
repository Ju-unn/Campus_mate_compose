"""관리자 매칭 현황(설계 10-18 §8-4c, 화면 A9): 숫자 카드 · 30일 그래프 · 누가 누구랑 매칭됐나. 읽기만 한다.

누가 누구와 매칭됐는지는 민감한 정보다 — 닉네임 · 학교 이름 · 프로필 id · 시각 · 상태만 싣고 사진 · 카톡 아이디 · 대화 · 전화는 싣지 않는다
(카톡 아이디는 사용자 상세의 "열람"(사유 필수 · 기록)으로만). 목록 보기 자체는 작업 기록에 남기지 않는다(설계 §8-4c).
필터 값은 핸들러가 직접 검사해 틀리면 입력을 되돌리지 않는 422 로 돌리고, 맞으면 DB 함수의 타입 있는 인자로만 보낸다.
"""
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from app.admin import cursor
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.matching_repository import AdminMatchingRepository

router = APIRouter(prefix="/matching")

DEFAULT_DAYS = 30
DEFAULT_LIMIT = 50  # 설계 §12 의 기본 쪽 크기
STATUSES = frozenset({"chatting", "shared", "closed"})


def _repo(caller: AdminCaller) -> AdminMatchingRepository:
    return AdminMatchingRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _person(row: dict, side: str) -> dict:
    return {"id": row[f"{side}_id"], "nickname": row[f"{side}_nickname"], "university": row[f"{side}_university"]}


def _pair(row: dict) -> dict:
    # 칸을 하나씩 적는다 — DB 함수가 바뀌어 다른 칸이 섞여 와도 응답으로 새지 않는다.
    return {"id": row["match_id"], "matched_at": row["matched_at"], "status": row["status"], "shared_at": row["shared_at"],
            "a": _person(row, "a"), "b": _person(row, "b")}


@router.get("/summary")
async def get_summary(caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    row = await _repo(caller).summary()
    matches, shared = row["matches_total"], row["shared_total"]
    return {
        **{key: row[key] for key in ("accepts_today", "accepts_yesterday", "accepts_total", "accepters_total",
                                     "matches_total", "shared_total")},
        # 공유 쌍 ÷ 매칭 쌍(0~1). 매칭이 없으면 나눌 수 없어 null — 화면이 "-" 로 그린다.
        "share_rate": shared / matches if matches else None,
    }


@router.get("/daily")
async def get_daily(days: int = Query(DEFAULT_DAYS, ge=1, le=90), caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    rows = await _repo(caller).daily(days)
    return {"days": [{"date": row["day"], "accept_count": row["accept_count"], "match_count": row["match_count"],
                      "share_count": row["share_count"]} for row in rows]}


@router.get("/pairs")
async def list_pairs(
    status: str | None = None,
    university: str | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=100),
    before: str | None = None,
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    if status is not None and status not in STATUSES:
        raise cursor.bad()
    try:
        school = None if university is None else str(UUID(university))
    except ValueError:
        raise cursor.bad()
    page = None if before is None else cursor.parse(before)
    rows = await _repo(caller).pairs(status, school, page, limit + 1)
    more = len(rows) > limit
    rows = rows[:limit]
    return {
        "items": [_pair(row) for row in rows],
        "next_before": f"{rows[-1]['matched_at']}|{rows[-1]['match_id']}" if more else None,
    }
