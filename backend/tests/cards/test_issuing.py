from datetime import datetime

from app.cards.issuing import issue_daily_cards
from app.core.time import SEOUL

MONDAY_7AM = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)     # 월요일
TUESDAY_7AM = datetime(2026, 9, 22, 7, 0, tzinfo=SEOUL)    # 화요일


class _FakeCardRepo:
    def __init__(self, owners, counts=None, settings=None, issued_today=()):
        self._owners = owners
        self._issued_today = set(issued_today)
        self._counts = counts or {"seoul": {"male": 10, "female": 10}}
        self._settings = settings or [{
            "region_group": "seoul", "issue_weekdays": [1, 4], "issue_time": "07:00",
            "ladder_three_per_week_min": 200, "ladder_daily_min": 500,
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
        return card

    async def fetch_card_profile(self, profile_id):
        return {"nickname": "여우비"}

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


def _candidate(candidate_id: str, trait_score: float) -> dict:
    return {"candidate_id": candidate_id, "trait_score": trait_score, "tag_score": 0.0,
            "text_score": 0.0, "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
            "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
            "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False,
            "religion": "none", "last_active_at": "2026-09-21T00:00:00+00:00"}


async def test_issues_one_card_to_the_top_candidate():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("low", 0.1), _candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result["issued"] == 1
    assert repo.cards[0]["target_id"] == "high"


async def test_expiry_is_the_next_issue_day():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    # 월·목 지급이므로 월요일에 준 카드는 목요일 07:00 에 만료된다(설계 §2.4).
    assert repo.cards[0]["expires_at"] == datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)


async def test_non_issue_day_issues_nothing():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 0
    assert repo.cards == []


async def test_ladder_moves_up_and_is_written_back():
    """활성 500명을 넘으면 매일 지급으로 올라가고, 그 결과를 설정 행에 적어 둔다(앱이 읽는다)."""
    repo = _FakeCardRepo(
        [{"profile_id": "owner-1", "region_group": "seoul"}],
        counts={"seoul": {"male": 600, "female": 700}},
    )
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 1
    assert repo.saved_weekdays == [("seoul", [1, 2, 3, 4, 5, 6, 7])]


async def test_rerunning_the_same_day_does_not_issue_a_second_card():
    """오늘 카드를 이미 받고 수락·거절까지 끝낸 사람은 card_issue_owners() 에 다시 올라온다.
    Cloud Scheduler 재시도나 손으로 다시 돌릴 때 한 장이 더 나가면 안 된다."""
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}],
                         issued_today={"owner-1"})
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

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
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, _ExplodingSender(), now=MONDAY_7AM)

    assert result["issued"] == 2


async def _tokens():
    return ["tok"]


async def test_owner_without_candidates_is_counted_not_crashed():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([])

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result == {"issued": 0, "no_candidate": 1, "skipped_regions": []}
