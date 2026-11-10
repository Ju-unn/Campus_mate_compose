"""문자 발송기 — 솔라피 서명 · 실패 판정, 가짜 발송기는 로컬에서만, SMS_PROVIDER 로 고르기."""
import hashlib
import hmac
import json
import logging
import re
from datetime import datetime, timedelta, timezone

import httpx
import pytest

from app.phone_verification.sms import FakeSmsSender, SolapiSmsSender, get_sms_sender
from phone_world import LOCAL_URL, PRODUCTION_URL, settings

TEXT = "[CampusMate] 인증번호 [123456]을 입력해 주세요."
SOLAPI = "https://api.solapi.com/messages/v4/send-many/detail"


def _solapi(handler) -> tuple[SolapiSmsSender, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def wrapped(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return SolapiSmsSender("key-1", "secret-1", "01099998888", client), seen


def _ok(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json={"groupInfo": {"count": {"registeredSuccess": 1}}, "failedMessageList": []})


async def test_solapi_posts_one_message_to_send_many_detail():
    sender, seen = _solapi(_ok)

    assert await sender.send("+821001352468", TEXT) is True

    assert len(seen) == 1 and str(seen[0].url) == SOLAPI and seen[0].method == "POST"
    assert json.loads(seen[0].content) == {"messages": [{"to": "01001352468", "from": "01099998888", "text": TEXT}]}


async def test_solapi_signs_with_hmac_sha256_of_date_and_salt():
    sender, seen = _solapi(_ok)
    await sender.send("+821001352468", TEXT)

    header = seen[0].headers["Authorization"]
    match = re.fullmatch(r"HMAC-SHA256 ApiKey=key-1, Date=(\S+), salt=([0-9a-f]{32}), signature=([0-9a-f]{64})", header)
    assert match, header
    date, salt, signature = match.groups()
    assert signature == hmac.new(b"secret-1", (date + salt).encode(), hashlib.sha256).hexdigest()
    sent_at = datetime.fromisoformat(date.replace("Z", "+00:00"))
    assert sent_at.tzinfo is not None and abs(datetime.now(timezone.utc) - sent_at) < timedelta(minutes=1)


async def test_solapi_salt_changes_every_call():
    sender, seen = _solapi(_ok)
    await sender.send("+821001352468", TEXT)
    await sender.send("+821001352468", TEXT)

    salts = {re.search(r"salt=(\w+)", r.headers["Authorization"])[1] for r in seen}
    assert len(salts) == 2


@pytest.mark.parametrize("status", [400, 401, 403, 500, 503])
async def test_solapi_non_2xx_is_a_failure_and_logs_only_the_status(status, caplog):
    sender, _ = _solapi(lambda request: httpx.Response(status, json={"errorCode": "x", "errorMessage": "01001352468"}))

    with caplog.at_level(logging.WARNING):
        assert await sender.send("+821001352468", TEXT) is False

    logged = " ".join(record.getMessage() for record in caplog.records)
    assert str(status) in logged
    assert "0135" not in logged and "123456" not in logged and "secret-1" not in logged


async def test_solapi_failed_message_list_is_a_failure(caplog):
    sender, _ = _solapi(lambda request: httpx.Response(200, json={
        "failedMessageList": [{"to": "01001352468", "statusCode": "1062", "statusMessage": "발신번호 미등록"}]}))

    with caplog.at_level(logging.WARNING):
        assert await sender.send("+821001352468", TEXT) is False

    assert "0135" not in " ".join(record.getMessage() for record in caplog.records)


async def test_solapi_network_error_and_unreadable_body_are_failures():
    def boom(request):
        raise httpx.ConnectTimeout("timeout", request=request)

    down, _ = _solapi(boom)
    garbled, _ = _solapi(lambda request: httpx.Response(200, content=b"<html>"))

    assert await down.send("+821001352468", TEXT) is False
    assert await garbled.send("+821001352468", TEXT) is False


async def test_fake_sender_keeps_messages_in_memory():
    fake = FakeSmsSender()

    assert await fake.send("+821001352468", TEXT) is True
    assert fake.sent == [("+821001352468", TEXT)]


def _pick(**overrides):
    return get_sms_sender(settings(**overrides), httpx.AsyncClient())


def test_fake_is_the_default_provider_locally():
    assert isinstance(_pick(), FakeSmsSender)


def test_fake_provider_is_refused_in_production(caplog):
    """None = 보낼 수 없다 — 보내기 경로가 줄을 만들기 전에 503 을 준다."""
    with caplog.at_level(logging.ERROR):
        assert _pick(supabase_url=PRODUCTION_URL) is None

    assert any(record.levelno == logging.ERROR for record in caplog.records)


def test_an_unknown_provider_counts_as_fake_and_is_refused_in_production():
    assert _pick(supabase_url=PRODUCTION_URL, sms_provider="solapii") is None


def test_solapi_provider_builds_the_solapi_sender():
    sender = _pick(supabase_url=PRODUCTION_URL, sms_provider="solapi", solapi_api_key="k",
                   solapi_api_secret="s", solapi_sender="01099998888")

    assert isinstance(sender, SolapiSmsSender)


def test_solapi_without_its_keys_cannot_send(caplog):
    with caplog.at_level(logging.ERROR):
        assert _pick(supabase_url=PRODUCTION_URL, sms_provider="solapi", solapi_api_key="k") is None

    assert any(record.levelno == logging.ERROR for record in caplog.records)


@pytest.mark.parametrize(("url", "local"), [
    (LOCAL_URL, True), ("http://localhost:54321", True), ("http://[::1]:54321", True),
    (PRODUCTION_URL, False), ("https://127.0.0.1.example.com", False), ("https://example.supabase.co", False),
])
def test_runs_locally_only_for_a_loopback_supabase(url, local):
    assert settings(supabase_url=url).runs_locally is local


def test_phone_verification_is_not_required_by_default():
    """심사 중인 앱(인증 없이 번호를 보냄)이 막히지 않게 — 서버가 먼저 나가고 옛 앱을 받아야 한다."""
    assert settings().phone_verification_required is False
    assert settings().sms_provider == "fake"
