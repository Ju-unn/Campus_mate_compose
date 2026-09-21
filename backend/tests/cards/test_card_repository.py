from datetime import datetime, timedelta, timezone

import httpx

from app.cards.repository import CardRepository

URL = "https://x.supabase.co/rest/v1"


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
    pending = await repo.fetch_pending_acceptances("me")

    assert [p["card_id"] for p in pending] == ["c1"]
    # card_decisions 에서 acceptance_responses 로 바로 가면 PGRST200 이라 daily_cards 를 거쳐야 한다.
    assert "daily_cards!inner(id,owner_id,target_id,acceptance_responses(card_id))" in select[0]
    # 기한은 "7일"이 아니라 실제 시각으로 나가야 한다 — 숫자를 그대로 보내면 PostgREST 가 전부 돌려준다.
    cutoff = datetime.fromisoformat(seen[0].removeprefix("gte."))
    assert abs(cutoff - (datetime.now(timezone.utc) - timedelta(days=7))) < timedelta(minutes=1)


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


async def test_create_match_upserts_so_a_second_accept_does_not_blow_up():
    """A→B, B→A 카드가 같은 날 나가면 양쪽이 각자 매칭을 만들려 한다.
    나중 쪽이 matches_pair_unique 로 500 나지 않게 기존 행을 그대로 받아야 한다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": "match-1"}])

    repo, _ = _repo(handler)
    match = await repo.create_match("bbbb", "aaaa")

    assert match["id"] == "match-1"
    matches, participants = seen[0], seen[1]
    assert matches.url.params["on_conflict"] == "profile_a,profile_b"
    assert "resolution=merge-duplicates" in matches.headers["Prefer"]
    assert "return=representation" in matches.headers["Prefer"]
    assert participants.url.params["on_conflict"] == "match_id,profile_id"
    assert "resolution=merge-duplicates" in participants.headers["Prefer"]
