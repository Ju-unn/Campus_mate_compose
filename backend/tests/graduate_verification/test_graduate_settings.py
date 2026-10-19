from app.graduate_verification.settings import graduate_enabled


def test_graduate_enabled_defaults_off(monkeypatch):
    monkeypatch.delenv("GRADUATE_VERIFICATION_ENABLED", raising=False)

    assert graduate_enabled() is False


def test_graduate_enabled_reads_the_env_flag(monkeypatch):
    monkeypatch.setenv("GRADUATE_VERIFICATION_ENABLED", "true")
    assert graduate_enabled() is True

    monkeypatch.setenv("GRADUATE_VERIFICATION_ENABLED", "false")
    assert graduate_enabled() is False
