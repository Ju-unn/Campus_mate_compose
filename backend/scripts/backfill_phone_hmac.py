"""한 번 쓰고 버리는 백필(계획서 B4): 조각 6 전에 저장된 전화번호에 지인 차단 HMAC 을 채운다.

순서는 DEPLOY.md §4-4 다 — 마이그레이션 적용 → 스키마 캐시 새로 고침 → 새 서버 배포 → **그 뒤에** 이것 한 번.
새 서버 전에 돌리면 옛 서버가 번호를 저장할 때 phone_hmac 을 다시 null 로 덮는다.

실행(backend 폴더, 비밀값은 Secret Manager 에서 env 로 넣는다):
    python -m scripts.backfill_phone_hmac

다시 돌려도 안전하다 — phone_hmac 이 빈 행만 고르고, 채울 때도 빈 칸일 때만 쓴다.
출력은 건수뿐이다(번호 · 해시 · profile_id 를 찍지 않는다).
"""
import asyncio

import httpx

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.profile_onboarding.phone_number import to_e164
from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone

PAGE = 500


class PhoneHmacBackfill(PostgrestRepository):

    async def run(self, phone_key: str, identity_key: str, page: int = PAGE) -> dict[str, int]:
        filled = skipped = 0
        last = None
        while True:
            # profile_id 로 넘겨 가며 읽는다 — 건너뛴 행은 계속 null 이라 offset 없이 다시 읽으면 끝나지 않는다.
            params = {"phone_number": "not.is.null", "phone_hmac": "is.null",
                      "select": "profile_id", "order": "profile_id.asc", "limit": page}
            if last is not None:
                params["profile_id"] = f"gt.{last}"
            response = await self._get("profile_private", params=params)
            raise_for_status(response)
            rows = response.json()
            if not rows:
                return {"filled": filled, "skipped": skipped}
            for row in rows:
                if await self._fill(row["profile_id"], phone_key, identity_key):
                    filled += 1
                else:
                    skipped += 1
            last = rows[-1]["profile_id"]

    async def _fill(self, profile_id: str, phone_key: str, identity_key: str) -> bool:
        # 키는 JSON 바디로만 넘긴다(encryption.py 와 같은 이유 — URL 은 접근 로그에 남는다).
        response = await self._post("rpc/decrypt_phone_number", json={"p_profile_id": profile_id, "p_key": phone_key})
        raise_for_status(response)
        phone = response.json()
        e164 = to_e164(phone) if phone else None
        if e164 is None:
            return False
        response = await self._patch(
            "profile_private",
            params={"profile_id": f"eq.{profile_id}", "phone_hmac": "is.null"},
            json={"phone_hmac": bytea_literal(hash_phone(identity_key, e164)),
                  "phone_hmac_key_version": IDENTITY_KEY_VERSION},
        )
        raise_for_status(response)
        return True


async def _main() -> dict[str, int]:
    settings = Settings()
    async with httpx.AsyncClient(timeout=30) as client:
        job = PhoneHmacBackfill(settings.postgrest_url, settings.supabase_service_role_key, client)
        return await job.run(settings.phone_encryption_key, settings.identity_hmac_key)


if __name__ == "__main__":
    counts = asyncio.run(_main())
    print(f"filled={counts['filled']} skipped={counts['skipped']}")
