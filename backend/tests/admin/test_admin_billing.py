"""관리자 결제 조회(설계 10-18 §8-5 · §8-4b, 계획서 2026-10-18-admin-users-billing Task 3)."""
import logging
from datetime import date

import pytest

from admin_world import ADMIN, STRANGER, bearer
from app.admin import billing

U1 = "11111111-0000-0000-0000-000000000001"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
ORDER = "GPA.1234-5678-9012-34567"
ROUTES = [
    ("post", "/admin/billing/orders/search", {"order": ORDER}),
    ("get", "/admin/billing/shortfall", None),
    ("get", "/admin/billing/frequent-returns", None),
    ("get", "/admin/billing/summary", None),
    ("get", "/admin/billing/daily", None),
]


def _purchase(order: str = ORDER, **overrides) -> dict:
    return {
        "id": "p1", "store": "play_store", "product_id": "heart_100", "store_order_id": order, "status": "granted",
        "is_test": False, "heart_amount": 100, "bonus_hearts": 50, "clawed_back_hearts": None, "price_krw": 5700,
        "purchased_at": "2026-10-10T09:20:00+00:00", "granted_at": "2026-10-10T09:20:05+00:00", "refunded_at": None,
        "profiles": {"id": U1, "nickname": "닉네임A"}, "token_hash": "ab" * 32, **overrides,
    }


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("method", "url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_billing_route_is_behind_the_admin_gate(client, world, method, url, body, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = getattr(client, method)(url, headers=headers, **({"json": body} if body else {}))

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == [] and world.calls("GET", "/rest/v1/purchases") == []


# 주문 번호 찾기 ------------------------------------------------------------------

def test_order_search_is_an_exact_match_and_shows_what_the_screen_needs(client, world):
    world.purchases = [_purchase(status="refunded", clawed_back_hearts=60, refunded_at="2026-10-11T00:00:00+00:00")]

    response = client.post("/admin/billing/orders/search", json={"order": f"  {ORDER}  "}, headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"items": [{
        "id": "p1", "store": "play_store", "product_id": "heart_100", "store_order_id": ORDER, "status": "refunded",
        "is_test": False, "heart_amount": 100, "bonus_hearts": 50, "granted_hearts": 150, "clawed_back_hearts": 60,
        "shortfall_hearts": 90, "price_krw": 5700, "purchased_at": "2026-10-10T09:20:00+00:00",
        "granted_at": "2026-10-10T09:20:05+00:00", "refunded_at": "2026-10-11T00:00:00+00:00",
        "profile": {"id": U1, "nickname": "닉네임A"},
    }]}
    query = world.calls("GET", "/rest/v1/purchases")[0].url.params
    assert query["store_order_id"] == f"eq.{ORDER}"
    assert "token_hash" not in query["select"]  # 토큰 해시는 고르지도 않는다
    assert "ab" * 32 not in response.text


def test_order_search_not_found_is_an_empty_list(client, world):
    assert client.post("/admin/billing/orders/search", json={"order": "GPA.0"}, headers=ADMIN_HEADERS).json() == {"items": []}


def test_order_search_of_a_deleted_account_has_no_profile_and_no_shortfall(client, world):
    world.purchases = [_purchase(status="refunded", clawed_back_hearts=0, refunded_at="2026-10-11T00:00:00+00:00", profiles=None)]

    item = client.post("/admin/billing/orders/search", json={"order": ORDER}, headers=ADMIN_HEADERS).json()["items"][0]

    assert item["profile"] is None and item["shortfall_hearts"] == 0


def test_order_search_finds_a_test_purchase_and_says_so(client, world):
    world.purchases = [_purchase(is_test=True)]

    item = client.post("/admin/billing/orders/search", json={"order": ORDER}, headers=ADMIN_HEADERS).json()["items"][0]

    assert item["is_test"] is True and item["shortfall_hearts"] == 0


@pytest.mark.parametrize("order", ["", "   ", "a b", "x" * 65, "a,b", "(a)", "a=eq.b", "주문"])
def test_order_search_rejects_bad_input_without_touching_the_db_or_echoing_it(client, world, order):
    response = client.post("/admin/billing/orders/search", json={"order": order}, headers=ADMIN_HEADERS)

    assert response.status_code == 422
    if order.strip():
        assert order not in response.text
    assert world.calls("GET", "/rest/v1/purchases") == []


# 못 거둔 하트 ---------------------------------------------------------------------

def test_shortfall_passes_the_db_rows_through(client, world):
    row = {"purchase_id": "p1", "profile_id": U1, "nickname": "닉네임A", "store": "play_store", "product_id": "heart_100",
           "heart_amount": 100, "bonus_hearts": 0, "clawed_back_hearts": 60, "granted_hearts": 100, "shortfall_hearts": 40,
           "purchased_at": "2026-10-10T09:20:00+00:00", "refunded_at": "2026-10-11T00:00:00+00:00"}
    world.rpc_results["admin_billing_shortfall"] = [row]

    response = client.get("/admin/billing/shortfall?limit=7", headers=ADMIN_HEADERS)

    assert response.json() == {"items": [row]}
    assert world.rpcs == [("admin_billing_shortfall", {"p_limit": 7})]


@pytest.mark.parametrize("limit", [0, 501])
def test_shortfall_limit_is_bounded(client, world, limit):
    assert client.get(f"/admin/billing/shortfall?limit={limit}", headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


# 환불이 잦은 계정 --------------------------------------------------------------------

def test_frequent_returns_passes_the_db_rows_through(client, world):
    # 한 계정이 50 · 100(보너스 50) · 800하트를 환불: 전부 회수 50 · 일부 60 · 하나도 0
    row = {"profile_id": U1, "nickname": "닉네임A", "refund_count": 3, "refunded_krw": 47100, "granted_hearts": 1000,
           "clawed_back_hearts": 110, "shortfall_hearts": 890, "last_refunded_at": "2026-10-11T00:00:00+00:00"}
    world.rpc_results["admin_billing_returned_accounts"] = [row]

    response = client.get("/admin/billing/frequent-returns?limit=7", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"items": [row]}
    assert world.rpcs == [("admin_billing_returned_accounts", {"p_limit": 7})]


def test_frequent_returns_defaults_to_a_hundred_accounts(client, world):
    client.get("/admin/billing/frequent-returns", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_billing_returned_accounts", {"p_limit": 100})]


@pytest.mark.parametrize("limit", [1, 500])
def test_frequent_returns_limit_edges_are_allowed(client, world, limit):
    assert client.get(f"/admin/billing/frequent-returns?limit={limit}", headers=ADMIN_HEADERS).status_code == 200
    assert world.rpcs == [("admin_billing_returned_accounts", {"p_limit": limit})]


@pytest.mark.parametrize("limit", [0, 501])
def test_frequent_returns_limit_is_bounded(client, world, limit):
    assert client.get(f"/admin/billing/frequent-returns?limit={limit}", headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


def test_a_db_rule_violation_is_422(client, world):
    world.rpc_error_code = "22023"

    assert client.get("/admin/billing/shortfall", headers=ADMIN_HEADERS).status_code == 422


# 그래프 · 이번 달 매출 --------------------------------------------------------------

def _days(n: int, per_day: int = 1000) -> list[dict]:
    return [{"day": f"2026-10-{d:02d}", "revenue_krw": per_day, "order_count": 1, "refunded_krw": 0} for d in range(1, n + 1)]


def test_daily_renames_day_to_date_and_keeps_every_row(client, world):
    world.rpc_results["admin_billing_daily"] = [
        {"day": "2026-10-17", "revenue_krw": 5700, "order_count": 1, "refunded_krw": 0},
        {"day": "2026-10-18", "revenue_krw": 0, "order_count": 0, "refunded_krw": 10800},
    ]

    response = client.get("/admin/billing/daily?days=2", headers=ADMIN_HEADERS)

    assert response.json() == {"days": [
        {"date": "2026-10-17", "revenue_krw": 5700, "order_count": 1, "refunded_krw": 0},
        {"date": "2026-10-18", "revenue_krw": 0, "order_count": 0, "refunded_krw": 10800},
    ]}
    assert world.rpcs == [("admin_billing_daily", {"p_days": 2})]


def test_daily_defaults_to_thirty_days(client, world):
    client.get("/admin/billing/daily", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_billing_daily", {"p_days": 30})]


@pytest.mark.parametrize("days", [0, 91])
def test_daily_days_is_bounded(client, world, days):
    assert client.get(f"/admin/billing/daily?days={days}", headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


@pytest.mark.parametrize(("today", "days"), [(date(2026, 10, 18), 18), (date(2026, 10, 1), 1), (date(2026, 12, 31), 31)])
def test_summary_asks_for_the_days_since_the_first_of_the_kst_month(client, world, monkeypatch, today, days):
    monkeypatch.setattr(billing, "_today", lambda: today)
    world.rpc_results["admin_billing_daily"] = _days(days)

    response = client.get("/admin/billing/summary", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_billing_daily", {"p_days": days})]
    assert response.json() == {"month": f"{today:%Y-%m}", "revenue_krw": 1000 * days, "order_count": days, "refunded_krw": 0}


def test_summary_sums_revenue_and_refunds_separately(client, world, monkeypatch):
    monkeypatch.setattr(billing, "_today", lambda: date(2026, 10, 2))
    world.rpc_results["admin_billing_daily"] = [
        {"day": "2026-10-01", "revenue_krw": 5700, "order_count": 1, "refunded_krw": 3000},
        {"day": "2026-10-02", "revenue_krw": 3000, "order_count": 2, "refunded_krw": 0},
    ]

    assert client.get("/admin/billing/summary", headers=ADMIN_HEADERS).json() == {
        "month": "2026-10", "revenue_krw": 8700, "order_count": 3, "refunded_krw": 3000}


def test_order_number_never_reaches_response_logs_or_actions(client, world, caplog):
    caplog.set_level(logging.DEBUG)
    secret_order, missing_order = "GPA.7777-8888-9999-00001", "GPA.1111-2222-3333-00002"
    world.purchases = [_purchase(secret_order)]
    responses = [
        client.post("/admin/billing/orders/search", json={"order": secret_order}, headers=ADMIN_HEADERS),  # 찾음
        client.post("/admin/billing/orders/search", json={"order": missing_order}, headers=ADMIN_HEADERS),  # 없음
        client.post("/admin/billing/orders/search", json={"order": "GPA.7777 8888"}, headers=ADMIN_HEADERS),  # 모양 틀림
    ]
    world.table_status["/rest/v1/purchases"] = 500
    responses.append(client.post("/admin/billing/orders/search", json={"order": secret_order}, headers=ADMIN_HEADERS))  # 저장소 실패

    assert [r.status_code for r in responses] == [200, 200, 422, 500]
    failures = responses[2:]  # 오류 본문에는 번호를 되돌리지 않는다(찾음 응답의 store_order_id 는 화면이 쓰는 값이다)
    assert not any("7777" in r.text for r in failures) and responses[1].json() == {"items": []}
    assert "7777" not in caplog.text and "1111-2222" not in caplog.text
    assert world.actions == []  # 읽기 화면이라 기록하지 않는다
