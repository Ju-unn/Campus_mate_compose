"""관리자 관문 get_admin_caller(설계 10-18 §6-3): 로그인 → aal2 → admin_users. 하나라도 아니면 막는다."""
import pytest
from fastapi.routing import APIRoute

from admin_world import ADMIN, STRANGER, bearer
from app.admin.caller import get_admin_caller, token_aal
from app.core import errors
from app.main import app


def test_no_token_is_401_like_every_other_api(client, world):
    response = client.get("/admin/me")

    assert response.status_code == 401
    assert response.json()["detail"] == errors.LOGIN_REQUIRED
    assert world.requests == []


def test_a_token_supabase_rejects_is_401(client, world):
    world.auth_status = 401

    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2"))

    assert response.status_code == 401
    assert response.json()["detail"] == errors.SESSION_EXPIRED


def test_a_session_without_the_second_factor_is_403_mfa_required(client, world):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal1"))

    assert response.status_code == 403
    assert response.json()["detail"] == "mfa_required"
    # 2단계 전에는 관리자인지도 알려 주지 않는다 — 명단을 보러 가지 않는다.
    assert world.calls("GET", "/rest/v1/admin_users") == []


def test_a_signed_in_non_admin_with_the_second_factor_is_403_not_admin(client, world):
    world.caller = STRANGER

    response = client.get("/admin/me", headers=bearer(sub=STRANGER, aal="aal2"))

    assert response.status_code == 403
    assert response.json()["detail"] == "not_admin"


def test_an_admin_with_the_second_factor_gets_in(client, world):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2"))

    assert response.status_code == 200
    assert response.json() == {"user_id": ADMIN, "aal": "aal2", "is_admin": True}
    # 명단은 Supabase 가 확인한 id(토큰 페이로드의 sub 가 아니다)로 찾는다.
    (lookup,) = world.calls("GET", "/rest/v1/admin_users")
    assert lookup.url.params["user_id"] == f"eq.{ADMIN}"


def test_the_admin_list_is_checked_with_the_id_supabase_confirmed_not_the_payload_sub(client, world):
    world.caller = STRANGER

    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2"))

    assert response.status_code == 403
    assert response.json()["detail"] == "not_admin"


def test_a_failed_admin_lookup_does_not_let_anyone_in(client, world):
    world.admin_lookup_status = 503

    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2"))

    assert response.status_code == 500


@pytest.mark.parametrize("authorization", [
    "Bearer not-a-jwt",
    "Bearer a.%%%.c",
    "Bearer a.bm90LWpzb24.c",  # "not-json"
    "Bearer a.WzEsMl0.c",       # [1,2] — 객체가 아니다
])
def test_a_token_whose_payload_cannot_be_read_is_403_mfa_required(client, authorization):
    response = client.get("/admin/me", headers={"Authorization": authorization})

    assert response.status_code == 403
    assert response.json()["detail"] == "mfa_required"


def test_a_token_without_an_aal_claim_is_403_mfa_required(client):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN))

    assert response.status_code == 403
    assert response.json()["detail"] == "mfa_required"


@pytest.mark.parametrize("pad", ["", "x", "xx", "xxx"])
def test_token_aal_reads_payloads_of_every_padding_length(pad):
    # base64url 은 채움('=')을 떼고 실린다. 길이 나머지가 0 · 1 · 2 · 3 인 경우를 다 본다.
    authorization = bearer(sub=ADMIN, aal="aal2", pad=pad)["Authorization"]

    assert token_aal(authorization) == "aal2"


def _routes(routes):
    for route in routes:
        if isinstance(route, APIRoute):
            yield route
        else:
            yield from _routes(getattr(route, "routes", None) or getattr(getattr(route, "original_router", None), "routes", []))


def _uses(dependant, dependency) -> bool:
    return any(sub.call is dependency or _uses(sub, dependency) for sub in dependant.dependencies)


def test_every_admin_route_goes_through_the_admin_gate():
    # 다음 조각이 /admin 경로를 늘려도 관문을 빠뜨린 경로가 생기면 여기서 걸린다.
    admin_routes = [r for r in _routes(app.routes) if r.path.startswith("/admin")]

    assert "/admin/me" in {r.path for r in admin_routes}
    assert [r.path for r in admin_routes if not _uses(r.dependant, get_admin_caller)] == []
