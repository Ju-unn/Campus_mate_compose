import json

import httpx
import pytest

from app.profile_onboarding.hearts import grant_hearts, spend_hearts


async def test_grant_hearts_calls_rpc_with_amount_reason_and_ref_id():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["json"] = request.content
        captured["headers"] = dict(request.headers)
        return httpx.Response(200)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await grant_hearts(
            "https://x.supabase.co/rest/v1", "service-key", client,
            profile_id="00000000-0000-0000-0000-0000000000aa",
            amount=10, reason="admin_adjust",
        )

    assert captured["url"] == "https://x.supabase.co/rest/v1/rpc/grant_hearts"
    assert b'"p_amount":10' in captured["json"]
    assert b'"p_reason":"admin_adjust"' in captured["json"]
    assert b'"p_ref_id":null' in captured["json"]
    assert captured["headers"]["apikey"] == "service-key"


async def test_grant_hearts_passes_ref_id_when_given():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["json"] = request.content
        return httpx.Response(200)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await grant_hearts(
            "https://x.supabase.co/rest/v1", "service-key", client,
            profile_id="00000000-0000-0000-0000-0000000000aa",
            amount=-5, reason="avatar_regen", ref_id="00000000-0000-0000-0000-0000000000bb",
        )

    assert b'"p_ref_id":"00000000-0000-0000-0000-0000000000bb"' in captured["json"]


async def test_spend_hearts_sends_a_negative_amount_and_says_it_spent():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["json"] = json.loads(request.content)
        return httpx.Response(200)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        spent = await spend_hearts(
            "https://x.supabase.co/rest/v1", "service-key", client,
            profile_id="00000000-0000-0000-0000-0000000000aa",
            amount=10, reason="avatar_regen", ref_id="00000000-0000-0000-0000-0000000000bb",
        )

    assert spent is True
    # 쓰기 함수를 따로 만들지 않고 grant_hearts 에 음수를 넣는다(계획서 3절).
    assert captured["url"] == "https://x.supabase.co/rest/v1/rpc/grant_hearts"
    assert captured["json"] == {
        "p_profile_id": "00000000-0000-0000-0000-0000000000aa", "p_amount": -10,
        "p_reason": "avatar_regen", "p_ref_id": "00000000-0000-0000-0000-0000000000bb",
    }


async def test_spend_hearts_says_no_when_the_balance_check_fails():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"code": "23514", "message": "entitlements_balance_non_negative"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        spent = await spend_hearts(
            "https://x.supabase.co/rest/v1", "service-key", client,
            profile_id="00000000-0000-0000-0000-0000000000aa", amount=10, reason="avatar_regen",
        )

    assert spent is False


async def test_spend_hearts_raises_on_any_other_failure():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"message": "boom"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await spend_hearts(
                "https://x.supabase.co/rest/v1", "service-key", client,
                profile_id="00000000-0000-0000-0000-0000000000aa", amount=10, reason="avatar_regen",
            )
