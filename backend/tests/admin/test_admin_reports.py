"""관리자 신고 검수 API(설계 10-18 §8-2, 계획서 2026-10-18-admin-report-review Task 2 · 3)."""
import json
import logging

import httpx
import pytest

from admin_world import ADMIN, MATCH, PHOTO_SIGN_PREFIX, STRANGER, TARGET, bearer, report, target_profile

R1 = "22222222-0000-0000-0000-000000000001"
R2 = "22222222-0000-0000-0000-000000000002"
OTHER = "22222222-0000-0000-0000-0000000000ff"
POLL = "33333333-0000-0000-0000-000000000001"
MESSAGE = "44444444-0000-0000-0000-000000000006"
REPORTER = "55555555-0000-0000-0000-000000000001"
STORAGE = "https://x.supabase.co/storage/v1"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
SUMMARY_KEYS = {"id", "target_type", "target_id", "reason", "reason_note", "status", "created_at", "resolved_at",
                "target_profile"}
DETAIL_KEYS = SUMMARY_KEYS | {"snapshot", "content_status", "open_reporters", "other_reports"}
REASON = {"reason": "신고 내용 확인"}
ROUTES = [
    ("GET", "/admin/reports", None),
    ("GET", f"/admin/reports/{R1}", None),
    ("POST", f"/admin/reports/{R1}/chat-context", REASON),
    ("POST", f"/admin/reports/{R1}/resolve", {"outcome": "dismissed"}),
]


def _signed(path: str) -> str:
    return f"{STORAGE}/object/sign/profile-photos/{path}?token=t"


def _data_requests(world) -> list[tuple[str, str]]:
    """관문(로그인 · 명단) 뒤의 요청들."""
    return [(r.method, r.url.path) for r in world.requests if r.url.path not in ("/auth/v1/user", "/rest/v1/admin_users")]


def _message_report(rid: str = R1) -> dict:
    return report(rid, target_type="message", target_id=MESSAGE, snapshot={
        "message_id": MESSAGE, "match_id": MATCH, "body": "기분 나쁜 말", "created_at": "2026-10-17T10:06:00+00:00",
    })


def _conversation(world) -> None:
    """13줄 대화. 6번 줄(10:06)이 신고된 줄 — 앞으로 6줄, 뒤로 6줄이 있어 앞뒤 5개로 잘린다. 짝수는 신고당한 사람이 보냈다."""
    world.messages = [
        {"id": f"44444444-0000-0000-0000-0000000000{i:02d}", "match_id": MATCH,
         "sender_id": TARGET if i % 2 == 0 else REPORTER, "kind": "text", "body": f"말 {i}",
         "created_at": f"2026-10-17T10:{i:02d}:00+00:00"}
        for i in range(13)
    ]


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("method", "url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_report_route_is_behind_the_admin_gate(client, world, method, url, body, who, headers, status, detail):
    world.reports[R1] = _message_report()
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.request(method, url, headers=headers, json=body)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert _data_requests(world) == []


# 목록 ---------------------------------------------------------------------------

def test_list_asks_for_open_reports_oldest_first_with_the_reported_person(client, world):
    world.reports[R1] = report(R1)

    response = client.get("/admin/reports", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    (query,) = world.calls("GET", "/rest/v1/reports")
    params = query.url.params
    assert params["status"] == "eq.open"
    assert params["order"] == "created_at.asc"
    assert params["limit"] == "50"
    assert "target_type" not in params
    # reports 는 profiles 를 두 번 가리킨다(reporter_id · target_profile_id) — 어느 쪽인지 짚어야 임베드가 된다.
    assert "target_profile:profiles!target_profile_id(id,nickname,status,auto_hidden_at,universities(name))" in params["select"]
    # 목록에는 사본을 싣지 않는다 — 고른 건만 상세로 받는다.
    assert "target_snapshot" not in params["select"]


def test_list_filters_by_type_and_status_and_takes_a_limit(client, world):
    response = client.get("/admin/reports?type=message&status=dismissed&limit=100", headers=ADMIN_HEADERS)

    assert (response.status_code, response.json()) == (200, {"items": []})
    params = world.calls("GET", "/rest/v1/reports")[0].url.params
    assert (params["target_type"], params["status"], params["limit"]) == ("eq.message", "eq.dismissed", "100")


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "type=user", "status=closed"])
def test_list_rejects_out_of_range_query_before_reading(client, world, query):
    response = client.get(f"/admin/reports?{query}", headers=ADMIN_HEADERS)

    assert response.status_code == 422
    assert _data_requests(world) == []


def test_list_is_one_read_with_a_summary_per_row(client, world):
    world.reports[R1] = report(R1)
    world.reports[R2] = _message_report(R2)

    items = client.get("/admin/reports", headers=ADMIN_HEADERS).json()["items"]

    assert [set(i) for i in items] == [SUMMARY_KEYS, SUMMARY_KEYS]
    assert items[0]["target_profile"] == {"id": TARGET, "nickname": "여우비", "university": "테스트대학교",
                                          "status": "active", "auto_hidden_at": None}
    assert (items[1]["id"], items[1]["target_type"], items[1]["target_id"]) == (R2, "message", MESSAGE)
    # 서명 · 같은 대상 · 신고자 세기 조회는 하나도 없다.
    assert _data_requests(world) == [("GET", "/rest/v1/reports")]


def test_a_report_whose_target_account_is_gone_has_a_null_target_profile(client, world):
    # 대상이 탈퇴해 지워지면 target_profile_id 가 null(on delete set null)이고 임베드도 null 이다.
    world.reports[R1] = report(R1, profile=None)

    listed = client.get("/admin/reports", headers=ADMIN_HEADERS)
    detail = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS)

    assert (listed.status_code, listed.json()["items"][0]["target_profile"]) == (200, None)
    assert detail.status_code == 200
    body = detail.json()
    assert (body["target_profile"], body["open_reporters"], body["other_reports"]) == (None, 0, [])
    # 대상이 없으니 같은 대상 · 신고자 세기를 묻지 않는다(target_profile_id=eq.None 같은 조회가 나가지 않게).
    assert [r for r in world.calls("GET", "/rest/v1/reports") if "target_profile_id" in r.url.params] == []


# 상세 --------------------------------------------------------------------------

def test_detail_signs_snapshot_photos_for_five_minutes_and_hides_raw_paths(client, world):
    world.reports[R1] = report(R1)

    response = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == DETAIL_KEYS
    assert body["snapshot"] == {
        "nickname": "여우비", "bio": "안녕하세요",
        "avatar_url": f"{STORAGE}/object/public/avatars/{TARGET}/a.png",
        "photo_urls": [_signed(f"{TARGET}/1.jpg"), _signed(f"{TARGET}/2.jpg")],
    }
    signs = [r for r in world.requests if r.url.path.startswith(PHOTO_SIGN_PREFIX)]
    assert [json.loads(r.content) for r in signs] == [{"expiresIn": 300}, {"expiresIn": 300}]
    # 사본 원문 · 신고 줄 원문을 그대로 싣지 않는다.
    assert "target_snapshot" not in body


def test_a_snapshot_photo_that_cannot_be_signed_is_left_out(client, world):
    # 대상이 탈퇴하고 30일 뒤 정리되면 파일이 없다(설계 §13-2) — 500 이 아니라 그 사진만 빠진다.
    world.reports[R1] = report(R1)
    world.unsignable_photos.add(f"{TARGET}/1.jpg")

    response = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json()["snapshot"]["photo_urls"] == [_signed(f"{TARGET}/2.jpg")]


def test_a_profile_snapshot_without_photos_has_no_urls(client, world):
    world.reports[R1] = report(R1, snapshot={"nickname": "여우비", "bio": None, "avatar_path": None, "photo_paths": []})

    snapshot = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS).json()["snapshot"]

    assert snapshot == {"nickname": "여우비", "bio": None, "avatar_url": None, "photo_urls": []}
    assert [r for r in world.requests if r.url.path.startswith("/storage/")] == []


@pytest.mark.parametrize(("target_type", "snapshot"), [
    ("message", {"message_id": MESSAGE, "match_id": MATCH, "body": "기분 나쁜 말", "created_at": "2026-10-17T10:06:00+00:00"}),
    ("poll", {"poll_id": POLL, "question": "질문", "option_a_label": "찬성", "option_b_label": "반대",
              "created_at": "2026-10-17T10:00:00+00:00"}),
    ("friend_review", {"review_id": POLL, "tags": ["다정해요"], "comment": "별로", "created_at": "2026-10-17T10:00:00+00:00"}),
])
def test_text_snapshots_come_back_as_they_were_stored(client, world, target_type, snapshot):
    world.reports[R1] = report(R1, target_type=target_type, target_id=POLL, snapshot=snapshot)

    body = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS).json()

    assert body["snapshot"] == snapshot
    assert [r for r in world.requests if r.url.path.startswith("/storage/")] == []


def test_detail_counts_open_reporters_and_lists_the_same_persons_other_reports(client, world):
    world.reports[R1] = report(R1)
    other = {"id": OTHER, "target_type": "message", "reason": "spam", "status": "dismissed",
             "created_at": "2026-10-10T00:00:00+00:00"}
    world.other_reports[TARGET] = [other]
    # 같은 사람이 두 번(프로필 · 메시지) 신고했고, 탈퇴한 신고자(null)는 누구인지 몰라 세지 않는다.
    world.open_reporters[TARGET] = [REPORTER, REPORTER, STRANGER, None]

    body = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS).json()

    assert body["open_reporters"] == 2
    assert body["other_reports"] == [other]
    (others,) = [r for r in world.calls("GET", "/rest/v1/reports") if "id" in r.url.params and "target_profile_id" in r.url.params]
    params = others.url.params
    assert params["target_profile_id"] == f"eq.{TARGET}"
    assert params["id"] == f"neq.{R1}"  # 자기 자신은 빼고
    assert (params["order"], params["limit"]) == ("created_at.desc", "20")
    assert params["select"] == "id,target_type,reason,status,created_at"  # 신고자 id 는 싣지 않는다
    (count,) = [r for r in world.calls("GET", "/rest/v1/reports") if r.url.params.get("select") == "reporter_id"]
    # 자동 가림이 세는 기준(safety count_open_reporters)과 같다 — 열린 신고만.
    assert (count.url.params["target_profile_id"], count.url.params["status"]) == (f"eq.{TARGET}", "eq.open")


@pytest.mark.parametrize(("target_type", "table", "stored", "expected"), [
    ("poll", "/rest/v1/polls", "blinded", "blinded"),
    ("friend_review", "/rest/v1/friend_reviews", "visible", "visible"),
    ("poll", "/rest/v1/polls", None, None),  # 글이 지워졌다(작성자 탈퇴 cascade)
])
def test_content_reports_carry_the_current_content_status(client, world, target_type, table, stored, expected):
    world.reports[R1] = report(R1, target_type=target_type, target_id=POLL, snapshot={"poll_id": POLL})
    if stored:
        world.content[POLL] = stored

    body = client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS).json()

    assert body["content_status"] == expected
    (query,) = world.calls("GET", table)
    assert (query.url.params["id"], query.url.params["select"]) == (f"eq.{POLL}", "status")


def test_profile_and_message_reports_have_no_content_status(client, world):
    world.reports[R1] = report(R1)
    world.reports[R2] = _message_report(R2)

    assert client.get(f"/admin/reports/{R1}", headers=ADMIN_HEADERS).json()["content_status"] is None
    assert client.get(f"/admin/reports/{R2}", headers=ADMIN_HEADERS).json()["content_status"] is None
    assert world.calls("GET", "/rest/v1/polls") == world.calls("GET", "/rest/v1/friend_reviews") == []


@pytest.mark.parametrize(("method", "url", "body"), ROUTES[1:])
def test_unknown_report_is_404(client, world, method, url, body):
    response = client.request(method, url, headers=ADMIN_HEADERS, json=body)

    assert (response.status_code, response.json()["detail"]) == (404, "not_found")
    assert world.actions == []


def test_a_malformed_id_is_422_before_reading(client, world):
    response = client.get("/admin/reports/not-a-uuid", headers=ADMIN_HEADERS)

    assert response.status_code == 422
    assert _data_requests(world) == []


# 채팅 앞뒤 보기(D) -------------------------------------------------------------------

def test_chat_context_is_five_lines_before_and_after_the_reported_line_as_text(client, world):
    world.reports[R1] = _message_report()
    _conversation(world)

    response = client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code == 200
    messages = response.json()["messages"]
    # 오래된 순, 신고된 6번 줄 앞 1~5 · 뒤 7~11. 0번 · 12번은 잘린다.
    assert [m["body"] for m in messages] == [f"말 {i}" for i in range(1, 12)]
    assert {frozenset(m) for m in messages} == {frozenset({"id", "kind", "body", "created_at", "from_target", "reported"})}
    assert [m["id"] for m in messages if m["reported"]] == [MESSAGE]
    assert [m["from_target"] for m in messages] == [i % 2 == 0 for i in range(1, 12)]
    queries = {(r.url.params.get("created_at", "id"), r.url.params.get("order"), r.url.params.get("limit"))
               for r in world.calls("GET", "/rest/v1/messages")}
    assert queries == {
        ("lt.2026-10-17T10:06:00+00:00", "created_at.desc", "5"),  # 앞: 가까운 것부터 5개
        ("gt.2026-10-17T10:06:00+00:00", "created_at.asc", "5"),   # 뒤
        ("id", None, None),                                         # 그 줄
    }
    assert all(r.url.params["match_id"] == f"eq.{MATCH}" for r in world.calls("GET", "/rest/v1/messages"))


def test_chat_context_records_one_view_with_the_reason_and_no_conversation(client, world, caplog):
    world.reports[R1] = _message_report()
    _conversation(world)

    with caplog.at_level(logging.DEBUG):
        client.post(f"/admin/reports/{R1}/chat-context", json={"reason": "  신고 내용 확인  "},
                    headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    # 열람만 남긴다 — 대화 본문 · 방 번호는 기록에 없다(사유는 앞뒤 공백을 뗀다).
    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "report_chat_view", "target_type": "report", "target_id": R1,
        "before": None, "after": None, "reason": "신고 내용 확인", "ip": "203.0.113.7",
    }]
    assert "말 " not in caplog.text and "기분 나쁜 말" not in caplog.text


def test_chat_context_is_recorded_before_the_conversation_is_read(client, world):
    world.reports[R1] = _message_report()
    _conversation(world)

    client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=REASON)

    order = _data_requests(world)
    assert order.index(("POST", "/rest/v1/admin_actions")) < order.index(("GET", "/rest/v1/messages"))


def test_a_view_that_cannot_be_recorded_reads_no_conversation(client, world):
    world.reports[R1] = _message_report()
    _conversation(world)
    world.action_insert_status = 503

    response = client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=REASON)

    assert response.status_code == 500
    assert world.calls("GET", "/rest/v1/messages") == []


@pytest.mark.parametrize("target_type", ["profile", "poll", "friend_review"])
def test_chat_context_is_only_for_message_reports(client, world, target_type):
    world.reports[R1] = report(R1, target_type=target_type)

    response = client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=REASON)

    assert (response.status_code, response.json()["detail"]) == (422, "not_message_report")
    assert world.actions == []
    assert world.calls("GET", "/rest/v1/messages") == []


@pytest.mark.parametrize("body", [None, {}, {"reason": None}, {"reason": "   "}, {"reason": "가" * 501}],
                         ids=["본문 없음", "사유 없음", "null", "공백", "501자"])
def test_chat_context_needs_a_reason(client, world, body):
    world.reports[R1] = _message_report()

    response = client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=body)

    assert response.status_code == 422
    assert world.actions == []
    assert _data_requests(world) == []


def test_a_conversation_that_is_gone_is_an_empty_list(client, world):
    # 대화방이 지워지면(계정 정리 cascade) 메시지가 없다 — 화면은 "없음". 열람 시도는 기록에 남는다.
    world.reports[R1] = _message_report()

    response = client.post(f"/admin/reports/{R1}/chat-context", headers=ADMIN_HEADERS, json=REASON)

    assert (response.status_code, response.json()) == (200, {"messages": []})
    assert len(world.actions) == 1


# 조치 완료 · 기각 ---------------------------------------------------------------------

def _resolves(world) -> list[dict]:
    return [body for name, body in world.rpcs if name == "admin_resolve_report"]


def test_resolve_sends_the_admin_note_and_ip_and_returns_the_detail(client, world):
    world.reports[R1] = report(R1)

    response = client.post(f"/admin/reports/{R1}/resolve", json={"outcome": "actioned", "note": "  욕설 확인  "},
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    assert response.status_code == 200
    # 같은 대상 함께 닫기는 고른 때만(기본 false). 메모는 앞뒤 공백을 뗀다.
    assert _resolves(world) == [{"p_admin": ADMIN, "p_report": R1, "p_outcome": "actioned", "p_note": "욕설 확인",
                                 "p_same_target": False, "p_ip": "203.0.113.7"}]
    body = response.json()
    assert set(body) == DETAIL_KEYS
    assert (body["status"], body["resolved_at"]) == ("actioned", "2026-10-18T02:00:00+00:00")


@pytest.mark.parametrize(("note", "sent"), [(None, None), ("   ", None)], ids=["없음", "공백"])
def test_resolve_can_close_the_same_persons_open_reports_without_a_note(client, world, note, sent):
    world.reports[R1] = report(R1)

    response = client.post(f"/admin/reports/{R1}/resolve", headers=ADMIN_HEADERS,
                           json={"outcome": "dismissed", "note": note, "same_target": True})

    assert response.status_code == 200
    (body,) = _resolves(world)
    assert (body["p_outcome"], body["p_note"], body["p_same_target"]) == ("dismissed", sent, True)


@pytest.mark.parametrize("body", [None, {}, {"outcome": "open"}, {"outcome": "closed"},
                                  {"outcome": "dismissed", "note": "가" * 501},
                                  {"outcome": "dismissed", "same_target": "maybe"}],
                         ids=["본문 없음", "결과 없음", "open", "모르는 값", "메모 501자", "함께 닫기 글자"])
def test_resolve_needs_one_of_the_two_outcomes(client, world, body):
    world.reports[R1] = report(R1)

    response = client.post(f"/admin/reports/{R1}/resolve", headers=ADMIN_HEADERS, json=body)

    assert response.status_code == 422
    assert world.rpcs == []


def test_second_action_is_409(client, world):
    # 두 관리자가 같은 신고를 닫았다 — 두 번째는 DB 함수가 CM409 로 막는다(기록은 한 번, pgTAP 이 본다).
    world.reports[R1] = report(R1)
    client.post(f"/admin/reports/{R1}/resolve", headers=ADMIN_HEADERS, json={"outcome": "actioned"})

    again = client.post(f"/admin/reports/{R1}/resolve", headers=ADMIN_HEADERS, json={"outcome": "dismissed"})

    assert (again.status_code, again.json()) == (409, {"detail": "already_done"})


def test_a_resolve_the_db_function_calls_invalid_is_422(client, world):
    world.reports[R1] = report(R1)
    world.rpc_error_code = "22023"

    response = client.post(f"/admin/reports/{R1}/resolve", headers=ADMIN_HEADERS, json={"outcome": "actioned"})

    assert response.status_code == 422
