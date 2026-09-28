import logging
from datetime import datetime, timedelta

from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage

logger = logging.getLogger(__name__)

# 검수가 끝나고 이만큼 지나면 인증샷을 지운다(계획서 D6). 단톡방 캡처에는 다른 학생 이름 · 대화가 찍힌다 —
# 60일이면 운영자가 지난달 캡처와 비교할 수 있다.
PROOF_RETENTION = timedelta(days=60)
# ponytail: 하루 100장(계정 정리 CLEANUP_ACCOUNT_LIMIT 와 같다). 남은 것은 다음 날 이어서 지운다. 경로 비우기가
# id 를 주소(`in.(...)`)에 싣기 때문에 100개 ≈ 3.9KB — 500개면 19KB 로 게이트웨이 주소 한도(8~16KB)를 넘어 같은
# 줄에서 매일 막힌다. 올려야 하면 clear_proof_paths 를 100개씩 나눠 PATCH 한다.
PROOF_CLEANUP_LIMIT = 100


async def purge_reviewed_proofs(repo: HeartTaskRepository, storage: HeartProofStorage, now: datetime) -> int:
    """매일 04:00 `/batch/cleanup` 이 부른다. 지운 개수를 돌려주고, 멱등이다 — 다시 돌리면 0이다.

    파일을 먼저 지우고 경로를 나중에 비운다. 반대 순서면 비운 뒤 삭제가 실패할 때 파일을 다시 찾을 길이 없다.
    파일은 지웠는데 비우기가 실패하면 내일 같은 파일을 다시 지운다(없는 파일 삭제는 오류가 아니다)."""
    try:
        rows = await repo.fetch_expired_proofs(now - PROOF_RETENTION, PROOF_CLEANUP_LIMIT)
        if not rows:
            return 0
        await storage.delete([row["storage_path"] for row in rows])
        await repo.clear_proof_paths([row["id"] for row in rows])
    except Exception as exc:
        # 계정 · 신고 정리를 멈추지 않는다. 내일 다시 고른다. 경로는 로그에 남기지 않는다 — 예외 종류만.
        logger.warning("무료 하트 인증샷 정리 건너뜀 %s", type(exc).__name__)
        return 0
    return len(rows)
