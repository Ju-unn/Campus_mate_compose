"""조각 6: "상대가 내 카드 화면에서 사라져야 하는가".

차단(양방향) · 상대 status 가 active 가 아님(정지 · 탈퇴) · 상대 auto_hidden_at 이 있음. 후보 SQL 은 새 카드를
막고(PR 1), 여기는 **이미 나간 카드와 받은 수락**을 막는다 — 차단한 상대의 수락을 눌러 매칭이 생기면 안 된다.
"""
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.cards.push import FcmSender
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
AUTH = {"Authorization": "Bearer valid-token"}
HIDDEN = {
    "i-blocked": {},
    "blocked-me": {},
    "auto-hidden": {"auto_hidden_at": "2026-09-26T10:00:00+09:00"},
    "suspended": {"status": "suspended"},
    "withdrawn": {"status": "withdrawn"},
}
VISIBLE = "visible"
BLOCKS = [{"blocker_id": ME, "blocked_id": "i-blocked"}, {"blocker_id": "blocked-me", "blocked_id": ME}]


class _FakeCredentials:
    valid = True
    token = "ya29.test"


def _profile(profile_id: str) -> dict:
    return {
        "id": profile_id, "nickname": f"닉-{profile_id}", "birth_year": 2003, "major": "컴퓨터공학과",
        "status": "active", "auto_hidden_at": None, "universities": {"name": "테스트대학교"},
        "profile_avatars": [], **HIDDEN.get(profile_id, {}),
    }


def _decided_at() -> str:
    return (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()


class _World:
    def __init__(self) -> None:
        self.posted: list[str] = []
        self.pushes = 0

    def handle(self, request: httpx.Request) -> httpx.Response:
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        if request.url.host == "fcm.googleapis.com":
            self.pushes += 1
            return httpx.Response(200, json={"name": "sent"})
        table = path.removeprefix("/rest/v1/")
        if request.method in ("POST", "PATCH"):
            self.posted.append(table)
            if table == "matches":
                return httpx.Response(201, json=[{"id": "match-1"}])
            return httpx.Response(201, json=[])
        if table == "profiles":
            if "student_verification" in params.get("select", ""):
                return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
            return httpx.Response(200, json=[_profile(params["id"].removeprefix("eq."))])
        if table == "blocks":
            return httpx.Response(200, json=BLOCKS)
        if table == "daily_cards":
            if "id" in params:
                return httpx.Response(200, json=[self._card(params["id"].removeprefix("eq.card-"))])
            return httpx.Response(200, json=[self._card(t) for t in [*HIDDEN, VISIBLE]])
        if table == "card_decisions":
            return httpx.Response(200, json=[{
                "card_id": f"card-{owner}", "decided_at": _decided_at(),
                "daily_cards": {"id": f"card-{owner}", "owner_id": owner, "target_id": ME,
                                "acceptance_responses": None},
            } for owner in [*HIDDEN, VISIBLE]])
        if table == "push_tokens":
            return httpx.Response(200, json=[{"token": "tok"}])
        return httpx.Response(200, json=[])

    def _card(self, other: str) -> dict:
        """내 카드면 other 가 대상이고, 받은 수락이면 other 가 카드 주인이다 — 두 모양을 한 장에 담는다."""
        return {
            "id": f"card-{other}", "owner_id": ME, "target_id": other, "source": "daily",
            "issued_at": "2026-09-27T07:00:00+09:00", "expires_at": "2126-09-30T07:00:00+09:00",
            "card_decisions": None, "acceptance_responses": None,
        }


def _received(other: str) -> dict:
    return {
        "id": f"card-{other}", "owner_id": other, "target_id": ME, "source": "daily",
        "issued_at": "2026-09-27T07:00:00+09:00", "expires_at": None,
        "card_decisions": {"decision": "accept", "decided_at": _decided_at()},
        "acceptance_responses": None,
    }


@pytest.fixture
def world():
    world = _World()
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", http, credentials=_FakeCredentials())
    yield world
    app.dependency_overrides.clear()


def test_today_drops_every_hidden_partner(world):
    body = TestClient(app).get("/cards/today", headers=AUTH).json()

    assert [card["profile"]["profile_id"] for card in body["cards"]] == [VISIBLE]


@pytest.mark.parametrize("other", list(HIDDEN))
def test_a_hidden_partners_card_detail_is_404(world, other):
    response = TestClient(app).get(f"/cards/card-{other}", headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "카드를 찾을 수 없어요"


@pytest.mark.parametrize("other", list(HIDDEN))
def test_deciding_on_a_hidden_partner_is_404_and_writes_nothing(world, other):
    response = TestClient(app).post(f"/cards/card-{other}/decision", headers=AUTH,
                                    json={"decision": "accept"})

    assert response.status_code == 404
    assert response.json()["detail"] == "카드를 찾을 수 없어요"
    assert world.posted == []
    assert world.pushes == 0


def test_the_visible_partner_is_still_decidable(world):
    response = TestClient(app).post(f"/cards/card-{VISIBLE}/decision", headers=AUTH,
                                    json={"decision": "reject"})

    assert response.status_code == 200
    assert world.posted == ["card_decisions"]


def test_acceptances_drop_every_hidden_accepter(world):
    body = TestClient(app).get("/cards/acceptances", headers=AUTH).json()

    assert [row["profile"]["profile_id"] for row in body["acceptances"]] == [VISIBLE]


@pytest.mark.parametrize("other", list(HIDDEN))
def test_accepting_a_hidden_accepter_is_404_and_makes_no_match(world, other, monkeypatch):
    monkeypatch.setattr(_World, "_card", lambda self, o: _received(o))

    response = TestClient(app).post(f"/cards/acceptances/card-{other}", headers=AUTH,
                                    json={"decision": "accept"})

    assert response.status_code == 404
    assert response.json()["detail"] == "수락을 찾을 수 없어요"
    assert "matches" not in world.posted
    assert world.posted == []


def test_the_visible_accepter_still_makes_a_match(world, monkeypatch):
    monkeypatch.setattr(_World, "_card", lambda self, o: _received(o))

    response = TestClient(app).post(f"/cards/acceptances/card-{VISIBLE}", headers=AUTH,
                                    json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert "matches" in world.posted


def test_blocks_are_read_once_per_request_not_per_card(world):
    """카드마다 차단을 따로 묻지 않는다 — N+1 은 프로필 조회 한 번(기존 구조)까지만."""
    seen: list[str] = []
    original = world.handle

    def counting(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        return original(request)

    http = httpx.AsyncClient(transport=httpx.MockTransport(counting))
    app.dependency_overrides[get_client] = lambda: http

    TestClient(app).get("/cards/today", headers=AUTH)

    assert seen.count("/rest/v1/blocks") == 1

