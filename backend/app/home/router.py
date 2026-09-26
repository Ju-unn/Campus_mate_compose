from fastapi import APIRouter, Depends

from app.core.deps import Caller, get_verified_caller
from app.home.completion import completion_percent
from app.home.repository import HomeRepository

router = APIRouter()


@router.get("/home/summary")
async def get_home_summary(caller: Caller = Depends(get_verified_caller)) -> dict:
    """홈 09b 메인의 숫자들. 전체 집계는 모두에게 같은 값이라 DB 함수로, 완성도는 내 행이라 따로 읽는다."""
    settings, client, profile_id = caller
    repo = HomeRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    stats = await repo.fetch_stats()
    me = await repo.fetch_completion_materials(profile_id)
    return {
        "delivered_cards": stats["delivered_cards"],
        "signups": stats["signups"],
        "conversations_started": stats["conversations_started"],
        "campuses": stats["campuses"],
        "profile_completion_percent": completion_percent(
            # embed count 는 [{"count": n}] 모양이다.
            photo_count=me["profile_photos"][0]["count"],
            mbti=me["mbti"],
            preferred_height_min=me["preferred_height_min"],
            preferred_height_max=me["preferred_height_max"],
            interest_tags=me["interest_tags"],
        ),
    }
