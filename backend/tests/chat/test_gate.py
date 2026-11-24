from datetime import datetime, timedelta, timezone

import pytest

from app.chat import gate
from app.core.time import SEOUL


def _at(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 9, day, hour, minute, tzinfo=SEOUL)


def test_deadline_is_72_hours_after_the_match():
    """24시간 뒤 창이 뜨고 그 뒤로 48시간을 더 준다(사용자 11-24) — 시계는 매칭 시각 하나다."""
    assert gate.deadline_at(_at(21, 13)) == _at(24, 13)


def test_remaining_goes_negative_after_the_deadline():
    assert gate.remaining(_at(21, 13), _at(22, 13)) == timedelta(hours=48)
    assert gate.remaining(_at(21, 13), _at(23, 14)) == timedelta(hours=23)  # 옛 48시간 마감을 지나도 남아 있다
    assert gate.remaining(_at(21, 13), _at(24, 13)) == timedelta(0)
    assert gate.remaining(_at(21, 13), _at(24, 14)).total_seconds() < 0


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
    runs = (midnight + timedelta(hours=i, seconds=delay) for i in range(int(gate.GATE_DEADLINE / timedelta(hours=1)) + 24))
    return [t for t in runs if created <= t < deadline]


def _is_quiet(moment: datetime) -> bool:
    return moment.hour >= 22 or moment.hour < 8


def test_a_21_30_match_is_reminded_once_at_the_next_morning_batch():
    """리마인드 기본 시각이 21:30 이면 그 창(21:30~22:30)에 걸리는 정각은 22:00 뿐인데, 방해 금지를 켠 사람에게는 그 시각에 버려진다.
    아침 08:00 까지 미룬다 — 마감(매칭 72시간 뒤 21:30) 안이다."""
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


# 마감 3시간 전 마지막 알림 ---------------------------------------------------------------

def test_last_call_lands_on_the_hour_three_hours_before_the_deadline():
    """기본은 마감 - 3시간을 정각으로 내린 창이다 — 받는 사람에게 3시간 이상 남는다. 매칭 69시간 뒤 쪽이다."""
    assert gate.last_call_at(_at(20, 13, 20)) == _at(23, 10)  # 마감 23일 13:20
    assert gate.last_call_at(_at(20, 13, 0)) == _at(23, 10)   # 마감 23일 13:00 — 딱 3시간 전 = 매칭 69시간 뒤


def test_last_call_window_fires_once_on_the_hourly_batch():
    created = _at(20, 13, 20)

    assert gate.needs_last_call(created, _at(22, 10).replace(second=2), responded=False) is False  # 옛 48시간 자리
    assert gate.needs_last_call(created, _at(23, 9), responded=False) is False
    assert gate.needs_last_call(created, _at(23, 10).replace(second=2), responded=False) is True
    assert gate.needs_last_call(created, _at(23, 11), responded=False) is False


def test_the_24_hour_reminder_stays_at_24_hours_with_the_longer_deadline():
    created = _at(20, 13, 20)
    assert gate.reminder_at(created) == _at(21, 13, 20)
    assert [t for t in _hourly_batches(created) if gate.needs_reminder(created, t, responded=False)] == [_at(21, 14)]


def test_people_who_already_answered_get_no_last_call():
    assert gate.needs_last_call(_at(20, 13, 20), _at(23, 10), responded=True) is False


def test_no_last_call_at_or_after_the_deadline():
    created = _at(20, 13, 20)
    assert gate.needs_last_call(created, gate.deadline_at(created), responded=False) is False
    assert gate.needs_last_call(created, gate.deadline_at(created) + timedelta(hours=1), responded=False) is False


@pytest.mark.parametrize(("deadline", "last_call"), [
    # 기본 시각(마감 - 3시간)이 21:59 → 21시 창 그대로.
    ((22, 0, 59), (21, 21)),
    # 22:00 → 조용한 시간이라 같은 날 21:00 으로 앞당긴다(뒤로 밀면 마감을 넘긴다).
    ((22, 1, 0), (21, 21)),
    # 23:30 → 21:00.
    ((22, 2, 30), (21, 21)),
    # 새벽(0~7시)이면 그날 08:00 창에 보내도 마감까지 2시간 이상 남을 때 08:00 — 14시간 전보다 "3시간 전" 뜻에 가깝다.
    ((22, 10, 59), (22, 8)),  # 07:59 → 08:00(마감까지 2시간 59분)
    ((22, 10, 0), (22, 8)),   # 07:00 → 08:00(딱 2시간)
    # 2시간 미만이면 전날 21:00.
    ((22, 9, 59), (21, 21)),  # 06:59 → 08:00 이면 1시간 59분이라 안 된다
    ((22, 8, 30), (21, 21)),
    # 08:00 → 08시 창 그대로.
    ((22, 11, 0), (22, 8)),
])
def test_a_last_call_in_the_quiet_hours_moves_to_8_or_back_to_21(deadline, last_call):
    created = _at(*deadline) - gate.GATE_DEADLINE

    assert gate.last_call_at(created) == _at(*last_call)


def test_a_last_call_that_would_collide_with_the_24_hour_reminder_is_dropped(monkeypatch):
    """지금 상수로는 둘이 10시간 넘게 떨어져 있지만(아래 전수 시험), 마감이 짧아지면 같은 배치에 두 번 갈 수 있다 —
    그때는 마지막 알림을 버린다."""
    monkeypatch.setattr(gate, "GATE_DEADLINE", timedelta(hours=27))  # 마지막 알림 기본 = 매칭 24시간 뒤 = 리마인드와 같은 창
    created = _at(20, 13, 0)

    assert gate.needs_reminder(created, _at(21, 13), responded=False) is True
    assert [t for t in _hourly_batches(created) if gate.needs_last_call(created, t, responded=False)] == []


@pytest.mark.parametrize("delay", [0, 2, 30])
@pytest.mark.parametrize("second", [0, 1, 59])
def test_every_match_gets_exactly_one_last_call_well_after_the_reminder(second, delay):
    """분 단위로 매칭 시각을 전부 훑는다 — 마지막 알림은 딱 한 번, 조용한 시간 밖, 마감 2시간 이상 전(창 시작 기준 —
    배치가 늦은 만큼만 모자랄 수 있다), 24시간 리마인드보다 10시간 이상 뒤에 간다."""
    for minute_of_day in range(24 * 60):
        created = _at(20, minute_of_day // 60, minute_of_day % 60).replace(second=second)
        batches = _hourly_batches(created, delay)
        reminder = [t for t in batches if gate.needs_reminder(created, t, responded=False)]
        last = [t for t in batches if gate.needs_last_call(created, t, responded=False)]

        label = f"{created:%H:%M:%S} 매칭 · 배치 +{delay}초"
        assert len(last) == 1, f"{label}: 마지막 알림 {len(last)}번 {last}"
        assert not _is_quiet(last[0]), f"{label}: 조용한 시간 {last[0]:%H:%M:%S}"
        assert gate.remaining(created, last[0]) >= timedelta(hours=2, seconds=-delay), f"{label}: 마감에 너무 가깝다 {last[0]}"
        assert last[0] - reminder[0] >= timedelta(hours=10), f"{label}: 리마인드 {reminder[0]} 와 가깝다 {last[0]}"


def test_a_utc_match_time_gets_the_same_last_call_as_seoul():
    """DB 의 created_at 은 UTC(+00:00)로 온다 — 조용한 시간 · 08:00 · 21:00 은 서울 시각으로 따져야 한다."""
    for minute_of_day in range(24 * 60):
        seoul = _at(20, minute_of_day // 60, minute_of_day % 60)
        utc = seoul.astimezone(timezone.utc)

        assert gate.last_call_at(utc) == gate.last_call_at(seoul), f"{seoul:%H:%M} 매칭"
        assert gate.last_call_at(utc).astimezone(SEOUL).hour in range(8, 22), f"{seoul:%H:%M} 매칭"
