"""채팅 실시간 전환 안 A(설계안 10-13): 쓰기 직후 사람마다 비공개 채널 `user:<profile_id>` 로 이벤트를 쏜다.

앱은 이 채널 하나로 목록 · 배지 · 읽음 '1' 을 바로 고친다. 값의 기준은 늘 서버 API 다 — 이벤트는 빨리 보여 주는
용도라 유실돼도 30초 폴링 · 복귀 새로고침이 메운다. 그래서 쏘기 실패는 로그만 남기고 삼킨다(요청은 성공한다).

채널에 들어오는 권한은 `realtime.messages` 의 받기(select) 정책이 정한다(본인 토픽만). 보내기(insert) 정책은 없어
앱은 남의 채널로 쏘지 못하고, 서버만 서비스 키로 쏜다 — 10-13 로컬 스파이크에서 둘 다 확인했다.
"""
import logging
from collections.abc import Iterable

import httpx

logger = logging.getLogger(__name__)

# 메시지 보내기 · 읽음 요청 안에서 기다린다. 이보다 늦으면 이벤트를 버린다 — 푸시와 폴링이 받쳐 준다.
TIMEOUT_SECONDS = 1.5


class Broadcaster:
    """Supabase Realtime REST(`POST /realtime/v1/api/broadcast`)로 여러 사람 몫을 한 번에 쏜다."""

    def __init__(self, supabase_url: str, service_role_key: str, client: httpx.AsyncClient,
                 give_up_after_failure: bool = False):
        """`give_up_after_failure` 는 배치용이다 — 한 번 실패하면 이 인스턴스의 나머지 쏘기를 건너뛴다.
        Realtime 장애 때 마감 방마다 제한시간을 기다려 배치가 길어지지 않게(검토 권고 1). 요청 경로는 매번 시도한다."""
        self._url = f"{supabase_url}/realtime/v1/api/broadcast" if supabase_url else ""
        self._key = service_role_key
        self._client = client
        self._give_up_after_failure = give_up_after_failure
        self._gave_up = False

    async def send(self, profile_ids: Iterable[str], event: str, payload: dict) -> None:
        """받는 사람마다 `user:<id>` 토픽 한 줄. 실패해도 예외를 올리지 않는다."""
        messages = [{"topic": f"user:{profile_id}", "event": event, "payload": payload, "private": True}
                    for profile_id in profile_ids]
        if not messages or not self._url or not self._key or self._gave_up:
            return
        try:
            response = await self._client.post(
                self._url, json={"messages": messages}, timeout=TIMEOUT_SECONDS,
                headers={"apikey": self._key, "Authorization": f"Bearer {self._key}"},
            )
        except Exception as exc:
            # str(exc) 에는 주소(프로젝트 ref)가 들어 있을 수 있다 — 예외 이름만 남긴다.
            logger.warning("실시간 쏘기 실패 event=%s %s", event, type(exc).__name__)
            self._gave_up = self._give_up_after_failure
            return
        if not response.is_success:
            logger.warning("실시간 쏘기 실패 event=%s status=%s", event, response.status_code)
            self._gave_up = self._give_up_after_failure
