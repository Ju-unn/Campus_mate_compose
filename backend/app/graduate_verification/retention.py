"""졸업증명서 사진 보관 한도(결정 D12): 신청 중에도 14일을 넘기지 못하고, 결정(승인 · 반려 · 취소 · 만료)이 나면 바로 지운다.
매시 chat-gate 배치가 부른다. 로그에는 신청 id 만 남긴다 — 사진 경로 · 번호 · 이메일은 쓰지 않는다(COMMON §3).

구조는 student_verification/retention.py 와 같다: 상태를 먼저 닫고 사진을 나중에 지운다 — 삭제가 실패해도 다음 시각이
"결정됐는데 남은 사진"으로 걸려 다시 지운다(사진부터 지우면 대기 행이 영영 만료 대상에서 빠질 수 있다)."""
import logging
from datetime import datetime, timedelta

from app.graduate_verification.repository import GraduateRequestRepository
from app.graduate_verification.storage import GraduateCertStorage

logger = logging.getLogger(__name__)

PENDING_LIMIT = timedelta(days=14)
# ponytail: 한 단계에 100건. 남은 건 다음 시각 배치가 이어서 닫는다.
BATCH_LIMIT = 100


async def purge_graduate_photos(repo: GraduateRequestRepository, storage: GraduateCertStorage,
                                now: datetime) -> dict[str, int]:
    """① 14일 지난 대기 신청을 만료(cancelled · expired)로 닫는다 ② 이미 인증된 사람(학교 메일로 따로 통과)의 대기 신청을
    닫는다(verified_otherwise) ③ 결정이 났는데 사진 경로가 남은 줄의 사진을 지운다. 닫을 때 평문 세 칸도 비운다.
    멱등이고 절대 예외를 내지 않는다 — 한 건 · 한 단계가 실패해도 나머지를 계속하고 다음 시각이 다시 고른다.

    ①②에서 닫은 줄의 사진은 같은 단계에서 바로 지우려 한다(실패하면 ③이 다음에 지운다)."""
    old = await _safe_fetch(repo.fetch_pending_older_than(now - PENDING_LIMIT, BATCH_LIMIT), "만료 대상")
    expired, expired_photos = await _close(repo, storage, now, "expired", old)
    already = await _safe_fetch(repo.fetch_pending_of_verified(BATCH_LIMIT), "인증된 사람의 대기")
    verified, verified_photos = await _close(repo, storage, now, "verified_otherwise", already)
    deleted = expired_photos + verified_photos
    for item in await _safe_fetch(repo.fetch_decided_with_photo(BATCH_LIMIT), "남은 사진"):
        deleted += await delete_photo(repo, storage, item["id"], item["photo_path"])
    return {"photos_deleted": deleted, "pending_expired": expired, "verified_cancelled": verified}


async def _safe_fetch(call, what: str) -> list[dict]:
    try:
        return await call
    except Exception as exc:
        logger.warning("졸업생 인증 %s 조회 실패 %s", what, type(exc).__name__)
        return []


async def _close(repo: GraduateRequestRepository, storage: GraduateCertStorage, now: datetime, reason: str,
                 due: list[dict]) -> tuple[int, int]:
    """(닫은 수, 지운 사진 수). 줄을 먼저 닫고(평문 비움) 사진은 그 다음에 지운다."""
    closed = photos = 0
    for item in due:
        try:
            cancelled = await repo.cancel_pending(item["profile_id"], reason, now)
        except Exception as exc:
            logger.warning("졸업생 인증 신청 닫기 건너뜀 request=%s %s", item["id"], type(exc).__name__)
            continue
        if cancelled is None:  # 그 사이 승인 · 반려 · 취소됐다 — 이미 닫힌 줄이다.
            continue
        closed += 1
        photos += await delete_photo(repo, storage, cancelled["id"], cancelled["photo_path"])
    return closed, photos


async def delete_photo(repo: GraduateRequestRepository, storage: GraduateCertStorage, request_id: str,
                       photo_path: str | None) -> int:
    """결정(취소)된 신청의 사진을 지우고 경로를 비운다. 지웠으면 1. 절대 예외를 내지 않는다 — 실패하면 경로가 남아 다음 배치가 다시 지운다."""
    if photo_path is None:
        return 0
    if not await storage.delete(photo_path):
        logger.warning("졸업생 인증 사진 삭제 실패 — 다음 배치가 다시 지운다 request=%s", request_id)
        return 0
    try:
        await repo.clear_photo_path(request_id)
    except Exception as exc:
        # 사진은 이미 지웠다. 경로가 남으면 다음 배치가 "이미 없음(404 = 지워짐)"으로 한 번 더 지우고 비운다.
        logger.warning("졸업생 인증 사진 경로 비우기 실패 request=%s %s", request_id, type(exc).__name__)
    return 1
