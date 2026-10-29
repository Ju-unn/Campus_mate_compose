import math
from datetime import datetime, timedelta, timezone

from app.core.time import SEOUL
from app.matching.scoring import activity_coefficient, face_fit, final_score, mbti_coefficient, mbti_fit, rank

# 설계 §6.4 판정 예시: 내 설정이 E ok, I ok, N ok, S no, T ok, F no, J ok, P ok
MY_FLAGS = {"E": True, "I": True, "N": True, "S": False, "T": True, "F": False, "J": True, "P": True}
ALL_OK = {}
# 글 정리가 없으면(이 파일의 대부분) 정리 몫 0.05 의 절반만 받는다 — 다 맞아도 최종 0.975.
NO_FACETS = 1 - 0.05 * 0.5
CAFE_LOVER = {"like_places": ["카페"], "dislike_places": [], "talk": None, "values": []}
CAFE_HATER = {"like_places": [], "dislike_places": ["카페"], "talk": None, "values": []}
# 내 MBTI(ENFP)를 상대가 같은 비율로 깎는 설정 — 양방향이 같은 값이라야 §6.4 표의 계수가 그대로 나온다.
PARTNER_THREE_OF_FOUR = {"T": True, "F": False}
PARTNER_TWO_OF_FOUR = {"T": True, "F": False, "J": True, "P": False}


def test_mbti_coefficient_matches_the_spec_table():
    """§6.4 표의 적합도 4/4·3/4·2/4 → 1.00·0.90·0.80(양방향이 같을 때의 값이다)."""
    assert mbti_coefficient(MY_FLAGS, "ENTJ", ALL_OK, "ENFP") == 1.00
    assert round(mbti_coefficient(MY_FLAGS, "ESTJ", PARTNER_THREE_OF_FOUR, "ENFP"), 2) == 0.90
    assert round(mbti_coefficient(MY_FLAGS, "ESFJ", PARTNER_TWO_OF_FOUR, "ENFP"), 2) == 0.80


def test_mbti_coefficient_is_the_geometric_mean_of_both_directions():
    """상대가 나를 안 깎으면 내 감점도 절반만 먹는다(§6.4 양방향적합도 = √(A→B × B→A))."""
    assert round(mbti_coefficient(MY_FLAGS, "ESTJ", ALL_OK, "ENFP"), 4) == round(
        0.6 + 0.4 * math.sqrt(0.75), 4
    )


def test_mbti_coefficient_reads_app_payload_with_only_chosen_poles():
    """06-1 앱은 켠 극만 보낸다({"E": True}). 한 축에 하나만 켰으면 그 극만 ok 다(2026-09-26 실기기 d)."""
    assert round(mbti_coefficient({"E": True}, "ISTJ", ALL_OK, "ENFP"), 4) == round(
        0.6 + 0.4 * math.sqrt(0.75), 4
    )
    assert mbti_coefficient({"E": True, "I": True}, "ISTJ", ALL_OK, "ENFP") == 1.00


def test_mbti_coefficient_is_one_when_partner_mbti_is_unknown():
    """모른다는 이유로 불이익을 주지 않는다(설계 §6.4)."""
    assert mbti_coefficient(MY_FLAGS, None, ALL_OK, "ENFP") == 1.00


def _face(animal, impression, wants_animals=(), wants_impressions=()):
    return {"animal_type": animal, "impression_type": impression,
            "preferred_animal_types": list(wants_animals), "preferred_impression_types": list(wants_impressions)}


def test_face_fit_is_one_when_both_sides_get_what_they_picked():
    me = _face("bear", "arab", ["rabbit"], ["chic"])
    partner = _face("rabbit", "chic", ["bear"], ["arab"])
    assert face_fit(me, partner) == 1.0


def test_face_fit_counts_animal_and_impression_as_half_each_per_direction():
    """여02(곰 · 아랍, 원함 강아지 · 햄스터 · 늑대 / 두부 · 시크) ↔ 남30(토끼 · 시크, 원함 강아지 · 곰 / 선한):
    여02 쪽은 인상만 맞아 0.5, 남30 쪽은 동물상만 맞아 0.5 → √(0.5 × 0.5) = 0.5."""
    f02 = _face("bear", "arab", ["dog", "hamster", "wolf"], ["tofu", "chic"])
    m30 = _face("rabbit", "chic", ["dog", "bear"], ["kind"])
    assert face_fit(f02, m30) == 0.5


def test_face_fit_is_zero_when_nothing_matches_either_way():
    me = _face("bear", "arab", ["dog"], ["tofu"])
    partner = _face("cat", "chic", ["fox"], ["kind"])
    assert face_fit(me, partner) == 0.0


def test_face_fit_treats_an_empty_choice_as_anything_goes():
    """고르지 않은 칸 · 상대 얼굴 정보가 없는 칸은 불이익을 주지 않는다(MBTI 모름과 같은 원칙)."""
    assert face_fit(_face("bear", "arab"), _face("cat", "chic")) == 1.0
    assert face_fit(_face("bear", None, ["cat"], ["chic"]), _face(None, None, ["bear"], ["tofu"])) == 1.0


def test_mbti_fit_is_the_inside_of_the_old_coefficient():
    """MBTI 적합은 0~1(양방향 기하평균). 옛 계수 0.6 + 0.4 × 적합 의 안쪽 값과 같다 — 유료 카드 이유 문구는 계수를 계속 쓴다."""
    assert round(mbti_fit(MY_FLAGS, "ESTJ", ALL_OK, "ENFP"), 4) == round(math.sqrt(0.75), 4)
    assert mbti_fit(MY_FLAGS, None, ALL_OK, "ENFP") == 1.0
    assert round(mbti_coefficient(MY_FLAGS, "ESTJ", ALL_OK, "ENFP"), 4) == round(0.6 + 0.4 * math.sqrt(0.75), 4)


def test_activity_coefficient_steps():
    now = datetime.now(timezone.utc)
    assert activity_coefficient(now - timedelta(days=1)) == 1.0
    assert activity_coefficient(now - timedelta(days=5)) == 0.7
    assert activity_coefficient(now - timedelta(days=10)) == 0.4


def test_final_score_multiplies_weighted_sum_by_every_coefficient():
    """가중합(성향 0.25 · 태그 0.10 · 글 0.45 + 글 정리 0.05 · MBTI 적합 0.075 · 얼굴 적합 0.075)에 남은 계수를 곱한다(10-28 E7 + 0번)."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": "ENFP", "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": "ENFP",
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": True, "religion": "buddhist",
        "last_active_at": now.isoformat(),
    }

    # 가중합 0.975(정리 없음) × 키 1.0 × 나이 1.0 × 흡연 0.5(비흡연자에게 흡연자) × 종교 0.6 × 활동성 1.0
    assert round(final_score(owner, candidate), 4) == round(NO_FACETS * 0.30, 4)


def test_final_score_adds_the_face_fit_as_seven_and_a_half_percent():
    """얼굴상 · 인상이 양쪽 다 안 맞으면 가중합에서 0.075 가 빠진다(곱하기 계수가 아니라 더하기 — 10-28 E7)."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
        "animal_type": "bear", "impression_type": "arab",
        "preferred_animal_types": ["dog"], "preferred_impression_types": ["tofu"],
    }
    base = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": None,
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "last_active_at": now.isoformat(),
    }
    fits = {**base, "animal_type": "dog", "impression_type": "tofu",
            "preferred_animal_types": ["bear"], "preferred_impression_types": ["arab"]}
    misses = {**base, "animal_type": "cat", "impression_type": "chic",
              "preferred_animal_types": ["fox"], "preferred_impression_types": ["kind"]}

    assert round(final_score(owner, fits), 4) == NO_FACETS
    assert round(final_score(owner, misses), 4) == round(NO_FACETS - 0.075, 4)


def test_final_score_adds_the_mbti_fit_instead_of_multiplying():
    """내가 E 만 골랐는데 상대가 ISTJ 면 적합 √0.75 — 가중합에서 0.075 × (1 − √0.75) 만 빠진다."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": "ENFP", "preferred_mbti_flags": {"E": True}, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": "ISTJ",
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "last_active_at": now.isoformat(),
    }

    assert round(final_score(owner, candidate), 4) == round(NO_FACETS - 0.075 * (1 - math.sqrt(0.75)), 4)


def test_each_part_carries_its_own_weight():
    """E7 + 0번 분배(성향 0.25 · 태그 0.10 · 글 0.45 · 글 정리 0.05 · MBTI 0.075 · 얼굴 0.075)를 고정한다 — 한 칸만 1 이고
    나머지가 0 이면 그 칸의 비중이 나온다. MBTI · 얼굴은 적합 0 을 만들 수 없어(모르면 1.0) 다 맞음으로 두고 그 몫(0.15)을 함께 더한다.
    글 정리는 두 사람 모두 카페를 싫어하는데 카페를 좋아하는 상대를 원하게 두어 양방향 0 을 만든다."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
    }
    base = {
        "trait_score": 0.0, "tag_score": 0.0, "text_score": 0.0, "mbti": None,
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "last_active_at": now.isoformat(),
    }

    owner = {**owner, "self_facets": CAFE_HATER, "want_facets": CAFE_LOVER}
    base = {**base, "self_facets": CAFE_HATER, "want_facets": CAFE_LOVER}

    assert round(final_score(owner, base), 4) == 0.15
    assert round(final_score(owner, {**base, "trait_score": 1.0}), 4) == 0.40
    assert round(final_score(owner, {**base, "tag_score": 1.0}), 4) == 0.25
    assert round(final_score(owner, {**base, "text_score": 1.0}), 4) == 0.60
    assert round(final_score(owner, {**base, "self_facets": CAFE_LOVER, "want_facets": CAFE_HATER}), 4) == 0.20


def test_final_score_adds_the_text_facets_as_five_percent_both_ways():
    """글 정리 일치는 양방향 평균 × 0.05 — 내가 원하는 카페를 상대가 싫다고 적었으면 그 방향이 0 이다(임베딩은 못 가르는 부정)."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
        "self_facets": CAFE_HATER, "want_facets": CAFE_LOVER,
    }
    base = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": None,
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "last_active_at": now.isoformat(),
    }

    assert round(final_score(owner, {**base, "self_facets": CAFE_LOVER, "want_facets": CAFE_HATER}), 4) == 1.0
    assert round(final_score(owner, {**base, "self_facets": CAFE_HATER, "want_facets": CAFE_HATER}), 4) == 0.975
    assert round(final_score(owner, {**base, "self_facets": CAFE_HATER, "want_facets": CAFE_LOVER}), 4) == 0.95
    assert round(final_score(owner, base), 4) == NO_FACETS


def test_age_coefficient_uses_age_not_birth_year():
    this_year = datetime.now(SEOUL).year
    owner = {
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None,
        "birth_year": this_year - 25, "preferred_age_min": 22, "preferred_age_max": 27,
        "is_smoker": True, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": None,
        "preferred_mbti_flags": {}, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": this_year - 28, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": True, "religion": "none",
        "last_active_at": datetime.now(timezone.utc).isoformat(),
    }

    assert round(final_score(owner, candidate), 4) == round(NO_FACETS * math.sqrt(0.85), 4)


def test_rank_sorts_by_final_score():
    now = datetime.now(timezone.utc).isoformat()
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
    }
    base = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
        "last_active_at": now, "tag_score": 0, "text_score": 0,
    }
    ranked = rank(owner, [
        {**base, "candidate_id": "low", "trait_score": 0.1},
        {**base, "candidate_id": "high", "trait_score": 0.9},
    ])

    assert [c["candidate_id"] for c in ranked] == ["high", "low"]
    assert ranked[0]["score"] > ranked[1]["score"]


def _plain_pair():
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": None,
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": False, "religion": "none", "last_active_at": now.isoformat(),
    }
    return owner, candidate


def test_final_score_multiplies_a_text_taste_clash_by_zero_point_six():
    """글 속 취향이 부딪히면(10-30 — 좋아함 ↔ 싫어함) 총점에 ×0.6. 흡연 · 종교 감점과 같은 곱하기 자리다."""
    owner, candidate = _plain_pair()

    assert round(final_score(owner, {**candidate, "taste_clash": True}), 4) == round(NO_FACETS * 0.6, 4)
    assert round(final_score(owner, {**candidate, "taste_clash": False}), 4) == NO_FACETS


def test_final_score_without_the_taste_clash_key_is_unchanged():
    """칸이 아예 없는 후보(옛 가짜 · 부딪힘 계산을 못 한 경우)는 지금 점수 그대로다 — 가점도 감점도 없다."""
    owner, candidate = _plain_pair()

    assert "taste_clash" not in candidate
    assert round(final_score(owner, candidate), 4) == NO_FACETS


def test_final_score_taste_clash_stacks_with_the_other_penalties():
    owner, candidate = _plain_pair()
    smoker = {**candidate, "is_smoker": True, "taste_clash": True}

    # 흡연 0.5 × 부딪힘 0.6
    assert round(final_score(owner, smoker), 4) == round(NO_FACETS * 0.5 * 0.6, 4)
