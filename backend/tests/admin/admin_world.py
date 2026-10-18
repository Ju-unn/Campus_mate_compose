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
SIGN_PREFIX = "/storage/v1/object/sign/heart-task-proofs/"


def submission(sid: str, profile_id: str = "cccccccc-0000-0000-0000-00000000000a", *, task: str = "everytime_post",
               path: str | None = "default", created_at: str = "2026-10-18T01:00:00+00:00") -> dict:
    """heart_task_submissions 한 줄 — 서버가 고르는 select(프로필 · 학교 임베드)를 PostgREST 가 돌려주는 모양."""
    return {
        "id": sid, "task": task, "status": "submitted", "reject_reason": None, "reward_hearts": 40,
        "created_at": created_at, "reviewed_at": None,
        "storage_path": f"{profile_id}/{sid}.jpg" if path == "default" else path,
        "profiles": {"id": profile_id, "nickname": "하늘", "universities": {"name": "테스트대학교"}},
    }


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
        # 인증샷 검수(D1). submissions 는 id → 줄, previous 는 제출자 id → 지난 제출 줄들(PostgREST 가 거른 뒤의 모양).
        self.submissions: dict[str, dict] = {}
        self.previous: dict[str, list[dict]] = {}
        self.unsignable: set[str] = set()
        # 경로 → Storage 서명 응답을 통째로 바꾼다(200 인데 signedURL 이 없거나 JSON 이 아닌 응답 같은 것).
        self.sign_replies: dict[str, httpx.Response] = {}
        self.review_error_code: str | None = None

    def _heart_task_submissions(self, params) -> httpx.Response:
        # 세 조회를 params 키로 가른다 — 지난 제출(profile_id) · 목록(status) · 한 건(id=eq.).
        if "profile_id" in params:
            return httpx.Response(200, json=self.previous.get(params["profile_id"].removeprefix("eq."), []))
        if "status" in params:
            return httpx.Response(200, json=list(self.submissions.values()))
        row = self.submissions.get(params["id"].removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    def _review(self, body: dict) -> httpx.Response:
        # DB 함수와 같은 약속: 없으면 CM404, 검수 중이 아니면 CM409. PostgREST 는 모르는 코드를 400 으로 보낸다.
        row = self.submissions.get(body["p_submission"])
        code = self.review_error_code or ("CM404" if row is None else "CM409" if row["status"] != "submitted" else None)
        if code:
            return httpx.Response(400, json={"code": code, "message": "x"})
        row.update(status=body["p_status"], reject_reason=body["p_reject_reason"], reviewed_at="2026-10-18T02:00:00+00:00")
        return httpx.Response(200, json={key: row[key] for key in ("id", "status", "reject_reason", "reward_hearts", "reviewed_at")})

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
        if path == "/rest/v1/heart_task_submissions" and request.method == "GET":
            return self._heart_task_submissions(params)
        if path == "/rest/v1/rpc/admin_review_heart_task" and request.method == "POST":
            return self._review(json.loads(request.content))
        if path.startswith(SIGN_PREFIX) and request.method == "POST":
            object_path = path.removeprefix(SIGN_PREFIX)
            if object_path in self.sign_replies:
                return self.sign_replies[object_path]
            if object_path in self.unsignable:
                return httpx.Response(400, json={"error": "not_found"})
            return httpx.Response(200, json={"signedURL": f"/object/sign/heart-task-proofs/{object_path}?token=t"})
        raise AssertionError(f"관리자 가짜가 모르는 요청 {request.method} {path}")

    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
