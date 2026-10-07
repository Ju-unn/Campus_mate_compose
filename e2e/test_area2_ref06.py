"""E-REF-06 판 시험 — 가짜 서버 · 가짜 앱으로 돈다(폰 · 운영 없음). 저장소 루트에서 `python -m unittest e2e.test_area2_ref06`.
기대는 시나리오 줄: referrals 1행 · 원장 reason=referral(ref=B id) · A +50 · B +50. 계정은 만든 순서대로 id-1(코드 주인 A) · id-2(새 사람 B)."""

import re
import subprocess
import sys
import unittest
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area2_ref06, tools
from e2e.test_area1_phone import FakePhone
from e2e.test_area2 import Base, Fake
from e2e.tools import Reply

A, B = 'id-1', 'id-2'
GOOD_LEDGER = {A: [{'amount': 50, 'ref_id': B}], B: [{'amount': 50, 'ref_id': B}]}


def read(*parts):
    return tools.ROOT.joinpath(*parts).read_text(encoding='utf-8')


class RunTest(Base):
    def run06(self, ledger=GOOD_LEDGER, got_by=B, gave=None, phone=None):
        def hearts(body, url):
            for person, rows in ledger.items():
                if f'profile_id=eq.{person}' in url:
                    return Reply(200, rows)
            return Reply(200, [])

        fake = Fake([
            ('GET', 'referrals?referee_id', lambda body, url: Reply(200, [{'referrer_id': A}] if got_by == B else [])),
            ('GET', 'referrals?referrer_id', lambda body, url: Reply(200, gave if gave is not None else [{'referee_id': B}])),
            ('GET', 'heart_transactions', hearts),
            ('GET', '/rest/v1/profiles', lambda body, url: Reply(200, [{'referral_code': 'K7M2QX'}])),
        ])
        phone = phone or FakePhone()
        with mock.patch.object(tools, 'call', fake):
            return area1.attempt_phone(self.run, 'E-REF-06', phone), phone

    def test_pass_one_referral_row_and_fifty_hearts_each_with_the_newcomers_id_as_ref(self):
        (result, note), phone = self.run06()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(phone.jobs[0]['code'], 'K7M2QX')  # 앱은 코드 주인의 코드를 넣는다
        self.assertIn('token_hash', phone.jobs[0])

    def test_a_ledger_line_pointing_at_the_wrong_person_is_a_fail(self):
        # E-ONB-60 은 금액만 봐서 통과시키지만, 시나리오는 ref=B id 다.
        wrong = {A: [{'amount': 50, 'ref_id': A}], B: [{'amount': 50, 'ref_id': B}]}
        (result, note), _ = self.run06(wrong)
        self.assertEqual(result, 'fail', note)
        self.assertIn('코드 주인 A', note)

    def test_a_missing_or_wrong_amount_for_either_side_is_a_fail(self):
        for label, ledger in (('B 없음', {A: GOOD_LEDGER[A], B: []}), ('A 없음', {A: [], B: GOOD_LEDGER[B]}),
                              ('A 40', {A: [{'amount': 40, 'ref_id': B}], B: GOOD_LEDGER[B]})):
            with self.subTest(label):
                self.setUp()
                (result, note), _ = self.run06(ledger)
                self.assertEqual(result, 'fail', note)

    def test_a_double_payment_is_a_fail(self):
        twice = {A: GOOD_LEDGER[A] * 2, B: GOOD_LEDGER[B]}
        (result, note), _ = self.run06(twice)
        self.assertEqual(result, 'fail', note)

    def test_no_referral_row_or_a_second_one_is_a_fail(self):
        (result, _), _ = self.run06(got_by=None)
        self.assertEqual(result, 'fail')
        self.setUp()
        (result, note), _ = self.run06(gave=[{'referee_id': B}, {'referee_id': 'id-9'}])
        self.assertEqual(result, 'fail', note)

    def test_an_app_that_says_blocked_makes_the_case_blocked(self):
        (result, _), _ = self.run06(phone=FakePhone({'result': 'blocked', 'note': '20 에 못 닿음'}))
        self.assertEqual(result, 'blocked')


class RegistryTest(unittest.TestCase):
    def test_it_is_a_phone_case_in_its_own_bundle_and_the_runner_sees_it(self):
        self.assertIn('E-REF-06', area1.PHONE)
        self.assertEqual(cli.BUNDLES['area2-ref06'], ['E-REF-06'])
        self.assertNotIn('E-REF-06', cli.API_CASES)
        self.assertFalse(any('E-REF-06' in bundle for name, bundle in cli.BUNDLES.items() if name != 'area2-ref06'))

    def test_a_fresh_interpreter_that_only_imports_the_program_entry_sees_it(self):
        probe = 'from e2e import __main__ as m, area1; print("E-REF-06" in area1.PHONE, m.BUNDLES.get("area2-ref06"))'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), "True ['E-REF-06']")

    def test_the_program_entry_imports_the_module_uncommented_after_its_helpers(self):
        text = read('e2e', '__main__.py')
        mine = re.search(r'(?m)^from e2e import area2_ref06\b', text)
        self.assertTrue(mine, 'from e2e import area2_ref06 줄이 없거나 주석 처리됨')
        self.assertLess(re.search(r'(?m)^from e2e import area1_b2\b', text).start(), mine.start())

    def test_the_app_answers_it_with_the_onb_60_case(self):
        dart = read('frontend', 'integration_test', 'e2e_test.dart')
        self.assertIn("'E-REF-06': area1Cases['E-ONB-60']!,", dart)


if __name__ == '__main__':
    unittest.main()
