"""관리자 관문 · 작업 기록 시험이 같이 쓰는 Supabase 가짜(관리자 대시보드 설계 10-18 §6 · §7).

요청은 URL 부분 문자열이 아니라 **경로 + params 키**로 가른다(메모 reference_backend_test_mock_traps ①).
모르는 요청은 바로 실패시킨다 — 관문이 엉뚱한 표를 부르면 조용히 [] 를 받고 통과하지 않게.
"""
import base64
import json
import time

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


def amr(hours_ago: float = 0, method: str = "totp") -> list[dict]:
    """Supabase 가 싣는 amr 모양 — 최근 순, 항목마다 방법과 그 방법을 마친 유닉스 초(supabase/auth models/sessions.go AMREntry)."""
    at = int(time.time() - hours_ago * 3600)
    return [{"method": method, "timestamp": at}, {"method": "oauth", "timestamp": at - 60}]


def bearer(**claims) -> dict[str, str]:
    """Supabase 접근 토큰 모양(헤더.페이로드.서명)의 Authorization 헤더. 서명은 가짜 — 확인은 /auth/v1/user 가 한다.
    aal2 면 방금 2단계(totp)를 마친 amr 을 기본으로 싣는다. 값이 None 인 클레임은 뺀다(amr=None = amr 칸 없음)."""
    if claims.get("aal") == "aal2":
        claims.setdefault("amr", amr())
    claims = {key: value for key, value in claims.items() if value is not None}
    return {"Authorization": f"Bearer {_b64url({'alg': 'ES256', 'typ': 'JWT'})}.{_b64url(claims)}.signature"}


def user_profile(uid: str, nickname: str | None = "하늘", *, status: str = "active", university: str | None = "테스트대학교",
                 created_at: str = "2026-09-30T00:00:00+00:00", avatar: str | None = None, **overrides) -> dict:
    """profiles 한 줄 — 서버가 고르는 select(학교 · 아바타 임베드 포함)를 PostgREST 가 돌려주는 모양."""
    return {
        "id": uid, "nickname": nickname, "status": status, "created_at": created_at,
        "last_active_at": "2026-10-18T00:00:00+00:00", "auto_hidden_at": None, "school_email_verified_at": created_at,
        "universities": None if university is None else {"name": university},
        "profile_avatars": [] if avatar is None else [{"storage_path": avatar, "status": "ready", "created_at": created_at}],
        **overrides,
    }


def _project(row: dict, select: str) -> dict:
    """PostgREST select 문자열("a,b,rel(c,d)")이 고르는 칸만 남긴다. 임베드 rel(...) 은 행에 같은 이름 칸이 있으면 통째로 싣는다."""
    names, depth, current = [], 0, ""
    for ch in select:
        depth += ch == "("
        depth -= ch == ")"
        if ch == "," and depth == 0:
            names.append(current)
            current = ""
        else:
            current += ch
    names.append(current)
    return {name.split("(")[0]: row[name.split("(")[0]] for name in names if name.split("(")[0] in row}


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
        self.rpc_error_message = "x"
        # 사용자 · 결제 · 작업 기록(D3). user_profiles 는 id → profiles 한 줄(PostgREST 가 고르는 모양), claims 는 school_email_claims 줄들,
        # report_targets 는 신고 한 건마다 신고당한 사람 id, balances / ledger / purchases / action_rows / contact_blocks 는 표 줄들,
        # auth_users 는 auth 관리자 API 의 사용자(identities), rpc_results 는 새 DB 함수 이름 → 돌려줄 JSON,
        # table_status 는 경로 → 그 경로를 통째로 실패시키는 상태 코드.
        self.user_profiles: dict[str, dict] = {}
        self.claims: list[dict] = []
        self.report_targets: list[str] = []
        self.balances: dict[str, int] = {}
        self.ledger: dict[str, list[dict]] = {}
        self.purchases: list[dict] = []
        self.action_rows: list[dict] = []
        self.contact_blocks: dict[str, int] = {}
        self.auth_users: dict[str, dict] = {}
        self.auth_user_status = 200
        self.rpc_results: dict[str, object] = {}
        self.table_status: dict[str, int] = {}
        # 열람(D3 Task 4): 복호화한 전화 · 카톡 아이디. 탈퇴 대행(Task 5): 푸시 토큰 삭제 · Storage 목록 · 카카오 연결 끊기의 응답 상태.
        self.phone: str | None = None
        self.kakao_id: str | None = None
        self.kakao_unlinks: list[httpx.Request] = []
        # get_settings 를 시험마다 바꾸는 값(예: {"kakao_admin_key": "..."}). conftest 의 람다가 요청마다 읽는다.
        self.settings_overrides: dict = {}

    def _act(self, name: str, body: dict) -> httpx.Response:
        """DB 함수와 같은 약속: 없으면 CM404, 이미 그 상태면 CM409. PostgREST 는 모르는 코드를 400 으로 보낸다."""
        def refuse(code: str, message: str = "x") -> httpx.Response:
            return httpx.Response(400, json={"code": code, "message": message})

        if self.rpc_error_code:
            return refuse(self.rpc_error_code, self.rpc_error_message)
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
        if params.get("select") == "id" and "target_profile_id" in params:  # 한 사람이 받은 신고 수(count=exact)
            target = params["target_profile_id"].removeprefix("eq.")
            return httpx.Response(200, json=[], headers={"Content-Range": f"*/{self.report_targets.count(target)}"})
        if params.get("target_profile_id", "").startswith("in."):  # 목록의 신고 수를 한 번에
            wanted = params["target_profile_id"].removeprefix("in.(").removesuffix(")").split(",")
            return httpx.Response(200, json=[{"target_profile_id": t} for t in self.report_targets if t in wanted])
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

    def _profiles(self, params) -> httpx.Response:
        rows = list(self.user_profiles.values())
        if params.get("id", "").startswith("eq."):
            rows = [r for r in rows if r["id"] == params["id"].removeprefix("eq.")]
        if params.get("id", "").startswith("in."):
            wanted = params["id"].removeprefix("in.(").removesuffix(")").split(",")
            rows = [r for r in rows if r["id"] in wanted]
        if params.get("id", "").startswith("not.in."):
            blocked = params["id"].removeprefix("not.in.(").removesuffix(")").split(",")
            rows = [r for r in rows if r["id"] not in blocked]
        if "nickname" in params:  # ilike.*패턴* — 이스케이프(백슬래시)를 풀어 부분 일치로 본다
            needle = params["nickname"].removeprefix("ilike.*").removesuffix("*").replace("\\", "")
            rows = [r for r in rows if r["nickname"] and needle.lower() in r["nickname"].lower()]
        if params.get("order") == "created_at.desc":
            rows.sort(key=lambda r: r["created_at"], reverse=True)
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        if params.get("select") == "status":
            rows = [{"status": r["status"]} for r in rows]
        return httpx.Response(200, json=rows)

    def _admin_actions_get(self, params) -> httpx.Response:
        rows = list(self.action_rows)
        for column in ("action", "target_type", "target_id", "admin_user_id"):
            if column in params:
                rows = [r for r in rows if r[column] == params[column].removeprefix("eq.")]
        rows.sort(key=lambda r: (r["created_at"], r["id"]), reverse=True)
        if "or" in params:  # or=(created_at.lt.X,and(created_at.eq.X,id.lt.Y))
            first, rest = params["or"][1:-1].split(",and(", 1)
            at, last_id = first.removeprefix("created_at.lt."), rest.removesuffix(")").split(",id.lt.")[1]
            rows = [r for r in rows if r["created_at"] < at or (r["created_at"] == at and r["id"] < last_id)]
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        return httpx.Response(200, json=rows)

    def _new_rpc(self, name: str, body: dict) -> httpx.Response:
        """D3 의 DB 함수들. 돌려줄 값은 rpc_results[name], 오류는 rpc_error_code(D2 와 같은 약속)."""
        self.rpcs.append((name, body))
        if self.rpc_error_code:
            return httpx.Response(400, json={"code": self.rpc_error_code, "message": self.rpc_error_message})
        return httpx.Response(200, json=self.rpc_results.get(name, [] if name.startswith("admin_billing_") else {}))

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(self.auth_status, json={"id": self.caller})
        if path == "/rest/v1/admin_users" and request.method == "GET":
            if self.admin_lookup_status >= 400:
                return httpx.Response(self.admin_lookup_status, json={})
            if "user_id" not in params:  # 명단 전체(사용자 목록에서 관리자를 뺄 때)
                return httpx.Response(200, json=[{"user_id": a} for a in sorted(self.admins)])
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
        d3 = self._d3(request, path, params)
        if d3 is not None:
            return d3
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

    def _d3(self, request: httpx.Request, path: str, params) -> httpx.Response | None:
        """D3(사용자 · 결제 · 작업 기록)가 부르는 곳. 모르는 요청은 None 이라 D2 분기와 마지막 AssertionError 로 간다."""
        method = request.method
        if path in self.table_status:  # 경로 하나를 통째로 실패시킨다
            return httpx.Response(self.table_status[path], json={})
        if path == "/rest/v1/profiles" and method == "GET":
            return self._profiles(params)
        if path == "/rest/v1/school_email_claims" and method == "GET":
            key, value = next((k, v) for k, v in params.items() if k in ("school_email_hmac", "profile_id"))
            rows = [c for c in self.claims if c[key] == value.removeprefix("eq.")]
            return httpx.Response(200, json=[{k: c[k] for k in ("profile_id", "school_email_hmac", "key_version")} for c in rows])
        if path == "/rest/v1/entitlements" and method == "GET":
            uid = params["profile_id"].removeprefix("eq.")
            return httpx.Response(200, json=[{"heart_balance": self.balances[uid]}] if uid in self.balances else [])
        if path == "/rest/v1/heart_transactions" and method == "GET":
            return httpx.Response(200, json=self.ledger.get(params["profile_id"].removeprefix("eq."), []))
        if path == "/rest/v1/contact_blocks" and method == "GET":
            count = self.contact_blocks.get(params["owner_id"].removeprefix("eq."), 0)
            return httpx.Response(200, json=[], headers={"Content-Range": f"*/{count}"})
        if path == "/rest/v1/purchases" and method == "GET":
            key = "profile_id" if "profile_id" in params else "store_order_id"
            rows = [r for r in self.purchases if r[key] == params[key].removeprefix("eq.")]
            if "limit" in params:
                rows = rows[:int(params["limit"])]
            # PostgREST 는 select 에 적은 칸만 돌려준다 — 서버가 주문 번호 · 토큰 해시를 고르지 않았는지 시험이 볼 수 있게 같이 자른다.
            return httpx.Response(200, json=[_project(r, params["select"]) for r in rows])
        if path == "/rest/v1/admin_actions" and method == "GET":
            return self._admin_actions_get(params)
        if path.startswith("/auth/v1/admin/users/") and method == "GET":
            user = self.auth_users.get(path.removeprefix("/auth/v1/admin/users/"))
            if self.auth_user_status >= 400 or user is None:
                return httpx.Response(self.auth_user_status if self.auth_user_status >= 400 else 404, json={})
            return httpx.Response(200, json=user)
        if path == "/rest/v1/push_tokens" and method == "DELETE":
            return httpx.Response(204)
        if path == "/storage/v1/object/list/student-id-temp" and method == "POST":
            return httpx.Response(200, json=[])
        if path == "/v1/user/unlink" and method == "POST":  # 카카오(kapi.kakao.com) 연결 끊기
            self.kakao_unlinks.append(request)
            return httpx.Response(200, json={"id": 1})
        if path == "/rest/v1/rpc/decrypt_phone_number" and method == "POST":
            return httpx.Response(200, content=json.dumps(self.phone), headers={"content-type": "application/json"})
        if path == "/rest/v1/rpc/decrypt_profile_private" and method == "POST":
            return httpx.Response(200, json=[{"real_name": None, "kakao_id": self.kakao_id}])
        if path in ("/rest/v1/rpc/admin_adjust_hearts", "/rest/v1/rpc/admin_close_account", "/rest/v1/rpc/admin_billing_daily",
                    "/rest/v1/rpc/admin_billing_shortfall") and method == "POST":
            return self._new_rpc(path.removeprefix("/rest/v1/rpc/"), json.loads(request.content))
        return None

    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
