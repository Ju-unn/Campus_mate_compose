import math

# 설계 §6.2 는 "축별 가중치를 저장 전에 곱한다"까지만 정하고 값은 조각 3·4 로 미뤘다. 지금은 전 축 균등
# 1.0 으로 시작한다 — 실제 데이터를 보고 조정할 때 이 표 한 곳만 고치면 된다.
# 값을 바꾸면 match_candidates SQL 의 상수 5.657 도 MAX_SURVEY_DISTANCE 로 맞춰 바꿔야 한다.
AXIS_WEIGHTS = {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0, 7: 1.0, 8: 1.0, 9: 1.0}

SHYNESS_AXIS = 2  # 낯가림. 유유상종이 아니라 다를수록 좋은 축이라 같은 L2 에 넣지 않는다.
_VECTOR_AXES = [axis for axis in sorted(AXIS_WEIGHTS) if axis != SHYNESS_AXIS]

# 각 축이 [-w, +w] 라서 한 축의 최대 차이는 2w, 전체는 그 유클리드 합이다.
MAX_SURVEY_DISTANCE = 2 * math.sqrt(sum(AXIS_WEIGHTS[axis] ** 2 for axis in _VECTOR_AXES))


def survey_vector(answers: dict[int, float]) -> tuple[list[float], float | None]:
    vector = [float(answers.get(axis, 0)) * AXIS_WEIGHTS[axis] for axis in _VECTOR_AXES]
    shyness = answers.get(SHYNESS_AXIS)
    return vector, None if shyness is None else float(shyness)
