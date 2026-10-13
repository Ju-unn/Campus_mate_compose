"""lifespan 이 설정을 확인하고 HTTP 클라이언트를 하나 만드는지(미결 41③)."""
import logging
import pathlib
import subprocess
import sys

import cryptography
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from starlette.requests import Request

from app.core.deps import get_client, get_settings
from app.main import app


def test_one_client_is_shared_and_closed_on_shutdown():
    # `with` 를 써야 lifespan 이 돈다 — 다른 테스트들은 get_client 를 덮어써서 켜지 않는다.
    with TestClient(app) as test_client:
        shared = app.state.http_client
        assert not shared.is_closed
        assert test_client.get("/health").status_code == 200

        # 요청이 꺼내 쓰는 것도 그 하나다(요청마다 새로 만들지 않는다).
        request = Request({"type": "http", "app": app, "headers": []})
        assert get_client(request) is shared

    # 프로세스가 내려가면 커넥션도 같이 닫힌다.
    assert shared.is_closed


@pytest.fixture
def fresh_settings():
    """`get_settings` 는 lru_cache 다 — 환경변수를 바꾸는 테스트는 앞뒤로 비워야 한다."""
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.mark.parametrize("value", [None, ""])
@pytest.mark.parametrize("name", ["IDENTITY_HMAC_KEY", "PHONE_ENCRYPTION_KEY"])
def test_boot_fails_when_a_secret_is_missing_or_empty(monkeypatch, fresh_settings, name, value):
    """빠진 · 빈 환경변수는 **첫 요청이 아니라 부팅에서** 잡혀야 한다.

    lifespan 이 설정을 만들기 전에는 컨테이너가 뜨고 /health 까지 통과한 뒤 첫 요청부터 500 이었다.
    빈 문자열도 막는다 — 빈 키로 해시를 계산하면 재가입 차단이 조용히 풀리고, 빈 암호 키로는 전화번호 ·
    실명 · 카카오톡 아이디가 빈 키로 암호화된다(2026-10-12 보안 점검 #12).
    """
    if value is None:
        monkeypatch.delenv(name, raising=False)
    else:
        monkeypatch.setenv(name, value)

    with pytest.raises(ValidationError):
        with TestClient(app):
            pass


def test_boot_logs_the_cryptography_version(caplog):
    """애플 서명(인앱결제 JWS · 탈퇴 철회 client_secret)이 쓰는 cryptography 가 운영 이미지에 들었는지 배포 뒤 로그 한 줄로 본다."""
    caplog.set_level(logging.INFO)
    with TestClient(app):
        pass

    assert f"cryptography={cryptography.__version__}" in [r.getMessage() for r in caplog.records]


def test_the_boot_log_reaches_stderr_in_a_fresh_process():
    """운영(uvicorn)은 루트 로거에 핸들러가 없고 수준이 WARNING 이라 INFO 가 버려진다(core/logs.py)."""
    code = "from app import main; main._logger.info('main-probe')"
    backend = pathlib.Path(__file__).resolve().parents[1]
    done = subprocess.run([sys.executable, "-c", code], cwd=backend, capture_output=True, text=True, timeout=60)
    assert "main-probe" in done.stderr, done.stderr
