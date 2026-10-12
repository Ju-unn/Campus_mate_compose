"""한 번 쓰고 버리는 백필(M1 → M2 사이): 옛 평문 real_name · kakao_id 를 *_enc 열로 옮기고, 옮긴 값이 맞는지 센다.

순서는 마이그레이션 20261011010000 머리말이다 — M1 적용 → 이중 쓰기 서버 배포 → **그 뒤에** 이것 →
읽기 전환 → M2(평문 열 · backfill 함수 삭제). 이중 쓰기 서버 전에 돌리면 그 뒤 가입한 행의 enc 가 비어 남는다.

실행(backend 폴더, 비밀값은 Secret Manager 에서 env 로 넣는다):
    python -m scripts.backfill_encrypt_profile_private

다시 돌려도 안전하다 — enc 가 빈 행만 고르고, DB 함수도 enc 가 이미 있는 열은 덮지 않는다.
끝에 모든 행을 복호화해 평문과 비교한다. 불일치가 하나라도 있으면 종료 코드 1 이다(M2 전에 손봐야 한다).
출력은 건수뿐이다(실명 · 카카오 아이디 · 키 · profile_id 를 찍지 않는다).
"""
import asyncio
import sys

import httpx

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.profile_onboarding.encryption import decrypt_profile_private
from app.settings import Settings

PAGE = 500
FIELDS = ("real_name", "kakao_id")
# 평문이 있는데 그 열의 enc 가 빈 행. 열마다 따로 본다(이중 쓰기로 한쪽만 먼저 찼을 수 있다).
NEEDS_FILL = "(" + ",".join(f"and({f}.not.is.null,{f}_enc.is.null)" for f in FIELDS) + ")"


class ProfilePrivateEncryptionBackfill(PostgrestRepository):

    async def _pages(self, params: dict, page: int):
        # profile_id 로 넘겨 가며 읽는다 — 빈 문자열 평문 행은 DB 함수가 안 채워 계속 골라지므로 offset 없이 다시 읽으면 끝나지 않는다.
        last = None
        while True:
            query = {**params, "order": "profile_id.asc", "limit": page}
            if last is not None:
                query["profile_id"] = f"gt.{last}"
            response = await self._get("profile_private", params=query)
            raise_for_status(response)
            rows = response.json()
            if rows:
                yield rows
            if len(rows) < page:
                return
            last = rows[-1]["profile_id"]

    async def run(self, page: int = PAGE) -> int:
        """DB 함수를 부른 행 수. 함수가 void 라 실제로 채웠는지는 verify 가 센다."""
        requested = 0
        async for rows in self._pages({"or": NEEDS_FILL, "select": "profile_id"}, page):
            for row in rows:
                # 키는 JSON 바디로만 넘긴다(encryption.py 와 같은 이유 — URL 은 접근 로그에 남는다).
                response = await self._post("rpc/backfill_profile_private_encryption",
                                            json={"p_profile": row["profile_id"], "p_key": self._encryption_key})
                raise_for_status(response)
                requested += 1
        return requested

    async def verify(self, page: int = PAGE) -> dict[str, int]:
        """열마다 평문 있는 행 · enc 있는 행 · 복호화 값 ≠ 평문인 행 수. 빈 문자열은 없음과 같다(DB 함수 규칙)."""
        counts = {f"{f}_{kind}": 0 for f in FIELDS for kind in ("plain", "enc", "mismatch")}
        # ponytail: 모든 행을 한 건씩 복호화한다(행 수 = 가입자 수). 느려지면 enc · 평문 not.is.null 필터로 줄인다.
        async for rows in self._pages({"select": "profile_id," + ",".join(FIELDS)}, page):
            for row in rows:
                decrypted = await decrypt_profile_private(
                    self._postgrest_url, self._service_role_key, self._client, row["profile_id"], self._encryption_key)
                for f in FIELDS:
                    plain, enc = row[f] or None, decrypted[f] or None
                    counts[f"{f}_plain"] += plain is not None
                    counts[f"{f}_enc"] += enc is not None
                    counts[f"{f}_mismatch"] += plain != enc
        return counts


async def main(job: ProfilePrivateEncryptionBackfill, page: int = PAGE) -> int:
    requested = await job.run(page)
    counts = await job.verify(page)
    print(" ".join([f"requested={requested}", *(f"{k}={v}" for k, v in counts.items())]))
    return 1 if any(counts[f"{f}_mismatch"] for f in FIELDS) else 0


async def _main() -> int:
    settings = Settings()
    async with httpx.AsyncClient(timeout=30) as client:
        return await main(ProfilePrivateEncryptionBackfill(
            settings.postgrest_url, settings.supabase_service_role_key, client, settings.phone_encryption_key))


if __name__ == "__main__":
    sys.exit(asyncio.run(_main()))
