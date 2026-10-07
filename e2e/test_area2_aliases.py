"""영역 2 별칭 9개(E-CARD-40 · 43 · 46 · 48, E-BATCH-05~09)의 PC 쪽 시험 — 새 로직이 아니라 "별칭이 원본을 한 번만 부른다 · 등록 줄이 다 있다" 시험이다.
폰 · 운영 · gcloud 없이 가짜로만. 저장소 루트에서 `python -m unittest e2e.test_area2_aliases`.
기대 표는 이 시험이 따로 적는다 — 가설 코드가 읽는 표와 같은 곳에서 가져오지 않는다.
"""

import re
import subprocess
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area2, area2_aliases as mod, tools
from e2e.tools import Blocked, CaseTimeout

PHONE = {'E-CARD-40': 'E-PUSH-10', 'E-CARD-43': 'E-PUSH-13', 'E-CARD-46': 'E-PUSH-18', 'E-CARD-48': 'E-PUSH-22',
         'E-BATCH-09': 'E-CARD-13'}
BATCH = {'E-BATCH-05': 'E-CARD-04', 'E-BATCH-06': 'E-CARD-09', 'E-BATCH-07': 'E-CARD-08', 'E-BATCH-08': 'E-CARD-11'}
BUNDLE = 'area2-alias'


def read(*parts):
    return tools.ROOT.joinpath(*parts).read_text(encoding='utf-8')


class RegistryTest(unittest.TestCase):
    def test_the_bundle_is_the_nine_aliases(self):
        self.assertEqual(cli.BUNDLES[BUNDLE], [*PHONE, *BATCH])

    def test_phone_aliases_are_phone_cases_and_batch_aliases_are_api_cases_of_this_module(self):
        for case in PHONE:
            self.assertIn(case, area1.PHONE)
            self.assertNotIn(case, cli.API_CASES)
        for case in BATCH:
            self.assertIs(cli.API_CASES[case], mod)
            self.assertNotIn(case, area1.PHONE)

    def test_the_skipped_table_and_the_originals_stay_as_they_were(self):
        self.assertEqual(sorted(area2.SKIPPED), [])  # E-CARD-73 은 card_73 으로 등록, E-HEART-46 은 area4_extra(area4-extra-ai)에서 돈다
        for case in [*PHONE, *BATCH]:
            self.assertNotIn(case, area2.SKIPPED)
            self.assertNotIn(case, area2.CASES)
        for theirs in [*PHONE.values(), *BATCH.values()]:
            self.assertTrue(theirs in area1.PHONE or theirs in cli.API_CASES, theirs)

    def test_a_fresh_interpreter_that_only_imports_the_program_entry_sees_them(self):
        probe = ('from e2e import __main__ as m, area1; '
                 f'print(m.BUNDLES.get("{BUNDLE}") is not None, all(c in area1.PHONE for c in {list(PHONE)}), '
                 f'all(c in m.API_CASES for c in {list(BATCH)}))')
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), 'True True True')

    def test_the_module_imports_alone_because_it_loads_its_own_originals(self):
        out = subprocess.run([sys.executable, '-c', 'from e2e import area2_aliases'], cwd=tools.ROOT,
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)

    def test_the_program_entry_imports_the_module_uncommented_after_the_originals(self):
        text = read('e2e', '__main__.py')
        mine = re.search(r'(?m)^from e2e import area2_aliases\b', text)
        self.assertTrue(mine, 'from e2e import area2_aliases 줄이 없거나 주석 처리됨')
        for original in ('area2_time_device', 'area2_time_batch', 'area4_push'):
            self.assertLess(re.search(rf'(?m)^from e2e import {original}\b', text).start(), mine.start(), original)

    def test_limits_follow_the_originals_where_the_original_has_one(self):
        for mine, theirs in {**PHONE, **BATCH}.items():
            if theirs in tools.CASE_LIMITS:
                self.assertEqual(tools.CASE_LIMITS[mine], tools.CASE_LIMITS[theirs], mine)
            else:
                self.assertNotIn(mine, tools.CASE_LIMITS, mine)

    def test_no_alias_number_lives_in_another_bundle_or_is_its_own_target(self):
        for name, bundle in cli.BUNDLES.items():
            if name != BUNDLE:
                self.assertFalse(set(PHONE) & set(bundle) | set(BATCH) & set(bundle), name)
        self.assertFalse((set(PHONE) | set(BATCH)) & (set(PHONE.values()) | set(BATCH.values())))

    def test_the_app_answers_every_phone_alias_with_its_originals_case(self):
        dart = read('frontend', 'integration_test', 'e2e_test.dart')
        self.assertIn("for (final number in ['40', '43', '46', '48']) 'E-CARD-$number': area1Cases['E-ONB-61']!,", dart)
        self.assertIn("'E-BATCH-09': area2dCases['E-CARD-13']!,", dart)
        # E-PUSH-10 · 13 · 18 · 22 의 앱 가설도 area1Cases['E-ONB-61'] 이다(area4_push.dart) — 별칭이 같은 가설을 돈다.
        push = read('frontend', 'integration_test', 'area4_push.dart')
        numbers = re.search(r'_pushHomeCases = \[(.*?)\];', push).group(1)
        for number in ('10', '13', '18', '22'):
            self.assertIn(f"'{number}'", numbers, number)
        self.assertIn("'E-PUSH-$number': area1Cases['E-ONB-61']!", push)


class FakeRun:
    """tools.Run 의 record · records 만 — 결과 폴더의 줄을 리스트로 쓴다. [earlier] 는 같은 폴더에 앞 실행이 남긴 줄."""

    def __init__(self, earlier=()):
        self.lines = [{'case': c, 'result': r, 'note': n} for c, r, n in earlier]
        self.record = mock.Mock(side_effect=lambda case, result, note='': self.lines.append({'case': case, 'result': result, 'note': note}))

    def records(self):
        return list(self.lines)


class TwinTest(unittest.TestCase):
    def twin(self, source, earlier=()):
        with mock.patch.dict(area1.PHONE, {'E-THEIRS': source}):
            run = FakeRun(earlier)
            return mod._twin('E-MINE', 'E-THEIRS'), run

    def test_it_runs_the_original_once_and_writes_both_numbers(self):
        source = mock.Mock(return_value=('pass', '메모'))
        twin, run = self.twin(source)
        self.assertEqual(twin(run, 'phone'), ('pass', '메모'))
        source.assert_called_once_with(run, 'phone')
        run.record.assert_called_once_with('E-THEIRS', 'pass', 'E-MINE 로 돌린 같은 판 — 메모')

    def test_an_empty_note_adds_no_dash(self):
        twin, run = self.twin(mock.Mock(return_value=('pass', '')))
        twin(run, 'phone')
        run.record.assert_called_once_with('E-THEIRS', 'pass', 'E-MINE 로 돌린 같은 판')

    def test_blocked_is_a_verdict_not_a_crash(self):
        twin, run = self.twin(mock.Mock(side_effect=Blocked('폰 없음')))
        self.assertEqual(twin(run, 'phone'), ('blocked', '폰 없음'))
        run.record.assert_called_once_with('E-THEIRS', 'blocked', 'E-MINE 로 돌린 같은 판 — 폰 없음')

    def test_a_time_out_goes_to_the_runner_and_the_original_is_not_written(self):
        twin, run = self.twin(mock.Mock(side_effect=CaseTimeout('기다림')))
        with self.assertRaises(CaseTimeout):
            twin(run, 'phone')
        run.record.assert_not_called()

    def test_a_missing_original_fails_at_import_time(self):
        with self.assertRaises(KeyError):
            mod._twin('E-MINE', 'E-NO-SUCH')


class BatchAliasTest(unittest.TestCase):
    def test_it_hands_the_original_to_the_batch_module_once_and_writes_both_numbers(self):
        run = FakeRun()
        with mock.patch.object(mod.area2_time_batch, 'attempt', return_value=('fail', '카드 2장')) as attempt:
            self.assertEqual(mod.attempt(run, 'E-BATCH-07'), ('fail', '카드 2장'))
        attempt.assert_called_once_with(run, 'E-CARD-08')
        run.record.assert_called_once_with('E-CARD-08', 'fail', 'E-BATCH-07 로 돌린 같은 판 — 카드 2장')

    def test_every_batch_alias_reaches_its_own_original(self):
        with mock.patch.object(mod.area2_time_batch, 'attempt', return_value=('pass', '')) as attempt:
            for case in BATCH:
                mod.attempt(FakeRun(), case)  # 폴더마다 새로 — 앞 별칭이 쓴 줄이 다음 별칭을 막지 않게
        self.assertEqual([c.args[1] for c in attempt.call_args_list], list(BATCH.values()))


class SameFolderGuardTest(unittest.TestCase):
    """별칭과 원본을 다른 실행에서 같은 --bundle 폴더로 돌리면 운영 배치가 또 나간다 — 폴더에 원본 줄이 이미 있으면 별칭은 돌지 않고 blocked(area3_batch 와 같은 방어)."""
    OTHER_RUN = [('E-CARD-04', 'pass', '다른 실행이 원본으로 돌림')]

    def test_a_batch_alias_does_not_call_the_batch_when_the_original_already_ran_in_this_folder(self):
        run = FakeRun(self.OTHER_RUN)
        with mock.patch.object(mod.area2_time_batch, 'attempt') as attempt:
            result, note = mod.attempt(run, 'E-BATCH-05')
        attempt.assert_not_called()
        self.assertEqual(result, 'blocked')
        self.assertIn('두 번', note)
        run.record.assert_not_called()

    def test_a_phone_alias_does_not_run_the_original_when_it_already_ran_in_this_folder(self):
        source = mock.Mock(return_value=('pass', ''))
        twin, run = TwinTest().twin(source, earlier=[('E-THEIRS', 'pass', '다른 실행')])
        result, note = twin(run, 'phone')
        source.assert_not_called()
        self.assertEqual(result, 'blocked')
        run.record.assert_not_called()

    def test_a_failed_batch_alias_retried_by_run_case_returns_its_own_fail_and_does_not_call_again(self):
        run = FakeRun()
        with mock.patch.object(mod.area2_time_batch, 'attempt', return_value=('fail', '카드 2장')) as attempt:
            first = mod.attempt(run, 'E-BATCH-07')
            second = mod.attempt(run, 'E-BATCH-07')
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second[0], 'fail')
        attempt.assert_called_once()  # 두 번째는 원본(배치)을 다시 부르지 않는다
        self.assertEqual(len(run.lines), 1)

    def test_a_failed_phone_alias_retried_returns_its_own_fail_and_does_not_run_the_original_again(self):
        source = mock.Mock(return_value=('fail', '알림 0건'))
        twin, run = TwinTest().twin(source)
        first, second = twin(run, 'phone'), twin(run, 'phone')
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second[0], 'fail')
        source.assert_called_once()

    def test_a_pass_the_alias_wrote_is_not_returned_again_on_a_rerun(self):
        # 같은 폴더에서 별칭을 통과 뒤 다시 돌리면 배치가 또 나간다 — 막는다
        run = FakeRun()
        with mock.patch.object(mod.area2_time_batch, 'attempt', return_value=('pass', '')) as attempt:
            mod.attempt(run, 'E-BATCH-06')
            result, _ = mod.attempt(run, 'E-BATCH-06')
        self.assertEqual(result, 'blocked')
        attempt.assert_called_once()


if __name__ == '__main__':
    unittest.main()
