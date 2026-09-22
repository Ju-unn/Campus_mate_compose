from datetime import datetime

import httpx

from app.cards.push import FcmSender, notify
from app.core.time import SEOUL


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _FakeRepo:
    def __init__(self, tokens, settings):
        self._tokens, self._settings = tokens, settings
        self.deleted: list[str] = []

    async def fetch_push_tokens(self, profile_id):
        return list(self._tokens)

    async def fetch_notification_settings(self, profile_id):
        return dict(self._settings)

    async def delete_push_token(self, token, profile_id):
        self.deleted.append(token)


def _sender(handler) -> FcmSender:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return FcmSender("campus-mate", client, credentials=_FakeCredentials())


async def test_send_posts_to_fcm_v1_with_bearer_token():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"name": "projects/campus-mate/messages/1"})

    assert await _sender(handler).send("tok", "제목", "본문", {"route": "daily_card"}) == "sent"
    assert seen[0].url.path == "/v1/projects/campus-mate/messages:send"
    assert seen[0].headers["Authorization"] == "Bearer ya29.test"


async def test_dead_token_is_reported_as_dead():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"status": "NOT_FOUND"}})

    assert await _sender(handler).send("dead", "제목", "본문", {}) == "dead"


async def test_bad_request_is_our_fault_not_a_dead_token():
    """400 은 payload 가 잘못됐다는 뜻이다. 죽은 토큰으로 보고 지우면 멀쩡한 사람의 알림이 끊긴다."""
    repo = _FakeRepo(["살아있는-토큰"], {"acceptance_received": True, "quiet_hours": False})

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": {"status": "INVALID_ARGUMENT"}})

    sent = await notify(repo, _sender(handler), "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 0
    assert repo.deleted == []


async def test_notify_deletes_tokens_that_came_back_dead():
    repo = _FakeRepo(["dead"], {"acceptance_received": True, "quiet_hours": False})

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={})

    sent = await notify(repo, _sender(handler), "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 0
    assert repo.deleted == ["dead"]


async def test_switched_off_kind_is_not_sent():
    repo = _FakeRepo(["tok"], {"acceptance_received": False, "quiet_hours": False})
    sent = await notify(repo, _sender(lambda r: httpx.Response(200, json={})), "p1",
                        "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))
    assert sent == 0


async def test_quiet_hours_block_everything_except_the_card_alarm():
    """22~8시는 보류. 단 카드 도착은 지급 시각이 07:00 이라 예외다(계획서 실행 전 확인 6번)."""
    night = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
    repo = _FakeRepo(["tok"], {"acceptance_received": True, "card_arrived": True, "quiet_hours": True})
    handler = lambda request: httpx.Response(200, json={})

    assert await notify(repo, _sender(handler), "p1", "acceptance_received", "제", "본", {}, now=night) == 0
    assert await notify(repo, _sender(handler), "p1", "card_arrived", "제", "본", {}, now=night) == 1


async def test_chat_messages_ignore_quiet_hours_but_gate_reminders_do_not():
    """조각 5 결정 5(2026-09-22 사용자): 대화는 밤에도 오간다 — 채팅 푸시만 예외다.

    게이트 리마인드는 예외가 아니다. 대신 보낼 시각 자체를 아침으로 미뤄서(chat/gate.py 의
    reminder_at) 조용한 시간에 버려지지 않게 한다."""
    dawn = datetime(2026, 9, 22, 3, 0, tzinfo=SEOUL)
    repo = _FakeRepo(["tok"], {"new_message": True, "trust_reminder": True, "quiet_hours": True})
    handler = lambda request: httpx.Response(200, json={})

    assert await notify(repo, _sender(handler), "p1", "new_message", "제", "본", {}, now=dawn) == 1
    assert await notify(repo, _sender(handler), "p1", "trust_reminder", "제", "본", {}, now=dawn) == 0
