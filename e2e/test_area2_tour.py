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

    def test_reordered_titles_fail(self):
        titles = list(area2_tour.TITLES)
        titles[0], titles[1] = titles[1], titles[0]
        text = '\n'.join(f"    title: '{t}'," for t in titles)
        self.assertTrue(area2_tour.steps_problems(text))

    def test_bundle(self):
        self.assertEqual(area1.BUNDLES['area2-tour'], ['E-HOME-34', 'E-HOME-35'])

    def test_numbers_do_not_take_the_wait_screen_cases(self):
        # 번호가 겹치면 진행 프로그램(once)이 API 가설을 먼저 골라 에뮬 대기 화면 가설(E-HOME-30 · 31)이 돌지 않는다.
        self.assertFalse(set(area2_tour.CASES) & set(area2_emu_home.PHONE))


if __name__ == '__main__':
    unittest.main()
