"""profile_private 읽기 단일 지점(core/postgrest.PostgrestRepository._read_private)."""
import logging

import httpx
import pytest

from app.core.postgrest import PostgrestRepository

URL = "https://x.supabase.co/rest/v1"
KEY = "enc-key-SECRET"
PROFILE = "11111111-1111-1111-1111-111111111111"
PLAINTEXT = "홍길동"


async def test_a_decrypt_failure_is_logged_with_only_the_profile_id_and_status_then_raised(caplog):
    """복호화 RPC 가 실패하면 운영에서 원인을 찾을 한 줄을 남기고, 예외는 삼키지 않고 그대로 올린다.

    줄에는 profile_id 와 상태 코드만 — 키 · 평문 · URL(str(exc) 에 들어 있다) · 응답 본문은 남기지 않는다."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"message": f"{KEY} {PLAINTEXT}"})

    repo = PostgrestRepository(
        URL, "service-key", httpx.AsyncClient(transport=httpx.MockTransport(handler)), encryption_key=KEY
    )

    with caplog.at_level(logging.DEBUG, logger="app.core.postgrest"), pytest.raises(httpx.HTTPStatusError) as raised:
        await repo._read_private(PROFILE, ("kakao_id",))

    assert raised.value.response.status_code == 500
    ours = [r for r in caplog.records if r.name == "app.core.postgrest"]
    assert [r.levelno for r in ours] == [logging.ERROR]
    line = ours[0].getMessage()
    assert line == f"profile_private 복호화 실패 profile_id={PROFILE} status=500"
    for secret in (KEY, PLAINTEXT, "supabase.co", "service-key"):
        assert secret not in caplog.text
