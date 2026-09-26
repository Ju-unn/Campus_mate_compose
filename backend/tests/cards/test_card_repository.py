from datetime import datetime, timedelta, timezone

import httpx

from app.cards.repository import CardRepository
from app.core.time import SEOUL

URL = "https://x.supabase.co/rest/v1"
# 기한 계산이 이 시각에서 나온다 — 실제 시계를 읽으면 "1분 안" 같은 어림밖에 못 쓴다.
NOW = datetime(2026, 9, 22, 14, 0, tzinfo=SEOUL)


def _repo(handler) -> tuple[CardRepository, httpx.AsyncClient]:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return CardRepository(URL, "service-key", client), client


async def test_insert_card_sends_owner_target_and_expiry():
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        seen.append(json.loads(request.content))
        return httpx.Response(201, json=[{"id": "card-1"}])

    repo, _ = _repo(handler)
    expires = datetime(2026, 9, 24, 22, 0, tzinfo=timezone.utc)
    card = await repo.insert_card("owner-1", "target-1", expires)

    assert card["id"] == "card-1"
    assert seen[0]["owner_id"] == "owner-1"
    assert seen[0]["target_id"] == "target-1"
    assert seen[0]["source"] == "daily"
    assert seen[0]["expires_at"] == expires.isoformat()


async def test_active_counts_are_grouped_by_region_and_gender():
    def handler(request: httpx.Request) -> httpx.Response:
        assert "/rpc/region_active_counts" in str(request.url)
        return httpx.Response(200, json=[
            {"region_group": "seoul", "gender": "male", "active_count": 12},
            {"region_group": "seoul", "gender": "female", "active_count": 9},
        ])

    repo, _ = _repo(handler)
    assert await repo.fetch_active_counts() == {"seoul": {"male": 12, "female": 9}}


async def test_pending_acceptances_drop_already_answered_ones():
    """7일 안에 받은 수락 중 아직 응답하지 않은 것만 받은 수락함에 보인다(설계 §2.2·§2.4)."""
    seen: list[str] = []

    select: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params["decided_at"])
        select.append(request.url.params["select"])
        # 응답은 daily_cards 안에 one-to-one 으로 붙어 온다(둘 사이에는 FK 가 없다).
        return httpx.Response(200, json=[
            {"card_id": "c1", "decided_at": "2026-09-20T07:00:00+00:00",
             "daily_cards": {"id": "c1", "owner_id": "o1", "target_id": "me",
                             "acceptance_responses": None}},
            {"card_id": "c2", "decided_at": "2026-09-20T07:00:00+00:00",
             "daily_cards": {"id": "c2", "owner_id": "o2", "target_id": "me",
                             "acceptance_responses": {"card_id": "c2"}}},
        ])

    repo, _ = _repo(handler)
    pending = await repo.fetch_pending_acceptances("me", now=NOW)

    assert [p["card_id"] for p in pending] == ["c1"]
    # card_decisions 에서 acceptance_responses 로 바로 가면 PGRST200 이라 daily_cards 를 거쳐야 한다.
    assert "daily_cards!inner(id,owner_id,target_id,acceptance_responses(card_id))" in select[0]
    # 기한은 "7일"이 아니라 실제 시각으로 나가야 한다 — 숫자를 그대로 보내면 PostgREST 가 전부 돌려준다.
    cutoff = datetime.fromisoformat(seen[0].removeprefix("gte."))
    assert cutoff == NOW.astimezone(timezone.utc) - timedelta(days=7)
    # 저장된 값이 UTC 라 보내는 것도 UTC 여야 한다 — KST 로 나가면 9시간 어긋난 목록이 온다.
    assert seen[0].endswith("+00:00")


async def test_create_match_orders_the_pair():
    """matches 는 항상 작은 uuid 가 profile_a 다(C3 체크 제약)."""
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        body = json.loads(request.content)
        seen.append(body if isinstance(body, dict) else body[0])
        return httpx.Response(201, json=[{"id": "match-1"}])

    repo, _ = _repo(handler)
    await repo.create_match("bbbb", "aaaa")

    assert seen[0]["profile_a"] == "aaaa"
    assert seen[0]["profile_b"] == "bbbb"


async def test_live_cards_put_this_cycle_free_cards_before_bought_ones():
    """설계 §2.4 노출 순서. card_source enum 이 ('daily','purchased') 라 source 오름차순이
    곧 [무료 → 구매]다. issued_at 만으로 정렬하면 조각 7 에서 구매 카드가 위로 올라온다."""
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params["order"])
        return httpx.Response(200, json=[])

    repo, _ = _repo(handler)
    await repo.fetch_live_cards("me")

    assert seen[0] == "source.asc,issued_at.desc"


async def test_create_match_says_it_is_new_only_when_it_inserted_a_row():
    """ignore-duplicates 면 실제로 넣은 행만 돌아온다. 빈 응답이 곧 "이미 매칭돼 있었다" 다 —
    부른 쪽은 이걸로 "매칭됐어요" 푸시를 두 번 보내지 않는다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json=[{"id": "match-1"}])
        if "/matches" in request.url.path:
            return httpx.Response(201, json=[])  # on conflict do nothing
        return httpx.Response(201, json=[])

    repo, _ = _repo(handler)
    match, is_new = await repo.create_match("bbbb", "aaaa")

    assert is_new is False
    assert match["id"] == "match-1"


async def test_create_match_raises_409_when_the_reread_comes_back_empty():
    """넣지도 못했는데 되읽기까지 비면(그 사이 매칭이 지워진 경우) 예전에는 IndexError 로 500 이 났다
    — 조각 4 리뷰 권고 1번."""
    import pytest
    from fastapi import HTTPException

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    repo, _ = _repo(handler)
    with pytest.raises(HTTPException) as caught:
        await repo.create_match("bbbb", "aaaa")

    assert caught.value.status_code == 409


async def test_issued_owners_query_has_an_explicit_limit():
    """PostgREST db-max-rows 에 조용히 잘리면 이미 받은 사람이 빠져 카드가 두 번 나간다(권고 2번)."""
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    repo, _ = _repo(handler)
    await repo.fetch_owners_issued_since(datetime(2026, 9, 22, tzinfo=timezone.utc))

    assert int(seen[0]["limit"]) > 0


async def test_create_match_upserts_so_a_second_accept_does_not_blow_up():
    """A→B, B→A 카드가 같은 날 나가면 양쪽이 각자 매칭을 만들려 한다.
    나중 쪽이 matches_pair_unique 로 500 나지 않게 기존 행을 그대로 받아야 한다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": "match-1"}])

    repo, _ = _repo(handler)
    match, is_new = await repo.create_match("bbbb", "aaaa")

    assert (match["id"], is_new) == ("match-1", True)
    matches, participants = seen[0], seen[1]
    assert matches.url.params["on_conflict"] == "profile_a,profile_b"
    assert "resolution=ignore-duplicates" in matches.headers["Prefer"]
    assert "return=representation" in matches.headers["Prefer"]
    assert participants.url.params["on_conflict"] == "match_id,profile_id"
    assert "resolution=merge-duplicates" in participants.headers["Prefer"]


async def test_profile_status_is_read_for_the_push_gate():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[{"status": "suspended"}])

    repo, _ = _repo(handler)

    assert await repo.fetch_profile_status("p1") == "suspended"
    assert seen[0]["id"] == "eq.p1"
    assert seen[0]["select"] == "status"
