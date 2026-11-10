"""인증번호 문자 발송기. SMS_PROVIDER 로 고른다 — solapi 면 솔라피, 그 밖은 가짜(로컬 스택에서만).

로그에는 상태 코드 · 예외 이름만 남긴다 — 번호 · 인증번호 · 키는 남기지 않는다(가짜 발송기의 로컬 로그만 예외).
"""
import hashlib
import hmac
import logging
import uuid
from datetime import datetime, timezone
from typing import Protocol

import httpx
from fastapi import Depends

from app.core.deps import get_client, get_settings
from app.core.logs import show_info
from app.settings import Settings

logger = logging.getLogger(__name__)
# 가짜 발송기의 "인증번호 한 줄"(INFO)이 로컬 서버 로그에 나오게 한다 — 운영 uvicorn 은 INFO 를 버리고, 운영에는 가짜 발송기가 없다.
show_info(logger)

# 단문(45자 안), 인증번호만 — 홍보 문구를 섞으면 광고 문자가 된다(계획서 §5).
VERIFICATION_TEXT = "[CampusMate] 인증번호 [{code}]을 입력해 주세요."
SOLAPI_SEND_URL = "https://api.solapi.com/messages/v4/send-many/detail"
SOLAPI_TIMEOUT_SECONDS = 10.0


class SmsSender(Protocol):
    async def send(self, to: str, text: str) -> bool:
        """to 는 E.164(+8210…). 보냈으면 True, 못 보냈으면 False(예외를 올리지 않는다)."""


class FakeSmsSender:
    """문자를 보내지 않고 메모리에 남긴다. get_sms_sender 가 로컬 스택일 때만 만든다."""

    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    async def send(self, to: str, text: str) -> bool:
        self.sent.append((to, text))
        # 로컬에서 앱으로 시험할 때 인증번호를 볼 곳이 여기뿐이다. 번호는 끝 4자리만.
        logger.info("가짜 문자 발송(로컬) to=…%s text=%s", to[-4:], text)
        return True


class SolapiSmsSender:
    """솔라피 send-many/detail 로 한 통. 인증은 HMAC-SHA256(시크릿, 시각 + salt) 서명 헤더다."""

    def __init__(self, api_key: str, api_secret: str, sender: str, client: httpx.AsyncClient):
        self._api_key, self._api_secret, self._sender, self._client = api_key, api_secret, sender, client

    async def send(self, to: str, text: str) -> bool:
        date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        salt = uuid.uuid4().hex
        signature = hmac.new(self._api_secret.encode(), (date + salt).encode(), hashlib.sha256).hexdigest()
        headers = {"Authorization": f"HMAC-SHA256 ApiKey={self._api_key}, Date={date}, salt={salt}, signature={signature}"}
        # 솔라피는 국내 번호를 0 으로 시작하는 숫자로 받는다(+8210… → 010…).
        message = {"to": "0" + to.removeprefix("+82"), "from": self._sender, "text": text}
        try:
            response = await self._client.post(SOLAPI_SEND_URL, json={"messages": [message]}, headers=headers,
                                               timeout=SOLAPI_TIMEOUT_SECONDS)
        except httpx.HTTPError as exc:
            logger.warning("솔라피 발송 실패 %s", type(exc).__name__)
            return False
        if not response.is_success:
            logger.warning("솔라피 발송 실패 status=%s", response.status_code)
            return False
        try:
            failed = response.json().get("failedMessageList")
        except (ValueError, AttributeError):
            logger.warning("솔라피 발송 응답을 읽지 못함 status=%s", response.status_code)
            return False
        if failed:
            logger.warning("솔라피 발송 실패 status=%s failed=%s", response.status_code, len(failed))
            return False
        return True


def get_sms_sender(
    settings: Settings = Depends(get_settings), client: httpx.AsyncClient = Depends(get_client),
) -> SmsSender | None:
    """None = 지금은 보낼 수 없다(보내기 경로가 줄을 만들기 전에 503). 시험은 dependency_overrides 로 가짜를 끼운다."""
    if settings.sms_provider == "solapi":
        if settings.solapi_api_key and settings.solapi_api_secret and settings.solapi_sender:
            return SolapiSmsSender(settings.solapi_api_key, settings.solapi_api_secret, settings.solapi_sender, client)
        logger.error("SMS_PROVIDER=solapi 인데 SOLAPI_API_KEY · SOLAPI_API_SECRET · SOLAPI_SENDER 가 비었다 — 문자를 보내지 않는다")
        return None
    if not settings.runs_locally:
        # 가짜 발송기는 누구에게나 인증을 열어 준다 — 운영 DB 를 보는 서버에서는 절대 쓰지 않는다.
        logger.error("SMS_PROVIDER=%s 는 로컬 스택에서만 쓴다 — 운영에서는 문자를 보내지 않는다", settings.sms_provider)
        return None
    return _LOCAL_FAKE


# 로컬 서버 하나가 같이 쓰는 가짜 발송기(보낸 기록이 프로세스 안에만 남는다).
_LOCAL_FAKE = FakeSmsSender()
