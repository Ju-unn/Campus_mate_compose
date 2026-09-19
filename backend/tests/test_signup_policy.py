import httpx
import pytest
from app.signup_policy import SignupPolicy, hash_email


def test_hash_email_is_deterministic():
    assert hash_email("secret", "hong@snu.ac.kr") == hash_email("secret", "hong@snu.ac.kr")


def test_hash_email_differs_by_secret():
    assert hash_email("secret-a", "hong@snu.ac.kr") != hash_email("secret-b", "hong@snu.ac.kr")


def test_hash_email_normalizes_case():
    assert hash_email("secret", "HONG@SNU.AC.KR") == hash_email("secret", "hong@snu.ac.kr")


@pytest.fixture
def transport_factory():
    def _factory(handler):
        return httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return _factory


async def test_find_university_id_returns_id_when_domain_known(transport_factory):
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["domain"] == "eq.snu.ac.kr"
        return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])

    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    result = await policy.find_university_id("snu.ac.kr")

    assert result == "22222222-2222-2222-2222-222222222222"


async def test_find_university_id_returns_none_when_domain_unknown(transport_factory):
    handler = lambda request: httpx.Response(200, json=[])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.find_university_id("unknown.ac.kr") is None


async def test_is_blocked_true_when_row_exists(transport_factory):
    handler = lambda request: httpx.Response(200, json=[{"blocked_until": "2027-01-01T00:00:00Z"}])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.is_blocked(b"\x01\x02") is True


async def test_is_blocked_false_when_no_row(transport_factory):
    handler = lambda request: httpx.Response(200, json=[])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.is_blocked(b"\x01\x02") is False
