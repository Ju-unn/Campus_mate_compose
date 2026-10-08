"""`POST /school-email/verify` 테스트가 쓰는 Supabase 가짜(auth · admin · PostgREST).

앱은 소셜 연결과 따로 둔 저장 없는 연결로 학교 메일 OTP 를 받아 provider=email 인 **임시 계정**을 만든다.
서버에는 소셜 토큰(Authorization)과 그 임시 계정의 access_token 이 같이 온다. 가짜는 토큰마다 계정을 들고 있다.

요청은 경로 + params **키**로 가른다(`"id=eq." in url` 은 `profile_id=eq.` 에도 걸린다).
"""
import json
from datetime import datetime

import httpx

from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.core.time import SEOUL
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
OTHER = "44444444-4444-4444-4444-444444444444"
TEMP = "77777777-7777-7777-7777-777777777777"
SNU = "22222222-2222-2222-2222-222222222222"
AUTH = {"Authorization": "Bearer user-token"}
TEMP_TOKEN = "temp-token"
OTHER_TOKEN = "other-social-token"
IDENTITY_KEY = "identity-key-test"
NOW = datetime(2026, 10, 8, 12, 0, tzinfo=SEOUL)


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key=IDENTITY_KEY, **overrides,
    )


def social_user(user_id: str, provider: str = "kakao") -> dict:
    # 소셜 계정은 가입 순간 email_confirmed_at 이 채워진다(카카오는 이메일이 없는데도).
    return {"id": user_id, "email": "", "email_confirmed_at": "2026-10-01T00:00:00Z",
            "app_metadata": {"provider": provider, "providers": [provider]},
            "identities": [{"provider": provider, "identity_data": {"sub": "4242"}}]}


def temp_email_user(email: str = "hong@snu.ac.kr", user_id: str = TEMP,
                    created_at: str | None = "2026-10-08T02:58:00Z") -> dict:
    """방금(NOW 2분 전) 만든 임시 계정. 프로필은 없다(VerifyWorld.profiles 에 넣지 않는다)."""
    return {"id": user_id, "email": email, "email_confirmed_at": "2026-10-08T02:59:00Z", "created_at": created_at,
            "app_metadata": {"provider": "email", "providers": ["email"]},
            "identities": [{"provider": "email", "identity_data": {"email": email, "sub": TEMP}}]}


class VerifyWorld:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        # 소셜(카카오)로 막 가입한 사람 — 학교 메일 전이라 학교도 인증 시각도 비어 있다.
        self.profiles: dict[str, dict] = {
            ME: {"status": "active", "university_id": None, "school_email_verified_at": None},
        }
        self.consented = True
        # Authorization 값(Bearer 뺀 것) → 그 토큰 주인의 GET /user 응답
        self.tokens: dict[str, dict] = {
            "user-token": social_user(ME),
            TEMP_TOKEN: temp_email_user(),
            OTHER_TOKEN: social_user(OTHER),
        }
        # 토큰 → 인증 서비스가 돌려줄 상태 코드("unreachable" 이면 연결 실패)
        self.auth_trouble: dict[str, int | str] = {}
        self.domains: dict[str, str] = {"snu.ac.kr": SNU}
        self.blocked_hmacs: set[str] = set()
        # bytea 리터럴 → (그 학교 메일을 쓴 profile id, 그 계정의 provider). SQL school_email_claims 흉내.
        self.claims: dict[str, tuple[str, str]] = {}
        self.rpc_bodies: list[dict] = []
        self.rpc_status = 200
        self.rpc_result: str | None = None     # 정하면 계산 대신 이 값을 돌려준다
        self.admin_delete_status = 200
        self.admin_get_status = 200
        self.deleted_users: list[str] = []
        # 프로필 읽기(id 하나)가 실패할 id
        self.unreadable_profiles: set[str] = set()
        # DB 함수를 부른 뒤 이 id 의 프로필이 막 생긴 것처럼 만든다(삭제 직전 재확인 경쟁)
        self.profile_appears_on_rpc: str | None = None

    # ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path = request.url.path
        params = request.url.params
        body = json.loads(request.content) if request.content else None
        if path == "/auth/v1/user":
            return self._auth_user(request)
        if path.startswith("/auth/v1/admin/users/"):
            assert request.headers["authorization"] == "Bearer service-key"
            user_id = path.rsplit("/", 1)[1]
            if request.method == "GET":
                user = next((u for u in self.tokens.values() if u["id"] == user_id), None)
                if self.admin_get_status != 200:
                    return httpx.Response(self.admin_get_status, json={"msg": "boom"})
                return httpx.Response(200, json=user) if user else httpx.Response(404, json={"msg": "User not found"})
            assert request.method == "DELETE"
            if self.admin_delete_status != 200:
                return httpx.Response(self.admin_delete_status, json={"msg": "boom"})
            self.deleted_users.append(user_id)
            self.tokens = {t: u for t, u in self.tokens.items() if u["id"] != user_id}
            return httpx.Response(200, json={})
        if path == "/rest/v1/profiles":
            if params["id"].removeprefix("eq.") in self.unreadable_profiles:
                return httpx.Response(500, json={"message": "boom"})
            row = self.profiles.get(params["id"].removeprefix("eq."))
            if row is None:
                return httpx.Response(200, json=[])
            return httpx.Response(200, json=[{c: row.get(c) for c in params["select"].split(",")}])
        if path == "/rest/v1/user_consents":
            rows = [{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)] if self.consented else []
            return httpx.Response(200, json=rows)
        if path == "/rest/v1/university_email_domains":
            university = self.domains.get(params["domain"].removeprefix("eq."))
            return httpx.Response(200, json=[{"university_id": university}] if university else [])
        if path == "/rest/v1/signup_blocks":
            blocked = params["email_hmac"].removeprefix("eq.") in self.blocked_hmacs
            return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00Z"}] if blocked else [])
        if path == "/rest/v1/rpc/complete_school_email_verification":
            return self._complete(body)
        raise AssertionError(f"예상하지 못한 요청 {request.method} {request.url}")

    def _auth_user(self, request: httpx.Request) -> httpx.Response:
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        trouble = self.auth_trouble.get(token)
        if trouble == "unreachable":
            raise httpx.ConnectError("연결 실패", request=request)
        if trouble is not None:
            return httpx.Response(trouble, json={"msg": "trouble"})
        user = self.tokens.get(token)
        if user is None:
            return httpx.Response(401, json={"msg": "invalid JWT"})
        return httpx.Response(200, json=user)

    def _complete(self, body: dict) -> httpx.Response:
        """SQL complete_school_email_verification 흉내. text 하나를 돌려주니 본문은 JSON 스칼라다."""
        self.rpc_bodies.append(body)
        if self.rpc_status != 200:
            return httpx.Response(self.rpc_status, json={"message": "boom"})
        result = self.rpc_result or self._decide(body)
        if self.profile_appears_on_rpc:
            self.profiles[self.profile_appears_on_rpc] = {"status": "active", "school_email_verified_at": None}
        return httpx.Response(200, content=json.dumps(result), headers={"Content-Type": "application/json"})

    def _decide(self, body: dict) -> str:
        profile = self.profiles.get(body["p_profile"])
        if profile is None:
            return "no_profile"
        owner = self.claims.get(body["p_email_hmac"])
        if owner and owner[0] != body["p_profile"]:
            return owner[1]
        if profile["school_email_verified_at"] is not None:
            return "ok" if owner else "already_verified"
        self.claims[body["p_email_hmac"]] = (body["p_profile"], body["p_provider"])
        profile.update(university_id=body["p_university"], school_email_verified_at="2026-10-08T03:00:00+00:00")
        return "ok"

    # 도우미 ------------------------------------------------------------------
    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]

    def temp_reads(self) -> list[httpx.Request]:
        return [r for r in self.calls("GET", "/auth/v1/user")
                if r.headers.get("authorization") != AUTH["Authorization"]]
