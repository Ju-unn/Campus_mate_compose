"""유사도 고도화 1단계 — 가짜 사용자로 점수·순위·구간 뽑기를 확인한다.

성향·태그·글 점수는 SQL(match_candidates)이 계산해 온다. 여기서는 같은 식을 손으로 만든 벡터·태그에
적용해 그 점수 칸을 후보 dict 에 미리 넣는다(실제 임베딩·외부 호출 없음). 칸 모양은 scoring.final_score
와 test_scoring 의 가짜를 따른다."""

import math
import random
from datetime import datetime, timedelta, timezone

from app.core.time import SEOUL
from app.matching.band import FREE_BAND_RATIO, PAID_BAND_RATIO, band_size, pick_from_band, rank_all

THIS_YEAR = datetime.now(SEOUL).year
TAGS = [f"t{i:02d}" for i in range(45)]
DIM = 8


# ---------- 가짜 사용자 도우미 ----------

def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


def _jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a | b else 0.0


def _scores(me: dict, other: dict) -> dict:
    """match_candidates 의 세 점수 식을 그대로 옮긴다(성향: 거리/5.657, 태그: 자카드 평균, 글: 양방향 코사인)."""
    distance = math.dist(me["survey"], other["survey"])
    tag = (
        _jaccard(me["interests"], other["interests"])
        + (_jaccard(me["my_traits"], other["ideal_traits"]) + _jaccard(other["my_traits"], me["ideal_traits"])) / 2
    ) / 2
    text = (_cosine(me["want"], other["self"]) + _cosine(other["want"], me["self"])) / 2
    return {
        "trait_score": max(0.0, 1 - distance / 5.657),
        "tag_score": tag,
        "text_score": max(0.0, text),
    }


def _owner() -> dict:
    """비흡연·무교·키 180·25세, 상대 키 160~170·나이 22~27 선호. MBTI 는 비워 계수 1.0."""
    return {
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 180,
        "preferred_height_min": 160, "preferred_height_max": 170, "birth_year": THIS_YEAR - 25,
        "preferred_age_min": 22, "preferred_age_max": 27, "is_smoker": False, "religion": "none",
        # 점수 계산용 원재료(SQL 이 쓰는 컬럼을 흉내 낸 것)
        "survey": [3.0] * 8, "interests": set(TAGS[:5]), "my_traits": set(TAGS[10:15]),
        "ideal_traits": set(TAGS[20:25]), "self": [1.0] * DIM, "want": [1.0] * DIM,
    }


def _profile(kind: str, rng: random.Random) -> dict:
    """twin: 나와 거의 같은 사람 / opposite: 정반대 / middle: 그 사이."""
    if kind == "twin":
        survey = [3.0 + rng.uniform(-0.1, 0.1) for _ in range(8)]
        vector = [1.0 + rng.uniform(-0.05, 0.05) for _ in range(DIM)]
        return {
            "survey": survey, "interests": set(TAGS[:5]), "my_traits": set(TAGS[20:25]),
            "ideal_traits": set(TAGS[10:15]), "self": vector, "want": vector,
        }
    if kind == "opposite":
        survey = [rng.choice((0.0, 6.0)) for _ in range(8)]
        vector = [-1.0 + rng.uniform(-0.05, 0.05) for _ in range(DIM)]
        return {
            "survey": survey, "interests": set(TAGS[40:45]), "my_traits": set(TAGS[30:35]),
            "ideal_traits": set(TAGS[35:40]), "self": vector, "want": vector,
        }
    survey = [rng.uniform(1.5, 4.5) for _ in range(8)]
    vector = [rng.uniform(-0.2, 1.0) for _ in range(DIM)]
    return {
        "survey": survey, "interests": set(rng.sample(TAGS, 5)), "my_traits": set(rng.sample(TAGS, 5)),
        "ideal_traits": set(rng.sample(TAGS, 5)), "self": vector, "want": [rng.uniform(-0.2, 1.0) for _ in range(DIM)],
    }


def _candidate(candidate_id: str, owner: dict, raw: dict, **overrides) -> dict:
    """final_score 가 읽는 칸 + DB 가 붙여 줄 pickable. 기본값은 모든 계수가 1.0 인 사람."""
    return {
        "candidate_id": candidate_id, **_scores(owner, raw),
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": THIS_YEAR - 24,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
        "last_active_at": datetime.now(timezone.utc).isoformat(), "pickable": True,
        "kind": raw.get("kind"), **overrides,
    }


def _population(owner: dict, twins: int = 10, opposites: int = 20, total: int = 100, seed: int = 0) -> list[dict]:
    rng = random.Random(seed)
    kinds = ["twin"] * twins + ["opposite"] * opposites + ["middle"] * (total - twins - opposites)
    rng.shuffle(kinds)
    return [_candidate(f"u{i:03d}", owner, {**_profile(kind, rng), "kind": kind}) for i, kind in enumerate(kinds)]


# ---------- 1. 비슷한 사람이 위로 ----------

def test_near_twins_fill_the_top_ten_percent():
    owner = _owner()
    ranked = rank_all(owner, _population(owner))
    top = ranked[: len(ranked) // 10]

    assert [c["kind"] for c in top] == ["twin"] * 10


def test_opposites_sink_to_the_bottom_twenty_percent():
    owner = _owner()
    ranked = rank_all(owner, _population(owner))

    assert {c["kind"] for c in ranked[-20:]} == {"opposite"}


# ---------- 2. 계수가 순위를 뒤로 민다 ----------

def test_penalties_push_otherwise_equal_candidates_down():
    """같은 기본 점수(같은 원재료)에서 계수 하나씩만 다르게 한다 — 감점이 없는 사람이 1등이다."""
    owner = _owner()
    raw = _profile("twin", random.Random(5))
    stale = (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()
    candidates = [
        _candidate("smoker", owner, raw, is_smoker=True),
        _candidate("religion", owner, raw, religion="christian"),
        _candidate("too_tall", owner, raw, height_cm=185),
        _candidate("too_old", owner, raw, birth_year=THIS_YEAR - 35),
        _candidate("inactive", owner, raw, last_active_at=stale),
        _candidate("zz_clean", owner, raw),  # id 를 뒤로 둬 동점 정렬로 1등이 되는 게 아님을 분명히 한다
    ]
    ranked = rank_all(owner, candidates)
    by_id = {c["candidate_id"]: c["score"] for c in ranked}

    assert ranked[0]["candidate_id"] == "zz_clean"
    for penalised in ("smoker", "religion", "too_tall", "too_old", "inactive"):
        assert by_id[penalised] < by_id["zz_clean"], penalised


def test_penalty_drops_a_twin_below_untouched_twins():
    owner = _owner()
    population = _population(owner)
    smoker_twin = next(c for c in population if c["kind"] == "twin")
    population = [
        {**c, "is_smoker": True} if c is smoker_twin else c for c in population
    ]
    ranked = rank_all(owner, population)
    position = [c["candidate_id"] for c in ranked].index(smoker_twin["candidate_id"])

    assert position >= 9  # 다른 쌍둥이 9명보다 뒤


# ---------- 3. 구간 뽑기 ----------

def test_free_band_never_reaches_the_opposite_bottom_twenty():
    owner = _owner()
    ranked = rank_all(owner, _population(owner))
    bottom = {c["candidate_id"] for c in ranked[band_size(len(ranked), FREE_BAND_RATIO):]}
    rng = random.Random(11)
    picks = [pick_from_band(ranked, FREE_BAND_RATIO, rng) for _ in range(500)]

    assert all(p["kind"] != "opposite" for p in picks)
    assert {p["candidate_id"] for p in picks}.isdisjoint(bottom)


def test_paid_band_only_picks_the_top_twenty():
    owner = _owner()
    ranked = rank_all(owner, _population(owner))
    size = band_size(len(ranked), PAID_BAND_RATIO)
    top = {c["candidate_id"] for c in ranked[:size]}
    rng = random.Random(12)
    picks = [pick_from_band(ranked, PAID_BAND_RATIO, rng) for _ in range(500)]

    assert size == 20
    assert {p["candidate_id"] for p in picks} <= top
    assert all(p["kind"] in ("twin", "middle") for p in picks)
    assert sum(p["kind"] == "twin" for p in picks) >= 150  # 쌍둥이 10명/20명 → 기대 250, 넉넉히 잡는다
