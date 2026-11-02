import logging

import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_settings
from app.main import app
from app.settings import Settings


def _settings(**extra: str) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        **extra,
    )


def _ask(min_app_version: str | None = None):
    extra = {} if min_app_version is None else {"min_app_version": min_app_version}
    app.dependency_overrides[get_settings] = lambda: _settings(**extra)
    try:
        # 인증 헤더 없이 부른다 — 로그인 전 시작 화면에서 쓰는 공개 경로다.
        return TestClient(app).get("/app/version")
    finally:
        app.dependency_overrides.clear()


def test_the_default_blocks_nobody():
    response = _ask()

    assert response.status_code == 200
    assert response.json() == {"min_version": None}


def test_an_empty_value_blocks_nobody():
    assert _ask("").json() == {"min_version": None}


def test_a_set_value_is_returned_as_it_is():
    assert _ask("1.0.1").json() == {"min_version": "1.0.1"}


def test_surrounding_spaces_are_trimmed():
    # Cloud Run 콘솔에 손으로 붙여 넣을 때 따라오는 공백.
    assert _ask(" 1.0.10\n").json() == {"min_version": "1.0.10"}


@pytest.mark.parametrize("bad", ["1.0", "v1.0.1", "1.0.1+19", "1.0.x", "latest", "1.0.1.2", "-1.0.1", "١.٠.١"])
def test_a_malformed_value_blocks_nobody_and_is_warned(bad, caplog):
    # 잘못 적어 부팅이 멈추면 서버 전체가 죽는다. 막지 않는 쪽이 안전하다 — 대신 로그로 알린다.
    with caplog.at_level(logging.WARNING):
        response = _ask(bad)

    assert response.status_code == 200
    assert response.json() == {"min_version": None}
    assert "MIN_APP_VERSION" in caplog.text


def test_the_answer_may_be_cached_for_a_short_time():
    assert _ask("1.0.1").headers["Cache-Control"] == "public, max-age=300"
