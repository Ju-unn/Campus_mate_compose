"""폰 시험이 옮기는 방 나이의 기준이 진짜 서버 규칙(backend/app/chat/gate.py)과 같은지 — 서버가 바뀌면 여기서 먼저 안다.
저장소 루트에서 `python -m unittest e2e.test_chat_clock`."""

import sys
import unittest
from datetime import timedelta

from e2e import chat_clock, tools


class ServerContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(tools.ROOT / 'backend'))
        try:
            from app.chat import gate
        finally:
            sys.path.remove(str(tools.ROOT / 'backend'))
        cls.gate = gate

    def test_the_deadline_is_the_servers(self):
        self.assertEqual(chat_clock.DEADLINE, self.gate.GATE_DEADLINE)

    def test_the_sheet_and_reminder_time_is_the_servers(self):
        self.assertEqual(chat_clock.PROMPT_AFTER, self.gate.GATE_REMINDER_AFTER)


class RuleTest(unittest.TestCase):
    def test_the_sheet_comes_a_day_before_the_deadline(self):
        """사용자 11-24: 자유 대화 48시간 → 48시간째 시트 · 리마인드 → 72시간 마감."""
        self.assertEqual(chat_clock.PROMPT_AFTER, timedelta(hours=48))
        self.assertEqual(chat_clock.DEADLINE, timedelta(hours=72))
