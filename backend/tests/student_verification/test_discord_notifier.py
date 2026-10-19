import inspect
import json
import logging
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


async def test_orphan_notice_carries_only_the_account_id():
    # 사진 경로는 싣지 않는다(COMMON §3, 2026-10-12 보안 점검 #18) — 계정 id 로 Storage 폴더를 찾는다.
    client, captured = _mock_client()

    await DiscordNotifier(WEBHOOK_URL, client).notify_orphaned_file(PROFILE_ID)

    assert json.loads(captured["body"]) == {
        "content": (
            f"학생증 사진 삭제가 실패해 고아 파일이 남았어요 (계정: {PROFILE_ID}). "
            "Storage student-id-temp 에서 그 계정 폴더를 손으로 지워 주세요."
        )
    }
    assert list(inspect.signature(DiscordNotifier.notify_orphaned_file).parameters) == ["self", "profile_id"]


# 웹훅 주소에는 토큰이 들어 있다. httpx 의 raise_for_status 예외 문구에는 주소가 통째로 실려
# 로그에 남는다(2026-10-12 보안 점검 #9) — 상태 코드 · 예외 이름만 남기고 삼킨다.
SECRET_WEBHOOK_URL = "https://discord.com/api/webhooks/123/SECRET-TOKEN"
SENDS = {
    "pending_review": lambda notifier: notifier.notify_pending_review("vision_error", PROFILE_ID),
    "orphaned_file": lambda notifier: notifier.notify_orphaned_file(PROFILE_ID),
    "missing_fallback_avatar": lambda notifier: notifier.notify_missing_fallback_avatar("defaults/fallback-avatar.png"),
}


@pytest.mark.parametrize("reply", [httpx.Response(429), httpx.Response(500, json={"message": "boom"}),
                                   httpx.ConnectError("down")], ids=["429", "500", "connect"])
@pytest.mark.parametrize("send", SENDS.values(), ids=SENDS.keys())
async def test_a_failed_notice_is_swallowed_and_never_logs_the_webhook_address(reply, send, caplog):
    def handler(request: httpx.Request) -> httpx.Response:
        if isinstance(reply, Exception):
            raise reply
        return reply

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    with caplog.at_level(logging.WARNING):
        await send(DiscordNotifier(SECRET_WEBHOOK_URL, client))

    assert caplog.records, "실패는 로그에 남아야 한다"
    assert "SECRET-TOKEN" not in caplog.text
    assert "webhooks" not in caplog.text
    if isinstance(reply, httpx.Response):
        assert f"status={reply.status_code}" in caplog.text


# 설정 오류 모양의 주소(시크릿 끝의 줄바꿈 · 잘못된 포트). httpx.InvalidURL 은 HTTPError 하위가 아니라 따로 잡아야 한다.
@pytest.mark.parametrize("webhook_url", [SECRET_WEBHOOK_URL + "\n", "https://discord.com:abc/api/webhooks/123/SECRET-TOKEN"],
                         ids=["trailing_newline", "bad_port"])
async def test_a_malformed_webhook_address_is_swallowed_and_never_logged(webhook_url, caplog):
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(204)))

    with caplog.at_level(logging.WARNING):
        await DiscordNotifier(webhook_url, client).notify_pending_review("vision_error", PROFILE_ID)

    assert "InvalidURL" in caplog.text
    assert "SECRET-TOKEN" not in caplog.text
    assert "webhooks" not in caplog.text


async def test_graduate_orphan_notice_names_the_graduate_bucket_and_carries_only_the_account_id():
    client, captured = _mock_client()

    await DiscordNotifier(WEBHOOK_URL, client).notify_graduate_orphaned_file(PROFILE_ID)

    assert json.loads(captured["body"]) == {
        "content": (
            f"졸업생 인증 사진 삭제가 실패해 고아 파일이 남았어요 (계정: {PROFILE_ID}). "
            "Storage graduate-cert-temp 에서 그 계정 폴더를 손으로 지워 주세요."
        )
    }


async def test_notify_graduate_request_carries_ids_only():
    client, captured = _mock_client()
    request_id = UUID("22222222-2222-2222-2222-222222222222")

    await DiscordNotifier(WEBHOOK_URL, client).notify_graduate_request(request_id, PROFILE_ID)

    body = captured["body"].decode("utf-8")
    assert captured["url"] == WEBHOOK_URL
    assert "졸업생 인증 신청" in body
    assert str(request_id) in body and str(PROFILE_ID) in body
