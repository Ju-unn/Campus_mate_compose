from datetime import datetime

from fastapi import APIRouter, Depends

from app.core.deps import Caller, get_now, get_verified_caller
from app.me.repository import MeRepository
from app.profile_onboarding.router import avatar_url
from app.profile_onboarding.storage import ProfilePhotoStorage

router = APIRouter()

# 실사진 서명 URL 의 유효 시간. 채팅방(chat/router.py)과 같은 1시간이다.
PHOTO_URL_TTL_SECONDS = 3600


def _latest_avatar_url(profile: dict, supabase_url: str) -> str | None:
    # 채팅방 _avatar_url 과 같은 규칙 — ready 중 가장 늦게 만든 한 장, 없으면 None.
    ready = [a for a in profile["profile_avatars"] if a["status"] == "ready"]
    latest = max(ready, key=lambda a: a["created_at"], default=None)
    return avatar_url(supabase_url, latest["storage_path"]) if latest else None


@router.get("/me/profile")
async def get_my_profile(
    caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now),
) -> dict:
    """화면 15 내 프로필. 인증 전 게이트는 기존 /me/verification-status 가 맡고, 이 API 는 관문을
    통과한 사람만 닿으니 화면 15 배지는 늘 '인증 완료'다 — 그래서 인증 상태는 싣지 않는다."""
    settings, client, profile_id = caller
    key = settings.supabase_service_role_key
    profile = await MeRepository(settings.postgrest_url, key, client).fetch_profile(profile_id)
    photos = ProfilePhotoStorage(settings.storage_url, key, client)

    # embed 순서는 PostgREST 가 보장하지 않는다 — 대표 사진(0번)부터 여기서 줄 세운다.
    ordered = sorted(profile["profile_photos"], key=lambda p: p["position"])
    # 인증 관문은 온보딩 완료를 보지 않으니 출생연도가 아직 비었을 수 있다 — 그때 나이는 null.
    birth_year = profile["birth_year"]
    return {
        "nickname": profile["nickname"],
        # 화면은 "늑대, 24" 처럼 쓴다(pen `xew8J`). 조각 2 와 같은 계산식을 쓴다.
        "age": now.year - birth_year + 1 if birth_year is not None else None,
        "university": profile["universities"]["name"],
        "major": profile["major"],
        "height_cm": profile["height_cm"],
        "mbti": profile["mbti"],
        "avatar_url": _latest_avatar_url(profile, settings.supabase_url),
        "photo_urls": [
            await photos.create_signed_url(p["storage_path"], PHOTO_URL_TTL_SECONDS) for p in ordered
        ],
        "preferred_age_min": profile["preferred_age_min"],
        "preferred_age_max": profile["preferred_age_max"],
        "preferred_height_min": profile["preferred_height_min"],
        "preferred_height_max": profile["preferred_height_max"],
        "bio": profile["bio"],
    }
