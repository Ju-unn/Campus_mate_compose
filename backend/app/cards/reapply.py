"""거절 되돌리기(1.0.7 할 일 #20)의 규칙을 한 곳에 둔다. 라우터(다시 신청 · 되돌리기 · 거절 목록 · 카드 상세 · 받은 신청
상세)와 저장소의 조건부 PATCH(CardRepository.reapply_rejected · reapply_rejected_answer)가 여기 값을 쓴다.

두 가지 거절이 있다:
- (a) 카드 거절(source "card"): 내가 받은 카드를 거절했다 → 다시 대화 신청(card_decisions 를 accept 로).
- (b) 받은 신청 거절(source "acceptance"): 상대가 보낸 신청을 내가 거절했다 → 되돌려 바로 매칭(acceptance_responses 를
  accept 로). 상대 신청의 원래 응답 기한(상대 수락 + 7일)도 넘지 못한다.

- 기한: 내가 거절한 시각(그 행의 decided_at)부터 REAPPLY_WINDOW_DAYS 일, 서버 시계(wiring.now) 기준.
  카드 expires_at 은 보지 않는다. 경계는 "거절 시각 > 지금 - 7일" 하나로 모든 자리가 같이 쓴다.
- 한 번만(2026-11-24 사용자 확정 「카드 한 장에 다시 신청 한 번」): 되돌리면 decision 이 accept 가 되어
  "아직 거절(decision = reject)" 조건에 다시 걸리지 않는다. "여러 번 허용" 으로 바뀌면 이 모듈과 저장소 두 메서드의
  decision 조건을 같이 바꾼다.
"""
from datetime import datetime, timedelta

REAPPLY_WINDOW_DAYS = 7
# GET /cards/rejected 줄의 출처.
REJECTED_SOURCE_CARD = "card"
REJECTED_SOURCE_ACCEPTANCE = "acceptance"


def reapply_cutoff(now: datetime) -> datetime:
    """이 시각보다 **뒤에** 거절한 것만 되돌릴 수 있다."""
    return now - timedelta(days=REAPPLY_WINDOW_DAYS)


def reapply_deadline(rejected_at: datetime, request_expires_at: datetime | None = None) -> datetime:
    """되돌리기가 닫히는 시각(거절 목록의 expires_at). 받은 신청 거절이면 상대 신청의 원래 기한과 둘 중 먼저 오는 것."""
    deadline = rejected_at + timedelta(days=REAPPLY_WINDOW_DAYS)
    return min(deadline, request_expires_at) if request_expires_at else deadline


def reapply_open(rejected_at: str, now: datetime, request_expires_at: datetime | None = None) -> bool:
    """아직 되돌릴 수 있는가. rejected_at 은 DB 가 준 거절 시각 글자다."""
    return now < reapply_deadline(datetime.fromisoformat(rejected_at), request_expires_at)


def rejection_closed(decision: dict | None, now: datetime) -> bool:
    """내 카드 결정이 거절이고 다시 신청 기한이 지났는가 — 다시 신청 · 카드 상세가 이유 없는 404 로 닫는다."""
    return bool(decision) and decision["decision"] == "reject" and not reapply_open(decision["decided_at"], now)
