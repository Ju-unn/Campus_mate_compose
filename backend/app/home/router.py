import asyncio
import logging
import random
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from app.cards.paid_preview import cached_preview
from app.cards.repository import CardRepository
from app.core.deps import Caller, get_verified_caller
from app.home.completion import completion_missing, completion_percent
from app.home.repository import HomeRepository
from app.home.store_ratings import StoreRatings, StoreRatingSettings
from app.profile_onboarding.storage import AvatarStorage
from app.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter()

# 레일 사람 칸(pen `O5FCD9`) 112×140 의 2배. 블러가 없어 칸 크기 그대로면 기기 배율(2~3배)에서 뭉개져 보인다.
# 앱은 112×140 칸에 덮어(cover) 그리므로 레이아웃은 그대로다.
HOME_PEOPLE_SIZE = (224, 280)
# 블러 없음(사용자 결정 2026-10-17 "실제 가입자도 블러 없이 보여준다") — 아바타는 실사진이 아니라 AI 일러스트이고 카드에서도
# 공개된다. 반경 0 이면 줄이기만 한다(Pillow 가 섞지 않고 복사한다). 종전 8. 서버 배포만으로 바꿀 수 있게 이 한 곳에만 둔다.
HOME_PEOPLE_BLUR_RADIUS = 0
# 최근 활동 상위 몇 명 안에서(모든 학교 · 내 성별의 반대 성별만) 몇 명을 무작위로 보이나.
HOME_PEOPLE_POOL = 60
HOME_PEOPLE_COUNT = 12
# 이보다 적으면 빈 목록이다 — 몇 사람만 되풀이되는 레일 대신 앱이 예시 칸(아바타 일러스트 · 마스코트)을 보이는 기준이다.
# 레일을 숨기지는 않는다. 5명(사용자 결정 2026-10-16, 종전 10명 · 블러를 없앤 10-17 뒤에도 그대로). 후보 수로 센다 — 후보가 5명이 넘어도 사진 몇 장을 못 만들면 5장보다 적게 나갈 수
# 있다(남은 사진은 그대로 준다).
HOME_PEOPLE_MIN = 5


# 리뷰 띠의 실제 스토어 별점(home/store_ratings.py) — 프로세스에 하나라 몇 시간 캐시된다. 시험이 바꿔 끼운다.
STORE_RATINGS = StoreRatings()

# 옛 앱(1.0.0 ~ 1.0.2)이 읽는 두 칸은 늘 0 이다(띠가 숨는다). 사람이 env(STORE_RATING · STORE_RATING_COUNT)로 넣던 값은
# 더 읽지 않는다 — 손으로 넣는 숫자의 길을 없앴다(2026-11-16 사용자 「실제 스토어 값만」). 옛 칸은 플랫폼을 몰라
# 아이폰 별점을 안드로이드 옛 앱에 보일 수 있어 실제 값도 싣지 않는다.
_OLD_STORE_RATING = {"store_rating": 0.0, "store_rating_count": 0}


async def _banners(repo: HomeRepository, supabase_url: str) -> list[dict]:
    """홈 배너(홈 v3) — 공개 버킷 home-banners 의 주소로 바꿔 싣는다(아바타 공개 주소와 같은 모양). 못 읽어도 홈은 그려야 해서
    빈 목록으로 내린다. 옛 앱은 모르는 칸이라 읽지 않는다."""
    try:
        rows = await repo.fetch_banners(datetime.now(timezone.utc))
    except Exception:
        # 사람 정보가 없는 표다 — 예외 문구에도 profile_id 가 없다.
        logger.exception("홈 배너를 못 읽어 빈 목록으로 보낸다")
        return []
    return [{"image_url": f"{supabase_url}/storage/v1/object/public/home-banners/{row['image_path']}",
             "alt_text": row["alt_text"]} for row in rows]


def get_rng() -> random.Random:
    """레일에 보일 사람을 고르는 난수 발생기. 시험은 시드를 고정한 발생기를 끼운다."""
    return random.Random()


# 내 성별 → 레일에 보일 성별. 이 두 값만 DB 필터에 들어간다.
_OPPOSITE_GENDER = {"male": "female", "female": "male"}


def _shown_avatar_path(profile: dict) -> str | None:
    """지금 쓰는 아바타(ready 중 최신, chat latest_avatar_path 와 같은 규칙)의 경로. 그게 기본 그림(is_fallback)이면
    None — 옛 아바타가 있어도 이제 안 쓰는 얼굴은 꺼내지 않는다."""
    ready = [a for a in profile.get("profile_avatars") or [] if a["status"] == "ready"]
    latest = max(ready, key=lambda a: a["created_at"], default=None)
    return latest["storage_path"] if latest and not latest["is_fallback"] else None


@router.get("/home/people")
async def get_home_people(caller: Caller = Depends(get_verified_caller),
                          rng: random.Random = Depends(get_rng)) -> dict:
    """mosaic-rail 사람 칸. 내 성별의 반대 성별인 실제 가입자 아바타를 서버가 받아 줄이기만 한 JPEG(base64, 블러 없음)만 싣는다 — id · 경로 ·
    공개 주소 · 닉네임 · 학교 · 성별은 싣지 않는다(공개 저장소 주소에 profile_id 가 있다). summary 와 따로 둔다: 캐시가 빈
    인스턴스가 원본을 받아 줄이는 동안 summary 가 늦어지지 않고, 여기가 실패해도 다른 블록은 그려진다."""
    settings, client, profile_id = caller
    me = str(profile_id)
    key = settings.supabase_service_role_key
    home = HomeRepository(settings.postgrest_url, key, client)
    cards = CardRepository(settings.postgrest_url, key, client)
    # 내 성별의 반대 성별 사람만 보인다(사용자 요청 2026-10-18). 내 성별이 비어 있으면 누구를 보일지 알 수 없어 빈 줄이다.
    shown = _OPPOSITE_GENDER.get(await home.fetch_my_gender(profile_id))
    if shown is None:
        return {"people": []}
    paths = {row["id"]: path for row in await home.fetch_recent_people(profile_id, HOME_PEOPLE_POOL, shown)
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
        logger.warning("홈 레일 사진 %d/%d 장을 못 만들어 건너뛰었다", len(picked) - len(people), len(picked))
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

    # 스토어 별점은 DB 읽기와 겹쳐 받는다(캐시가 비었을 때만 바깥으로 나가고, 길어도 몇 초 안에 끝난다).
    ratings = asyncio.create_task(STORE_RATINGS.get(client, StoreRatingSettings().play_reports_bucket))
    stats = await repo.fetch_stats()
    # 초반엔 작은 숫자가 오히려 휑해 보인다 — 앱이 0 인 칸을 숨기니(셋 다 0 이면 행 전체) 0 으로 내린다. DB 값은 그대로다.
    if stats["signups"] < settings.home_stats_min_signups:
        stats = {**stats, "delivered_cards": 0, "signups": 0, "conversations_started": 0}
    me = await repo.fetch_completion_materials(profile_id)
    materials = {
        # embed count 는 [{"count": n}] 모양이다.
        "photo_count": me["profile_photos"][0]["count"],
        "mbti": me["mbti"],
        "preferred_height_min": me["preferred_height_min"],
        "preferred_height_max": me["preferred_height_max"],
        "interest_tags": me["interest_tags"],
    }

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
        # 퍼센트는 옛 앱이 읽는다(그대로). 새 앱은 안 채운 항목 목록으로 칩을 그린다(2026-11-15).
        "profile_completion_percent": completion_percent(**materials),
        "profile_completion_missing": completion_missing(**materials),
        "cohort": cohort,
        **_OLD_STORE_RATING,
        # 새 앱이 자기 플랫폼 값만 읽는다. count None = 그 스토어가 평가 수를 주지 않는다(안드로이드 보고서).
        "store_ratings": await ratings,
        "banners": await _banners(repo, settings.supabase_url),
    }
