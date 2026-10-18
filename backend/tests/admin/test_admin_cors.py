"""관리자 웹 CORS(설계 10-18 §6-6): ADMIN_ALLOWED_ORIGINS 가 있을 때만 그 주소만 허용한다. 비면 지금과 똑같다. `*` 는 시작 때 거절."""
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.admin.cors import install_admin_cors
from app.main import app as real_app
from app.settings import AdminWebSettings

ADMIN_WEB = "https://admin.campus-mates.com"
BACKEND = Path(__file__).resolve().parents[2]


def _app_with(origins: list[str]) -> TestClient:
    app = FastAPI()

    @app.get("/ping")
    def ping() -> dict[str, bool]:
        return {"ok": True}

    install_admin_cors(app, origins)
    return TestClient(app)


def _preflight(client: TestClient, origin: str):
    return client.options("/ping", headers={
        "Origin": origin, "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type",
    })


def test_the_server_sends_no_cors_headers_when_nothing_is_set():
    # 지금 배포(값 없음)와 같다 — 모바일 앱이 보던 응답이 바뀌지 않는다.
    response = TestClient(real_app).get("/health", headers={"Origin": ADMIN_WEB})

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_an_empty_list_adds_no_middleware():
    app = FastAPI()

    install_admin_cors(app, [])

    assert app.user_middleware == []


def test_the_admin_web_origin_gets_cors_headers():
    client = _app_with([ADMIN_WEB])

    response = client.get("/ping", headers={"Origin": ADMIN_WEB})

    assert response.headers["access-control-allow-origin"] == ADMIN_WEB
    # 토큰은 Authorization 헤더로만 간다 — 쿠키(자격 증명)는 허용하지 않는다.
    assert "access-control-allow-credentials" not in response.headers


def test_the_admin_web_preflight_allows_get_post_and_the_two_headers_only():
    response = _preflight(_app_with([ADMIN_WEB]), ADMIN_WEB)

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == ADMIN_WEB
    methods = {m.strip() for m in response.headers["access-control-allow-methods"].split(",")}
    assert methods == {"GET", "POST"}
    headers = {h.strip().lower() for h in response.headers["access-control-allow-headers"].split(",")}
    assert {"authorization", "content-type"} <= headers
    assert "access-control-allow-credentials" not in response.headers


def test_another_origin_gets_no_cors_headers():
    client = _app_with([ADMIN_WEB])

    assert "access-control-allow-origin" not in client.get("/ping", headers={"Origin": "https://evil.example"}).headers
    preflight = _preflight(client, "https://evil.example")
    assert preflight.status_code == 400
    assert "access-control-allow-origin" not in preflight.headers


def test_the_setting_is_empty_by_default(monkeypatch):
    monkeypatch.delenv("ADMIN_ALLOWED_ORIGINS", raising=False)

    assert AdminWebSettings().admin_origins == []


def test_the_setting_reads_a_comma_list_from_the_env(monkeypatch):
    # 끝의 '/' 는 뗀다 — 브라우저 Origin 에는 붙지 않아 그대로 두면 조용히 안 맞는다.
    monkeypatch.setenv("ADMIN_ALLOWED_ORIGINS", f" {ADMIN_WEB}/ , http://localhost:5000 ,")

    assert AdminWebSettings().admin_origins == [ADMIN_WEB, "http://localhost:5000"]


@pytest.mark.parametrize("value", ["*", f"{ADMIN_WEB},*", "https://*.vercel.app"])
def test_a_wildcard_is_refused(monkeypatch, value):
    monkeypatch.setenv("ADMIN_ALLOWED_ORIGINS", value)

    with pytest.raises(ValidationError):
        AdminWebSettings()


def _boot(origins: str, script: str) -> subprocess.CompletedProcess:
    """설정은 app.main 을 읽을 때 한 번 정해진다 — 다른 값으로 서버를 띄운 모습은 새 프로세스에서만 본다."""
    return subprocess.run(
        [sys.executable, "-c", script], cwd=BACKEND, capture_output=True, encoding="utf-8", timeout=120,
        env={**os.environ, "ADMIN_ALLOWED_ORIGINS": origins, "PYTHONIOENCODING": "utf-8"},
    )


def test_the_server_refuses_to_start_with_a_wildcard():
    result = _boot("*", "import app.main")

    assert result.returncode != 0
    assert "ADMIN_ALLOWED_ORIGINS" in result.stderr


def test_the_server_answers_the_admin_web_when_its_origin_is_set():
    script = (
        "from fastapi.testclient import TestClient\n"
        "from app.main import app\n"
        f"r = TestClient(app).get('/health', headers={{'Origin': '{ADMIN_WEB}'}})\n"
        "print(r.headers.get('access-control-allow-origin'))\n"
        "r = TestClient(app).get('/health', headers={'Origin': 'https://evil.example'})\n"
        "print(r.headers.get('access-control-allow-origin'))\n"
    )

    result = _boot(ADMIN_WEB, script)

    assert result.returncode == 0, result.stderr
    assert result.stdout.split() == [ADMIN_WEB, "None"]
