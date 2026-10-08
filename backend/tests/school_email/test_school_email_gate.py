"""학교 메일 확인 전 차단 — get_verified_* 를 쓰는 **모든** API 가 school_email_verified_at 이 NULL 이면 403.

라우터를 하나씩 적지 않고 의존성 트리를 훑는다. 새 엔드포인트가 get_verified_caller 를 쓰면 자동으로 여기 걸린다.
열어 둔 곳(인증 상태 조회 · 동의 · 탈퇴 · /school-email/*)은 아래에서 따로 본다.
"""
import re

import httpx
import pytest
from fastapi import APIRouter
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

import app.main as main
from app.core import errors
from app.core.deps import get_client, get_settings, get_verified_caller
from verify_world import AUTH, ME, settings


def _uses_verified_caller(dependant) -> bool:
    return any(sub.call is get_verified_caller or _uses_verified_caller(sub) for sub in dependant.dependencies)


def _verified_routes() -> list[tuple[str, str]]:
    routes = []
    for router in (value for value in vars(main).values() if isinstance(value, APIRouter)):
        for route in router.routes:
            if isinstance(route, APIRoute) and _uses_verified_caller(route.dependant):
                routes.extend((method, route.path) for method in sorted(route.methods))
    return routes


VERIFIED_ROUTES = _verified_routes()


def _gate_handler(gate_row: dict):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        if request.url.path == "/rest/v1/profiles" and request.method == "GET":
            return httpx.Response(200, json=[gate_row])
        return httpx.Response(200, json=[])
    return handler


@pytest.fixture
def wire():
    def _wire(**gate) -> TestClient:
        row = {"student_verification": "verified", "department": "컴공", "universities": {"name": "서울대학교"},
               "status": "active", "school_email_verified_at": None, **gate}
        http = httpx.AsyncClient(transport=httpx.MockTransport(_gate_handler(row)))
        app = main.app
        app.dependency_overrides[get_settings] = lambda: settings()
        app.dependency_overrides[get_client] = lambda: http
        return TestClient(app)
    yield _wire
    main.app.dependency_overrides.clear()


def test_the_sweep_finds_the_onboarding_and_main_apis():
    # 훑기가 비면 아래 시험이 아무것도 안 보고 통과한다 — 대표 몇 곳이 들어 있는지 먼저 본다.
    paths = {path for _, path in VERIFIED_ROUTES}
    assert {"/profile-onboarding/basic-info", "/profile-onboarding/next-step", "/home/summary",
            "/account", "/cards/today", "/reports"} <= paths
    assert len(VERIFIED_ROUTES) > 30


@pytest.mark.parametrize("method, path", VERIFIED_ROUTES)
def test_every_verified_api_is_403_before_the_school_email(wire, method, path):
    client = wire()
    url = re.sub(r"\{[^}]+\}", "55555555-5555-5555-5555-555555555555", path)

    response = client.request(method, url, headers=AUTH, json={})

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_REQUIRED
    # 정지 안내 화면으로 오인하지 않게 계정 상태 헤더를 싣지 않는다(동의 관문과 같다).
    assert "x-account-status" not in response.headers


def test_a_suspended_account_still_gets_the_suspension_answer_first(wire):
    response = wire(status="suspended").get("/home/summary", headers=AUTH)

    assert response.status_code == 403
    assert response.headers["X-Account-Status"] == "suspended"


def test_the_status_api_stays_open_before_the_school_email(wire):
    client = wire(student_verification="none", department=None)

    response = client.get("/me/verification-status", headers=AUTH)

    assert response.status_code == 200
    assert response.json()["school_email_verified"] is False


def test_consent_stays_open_before_the_school_email(wire):
    response = wire(student_verification="none", department=None).post(
        "/me/consents", headers=AUTH, json={"agreed": ["terms", "privacy"]})

    assert response.status_code == 200
