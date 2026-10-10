import logging
from datetime import datetime, timedelta

from app.notifications.repository import NotificationRepository

logger = logging.getLogger(__name__)

# 설계 §8-4: 알림함은 90일 보관한다.
RETENTION_DAYS = 90


async def purge_expired(repo: NotificationRepository, now: datetime) -> int:
    """90일 지난 알림을 지우고 지운 줄 수를 돌려준다. 매시 chat-gate 배치가 한 번 부른다.
    실패해도 배치는 계속 가야 하므로 로그만 남기고 0 을 돌려준다 — 다음 시각이 다시 지운다."""
    try:
        return await repo.delete_older_than(now - timedelta(days=RETENTION_DAYS))
    except Exception:
        logger.exception("알림함 정리 실패")
        return 0
