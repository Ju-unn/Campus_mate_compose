"""탈퇴 · 정리 배치 · 카톡 아이디 테스트가 같이 쓰는 Supabase 가짜(auth admin · Storage · PostgREST).

요청은 경로 + params **키**로 가른다(메모 reference_backend_test_mock_traps ①). 상태를 들고 있어
"탈퇴 → 다시 부르면 401", "정리 → 다시 돌리면 0건" 처럼 앞 요청이 뒤 요청의 답을 바꾸는 흐름을 그대로 흉내 낸다.
"""
import json
from datetime import datetime, timedelta, timezone

import httpx

from app.core.time import SEOUL
from app.settings import Settings
from app.signup_policy import bytea_literal, hash_email

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
                 "school_email_verified_at": "2026-09-01T10:30:00+00:00",
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
        # school_email_claims(학교 메일 인증 기록) — profile_id → {school_email_hmac(bytea 리터럴), key_version}.
        # ME 는 학교 메일(EMAIL)로 인증을 마친 사람이다. 탈퇴의 재가입 제한 해시는 이 행에서 온다(auth 의 email 이 아니다).
        self.claims: dict[str, dict] = {
            ME: {"school_email_hmac": bytea_literal(hash_email("identity-key-test", EMAIL)), "key_version": 1},
        }
        self.claims_unreachable = False
        self.unverified_lookups: list[dict] = []
        # RPC 가 고른 뒤 그 사이 인증을 마친 사람처럼, 조건과 상관없이 RPC 결과에 끼워 넣을 id
        self.stale_unverified: list[str] = []
        # 프로필 재확인(id 하나 읽기)이 실패할 id
        self.unreadable_profiles: set[str] = set()
        # GET /auth/v1/admin/users 목록(관리자 API). 기본은 카카오 가입자 ME 하나.
        self.auth_users: dict[str, dict] = {
            ME: {"id": ME, "created_at": "2026-09-01T10:00:00Z",
                 "identities": [{"provider": "kakao"}], "app_metadata": {"provider": "kakao"}},
        }
        self.admin_list_status = 200
        self.admin_list_requests: list[httpx.Request] = []
        # GET /auth/v1/user 의 identities(탈퇴 때 카카오 연결 끊기가 본다). 기본은 카카오 가입자.
        self.identities: list[dict] = [{"provider": "kakao", "identity_data": {"sub": "4242"}}]
        self.kakao_unlinks: list[httpx.Request] = []
        self.kakao_unlink_status = 200
        self.kakao_unreachable = False
        self.settings_overrides: dict = {}

    def withdrawn(self, profile_id: str, days_ago: int) -> None:
        """days_ago 일 전에 탈퇴한 사람을 세상에 둔다(버킷마다 파일 하나씩)."""
        self.profiles[profile_id] = {"status": "withdrawn", "withdrawn_at": NOW - timedelta(days=days_ago)}
        self.emails[profile_id] = f"{profile_id[:4]}@snu.ac.kr"
        for bucket in BUCKETS:
            self.files[bucket][profile_id] = ["x.jpg"]

    def unverified(self, profile_id: str, days_ago: int) -> None:
        """days_ago 일 전에 소셜로 가입하고 학교 메일 확인을 안 한 사람(버킷마다 파일 하나씩)."""
        self.profiles[profile_id] = {"status": "active", "withdrawn_at": None, "school_email_verified_at": None,
                                     "signed_up_at": NOW - timedelta(days=days_ago)}
        self.emails[profile_id] = ""
        for bucket in BUCKETS:
            self.files[bucket][profile_id] = ["u.jpg"]

    def temp_email_account(self, user_id: str, hours_ago: int, with_profile: bool = False) -> None:
        """학교 메일 인증용 임시 계정(provider=email 하나뿐). 서버가 지우지 못하고 남은 잔여물."""
        created = (NOW - timedelta(hours=hours_ago)).astimezone(timezone.utc)
        self.auth_users[user_id] = {
            "id": user_id, "created_at": created.isoformat().replace("+00:00", "Z"),
            "identities": [{"provider": "email"}], "app_metadata": {"provider": "email"},
        }
        self.emails[user_id] = f"{user_id[:4]}@snu.ac.kr"
        if with_profile:
            # 소셜 전환 전 학교 메일 OTP 로 가입한 옛 계정 — 프로필이 있어 지우면 안 된다.
            self.profiles[user_id] = {"status": "active", "withdrawn_at": None,
                                      "school_email_verified_at": "2026-09-01T00:00:00+00:00"}

    # ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path = request.url.path
        if any(f"{request.method} {path}".startswith(rule) for rule in self.fail):
            return httpx.Response(500, json={"message": "boom"})
        if request.url.host == "kapi.kakao.com":
            assert path == "/v1/user/unlink"
            self.kakao_unlinks.append(request)
            if self.kakao_unreachable:
                raise httpx.ConnectError("연결 실패", request=request)
            return httpx.Response(self.kakao_unlink_status, json={"id": 4242})
        body = json.loads(request.content) if request.content else None
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": self.caller, "identities": self.identities})
        if path == "/auth/v1/admin/users":
            return self._admin_list(request)
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

    def _admin_list(self, request: httpx.Request) -> httpx.Response:
        """GoTrue `GET /admin/users?page=&per_page=` — {"users": [...]} 를 한 쪽씩 돌려준다(1부터)."""
        assert request.method == "GET"
        assert request.headers["authorization"] == "Bearer service-key"
        self.admin_list_requests.append(request)
        if self.admin_list_status != 200:
            return httpx.Response(self.admin_list_status, json={"msg": "boom"})
        page, per_page = int(request.url.params["page"]), int(request.url.params["per_page"])
        users = [u for uid, u in self.auth_users.items() if uid in self.emails]
        return httpx.Response(200, json={"users": users[(page - 1) * per_page: page * per_page]})

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
        profile_id = self._eq(params, "id")
        if params.get("select") in ("id", "school_email_verified_at") and profile_id in self.unreadable_profiles:
            return httpx.Response(500, json={"message": "boom"})
        row = self.profiles.get(profile_id)
        if row is None:
            return httpx.Response(200, json=[])
        if params["select"] == "id":
            return httpx.Response(200, json=[{"id": profile_id}])
        if params["select"] == "school_email_verified_at":
            return httpx.Response(200, json=[{"school_email_verified_at": row.get("school_email_verified_at")}])
        if "created_at" in params["select"]:
            return httpx.Response(200, json=[{"birth_year": row["birth_year"], "created_at": row["created_at"],
                                              "universities": {"name": row["university"]}}])
        if "student_verification" in params["select"]:
            return httpx.Response(200, json=[{"student_verification": row.get("student_verification"),
                                              "department": row.get("department"), "status": row["status"],
                                              "school_email_verified_at": row.get("school_email_verified_at")}])
        return httpx.Response(200, json=[{"status": row["status"]}])

    def _rpc_list_unverified_accounts(self, method, params, body):
        """SQL 함수 흉내: school_email_verified_at 이 null 이고 가입 뒤 p_older_than_days 일이 지난 프로필 id."""
        assert method == "POST"
        self.unverified_lookups.append(body)
        cutoff = NOW - timedelta(days=body["p_older_than_days"])
        ids = [pid for pid, p in self.profiles.items()
               if "signed_up_at" in p and p["school_email_verified_at"] is None and p["signed_up_at"] < cutoff]
        ids += [pid for pid in self.stale_unverified if pid not in ids]
        return httpx.Response(200, json=[{"id": pid} for pid in ids[:body.get("p_limit", 100)]])

    def _school_email_claims(self, method, params, body):
        assert method == "GET"
        assert set(params) == {"profile_id", "select"}
        if self.claims_unreachable:
            raise httpx.ConnectError("연결 실패")
        row = self.claims.get(self._eq(params, "profile_id"))
        if row is None:
            return httpx.Response(200, json=[])
        return httpx.Response(200, json=[{c: row[c] for c in params["select"].split(",")}])

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
