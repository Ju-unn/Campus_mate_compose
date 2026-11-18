"""관리자가 적는 사유(작업 기록 admin_actions.reason). 정지 · 해제 · 가림 해제 · 글 가림 · 채팅 앞뒤 보기는 필수다(설계 10-18 §8-2)."""
from typing import Annotated

from pydantic import BaseModel, StringConstraints

from app.core.text import SAFE_TEXT

# admin_actions_reason_length check(20261018002902)와 같은 상한. 앞뒤 공백을 떼고 센다 — 공백뿐인 사유는 사유가 아니다.
REASON_MAX = 500
# SAFE_TEXT = 널 문자 · 제어 문자(줄바꿈 · 탭 빼고) · 글 방향 문자 거절(core/text.py, 11-18 검토).
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=REASON_MAX), SAFE_TEXT]


class ReasonBody(BaseModel):
    reason: Reason
