from datetime import datetime, time, timedelta, timezone
from functools import lru_cache

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, field_validator

from app.cards.ladder import next_issue_at
from app.cards.push import FcmSender, notify
from app.cards.repository import NOTIFICATION_DEFAULTS, CardRepository
from app.matching.repository import MatchingRepository
from app.profile_onboarding.schemas import SEOUL
from app.settings import Settings
from app.student_verification.current_user import get_verified_user_id

router = APIRouter()

# 받은 수락은 7일이 지나면 목록에서도, 응답에서도 사라진다(2026-09-21 사용자 확정).
ACCEPTANCE_TTL_DAYS = 7

# 테스트가 실제 Supabase·FCM 대신 목을 주입할 수 있게 하는 훅(조각1b·2·3 라우터와 같은 패턴).
_client_override: httpx.AsyncClient | None = None
_sender_override = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


class DecisionRequest(BaseModel):
    decision: str

    @field_validator("decision")
    @classmethod
    def _known(cls, value: str) -> str:
        if value not in ("accept", "reject"):
            raise ValueError("accept 또는 reject 만 받는다")
        return value


class PushTokenRequest(BaseModel):
    token: str
    platform: str

    @field_validator("platform")
    @classmethod
    def _known(cls, value: str) -> str:
        if value not in ("android", "ios"):
            raise ValueError("device_platform 에 있는 값만 받는다")
        return value


class MatchingPausedRequest(BaseModel):
    paused: bool


class _Wiring:
    """엔드포인트마다 똑같이 반복되는 배선(설정 · 클라이언트 · 본인 확인 · 저장소)을 한 곳에 둔다."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient, profile_id: str,
                 repo: CardRepository, sender: FcmSender):
        self.settings = settings
        self.client = client
        self.profile_id = profile_id
        self.repo = repo
        self.sender = sender


async def _wire(authorization: str | None) -> _Wiring:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)
    repo = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    sender = _sender_override or FcmSender(settings.google_cloud_project, client)
    return _Wiring(settings, client, str(profile_id), repo, sender)


def _card_profile(profile: dict, supabase_url: str, now: datetime) -> dict:
    """카드 앞면에 그릴 것만 고른다 — 실명·연락처·사진 원본은 내려보내지 않는다(설계 §7.1)."""
    avatars = [a for a in profile.get("profile_avatars", []) if a["status"] == "ready"]
    latest = max(avatars, key=lambda a: a["created_at"], default=None)
    return {
        "profile_id": profile["id"],
        "nickname": profile["nickname"],
        # 화면은 "여우비, 23" 처럼 쓴다(pen `eWD7g`). 조각 2 와 같은 계산식을 쓴다.
        "age": now.year - profile["birth_year"] + 1,
        "university": (profile.get("universities") or {}).get("name"),
        "major": profile.get("major"),
        "avatar_url": (
            f"{supabase_url}/storage/v1/object/public/avatars/{latest['storage_path']}"
            if latest else None
        ),
    }


async def _next_issue_at(repo: CardRepository, profile_id: str, now: datetime) -> str | None:
    """다음 지급 시각(화면 11 의 카운트다운 재료). 지역 설정 행이 없으면 알 수 없으니 null 이다."""
    region = await repo.fetch_region_group(profile_id)
    rows = {row["region_group"]: row for row in await repo.fetch_region_settings()}
    row = rows.get(region)
    if row is None:
        return None
    issued = next_issue_at(now, row["issue_weekdays"], time.fromisoformat(row["issue_time"]))
    return issued.isoformat()


@router.get("/cards/today")
async def get_today_cards(authorization: str | None = Header(default=None)) -> dict:
    """오늘의 카드(화면 10 `W0CjO`). 살아 있는 카드가 없으면 빈 목록 + 다음 지급 시각만 내려간다
    (화면 11 `i4VFS` 가 그 상태를 그린다)."""
    wiring = await _wire(authorization)
    now = datetime.now(SEOUL)

    cards = []
    for card in await wiring.repo.fetch_live_cards(wiring.profile_id):
        profile = await wiring.repo.fetch_card_profile(card["target_id"])
        cards.append({
            "card_id": card["id"],
            "source": card["source"],
            "expires_at": card["expires_at"],
            "profile": _card_profile(profile, wiring.settings.supabase_url, now),
        })

    candidate_pool_empty = False
    if not cards:
        # 카드가 있으면 묻지 않는다 — 평소에는 추가 쿼리가 0 이다. 화면 11 과 11b 를 가르는 값이다.
        matching_repo = MatchingRepository(
            wiring.settings.postgrest_url, wiring.settings.supabase_service_role_key, wiring.client
        )
        candidate_pool_empty = not await matching_repo.fetch_candidates(wiring.profile_id)

    return {
        "cards": cards,
        "next_issue_at": await _next_issue_at(wiring.repo, wiring.profile_id, now),
        # 잠금 카드는 하트로 여는 조각 7 물건이라 아직 생기지 않는다 — 계약만 채워 둔다.
        "locked_card_available": False,
        "candidate_pool_empty": candidate_pool_empty,
    }


@router.post("/cards/{card_id}/decision")
async def decide_card(card_id: str, body: DecisionRequest,
                      authorization: str | None = Header(default=None)) -> dict:
    """수락·거절을 남긴다. 저장이 먼저고 알림이 나중이다 — 알림이 실패해도 결정은 남는다."""
    wiring = await _wire(authorization)
    now = datetime.now(SEOUL)

    card = await wiring.repo.fetch_card(card_id)
    if card is None or card["owner_id"] != wiring.profile_id:
        raise HTTPException(status_code=404, detail="카드를 찾을 수 없어요")
    if card["card_decisions"]:
        raise HTTPException(status_code=409, detail="이미 결정한 카드예요")
    if card["expires_at"] and datetime.fromisoformat(card["expires_at"]) <= now:
        raise HTTPException(status_code=409, detail="지난 카드예요")

    await wiring.repo.insert_decision(card_id, body.decision)
    if body.decision == "accept":
        # 거절은 조용히 끝난다 — 상대에게 아무 신호도 보내지 않는다(설계 §2.2).
        me = await wiring.repo.fetch_card_profile(wiring.profile_id)
        await notify(wiring.repo, wiring.sender, card["target_id"], "acceptance_received",
                     "나를 수락한 사람이 있어요", f"{me['nickname']} 님이 대화를 하고 싶어 해요",
                     {"route": "acceptances", "card_id": card_id}, now=now)
    return {"ok": True}


@router.get("/cards/acceptances")
async def get_acceptances(authorization: str | None = Header(default=None)) -> dict:
    """받은 수락함(화면 13 `XCN1f`). 7일이 지난 것은 아예 내려보내지 않는다 —
    앱이 만료를 계산하지 않게 한다(2026-09-21 확정)."""
    wiring = await _wire(authorization)
    now = datetime.now(SEOUL)

    acceptances = []
    for row in await wiring.repo.fetch_pending_acceptances(wiring.profile_id, ACCEPTANCE_TTL_DAYS):
        accepter_id = row["daily_cards"]["owner_id"]
        profile = await wiring.repo.fetch_card_profile(accepter_id)
        decided_at = datetime.fromisoformat(row["decided_at"])
        acceptances.append({
            "card_id": row["card_id"],
            "expires_at": (decided_at + timedelta(days=ACCEPTANCE_TTL_DAYS)).isoformat(),
            "profile": _card_profile(profile, wiring.settings.supabase_url, now),
        })
    return {"acceptances": acceptances}


@router.post("/cards/acceptances/{card_id}")
async def respond_to_acceptance(card_id: str, body: DecisionRequest,
                                authorization: str | None = Header(default=None)) -> dict:
    """받은 수락에 답한다. 내가 수락하면 그 자리에서 매칭이 성사된다(설계 §2.2)."""
    wiring = await _wire(authorization)
    now = datetime.now(SEOUL)

    card = await wiring.repo.fetch_card(card_id)
    accepted = [d for d in (card or {}).get("card_decisions", []) if d["decision"] == "accept"]
    if card is None or card["target_id"] != wiring.profile_id or not accepted:
        raise HTTPException(status_code=404, detail="수락을 찾을 수 없어요")
    if card["acceptance_responses"]:
        raise HTTPException(status_code=409, detail="이미 답한 수락이에요")
    decided_at = datetime.fromisoformat(accepted[0]["decided_at"])
    if decided_at <= now - timedelta(days=ACCEPTANCE_TTL_DAYS):
        raise HTTPException(status_code=410, detail="기한이 지났어요")

    await wiring.repo.insert_acceptance_response(card_id, wiring.profile_id, body.decision)
    if body.decision != "accept":
        return {"matched": False}

    match = await wiring.repo.create_match(card["owner_id"], wiring.profile_id)
    me = await wiring.repo.fetch_card_profile(wiring.profile_id)
    other = await wiring.repo.fetch_card_profile(card["owner_id"])
    # 매칭 성사는 양쪽 모두에게 알린다(화면 12 `UFNSi`).
    await notify(wiring.repo, wiring.sender, card["owner_id"], "match_made", "매칭됐어요!",
                 f"{me['nickname']} 님도 수락했어요",
                 {"route": "match", "match_id": match["id"]}, now=now)
    await notify(wiring.repo, wiring.sender, wiring.profile_id, "match_made", "매칭됐어요!",
                 f"{other['nickname']} 님과 대화를 시작해 보세요",
                 {"route": "match", "match_id": match["id"]}, now=now)
    return {"matched": True, "match_id": match["id"]}


@router.post("/cards/push-tokens")
async def register_push_token(body: PushTokenRequest,
                              authorization: str | None = Header(default=None)) -> dict:
    """앱이 받은 FCM 토큰을 등록한다. 같은 토큰이 다시 오면 주인만 갱신된다(기기 인계)."""
    wiring = await _wire(authorization)
    await wiring.repo.upsert_push_token(body.token, wiring.profile_id, body.platform)
    return {"ok": True}


@router.delete("/cards/push-tokens/{token}")
async def delete_push_token(token: str, authorization: str | None = Header(default=None)) -> dict:
    """로그아웃 때 부른다 — 남의 기기로 알림이 가지 않게 토큰을 지운다."""
    wiring = await _wire(authorization)
    await wiring.repo.delete_push_token(token)
    return {"ok": True}


@router.get("/cards/notification-settings")
async def get_notification_settings(authorization: str | None = Header(default=None)) -> dict:
    """알림 스위치 8개(화면 16d `NMgCa`). 저장한 적이 없으면 기본값이 내려간다."""
    wiring = await _wire(authorization)
    settings = await wiring.repo.fetch_notification_settings(wiring.profile_id)
    return {key: settings.get(key, default) for key, default in NOTIFICATION_DEFAULTS.items()}


@router.patch("/cards/notification-settings")
async def update_notification_settings(body: dict,
                                       authorization: str | None = Header(default=None)) -> dict:
    """바뀐 스위치만 보낸다. 이름을 그대로 컬럼으로 쓰기 때문에 아는 이름만 받는다."""
    unknown = set(body) - set(NOTIFICATION_DEFAULTS)
    if unknown or not all(isinstance(value, bool) for value in body.values()):
        raise HTTPException(status_code=422, detail="알 수 없는 알림 설정이에요")

    wiring = await _wire(authorization)
    fields = dict(body)
    if "marketing" in fields:
        # 동의 시각은 서버가 적는다 — 법적 근거가 되는 값이라 앱이 보낸 시각을 믿지 않는다.
        fields["marketing_consented_at"] = (
            datetime.now(timezone.utc).isoformat() if fields["marketing"] else None
        )
    await wiring.repo.update_notification_settings(wiring.profile_id, **fields)
    return {"ok": True}


@router.patch("/cards/matching-paused")
async def update_matching_paused(body: MatchingPausedRequest,
                                 authorization: str | None = Header(default=None)) -> dict:
    """매칭 활성화 토글(화면 16 `TLrmq`). 끄면 다음 지급부터 카드가 오지도 가지도 않는다."""
    wiring = await _wire(authorization)
    await wiring.repo.set_matching_paused(wiring.profile_id, body.paused)
    return {"ok": True}


# ↓ 아래에 새 `/cards/...` 경로를 두지 않는다. `{card_id}` 가 먼저 먹어 버린다.
@router.get("/cards/{card_id}")
async def get_card_detail(card_id: str,
                          authorization: str | None = Header(default=None)) -> dict:
    """10b 상대 프로필 상세(`TORAs`). 카드 주인에게만 보인다."""
    wiring = await _wire(authorization)
    now = datetime.now(SEOUL)

    card = await wiring.repo.fetch_card(card_id)
    if card is None or card["owner_id"] != wiring.profile_id:
        raise HTTPException(status_code=404, detail="카드를 찾을 수 없어요")

    profile = await wiring.repo.fetch_card_detail_profile(card["target_id"])
    return {
        "card_id": card["id"],
        "profile": _card_profile(profile, wiring.settings.supabase_url, now),
        "survey": await wiring.repo.fetch_survey(card["target_id"]),
        "animal_type": profile.get("animal_type"),
        "impression_type": profile.get("impression_type"),
        "religion": profile.get("religion"),
        "is_smoker": profile.get("is_smoker"),
        "interests": profile.get("interest_tags") or [],
        "my_traits": profile.get("my_traits") or [],
        "ideal_traits": profile.get("ideal_traits") or [],
        "height_cm": profile.get("height_cm"),
        "mbti": profile.get("mbti"),
        "student_number": profile.get("student_number"),
        "bio": profile.get("bio"),
        "ideal_note": profile.get("ideal_note"),
    }
