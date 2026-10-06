"""E-BATCH 별칭 시험 — 운영 · gcloud 없이. 별칭이 기존 판을 부르고 두 번호에 적는지, 배치를 직접 부르지 않는지 본다. `python -m unittest e2e.test_area3_batch`."""

import unittest
from unittest import mock

from e2e import area1, area2, area3, area3_batch, tools
from e2e.tools import Blocked


class FakeRun:
    def __init__(self, earlier=()):
        self.recorded = []
        self.earlier = [{'case': c, 'result': 'pass', 'note': '다른 실행'} for c in earlier]

    def records(self):
        return self.earlier + [{'case': c, 'result': r, 'note': n} for c, r, n in self.recorded]

    def record(self, case, result, note=''):
        self.recorded.append((case, result, note))


class AliasTest(unittest.TestCase):
    def setUp(self):
        for patched in (mock.patch.object(tools, 'batch', side_effect=AssertionError('gcloud 호출 금지')),
                        mock.patch.object(area2, '_batch', side_effect=AssertionError('배치 호출 금지'))):
            patched.start()
            self.addCleanup(patched.stop)

    def test_registered_phone_cases_are_14_to_17_and_api_cases_22_23(self):
        self.assertEqual(sorted(area3_batch.PHONE), ['E-BATCH-14', 'E-BATCH-15', 'E-BATCH-16', 'E-BATCH-17'])
        self.assertEqual(sorted(area3_batch.CASES), ['E-BATCH-22', 'E-BATCH-23'])
        self.assertEqual(area3.BUNDLES['area3-batch'], [*area3_batch.PHONE, *area3_batch.CASES])
        self.assertTrue(set(area3_batch.PHONE) <= set(area1.PHONE))

    def test_every_phone_alias_points_at_a_registered_gate_case(self):
        for mine, theirs in area3_batch.PHONE_ALIAS.items():
            self.assertIn(theirs, area3_batch.GATE_PHONE, mine)

    def test_phone_alias_runs_the_original_and_records_both_numbers(self):
        run, original = FakeRun(), mock.Mock(return_value=('pass', '본 것'))
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-40': original}):
            got = area3_batch.PHONE['E-BATCH-14'](run, 'phone')
        original.assert_called_once_with(run, 'phone')
        self.assertEqual(got[0], 'pass')
        self.assertEqual([c for c, _, _ in run.recorded], ['E-PUSH-40'])
        self.assertIn('E-BATCH-14', run.recorded[0][2])

    def test_phone_alias_turns_blocked_into_a_result_not_a_crash(self):
        run = FakeRun()
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-46': mock.Mock(side_effect=Blocked('13:06 에 다시'))}):
            result, note = area3_batch.PHONE['E-BATCH-15'](run, 'phone')
        self.assertEqual(result, 'blocked')
        self.assertIn('13:06', note)

    def test_17_says_it_only_covers_the_left_room(self):
        run = FakeRun()
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-47': mock.Mock(return_value=('pass', ''))}):
            _, note = area3_batch.PHONE['E-BATCH-17'](run, 'phone')
        self.assertIn('정지 · 탈퇴', note)

    def test_api_alias_goes_through_the_module_attempt(self):
        run = FakeRun()
        for mine, (module, theirs) in area3_batch.API_ALIAS.items():
            with mock.patch.object(module, 'attempt', return_value=('pass', 'ok')) as attempt:
                result, note = area3_batch.attempt(run, mine)
            attempt.assert_called_once_with(run, theirs)
            self.assertEqual(result, 'pass')
        self.assertEqual([c for c, _, _ in run.recorded], ['E-AUTH-12', 'E-HEART-22'])

    def test_phone_alias_refuses_when_the_original_already_ran_in_this_folder(self):
        run, original = FakeRun(earlier=['E-PUSH-40']), mock.Mock(return_value=('pass', ''))
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-40': original}):
            result, note = area3_batch.PHONE['E-BATCH-14'](run, 'phone')
        original.assert_not_called()
        self.assertEqual(result, 'blocked')
        self.assertIn('두 번', note)
        self.assertEqual(run.recorded, [])

    def test_api_alias_refuses_when_the_original_already_ran_in_this_folder(self):
        run = FakeRun(earlier=['E-AUTH-12'])
        with mock.patch.object(area1, 'attempt') as attempt:
            result, note = area3_batch.attempt(run, 'E-BATCH-22')
        attempt.assert_not_called()
        self.assertEqual(result, 'blocked')

    def test_a_failed_alias_retried_by_run_case_returns_its_own_fail_not_blocked(self):
        # 진행 프로그램은 fail 이면 같은 가설을 한 번 더 부른다 — 첫 시도가 적은 원본 번호 줄을 "이미 돌렸다" 로 읽어 fail 을 blocked 로 덮으면 안 된다
        run, original = FakeRun(), mock.Mock(return_value=('fail', '알림 0건'))
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-40': original}):
            first = area3_batch.PHONE['E-BATCH-14'](run, 'phone')
            second = area3_batch.PHONE['E-BATCH-14'](run, 'phone')
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second, first)
        original.assert_called_once()  # 두 번째는 원본을 다시 부르지 않는다(배치가 또 나가지 않는다)
        self.assertEqual(len(run.recorded), 1)

    def test_a_failed_api_alias_retried_returns_its_own_fail_and_does_not_call_again(self):
        run = FakeRun()
        with mock.patch.object(area1, 'attempt', return_value=('fail', '행이 남음')) as attempt:
            first = area3_batch.attempt(run, 'E-BATCH-22')
            second = area3_batch.attempt(run, 'E-BATCH-22')
        self.assertEqual(second, first)
        attempt.assert_called_once()

    def test_a_pass_recorded_by_the_alias_is_not_returned_again_on_a_rerun(self):
        # 같은 폴더에서 별칭을 또 돌리면(통과 뒤) 배치가 또 나간다 — 막는다
        run, original = FakeRun(), mock.Mock(return_value=('pass', ''))
        with mock.patch.dict(area3_batch.GATE_PHONE, {'E-PUSH-40': original}):
            area3_batch.PHONE['E-BATCH-14'](run, 'phone')
            result, _ = area3_batch.PHONE['E-BATCH-14'](run, 'phone')
        self.assertEqual(result, 'blocked')
        original.assert_called_once()

    def test_notes_name_what_the_original_does_not_check(self):
        for mine, words in {'E-BATCH-14': ('E-PUSH-41',), 'E-BATCH-15': ('예약',), 'E-BATCH-17': ('닫기', 'chat_closed_at', '정지')}.items():
            for word in words:
                self.assertIn(word, area3_batch.NOTES[mine], mine)

    def test_case_limit_follows_the_original(self):
        self.assertEqual(tools.CASE_LIMITS['E-BATCH-16'], tools.CASE_LIMITS.get('E-PUSH-44', tools.CASE_LIMIT))


if __name__ == '__main__':
    unittest.main()
