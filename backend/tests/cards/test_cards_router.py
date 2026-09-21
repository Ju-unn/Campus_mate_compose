from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.cards.push import FcmSender
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}

TARGET_PROFILE = {
    "id": "t1", "nickname": "여우비", "birth_year": 2003, "major": "컴퓨터공학과",
    "animal_type": "cat", "impression_type": "cute", "interest_tags": ["영화"],
    "my_traits": ["조용한"], "ideal_traits": ["다정한"], "ideal_note": "같이 영화 보는 사람",
    "bio": "안녕하세요", "height_cm": 165, "mbti": "INFP", "student_number": "20",
    "religion": "none", "is_smoker": False,
    "universities": {"name": "테스트대학교", "region_group": "seoul"},
    "profile_avatars": [{"storage_path": "t1/a.png", "status": "ready",
                         "created_at": "2026-09-20T00:00:00+00:00"}],
}
REGION_SETTINGS = [{"region_group": "seoul", "issue_weekdays": [1, 4], "issue_time": "07:00:00",
                    "ladder_three_per_week_min": 200, "ladder_daily_min": 500}]


class _FakeCredentials:
    valid = True
    token = "ya29.test"


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    monkeypatch.setattr(router_module, "get_settings", lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test",
    ))
    yield
    router_module._client_override = None
    router_module._sender_override = None


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    router_module._client_override = client
    # FCM 은 목 클라이언트로 보낸다 — ADC 자격증명을 테스트에서 찾지 않게 한다.
    router_module._sender_override = FcmSender("campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _live_card(**overrides) -> dict:
    return {"id": "card-1", "owner_id": PROFILE_ID, "target_id": "t1", "source": "daily",
            "issued_at": "2026-09-21T07:00:00+09:00", "expires_at": "2126-09-24T07:00:00+09:00",
            "card_decisions": None, **overrides}


def test_today_returns_the_live_card_with_profile():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[_live_card()])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[TARGET_PROFILE])
        if "/rest/v1/region_group_settings" in url:
            return httpx.Response(200, json=REGION_SETTINGS)
        return httpx.Response(200, json=[])

    response = _wire(handler).get("/cards/today", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    card = body["cards"][0]
    assert card["card_id"] == "card-1"
    assert card["source"] == "daily"
    assert card["profile"]["nickname"] == "여우비"
    assert card["profile"]["age"] == 24  # 한국 나이 계산은 조각 2 규칙을 따른다
    assert card["profile"]["university"] == "테스트대학교"
    assert card["profile"]["avatar_url"].endswith("/avatars/t1/a.png")
    # 카드가 있으면 후보 풀을 다시 묻지 않는다.
    assert body["candidate_pool_empty"] is False


def test_today_without_cards_tells_the_pool_is_empty():
    """카드도 후보도 없으면 화면 11b(지금은 소개할 사람이 없어요)가 떠야 한다."""
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/region_group_settings" in url:
            return httpx.Response(200, json=REGION_SETTINGS)
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[TARGET_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get("/cards/today", headers=AUTH_HEADERS).json()

    assert body["cards"] == []
    assert body["candidate_pool_empty"] is True
    # 다음 지급일은 지역 설정에서 읽는다(월·목 지급).
    assert body["next_issue_at"].endswith("+09:00")


def test_card_detail_carries_the_nine_survey_axes():
    """10b 상세는 성향 9축을 축 번호 순서대로 받는다 — 답하지 않은 축은 0 이다."""
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[_live_card()])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[TARGET_PROFILE])
        if "/rest/v1/survey_answers" in url:
            return httpx.Response(200, json=[{"axis": 1, "value": 0.5}, {"axis": 9, "value": -1}])
        return httpx.Response(200, json=[])

    body = _wire(handler).get("/cards/card-1", headers=AUTH_HEADERS).json()

    assert body["survey"] == [0.5, 0, 0, 0, 0, 0, 0, 0, -1.0]
    assert body["animal_type"] == "cat"
    assert body["is_smoker"] is False
    assert body["ideal_note"] == "같이 영화 보는 사람"


def test_decision_on_someone_elses_card_is_404():
    """카드 주인만 결정할 수 있다. 남의 카드 id 를 찍어 보는 시도는 존재 자체를 알려주지 않는다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_live_card(owner_id="somebody-else")])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})
    assert response.status_code == 404


def test_expired_card_cannot_be_decided():
    """만료된 카드는 결정할 수 없다 — 무응답으로 끝난 카드다(설계 §2.4)."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_live_card(expires_at="2026-09-20T07:00:00+09:00")])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})
    assert response.status_code == 409


def test_deciding_twice_is_conflict():
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_live_card(card_decisions={"decision": "accept",
                                                                        "decided_at": "2026-09-21T08:00:00+09:00"})])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "reject"})
    assert response.status_code == 409


def test_accept_notifies_the_target():
    """A 가 수락하면 B 에게 '받은 수락' 알림이 간다(설계 §2.2)."""
    pushes: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            pushes.append(url)
            return httpx.Response(200, json={"name": "sent"})
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[_live_card()])
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        if "/rest/v1/notification_settings" in url:
            return httpx.Response(200, json=[{"acceptance_received": True, "quiet_hours": False}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[TARGET_PROFILE])
        return httpx.Response(201, json=[{"id": "x"}])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert len(pushes) == 1


def test_reject_notifies_nobody():
    """거절은 조용히 끝난다 — 상대에게 아무 신호도 가지 않는다(설계 §2.2)."""
    pushes: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            pushes.append(url)
            return httpx.Response(200, json={"name": "sent"})
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[_live_card()])
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        return httpx.Response(201, json=[{"id": "x"}])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "reject"})

    assert response.status_code == 200
    assert pushes == []


def test_unknown_decision_value_is_rejected():
    response = _wire(lambda r: httpx.Response(200, json=[])).post(
        "/cards/card-1/decision", headers=AUTH_HEADERS, json={"decision": "maybe"}
    )
    assert response.status_code == 422
