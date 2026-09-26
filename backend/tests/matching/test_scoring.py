import math
from datetime import datetime, timedelta, timezone

from app.core.time import SEOUL
from app.matching.scoring import activity_coefficient, final_score, mbti_coefficient, rank

# 설계 §6.4 판정 예시: 내 설정이 E ok, I ok, N ok, S no, T ok, F no, J ok, P ok
MY_FLAGS = {"E": True, "I": True, "N": True, "S": False, "T": True, "F": False, "J": True, "P": True}
ALL_OK = {}
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


def test_activity_coefficient_steps():
    now = datetime.now(timezone.utc)
    assert activity_coefficient(now - timedelta(days=1)) == 1.0
    assert activity_coefficient(now - timedelta(days=5)) == 0.7
    assert activity_coefficient(now - timedelta(days=10)) == 0.4


def test_final_score_multiplies_weighted_sum_by_every_coefficient():
    """가중합 0.3/0.2/0.5 에 계수를 전부 곱한다(설계 §6.7)."""
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

    # 가중합 1.0 × MBTI 1.0 × 키 1.0 × 나이 1.0 × 흡연 0.5(비흡연자에게 흡연자) × 종교 0.8 × 활동성 1.0
    assert round(final_score(owner, candidate), 4) == 0.40


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

    assert round(final_score(owner, candidate), 4) == round(math.sqrt(0.85), 4)


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
