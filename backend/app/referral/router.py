"""추천 코드: 내 코드 조회(홈탭 19) · 코드 입력(화면 20). 계획서 docs/superpowers/plans/2026-09-28-referral.md"""
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, StringConstraints

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.cards.router import get_sender
from app.core.deps import Caller, get_now, get_verified_caller
from app.friend_reviews.router import notify_review_request
from app.referral.repository import ReferralRepository

router = APIRouter()


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
    referrer_id = await _repo(caller).redeem(caller.profile_id, body.code)
    # 추천인에게 "가입했어요, 리뷰를 남겨 주세요" — 누르면 20b(지인 리뷰 결정 8). 푸시가 죽어도 redeem 은 성공이다.
    cards = CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    await notify_review_request(cards, sender, referrer_id, str(caller.profile_id), now)
    return {"referrer_id": referrer_id}
