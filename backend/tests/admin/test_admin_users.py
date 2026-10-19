"""관리자 사용자 목록 · 학교 메일 찾기 · 상세 · 메모(설계 10-18 §8-3, 계획서 2026-10-18-admin-users-billing Task 2)."""
import logging

import pytest

from admin_world import ADMIN, STRANGER, bearer, user_profile
from app.core import errors
from app.signup_policy import bytea_literal, hash_email

U1 = "11111111-0000-0000-0000-000000000001"
U2 = "11111111-0000-0000-0000-000000000002"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
EMAIL = "alice.test@campus.ac.kr"
HMAC_LITERAL = bytea_literal(hash_email("identity-key-test", EMAIL))
ROUTES = [
    ("get", "/admin/users", None),
    ("post", "/admin/users/search", {"school_email": EMAIL}),
    ("get", f"/admin/users/{U1}", None),
    ("post", f"/admin/users/{U1}/notes", {"text": "메모"}),
]


def _two_users(world) -> None:
    world.user_profiles[U1] = user_profile(U1, "닉네임A", created_at="2026-09-30T00:00:00+00:00")
    world.user_profiles[U2] = user_profile(U2, "닉네임B", status="suspended", university=None, created_at="2026-10-10T00:00:00+00:00")


def _detail_world(world) -> None:
    world.user_profiles[U1] = user_profile(U1, "닉네임A", avatar=f"{U1}/a.png")
    world.report_targets += [U1, U1]
    world.contact_blocks[U1] = 14
    world.balances[U1] = 120
    world.ledger[U1] = [
        {"id": "l1", "created_at": "2026-10-18T10:02:00+00:00", "amount": 40, "reason": "free_task"},
        {"id": "l2", "created_at": "2026-10-17T21:30:00+00:00", "amount": -30, "reason": "extra_card"},
    ]
    world.purchases = [{
        "id": "p1", "profile_id": U1, "store": "play_store", "product_id": "heart_100", "status": "granted", "is_test": False,
        "heart_amount": 100, "bonus_hearts": 50, "clawed_back_hearts": None, "purchased_at": "2026-10-10T09:20:00+00:00",
        "store_order_id": "GPA.1234-5678-9012-34567", "token_hash": "ab" * 32,
    }]
    world.action_rows = [{
        "id": "a1", "created_at": "2026-10-12T00:00:00+00:00", "admin_user_id": ADMIN, "action": "profile_note",
        "target_type": "profile", "target_id": U1, "reason": "결제 문의, 영수증 확인함",
    }, {
        "id": "a2", "created_at": "2026-10-13T00:00:00+00:00", "admin_user_id": ADMIN, "action": "profile_suspend",
        "target_type": "profile", "target_id": U1, "reason": "정지 기록은 메모가 아니다",
    }]
    world.auth_users[U1] = {"id": U1, "email": "secret@gmail.com", "identities": [
        {"provider": "kakao", "identity_data": {"sub": "123456789"}}]}


# 관문 ---------------------------------------------------------------------------

@pytest.mark.parametrize(("method", "url", "body"), ROUTES)
@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_every_user_route_is_behind_the_admin_gate(client, world, method, url, body, who, headers, status, detail):
    _two_users(world)
    if who == "관리자 아님":
        world.caller = STRANGER

    response = getattr(client, method)(url, headers=headers, **({"json": body} if body else {}))

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert world.calls("GET", "/rest/v1/profiles") == [] and world.actions == []


# 목록 ---------------------------------------------------------------------------

def test_list_is_newest_first_with_report_counts_in_one_query(client, world):
    _two_users(world)
    world.report_targets += [U1, U1, U2]

    response = client.get("/admin/users", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"items": [
        {"id": U2, "nickname": "닉네임B", "university": None, "status": "suspended",
         "created_at": "2026-10-10T00:00:00+00:00", "report_count": 1},
        {"id": U1, "nickname": "닉네임A", "university": "테스트대학교", "status": "active",
         "created_at": "2026-09-30T00:00:00+00:00", "report_count": 2},
    ]}
    listing = world.calls("GET", "/rest/v1/profiles")[0].url.params
    assert listing["order"] == "created_at.desc" and listing["limit"] == "50"
    assert len(world.calls("GET", "/rest/v1/reports")) == 1  # 줄마다 따로 세지 않는다


@pytest.mark.parametrize("limit", [0, 101])
def test_list_limit_is_bounded(client, world, limit):
    assert client.get(f"/admin/users?limit={limit}", headers=ADMIN_HEADERS).status_code == 422


def test_nickname_search_escapes_like_wildcards(client, world):
    _two_users(world)

    client.get("/admin/users", params={"q": "50%_"}, headers=ADMIN_HEADERS)

    assert world.calls("GET", "/rest/v1/profiles")[0].url.params["nickname"] == "ilike.*50\\%\\_*"


def test_search_by_profile_id_and_admins_never_appear(client, world):
    _two_users(world)
    world.user_profiles[ADMIN] = user_profile(ADMIN, "관리자")

    by_id = client.get("/admin/users", params={"q": U2}, headers=ADMIN_HEADERS).json()["items"]
    by_admin_id = client.get("/admin/users", params={"q": ADMIN}, headers=ADMIN_HEADERS).json()["items"]
    everyone = client.get("/admin/users", headers=ADMIN_HEADERS).json()["items"]

    assert [u["id"] for u in by_id] == [U2]
    assert by_admin_id == []
    assert ADMIN not in [u["id"] for u in everyone]
    # 관리자 제외는 PostgREST 필터로 한다 — 쪽 나누기와 limit 이 관리자 때문에 어긋나지 않게.
    assert world.calls("GET", "/rest/v1/profiles")[-1].url.params["id"] == f"not.in.({ADMIN})"


# 학교 메일 찾기 ------------------------------------------------------------------

def test_search_by_school_email_finds_by_hmac_only(client, world):
    _two_users(world)
    world.claims = [{"profile_id": U1, "school_email_hmac": HMAC_LITERAL, "key_version": 1}]

    response = client.post("/admin/users/search", json={"school_email": f"  {EMAIL.upper()}  "}, headers=ADMIN_HEADERS)

    assert [u["id"] for u in response.json()["items"]] == [U1]
    claim_query = world.calls("GET", "/rest/v1/school_email_claims")[0]
    assert claim_query.url.params["school_email_hmac"] == f"eq.{HMAC_LITERAL}"  # 대문자 · 공백도 hash_email 규칙 그대로
    assert "alice" not in str(claim_query.url).lower()


def test_search_by_school_email_not_found_is_an_empty_list(client, world):
    _two_users(world)

    response = client.post("/admin/users/search", json={"school_email": "nobody@campus.ac.kr"}, headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json() == {"items": []}


def test_search_by_school_email_hides_an_admin_profile(client, world):
    world.user_profiles[ADMIN] = user_profile(ADMIN, "관리자")
    world.claims = [{"profile_id": ADMIN, "school_email_hmac": HMAC_LITERAL, "key_version": 1}]

    response = client.post("/admin/users/search", json={"school_email": EMAIL}, headers=ADMIN_HEADERS)

    assert response.json() == {"items": []}


def test_school_email_never_reaches_response_logs_or_actions(client, world, caplog):
    caplog.set_level(logging.DEBUG)
    _two_users(world)
    world.claims = [{"profile_id": U1, "school_email_hmac": HMAC_LITERAL, "key_version": 1}]
    responses = [
        client.post("/admin/users/search", json={"school_email": EMAIL}, headers=ADMIN_HEADERS),  # 찾음
        client.post("/admin/users/search", json={"school_email": "other.test@campus.ac.kr"}, headers=ADMIN_HEADERS),  # 없음
        client.post("/admin/users/search", json={"school_email": "alice.test"}, headers=ADMIN_HEADERS),  # 모양이 틀림
    ]
    world.table_status["/rest/v1/school_email_claims"] = 500
    responses.append(client.post("/admin/users/search", json={"school_email": EMAIL}, headers=ADMIN_HEADERS))  # 저장소 실패

    assert [r.status_code for r in responses] == [200, 200, 422, 500]
    assert responses[2].json()["detail"] == errors.INVALID_INPUT  # 입력을 되돌리지 않는다(FastAPI 기본 422 는 input 을 싣는다)
    for needle in ("alice.test", "other.test"):
        assert not any(needle in r.text for r in responses)
        assert needle not in caplog.text
        assert not any(needle.encode() in r.content or needle in str(r.url) for r in world.requests)
    assert world.actions == []  # 검색은 기록하지 않는다(pen "검색어는 기록되지 않아요")


@pytest.mark.parametrize("email", ["", "no-at-sign", "a@b", "two@@x.kr", "sp ace@x.kr", "a@" + "b" * 250 + ".kr"])
def test_search_rejects_malformed_input_without_touching_the_db(client, world, email):
    response = client.post("/admin/users/search", json={"school_email": email}, headers=ADMIN_HEADERS)

    assert response.status_code == 422
    if email:
        assert email not in response.text
    assert world.calls("GET", "/rest/v1/school_email_claims") == []


# 상세 ---------------------------------------------------------------------------

def test_detail_has_everything_the_screen_needs(client, world):
    _detail_world(world)

    response = client.get(f"/admin/users/{U1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert body == {
        "id": U1, "nickname": "닉네임A", "university": "테스트대학교", "status": "active",
        "created_at": "2026-09-30T00:00:00+00:00", "report_count": 2,
        "last_active_at": "2026-10-18T00:00:00+00:00", "auto_hidden_at": None,
        "avatar_url": f"https://x.supabase.co/storage/v1/object/public/avatars/{U1}/a.png",
        "school_email_verified": True, "login_providers": ["kakao"], "heart_balance": 120, "contact_block_count": 14,
        "hearts": [
            {"id": "l1", "created_at": "2026-10-18T10:02:00+00:00", "amount": 40, "reason": "free_task", "balance_after": 120},
            {"id": "l2", "created_at": "2026-10-17T21:30:00+00:00", "amount": -30, "reason": "extra_card", "balance_after": 80},
        ],
        "purchases": [{
            "id": "p1", "store": "play_store", "product_id": "heart_100", "status": "granted", "is_test": False,
            "granted_hearts": 150, "bonus_hearts": 50, "clawed_back_hearts": None, "purchased_at": "2026-10-10T09:20:00+00:00",
        }],
        "notes": [{"id": "a1", "created_at": "2026-10-12T00:00:00+00:00", "admin_user_id": ADMIN, "text": "결제 문의, 영수증 확인함"}],
    }
    # 로그인 메일 · 카카오 회원번호 · 주문 번호 · 토큰 해시는 어디에도 없다.
    for secret in ("secret@gmail.com", "123456789", "GPA.1234", "abab"):
        assert secret not in response.text


def test_detail_survives_an_auth_admin_failure(client, world):
    _detail_world(world)
    world.auth_user_status = 500

    response = client.get(f"/admin/users/{U1}", headers=ADMIN_HEADERS)

    assert response.status_code == 200 and response.json()["login_providers"] is None


def test_detail_of_an_unverified_user_without_a_school_or_ledger(client, world):
    world.user_profiles[U2] = user_profile(U2, None, status="pending", university=None, school_email_verified_at=None)

    body = client.get(f"/admin/users/{U2}", headers=ADMIN_HEADERS).json()

    assert body["university"] is None and body["school_email_verified"] is False
    assert body["heart_balance"] == 0 and body["hearts"] == [] and body["purchases"] == [] and body["notes"] == []


def test_detail_of_a_withdrawn_user_still_opens(client, world):
    world.user_profiles[U2] = user_profile(U2, "탈퇴자", status="withdrawn")

    assert client.get(f"/admin/users/{U2}", headers=ADMIN_HEADERS).json()["status"] == "withdrawn"


def test_detail_of_an_admin_or_a_missing_user_is_404(client, world):
    world.user_profiles[ADMIN] = user_profile(ADMIN, "관리자")

    assert client.get(f"/admin/users/{ADMIN}", headers=ADMIN_HEADERS).status_code == 404
    assert client.get(f"/admin/users/{U2}", headers=ADMIN_HEADERS).status_code == 404


# 메모 ---------------------------------------------------------------------------

def test_note_is_one_action_row_and_nothing_else(client, world):
    _two_users(world)

    response = client.post(f"/admin/users/{U1}/notes", json={"text": "  결제 문의 접수  "},
                           headers={**ADMIN_HEADERS, "X-Forwarded-For": "203.0.113.7"})

    assert response.status_code == 200 and response.json() == {"saved": True}
    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "profile_note", "target_type": "profile", "target_id": U1,
        "before": None, "after": None, "reason": "결제 문의 접수", "ip": "203.0.113.7",
    }]
    assert [r for r in world.requests if r.method in ("PATCH", "DELETE")] == []


@pytest.mark.parametrize("text", ["", "   ", "가" * 501])
def test_note_text_is_one_to_five_hundred_characters(client, world, text):
    _two_users(world)

    assert client.post(f"/admin/users/{U1}/notes", json={"text": text}, headers=ADMIN_HEADERS).status_code == 422
    assert world.actions == []


def test_note_accepts_exactly_five_hundred_characters(client, world):
    _two_users(world)

    assert client.post(f"/admin/users/{U1}/notes", json={"text": "가" * 500}, headers=ADMIN_HEADERS).status_code == 200


def test_note_on_an_admin_or_a_missing_user_is_404_and_unrecorded(client, world):
    world.user_profiles[ADMIN] = user_profile(ADMIN, "관리자")

    assert client.post(f"/admin/users/{ADMIN}/notes", json={"text": "x"}, headers=ADMIN_HEADERS).status_code == 404
    assert client.post(f"/admin/users/{U2}/notes", json={"text": "x"}, headers=ADMIN_HEADERS).status_code == 404
    assert world.actions == []


def test_note_on_a_withdrawn_user_is_saved(client, world):
    world.user_profiles[U2] = user_profile(U2, "탈퇴자", status="withdrawn")

    assert client.post(f"/admin/users/{U2}/notes", json={"text": "탈퇴 문의 응대"}, headers=ADMIN_HEADERS).status_code == 200
    assert len(world.actions) == 1


@pytest.mark.parametrize(("status", "code", "expected"), [(422, "23514", 422), (500, None, 500)])
def test_note_surfaces_a_failed_record_insert(client, world, status, code, expected):
    _two_users(world)
    world.action_insert_status, world.action_insert_code = status, code

    assert client.post(f"/admin/users/{U1}/notes", json={"text": "x"}, headers=ADMIN_HEADERS).status_code == expected
