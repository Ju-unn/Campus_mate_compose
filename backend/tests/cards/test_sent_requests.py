"""보낸 신청(`GET /cards/sent`, 2026-10-13 사용자 결정 B) — 내가 수락(= 대화 신청)한 카드의 지금 상태.

상태 4가지: 응답 기다리는 중(waiting) · 매칭됨(matched) · 거절됨(rejected) · 만료됨(expired, 7일 무응답).
끝난 것(거절 · 만료 · 성사)은 끝난 뒤 7일까지만 남는다. 상대가 차단 · 정지 · 탈퇴 · 가림이면 목록에서 빠진다
(카드 · 수락함과 같은 판정 cards/visibility.hidden_from_cards).
"""
import json
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.cards.push import FcmSender
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
SOMEONE = "99999999-9999-9999-9999-999999999999"
AUTH = {"Authorization": "Bearer valid-token"}
NOW = datetime(2026, 10, 13, 12, 0, tzinfo=SEOUL)
SUPABASE_URL = "https://x.supabase.co"
HIDDEN = {
    "i-blocked": {},
    "blocked-me": {},
    "suspended": {"status": "suspended"},
    "withdrawn": {"status": "withdrawn"},
    "auto-hidden": {"auto_hidden_at": "2026-10-10T10:00:00+09:00"},
}
BLOCKS = [{"blocker_id": ME, "blocked_id": "i-blocked"}, {"blocker_id": "blocked-me", "blocked_id": ME}]


def _iso(ago: timedelta) -> str:
    """DB 가 돌려주는 모양(UTC)."""
    return (NOW - ago).astimezone(timezone.utc).isoformat()


def _in(value: str) -> list[str]:
    return value.removeprefix("in.(").removesuffix(")").split(",")


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _World:
    """PostgREST 가짜. 필터는 **키**로 본다(테스트 목 함정 ①) — 이번 경로가 쓰는 것만 흉내 낸다."""

    def __init__(self) -> None:
        self.decisions: list[dict] = []
        self.matches: list[dict] = []
        self.profiles: dict[str, dict] = {}
        self.seen: list[httpx.Request] = []

    # 준비 ------------------------------------------------------------------
    def profile(self, profile_id: str, **fields) -> None:
        self.profiles[profile_id] = {
            "id": profile_id, "nickname": f"닉-{profile_id}", "birth_year": 2003, "major": "컴퓨터공학과",
            "status": "active", "auto_hidden_at": None, "universities": {"name": "테스트대학교"},
            "profile_avatars": [], **HIDDEN.get(profile_id, {}), **fields,
        }

    def sent(self, card_id: str, target: str, ago: timedelta, *, owner: str = ME, decision: str = "accept",
             response: tuple[str, timedelta] | None = None) -> None:
        """owner 가 target 의 카드에 decision 을 남겼다. response = (상대 응답, 몇 전)."""
        if target not in self.profiles:
            self.profile(target)
        self.decisions.append({
            "card_id": card_id, "decision": decision, "decided_at": _iso(ago),
            "daily_cards": {
                "id": card_id, "owner_id": owner, "target_id": target,
                "acceptance_responses": None if response is None else {
                    "decision": response[0], "decided_at": _iso(response[1]),
                },
            },
        })

    def matched(self, other: str, ago: timedelta, match_id: str = "match-1", *, me: str = ME,
                left: str | None = None) -> None:
        """left = 방을 나간 쪽(me · other 중 하나, 없으면 None). 차단도 차단한 쪽의 left_at 이다(safety)."""
        first, second = sorted([me, other])
        self.matches.append({
            "id": match_id, "profile_a": first, "profile_b": second, "created_at": _iso(ago),
            "match_participants": [
                {"profile_id": who, "left_at": _iso(timedelta(hours=1)) if who == left else None}
                for who in (me, other)
            ],
        })

    # 응답 ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.seen.append(request)
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        table = path.removeprefix("/rest/v1/")
        select = params.get("select", "")
        if table == "profiles":
            if "student_verification" in select:
                return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                                  "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
            ids = _in(params["id"]) if params["id"].startswith("in.") else [params["id"].removeprefix("eq.")]
            return httpx.Response(200, json=[self.profiles[i] for i in ids if i in self.profiles])
        if table == "card_decisions":
            return httpx.Response(200, json=self._decisions(params))
        if table == "matches":
            mine = [m for m in self.matches if f"profile_a.eq.{ME}" in params.get("or", "")
                    and ME in (m["profile_a"], m["profile_b"])]
            # 참가자는 select 에 있을 때만 붙는다(PostgREST 와 같다) — 안 고르면 읽는 쪽이 KeyError 로 드러난다.
            embed = "match_participants(" in select
            return httpx.Response(200, json=[
                {k: v for k, v in m.items() if embed or k != "match_participants"} for m in mine
            ])
        if table == "blocks":
            return httpx.Response(200, json=BLOCKS)
        if table == "profile_private":
            return httpx.Response(200, json=[
                {"profile_id": i, "phone_hmac": None, "phone_hmac_key_version": None}
                for i in _in(params["profile_id"])
            ])
        return httpx.Response(200, json=[])

    def _decisions(self, params: httpx.QueryParams) -> list[dict]:
        rows = list(self.decisions)
        if "decision" in params:
            rows = [r for r in rows if r["decision"] == params["decision"].removeprefix("eq.")]
        # `daily_cards!inner(...)` 일 때만 임베드 필터가 위 행을 거른다(PostgREST 와 같다).
        if "daily_cards!inner(" in params.get("select", "") and "daily_cards.owner_id" in params:
            rows = [r for r in rows if r["daily_cards"]["owner_id"] == params["daily_cards.owner_id"].removeprefix("eq.")]
        if "decided_at" in params:
            since = datetime.fromisoformat(params["decided_at"].removeprefix("gte."))
            rows = [r for r in rows if datetime.fromisoformat(r["decided_at"]) >= since]
        if params.get("order") == "decided_at.desc":
            rows.sort(key=lambda r: r["decided_at"], reverse=True)
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        return [{k: v for k, v in r.items() if k != "decision"} for r in rows]

    def reads(self, table: str) -> list[httpx.QueryParams]:
        return [r.url.params for r in self.seen if r.url.path == f"/rest/v1/{table}"]


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
    app.dependency_overrides[get_now] = lambda: NOW
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", http, credentials=_FakeCredentials())
    yield world
    app.dependency_overrides.clear()


def _sent(world: _World) -> list[dict]:
    response = TestClient(app).get("/cards/sent", headers=AUTH)
    assert response.status_code == 200, response.text
    return response.json()["sent"]


# 상태 4가지 ----------------------------------------------------------------------------------------

@pytest.mark.parametrize(("ago", "days_left"), [
    (timedelta(hours=1), 7),               # 6일 23시간 남음 → 올려서 7
    (timedelta(days=1), 6),                # 딱 6일 남음
    (timedelta(days=6, hours=23), 1),      # 1시간 남음 → 0 이 아니라 1(기다리는 중에는 0 일이 없다)
])
def test_waiting_shows_the_deadline_and_days_left(world, ago, days_left):
    world.sent("card-1", "t1", ago)

    [item] = _sent(world)

    assert item["card_id"] == "card-1"
    assert item["status"] == "waiting"
    sent_at = NOW - ago
    assert datetime.fromisoformat(item["sent_at"]) == sent_at
    # 응답 기한은 받은 수락함과 같은 7일이다(ACCEPTANCE_TTL_DAYS).
    assert datetime.fromisoformat(item["expires_at"]) == sent_at + timedelta(days=7)
    assert item["days_left"] == days_left
    assert item["resolved_at"] is None
    assert item["match_id"] is None


def test_matched_carries_the_room_to_open(world):
    """상대가 받은 수락함에서 수락했다 — 대화 탭의 그 방(match_id)으로 갈 수 있다."""
    world.sent("card-1", "t1", timedelta(days=2), response=("accept", timedelta(days=1)))
    world.matched("t1", timedelta(days=1), "match-7")

    [item] = _sent(world)

    assert item["status"] == "matched"
    assert item["match_id"] == "match-7"
    assert datetime.fromisoformat(item["resolved_at"]) == NOW - timedelta(days=1)
    assert item["days_left"] is None


def test_a_match_made_through_their_own_card_also_counts(world):
    """A→B, B→A 를 둘 다 수락하고 내가 B 의 수락에 답해 매칭이 생기면, 내 신청(c1)에는 B 의 응답 행이 없다.
    그래도 매칭이 있으니 matched 다(받은 수락함의 결정 11 과 같은 판단)."""
    world.sent("card-1", "t1", timedelta(days=3))
    world.matched("t1", timedelta(days=2), "match-7")

    [item] = _sent(world)

    assert item["status"] == "matched"
    assert item["match_id"] == "match-7"
    assert datetime.fromisoformat(item["resolved_at"]) == NOW - timedelta(days=2)


def test_an_accept_without_a_match_row_is_still_answered(world):
    """상대가 수락했는데 매칭 쓰기가 끊겨 matches 행이 없다 — '응답 없음'(기다리는 중 · 만료)으로 보이면 거짓이다."""
    world.sent("card-1", "t1", timedelta(days=9), response=("accept", timedelta(days=3)))

    [item] = _sent(world)

    assert item["status"] == "matched"
    assert item["match_id"] is None
    assert datetime.fromisoformat(item["resolved_at"]) == NOW - timedelta(days=3)


def test_rejected_is_shown_with_when(world):
    """거절도 보낸 사람에게 보인다(2026-10-13 사용자 결정 — 설계 §2.2 '거절은 알리지 않는다' 번복)."""
    world.sent("card-1", "t1", timedelta(days=3), response=("reject", timedelta(days=2)))

    [item] = _sent(world)

    assert item["status"] == "rejected"
    assert datetime.fromisoformat(item["resolved_at"]) == NOW - timedelta(days=2)
    assert item["days_left"] is None
    assert item["match_id"] is None


def test_no_answer_for_seven_days_is_expired(world):
    world.sent("card-1", "t1", timedelta(days=8))

    [item] = _sent(world)

    assert item["status"] == "expired"
    # 끝난 시각 = 보낸 때 + 7일(응답 기한).
    assert datetime.fromisoformat(item["resolved_at"]) == NOW - timedelta(days=1)
    assert item["days_left"] is None


def test_the_seventh_day_itself_is_already_expired(world):
    """딱 7일 — 받은 쪽은 이 순간부터 410 으로 답할 수 없다(respond_to_acceptance). 보낸 쪽도 같은 순간에 만료다."""
    world.sent("card-1", "t1", timedelta(days=7))

    [item] = _sent(world)

    assert item["status"] == "expired"


# 보존 기간 -----------------------------------------------------------------------------------------

def _rejected(world, resolved_ago):
    world.sent("card-1", "t1", resolved_ago + timedelta(days=1), response=("reject", resolved_ago))


def _expired(world, resolved_ago):
    world.sent("card-1", "t1", resolved_ago + timedelta(days=7))


def _matched(world, resolved_ago):
    world.sent("card-1", "t1", resolved_ago + timedelta(days=1), response=("accept", resolved_ago))
    world.matched("t1", resolved_ago)


@pytest.mark.parametrize("make", [_rejected, _expired, _matched], ids=["rejected", "expired", "matched"])
@pytest.mark.parametrize(("resolved_ago", "shown"), [
    (timedelta(days=6, hours=23), True),
    (timedelta(days=7), False),
    (timedelta(days=7, minutes=1), False),
])
def test_finished_requests_stay_for_seven_days(world, make, resolved_ago, shown):
    make(world, resolved_ago)

    assert [item["card_id"] for item in _sent(world)] == (["card-1"] if shown else [])


def test_retention_is_a_constant(world, monkeypatch):
    """보존 기간은 상수 한 곳에서 바꾼다(사용자 요청: 바꾸기 쉽게)."""
    monkeypatch.setattr(router_module, "SENT_RETENTION_DAYS", 3)
    _rejected(world, timedelta(days=4))

    assert _sent(world) == []


# 숨김 · 남의 것 ------------------------------------------------------------------------------------

@pytest.mark.parametrize("other", list(HIDDEN))
def test_a_hidden_partner_drops_out(world, other):
    """차단(어느 쪽이든) · 정지 · 탈퇴 · 자동 가림이면 보낸 신청에서도 사라진다 — 카드 · 수락함과 같은 판정."""
    world.sent("card-hidden", other, timedelta(days=1))
    world.sent("card-visible", "visible", timedelta(days=2))

    assert [item["card_id"] for item in _sent(world)] == ["card-visible"]


def _partner_left(world):
    world.sent("card-gone", "t1", timedelta(days=2), response=("accept", timedelta(days=1)))
    world.matched("t1", timedelta(days=1), left="t1")


def _i_left(world):
    world.sent("card-gone", "t1", timedelta(days=2), response=("accept", timedelta(days=1)))
    world.matched("t1", timedelta(days=1), left=ME)


def _matched_then(other):
    def make(world):
        world.sent("card-gone", other, timedelta(days=2), response=("accept", timedelta(days=1)))
        # 차단은 차단한 쪽(상대)의 left_at 도 찍는다(safety → leave_and_announce).
        world.matched(other, timedelta(days=1), left=other if other == "blocked-me" else None)
    return make


@pytest.mark.parametrize("make", [_partner_left, _i_left, _matched_then("blocked-me"), _matched_then("i-blocked"),
                                  _matched_then("suspended"), _matched_then("withdrawn")],
                         ids=["partner-left", "i-left", "blocked-me", "i-blocked", "suspended", "withdrawn"])
def test_a_matched_request_vanishes_the_same_way_whatever_ended_the_room(world, make):
    """매칭 뒤 상대가 나가기만 해도 차단 · 정지 · 탈퇴와 똑같이 사라진다 — 남아 있으면 '나를 차단했다'가 갈려
    차단 사실이 샌다(설계 §7.2, 14c 상대 프로필과 같은 규칙). 내가 나간 방도 사라진다(그 match_id 는 404 다)."""
    make(world)
    world.sent("card-visible", "visible", timedelta(days=3))

    assert [item["card_id"] for item in _sent(world)] == ["card-visible"]


def test_leaving_some_other_room_does_not_touch_requests_without_that_match(world):
    """나가기는 그 매칭의 상대에게만 걸린다 — 매칭이 없는 waiting · rejected · expired 와 남이 나가지 않은 매칭은 그대로다."""
    world.matched("t9", timedelta(days=1), "match-9", left=ME)
    world.sent("card-waiting", "t1", timedelta(days=1))
    world.sent("card-rejected", "t2", timedelta(days=2), response=("reject", timedelta(days=1)))
    world.sent("card-expired", "t3", timedelta(days=8))
    world.sent("card-matched", "t4", timedelta(days=9), response=("accept", timedelta(days=4)))
    world.matched("t4", timedelta(days=4), "match-4")

    items = {item["card_id"]: item for item in _sent(world)}

    assert {card_id: item["status"] for card_id, item in items.items()} == {
        "card-waiting": "waiting", "card-rejected": "rejected", "card-expired": "expired", "card-matched": "matched",
    }
    assert items["card-matched"]["match_id"] == "match-4"


def test_someone_elses_requests_and_my_passes_are_not_mine(world):
    """남이 보낸 신청(나에게 온 것 포함)은 보이지 않는다. 내가 넘긴(reject) 카드는 신청이 아니다."""
    world.sent("card-mine", "t1", timedelta(days=1))
    world.sent("card-theirs", ME, timedelta(days=1), owner=SOMEONE)
    world.sent("card-other", "t2", timedelta(days=1), owner=SOMEONE)
    world.sent("card-passed", "t3", timedelta(days=1), decision="reject")

    assert [item["card_id"] for item in _sent(world)] == ["card-mine"]
    [query] = world.reads("card_decisions")
    assert query["daily_cards.owner_id"] == f"eq.{ME}"
    assert query["decision"] == "eq.accept"


def test_newest_first(world):
    world.sent("card-old", "t1", timedelta(days=3))
    world.sent("card-new", "t2", timedelta(hours=1))
    world.sent("card-mid", "t3", timedelta(days=1))

    assert [item["card_id"] for item in _sent(world)] == ["card-new", "card-mid", "card-old"]


def test_at_most_fifty(world):
    for n in range(51):
        world.sent(f"card-{n}", f"t{n}", timedelta(minutes=n + 1))

    assert len(_sent(world)) == 50


# 경로 · 응답 모양 · 쿼리 수 ------------------------------------------------------------------------

def test_sent_is_not_swallowed_by_the_card_detail_route(world):
    """`GET /cards/{card_id}` 가 먼저 걸리면 card_id='sent' 로 카드를 찾다 404 가 난다."""
    response = TestClient(app).get("/cards/sent", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"sent": []}
    assert not any(params.get("id") == "eq.sent" for params in world.reads("daily_cards"))


def test_no_partner_id_or_raw_avatar_path_in_the_response(world):
    """상대 profile_id 키와 저장소 원본 경로(storage_path · profile_avatars)는 싣지 않는다. 아바타는 그 카드 앞면에서
    이미 보던 공개 주소(_avatar_url) 그대로다 — 신청한 카드는 결제 전 유료 카드(흐린 preview)가 아니라 이미 열어 본 카드다."""
    target = "22222222-2222-2222-2222-222222222222"
    world.profile(target, nickname="여우비", profile_avatars=[
        {"storage_path": f"{target}/old.png", "status": "ready", "created_at": "2026-10-01T00:00:00+00:00"},
        {"storage_path": f"{target}/new.png", "status": "ready", "created_at": "2026-10-02T00:00:00+00:00"},
    ])
    world.sent("card-1", target, timedelta(days=1))

    [item] = _sent(world)

    assert set(item) == {"card_id", "status", "sent_at", "expires_at", "days_left", "resolved_at", "match_id",
                         "profile"}
    assert item["profile"] == {
        "nickname": "여우비", "age": NOW.year - 2003 + 1, "university": "테스트대학교",
        "major": "컴퓨터공학과",
        "avatar_url": f"{SUPABASE_URL}/storage/v1/object/public/avatars/{target}/new.png",
    }
    text = json.dumps(item)
    assert "profile_id" not in text
    assert "storage_path" not in text and "profile_avatars" not in text
    # 상대 id 가 남는 곳은 공개 아바타 주소 안뿐이다(기존 카드 앞면과 같은 노출).
    assert target not in json.dumps({k: v for k, v in item["profile"].items() if k != "avatar_url"})


def test_everything_is_read_once_not_per_request(world):
    """N+1 없음 — 결정 · 프로필 · 매칭 · 차단을 요청마다 한 번씩만 읽는다."""
    world.sent("card-1", "t1", timedelta(days=1))
    world.sent("card-2", "t2", timedelta(days=2), response=("reject", timedelta(days=1)))
    world.sent("card-3", "t3", timedelta(days=3), response=("accept", timedelta(days=2)))
    world.matched("t3", timedelta(days=2))

    assert len(_sent(world)) == 3

    card_profile_reads = [p for p in world.reads("profiles") if "nickname" in p.get("select", "")]
    assert len(card_profile_reads) == 1
    assert sorted(_in(card_profile_reads[0]["id"])) == ["t1", "t2", "t3"]
    assert len(world.reads("card_decisions")) == 1
    assert len(world.reads("matches")) == 1
    assert len(world.reads("blocks")) == 1
    assert len(world.reads("profile_private")) == 1
