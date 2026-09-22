from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator

from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository
from app.chat import gate
from app.chat.repository import MESSAGE_MAX_LENGTH, MESSAGE_PAGE_SIZE, ChatRepository
from app.core import errors
from app.core.deps import Caller, get_client, get_settings, get_verified_caller
from app.core.time import SEOUL
from app.profile_onboarding.storage import ProfilePhotoStorage
from app.settings import Settings

router = APIRouter()

# 상대가 그 방을 보고 있으면 메시지 푸시를 보내지 않는다(결정 5). "보고 있다" 는 판정은
# 상대의 last_read_at 이 방금인지로 한다 — 방에 들어올 때 갱신되므로 추가 상태가 필요 없다.
# ponytail: 30초는 눈대중이다. 정확히 하려면 presence 가 필요하다(백로그).
IN_ROOM_WINDOW = timedelta(seconds=30)
# 푸시 본문에 싣는 메시지 앞부분. 잠금화면에 대화 내용이 통째로 뜨지 않게 자른다.
PUSH_PREVIEW_LENGTH = 40
# 실사진 서명 URL 의 유효 시간. 화면을 열어 둔 동안만 살아 있으면 된다.
PHOTO_URL_TTL_SECONDS = 3600


class MessageRequest(BaseModel):
    body: str = Field(min_length=1, max_length=MESSAGE_MAX_LENGTH)

    @field_validator("body")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("빈 메시지는 보낼 수 없다")
        return stripped


class _Wiring:
    """공통 배선(core/deps 의 Caller) 위에 채팅 저장소·푸시 발송기·사진 보관소를 얹은 것.

    `push_repo` 가 따로 있는 이유: `notify()` 는 알림 스위치와 기기 토큰만 읽는데 그 두 테이블은
    조각 4 의 `CardRepository` 가 이미 들고 있다. 같은 메서드를 채팅 저장소에 한 벌 더 만드는 것보다
    그대로 넘기는 편이 짧다."""

    def __init__(self, settings: Settings, profile_id: str, repo: ChatRepository,
                 push_repo: CardRepository, sender: FcmSender, photos: ProfilePhotoStorage):
        self.settings = settings
        self.profile_id = profile_id
        self.repo = repo
        self.push_repo = push_repo
        self.sender = sender
        self.photos = photos


def get_sender(
    settings: Settings = Depends(get_settings), client: httpx.AsyncClient = Depends(get_client)
) -> FcmSender:
    """푸시 발송기. 테스트는 이 자리에 목 자격증명을 쓰는 발송기를 끼운다."""
    return FcmSender(settings.google_cloud_project, client)


async def _wire(
    caller: Caller = Depends(get_verified_caller), sender: FcmSender = Depends(get_sender)
) -> _Wiring:
    settings, client, profile_id = caller
    key = settings.supabase_service_role_key
    repo = ChatRepository(settings.postgrest_url, key, client)
    push_repo = CardRepository(settings.postgrest_url, key, client)
    photos = ProfilePhotoStorage(settings.storage_url, key, client)
    # profile_id 는 PostgREST 에서 문자열로 오니 비교가 되게 str 로 맞춘다.
    return _Wiring(settings, str(profile_id), repo, push_repo, sender, photos)


def _avatar_url(profile: dict, supabase_url: str) -> str | None:
    avatars = [a for a in profile.get("profile_avatars", []) if a["status"] == "ready"]
    latest = max(avatars, key=lambda a: a["created_at"], default=None)
    return f"{supabase_url}/storage/v1/object/public/avatars/{latest['storage_path']}" if latest else None


def _sides(match: dict, profile_id: str) -> tuple[dict, dict]:
    """(내 참가자 행, 상대 참가자 행). 매칭은 항상 두 행이라 한쪽이 없으면 데이터가 깨진 것이다."""
    mine = next((p for p in match["match_participants"] if p["profile_id"] == profile_id), None)
    partner = next((p for p in match["match_participants"] if p["profile_id"] != profile_id), None)
    if mine is None or partner is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)
    return mine, partner


def _guard_writable(match: dict, mine: dict, partner: dict) -> None:
    """글을 남길 수 있는 방인지. 보내기와 게이트 수락이 같은 문을 쓴다."""
    if match["chat_closed_at"]:
        raise HTTPException(status_code=409, detail=errors.CHAT_CLOSED)
    if mine["left_at"]:
        raise HTTPException(status_code=409, detail=errors.CHAT_LEFT)
    if partner["left_at"]:
        # 결정 7: 상대가 나가면 입력창이 잠긴다. 대화는 읽을 수 있지만 더 쓰지는 못한다.
        raise HTTPException(status_code=409, detail=errors.CHAT_PARTNER_LEFT)


def _gate_state(match: dict, mine: dict, partner: dict, now: datetime) -> dict:
    """화면 14f 시트·14g·14h 배너·미리 수락 배너가 고를 재료. 시각은 서버가 계산해 내려보낸다."""
    created_at = datetime.fromisoformat(match["created_at"])
    return {
        "my_response": mine["trust_response"],
        "passed": bool(match["trust_passed_at"]),
        "partner_left": bool(partner["left_at"]),
        "deadline_at": gate.deadline_at(created_at).isoformat(),
        "remaining_seconds": max(0, int(gate.remaining(created_at, now).total_seconds())),
    }


async def _notify_message(wiring: _Wiring, partner: dict, title: str, body: str,
                          match_id: str, now: datetime) -> None:
    """새 메시지 알림(결정 5). 상대가 그 방을 보고 있으면 보내지 않는다."""
    last_read_at = partner["last_read_at"]
    if last_read_at and datetime.fromisoformat(last_read_at) > now - IN_ROOM_WINDOW:
        return
    await notify(wiring.push_repo, wiring.sender, partner["profile_id"], "new_message", title, body,
                 {"route": "chat", "match_id": str(match_id)}, now=now)


@router.get("/chat/conversations")
async def get_conversations(wiring: _Wiring = Depends(_wire)) -> dict:
    """대화 중 목록(화면 13). 최근 이야기한 방이 위로 온다.

    ponytail: 방마다 상대 프로필·마지막 줄·안 읽은 수를 따로 읽는 N+1 이다. 한 사람의 대화가
    수십 개를 넘지 않는 동안은 이게 제일 단순하고, 수백 개가 되면 RPC 하나로 접는다(백로그)."""
    now = datetime.now(SEOUL)

    conversations = []
    for row in await wiring.repo.fetch_conversations(wiring.profile_id):
        match = row["matches"]
        partner_id = match["profile_b"] if match["profile_a"] == wiring.profile_id else match["profile_a"]
        profile = await wiring.repo.fetch_partner_profile(partner_id)
        last = await wiring.repo.fetch_last_message(match["id"])
        created_at = datetime.fromisoformat(match["created_at"])
        conversations.append({
            "match_id": match["id"],
            "partner": {
                "profile_id": partner_id,
                "nickname": profile.get("nickname"),
                "avatar_url": _avatar_url(profile, wiring.settings.supabase_url),
            },
            "last_message": last["body"] if last else None,
            "last_message_kind": last["kind"] if last else None,
            "last_message_at": last["created_at"] if last else match["created_at"],
            "unread_count": await wiring.repo.count_unread(
                match["id"], wiring.profile_id, row["last_read_at"]
            ),
            "trust_passed": bool(match["trust_passed_at"]),
            "my_trust_response": row["trust_response"],
            "remaining_seconds": max(0, int(gate.remaining(created_at, now).total_seconds())),
        })

    conversations.sort(key=lambda c: c["last_message_at"], reverse=True)
    return {"conversations": conversations}


@router.get("/chat/matches/{match_id}")
async def get_chat_room(match_id: str, wiring: _Wiring = Depends(_wire)) -> dict:
    """방 머리말(화면 14). 게이트를 통과한 뒤에만 카카오톡 아이디와 실사진이 응답에 담긴다."""
    now = datetime.now(SEOUL)

    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)
    mine, partner = _sides(match, wiring.profile_id)
    if mine["left_at"]:
        # 나간 사람에게는 방이 없는 것과 같다(RLS 도 같은 판단을 한다).
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)

    profile = await wiring.repo.fetch_partner_profile(partner["profile_id"])
    room = {
        "match_id": match["id"],
        "created_at": match["created_at"],
        "chat_closed_at": match["chat_closed_at"],
        "my_last_read_at": mine["last_read_at"],
        "partner": {
            "profile_id": partner["profile_id"],
            "nickname": profile.get("nickname"),
            "avatar_url": _avatar_url(profile, wiring.settings.supabase_url),
        },
        "gate": _gate_state(match, mine, partner, now),
    }
    if match["trust_passed_at"]:
        # 여기까지 와야 연락처와 실사진이 나간다(설계 §2.5). 통과 전에는 키 자체가 응답에 없다.
        room["kakao_id"] = await wiring.repo.fetch_kakao_id(partner["profile_id"])
        room["photo_urls"] = [
            await wiring.photos.create_signed_url(path, PHOTO_URL_TTL_SECONDS)
            for path in await wiring.repo.fetch_photo_paths(partner["profile_id"])
        ]
    return room


@router.get("/chat/matches/{match_id}/messages")
async def get_messages(match_id: str, before: datetime | None = None,
                       before_id: str | None = None,
                       # 0 이나 음수를 그대로 PostgREST 에 넘기면 빈 페이지가 돌아와
                       # 앱이 "더 없음" 으로 읽는다. 문 앞에서 막는다.
                       limit: int = Query(default=MESSAGE_PAGE_SIZE, ge=1),
                       wiring: _Wiring = Depends(_wire)) -> dict:
    """최근 50건. 위로 올리면 **화면에 있는 가장 오래된 줄의 `created_at` 과 `id` 를 그대로**
    `before` · `before_id` 로 보내 50건씩 더 가져간다(결정 9).

    시각만 보내도 동작하지만, 같은 시각에 들어간 두 줄이 있으면 경계에서 한 줄이 빠진다 —
    앱은 둘 다 보낸다."""
    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)
    mine, _ = _sides(match, wiring.profile_id)
    if mine["left_at"]:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)

    page_size = min(limit, MESSAGE_PAGE_SIZE)
    messages = await wiring.repo.fetch_messages(
        match_id, before=before, before_id=before_id, limit=page_size
    )
    return {"messages": messages, "has_more": len(messages) == page_size}


@router.post("/chat/matches/{match_id}/messages", status_code=201)
async def send_message(match_id: str, body: MessageRequest,
                       wiring: _Wiring = Depends(_wire)) -> dict:
    """보내기. 저장이 먼저고 푸시가 나중이다 — 푸시가 실패해도 메시지는 남는다."""
    now = datetime.now(SEOUL)

    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)
    mine, partner = _sides(match, wiring.profile_id)
    _guard_writable(match, mine, partner)

    message = await wiring.repo.insert_message(match_id, wiring.profile_id, body.body)
    nickname = await wiring.repo.fetch_nickname(wiring.profile_id)
    preview = body.body.replace("\n", " ")[:PUSH_PREVIEW_LENGTH]
    await _notify_message(wiring, partner, nickname, preview, match_id, now)
    return {"message": message}


@router.patch("/chat/matches/{match_id}/read")
async def mark_read(match_id: str, wiring: _Wiring = Depends(_wire)) -> dict:
    """방에 들어올 때와 나갈 때 한 번씩 부른다(ERD §4). 상대에게 보이는 읽음 표시는 없다."""
    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)

    await wiring.repo.touch_read(match_id, wiring.profile_id, datetime.now(SEOUL))
    return {"ok": True}


@router.post("/chat/matches/{match_id}/leave")
async def leave_chat(match_id: str, wiring: _Wiring = Depends(_wire)) -> dict:
    """채팅방 나가기. 게이트 거절도 여기로 온다(결정 11) — 서버는 둘을 구분하지 않는다.

    되돌릴 수 없고 상대에게 시스템 줄로 보인다(결정 7)."""
    now = datetime.now(SEOUL)

    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)

    # left_at 을 먼저 찍고 시스템 줄을 나중에 넣는다. 반대로 하면 줄만 남고 나가기가 실패할 수 있다.
    if not await wiring.repo.leave(match_id, wiring.profile_id, now):
        raise HTTPException(status_code=409, detail=errors.CHAT_LEFT)

    nickname = await wiring.repo.fetch_nickname(wiring.profile_id)
    await wiring.repo.insert_message(
        match_id, wiring.profile_id, f"{nickname}님이 채팅방을 나갔어요", kind="left"
    )
    # 푸시는 보내지 않는다 — 나갔다는 소식으로 알림을 울릴 일은 아니다. 다음에 방을 열면 보인다.
    return {"ok": True}


@router.post("/chat/matches/{match_id}/trust")
async def accept_trust_gate(match_id: str, wiring: _Wiring = Depends(_wire)) -> dict:
    """신뢰 확인 수락(화면 14f). **수락 전용이다** — 거절은 /leave 로 간다(결정 11).

    매칭 순간부터 부를 수 있고, 양쪽이 수락하면 48시간을 기다리지 않고 그 자리에서 공개된다(결정 10)."""
    now = datetime.now(SEOUL)

    match = await wiring.repo.fetch_match(match_id, wiring.profile_id)
    if match is None:
        raise HTTPException(status_code=404, detail=errors.CHAT_NOT_FOUND)
    mine, partner = _sides(match, wiring.profile_id)
    _guard_writable(match, mine, partner)
    if gate.remaining(datetime.fromisoformat(match["created_at"]), now).total_seconds() <= 0:
        raise HTTPException(status_code=409, detail=errors.TRUST_DEADLINE_PASSED)
    if not await wiring.repo.save_trust_accept(match_id, wiring.profile_id, now):
        raise HTTPException(status_code=409, detail=errors.TRUST_ALREADY_ANSWERED)

    # **통과 도장이 수락 바로 다음이다.** 사이에 시스템 줄이나 푸시를 끼우면, 그 한 번이 끊겼을 때
    # trust_response=accept 인데 trust_passed_at 은 비어 있는 방이 남는다. 다시 눌러도 409 고
    # 48시간 배치가 그 방을 닫아 버려 되살릴 길이 없다.
    passed = gate.is_passed(["accept", partner["trust_response"]])
    # False 면 같은 순간에 양쪽이 눌러 상대가 먼저 찍은 것이다 — 알림은 찍은 쪽이 보냈다.
    stamped = passed and await wiring.repo.pass_trust_gate(match_id, now)

    nickname = await wiring.repo.fetch_nickname(wiring.profile_id)
    # 수락은 상대에게 보인다(결정 10). 거절만 보이지 않는데, 그 거절은 이제 나가기다(결정 11).
    await wiring.repo.insert_message(
        match_id, wiring.profile_id,
        f"{nickname}님이 카카오톡 아이디·실사진 공개를 수락했어요", kind="trust_accept",
    )
    await _notify_message(wiring, partner, nickname,
                          "카카오톡 아이디·실사진 공개를 수락했어요", match_id, now)

    if not passed:
        return {"passed": False}
    if not stamped:
        return {"passed": True}

    partner_nickname = (await wiring.repo.fetch_partner_profile(partner["profile_id"])).get("nickname")
    for target, other in ((partner["profile_id"], nickname), (wiring.profile_id, partner_nickname)):
        await notify(wiring.push_repo, wiring.sender, target, "match_made",
                     "카카오톡 아이디를 주고받았어요", f"{other} 님의 프로필이 공개됐어요",
                     {"route": "chat", "match_id": str(match_id)}, now=now)
    return {"passed": True, "kakao_id": await wiring.repo.fetch_kakao_id(partner["profile_id"])}
