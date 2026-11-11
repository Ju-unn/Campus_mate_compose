"""phone_verifications 저장소. 표는 RLS 정책 0개 · service_role 전용이고, 한도 · 잠금 판정은 DB 함수 셋이 한다
(20261111010000). 여기서는 부르기만 한다."""
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal


# returns table 함수는 PostgREST 가 행 목록으로 준다 — 아래 두 함수는 늘 한 행이라 [0] 을 꺼낸다.
class PhoneVerificationRepository(PostgrestRepository):

    async def issue(self, profile_id: UUID, phone_hmac: bytes, code_hash: bytes, daily_global_limit: int) -> dict:
        """{result, verification_id, retry_after_seconds, expires_in_seconds, global_limit_reached}."""
        response = await self._post("rpc/issue_phone_verification", json={
            "p_profile_id": str(profile_id), "p_phone_hmac": bytea_literal(phone_hmac),
            "p_phone_hmac_key_version": IDENTITY_KEY_VERSION, "p_code_hash": bytea_literal(code_hash),
            "p_daily_global_limit": daily_global_limit,
        })
        raise_for_status(response)
        return response.json()[0]

    async def delete(self, verification_id: str) -> None:
        response = await self._delete("phone_verifications", params={"id": f"eq.{verification_id}"})
        raise_for_status(response)

    async def attempt(self, profile_id: UUID, phone_hmac: bytes) -> dict:
        """{result, verification_id, code_hash, attempts_left}. code_hash 는 result=check 일 때만 있다(`\\x…`)."""
        response = await self._post("rpc/attempt_phone_verification", json={
            "p_profile_id": str(profile_id), "p_phone_hmac": bytea_literal(phone_hmac),
            "p_phone_hmac_key_version": IDENTITY_KEY_VERSION,
        })
        raise_for_status(response)
        return response.json()[0]

    async def mark_verified(self, verification_id: str) -> None:
        # 'now()' 는 Postgres 가 timestamptz 로 읽는 특수 입력이다 — 시각은 DB 시계로 맞춘다(만료 · 30분 기준과 같은 시계).
        response = await self._patch("phone_verifications", params={"id": f"eq.{verification_id}", "verified_at": "is.null"},
                                     json={"verified_at": "now()"})
        raise_for_status(response)

    async def check_verified_phone(self, profile_id: UUID, phone_hmac: bytes) -> str:
        """ok · not_verified · in_use. 아무것도 바꾸지 않는 미리 보기 — 저장 함수가 잠금 안에서 같은 판정을 다시 한다."""
        response = await self._post("rpc/check_verified_phone_number", json={
            "p_profile_id": str(profile_id), "p_phone_hmac": bytea_literal(phone_hmac),
            "p_phone_hmac_key_version": IDENTITY_KEY_VERSION,
        })
        raise_for_status(response)
        return response.json()

    async def save_verified_phone(self, profile_id: UUID, phone_e164: str, encryption_key: str, phone_hmac: bytes) -> str:
        """saved · not_verified · in_use. 키는 JSON 바디로만 넘긴다(set_phone_number 와 같은 규칙)."""
        response = await self._post("rpc/save_verified_phone_number", json={
            "p_profile_id": str(profile_id), "p_phone": phone_e164, "p_key": encryption_key,
            "p_phone_hmac": bytea_literal(phone_hmac), "p_phone_hmac_key_version": IDENTITY_KEY_VERSION,
        })
        raise_for_status(response)
        return response.json()
