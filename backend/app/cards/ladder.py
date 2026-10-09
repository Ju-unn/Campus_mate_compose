from collections.abc import Sequence
from datetime import datetime, time, timedelta

# 설계 §2.1 + 2026-10-01 사용자 확정(결정 12). ISO 요일(1=월 … 7=일).
# 월요일은 모든 칸에 있다 — 코호트 첫 지급이 월 07:00 이다(universities.card_opens_at check).
ONCE_A_WEEK = [1]               # 월
TWICE_A_WEEK = [1, 4]           # 월 · 목
THREE_TIMES_A_WEEK = [1, 3, 5]  # 월 · 수 · 금
FOUR_TIMES_A_WEEK = [1, 3, 5, 7]  # 월 · 수 · 금 · 일
EVERY_DAY = [1, 2, 3, 4, 5, 6, 7]


def ladder_weekdays(active_count: int, twice_per_week_min: int, three_per_week_min: int,
                    four_per_week_min: int, daily_min: int) -> list[int]:
    """활성 인원이 많을수록 자주 준다. 임계값은 region_group_settings 가 들고 있어 배포 없이 바꾼다."""
    if active_count >= daily_min:
        return list(EVERY_DAY)
    if active_count >= four_per_week_min:
        return list(FOUR_TIMES_A_WEEK)
    if active_count >= three_per_week_min:
        return list(THREE_TIMES_A_WEEK)
    if active_count >= twice_per_week_min:
        return list(TWICE_A_WEEK)
    return list(ONCE_A_WEEK)


def bottleneck_count(counts: dict[str, int]) -> int:
    """남녀 중 적은 쪽이 후보 풀의 두께다. 한쪽이 아예 없으면 0 이다."""
    return min(counts.get("male", 0), counts.get("female", 0))


def _issue_times(now: datetime, weekdays: Sequence[int], issue_time: time, days) -> list[datetime]:
    """now 의 날짜에서 days 만큼 떨어진 날 중 지급 요일인 날의 지급 시각들(days 순서 그대로)."""
    times = []
    for offset in days:
        day = (now + timedelta(days=offset)).date()
        if day.isoweekday() in weekdays:
            times.append(datetime.combine(day, issue_time, tzinfo=now.tzinfo))
    return times


def next_issue_at(now: datetime, weekdays: Sequence[int], issue_time: time) -> datetime:
    """오늘 다음으로 카드가 나가는 시각. 무료 카드의 expires_at 이 이 값이다(설계 §2.4)."""
    for issued in _issue_times(now, weekdays, issue_time, range(1, 8)):
        return issued
    raise ValueError(f"지급 요일이 비어 있다: {weekdays!r}")


def last_issue_at(now: datetime, weekdays: Sequence[int], issue_time: time) -> datetime:
    """now 이하인 가장 최근 지급 시각 — 유료 카드 제안의 "이번 주기"(paid_card_offers.cycle_started_at).

    오늘이 지급 요일이라도 지급 시각 전이면 지난 지급일이다. 사다리가 바뀌면 weekdays 가 바뀌므로 주기 시작도
    따라 바뀐다(주 1회 → 매일로 오르면 수요일의 주기 시작이 월요일에서 수요일이 된다)."""
    for issued in _issue_times(now, weekdays, issue_time, range(0, -8, -1)):
        if issued <= now:
            return issued
    raise ValueError(f"지급 요일이 비어 있다: {weekdays!r}")
