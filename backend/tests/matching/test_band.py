import copy
import random
from collections import Counter
from datetime import datetime, timezone

import pytest

from app.matching.band import (
    BAND_MINIMUM,
    FREE_BAND_RATIO,
    PAID_BAND_RATIO,
    band_size,
    pick_from_band,
    rank_all,
)

ALL_OK = {}
SEEDS = (0, 1, 7, 42, 2026)


def _owner() -> dict:
    # 계수가 전부 1.0 이 되는 소유자 — 순위가 trait_score 만으로 갈리게 한다(test_scoring 과 같은 모양).
    return {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
    }


def _candidate(candidate_id: str, trait_score: float, pickable: bool = True) -> dict:
    return {
        "candidate_id": candidate_id, "trait_score": trait_score, "tag_score": 0, "text_score": 0,
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
        "last_active_at": datetime.now(timezone.utc).isoformat(), "pickable": pickable,
    }


def _ranked(n: int, unpickable: set[int] = frozenset()) -> list[dict]:
    """점수 내림차순으로 이미 정렬된 rank_all 결과 모양. i 번째 = 순위 인덱스 i."""
    return [
        {"candidate_id": f"c{i:03d}", "score": 1 - i / (n + 1), "pickable": i not in unpickable}
        for i in range(n)
    ]


def _index(ranked: list[dict]) -> dict[str, int]:
    return {c["candidate_id"]: i for i, c in enumerate(ranked)}


# ---------- band_size ----------

def test_band_size_is_zero_without_candidates():
    assert band_size(0, PAID_BAND_RATIO) == 0
    assert band_size(0, FREE_BAND_RATIO) == 0


def test_band_size_is_everyone_when_fewer_than_minimum():
    assert band_size(3, PAID_BAND_RATIO) == 3
    assert band_size(3, FREE_BAND_RATIO) == 3


def test_band_size_never_drops_below_minimum():
    """N=10 의 20% 는 2명이지만 최소 5명은 보장한다."""
    assert band_size(10, PAID_BAND_RATIO) == 5


def test_band_size_follows_ratio_for_large_pools():
    assert band_size(100, PAID_BAND_RATIO) == 20
    assert band_size(100, FREE_BAND_RATIO) == 80
    assert band_size(7, FREE_BAND_RATIO) == 6  # ceil(5.6)


def test_band_size_rounds_up():
    assert band_size(26, PAID_BAND_RATIO) == 6  # 5.2 → 6
    assert band_size(101, PAID_BAND_RATIO) == 21  # 20.2 → 21
    assert band_size(25, PAID_BAND_RATIO) == 5  # 정확히 5.0 은 그대로


def test_band_size_respects_custom_minimum():
    assert band_size(10, PAID_BAND_RATIO, minimum=1) == 2
    assert band_size(10, PAID_BAND_RATIO, minimum=BAND_MINIMUM) == 5


@pytest.mark.parametrize("ratio", [0, -0.1, 1.01, 2])
def test_band_size_rejects_invalid_ratio(ratio):
    with pytest.raises(ValueError):
        band_size(10, ratio)


def test_band_ratio_constants():
    assert (FREE_BAND_RATIO, PAID_BAND_RATIO, BAND_MINIMUM) == (0.8, 0.2, 5)


# ---------- rank_all ----------

def test_rank_all_sorts_by_score_descending():
    ranked = rank_all(_owner(), [_candidate("low", 0.1), _candidate("high", 0.9), _candidate("mid", 0.5)])

    assert [c["candidate_id"] for c in ranked] == ["high", "mid", "low"]
    assert ranked[0]["score"] > ranked[1]["score"] > ranked[2]["score"]


def test_rank_all_breaks_ties_by_candidate_id():
    candidates = [_candidate("c", 0.5), _candidate("a", 0.5), _candidate("top", 0.9), _candidate("b", 0.5)]

    first = rank_all(_owner(), candidates)
    second = rank_all(_owner(), list(reversed(candidates)))

    assert [c["candidate_id"] for c in first] == ["top", "a", "b", "c"]
    assert [c["candidate_id"] for c in second] == [c["candidate_id"] for c in first]


def test_rank_all_keeps_pickable_and_does_not_drop_unpickable():
    """본 사람도 순위에는 남는다 — 뽑을 때만 뺀다."""
    ranked = rank_all(_owner(), [_candidate("seen", 0.9, pickable=False), _candidate("new", 0.1)])

    assert [(c["candidate_id"], c["pickable"]) for c in ranked] == [("seen", False), ("new", True)]


# ---------- pick_from_band ----------

def test_pick_always_stays_inside_the_band():
    ranked = _ranked(100)
    index = _index(ranked)
    for ratio in (PAID_BAND_RATIO, FREE_BAND_RATIO):
        size = band_size(len(ranked), ratio)
        for seed in SEEDS:
            rng = random.Random(seed)
            for _ in range(500):
                assert index[pick_from_band(ranked, ratio, rng)["candidate_id"]] < size


def test_pick_never_returns_unpickable():
    ranked = _ranked(100, unpickable={0, 3, 5, 10, 19})
    rng = random.Random(1)
    picked = {pick_from_band(ranked, PAID_BAND_RATIO, rng)["candidate_id"] for _ in range(500)}

    assert picked.isdisjoint({"c000", "c003", "c005", "c010", "c019"})


def test_pick_never_returns_excluded():
    ranked = _ranked(100)
    exclude = frozenset({"c001", "c002", "c018"})
    rng = random.Random(2)
    picked = {pick_from_band(ranked, PAID_BAND_RATIO, rng, exclude=exclude)["candidate_id"] for _ in range(500)}

    assert picked.isdisjoint(exclude)


def test_band_is_measured_on_everyone_not_on_pickable_only():
    """상위 20%(20명)가 모두 본 사람이면 None — 21등 아래로 내려가 뽑지 않는다."""
    ranked = _ranked(100, unpickable=set(range(20)))

    for seed in SEEDS:
        assert pick_from_band(ranked, PAID_BAND_RATIO, random.Random(seed)) is None


def test_excluded_band_also_yields_none():
    ranked = _ranked(100, unpickable=set(range(10)))
    exclude = frozenset(f"c{i:03d}" for i in range(10, 20))

    assert pick_from_band(ranked, PAID_BAND_RATIO, random.Random(0), exclude=exclude) is None


def test_pick_returns_none_for_empty_ranking():
    assert pick_from_band([], FREE_BAND_RATIO, random.Random(0)) is None


def test_single_pickable_in_band_is_always_chosen():
    ranked = _ranked(100, unpickable=set(range(20)) - {7})
    rng = random.Random(3)

    assert {pick_from_band(ranked, PAID_BAND_RATIO, rng)["candidate_id"] for _ in range(50)} == {"c007"}


def test_pick_does_not_mutate_input():
    ranked = _ranked(30, unpickable={2})
    before = copy.deepcopy(ranked)

    pick_from_band(ranked, PAID_BAND_RATIO, random.Random(0), exclude=frozenset({"c001"}))

    assert ranked == before


def test_same_seed_gives_same_pick_sequence():
    ranked = _ranked(100)
    rng_a, rng_b, rng_c = random.Random(42), random.Random(42), random.Random(43)

    seq_a = [pick_from_band(ranked, FREE_BAND_RATIO, rng_a)["candidate_id"] for _ in range(50)]
    seq_b = [pick_from_band(ranked, FREE_BAND_RATIO, rng_b)["candidate_id"] for _ in range(50)]
    seq_c = [pick_from_band(ranked, FREE_BAND_RATIO, rng_c)["candidate_id"] for _ in range(50)]

    assert seq_a == seq_b
    assert seq_a != seq_c


def test_picks_spread_across_the_band():
    """500번 뽑으면 구간 안 사람마다 평균의 절반 이상은 나온다(균등 무작위)."""
    ranked = _ranked(100)
    size = band_size(len(ranked), PAID_BAND_RATIO)
    rng = random.Random(2026)
    counts = Counter(pick_from_band(ranked, PAID_BAND_RATIO, rng)["candidate_id"] for _ in range(500))
    mean = 500 / size

    assert set(counts) == {c["candidate_id"] for c in ranked[:size]}
    assert min(counts.values()) >= mean / 2


# ---------- 품질이 안 떨어진다는 시뮬레이션 ----------

def _pool(n: int) -> list[dict]:
    # 점수가 서로 다른 후보 n 명(동점 없음). 순서를 섞어 넣어 rank_all 의 정렬에 기대게 한다.
    candidates = [_candidate(f"p{i:03d}", 1 - i / (n + 1)) for i in range(n)]
    random.Random(0).shuffle(candidates)
    return candidates


def _rest(ranked: list[dict], seen: set[str]) -> list[dict]:
    """본 사람은 다음 주기부터 pickable=False(쉼) — DB 가 붙여 줄 칸을 흉내 낸다."""
    return [{**c, "pickable": c["pickable"] and c["candidate_id"] not in seen} for c in ranked]


def test_paid_picks_stay_in_original_top_band_until_exhausted():
    ranked = rank_all(_owner(), _pool(200))
    original = _index(ranked)
    size = band_size(len(ranked), PAID_BAND_RATIO)
    rng = random.Random(7)
    seen: set[str] = set()

    while (card := pick_from_band(_rest(ranked, seen), PAID_BAND_RATIO, rng)) is not None:
        assert original[card["candidate_id"]] < size
        assert card["candidate_id"] not in seen
        seen.add(card["candidate_id"])

    assert len(seen) == size  # 상위 20%(40명)를 다 보면 소진
    assert pick_from_band(_rest(ranked, seen), PAID_BAND_RATIO, rng) is None


def test_old_top_one_rule_slides_out_of_the_band():
    """옛 방식(본 사람 빼고 1등): 소진 개념이 없어 계속 내려간다. 구간 크기 + 1 번째 카드부터는
    처음 순위 기준 상위 20% 밖이다. 새 방식은 같은 시점에 None 을 돌려준다."""
    ranked = rank_all(_owner(), _pool(200))
    original = _index(ranked)
    size = band_size(len(ranked), PAID_BAND_RATIO)
    seen: set[str] = set()
    old_ranks = []

    for _ in range(size + 20):
        top = next(c for c in _rest(ranked, seen) if c["pickable"])  # ranked[0] after exclusion
        old_ranks.append(original[top["candidate_id"]])
        seen.add(top["candidate_id"])

    assert old_ranks == list(range(size + 20))  # 볼수록 한 칸씩 덜 맞는 사람
    assert all(r >= size for r in old_ranks[size:])  # 41번째부터 20% 밖
    top_band_seen = {c["candidate_id"] for c in ranked[:size]}
    assert pick_from_band(_rest(ranked, top_band_seen), PAID_BAND_RATIO, random.Random(0)) is None


def test_a_candidate_without_pickable_is_a_key_error():
    """DB 계약(지시문 22)의 pickable 이 빠진 후보는 조용히 True 로 읽지 않고 터진다 — 검토 권고."""
    ranked = [{"candidate_id": "c000", "score": 0.9}]
    with pytest.raises(KeyError):
        pick_from_band(ranked, FREE_BAND_RATIO, random.Random(0))
