from collections.abc import Sequence
from datetime import datetime, time, timedelta

# 설계 §2.1 + 2026-09-21 사용자 확정. ISO 요일(1=월 … 7=일).
TWICE_A_WEEK = [1, 4]        # 월 · 목
THREE_TIMES_A_WEEK = [1, 3, 5]  # 월 · 수 · 금
EVERY_DAY = [1, 2, 3, 4, 5, 6, 7]


def ladder_weekdays(active_count: int, three_per_week_min: int, daily_min: int) -> list[int]:
    """활성 인원이 많을수록 자주 준다. 임계값은 region_group_settings 가 들고 있어 배포 없이 바꾼다."""
    if active_count >= daily_min:
        return list(EVERY_DAY)
    if active_count >= three_per_week_min:
        return list(THREE_TIMES_A_WEEK)
    return list(TWICE_A_WEEK)


def bottleneck_count(counts: dict[str, int]) -> int:
    """남녀 중 적은 쪽이 후보 풀의 두께다. 한쪽이 아예 없으면 0 이다."""
    return min(counts.get("male", 0), counts.get("female", 0))


def next_issue_at(now: datetime, weekdays: Sequence[int], issue_time: time) -> datetime:
    """오늘 다음으로 카드가 나가는 시각. 무료 카드의 expires_at 이 이 값이다(설계 §2.4)."""
    for ahead in range(1, 8):
        day = (now + timedelta(days=ahead)).date()
        if day.isoweekday() in weekdays:
            return datetime.combine(day, issue_time, tzinfo=now.tzinfo)
    raise ValueError(f"지급 요일이 비어 있다: {weekdays!r}")
