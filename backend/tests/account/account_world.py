"""탈퇴 · 정리 배치 · 카톡 아이디 테스트가 같이 쓰는 Supabase 가짜(auth admin · Storage · PostgREST).

요청은 경로 + params **키**로 가른다(메모 reference_backend_test_mock_traps ①). 상태를 들고 있어
"탈퇴 → 다시 부르면 401", "정리 → 다시 돌리면 0건" 처럼 앞 요청이 뒤 요청의 답을 바꾸는 흐름을 그대로 흉내 낸다.
"""
import json
from datetime import datetime, timedelta

import httpx

from app.core.time import SEOUL
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
OLD = "22222222-2222-2222-2222-222222222222"     # 31일 전 탈퇴
RECENT = "33333333-3333-3333-3333-333333333333"  # 29일 전 탈퇴
AUTH = {"Authorization": "Bearer user-token"}
EMAIL = "Hong@SNU.ac.kr"
NOW = datetime(2026, 9, 27, 4, 0, tzinfo=SEOUL)
BUCKETS = ("avatars", "profile-photos", "student-id-temp", "heart-task-proofs")
INFINITY = datetime.max.replace(tzinfo=SEOUL)


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


def _when(filter_value: str) -> datetime:
    return datetime.fromisoformat(filter_value.split(".", 1)[1])


class AccountWorld:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.caller = ME
        self.profiles: dict[str, dict] = {
            ME: {"status": "active", "withdrawn_at": None, "student_verification": "verified", "department": "컴공",
                 "birth_year": 2003, "created_at": "2026-09-01T10:00:00+00:00", "university": "서울대학교"},
        }
        self.emails: dict[str, str] = {ME: EMAIL}
        self.files: dict[str, dict[str, list[str]]] = {
            bucket: {ME: ["a.png"]} for bucket in BUCKETS
        }
        self.push_tokens: dict[str, list[str]] = {ME: ["tok-1", "tok-2"]}
        self.kakao_ids: dict[str, str] = {}
        self.real_names: dict[str, str] = {}
        self.reports: list[dict] = []          # {id, created_at, resolved_at}
        self.signup_blocks: list[dict] = []    # {email_hmac, blocked_until}
        self.contact_key_versions: list[int] = []
        self.fail: set[str] = set()            # "DELETE /storage/v1/object/avatars" 처럼 막을 요청
        self.withdraw_bodies: list[dict] = []

    def withdrawn(self, profile_id: str, days_ago: int) -> None:
        """days_ago 일 전에 탈퇴한 사람을 세상에 둔다(버킷마다 파일 하나씩)."""
        self.profiles[profile_id] = {"status": "withdrawn", "withdrawn_at": NOW - timedelta(days=days_ago)}
        self.emails[profile_id] = f"{profile_id[:4]}@snu.ac.kr"
        for bucket in BUCKETS:
            self.files[bucket][profile_id] = ["x.jpg"]

    # ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path = request.url.path
        if any(f"{request.method} {path}".startswith(rule) for rule in self.fail):
            return httpx.Response(500, json={"message": "boom"})
        body = json.loads(request.content) if request.content else None
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": self.caller})
        if path.startswith("/auth/v1/admin/users/"):
            return self._admin_user(request.method, path.rsplit("/", 1)[1])
        if path == "/auth/v1/logout":
            return httpx.Response(204)
        if path.startswith("/storage/v1/object/list/"):
            bucket = path.rsplit("/", 1)[1]
            owner = body["prefix"].rstrip("/")
            return httpx.Response(200, json=[{"name": n, "id": f"obj-{n}", "metadata": {}}
                                             for n in self.files[bucket].get(owner, [])])
        if path.startswith("/storage/v1/object/"):
            bucket = path.rsplit("/", 1)[1]
            gone = []
            for prefix in body["prefixes"]:
                owner, name = prefix.split("/", 1)
                if name in self.files[bucket].get(owner, []):
                    self.files[bucket][owner].remove(name)
                    gone.append({"name": prefix})
            return httpx.Response(200, json=gone)
        table = path.removeprefix("/rest/v1/")
        return getattr(self, "_" + table.replace("/", "_"))(request.method, request.url.params, body)

    def _admin_user(self, method: str, user_id: str) -> httpx.Response:
        if user_id not in self.emails:
            return httpx.Response(404, json={"msg": "User not found"})
        if method == "DELETE":
            # auth.users 삭제가 profiles 로 cascade 된다(pr3-db-report §2).
            del self.emails[user_id]
            self.profiles.pop(user_id, None)
            return httpx.Response(200, json={"id": user_id})
        return httpx.Response(200, json={"id": user_id, "email": self.emails[user_id]})

    def _eq(self, params: httpx.QueryParams, key: str) -> str | None:
        value = params.get(key)
        return value.removeprefix("eq.") if value else None

    # 테이블별 ----------------------------------------------------------------
    def _profiles(self, method, params, body):
        if "withdrawn_at" in params:
            assert params["status"] == "eq.withdrawn"
            cutoff = _when(params["withdrawn_at"])
            rows = [{"id": pid} for pid, p in self.profiles.items()
                    if p["status"] == "withdrawn" and p["withdrawn_at"] < cutoff]
            return httpx.Response(200, json=rows[:int(params["limit"])])
        row = self.profiles.get(self._eq(params, "id"))
        if row is None:
            return httpx.Response(200, json=[])
        if "created_at" in params["select"]:
            return httpx.Response(200, json=[{"birth_year": row["birth_year"], "created_at": row["created_at"],
                                              "universities": {"name": row["university"]}}])
        if "student_verification" in params["select"]:
            return httpx.Response(200, json=[{"student_verification": row.get("student_verification"),
                                              "department": row.get("department"), "status": row["status"]}])
        return httpx.Response(200, json=[{"status": row["status"]}])

    def _heart_task_submissions(self, method, params, body):
        return httpx.Response(200, json=[])

    def _rpc_withdraw_account(self, method, params, body):
        self.withdraw_bodies.append(body)
        row = self.profiles.get(body["p_profile_id"])
        if row and row["status"] != "withdrawn":
            row.update(status="withdrawn", withdrawn_at=NOW)
        return httpx.Response(204)

    def _push_tokens(self, method, params, body):
        assert method == "DELETE"
        self.push_tokens.pop(self._eq(params, "profile_id"), None)
        return httpx.Response(204)

    def _profile_private(self, method, params, body):
        owner = self._eq(params, "profile_id")
        row = {"kakao_id": self.kakao_ids.get(owner), "real_name": self.real_names.get(owner)}
        if not any(row.values()):
            return httpx.Response(200, json=[])
        return httpx.Response(200, json=[{column: row[column] for column in params["select"].split(",")}])

    def _reports(self, method, params, body):
        assert method == "DELETE"
        # 보낸 날짜 조건(lt.)을 전부 건다. SQL `<` 처럼 null(열린 신고의 resolved_at)은 걸리지 않는다.
        cutoffs = {column: _when(value) for column, value in params.items() if column != "select"}
        assert cutoffs
        gone = [r for r in self.reports
                if all(r[column] is not None and r[column] < cutoff for column, cutoff in cutoffs.items())]
        self.reports = [r for r in self.reports if r not in gone]
        return httpx.Response(200, json=[{"id": r["id"]} for r in gone])

    def _signup_blocks(self, method, params, body):
        assert method == "DELETE"
        cutoff = _when(params["blocked_until"])
        gone = [b for b in self.signup_blocks if b["blocked_until"] < cutoff]
        self.signup_blocks = [b for b in self.signup_blocks if b not in gone]
        return httpx.Response(200, json=[{"key_version": 1} for _ in gone])

    def _contact_blocks(self, method, params, body):
        other = int(params["key_version"].removeprefix("neq."))
        stale = sum(1 for version in self.contact_key_versions if version != other)
        return httpx.Response(200, json=[], headers={"Content-Range": f"*/{stale}"})

    # 도우미 ------------------------------------------------------------------
    def calls(self, method: str, path: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path == path]
