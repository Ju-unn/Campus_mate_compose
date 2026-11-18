"""프로세스에 하나 두는 구글 ADC 자격 → 접근 토큰. 요청마다 ADC 를 다시 읽지 않는다(메타데이터 서버를 매번 부르지 않게)."""
import asyncio

import google.auth
from google.auth.transport.requests import Request as GoogleAuthRequest


class AdcToken:
    """`await token()` → 유효한 접근 토큰. 실패는 GoogleAuthError 그대로 올린다(부른 쪽이 503 등으로 바꾼다).

    만들기와 refresh 를 락 하나로 감싼다 — 새 인스턴스에 동시 요청이 몰리면 각자 자격을 만들어 서로 덮고,
    refresh 안 된 남의 자격에서 token(None) 을 읽어 `Bearer None` → 401 이 났다(11-18 운영)."""

    def __init__(self, scope: str):
        self._scope = scope
        self._credentials = None
        self._lock = asyncio.Lock()

    async def __call__(self) -> str:
        async with self._lock:
            if self._credentials is None:
                self._credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[self._scope])
            credentials = self._credentials
            if not credentials.valid:
                # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다.
                await asyncio.to_thread(credentials.refresh, GoogleAuthRequest())
            return credentials.token
