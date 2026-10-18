"""관리자 정지 · 해제 · 가림 해제 · 글 가림 API(설계 10-18 §8-2, 계획서 2026-10-18-admin-report-review Task 3)."""
import pytest

from admin_world import ADMIN, STRANGER, TARGET, bearer

POLL = "33333333-0000-0000-0000-000000000001"
REVIEW = "33333333-0000-0000-0000-000000000002"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
REASON = {"reason": "반복 욕설"}
SEEN_1 = "22222222-0000-0000-0000-000000000001"
SEEN_2 = "22222222-0000-0000-0000-00000000000a"
UNHIDE = {**REASON, "seen_report_ids": []}
PROFILE_ROUTES = [
    (f"/admin/profiles/{TARGET}/suspend", "admin_suspend_profile"),
    (f"/admin/profiles/{TARGET}/unsuspend", "admin_unsuspend_profile"),
    (f"/admin/profiles/{TARGET}/unhide", "admin_unhide_profile"),
]
# (경로, 글 id, DB 의 대상 종류, 바꿀 상태)
CONTENT_ROUTES = [
    (f"/admin/content/polls/{POLL}/blind", POLL, "poll", "blinded"),
    (f"/admin/content/polls/{POLL}/unblind", POLL, "poll", "visible"),
    (f"/admin/content/friend-reviews/{REVIEW}/blind", REVIEW, "friend_review", "blinded"),
    (f"/admin/content/friend-reviews/{REVIEW}/unblind", REVIEW, "friend_review", "visible"),
]
ALL_URLS = [url for url, _ in PROFILE_ROUTES] + [route[0] for route in CONTENT_ROUTES]


def _ready(world) -> None:
    """정지 · 해제 · 가림 해제 · 가림 · 해제가 모두 한 번씩은 통하는 세상."""
    world.profiles[TARGET] = {"status": "active", "auto_hidden_at": "2026-10-17T00:00:00+00:00"}


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize("url", ALL_URLS)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_moderation_route_is_behind_the_admin_gate(client, world, url, who, headers, status, detail):
    _ready(world)
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.post(url, headers=headers, json=REASON)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.rpcs == []


# 정지 · 해제 · 가림 해제 ---------------------------------------------------------------

@pytest.mark.parametrize(("url", "function"), PROFILE_ROUTES)
def test_profile_actions_send_the_admin_reason_and_ip_to_one_db_function(client, world, url, function):
    _ready(world)
    if function == "admin_unsuspend_profile":
        world.profiles[TARGET]["status"] = "suspended"

    response = client.post(url, json={"reason": "  반복 욕설  ", "seen_report_ids": []},
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    assert response.status_code == 200
    # 바꾸기와 기록은 DB 함수 한 번(한 트랜잭션) — 서버가 profiles · reports 를 따로 PATCH 하지 않는다.
    # 본 신고 목록(p_seen)은 가림 해제만 받는다 — 정지 · 해제 함수에는 그 칸이 없다.
    expected = {"p_admin": ADMIN, "p_profile": TARGET, "p_reason": "반복 욕설", "p_ip": "203.0.113.7"}
    if function == "admin_unhide_profile":
        expected["p_seen"] = []
    assert world.rpcs == [(function, expected)]
    assert [r for r in world.requests if r.method == "PATCH"] == []
    assert world.actions == []  # 기록은 함수 안에서 — 서버가 admin_actions 에 따로 쓰지 않는다


def test_unhide_returns_what_the_db_function_dismissed(client, world):
    _ready(world)

    response = client.post(f"/admin/profiles/{TARGET}/unhide", headers=ADMIN_HEADERS, json=UNHIDE)

    assert response.json() == {"id": TARGET, "auto_hidden_at": None, "dismissed_ids": []}


def test_unhide_dismisses_only_the_reports_the_operator_saw(client, world):
    # 상세를 연 뒤에 들어온 새 신고까지 닫지 않게 — 본 신고 id 만 DB 함수로 간다(보안 검토 낮음 8).
    _ready(world)

    client.post(f"/admin/profiles/{TARGET}/unhide", headers=ADMIN_HEADERS,
                json={**REASON, "seen_report_ids": [SEEN_1, SEEN_2.upper()]})

    ((_, body),) = world.rpcs
    assert body["p_seen"] == [SEEN_1, SEEN_2]  # 표준 소문자 꼴로 고쳐 보낸다


def test_unhide_without_the_seen_list_is_refused_before_the_db_function(client, world):
    # 옛 웹이 목록 없이 보내면 "전부 기각" 이 되살아나지 않게 거절한다. 빈 목록([])은 "본 신고 없음" 이라 통과한다.
    _ready(world)

    response = client.post(f"/admin/profiles/{TARGET}/unhide", headers=ADMIN_HEADERS, json=REASON)

    assert (response.status_code, response.json()) == (422, {"detail": "seen_reports_required"})
    assert world.rpcs == []


@pytest.mark.parametrize("seen", [None, "x", [1], ["not-a-uuid"], [SEEN_1] * 101], ids=["null", "글자", "숫자", "UUID 아님", "101개"])
def test_unhide_rejects_a_malformed_seen_list(client, world, seen):
    _ready(world)

    response = client.post(f"/admin/profiles/{TARGET}/unhide", headers=ADMIN_HEADERS, json={**REASON, "seen_report_ids": seen})

    assert response.status_code == 422
    assert world.rpcs == []


def test_suspend_ignores_a_seen_list(client, world):
    _ready(world)

    client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json={**REASON, "seen_report_ids": [SEEN_1]})

    ((_, body),) = world.rpcs
    assert "p_seen" not in body


# 글 가림 · 해제 ------------------------------------------------------------------------

@pytest.mark.parametrize(("url", "content_id", "target", "status"), CONTENT_ROUTES)
def test_content_routes_name_the_kind_and_status_for_the_db_function(client, world, url, content_id, target, status):
    world.content[content_id] = "visible" if status == "blinded" else "blinded"

    response = client.post(url, headers=ADMIN_HEADERS, json=REASON)

    assert (response.status_code, response.json()) == (200, {"id": content_id, "status": status})
    assert world.rpcs == [("admin_set_content_status", {
        "p_admin": ADMIN, "p_target": target, "p_content": content_id, "p_status": status,
        "p_reason": "반복 욕설", "p_ip": None,
    })]


@pytest.mark.parametrize("url", [f"/admin/content/comments/{POLL}/blind", f"/admin/content/polls/{POLL}/delete",
                                 f"/admin/profiles/{TARGET}/delete"])
def test_an_unknown_kind_or_action_reaches_no_db_function(client, world, url):
    _ready(world)

    response = client.post(url, headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code in (404, 422)
    assert world.rpcs == []


# 공통 오류 ------------------------------------------------------------------------------

@pytest.mark.parametrize("url", ALL_URLS)
@pytest.mark.parametrize("body", [None, {}, {"reason": None}, {"reason": "  "}, {"reason": "가" * 501}],
                         ids=["본문 없음", "사유 없음", "null", "공백", "501자"])
def test_every_moderation_needs_a_reason(client, world, url, body):
    _ready(world)

    response = client.post(url, headers=ADMIN_HEADERS, json=body)

    assert response.status_code == 422
    assert world.rpcs == []


def test_second_action_is_409(client, world):
    # 두 관리자가 같은 사람을 정지 · 같은 글을 가렸다 — 두 번째는 DB 함수가 CM409 로 막는다.
    _ready(world)
    world.content[POLL] = "visible"
    client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json=REASON)
    client.post(f"/admin/content/polls/{POLL}/blind", headers=ADMIN_HEADERS, json=REASON)

    suspend = client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json=REASON)
    blind = client.post(f"/admin/content/polls/{POLL}/blind", headers=ADMIN_HEADERS, json=REASON)

    assert (suspend.status_code, suspend.json()) == (409, {"detail": "already_done"})
    assert (blind.status_code, blind.json()) == (409, {"detail": "already_done"})


@pytest.mark.parametrize("url", ALL_URLS)
def test_an_unknown_profile_or_content_is_404(client, world, url):
    response = client.post(url, headers=ADMIN_HEADERS, json=UNHIDE)

    assert (response.status_code, response.json()) == (404, {"detail": "not_found"})


def test_a_change_the_db_function_calls_invalid_is_422(client, world):
    _ready(world)
    world.rpc_error_code = "22023"

    response = client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code == 422


def test_a_db_function_that_finds_the_caller_off_the_admin_list_is_403_not_admin(client, world):
    # DB 함수 맨 앞의 admin_assert 가 명단에 없는 p_admin 을 42501 로 막는다 — 관문을 지난 뒤 명단에서 빠진 경우.
    _ready(world)
    world.rpc_error_code, world.rpc_error_message = "42501", "not admin"

    response = client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json=REASON)

    assert (response.status_code, response.json()) == (403, {"detail": "not_admin"})


def test_another_42501_from_a_db_function_stays_a_server_error(client, world):
    # 권한 설정 실수(예: 기록 표 insert 권한이 빠짐)는 "관리자 아님" 화면으로 숨기지 않는다 — 500 으로 드러낸다.
    _ready(world)
    world.rpc_error_code, world.rpc_error_message = "42501", "permission denied for table admin_actions"

    response = client.post(f"/admin/profiles/{TARGET}/suspend", headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code == 500


def test_a_malformed_id_is_422_before_any_db_function(client, world):
    response = client.post("/admin/profiles/not-a-uuid/suspend", headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code == 422
    assert world.rpcs == []
