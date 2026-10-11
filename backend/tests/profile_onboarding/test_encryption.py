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


# 실명 · 카카오톡 아이디 · 복호화 읽기 wrapper(서버 PR 2). 전화번호 wrapper 와 같은 규칙 —
# 암호화는 DB 안(pgcrypto)에서 하고, 키는 JSON 바디로만 간다.
_SETTERS = [
    ("set_encrypted_real_name", "set_real_name", "p_real_name", "홍길동"),
    ("set_encrypted_kakao_id", "set_kakao_id", "p_kakao_id", "fox_rain"),
]


@pytest.mark.parametrize("function, rpc, value_param, value", _SETTERS)
async def test_setter_sends_plaintext_and_key_only_in_the_json_body(function, rpc, value_param, value):
    import app.profile_onboarding.encryption as encryption

    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        return httpx.Response(204)

    async with _client(handler) as client:
        await getattr(encryption, function)(
            "https://x.supabase.co/rest/v1", "service-key", client, PROFILE_ID, value, "phone-key",
        )

    request = sent[0]
    assert str(request.url) == f"https://x.supabase.co/rest/v1/rpc/{rpc}"
    assert json.loads(request.content) == {"p_profile": str(PROFILE_ID), value_param: value, "p_key": "phone-key"}
    # 키 · 평문은 URL(웹서버 접근 로그)에 새면 안 된다.
    assert "phone-key" not in str(request.url) and value not in str(request.url)
    assert request.headers["apikey"] == "service-key"


@pytest.mark.parametrize("function, rpc, value_param, value", _SETTERS)
async def test_setter_raises_on_http_error(function, rpc, value_param, value):
    import app.profile_onboarding.encryption as encryption

    async with _client(lambda request: httpx.Response(404)) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await getattr(encryption, function)(
                "https://x.supabase.co/rest/v1", "service-key", client, PROFILE_ID, value, "phone-key",
            )


async def test_decrypt_profile_private_sends_the_key_in_the_body_and_returns_both_fields():
    from app.profile_onboarding.encryption import decrypt_profile_private

    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        return httpx.Response(200, json=[{"real_name": "홍길동", "kakao_id": "fox_rain"}])

    async with _client(handler) as client:
        result = await decrypt_profile_private(
            "https://x.supabase.co/rest/v1", "service-key", client, PROFILE_ID, "phone-key",
        )

    assert result == {"real_name": "홍길동", "kakao_id": "fox_rain"}
    assert str(sent[0].url) == "https://x.supabase.co/rest/v1/rpc/decrypt_profile_private"
    assert json.loads(sent[0].content) == {"p_profile": str(PROFILE_ID), "p_key": "phone-key"}
    assert "phone-key" not in str(sent[0].url)


@pytest.mark.parametrize("body", [[], None, [{"real_name": None, "kakao_id": None}]])
async def test_decrypt_profile_private_treats_no_row_and_null_columns_alike(body):
    from app.profile_onboarding.encryption import decrypt_profile_private

    async with _client(lambda request: httpx.Response(200, json=body)) as client:
        result = await decrypt_profile_private(
            "https://x.supabase.co/rest/v1", "service-key", client, PROFILE_ID, "phone-key",
        )

    assert result == {"real_name": None, "kakao_id": None}


async def test_decrypt_profile_private_raises_on_http_error():
    from app.profile_onboarding.encryption import decrypt_profile_private

    async with _client(lambda request: httpx.Response(500)) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await decrypt_profile_private(
                "https://x.supabase.co/rest/v1", "service-key", client, PROFILE_ID, "phone-key",
            )
