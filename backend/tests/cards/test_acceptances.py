from collections.abc import Callable
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.cards.push import FcmSender
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
OTHER_ID = "22222222-2222-2222-2222-222222222222"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}

ACCEPTER_PROFILE = {
    "id": OTHER_ID, "nickname": "여우비", "birth_year": 2003, "major": "컴퓨터공학과",
    "universities": {"name": "테스트대학교"}, "profile_avatars": [],
}


class _FakeCredentials:
    valid = True
    token = "ya29.test"


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender("campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _hours_ago(hours: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


def _accepted_card(decided_at: str, **overrides) -> dict:
    """나를 수락한 카드 한 장 — 주인은 상대(OTHER_ID), 대상은 나다."""
    return {
        "id": "card-1", "owner_id": OTHER_ID, "target_id": PROFILE_ID, "source": "daily",
        "issued_at": _hours_ago(48), "expires_at": None,
        # PostgREST 는 card_id 가 PK 인 두 테이블을 one-to-one 으로 보고 객체/null 을 준다.
        "card_decisions": {"decision": "accept", "decided_at": decided_at},
        "acceptance_responses": None, **overrides,
    }


def _pushes_and_matches(handler_extra=None):
    """FCM 호출과 만들어진 매칭·참가자 행을 모아 두는 공통 핸들러."""
    pushes: list[dict] = []
    posted: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            import json
            pushes.append(json.loads(request.content))
            return httpx.Response(200, json={"name": "sent"})
        if request.method == "POST" and "/rest/v1/" in url:
            posted.append(url)
        if "/rest/v1/matches" in url and request.method == "POST":
            return httpx.Response(201, json=[{"id": "match-1"}])
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        if "/rest/v1/notification_settings" in url:
            return httpx.Response(200, json=[{"match_made": True, "quiet_hours": False}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[ACCEPTER_PROFILE])
        if handler_extra is not None:
            return handler_extra(request)
        return httpx.Response(200, json=[])

    return handler, pushes, posted


def test_acceptances_list_shows_who_accepted_me():
    """받은 수락함(13 `XCN1f`)은 아직 답하지 않은 수락만, 받은 지 7일까지 보여준다."""
    decided_at = _hours_ago(24)

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/card_decisions" in url:
            return httpx.Response(200, json=[{
                "card_id": "card-1", "decided_at": decided_at,
                "daily_cards": {"id": "card-1", "owner_id": OTHER_ID, "target_id": PROFILE_ID,
                                "acceptance_responses": None},
            }])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[ACCEPTER_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get("/cards/acceptances", headers=AUTH_HEADERS).json()

    assert len(body["acceptances"]) == 1
    row = body["acceptances"][0]
    assert row["card_id"] == "card-1"
    assert row["profile"]["nickname"] == "여우비"
    # 만료는 수락받은 때 + 7일이다 — 앱은 계산하지 않고 이 값을 그대로 쓴다.
    assert datetime.fromisoformat(row["expires_at"]) == datetime.fromisoformat(decided_at) + timedelta(days=7)


def test_accepting_creates_a_match_and_notifies_both():
    """쌍방 수락이면 matches 한 행 + participants 두 행이 생기고, 두 사람 모두에게 알림이 간다(설계 §2.2)."""
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        return httpx.Response(200, json=[])

    handler, pushes, posted = _pushes_and_matches(extra)
    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 200
    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert sum("/rest/v1/match_participants" in url for url in posted) == 1
    assert len(pushes) == 2


def test_an_already_existing_match_does_not_notify_twice():
    """A→B, B→A 카드가 같은 날 나가 둘 다 수락하면 두 번째 수락은 이미 있는 매칭을 본다.
    빈 insert 응답(on conflict do nothing)이 그 신호다 — 여기서 또 보내면 알림이 두 번 간다."""
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        return httpx.Response(200, json=[])

    handler, pushes, posted = _pushes_and_matches(extra)

    def conflicting(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/matches" in str(request.url):
            if request.method == "POST":
                return httpx.Response(201, json=[])
            return httpx.Response(200, json=[{"id": "match-1"}])
        return handler(request)

    response = _wire(conflicting).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                       json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert pushes == []


def test_rejecting_does_not_notify_anyone():
    """거절은 조용히 끝난다 — 상대에게 신호가 가지 않는다(설계 §2.2)."""
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        return httpx.Response(200, json=[])

    handler, pushes, posted = _pushes_and_matches(extra)
    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "reject"})

    assert response.json() == {"matched": False}
    assert pushes == []
    assert not any("/rest/v1/matches" in url for url in posted)


def test_acceptance_older_than_seven_days_is_gone():
    """받은 수락함은 7일이 지나면 목록에서 사라진다(2026-09-21 확정). 응답도 받지 않는다(410)."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24 * 8))])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 410


def test_responding_twice_is_conflict():
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(
                _hours_ago(24), acceptance_responses={"responder_id": PROFILE_ID},
            )])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 409


def test_responding_to_someone_elses_acceptance_is_404():
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24), target_id="nobody")])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 404
