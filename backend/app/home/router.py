import asyncio
import logging
import random
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from app.cards.paid_preview import cached_preview
from app.cards.repository import CardRepository
from app.core.deps import Caller, get_verified_caller
from app.home.completion import completion_percent
from app.home.repository import HomeRepository
from app.profile_onboarding.storage import AvatarStorage
from app.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter()

# 레일 사람 칸(pen `O5FCD9`) 크기 그대로. 흐린 그림이라 기기 배율만큼 키워 그려도 잃는 것이 없다.
HOME_PEOPLE_SIZE = (112, 140)
# 블러 반경(픽셀, 가우스 표준편차). 머리색 · 옷 색 · 몸 형태는 남고 눈 · 코 · 입 · 안경과 얼굴 윤곽은 뭉개져 누구인지
# 알아보기 어려운 "중간" 강도다. 유료 카드는 8×10 칸에 반경 1칸이라 이 크기로 치면 약 14px — 그 절반 남짓이다.
# 2026-10-15 그림 예시(example-illust-a)로 3 · 5 · 6 · 8 · 10 을 견줘 골랐다: 6 이하는 얼굴 생김이 어렴풋이 남고,
# 10 은 머리와 얼굴의 경계까지 사라진다. 서버 배포만으로 바꿀 수 있게 이 한 곳에만 둔다.
HOME_PEOPLE_BLUR_RADIUS = 8
# 최근 활동 상위 몇 명 안에서(모든 학교 · 성별 섞어서) 몇 명을 무작위로 보이나.
HOME_PEOPLE_POOL = 60
HOME_PEOPLE_COUNT = 12
# 이보다 적으면 빈 목록이다 — 사람이 적으면 흐린 얼굴도 누구인지 짐작된다. 앱은 레일을 숨기지 않고 마스코트 칸으로 대신한다.
# 5명(사용자 결정 2026-10-16, 종전 10명). 후보 수로 센다 — 후보가 5명이 넘어도 사진 몇 장을 못 만들면 5장보다 적게 나갈 수
# 있다(남은 사진은 그대로 준다).
HOME_PEOPLE_MIN = 5


def _store_rating(settings: Settings) -> dict:
    """review-strip 의 실제 스토어 평점 · 평가 수(env `STORE_RATING` · `STORE_RATING_COUNT`). 하나라도 어긋나면 둘 다 0 —
    앱은 평가 수 0 이면 띠를 숨긴다(가짜 숫자를 보이지 않는다)."""
    none = {"store_rating": 0.0, "store_rating_count": 0}
    try:
        rating, count = float(settings.store_rating), int(settings.store_rating_count)
    except ValueError:
        return none
    # `0 <= rating` 이 NaN 도 거른다. 스토어 별점은 1~5 라 평가가 있는데 1 미만이면 평점을 빠뜨린 설정이다.
    if count < 0 or not 0 <= rating <= 5 or (count > 0 and rating < 1):
        return none
    return {"store_rating": rating, "store_rating_count": count}


def get_rng() -> random.Random:
    """레일에 보일 사람을 고르는 난수 발생기. 시험은 시드를 고정한 발생기를 끼운다."""
    return random.Random()


def _shown_avatar_path(profile: dict) -> str | None:
    """지금 쓰는 아바타(ready 중 최신, chat latest_avatar_path 와 같은 규칙)의 경로. 그게 기본 그림(is_fallback)이면
    None — 옛 아바타가 있어도 이제 안 쓰는 얼굴은 꺼내지 않는다."""
    ready = [a for a in profile.get("profile_avatars") or [] if a["status"] == "ready"]
    latest = max(ready, key=lambda a: a["created_at"], default=None)
    return latest["storage_path"] if latest and not latest["is_fallback"] else None


@router.get("/home/people")
async def get_home_people(caller: Caller = Depends(get_verified_caller),
                          rng: random.Random = Depends(get_rng)) -> dict:
    """mosaic-rail 사람 칸. 실제 가입자 아바타를 서버가 받아 흐리게 줄인 JPEG(base64)만 싣는다 — id · 경로 · 공개 주소 ·
    닉네임 · 학교 · 성별은 싣지 않는다(공개 저장소 주소에 profile_id 가 있다). summary 와 따로 둔다: 캐시가 빈 인스턴스가
    원본을 받아 흐리는 동안 summary 가 늦어지지 않고, 여기가 실패해도 다른 블록은 그려진다."""
    settings, client, profile_id = caller
    me = str(profile_id)
    key = settings.supabase_service_role_key
    home = HomeRepository(settings.postgrest_url, key, client)
    cards = CardRepository(settings.postgrest_url, key, client)
    paths = {row["id"]: path for row in await home.fetch_recent_people(profile_id, HOME_PEOPLE_POOL)
             if (path := _shown_avatar_path(row))}
    # 카드와 같은 차단 규칙 — 일반 차단 양방향 + 지인 차단 양방향. 지인을 막아 둔 사람의 얼굴이 그 지인 홈에 뜨면 안 된다.
    # 둘 다 후보 id 로만 묻는다 — 내 차단 전부를 읽으면 1000줄에서 잘린다.
    others = list(paths)
    blocked = await home.fetch_blocked_among(profile_id, others) \
        | await cards.fetch_contact_block_partner_ids(me, others)
    candidates = [path for person, path in paths.items() if person not in blocked]
    if len(candidates) < HOME_PEOPLE_MIN:
        return {"people": []}

    storage = AvatarStorage(settings.storage_url, key, client)
    picked = rng.sample(candidates, min(HOME_PEOPLE_COUNT, len(candidates)))
    # 처음 한 번만 원본을 받는다(경로별 캐시). 동시에 받고, 못 받거나 못 읽은 사람만 건너뛴다.
    results = await asyncio.gather(
        *(cached_preview(storage, path, HOME_PEOPLE_SIZE, HOME_PEOPLE_BLUR_RADIUS) for path in picked),
        return_exceptions=True,
    )
    people = [result for result in results if isinstance(result, str)]
    if len(people) < len(picked):
        # 개수만 남긴다 — 예외 문구에는 저장소 주소(경로 = profile_id)가 들어 있다(COMMON §3).
        logger.warning("홈 레일 흐린 사진 %d/%d 장을 못 만들어 건너뛰었다", len(picked) - len(people), len(picked))
    return {"people": people}


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
        **_store_rating(settings),
    }
