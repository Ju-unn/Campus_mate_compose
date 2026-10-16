"""받은 신청 · 프로필 보기(GET /cards/acceptances/{card_id}, pen `o4QqYR`).

받는 사람이 수락하기 전에 상대 프로필을 카드 상세(10b)와 같은 수준으로 본다. 몸통은 `profile_detail` 그대로이고,
거부 판정은 수락 응답(POST /cards/acceptances/{card_id})과 같은 코드다 — 남의 것 · 수락 아님 · 숨김 · 이미 매칭 404,
이미 답함 409, 7일 지남 410. 실사진 · 카카오톡 아이디는 신뢰 확인 뒤(14c)라 여기 없다.
"""
import json
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
ACCEPTER = "22222222-2222-2222-2222-222222222222"
AUTH = {"Authorization": "Bearer valid-token"}
SUPABASE_URL = "https://x.supabase.co"

# 10b 카드 상세와 같은 키(tests/me/test_me_card_preview.py DETAIL_KEYS + card_id).
DETAIL_KEYS = {
    "card_id", "profile", "survey", "animal_type", "impression_type", "religion", "is_smoker",
    "interests", "my_traits", "ideal_traits", "height_cm", "mbti", "student_number", "bio", "ideal_note",
}

ACCEPTER_ROW = {
    "id": ACCEPTER, "nickname": "여우비", "birth_year": 2003, "major": "컴퓨터공학과",
    "animal_type": "cat", "impression_type": "chic", "interest_tags": ["등산"], "my_traits": ["유머러스"],
    "ideal_traits": ["다정한"], "ideal_note": "같이 영화 보는 사람", "bio": "주말엔 산책해요",
    "status": "active", "auto_hidden_at": None, "universities": {"name": "테스트대학교"},
    "profile_avatars": [{"storage_path": f"{ACCEPTER}/a.png", "status": "ready", "created_at": "2026-10-01T00:00:00+00:00"}],
    "height_cm": 170, "mbti": "ENFP", "student_number": "22", "religion": "none", "is_smoker": False,
    # select 가 달라고 하지 않지만, 행에 섞여 와도 응답에 새면 안 된다.
    "kakao_id": "fox_kakao",
    "profile_photos": [{"storage_path": f"{ACCEPTER}/real.jpg", "position": 0}],
}


class _FakeCredentials:
    valid = True
    token = "ya29.test"


def _hours_ago(hours: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


class _World:
    """카드 한 장 · 상대 한 명 · 차단 · 매칭만 흉내 낸다. 쓰기(POST · PATCH)가 오면 기록한다 — 보기는 아무것도 쓰지 않는다."""

    def __init__(self) -> None:
        self.card: dict | None = {
            "id": "card-1", "owner_id": ACCEPTER, "target_id": ME, "source": "daily",
            "issued_at": _hours_ago(48), "expires_at": None,
            "card_decisions": {"decision": "accept", "decided_at": _hours_ago(24)},
            "acceptance_responses": None,
        }
        self.profile = dict(ACCEPTER_ROW)
        self.blocks: list[dict] = []
        self.matches: list[dict] = []
        self.writes: list[str] = []
        self.seen: list[httpx.Request] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.seen.append(request)
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        table = path.removeprefix("/rest/v1/")
        if request.method != "GET":
            self.writes.append(table)
            return httpx.Response(201, json=[])
        if table == "profiles":
            if "student_verification" in params.get("select", ""):
                return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                                  "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
            found = self.profile is not None and params.get("id") == f"eq.{ACCEPTER}"
            return httpx.Response(200, json=[self.profile] if found else [])
        if table == "daily_cards":
            card = self.card
            return httpx.Response(200, json=[card] if card and params.get("id") == f"eq.{card['id']}" else [])
        if table == "survey_answers":
            return httpx.Response(200, json=[{"axis": 1, "value": 0.5}])
        if table == "blocks":
            return httpx.Response(200, json=self.blocks)
        if table == "matches":
            return httpx.Response(200, json=self.matches)
        return httpx.Response(200, json=[])


@pytest.fixture
def world():
    world = _World()
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url=SUPABASE_URL, supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", http, credentials=_FakeCredentials())
    yield world
    app.dependency_overrides.clear()


def _get(card_id: str = "card-1") -> httpx.Response:
    return TestClient(app).get(f"/cards/acceptances/{card_id}", headers=AUTH)


def test_the_receiver_sees_the_accepter_like_a_card_detail(world):
    response = _get()

    assert response.status_code == 200
    body = response.json()
    assert set(body) == DETAIL_KEYS
    assert body["card_id"] == "card-1"
    assert body["profile"] == {
        "profile_id": ACCEPTER, "nickname": "여우비", "age": datetime.now().year - 2003 + 1,
        "university": "테스트대학교", "major": "컴퓨터공학과",
        "avatar_url": f"{SUPABASE_URL}/storage/v1/object/public/avatars/{ACCEPTER}/a.png",
    }
    assert body["survey"] == [0.5, 0, 0, 0, 0, 0, 0, 0, 0]
    assert body["bio"] == "주말엔 산책해요"
    assert body["interests"] == ["등산"]
    # 보기만 한다 — 응답 · 매칭 · 알림을 쓰지 않는다.
    assert world.writes == []


def test_the_body_never_carries_what_opens_only_after_trust(world):
    response = _get()
    body = response.json()

    assert response.status_code == 200 and set(body) == DETAIL_KEYS
    dumped = json.dumps(body, ensure_ascii=False)
    assert "fox_kakao" not in dumped and "real.jpg" not in dumped
    assert not any(word in key for key in body for word in ("kakao", "photo", "phone", "real_name"))
    select = next(r for r in world.seen if r.url.path == "/rest/v1/profiles"
                  and r.url.params.get("id") == f"eq.{ACCEPTER}").url.params["select"]
    assert "kakao" not in select and "profile_photos" not in select and "profile_private" not in select


@pytest.mark.parametrize("card", [
    None,  # 없는 카드
    {"target_id": "33333333-3333-3333-3333-333333333333"},  # 남이 받은 수락
    {"owner_id": ME, "target_id": ACCEPTER},  # 내가 보낸 신청(받는 사람이 아니다)
    {"card_decisions": {"decision": "reject", "decided_at": _hours_ago(24)}},  # 상대가 거절한 카드
    {"card_decisions": None},  # 상대가 아직 결정하지 않은 카드
])
def test_anything_but_an_acceptance_sent_to_me_is_404(world, card):
    world.card = None if card is None else {**world.card, **card}

    response = _get()

    assert response.status_code == 404
    assert response.json()["detail"] == "수락을 찾을 수 없어요"


def test_an_acceptance_older_than_seven_days_is_410(world):
    world.card["card_decisions"] = {"decision": "accept", "decided_at": _hours_ago(24 * 7 + 1)}

    response = _get()

    assert response.status_code == 410
    assert response.json()["detail"] == "기한이 지났어요"


def test_an_acceptance_i_already_answered_is_409(world):
    world.card["acceptance_responses"] = {"responder_id": ME}

    response = _get()

    assert response.status_code == 409
    assert response.json()["detail"] == "이미 답한 수락이에요"


@pytest.mark.parametrize("blocks", [
    [{"blocker_id": ME, "blocked_id": ACCEPTER}],
    [{"blocker_id": ACCEPTER, "blocked_id": ME}],
])
def test_a_blocked_accepter_is_404(world, blocks):
    world.blocks = blocks

    response = _get()

    assert response.status_code == 404
    assert response.json()["detail"] == "수락을 찾을 수 없어요"


@pytest.mark.parametrize("hidden", [
    {"status": "suspended"}, {"status": "withdrawn"}, {"auto_hidden_at": "2026-10-01T00:00:00+00:00"},
])
def test_a_suspended_withdrawn_or_hidden_accepter_is_404(world, hidden):
    world.profile.update(hidden)

    assert _get().status_code == 404


def test_an_accepter_without_a_profile_row_is_404_not_500(world):
    world.profile = None

    response = _get()

    assert response.status_code == 404
    assert response.json()["detail"] == "수락을 찾을 수 없어요"


def test_someone_already_matched_with_me_is_404(world):
    """받은 신청 목록처럼 이미 매칭된 상대는 답할 게 없다(결정 11) — 목록에 없는 줄은 열리지도 않는다."""
    world.matches = [{"id": "match-1", "profile_a": ME, "profile_b": ACCEPTER, "created_at": _hours_ago(1),
                      "match_participants": []}]

    response = _get()

    assert response.status_code == 404
    assert response.json()["detail"] == "수락을 찾을 수 없어요"


def test_the_route_does_not_swallow_the_acceptances_list(world):
    """`/cards/acceptances` 목록은 그대로 목록이다 — 새 경로가 앞을 가로채지 않는다."""
    response = TestClient(app).get("/cards/acceptances", headers=AUTH)

    assert response.status_code == 200
    assert "acceptances" in response.json()
