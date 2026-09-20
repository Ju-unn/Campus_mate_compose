from datetime import datetime

import httpx

from app.cards.push import FcmSender, notify
from app.profile_onboarding.schemas import SEOUL


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

    async def delete_push_token(self, token):
        self.deleted.append(token)


def _sender(handler) -> FcmSender:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return FcmSender("campus-mate", client, credentials=_FakeCredentials())


async def test_send_posts_to_fcm_v1_with_bearer_token():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"name": "projects/campus-mate/messages/1"})

    assert await _sender(handler).send("tok", "제목", "본문", {"route": "daily_card"}) is True
    assert seen[0].url.path == "/v1/projects/campus-mate/messages:send"
    assert seen[0].headers["Authorization"] == "Bearer ya29.test"


async def test_dead_token_is_reported_as_false():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"status": "NOT_FOUND"}})

    assert await _sender(handler).send("dead", "제목", "본문", {}) is False


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
