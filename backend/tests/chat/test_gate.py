from datetime import datetime, timedelta

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
