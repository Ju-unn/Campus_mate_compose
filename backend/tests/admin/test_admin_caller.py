"""관리자 관문 get_admin_caller(설계 10-18 §6-3): 로그인 → aal2 → admin_users. 하나라도 아니면 막는다."""
import time

import pytest
from fastapi.routing import APIRoute

from admin_world import ADMIN, STRANGER, amr, bearer, settings
from app.admin.caller import get_admin_caller, token_claims
from app.core import errors
from app.core.deps import get_settings
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


@pytest.mark.parametrize("hours_ago", [0, 11])
def test_a_second_factor_entered_within_12_hours_lets_the_admin_in(client, hours_ago):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2", amr=amr(hours_ago)))

    assert response.status_code == 200


def test_a_second_factor_entered_13_hours_ago_is_403_mfa_required(client, world):
    # 새로 고친 토큰도 aal2 는 그대로다 — 2단계를 마친 시각(amr 의 totp)으로 세션 수명을 끊는다.
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2", amr=amr(13)))

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")
    assert world.calls("GET", "/rest/v1/admin_users") == []


def test_an_aal2_session_whose_amr_has_no_totp_is_403_mfa_required(client):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2", amr=amr(0, method="mfa/phone")))

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")


@pytest.mark.parametrize("bad_amr", [
    None,                                              # amr 칸이 없다
    "totp",
    {"method": "totp", "timestamp": int(time.time())},  # 목록이 아니다
    ["totp"],
    [{"method": "totp"}],                              # 시각이 없다
    [{"method": "totp", "timestamp": str(int(time.time()))}],
    [{"method": "totp", "timestamp": None}],
])
def test_an_aal2_session_with_a_missing_or_malformed_amr_is_403_mfa_required(client, bad_amr):
    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2", amr=bad_amr))

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")


def test_the_second_factor_age_limit_comes_from_settings(client):
    app.dependency_overrides[get_settings] = lambda: settings(admin_mfa_max_age_hours=1)

    response = client.get("/admin/me", headers=bearer(sub=ADMIN, aal="aal2", amr=amr(2)))

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")


def _token(**claims) -> str:
    return bearer(**claims)["Authorization"].removeprefix("Bearer ")


@pytest.mark.parametrize("authorization", [
    "Bearer a.b.c {token}",  # 공백 뒤 둘째 토막 — 예전에는 마지막 토막의 aal 을 읽었다
    "Bearer  {token}",       # 공백 둘
    "Token {token}",
    "{token}",
])
def test_an_authorization_that_is_not_exactly_bearer_and_one_token_is_403_mfa_required(client, authorization):
    response = client.get("/admin/me", headers={"Authorization": authorization.format(token=_token(sub=ADMIN, aal="aal2"))})

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")


@pytest.mark.parametrize("scheme", ["bearer", "BEARER", "BeArEr"])
def test_the_bearer_word_is_read_in_any_case_like_gotrue(client, scheme):
    # GoTrue(supabase/auth internal/api/api.go)의 bearerRegexp 는 (?i)^bearer (\S+$) 다 — 같은 규칙으로 읽는다.
    response = client.get("/admin/me", headers={"Authorization": f"{scheme} {_token(sub=ADMIN, aal='aal2')}"})

    assert response.status_code == 200


@pytest.mark.parametrize("pad", ["", "x", "xx", "xxx"])
def test_token_claims_reads_payloads_of_every_padding_length(pad):
    # base64url 은 채움('=')을 떼고 실린다. 길이 나머지가 0 · 1 · 2 · 3 인 경우를 다 본다.
    authorization = bearer(sub=ADMIN, aal="aal2", pad=pad)["Authorization"]

    assert token_claims(authorization)["aal"] == "aal2"


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
