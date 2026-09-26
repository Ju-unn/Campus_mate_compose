from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.home.completion import completion_percent
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}

STATS_ROW = {
    "delivered_cards": 1280, "signups": 342, "conversations_started": 57,
    "campuses": ["고려대학교", "서울대학교", "연세대학교"],
}
# 4개 다 채운 사람 — 완성도 100.
FULL_PROFILE = {
    "mbti": "INFP", "preferred_height_min": 170, "preferred_height_max": None,
    "interest_tags": ["영화", "카페가기", "여행", "독서", "요리"],
    "profile_photos": [{"count": 3}],
}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response], verification: str = "verified") -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다 — 완성도 조회도 profiles 를 읽는다.
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴공"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _handler(profile: dict, seen: list[httpx.Request] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        if request.method == "POST" and request.url.path.endswith("/rpc/home_stats"):
            return httpx.Response(200, json=[STATS_ROW])
        if request.method == "GET" and request.url.path.endswith("/profiles") \
                and request.url.params.get("id") == f"eq.{PROFILE_ID}":
            return httpx.Response(200, json=[profile])
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_summary_returns_service_stats_and_my_completion():
    response = _wire(_handler(FULL_PROFILE)).get("/home/summary", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json() == {
        "delivered_cards": 1280, "signups": 342, "conversations_started": 57,
        "campuses": ["고려대학교", "서울대학교", "연세대학교"],
        "profile_completion_percent": 100,
    }


def test_summary_reads_my_profile_and_photo_count_in_one_request():
    """전체 집계는 RPC 한 번, 내 완성도는 profiles 한 줄 + 사진 개수 embed 로 한 번 — 합쳐 두 번."""
    seen: list[httpx.Request] = []
    _wire(_handler(FULL_PROFILE, seen)).get("/home/summary", headers=AUTH_HEADERS)

    assert len(seen) == 2
    profile_request = next(r for r in seen if r.url.path.endswith("/profiles"))
    assert "profile_photos(count)" in profile_request.url.params["select"]


def test_summary_rejects_missing_login():
    response = _wire(_handler(FULL_PROFILE)).get("/home/summary")

    assert response.status_code == 401


def test_summary_rejects_unverified_student():
    response = _wire(_handler(FULL_PROFILE), verification="pending").get("/home/summary", headers=AUTH_HEADERS)

    assert response.status_code == 403


# 완성도: 60 + (사진 3장 이상 · MBTI · 선호 키 한쪽 이상 · 관심 태그 5개) 각 10 ----------------

def _percent(**overrides) -> int:
    values = {"photo_count": 3, "mbti": "INFP", "preferred_height_min": 170,
              "preferred_height_max": 185, "interest_tags": ["a", "b", "c", "d", "e"]}
    return completion_percent(**{**values, **overrides})


def test_completion_is_100_when_all_four_are_filled():
    assert _percent() == 100


def test_completion_floor_is_60_when_none_are_filled():
    assert _percent(photo_count=2, mbti=None, preferred_height_min=None,
                    preferred_height_max=None, interest_tags=["a", "b", "c"]) == 60


def test_completion_is_70_with_only_one_filled():
    assert _percent(photo_count=0, preferred_height_min=None,
                    preferred_height_max=None, interest_tags=[]) == 70


def test_two_photos_do_not_count_but_three_do():
    assert _percent(photo_count=2) == 90
    assert _percent(photo_count=3) == 100


def test_four_tags_do_not_count_but_five_do():
    assert _percent(interest_tags=["a", "b", "c", "d"]) == 90
    assert _percent(interest_tags=["a", "b", "c", "d", "e"]) == 100


def test_either_side_of_preferred_height_counts():
    assert _percent(preferred_height_min=170, preferred_height_max=None) == 100
    assert _percent(preferred_height_min=None, preferred_height_max=185) == 100
    assert _percent(preferred_height_min=None, preferred_height_max=None) == 90
