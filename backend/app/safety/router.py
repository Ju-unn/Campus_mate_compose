"""조각 6 안전: 신고 · 차단 · 차단 목록(16f).

**차단당한 쪽은 알 수 없다**(설계 §7.2) — 상대에게 보이는 것은 조각 5 나가기와 글자까지 같은 시스템 줄뿐이다.
"""
import logging
from datetime import datetime
from typing import Literal
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator, model_validator

from app.cards.repository import CardRepository
from app.cards.router import is_active, profile_detail
from app.chat.repository import ChatRepository
from app.chat.router import avatar_url, latest_avatar_path, revealed_contact
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller
from app.profile_onboarding.storage import ProfilePhotoStorage
from app.safety.discord import ReportNotifier, auto_hidden_line, report_line
from app.safety.reasons import (
    AUTO_HIDE_REPORTERS,
    DAILY_REPORT_LIMIT,
    DAILY_REPORT_WINDOW,
    REASON_LABELS,
    REASON_NOTE_MAX,
)
from app.safety.repository import SafetyRepository

logger = logging.getLogger(__name__)

router = APIRouter()


class ReportRequest(BaseModel):
    # friend_review · poll 은 DB enum 에는 있지만 그 기능이 아직 없다 — 여기서 422 로 막는다.
    target_type: Literal["profile", "message"]
    target_id: UUID
    reason: str
    reason_note: str | None = None

    @field_validator("reason")
    @classmethod
    def _known_reason(cls, value: str) -> str:
        if value not in REASON_LABELS:
            raise ValueError("사유 5개 중 하나만 받는다")
        return value

    @model_validator(mode="after")
    def _note_only_for_other(self) -> "ReportRequest":
        if self.reason != "other":
            # 다른 사유에 딸려 온 글은 버린다(저장하지 않는다) — 422 로 막으면 사유를 바꾼 앱이 남은 글 때문에 실패한다.
            self.reason_note = None
            return self
        note = (self.reason_note or "").strip()
        if not 1 <= len(note) <= REASON_NOTE_MAX:
            raise ValueError(f"기타 사유는 한 줄(1~{REASON_NOTE_MAX}자)이 필요하다")
        self.reason_note = note
        return self


class _Wiring:
    """공통 배선(core/deps 의 Caller) 위에 안전 · 채팅 · 카드 저장소와 실사진 보관소를 얹은 것."""

    def __init__(self, caller: Caller, now: datetime):
        settings, client, profile_id = caller
        key = settings.supabase_service_role_key
        self.settings = settings
        self.client: httpx.AsyncClient = client
        # PostgREST 가 돌려주는 id 는 문자열이라 비교가 되게 str 로 맞춘다.
        self.profile_id = str(profile_id)
        self.repo = SafetyRepository(settings.postgrest_url, key, client)
        self.chat = ChatRepository(settings.postgrest_url, key, client)
        self.cards = CardRepository(settings.postgrest_url, key, client)
        self.photos = ProfilePhotoStorage(settings.storage_url, key, client)
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


async def _message_target(wiring: _Wiring, message_id: UUID) -> tuple[dict, dict]:
    """(말풍선, 그 방의 매칭). 없는 메시지 · 내가 없는 방 · 내가 보낸 것 · 시스템 줄은 전부 같은 404 다.
    방이 닫혔거나 누가 나갔어도 막지 않는다 — 과거 매칭이면 된다."""
    message = await wiring.chat.fetch_message(message_id)
    match = message and await wiring.chat.fetch_match(message["match_id"], wiring.profile_id)
    if not match or message["sender_id"] == wiring.profile_id or message["kind"] != "text":
        raise HTTPException(status_code=404, detail=errors.MESSAGE_NOT_FOUND)
    return message, match


async def _profile_snapshot(wiring: _Wiring, target: str) -> dict:
    """서명 URL 이 아니라 **storage 경로**를 남긴다 — 서명 URL 은 만료돼 검토할 때 열리지 않는다."""
    profile = await wiring.repo.fetch_snapshot_profile(target)
    return {
        "nickname": profile.get("nickname"),
        "bio": profile.get("bio"),
        "avatar_path": latest_avatar_path(profile),
        "photo_paths": await wiring.chat.fetch_photo_paths(target),
    }


@router.post("/reports", status_code=201)
async def report(body: ReportRequest, wiring: _Wiring = Depends(_wire)) -> dict:
    """신고(8d 시트). 신고하면 차단도 같이 된다(결정 4). 처리 순서가 계약이다(계획서 B1)."""
    me = wiring.profile_id

    # ① 대상 확인 + 접근 권한(과거 매칭 상대만)
    if body.target_type == "profile":
        target = str(body.target_id)
        match = await find_match(wiring.chat, me, target)
        message = None
    else:
        message, match = await _message_target(wiring, body.target_id)
        target = message["sender_id"]

    # ② 하루 상한
    since = wiring.now - DAILY_REPORT_WINDOW
    if await wiring.repo.count_recent_reports(me, since, DAILY_REPORT_LIMIT) >= DAILY_REPORT_LIMIT:
        raise HTTPException(status_code=429, detail=errors.REPORT_DAILY_LIMIT)

    # ③ 스냅샷 — 원본이 지워져도 검토 근거가 남아야 한다(애플 1.2, ERD §5).
    snapshot = await _profile_snapshot(wiring, target) if message is None else {
        "message_id": message["id"], "match_id": message["match_id"],
        "body": message["body"], "created_at": message["created_at"],
    }

    # ④ **차단 먼저.** ④⑤ 는 PostgREST 호출 두 번이라 한 트랜잭션이 아니다. 신고를 먼저 넣으면 차단이
    # 실패했을 때 "신고만 되고 차단은 안 된" 채로 갇힌다 — 다시 신고해도 409 라 영영 차단할 길이 없다.
    # 차단은 멱등이라 먼저 해도, 두 번 해도 안전하다. 반대로 차단만 되고 신고가 실패하면 앱이 시트를
    # 닫지 않고 다시 보낸다(차단 뒤에는 방 · 14c · 카드가 사라져 신고 진입점이 없어진다).
    await block_profile(wiring, match, target)

    # ⑤ 신고(중복이면 409 "이미 신고한 사용자예요")
    report_row = {
        "reporter_id": me, "target_type": body.target_type, "target_id": str(body.target_id),
        "target_profile_id": target, "target_snapshot": snapshot, "reason": body.reason,
    }
    if body.reason_note is not None:
        report_row["reason_note"] = body.reason_note
    report_id = await wiring.repo.insert_report(report_row)

    # ⑥ 디스코드 한 줄 — 누적 신고자 수를 싣기 때문에 ⑦ 의 세기를 먼저 한다.
    # 신고 · 차단은 이미 저장됐다. 세기가 실패해 500 이 나면 알림도 사라지고 재시도는 409 라 영영 안 온다 —
    # 수를 "?" 로 보내고 가림은 건너뛴다. 가림은 다음 신고 때 다시 센다.
    try:
        reporters: int | None = await wiring.repo.count_open_reporters(target)
    except Exception:
        logger.exception("신고자 세기 실패 report=%s target=%s", report_id, target)
        reporters = None
    notifier = ReportNotifier(wiring.settings.discord_report_webhook_url, wiring.client)
    await notifier.send(report_line(report_id, target, body.reason, "?" if reporters is None else reporters))

    # ⑦ 서로 다른 신고자 3명이면 자동 가림. 조건부라 이번에 실제로 찍혔을 때만 한 줄 더 보낸다.
    if reporters is not None and reporters >= AUTO_HIDE_REPORTERS \
            and await wiring.repo.auto_hide(target, wiring.now):
        await notifier.send(auto_hidden_line(target))
    return {"ok": True}


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


@router.get("/profiles/{profile_id}")
async def get_partner_profile(profile_id: UUID, wiring: _Wiring = Depends(_wire)) -> dict:
    """14c 상대 프로필. 10b 카드 상세와 같은 몸통에 card_id 대신 match_id, 게이트를 통과했으면 연락처까지.

    404 는 전부 같은 문구다 — 자기 자신 · 매칭 이력 없음 · 내가 나감 · **상대가 나감** · 차단(양방향) ·
    상대가 active 가 아님(정지 · 탈퇴). 상대가 나간 방까지 막는 이유: "나를 차단한 상대"(나간 것처럼 보인다)와
    "그냥 나간 상대"가 14c 에서 갈리면 차단 사실이 샌다(설계 §7.2, 편차 ②).
    상대의 auto_hidden_at 은 막지 않는다 — 자동 가림은 카드에서만 빠진다(결정 3: 진행 중 채팅은 유지)."""
    target = str(profile_id)
    match = await find_match(wiring.chat, wiring.profile_id, target)
    if any(p["left_at"] for p in match["match_participants"]):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    profile = await wiring.cards.fetch_card_detail_profile(target)
    if not is_active(profile) or target in await wiring.cards.fetch_block_partner_ids(wiring.profile_id):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)

    detail = {"match_id": match["id"],
              **await profile_detail(wiring.cards, profile, wiring.settings.supabase_url, wiring.now)}
    if match["trust_passed_at"]:
        detail.update(await revealed_contact(wiring.chat, wiring.photos, target))
    return detail
