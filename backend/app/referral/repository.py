"""추천 코드 저장소. 검사 · 행 넣기 · 양쪽 50하트는 DB 함수 redeem_referral 한 트랜잭션이 한다."""
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository


class ReferralRepository(PostgrestRepository):
    async def fetch_my_code(self, profile_id: UUID) -> str:
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": "referral_code"})
        raise_for_status(response)
        rows = response.json()
        if not rows:
            raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
        return rows[0]["referral_code"]

    async def redeem(self, referee_id: UUID, code: str) -> str:
        response = await self._post("rpc/redeem_referral", json={"p_referee_id": str(referee_id), "p_code": code})
        # 자기 코드 · 같은 번호 · 이미 받은 번호는 모두 CM422 한 문구다 — 거절 이유를 드러내지 않는다(D4).
        match error_code(response):
            case "CM404":
                raise HTTPException(status_code=404, detail=errors.REFERRAL_CODE_NOT_FOUND)
            case "CM422":
                raise HTTPException(status_code=422, detail=errors.REFERRAL_CODE_NOT_ALLOWED)
        # 23505 = 이 사람이 이미 입력했다(referrals PK) → 409.
        raise_for_status(response, conflict_detail=errors.REFERRAL_ALREADY_REDEEMED)
        return response.json()
