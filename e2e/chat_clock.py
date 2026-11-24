"""채팅 신뢰 확인 시계 — 폰 시험이 matches.created_at 을 옮길 때 쓰는 기준 두 개.

서버 backend/app/chat/gate.py 와 같은 값이다(test_chat_clock 이 진짜 서버 값과 맞춰 본다). 규칙이 바뀌면 여기 두 줄만 고친다.
방 나이는 이 둘에서 끌어 쓴다: 띠 방 < PROMPT_AFTER ≤ 시트 방 < DEADLINE ≤ 닫힐 방.
"""

from datetime import timedelta

DEADLINE = timedelta(hours=72)  # gate.GATE_DEADLINE — 응답 기한, 매시 배치가 이 뒤에 방을 닫는다
PROMPT_AFTER = timedelta(hours=48)  # gate.GATE_REMINDER_AFTER — 14f 시트가 뜨고 리마인드 창이 열린다(마감 24시간 전)
