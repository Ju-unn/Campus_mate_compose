"""HTTP 클라이언트를 lifespan 하나가 만들고 닫는지(미결 41③)."""
from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.deps import get_client
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
