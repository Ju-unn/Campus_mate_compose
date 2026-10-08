"""한 번 쓰는 백필: 학교 메일 OTP 로 가입한 기존 계정의 학교 메일 해시를 school_email_claims 에 채운다.

요청은 경로와 params **키**로 가른다(`"id=eq." in url` 은 `profile_id=eq.` 에도 걸린다).
"""
import json

import httpx
import pytest

from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_email
from scripts.backfill_school_email_claims import SchoolEmailClaimsBackfill, format_counts

IDENTITY_KEY = "identity-key"
SNU = "univ-snu"
VERIFIED_AT = "2026-09-01T10:00:00+00:00"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key=IDENTITY_KEY,
    )


def _hmac(email: str) -> str:
    return bytea_literal(hash_email(IDENTITY_KEY, email))


class World:
    """profiles · school_email_claims(PostgREST) 와 auth 관리자 API 가짜."""

    def __init__(self) -> None:
        self.profiles: dict[str, dict] = {}
        self.emails: dict[str, object] = {}      # id → 이메일 문자열 · "" · None · 500 · "unreachable"
        self.claims: list[dict] = []
        self.requests: list[httpx.Request] = []

    def verified(self, pid: str, email: str, status: str = "active", verified_at: str = VERIFIED_AT) -> None:
        self.profiles[pid] = {"id": pid, "university_id": SNU, "school_email_verified_at": verified_at,
                              "status": status}
        self.emails[pid] = email

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params = request.url.path, request.url.params
        if path.startswith("/auth/v1/admin/users/"):
            assert request.method == "GET"
            assert request.headers["authorization"] == "Bearer service-key"
            email = self.emails.get(path.rsplit("/", 1)[1])
            if email == "unreachable":
                raise httpx.ConnectError("연결 실패", request=request)
            if email == 500:
                return httpx.Response(500, json={"msg": "boom"})
            return httpx.Response(200, json={"id": path.rsplit("/", 1)[1], "email": email})
        if path == "/rest/v1/profiles":
            return self._profiles(params)
        if path == "/rest/v1/school_email_claims" and request.method == "GET":
            assert set(params) == {"profile_id", "select"}
            ids = params["profile_id"].removeprefix("in.(").removesuffix(")").split(",")
            return httpx.Response(200, json=[{"profile_id": c["profile_id"]} for c in self.claims
                                             if c["profile_id"] in ids])
        if path == "/rest/v1/school_email_claims" and request.method == "POST":
            return self._insert_claim(request)
        raise AssertionError(f"예상하지 못한 요청 {request.method} {request.url}")

    def _profiles(self, params: httpx.QueryParams) -> httpx.Response:
        assert params["school_email_verified_at"] == "not.is.null"
        assert params["university_id"] == "not.is.null"
        assert params["status"] == "neq.withdrawn"
        assert params["order"] == "id.asc"
        after = params.get("id", "gt.").removeprefix("gt.")
        rows = [p for pid, p in sorted(self.profiles.items())
                if p["school_email_verified_at"] and p["university_id"] and p["status"] != "withdrawn" and pid > after]
        columns = params["select"].split(",")
        return httpx.Response(200, json=[{c: r[c] for c in columns} for r in rows[:int(params["limit"])]])

    def _insert_claim(self, request: httpx.Request) -> httpx.Response:
        # 이미 있는 행은 덮지 않는다: on_conflict=school_email_hmac + resolution=ignore-duplicates 면 무시하고 빈 목록.
        assert request.url.params["on_conflict"] == "school_email_hmac"
        assert "resolution=ignore-duplicates" in request.headers["prefer"]
        assert "return=representation" in request.headers["prefer"]
        row = json.loads(request.content)
        if any(c["school_email_hmac"] == row["school_email_hmac"] for c in self.claims):
            return httpx.Response(201, json=[])
        if any(c["profile_id"] == row["profile_id"] for c in self.claims):
            # profile_id unique — 그 사이 verify 가 먼저 채운 경우
            return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
        self.claims.append(row)
        return httpx.Response(201, json=[row])

    def admin_calls(self, pid: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.url.path == f"/auth/v1/admin/users/{pid}"]


async def _run(world: World, page: int = 500) -> dict[str, int]:
    async with httpx.AsyncClient(transport=httpx.MockTransport(world.handle)) as client:
        job = SchoolEmailClaimsBackfill(_settings(), client)
        return await job.run(page=page)


# 1 ---------------------------------------------------------------------------------------------

async def test_verified_accounts_each_get_one_claim_with_the_signup_hash():
    world = World()
    world.verified("p1", "  Hong@SNU.ac.kr ")
    world.verified("p2", "kim@snu.ac.kr", verified_at="2026-09-02T11:00:00+00:00")
    world.verified("p3", "lee@snu.ac.kr", status="suspended")  # 정지도 학교 메일은 그 사람 것이다

    counts = await _run(world)

    assert counts == {"filled": 3, "skipped": 0, "already": 0, "conflicts": 0}
    by_profile = {c["profile_id"]: c for c in world.claims}
    assert set(by_profile) == {"p1", "p2", "p3"}
    # 가입 · 탈퇴 · verify 와 같은 hash_email(소문자 · 공백 제거)이어야 같은 메일로 맞는다.
    assert by_profile["p1"]["school_email_hmac"] == _hmac("hong@snu.ac.kr")
    assert by_profile["p1"] == {"school_email_hmac": _hmac("hong@snu.ac.kr"), "university_id": SNU,
                                "profile_id": "p1", "provider": "email", "key_version": IDENTITY_KEY_VERSION,
                                "verified_at": VERIFIED_AT}
    assert by_profile["p2"]["verified_at"] == "2026-09-02T11:00:00+00:00"


# 2 ---------------------------------------------------------------------------------------------

async def test_an_account_that_already_has_a_claim_is_not_written_again_and_a_rerun_fills_nothing():
    world = World()
    world.verified("p1", "hong@snu.ac.kr")
    world.verified("p2", "kim@snu.ac.kr")
    world.claims.append({"school_email_hmac": _hmac("kim@snu.ac.kr"), "university_id": SNU, "profile_id": "p2",
                         "provider": "kakao", "key_version": 1, "verified_at": VERIFIED_AT})

    first = await _run(world)
    second = await _run(world)

    assert first == {"filled": 1, "skipped": 0, "already": 1, "conflicts": 0}
    assert second == {"filled": 0, "skipped": 0, "already": 2, "conflicts": 0}
    # 이미 있는 행은 그대로(provider 를 email 로 덮지 않는다). 관리자 API 도 다시 부르지 않는다.
    assert next(c for c in world.claims if c["profile_id"] == "p2")["provider"] == "kakao"
    assert world.admin_calls("p2") == []
    assert len(world.admin_calls("p1")) == 1
    assert len(world.claims) == 2


async def test_a_claim_written_by_verify_in_the_meantime_counts_as_already():
    """profile_id unique 충돌(23505) — 그 사이 verify 가 먼저 채웠다. 덮지 않고 already 로 센다."""
    world = World()
    world.verified("p1", "hong@snu.ac.kr")
    original = world._insert_claim

    def verify_first(request: httpx.Request) -> httpx.Response:
        world.claims.append({"school_email_hmac": _hmac("other@snu.ac.kr"), "profile_id": "p1"})
        world._insert_claim = original
        return original(request)

    world._insert_claim = verify_first

    assert await _run(world) == {"filled": 0, "skipped": 0, "already": 1, "conflicts": 0}


# 3 ---------------------------------------------------------------------------------------------

async def test_withdrawn_profiles_are_not_targets():
    world = World()
    world.verified("p1", "hong@snu.ac.kr", status="withdrawn")
    world.verified("p2", "kim@snu.ac.kr")

    counts = await _run(world)

    assert counts == {"filled": 1, "skipped": 0, "already": 0, "conflicts": 0}
    assert world.admin_calls("p1") == []
    assert [c["profile_id"] for c in world.claims] == ["p2"]


async def test_unverified_or_schoolless_profiles_are_not_targets():
    world = World()
    world.verified("p1", "hong@snu.ac.kr")
    world.profiles["p1"]["school_email_verified_at"] = None
    world.verified("p2", "kim@snu.ac.kr")
    world.profiles["p2"]["university_id"] = None

    assert await _run(world) == {"filled": 0, "skipped": 0, "already": 0, "conflicts": 0}
    assert world.admin_calls("p1") == [] and world.admin_calls("p2") == []


# 4 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("trouble", [500, "unreachable", "", None])
async def test_an_unreadable_or_empty_email_is_skipped_and_the_rest_continue(trouble):
    world = World()
    world.verified("p1", "hong@snu.ac.kr")
    world.verified("p2", "kim@snu.ac.kr")
    world.emails["p1"] = trouble

    counts = await _run(world)

    assert counts == {"filled": 1, "skipped": 1, "already": 0, "conflicts": 0}
    assert [c["profile_id"] for c in world.claims] == ["p2"]


# 5 ---------------------------------------------------------------------------------------------

async def test_the_same_hash_on_another_account_is_a_conflict_and_is_not_overwritten(capsys):
    world = World()
    world.verified("p1", "hong@snu.ac.kr")
    world.claims.append({"school_email_hmac": _hmac("hong@snu.ac.kr"), "university_id": SNU, "profile_id": "p9",
                         "provider": "kakao", "key_version": 1, "verified_at": VERIFIED_AT})

    counts = await _run(world)

    assert counts == {"filled": 0, "skipped": 0, "already": 0, "conflicts": 1}
    assert world.claims == [{"school_email_hmac": _hmac("hong@snu.ac.kr"), "university_id": SNU, "profile_id": "p9",
                             "provider": "kakao", "key_version": 1, "verified_at": VERIFIED_AT}]
    out = capsys.readouterr()
    assert "p1" not in out.out + out.err and "p9" not in out.out + out.err


# 6 ---------------------------------------------------------------------------------------------

async def test_paging_by_id_finishes_without_missing_anyone():
    world = World()
    for n in range(1, 6):
        world.verified(f"p{n}", f"user{n}@snu.ac.kr")
    world.emails["p2"] = 500  # 건너뛴 행이 계속 조건에 걸려도 id 로 넘겨 가니 끝난다

    counts = await _run(world, page=2)

    assert counts == {"filled": 4, "skipped": 1, "already": 0, "conflicts": 0}
    profile_reads = [r for r in world.requests if r.url.path == "/rest/v1/profiles"]
    assert len(profile_reads) == 3  # 2 + 2 + 1, 마지막 쪽이 page 보다 작아 끝난다
    assert [r.url.params.get("id") for r in profile_reads] == [None, "gt.p2", "gt.p4"]


# 7 ---------------------------------------------------------------------------------------------

async def test_the_output_is_counts_only(capsys):
    world = World()
    world.verified("p1", "Hong@SNU.ac.kr")
    world.verified("p2", "kim@snu.ac.kr")
    world.emails["p2"] = 500

    counts = await _run(world)
    line = format_counts(counts)
    out = capsys.readouterr()

    assert line == "filled=1 skipped=1 already=0 conflicts=0"
    printed = line + out.out + out.err
    for secret in ("hong", "kim", "snu", "p1", "p2", _hmac("hong@snu.ac.kr"), hash_email(IDENTITY_KEY, "hong@snu.ac.kr").hex(),
                   IDENTITY_KEY):
        assert secret not in printed.lower()


async def test_the_identity_key_never_goes_into_a_url():
    world = World()
    world.verified("p1", "hong@snu.ac.kr")

    await _run(world)

    assert all(IDENTITY_KEY not in str(r.url) for r in world.requests)
