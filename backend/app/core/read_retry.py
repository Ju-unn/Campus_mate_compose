"""서버가 함께 쓰는 HTTP 클라이언트 — 연결이 끊긴 GET 을 한 번만 다시 보낸다.

2026-11-16 시험 서버에서 앱을 켜는 순간 PostgREST 로 가던 요청 넷이 같은 순간 httpx.ReadError 로 끊겨 500 이 됐다
(운영도 11-08 · 11-11 · 11-14 에 같은 500). 끊긴 까닭은 DB 쪽 네트워크라 우리 로그로는 안 보이고, 바로 다시 보내면 된다.

이 클라이언트 하나를 PostgREST 뿐 아니라 Storage · 인증(GoTrue) · 애플 · 플레이 · GCS · 아이튠즈 조회도 같이 쓴다 —
그 GET 들도 모두 읽기라 다시 보내도 된다. GET · HEAD 만 다시 보낸다. 쓰기(POST · PATCH · PUT · DELETE, rpc 포함)는
끊긴 것이 보내기 전인지 뒤인지 몰라 다시 보내면 하트 차감 · 카드 지급이 두 번 될 수 있다. 시간 초과도 다시 보내지 않는다
— 이미 오래 기다린 요청이다. 응답 본문을 읽다 끊긴 것은 transport 밖(client.send 의 aread)이라 여기서 잡지 못한다
(이번 사고는 응답 머리 단계였다).

shortcut: transport 를 직접 주면 httpx 가 HTTP(S)_PROXY 환경변수를 읽지 않는다 — 지금은 프록시가 없다. 필요해지면
안쪽 AsyncHTTPTransport 에 proxy= 를 준다.
"""
import logging

import httpx

from app.core.logs import show_info

logger = logging.getLogger(__name__)
show_info(logger)

# WriteError: GET 을 보내는 도중 끊긴 것 — 본문이 없는 읽기라 다시 보내도 된다.
_DROPPED = (httpx.ReadError, httpx.WriteError, httpx.RemoteProtocolError)
_SAFE_METHODS = frozenset({"GET", "HEAD"})


class ReadRetryTransport(httpx.AsyncBaseTransport):
    def __init__(self, inner: httpx.AsyncBaseTransport):
        self._inner = inner

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        try:
            return await self._inner.handle_async_request(request)
        except _DROPPED as exc:
            if request.method not in _SAFE_METHODS:
                raise
            # 주소는 남기지 않는다 — 길에 결제 토큰 · 애플 거래 번호 · 사진 경로 · 사람 id 가 들어간다(main.py 의 바깥 호출 실패 로그와 같은 규칙).
            logger.warning("연결이 끊겨 %s 를 한 번 다시 보낸다 error=%s", request.method, type(exc).__name__)
            return await self._inner.handle_async_request(request)

    async def aclose(self) -> None:
        await self._inner.aclose()


def make_http_client(inner: httpx.AsyncBaseTransport | None = None) -> httpx.AsyncClient:
    """lifespan 이 한 번 만드는 공용 클라이언트. inner 는 시험이 끊김을 흉내 낼 때만 넘긴다."""
    return httpx.AsyncClient(transport=ReadRetryTransport(inner or httpx.AsyncHTTPTransport()))
