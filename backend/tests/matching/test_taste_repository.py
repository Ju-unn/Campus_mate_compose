import json
import logging

import httpx
import pytest

from app.matching.repository import MatchingRepository

OWNER = "11111111-1111-1111-1111-111111111111"
A, B, C = "aaaaaaaa-0000-0000-0000-000000000001", "bbbbbbbb-0000-0000-0000-000000000002", "cccccccc-0000-0000-0000-000000000003"


def _repo(handler) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


def _world(clashing, taste_status: int = 200, candidates=None, seen: list | None = None):
    candidates = [{"candidate_id": A}, {"candidate_id": B}, {"candidate_id": C}] if candidates is None else candidates

    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        if request.url.path == "/rest/v1/rpc/match_candidates":
            return httpx.Response(200, json=candidates)
        if request.url.path == "/rest/v1/rpc/taste_clash_candidates":
            if isinstance(taste_status, Exception):
                raise taste_status
            return httpx.Response(taste_status, json=clashing)
        return httpx.Response(404)

    return handler


async def test_fetch_candidates_marks_who_clashes_with_the_owner():
    seen: list[httpx.Request] = []

    candidates = await _repo(_world([B], seen=seen)).fetch_candidates(OWNER)

    assert {c["candidate_id"]: c["taste_clash"] for c in candidates} == {A: False, B: True, C: False}
    [taste] = [r for r in seen if r.url.path == "/rest/v1/rpc/taste_clash_candidates"]
    assert json.loads(taste.content) == {"p_owner": OWNER}


async def test_fetch_candidates_keeps_every_other_candidate_field():
    handler = _world([], candidates=[{"candidate_id": A, "trait_score": 0.5, "pickable": True}])

    [candidate] = await _repo(handler).fetch_candidates(OWNER)

    assert candidate == {"candidate_id": A, "trait_score": 0.5, "pickable": True, "taste_clash": False}


async def test_fetch_candidates_asks_for_the_clash_list_once_per_owner_not_per_candidate():
    seen: list[httpx.Request] = []

    await _repo(_world([], seen=seen)).fetch_candidates(OWNER)

    assert len([r for r in seen if r.url.path == "/rest/v1/rpc/taste_clash_candidates"]) == 1


async def test_fetch_candidates_skips_the_clash_rpc_when_nobody_is_a_candidate():
    seen: list[httpx.Request] = []

    assert await _repo(_world([], candidates=[], seen=seen)).fetch_candidates(OWNER) == []
    assert [r.url.path for r in seen] == ["/rest/v1/rpc/match_candidates"]


@pytest.mark.parametrize("failure", [500, 404, httpx.ReadTimeout("slow"), httpx.ConnectError("down")])
async def test_fetch_candidates_treats_a_failed_clash_rpc_as_no_clash(failure, caplog):
    """카드 지급이 멈추면 안 된다 — 함수가 죽으면 부딪힘 감점만 빠지고(전원 False) 후보는 그대로 나온다."""
    with caplog.at_level(logging.WARNING, logger="app.matching.repository"):
        candidates = await _repo(_world([B], taste_status=failure)).fetch_candidates(OWNER)

    assert [c["taste_clash"] for c in candidates] == [False, False, False]
    assert OWNER in caplog.text  # 실패는 로그에 profile_id 만 남긴다


@pytest.mark.parametrize("odd", [{"message": "x"}, "text", 7, None])
async def test_fetch_candidates_treats_an_unexpected_clash_answer_as_no_clash(odd):
    candidates = await _repo(_world(odd)).fetch_candidates(OWNER)

    assert [c["taste_clash"] for c in candidates] == [False, False, False]


async def test_fetch_candidates_still_fails_when_match_candidates_fails():
    """부딪힘은 덤이다 — 기본 후보 조회가 실패한 것까지 삼키면 안 된다(전과 같이 올라온다)."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"message": "boom"})

    with pytest.raises(httpx.HTTPStatusError):
        await _repo(handler).fetch_candidates(OWNER)
