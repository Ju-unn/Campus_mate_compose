"""lifespan 이 설정을 확인하고 HTTP 클라이언트를 하나 만드는지(미결 41③)."""
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
def test_boot_fails_when_a_secret_is_missing_or_empty(monkeypatch, fresh_settings, value):
    """빠진 · 빈 환경변수는 **첫 요청이 아니라 부팅에서** 잡혀야 한다.

    lifespan 이 설정을 만들기 전에는 컨테이너가 뜨고 /health 까지 통과한 뒤 첫 요청부터 500 이었다.
    빈 문자열도 막는다 — 빈 키로 해시를 계산하면 재가입 차단이 조용히 풀린다.
    """
    if value is None:
        monkeypatch.delenv("IDENTITY_HMAC_KEY", raising=False)
    else:
        monkeypatch.setenv("IDENTITY_HMAC_KEY", value)

    with pytest.raises(ValidationError):
        with TestClient(app):
            pass
