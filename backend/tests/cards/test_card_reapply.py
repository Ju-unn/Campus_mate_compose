"""거절한 카드 다시 신청(1.0.7 할 일 #20) — `POST /cards/{card_id}/reapply` · `GET /cards/rejected` · 카드 상세의 7일.

규칙(app/cards/reapply.py 한 곳): 내 카드 · 내 결정이 거절 · 거절 시각부터 7일(서버 시계) 안 · 상대가 숨김(차단 · 지인 차단 ·
정지 · 탈퇴 · 가림 · 이미 매칭)이 아님. 카드 expires_at 은 보지 않고 하트도 쓰지 않는다. 카드 한 장에 한 번만(2026-11-24 사용자
확정) — 다시 신청하면 결정이 accept 가 되어 거절 조건에 다시 걸리지 않는다. 상대에게는 처음 수락과 똑같이 보인다(거절 흔적 0).
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
# 상대 쪽으로 로그인해 볼 사람 — 로그인 관문이 UUID 를 본다.
PARTNER = "22222222-2222-2222-2222-222222222222"
OTHER_PARTNER = "33333333-3333-3333-3333-333333333333"
AUTH = {"Authorization": "Bearer valid-token"}
NOW = datetime(2026, 11, 24, 12, 0, tzinfo=SEOUL)
SUPABASE_URL = "https://x.supabase.co"
# 숨김 상대 — 다시 신청 · 거절 목록 모두에서 같은 이유 없는 404 · 빠짐이 돼야 한다.
HIDDEN = {
    "i-blocked": {},
    "blocked-me": {},
    "i-contact-blocked": {},
    "contact-blocked-me": {},
    "suspended": {"status": "suspended"},
    "withdrawn": {"status": "withdrawn"},
    "auto-hidden": {"auto_hidden_at": "2026-11-20T10:00:00+09:00"},
    "matched": {},
}
BLOCKS = [{"blocker_id": ME, "blocked_id": "i-blocked"}, {"blocker_id": "blocked-me", "blocked_id": ME}]
# 번호 HMAC(PostgREST 가 bytea 를 돌려주는 모양). 지인 차단은 번호 · 키 버전이 같아야 걸린다(cards 숨김 시험과 같은 규칙).
PHONES = {ME: "\\x6d65", "i-contact-blocked": "\\x6963", "contact-blocked-me": "\\x6362"}
CONTACT_BLOCKS = [(ME, PHONES["i-contact-blocked"], 1), ("contact-blocked-me", PHONES[ME], 1)]
# 10b 카드 상세 · 받은 신청 상세와 같은 키.
DETAIL_KEYS = {
    "card_id", "profile", "survey", "animal_type", "impression_type", "religion", "is_smoker",
    "interests", "my_traits", "ideal_traits", "height_cm", "mbti", "student_number", "bio", "ideal_note",
}


def _iso(ago: timedelta) -> str:
    """DB 가 돌려주는 모양(UTC)."""
    return (NOW - ago).astimezone(timezone.utc).isoformat()


def _in(value: str) -> list[str]:
    return value.removeprefix("in.(").removesuffix(")").split(",")


def _eq(params: httpx.QueryParams, key: str, value: str) -> bool:
    """eq. · in. 필터만 흉내 낸다. 필터가 없는 칸은 통과."""
    condition = params.get(key)
    if condition is None:
        return True
    return value == condition.removeprefix("eq.") if condition.startswith("eq.") else value in _in(condition)


def _time_filter(condition: str, value: str) -> bool:
    op, _, at = condition.partition(".")
    left, right = datetime.fromisoformat(value), datetime.fromisoformat(at)
    return {"gt": left > right, "gte": left >= right}[op]


def _embed(select: str, name: str) -> list[str] | None:
    """select 안 `name(a,b)` 의 칸 이름. 고르지 않았으면 None(PostgREST 처럼 붙지 않는다)."""
    start = select.find(f"{name}(")
    if start < 0:
        return None
    return select[start + len(name) + 1:select.index(")", start)].split(",")


def _top_level(select: str) -> list[str]:
    """select 를 괄호 밖 쉼표로만 나눈다 — `a,b(c,d)` → [a, b(c,d)]."""
    fields, depth, start = [], 0, 0
    for i, ch in enumerate(select):
        depth += {"(": 1, ")": -1}.get(ch, 0)
        if ch == "," and depth == 0:
            fields.append(select[start:i])
            start = i + 1
    return [*fields, select[start:]]


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _World:
    """PostgREST 가짜. 필터는 **키**로 본다(테스트 목 함정 ①). 결정 행은 상태로 들고 있어 PATCH 가 실제로 바꾼다."""

    def __init__(self) -> None:
        self.caller = ME
        self.cards: dict[str, dict] = {}
        self.decisions: dict[str, dict] = {}
        # 받은 신청에 대한 받는 사람(카드 target)의 응답 — card_id → {responder_id, decision, decided_at, rejected_at}.
        self.responses: dict[str, dict] = {}
        self.match_writes: list[dict] = []
        self.participant_writes: list[list] = []
        # True 면 다음 매칭 쓰기 한 번이 500 으로 끊긴다(응답만 저장되고 매칭이 안 생긴 경우).
        self.fail_match_once = False
        self.offers: list[dict] = []
        self.matches: list[tuple[str, str]] = []
        self.profiles: dict[str, dict] = {}
        self.pushes: list[dict] = []
        self.seen: list[httpx.Request] = []
        # True 면 PATCH 를 풀기 직전에 다른 요청이 먼저 다시 신청을 끝낸다(동시 요청 · 연타 흉내).
        self.race = False
        self.profile(ME)

    # 준비 ------------------------------------------------------------------
    def profile(self, profile_id: str, **fields) -> None:
        self.profiles[profile_id] = {
            "id": profile_id, "nickname": f"닉-{profile_id[:4]}", "birth_year": 2003, "major": "컴퓨터공학과",
            "status": "active", "auto_hidden_at": None, "universities": {"name": "테스트대학교"},
            "profile_avatars": [], **HIDDEN.get(profile_id, {}), **fields,
        }

    def card(self, card_id: str, target: str, *, owner: str = ME, source: str = "daily",
             expires_at: str | None = None, decision: str | None = None, ago: timedelta | None = None) -> None:
        """owner 가 받은 target 카드. decision 을 주면 ago 전에 그 결정을 남겼다."""
        for who in (owner, target):
            if who not in self.profiles:
                self.profile(who)
        self.cards[card_id] = {
            "id": card_id, "owner_id": owner, "target_id": target, "source": source,
            "issued_at": _iso(timedelta(days=10)),
            "expires_at": expires_at if expires_at is not None else (NOW + timedelta(days=1)).isoformat(),
        }
        if decision:
            self.decisions[card_id] = {"decision": decision, "decided_at": _iso(ago or timedelta(hours=1)),
                                       "rejected_at": None}

    def request(self, card_id: str, owner: str, ago: timedelta, *, answer: str | None = None,
                answered: timedelta | None = None, target: str = ME) -> None:
        """owner 가 target(기본 나)에게 ago 전에 대화를 신청했다. answer 를 주면 target 이 answered 전에 그렇게 답했다."""
        self.card(card_id, target, owner=owner, decision="accept", ago=ago)
        if answer:
            self.responses[card_id] = {"responder_id": target, "decision": answer,
                                       "decided_at": _iso(answered or timedelta(hours=1)), "rejected_at": None}

    # 응답 ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.seen.append(request)
        path, params = request.url.path, request.url.params
        if request.url.host == "fcm.googleapis.com":
            self.pushes.append(json.loads(request.content)["message"])
            return httpx.Response(200, json={"name": "sent"})
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": self.caller})
        table = path.removeprefix("/rest/v1/")
        select = params.get("select", "")
        if table == "card_decisions" and request.method == "PATCH":
            return self._patch_decision(params, json.loads(request.content))
        if table == "acceptance_responses" and request.method == "PATCH":
            return self._patch_response(params, json.loads(request.content))
        if table == "acceptance_responses" and request.method == "POST":
            body = json.loads(request.content)
            self.responses[body["card_id"]] = {"responder_id": body["responder_id"], "decision": body["decision"],
                                               "decided_at": NOW.astimezone(timezone.utc).isoformat(),
                                               "rejected_at": None}
            return httpx.Response(201, content=b"")
        if table == "matches" and request.method == "POST":
            return self._insert_match(json.loads(request.content))
        if table == "match_participants" and request.method == "POST":
            self.participant_writes.append(json.loads(request.content))
            return httpx.Response(201, content=b"")
        if table == "card_decisions" and request.method == "POST":
            body = json.loads(request.content)
            if body["card_id"] in self.decisions:
                return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
            self.decisions[body["card_id"]] = {"decision": body["decision"],
                                               "decided_at": NOW.astimezone(timezone.utc).isoformat(),
                                               "rejected_at": None}
            return httpx.Response(201, content=b"")
        if request.method != "GET":
            return httpx.Response(201, content=b"")
        if table == "profiles":
            if "student_verification" in select:
                return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                                  "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
            ids = _in(params["id"]) if params["id"].startswith("in.") else [params["id"].removeprefix("eq.")]
            return httpx.Response(200, json=[self.profiles[i] for i in ids if i in self.profiles])
        if table == "daily_cards":
            return httpx.Response(200, json=[self._card_row(c, select) for c in self.cards.values()
                                             if _eq(params, "id", c["id"])])
        if table == "card_decisions":
            return httpx.Response(200, json=self._decision_rows(params, select))
        if table == "acceptance_responses":
            return httpx.Response(200, json=self._response_rows(params, select))
        if table == "paid_card_offers":
            return httpx.Response(200, json=[o for o in self.offers if _eq(params, "id", o["id"])])
        if table == "matches":
            if "profile_a" in params:  # create_match 의 되읽기
                pair = [params["profile_a"].removeprefix("eq."), params["profile_b"].removeprefix("eq.")]
                return httpx.Response(200, json=[self._match_row(a, b) for a, b in self.matches
                                                 if sorted([a, b]) == pair])
            return httpx.Response(200, json=[self._match_row(a, b) for a, b in self.matches if self.caller in (a, b)])
        if table == "blocks":
            return httpx.Response(200, json=[b for b in BLOCKS if self.caller in b.values()])
        if table == "profile_private":
            return httpx.Response(200, json=[
                {"profile_id": i, "phone_hmac": PHONES.get(i), "phone_hmac_key_version": 1}
                for i in _in(params["profile_id"])
            ])
        if table == "contact_blocks":
            return httpx.Response(200, json=[
                {"owner_id": owner, "contact_hmac": phone, "key_version": version}
                for owner, phone, version in CONTACT_BLOCKS
                if _eq(params, "owner_id", owner) and _eq(params, "contact_hmac", phone)
                and _eq(params, "key_version", str(version))
            ])
        if table == "push_tokens":
            return httpx.Response(200, json=[{"token": "tok", "platform": "android"}])
        return httpx.Response(200, json=[])

    def _card_row(self, card: dict, select: str) -> dict:
        decision = self.decisions.get(card["id"])
        cols = _embed(select, "card_decisions")
        row = dict(card)
        if cols is not None:
            row["card_decisions"] = {k: decision[k] for k in cols} if decision else None
        response_cols = _embed(select, "acceptance_responses")
        if response_cols is not None:
            response = self.responses.get(card["id"])
            row["acceptance_responses"] = {k: response[k] for k in response_cols} if response else None
        return row

    def _answer(self, card_id: str) -> dict | None:
        response = self.responses.get(card_id)
        if response is None:
            return None
        return {"card_id": card_id, "decision": response["decision"], "decided_at": response["decided_at"]}

    def _joined(self) -> list[dict]:
        return [{"card_id": card_id, **decision,
                 "daily_cards": {**self.cards[card_id], "acceptance_responses": self._answer(card_id)}}
                for card_id, decision in self.decisions.items()]

    def _response_rows(self, params: httpx.QueryParams, select: str) -> list[dict]:
        rows = [{"card_id": card_id, **response,
                 "daily_cards": {**self.cards[card_id], "card_decisions": {
                     "decision": self.decisions[card_id]["decision"],
                     "decided_at": self.decisions[card_id]["decided_at"]}}}
                for card_id, response in self.responses.items()]
        for key in ("decision", "responder_id"):
            if key in params:
                rows = [r for r in rows if r[key] == params[key].removeprefix("eq.")]
        if "decided_at" in params:
            rows = [r for r in rows if _time_filter(params["decided_at"], r["decided_at"])]
        if params.get("order") == "decided_at.desc":
            rows.sort(key=lambda r: r["decided_at"], reverse=True)
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        top = [field for field in _top_level(select) if "(" not in field]
        return [{**{k: r[k] for k in top}, "daily_cards": r["daily_cards"]} for r in rows]

    def _patch_response(self, params: httpx.QueryParams, body: dict) -> httpx.Response:
        card_id = params["card_id"].removeprefix("eq.")
        if self.race:
            # 다른 요청이 먼저 되돌리기를 끝냈다.
            self.responses[card_id].update(decision="accept", decided_at=NOW.astimezone(timezone.utc).isoformat())
        response = self.responses.get(card_id)
        hit = response is not None \
            and response["responder_id"] == params["responder_id"].removeprefix("eq.") \
            and response["decision"] == params["decision"].removeprefix("eq.") \
            and _time_filter(params["decided_at"], response["decided_at"])
        if not hit:
            return httpx.Response(200, json=[])
        response.update(body)
        return httpx.Response(200, json=[{"card_id": card_id}])

    def _insert_match(self, body: dict) -> httpx.Response:
        if self.fail_match_once:
            self.fail_match_once = False
            return httpx.Response(500, json={"message": "끊김"})
        self.match_writes.append(body)
        pair = (body["profile_a"], body["profile_b"])
        if any(sorted([a, b]) == list(pair) for a, b in self.matches):
            return httpx.Response(201, json=[])
        self.matches.append(pair)
        return httpx.Response(201, json=[self._match_row(*pair)])

    def _decision_rows(self, params: httpx.QueryParams, select: str) -> list[dict]:
        rows = self._joined()
        if "decision" in params:
            rows = [r for r in rows if r["decision"] == params["decision"].removeprefix("eq.")]
        # `daily_cards!inner(...)` 일 때만 임베드 필터가 위 행을 거른다(PostgREST 와 같다).
        for key in ("owner_id", "target_id"):
            if "daily_cards!inner(" in select and f"daily_cards.{key}" in params:
                rows = [r for r in rows if r["daily_cards"][key] == params[f"daily_cards.{key}"].removeprefix("eq.")]
        if "decided_at" in params:
            rows = [r for r in rows if _time_filter(params["decided_at"], r["decided_at"])]
        if params.get("order") == "decided_at.desc":
            rows.sort(key=lambda r: r["decided_at"], reverse=True)
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        top = [field for field in _top_level(select) if "(" not in field]
        return [{**{k: r[k] for k in top}, "daily_cards": r["daily_cards"]} for r in rows]

    def _patch_decision(self, params: httpx.QueryParams, body: dict) -> httpx.Response:
        card_id = params["card_id"].removeprefix("eq.")
        if self.race:
            # 다른 요청이 먼저 다시 신청을 끝냈다.
            self.decisions[card_id].update(decision="accept", decided_at=NOW.astimezone(timezone.utc).isoformat())
        decision = self.decisions.get(card_id)
        hit = decision is not None and decision["decision"] == params["decision"].removeprefix("eq.") \
            and _time_filter(params["decided_at"], decision["decided_at"])
        if not hit:
            return httpx.Response(200, json=[])
        decision.update(body)
        return httpx.Response(200, json=[{"card_id": card_id}])

    def _match_row(self, a: str, b: str) -> dict:
        first, second = sorted([a, b])
        return {"id": f"match-{first[:8]}-{second[:8]}", "profile_a": first, "profile_b": second,
                "created_at": _iso(timedelta(days=1)),
                "match_participants": [{"profile_id": a, "left_at": None}, {"profile_id": b, "left_at": None}]}

    def requests(self, table: str, method: str = "GET") -> list[httpx.Request]:
        return [r for r in self.seen if r.url.path == f"/rest/v1/{table}" and r.method == method]

    def broadcasts(self) -> list[dict]:
        return [json.loads(r.content) for r in self.seen if r.url.path == "/realtime/v1/api/broadcast"]


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


def _reapply(card_id: str) -> httpx.Response:
    return TestClient(app).post(f"/cards/{card_id}/reapply", headers=AUTH)


def _rejected() -> list[dict]:
    response = TestClient(app).get("/cards/rejected", headers=AUTH)
    assert response.status_code == 200, response.text
    return response.json()["rejected"]


# 다시 신청 — 되는 길 --------------------------------------------------------------------------------

def test_reapply_within_seven_days_turns_the_rejection_into_a_request(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=3))
    rejected_at = world.decisions["card-1"]["decided_at"]

    response = _reapply("card-1")

    assert response.status_code == 200, response.text
    assert response.json() == {"ok": True}
    # 신청 시각은 서버 시계, 원래 거절 시각은 rejected_at 에 남는다(관리자 통계용).
    assert world.decisions["card-1"] == {
        "decision": "accept", "decided_at": NOW.astimezone(timezone.utc).isoformat(), "rejected_at": rejected_at,
    }


def test_reapply_patches_only_a_row_still_rejected_inside_the_window(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=3))

    _reapply("card-1")

    [patch] = world.requests("card_decisions", "PATCH")
    assert patch.url.params["card_id"] == "eq.card-1"
    assert patch.url.params["decision"] == "eq.reject"
    cutoff = (NOW - timedelta(days=7)).astimezone(timezone.utc)
    assert patch.url.params["decided_at"] == f"gt.{cutoff.isoformat()}"
    assert patch.headers["Prefer"] == "return=representation"


def test_reapply_notifies_exactly_like_a_first_accept(world):
    """상대가 받는 알림은 처음 수락(decide_card accept)과 제목 · 본문 · data 가 같다 — 다시 신청인지 알 수 없다."""
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=3))
    world.card("card-2", "t2")

    assert _reapply("card-1").status_code == 200
    assert TestClient(app).post("/cards/card-2/decision", headers=AUTH, json={"decision": "accept"}).status_code == 200

    reapplied, first = world.pushes
    assert reapplied["notification"] == first["notification"] == {
        "title": "대화 신청이 왔어요", "body": f"{world.profiles[ME]['nickname']} 님이 대화를 신청했어요"}
    assert reapplied["data"] == {**first["data"], "card_id": "card-1"}
    assert first["data"] == {"route": "acceptances", "card_id": "card-2"}
    # 알림함 줄도 같은 모양이다.
    inbox = [json.loads(r.content) for r in world.requests("notifications", "POST")]
    assert [{k: v for k, v in row.items() if k != "data"} for row in inbox] == [
        {"profile_id": "t1", "kind": inbox[0]["kind"], "title": "대화 신청이 왔어요", "body": inbox[0]["body"]},
        {"profile_id": "t2", "kind": inbox[0]["kind"], "title": "대화 신청이 왔어요", "body": inbox[0]["body"]},
    ]
    assert inbox[0]["data"] == {"route": "acceptances", "card_id": "card-1"}


def test_reapply_ignores_the_card_expiry(world):
    """카드 expires_at 이 지나도(다음 지급) 거절 7일 안이면 된다 — 기한은 거절 시각만 본다."""
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=5),
               expires_at=(NOW - timedelta(days=2)).isoformat())

    assert _reapply("card-1").status_code == 200


def test_reapply_on_a_bought_card_spends_no_hearts(world):
    world.card("card-1", "t1", source="purchased", expires_at="", decision="reject", ago=timedelta(days=1))
    world.cards["card-1"]["expires_at"] = None

    assert _reapply("card-1").status_code == 200
    touched = {r.url.path for r in world.seen}
    assert not [p for p in touched if "heart" in p or "purchase" in p or "/rpc/" in p], touched


# 다시 신청 — 막히는 길 ------------------------------------------------------------------------------

def _refused(world: _World, response: httpx.Response, status: int, detail: str) -> None:
    assert response.status_code == status, response.text
    assert response.json() == {"detail": detail}
    assert world.requests("card_decisions", "PATCH") == []
    assert world.pushes == []


def test_reapply_on_someone_elses_card_is_404(world):
    world.card("card-1", "t1", owner=SOMEONE, decision="reject", ago=timedelta(days=1))

    _refused(world, _reapply("card-1"), 404, "카드를 찾을 수 없어요")


@pytest.mark.parametrize("card_id", ["no-such-card", "offer-1"])
def test_reapply_on_an_unknown_card_or_an_unbought_offer_is_404(world, card_id):
    """사지 않은 유료 제안 id 는 daily_cards 행이 없다 — 무료로 사는 구멍이 되면 안 된다."""
    world.offers.append({"id": "offer-1", "owner_id": ME, "target_id": "t1", "status": "offered"})

    _refused(world, _reapply(card_id), 404, "카드를 찾을 수 없어요")


def test_reapply_before_deciding_is_404(world):
    world.card("card-1", "t1")

    _refused(world, _reapply("card-1"), 404, "카드를 찾을 수 없어요")


def test_reapply_on_an_accepted_card_is_409(world):
    world.card("card-1", "t1", decision="accept", ago=timedelta(days=1))

    _refused(world, _reapply("card-1"), 409, "이미 결정한 카드예요")


@pytest.mark.parametrize("ago", [timedelta(days=7), timedelta(days=8)])
def test_reapply_seven_days_after_the_rejection_is_404(world, ago):
    world.card("card-1", "t1", decision="reject", ago=ago)

    _refused(world, _reapply("card-1"), 404, "카드를 찾을 수 없어요")


@pytest.mark.parametrize("partner", list(HIDDEN))
def test_reapply_to_a_hidden_partner_is_404(world, partner):
    world.card("card-1", partner, decision="reject", ago=timedelta(days=1))
    world.matches.append((ME, "matched"))

    _refused(world, _reapply("card-1"), 404, "카드를 찾을 수 없어요")


def test_blocked_withdrawn_and_late_answers_cannot_be_told_apart(world):
    """"상대가 나를 차단함" 을 응답으로 가를 수 없어야 한다 — 탈퇴 · 기한 지남과 상태 · 본문이 완전히 같다."""
    world.card("card-b", "blocked-me", decision="reject", ago=timedelta(days=1))
    world.card("card-w", "withdrawn", decision="reject", ago=timedelta(days=1))
    world.card("card-l", "t1", decision="reject", ago=timedelta(days=8))

    answers = [_reapply(card) for card in ("card-b", "card-w", "card-l")]

    assert {(a.status_code, a.content) for a in answers} == {(404, answers[0].content)}


def test_a_second_reapply_is_409_without_a_second_push(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=1))

    assert _reapply("card-1").status_code == 200
    again = _reapply("card-1")

    assert again.status_code == 409
    assert again.json() == {"detail": "이미 결정한 카드예요"}
    assert len(world.pushes) == 1


def test_a_concurrent_reapply_that_loses_the_patch_is_409_without_a_push(world):
    """두 요청이 둘 다 거절 상태를 읽고 PATCH 로 가면, 조건부 PATCH 가 0행인 쪽은 409 이고 알림을 보내지 않는다."""
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=1))
    world.race = True

    response = _reapply("card-1")

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 결정한 카드예요"}
    assert world.pushes == []
    assert world.requests("notifications", "POST") == []


def test_the_old_decision_path_on_a_rejected_card_stays_409(world):
    """옛 앱(1.0.6) 길은 그대로 — 거절한 카드에 다시 결정을 보내면 409 CARD_ALREADY_DECIDED."""
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=1))

    response = TestClient(app).post("/cards/card-1/decision", headers=AUTH, json={"decision": "accept"})

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 결정한 카드예요"}
    assert world.decisions["card-1"]["decision"] == "reject"


# 거절 목록 ------------------------------------------------------------------------------------------

def test_rejected_list_has_only_my_rejections_inside_seven_days(world):
    world.card("fresh", "t1", decision="reject", ago=timedelta(days=1))
    world.card("old", "t2", decision="reject", ago=timedelta(days=7, minutes=1))
    world.card("accepted", "t3", decision="accept", ago=timedelta(days=1))
    world.card("undecided", "t4")
    world.card("theirs", "t5", owner=SOMEONE, decision="reject", ago=timedelta(days=1))
    world.card("newer", "t6", decision="reject", ago=timedelta(hours=2))

    assert [item["card_id"] for item in _rejected()] == ["newer", "fresh"]


def test_rejected_list_item_shape(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=2))

    [item] = _rejected()

    assert set(item) == {"card_id", "source", "rejected_at", "expires_at", "days_left", "profile"}
    # 지금은 내 카드 거절뿐이다. 받은 신청 거절은 나중에 다른 source 로 들어온다.
    assert item["source"] == "card"
    assert datetime.fromisoformat(item["rejected_at"]) == NOW - timedelta(days=2)
    assert datetime.fromisoformat(item["expires_at"]) == NOW + timedelta(days=5)
    assert item["profile"]["nickname"] == world.profiles["t1"]["nickname"]
    assert "profile_id" not in item["profile"]


def test_rejected_list_carries_the_partners_academic_status(world):
    """거절 목록(`GET /cards/rejected`)도 같은 `_card_profile` 로 신분을 싣는다(1.0.7 1-1)."""
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=2))
    world.profiles["t1"]["academic_status"] = "graduate_student"

    [item] = _rejected()

    assert item["profile"]["academic_status"] == "graduate_student"


@pytest.mark.parametrize(("ago", "days_left"), [
    (timedelta(hours=1), 7),               # 6일 23시간 남음 → 올려서 7
    (timedelta(days=1), 6),                # 딱 6일 남음
    (timedelta(days=6, hours=23), 1),      # 1시간 남음 → 0 이 아니라 1
])
def test_rejected_list_days_left_is_rounded_up(world, ago, days_left):
    world.card("card-1", "t1", decision="reject", ago=ago)

    [item] = _rejected()

    assert item["days_left"] == days_left


@pytest.mark.parametrize("partner", list(HIDDEN))
def test_rejected_list_drops_hidden_partners(world, partner):
    world.card("hidden", partner, decision="reject", ago=timedelta(days=1))
    world.card("visible", "t1", decision="reject", ago=timedelta(days=2))
    world.matches.append((ME, "matched"))

    assert [item["card_id"] for item in _rejected()] == ["visible"]


def test_rejected_list_drops_a_reapplied_card(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=1))

    assert _reapply("card-1").status_code == 200

    assert _rejected() == []


def test_rejected_list_query_is_mine_rejected_and_bounded(world):
    _rejected()

    [read] = world.requests("card_decisions")
    cutoff = (NOW - timedelta(days=7)).astimezone(timezone.utc)
    assert read.url.params["decision"] == "eq.reject"
    assert read.url.params["decided_at"] == f"gt.{cutoff.isoformat()}"
    assert read.url.params["daily_cards.owner_id"] == f"eq.{ME}"
    assert read.url.params["order"] == "decided_at.desc"
    assert read.url.params["limit"] == "50"


# 다시 신청 뒤 ---------------------------------------------------------------------------------------

def test_a_reapplied_card_waits_in_sent_with_a_fresh_deadline(world):
    world.card("card-1", "t1", decision="reject", ago=timedelta(days=5))

    assert _reapply("card-1").status_code == 200
    response = TestClient(app).get("/cards/sent", headers=AUTH)

    [item] = response.json()["sent"]
    assert item["card_id"] == "card-1"
    assert item["status"] == "waiting"
    assert datetime.fromisoformat(item["sent_at"]) == NOW
    assert datetime.fromisoformat(item["expires_at"]) == NOW + timedelta(days=7)


def test_the_partner_sees_a_reapply_exactly_like_a_first_accept(world):
    """상대 쪽 받은 신청 목록 · 상세의 모양이 평소 수락과 같은 키만이고, 상대 쪽 읽기는 rejected_at 을 고르지도 않는다."""
    world.card("card-1", PARTNER, decision="reject", ago=timedelta(days=3))
    world.card("card-2", OTHER_PARTNER)
    assert _reapply("card-1").status_code == 200
    assert TestClient(app).post("/cards/card-2/decision", headers=AUTH, json={"decision": "accept"}).status_code == 200

    shapes = []
    for partner, card_id in ((PARTNER, "card-1"), (OTHER_PARTNER, "card-2")):
        world.caller = partner
        [item] = TestClient(app).get("/cards/acceptances", headers=AUTH).json()["acceptances"]
        detail = TestClient(app).get(f"/cards/acceptances/{card_id}", headers=AUTH)
        assert detail.status_code == 200, detail.text
        shapes.append((set(item), set(item["profile"]), set(detail.json()), item["expires_at"]))

    reapplied, first = shapes
    assert reapplied[:3] == first[:3]
    assert set(reapplied[2]) == DETAIL_KEYS
    # 다시 신청한 카드의 응답 기한도 신청 시각 + 7일이다(처음 수락과 같은 시각에 보냈다).
    assert reapplied[3] == first[3]
    assert not [r for r in world.seen if r.method == "GET" and "rejected_at" in r.url.params.get("select", "")]


# 카드 상세 ------------------------------------------------------------------------------------------

@pytest.mark.parametrize(("decision", "ago", "status"), [
    ("reject", timedelta(days=8), 404),   # 다시 신청 기한이 지난 거절 카드는 닫힌다
    ("reject", timedelta(days=7), 404),   # 경계 — 다시 신청과 같은 7일
    ("reject", timedelta(days=3), 200),   # 거절 목록에서 여는 읽기 전용 프로필
    (None, None, 200),                    # 결정 전 카드는 그대로
    ("accept", timedelta(days=30), 200),  # 수락한 카드도 그대로
])
def test_card_detail_closes_a_rejection_older_than_seven_days(world, decision, ago, status):
    world.card("card-1", "t1", decision=decision, ago=ago)

    response = TestClient(app).get("/cards/card-1", headers=AUTH)

    assert response.status_code == status, response.text
    if status == 404:
        assert response.json() == {"detail": "카드를 찾을 수 없어요"}
    else:
        assert set(response.json()) == DETAIL_KEYS


# (b) 받은 신청 거절 되돌리기 — 바로 매칭 -------------------------------------------------------------
# 받은 신청(상대가 나에게 보낸 수락)을 내가 거절했다 → 내 거절 시각부터 7일 · 상대 신청의 원래 기한 안이면 되돌려 바로 매칭.

def _undo(card_id: str, client: TestClient | None = None) -> httpx.Response:
    return (client or TestClient(app)).post(f"/cards/acceptances/{card_id}/reapply", headers=AUTH)


def _shape(value, swaps: dict[str, str]) -> str:
    """사람 · 매칭 id 를 자리표시로 바꾼 글 — 두 길의 신호 · 알림 모양만 비교한다."""
    text = json.dumps(value, sort_keys=True, ensure_ascii=False)
    for old, new in swaps.items():
        text = text.replace(old, new)
    return text


def test_undo_within_seven_days_matches_right_away(world):
    world.request("card-1", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))
    rejected_at = world.responses["card-1"]["decided_at"]

    response = _undo("card-1")

    assert response.status_code == 200, response.text
    assert response.json() == {"matched": True, "match_id": world._match_row(PARTNER, ME)["id"]}
    assert world.responses["card-1"] == {
        "responder_id": ME, "decision": "accept", "decided_at": NOW.astimezone(timezone.utc).isoformat(),
        "rejected_at": rejected_at,
    }
    assert [sorted(pair) for pair in world.matches] == [sorted([ME, PARTNER])]


def test_undo_patches_only_my_rejection_still_inside_the_window(world):
    world.request("card-1", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))

    _undo("card-1")

    [patch] = world.requests("acceptance_responses", "PATCH")
    assert patch.url.params["card_id"] == "eq.card-1"
    assert patch.url.params["responder_id"] == f"eq.{ME}"
    assert patch.url.params["decision"] == "eq.reject"
    cutoff = (NOW - timedelta(days=7)).astimezone(timezone.utc)
    assert patch.url.params["decided_at"] == f"gt.{cutoff.isoformat()}"
    assert patch.headers["Prefer"] == "return=representation"


def test_undo_leaves_the_requester_no_trace_of_the_rejection(world):
    """카드 주인 쪽에서 보면 되돌리기로 생긴 매칭이 평소 수락으로 생긴 매칭과 같다 — 매칭 · 참가자 쓰기(대화방 목록 · 방
    응답의 재료), room_changed 신호, match_made 알림(제목 · 본문 · data), 보낸 신청 줄의 키 · 값 모양."""
    world.request("card-a", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))
    world.request("card-b", OTHER_PARTNER, timedelta(days=3))

    undone = _undo("card-a")
    first = TestClient(app).post("/cards/acceptances/card-b", headers=AUTH, json={"decision": "accept"})

    assert undone.status_code == first.status_code == 200
    assert set(undone.json()) == set(first.json()) == {"matched", "match_id"}
    swaps_a = {undone.json()["match_id"]: "<match>", PARTNER: "<owner>", world.profiles[PARTNER]["nickname"]: "<nick>"}
    swaps_b = {first.json()["match_id"]: "<match>", OTHER_PARTNER: "<owner>",
               world.profiles[OTHER_PARTNER]["nickname"]: "<nick>"}
    # 대화방 목록(/chat/conversations) · 방(/chat/matches/{id})은 matches · match_participants 행에서만 나온다.
    write_a, write_b = world.match_writes
    assert _shape(write_a, swaps_a) == _shape(write_b, swaps_b)
    part_a, part_b = world.participant_writes
    assert _shape(part_a, swaps_a) == _shape(part_b, swaps_b)
    signal_a, signal_b = world.broadcasts()
    assert _shape(signal_a, swaps_a) == _shape(signal_b, swaps_b)
    # 알림 — 카드 주인에게 하나, 나에게 하나씩(평소와 같다).
    assert len(world.pushes) == 4
    assert _shape(world.pushes[:2], swaps_a) == _shape(world.pushes[2:], swaps_b)
    inbox = [json.loads(r.content) for r in world.requests("notifications", "POST")]
    assert _shape(inbox[:2], swaps_a) == _shape(inbox[2:], swaps_b)
    # 보낸 신청(카드 주인 쪽) 줄.
    rows = []
    for owner, card_id, swaps in ((PARTNER, "card-a", swaps_a), (OTHER_PARTNER, "card-b", swaps_b)):
        world.caller = owner
        [item] = TestClient(app).get("/cards/sent", headers=AUTH).json()["sent"]
        rows.append(_shape(item, {**swaps, card_id: "<card>"}))
    assert rows[0] == rows[1]
    assert '"status": "matched"' in rows[0]
    assert not [r for r in world.seen if r.method == "GET" and "rejected_at" in r.url.params.get("select", "")]


def test_undo_refusals_cannot_be_told_apart(world):
    """조건 밖은 전부 같은 404 — 상태 코드와 본문까지 같아 차단 · 탈퇴 · 기한 지남을 응답으로 가를 수 없다."""
    for partner in HIDDEN:
        world.request(f"card-{partner}", partner, timedelta(days=2), answer="reject", answered=timedelta(days=1))
    world.matches.append((ME, "matched"))
    world.request("card-late-mine", PARTNER, timedelta(days=8), answer="reject", answered=timedelta(days=7))
    world.request("card-late-theirs", OTHER_PARTNER, timedelta(days=7), answer="reject", answered=timedelta(days=1))
    world.request("card-not-mine", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1),
                  target=SOMEONE)
    world.request("card-unanswered", OTHER_PARTNER, timedelta(days=2))
    world.card("card-owner-rejected", ME, owner=PARTNER, decision="reject", ago=timedelta(days=2))
    world.card("card-owner-undecided", ME, owner=PARTNER)
    cards = [*(f"card-{partner}" for partner in HIDDEN), "card-late-mine", "card-late-theirs", "card-not-mine",
             "card-unanswered", "card-owner-rejected", "card-owner-undecided", "no-such-card"]

    answers = [_undo(card) for card in cards]

    assert {(a.status_code, a.content) for a in answers} == {(404, answers[0].content)}
    assert answers[0].json() == {"detail": "수락을 찾을 수 없어요"}
    assert world.requests("acceptance_responses", "PATCH") == []
    assert (world.match_writes, world.pushes, world.broadcasts()) == ([], [], [])


def test_undo_on_an_accepted_answer_is_409(world):
    world.request("card-1", PARTNER, timedelta(days=2), answer="accept", answered=timedelta(days=1))

    response = _undo("card-1")

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 답한 수락이에요"}
    assert world.requests("acceptance_responses", "PATCH") == []


def test_a_second_undo_after_the_match_is_404_without_a_second_match(world):
    """연달아 두 번째는 이미 매칭된 상대라 숨김 관문에서 404 다(판단 순서: 숨김 · 이미 매칭 → 응답 확인).
    둘이 동시에 관문을 지나는 경우는 조건부 PATCH 가 409 로 막는다(아래 동시 요청 시험)."""
    world.request("card-1", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1))

    assert _undo("card-1").status_code == 200
    again = _undo("card-1")

    assert again.status_code == 404
    assert again.json() == {"detail": "수락을 찾을 수 없어요"}
    assert len(world.match_writes) == 1
    assert len(world.pushes) == 2


def test_a_concurrent_undo_that_loses_the_patch_is_409_without_a_match(world):
    world.request("card-1", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1))
    world.race = True

    response = _undo("card-1")

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 답한 수락이에요"}
    assert (world.match_writes, world.pushes, world.broadcasts()) == ([], [], [])


def test_the_old_answer_path_on_my_rejection_stays_409(world):
    """옛 앱(1.0.6) 길은 그대로 — 거절로 답한 받은 신청에 다시 수락을 보내면 409."""
    world.request("card-1", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1))

    response = TestClient(app).post("/cards/acceptances/card-1", headers=AUTH, json={"decision": "accept"})

    assert response.status_code == 409
    assert response.json() == {"detail": "이미 답한 수락이에요"}
    assert world.responses["card-1"]["decision"] == "reject"
    assert world.match_writes == []


def test_a_match_cut_off_after_undo_is_rebuilt_by_the_acceptance_list(world):
    """되돌리기는 저장됐는데 매칭 쓰기가 끊겼다 — 받은 신청 목록을 읽을 때 accept 응답을 보고 이어 만든다."""
    world.request("card-1", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1))
    world.fail_match_once = True

    cut = _undo("card-1", TestClient(app, raise_server_exceptions=False))
    assert cut.status_code == 500
    assert world.responses["card-1"]["decision"] == "accept"
    assert world.matches == []

    assert TestClient(app).get("/cards/acceptances", headers=AUTH).status_code == 200

    assert [sorted(pair) for pair in world.matches] == [sorted([ME, PARTNER])]


def test_the_requester_sent_row_turns_from_rejected_to_matched(world):
    world.request("card-1", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))

    world.caller = PARTNER
    [before] = TestClient(app).get("/cards/sent", headers=AUTH).json()["sent"]
    world.caller = ME
    assert _undo("card-1").status_code == 200
    world.caller = PARTNER
    [after] = TestClient(app).get("/cards/sent", headers=AUTH).json()["sent"]

    assert before["status"] == "rejected"
    assert after["status"] == "matched"
    assert after["match_id"] == world._match_row(PARTNER, ME)["id"]
    assert set(before) == set(after)


# (b) 거절 목록의 받은 신청 줄 ---------------------------------------------------------------------------

def test_rejected_list_carries_my_rejected_requests(world):
    world.request("card-1", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))

    [item] = _rejected()

    assert set(item) == {"card_id", "source", "rejected_at", "expires_at", "days_left", "profile"}
    assert item["card_id"] == "card-1"
    assert item["source"] == "acceptance"
    assert datetime.fromisoformat(item["rejected_at"]) == NOW - timedelta(days=1)
    # min(내 거절 + 7일, 상대 신청 + 7일) — 여기서는 상대 신청 기한이 먼저 온다.
    assert datetime.fromisoformat(item["expires_at"]) == NOW + timedelta(days=4)
    assert item["days_left"] == 4
    assert item["profile"]["nickname"] == world.profiles[PARTNER]["nickname"]
    assert "profile_id" not in item["profile"]


def test_rejected_list_merges_both_kinds_newest_rejection_first(world):
    world.card("card-new", "t1", decision="reject", ago=timedelta(hours=2))
    world.request("request-mid", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=1))
    world.card("card-old", "t2", decision="reject", ago=timedelta(days=2))

    assert [(item["card_id"], item["source"]) for item in _rejected()] == [
        ("card-new", "card"), ("request-mid", "acceptance"), ("card-old", "card")]


def test_rejected_list_drops_requests_past_their_own_deadline(world):
    world.request("card-1", PARTNER, timedelta(days=7), answer="reject", answered=timedelta(days=1))

    assert _rejected() == []


@pytest.mark.parametrize("partner", list(HIDDEN))
def test_rejected_list_drops_hidden_requesters(world, partner):
    world.request("hidden", partner, timedelta(days=2), answer="reject", answered=timedelta(days=1))
    world.request("visible", PARTNER, timedelta(days=3), answer="reject", answered=timedelta(days=2))
    world.matches.append((ME, "matched"))

    assert [item["card_id"] for item in _rejected()] == ["visible"]


def test_rejected_list_drops_an_undone_request_and_accepted_answers(world):
    world.request("undone", PARTNER, timedelta(days=2), answer="reject", answered=timedelta(days=1))
    world.request("accepted", OTHER_PARTNER, timedelta(days=2), answer="accept", answered=timedelta(days=1))
    assert _undo("undone").status_code == 200

    assert _rejected() == []


def test_rejected_list_request_query_is_mine_rejected_and_bounded(world):
    _rejected()

    [read] = world.requests("acceptance_responses")
    cutoff = (NOW - timedelta(days=7)).astimezone(timezone.utc)
    assert read.url.params["decision"] == "eq.reject"
    assert read.url.params["responder_id"] == f"eq.{ME}"
    assert read.url.params["decided_at"] == f"gt.{cutoff.isoformat()}"
    assert read.url.params["order"] == "decided_at.desc"
    assert read.url.params["limit"] == "50"
    assert "rejected_at" not in read.url.params["select"]


def test_rejected_list_is_capped_at_fifty_across_both_kinds(world):
    for i in range(30):
        world.card(f"card-{i:02}", f"t{i:02}", decision="reject", ago=timedelta(hours=i + 1))
        world.request(f"request-{i:02}", f"o{i:02}", timedelta(days=3), answer="reject",
                      answered=timedelta(hours=i + 1, minutes=30))

    items = _rejected()

    assert len(items) == 50
    stamps = [datetime.fromisoformat(item["rejected_at"]) for item in items]
    assert stamps == sorted(stamps, reverse=True)


# (b) 받은 신청 상세 — 되돌릴 수 있는 거절은 읽기 전용으로 연다 ----------------------------------------------

@pytest.mark.parametrize(("answer", "asked", "answered", "status"), [
    ("reject", timedelta(days=3), timedelta(days=1), 200),   # 되돌릴 수 있는 거절 — 프로필을 본다
    ("reject", timedelta(days=7), timedelta(days=1), 409),   # 상대 신청 기한이 지난 거절 — 예전처럼 "이미 답함"
    ("accept", timedelta(days=3), timedelta(days=1), 409),   # 수락으로 답한 것은 그대로 409
])
def test_acceptance_detail_opens_an_undoable_rejection(world, answer, asked, answered, status):
    world.request("card-1", PARTNER, asked, answer=answer, answered=answered)

    response = TestClient(app).get("/cards/acceptances/card-1", headers=AUTH)

    assert response.status_code == status, response.text
    if status == 200:
        assert set(response.json()) == DETAIL_KEYS
    else:
        assert response.json() == {"detail": "이미 답한 수락이에요"}
