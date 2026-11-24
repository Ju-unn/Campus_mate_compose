"""신뢰 확인 게이트의 시각 판정(설계 §2.5).

시계는 `matches.created_at + 72시간` 하나뿐이다(자유 대화 48시간 뒤 시트 · 리마인드가 뜨고 그 뒤로 24시간 더, 사용자 11-24). "리마인드를 보냈다" 같은 상태 컬럼을 두지 않고
시각만 보고 판정한다 — 조각 4 의 카드 만료와 같은 방식이다. 전부 순수 함수라 테스트가 시계를
직접 넘긴다.
"""
from datetime import datetime, timedelta

from app.core.time import SEOUL

GATE_DEADLINE = timedelta(hours=72)
GATE_REMINDER_AFTER = timedelta(hours=48)
# 마감 전 마지막 알림(last_call_at) — 마감 몇 시간 전에 한 번 더 알리는가.
LAST_CALL_BEFORE = timedelta(hours=3)
# 새벽에 걸린 마지막 알림을 아침 08:00 으로 미룰 때 마감까지 남아야 하는 최소 시간. 모자라면 전날 21시로 앞당긴다.
LAST_CALL_MORNING_MIN = timedelta(hours=2)
# 리마인드를 밀어 넣을 아침 시각. push.py 의 조용한 시간(22~8시)과 같은 경계를 쓴다.
_QUIET_START_HOUR = 22
_QUIET_END_HOUR = 8


def deadline_at(created_at: datetime) -> datetime:
    """이 매칭의 응답 기한. 화면 14f 카운트다운·14h 배너가 이 시각에서 남은 시간을 뺀다."""
    return created_at + GATE_DEADLINE


def remaining(created_at: datetime, now: datetime) -> timedelta:
    """남은 시간. 음수면 기한이 지난 것이다."""
    return deadline_at(created_at) - now


def is_gone(participant: dict) -> bool:
    """이 참가자와는 대화를 이어 갈 수 없는가 — 나갔거나 정지 · 탈퇴했다(조각 6).

    정지 · 탈퇴는 left_at 을 찍지 않는다. 조회 시점 판정이라 대시보드에서 status 한 칸만 되돌리면 방이 그대로
    돌아온다(left_at 으로 구현하면 해제가 불가능해진다). 상대에게는 셋이 같은 모양으로 보인다 —
    정지 · 탈퇴 사실을 알리지 않는다. 방 머리말 · 보내기 · 게이트 수락 · 매시 배치가 모두 이 함수를 쓴다."""
    status = (participant.get("profiles") or {}).get("status")
    return bool(participant["left_at"]) or status in ("suspended", "withdrawn")


def is_passed(responses: list[str | None]) -> bool:
    """둘 다 accept 여야 통과다. 한 명이라도 미응답이면 아직 아니다.

    결정 10(미리 수락)으로 시트가 뜨기 전에도 통과할 수 있어서 이 함수는 시각을 보지 않는다.
    거절은 값으로 들어오지 않는다 — 거절은 채팅방 나가기다(결정 11)."""
    return len(responses) == 2 and all(response == "accept" for response in responses)


def reminder_at(created_at: datetime) -> datetime:
    """리마인드를 보낼 시각. 기본은 매칭 48시간 뒤(마감 24시간 전)인데, 실제로 보내지는 정각이 조용한 시간(22~8시)에 걸리면
    그다음 아침 8시로 민다.

    배치는 매시 정각에만 돌고 창은 [시각, 시각 + 1시간) 이라, 실제로 보내지는 때는 기본 시각을 정각으로 올림한 시각이다
    (정각이면 그대로). 21:30 이면 창에 걸리는 정각은 22:00 하나뿐이라 '시'(21)만 봐서는 놓친다.
    반대로 07시대(07:00:01 ~ 07:59:59)는 올림이 08:00 이라 괜찮아 보이지만, 스케줄러는 정각보다 몇 초 늦게 부르니
    07:00:02 배치가 창에 걸려 버려질 수 있다 — 기본 시각의 '시'가 8시 전이면 올림과 상관없이 08:00 으로 민다.
    미루지 않으면 그 리마인드가 notify() 의 조용한 시간 검사에 걸려 조용히 버려지는데, 창이 한 번뿐이라 영영 다시 오지 않는다.
    채팅 푸시와 달리 게이트 리마인드는 조용한 시간을 지킨다(결정 5 의 예외는 채팅 푸시뿐).

    밀어도 기본 시각에서 최대 11시간(21:00:01 → 다음 아침 08:00)이라 마감(매칭 72시간 뒤 = 기본 시각 + 24시간)보다 늘 이르다."""
    base = (created_at + GATE_REMINDER_AFTER).astimezone(SEOUL)
    hour_start = base.replace(minute=0, second=0, microsecond=0)
    fires_at = hour_start if base == hour_start else hour_start + timedelta(hours=1)
    if fires_at.hour >= _QUIET_START_HOUR:
        return (fires_at + timedelta(days=1)).replace(hour=_QUIET_END_HOUR)
    if base.hour < _QUIET_END_HOUR or fires_at.hour < _QUIET_END_HOUR:
        return fires_at.replace(hour=_QUIET_END_HOUR)
    return base


def needs_reminder(created_at: datetime, now: datetime, responded: bool) -> bool:
    """매시 배치용. reminder_at 부터 한 시간짜리 창에 걸릴 때만 True —
    창을 쓰면 "보냈다" 표시 컬럼 없이도 리마인드가 딱 한 번 간다.

    ponytail: 같은 시간 안에 배치를 두 번 돌리면 두 번 간다. 그것까지 막으려면 컬럼이 하나
    필요한데, 알림 한 건이 겹치는 것보다 컬럼과 마이그레이션이 더 비싸다."""
    if responded:
        return False
    start = reminder_at(created_at)
    return start <= now < start + timedelta(hours=1)


def last_call_at(created_at: datetime) -> datetime:
    """마감 전 마지막 알림을 보낼 시각. 기본은 마감 3시간 전을 정각으로 내린 것이다 — 받는 사람에게 3시간 이상 남는다.

    정각에서 시작하는 한 시간 창이라 배치가 몇 초 늦어도 그 정각 배치 하나만 걸리고, 그 배치의 '시'가 곧 이 시각의 '시'다.
    조용한 시간(22~8시)에 걸리면: 22~23시는 같은 날 21시로 앞당긴다(뒤로 밀면 마감을 넘긴다). 0~7시는 그날 08:00 창에 보내도
    마감까지 2시간 이상 남으면 08:00 — 전날 21시(최대 14시간 전)보다 "3시간 전" 뜻에 가깝다. 2시간 미만이면 전날 21시.
    어느 경우든 리마인드보다 10시간 넘게 뒤다 — tests/chat/test_gate.py 의 전수 시험이 못박는다."""
    deadline = deadline_at(created_at)
    base = (deadline - LAST_CALL_BEFORE).astimezone(SEOUL)
    start = base.replace(minute=0, second=0, microsecond=0)
    if start.hour < _QUIET_END_HOUR:
        morning = start.replace(hour=_QUIET_END_HOUR)
        if deadline - morning >= LAST_CALL_MORNING_MIN:
            return morning
        return (start - timedelta(days=1)).replace(hour=_QUIET_START_HOUR - 1)
    if start.hour >= _QUIET_START_HOUR:
        return start.replace(hour=_QUIET_START_HOUR - 1)
    return start


def needs_last_call(created_at: datetime, now: datetime, responded: bool) -> bool:
    """매시 배치용. last_call_at 부터 한 시간짜리 창 — needs_reminder 와 같은 방식으로 딱 한 번 간다.
    창이 리마인드 창과 겹치거나 그보다 이르면 보내지 않는다(같은 사람에게 같은 배치에서 두 번 금지).
    지금 상수로는 일어나지 않지만 GATE_DEADLINE 을 줄이면 일어난다."""
    if responded:
        return False
    start = last_call_at(created_at)
    if start < reminder_at(created_at) + timedelta(hours=1):
        return False
    return start <= now < start + timedelta(hours=1)
