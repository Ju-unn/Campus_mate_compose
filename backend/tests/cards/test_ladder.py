from datetime import datetime, time

from app.cards.ladder import bottleneck_count, ladder_weekdays, next_issue_at
from app.profile_onboarding.schemas import SEOUL


def test_under_two_hundred_is_twice_a_week():
    assert ladder_weekdays(199, 200, 500) == [1, 4]


def test_two_hundred_is_three_times_a_week():
    assert ladder_weekdays(200, 200, 500) == [1, 3, 5]
    assert ladder_weekdays(499, 200, 500) == [1, 3, 5]


def test_five_hundred_is_every_day():
    assert ladder_weekdays(500, 200, 500) == [1, 2, 3, 4, 5, 6, 7]


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
