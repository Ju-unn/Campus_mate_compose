"""한 번 쓰고 버리는 백필(소셜 로그인 전환): 학교 메일 OTP 로 가입한 기존 계정의 학교 메일 해시를 school_email_claims 에 채운다.

왜: 기존 계정은 profiles.school_email_verified_at 을 마이그레이션이 채웠지만 school_email_claims(학교 메일 해시 → 계정)는
비어 있다. HMAC 키는 서버에만 있어 SQL 로 못 채운다. 비어 있으면 기존 사용자의 학교 메일로 새 소셜 계정이 인증받을 수 있다
(한 학교 메일 = 한 계정 규칙이 기존 사용자에게 안 걸린다).

순서: 마이그레이션 적용 → 이 스크립트 → **그 뒤에** Supabase 의 카카오 · 구글 로그인을 켜고 앱을 배포한다.
소셜 로그인을 켜기 전에 끝내야 구멍이 없다. 서버 배포 전후 어느 쪽에 돌려도 되지만(새 서버가 verify 를 받기 전에도
표만 채운다) 소셜 로그인 공개 전에는 반드시. 자세한 절차는 DEPLOY.md §4-4.

실행(backend 폴더, 비밀값은 Secret Manager 에서 env 로 넣는다):
    python -m scripts.backfill_school_email_claims

다시 돌려도 안전하다 — claims 가 이미 있는 계정은 건너뛰고(already), 쓸 때도 같은 해시가 있으면 덮지 않는다(conflicts).
출력은 건수뿐이다(이메일 · 해시 · profile_id 를 찍지 않는다. 로그에도 남기지 않는다).
"""
import asyncio

import httpx

from app.account.repository import SupabaseAdmin
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository
from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_email

PAGE = 500


class SchoolEmailClaimsBackfill(PostgrestRepository):

    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        super().__init__(settings.postgrest_url, settings.supabase_service_role_key, client)
        self._admin = SupabaseAdmin(settings, client)
        self._identity_key = settings.identity_hmac_key

    async def run(self, page: int = PAGE) -> dict[str, int]:
        counts = {"filled": 0, "skipped": 0, "already": 0, "conflicts": 0}
        last = None
        while True:
            # id 로 넘겨 가며 읽는다 — 건너뛴 행은 계속 조건에 걸려서 offset 없이 다시 읽으면 끝나지 않는다.
            params = {"school_email_verified_at": "not.is.null", "university_id": "not.is.null",
                      "status": "neq.withdrawn", "select": "id,university_id,school_email_verified_at,status",
                      "order": "id.asc", "limit": page}
            if last is not None:
                params["id"] = f"gt.{last}"
            response = await self._get("profiles", params=params)
            raise_for_status(response)
            rows = response.json()
            if not rows:
                return counts
            claimed = await self._claimed([row["id"] for row in rows])
            for row in rows:
                if row["id"] in claimed:
                    counts["already"] += 1
                    continue
                counts[await self._fill(row)] += 1
            last = rows[-1]["id"]
            if len(rows) < page:
                return counts

    async def _claimed(self, profile_ids: list[str]) -> set[str]:
        """이 쪽의 프로필 중 school_email_claims 에 이미 행이 있는 id."""
        response = await self._get("school_email_claims", params={
            "profile_id": f"in.({','.join(profile_ids)})", "select": "profile_id",
        })
        raise_for_status(response)
        return {row["profile_id"] for row in response.json()}

    async def _fill(self, row: dict) -> str:
        try:
            # 서버의 관리자 호출 헬퍼(GET /admin/users/{id}, service key)를 그대로 쓴다.
            email = (await self._admin.fetch_user(row["id"])).get("email")
        except httpx.HTTPError:
            return "skipped"  # 그 계정만 건너뛴다 — 다음에 다시 돌리면 다시 고른다
        if not email or not email.strip():
            return "skipped"
        response = await self._post(
            "school_email_claims",
            params={"on_conflict": "school_email_hmac"},
            json={
                # 가입 · 탈퇴 · verify 와 같은 함수(소문자 · 공백 제거)라야 같은 메일로 맞는다.
                "school_email_hmac": bytea_literal(hash_email(self._identity_key, email)),
                "university_id": row["university_id"],
                "profile_id": row["id"],
                "provider": "email",
                "key_version": IDENTITY_KEY_VERSION,
                "verified_at": row["school_email_verified_at"],
            },
            # 같은 해시가 이미 있으면 덮지 않는다(무시하고 빈 목록). 이 계정 행이 그 사이 생겼으면 profile_id unique 23505.
            prefer="resolution=ignore-duplicates,return=representation",
        )
        if error_code(response) == "23505":
            return "already"
        raise_for_status(response)
        # 무시됐으면 같은 학교 메일을 다른 계정이 쓴다는 뜻이다(정상이면 없어야 한다). id 는 찍지 않는다.
        return "filled" if response.json() else "conflicts"


def format_counts(counts: dict[str, int]) -> str:
    return (f"filled={counts['filled']} skipped={counts['skipped']} "
            f"already={counts['already']} conflicts={counts['conflicts']}")


async def _main() -> dict[str, int]:
    settings = Settings()
    async with httpx.AsyncClient(timeout=30) as client:
        return await SchoolEmailClaimsBackfill(settings, client).run()


if __name__ == "__main__":
    print(format_counts(asyncio.run(_main())))
