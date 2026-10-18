"""관리자 운영 상태판 GET /admin/health(설계 10-18 §8-4 E, 계획서 2026-10-18-admin-stats-matching Task 5). 읽기만 한다.
DB 함수는 개수만 돌려주고 정상 / 경고 / 위험 판단은 서버 상수(app/admin/health.py)가 한다."""
import pytest

from admin_world import ADMIN, STRANGER, bearer
from stats_world import StatsWorld

ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
CLEAN = {"cards_checked": 1, "cards_issued": 1, "stuck_rooms": 0, "overdue_withdrawn": 0, "avatar_failures": 0, "stuck_pushes": 0}


@pytest.fixture
def world() -> StatsWorld:
    return StatsWorld()


def _items(client, world, **counts) -> dict[str, dict]:
    world.rpc_results["admin_health"] = [{**CLEAN, **counts}]
    response = client.get("/admin/health", headers=ADMIN_HEADERS)
    assert response.status_code == 200
    return {item["key"]: item for item in response.json()["items"]}


@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_health_is_behind_the_admin_gate(client, world, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.get("/admin/health", headers=headers)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == []


def test_health_sends_the_threshold_windows_to_the_db(client, world):
    world.rpc_results["admin_health"] = [CLEAN]
    client.get("/admin/health", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_health", {
        "p_cards_grace_minutes": 60, "p_room_hours": 50, "p_withdrawn_days": 31, "p_avatar_hours": 24, "p_push_hours": 12})]


@pytest.mark.parametrize(("key", "field", "alert"), [
    ("stuck_chat_rooms", "stuck_rooms", 5),
    ("overdue_withdrawn", "overdue_withdrawn", 100),
    ("avatar_failures_24h", "avatar_failures", 3),
    ("stuck_pending_pushes", "stuck_pushes", 20),
])
def test_status_boundaries(client, world, key, field, alert):
    expected = [(0, "ok"), (1, "warn"), (alert - 1, "warn"), (alert, "alert"), (alert + 5, "alert")]

    for count, status in expected:
        item = _items(client, world, **{field: count})[key]
        assert (item["count"], item["status"]) == (count, status), (count, status)


def test_cards_not_due_is_na_not_ok_and_not_an_alert(client, world):
    # 11/2 전 코호트(받을 사람 0) · 지급 요일 아님 · 지급 시각 전은 DB 가 점검 대상에서 빼서 cards_checked 가 0 이다.
    item = _items(client, world, cards_checked=0, cards_issued=0)["cards_issued_today"]

    assert (item["status"], item["count"]) == ("na", 0)


def test_cards_issued_today_is_ok(client, world):
    item = _items(client, world, cards_checked=2, cards_issued=2)["cards_issued_today"]

    assert (item["status"], item["count"]) == ("ok", 0)


def test_some_regions_without_cards_is_still_ok(client, world):
    # 목적은 "지급 배치가 아예 안 돌았는지" 다 — 후보 부족으로 일부 지역만 0장인 것은 경고하지 않는다.
    item = _items(client, world, cards_checked=3, cards_issued=1)["cards_issued_today"]

    assert (item["status"], item["count"]) == ("ok", 0)


def test_checked_regions_and_no_card_anywhere_is_alert_with_the_region_count(client, world):
    item = _items(client, world, cards_checked=2, cards_issued=0)["cards_issued_today"]

    assert (item["status"], item["count"]) == ("alert", 2)


def test_items_are_in_screen_order_and_always_five(client, world):
    world.rpc_results["admin_health"] = [CLEAN]

    body = client.get("/admin/health", headers=ADMIN_HEADERS).json()

    assert [item["key"] for item in body["items"]] == [
        "cards_issued_today", "stuck_chat_rooms", "overdue_withdrawn", "avatar_failures_24h", "stuck_pending_pushes"]
    assert all(set(item) == {"key", "status", "count"} for item in body["items"])


def test_refund_batch_is_always_listed_as_unobservable(client, world):
    world.rpc_results["admin_health"] = [CLEAN]

    assert client.get("/admin/health", headers=ADMIN_HEADERS).json()["unobservable"] == ["refund_batch"]


def test_checked_at_is_the_request_time(client, world):
    world.rpc_results["admin_health"] = [CLEAN]

    assert client.get("/admin/health", headers=ADMIN_HEADERS).json()["checked_at"] == world.now.isoformat()


def test_health_db_failure_is_500_not_all_clear(client, world):
    world.table_status["/rest/v1/rpc/admin_health"] = 500

    assert client.get("/admin/health", headers=ADMIN_HEADERS).status_code == 500


def test_a_db_rule_violation_is_422_and_nothing_is_recorded(client, world):
    world.rpc_error_code = "22023"

    assert client.get("/admin/health", headers=ADMIN_HEADERS).status_code == 422
    assert world.actions == []
