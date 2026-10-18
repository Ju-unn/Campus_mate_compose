"""관리자 홈 통계 · 일별 그래프 · 미등록 학교 메일 · 학교별 현황(설계 10-18 §8-4 · §8-4b, 화면 A2 · A6). 읽기만 한다 — 작업 기록에 쓰지 않는다.

관리자 계정은 통계에서 빠진다(DB 함수가 거른다). 응답은 칸 이름을 하나씩 적어 만든다 — DB 줄을 그대로 흘리지 않는다.
"""
from fastapi import APIRouter, Depends, Query

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.stats_repository import AdminStatsRepository

router = APIRouter()

# 설계 §8-4b: 그래프 기본 30일, 서버는 90일까지(화면은 30일 고정 — 대장 확정 10-18).
DEFAULT_DAYS = 30
MAX_DAYS = 90
# 미등록 도메인은 행 상한이 5000 이라 한 쪽에 다 담지 않는다 — 많은 순 위쪽만.
DEFAULT_DOMAINS = 200
MAX_DOMAINS = 500


def _repo(caller: AdminCaller) -> AdminStatsRepository:
    return AdminStatsRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.get("/stats")
async def get_stats(caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    row = await _repo(caller).overview()
    return {
        "profiles": {"pending": row["pending_count"], "active": row["active_count"],
                     "suspended": row["suspended_count"], "withdrawn": row["withdrawn_count"]},
        "open_reports": row["open_reports"], "pending_proofs": row["pending_proofs"],
        "signups_today": row["signups_today"], "signups_7d": row["signups_7d"],
    }


@router.get("/stats/daily")
async def get_stats_daily(days: int = Query(DEFAULT_DAYS, ge=1, le=MAX_DAYS), caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    rows = await _repo(caller).daily(days)
    return {"days": [{"date": row["day"], "male_signups": row["male_signups"], "female_signups": row["female_signups"],
                      "report_count": row["report_count"], "proof_count": row["proof_count"]} for row in rows]}


@router.get("/unknown-domains")
async def get_unknown_domains(
    limit: int = Query(DEFAULT_DOMAINS, ge=1, le=MAX_DOMAINS), caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    rows = await _repo(caller).unknown_domains(limit)
    return {"items": [{"domain": row["domain"], "attempt_count": row["attempt_count"],
                       "first_seen_at": row["first_seen_at"], "last_seen_at": row["last_seen_at"]} for row in rows]}


@router.get("/universities")
async def get_universities(include_empty: bool = False, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    rows = await _repo(caller).universities(include_empty)
    return {"items": [{key: row[key] for key in ("id", "name", "region_group", "card_opens_at", "is_open",
                                                  "male_active", "female_active")} for row in rows]}
