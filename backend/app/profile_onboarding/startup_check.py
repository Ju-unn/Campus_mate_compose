"""서버 시작 때 기본 아바타 원본이 버킷에 있는지 본다(결함 D-02).

없으면 5번째 아바타 실패 보상이 복사에서 멈춘다(storage.py `copy_fallback_avatar`). 알리는 것만 하고
**부팅을 막지 않는다** — 이 파일이 없어도 가입 말고는 멀쩡해서, 막으면 배포 하나가 서비스 전체를 내린다.
"""
import asyncio
import logging

import httpx

from app.profile_onboarding.storage import _FALLBACK_AVATAR_SOURCE_PATH, AvatarStorage
from app.settings import Settings
from app.student_verification.discord_notifier import DiscordNotifier

_logger = logging.getLogger(__name__)

# 부팅이 이 확인 때문에 늦어지는 상한. Cloud Run 시작 프로브 안에서 끝나야 한다.
CHECK_TIMEOUT_SECONDS = 5.0


async def warn_if_fallback_avatar_missing(settings: Settings, client: httpx.AsyncClient) -> None:
    """어떤 실패든 밖으로 내지 않는다. 읽기 실패는 "없다"가 아니라서 로그 경고만 한다(거짓 경보 방지)."""
    try:
        await asyncio.wait_for(_check(settings, client), timeout=CHECK_TIMEOUT_SECONDS)
    except Exception:
        _logger.warning("기본 아바타 원본 확인을 못 했다 — 서버는 그대로 뜬다", exc_info=True)


async def _check(settings: Settings, client: httpx.AsyncClient) -> None:
    storage = AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client)
    if await storage.fallback_exists():
        return
    _logger.error(
        "기본 아바타 원본이 없다 — avatars/%s 를 올려야 5번째 아바타 실패 보상이 된다(DEPLOY.md §4-2)",
        _FALLBACK_AVATAR_SOURCE_PATH,
    )
    try:
        await DiscordNotifier(settings.discord_webhook_url, client).notify_missing_fallback_avatar(
            _FALLBACK_AVATAR_SOURCE_PATH
        )
    except Exception:
        _logger.warning("기본 아바타 원본 없음 Discord 알림 실패", exc_info=True)
