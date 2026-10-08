"""학교 메일 확인(`/school-email/*`) 테스트가 같이 쓰는 Supabase 가짜(auth · PostgREST).

요청은 경로 + params **키**로 가른다(`"id=eq." in url` 은 `profile_id=eq.` 에도 걸린다). 상태를 들고 있어
"한 번 기록 → 다시 불러도 그대로" 처럼 앞 요청이 뒤 요청의 답을 바꾸는 흐름을 그대로 흉내 낸다.
"""
import json
from datetime import datetime

import httpx

from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.core.time import SEOUL
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
OTHER = "44444444-4444-4444-4444-444444444444"
SNU = "22222222-2222-2222-2222-222222222222"
AUTH = {"Authorization": "Bearer user-token"}
IDENTITY_KEY = "identity-key-test"
NOW = datetime(2026, 10, 8, 12, 0, tzinfo=SEOUL)


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key=IDENTITY_KEY, **overrides,
    )


class SchoolEmailWorld:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        # 소셜(카카오)로 막 가입한 사람 — 학교 메일 전이라 학교도 인증 시각도 비어 있다.
        self.profile: dict = {"status": "active", "university_id": None, "school_email_verified_at": None}
        self.consented = True
        # GET /auth/v1/user 가 돌려줄 계정 정보. 카카오는 이메일이 없어도 email_confirmed_at 이 채워진다.
        self.auth_user: dict = {
            "id": ME, "email": "", "email_confirmed_at": "2026-10-01T00:00:00Z",
            "identities": [{"provider": "kakao", "identity_data": {"sub": "4242"}}],
        }
        self.domains: dict[str, str] = {"snu.ac.kr": SNU}
        self.blocked_hmacs: set[str] = set()
        # 소문자 이메일 → (계정 id, 주 로그인 수단)
        self.accounts: dict[str, tuple[str, str]] = {}
        self.provider_lookups: list[dict] = []

    def verified_school_email(self, email: str) -> None:
        """앱이 updateUser(email) → verifyOTP(emailChange) 를 끝낸 뒤의 계정 모양."""
        self.auth_user["email"] = email
        self.auth_user["identities"] = [*self.auth_user["identities"], {"provider": "email",
                                                                          "identity_data": {"email": email}}]

    # ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path = request.url.path
        params = request.url.params
        body = json.loads(request.content) if request.content else None
        if path == "/auth/v1/user":
            return httpx.Response(200, json=self.auth_user)
        if path == "/rest/v1/profiles":
            return self._profiles(request.method, params, body)
        if path == "/rest/v1/user_consents":
            rows = [{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)] if self.consented else []
            return httpx.Response(200, json=rows)
        if path == "/rest/v1/university_email_domains":
            university = self.domains.get(params["domain"].removeprefix("eq."))
            return httpx.Response(200, json=[{"university_id": university}] if university else [])
        if path == "/rest/v1/signup_blocks":
            blocked = params["email_hmac"].removeprefix("eq.") in self.blocked_hmacs
            return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00Z"}] if blocked else [])
        if path == "/rest/v1/rpc/find_other_account_provider":
            self.provider_lookups.append(body)
            owner, provider = self.accounts.get(body["p_email"].lower(), (None, None))
            # RPC 가 text 하나를 돌려주면 PostgREST 본문은 JSON 스칼라다("kakao" 또는 null).
            return httpx.Response(200, json=provider if owner and owner != body["p_caller"] else None)
        raise AssertionError(f"예상하지 못한 요청 {request.method} {request.url}")

    def _profiles(self, method, params, body):
        assert params["id"] == f"eq.{ME}"
        if method == "GET":
            return httpx.Response(200, json=[{c: self.profile.get(c) for c in params["select"].split(",")}])
        assert method == "PATCH"
        # 요청에 건 조건(school_email_verified_at=is.null)을 DB 처럼 적용한다.
        if params.get("school_email_verified_at") == "is.null" and self.profile["school_email_verified_at"] is not None:
            return httpx.Response(204)
        self.profile.update(body)
        return httpx.Response(204)

    # 도우미 ------------------------------------------------------------------
    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
