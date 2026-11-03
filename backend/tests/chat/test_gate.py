from datetime import datetime, timedelta

import pytest

from app.chat import gate
from app.core.time import SEOUL


def _at(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 9, day, hour, minute, tzinfo=SEOUL)


def test_deadline_is_48_hours_after_the_match():
    assert gate.deadline_at(_at(21, 13)) == _at(23, 13)


def test_remaining_goes_negative_after_the_deadline():
    assert gate.remaining(_at(21, 13), _at(22, 13)) == timedelta(hours=24)
    assert gate.remaining(_at(21, 13), _at(23, 14)).total_seconds() < 0


def test_gate_passes_only_when_both_accepted():
    assert gate.is_passed(["accept", "accept"]) is True
    assert gate.is_passed(["accept", None]) is False
    assert gate.is_passed([None, None]) is False
    # 한 사람만 있는 매칭은 있을 수 없다 — 그래도 통과로 새지 않게 막는다.
    assert gate.is_passed(["accept"]) is False


def test_reminder_lands_24_hours_later_at_a_normal_hour():
    assert gate.reminder_at(_at(21, 13, 20)) == _at(22, 13, 20)


def test_reminder_at_dawn_is_pushed_to_the_morning():
    """새벽에 걸린 리마인드를 그대로 두면 조용한 시간에 버려지는데, 창이 한 번뿐이라 영영 안 온다."""
    # 매칭이 새벽 3시 → 24시간 뒤도 새벽 3시다. 같은 날 아침 8시로 민다.
    assert gate.reminder_at(_at(20, 3, 40)) == _at(21, 8)
    # 밤 23시 → 다음 날 아침 8시로 민다.
    assert gate.reminder_at(_at(20, 23, 10)) == _at(22, 8)


def test_reminder_window_fires_once_on_the_hourly_batch():
    created = _at(20, 13, 20)  # 리마인드 시각은 21일 13:20

    assert gate.needs_reminder(created, _at(21, 13), responded=False) is False  # 아직 이르다
    assert gate.needs_reminder(created, _at(21, 14), responded=False) is True   # 창 안의 유일한 정각
    assert gate.needs_reminder(created, _at(21, 15), responded=False) is False  # 창을 지났다


def test_already_accepted_people_are_not_reminded():
    created = _at(20, 13, 20)
    assert gate.needs_reminder(created, _at(21, 14), responded=True) is False


def test_dawn_match_is_reminded_on_the_morning_batch():
    created = _at(20, 3, 40)
    assert gate.needs_reminder(created, _at(21, 3), responded=False) is False
    assert gate.needs_reminder(created, _at(21, 8), responded=False) is True


def _hourly_batches(created: datetime, delay: int = 0) -> list[datetime]:
    """매시 정각 배치 중 매칭 뒤 ~ 기한 전(기한이 지나면 리마인드 대신 방이 닫힌다) 것.
    [delay] 초는 스케줄러 호출이 정각보다 늦게 도는 만큼이다 — 실제 배치의 now 는 hh:00:00 이 아니라 hh:00:02 쯤이다."""
    midnight = created.replace(hour=0, minute=0, second=0, microsecond=0)
    deadline = gate.deadline_at(created)
    runs = (midnight + timedelta(hours=i, seconds=delay) for i in range(72))
    return [t for t in runs if created <= t < deadline]


def _is_quiet(moment: datetime) -> bool:
    return moment.hour >= 22 or moment.hour < 8


def test_a_21_30_match_is_reminded_once_at_the_next_morning_batch():
    """리마인드 기본 시각이 21:30 이면 그 창(21:30~22:30)에 걸리는 정각은 22:00 뿐인데, 방해 금지를 켠 사람에게는 그 시각에 버려진다.
    아침 08:00 까지 미룬다 — 마감(매칭 48시간 뒤 21:30) 안이다."""
    created = _at(20, 21, 30)  # 기본 시각은 21일 21:30

    assert gate.reminder_at(created) == _at(22, 8)
    assert gate.needs_reminder(created, _at(21, 22), responded=False) is False  # 예전에는 여기서 True 였다
    assert gate.needs_reminder(created, _at(22, 8), responded=False) is True
    assert gate.needs_reminder(created, _at(22, 9), responded=False) is False
    assert [t for t in _hourly_batches(created) if gate.needs_reminder(created, t, responded=False)] == [_at(22, 8)]


def test_a_21_00_match_is_still_reminded_at_21_00():
    """정각이면 그 정각 배치가 바로 보내고 조용한 시간도 아니다 — 미룰 이유가 없다."""
    created = _at(20, 21, 0)

    assert gate.reminder_at(created) == _at(21, 21)
    assert gate.needs_reminder(created, _at(21, 21), responded=False) is True
    assert gate.needs_reminder(created, _at(21, 22), responded=False) is False


def test_a_reminder_due_in_the_7_oclock_hour_waits_for_8_even_when_the_batch_runs_a_few_seconds_late():
    """07:00:01 이 기본 시각이면 07시 배치(07:00:02)가 창에 걸리는데 조용한 시간이라 버려진다 — 07시대 전체를 08:00 으로 민다."""
    for base in (_at(21, 7, 0), _at(21, 7, 0).replace(second=1), _at(21, 7, 30), _at(21, 7, 59).replace(second=59)):
        created = base - timedelta(hours=24)

        assert gate.reminder_at(created) == _at(21, 8), base
        assert gate.needs_reminder(created, _at(21, 7).replace(second=2), responded=False) is False, base
        assert gate.needs_reminder(created, _at(21, 8).replace(second=2), responded=False) is True, base


@pytest.mark.parametrize("delay", [0, 2, 30])
@pytest.mark.parametrize("second", [0, 1, 59])
def test_every_match_gets_exactly_one_reminder_on_a_batch_outside_the_quiet_hours(second, delay):
    """분 단위로 매칭 시각을 전부 훑는다 — 어느 시각에 매칭돼도 방해 금지에 걸리지 않는 정각 배치에서 딱 한 번, 마감 전에 간다.
    배치가 정각보다 몇 초 늦게 돌아도(delay) 같다."""
    for minute_of_day in range(24 * 60):
        created = _at(20, minute_of_day // 60, minute_of_day % 60).replace(second=second)
        fires = [t for t in _hourly_batches(created, delay) if gate.needs_reminder(created, t, responded=False)]

        assert len(fires) == 1, f"{created:%H:%M:%S} 매칭 · 배치 +{delay}초: 리마인드가 {len(fires)}번 {fires}"
        assert not _is_quiet(fires[0]), f"{created:%H:%M:%S} 매칭 · 배치 +{delay}초: 조용한 시간 {fires[0]:%H:%M:%S} 에 걸린다"
