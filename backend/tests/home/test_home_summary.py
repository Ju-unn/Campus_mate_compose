import json
import logging
from collections.abc import Callable
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_settings
from app.home.completion import completion_percent
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
UNIVERSITY_ID = "22222222-2222-2222-2222-222222222222"
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
    # 여는 시각 null = 코호트 없이 이미 열린 학교(지금 학교 전부).
    "university_id": UNIVERSITY_ID, "universities": {"card_opens_at": None},
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
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _handler(profile: dict, seen: list[httpx.Request] | None = None, touch_status: int = 204):
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        if request.method == "POST" and request.url.path.endswith("/rpc/home_stats"):
            return httpx.Response(200, json=[STATS_ROW])
        if request.url.path.endswith("/profiles") and request.url.params.get("id") == f"eq.{PROFILE_ID}":
            if request.method == "GET":
                return httpx.Response(200, json=[profile])
            if request.method == "PATCH":
                return httpx.Response(touch_status)
        # 모집 인원 세기는 university_id 키로 가른다 — 완성도 조회도 profiles 를 읽는다.
        if request.method == "GET" and request.url.params.get("university_id") == f"eq.{UNIVERSITY_ID}":
            return httpx.Response(200, json=[{"id": PROFILE_ID}], headers={"Content-Range": "0-0/37"})
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_summary_returns_service_stats_and_my_completion():
    response = _wire(_handler(FULL_PROFILE)).get("/home/summary", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json() == {
        "delivered_cards": 1280, "signups": 342, "conversations_started": 57,
        "campuses": ["고려대학교", "서울대학교", "연세대학교"],
        "profile_completion_percent": 100,
        "cohort": None,
    }


def test_summary_reads_my_profile_and_photo_count_in_one_request():
    """전체 집계는 RPC 한 번, 내 완성도는 profiles 한 줄 + 사진 개수 embed 로 한 번 — 합쳐 두 번."""
    seen: list[httpx.Request] = []
    _wire(_handler(FULL_PROFILE, seen)).get("/home/summary", headers=AUTH_HEADERS)

    reads = [r for r in seen if r.method != "PATCH"]
    assert len(reads) == 2
    profile_request = next(r for r in reads if r.url.path.endswith("/profiles"))
    assert "profile_photos(count)" in profile_request.url.params["select"]
    assert "universities(card_opens_at)" in profile_request.url.params["select"]


# 코호트(19): 학교 여는 시각이 아직 안 왔으면 첫 카드 시각과 모집 인원을 준다 --------------------------

def _summary_with_opens_at(opens_at: str | None, seen: list[httpx.Request]) -> dict:
    profile = {**FULL_PROFILE, "universities": {"card_opens_at": opens_at}}
    response = _wire(_handler(profile, seen)).get("/home/summary", headers=AUTH_HEADERS)
    assert response.status_code == 200
    return response.json()


def _recruit_counts(seen: list[httpx.Request]) -> list[httpx.Request]:
    return [r for r in seen if "university_id" in r.url.params]


def test_cohort_is_null_and_nothing_is_counted_when_the_school_has_no_opening_time():
    """지금 운영 중인 학교는 전부 null 이다 — 이 사람들에게 인원 세기를 부르면 홈을 열 때마다 헛일이다."""
    seen: list[httpx.Request] = []

    assert _summary_with_opens_at(None, seen)["cohort"] is None
    assert _recruit_counts(seen) == []


def test_cohort_is_null_once_the_opening_time_has_passed():
    seen: list[httpx.Request] = []
    past = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()

    assert _summary_with_opens_at(past, seen)["cohort"] is None
    assert _recruit_counts(seen) == []


def test_cohort_has_first_card_time_and_active_recruit_count_before_opening():
    seen: list[httpx.Request] = []
    # PostgREST 는 timestamptz 를 +00:00 으로 준다. 서울 월요일 07:00 = UTC 일요일 22:00.
    opens_at = "2099-01-04T22:00:00+00:00"

    assert _summary_with_opens_at(opens_at, seen)["cohort"] == {
        "first_card_at": opens_at, "recruit_count": 37,
    }
    [count] = _recruit_counts(seen)
    assert count.url.path.endswith("/profiles")
    assert count.url.params["university_id"] == f"eq.{UNIVERSITY_ID}"
    # 모집 인원 = 가입을 다 끝낸 사람(계획서 결정 3, 홈 "가입 수"와 같은 기준).
    assert count.url.params["status"] == "eq.active"
    assert count.headers["prefer"] == "count=exact"


# 활동 시각: 홈을 열 때 한 시간보다 오래됐을 때만 지금으로 바꾼다 ---------------------------------

def _touch(seen: list[httpx.Request]) -> httpx.Request:
    [touch] = [r for r in seen if r.method == "PATCH"]
    return touch


def test_summary_touches_last_active_only_when_older_than_an_hour():
    """조건은 PostgREST 필터에 건다 — 읽고 비교한 뒤 쓰면 두 요청이 겹칠 때 둘 다 쓴다.
    이 값이 안 바뀌면 가입 14일 뒤 카드가 끊기고 15일 뒤 남의 후보에서 빠진다(card_issue_owners · match_candidates)."""
    seen: list[httpx.Request] = []
    before = datetime.now(timezone.utc)
    _wire(_handler(FULL_PROFILE, seen)).get("/home/summary", headers=AUTH_HEADERS)
    after = datetime.now(timezone.utc)

    touch = _touch(seen)
    assert touch.url.path.endswith("/profiles")
    assert touch.url.params["id"] == f"eq.{PROFILE_ID}"
    op, threshold = touch.url.params["last_active_at"].split(".", 1)
    assert op == "lt"
    assert before - timedelta(hours=1) <= datetime.fromisoformat(threshold) <= after - timedelta(hours=1)
    written = datetime.fromisoformat(json.loads(touch.content)["last_active_at"])
    assert before <= written <= after


def test_summary_succeeds_and_logs_when_the_touch_fails(caplog):
    seen: list[httpx.Request] = []
    with caplog.at_level(logging.WARNING, logger="app.home.router"):
        response = _wire(_handler(FULL_PROFILE, seen, touch_status=500)).get("/home/summary", headers=AUTH_HEADERS)

    assert _touch(seen)
    assert response.status_code == 200
    assert response.json()["profile_completion_percent"] == 100
    assert "last_active_at" in caplog.text


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
