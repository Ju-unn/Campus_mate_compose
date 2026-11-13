"""profile_private 읽기 단일 지점(core/postgrest.PostgrestRepository._read_private)."""
import logging

import httpx
import pytest

from app.core.postgrest import POSTGREST_MAX_ROWS, PostgrestRepository, read_all_pages

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


async def test_read_all_pages_logs_how_many_pages_and_rows_it_read(caplog):
    """db-max-rows 넘김 읽기가 운영에서 실제로 몇 쪽 · 몇 줄을 읽었는지 한 줄(배치 하나에 한 번)."""
    pages = [[{"id": i} for i in range(POSTGREST_MAX_ROWS)], [{"id": POSTGREST_MAX_ROWS}], []]

    async def fetch(_params: dict) -> list[dict]:
        return pages.pop(0)

    with caplog.at_level(logging.INFO, logger="app.core.postgrest"):
        rows = await read_all_pages(fetch, "id")

    assert len(rows) == POSTGREST_MAX_ROWS + 1
    assert [r.getMessage() for r in caplog.records if r.name == "app.core.postgrest"] == [
        f"쪽 넘김 읽기 key=id 쪽=3 줄={POSTGREST_MAX_ROWS + 1}"]
