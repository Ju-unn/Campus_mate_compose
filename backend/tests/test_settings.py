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


def test_settings_requires_all_values(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    with pytest.raises(Exception):
        Settings(_env_file=None)
