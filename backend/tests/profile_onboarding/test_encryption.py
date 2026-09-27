import json
from uuid import UUID

import httpx
import pytest

from app.profile_onboarding.encryption import set_encrypted_phone_number
from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_set_encrypted_phone_number_calls_rpc_with_plaintext_key_in_json_body():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["json"] = httpx.Request(request.method, request.url, content=request.content).read()
        captured["headers"] = dict(request.headers)
        return httpx.Response(204)

    async with _client(handler) as client:
        await set_encrypted_phone_number(
            "https://x.supabase.co/rest/v1", "service-key", client,
            PROFILE_ID, "01012345678", "phone-key", identity_key="identity-key",
        )

    assert captured["url"] == "https://x.supabase.co/rest/v1/rpc/set_phone_number"
    # 키는 URL 쿼리스트링이 아니라 JSON 바디로만 넘긴다(접근 로그에 안 남게, 2026-09-20 사용자 승인 조건).
    assert b"phone-key" in captured["json"]
    assert b"01012345678" in captured["json"]
    assert "phone-key" not in captured["url"]
    assert captured["headers"]["apikey"] == "service-key"


async def test_the_rpc_also_stores_the_contact_block_hmac_of_the_saved_e164_value():
    """지인 차단 대조(match_candidates)는 phone_hmac 을 본다 — 저장하는 값 그대로 해시해야 연락처 쪽과 맞는다."""
    sent: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content))
        return httpx.Response(204)

    async with _client(handler) as client:
        await set_encrypted_phone_number(
            "https://x.supabase.co/rest/v1", "service-key", client,
            PROFILE_ID, "+821012345678", "phone-key", identity_key="identity-key",
        )

    assert sent[0]["p_phone_hmac"] == bytea_literal(hash_phone("identity-key", "+821012345678"))
    assert sent[0]["p_phone_hmac_key_version"] == IDENTITY_KEY_VERSION


async def test_set_encrypted_phone_number_raises_on_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500)

    async with _client(handler) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await set_encrypted_phone_number(
                "https://x.supabase.co/rest/v1", "service-key", client,
                PROFILE_ID, "01012345678", "phone-key", identity_key="identity-key",
            )
