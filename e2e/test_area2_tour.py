"""앱 투어 소스 확인 가설(E-HOME-34 · 35)의 PC 쪽 시험 — 폰 · 운영 없이 지금 저장소 파일과 바꾼 글로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_tour`."""

import unittest

from e2e import area1, area2_emu_home, area2_tour

ENTRY = """void main() {
  testWidgets('e2e 가설 하나', (tester) async {
    AppTourViewModel.autoStartEnabled = false;
    await app.main();
  });
}"""


class TourOff(unittest.TestCase):
    def test_repo_entry_turns_auto_start_off(self):
        self.assertEqual(area1.CASES['E-HOME-34'](None), ('pass', ''))

    def test_off_before_main(self):
        self.assertEqual(area2_tour.tour_off_problems(ENTRY), [])

    def test_missing_switch_fails(self):
        self.assertTrue(area2_tour.tour_off_problems(ENTRY.replace('AppTourViewModel.autoStartEnabled = false;', '')))

    def test_switch_after_main_fails(self):
        late = ENTRY.replace('    AppTourViewModel.autoStartEnabled = false;\n', '') + '\nAppTourViewModel.autoStartEnabled = false;'
        self.assertTrue(area2_tour.tour_off_problems(late))


class TourSteps(unittest.TestCase):
    def test_repo_steps_match_confirmed_titles(self):
        self.assertEqual(area1.CASES['E-HOME-35'](None), ('pass', ''))

    # 소스 모양 그대로의 작은 조각(단계 6개 + 제목 키 표) — 글자는 ARB 가 정하므로 키 → 글자 표를 따로 준다.
    STEPS = """  TourStep(location: AppRoutes.home, copy: TourCopy.start),
  TourStep(location: AppRoutes.home, copy: TourCopy.profile),
  TourStep(location: AppRoutes.community, copy: TourCopy.community),
  TourStep(location: AppRoutes.today, copy: TourCopy.arrival, titleAt: _arrivalTitle),
  TourStep(location: AppRoutes.today, copy: TourCopy.precision),
  TourStep(location: AppRoutes.heartStore, copy: TourCopy.heartFree),
  TourCopy.start => l10n.tourStartTitle,
  TourCopy.profile => l10n.tourProfileTitle,
  TourCopy.community => l10n.tourCommunityTitle,
  TourCopy.arrival => l10n.tourArrivalTitle,
  TourCopy.precision => l10n.tourPrecisionTitle,
  TourCopy.heartFree => l10n.tourHeartFreeTitle,
"""
    KEYS = ['tourStartTitle', 'tourProfileTitle', 'tourCommunityTitle', 'tourArrivalTitle', 'tourPrecisionTitle', 'tourHeartFreeTitle']
    MESSAGES = dict(zip(KEYS, area2_tour.TITLES))

    def test_titles_are_read_through_the_arb_keys_in_step_order(self):
        self.assertEqual(area2_tour.steps_problems(self.STEPS, self.MESSAGES), [])

    def test_reordered_steps_fail(self):
        lines = self.STEPS.splitlines()
        lines[0], lines[1] = lines[1], lines[0]
        self.assertTrue(area2_tour.steps_problems('\n'.join(lines), self.MESSAGES))

    def test_a_changed_title_text_fails(self):
        self.assertTrue(area2_tour.steps_problems(self.STEPS, {**self.MESSAGES, 'tourStartTitle': '다른 제목'}))

    def test_a_step_without_a_title_key_fails(self):
        self.assertTrue(area2_tour.steps_problems(self.STEPS.replace('TourCopy.heartFree => l10n.tourHeartFreeTitle,', ''), self.MESSAGES))

    def test_bundle(self):
        self.assertEqual(area1.BUNDLES['area2-tour'], ['E-HOME-34', 'E-HOME-35'])

    def test_numbers_do_not_take_the_wait_screen_cases(self):
        # 번호가 겹치면 진행 프로그램(once)이 API 가설을 먼저 골라 에뮬 대기 화면 가설(E-HOME-30 · 31)이 돌지 않는다.
        self.assertFalse(set(area2_tour.CASES) & set(area2_emu_home.PHONE))


if __name__ == '__main__':
    unittest.main()
