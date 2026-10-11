"""학생증 사진 보관 한도(사용자 결정 2026-10-11): 사람이 재검토해 확정한 사진은 서버가 바로 지우고,
검토 대기는 30일을 넘기지 못한다. 매시 chat-gate 배치가 부른다. 로그에는 시도 id 만 남긴다 — 사진 경로 · 이름은 쓰지 않는다."""
import logging
from datetime import datetime, timedelta

from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.storage import StudentIdStorage

logger = logging.getLogger(__name__)

PENDING_LIMIT = timedelta(days=30)
# 앱 3b 배너가 그대로 보여 주는 문장이고, 검토 결과 훅이 "기한 만료 반려"를 알아보는 표식이다.
EXPIRED_REASON = "검토 기한이 지나 사진을 삭제했어요. 학생증을 다시 올려 주세요"
# ponytail: 한 번에 100명. 남은 사람은 다음 시각 배치가 이어서 닫는다.
EXPIRE_LIMIT = 100


async def purge_student_id_photos(repo: StudentVerificationRepository, storage: StudentIdStorage,
                                  now: datetime) -> dict[str, int]:
    """① 30일 지난 검토 대기를 반려(사유: 기한 만료)로 닫고 사진을 지운다 ② 검토가 끝났는데 버킷에 남은 사진을 지운다.
    멱등이고 절대 예외를 내지 않는다 — 한 사람 · 한 단계가 실패해도 나머지를 계속하고 다음 시각이 다시 고른다.

    ①이 ②보다 먼저다. 상태를 먼저 닫고 사진을 나중에 지우므로, 삭제가 실패해도 ②가 다음에 치운다
    (사진부터 지우면 대기 행이 영영 만료 대상에서 빠질 수 있다)."""
    expired = photos_deleted = 0
    try:
        due = await repo.fetch_pending_attempts_submitted_by(now - PENDING_LIMIT, EXPIRE_LIMIT)
    except Exception as exc:
        logger.warning("학생증 기한 만료 목록 조회 실패 %s", type(exc).__name__)
        due = []
    for attempt in due:
        try:
            await _close_attempt_and_profile(repo, attempt, now)
        except Exception as exc:
            logger.warning("학생증 기한 만료 건너뜀 attempt=%s %s", attempt["id"], type(exc).__name__)
            continue
        expired += 1
        photos_deleted += await _delete_photo(storage, attempt["id"], attempt["file_path"])

    try:
        leftovers = await storage.list_paths()
    except Exception as exc:
        logger.warning("학생증 버킷 목록 조회 실패 %s", type(exc).__name__)
        leftovers = []
    for path in leftovers:
        try:
            attempt = await repo.fetch_attempt_by_path(path)
        except Exception as exc:
            logger.warning("학생증 시도 조회 실패 %s", type(exc).__name__)
            continue
        # 시도 행이 없으면 방금 올려 아직 기록 전일 수 있다 — 대기 중이면 ①이 30일에 맡는다.
        if attempt is not None and attempt["result"] in ("verified", "rejected"):
            photos_deleted += await _delete_photo(storage, attempt["id"], path)
    return {"photos_deleted": photos_deleted, "pending_expired": expired}


async def _close_attempt_and_profile(repo: StudentVerificationRepository, attempt: dict, now: datetime) -> None:
    """시도를 먼저 닫고 프로필을 나중에 바꾼다 — 프로필이 바뀌는 순간 DB 트리거가 검토 결과 훅을 불러
    훅이 시도의 만료 사유를 읽어 알림 문구를 고른다. 프로필을 못 바꾸거나 최근 시도를 못 읽으면 시도를 되돌려 대기에 갇히지 않게 한다."""
    await repo.close_attempt(attempt["id"], EXPIRED_REASON, now)
    try:
        # 프로필은 가장 최근 시도를 따라간다 — 새로 낸 시도가 심사를 기다리면 옛 시도만 닫고 프로필은 둔다.
        latest = await repo.fetch_latest_attempt(attempt["profile_id"])
        if latest is None or latest["id"] == attempt["id"]:
            await repo.reject_profile_if_pending(attempt["profile_id"])
    except Exception:
        try:
            await repo.reopen_attempt(attempt["id"])
        except Exception as exc:
            logger.error("학생증 기한 만료 되돌리기 실패 attempt=%s %s", attempt["id"], type(exc).__name__)
        raise


async def _delete_photo(storage: StudentIdStorage, attempt_id: int, path: str) -> int:
    if await storage.delete(path):
        return 1
    logger.warning("학생증 사진 삭제 실패 — 다음 배치가 다시 지운다 attempt=%s", attempt_id)
    return 0
