"""학생증 검토 결과 알림(결함 A7 · 결정 3). 대시보드에서 profiles.student_verification 을
pending → verified/rejected 로 바꾸면 DB 트리거가 pg_net 으로 이 주소를 부른다.

DB 는 구글 ID 토큰을 만들 수 없어 배치처럼 OIDC 로 지키지 못한다 — Vault 의 공유 비밀을 헤더로 받는다.
본문의 상태는 믿지 않고 profiles 를 다시 읽는다. 비밀이 새도 최악은 "같은 알림 한 번 더" 다.
"""
import hmac
from datetime import datetime
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel

from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository
from app.cards.router import get_sender
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.settings import Settings
from app.student_verification.repository import StudentVerificationRepository

router = APIRouter()

# 반려 사유는 알림에 넣지 않는다 — 대시보드에서 profiles 와 attempts.reject_reason 중 어느 쪽을 먼저 고쳐도
# 순서에 걸리지 않게. 사유는 앱 3b 배너가 보여 준다(대장 10-03 문구 승인).
_MESSAGES = {
    "verified": ("학생 인증이 끝났어요", "학과 정보를 입력하고 시작해 보세요"),
    "rejected": ("학생 인증을 다시 해 주세요", "서류를 확인하지 못했어요. 앱에서 이유를 확인해 주세요"),
}


class ReviewedHook(BaseModel):
    profile_id: UUID


@router.post("/hooks/verification-reviewed")
async def verification_reviewed(
    body: ReviewedHook,
    x_webhook_secret: str = Header(default=""),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    sender: FcmSender = Depends(get_sender),
    now: datetime = Depends(get_now),
) -> dict[str, int]:
    expected = settings.verification_hook_secret
    # 시크릿을 빠뜨린 배포가 열린 문이 되지 않게 빈 설정이면 아무도 통과시키지 않는다(batch_auth 와 같은 규칙).
    if not expected or not hmac.compare_digest(x_webhook_secret.encode(), expected.encode()):
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)

    key = settings.supabase_service_role_key
    gate = await StudentVerificationRepository(settings.postgrest_url, key, client).fetch_gate_status(body.profile_id)
    message = _MESSAGES.get(gate["student_verification"])
    if message is None:
        return {"sent": 0}
    # 알림 스위치 칸이 없어 늘 보낸다. 조용한 시간엔 지금 notify 가 버린다 — B1 보관함이 생기면 아침에 간다(대장 10-03).
    sent = await notify(CardRepository(settings.postgrest_url, key, client), sender, body.profile_id,
                        "verification_result", *message, {"route": "verification"}, now=now)
    return {"sent": sent}
