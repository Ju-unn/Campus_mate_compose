import math

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


def test_max_distance_matches_the_weights():
    """최대가능거리는 가중치에서 계산한다 — SQL 상수 5.657 과 같아야 한다(설계 §6.2)."""
    expected = 2 * math.sqrt(sum(w * w for a, w in AXIS_WEIGHTS.items() if a != 2))

    assert MAX_SURVEY_DISTANCE == expected
    assert round(MAX_SURVEY_DISTANCE, 3) == 5.657
