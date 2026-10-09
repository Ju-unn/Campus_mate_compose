"""카드 뽑기 구간 규칙. 1등을 그대로 주지 않고 상위 구간 안에서 무작위로 고른다.

순위는 본 사람까지 포함한 전체 후보로 매기고, 본 사람(쉼·결정 전·매칭됨 = `pickable` False)은 뽑을
때만 뺀다. 구간을 남은 사람 기준으로 다시 재면 볼수록 구간이 아래로 내려가 1등만 주던 옛 방식과 같은
문제가 생기기 때문이다. 순수 함수만 둔다 — DB·네트워크·전역 상태 없이 난수 발생기를 인자로 받는다."""

import math
import random

from app.matching.scoring import rank

# 출처: 카드 구간 뽑기 설계(사용자 승인) — 무료 상위 80%, 유료 상위 20%, 구간은 최소 5명.
FREE_BAND_RATIO = 0.8
PAID_BAND_RATIO = 0.2
BAND_MINIMUM = 5


def band_size(total: int, ratio: float, minimum: int = BAND_MINIMUM) -> int:
    """전체 후보 total 명에서 구간 크기 = max(ceil(total × ratio), min(minimum, total))."""
    if not 0 < ratio <= 1:
        raise ValueError(f"ratio must be in (0, 1], got {ratio}")
    if total <= 0:
        return 0
    return max(math.ceil(total * ratio), min(minimum, total))


def rank_all(owner: dict, candidates: list[dict]) -> list[dict]:
    """scoring.rank 를 감싸 동점을 candidate_id 오름차순으로 고정한다(같은 입력 → 같은 출력)."""
    by_id = sorted(rank(owner, candidates), key=lambda c: str(c["candidate_id"]))
    return sorted(by_id, key=lambda c: c["score"], reverse=True)


def pick_from_band(
    ranked: list[dict],
    ratio: float,
    rng: random.Random,
    exclude: frozenset = frozenset(),
    minimum: int = BAND_MINIMUM,
) -> dict | None:
    """전체 순위 앞쪽 band_size 명 중 pickable 이고 exclude 에 없는 사람에서 균등 무작위 1명. 없으면 None."""
    band = ranked[: band_size(len(ranked), ratio, minimum)]
    # pickable 이 빠진 후보는 KeyError 로 드러낸다 — 기본값 True 로 읽으면 쉬는 사람이 조용히 다시 나온다.
    eligible = [c for c in band if c["pickable"] and c["candidate_id"] not in exclude]
    return rng.choice(eligible) if eligible else None
