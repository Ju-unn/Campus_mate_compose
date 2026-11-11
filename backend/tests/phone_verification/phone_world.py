"""휴대폰 문자 인증(POST /phone-verification/*) 시험이 같이 쓰는 Supabase 가짜.

요청은 URL 부분 문자열이 아니라 **경로 + params 키**로 가른다(메모 reference_backend_test_mock_traps ①).
모르는 요청은 바로 실패시킨다. 세 RPC 는 DB 함수(20261111010000)의 겉모양만 흉내 낸다 — 한도 · 잠금 판정 자체는
supabase/tests/phone_verifications_test.sql 이 진짜 DB 에서 본다. 여기서는 서버가 그 결과를 어떻게 다루는지만 본다.
"""
import json

import httpx

from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"
USER_AUTH = {"Authorization": "Bearer valid-token"}
LOCAL_URL = "http://127.0.0.1:54321"
PRODUCTION_URL = "https://x.supabase.co"


def settings(**overrides) -> Settings:
    """기본은 로컬 스택 주소다 — 가짜 문자 발송이 허락되는 자리."""
    values = dict(
        supabase_url=LOCAL_URL, supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    return Settings(**{**values, **overrides})


def _hex(value: str) -> str:
    """PostgREST 가 bytea 를 주고받는 모양(`\\x…`)에서 hex 만."""
    return value.removeprefix("\\x")


class PhoneWorld:
    """ME 한 명이 로그인한 세상. rows 는 phone_verifications 줄(가장 뒤가 가장 최근)."""

    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.caller = ME
        self.rows: list[dict] = []
        # 보내기 결과를 정해 두면 그대로 돌려준다(한도 · in_use 같은 DB 판정). None 이면 아래 흉내로 판정한다.
        self.issue_result: dict | None = None
        self.save_result = "saved"
        self.discord: list[str] = []
        self.delete_status = 204
        self._next = 0

    # ------------------------------------------------------------------
    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]

    def rpc_bodies(self, name: str) -> list[dict]:
        return [json.loads(r.content) for r in self.calls("POST", f"/rest/v1/rpc/{name}")]

    def cooldown_passes(self) -> None:
        """1분이 지났다 — 지금까지 보낸 줄은 다시 받기 대기를 막지 않는다."""
        for row in self.rows:
            row["fresh"] = False

    def expire_all(self) -> None:
        for row in self.rows:
            row["expired"] = True

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params, method = request.url.path, request.url.params, request.method
        if request.url.host == "discord.com":
            self.discord.append(json.loads(request.content)["content"])
            return httpx.Response(204)
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": self.caller})
        if path == "/rest/v1/profiles" and method == "GET" and "select" in params:
            # get_verified_caller 의 관문 조회 — 학교 메일 · 학과까지 끝낸 활동 계정.
            return httpx.Response(200, json=[{
                "student_verification": "verified", "department": "경영학과", "status": "active",
                "school_email_verified_at": "2026-10-01T00:00:00+00:00",
            }])
        if path == "/rest/v1/rpc/issue_phone_verification":
            return self._issue(json.loads(request.content))
        if path == "/rest/v1/rpc/attempt_phone_verification":
            return self._attempt(json.loads(request.content))
        if path == "/rest/v1/rpc/save_verified_phone_number":
            return httpx.Response(200, json=self.save_result)
        if path == "/rest/v1/phone_verifications" and method == "DELETE":
            target = params["id"].removeprefix("eq.")
            self.rows = [r for r in self.rows if r["id"] != target]
            return httpx.Response(self.delete_status)
        if path == "/rest/v1/phone_verifications" and method == "PATCH":
            target = params["id"].removeprefix("eq.")
            assert params["verified_at"] == "is.null"
            for row in self.rows:
                if row["id"] == target:
                    row["verified"] = True
            return httpx.Response(204)
        raise AssertionError(f"문자 인증 가짜가 모르는 요청 {method} {path}")

    # ------------------------------------------------------------------
    def _latest(self, profile_id: str, phone_hmac: str) -> dict | None:
        mine = [r for r in self.rows if r["profile_id"] == profile_id and r["phone_hmac"] == phone_hmac]
        return mine[-1] if mine else None

    def _issue(self, body: dict) -> httpx.Response:
        if self.issue_result is not None:
            return httpx.Response(200, json=[self.issue_result])
        profile_id, phone_hmac = body["p_profile_id"], _hex(body["p_phone_hmac"])
        last = self._latest(profile_id, phone_hmac)
        if last is not None and last["fresh"]:
            return httpx.Response(200, json=[{
                "result": "already_sent", "verification_id": last["id"], "retry_after_seconds": 42,
                "expires_in_seconds": 162, "global_limit_reached": False,
            }])
        self._next += 1
        row = {"id": f"00000000-0000-0000-0000-{self._next:012d}", "profile_id": profile_id,
               "phone_hmac": phone_hmac, "code_hash": _hex(body["p_code_hash"]), "attempts": 0,
               "verified": False, "expired": False, "fresh": True}
        self.rows.append(row)
        return httpx.Response(200, json=[{
            "result": "issued", "verification_id": row["id"], "retry_after_seconds": 60,
            "expires_in_seconds": 180, "global_limit_reached": False,
        }])

    def _attempt(self, body: dict) -> httpx.Response:
        row = self._latest(body["p_profile_id"], _hex(body["p_phone_hmac"]))
        if row is None:
            answer = {"result": "expired", "verification_id": None, "code_hash": None, "attempts_left": 0}
        elif row["verified"]:
            answer = {"result": "verified", "verification_id": row["id"], "code_hash": None,
                      "attempts_left": 5 - row["attempts"]}
        elif row["expired"]:
            answer = {"result": "expired", "verification_id": row["id"], "code_hash": None,
                      "attempts_left": 5 - row["attempts"]}
        elif row["attempts"] >= 5:
            answer = {"result": "locked", "verification_id": row["id"], "code_hash": None, "attempts_left": 0}
        else:
            row["attempts"] += 1
            answer = {"result": "check", "verification_id": row["id"], "code_hash": "\\x" + row["code_hash"],
                      "attempts_left": 5 - row["attempts"]}
        return httpx.Response(200, json=[answer])
