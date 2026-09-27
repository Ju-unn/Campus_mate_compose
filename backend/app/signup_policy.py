import hashlib
import hmac

import httpx

# 신원 해시(아래 두 함수)를 뜬 키의 버전. `signup_blocks.key_version` · `profile_private.phone_hmac_key_version`
# · `contact_blocks.key_version` 이 모두 이 값을 적고, 대조는 같은 버전끼리만 한다.
# identity_hmac_key 를 바꾸는 날 여기를 올린다(계획서 편차 ①) — 옛 버전 행은 정리 배치가 경고로 센다.
IDENTITY_KEY_VERSION = 1


def hash_email(secret: str, email: str) -> bytes:
    """탈퇴 후 재가입 제한 대조용 HMAC. 원본 이메일은 저장하지 않는다
    (ERD.md `signup_blocks`, §11-12)."""
    return hmac.new(secret.encode(), email.strip().lower().encode(), hashlib.sha256).digest()


def hash_phone(secret: str, e164: str) -> bytes:
    """지인 차단 대조용 HMAC(hash_email 과 같은 키 · 같은 방식). 입력은 `to_e164` 가 돌려준 값 그대로다 —
    온보딩 저장과 연락처 등록이 같은 모양을 넣어야 두 해시가 맞는다."""
    return hmac.new(secret.encode(), e164.encode(), hashlib.sha256).digest()


def bytea_literal(value: bytes) -> str:
    """PostgREST 로 bytea 를 보내는 모양(`\\x` + hex). 필터 값과 JSON 바디 둘 다 이 문자열이다."""
    return f"\\x{value.hex()}"


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
        response = await self._client.get(
            f"{self._postgrest_url}/signup_blocks",
            params={"email_hmac": f"eq.{bytea_literal(email_hmac)}", "blocked_until": "gt.now()",
                    "select": "blocked_until"},
            headers=self._headers,
        )
        response.raise_for_status()
        return len(response.json()) > 0
