"""앱을 띄우는 테스트가 쓰는 필수 환경변수.

lifespan 이 부팅 때 `Settings()` 를 만든다(main.py) — `dependency_overrides` 는 요청 의존성에만
걸리고 lifespan 안의 직접 호출에는 걸리지 않는다. 그래서 `with TestClient(app)` 로 도는 테스트는
진짜 환경변수가 있어야 한다. 테스트마다 setenv 하지 않고 여기 한 곳에서 채운다.
"""
import pytest

_REQUIRED_ENV = {
    "SUPABASE_URL": "https://example.supabase.co",
    "SUPABASE_SERVICE_ROLE_KEY": "service-key",
    "AUTH_HOOK_SIGNING_SECRET": "whsec_test",
    "IDENTITY_HMAC_KEY": "identity-key-test",
    "DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/test",
    "GOOGLE_CLOUD_PROJECT": "campus-mate-test",
    "OPENAI_API_KEY": "sk-test",
    "PHONE_ENCRYPTION_KEY": "phone-key-test",
}


@pytest.fixture(scope="session", autouse=True)
def required_env():
    # 세션 스코프라 monkeypatch 픽스처(함수 스코프)를 쓸 수 없다.
    patch = pytest.MonkeyPatch()
    for key, value in _REQUIRED_ENV.items():
        patch.setenv(key, value)
    yield
    patch.undo()
