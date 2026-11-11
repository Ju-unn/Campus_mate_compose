"""문의하기(POST /inquiries · /admin/inquiries) 시험이 같이 쓰는 Supabase 가짜.

요청은 URL 부분 문자열이 아니라 **경로 + params 키**로 가른다(메모 reference_backend_test_mock_traps ①).
모르는 요청은 바로 실패시킨다. inquiries 표는 PostgREST 처럼 필터 · 정렬 · limit 을 흉내 낸다.
"""
import base64
import json
import re
import time
from datetime import datetime

import httpx

from app.core.time import SEOUL
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
ADMIN = "aaaaaaaa-0000-0000-0000-000000000001"
STRANGER = "bbbbbbbb-0000-0000-0000-000000000002"
NOW = datetime(2026, 11, 10, 14, 0, tzinfo=SEOUL)
USER_AUTH = {"Authorization": "Bearer valid-token"}


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


def _b64url(obj) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def admin_auth(**claims) -> dict[str, str]:
    """2단계(aal2 + 방금 마친 totp)를 마친 Supabase 접근 토큰 모양. 서명은 가짜 — 확인은 /auth/v1/user 가 한다."""
    claims = {"aal": "aal2", "amr": [{"method": "totp", "timestamp": int(time.time())}], **claims}
    claims = {key: value for key, value in claims.items() if value is not None}
    return {"Authorization": f"Bearer {_b64url({'alg': 'ES256'})}.{_b64url(claims)}.signature"}


def row(inquiry_id: str, *, created_at: str = "2026-11-10T01:00:00+00:00", profile_id: str | None = ME,
        status: str = "new", answered_at: str | None = None, **overrides) -> dict:
    """inquiries 한 줄(DB 에 저장된 모양)."""
    return {
        "id": inquiry_id, "profile_id": profile_id, "reason": "bug", "body": "앱이 멈춰요",
        "reply_email": "me@example.com", "status": status, "admin_memo": None,
        "created_at": created_at, "updated_at": created_at, "answered_at": answered_at, **overrides,
    }


class InquiryWorld:
    """ME 한 명이 로그인한 세상. 로그인한 사람은 caller, 그 사람의 계정 상태는 status 로 바꾼다."""

    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.caller = ME
        self.auth_status = 200
        self.status = "active"              # profiles.status — suspended 여도 문의는 된다
        self.profile_ids = {ME, STRANGER}   # profiles 에 있는 사람. 없는 사람의 insert 는 FK(23503)로 막힌다
        self.admins = {ADMIN}
        self.inquiries: list[dict] = []
        self.actions: list[dict] = []
        self.insert_status = 201
        self.insert_code: str | None = None   # insert 가 실패할 때 PostgREST 가 싣는 Postgres 오류 코드
        self.action_insert_status = 201
        # 문의 알림 메일이 읽는 쓴 사람의 닉네임 · 학교(profiles select=nickname,universities(name)).
        self.nickname: str | None = "하늘"
        self.school: str | None = "테스트대학교"
        self.author_read_status = 200
        self._next = 0

    # ------------------------------------------------------------------
    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params, method = request.url.path, request.url.params, request.method
        if path == "/auth/v1/user":
            return httpx.Response(self.auth_status, json={"id": self.caller})
        if path == "/rest/v1/profiles" and method == "GET" and params.get("select") == "nickname,universities(name)":
            return self._author(params)
        if path == "/rest/v1/profiles" and method == "GET":
            return httpx.Response(200, json=[{"status": self.status}] if self.caller in self.profile_ids else [])
        if path == "/rest/v1/admin_users" and method == "GET":
            user_id = params["user_id"].removeprefix("eq.")
            return httpx.Response(200, json=[{"user_id": user_id}] if user_id in self.admins else [])
        if path == "/rest/v1/admin_actions" and method == "POST":
            if self.action_insert_status >= 400:
                return httpx.Response(self.action_insert_status, json={})
            self.actions.append(json.loads(request.content))
            return httpx.Response(201)
        if path == "/rest/v1/inquiries":
            return {"GET": self._get, "POST": self._post, "PATCH": self._patch}[method](request, params)
        raise AssertionError(f"문의 가짜가 모르는 요청 {method} {path}")

    # ------------------------------------------------------------------
    def _author(self, params) -> httpx.Response:
        if self.author_read_status >= 400:
            return httpx.Response(self.author_read_status, json={})
        if params["id"].removeprefix("eq.") not in self.profile_ids:
            return httpx.Response(200, json=[])
        university = {"name": self.school} if self.school is not None else None
        return httpx.Response(200, json=[{"nickname": self.nickname, "universities": university}])

    def _embed(self, stored: dict) -> dict:
        """select 의 profile:profiles(id,nickname,universities(name)) 임베드. 프로필이 없으면 null."""
        shown = {k: v for k, v in stored.items() if k != "profile_id"}
        shown["profile"] = None if stored["profile_id"] not in self.profile_ids else {
            "id": stored["profile_id"], "nickname": "하늘", "universities": {"name": "테스트대학교"},
        }
        return shown

    def _get(self, request: httpx.Request, params) -> httpx.Response:
        rows = list(self.inquiries)
        if "profile_id" in params:
            rows = [r for r in rows if r["profile_id"] == params["profile_id"].removeprefix("eq.")]
        if "created_at" in params:
            rows = [r for r in rows if r["created_at"] >= params["created_at"].removeprefix("gte.")]
        if "status" in params:
            rows = [r for r in rows if r["status"] == params["status"].removeprefix("eq.")]
        if "or" in params:
            at, last_id = re.fullmatch(
                r"\(created_at\.lt\.(.+),and\(created_at\.eq\.\1,id\.lt\.(.+)\)\)", params["or"]).groups()
            rows = [r for r in rows if r["created_at"] < at or (r["created_at"] == at and r["id"] < last_id)]
        if "id" in params:
            rows = [r for r in rows if r["id"] == params["id"].removeprefix("eq.")]
        if params.get("order") == "created_at.desc,id.desc":
            rows.sort(key=lambda r: (r["created_at"], r["id"]), reverse=True)
        rows = rows[: int(params["limit"])] if "limit" in params else rows
        select = params.get("select", "")
        return httpx.Response(200, json=[self._embed(r) if "profile:" in select else {"id": r["id"]} for r in rows])

    def _post(self, request: httpx.Request, params) -> httpx.Response:
        body = json.loads(request.content)
        if self.insert_status >= 400:
            return httpx.Response(self.insert_status, json={"code": self.insert_code} if self.insert_code else {})
        if body["profile_id"] is not None and body["profile_id"] not in self.profile_ids:
            return httpx.Response(409, json={"code": "23503"})
        self._next += 1
        stored = row(f"00000000-0000-0000-0000-{self._next:012d}", created_at=NOW.isoformat(), **body)
        self.inquiries.append(stored)
        return httpx.Response(201, json=[stored])

    def _patch(self, request: httpx.Request, params) -> httpx.Response:
        target = params["id"].removeprefix("eq.")
        changed = [r for r in self.inquiries if r["id"] == target]
        for r in changed:
            r.update(json.loads(request.content))
        return httpx.Response(200, json=[self._embed(r) for r in changed])
