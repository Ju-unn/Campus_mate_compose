import hashlib
import hmac
import json
import logging

import httpx
import pytest
from app.signup_policy import IDENTITY_KEY_VERSION, SignupPolicy, bytea_literal, hash_email, hash_phone


def test_hash_email_is_deterministic():
    assert hash_email("secret", "hong@snu.ac.kr") == hash_email("secret", "hong@snu.ac.kr")


def test_hash_email_differs_by_secret():
    assert hash_email("secret-a", "hong@snu.ac.kr") != hash_email("secret-b", "hong@snu.ac.kr")


def test_hash_email_normalizes_case():
    assert hash_email("secret", "HONG@SNU.AC.KR") == hash_email("secret", "hong@snu.ac.kr")


def test_hash_phone_is_hmac_sha256_of_the_e164_value_as_given():
    """지인 차단 대조는 서버 두 곳(온보딩 저장 · 연락처 등록)이 같은 바이트를 떠야 맞는다 — 입력을 손대지 않는다."""
    expected = hmac.new(b"secret", b"+821012345678", hashlib.sha256).digest()

    assert hash_phone("secret", "+821012345678") == expected
    assert hash_phone("secret-b", "+821012345678") != expected


def test_identity_key_version_starts_at_one():
    # signup_blocks · profile_private.phone_hmac_key_version · contact_blocks.key_version 의 DB 기본값과 같다.
    assert IDENTITY_KEY_VERSION == 1


def test_bytea_literal_is_the_postgrest_hex_form():
    assert bytea_literal(b"\x9a\x1b\xcd") == "\\x9a1bcd"


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


# 등록되지 않은 학교 메일 도메인 기록(최선만) — 도메인 문자열만 보낸다 ---------------------------------------

async def test_record_unknown_domain_sends_only_the_domain_to_the_db_function(transport_factory):
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    await policy.record_unknown_domain("unknown.ac.kr")

    [request] = seen
    assert request.method == "POST"
    assert request.url.path == "/rest/v1/rpc/record_unknown_email_domain"
    assert json.loads(request.content) == {"p_domain": "unknown.ac.kr"}
    assert request.headers["authorization"] == "Bearer service-key"


async def test_record_unknown_domain_waits_only_a_short_time(transport_factory):
    """거절 응답 안에서 기다리는 호출이다 — 훅 전체가 Supabase Auth HTTP 훅 제한(5초) 안에 들도록 1초로 끊는다."""
    timeouts: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        timeouts.append(request.extensions["timeout"])
        return httpx.Response(204)

    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    await policy.record_unknown_domain("unknown.ac.kr")

    assert all(0 < seconds <= 1.0 for seconds in timeouts[0].values())


def _raise(exc_type):
    def handler(request: httpx.Request) -> httpx.Response:
        raise exc_type("boom", request=request)
    return handler


@pytest.mark.parametrize("handler", [
    lambda request: httpx.Response(500, json={"message": "boom"}),
    lambda request: httpx.Response(404, json={"message": "function not found"}),
    _raise(httpx.ReadTimeout),
    _raise(httpx.ConnectError),
], ids=["500", "404", "timeout", "unreachable"])
async def test_record_unknown_domain_never_raises_and_logs_only_the_domain(transport_factory, handler, caplog):
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    with caplog.at_level(logging.DEBUG):
        await policy.record_unknown_domain("unknown.ac.kr")

    [warning] = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert "unknown.ac.kr" in warning.getMessage()
    # 주소(프로젝트 ref) · 서비스 키는 남기지 않는다(httpx 자체의 요청 줄은 이 경고가 아니다).
    assert "x.supabase.co" not in warning.getMessage()
    assert "service-key" not in caplog.text
