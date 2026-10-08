import json
from collections.abc import Callable
from datetime import datetime

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
SUPABASE_URL = "https://x.supabase.co"
# 나이는 "지금" 의 해로 센다 — 벽시계 대신 끼워서 고정한다.
NOW = datetime(2026, 9, 27, 14, 0, tzinfo=SEOUL)

FULL_PROFILE = {
    "nickname": "하늘",
    "bio": "주말엔 산책해요",
    "birth_year": 2003, "height_cm": 178, "mbti": "ENFP", "major": "컴퓨터공학과",
    "universities": {"name": "서울대학교"},
    "preferred_age_min": 21, "preferred_age_max": 27,
    "preferred_height_min": 160, "preferred_height_max": None,
    "profile_avatars": [
        {"status": "ready", "storage_path": f"{PROFILE_ID}/old.png", "created_at": "2026-09-20T10:00:00+00:00"},
        {"status": "ready", "storage_path": f"{PROFILE_ID}/new.png", "created_at": "2026-09-25T10:00:00+00:00"},
        # 가장 늦었지만 실패한 것 — 고르면 안 된다.
        {"status": "failed", "storage_path": None, "created_at": "2026-09-26T10:00:00+00:00"},
    ],
    # PostgREST 는 embed 순서를 보장하지 않는다 — 일부러 섞어 둔다.
    "profile_photos": [
        {"id": "p-c", "storage_path": f"{PROFILE_ID}/c.jpg", "position": 2, "is_avatar_source": False},
        {"id": "p-a", "storage_path": f"{PROFILE_ID}/a.jpg", "position": 0, "is_avatar_source": True},
        {"id": "p-b", "storage_path": f"{PROFILE_ID}/b.jpg", "position": 1, "is_avatar_source": False},
    ],
    "nickname_changed_at": "2026-09-20T14:00:00+09:00",   # NOW(09-27 14:00) 기준 7일 전 → 10-20 14:00 에 풀림
    "interest_tags": ["카페가기", "여행", "요리"],
    "my_traits": ["유머러스", "성실한", "차분한"],
    "ideal_traits": ["다정한", "연락 잘하는", "솔직한"],
    "preferred_mbti_flags": {"E": True},
    "preferred_animal_types": ["dog"],
    "preferred_impression_types": ["kind"],
    # 1:1 embed 라 객체(없으면 null)로 온다.
    "entitlements": {"heart_balance": 30},
}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url=SUPABASE_URL, supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response], verification: str = "verified") -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다 — 내 프로필 조회도 profiles 를 읽는다.
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _handler(profile: dict, seen: list[httpx.Request] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        if request.method == "GET" and request.url.path.endswith("/profiles") \
                and request.url.params.get("id") == f"eq.{PROFILE_ID}":
            return httpx.Response(200, json=[profile])
        sign_prefix = "/storage/v1/object/sign/profile-photos/"
        if request.method == "POST" and request.url.path.startswith(sign_prefix):
            path = request.url.path.removeprefix(sign_prefix)
            return httpx.Response(200, json={"signedURL": f"/object/sign/profile-photos/{path}?token=t"})
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def _signed(name: str) -> str:
    return f"{SUPABASE_URL}/storage/v1/object/sign/profile-photos/{PROFILE_ID}/{name}?token=t"


def _get(profile: dict, seen: list[httpx.Request] | None = None) -> httpx.Response:
    return _wire(_handler(profile, seen)).get("/me/profile", headers=AUTH_HEADERS)


def test_profile_returns_my_fields():
    response = _get(FULL_PROFILE)

    assert response.status_code == 200
    assert response.json() == {
        "nickname": "하늘",
        "age": 24, "university": "서울대학교", "major": "컴퓨터공학과",
        "height_cm": 178, "mbti": "ENFP",
        "avatar_url": f"{SUPABASE_URL}/storage/v1/object/public/avatars/{PROFILE_ID}/new.png",
        "photo_urls": [_signed("a.jpg"), _signed("b.jpg"), _signed("c.jpg")],
        "preferred_age_min": 21, "preferred_age_max": 27,
        "preferred_height_min": 160, "preferred_height_max": None,
        "bio": "주말엔 산책해요",
        "interest_tags": ["카페가기", "여행", "요리"],
        "my_traits": ["유머러스", "성실한", "차분한"],
        "ideal_traits": ["다정한", "연락 잘하는", "솔직한"],
        "preferred_mbti_flags": {"E": True},
        "preferred_animal_types": ["dog"],
        "preferred_impression_types": ["kind"],
        "photos": [
            {"id": "p-a", "url": _signed("a.jpg"), "is_avatar_source": True},
            {"id": "p-b", "url": _signed("b.jpg"), "is_avatar_source": False},
            {"id": "p-c", "url": _signed("c.jpg"), "is_avatar_source": False},
        ],
        "heart_balance": 30,
        "avatar_regen_cost": 10,   # FULL_PROFILE 은 ready 2장
        "nickname_changeable_at": "2026-10-20T14:00:00+09:00",
    }


def test_profile_rejects_missing_login():
    response = _wire(_handler(FULL_PROFILE)).get("/me/profile")

    assert response.status_code == 401


def test_profile_rejects_unverified_student():
    response = _wire(_handler(FULL_PROFILE), verification="pending").get("/me/profile", headers=AUTH_HEADERS)

    assert response.status_code == 403


def test_photos_are_signed_in_position_order_for_one_hour():
    seen: list[httpx.Request] = []
    response = _get(FULL_PROFILE, seen)

    assert response.json()["photo_urls"] == [_signed("a.jpg"), _signed("b.jpg"), _signed("c.jpg")]
    signs = [r for r in seen if "/object/sign/" in r.url.path]
    assert [json.loads(r.content) for r in signs] == [{"expiresIn": 3600}] * 3


def test_avatar_is_null_when_only_failed():
    profile = {**FULL_PROFILE, "profile_avatars": [
        {"status": "failed", "storage_path": None, "created_at": "2026-09-26T10:00:00+00:00"},
    ]}

    assert _get(profile).json()["avatar_url"] is None


def test_avatar_is_null_when_none():
    assert _get({**FULL_PROFILE, "profile_avatars": []}).json()["avatar_url"] is None


def test_empty_profile_gives_nulls_and_no_photos():
    # 학생 인증 관문은 온보딩 완료(status active)를 보지 않는다 — 출생연도·키가 아직 빈 채로 닿을 수 있다.
    profile = {
        "nickname": "하늘", "bio": None,
        "birth_year": None, "height_cm": None, "mbti": None, "major": None,
        "universities": {"name": "서울대학교"},
        "preferred_age_min": None, "preferred_age_max": None,
        "preferred_height_min": None, "preferred_height_max": None,
        "profile_avatars": [], "profile_photos": [],
        # 태그 · 선호 칸은 DB 가 not null default '{}' 라 null 로 오지 않는다.
        "nickname_changed_at": None,
        "interest_tags": [], "my_traits": [], "ideal_traits": [],
        "preferred_mbti_flags": {}, "preferred_animal_types": [], "preferred_impression_types": [],
        "entitlements": None,
    }
    seen: list[httpx.Request] = []

    body = _get(profile, seen).json()

    assert body["photo_urls"] == []
    assert body["photos"] == []
    assert (body["heart_balance"], body["avatar_regen_cost"], body["nickname_changeable_at"]) == (0, 0, None)
    for key in ("bio", "age", "height_cm", "mbti", "major",
                "preferred_age_min", "preferred_age_max", "preferred_height_min", "preferred_height_max"):
        assert body[key] is None
    # 사진이 없으면 서명 요청도 없다.
    assert not [r for r in seen if "/object/sign/" in r.url.path]


def test_response_never_carries_private_fields():
    response = _get(FULL_PROFILE)
    body = response.json()

    # 404 본문으로 빈손 통과하지 않게 200 과 nickname 부터 본다.
    assert response.status_code == 200 and "nickname" in body
    for key in body:
        assert not any(word in key for word in ("real_name", "phone", "kakao", "verification"))


def test_reads_only_my_row_in_one_request_after_gate_and_never_profile_private():
    # seen 에는 가드(get_verified_caller) 조회가 빠진다 — "1번"은 가드 뒤 이 API 가 낸 요청 수다.
    seen: list[httpx.Request] = []
    _get(FULL_PROFILE, seen)

    reads = [r for r in seen if r.method == "GET"]
    assert len(reads) == 1
    assert reads[0].url.path.endswith("/profiles")
    assert reads[0].url.params["id"] == f"eq.{PROFILE_ID}"
    assert "profile_private" not in str(reads[0].url)


@pytest.mark.parametrize(("now_year", "age"), [(2026, 24), (2030, 28)])
def test_age_is_counted_from_injected_now_year(now_year, age):
    # 벽시계가 아니라 get_now 를 보는지 가르려고 올해가 아닌 해도 넣는다.
    app.dependency_overrides[get_now] = lambda: NOW.replace(year=now_year)

    assert _get(FULL_PROFILE).json()["age"] == age


def test_header_and_facts_come_from_my_row():
    body = _get(FULL_PROFILE).json()

    assert (body["university"], body["major"], body["height_cm"], body["mbti"]) == \
        ("서울대학교", "컴퓨터공학과", 178, "ENFP")


def test_mbti_is_null_when_not_chosen():
    # 04-1 에서 MBTI 는 선택이다.
    assert _get({**FULL_PROFILE, "mbti": None}).json()["mbti"] is None


def test_select_asks_for_header_and_fact_columns():
    seen: list[httpx.Request] = []
    _get(FULL_PROFILE, seen)

    select = seen[0].url.params["select"]
    for column in ("birth_year", "height_cm", "mbti", "major", "universities(name)",
                   "interest_tags", "nickname_changed_at", "entitlements(heart_balance)", "is_avatar_source"):
        assert column in select


def test_each_photo_is_signed_once_for_both_lists():
    seen: list[httpx.Request] = []
    _get(FULL_PROFILE, seen)
    assert len([r for r in seen if "/object/sign/" in r.url.path]) == 3


@pytest.mark.parametrize(("entitlements", "balance"), [(None, 0), ({"heart_balance": 7}, 7)])
def test_heart_balance_is_zero_without_an_entitlements_row(entitlements, balance):
    assert _get({**FULL_PROFILE, "entitlements": entitlements}).json()["heart_balance"] == balance


@pytest.mark.parametrize(("ready", "cost"), [(1, 0), (2, 10)])
def test_regen_cost_follows_the_ready_count(ready, cost):
    avatars = [{"status": "ready", "storage_path": f"{PROFILE_ID}/{i}.png", "created_at": f"2026-09-2{i}T00:00:00+00:00"}
               for i in range(ready)]
    assert _get({**FULL_PROFILE, "profile_avatars": avatars}).json()["avatar_regen_cost"] == cost


@pytest.mark.parametrize(("changed_at", "changeable_at"), [
    (None, None),                                                 # 한 번도 안 바꿈
    ("2026-08-28T14:00:00+09:00", None),                          # 정확히 30일 전 — 지금 된다
    ("2026-08-28T14:00:01+09:00", "2026-09-27T14:00:01+09:00"),   # 30일에서 1초 모자람 — 아직 잠김
    ("2026-09-27T14:00:00+09:00", "2026-10-27T14:00:00+09:00"),   # 방금(pen 15-6-2 "10월 27일부터")
])
def test_nickname_lock_is_judged_from_the_injected_now(changed_at, changeable_at):
    assert _get({**FULL_PROFILE, "nickname_changed_at": changed_at}).json()["nickname_changeable_at"] == changeable_at
