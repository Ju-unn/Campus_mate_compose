"""E-SET-56(약관 줄)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버. 저장소 루트에서 `python -m unittest e2e.test_area4_set56`."""

import re
import unittest
from unittest import mock

from e2e import area1, area4_set56, tools
from e2e.test_area3_phone import said
from e2e.test_area5_read import OURS, ReadBase, StepApp

BROWSER = 'topResumedActivity=ActivityRecord{1 u0 com.android.chrome/org.chromium.chrome.browser.ChromeTabbedActivity t9}'


class TermsRowsTest(ReadBase):
    def run56(self, top, dump=''):
        events = []
        app = StepApp(lambda job: said(), ['terms', 'privacy'], events, top=top)
        with mock.patch.object(area4_set56.time, 'sleep'), \
                mock.patch.object(area4_set56, '_intent_seen', lambda serial: bool(dump)):
            result, app = self.case('E-SET-56', {}, app)
        return result, events

    def test_both_rows_open_another_app_and_the_human_part_is_left_in_the_note(self):
        (result, note), events = self.run56(BROWSER, dump='x')
        self.assertEqual(result, 'pass', note)
        self.assertIn('사람 필요', note)
        self.assertEqual(events.count('top'), 2)  # 줄마다 한 번 맨 앞 앱을 읽는다

    def test_a_row_that_leaves_our_app_in_front_fails_for_each_row(self):
        (result, note), _ = self.run56(OURS)
        self.assertEqual(result, 'fail', note)
        self.assertIn('이용약관', note)
        self.assertIn('개인정보처리방침', note)

    def test_the_notion_address_missing_from_dumpsys_does_not_decide_the_result(self):
        (result, note), _ = self.run56(BROWSER)
        self.assertEqual(result, 'pass', note)
        self.assertIn('판정에 안 씀', note)

    def test_the_app_is_brought_back_to_the_front_after_each_row(self):
        calls = []
        with mock.patch.object(area4_set56, '_front', lambda serial: calls.append(serial)):
            self.run56(BROWSER)
        self.assertEqual(len(calls), 2)


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_registered_in_a_bundle_and_main(self):
        self.assertEqual(area1.BUNDLES['area4-set56'], ['E-SET-56'])
        self.assertIs(area1.PHONE['E-SET-56'], area4_set56.p_set_56)
        from e2e import __main__ as main
        self.assertIn('from e2e import area4_set56', main.__loader__.get_source('e2e.__main__'))

    def test_the_app_says_the_steps_the_pc_waits_for_and_checks_the_row_order(self):
        text = self.dart('area4_set56.dart')
        self.assertEqual(re.findall(r"step\('(\w+)'", text), ['terms', 'privacy'])
        self.assertIn("'자주 묻는 질문', '이용약관', '개인정보처리방침', '로그아웃'", text)
        wiring = self.dart('area4.dart')
        self.assertIn("part 'area4_set56.dart';", wiring)
        self.assertIn('..._set56Cases,', wiring)

    def test_the_notion_page_id_is_the_one_the_app_opens(self):
        links = (tools.ROOT / 'frontend' / 'lib' / 'consent' / 'model' / 'consent_links.dart').read_text(encoding='utf-8')
        self.assertIn(area4_set56.PAGE, links)


if __name__ == '__main__':
    unittest.main()
