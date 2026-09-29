import pytest
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


def test_settings_requires_all_values(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    with pytest.raises(Exception):
        Settings(_env_file=None)
