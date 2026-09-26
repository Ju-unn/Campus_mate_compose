import hmac
import logging
from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository
from app.chat import gate
from app.chat.repository import ChatRepository
from app.core import errors
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter()


async def run_chat_gate(repo: ChatRepository, push_repo: CardRepository, sender: FcmSender,
                        now: datetime) -> dict:
    """매시 정각(Asia/Seoul)에 도는 게이트 배치. 세 가지만 한다.

    ① 양쪽 다 수락했는데 도장이 빠진 매칭에 trust_passed_at 기록(기한과 상관없이, 백로그 16)
    ② 리마인드 창에 걸렸고 아직 수락하지 않은 사람에게 trust_reminder 푸시
    ③ 48시간을 넘겼고 아직 통과하지 않은 매칭에 chat_closed_at 기록

    셋 다 **한쪽이라도 나간 매칭은 건너뛴다**(결정 7·11). 거절은 곧 나가기라서, 닫아 봐야
    남은 사람의 기록만 목록에서 감춰진다."""
    reminded = 0
    closed = 0
    passed = 0
    for match in await repo.fetch_open_matches():
        participants = match["match_participants"]
        if any(p["left_at"] for p in participants):
            continue

        if gate.is_passed([p["trust_response"] for p in participants]):
            # 양쪽 다 수락했는데 도장이 없는 방은 닫지 않고 찍는다. /trust 가 도장 직전에
            # 끊겼을 때 남는 자국인데, 닫아 버리면 되살릴 길이 없다. 기한 분기보다 먼저 봐야
            # 기한 전 방도 다음 매시 배치에서 바로 열린다(백로그 16). 둘 다 수락했으니 리마인드도 없다.
            if await repo.pass_trust_gate(match["id"], now):
                passed += 1
            continue

        created_at = datetime.fromisoformat(match["created_at"])
        if gate.remaining(created_at, now).total_seconds() <= 0:
            # 닫는다 = chat_closed_at 한 칸을 찍는 것뿐이다. 메시지는 남는다(결정 3·4).
            if await repo.close_chat(match["id"], now):
                closed += 1
            continue

        for participant in participants:
            if not gate.needs_reminder(created_at, now, participant["trust_response"] is not None):
                continue
            try:
                sent = await notify(
                    push_repo, sender, participant["profile_id"], "trust_reminder",
                    "신뢰 확인이 기다리고 있어요", "카카오톡 아이디를 공유할지 정해 주세요",
                    {"route": "chat", "match_id": str(match["id"])}, now=now,
                )
            except Exception:
                # 알림 한 건 때문에 뒷사람 리마인드와 마감까지 멈추는 쪽이 훨씬 나쁘다.
                logger.exception("신뢰 확인 리마인드 실패 match=%s", match["id"])
                continue
            # 알림을 끈 사람은 0 이 돌아온다 — 보낸 사람만 센다.
            reminded += 1 if sent else 0

    return {"reminded": reminded, "closed": closed, "passed": passed}


@router.post("/batch/chat-gate")
async def run_chat_gate_batch(
    x_batch_secret: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> dict:
    """Cloud Scheduler 전용. 카드 배치와 같은 공유 비밀을 쓴다 — 둘 다 우리 스케줄러만 부른다."""
    if not settings.card_batch_secret or not x_batch_secret or not hmac.compare_digest(
        x_batch_secret, settings.card_batch_secret
    ):
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)

    key = settings.supabase_service_role_key
    repo = ChatRepository(settings.postgrest_url, key, client)
    # notify() 가 보는 알림 스위치·기기 토큰은 조각 4 저장소가 들고 있다(router.py 와 같은 이유).
    push_repo = CardRepository(settings.postgrest_url, key, client)
    sender = FcmSender(settings.google_cloud_project, client)
    return await run_chat_gate(repo, push_repo, sender, now=datetime.now(SEOUL))
