import logging

import httpx
import pytest
from fastapi.testclient import TestClient
from app.main import app


def test_health_returns_ok():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"])
def test_api_docs_are_not_served_publicly(path):
    # 운영 서버가 경로 목록 · 요청 모양을 누구에게나 보여 주지 않는다(2026-10-12 보안 점검 #10).
    assert TestClient(app).get(path).status_code == 404


def test_the_route_list_is_still_readable_in_code():
    # 공개 주소만 닫는다 — 코드에서 app.openapi() 로 경로 이름을 읽는 쪽은 그대로 된다.
    assert "/health" in app.openapi()["paths"]


# 저장소 호출이 raise_for_status 로 실패하면 httpx 예외 문구에 요청 주소(Supabase 호스트 · 사진 경로)가 통째로 실린다.
SUPABASE_HOST = "abcdefghijklmnop.supabase.co"
PHOTO_PATH = "profile-photos/PID/UUID.jpg"


@pytest.fixture
def upstream_failing_route():
    async def fail():
        request = httpx.Request("DELETE", f"https://{SUPABASE_HOST}/storage/v1/object/{PHOTO_PATH}")
        httpx.Response(400, request=request).raise_for_status()

    app.add_api_route("/__test__/upstream-fails", fail)
    yield "/__test__/upstream-fails"
    app.router.routes.pop()


@pytest.mark.parametrize("raise_server_exceptions", [True, False])
def test_a_failed_upstream_call_answers_500_without_logging_its_address(
    upstream_failing_route, raise_server_exceptions, caplog
):
    # 처리기가 예외를 다시 던지면 uvicorn 이 "Exception in ASGI application" 에 문구를 그대로 찍는다(2026-10-12 보안 점검).
    # raise_server_exceptions=True 는 다시 던지면 여기서 터진다 — 응답이 오면 앱 밖으로 새지 않은 것이다.
    client = TestClient(app, raise_server_exceptions=raise_server_exceptions)

    with caplog.at_level(logging.DEBUG):
        response = client.get(upstream_failing_route)

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal Server Error"}
    assert PHOTO_PATH not in caplog.text
    assert SUPABASE_HOST not in caplog.text
    assert "HTTPStatusError" in caplog.text and "DELETE" in caplog.text and "status=400" in caplog.text
