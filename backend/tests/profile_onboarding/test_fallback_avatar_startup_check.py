"""서버가 뜰 때 기본 아바타 원본(`avatars/defaults/fallback-avatar.png`)이 있는지 보고, 없으면 눈에 띄게 알린다.

결함 D-02 — 운영 버킷에 이 파일이 없으면 5번째 아바타 실패 보상이 복사에서 멈추는데, 겉으로는
조용하다. 알리는 것(로그 ERROR + Discord)까지만 하고 **서버를 못 뜨게 막지는 않는다** — 가입 말고
나머지 기능은 이 파일 없이도 멀쩡하다.
"""
import asyncio
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient

from app import main as app_main
from app.profile_onboarding import startup_check
from app.profile_onboarding.startup_check import warn_if_fallback_avatar_missing
from app.settings import Settings

PATH = "defaults/fallback-avatar.png"
WEBHOOK = "https://discord.com/api/webhooks/test"


def _settings() -> Settings:
    return Settings(
        supabase_url="https://example.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="s", identity_hmac_key="k", discord_webhook_url=WEBHOOK,
        google_cloud_project="p", openai_api_key="o", phone_encryption_key="e",
    )


def _client(listed, requests: list[httpx.Request], discord_status: int = 204) -> httpx.AsyncClient:
    """`listed` 는 목록 응답 본문(리스트) · 응답 객체 · 던질 예외 · 안 끝나는 코루틴 중 하나."""

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if str(request.url) == WEBHOOK:
            return httpx.Response(discord_status)
        assert str(request.url) == "https://example.supabase.co/storage/v1/object/list/avatars"
        if isinstance(listed, Exception):
            raise listed
        if listed == "hang":
            await asyncio.sleep(60)
        if isinstance(listed, httpx.Response):
            return listed
        return httpx.Response(200, json=listed)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def _discord_posts(requests: list[httpx.Request]) -> list[httpx.Request]:
    return [r for r in requests if str(r.url) == WEBHOOK]


async def test_missing_source_is_logged_as_error_and_sent_to_discord(caplog):
    requests: list[httpx.Request] = []
    async with _client([], requests) as client:
        with caplog.at_level(logging.ERROR):
            await warn_if_fallback_avatar_missing(_settings(), client)

    errors = [r for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1 and PATH in errors[0].getMessage()
    posts = _discord_posts(requests)
    assert len(posts) == 1 and PATH in posts[0].content.decode()


async def test_listing_request_targets_the_defaults_folder_with_the_service_key():
    """prefix 가 틀리면 매 부팅 거짓 경보, 키가 빠지면 늘 읽기 실패 — 둘 다 겉으로 조용해서 요청 모양을 못박는다."""
    requests: list[httpx.Request] = []
    async with _client([{"name": "fallback-avatar.png"}], requests) as client:
        await warn_if_fallback_avatar_missing(_settings(), client)

    (listing,) = requests
    assert json.loads(listing.content)["prefix"] == "defaults"
    assert listing.headers["Authorization"] == "Bearer service-key"
    assert listing.headers["apikey"] == "service-key"


async def test_present_source_is_silent(caplog):
    requests: list[httpx.Request] = []
    async with _client([{"name": "fallback-avatar.png", "id": "o1"}], requests) as client:
        with caplog.at_level(logging.DEBUG):
            await warn_if_fallback_avatar_missing(_settings(), client)

    assert not [r for r in caplog.records if r.levelno >= logging.WARNING]
    assert _discord_posts(requests) == []


async def test_a_different_file_in_the_folder_does_not_count(caplog):
    requests: list[httpx.Request] = []
    async with _client([{"name": "other.png", "id": "o2"}], requests) as client:
        await warn_if_fallback_avatar_missing(_settings(), client)

    assert len(_discord_posts(requests)) == 1


@pytest.mark.parametrize("listed", [
    httpx.Response(500, json={"message": "boom"}),
    httpx.Response(500, json=[]),  # 본문이 빈 목록이어도 상태 코드가 500 이면 "없다"가 아니다
    httpx.ConnectError("dns"),
])
async def test_unreadable_listing_only_warns_and_never_raises(listed, caplog):
    """목록을 못 읽은 것은 "없다"가 아니다 — 거짓 경보를 Discord 로 보내지 않는다."""
    requests: list[httpx.Request] = []
    async with _client(listed, requests) as client:
        with caplog.at_level(logging.WARNING):
            await warn_if_fallback_avatar_missing(_settings(), client)

    assert [r for r in caplog.records if r.levelno == logging.WARNING]
    assert not [r for r in caplog.records if r.levelno >= logging.ERROR]
    assert _discord_posts(requests) == []


async def test_discord_failure_does_not_raise_and_error_is_still_logged(caplog):
    requests: list[httpx.Request] = []
    async with _client([], requests, discord_status=500) as client:
        with caplog.at_level(logging.ERROR):
            await warn_if_fallback_avatar_missing(_settings(), client)

    assert any(PATH in r.getMessage() for r in caplog.records if r.levelno == logging.ERROR)


async def test_a_hanging_storage_call_is_cut_off(monkeypatch, caplog):
    monkeypatch.setattr(startup_check, "CHECK_TIMEOUT_SECONDS", 0.05)
    requests: list[httpx.Request] = []
    async with _client("hang", requests) as client:
        with caplog.at_level(logging.WARNING):
            await asyncio.wait_for(warn_if_fallback_avatar_missing(_settings(), client), timeout=5)

    assert [r for r in caplog.records if r.levelno == logging.WARNING]


# ── 실제 lifespan: 어떤 경우에도 서버는 뜬다 ─────────────────────────────────────────────


@pytest.fixture
def real_check(monkeypatch):
    """conftest 가 다른 부팅 테스트용으로 꺼 둔 확인을 되살린다."""
    monkeypatch.setattr(app_main, "warn_if_fallback_avatar_missing", warn_if_fallback_avatar_missing)


@pytest.mark.parametrize("failure", [RuntimeError("boom"), "hang"])
def test_boot_survives_a_failing_or_hanging_check(real_check, monkeypatch, failure):
    async def fake_exists(self):
        if failure == "hang":
            await asyncio.sleep(60)
        raise failure

    monkeypatch.setattr(startup_check, "CHECK_TIMEOUT_SECONDS", 0.05)
    monkeypatch.setattr(startup_check.AvatarStorage, "fallback_exists", fake_exists)

    with TestClient(app_main.app) as test_client:
        assert test_client.get("/health").status_code == 200


def test_boot_survives_a_missing_source_and_a_broken_discord(real_check, monkeypatch, caplog):
    async def missing(self):
        return False

    async def broken(self, *args):
        raise RuntimeError("discord down")

    monkeypatch.setattr(startup_check.AvatarStorage, "fallback_exists", missing)
    monkeypatch.setattr(startup_check.DiscordNotifier, "notify_missing_fallback_avatar", broken)

    with caplog.at_level(logging.ERROR):
        with TestClient(app_main.app) as test_client:
            assert test_client.get("/health").status_code == 200
            # 종료 뒤가 아니라 **떠 있는 동안**(= 시작 때) 이미 알렸어야 한다.
            assert any(PATH in r.getMessage() for r in caplog.records if r.levelno == logging.ERROR)
