import logging
import random
from datetime import datetime

import httpx
from fastapi import HTTPException

from app.cards.issuing import issue_daily_cards
from app.core.time import SEOUL
from app.matching.repository import MatchingRepository
from paid_world import OfferStore

MONDAY_7AM = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)     # 월요일
TUESDAY_7AM = datetime(2026, 9, 22, 7, 0, tzinfo=SEOUL)    # 화요일


class _FakeCardRepo(OfferStore):
    def __init__(self, owners, counts=None, settings=None, issued_today=(), offers=None, hidden_profiles=None):
        super().__init__(offers=offers, hidden_profiles=hidden_profiles)
        self._owners = owners
        self._issued_today = set(issued_today)
        # 기본은 주 2회 칸(적은 쪽 50 이상) — 아래 테스트들이 월 · 목 지급을 전제로 한다.
        self._counts = counts or {"seoul": {"male": 60, "female": 60}}
        self._settings = settings or [{
            "region_group": "seoul", "issue_weekdays": [1, 4], "issue_time": "07:00",
            "ladder_twice_per_week_min": 50, "ladder_three_per_week_min": 500,
            "ladder_four_per_week_min": 1000, "ladder_daily_min": 2000,
        }]
        self.cards: list[dict] = []
        self.saved_weekdays: list[tuple] = []

    async def fetch_region_settings(self):
        return self._settings

    async def fetch_active_counts(self):
        return self._counts

    async def fetch_issue_owners(self):
        return self._owners

    async def fetch_owners_issued_since(self, since):
        self.issued_since = since
        return set(self._issued_today)

    async def save_issue_weekdays(self, region_group, weekdays):
        self.saved_weekdays.append((region_group, weekdays))

    async def insert_card(self, owner_id, target_id, expires_at, source="daily"):
        card = {"id": f"card-{len(self.cards)}", "owner_id": owner_id,
                "target_id": target_id, "expires_at": expires_at}
        self.cards.append(card)
        # 진짜 DB 처럼 오늘 받은 사람으로 남는다 — 같은 날 배치를 다시 돌리면 건너뛴다.
        self._issued_today.add(owner_id)
        return card

    async def fetch_card_profile(self, profile_id):
        return {"nickname": "여우비"}

    async def fetch_profile_status(self, profile_id):
        return "active"

    async def fetch_push_tokens(self, profile_id):
        return []

    async def fetch_notification_settings(self, profile_id):
        return {"card_arrived": True, "quiet_hours": True}


class _FakeMatchingRepo:
    def __init__(self, candidates):
        self._candidates = candidates

    async def fetch_owner(self, profile_id):
        return {"id": profile_id, "status": "active", "gender": "male", "mbti": None,
                "preferred_mbti_flags": {}, "height_cm": 180, "preferred_height_min": None,
                "preferred_height_max": None, "birth_year": 2002, "preferred_age_min": None,
                "preferred_age_max": None, "is_smoker": False, "religion": "none"}

    async def fetch_candidates(self, profile_id):
        return list(self._candidates)


def _candidate(candidate_id: str, trait_score: float, pickable: bool = True) -> dict:
    return {"candidate_id": candidate_id, "trait_score": trait_score, "tag_score": 0.0,
            "text_score": 0.0, "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
            "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
            "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False,
            "religion": "none", "last_active_at": "2026-09-21T00:00:00+00:00",
            "pickable": pickable}


# 유료 제안이 한 명을 미리 가져가므로(지시문 22 B), 무료 카드를 보려면 후보가 둘 이상이어야 한다.
TWO = [_candidate("high", 0.9), _candidate("next", 0.8)]


def _many(n: int, pickable=lambda i: True) -> list[dict]:
    """점수가 i 순서대로 내려가는 n 명(c0000 이 1등)."""
    return [_candidate(f"c{i:04d}", 1 - i / (n + 1), pickable(i)) for i in range(n)]


def _old_offer(target_id: str, cycle: datetime = MONDAY_7AM, band_count: int = 5) -> dict:
    return {"id": "offer-old", "owner_id": "owner-1", "cycle_started_at": cycle.isoformat(),
            "target_id": target_id, "reasons": [], "band_count": band_count, "status": "offered",
            "purchased_card_id": None}


async def test_issues_one_card_from_the_band_not_always_the_top():
    """1등을 그대로 주지 않는다 — 상위 80% 구간 안에서 고르고, 시드를 바꾸면 다른 사람이 나온다."""
    picked = set()
    for seed in range(30):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
        result = await issue_daily_cards(repo, _FakeMatchingRepo(_many(50)), sender=None,
                                         now=MONDAY_7AM, rng=random.Random(seed))
        assert result["issued"] == 1
        picked.add(repo.cards[0]["target_id"])

    assert picked <= {f"c{i:04d}" for i in range(40)}  # 50명의 80% = 40명
    assert len(picked) > 5


async def test_a_seeded_batch_is_repeatable():
    results = []
    for _ in range(2):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
        await issue_daily_cards(repo, _FakeMatchingRepo(_many(50)), sender=None,
                                now=MONDAY_7AM, rng=random.Random(7))
        results.append((repo.cards[0]["target_id"], repo.offers[0]["target_id"]))

    assert results[0] == results[1]


async def test_unpickable_people_rank_but_are_never_issued():
    """이미 본 사람(pickable=False)도 순위에는 들어가고 뽑히지는 않는다."""
    for seed in range(20):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
        await issue_daily_cards(repo, _FakeMatchingRepo(_many(10, lambda i: i in (6, 7))), sender=None,
                                now=MONDAY_7AM, rng=random.Random(seed))
        # 10명의 80% = 8명 구간 중 뽑을 수 있는 사람은 c0006 · c0007 뿐이다. 유료 구간(5명)은 비어 있다.
        assert repo.cards[0]["target_id"] in {"c0006", "c0007"}
        assert repo.offers == []


async def test_the_paid_offer_target_is_never_the_free_card():
    for seed in range(30):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
        # 두 구간에 다 드는 사람은 c0000 · c0001 둘뿐 — 유료가 한 명을 가져가면 무료는 다른 한 명이다.
        await issue_daily_cards(repo, _FakeMatchingRepo(_many(10, lambda i: i < 2)), sender=None,
                                now=MONDAY_7AM, rng=random.Random(seed))
        assert len(repo.offers) == 1
        assert repo.cards[0]["target_id"] != repo.offers[0]["target_id"]


async def test_a_paid_offer_is_made_even_without_a_free_card():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    # 뽑을 사람이 c0000 한 명 — 유료 제안이 가져가면 무료로 줄 사람이 없다.
    result = await issue_daily_cards(repo, _FakeMatchingRepo(_many(10, lambda i: i == 0)), sender=None,
                                     now=MONDAY_7AM, rng=random.Random(0))

    assert result == {"issued": 0, "no_candidate": 1, "skipped_regions": [], "failed": 0}
    assert [(o["owner_id"], o["target_id"], o["status"]) for o in repo.offers] == [
        ("owner-1", "c0000", "offered")]
    assert repo.offers[0]["cycle_started_at"] == MONDAY_7AM.isoformat()
    assert repo.offers[0]["band_count"] == 1


async def test_running_the_batch_twice_the_same_day_keeps_one_card_and_one_offer_each():
    owners = [{"profile_id": "owner-1", "region_group": "seoul"},
              {"profile_id": "owner-2", "region_group": "seoul"}]
    repo = _FakeCardRepo(owners)

    class _PerOwner(_FakeMatchingRepo):
        async def fetch_candidates(self, profile_id):
            # owner-2 는 뽑을 사람이 한 명뿐이라 무료 카드가 없다 — 다시 돌리면 다시 대상이 된다.
            return _many(20) if profile_id == "owner-1" else _many(10, lambda i: i == 0)

    for seed in (1, 2):
        await issue_daily_cards(repo, _PerOwner([]), sender=None, now=MONDAY_7AM, rng=random.Random(seed))

    assert [c["owner_id"] for c in repo.cards] == ["owner-1"]
    assert sorted(o["owner_id"] for o in repo.offers) == ["owner-1", "owner-2"]
    assert repo.inserts == 2


async def test_a_target_who_lost_eligibility_gets_a_new_offer_in_the_batch():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}], offers=[_old_offer("c0001")],
                         hidden_profiles={"c0001": {"status": "suspended"}})

    await issue_daily_cards(repo, _FakeMatchingRepo(_many(50)), sender=None, now=MONDAY_7AM,
                            rng=random.Random(3))

    assert [o["id"] for o in repo.by_status("replaced")] == ["offer-old"]
    [live] = repo.by_status("offered")
    assert live["target_id"] != "c0001"
    assert repo.cards[0]["target_id"] != live["target_id"]


async def test_an_unbought_offer_expires_on_the_next_cycle():
    last_cycle = datetime(2026, 9, 17, 7, 0, tzinfo=SEOUL)  # 지난 목요일
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}],
                         offers=[_old_offer("c0001", cycle=last_cycle)])

    await issue_daily_cards(repo, _FakeMatchingRepo(_many(50)), sender=None, now=MONDAY_7AM,
                            rng=random.Random(3))

    assert [o["id"] for o in repo.by_status("expired")] == ["offer-old"]
    [live] = repo.by_status("offered")
    assert live["cycle_started_at"] == MONDAY_7AM.isoformat()


async def test_a_live_offer_this_cycle_is_kept_and_excluded_from_the_free_card():
    for seed in range(20):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}],
                             offers=[_old_offer("c0000", band_count=2)])
        await issue_daily_cards(repo, _FakeMatchingRepo(_many(10, lambda i: i < 2)), sender=None,
                                now=MONDAY_7AM, rng=random.Random(seed))
        assert [o["id"] for o in repo.offers] == ["offer-old"]
        assert repo.cards[0]["target_id"] == "c0001"


# 후보 1,000명 제한(지시문 22 H) ------------------------------------------------------------------

def _postgrest_with(candidates: list[dict], seen: list[httpx.Request]) -> MatchingRepository:
    """진짜 MatchingRepository 를 가짜 PostgREST(경로로 가른다) 위에 올린다."""
    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path == "/rest/v1/rpc/match_candidates":
            # DB 계약 1: jsonb 배열 한 덩어리 — 행 수 상한(db-max-rows 1000)에 걸리지 않는다.
            return httpx.Response(200, json=candidates)
        if request.url.path == "/rest/v1/profiles":
            return httpx.Response(200, json=[{
                "id": "owner-1", "status": "active", "gender": "male", "mbti": None,
                "preferred_mbti_flags": {}, "height_cm": 180, "preferred_height_min": None,
                "preferred_height_max": None, "birth_year": 2002, "preferred_age_min": None,
                "preferred_age_max": None, "is_smoker": False, "religion": "none"}])
        return httpx.Response(404)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handle))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


async def test_all_fifteen_hundred_candidates_reach_the_band():
    """1,500명 중 1,000등 밖의 사람만 뽑을 수 있다 — 1,000명에서 잘리면 아무도 못 받는다.
    80% 구간은 1,200명이라 1,000~1,199등이 뽑힌다."""
    seen: list[httpx.Request] = []
    matching = _postgrest_with(_many(1500, lambda i: i >= 1000), seen)
    picked = set()
    for seed in range(10):
        repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
        result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM, rng=random.Random(seed))
        assert result["issued"] == 1
        picked.add(int(repo.cards[0]["target_id"][1:]))
        assert repo.offers == []  # 상위 20%(300명)는 전부 이미 본 사람이다

    assert all(1000 <= rank < 1200 for rank in picked)


async def test_the_candidate_request_asks_for_no_row_limit():
    seen: list[httpx.Request] = []
    matching = _postgrest_with(_many(1500), seen)

    candidates = await matching.fetch_candidates("owner-1")

    assert len(candidates) == 1500
    [rpc] = [r for r in seen if r.url.path == "/rest/v1/rpc/match_candidates"]
    assert "limit" not in rpc.url.params
    assert "range" not in {key.lower() for key in rpc.headers}


async def test_rank_twelve_hundred_is_drawn_when_it_is_the_only_one_inside_the_band():
    """1,500명 중 1,200등까지가 80% 구간 — 1,200등(0부터 1,199)만 뽑을 수 있으면 그 사람이 나온다."""
    seen: list[httpx.Request] = []
    matching = _postgrest_with(_many(1500, lambda i: i in (1199, 1200)), seen)
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])

    await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM, rng=random.Random(0))

    # 1,201등(1200)은 구간 밖이라 절대 나오지 않는다.
    assert repo.cards[0]["target_id"] == "c1199"


async def test_expiry_is_the_next_issue_day():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo(TWO)

    await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    # 월·목 지급이므로 월요일에 준 카드는 목요일 07:00 에 만료된다(설계 §2.4).
    assert repo.cards[0]["expires_at"] == datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)


async def test_non_issue_day_issues_nothing():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo(TWO)

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 0
    assert repo.cards == []


async def test_ladder_moves_up_and_is_written_back():
    """적은 쪽 활성 2000명을 넘으면 매일 지급으로 올라가고, 그 결과를 설정 행에 적어 둔다(앱이 읽는다)."""
    repo = _FakeCardRepo(
        [{"profile_id": "owner-1", "region_group": "seoul"}],
        counts={"seoul": {"male": 2100, "female": 2000}},
    )
    matching = _FakeMatchingRepo(TWO)

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 1
    assert repo.saved_weekdays == [("seoul", [1, 2, 3, 4, 5, 6, 7])]


async def test_a_thin_pool_drops_to_monday_only_and_cards_last_a_week():
    """적은 쪽 50 미만이면 주 1회(월)다(결정 12). 월요일 카드는 다음 월요일 07:00 에 만료된다."""
    repo = _FakeCardRepo(
        [{"profile_id": "owner-1", "region_group": "seoul"}],
        counts={"seoul": {"male": 300, "female": 49}},
    )
    matching = _FakeMatchingRepo(TWO)

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result["issued"] == 1
    assert repo.saved_weekdays == [("seoul", [1])]
    assert repo.cards[0]["expires_at"] == datetime(2026, 9, 28, 7, 0, tzinfo=SEOUL)


async def test_a_pool_of_a_thousand_issues_four_times_a_week():
    """적은 쪽 1000~1999 면 주 4회(월 · 수 · 금 · 일)다. 주 4회 기준과 매일 기준을 바꿔 읽으면 여기서 잡힌다."""
    repo = _FakeCardRepo(
        [{"profile_id": "owner-1", "region_group": "seoul"}],
        counts={"seoul": {"male": 1500, "female": 1200}},
    )
    matching = _FakeMatchingRepo(TWO)

    await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert repo.saved_weekdays == [("seoul", [1, 3, 5, 7])]
    assert repo.cards[0]["expires_at"] == datetime(2026, 9, 23, 7, 0, tzinfo=SEOUL)


async def test_rerunning_the_same_day_does_not_issue_a_second_card():
    """오늘 카드를 이미 받고 수락·거절까지 끝낸 사람은 card_issue_owners() 에 다시 올라온다.
    Cloud Scheduler 재시도나 손으로 다시 돌릴 때 한 장이 더 나가면 안 된다."""
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}],
                         issued_today={"owner-1"})
    matching = _FakeMatchingRepo(TWO)

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result["issued"] == 0
    assert repo.cards == []
    # 기준 시각은 배치가 도는 날의 자정(KST)이다 — 어제 받은 사람까지 걸러 내면 안 된다.
    assert repo.issued_since == datetime(2026, 9, 21, 0, 0, tzinfo=SEOUL)


async def test_one_failing_push_does_not_stop_the_batch():
    """카드는 이미 insert_card 로 들어간 뒤다. 알림 한 건이 터졌다고 뒷사람이 카드를 못 받으면 안 된다."""
    class _ExplodingSender:
        async def send(self, *args, **kwargs):
            raise RuntimeError("FCM 죽음")

    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"},
                          {"profile_id": "owner-2", "region_group": "seoul"}])
    repo.fetch_push_tokens = lambda profile_id: _tokens()
    matching = _FakeMatchingRepo(TWO)

    result = await issue_daily_cards(repo, matching, _ExplodingSender(), now=MONDAY_7AM)

    assert result["issued"] == 2


async def _tokens():
    return ["tok"]


async def test_owner_without_candidates_is_counted_not_crashed():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([])

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result == {"issued": 0, "no_candidate": 1, "skipped_regions": [], "failed": 0}


class _PerOwnerFailure(_FakeMatchingRepo):
    """owner-1 만 터지고 owner-2 는 멀쩡한 가짜. broken 은 fetch_owner(404) 나 fetch_candidates(그 밖의 예외)."""
    def __init__(self, candidates, broken: str):
        super().__init__(candidates)
        self._broken = broken

    async def fetch_owner(self, profile_id):
        if self._broken == "owner" and profile_id == "owner-1":
            raise HTTPException(status_code=404)
        return await super().fetch_owner(profile_id)

    async def fetch_candidates(self, profile_id):
        if self._broken == "candidates" and profile_id == "owner-1":
            raise RuntimeError("후보 RPC 죽음 닉네임=여우비")
        return await super().fetch_candidates(profile_id)


async def test_one_failing_owner_does_not_stop_the_next_owner(caplog):
    """사람 한 명이 실패해도 배치는 다음 사람으로 간다. 실패한 수는 결과에 failed 로 알린다."""
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"},
                          {"profile_id": "owner-2", "region_group": "seoul"}])

    with caplog.at_level(logging.ERROR, logger="app.cards.issuing"):
        result = await issue_daily_cards(repo, _PerOwnerFailure(TWO, "candidates"), sender=None,
                                         now=MONDAY_7AM, rng=random.Random(0))

    assert result == {"issued": 1, "no_candidate": 0, "skipped_regions": [], "failed": 1}
    assert [c["owner_id"] for c in repo.cards] == ["owner-2"]
    # 로그에는 profile_id 만 남긴다 — 예외 메시지에 닉네임이 섞여 있어도 우리 문구에는 이름을 넣지 않는다.
    [record] = [r for r in caplog.records if r.name == "app.cards.issuing"]
    assert "owner-1" in record.getMessage()
    assert "여우비" not in record.getMessage()


async def test_a_deleted_profile_skips_only_that_owner():
    """fetch_owner 는 프로필이 지워졌으면 404 를 올린다 — 예전에는 배치 전체가 멈췄다."""
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"},
                          {"profile_id": "owner-2", "region_group": "seoul"}])

    result = await issue_daily_cards(repo, _PerOwnerFailure(TWO, "owner"), sender=None,
                                     now=MONDAY_7AM, rng=random.Random(0))

    assert result == {"issued": 1, "no_candidate": 0, "skipped_regions": [], "failed": 1}
    assert [c["owner_id"] for c in repo.cards] == ["owner-2"]
