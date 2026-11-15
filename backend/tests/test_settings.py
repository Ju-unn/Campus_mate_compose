import pytest
from pydantic import ValidationError

from app.settings import Settings


def test_settings_reads_from_env(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-key")
    monkeypatch.setenv("AUTH_HOOK_SIGNING_SECRET", "whsec_test")
    monkeypatch.setenv("IDENTITY_HMAC_KEY", "identity-key-test")
    monkeypatch.setenv("DISCORD_WEBHOOK_URL", "https://discord.com/api/webhooks/test")
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "campus-mate-test")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("PHONE_ENCRYPTION_KEY", "phone-key-test")

    settings = Settings()

    assert settings.supabase_url == "https://example.supabase.co"
    assert settings.postgrest_url == "https://example.supabase.co/rest/v1"
    assert settings.auth_url == "https://example.supabase.co/auth/v1"
    assert settings.storage_url == "https://example.supabase.co/storage/v1"
    assert settings.discord_webhook_url == "https://discord.com/api/webhooks/test"
    assert settings.google_cloud_project == "campus-mate-test"
    assert settings.identity_hmac_key == "identity-key-test"


def test_a_leftover_card_batch_secret_env_does_not_stop_boot(monkeypatch):
    """공유 열쇠를 지운 뒤 첫 배포는 `--source` 로만 올라가서 서비스에 옛 `CARD_BATCH_SECRET` 참조가
    남는다(DEPLOY.md §4-3). 모르는 env 는 읽지 않고 넘어가야 서버가 뜬다(`.env` 파일은 읽지 않는다)."""
    monkeypatch.setenv("CARD_BATCH_SECRET", "old")

    assert "card_batch_secret" not in Settings().model_dump()


def test_leftover_store_rating_env_does_not_stop_boot(monkeypatch):
    """홈 리뷰 띠 평점은 이제 실제 스토어에서 읽는다(home/store_ratings.py) — 사람이 넣던 `STORE_RATING` ·
    `STORE_RATING_COUNT` 칸은 지웠다. 운영 Cloud Run 에 두 env 가 남아 있어도 서버는 떠야 한다.
    Settings 는 extra='forbid' 지만 env_file 이 없고, env 원천은 선언한 칸 이름만 읽어 모르는 env 는 무시한다."""
    assert Settings.model_config.get("extra") == "forbid" and Settings.model_config.get("env_file") is None
    monkeypatch.setenv("STORE_RATING", "five")
    monkeypatch.setenv("STORE_RATING_COUNT", "1.5")

    settings = Settings()

    assert not hasattr(settings, "store_rating") and not hasattr(settings, "store_rating_count")


def test_settings_requires_all_values(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    with pytest.raises(Exception):
        Settings(_env_file=None)


@pytest.mark.parametrize("name", [
    "SUPABASE_SERVICE_ROLE_KEY", "AUTH_HOOK_SIGNING_SECRET", "OPENAI_API_KEY", "DISCORD_WEBHOOK_URL",
    "IDENTITY_HMAC_KEY", "PHONE_ENCRYPTION_KEY",
])
def test_an_empty_secret_stops_boot(monkeypatch, name):
    """`KEY=` 처럼 빈 값으로 배포되면 서버가 뜨지 않아야 한다 — 뜨고 나면 서명 검증 · DB 호출 · 알림이 첫 요청부터 조용히 틀어진다."""
    monkeypatch.setenv(name, "")

    with pytest.raises(ValidationError) as caught:
        Settings()

    assert [error["loc"] for error in caught.value.errors()] == [(name.lower(),)]


def test_min_app_version_is_empty_by_default_and_a_bad_value_does_not_stop_boot(monkeypatch):
    """최소 앱 버전은 사람이 Cloud Run 에 손으로 넣는다. 비면 아무도 막지 않고, 형식이 틀려도 `Settings()` 는 죽지 않는다
    (검사는 `GET /app/version` 이 한다 — 위 평점 값과 같은 이유)."""
    monkeypatch.delenv("MIN_APP_VERSION", raising=False)
    assert Settings().min_app_version == ""

    monkeypatch.setenv("MIN_APP_VERSION", "one.zero.one")
    assert Settings().min_app_version == "one.zero.one"
