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
PHOTO_SIGN_PREFIX = "/storage/v1/object/sign/profile-photos/"
# 신고 검수(D2). TARGET = 신고당한 사람, MATCH = 신고된 메시지가 있는 대화방.
TARGET = "dddddddd-0000-0000-0000-00000000000d"
MATCH = "eeeeeeee-0000-0000-0000-00000000000e"


def target_profile(**overrides) -> dict:
    """신고 줄에 임베드되는 신고당한 사람(target_profile:profiles!target_profile_id(...))."""
    return {"id": TARGET, "nickname": "여우비", "status": "active", "auto_hidden_at": None,
            "universities": {"name": "테스트대학교"}, **overrides}


def report(rid: str, *, target_type: str = "profile", target_id: str = TARGET, snapshot: dict | None = None,
           profile: dict | None | str = "default", status: str = "open",
           created_at: str = "2026-10-18T01:00:00+00:00") -> dict:
    """reports 한 줄 — 서버가 고르는 select(사본 + 대상 프로필 임베드)를 PostgREST 가 돌려주는 모양."""
    return {
        "id": rid, "target_type": target_type, "target_id": target_id, "reason": "abuse", "reason_note": None,
        "status": status, "created_at": created_at, "resolved_at": None,
        "target_profile": target_profile() if profile == "default" else profile,
        "target_snapshot": snapshot if snapshot is not None else {
            "nickname": "여우비", "bio": "안녕하세요", "avatar_path": f"{TARGET}/a.png",
            "photo_paths": [f"{TARGET}/1.jpg", f"{TARGET}/2.jpg"],
        },
    }


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
        # 신고 검수(D2). reports 는 id → 줄, other_reports 는 대상 → 같은 대상의 다른 신고(거른 뒤 모양),
        # open_reporters 는 대상 → 열린 신고들의 reporter_id, content 는 투표 글 · 리뷰 id → status,
        # messages 는 대화 줄들(PostgREST 처럼 match_id · created_at · id 로 거르고 정렬한다).
        self.reports: dict[str, dict] = {}
        self.other_reports: dict[str, list[dict]] = {}
        self.open_reporters: dict[str, list[str | None]] = {}
        self.content: dict[str, str] = {}
        self.messages: list[dict] = []
        self.unsignable_photos: set[str] = set()
        # 조치 DB 함수(D2 Task 1)들. profiles 는 id → {status, auto_hidden_at}, rpcs 는 (함수 이름, 본문) 순서대로.
        self.profiles: dict[str, dict] = {}
        self.rpcs: list[tuple[str, dict]] = []
        self.rpc_error_code: str | None = None

    def _act(self, name: str, body: dict) -> httpx.Response:
        """DB 함수와 같은 약속: 없으면 CM404, 이미 그 상태면 CM409. PostgREST 는 모르는 코드를 400 으로 보낸다."""
        def refuse(code: str) -> httpx.Response:
            return httpx.Response(400, json={"code": code, "message": "x"})

        if self.rpc_error_code:
            return refuse(self.rpc_error_code)
        if name == "admin_resolve_report":
            row = self.reports.get(body["p_report"])
            if row is None or row["status"] != "open":
                return refuse("CM404" if row is None else "CM409")
            row.update(status=body["p_outcome"], resolved_at="2026-10-18T02:00:00+00:00")
            return httpx.Response(200, json={"id": row["id"], "status": row["status"], "closed_ids": [row["id"]]})
        if name == "admin_set_content_status":
            status = self.content.get(body["p_content"])
            if status is None or status == body["p_status"]:
                return refuse("CM404" if status is None else "CM409")
            self.content[body["p_content"]] = body["p_status"]
            return httpx.Response(200, json={"id": body["p_content"], "status": body["p_status"]})
        profile = self.profiles.get(body["p_profile"])
        if profile is None:
            return refuse("CM404")
        if name == "admin_suspend_profile" and profile["status"] in ("pending", "active"):
            profile["status"] = "suspended"
        elif name == "admin_unsuspend_profile" and profile["status"] == "suspended":
            profile["status"] = "active"
        elif name == "admin_unhide_profile" and profile["auto_hidden_at"]:
            profile["auto_hidden_at"] = None
            return httpx.Response(200, json={"id": body["p_profile"], "auto_hidden_at": None, "dismissed_ids": []})
        else:
            return refuse("CM409")
        return httpx.Response(200, json={"id": body["p_profile"], "status": profile["status"]})

    def _reports(self, params) -> httpx.Response:
        # 네 조회를 params 키로 가른다 — 신고자 세기(select=reporter_id) · 같은 대상(target_profile_id) · 한 건(id) · 목록.
        if params.get("select") == "reporter_id":
            target = params["target_profile_id"].removeprefix("eq.")
            return httpx.Response(200, json=[{"reporter_id": r} for r in self.open_reporters.get(target, [])])
        if "target_profile_id" in params:
            return httpx.Response(200, json=self.other_reports.get(params["target_profile_id"].removeprefix("eq."), []))
        if "id" in params:
            row = self.reports.get(params["id"].removeprefix("eq."))
            return httpx.Response(200, json=[row] if row else [])
        return httpx.Response(200, json=list(self.reports.values()))

    def _messages(self, params) -> httpx.Response:
        rows = [m for m in self.messages if m["match_id"] == params["match_id"].removeprefix("eq.")]
        if "id" in params:
            rows = [m for m in rows if m["id"] == params["id"].removeprefix("eq.")]
        op, _, at = params.get("created_at", "").partition(".")
        if op == "lt":
            rows = [m for m in rows if m["created_at"] < at]
        elif op == "gt":
            rows = [m for m in rows if m["created_at"] > at]
        rows.sort(key=lambda m: m["created_at"], reverse=params.get("order") == "created_at.desc")
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        return httpx.Response(200, json=[{k: m[k] for k in ("id", "sender_id", "kind", "body", "created_at")} for m in rows])

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
        if path.startswith("/rest/v1/rpc/admin_") and request.method == "POST":
            name, body = path.removeprefix("/rest/v1/rpc/"), json.loads(request.content)
            self.rpcs.append((name, body))
            return self._act(name, body)
        if path == "/rest/v1/reports" and request.method == "GET":
            return self._reports(params)
        if path in ("/rest/v1/polls", "/rest/v1/friend_reviews") and request.method == "GET":
            status = self.content.get(params["id"].removeprefix("eq."))
            return httpx.Response(200, json=[{"status": status}] if status else [])
        if path == "/rest/v1/messages" and request.method == "GET":
            return self._messages(params)
        if path.startswith(PHOTO_SIGN_PREFIX) and request.method == "POST":
            object_path = path.removeprefix(PHOTO_SIGN_PREFIX)
            if object_path in self.unsignable_photos:
                return httpx.Response(400, json={"error": "not_found"})
            return httpx.Response(200, json={"signedURL": f"/object/sign/profile-photos/{object_path}?token=t"})
        raise AssertionError(f"관리자 가짜가 모르는 요청 {request.method} {path}")

    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
