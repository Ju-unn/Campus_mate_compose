"""신뢰 확인 게이트의 시각 판정(설계 §2.5).

시계는 `matches.created_at + 48시간` 하나뿐이다. "리마인드를 보냈다" 같은 상태 컬럼을 두지 않고
시각만 보고 판정한다 — 조각 4 의 카드 만료와 같은 방식이다. 전부 순수 함수라 테스트가 시계를
직접 넘긴다.
"""
from datetime import datetime, timedelta

from app.core.time import SEOUL

GATE_DEADLINE = timedelta(hours=48)
GATE_REMINDER_AFTER = timedelta(hours=24)
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
    """이 참가자와는 대화를 이어 갈 수 없는가 — 나갔거나 정지됐다(조각 6).

    정지는 left_at 을 찍지 않는다. 조회 시점 판정이라 대시보드에서 status 한 칸만 되돌리면 방이 그대로
    돌아온다(left_at 으로 구현하면 해제가 불가능해진다). 상대에게는 둘이 같은 모양으로 보인다 —
    정지 사실을 알리지 않는다. 방 머리말 · 보내기 · 게이트 수락 · 매시 배치가 모두 이 함수를 쓴다."""
    status = (participant.get("profiles") or {}).get("status")
    return bool(participant["left_at"]) or status == "suspended"


def is_passed(responses: list[str | None]) -> bool:
    """둘 다 accept 여야 통과다. 한 명이라도 미응답이면 아직 아니다.

    결정 10(미리 수락)으로 24시간 전에도 통과할 수 있어서 이 함수는 시각을 보지 않는다.
    거절은 값으로 들어오지 않는다 — 거절은 채팅방 나가기다(결정 11)."""
    return len(responses) == 2 and all(response == "accept" for response in responses)


def reminder_at(created_at: datetime) -> datetime:
    """리마인드를 보낼 시각. 기본은 매칭 24시간 뒤인데, 그 시각이 조용한 시간(22~8시)에 걸리면
    그다음 아침 8시로 민다.

    미루지 않으면 새벽에 잡힌 리마인드가 notify() 의 조용한 시간 검사에 걸려 조용히 버려지는데,
    창(window)이 한 번뿐이라 영영 다시 오지 않는다. 채팅 푸시와 달리 게이트 리마인드는
    조용한 시간을 지킨다(결정 5 의 예외는 채팅 푸시뿐)."""
    base = (created_at + GATE_REMINDER_AFTER).astimezone(SEOUL)
    if base.hour >= _QUIET_START_HOUR:
        base = (base + timedelta(days=1)).replace(hour=_QUIET_END_HOUR, minute=0, second=0, microsecond=0)
    elif base.hour < _QUIET_END_HOUR:
        base = base.replace(hour=_QUIET_END_HOUR, minute=0, second=0, microsecond=0)
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
