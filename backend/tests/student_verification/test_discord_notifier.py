import inspect
import json
from typing import get_args
from uuid import UUID

import httpx
import pytest

from app.student_verification.discord_notifier import DiscordNotifier
from app.student_verification.matching import REVIEW_REASON_LABELS, ReviewReason

WEBHOOK_URL = "https://discord.com/api/webhooks/123/abc"
PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")


def _mock_client() -> tuple[httpx.AsyncClient, dict]:
    """나간 요청을 받아 두는 클라이언트를 돌려준다."""
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["body"] = request.content
        return httpx.Response(200)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return client, captured


async def test_notify_pending_review_posts_notice_with_reason():
    client, captured = _mock_client()

    await DiscordNotifier(WEBHOOK_URL, client).notify_pending_review("name_not_found", PROFILE_ID)

    assert captured["url"] == WEBHOOK_URL
    body = captured["body"].decode("utf-8")
    assert "학생증 재검토" in body
    assert "실명 불일치" in body


# 사유를 늘리면서 라벨을 빼먹으면 KeyError 로 터져야 한다 — 그래서 라벨 표가 아니라
# ReviewReason 정의 자체로 돌린다(2026-09-26 분석 권고2).
@pytest.mark.parametrize("reason", get_args(ReviewReason))
async def test_notify_pending_review_body_is_exactly_the_generic_notice(reason):
    client, captured = _mock_client()

    await DiscordNotifier(WEBHOOK_URL, client).notify_pending_review(reason, PROFILE_ID)

    # 개인정보 최소화(설계 §7.3, 2026-09-19 결정): 나가는 문장을 통째로 못 박는다 —
    # "실명이 없는지" 만 보면 나중에 무엇을 더 실어도 통과한다.
    assert json.loads(captured["body"]) == {
        "content": (
            f"학생증 재검토가 1건 있어요 (사유: {REVIEW_REASON_LABELS[reason]}, 계정: {PROFILE_ID}). "
            "Supabase 대시보드에서 확인해 주세요."
        )
    }


async def test_notify_pending_review_takes_no_parameter_that_could_carry_a_value():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200)))
    notifier = DiscordNotifier(WEBHOOK_URL, client)

    # 시그니처 자체에 학교명·실명을 받을 자리가 없어야 한다 — 받을 수 있으면 언젠가 들어간다.
    assert list(inspect.signature(notifier.notify_pending_review).parameters) == ["reason", "profile_id"]


async def test_notify_pending_review_raises_on_failure():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    notifier = DiscordNotifier(WEBHOOK_URL, client)

    with pytest.raises(httpx.HTTPStatusError):
        await notifier.notify_pending_review("vision_error", PROFILE_ID)
