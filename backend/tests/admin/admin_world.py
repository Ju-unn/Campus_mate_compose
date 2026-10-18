"""관리자 관문 · 작업 기록 시험이 같이 쓰는 Supabase 가짜(관리자 대시보드 설계 10-18 §6 · §7).

요청은 URL 부분 문자열이 아니라 **경로 + params 키**로 가른다(메모 reference_backend_test_mock_traps ①).
모르는 요청은 바로 실패시킨다 — 관문이 엉뚱한 표를 부르면 조용히 [] 를 받고 통과하지 않게.
"""
import base64
import json

import httpx

from app.settings import Settings

ADMIN = "aaaaaaaa-0000-0000-0000-000000000001"
STRANGER = "bbbbbbbb-0000-0000-0000-000000000002"


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


def _b64url(obj) -> str:
    # JWT 는 base64url 의 '=' 채움을 떼고 싣는다 — 서버가 채움 없이도 읽는지가 같이 시험된다.
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def bearer(**claims) -> dict[str, str]:
    """Supabase 접근 토큰 모양(헤더.페이로드.서명)의 Authorization 헤더. 서명은 가짜 — 확인은 /auth/v1/user 가 한다."""
    return {"Authorization": f"Bearer {_b64url({'alg': 'ES256', 'typ': 'JWT'})}.{_b64url(claims)}.signature"}


class AdminWorld:
    """ADMIN 한 명이 admin_users 에 있는 세상. 로그인한 사람은 caller 로 바꾼다."""

    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.caller = ADMIN
        self.auth_status = 200
        self.admins = {ADMIN}
        self.admin_lookup_status = 200
        self.action_insert_status = 201
        self.action_insert_code: str | None = None
        self.actions: list[dict] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(self.auth_status, json={"id": self.caller})
        if path == "/rest/v1/admin_users" and request.method == "GET":
            if self.admin_lookup_status >= 400:
                return httpx.Response(self.admin_lookup_status, json={})
            user_id = params["user_id"].removeprefix("eq.")
            return httpx.Response(200, json=[{"user_id": user_id}] if user_id in self.admins else [])
        if path == "/rest/v1/admin_actions" and request.method == "POST":
            if self.action_insert_status >= 400:
                payload = {"code": self.action_insert_code} if self.action_insert_code else {}
                return httpx.Response(self.action_insert_status, json=payload)
            self.actions.append(json.loads(request.content))
            return httpx.Response(201)
        raise AssertionError(f"관리자 가짜가 모르는 요청 {request.method} {path}")

    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
