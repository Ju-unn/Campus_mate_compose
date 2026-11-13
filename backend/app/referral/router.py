"""추천 코드: 내 코드 조회(홈탭 19) · 코드 입력(화면 20). 계획서 docs/superpowers/plans/2026-09-28-referral.md"""
import logging
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, StringConstraints

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.cards.router import get_sender
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller
from app.friend_reviews.repository import FriendReviewRepository
from app.friend_reviews.router import notify_review_request
from app.referral.repository import ReferralRepository

router = APIRouter()
logger = logging.getLogger(__name__)


class RedeemRequest(BaseModel):
    # 자르기 · 대문자는 DB 함수가 한다. 여기서는 빈 값과 터무니없이 긴 값만 DB 앞에서 막는다.
    code: Annotated[str, StringConstraints(min_length=1, max_length=20, pattern=r"\S")]


def _repo(caller: Caller) -> ReferralRepository:
    return ReferralRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.get("/referral/my-code")
async def get_my_referral_code(caller: Caller = Depends(get_verified_caller)) -> dict[str, str]:
    """홈탭 19 코호트 대기 "친구 초대"가 쓴다. 코드는 계정당 하나이고 바뀌지 않는다."""
    return {"code": await _repo(caller).fetch_my_code(caller.profile_id)}


@router.post("/referral/redeem")
async def redeem_referral_code(body: RedeemRequest, caller: Caller = Depends(get_verified_caller),
                               sender: FcmSender = Depends(get_sender),
                               now: datetime = Depends(get_now)) -> dict[str, str]:
    """화면 20. 성공하면 추천인 id 만 준다(닉네임 · 번호는 싣지 않는다) — 20b 가 이 id 로 상대를 불러온다."""
    # 같은 번호 검사(redeem_referral)는 내 번호 해시가 있어야 돈다 — 번호 저장(04-1) 전에 넣은 코드는 검사를 건너뛰어
    # 한 번호로 보상을 되풀이해 받을 수 있었다(최종 점검 11-13 ①). 앱은 04-1 뒤에만 화면 20 을 열어 정상 가입자는 여기 걸리지 않는다.
    # 문구는 같은 번호 거절과 같다(D4 — 거절 이유를 드러내지 않는다).
    phones = FriendReviewRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    if not await phones.fetch_phone_hmac(caller.profile_id):
        logger.warning("초대 코드 거절 reason=no_phone_hash profile=%s", caller.profile_id)
        raise HTTPException(status_code=422, detail=errors.REFERRAL_CODE_NOT_ALLOWED)
    referrer_id = await _repo(caller).redeem(caller.profile_id, body.code)
    # 추천인에게 "가입했어요, 리뷰를 남겨 주세요" — 누르면 20b(지인 리뷰 결정 8). 푸시가 죽어도 redeem 은 성공이다.
    cards = CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    await notify_review_request(cards, sender, referrer_id, str(caller.profile_id), now)
    return {"referrer_id": referrer_id}
