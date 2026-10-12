"""친구 코드(= 추천 코드 profiles.referral_code)로 쓰는 지인 리뷰. 가입 뒤에도 추천 연결 없이 쓴다.

사용자 결정(10-13): 하트 보상 없음(referrals · redeem 을 건드리지 않는다) · 한 사람에게 한 번(409 유지) ·
확인 결과는 닉네임 · 학교만 · 없는 코드 / 비 active / 차단(양방향) / 본인 / 같은 번호는 전부 같은 404 ·
코드 확인 실패 시간당 10번 · 코드 경로 작성은 최근 24시간 5건까지 · 코드는 대소문자 · 공백 무시.
"""
import json
import logging
from collections.abc import Callable
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.cards.push import FcmSender
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.friend_reviews import router as router_module
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
FRIEND = "33333333-3333-3333-3333-333333333333"
REVIEW_ID = "44444444-4444-4444-4444-444444444444"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
CODE = "K7M2QX"
WRONG = "ZZZZZZ"
NOT_FOUND_BODY = {"detail": "코드를 찾을 수 없어요"}
TRY_LATER_BODY = {"detail": "잠시 후 다시 시도해 주세요."}
T0 = datetime(2026, 10, 13, 12, 0, tzinfo=SEOUL)
clock: dict[str, datetime] = {}


def _friend(**overrides) -> dict:
    # 아바타를 일부러 둔다 — 서버가 응답에 아바타를 실으면 아래 시험이 잡는다. 번호 해시는 profiles 에 embed 로 온다
    # (profile_private 의 PK 가 profiles FK 라 일대일 — PostgREST 가 객체 하나로 준다). 기본값은 내 번호와 다르다.
    row = {"id": FRIEND, "nickname": "달빛", "status": "active", "universities": {"name": "테스트대학교"},
           "profile_private": {"phone_hmac": "\\xef01"},
           "profile_avatars": [{"storage_path": "f/a.png", "status": "ready", "created_at": "2026-09-01T00:00:00+00:00"}]}
    return {**row, **overrides}


class _FakeCredentials:
    token = "fake-access-token"
    valid = True

    def refresh(self, _request) -> None:
        pass


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    clock["now"] = T0
    app.dependency_overrides[get_now] = lambda: clock["now"]
    # 실패 · 작성 창은 프로세스 안에 산다 — 시험마다 비우지 않으면 앞 시험의 기록이 뒤 시험을 429 로 만든다.
    router_module._CODE_FAILURES.times.clear()
    router_module._CODE_WRITES.times.clear()
    yield
    app.dependency_overrides.clear()
    router_module._CODE_FAILURES.times.clear()
    router_module._CODE_WRITES.times.clear()



def _table(request: httpx.Request) -> str:
    return request.url.path.rsplit("/", 1)[-1]


MY_PHONE = [{"phone_hmac": "\\x1234"}]


def _handler(*, exists: bool = True, profile: dict | None = None, blocked: list[dict] | None = None,
             my_private: list[dict] = MY_PHONE, my_nickname: str | None = "나",
             written: bool = False, recent: int = 0, linked: bool = False, insert: httpx.Response | None = None):
    target = _friend() if profile is None else profile

    def handler(request: httpx.Request) -> httpx.Response:
        table, params = _table(request), request.url.params
        if table == "profiles" and "referral_code" in params:
            # 서버가 대문자 · 공백 정리를 안 하면 eq.k7m 2qx 같은 값이 와서 못 찾는다.
            return httpx.Response(200, json=[target] if exists and params["referral_code"] == f"eq.{CODE}" else [])
        if table == "profiles" and params.get("id") == f"eq.{ME}":
            # 푸시 문구의 내 닉네임(fetch_card_profile).
            return httpx.Response(200, json=[{"id": ME, "nickname": my_nickname, "status": "active"}])
        if table == "profiles":
            return httpx.Response(200, json=[{**target, "id": params.get("id", "")[3:]}])
        if table == "blocks":
            return httpx.Response(200, json=blocked or [])
        if table == "profile_private":
            return httpx.Response(200, json=my_private)
        if table == "friend_reviews" and request.method == "DELETE":
            return httpx.Response(200, json=[{"id": REVIEW_ID}])
        if table == "referrals":
            return httpx.Response(200, json=[{"referee_id": ME}] if linked else [])
        if table == "friend_reviews" and request.method == "GET" and "created_at" in params:
            return httpx.Response(200, json=[{"id": str(i)} for i in range(min(recent, int(params.get("limit", recent))))])
        if table == "friend_reviews" and request.method == "GET":
            return httpx.Response(200, json=[{"id": REVIEW_ID}] if written else [])
        if table == "friend_reviews" and request.method == "POST":
            return insert or httpx.Response(201, json=[{"id": REVIEW_ID}])
        # 푸시 쪽(알림함 · 설정 · 토큰)은 빈 값으로 흘려보낸다.
        return httpx.Response(200, json=[])
    return handler


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": ME})
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _lookup(client: TestClient, code: str = CODE):
    return client.post("/friend-reviews/code-lookup", json={"code": code}, headers=AUTH_HEADERS)


def _create(client: TestClient, **body):
    payload = {"friend_code": CODE, "tags": ["약속을 잘 지켜요"], "comment": None, **body}
    return client.post("/friend-reviews", json=payload, headers=AUTH_HEADERS)


def _inserts(seen: list[httpx.Request]) -> list[dict]:
    return [json.loads(r.content) for r in seen if _table(r) == "friend_reviews" and r.method == "POST"]


SAME_PHONE = {"profile": _friend(profile_private={"phone_hmac": "\\xabcd"}), "my_private": [{"phone_hmac": "\\xabcd"}]}
# (가짜 DB 설정, 내부 로그에만 남는 사유)
REFUSALS = {
    "unknown": ({"exists": False}, "not_found"),
    "self": ({"profile": _friend(id=ME)}, "self"),
    "suspended": ({"profile": _friend(status="suspended")}, "inactive"),
    "withdrawn": ({"profile": _friend(status="withdrawn")}, "inactive"),
    "pending": ({"profile": _friend(status="pending")}, "inactive"),
    "i_blocked": ({"blocked": [{"blocker_id": ME, "blocked_id": FRIEND}]}, "blocked"),
    "blocked_me": ({"blocked": [{"blocker_id": FRIEND, "blocked_id": ME}]}, "blocked"),
    "same_phone": (SAME_PHONE, "same_phone"),
}


# 코드 확인 -------------------------------------------------------------------------------------------

def test_lookup_gives_nickname_university_and_already_reviewed_only():
    response = _lookup(_wire(_handler()))
    assert response.status_code == 200
    # 프로필 id · 아바타는 싣지 않는다(사용자 결정). 학교 칸 이름은 다른 목록 응답(writable · received)과 같은 university.
    assert response.json() == {"nickname": "달빛", "university": "테스트대학교", "already_reviewed": False}
    assert FRIEND not in response.text
    assert "avatar" not in response.text


def test_lookup_ignores_case_and_spaces():
    seen: list[httpx.Request] = []
    response = _lookup(_wire(_handler(), seen), " k7m 2Qx\t")
    assert response.status_code == 200
    query = next(r for r in seen if "referral_code" in r.url.params).url.params
    assert query["referral_code"] == f"eq.{CODE}"


def test_lookup_of_an_already_reviewed_friend_says_so():
    response = _lookup(_wire(_handler(written=True)))
    assert response.status_code == 200
    assert response.json()["already_reviewed"] is True


@pytest.mark.parametrize("kind", REFUSALS)
def test_every_refusal_is_the_same_404(kind):
    response = _lookup(_wire(_handler(**REFUSALS[kind][0])))
    assert response.status_code == 404
    assert response.json() == NOT_FOUND_BODY


def test_refusals_cannot_be_told_apart():
    # 상태 · 본문 · 헤더 모양까지 한 가지 — "있는데 막힌 코드" 와 "없는 코드" 를 가를 수 없어야 한다.
    replies = set()
    for setup, _ in REFUSALS.values():
        response = _lookup(_wire(_handler(**setup)))
        replies.add((response.status_code, response.text, response.headers.get("content-type")))
    assert replies == {(404, json.dumps(NOT_FOUND_BODY, ensure_ascii=False, separators=(",", ":")), "application/json")}


H = "\\xabcd"


@pytest.mark.parametrize("mine, theirs", [
    ([{"phone_hmac": H}], {"phone_hmac": None}),
    ([{"phone_hmac": None}], {"phone_hmac": H}),
    ([], {"phone_hmac": H}),
    ([{"phone_hmac": H}], None),
    ([{"phone_hmac": None}], {"phone_hmac": None}),
    ([], None),
    ([{"phone_hmac": H}], {"phone_hmac": "\\xef01"}),
], ids=["only_me", "only_friend", "no_my_row", "no_friend_row", "both_empty", "no_rows", "different"])
def test_phone_is_compared_only_when_both_have_one(mine, theirs):
    # redeem_referral 과 같은 규칙 — 번호 해시가 빈 옛 계정은 비교하지 않는다.
    handler = _handler(profile=_friend(profile_private=theirs), my_private=mine)
    assert _lookup(_wire(handler)).status_code == 200


def test_lookup_reads_both_phones_in_the_same_round():
    # 상대 번호는 코드 조회에 embed, 내 번호는 따로 — 셋을 한 번에 보낸다(권고1).
    seen: list[httpx.Request] = []
    _lookup(_wire(_handler(), seen))
    by_code = next(r for r in seen if "referral_code" in r.url.params).url.params
    assert "profile_private(phone_hmac)" in by_code["select"]
    mine = next(r for r in seen if _table(r) == "profile_private").url.params
    assert mine["profile_id"] == f"eq.{ME}"
    assert mine["select"] == "phone_hmac"


@pytest.mark.parametrize("kind", REFUSALS)
def test_every_refusal_costs_the_same_db_round_trips(kind):
    # 사유마다 PostgREST 왕복 수가 다르면 응답 시간으로 "있는데 막힌 코드" 를 가를 수 있다 — 전부 같은 셋.
    seen: list[httpx.Request] = []
    _lookup(_wire(_handler(**REFUSALS[kind][0]), seen))
    assert sorted(_table(r) for r in seen) == ["blocks", "profile_private", "profiles"]


def test_lookup_touches_no_referral_or_heart_tables():
    seen: list[httpx.Request] = []
    assert _lookup(_wire(_handler(), seen)).status_code == 200
    assert not any(_table(r) == "referrals" or "/rpc/" in r.url.path for r in seen)


@pytest.mark.parametrize("kind", REFUSALS)
def test_refusal_reason_goes_only_to_the_log_without_code_or_nickname(kind, caplog):
    setup, reason = REFUSALS[kind]
    with caplog.at_level(logging.INFO):
        _lookup(_wire(_handler(**setup)), " k7m2qx ")
    text = " ".join(r.getMessage() for r in caplog.records if r.name.startswith("app"))
    assert f"reason={reason}" in text
    for secret in (CODE, "k7m2qx", "달빛"):
        assert secret not in text


def test_lookup_needs_verified_caller():
    response = _wire(_handler()).post("/friend-reviews/code-lookup", json={"code": CODE})
    assert response.status_code in (401, 403)


@pytest.mark.parametrize("body", [{}, {"code": ""}, {"code": "   "}, {"code": "A" * 21}])
def test_lookup_without_a_code_is_422(body):
    response = _wire(_handler()).post("/friend-reviews/code-lookup", json=body, headers=AUTH_HEADERS)
    assert response.status_code == 422


# 실패 횟수 제한(시간당 10번, 프로세스 안 슬라이딩 창) ---------------------------------------------------

def test_eleventh_try_after_ten_failures_is_429_even_with_the_right_code():
    seen: list[httpx.Request] = []
    client = _wire(_handler(), seen)
    assert [_lookup(client, WRONG).status_code for _ in range(10)] == [404] * 10
    seen.clear()
    response = _lookup(client)
    assert response.status_code == 429
    assert response.json() == TRY_LATER_BODY
    # 막힌 요청은 DB 에 코드를 묻지도 않는다.
    assert not any("referral_code" in r.url.params for r in seen)


def test_failures_expire_after_an_hour():
    client = _wire(_handler())
    for _ in range(10):
        _lookup(client, WRONG)
    clock["now"] = T0 + timedelta(minutes=59)
    assert _lookup(client).status_code == 429
    clock["now"] = T0 + timedelta(hours=1, seconds=1)
    assert _lookup(client).status_code == 200


def test_successful_lookups_do_not_count():
    client = _wire(_handler())
    assert [_lookup(client).status_code for _ in range(15)] == [200] * 15
    for _ in range(9):
        _lookup(client, WRONG)
    assert _lookup(client).status_code == 200


def test_429_tries_do_not_extend_the_lock():
    # 막힌 동안 계속 두드려도 창이 밀리지 않는다 — 첫 실패에서 한 시간이면 풀린다.
    client = _wire(_handler())
    for _ in range(10):
        _lookup(client, WRONG)
    clock["now"] = T0 + timedelta(minutes=30)
    # 한도(10)보다 많이 두드린다 — 막힌 시도를 세는 서버면 T0+30분 기록 12개가 남아 아래가 429 다.
    assert [_lookup(client, WRONG).status_code for _ in range(12)] == [429] * 12
    clock["now"] = T0 + timedelta(hours=1, seconds=1)
    assert _lookup(client).status_code == 200


def test_failed_friend_code_writes_count_toward_the_same_limit():
    client = _wire(_handler())
    assert [_create(client, friend_code=WRONG).status_code for _ in range(10)] == [404] * 10
    assert _lookup(client).status_code == 429
    assert _create(client).status_code == 429


def test_old_entries_are_dropped_so_memory_does_not_grow():
    router_module._CODE_FAILURES.hold("someone", T0)
    router_module._CODE_FAILURES.hold("other", T0 + timedelta(hours=1, seconds=1))
    assert "someone" not in router_module._CODE_FAILURES.times
    router_module._CODE_WRITES.hold("someone", T0)
    router_module._CODE_WRITES.hold("other", T0 + timedelta(hours=24, seconds=1))
    assert "someone" not in router_module._CODE_WRITES.times


def test_concurrent_tries_are_held_before_the_db_answers():
    # 확인 중(DB 응답 전)인 시도도 자리를 잡는다 — 동시에 100개를 쏴도 10개 넘게 DB 까지 가지 못한다.
    for _ in range(10):
        router_module._CODE_FAILURES.hold(ME, T0)
    with pytest.raises(HTTPException) as caught:
        router_module._CODE_FAILURES.hold(ME, T0)
    assert caught.value.status_code == 429


def test_failure_slot_is_held_before_the_code_query():
    # 라우터 수준에서 순서를 고정한다 — 코드 조회가 DB 에 닿을 때 이미 자리가 잡혀 있어야 동시 요청이 한도를 못 넘는다.
    held = []
    base = _handler()

    def handler(request: httpx.Request) -> httpx.Response:
        if "referral_code" in request.url.params:
            held.append(len(router_module._CODE_FAILURES.times.get(ME, [])))
        return base(request)

    assert _lookup(_wire(handler)).status_code == 200
    assert held == [1]


@pytest.mark.parametrize("broken", ["500", "timeout"])
def test_db_trouble_during_lookup_gives_the_slot_back(broken):
    # DB 장애 · 시간 초과는 코드 실패가 아니다 — 자리를 돌려줘 정상 사용자가 한 시간 429 에 갇히지 않게.
    base = _handler()

    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "blocks":
            if broken == "timeout":
                raise httpx.ReadTimeout("slow", request=request)
            return httpx.Response(500, json={"message": "boom"})
        return base(request)

    _wire(handler)
    client = TestClient(app, raise_server_exceptions=False)
    assert [_lookup(client).status_code >= 500 for _ in range(12)] == [True] * 12
    assert not router_module._CODE_FAILURES.times.get(ME)
    _wire(_handler())
    assert _lookup(TestClient(app)).status_code == 200


# 코드로 쓰기 -----------------------------------------------------------------------------------------

def test_create_by_friend_code_inserts_and_pushes(monkeypatch):
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, title, data))
        return 1

    monkeypatch.setattr(router_module, "notify", fake_notify)
    seen: list[httpx.Request] = []
    response = _create(_wire(_handler(), seen), friend_code=" k7m2qx ", tags=["성실해요"], comment=" 든든해요 ")
    assert response.status_code == 201
    assert response.json() == {"id": REVIEW_ID}
    assert _inserts(seen) == [{"reviewer_id": ME, "reviewee_id": FRIEND, "tags": ["성실해요"], "comment": "든든해요"}]
    assert calls == [(FRIEND, "new_friend_review", "새 지인 리뷰가 도착했어요", {"route": "friend_reviews"})]
    # 추천 연결 · 하트 보상과 무관하다 — referrals 와 RPC(redeem · grant_hearts)를 부르지 않는다.
    assert not any(_table(r) == "referrals" or "/rpc/" in r.url.path for r in seen)


@pytest.mark.parametrize("kind", REFUSALS)
def test_create_by_friend_code_rechecks_the_target(kind):
    # 앱이 본 확인 결과를 믿지 않는다 — 저장할 때 코드로 다시 찾아 같은 검사를 한다.
    seen: list[httpx.Request] = []
    response = _create(_wire(_handler(**REFUSALS[kind][0]), seen))
    assert response.status_code == 404
    assert response.json() == NOT_FOUND_BODY
    assert _inserts(seen) == []


def test_create_by_friend_code_for_an_already_reviewed_friend_is_409():
    seen: list[httpx.Request] = []
    response = _create(_wire(_handler(written=True), seen))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN
    assert _inserts(seen) == []


def test_create_by_friend_code_race_is_409():
    conflict = httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
    response = _create(_wire(_handler(insert=conflict)))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN


def test_create_by_friend_code_stops_at_five_reviews_a_day():
    seen: list[httpx.Request] = []
    response = _create(_wire(_handler(recent=5), seen))
    assert response.status_code == 429
    assert response.json() == TRY_LATER_BODY
    assert _inserts(seen) == []
    # 경로 · 상태와 무관하게 내가 최근 24시간에 쓴 리뷰 전부를 센다.
    query = next(r for r in seen if "created_at" in r.url.params).url.params
    assert query["reviewer_id"] == f"eq.{ME}"
    assert query["created_at"] == f"gte.{(T0 - timedelta(hours=24)).isoformat()}"
    assert "status" not in query


def test_create_by_friend_code_with_four_today_is_fine():
    assert _create(_wire(_handler(recent=4))).status_code == 201


def test_daily_cap_429_is_not_a_code_failure():
    client = _wire(_handler(recent=5))
    assert [_create(client).status_code for _ in range(12)] == [429] * 12
    assert _lookup(client).status_code == 200


# 하루 5건 — 프로세스 안 작성 기록(필수1: 지우고 다시 쓰기로 DB 수를 0 으로 되돌리는 우회) ---------------------

def _delete(client: TestClient):
    return client.delete(f"/friend-reviews/{REVIEW_ID}", headers=AUTH_HEADERS)


def _spy_notify(monkeypatch) -> list:
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, body))
        return 1

    monkeypatch.setattr(router_module, "notify", fake_notify)
    return calls


def test_write_delete_rewrite_to_the_same_friend_stops_at_five(monkeypatch):
    # DB 는 지운 행을 모른다(recent=0, written=False) — 프로세스 안 기록이 막아야 한다. 푸시도 5번까지만 간다.
    calls = _spy_notify(monkeypatch)
    seen: list[httpx.Request] = []
    client = _wire(_handler(), seen)
    for _ in range(5):
        assert _create(client).status_code == 201
        assert _delete(client).status_code == 204
    response = _create(client)
    assert response.status_code == 429
    assert response.json() == TRY_LATER_BODY
    assert len(_inserts(seen)) == 5
    assert len(calls) == 5


def test_five_writes_then_deleting_them_all_still_blocks_the_sixth():
    client = _wire(_handler())
    assert [_create(client).status_code for _ in range(5)] == [201] * 5
    assert [_delete(client).status_code for _ in range(5)] == [204] * 5
    assert _create(client).status_code == 429


def test_write_window_frees_after_24_hours():
    client = _wire(_handler())
    for _ in range(5):
        _create(client)
    clock["now"] = T0 + timedelta(hours=23, minutes=59)
    assert _create(client).status_code == 429
    clock["now"] = T0 + timedelta(hours=24, seconds=1)
    assert _create(client).status_code == 201


def test_write_slot_is_held_before_the_insert():
    # 저장 요청이 DB 에 닿을 때 이미 자리가 잡혀 있다 — 동시에 여러 개를 보내도 5건을 넘지 못한다.
    held = []
    base = _handler()

    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "friend_reviews" and request.method == "POST":
            held.append(len(router_module._CODE_WRITES.times.get(ME, [])))
        return base(request)

    assert _create(_wire(handler)).status_code == 201
    assert held == [1]
    for _ in range(4):
        router_module._CODE_WRITES.hold(ME, T0)
    with pytest.raises(HTTPException) as caught:
        router_module._CODE_WRITES.hold(ME, T0)
    assert caught.value.status_code == 429


def test_writes_that_are_not_saved_give_the_slot_back():
    conflict = httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
    raced = _wire(_handler(insert=conflict))
    assert [_create(raced).status_code for _ in range(3)] == [409] * 3
    capped = _wire(_handler(recent=5))
    assert [_create(capped).status_code for _ in range(3)] == [429] * 3
    client = _wire(_handler())
    assert [_create(client).status_code for _ in range(6)] == [201] * 5 + [429]


def test_reviewee_id_path_does_not_use_the_code_write_window():
    linked = _wire(_handler(linked=True))
    body = {"reviewee_id": FRIEND, "tags": ["성실해요"], "comment": None}
    assert [linked.post("/friend-reviews", json=body, headers=AUTH_HEADERS).status_code for _ in range(6)] == [201] * 6
    assert not router_module._CODE_WRITES.times.get(ME)
    client = _wire(_handler())
    assert [_create(client).status_code for _ in range(6)] == [201] * 5 + [429]


@pytest.mark.parametrize("body", [{"friend_code": CODE}, {"reviewee_id": FRIEND}], ids=["code", "reviewee_id"])
def test_no_push_text_with_a_missing_nickname(body, monkeypatch):
    # 내 닉네임이 비면(온보딩 중간) "None 님이 리뷰를 남겼어요" 가 나가지 않게 푸시를 건너뛴다. 저장은 그대로 201.
    calls = _spy_notify(monkeypatch)
    response = _wire(_handler(linked=True, my_nickname=None)).post(
        "/friend-reviews", headers=AUTH_HEADERS, json={"tags": ["성실해요"], "comment": None, **body})
    assert response.status_code == 201
    assert calls == []


def test_push_carries_my_nickname(monkeypatch):
    calls = _spy_notify(monkeypatch)
    _create(_wire(_handler(my_nickname="새싹")))
    assert calls == [(FRIEND, "새싹 님이 리뷰를 남겼어요")]


# 기존 reviewee_id 경로 회귀 · 본문 규칙 -------------------------------------------------------------

def test_reviewee_id_path_is_unchanged_and_has_no_daily_cap():
    seen: list[httpx.Request] = []
    response = _wire(_handler(linked=True, recent=5), seen).post("/friend-reviews", headers=AUTH_HEADERS, json={
        "reviewee_id": FRIEND, "tags": ["성실해요"], "comment": None})
    assert response.status_code == 201
    assert response.json() == {"id": REVIEW_ID}
    assert not any("created_at" in r.url.params or "referral_code" in r.url.params for r in seen)


def test_reviewee_id_path_still_needs_a_referral_link():
    response = _wire(_handler(linked=False)).post("/friend-reviews", headers=AUTH_HEADERS, json={
        "reviewee_id": FRIEND, "tags": ["성실해요"], "comment": None})
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


@pytest.mark.parametrize("target", [{"reviewee_id": FRIEND, "friend_code": CODE}, {}],
                         ids=["both", "neither"])
def test_create_needs_exactly_one_target(target):
    seen: list[httpx.Request] = []
    response = _wire(_handler(linked=True), seen).post(
        "/friend-reviews", headers=AUTH_HEADERS, json={"tags": ["성실해요"], "comment": None, **target})
    assert response.status_code == 422
    assert _inserts(seen) == []


def test_create_by_friend_code_keeps_tag_rules():
    response = _create(_wire(_handler()), tags=["잘생겼어요"])
    assert response.status_code == 422
    assert [error["loc"] for error in response.json()["detail"]] == [["body", "tags"]]
