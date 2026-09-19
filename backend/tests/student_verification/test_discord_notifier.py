import httpx
import pytest

from app.student_verification.discord_notifier import DiscordNotifier

WEBHOOK_URL = "https://discord.com/api/webhooks/123/abc"


async def test_notify_pending_review_posts_generic_notice_only():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["body"] = request.content
        return httpx.Response(200)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    notifier = DiscordNotifier(WEBHOOK_URL, client)

    await notifier.notify_pending_review()

    assert captured["url"] == WEBHOOK_URL
    body = captured["body"].decode("utf-8")
    assert "학생증 재검토" in body
    # 개인정보 최소화: 학교명·실명·사진 관련 정보는 절대 포함하지 않는다
    assert "학교" not in body
    assert "이름" not in body
    assert "사진" not in body


async def test_notify_pending_review_body_contains_only_generic_notice():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200)))
    notifier = DiscordNotifier(WEBHOOK_URL, client)

    # 시그니처 자체에 학교명·실명을 받을 파라미터가 없어야 한다
    import inspect

    params = inspect.signature(notifier.notify_pending_review).parameters
    assert params == {}


async def test_notify_pending_review_raises_on_failure():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    notifier = DiscordNotifier(WEBHOOK_URL, client)

    with pytest.raises(httpx.HTTPStatusError):
        await notifier.notify_pending_review()
