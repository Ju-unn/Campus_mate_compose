"""지인 리뷰(20b · 20c · 14c 섹션 · 14d). 기준 문서 spec §2.8, 계획서 2026-09-28-friend-review.

리뷰는 **숨길 때 한 곳**(`_visible`)에서 거른다 — 작성자 active 아님 · 가림 · 보는 사람과의 차단(결정 6).
응답에는 reviewer_id 를 싣지 않는다(Global Constraints).
"""
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, StringConstraints, field_validator, model_validator

from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository
from app.cards.router import get_sender, is_active
from app.chat.repository import ChatRepository
from app.chat.router import avatar_url
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller
from app.friend_reviews.repository import FriendReviewRepository
from app.safety.router import find_match
from app.settings import Settings

router = APIRouter()
logger = logging.getLogger(__name__)

# DESIGN §13-25 순서 그대로. 앱 friendReviewTags 와 같은 목록이다. 외모 태그는 넣지 않는다.
TAGS = (
    "약속을 잘 지켜요", "대화가 편해요", "배려가 깊어요", "유머 감각이 좋아요", "성실해요", "솔직해요",
    "이야기를 잘 들어줘요", "긍정적이에요", "센스 있어요", "다정해요", "차분해요", "리액션이 좋아요",
)
# 앱 friendReviewMaxTags · friendReviewCommentMaxLength, DB friend_reviews_* check 와 같은 값이다.
MAX_TAGS = 3
COMMENT_MAX_LENGTH = 100

# 친구 코드(= 추천 코드, 설정 > 친구 초대의 그 코드)로 쓰기 — 사용자 결정 10-13. 앱이 글자 그대로 띄운다.
# errors.py 는 공유 파일이라 여기 둔다(옮기려면 대장 허락).
FRIEND_CODE_NOT_FOUND = "코드를 찾을 수 없어요"
FRIEND_CODE_TRY_LATER = "잠시 후 다시 시도해 주세요."
CODE_FAILURE_LIMIT = 10
CODE_FAILURE_WINDOW = timedelta(hours=1)
CODE_REVIEW_DAILY_LIMIT = 5
CODE_REVIEW_WINDOW = timedelta(hours=24)

# 대문자 · 공백 정리는 서버가 한다. 여기서는 빈 값과 터무니없이 긴 값만 막는다(referral RedeemRequest 와 같은 틀).
FriendCode = Annotated[str, StringConstraints(min_length=1, max_length=20, pattern=r"\S")]


class CodeLookupRequest(BaseModel):
    code: FriendCode


class ReviewRequest(BaseModel):
    # 대상은 둘 중 하나만: 추천으로 이어진 사람(reviewee_id) 또는 친구 코드(friend_code).
    reviewee_id: UUID | None = None
    friend_code: FriendCode | None = None
    tags: list[str] = Field(min_length=1, max_length=MAX_TAGS)
    comment: str | None = Field(default=None, max_length=COMMENT_MAX_LENGTH)

    @field_validator("tags")
    @classmethod
    def _known_tags(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value) or any(tag not in TAGS for tag in value):
            raise ValueError("12종 목록 안에서 서로 다른 태그만 받는다")
        return value

    @field_validator("comment", mode="before")
    @classmethod
    def _trim(cls, value: object) -> object:
        # 깎은 뒤에 길이(max_length)를 잰다 — "가"×100 뒤에 공백 하나가 붙었다고 422 를 내지 않는다.
        # 공백뿐이면 한마디가 없는 것이다. DB check 는 빈 글을 막으므로 null 로 넣는다.
        return (value.strip() or None) if isinstance(value, str) else value

    @model_validator(mode="after")
    def _one_target(self) -> "ReviewRequest":
        if (self.reviewee_id is None) == (self.friend_code is None):
            raise ValueError("reviewee_id 와 friend_code 중 하나만 보낸다")
        return self


class _Window:
    """사용자당 최근 span 안의 시각, limit 개까지(슬라이딩 창). hold 는 await 없이 자리를 먼저 잡고(꽉 찼으면 429)
    일이 안 되면 release 로 돌려준다 — 동시에 여러 요청이 와도 한도를 넘지 못한다. 막힌(429) 시도는 세지 않아
    두드려도 창이 밀리지 않는다. span 이 지난 사람은 hold 때마다 지워 메모리가 늘지 않는다.
    ponytail: 프로세스 안 dict 라 한도가 인스턴스별이다 — Cloud Run 이 N 대로 늘면 N 배까지 느슨해지고 재시작하면
    비워진다. 한도가 실제로 뚫리면 DB 카운터(시각 행 + 시간 인덱스)로 올린다."""

    def __init__(self, limit: int, span: timedelta):
        self.limit, self.span = limit, span
        self.times: dict[str, list[datetime]] = {}

    def hold(self, me: str, now: datetime) -> None:
        cutoff = now - self.span
        for key in [key for key, times in self.times.items() if not times or times[-1] <= cutoff]:
            del self.times[key]
        times = [t for t in self.times.get(me, []) if t > cutoff]
        if len(times) >= self.limit:
            self.times[me] = times
            raise HTTPException(status_code=429, detail=FRIEND_CODE_TRY_LATER)
        self.times[me] = [*times, now]

    def release(self, me: str, now: datetime) -> None:
        times = self.times.get(me)
        if times and now in times:
            times.remove(now)


# 코드 확인 실패(시간당 10번). 확인 전에 잡고 맞으면 돌려준다 — 실패만 남는다.
_CODE_FAILURES = _Window(CODE_FAILURE_LIMIT, CODE_FAILURE_WINDOW)
# 코드 경로로 쓴 시각(24시간 5건). 저장 전에 잡고 저장이 안 되면 돌려준다. **지워도 남는다** — 쓰기 · 지우기를
# 되풀이해 DB 수(count_written_since)를 0 으로 되돌리면 상한과 "새 지인 리뷰" 푸시가 무한히 되풀이된다(검토 필수1).
_CODE_WRITES = _Window(CODE_REVIEW_DAILY_LIMIT, CODE_REVIEW_WINDOW)


class _Wiring:
    def __init__(self, caller: Caller, sender: FcmSender, now: datetime):
        settings, client, profile_id = caller
        key = settings.supabase_service_role_key
        self.settings: Settings = settings
        # PostgREST 가 돌려주는 id 는 문자열이라 비교가 되게 str 로 맞춘다.
        self.profile_id = str(profile_id)
        self.repo = FriendReviewRepository(settings.postgrest_url, key, client)
        self.cards = CardRepository(settings.postgrest_url, key, client)
        self.chat = ChatRepository(settings.postgrest_url, key, client)
        self.sender = sender
        # 이 요청의 "지금". 푸시의 조용한 시간을 이 시각으로 본다.
        self.now = now


async def _wire(caller: Caller = Depends(get_verified_caller), sender: FcmSender = Depends(get_sender),
                now: datetime = Depends(get_now)) -> _Wiring:
    return _Wiring(caller, sender, now)


def _item(row: dict, supabase_url: str) -> dict:
    """리뷰 한 장. reviewer_id 는 싣지 않는다 — 14c 를 보는 매칭 상대가 상대 지인의 id 를 알 이유가 없다."""
    reviewer = row["reviewer"]
    return {
        "id": row["id"],
        "reviewer": {
            "nickname": reviewer["nickname"],
            "avatar_url": avatar_url(reviewer, supabase_url),
            "university": (reviewer.get("universities") or {}).get("name"),
        },
        "tags": row["tags"],
        "comment": row["comment"],
        "created_at": row["created_at"],
    }


def _written_item(row: dict, supabase_url: str) -> dict:
    """내가 쓴 리뷰 한 장. `_item` 과 같은 모양, 사람 키만 reviewee. reviewee_id 는 싣지 않는다."""
    reviewee = row["reviewee"]
    return {
        "id": row["id"],
        "reviewee": {
            "nickname": reviewee["nickname"],
            "avatar_url": avatar_url(reviewee, supabase_url),
            "university": (reviewee.get("universities") or {}).get("name"),
        },
        "tags": row["tags"],
        "comment": row["comment"],
        "created_at": row["created_at"],
    }


async def _visible(w: _Wiring, reviewee: str, blocked: set[str]) -> dict:
    """reviewee 가 받은 리뷰 중 지금 보는 사람에게 보여 줄 것(결정 6). DB 가 active · visible 을 거르지만
    한 번 더 본다 — embed 필터 이름이 틀려도 탈퇴자 리뷰가 새지 않게. blocked 는 요청마다 한 번만 읽어 넘긴다."""
    rows = await w.repo.fetch_about(reviewee)
    return {"reviews": [
        _item(row, w.settings.supabase_url) for row in rows
        if is_active(row["reviewer"]) and row["reviewer_id"] not in blocked
    ]}


@router.get("/friend-reviews/received")
async def list_received(w: _Wiring = Depends(_wire)) -> dict:
    """20c. 받은 사람은 지울 수 없고 신고만 한다(spec §2.8)."""
    blocked = await w.cards.fetch_block_partner_ids(w.profile_id)
    return await _visible(w, w.profile_id, blocked)


@router.get("/friend-reviews/about/{profile_id}")
async def list_about(profile_id: UUID, w: _Wiring = Depends(_wire)) -> dict:
    """14c 섹션 · 14d. 여는 조건은 14c(safety GET /profiles/{id})와 같다 — 한쪽만 열리면 차단 · 나감이 샌다."""
    target = str(profile_id)
    match = await find_match(w.chat, w.profile_id, target)
    if any(p["left_at"] for p in match["match_participants"]):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    blocked = await w.cards.fetch_block_partner_ids(w.profile_id)
    if await w.cards.fetch_profile_status(target) != "active" or target in blocked:
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    return await _visible(w, target, blocked)


async def _writable_target(w: _Wiring, target: str) -> dict:
    """20b 를 열거나 저장할 수 있는 상대인가. 이유를 가르지 않고 전부 같은 404 — 있다는 사실도 알리지 않는다.
    이미 썼으면 409(앱이 시트 대신 토스트)."""
    if target == w.profile_id or not await w.repo.is_linked(w.profile_id, target):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    profile = await w.repo.fetch_target(target)
    if profile is None or not is_active(profile) \
            or target in await w.cards.fetch_block_partner_ids(w.profile_id):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    if await w.repo.has_written(w.profile_id, target):
        raise HTTPException(status_code=409, detail=errors.FRIEND_REVIEW_ALREADY_WRITTEN)
    return profile


@router.get("/friend-reviews/targets/{profile_id}")
async def get_target(profile_id: UUID, w: _Wiring = Depends(_wire)) -> dict:
    """20b 머리(상대 아바타 + 닉네임). 온보딩(20 뒤)과 추천인 푸시 양쪽이 연다."""
    profile = await _writable_target(w, str(profile_id))
    return {"profile_id": profile["id"], "nickname": profile["nickname"],
            "avatar_url": avatar_url(profile, w.settings.supabase_url)}


def _code_refusal(me: str, profile: dict | None, blocked: set[str], my_phone: str | None) -> str | None:
    """친구 코드의 주인에게 쓸 수 없는 이유(로그용 이름). 없으면 None."""
    if profile is None:
        return "not_found"
    target = profile["id"]
    if target == me:
        return "self"
    if not is_active(profile):
        return "inactive"
    if target in blocked:
        return "blocked"
    # 둘 다 번호 해시가 있을 때만 비교한다(redeem_referral 과 같은 규칙) — 같은 번호 = 한 사람의 두 계정.
    if my_phone and my_phone == (profile.get("profile_private") or {}).get("phone_hmac"):
        return "same_phone"
    return None


async def _code_target(w: _Wiring, code: str) -> dict:
    """친구 코드의 주인 — 리뷰를 쓸 수 있는 사람일 때만. 추천 연결(referrals)은 보지 않는다: 하트 · 랭킹과 무관하다.
    거절 이유는 로그에만 가르고 응답은 하나다(있는데 막힌 코드와 없는 코드를 구분할 수 없게). 확인 · 저장이 같이 쓴다."""
    _CODE_FAILURES.hold(w.profile_id, w.now)
    # 사유와 상관없이 같은 조회 셋을 한 번에 보낸다 — PostgREST 왕복 수(응답 시간)로 사유를 가를 수 없게(권고1).
    try:
        profile, blocked, my_phone = await asyncio.gather(
            w.repo.fetch_by_code("".join(code.split()).upper()),
            w.cards.fetch_block_partner_ids(w.profile_id),
            w.repo.fetch_phone_hmac(w.profile_id),
        )
    except BaseException:
        # DB 장애 · 시간 초과 · 끊김은 코드 실패가 아니다 — 자리를 돌려줘 정상 사용자가 한 시간 429 에 갇히지 않게.
        _CODE_FAILURES.release(w.profile_id, w.now)
        raise
    if reason := _code_refusal(w.profile_id, profile, blocked, my_phone):
        # 코드 · 닉네임 원문은 남기지 않는다.
        logger.warning("친구 코드 거절 reason=%s caller=%s", reason, w.profile_id)
        raise HTTPException(status_code=404, detail=FRIEND_CODE_NOT_FOUND)
    _CODE_FAILURES.release(w.profile_id, w.now)
    return profile


async def _write_by_code(w: _Wiring, code: str, row: dict) -> tuple[str, str]:
    """코드 경로 저장 → (받는 사람 id, 리뷰 id). 앱이 본 확인 결과를 믿지 않고 코드로 다시 찾아 같은 검사를 한다.
    코드만 알면 누구에게나 쓸 수 있어 하루 5건 상한을 둔다. 둘 중 하나라도 5건이면 429:
    ① 프로세스 안 작성 기록(_CODE_WRITES — 지워도 남는다, await 전에 자리를 잡아 동시 요청도 막는다)
    ② DB 수(재시작 · 다른 인스턴스 보완). 경로 · 상태 무관 — 추천 경로(reviewee_id)로 쓴 리뷰도 센다."""
    target = (await _code_target(w, code))["id"]
    if await w.repo.has_written(w.profile_id, target):
        raise HTTPException(status_code=409, detail=errors.FRIEND_REVIEW_ALREADY_WRITTEN)
    _CODE_WRITES.hold(w.profile_id, w.now)
    try:
        since = w.now - CODE_REVIEW_WINDOW
        if await w.repo.count_written_since(w.profile_id, since, CODE_REVIEW_DAILY_LIMIT) >= CODE_REVIEW_DAILY_LIMIT:
            raise HTTPException(status_code=429, detail=FRIEND_CODE_TRY_LATER)
        return target, await w.repo.insert_review({**row, "reviewee_id": target})
    except BaseException:
        # 저장이 안 됐으면(DB 상한 · 동시 409 · 오류 · 끊김) 자리를 돌려준다.
        _CODE_WRITES.release(w.profile_id, w.now)
        raise


@router.post("/friend-reviews/code-lookup")
async def lookup_code(body: CodeLookupRequest, w: _Wiring = Depends(_wire)) -> dict:
    """친구 코드 확인(가입 뒤 지인 리뷰 쓰기 입구). 닉네임 · 학교만 준다 — 프로필 id · 아바타는 싣지 않는다.
    이미 썼으면 already_reviewed(앱이 쓰기 대신 안내). 저장은 POST /friend-reviews 가 코드로 다시 확인한다."""
    profile = await _code_target(w, body.code)
    return {"nickname": profile["nickname"], "university": (profile.get("universities") or {}).get("name"),
            "already_reviewed": await w.repo.has_written(w.profile_id, profile["id"])}


@router.post("/friend-reviews", status_code=201)
async def create_review(body: ReviewRequest, w: _Wiring = Depends(_wire)) -> dict:
    """20b "리뷰 남기기". 저장한 뒤 받은 사람에게 푸시(결정 8). 푸시 쪽 예외는 전부 로그만 남기고 저장은 그대로다.
    friend_code 면 _write_by_code 가 코드로 다시 확인하고 하루 상한을 본다."""
    row = {"reviewer_id": w.profile_id, "tags": body.tags, "comment": body.comment}
    if body.friend_code is None:
        target = str(body.reviewee_id)
        await _writable_target(w, target)
        review_id = await w.repo.insert_review({**row, "reviewee_id": target})
    else:
        target, review_id = await _write_by_code(w, body.friend_code, row)
    try:
        # 닉네임이 비면(온보딩 중간) "None 님이" 가 나가지 않게 푸시를 건너뛴다 — 프로필이 없을 때와 같은 처리다.
        if nickname := (await w.cards.fetch_card_profile(w.profile_id)).get("nickname"):
            await notify(w.cards, w.sender, target, "new_friend_review", "새 지인 리뷰가 도착했어요",
                         f"{nickname} 님이 리뷰를 남겼어요", {"route": "friend_reviews"}, now=w.now)
    except Exception:
        # 리뷰는 이미 저장됐다 — 알림 한 건 때문에 201 을 놓치는 쪽이 훨씬 나쁘다.
        logger.exception("새 지인 리뷰 푸시 실패 review=%s reviewee=%s", review_id, target)
    return {"id": review_id}


async def notify_review_request(cards: CardRepository, sender: FcmSender, referrer_id: str,
                                referee_id: str, now: datetime) -> None:
    """추천 연결 순간 추천인에게 "가입했어요, 리뷰를 남겨 주세요"(결정 8). redeem 경로가 한 줄로 부른다(Task B4).
    보상은 이미 끝났다 — 푸시 실패가 redeem 자체를 실패시키면 안 된다."""
    try:
        referee = await cards.fetch_card_profile(referee_id)
        await notify(cards, sender, referrer_id, "new_friend_review", "친구가 가입했어요",
                     f"{referee['nickname']} 님이 가입했어요, 리뷰를 남겨 주세요",
                     {"route": "friend_review_write", "profile_id": referee_id}, now=now)
    except Exception:
        logger.exception("추천 리뷰 요청 푸시 실패 referrer=%s referee=%s", referrer_id, referee_id)


@router.get("/friend-reviews/writable")
async def list_writable(w: _Wiring = Depends(_wire)) -> dict:
    """20e 위 "리뷰를 기다리는 친구"(결함 A3, 사용자 10-03). 추천으로 이어졌고 아직 내 리뷰가 없는 사람 —
    지우면 다시 나오고, 가입 · 알림 때 놓친 사람도 여기서 쓴다. 빠지는 조건은 20b 를 여는 _writable_target 과 같다."""
    skip = await w.repo.fetch_reviewed_ids(w.profile_id) | await w.cards.fetch_block_partner_ids(w.profile_id)
    # 서로 추천했으면(PK 가 referee_id 하나라 가능) 같은 사람이 두 번 온다 — 순서를 지키며 한 번만.
    ids = [i for i in dict.fromkeys(await w.repo.fetch_linked_ids(w.profile_id)) if i not in skip]
    people = {p["id"]: p for p in await w.repo.fetch_people(ids) if is_active(p)} if ids else {}
    return {"friends": [
        {"profile_id": i, "nickname": people[i]["nickname"],
         "avatar_url": avatar_url(people[i], w.settings.supabase_url),
         "university": (people[i].get("universities") or {}).get("name")}
        for i in ids if i in people
    ]}


@router.get("/friend-reviews/written")
async def list_written(w: _Wiring = Depends(_wire)) -> dict:
    """20e "내가 쓴 리뷰"(결정 1 · 4). visible 만. 받은 사람이 탈퇴면 빠지고 정지는 남는다(내 글)."""
    rows = await w.repo.fetch_written(w.profile_id)
    # DB 가 탈퇴한 받은 사람을 거르지만 한 번 더 본다(`_visible` 과 같은 이유).
    return {"reviews": [_written_item(row, w.settings.supabase_url) for row in rows
                        if row["reviewee"].get("status") != "withdrawn"]}


@router.delete("/friend-reviews/{review_id}", status_code=204)
async def delete_review(review_id: UUID, w: _Wiring = Depends(_wire)) -> None:
    """작성자 삭제(결정 1 · 2 · 6). 하드 삭제, 푸시 없음. 지운 행이 없으면 이유를 가르지 않고 같은 404."""
    if not await w.repo.delete_own(review_id, w.profile_id):
        raise HTTPException(status_code=404, detail=errors.FRIEND_REVIEW_NOT_FOUND)
