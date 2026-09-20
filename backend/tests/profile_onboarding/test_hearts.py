import httpx

from app.profile_onboarding.hearts import grant_hearts


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
