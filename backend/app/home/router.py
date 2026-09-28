import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from app.core.deps import Caller, get_verified_caller
from app.home.completion import completion_percent
from app.home.repository import HomeRepository

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/home/summary")
async def get_home_summary(caller: Caller = Depends(get_verified_caller)) -> dict:
    """홈 09b 메인의 숫자들. 전체 집계는 모두에게 같은 값이라 DB 함수로, 완성도는 내 행이라 따로 읽는다.
    우리 학교가 아직 첫 카드를 안 열었으면 19 대기 화면 값(`cohort`)도 같이 준다."""
    settings, client, profile_id = caller
    repo = HomeRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    # 앱을 열면 늘 부르는 곳이라 여기서 활동 시각을 남긴다 — 이 값이 안 바뀌면 가입 14일 뒤 카드가 끊긴다.
    # 못 남겨도 홈은 그려야 한다. 다음에 열 때 다시 시도된다.
    try:
        await repo.touch_last_active(profile_id)
    except Exception:
        logger.exception("last_active_at 갱신 실패 profile=%s", profile_id)

    stats = await repo.fetch_stats()
    me = await repo.fetch_completion_materials(profile_id)

    # 코호트(19): 학교가 아직 첫 카드를 안 열었으면 앱이 메인 대신 대기 화면을 그린다. null 은 이미 열린 학교다.
    cohort = None
    opens_at = me["universities"]["card_opens_at"]
    if opens_at is not None and datetime.fromisoformat(opens_at) > datetime.now(timezone.utc):
        cohort = {"first_card_at": opens_at, "recruit_count": await repo.count_recruits(me["university_id"])}

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
        "cohort": cohort,
    }
