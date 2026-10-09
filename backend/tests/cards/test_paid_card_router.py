"""유료 카드(지시문 22 E · F): GET /cards/today 의 paid_card 와 POST /cards/paid/{offer_id}/purchase.

가짜 PostgREST 는 경로와 쿼리 키로만 가른다(URL 문자열 일부로 가르지 않는다). DB 계약:
paid_card_offers 표 · rpc/purchase_paid_card(하트 차감 · 카드 생성 · 제안 처리를 DB 가 한 번에)."""
import json
import random
from datetime import datetime

import httpx
import pytest
from fastapi.testclient import TestClient

import app.cards.router as router_module
from app.cards.push import FcmSender
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
AUTH = {"Authorization": "Bearer valid-token"}
NOW = datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL)          # 월요일 낮 — 이번 주기는 월 07:00 부터
CYCLE = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
LAST_CYCLE = datetime(2026, 9, 17, 7, 0, tzinfo=SEOUL)    # 지난 목요일
REGION_SETTINGS = [{"region_group": "seoul", "issue_weekdays": [1, 4], "issue_time": "07:00:00"}]
REASONS = [{"kind": "tendency", "text": "성향이 비슷해요"}, {"kind": "mbti", "text": "MBTI가 잘 맞아요"}]
PAID_CARD_KEYS = {"state", "offer_id", "band_count", "reasons", "avatar_url", "cost"}


class _FakeCredentials:
    valid = True
    token = "ya29.test"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )


def _profile(profile_id: str, **overrides) -> dict:
    """한 행에 카드 앞면 · 소유자 점수 칸 · 자격 판정 칸을 모두 담는다 — 어떤 select 로 읽어도 같은 사람이다."""
    return {
        "id": profile_id, "nickname": f"닉-{profile_id}", "birth_year": 2003, "major": "가짜학과",
        "status": "active", "auto_hidden_at": None, "matching_paused": False,
        "universities": {"name": "가짜대학교", "region_group": "seoul"},
        "profile_avatars": [{"storage_path": f"{profile_id}/a.png", "status": "ready",
                             "created_at": "2026-09-20T00:00:00+00:00"}],
        "gender": "male", "mbti": "INFP", "preferred_mbti_flags": {}, "height_cm": 170,
        "preferred_height_min": None, "preferred_height_max": None, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "interest_tags": [],
        **overrides,
    }


def _candidate(i: int, pickable: bool = True) -> dict:
    return {"candidate_id": f"c{i:02d}", "trait_score": 1 - i / 100, "tag_score": 0.0, "text_score": 0.0,
            "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165, "preferred_height_min": None,
            "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
            "preferred_age_max": None, "is_smoker": False, "religion": "none",
            "last_active_at": "2026-09-21T00:00:00+00:00", "pickable": pickable}


def _offer(offer_id: str = "offer-1", target_id: str = "c03", cycle: datetime = CYCLE,
           status: str = "offered", **overrides) -> dict:
    return {"id": offer_id, "owner_id": ME, "cycle_started_at": cycle.isoformat(), "target_id": target_id,
            "reasons": REASONS, "band_count": 4, "status": status, "purchased_card_id": None,
            "created_at": cycle.isoformat(), **overrides}


def _card(card_id: str, target_id: str, source: str = "daily") -> dict:
    return {"id": card_id, "owner_id": ME, "target_id": target_id, "source": source,
            "issued_at": "2026-09-21T07:00:00+09:00",
            "expires_at": None if source == "purchased" else "2126-09-24T07:00:00+09:00",
            "card_decisions": None}


def _in(value: str) -> list[str]:
    return value.removeprefix("in.(").removesuffix(")").split(",")


class _World:
    def __init__(self, offers=(), candidates=(), cards=(), profiles=None,
                 purchase=None, purchase_status: int = 200, region_settings=None):
        self.region_settings = REGION_SETTINGS if region_settings is None else region_settings
        self.offers = [dict(o) for o in offers]
        self.candidates = list(candidates)
        self.cards = list(cards)
        self.profiles = profiles or {}
        self.purchase = purchase or {"result": "ok", "card_id": "card-new"}
        self.purchase_status = purchase_status
        self.calls: list[tuple[str, str]] = []
        self.rpc_bodies: list[dict] = []

    def count(self, method: str, table: str) -> int:
        return self.calls.count((method, table))

    def writes(self) -> list[tuple[str, str]]:
        return [call for call in self.calls if call[0] != "GET"]

    def _person(self, profile_id: str) -> dict:
        return self.profiles.get(profile_id) or _profile(profile_id)

    def handle(self, request: httpx.Request) -> httpx.Response:
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        table = path.removeprefix("/rest/v1/")
        self.calls.append((request.method, table))
        if table == "profiles":
            if "student_verification" in params.get("select", ""):
                return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                                  "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
            ids = _in(params["id"]) if params["id"].startswith("in.") else [params["id"].removeprefix("eq.")]
            return httpx.Response(200, json=[self._person(i) for i in ids])
        if table == "region_group_settings":
            return httpx.Response(200, json=self.region_settings)
        if table == "daily_cards" and request.method == "GET":
            return httpx.Response(200, json=self.cards)
        if table == "rpc/match_candidates":
            return httpx.Response(200, json=self.candidates)
        if table == "paid_card_offers":
            return self._offers(request, params)
        if table == "rpc/purchase_paid_card":
            self.rpc_bodies.append(json.loads(request.content))
            return httpx.Response(self.purchase_status, json=self.purchase)
        if request.method != "GET":
            return httpx.Response(201, json=[])
        return httpx.Response(200, json=[])

    def _offers(self, request: httpx.Request, params: httpx.QueryParams) -> httpx.Response:
        if request.method == "POST":
            body = json.loads(request.content)
            row = {**body, "id": f"offer-new-{len(self.offers)}", "status": "offered", "purchased_card_id": None}
            self.offers.append(row)
            return httpx.Response(201, json=[row])
        if request.method == "PATCH":
            for offer in self.offers:
                if offer["id"] == params["id"].removeprefix("eq.") and offer["status"] == params["status"].removeprefix("eq."):
                    offer.update(json.loads(request.content))
            return httpx.Response(204)
        rows = self.offers
        if "id" in params:
            rows = [o for o in rows if o["id"] == params["id"].removeprefix("eq.")]
        if "purchased_card_id" in params:
            rows = [o for o in rows if o["purchased_card_id"] in _in(params["purchased_card_id"])]
        if "owner_id" in params:
            rows = [o for o in rows if o["owner_id"] == params["owner_id"].removeprefix("eq.")]
        if "status" in params:
            rows = [o for o in rows if o["status"] == params["status"].removeprefix("eq.")]
        if "cycle_started_at" in params:
            since = datetime.fromisoformat(params["cycle_started_at"].removeprefix("gte."))
            rows = [o for o in rows if datetime.fromisoformat(o["cycle_started_at"]) >= since]
        return httpx.Response(200, json=rows)


@pytest.fixture
def wire():
    def build(world: _World) -> TestClient:
        http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
        app.dependency_overrides[get_settings] = lambda: _settings()
        app.dependency_overrides[get_client] = lambda: http
        app.dependency_overrides[get_now] = lambda: NOW
        app.dependency_overrides[router_module.get_rng] = lambda: random.Random(0)
        app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
            "campus-mate-test", http, credentials=_FakeCredentials())
        return TestClient(app, raise_server_exceptions=False)

    yield build
    app.dependency_overrides.clear()


# GET /cards/today ----------------------------------------------------------------------------

def test_a_live_offer_is_shown_without_recomputing_the_ranking(wire):
    world = _World(offers=[_offer()], candidates=[_candidate(i) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"] == {
        "state": "offered", "offer_id": "offer-1", "band_count": 4, "reasons": REASONS,
        "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/c03/a.png", "cost": 50,
    }
    assert body["locked_card_available"] is True
    # 제안이 살아 있으면 후보 전체 순위를 다시 매기지 않는다 — 후보 풀이 비지 않았다는 것도 제안으로 안다.
    assert world.count("POST", "rpc/match_candidates") == 0
    assert body["candidate_pool_empty"] is False
    assert world.writes() == []


def test_an_offered_card_carries_no_other_profile_field(wire):
    secret = _profile("c03", nickname="숨은닉네임", major="숨은학과", mbti="ENTJ", birth_year=1999,
                      universities={"name": "숨은대학교", "region_group": "seoul"})
    world = _World(offers=[_offer()], profiles={"c03": secret})

    paid = wire(world).get("/cards/today", headers=AUTH).json()["paid_card"]

    assert set(paid) == PAID_CARD_KEYS
    dumped = json.dumps(paid, ensure_ascii=False)
    for leak in ("숨은닉네임", "숨은학과", "ENTJ", "숨은대학교", "1999", "c03\""):
        assert leak not in dumped


def test_no_offer_yet_makes_one_lazily(wire):
    world = _World(candidates=[_candidate(i) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"]["state"] == "offered"
    assert set(body["paid_card"]) == PAID_CARD_KEYS
    assert body["paid_card"]["cost"] == 50
    assert world.count("POST", "paid_card_offers") == 1
    [made] = world.offers
    assert made["target_id"] in {f"c{i:02d}" for i in range(5)}  # 20명의 20% → 최소 5명 구간
    assert datetime.fromisoformat(made["cycle_started_at"]) == CYCLE
    assert body["paid_card"]["band_count"] == made["band_count"] == 5
    assert body["locked_card_available"] is True


def test_opening_again_in_the_same_cycle_shows_the_same_person(wire):
    world = _World(candidates=[_candidate(i) for i in range(20)])
    client = wire(world)

    first = client.get("/cards/today", headers=AUTH).json()["paid_card"]
    second = client.get("/cards/today", headers=AUTH).json()["paid_card"]

    assert first["offer_id"] == second["offer_id"]
    assert world.count("POST", "paid_card_offers") == 1
    assert world.count("POST", "rpc/match_candidates") == 1


def test_an_empty_band_is_the_empty_state(wire):
    """후보는 있는데 상위 20% 가 모두 이미 본 사람이다 — 구매는 막히고 화면은 비어 있음을 그린다."""
    world = _World(candidates=[_candidate(i, pickable=i >= 5) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"] == {"state": "empty"}
    assert body["locked_card_available"] is False
    assert body["candidate_pool_empty"] is False
    assert world.count("POST", "paid_card_offers") == 0


def test_no_pickable_candidate_is_null_and_the_pool_is_empty(wire):
    """이제 후보에 이미 본 사람도 들어 있다 — pickable 이 하나도 없어야 화면 11b 다."""
    world = _World(candidates=[_candidate(i, pickable=False) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"] is None
    assert body["candidate_pool_empty"] is True
    assert body["locked_card_available"] is False


def test_bought_this_cycle_is_null(wire):
    world = _World(offers=[_offer(status="purchased", purchased_card_id="card-p")],
                   candidates=[_candidate(i) for i in range(20)],
                   cards=[_card("card-p", "c03", source="purchased")])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"] is None
    assert body["locked_card_available"] is False
    assert world.count("POST", "paid_card_offers") == 0


def test_last_cycles_purchase_does_not_block_this_cycle(wire):
    world = _World(offers=[_offer(cycle=LAST_CYCLE, status="purchased", purchased_card_id="card-p")],
                   candidates=[_candidate(i) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"]["state"] == "offered"


def test_a_suspended_target_is_replaced_when_opened(wire):
    world = _World(offers=[_offer(target_id="c03")], candidates=[_candidate(i) for i in range(20)],
                   profiles={"c03": _profile("c03", status="suspended")})

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert [o["status"] for o in world.offers if o["id"] == "offer-1"] == ["replaced"]
    assert body["paid_card"]["state"] == "offered"
    assert body["paid_card"]["offer_id"] != "offer-1"


def test_last_cycles_offer_expires_when_opened(wire):
    world = _World(offers=[_offer(cycle=LAST_CYCLE)], candidates=[_candidate(i) for i in range(20)])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert [o["status"] for o in world.offers if o["id"] == "offer-1"] == ["expired"]
    assert body["paid_card"]["offer_id"] != "offer-1"


def test_a_bought_card_carries_its_reasons_and_a_free_card_does_not(wire):
    world = _World(offers=[_offer(cycle=LAST_CYCLE, status="purchased", purchased_card_id="card-p")],
                   cards=[_card("card-d", "t1"), _card("card-p", "t2", source="purchased"),
                          _card("card-q", "t3", source="purchased")],
                   candidates=[_candidate(i) for i in range(20)])

    cards = wire(world).get("/cards/today", headers=AUTH).json()["cards"]

    by_id = {card["card_id"]: card for card in cards}
    assert "reasons" not in by_id["card-d"]
    assert by_id["card-p"]["reasons"] == REASONS
    # 제안을 못 찾으면 빈 목록이다.
    assert by_id["card-q"]["reasons"] == []


def test_the_design_comment_about_locked_cards_is_gone():
    source = open(router_module.__file__, encoding="utf-8").read()
    assert "아직 생기지 않는다" not in source


# POST /cards/paid/{offer_id}/purchase ---------------------------------------------------------

def _no_side_writes(world: _World) -> None:
    """하트 차감 · daily_cards 생성 · 제안 처리는 DB 함수 한 번이 한다 — 서버가 따로 쓰지 않는다."""
    assert world.writes() == [("POST", "rpc/purchase_paid_card")]
    assert not any("heart" in table for _, table in world.calls)


@pytest.mark.parametrize("result", ["ok", "already_purchased"])
def test_buying_returns_the_card_id(wire, result):
    world = _World(offers=[_offer()], purchase={"result": result, "card_id": "card-new"})

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"card_id": "card-new"}
    assert world.rpc_bodies == [{"p_owner": ME, "p_offer": "offer-1"}]
    _no_side_writes(world)


def test_pressing_buy_twice_gives_the_same_answer(wire):
    world = _World(offers=[_offer()])
    client = wire(world)

    first = client.post("/cards/paid/offer-1/purchase", headers=AUTH)
    world.purchase = {"result": "already_purchased", "card_id": "card-new"}
    second = client.post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert first.json() == second.json() == {"card_id": "card-new"}
    # 한 번 누를 때 RPC 는 정확히 한 번이다.
    assert world.count("POST", "rpc/purchase_paid_card") == 2


def test_not_enough_hearts_is_402(wire):
    world = _World(offers=[_offer()], purchase={"result": "not_enough_hearts"})

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 402
    assert response.json()["detail"] == errors.HEARTS_NOT_ENOUGH
    _no_side_writes(world)


def test_a_gone_offer_is_409(wire):
    world = _World(offers=[_offer()], purchase={"result": "offer_gone"})

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.PAID_OFFER_GONE == "지금은 열 수 없는 카드예요"
    _no_side_writes(world)


@pytest.mark.parametrize("offers", [[_offer(owner_id="22222222-2222-2222-2222-222222222222")], []])
def test_someone_elses_or_a_missing_offer_is_404(wire, offers):
    world = _World(offers=offers)

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.CARD_NOT_FOUND
    assert world.count("POST", "rpc/purchase_paid_card") == 0
    assert world.writes() == []


def test_a_failing_purchase_function_is_a_5xx_and_nothing_else_is_written(wire):
    world = _World(offers=[_offer()], purchase={"message": "boom"}, purchase_status=503)

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code >= 500
    _no_side_writes(world)


def test_without_region_settings_the_paid_card_is_null(wire):
    """지역 설정 행이 없으면 주기를 몰라 제안을 만들지도 읽지도 않는다 — 다음 지급 시각도 null."""
    world = _World(offers=[_offer()], candidates=[_candidate(i) for i in range(20)], region_settings=[])

    body = wire(world).get("/cards/today", headers=AUTH).json()

    assert body["paid_card"] is None
    assert body["locked_card_available"] is False
    assert body["next_issue_at"] is None
    assert world.count("POST", "paid_card_offers") == 0


def test_an_unknown_purchase_result_is_a_5xx_and_nothing_else_is_written(wire):
    """DB 계약 밖의 result 는 성공으로 읽지 않고 그대로 500 으로 올린다(반쪽 상태를 만들지 않는다)."""
    world = _World(offers=[_offer()], purchase={"result": "surprise"})

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 500
    _no_side_writes(world)


@pytest.mark.parametrize("purchase", [{"result": "already_purchased", "card_id": None},
                                      {"result": "already_purchased"}])
def test_already_purchased_but_the_card_is_gone_is_409(wire, purchase):
    """산 카드가 지워져 card_id 가 null(또는 없음)이면 줄 카드가 없다 — 500 이 아니라 앱이 화면을 새로 읽게 409 다."""
    world = _World(offers=[_offer()], purchase=purchase)

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.PAID_OFFER_GONE
    _no_side_writes(world)


def test_ok_without_a_card_id_is_a_5xx(wire):
    """ok 는 항상 card_id 를 담는다는 계약이다 — 깨졌으면 null 카드를 200 으로 주지 않는다."""
    world = _World(offers=[_offer()], purchase={"result": "ok", "card_id": None})

    response = wire(world).post("/cards/paid/offer-1/purchase", headers=AUTH)

    assert response.status_code == 500
    _no_side_writes(world)
