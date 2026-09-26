"""최종점수(설계 §6.7)의 감점 계수 부분. 점수 3종(성향·태그·문장)은 SQL 이 이미 계산해 온다.

계수를 SQL 이 아니라 여기서 곱하는 이유: MBTI 8극 토글·범위 벗어남 단계처럼 분기가 많은 규칙이라
설계 §6.4·§6.5 의 판정 표를 그대로 단위 테스트로 옮길 수 있는 쪽이 낫다. 후보 수가 커져 파이썬
정렬이 느려지면 이 모듈의 규칙을 SQL 함수로 내린다."""

import math
from datetime import datetime, timezone

from app.core.time import SEOUL

_AXES = (("E", "I"), ("N", "S"), ("T", "F"), ("J", "P"))


def _fit(flags: dict, mbti: str) -> float:
    """상대 4글자 중 내가 ok 로 둔 글자 비율. 한 축에서 양쪽을 다 끄면 그 축은 보지 않는다(설계 §6.4).
    앱은 켠 극만 보내므로 빠진 키는 꺼진 것으로 읽는다 — {} 는 전부 꺼짐 = 전부 상관없음."""
    ok = 0
    for left, right in _AXES:
        left_ok, right_ok = flags.get(left, False), flags.get(right, False)
        if left_ok == right_ok:  # 둘 다 ok 거나 둘 다 no = 상관없음
            ok += 1
        elif (left in mbti and left_ok) or (right in mbti and right_ok):
            ok += 1
    return ok / 4


def mbti_coefficient(
    my_flags: dict, partner_mbti: str | None, partner_flags: dict, my_mbti: str | None
) -> float:
    if not partner_mbti or not my_mbti:
        return 1.00
    both = math.sqrt(_fit(my_flags, partner_mbti) * _fit(partner_flags, my_mbti))
    return 0.6 + 0.4 * both


def _one_way_range(value: int | None, low: int | None, high: int | None, near: int) -> float:
    """범위 안 1.00 / near 이내로 벗어나면 0.85 / 그 밖은 0.70 / 범위 미지정은 1.00(설계 §6.5·§6.7)."""
    if value is None or (low is None and high is None):
        return 1.00
    over = max((low - value) if low is not None else 0, (value - high) if high is not None else 0)
    if over <= 0:
        return 1.00
    return 0.85 if over <= near else 0.70


def range_coefficient(
    my_value: int | None, my_low: int | None, my_high: int | None,
    partner_value: int | None, partner_low: int | None, partner_high: int | None, near: int,
) -> float:
    return math.sqrt(
        _one_way_range(partner_value, my_low, my_high, near)
        * _one_way_range(my_value, partner_low, partner_high, near)
    )


def activity_coefficient(last_active_at: datetime | str) -> float:
    if isinstance(last_active_at, str):
        last_active_at = datetime.fromisoformat(last_active_at)
    # 여기는 일부러 벽시계다 — 경계가 일 단위라 요청 안에서 갈릴 일이 없고, 시각에 걸린 푸시도 없다.
    days = (datetime.now(timezone.utc) - last_active_at).days
    if days <= 3:
        return 1.0
    if days <= 7:
        return 0.7
    return 0.4  # 15일 이상은 SQL 하드 필터에서 이미 빠졌다


def _age(profile: dict) -> int | None:
    """설계 §6.1 의 나이는 만 나이가 아니라 "올해 − 태어난 해"다(가입 자격 계산과 같은 기준)."""
    birth_year = profile.get("birth_year")
    # 여기도 일부러 벽시계다 — 경계가 해 단위다. 요청 경로이긴 하지만 시각에 따라 갈리는 동작이 없다.
    return None if birth_year is None else datetime.now(SEOUL).year - birth_year


def final_score(owner: dict, candidate: dict) -> float:
    weighted = (
        0.3 * float(candidate["trait_score"])
        + 0.2 * float(candidate["tag_score"])
        + 0.5 * float(candidate["text_score"])
    )
    smoking = 0.5 if owner["is_smoker"] is False and candidate["is_smoker"] is True else 1.0
    religion = 0.8 if owner["religion"] != candidate["religion"] else 1.0
    return (
        weighted
        * mbti_coefficient(
            owner["preferred_mbti_flags"] or {}, candidate["mbti"],
            candidate["preferred_mbti_flags"] or {}, owner["mbti"],
        )
        * range_coefficient(
            owner["height_cm"], owner["preferred_height_min"], owner["preferred_height_max"],
            candidate["height_cm"], candidate["preferred_height_min"],
            candidate["preferred_height_max"], near=5,
        )
        # 선호는 "나이"인데 컬럼은 "태어난 해"라 부호가 반대다 — 나이로 바꿔 넘긴다.
        * range_coefficient(
            _age(owner), owner["preferred_age_min"], owner["preferred_age_max"],
            _age(candidate), candidate["preferred_age_min"], candidate["preferred_age_max"],
            near=2,
        )
        * smoking
        * religion
        * activity_coefficient(candidate["last_active_at"])
    )


def rank(owner: dict, candidates: list[dict]) -> list[dict]:
    scored = [{**c, "score": final_score(owner, c)} for c in candidates]
    return sorted(scored, key=lambda c: c["score"], reverse=True)
