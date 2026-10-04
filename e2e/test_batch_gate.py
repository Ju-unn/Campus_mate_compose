"""운영 배치를 손으로 부를 수 있는 시각 규칙 시험 — 가짜 시계만 쓴다. 저장소 루트에서 `python -m unittest e2e.test_batch_gate`."""

import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

from e2e import area2, batch_gate
from e2e.area1 import SEOUL
from e2e.tools import Blocked


def at(day, hhmm, second=0):
    """2026-10 의 [day]일 서울 시각. 10-05 = 월요일 · 10-06 = 화요일 · 10-07 = 수요일."""
    hour, minute = map(int, hhmm.split(':'))
    return datetime(2026, 10, day, hour, minute, second, tzinfo=SEOUL)


class DailyCardsTest(unittest.TestCase):
    def test_midnight_to_ten_past_seven_is_closed_on_a_tuesday(self):
        for hhmm in ('00:00', '03:30', '07:00', '07:10'):
            self.assertIn('07:11', batch_gate.refusal('daily-cards', at(6, hhmm)), hhmm)

    def test_it_opens_a_minute_after_ten_past_seven(self):
        self.assertIsNone(batch_gate.refusal('daily-cards', at(6, '07:11')))
        self.assertIsNone(batch_gate.refusal('daily-cards', at(6, '22:30')))
        self.assertIsNone(batch_gate.refusal('daily-cards', at(6, '23:59')))

    def test_a_monday_is_closed_all_day_and_names_tuesday(self):
        for hhmm in ('09:00', '12:00', '23:59'):
            said = batch_gate.refusal('daily-cards', at(5, hhmm))
            self.assertIn('화요일 07:11', said, hhmm)

    def test_the_message_asks_to_come_back_with_the_time(self):
        self.assertEqual('지금은 실행 금지 시간 — 07:11 에 다시', batch_gate.refusal('daily-cards', at(6, '05:00')))


class CleanupTest(unittest.TestCase):
    def test_five_minutes_around_four_are_closed_both_ways(self):
        for hhmm in ('03:55', '04:00', '04:05'):
            self.assertIn('04:06', batch_gate.refusal('cleanup', at(6, hhmm)), hhmm)

    def test_just_outside_the_five_minutes_is_open(self):
        self.assertIsNone(batch_gate.refusal('cleanup', at(6, '03:54')))
        self.assertIsNone(batch_gate.refusal('cleanup', at(6, '04:06')))

    def test_monday_is_fine_for_cleanup(self):
        self.assertIsNone(batch_gate.refusal('cleanup', at(5, '12:00')))


class ChatGateTest(unittest.TestCase):
    def test_five_minutes_around_the_hour_are_closed(self):
        for hhmm in ('13:55', '13:59', '14:00', '14:05'):
            self.assertIsNotNone(batch_gate.refusal('chat-gate', at(6, hhmm)), hhmm)

    def test_closed_minutes_name_the_next_open_minute(self):
        self.assertEqual('지금은 실행 금지 시간 — 14:06 에 다시', batch_gate.refusal('chat-gate', at(6, '14:03')))
        self.assertEqual('지금은 실행 금지 시간 — 14:06 에 다시', batch_gate.refusal('chat-gate', at(6, '13:56')))

    def test_the_middle_of_the_hour_is_open(self):
        for hhmm in ('14:06', '14:30', '14:54'):
            self.assertIsNone(batch_gate.refusal('chat-gate', at(6, hhmm)), hhmm)

    def test_a_second_run_in_the_same_hour_is_closed_until_the_next_hours_open_minute(self):
        ran = [at(6, '14:10')]
        self.assertEqual('지금은 실행 금지 시간 — 15:06 에 다시', batch_gate.refusal('chat-gate', at(6, '14:40'), ran))

    def test_a_run_in_another_hour_or_day_does_not_count(self):
        ran = [at(6, '13:10'), at(5, '14:10')]
        self.assertIsNone(batch_gate.refusal('chat-gate', at(6, '14:40'), ran))

    def test_the_second_run_rule_is_only_for_chat_gate(self):
        self.assertIsNone(batch_gate.refusal('cleanup', at(6, '12:00'), [at(6, '12:10')]))


class UnknownJobTest(unittest.TestCase):
    def test_a_job_without_a_rule_is_refused_loudly(self):
        with self.assertRaises(ValueError):
            batch_gate.refusal('send-everything', at(6, '12:00'))


class CheckTest(unittest.TestCase):
    """check = 규칙 + 기록 파일 — 통과한 chat-gate 만 기록에 남는다."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        patcher = mock.patch.object(batch_gate, 'HISTORY', Path(folder.name) / 'runs.jsonl')
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_closed_time_raises_blocked_with_the_message(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(5, '12:00')):
            with self.assertRaisesRegex(Blocked, '지금은 실행 금지 시간 — 화요일 07:11 에 다시'):
                batch_gate.check('daily-cards')

    def test_a_second_chat_gate_in_the_same_hour_is_blocked_even_in_a_new_process(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '14:10')):
            batch_gate.check('chat-gate')
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '14:40')):
            with self.assertRaisesRegex(Blocked, '15:06'):
                batch_gate.check('chat-gate')

    def test_a_refused_chat_gate_is_not_recorded(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '14:02')):
            with self.assertRaises(Blocked):
                batch_gate.check('chat-gate')
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '14:10')):
            batch_gate.check('chat-gate')  # 앞의 거절이 기록돼 있으면 여기서 걸린다

    def test_a_damaged_history_line_is_skipped_not_fatal(self):
        batch_gate.HISTORY.write_text('여기가 깨짐' + chr(10) + at(6, '14:10').isoformat() + chr(10), encoding='utf-8')
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '14:40')):
            with self.assertRaisesRegex(Blocked, '15:06'):  # 깨진 줄은 건너뛰고 멀쩡한 줄은 그대로 읽는다
                batch_gate.check('chat-gate')

    def test_other_jobs_leave_no_record(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '12:00')):
            batch_gate.check('cleanup')
        self.assertFalse(batch_gate.HISTORY.exists())


class WiredIntoTheBatchCallTest(unittest.TestCase):
    """area2._batch 가 관문을 지난 뒤에만 gcloud(tools.batch)를 부른다 — 모든 영역 2 배치 호출이 지나는 한 자리."""

    def test_a_closed_time_never_reaches_gcloud(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(5, '12:00')), \
                mock.patch.object(area2.tools, 'batch') as gcloud:
            with self.assertRaises(Blocked):
                area2._batch('daily-cards')
        gcloud.assert_not_called()

    def test_an_open_time_calls_gcloud_once(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=at(6, '12:00')), \
                mock.patch.object(area2.tools, 'batch') as gcloud:
            area2._batch('daily-cards')
        gcloud.assert_called_once_with('daily-cards')


if __name__ == '__main__':
    unittest.main()
