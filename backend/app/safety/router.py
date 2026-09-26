"""조각 6 안전: 신고 · 차단 · 차단 목록(16f).

**차단당한 쪽은 알 수 없다**(설계 §7.2) — 상대에게 보이는 것은 조각 5 나가기와 글자까지 같은 시스템 줄뿐이다.
"""
import logging
from datetime import datetime
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.chat.repository import ChatRepository
from app.chat.router import avatar_url
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller
from app.safety.repository import SafetyRepository

logger = logging.getLogger(__name__)

router = APIRouter()


class _Wiring:
    """공통 배선(core/deps 의 Caller) 위에 안전 · 채팅 저장소를 얹은 것."""

    def __init__(self, caller: Caller, now: datetime):
        settings, client, profile_id = caller
        key = settings.supabase_service_role_key
        self.settings = settings
        self.client: httpx.AsyncClient = client
        # PostgREST 가 돌려주는 id 는 문자열이라 비교가 되게 str 로 맞춘다.
        self.profile_id = str(profile_id)
        self.repo = SafetyRepository(settings.postgrest_url, key, client)
        self.chat = ChatRepository(settings.postgrest_url, key, client)
        self.now = now


async def _wire(caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now)) -> _Wiring:
    return _Wiring(caller, now)


async def find_match(chat: ChatRepository, me: str, other: str) -> dict:
    """둘 사이 매칭(지금이든 과거든). 자기 자신이거나 한 번도 매칭된 적 없으면 404.

    매칭 이력으로 막지 않으면 아무나 셋이 모여 임의의 프로필을 신고해 가릴 수 있다(계획서 B1 ①).
    403 이 아니라 404 인 이유: 그런 프로필이 있다는 사실부터 알려 주지 않는다(편차 ①)."""
    match = None if other == me else await chat.fetch_match_between(me, other)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    return match


async def block_profile(wiring: _Wiring, match: dict, target: str) -> None:
    """차단 한 번. 신고도 이 함수를 그대로 부른다 — 멱등이라 두 번 불러도 안전하다.

    ① blocks 행(이미 있으면 조용히 성공) ② 방이 살아 있고 내가 아직 안 나갔으면 `/leave` 와 **같은 함수로**
    나간다. 방이 이미 닫혔거나 내가 나간 뒤면 ② 를 건너뛴다 — 차단은 방이 아니라 사람에 거는 것이라,
    방 상태로 실패하면 14c 에서 온 차단과 신고가 막힌다. 푸시는 없다(나가기와 같다)."""
    await wiring.repo.insert_block(wiring.profile_id, target)
    mine = next((p for p in match["match_participants"] if p["profile_id"] == wiring.profile_id), None)
    if mine is not None and not mine["left_at"] and not match["chat_closed_at"]:
        await wiring.chat.leave_and_announce(match["id"], wiring.profile_id, wiring.now)


@router.post("/blocks/{profile_id}")
async def block(profile_id: UUID, wiring: _Wiring = Depends(_wire)) -> dict:
    """차단(14c · 채팅 메뉴). 이미 막았어도 200 — 재시도 안전(조각 5 "이미 나간 방" 과 같은 판단)."""
    target = str(profile_id)
    await block_profile(wiring, await find_match(wiring.chat, wiring.profile_id, target), target)
    return {"ok": True}


@router.get("/blocks")
async def list_blocks(wiring: _Wiring = Depends(_wire)) -> dict:
    """차단 목록(16f). 닉네임 · 아바타 · 차단일만 — 실사진도 사유도 없다."""
    return {"blocks": [
        {
            "profile_id": row["blocked_id"],
            "nickname": row["profile"]["nickname"],
            "avatar_url": avatar_url(row["profile"], wiring.settings.supabase_url),
            "blocked_at": row["created_at"],
        }
        for row in await wiring.repo.fetch_blocks(wiring.profile_id)
    ]}


@router.delete("/blocks/{profile_id}")
async def unblock(profile_id: UUID, wiring: _Wiring = Depends(_wire)) -> dict:
    """해제. 없어도 200. **대화는 복구하지 않는다**(16f 문구) — left_at 은 그대로 둔다."""
    await wiring.repo.delete_block(wiring.profile_id, profile_id)
    return {"ok": True}
