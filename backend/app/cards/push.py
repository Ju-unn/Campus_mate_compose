import asyncio
import logging
from datetime import datetime

import google.auth
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
# 조용한 시간(설계 화면 16d): 22시 ~ 다음날 8시.
_QUIET_START_HOUR = 22
_QUIET_END_HOUR = 8
# 카드 도착 알림은 지급 시각(07:00)이 조용한 시간 안이라 예외다 — 아니면 영영 못 간다.
_QUIET_HOURS_EXEMPT = {"card_arrived"}


class FcmSender:
    """FCM HTTP v1 에 알림 한 건을 보낸다. 자격증명은 Cloud Run 서비스 계정(ADC)이다 —
    Vision 과 같은 방식이고 서버 키를 따로 만들지 않는다(2026-09-20 준비 가이드)."""

    def __init__(self, project_id: str, client: httpx.AsyncClient, credentials=None):
        self._project_id = project_id
        self._client = client
        self._credentials = credentials

    async def _access_token(self) -> str:
        if self._credentials is None:
            self._credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
        if not self._credentials.valid:
            # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다.
            await asyncio.to_thread(self._credentials.refresh, GoogleAuthRequest())
        return self._credentials.token

    async def send(self, token: str, title: str, body: str, data: dict[str, str]) -> str:
        """`"sent"` · `"dead"` · `"failed"` 중 하나. `"dead"` 일 때만 부른 쪽이 토큰을 지운다.

        400 은 죽은 토큰이 아니라 우리가 보낸 payload 가 잘못됐다는 뜻이다 — 예전에는 404 와
        한데 묶여서 멀쩡한 사람의 토큰을 조용히 지웠다."""
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                # data 값은 문자열만 허용된다. 앱은 route 로 어느 화면을 열지 고른다(Task A7).
                "data": {key: str(value) for key, value in data.items()},
                "android": {"priority": "high"},
            }
        }
        response = await self._client.post(
            f"https://fcm.googleapis.com/v1/projects/{self._project_id}/messages:send",
            json=payload,
            headers={"Authorization": f"Bearer {await self._access_token()}"},
        )
        if response.status_code == 404:
            return "dead"
        if not response.is_success:
            # 푸시 실패가 카드 지급을 되돌리게 두지 않는다 — 로그만 남기고 넘어간다.
            logger.warning("FCM 전송 실패 %s %s", response.status_code, response.text[:200])
            return "failed"
        return "sent"


def _is_quiet(now: datetime) -> bool:
    return now.hour >= _QUIET_START_HOUR or now.hour < _QUIET_END_HOUR


async def notify(repo, sender: FcmSender, profile_id, kind: str,
                 title: str, body: str, data: dict[str, str], now: datetime) -> int:
    """알림 스위치와 조용한 시간을 본 뒤 그 사람의 모든 기기로 보낸다. 보낸 건수를 돌려준다."""
    settings = await repo.fetch_notification_settings(profile_id)
    if not settings.get(kind, True):
        return 0
    if settings.get("quiet_hours", True) and kind not in _QUIET_HOURS_EXEMPT and _is_quiet(now):
        # ponytail: 지금은 그냥 버린다. 모아 뒀다 아침에 보내려면 큐가 필요하다(백로그).
        return 0

    sent = 0
    for token in await repo.fetch_push_tokens(profile_id):
        result = await sender.send(token, title, body, data)
        if result == "sent":
            sent += 1
        elif result == "dead":
            # 이 토큰은 방금 profile_id 로 꺼내 온 것이라 주인이 확실하다.
            await repo.delete_push_token(token, profile_id)
    return sent
