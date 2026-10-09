"""유료 카드 제안(지시문 22 C · D) — 주기마다 한 명을 미리 정하고, 맞는 이유 태그를 붙인다."""
import random
import re
from datetime import datetime

import pytest

from app.cards.paid_offer import REASON_THRESHOLD, build_reasons, ensure_offer
from app.core.time import SEOUL
from app.matching.band import rank_all
from paid_world import OfferStore, candidate, owner_row

MONDAY_7AM = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
THURSDAY_7AM = datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)
MONDAY_NOON = datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL)


def _ranked(n: int, unpickable: set[int] = frozenset()) -> list[dict]:
    """점수가 i 순서대로 내려가는 n 명(c00 이 1등)."""
    return rank_all(owner_row(), [
        candidate(f"c{i:02d}", 1 - i / (n + 1), pickable=i not in unpickable) for i in range(n)
    ])


def _offer(target_id: str, cycle: datetime = MONDAY_7AM, status: str = "offered", **overrides) -> dict:
    return {"id": "offer-old", "owner_id": "owner-1", "cycle_started_at": cycle.isoformat(),
            "target_id": target_id, "reasons": [], "band_count": 5, "status": status,
            "purchased_card_id": None, **overrides}


# build_reasons ----------------------------------------------------------------------------

def _target(**scores) -> dict:
    return candidate("t", **{"trait_score": 0.0, **scores})


def test_threshold_is_one_constant_starting_at_half():
    assert REASON_THRESHOLD == 0.5


def test_reasons_are_at_most_three_and_ordered_by_strength():
    owner = owner_row(interest_tags=["러닝", "카페가기"], mbti="INFP", preferred_mbti_flags={"E": True},
                      religion="christian")
    target = _target(trait_score=0.9, text_score=0.7, mbti="ENFJ",
                     interest_tags=["카페가기", "러닝"], religion="none")

    reasons = build_reasons(owner, target)

    # 성향 0.9 > 태그(공통 2개) 0.8 > 이상형 0.7 > MBTI 0.6 — 네 개가 후보지만 셋만 남는다.
    assert [r["kind"] for r in reasons] == ["tendency", "tags", "ideal"]
    assert len(reasons) == 3


def test_ties_follow_the_listed_order():
    owner = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, preferred_height_min=160,
                      preferred_height_max=175)
    target = _target(trait_score=0.6, mbti="ENFJ")

    reasons = build_reasons(owner, target)

    # tendency · mbti · age_height · smoke_religion 이 모두 0.6 — 나열 순서대로 앞의 셋.
    assert [r["kind"] for r in reasons] == ["tendency", "mbti", "age_height"]


def test_below_threshold_is_left_out():
    owner = owner_row(religion="christian")
    target = _target(trait_score=REASON_THRESHOLD - 0.01, text_score=REASON_THRESHOLD, religion="none")

    assert [r["kind"] for r in build_reasons(owner, target)] == ["ideal"]


def test_tags_carry_at_most_two_names():
    owner = owner_row(interest_tags=["러닝", "카페가기", "영화", "등산"], religion="christian")
    target = _target(tag_score=0.9, interest_tags=["등산", "영화", "카페가기", "러닝"], religion="none")

    reasons = build_reasons(owner, target)

    assert reasons == [{"kind": "tags", "text": "#러닝 #카페가기가 같아요"}]


def test_tag_particle_follows_the_last_name():
    owner = owner_row(interest_tags=["러닝"], religion="christian")
    target = _target(tag_score=0.9, interest_tags=["러닝"], religion="none")

    assert build_reasons(owner, target)[0]["text"] == "#러닝이 같아요"


def test_tags_without_names_are_left_out():
    """점수는 높아도 공통 관심 태그 이름이 없으면(특징 태그만 겹침) tags 를 넣지 않는다."""
    owner = owner_row(interest_tags=["러닝"], religion="christian")
    target = _target(tag_score=0.9, interest_tags=["영화"], religion="none")

    assert build_reasons(owner, target) == []


def test_mbti_needs_both_sides_to_have_one():
    """MBTI 가 없으면 계수가 1.0(상관없음)이지만 "잘 맞아요" 라고 말할 근거가 없다."""
    owner = owner_row(mbti=None, religion="christian")
    target = _target(mbti="ENFJ", religion="none")

    assert build_reasons(owner, target) == []


def test_mbti_with_a_penalty_is_left_out():
    owner = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, religion="christian")
    target = _target(mbti="ISTJ", religion="none")

    assert build_reasons(owner, target) == []


def test_age_height_needs_a_range_and_no_penalty():
    owner = owner_row(preferred_height_min=170, religion="christian")
    assert build_reasons(owner, _target(height_cm=160, religion="none")) == []
    assert [r["kind"] for r in build_reasons(owner, _target(height_cm=172, religion="none"))] == ["age_height"]
    # 아무도 범위를 두지 않았으면 말하지 않는다.
    assert build_reasons(owner_row(religion="christian"), _target(religion="none")) == []


def test_smoke_religion_needs_no_penalty_on_both():
    assert [r["kind"] for r in build_reasons(owner_row(), _target())] == ["smoke_religion"]
    assert build_reasons(owner_row(), _target(is_smoker=True)) == []
    assert build_reasons(owner_row(religion="christian"), _target(religion="none")) == []


def test_mbti_reason_needs_the_owner_to_have_chosen_a_preference():
    """선호 MBTI 가 `{}` 이면 "전부 상관없음" 이라 맞는 이유가 아니다. 한 글자라도 골랐을 때만 센다."""
    target = _target(mbti="ENFJ", religion="none")

    assert build_reasons(owner_row(mbti="INFP", preferred_mbti_flags={}, religion="christian"), target) == []
    chosen = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, religion="christian")
    assert [r["kind"] for r in build_reasons(chosen, target)] == ["mbti"]


def test_score_reasons_come_before_coefficient_reasons():
    """계수형(MBTI · 나이키 · 흡연종교)은 불이익이 없어도 0.6 이다 — 0.6 을 넘는 점수형이 앞선다."""
    owner = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, preferred_height_min=160,
                      preferred_height_max=175)
    target = _target(trait_score=0.65, text_score=0.7, mbti="ENFJ")

    assert [r["kind"] for r in build_reasons(owner, target)] == ["ideal", "tendency", "mbti"]


def test_coefficient_reasons_fill_in_when_the_scores_are_low():
    owner = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, preferred_height_min=160,
                      preferred_height_max=175)
    target = _target(trait_score=0.55, mbti="ENFJ")

    # 성향 0.55 는 문턱은 넘지만 계수형 0.6 보다 낮아, 셋이 다 차면 밀려난다.
    assert [r["kind"] for r in build_reasons(owner, target)] == ["mbti", "age_height", "smoke_religion"]


def test_one_common_tag_counts_half_and_ignores_tag_score():
    """공통 태그 1개 = 0.5(문턱 이상, 계수형 0.6 · 성향 0.55 보다 뒤). tag_score 가 0.99 여도 세기는 그대로다."""
    owner = owner_row(interest_tags=["러닝", "영화"])
    target = _target(trait_score=0.55, tag_score=0.99, interest_tags=["러닝", "등산"])

    assert [r["kind"] for r in build_reasons(owner, target)] == ["smoke_religion", "tendency", "tags"]


def test_two_or_more_common_tags_count_point_eight():
    owner = owner_row(interest_tags=["러닝", "영화", "등산"])
    target = _target(trait_score=0.7, tag_score=0.0, interest_tags=["러닝", "영화", "등산"])

    reasons = build_reasons(owner, target)

    assert [r["kind"] for r in reasons] == ["tags", "tendency", "smoke_religion"]
    assert reasons[0]["text"] == "#러닝 #영화가 같아요"  # 셋이 겹쳐도 이름은 둘까지


def test_texts_never_show_school_score_or_ideal_condition_words():
    who = {"universities": {"name": "테스트대학교"}, "nickname": "여우비"}
    them = {"universities": {"name": "가짜대학교"}, "nickname": "토끼", "score": 0.87}
    # 점수 세 가지가 다 나오는 쌍(계수 쪽은 종교를 달리해 끼지 않게)과, 계수 세 가지가 다 나오는 쌍.
    by_scores = build_reasons(
        owner_row(interest_tags=["러닝", "카페가기"], religion="christian", **who),
        _target(trait_score=0.93, tag_score=0.88, text_score=0.91, interest_tags=["러닝", "카페가기"],
                religion="none", **them))
    by_coefficients = build_reasons(
        owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, preferred_age_min=20, preferred_age_max=30,
                  **who),
        _target(mbti="ENFJ", **them))
    reasons = by_scores + by_coefficients

    assert {r["kind"] for r in reasons} == {"tendency", "tags", "ideal", "mbti", "age_height", "smoke_religion"}
    for text in {r["text"] for r in reasons}:
        assert "대학" not in text and "학교" not in text
        assert not re.search(r"\d|%", text)
        assert "이상형 조건에 맞는" not in text
        assert "여우비" not in text and "토끼" not in text


def test_reason_texts_are_the_agreed_words():
    texts = {}
    # 점수 세 가지는 하나씩 켠다(종교를 달리해 smoke_religion 이 끼지 않게).
    plain = owner_row(interest_tags=["러닝", "카페"], religion="christian")
    for scores in ({"trait_score": 0.9}, {"tag_score": 0.9}, {"text_score": 0.9}):
        target = _target(interest_tags=["러닝", "카페"], religion="none", **scores)
        texts.update({r["kind"]: r["text"] for r in build_reasons(plain, target)})
    # 계수 세 가지는 점수 없이 한 번에 나온다.
    strict = owner_row(mbti="INFP", preferred_mbti_flags={"E": True}, preferred_age_min=20,
                       preferred_age_max=30)
    texts.update({r["kind"]: r["text"] for r in build_reasons(strict, _target(mbti="ENFJ"))})

    assert texts == {
        "tendency": "성향이 비슷해요",
        "tags": "#러닝 #카페가 같아요",
        "ideal": "'이런 사람이 좋아요'와 잘 맞아요",
        "mbti": "MBTI가 잘 맞아요",
        "age_height": "나이·키가 원하는 범위예요",
        "smoke_religion": "흡연·종교 조건이 맞아요",
    }


# ensure_offer -----------------------------------------------------------------------------

async def test_new_offer_comes_from_the_top_twenty_percent_band():
    store = OfferStore()
    ranked = _ranked(50)  # 상위 20% = 10명

    for seed in range(40):
        store.offers.clear()
        offer = await ensure_offer(store, owner_row(), ranked, MONDAY_7AM, random.Random(seed), MONDAY_7AM)
        assert offer["target_id"] in {f"c{i:02d}" for i in range(10)}
        assert offer["band_count"] == 10
        assert offer["cycle_started_at"] == MONDAY_7AM.isoformat()


async def test_band_count_counts_only_pickable_people_in_the_band():
    store = OfferStore()
    ranked = _ranked(50, unpickable=set(range(9)))  # 상위 10명 중 9명이 쉼 → 1명

    offer = await ensure_offer(store, owner_row(), ranked, MONDAY_7AM, random.Random(0), MONDAY_7AM)

    assert offer["target_id"] == "c09"
    assert offer["band_count"] == 1


async def test_the_band_is_measured_on_everyone_not_on_pickable_only():
    """상위 20%(5명)가 모두 쉼이면 비어 있다 — 남은 사람으로 구간을 다시 재면 아래로 내려간다."""
    store = OfferStore()
    ranked = _ranked(20, unpickable=set(range(5)))

    offer = await ensure_offer(store, owner_row(), ranked, MONDAY_7AM, random.Random(0), MONDAY_7AM)

    assert offer is None
    assert store.offers == []


async def test_the_same_cycle_reuses_the_offer():
    store = OfferStore(offers=[_offer("c03")])
    ranked = _ranked(50)

    for seed in range(10):
        offer = await ensure_offer(store, owner_row(), ranked, MONDAY_7AM, random.Random(seed), MONDAY_NOON)
        assert offer["id"] == "offer-old"
        assert offer["target_id"] == "c03"
    assert store.inserts == 0


@pytest.mark.parametrize("lost", [
    {"status": "suspended"}, {"status": "withdrawn"}, {"auto_hidden_at": "2026-09-21T09:00:00+09:00"},
    {"matching_paused": True},
])
async def test_a_target_who_lost_eligibility_is_replaced(lost):
    store = OfferStore(offers=[_offer("c03")], hidden_profiles={"c03": lost})

    offer = await ensure_offer(store, owner_row(), _ranked(50), MONDAY_7AM, random.Random(1), MONDAY_NOON)

    assert store.by_status("replaced")[0]["id"] == "offer-old"
    assert offer["id"] != "offer-old"
    assert offer["status"] == "offered"


async def test_a_blocked_target_is_replaced():
    store = OfferStore(offers=[_offer("c03")], blocked={"c03"})

    offer = await ensure_offer(store, owner_row(), _ranked(50), MONDAY_7AM, random.Random(1), MONDAY_NOON)

    assert [o["id"] for o in store.by_status("replaced")] == ["offer-old"]
    assert offer["id"] != "offer-old"


async def test_a_target_who_left_the_candidates_is_replaced():
    """후보 SQL 이 하드 필터로 뺀 사람(차단 · 지인 차단 등)이나 이제 pickable 이 아닌 사람(매칭됨)."""
    store = OfferStore(offers=[_offer("c03")])
    ranked = _ranked(50, unpickable={3})

    offer = await ensure_offer(store, owner_row(), ranked, MONDAY_7AM, random.Random(1), MONDAY_NOON)

    assert store.by_status("replaced")[0]["id"] == "offer-old"
    assert offer["target_id"] != "c03"


async def test_an_unbought_offer_from_the_last_cycle_expires():
    store = OfferStore(offers=[_offer("c03", cycle=MONDAY_7AM)])

    offer = await ensure_offer(store, owner_row(), _ranked(50), THURSDAY_7AM, random.Random(1), THURSDAY_7AM)

    assert [o["id"] for o in store.by_status("expired")] == ["offer-old"]
    assert offer["cycle_started_at"] == THURSDAY_7AM.isoformat()


async def test_after_buying_this_cycle_no_new_offer_is_made():
    store = OfferStore(offers=[_offer("c03", status="purchased", purchased_card_id="card-9")])

    offer = await ensure_offer(store, owner_row(), _ranked(50), MONDAY_7AM, random.Random(1), MONDAY_NOON)

    assert offer is None
    assert store.inserts == 0


async def test_a_concurrent_insert_is_read_back_instead_of_failing():
    store = OfferStore()
    store.conflict_once = _offer("c07", id="offer-first")

    offer = await ensure_offer(store, owner_row(), _ranked(50), MONDAY_7AM, random.Random(1), MONDAY_7AM)

    assert offer["id"] == "offer-first"
    assert len(store.by_status("offered")) == 1


async def test_the_offer_stores_reasons_with_common_tag_names():
    store = OfferStore(tags={"owner-1": ["러닝", "카페가기"], "c00": ["카페가기"]})
    ranked = rank_all(owner_row(religion="christian"), [
        candidate("c00", 0.9, tag_score=0.9, religion="none"),
        *[candidate(f"z{i}", 0.1, pickable=False) for i in range(9)],
    ])

    offer = await ensure_offer(store, owner_row(religion="christian"), ranked, MONDAY_7AM,
                               random.Random(0), MONDAY_7AM)

    assert offer["target_id"] == "c00"
    # 둘 다 0.9 로 같으면 나열 순서(성향 → 태그)다.
    assert offer["reasons"] == [{"kind": "tendency", "text": "성향이 비슷해요"},
                                {"kind": "tags", "text": "#카페가기가 같아요"}]
