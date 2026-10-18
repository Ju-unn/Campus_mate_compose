"""관리자 작업 기록 보기 GET /admin/actions(설계 10-18 §8-5, 계획서 2026-10-18-admin-users-billing Task 6). 읽기만 한다."""
import pytest

from admin_world import ADMIN, STRANGER, bearer, user_profile

U1 = "11111111-0000-0000-0000-000000000001"
U2 = "11111111-0000-0000-0000-000000000002"
OTHER_ADMIN = "aaaaaaaa-0000-0000-0000-000000000009"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
SAME_TIME = "2026-10-18T10:00:00+00:00"


def _row(rid: str, created_at: str = SAME_TIME, **overrides) -> dict:
    return {
        "id": rid, "created_at": created_at, "admin_user_id": ADMIN, "action": "profile_note", "target_type": "profile",
        "target_id": U1, "before": None, "after": None, "reason": "메모", "ip": "203.0.113.7", **overrides,
    }


def _ids(response) -> list[str]:
    return [item["id"] for item in response.json()["items"]]


@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_action_log_is_behind_the_admin_gate(client, world, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.get("/admin/actions", headers=headers)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.calls("GET", "/rest/v1/admin_actions") == []


def test_rows_come_back_newest_first_with_every_column(client, world):
    world.action_rows = [_row("a1", "2026-10-17T00:00:00+00:00"), _row("a2", "2026-10-18T00:00:00+00:00",
                         action="hearts_adjust", before={"heart_balance": 10}, after={"heart_balance": 60, "amount": 50})]

    response = client.get("/admin/actions", headers=ADMIN_HEADERS)

    assert _ids(response) == ["a2", "a1"] and response.json()["next_before"] is None
    assert response.json()["items"][0]["before"] == {"heart_balance": 10}
    assert response.json()["items"][0]["after"] == {"heart_balance": 60, "amount": 50}
    assert set(response.json()["items"][0]) == {
        "id", "created_at", "admin_user_id", "admin_email", "action", "target_type", "target_id", "target_nickname",
        "before", "after", "reason", "ip"}
    query = world.calls("GET", "/rest/v1/admin_actions")[0].url.params
    assert query["order"] == "created_at.desc,id.desc" and query["limit"] == "51"  # 한 줄 더 읽어 다음 쪽이 있는지 안다


@pytest.mark.parametrize("limit", [0, 101])
def test_limit_is_bounded(client, world, limit):
    assert client.get(f"/admin/actions?limit={limit}", headers=ADMIN_HEADERS).status_code == 422


def test_filters_become_exact_postgrest_filters(client, world):
    world.action_rows = [_row("a1"), _row("a2", admin_user_id=OTHER_ADMIN), _row("a3", target_id=U2),
                         _row("a4", target_type="report", target_id="r1")]

    by_admin = client.get("/admin/actions", params={"admin": OTHER_ADMIN}, headers=ADMIN_HEADERS)
    by_target = client.get("/admin/actions", params={"target": f"  {U2} "}, headers=ADMIN_HEADERS)
    by_type = client.get("/admin/actions", params={"type": "report"}, headers=ADMIN_HEADERS)

    assert _ids(by_admin) == ["a2"] and _ids(by_target) == ["a3"] and _ids(by_type) == ["a4"]
    sent = [r.url.params for r in world.calls("GET", "/rest/v1/admin_actions")]
    assert sent[0]["admin_user_id"] == f"eq.{OTHER_ADMIN}" and sent[1]["target_id"] == f"eq.{U2}"


@pytest.mark.parametrize("params", [{"admin": "not-a-uuid"}, {"target": "   "}, {"target": "x" * 65}, {"type": "a b"},
                                    {"before": "garbage"}, {"before": "2026-10-18T10:00:00+00:00|not-a-uuid"},
                                    {"before": "2026-10-18T10:00:00+00:00),id.lt.x|" + U1}])
def test_malformed_filters_are_422_without_touching_the_db(client, world, params):
    assert client.get("/admin/actions", params=params, headers=ADMIN_HEADERS).status_code == 422
    assert world.calls("GET", "/rest/v1/admin_actions") == []


def test_cursor_does_not_skip_rows_sharing_a_timestamp(client, world):
    # 같은 트랜잭션에서 쓴 줄들은 created_at 이 같다(now()) — 시각만으로 자르면 줄을 놓친다.
    a1, a2, a3 = (f"00000000-0000-0000-0000-00000000000{n}" for n in (1, 2, 3))
    world.action_rows = [_row(a1), _row(a2), _row(a3)]

    first = client.get("/admin/actions?limit=2", headers=ADMIN_HEADERS)
    cursor = first.json()["next_before"]
    second = client.get("/admin/actions", params={"limit": 2, "before": cursor}, headers=ADMIN_HEADERS)

    assert _ids(first) == [a3, a2] and cursor == f"{SAME_TIME}|{a2}"
    assert _ids(second) == [a1] and second.json()["next_before"] is None


def test_the_cursor_is_sent_as_a_composite_condition(client, world):
    cursor = f"{SAME_TIME}|11111111-0000-0000-0000-0000000000aa"

    client.get("/admin/actions", params={"before": cursor}, headers=ADMIN_HEADERS)

    assert world.calls("GET", "/rest/v1/admin_actions")[0].url.params["or"] == (
        f"(created_at.lt.{SAME_TIME},and(created_at.eq.{SAME_TIME},id.lt.11111111-0000-0000-0000-0000000000aa))")


def test_admin_email_is_looked_up_once_per_admin_and_a_failure_is_null(client, world):
    world.action_rows = [_row("a1"), _row("a2"), _row("a3", admin_user_id=OTHER_ADMIN)]
    world.auth_users[ADMIN] = {"id": ADMIN, "email": "ops@example.com", "identities": []}

    response = client.get("/admin/actions", headers=ADMIN_HEADERS)

    emails = {i["id"]: i["admin_email"] for i in response.json()["items"]}
    assert emails == {"a1": "ops@example.com", "a2": "ops@example.com", "a3": None}  # 계정이 없으면(404) null, 500 아님
    assert len(world.calls("GET", f"/auth/v1/admin/users/{ADMIN}")) == 1


def test_an_auth_admin_outage_still_returns_the_log(client, world):
    world.action_rows = [_row("a1")]
    world.auth_user_status = 500

    response = client.get("/admin/actions", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["items"][0]["admin_email"] is None


def test_target_nickname_only_for_profile_rows(client, world):
    world.user_profiles[U1] = user_profile(U1, "닉네임A")
    world.action_rows = [_row("a1"), _row("a2", target_type="report", target_id="r-1"),
                         _row("a3", target_id="11111111-0000-0000-0000-0000000000ff")]

    items = {i["id"]: i for i in client.get("/admin/actions", headers=ADMIN_HEADERS).json()["items"]}

    assert items["a1"]["target_nickname"] == "닉네임A"
    assert items["a2"]["target_nickname"] is None  # 프로필 줄이 아니다
    assert items["a3"]["target_nickname"] is None  # 지워진 사람
    assert len(world.calls("GET", "/rest/v1/profiles")) == 1  # 한 번에 묶어 조회


def test_the_log_never_writes_anything(client, world):
    world.action_rows = [_row("a1")]

    client.get("/admin/actions", headers=ADMIN_HEADERS)

    assert world.actions == [] and [r for r in world.requests if r.method != "GET"] == []


@pytest.mark.parametrize("shape", ["{{{}}}", "urn:uuid:{}", "{nohyphen}"])
def test_the_cursor_id_is_normalised_to_the_standard_hyphenated_form(client, world, shape):
    last_id = "11111111-0000-0000-0000-0000000000aa"
    written = last_id.replace("-", "") if shape == "{nohyphen}" else shape.format(last_id)
    cursor = f"{SAME_TIME}|{written}"

    response = client.get("/admin/actions", params={"before": cursor}, headers=ADMIN_HEADERS)

    assert response.status_code == 200
    sent = world.calls("GET", "/rest/v1/admin_actions")[0].url.params["or"]
    assert sent == f"(created_at.lt.{SAME_TIME},and(created_at.eq.{SAME_TIME},id.lt.{last_id}))"
