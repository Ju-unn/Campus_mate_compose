from datetime import datetime, time

from app.cards.ladder import bottleneck_count, ladder_weekdays, next_issue_at
from app.core.time import SEOUL


# 결정 12(10-01 사용자 표)의 기준값. 운영 값은 region_group_settings 가 들고 있다.
THRESHOLDS = (50, 500, 1000, 2000)


def test_under_fifty_is_once_a_week_on_monday():
    """코호트 첫 지급이 월 07:00 이라(universities.card_opens_at check) 월요일은 모든 칸에 있다."""
    assert ladder_weekdays(0, *THRESHOLDS) == [1]
    assert ladder_weekdays(49, *THRESHOLDS) == [1]


def test_fifty_is_twice_a_week():
    assert ladder_weekdays(50, *THRESHOLDS) == [1, 4]
    assert ladder_weekdays(499, *THRESHOLDS) == [1, 4]


def test_five_hundred_is_three_times_a_week():
    assert ladder_weekdays(500, *THRESHOLDS) == [1, 3, 5]
    assert ladder_weekdays(999, *THRESHOLDS) == [1, 3, 5]


def test_thousand_is_four_times_a_week():
    assert ladder_weekdays(1000, *THRESHOLDS) == [1, 3, 5, 7]
    assert ladder_weekdays(1999, *THRESHOLDS) == [1, 3, 5, 7]


def test_two_thousand_is_every_day():
    assert ladder_weekdays(2000, *THRESHOLDS) == [1, 2, 3, 4, 5, 6, 7]


def test_all_zero_thresholds_mean_every_day():
    """E2E 그룹(결정 15)은 기준을 전부 0 으로 둔다 — 아무도 없어도 매일 나가야 한다."""
    assert ladder_weekdays(0, 0, 0, 0, 0) == [1, 2, 3, 4, 5, 6, 7]


def test_bottleneck_is_the_smaller_side():
    """남녀 각각 세고 적은 쪽으로 판정한다(2026-09-21 확정) — 많은 쪽에 맞추면 같은 사람이 계속 나온다."""
    assert bottleneck_count({"male": 300, "female": 150}) == 150


def test_missing_gender_counts_as_zero():
    assert bottleneck_count({"male": 300}) == 0


def test_next_issue_at_is_the_next_listed_weekday():
    monday_7am = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)  # 2026-09-21 은 월요일
    assert next_issue_at(monday_7am, [1, 4], time(7, 0)) == datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)


def test_next_issue_at_skips_today_even_when_today_is_an_issue_day():
    """오늘 07:00 지급 직후에 부르는 함수다 — 오늘이 또 나오면 카드가 즉시 만료된다."""
    monday_7am = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
    assert next_issue_at(monday_7am, [1, 2, 3, 4, 5, 6, 7], time(7, 0)).day == 22
