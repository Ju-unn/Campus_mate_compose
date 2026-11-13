import json
import logging
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
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공", "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
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


def _pushes_and_matches(handler_extra=None, broadcasts: list[dict] | None = None):
    """FCM 호출과 만들어진 매칭·참가자 행을 모아 두는 공통 핸들러. broadcasts 를 넘기면 실시간 이벤트도 모은다."""
    pushes: list[dict] = []
    posted: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            import json
            pushes.append(json.loads(request.content))
            return httpx.Response(200, json={"name": "sent"})
        if request.url.path == "/realtime/v1/api/broadcast":
            import json
            if broadcasts is not None:
                broadcasts.extend(json.loads(request.content)["messages"])
            return httpx.Response(202)
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


def test_acceptances_list_drops_someone_already_matched_with_me():
    """A→B, B→A 카드를 둘 다 수락하면 이미 매칭인데 수락함에 상대가 남았다(결정 11, B8)."""
    third_id = "33333333-3333-3333-3333-333333333333"
    decided_at = _hours_ago(24)

    def row(card_id: str, owner_id: str) -> dict:
        return {"card_id": card_id, "decided_at": decided_at,
                "daily_cards": {"id": card_id, "owner_id": owner_id, "target_id": PROFILE_ID,
                                "acceptance_responses": None}}

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/card_decisions" in url:
            return httpx.Response(200, json=[row("card-1", OTHER_ID), row("card-3", third_id)])
        if "/rest/v1/matches" in url:
            return httpx.Response(200, json=[{"profile_a": PROFILE_ID, "profile_b": OTHER_ID}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[ACCEPTER_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get("/cards/acceptances", headers=AUTH_HEADERS).json()

    assert [r["card_id"] for r in body["acceptances"]] == ["card-3"]


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
    # 신청한 쪽(카드 주인)에게는 "신청을 수락했어요"(지시문 22 G), 방금 수락한 나에게는 기존 문구 그대로.
    assert [p["message"]["notification"] for p in pushes] == [
        {"title": "매칭됐어요!", "body": "여우비 님이 신청을 수락했어요."},
        {"title": "매칭됐어요!", "body": "여우비 님과 대화를 시작해 보세요"},
    ]


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


def _accept_card_one(conflict: bool) -> list[dict]:
    """card-1 을 수락하고 나간 실시간 이벤트를 돌려준다. conflict 면 매칭이 이미 있었던 경우다."""
    broadcasts: list[dict] = []

    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        return httpx.Response(200, json=[])

    handler, _, _ = _pushes_and_matches(extra, broadcasts)

    def maybe_conflicting(request: httpx.Request) -> httpx.Response:
        if conflict and "/rest/v1/matches" in str(request.url):
            return httpx.Response(201, json=[]) if request.method == "POST" else httpx.Response(200, json=[{"id": "match-1"}])
        return handler(request)

    response = _wire(maybe_conflicting).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                             json={"decision": "accept"})
    assert response.status_code == 200
    return broadcasts


def test_a_new_match_tells_both_people_to_reload_the_list():
    """새 방은 상대 프로필이 필요해서 신호만 보낸다 — 앱이 목록을 한 번 다시 읽는다(설계안 A)."""
    broadcasts = _accept_card_one(conflict=False)

    assert [(b["topic"], b["event"]) for b in broadcasts] == [
        (f"user:{OTHER_ID}", "room_changed"), (f"user:{PROFILE_ID}", "room_changed")]
    assert broadcasts[0]["payload"] == {"match_id": "match-1", "reason": "matched"}
    assert broadcasts[0]["private"] is True


def test_an_already_existing_match_tells_nobody():
    assert _accept_card_one(conflict=True) == []


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


class _Unfinished:
    """받은 신청 한 장(card-1, 보낸 사람 OTHER_ID)에 내가 mine 으로 답해 둔 세상 — mine 이 None 이면 아직 안 답했다.
    매칭은 만들면 남는다: 두 번째 POST 는 on conflict do nothing 이라 빈 응답이고, 매칭 읽기는 만든 것을 돌려준다.
    참가자 쓰기(merge)도 그 매칭에 남는다. participants 를 주면 매칭이 이미 있고 참가자가 그만큼만 들어간 세상이다 —
    2 가 평소 모습, 0 · 1 은 매칭 행만 들어가고 참가자 쓰기가 끊긴 반쪽이다(대화 목록에 방이 안 보이고 열면 404)."""

    def __init__(self, mine: str | None = "accept", match_status: int = 201, blocked: bool = False,
                 participants: int | None = None) -> None:
        self.mine, self.match_status, self.blocked = mine, match_status, blocked
        self.matches: list[dict] = []
        if participants is not None:
            self.matches.append({"id": "match-1", "profile_a": PROFILE_ID, "profile_b": OTHER_ID,
                                 "created_at": _hours_ago(1),
                                 "match_participants": [{"profile_id": who, "left_at": None}
                                                        for who in (PROFILE_ID, OTHER_ID)[:participants]]})
        self.writes: list[str] = []
        self.pushes: list[dict] = []
        self.broadcasts: list[dict] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        path, params = request.url.path, request.url.params
        if request.url.host == "fcm.googleapis.com":
            self.pushes.append(json.loads(request.content)["message"])
            return httpx.Response(200, json={"name": "sent"})
        if path == "/realtime/v1/api/broadcast":
            self.broadcasts.extend(json.loads(request.content)["messages"])
            return httpx.Response(202)
        table = path.removeprefix("/rest/v1/")
        if request.method != "GET":
            self.writes.append(table)
            if table == "match_participants":
                rows = self.matches[0]["match_participants"]
                rows.extend({"profile_id": row["profile_id"], "left_at": None} for row in json.loads(request.content)
                            if row["profile_id"] not in [p["profile_id"] for p in rows])
            if table != "matches":
                return httpx.Response(201, json=[])
            if self.match_status != 201:
                return httpx.Response(self.match_status, json={})
            if self.matches:
                return httpx.Response(201, json=[])
            self.matches.append({"id": "match-1", "profile_a": PROFILE_ID, "profile_b": OTHER_ID,
                                 "created_at": _hours_ago(0), "match_participants": []})
            return httpx.Response(201, json=self.matches)
        if table == "daily_cards":
            return httpx.Response(200, json=[_accepted_card(
                _hours_ago(24), acceptance_responses={"responder_id": PROFILE_ID, "decision": self.mine})])
        if table == "card_decisions":
            # PostgREST 처럼 select 에 적힌 칸만 준다 — 저장소가 decision 을 읽지 않으면 이어 만들 카드를 못 알아본다.
            asked = "acceptance_responses(card_id,decision)" in params["select"]
            mine = {"card_id": "card-1", **({"decision": self.mine} if asked else {})} if self.mine else None
            return httpx.Response(200, json=[{
                "card_id": "card-1", "decided_at": _hours_ago(24),
                "daily_cards": {"id": "card-1", "owner_id": OTHER_ID, "target_id": PROFILE_ID,
                                "acceptance_responses": mine},
            }])
        if table == "matches":
            return httpx.Response(200, json=self.matches)
        if table == "blocks":
            return httpx.Response(200, json=[{"blocker_id": PROFILE_ID, "blocked_id": OTHER_ID}] if self.blocked else [])
        if table == "push_tokens":
            return httpx.Response(200, json=[{"token": "tok"}])
        if table == "notification_settings":
            return httpx.Response(200, json=[{"match_made": True, "quiet_hours": False}])
        if table == "profiles":
            return httpx.Response(200, json=[ACCEPTER_PROFILE])
        return httpx.Response(200, json=[])

    def read_list(self) -> httpx.Response:
        return _wire(self.handle).get("/cards/acceptances", headers=AUTH_HEADERS)

    def participants(self) -> list[str]:
        return sorted(p["profile_id"] for p in self.matches[0]["match_participants"])

    def room_writes(self) -> list[str]:
        """알림함 한 줄(notifications)을 뺀 쓰기 — 매칭 · 참가자 · 응답만 본다."""
        return [table for table in self.writes if table != "notifications"]


def test_reading_the_list_finishes_a_match_whose_write_was_cut_off():
    """수락 응답은 저장됐는데 매칭 만들기가 끊긴 카드 — 앱은 실패하면 POST 를 다시 보내지 않고 목록만 다시 읽는다.
    그 목록 읽기가 방을 이어 만든다: 매칭 1개 · 참가자 두 행 한 번 · 알림 2건. 답한 카드라 목록에는 여전히 없다."""
    world = _Unfinished()

    response = world.read_list()

    assert response.status_code == 200
    assert response.json() == {"acceptances": []}
    assert world.room_writes() == ["matches", "match_participants"]
    assert [p["notification"]["body"] for p in world.pushes] == [
        "여우비 님이 신청을 수락했어요.", "여우비 님과 대화를 시작해 보세요"]
    assert [b["event"] for b in world.broadcasts] == ["room_changed", "room_changed"]


def test_a_finished_match_is_logged_once_with_ids_only(caplog):
    with caplog.at_level(logging.WARNING, logger="app.cards.router"):
        _Unfinished().read_list()

    assert [record.getMessage() for record in caplog.records if record.name == "app.cards.router"] == [
        f"끊긴 매칭 이어 만듦 card=card-1 match=match-1 profile={PROFILE_ID} accepter={OTHER_ID}"]


def test_reading_the_list_twice_makes_one_match_and_notifies_once():
    world = _Unfinished()

    world.read_list()
    world.read_list()

    assert len(world.matches) == 1
    assert world.room_writes() == ["matches", "match_participants"]   # 두 번째는 이미 매칭된 상대라 쓰지도 않는다
    assert len(world.pushes) == 2
    assert len(world.broadcasts) == 2


def test_a_failing_match_write_does_not_break_the_list(caplog):
    """이어 만들기는 덤이다 — 실패해도 목록은 200 이고, 다음에 읽을 때 다시 해 본다. 로그에는 카드 번호와 예외 종류만."""
    world = _Unfinished(match_status=503)

    with caplog.at_level(logging.WARNING, logger="app.cards.router"):
        response = world.read_list()

    assert response.status_code == 200
    assert response.json() == {"acceptances": []}
    assert world.pushes == []
    assert [record.getMessage() for record in caplog.records
            if record.name == "app.cards.router"] == ["매칭 이어 만들기 실패 card=card-1 | HTTPStatusError"]


@pytest.mark.parametrize("world", [
    _Unfinished(mine="reject"),      # 내가 거절한 카드
    _Unfinished(blocked=True),       # 수락한 뒤 차단한 상대 — POST 와 같은 관문에 걸려 조용히 건너뛴다
    _Unfinished(mine=None),          # 이어 만들 것이 없다(아직 답하지 않은 카드뿐)
], ids=["rejected", "blocked", "nothing-to-finish"])
def test_reading_the_list_writes_nothing_when_there_is_no_match_to_finish(world):
    response = world.read_list()

    assert response.status_code == 200
    assert (world.writes, world.pushes, world.broadcasts) == ([], [], [])


def _list_reads(world: _Unfinished) -> list[str]:
    """목록 한 번에 서버가 Supabase 로 보낸 요청의 경로들(로그인 · 관문 읽기는 _wire 가 먼저 답해 여기 안 잡힌다)."""
    seen: list[str] = []

    def counting(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        return world.handle(request)

    _wire(counting).get("/cards/acceptances", headers=AUTH_HEADERS)
    return sorted(seen)


def test_an_already_matched_accepted_card_adds_no_database_round_trip():
    """평소 모습 — 내가 수락했고 매칭도 이미 있는 카드. 이어 만들 것이 없으면 예전과 같은 읽기 세 번뿐이다
    (상대 프로필 · 지인 차단을 더 읽지 않는다)."""
    world = _Unfinished(participants=2)

    assert _list_reads(world) == ["/rest/v1/blocks", "/rest/v1/card_decisions", "/rest/v1/matches"]
    assert world.writes == []


@pytest.mark.parametrize("participants", [0, 1])
def test_reading_the_list_fills_in_the_participants_of_a_half_made_match(participants):
    """매칭 행만 들어가고 참가자 쓰기가 끊긴 반쪽 — 매칭이 있다고 건너뛰면 방이 영영 안 열린다. 참가자를 채운다.
    매칭은 새로 생긴 것이 아니라 알림 · 실시간 신호는 없다. 다 채워진 뒤에는 다시 읽어도 아무것도 쓰지 않는다."""
    world = _Unfinished(participants=participants)

    response = world.read_list()

    assert response.status_code == 200
    assert response.json() == {"acceptances": []}   # 이미 매칭된 상대는 반쪽이어도 목록에 없다
    assert world.participants() == sorted([PROFILE_ID, OTHER_ID])
    assert len(world.matches) == 1
    assert (world.pushes, world.broadcasts) == ([], [])

    world.writes.clear()
    world.read_list()

    assert (world.writes, world.pushes) == ([], [])


@pytest.mark.parametrize("participants", [0, 1])
def test_a_half_made_match_still_hides_an_unanswered_card_of_the_same_person(participants):
    """목록의 "이미 매칭된 상대는 숨김" 은 참가자가 모자란 매칭에도 그대로다."""
    world = _Unfinished(mine=None, participants=participants)

    assert world.read_list().json() == {"acceptances": []}
    assert world.writes == []


@pytest.mark.parametrize("participants", [0, 1])
def test_accepting_again_fills_in_the_participants_of_a_half_made_match(participants):
    """다시 수락(POST)도 같은 반쪽을 채운다 — create_match 가 참가자를 merge 로 다시 넣는다. 알림은 없다."""
    world = _Unfinished(participants=participants)

    response = _wire(world.handle).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                        json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert world.participants() == sorted([PROFILE_ID, OTHER_ID])
    assert (world.pushes, world.broadcasts) == ([], [])


def test_a_rejected_card_adds_no_database_round_trip():
    assert _list_reads(_Unfinished(mine="reject")) == [
        "/rest/v1/blocks", "/rest/v1/card_decisions", "/rest/v1/matches"]


def test_acceptance_older_than_seven_days_is_gone():
    """받은 수락함은 7일이 지나면 목록에서 사라진다(2026-09-21 확정). 응답도 받지 않는다(410)."""
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24 * 8))])
        return httpx.Response(200, json=[])

    handler, pushes, posted = _pushes_and_matches(extra)
    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 410
    assert (posted, pushes) == ([], [])


def _answered_card(mine: str, decided_at: str | None = None) -> Callable[[httpx.Request], httpx.Response]:
    """내가 이미 mine(accept · reject)으로 답한 카드를 돌려주는 가짜. PostgREST 처럼 select 에 적힌 칸만 준다 —
    저장소가 decision 을 읽지 않으면 다시 수락이 409 로 돌아가 아래 시험이 잡는다."""
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            asked = "acceptance_responses(responder_id,decision)" in request.url.params["select"]
            return httpx.Response(200, json=[_accepted_card(
                decided_at or _hours_ago(24),
                acceptance_responses={"responder_id": PROFILE_ID, **({"decision": mine} if asked else {})},
            )])
        return httpx.Response(200, json=[])

    return extra


@pytest.mark.parametrize(("mine", "again"), [("reject", "reject"), ("reject", "accept"), ("accept", "reject")])
def test_responding_twice_is_conflict_and_writes_nothing(mine, again):
    """이미 거절했거나, 답을 바꾸려는 두 번째 응답은 409 다 — 응답 · 매칭 · 푸시 어느 것도 생기지 않는다."""
    handler, pushes, posted = _pushes_and_matches(_answered_card(mine))

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": again})

    assert response.status_code == 409
    assert posted == []
    assert pushes == []


def test_accepting_again_after_the_match_write_was_cut_off_makes_the_room():
    """수락 응답은 저장됐는데 매칭 만들기가 끊긴 사람(방이 영영 안 생기던 경우)이 다시 수락을 누르면,
    응답은 다시 쓰지 않고 매칭만 만들어 처음과 같은 답을 받는다. 새로 생긴 매칭이라 알림도 처음처럼 간다."""
    broadcasts: list[dict] = []
    handler, pushes, posted = _pushes_and_matches(_answered_card("accept"), broadcasts)

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 200
    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert not any("/rest/v1/acceptance_responses" in url for url in posted)
    assert sum("/rest/v1/matches" in url for url in posted) == 1
    assert sum("/rest/v1/match_participants" in url for url in posted) == 1
    assert len(pushes) == 2
    assert [b["event"] for b in broadcasts] == ["room_changed", "room_changed"]


def test_accepting_again_when_the_match_already_exists_is_quiet():
    """매칭까지 다 된 사람이 또 눌러도(앱 재시도) 같은 답만 돌아온다 — 알림 · 실시간 신호는 다시 가지 않는다."""
    broadcasts: list[dict] = []
    handler, pushes, posted = _pushes_and_matches(_answered_card("accept"), broadcasts)

    def existing(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/matches" in str(request.url):
            return httpx.Response(201, json=[]) if request.method == "POST" else httpx.Response(200, json=[{"id": "match-1"}])
        return handler(request)

    response = _wire(existing).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                    json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert pushes == []
    assert broadcasts == []


def test_accepting_again_is_rescued_even_after_the_seven_days():
    """구제가 목적이라 이미 수락한 사람의 다시 누르기에는 7일 만료(410)를 적용하지 않는다."""
    handler, _, _ = _pushes_and_matches(_answered_card("accept", decided_at=_hours_ago(24 * 8)))

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}


def test_responding_to_someone_elses_acceptance_is_404():
    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24), target_id="nobody")])
        return httpx.Response(200, json=[])

    handler, pushes, posted = _pushes_and_matches(extra)
    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 404
    assert (posted, pushes) == ([], [])


def test_accepting_reads_the_accepters_profile_only_once():
    """숨김 검사(조각 6)에서 읽은 상대 프로필을 매칭 알림 문구에도 그대로 쓴다 — 같은 행을 두 번 읽지 않는다."""
    card_profile_reads: list[str] = []

    def extra(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        return httpx.Response(200, json=[])

    handler, pushes, _ = _pushes_and_matches(extra)

    def counting(request: httpx.Request) -> httpx.Response:
        params = request.url.params
        if request.url.path == "/rest/v1/profiles" and "nickname" in params.get("select", ""):
            card_profile_reads.append(params["id"])
        return handler(request)

    response = _wire(counting).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                    json={"decision": "accept"})

    assert response.json() == {"matched": True, "match_id": "match-1"}
    assert len(pushes) == 2
    assert card_profile_reads.count(f"eq.{OTHER_ID}") == 1


def test_a_night_match_is_kept_only_for_the_other_side():
    """밤에 내가 눌러 생긴 매칭은 나에게 보류하지 않는다 — 방금 화면에서 본 것을 아침에 또 받으면 이상하다
    (대장 10-03 ④ 나). 상대 쪽 "매칭됐어요!" 는 결정 4 대로 아침에 간다."""
    import json

    from app.core.deps import get_now
    from app.core.time import SEOUL

    app.dependency_overrides[get_now] = lambda: datetime(2026, 10, 3, 23, 0, tzinfo=SEOUL)
    kept: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/pending_pushes" in url:
            kept.append(json.loads(request.content)["profile_id"])
            return httpx.Response(201)
        if "/rest/v1/notification_settings" in url:
            return httpx.Response(200, json=[{"match_made": True, "quiet_hours": True}])
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[_accepted_card(_hours_ago(24))])
        if "/rest/v1/matches" in url and request.method == "POST":
            return httpx.Response(201, json=[{"id": "match-1"}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[ACCEPTER_PROFILE])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/acceptances/card-1", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})

    assert response.status_code == 200
    assert kept == [OTHER_ID]
