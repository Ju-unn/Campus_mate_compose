"""추천 코드: 내 코드 조회(홈탭 19) · 코드 입력(화면 20). 계획서 docs/superpowers/plans/2026-09-28-referral.md"""
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, StringConstraints

from app.core.deps import Caller, get_verified_caller
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
async def redeem_referral_code(body: RedeemRequest, caller: Caller = Depends(get_verified_caller)) -> dict[str, str]:
    """화면 20. 성공하면 추천인 id 만 준다(닉네임 · 번호는 싣지 않는다) — 20b 가 이 id 로 상대를 불러온다."""
    referrer_id = await _repo(caller).redeem(caller.profile_id, body.code)
    # 푸시 훅 자리(채팅탭): referral merge 뒤 추천인에게 "○○님이 가입했어요" 푸시를 여기서 보낸다.
    return {"referrer_id": referrer_id}
