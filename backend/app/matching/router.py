from fastapi import APIRouter, Depends, HTTPException, Query

from app.core import errors
from app.core.deps import Caller, get_verified_caller
from app.matching.repository import MatchingRepository
from app.matching.scoring import rank

router = APIRouter()


@router.get("/matching/candidates")
async def get_candidates(
    limit: int = Query(default=10, ge=1, le=100),
    caller: Caller = Depends(get_verified_caller),
) -> dict:
    """하드 필터를 통과한 후보를 최종점수 내림차순으로 돌려준다(설계 §6.7·§6.8).
    카드 지급·수락은 조각 4 다 — 여기서는 순위만 본다."""
    settings, client, profile_id = caller
    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    owner = await repo.fetch_owner(profile_id)
    if owner["status"] != "active":
        # 온보딩을 끝내야 카드를 받는다(설계 §6.7 하드 필터는 후보쪽만 본다).
        raise HTTPException(status_code=403, detail=errors.PROFILE_INCOMPLETE)
    if not await repo.has_vectors(profile_id):
        # 내 벡터가 아직 없으면 어차피 후보가 안 나온다 — RPC 를 건너뙱다.
        return {"candidates": []}
    candidates = await repo.fetch_candidates(profile_id)

    ranked = rank(owner, candidates)[:limit]
    return {
        "candidates": [
            {"profile_id": c["candidate_id"], "score": round(c["score"], 4)} for c in ranked
        ]
    }
