"""관리자 매칭 현황 GET /admin/matching/{summary,daily,pairs}(설계 10-18 §8-4c, 계획서 2026-10-18-admin-stats-matching Task 6). 읽기만 한다.
pairs 는 사진 · 카톡 아이디 · 대화를 싣지 않고, 필터 값은 PostgREST 필터가 아니라 DB 함수의 타입 있는 인자로만 간다."""
import logging

import pytest

from admin_world import ADMIN, STRANGER, bearer
from app.admin import matching_repository
from stats_world import StatsWorld

ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
U1 = "11111111-0000-0000-0000-000000000001"
U2 = "11111111-0000-0000-0000-000000000002"
M1 = "22222222-0000-0000-0000-000000000001"
SCHOOL = "33333333-0000-0000-0000-000000000001"
ROUTES = ["/admin/matching/summary", "/admin/matching/daily", "/admin/matching/pairs", "/admin/matching/requests"]
SUMMARY = {"accepts_today": 18, "accepts_yesterday": 14, "accepts_total": 436, "accepters_total": 312,
           "matches_total": 67, "shared_total": 41}


@pytest.fixture
def world() -> StatsWorld:
    return StatsWorld()


def _pair(n: int, **overrides) -> dict:
    return {
        "match_id": f"22222222-0000-0000-0000-{n:012d}", "matched_at": f"2026-10-18T{23 - n % 24:02d}:00:00+00:00",
        "status": "chatting", "shared_at": None, "a_id": U1, "a_nickname": "닉네임A", "a_university": "서울대학교",
        "b_id": U2, "b_nickname": "닉네임B", "b_university": "연세대학교", **overrides,
    }


def _rpc_body(world) -> dict:
    assert len(world.rpcs) == 1 and world.rpcs[0][0] == "admin_matching_pairs"
    return world.rpcs[0][1]


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize("url", ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_matching_route_is_behind_the_admin_gate(client, world, url, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.get(url, headers=headers)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == []


# 요약 · 일별 --------------------------------------------------------------------

def test_summary_passes_numbers_and_computes_the_share_rate(client, world):
    world.rpc_results["admin_matching_summary"] = [{**SUMMARY, "x": "새는 칸"}]

    body = client.get("/admin/matching/summary", headers=ADMIN_HEADERS).json()

    assert body == {**SUMMARY, "share_rate": pytest.approx(41 / 67)}
    assert world.rpcs == [("admin_matching_summary", {})]


def test_summary_with_no_matches_has_a_null_share_rate(client, world):
    world.rpc_results["admin_matching_summary"] = [{**SUMMARY, "matches_total": 0, "shared_total": 0}]

    response = client.get("/admin/matching/summary", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["share_rate"] is None


def test_matching_daily_renames_day_to_date(client, world):
    world.rpc_results["admin_matching_daily"] = [
        {"day": "2026-10-17", "accept_count": 14, "match_count": 3, "share_count": 1},
        {"day": "2026-10-18", "accept_count": 18, "match_count": 0, "share_count": 2},
    ]

    response = client.get("/admin/matching/daily?days=2", headers=ADMIN_HEADERS)

    assert response.json() == {"days": [
        {"date": "2026-10-17", "accept_count": 14, "match_count": 3, "share_count": 1},
        {"date": "2026-10-18", "accept_count": 18, "match_count": 0, "share_count": 2},
    ]}
    assert world.rpcs == [("admin_matching_daily", {"p_days": 2})]


def test_matching_daily_defaults_to_thirty_days(client, world):
    client.get("/admin/matching/daily", headers=ADMIN_HEADERS)

    assert world.rpcs == [("admin_matching_daily", {"p_days": 30})]


@pytest.mark.parametrize("days", [0, 91])
def test_matching_daily_days_is_bounded(client, world, days):
    assert client.get(f"/admin/matching/daily?days={days}", headers=ADMIN_HEADERS).status_code == 422
    assert world.rpcs == []


# 누가 누구랑 --------------------------------------------------------------------

def test_pairs_sends_typed_params_from_the_start(client, world):
    client.get("/admin/matching/pairs", headers=ADMIN_HEADERS)

    assert _rpc_body(world) == {"p_status": None, "p_university": None, "p_before_at": None, "p_before_id": None, "p_limit": 101}


def test_pairs_filters_become_separate_typed_params(client, world):
    client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params={"status": "shared", "university": SCHOOL, "page": 2})

    assert _rpc_body(world) == {"p_status": "shared", "p_university": SCHOOL, "p_before_at": None, "p_before_id": None,
                                "p_limit": 101}


def test_pairs_read_every_row_so_any_page_and_the_total_are_exact(client, world):
    # DB 함수는 커서로 101줄씩 준다 — 끝까지 이어 읽어 전체 건수와 아무 쪽이나 만든다.
    rows = sorted((_pair(n) for n in range(1, 231)), key=lambda r: (r["matched_at"], r["match_id"]), reverse=True)
    world.rpc_results["admin_matching_pairs"] = rows

    body = client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params={"page": 2, "size": 100}).json()

    assert (body["total"], body["page"], body["size"]) == (230, 2, 100)
    assert [i["id"] for i in body["items"]] == [r["match_id"] for r in rows[100:200]]
    bodies = [b for name, b in world.rpcs if name == "admin_matching_pairs"]
    assert [b["p_limit"] for b in bodies] == [101, 101, 101]
    assert (bodies[1]["p_before_at"], bodies[1]["p_before_id"]) == (rows[100]["matched_at"], rows[100]["match_id"])


def test_pairs_stop_reading_at_the_chunk_cap_and_warn(client, world, monkeypatch, caplog):
    # 끝없이 이어 읽지 않는다 — 상한 번 읽으면 경고를 남기고 그때까지 읽은 줄로 쪽을 만든다.
    monkeypatch.setattr(matching_repository, "MAX_CHUNKS", 2)
    world.rpc_results["admin_matching_pairs"] = sorted((_pair(n) for n in range(1, 400)),
                                                       key=lambda r: (r["matched_at"], r["match_id"]), reverse=True)

    with caplog.at_level(logging.WARNING, logger="app.admin.matching_repository"):
        body = client.get("/admin/matching/pairs", headers=ADMIN_HEADERS).json()

    assert body["total"] == 202
    assert len([name for name, _ in world.rpcs if name == "admin_matching_pairs"]) == 2
    assert any("admin_matching_pairs" in record.getMessage() for record in caplog.records)


def test_pairs_past_the_last_page_is_empty_with_the_total(client, world):
    world.rpc_results["admin_matching_pairs"] = [_pair(1), _pair(2)]

    body = client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params={"page": 3}).json()

    assert body == {"items": [], "total": 2, "page": 3, "size": 20}


def test_pairs_shape_and_leak_proof_columns(client, world):
    # DB 줄에 카톡 아이디 · 사진 · 마지막 말 · 전화가 섞여 와도(함수가 바뀌는 사고) 응답에는 허용 목록 칸만 나간다.
    world.rpc_results["admin_matching_pairs"] = [_pair(
        1, status="shared", shared_at="2026-10-18T02:00:00+00:00", kakao_id="secret_kakao", photo_path="u1/p.jpg",
        last_message="비밀 대화", phone="01012345678")]

    response = client.get("/admin/matching/pairs", headers=ADMIN_HEADERS)

    assert response.json() == {"items": [{
        "id": "22222222-0000-0000-0000-000000000001", "matched_at": "2026-10-18T22:00:00+00:00", "status": "shared",
        "shared_at": "2026-10-18T02:00:00+00:00",
        "a": {"id": U1, "nickname": "닉네임A", "university": "서울대학교"},
        "b": {"id": U2, "nickname": "닉네임B", "university": "연세대학교"},
    }], "total": 1, "page": 1, "size": 20}
    for secret in ("secret_kakao", "p.jpg", "비밀 대화", "01012345678"):
        assert secret not in response.text


@pytest.mark.parametrize("params", [
    {"status": "ended"}, {"status": "shared,or=(id.eq.1)"}, {"status": ""}, {"status": "SHARED"},
    {"university": "not-a-uuid"}, {"university": f"{SCHOOL},or=(x)"}, {"university": ""},
    {"page": 0}, {"size": 0}, {"size": 101},
])
def test_bad_filters_never_reach_the_db(client, world, params):
    response = client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params=params)

    assert response.status_code == 422
    assert world.rpcs == []
    for key in ("status", "university"):
        if params.get(key):  # 입력 반사 없음(핸들러가 직접 검사해 INVALID_INPUT 만 돌려준다)
            assert str(params[key]) not in response.text


def test_the_university_id_is_normalised_too(client, world):
    client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params={"university": SCHOOL.replace("-", "").upper()})

    assert _rpc_body(world)["p_university"] == SCHOOL


def test_pairs_talks_only_to_rpc_and_never_records(client, world):
    world.rpc_results["admin_matching_pairs"] = [_pair(1)]
    client.get("/admin/matching/pairs", headers=ADMIN_HEADERS, params={"status": "closed", "university": SCHOOL})

    assert [r for r in world.requests if r.url.path in ("/rest/v1/matches", "/rest/v1/profiles")] == []
    assert world.actions == []  # 목록 보기는 작업 기록에 남기지 않는다(설계 §8-4c)


# 누가 누구에게 대화를 신청했나 ----------------------------------------------------

def _request(n: int, **overrides) -> dict:
    return {
        "card_id": f"44444444-0000-0000-0000-{n:012d}", "requested_at": f"2026-10-18T{23 - n % 24:02d}:00:00+00:00",
        "status": "waiting", "responded_at": None, "requester_id": U1, "requester_nickname": "신청자", "requester_university": "서울대학교",
        "target_id": U2, "target_nickname": "받은이", "target_university": "연세대학교", **overrides,
    }


def _requests_body(world) -> dict:
    assert len(world.rpcs) == 1 and world.rpcs[0][0] == "admin_matching_requests"
    return world.rpcs[0][1]


def test_requests_sends_typed_params_from_the_start(client, world):
    client.get("/admin/matching/requests", headers=ADMIN_HEADERS)

    assert _requests_body(world) == {"p_status": None, "p_before_at": None, "p_before_id": None, "p_limit": 101}


def test_requests_status_becomes_a_typed_param(client, world):
    client.get("/admin/matching/requests", headers=ADMIN_HEADERS, params={"status": "expired", "page": 2})

    assert _requests_body(world) == {"p_status": "expired", "p_before_at": None, "p_before_id": None, "p_limit": 101}


@pytest.mark.parametrize("status", ["waiting", "accepted", "rejected", "expired"])
def test_requests_accepts_the_four_statuses(client, world, status):
    assert client.get("/admin/matching/requests", headers=ADMIN_HEADERS, params={"status": status}).status_code == 200
    assert _requests_body(world)["p_status"] == status


def test_requests_read_every_row_so_any_page_and_the_total_are_exact(client, world):
    rows = sorted((_request(n) for n in range(1, 106)), key=lambda r: (r["requested_at"], r["card_id"]), reverse=True)
    world.rpc_results["admin_matching_requests"] = rows

    body = client.get("/admin/matching/requests", headers=ADMIN_HEADERS, params={"page": 6}).json()

    assert (body["total"], [i["id"] for i in body["items"]]) == (105, [r["card_id"] for r in rows[100:105]])
    bodies = [b for name, b in world.rpcs if name == "admin_matching_requests"]
    assert (bodies[1]["p_before_at"], bodies[1]["p_before_id"]) == (rows[100]["requested_at"], rows[100]["card_id"])


def test_requests_shape_and_leak_proof_columns(client, world):
    # DB 줄에 카톡 아이디 · 사진 · 마지막 말 · 전화가 섞여 와도(함수가 바뀌는 사고) 응답에는 허용 목록 칸만 나간다.
    world.rpc_results["admin_matching_requests"] = [_request(
        1, status="accepted", responded_at="2026-10-18T02:00:00+00:00", kakao_id="secret_kakao", photo_path="u1/p.jpg",
        last_message="비밀 대화", phone="01012345678")]

    response = client.get("/admin/matching/requests", headers=ADMIN_HEADERS)

    assert response.json() == {"items": [{
        "id": "44444444-0000-0000-0000-000000000001", "requested_at": "2026-10-18T22:00:00+00:00", "status": "accepted",
        "responded_at": "2026-10-18T02:00:00+00:00",
        "requester": {"id": U1, "nickname": "신청자", "university": "서울대학교"},
        "target": {"id": U2, "nickname": "받은이", "university": "연세대학교"},
    }], "total": 1, "page": 1, "size": 20}
    for secret in ("secret_kakao", "p.jpg", "비밀 대화", "01012345678"):
        assert secret not in response.text


@pytest.mark.parametrize("params", [
    {"status": "matched"}, {"status": "chatting"}, {"status": "waiting,or=(id.eq.1)"}, {"status": ""}, {"status": "WAITING"},
    {"page": 0}, {"size": 0}, {"size": 101},
])
def test_bad_request_filters_never_reach_the_db(client, world, params):
    response = client.get("/admin/matching/requests", headers=ADMIN_HEADERS, params=params)

    assert response.status_code == 422
    assert world.rpcs == []
    for key in ("status",):
        if params.get(key):  # 입력 반사 없음(핸들러가 직접 검사해 INVALID_INPUT 만 돌려준다)
            assert str(params[key]) not in response.text


def test_requests_talks_only_to_rpc_and_never_records(client, world):
    world.rpc_results["admin_matching_requests"] = [_request(1)]
    client.get("/admin/matching/requests", headers=ADMIN_HEADERS, params={"status": "waiting"})

    assert [r for r in world.requests if r.url.path in ("/rest/v1/card_decisions", "/rest/v1/daily_cards", "/rest/v1/profiles")] == []
    assert world.actions == []  # 목록 보기는 작업 기록에 남기지 않는다(설계 §8-4c)


def test_requests_db_failure_is_500_not_an_empty_list(client, world):
    world.table_status["/rest/v1/rpc/admin_matching_requests"] = 500

    assert client.get("/admin/matching/requests", headers=ADMIN_HEADERS).status_code == 500


def test_a_db_rule_violation_is_422(client, world):
    world.rpc_error_code = "22023"

    for url in ROUTES:
        assert client.get(url, headers=ADMIN_HEADERS).status_code == 422


def test_matching_db_failure_is_500_not_an_empty_list(client, world):
    world.table_status["/rest/v1/rpc/admin_matching_pairs"] = 500

    assert client.get("/admin/matching/pairs", headers=ADMIN_HEADERS).status_code == 500
