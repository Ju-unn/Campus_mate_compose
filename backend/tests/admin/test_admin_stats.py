"""관리자 홈 통계 · 일별 그래프 · 미등록 도메인 · 학교별 현황(설계 10-18 §8-4 · §8-4b, 계획서 2026-10-18-admin-stats-matching Task 4). 읽기만 한다."""
import pytest

from admin_world import ADMIN, STRANGER, bearer
from stats_world import StatsWorld

ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
ROUTES = ["/admin/stats", "/admin/stats/daily", "/admin/unknown-domains", "/admin/universities"]
OVERVIEW_ROW = {"pending_count": 3, "active_count": 120, "suspended_count": 2, "withdrawn_count": 5, "open_reports": 5,
                "pending_proofs": 12, "signups_today": 38, "signups_7d": 201}


@pytest.fixture
def world() -> StatsWorld:
    return StatsWorld()


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize("url", ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_stats_route_is_behind_the_admin_gate(client, world, url, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.get(url, headers=headers)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == []


# 홈 숫자 ------------------------------------------------------------------------

def test_stats_maps_the_single_db_row_to_the_screen_shape(client, world):
    world.rpc_results["admin_stats_overview"] = [OVERVIEW_ROW]

    response = client.get("/admin/stats", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {
        "profiles": {"pending": 3, "active": 120, "suspended": 2, "withdrawn": 5},
        "open_reports": 5, "pending_proofs": 12, "signups_today": 38, "signups_7d": 201,
    }
    assert world.rpcs == [("admin_stats_overview", {})]


# 일별 그래프 --------------------------------------------------------------------

def test_daily_renames_day_to_date_and_keeps_every_row(client, world):
    world.rpc_results["admin_stats_daily"] = [
        {"day": "2026-10-17", "male_signups": 4, "female_signups": 6, "report_count": 1, "proof_count": 0, "x": "새는 칸"},
        {"day": "2026-10-18", "male_signups": 0, "female_signups": 0, "report_count": 0, "proof_count": 9},
    ]

    response = client.get("/admin/stats/daily?days=2", headers=ADMIN_HEADERS)

    assert response.json() == {"days": [
        {"date": "2026-10-17", "male_signups": 4, "female_signups": 6, "report_count": 1, "proof_count": 0},
        {"date": "2026-10-18", "male_signups": 0, "female_signups": 0, "report_count": 0, "proof_count": 9},
    ]}
    assert world.rpcs == [("admin_stats_daily", {"p_days": 2})]


def test_daily_defaults_to_thirty_days(client, world):
    client.get("/admin/stats/daily", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_stats_daily", {"p_days": 30})]


@pytest.mark.parametrize("days", [0, 91])
def test_daily_days_is_bounded(client, world, days):
    assert client.get(f"/admin/stats/daily?days={days}", headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


# 미등록 도메인 ------------------------------------------------------------------

def test_unknown_domains_passes_rows_with_exactly_the_four_keys(client, world):
    world.rpc_results["admin_unknown_domains"] = [{
        "domain": "example-univ.ac.kr", "attempt_count": 12, "first_seen_at": "2026-10-10T01:00:00+00:00",
        "last_seen_at": "2026-10-18T04:40:00+00:00", "email_prefix": "alice",
    }]

    response = client.get("/admin/unknown-domains", headers=ADMIN_HEADERS)

    assert response.json() == {"items": [{
        "domain": "example-univ.ac.kr", "attempt_count": 12, "first_seen_at": "2026-10-10T01:00:00+00:00",
        "last_seen_at": "2026-10-18T04:40:00+00:00",
    }]}
    assert "alice" not in response.text
    assert world.rpcs == [("admin_unknown_domains", {"p_limit": 200})]


def test_unknown_domains_limit_is_passed_and_bounded(client, world):
    client.get("/admin/unknown-domains?limit=7", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_unknown_domains", {"p_limit": 7})]
    for limit in (0, 501):
        assert client.get(f"/admin/unknown-domains?limit={limit}", headers=ADMIN_HEADERS).status_code == 422
    assert len(world.rpcs) == 1


# 학교별 현황 --------------------------------------------------------------------

def test_universities_passes_include_empty_as_a_boolean(client, world):
    client.get("/admin/universities", headers=ADMIN_HEADERS)
    client.get("/admin/universities?include_empty=true", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_universities_status", {"p_include_empty": False}),
                          ("admin_universities_status", {"p_include_empty": True})]
    assert client.get("/admin/universities?include_empty=maybe", headers=ADMIN_HEADERS).status_code == 422
    assert len(world.rpcs) == 2


def test_universities_rows_have_exactly_the_screen_keys(client, world):
    row = {"id": "u1", "name": "서울대학교", "region_group": "seoul", "card_opens_at": "2026-11-01T22:00:00+00:00",
           "is_open": False, "male_active": 62, "female_active": 58}
    world.rpc_results["admin_universities_status"] = [{**row, "profile_ids": ["x"]}]

    assert client.get("/admin/universities", headers=ADMIN_HEADERS).json() == {"items": [row]}


# 오류 · 기록 --------------------------------------------------------------------

@pytest.mark.parametrize("url", ROUTES)
def test_a_db_rule_violation_is_422(client, world, url):
    world.rpc_error_code = "22023"

    assert client.get(url, headers=ADMIN_HEADERS).status_code == 422


@pytest.mark.parametrize(("url", "rpc"), [("/admin/stats", "admin_stats_overview"), ("/admin/stats/daily", "admin_stats_daily")])
def test_db_failure_is_500_not_an_empty_answer(client, world, url, rpc):
    world.table_status[f"/rest/v1/rpc/{rpc}"] = 500

    assert client.get(url, headers=ADMIN_HEADERS).status_code == 500


def test_stats_reads_are_never_recorded(client, world):
    world.rpc_results["admin_stats_overview"] = [OVERVIEW_ROW]
    for url in ROUTES:
        client.get(url, headers=ADMIN_HEADERS)

    assert world.actions == []
    assert [r for r in world.requests if r.method == "POST" and r.url.path == "/rest/v1/admin_actions"] == []
