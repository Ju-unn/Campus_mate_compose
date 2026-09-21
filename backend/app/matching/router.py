import httpx
from fastapi import APIRouter, Header, HTTPException, Query

from app.core.deps import get_settings
from app.matching.repository import MatchingRepository
from app.matching.scoring import rank
from app.student_verification.current_user import get_verified_user_id

router = APIRouter()

# 테스트가 실제 Supabase 대신 목을 주입할 수 있게 하는 훅(조각1b·2 라우터와 같은 패턴).
_client_override: httpx.AsyncClient | None = None


@router.get("/matching/candidates")
async def get_candidates(
    limit: int = Query(default=10, ge=1, le=100),
    authorization: str | None = Header(default=None),
) -> dict:
    """하드 필터를 통과한 후보를 최종점수 내림차순으로 돌려준다(설계 §6.7·§6.8).
    카드 지급·수락은 조각 4 다 — 여기서는 순위만 본다."""
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)

    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    owner = await repo.fetch_owner(profile_id)
    if owner["status"] != "active":
        # 온보딩을 끝내야 카드를 받는다(설계 §6.7 하드 필터는 후보쪽만 본다).
        raise HTTPException(status_code=403, detail="프로필을 먼저 완성해 주세요")
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
