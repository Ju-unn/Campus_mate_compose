"""서버의 공용 클라이언트(PostgREST · Storage · 애플 · 플레이 등) 연결이 끊기면 GET 만 한 번 다시 보낸다(core/read_retry.py).

2026-11-16 시험 서버에서 앱을 켜는 순간 요청 넷(/home/summary · /me/profile · /cards/today · 알림 수)이 같은 0.1초에
httpx.ReadError 로 500 이 됐고, 홈은 요약 칸을 비운 채 남았다. 운영도 11-08 · 11-11 · 11-14 에 같은 500 이 있었다.
"""
import logging

import httpx
import pytest

from app.core.read_retry import ReadRetryTransport, make_http_client


class _Flaky(httpx.AsyncBaseTransport):
    """처음 [fails] 번은 [error] 를 던지고 그다음부터 200."""

    def __init__(self, fails: int, error: type[Exception] = httpx.ReadError):
        self.fails = fails
        self.error = error
        self.calls: list[str] = []

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        self.calls.append(request.method)
        if len(self.calls) <= self.fails:
            raise self.error("connection dropped", request=request)
        return httpx.Response(200, json={"ok": True})


@pytest.mark.parametrize("error", [httpx.ReadError, httpx.WriteError, httpx.RemoteProtocolError])
async def test_a_get_dropped_once_is_sent_again(error):
    inner = _Flaky(fails=1, error=error)
    async with make_http_client(inner) as client:
        response = await client.get("https://db.test/rest/v1/profiles")

    assert response.status_code == 200
    assert inner.calls == ["GET", "GET"]


async def test_a_get_dropped_twice_still_fails():
    """한 번만 다시 보낸다 — DB 가 정말 내려가 있으면 오래 붙잡지 않고 실패를 그대로 올린다."""
    inner = _Flaky(fails=2)
    async with make_http_client(inner) as client:
        with pytest.raises(httpx.ReadError):
            await client.get("https://db.test/rest/v1/profiles")

    assert inner.calls == ["GET", "GET"]


@pytest.mark.parametrize("method", ["POST", "PATCH", "DELETE", "PUT"])
async def test_writes_are_never_sent_twice(method):
    """쓰기는 끊긴 것이 보내기 전인지 뒤인지 모른다 — 다시 보내면 하트 차감 · 카드 지급이 두 번 될 수 있다."""
    inner = _Flaky(fails=1)
    async with make_http_client(inner) as client:
        with pytest.raises(httpx.ReadError):
            await client.request(method, "https://db.test/rest/v1/rpc/x", json={})

    assert inner.calls == [method]


async def test_other_errors_are_not_retried():
    """연결 끊김만 다시 보낸다 — 시간 초과는 이미 오래 기다린 것이라 한 번 더 기다리지 않는다."""
    inner = _Flaky(fails=1, error=httpx.ReadTimeout)
    async with make_http_client(inner) as client:
        with pytest.raises(httpx.ReadTimeout):
            await client.get("https://db.test/rest/v1/profiles")

    assert inner.calls == ["GET"]


async def test_closing_the_client_closes_the_inner_transport():
    closed = []

    class _Inner(_Flaky):
        async def aclose(self) -> None:
            closed.append(True)

    client = make_http_client(_Inner(fails=0))
    await client.aclose()

    assert closed == [True]


async def test_the_retry_log_never_carries_the_address(caplog):
    """같은 클라이언트로 사진 · 결제 · 애플 조회도 간다 — 길에 사진 경로 · 결제 토큰 · 거래 번호 · 사람 id 가 들어 있다."""
    caplog.set_level(logging.WARNING, logger="app.core.read_retry")
    secrets = [
        "https://store.test/storage/v1/object/profile-photos/11111111-2222/photo-0.jpg",
        "https://play.test/androidpublisher/v3/applications/x/purchases/products/p/tokens/PURCHASE-TOKEN-SECRET",
        "https://apple.test/inApps/v1/transactions/2000000123456789",
        "https://auth.test/auth/v1/admin/users/11111111-2222?x=y",
    ]
    for url in secrets:
        async with make_http_client(_Flaky(fails=1)) as client:
            await client.get(url)

    logged = " ".join(record.getMessage() for record in caplog.records)
    assert len(caplog.records) == len(secrets)
    for part in ("profile-photos", "11111111-2222", "PURCHASE-TOKEN-SECRET", "2000000123456789", "store.test", "/"):
        assert part not in logged
    assert "GET" in logged and "ReadError" in logged


async def test_the_default_client_uses_the_retry_transport():
    async with make_http_client() as client:
        assert isinstance(client._transport, ReadRetryTransport)
