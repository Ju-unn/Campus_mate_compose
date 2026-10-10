import random
from datetime import datetime, time, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator

from app.cards.ladder import last_issue_at, next_issue_at
from app.cards.paid_offer import PAID_CARD_COST, ensure_offer, target_eligible
from app.cards.push import FcmSender, notify
from app.cards.repository import NOTIFICATION_DEFAULTS, CardRepository
# is_active 는 safety · friend_reviews 가 여기서 가져간다 — 판정 자체는 visibility 한 곳에 있다.
from app.cards.visibility import hidden_from_cards as _hidden_from_cards
from app.cards.visibility import is_active  # noqa: F401
from app.core import errors
from app.core.deps import Caller, get_caller, get_client, get_now, get_settings, get_verified_caller
from app.matching.band import rank_all
from app.matching.repository import MatchingRepository
from app.settings import Settings

router = APIRouter()

# 받은 수락은 7일이 지나면 목록에서도, 응답에서도 사라진다(2026-09-21 사용자 확정).
ACCEPTANCE_TTL_DAYS = 7


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
    """공통 배선(core/deps 의 Caller) 위에 카드 기능의 저장소·푸시 발송기를 얹은 것."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient, profile_id: str,
                 repo: CardRepository, sender: FcmSender, now: datetime):
        self.settings = settings
        self.client = client
        self.profile_id = profile_id
        self.repo = repo
        self.sender = sender
        # 이 요청의 "지금". 한 요청 안에서 두 번 읽으면 자정을 사이에 두고 갈릴 수 있다.
        self.now = now


def get_sender(
    settings: Settings = Depends(get_settings), client: httpx.AsyncClient = Depends(get_client)
) -> FcmSender:
    """푸시 발송기. 테스트는 이 자리에 목 자격증명을 쓰는 발송기를 끼운다."""
    return FcmSender(settings.google_cloud_project, client)


def get_rng() -> random.Random:
    """유료 카드 제안을 새로 정할 때 쓰는 난수 발생기. 시험은 시드를 고정한 발생기를 끼운다."""
    return random.Random()


def _wiring(caller: Caller, sender: FcmSender, now: datetime) -> _Wiring:
    settings, client, profile_id = caller
    repo = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    # owner_id·target_id 는 PostgREST 에서 문자열로 오니 비교가 되게 str 로 맞춘다.
    return _Wiring(settings, client, str(profile_id), repo, sender, now)


async def _wire(
    caller: Caller = Depends(get_verified_caller), sender: FcmSender = Depends(get_sender),
    now: datetime = Depends(get_now),
) -> _Wiring:
    return _wiring(caller, sender, now)


async def _wire_signed_in(
    caller: Caller = Depends(get_caller), sender: FcmSender = Depends(get_sender),
    now: datetime = Depends(get_now),
) -> _Wiring:
    """학생증 관문 앞에서도 열린다 — 푸시 토큰 등록 · 삭제만 쓴다. 검토를 기다리는 사람이
    토큰이 없으면 검토 결과 알림(결함 A7)을 받을 기기가 없다(대장 10-03 허락, 홈탭1 에 알림)."""
    return _wiring(caller, sender, now)


def _avatar_url(profile: dict, supabase_url: str) -> str | None:
    """가장 최근에 다 만든 아바타의 공개 저장소 주소. 카드 앞면과 유료 카드(흐림은 앱이 한다)가 같이 쓴다."""
    avatars = [a for a in profile.get("profile_avatars") or [] if a["status"] == "ready"]
    latest = max(avatars, key=lambda a: a["created_at"], default=None)
    return f"{supabase_url}/storage/v1/object/public/avatars/{latest['storage_path']}" if latest else None


def _card_profile(profile: dict, supabase_url: str, now: datetime) -> dict:
    """카드 앞면에 그릴 것만 고른다 — 실명·연락처·사진 원본은 내려보내지 않는다(설계 §7.1)."""
    return {
        "profile_id": profile["id"],
        "nickname": profile["nickname"],
        # 화면은 "여우비, 23" 처럼 쓴다(pen `eWD7g`). 조각 2 와 같은 계산식을 쓴다.
        "age": now.year - profile["birth_year"] + 1,
        "university": (profile.get("universities") or {}).get("name"),
        "major": profile.get("major"),
        "avatar_url": _avatar_url(profile, supabase_url),
    }


def _offered_card(offer: dict, target: dict, supabase_url: str) -> dict:
    """유료 카드 앞면(결제 전). 이름 · 닉네임 · 학교 · 나이 · 학과 · MBTI 같은 프로필 칸은 **절대** 넣지 않는다 —
    결제 전에 사람이 드러나면 안 된다. 아바타는 앱이 흐리게 그린다(주소 자체는 공개 저장소 주소다)."""
    return {
        "state": "offered",
        "offer_id": offer["id"],
        "band_count": offer["band_count"],
        "reasons": offer.get("reasons") or [],
        "avatar_url": _avatar_url(target, supabase_url),
        "cost": PAID_CARD_COST,
    }


async def _blocked_among(wiring: _Wiring, others: list[str]) -> set[str]:
    """_hidden_from_cards 의 `blocked` — 차단한 · 차단당한 사람 전부와, others 중 지인 차단으로 이어진 사람(결정 8 ②:
    나중에 지인 차단해도 이미 받은 카드 · 수락이 양쪽에서 바로 사라진다). 요청마다 한 번 읽는다.
    지인 차단은 카드 · 수락에만 건다 — 이미 매칭된 방 · 14c · 지인 리뷰는 일반 차단만 본다."""
    return await wiring.repo.fetch_block_partner_ids(wiring.profile_id) \
        | await wiring.repo.fetch_contact_block_partner_ids(wiring.profile_id, others)


async def _region_row(repo: CardRepository, profile_id: str) -> dict | None:
    """내 지역 설정 행(지급 요일 · 시각). 없으면 다음 지급 시각도 이번 주기도 알 수 없다."""
    region = await repo.fetch_region_group(profile_id)
    rows = {row["region_group"]: row for row in await repo.fetch_region_settings()}
    return rows.get(region)


@router.get("/cards/today")
async def get_today_cards(wiring: _Wiring = Depends(_wire), rng: random.Random = Depends(get_rng)) -> dict:
    """오늘의 카드(화면 10 `W0CjO`). 살아 있는 카드가 없으면 빈 목록 + 다음 지급 시각만 내려간다
    (화면 11 `i4VFS` 가 그 상태를 그린다). 유료 카드 제안은 `paid_card` 로 내려간다(지시문 22 E)."""
    now = wiring.now

    region = await _region_row(wiring.repo, wiring.profile_id)
    issue_time = time.fromisoformat(region["issue_time"]) if region else None
    # 유료 제안의 "이번 주기" = 가장 최근 지급 시각. 지역 설정이 없으면 주기를 몰라 제안도 없다(paid_card null).
    cycle = last_issue_at(now, region["issue_weekdays"], issue_time) if region else None
    offer = None
    if cycle is not None:
        # 지난 주기에 남은 offered 는 여기서 쓰지 않는다 — 아래 ensure_offer 가 expired 로 바꾼다.
        offer = next((o for o in await wiring.repo.fetch_offered(wiring.profile_id)
                      if datetime.fromisoformat(o["cycle_started_at"]) >= cycle), None)

    cards = []
    live = await wiring.repo.fetch_live_cards(wiring.profile_id)
    # 제안 대상도 같은 차단 조회에 넣는다 — 요청마다 차단은 한 번만 읽는다.
    others = [card["target_id"] for card in live] + ([str(offer["target_id"])] if offer else [])
    blocked = await _blocked_among(wiring, others)
    # ponytail: 카드마다 프로필을 읽는 N+1 이다(조각 4 부터). 살아 있는 카드는 몇 장뿐이라 이대로 두고,
    # 수십 장이 되면 target_id in (...) 한 번으로 접는다. 차단은 요청마다 한 번만 읽는다.
    for card in live:
        profile = await wiring.repo.fetch_card_profile(card["target_id"])
        if _hidden_from_cards(card["target_id"], profile, blocked):
            continue
        cards.append({
            "card_id": card["id"],
            "source": card["source"],
            "expires_at": card["expires_at"],
            "profile": _card_profile(profile, wiring.settings.supabase_url, now),
        })
    # 산 카드에는 그 카드를 만든 제안의 맞는 이유를 붙인다. 무료 카드에는 붙이지 않는다.
    bought = [card["card_id"] for card in cards if card["source"] == "purchased"]
    if bought:
        reasons = await wiring.repo.fetch_purchased_reasons(bought)
        for card in cards:
            if card["source"] == "purchased":
                card["reasons"] = reasons.get(card["card_id"], [])

    paid_card = None
    if offer is not None:
        eligible, target = await target_eligible(wiring.repo, wiring.profile_id, str(offer["target_id"]), blocked)
        if eligible:
            # 살아 있는 제안이 있으면 읽기만 한다 — 순위를 다시 매기지 않는다.
            paid_card = _offered_card(offer, target, wiring.settings.supabase_url)

    candidate_pool_empty = False
    if paid_card is None:
        # 이번 주기에 이미 샀으면 paid_card 는 null 이다(산 카드는 cards 목록에 있다).
        may_offer = cycle is not None and not await wiring.repo.has_purchased_since(wiring.profile_id, cycle)
        if not cards or may_offer:
            matching_repo = MatchingRepository(
                wiring.settings.postgrest_url, wiring.settings.supabase_service_role_key, wiring.client
            )
            candidates = await matching_repo.fetch_candidates(wiring.profile_id)
            # 후보에는 이미 본 사람도 들어 있다 — 뽑을 수 있는(pickable) 사람이 없어야 화면 11b 다.
            pool_empty = not any(c["pickable"] for c in candidates)
            # 카드가 있으면 11b 가 아니다 — 지금처럼 카드가 있을 때는 false 다.
            candidate_pool_empty = not cards and pool_empty
            if may_offer and not pool_empty:
                # ponytail: 살아 있는 제안이 없을 때만 여기서 후보 전체 순위를 다시 매긴다(새로 가입한 사람 · 지급
                # 요일이 아닌 날 · 배치가 놓친 날을 메운다). 후보 1,000명 규모면 요청당 rank_all 한 번(수 ms)과 RPC
                # 한 번이고, 주기당 한 번 만들고 나면 위의 읽기 경로로 간다. 병목은 파이썬이 아니라 RPC 한 번과
                # 응답 크기(후보 1,500명 약 650KB)다. 더 커지면 제안 만들기를 배치 전용으로
                # 돌리고 이 자리는 캐시(또는 "준비 중")만 읽게 바꾼다.
                owner_row = await matching_repo.fetch_owner(wiring.profile_id)
                made = await ensure_offer(wiring.repo, owner_row, rank_all(owner_row, candidates), cycle,
                                          rng, now, blocked=blocked)
                if made is None:
                    # 후보는 있는데 상위 20% 구간에 뽑을 사람이 없다 — 구매는 막힌다.
                    paid_card = {"state": "empty"}
                else:
                    target = await wiring.repo.fetch_offer_target(made["target_id"])
                    paid_card = _offered_card(made, target, wiring.settings.supabase_url)

    return {
        "cards": cards,
        # 다음 지급 시각(화면 11 의 카운트다운 재료). 지역 설정 행이 없으면 알 수 없으니 null 이다.
        "next_issue_at": next_issue_at(now, region["issue_weekdays"], issue_time).isoformat() if region else None,
        "paid_card": paid_card,
        # 옛 앱 호환: paid_card 가 offered 일 때만 true.
        "locked_card_available": bool(paid_card and paid_card["state"] == "offered"),
        "candidate_pool_empty": candidate_pool_empty,
    }


@router.post("/cards/{card_id}/decision")
async def decide_card(card_id: str, body: DecisionRequest,
                      wiring: _Wiring = Depends(_wire)) -> dict:
    """수락·거절을 남긴다. 저장이 먼저고 알림이 나중이다 — 알림이 실패해도 결정은 남는다."""
    now = wiring.now

    card = await wiring.repo.fetch_card(card_id)
    if card is None or card["owner_id"] != wiring.profile_id:
        raise HTTPException(status_code=404, detail=errors.CARD_NOT_FOUND)
    target = await wiring.repo.fetch_card_profile(card["target_id"])
    if _hidden_from_cards(card["target_id"], target, await _blocked_among(wiring, [card["target_id"]])):
        raise HTTPException(status_code=404, detail=errors.CARD_NOT_FOUND)
    if card["card_decisions"]:
        raise HTTPException(status_code=409, detail=errors.CARD_ALREADY_DECIDED)
    if card["expires_at"] and datetime.fromisoformat(card["expires_at"]) <= now:
        raise HTTPException(status_code=409, detail=errors.CARD_EXPIRED)

    await wiring.repo.insert_decision(card_id, body.decision)
    if body.decision == "accept":
        # 거절은 조용히 끝난다 — 상대에게 아무 신호도 보내지 않는다(설계 §2.2).
        # 받는 쪽 화면은 "대화 신청하기" · "받은 신청" 이다(지시문 22 G). kind 는 acceptance_received 그대로.
        me = await wiring.repo.fetch_card_profile(wiring.profile_id)
        await notify(wiring.repo, wiring.sender, card["target_id"], "acceptance_received",
                     "대화 신청이 왔어요", f"{me['nickname']} 님이 대화를 신청했어요",
                     {"route": "acceptances", "card_id": card_id}, now=now)
    return {"ok": True}


@router.get("/cards/acceptances")
async def get_acceptances(wiring: _Wiring = Depends(_wire)) -> dict:
    """받은 수락함(화면 13 `XCN1f`). 7일이 지난 것은 아예 내려보내지 않는다 —
    앱이 만료를 계산하지 않게 한다(2026-09-21 확정)."""
    now = wiring.now

    acceptances = []
    pending = await wiring.repo.fetch_pending_acceptances(wiring.profile_id, ACCEPTANCE_TTL_DAYS, now=now)
    blocked = await _blocked_among(wiring, [row["daily_cards"]["owner_id"] for row in pending])
    # 이미 매칭된 상대는 답할 게 없다(결정 11) — 프로필을 읽기 전에 거른다.
    matched = await wiring.repo.fetch_match_partner_ids(wiring.profile_id)
    for row in pending:
        accepter_id = row["daily_cards"]["owner_id"]
        if accepter_id in matched:
            continue
        profile = await wiring.repo.fetch_card_profile(accepter_id)
        if _hidden_from_cards(accepter_id, profile, blocked):
            continue
        decided_at = datetime.fromisoformat(row["decided_at"])
        acceptances.append({
            "card_id": row["card_id"],
            "expires_at": (decided_at + timedelta(days=ACCEPTANCE_TTL_DAYS)).isoformat(),
            "profile": _card_profile(profile, wiring.settings.supabase_url, now),
        })
    return {"acceptances": acceptances}


@router.post("/cards/acceptances/{card_id}")
async def respond_to_acceptance(card_id: str, body: DecisionRequest,
                                wiring: _Wiring = Depends(_wire)) -> dict:
    """받은 수락에 답한다. 내가 수락하면 그 자리에서 매칭이 성사된다(설계 §2.2)."""
    now = wiring.now

    card = await wiring.repo.fetch_card(card_id)
    # 임베드는 객체 하나 아니면 null 이다(카드 한 장당 결정도 응답도 최대 한 건).
    accepted = (card or {}).get("card_decisions") or {}
    if card is None or card["target_id"] != wiring.profile_id or accepted.get("decision") != "accept":
        raise HTTPException(status_code=404, detail=errors.ACCEPTANCE_NOT_FOUND)
    # 이미 받은 수락이라도 그사이 차단 · 정지 · 가림이 됐으면 매칭을 만들지 않는다(통합대장 결정).
    accepter = await wiring.repo.fetch_card_profile(card["owner_id"])
    if _hidden_from_cards(card["owner_id"], accepter, await _blocked_among(wiring, [card["owner_id"]])):
        raise HTTPException(status_code=404, detail=errors.ACCEPTANCE_NOT_FOUND)
    if card["acceptance_responses"]:
        raise HTTPException(status_code=409, detail=errors.ACCEPTANCE_ALREADY_ANSWERED)
    decided_at = datetime.fromisoformat(accepted["decided_at"])
    if decided_at <= now - timedelta(days=ACCEPTANCE_TTL_DAYS):
        raise HTTPException(status_code=410, detail=errors.ACCEPTANCE_EXPIRED)

    await wiring.repo.insert_acceptance_response(card_id, wiring.profile_id, body.decision)
    if body.decision != "accept":
        return {"matched": False}

    match, is_new = await wiring.repo.create_match(card["owner_id"], wiring.profile_id)
    # 매칭 성사는 양쪽 모두에게 알린다(화면 12 `UFNSi`). 다만 신규일 때만이다 —
    # A→B, B→A 카드가 같은 날 나가 둘 다 수락하면 두 번째 수락은 이미 있는 매칭을 다시 본다.
    if is_new:
        me = await wiring.repo.fetch_card_profile(wiring.profile_id)
        # 상대 프로필은 위 숨김 검사에서 이미 읽었다(accepter).
        await notify(wiring.repo, wiring.sender, card["owner_id"], "match_made", "매칭됐어요!",
                     f"{me['nickname']} 님이 신청을 수락했어요.",
                     {"route": "match", "match_id": match["id"]}, now=now)
        # 내 쪽은 방금 화면에서 매칭을 봤다 — 밤이면 아침에 다시 알리지 않고 버린다(대장 10-03).
        await notify(wiring.repo, wiring.sender, wiring.profile_id, "match_made", "매칭됐어요!",
                     f"{accepter['nickname']} 님과 대화를 시작해 보세요",
                     {"route": "match", "match_id": match["id"]}, now=now, defer=False)
    return {"matched": True, "match_id": match["id"]}


@router.post("/cards/push-tokens")
async def register_push_token(body: PushTokenRequest,
                              wiring: _Wiring = Depends(_wire_signed_in)) -> dict:
    """앱이 받은 FCM 토큰을 등록한다. 같은 토큰이 다시 오면 주인만 갱신된다(기기 인계)."""
    await wiring.repo.upsert_push_token(body.token, wiring.profile_id, body.platform)
    return {"ok": True}


@router.delete("/cards/push-tokens/{token}")
async def delete_push_token(token: str, wiring: _Wiring = Depends(_wire_signed_in)) -> dict:
    """로그아웃 때 부른다 — 남의 기기로 알림이 가지 않게 토큰을 지운다."""
    await wiring.repo.delete_push_token(token, wiring.profile_id)
    return {"ok": True}


@router.get("/cards/notification-settings")
async def get_notification_settings(wiring: _Wiring = Depends(_wire)) -> dict:
    """알림 스위치 8개(화면 16d `NMgCa`). 저장한 적이 없으면 기본값이 내려간다."""
    settings = await wiring.repo.fetch_notification_settings(wiring.profile_id)
    return {key: settings.get(key, default) for key, default in NOTIFICATION_DEFAULTS.items()}


@router.patch("/cards/notification-settings")
async def update_notification_settings(body: dict,
                                       wiring: _Wiring = Depends(_wire)) -> dict:
    """바뀐 스위치만 보낸다. 이름을 그대로 컬럼으로 쓰기 때문에 아는 이름만 받는다."""
    unknown = set(body) - set(NOTIFICATION_DEFAULTS)
    if unknown or not all(isinstance(value, bool) for value in body.values()):
        raise HTTPException(status_code=422, detail=errors.UNKNOWN_NOTIFICATION_SETTING)

    fields = dict(body)
    if "marketing" in fields:
        # 동의 시각은 서버가 적는다 — 법적 근거가 되는 값이라 앱이 보낸 시각을 믿지 않는다.
        fields["marketing_consented_at"] = (
            wiring.now.astimezone(timezone.utc).isoformat() if fields["marketing"] else None
        )
    await wiring.repo.update_notification_settings(wiring.profile_id, **fields)
    return {"ok": True}


@router.get("/cards/matching-paused")
async def get_matching_paused(wiring: _Wiring = Depends(_wire)) -> dict:
    """화면 16 토글이 그릴 값. 안 읽으면 일시중지해 둔 사람도 다시 열 때 "켜짐"으로 보인다."""
    return {"paused": await wiring.repo.fetch_matching_paused(wiring.profile_id)}


@router.patch("/cards/matching-paused")
async def update_matching_paused(body: MatchingPausedRequest,
                                 wiring: _Wiring = Depends(_wire)) -> dict:
    """매칭 활성화 토글(화면 16 `TLrmq`). 끄면 다음 지급부터 카드가 오지도 가지도 않는다."""
    await wiring.repo.set_matching_paused(wiring.profile_id, body.paused)
    return {"ok": True}


# 구매 결과(rpc/purchase_paid_card) → 응답. ok · already_purchased 는 카드 id 를 담는다.
_PURCHASE_FAILURES = {
    "not_enough_hearts": (402, errors.HEARTS_NOT_ENOUGH, errors.CODE_HEARTS_NOT_ENOUGH),  # 앱이 하트 스토어로 보낸다
    # 제안이 offered 가 아니거나 대상이 자격을 잃음 — 앱이 새로 읽는다
    "offer_gone": (409, errors.PAID_OFFER_GONE, errors.CODE_PAID_OFFER_GONE),
}


def _purchase_error(status_code: int, detail: str, code: str) -> JSONResponse:
    """{"detail": <문구>, "code": <기계용 값>}. detail 은 HTTPException 과 같은 자리라 옛 앱(문구 비교)도 읽는다."""
    return JSONResponse(status_code=status_code, content={"detail": detail, "code": code})


@router.post("/cards/paid/{offer_id}/purchase", response_model=None)
async def purchase_paid_card(offer_id: str, wiring: _Wiring = Depends(_wire)) -> dict | JSONResponse:
    """유료 카드 구매(지시문 22 F). 하트 차감 · daily_cards 생성 · 제안 purchased 처리는 DB 함수가 한 번에 한다 —
    서버는 따로 하트를 빼거나 카드를 만들지 않는다. 두 번 눌러도 같은 카드 id 다(하트는 DB 가 한 번만 뺀다)."""
    offer = await wiring.repo.fetch_offer(offer_id)
    if offer is None or str(offer["owner_id"]) != wiring.profile_id:
        # 남의 제안 id 는 있는지조차 알려 주지 않는다.
        raise HTTPException(status_code=404, detail=errors.CARD_NOT_FOUND)
    outcome = await wiring.repo.purchase_paid_card(wiring.profile_id, offer_id)
    result = outcome.get("result")
    if result in ("ok", "already_purchased"):
        card_id = outcome.get("card_id")
        if card_id:
            return {"card_id": card_id}
        if result == "already_purchased":
            # 산 카드가 지워졌다 — 줄 카드가 없으니 "열 수 없는 카드" 로 말해 앱이 화면을 새로 읽게 한다.
            return _purchase_error(409, errors.PAID_OFFER_GONE, errors.CODE_PAID_OFFER_GONE)
        # ok 는 항상 card_id 를 담는다는 계약이 깨졌다 — 아래 5xx 와 같이 올린다.
    if result in _PURCHASE_FAILURES:
        return _purchase_error(*_PURCHASE_FAILURES[result])
    # 계약에 없는 값 — 반쪽 상태를 만들지 않도록 그대로 5xx 로 올린다.
    raise RuntimeError(f"purchase_paid_card 가 계약 밖의 결과를 돌려줬다: {outcome!r}")


# ↓ 아래에 새 `/cards/...` 경로를 두지 않는다. `{card_id}` 가 먼저 먹어 버린다.
@router.get("/cards/{card_id}")
async def get_card_detail(card_id: str,
                          wiring: _Wiring = Depends(_wire)) -> dict:
    """10b 상대 프로필 상세(`TORAs`). 카드 주인에게만 보인다."""
    now = wiring.now

    card = await wiring.repo.fetch_card(card_id)
    if card is None or card["owner_id"] != wiring.profile_id:
        raise HTTPException(status_code=404, detail=errors.CARD_NOT_FOUND)

    profile = await wiring.repo.fetch_card_detail_profile(card["target_id"])
    if _hidden_from_cards(card["target_id"], profile, await _blocked_among(wiring, [card["target_id"]])):
        raise HTTPException(status_code=404, detail=errors.CARD_NOT_FOUND)
    return {"card_id": card["id"], **await profile_detail(wiring.repo, profile, wiring.settings.supabase_url, now)}


async def profile_detail(repo: CardRepository, profile: dict, supabase_url: str, now: datetime) -> dict:
    """10b 카드 상세와 14c 상대 프로필(safety)이 같이 쓰는 몸통. 둘이 같은 dict 를 만들어야 앱 모델이
    하나로 남는다 — 키를 늘릴 때는 여기서만 늘린다. `profile` 은 `fetch_card_detail_profile` 이 읽은 행이다."""
    return {
        "profile": _card_profile(profile, supabase_url, now),
        "survey": await repo.fetch_survey(profile["id"]),
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
