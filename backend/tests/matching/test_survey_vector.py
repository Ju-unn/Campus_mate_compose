import math
import re
from pathlib import Path

from app.matching.survey_vector import AXIS_WEIGHTS, MAX_SURVEY_DISTANCE, survey_vector


def test_survey_vector_drops_shyness_and_applies_weights():
    """axis 2(낯가림)는 벡터에서 빠지고 원값만 따로 돌려준다(설계 §6.2)."""
    answers = {1: 1.0, 2: -0.5, 3: 0.5, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0, 9: 1.0}

    vector, shyness = survey_vector(answers)

    assert len(vector) == 8
    assert shyness == -0.5
    assert vector[0] == 1.0 * AXIS_WEIGHTS[1]
    assert vector[7] == 1.0 * AXIS_WEIGHTS[9]


def test_survey_vector_treats_unanswered_axis_as_neutral():
    """온보딩은 9축을 다 받지만, 한 축이 비어도 500 대신 중립 0 으로 본다."""
    vector, shyness = survey_vector({1: 1.0})

    assert vector[1:] == [0.0] * 7
    assert shyness is None


def test_personality_axes_weigh_half_and_lifestyle_axes_full():
    """성격형(활동성 1 · 계획성 3 · 감정표현 5 · 새로움 9)은 0.5, 생활 습관(연락 4 · 음주 6 · 운동 7 · 관계 속도 8)은 1.0
    (10-28: 성격이 닮는 것은 첫 끌림과 관계가 없다는 연구 — Humberg 2023)."""
    assert {a: AXIS_WEIGHTS[a] for a in (1, 3, 5, 9)} == {1: 0.5, 3: 0.5, 5: 0.5, 9: 0.5}
    assert {a: AXIS_WEIGHTS[a] for a in (4, 6, 7, 8)} == {4: 1.0, 6: 1.0, 7: 1.0, 8: 1.0}


def test_the_latest_match_candidates_sql_divides_by_the_same_max_distance():
    """SQL 의 trait_score 나눗수와 파이썬 MAX_SURVEY_DISTANCE 가 어긋나면 성향 점수가 조용히 틀린다 — 마지막으로
    match_candidates 를 정의한 마이그레이션 파일에서 상수를 읽어 비교한다."""
    migrations = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
    latest = sorted(p for p in migrations.glob("*.sql") if "function public.match_candidates" in p.read_text(encoding="utf-8"))[-1]
    [constant] = re.findall(r"/ ([0-9.]+)\) as trait_score", latest.read_text(encoding="utf-8"))

    assert float(constant) == round(MAX_SURVEY_DISTANCE, 3)


def test_max_distance_matches_the_weights():
    """최대가능거리는 가중치에서 계산한다 — SQL 상수 4.472 와 같아야 한다(설계 §6.2)."""
    expected = 2 * math.sqrt(sum(w * w for a, w in AXIS_WEIGHTS.items() if a != 2))

    assert MAX_SURVEY_DISTANCE == expected
    assert round(MAX_SURVEY_DISTANCE, 3) == 4.472
