"""탈퇴 · 정리 배치 · 16e 계정 화면이 부르는 Supabase 세 곳(PostgREST · auth admin · Storage)의 출입구.

전부 service_role 키다. 응답 · 로그에 이메일 · 해시 · 파일 경로를 싣지 않는다 — 부르는 쪽은 profile_id 와 건수만 본다.
"""
from datetime import datetime
from uuid import UUID

import httpx

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository
from app.settings import Settings
from app.signup_policy import bytea_literal


class AccountRepository(PostgrestRepository):

    async def withdraw(self, profile_id: UUID | str, email_hmac: bytes, key_version: int) -> None:
        """상태 · withdrawn_at · 재가입 제한을 한 트랜잭션에서(SQL `withdraw_account`, 멱등)."""
        response = await self._post("rpc/withdraw_account", json={
            "p_profile_id": str(profile_id), "p_email_hmac": bytea_literal(email_hmac),
            "p_key_version": key_version,
        })
        raise_for_status(response)

    async def delete_push_tokens(self, profile_id: UUID | str) -> None:
        response = await self._delete("push_tokens", params={"profile_id": f"eq.{profile_id}"})
        raise_for_status(response)

    # 정리 배치 ----------------------------------------------------------------
    async def fetch_withdrawn_before(self, cutoff: datetime, limit: int) -> list[str]:
        """cutoff 전에 탈퇴한 사람. 오래된 사람부터 — 한 번에 다 못 지우면 밀린 사람이 먼저다."""
        response = await self._get("profiles", params={
            "status": "eq.withdrawn", "withdrawn_at": f"lt.{cutoff.isoformat()}",
            "select": "id", "order": "withdrawn_at.asc", "limit": limit,
        })
        raise_for_status(response)
        return [row["id"] for row in response.json()]

    async def _delete_counted(self, table: str, params: dict) -> int:
        """지운 행 수. 작은 칸 하나만 돌려받아 센다(PostgrestRepository._delete 는 Prefer 를 받지 않는다)."""
        response = await self._client.delete(
            f"{self._postgrest_url}/{table}", params=params,
            headers=self._with_prefer("return=representation"),
        )
        raise_for_status(response)
        return len(response.json())

    async def delete_reports_before(self, cutoff: datetime) -> int:
        # ERD_DECISIONS §11-23: 처리(조치 · 기각)가 끝난 시각에서 1년이다. 열린 신고는 resolved_at 이
        # null 이라(reports_status_pair) `lt.` 에 걸리지 않고 남는다.
        # ponytail: resolved_at 인덱스 없음(created_at 인덱스는 옛 기준) — 신고가 수만 건이면 인덱스 마이그레이션.
        return await self._delete_counted("reports", {
            "resolved_at": f"lt.{cutoff.isoformat()}", "select": "id",
        })

    async def delete_signup_blocks_before(self, now: datetime) -> int:
        # infinity(정지 중 탈퇴)는 어떤 시각보다도 크다 — 이 조건으로는 지워지지 않는다.
        return await self._delete_counted("signup_blocks", {
            "blocked_until": f"lt.{now.isoformat()}", "select": "key_version",
        })

    # 16e 계정 화면 ------------------------------------------------------------
    async def fetch_account(self, profile_id: UUID | str) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}", "select": "birth_year,created_at,universities(name)",
        })
        raise_for_status(response)
        return response.json()[0]

    async def fetch_private(self, profile_id: UUID | str) -> dict:
        """실명 · 카톡 아이디. 관문을 지났으면 행이 늘 있지만(3b 에서 만든다), 없다고 500 을 내지 않는다."""
        response = await self._get("profile_private", params={
            "profile_id": f"eq.{profile_id}", "select": "real_name,kakao_id",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else {}

    async def count_contact_blocks_not_on(self, key_version: int) -> int:
        response = await self._client.get(
            f"{self._postgrest_url}/contact_blocks",
            params={"key_version": f"neq.{key_version}", "select": "owner_id", "limit": 1},
            headers=self._with_prefer("count=exact"),
        )
        raise_for_status(response)
        # Content-Range: 0-0/12 (없으면 */0) — 전체 건수는 / 뒤다.
        return int(response.headers["content-range"].rsplit("/", 1)[1])


class SupabaseAdmin:
    """auth admin(GoTrue) · Storage 호출. 둘 다 PostgREST 가 아니라 따로 둔다."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self._auth_url = settings.auth_url
        self._storage_url = settings.storage_url
        self._key = settings.supabase_service_role_key
        self._headers = {"apikey": self._key, "Authorization": f"Bearer {self._key}"}
        self._client = client

    async def fetch_email(self, profile_id: UUID | str) -> str:
        """`GET /admin/users/{id}` — 원본 이메일은 해시를 뜨는 데만 쓰고 어디에도 남기지 않는다."""
        response = await self._client.get(f"{self._auth_url}/admin/users/{profile_id}", headers=self._headers)
        response.raise_for_status()
        return response.json()["email"]

    async def delete_user(self, profile_id: UUID | str) -> None:
        """auth 사용자째 지운다 — profiles 와 딸린 표는 FK cascade 다(pr3-db-report §2, 편차 2)."""
        response = await self._client.delete(f"{self._auth_url}/admin/users/{profile_id}", headers=self._headers)
        response.raise_for_status()

    async def logout_everywhere(self, authorization: str) -> None:
        """`POST /logout?scope=global` — 그 사용자의 모든 기기 세션을 끊는다. 사용자 본인의 토큰으로 부른다."""
        response = await self._client.post(
            f"{self._auth_url}/logout", params={"scope": "global"},
            headers={"apikey": self._key, "Authorization": authorization},
        )
        response.raise_for_status()

    async def empty_folder(self, bucket: str, profile_id: UUID | str) -> None:
        """`{profile_id}/` 아래 파일을 전부 지운다. 목록 · 삭제 어느 쪽이든 실패하면 예외다.

        경로는 세 버킷 모두 `{profile_id}/{uuid}.확장자` 한 층이라 한 번 목록으로 끝난다.
        ponytail: 한 사람 파일이 1000개를 넘으면 남는다(사진 4장 + 아바타 몇 장이 전부다) — 넘으면 offset 으로 돈다."""
        listed = await self._client.post(
            f"{self._storage_url}/object/list/{bucket}",
            json={"prefix": f"{profile_id}/", "limit": 1000, "offset": 0},
            headers=self._headers,
        )
        listed.raise_for_status()
        paths = [f"{profile_id}/{entry['name']}" for entry in listed.json()]
        if not paths:
            return  # prefixes 는 한 개 이상이어야 한다(Storage 스키마 minItems 1)
        deleted = await self._client.request(
            "DELETE", f"{self._storage_url}/object/{bucket}", json={"prefixes": paths}, headers=self._headers,
        )
        deleted.raise_for_status()
