import math

# 설계 §6.2 는 "축별 가중치를 저장 전에 곱한다"까지만 정하고 값은 조각 3·4 로 미뤘다. 처음엔 전 축 균등
# 1.0 이었다 — 실제 데이터를 보고 조정할 때 이 표 한 곳만 고치면 된다.
# 값을 바꾸면 match_candidates SQL 의 상수 4.472 도 MAX_SURVEY_DISTANCE 로 맞춰 바꿔야 한다.
# 10-28: 성격형 축(1 활동성 · 3 계획성 · 5 감정표현 · 9 새로움)은 0.5, 생활 습관 축(4 연락 · 6 음주 · 7 운동 · 8 관계 속도)은 1.0.
# 성격이 닮는 것은 첫 끌림과 관계가 없고(Humberg 2023), 생활 · 가치가 닮는 쪽이 커플 유사성에서 크다(Luo 2017).
AXIS_WEIGHTS = {1: 0.5, 2: 1.0, 3: 0.5, 4: 1.0, 5: 0.5, 6: 1.0, 7: 1.0, 8: 1.0, 9: 0.5}

SHYNESS_AXIS = 2  # 낯가림. 유유상종이 아니라 다를수록 좋은 축이라 같은 L2 에 넣지 않는다.
_VECTOR_AXES = [axis for axis in sorted(AXIS_WEIGHTS) if axis != SHYNESS_AXIS]

# 각 축이 [-w, +w] 라서 한 축의 최대 차이는 2w, 전체는 그 유클리드 합이다.
MAX_SURVEY_DISTANCE = 2 * math.sqrt(sum(AXIS_WEIGHTS[axis] ** 2 for axis in _VECTOR_AXES))


def survey_vector(answers: dict[int, float]) -> tuple[list[float], float | None]:
    vector = [float(answers.get(axis, 0)) * AXIS_WEIGHTS[axis] for axis in _VECTOR_AXES]
    shyness = answers.get(SHYNESS_AXIS)
    return vector, None if shyness is None else float(shyness)
