import hashlib
import hmac

import httpx


def hash_email(secret: str, email: str) -> bytes:
    """탈퇴 후 재가입 제한 대조용 HMAC. 원본 이메일은 저장하지 않는다
    (ERD.md `signup_blocks`, §11-12)."""
    return hmac.new(secret.encode(), email.strip().lower().encode(), hashlib.sha256).digest()


class SignupPolicy:
    """도메인 화이트리스트·재가입 제한 검사와 pending 프로필 생성을 맡는다
    (spec §7.3, ERD.md §11-12). service_role 키로 PostgREST 를 직접 호출한다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def find_university_id(self, domain: str) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/university_email_domains",
            params={"domain": f"eq.{domain}", "select": "university_id"},
            headers=self._headers,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["university_id"] if rows else None

    async def is_blocked(self, email_hmac: bytes) -> bool:
        hex_literal = f"\\x{email_hmac.hex()}"
        response = await self._client.get(
            f"{self._postgrest_url}/signup_blocks",
            params={"email_hmac": f"eq.{hex_literal}", "blocked_until": "gt.now()", "select": "blocked_until"},
            headers=self._headers,
        )
        response.raise_for_status()
        return len(response.json()) > 0
