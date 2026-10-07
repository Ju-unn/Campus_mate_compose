"""영역 5 나 탭 빠진 가설 셋(E-ME-05 · 22 · 32)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 서버 · 가짜 앱으로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_more`.

05 는 영역 2 두 기기 시험의 가짜 세계([World])와 같은 모양으로, 22 · 32 는 area5_act 시험의 [ActBase](진짜 서버 규칙을 흉내 낸 가짜 서버)로 돈다.
"""

import re
import unittest
from unittest import mock

from e2e import area1, area2_two_accept, area5_more, tools, twodev
from e2e.test_area2_two_accept import A, B, Base as TwoBase
from e2e.test_area3_phone import said
from e2e.test_area3_safe import _who
from e2e.test_area5_act import ActBase

CARD = ['나이', '닉네임', '주말엔 카페에서 책을 읽어요.', '#카페', '#자전거']  # 앱이 두 화면에서 읽어 말하는 카드 글자(예)


class TextTwo:
    """가짜 `two` — 앱이 말하는 차례 script = [(쪽, step, 카드 글자)] 대로 plan 의 핸들러에 `texts` 를 실어 부른다."""

    def __init__(self, script, result=('pass', 'A: pass  B: pass')):
        self.script, self.result, self.a_job, self.b_job, self.limit = script, result, None, None, None

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.a_job, self.b_job, self.limit = a_job, b_job, limit
        assert sorted(plan) == sorted((side, step) for side, step, _ in self.script), sorted(plan)
        sync = twodev.Sync()
        for side, step, texts in self.script:
            plan[(side, step)]({'step': step, 'texts': texts() if callable(texts) else texts}, sync)
        return self.result


class SameCardTest(TwoBase):
    def setUp(self):
        super().setUp()
        original = self.world._bio

        def bio(sent):  # 가짜 서버가 온보딩 자기소개를 프로필 칸에도 적는다(PC 가 닉네임 · 자기소개를 읽는다)
            reply = original(sent)
            self.world.profile(_who(sent))['bio'] = sent['body']['bio']
            return reply
        self.world.handlers.insert(0, ('POST', re.compile(r'/profile-onboarding/bio'), bio))

    def card(self, who=A):
        """진짜 닉네임 · 자기소개가 든 카드 글자 — 계정은 가설이 만든 뒤에야 있어 부를 때 읽는다."""
        profile = self.world.profile(who)
        return ['24세', profile['nickname'], profile['bio'], '#카페']

    def go05(self, a_texts, b_texts, result=('pass', 'A: pass  B: pass')):
        self.two = TextTwo([('A', 'card', a_texts), ('B', 'card', b_texts)], result)
        return twodev.TWO['E-ME-05'](self.run_, self.two)

    def test_05_two_screens_with_the_same_card_pass(self):
        result, memo = self.go05(self.card, self.card)
        self.assertEqual(result, 'pass', memo)

    def test_05_a_screen_that_differs_by_one_letter_fails(self):
        result, memo = self.go05(self.card, lambda: [t.replace('카페', '커피') for t in self.card()])
        self.assertEqual(result, 'fail', memo)
        self.assertIn('다름', memo)

    def test_05_a_different_order_fails_too(self):
        result, memo = self.go05(self.card, lambda: list(reversed(self.card())))
        self.assertEqual(result, 'fail', memo)

    def test_05_empty_or_missing_texts_fail_instead_of_passing_as_equal(self):
        result, memo = self.go05([], [])
        self.assertEqual(result, 'fail', memo)
        result, memo = self.go05(None, None)
        self.assertEqual(result, 'fail', memo)

    def test_05_a_card_without_the_owners_nickname_or_bio_fails(self):
        bare = lambda: [self.card()[0], self.card()[3]]  # noqa: E731
        result, memo = self.go05(bare, bare)
        self.assertEqual(result, 'fail', memo)
        self.assertIn('닉네임', memo)
        self.assertIn('자기소개', memo)

    def test_05_gives_each_side_a_token_and_the_card_is_for_b_to_see_a(self):
        self.go05(self.card, self.card)
        self.assertIn('token_hash', self.two.a_job)
        self.assertIn('token_hash', self.two.b_job)
        self.assertTrue(self.world.card_between(B, A))  # B 가 owner · A 가 target — B 의 오늘 카드에 A

    def test_05_what_the_pc_found_beats_a_blocked_app(self):
        result, memo = self.go05(self.card, lambda: self.card()[:1], ('blocked', 'B: 막힘'))
        self.assertEqual(result, 'fail', memo)
        self.assertIn('B: 막힘', memo)


class SlowBackTest(ActBase):
    def good(self, **over):
        def answer(job):
            self.api('PATCH', '/me/profile', {'bio': job['bio']})  # 앱이 저장을 눌렀다 — 화면을 나가도 서버는 끝까지 받는다
            return said(**{'title': '프로필 편집', 'manage_bios': [job['bio']], **over})
        return answer

    def app(self, answer, serial='emulator-5554', steps=('slow',)):
        from e2e.test_area3_phone2 import MidwayApp
        app = MidwayApp(answer, steps[0], self.events)
        app.serial = serial
        return app

    def test_22_saves_to_the_end_when_the_app_leaves_at_once_and_the_network_is_slow_only_in_between(self):
        _, app = self.passes('E-ME-22', self.good(), app=self.app(self.good()))
        self.assertEqual(app.jobs[0]['token_hash'], 'h')
        emu = [call[2:] for call in self.adb_calls if call[1] == 'emu']
        self.assertEqual(emu, [('network', 'speed', 'edge'), ('network', 'delay', 'gprs'),
                               ('network', 'speed', 'full'), ('network', 'delay', 'none')])  # 느리게 한 뒤 반드시 되돌린다
        self.assertIn(app.jobs[0]['tag'], app.jobs[0]['bio'])

    def test_22_fails_when_the_save_did_not_reach_the_db(self):
        self.fails('E-ME-22', lambda job: said(title='프로필 편집', manage_bios=[job['bio']]), 'DB 자기소개',
                   app=self.app(lambda job: said(title='프로필 편집', manage_bios=[job['bio']])))

    def test_22_fails_when_the_screen_does_not_show_the_new_text(self):
        self.fails('E-ME-22', self.good(manage_bios=[]), '15-5 자기소개', app=self.app(self.good(manage_bios=[])))

    def test_22_fails_when_the_back_went_further_than_15_5(self):
        self.fails('E-ME-22', self.good(title='내 프로필'), '뒤로 간 뒤', app=self.app(self.good(title='내 프로필')))

    def test_22_restores_the_network_even_when_the_app_is_blocked(self):
        from e2e.test_area3_phone2 import MidwayApp
        blocked = MidwayApp(lambda job: {'result': 'blocked', 'note': '못 찾음'}, 'slow', self.events)
        blocked.serial = 'emulator-5554'
        self.blocked('E-ME-22', None, '못 찾음', app=blocked)
        self.assertEqual([c[4] for c in self.adb_calls if c[1] == 'emu'][-2:], ['full', 'none'])

    def test_22_is_blocked_on_a_phone_that_is_not_an_emulator(self):
        self.blocked('E-ME-22', self.good(), '에뮬', app=self.app(self.good(), serial='R3CX'))

    def test_22_is_blocked_when_the_emulator_console_refuses(self):
        def refuse(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            return 'KO: unknown command' if args[0] == 'emu' else ''
        with mock.patch.object(tools, 'adb', refuse):
            self.blocked('E-ME-22', self.good(), '거절', app=self.app(self.good()))

    def test_22_without_the_paid_gate_sends_nothing(self):
        with mock.patch.dict('os.environ', {'E2E_REAL_AI': ''}):
            _, app = self.case('E-ME-22', self.good())
        self.assertEqual(self.fake.paid_calls, 0)


class TakenNicknameTest(ActBase):
    def good(self, **over):
        def answer(job):
            return said(**{'taken': True, 'save_enabled': False, 'after_save_taken': False, 'on_edit': True, **over})
        return answer

    def test_32_a_taken_nickname_is_refused_when_typed_and_save_stays_off(self):
        _, app = self.passes('E-ME-32', self.good())
        job = app.jobs[0]
        self.assertRegex(job['nickname'], r'^[가-힣]{2,5}$')
        self.assertEqual(self.profile(2)['nickname'], job['nickname'])  # B(id-2) 가 그 닉네임을 쓴다
        self.assertNotEqual(self.profile(1)['nickname'], job['nickname'])

    def test_32_an_app_that_only_learns_it_after_saving_passes_when_the_server_409_shows_and_it_stays(self):
        self.passes('E-ME-32', self.good(taken=False, save_enabled=True, after_save_taken=True))

    def test_32_fails_when_nothing_refuses_it(self):
        for over, word in (({'taken': False, 'save_enabled': True, 'after_save_taken': False}, '막음'),
                           ({'taken': False, 'save_enabled': True, 'after_save_taken': True, 'on_edit': False}, '머물러'),
                           ({'save_enabled': True}, '저장 버튼')):
            with self.subTest(over):
                self.fails('E-ME-32', self.good(**over), word)

    def test_32_fails_when_the_db_nickname_changed(self):
        def changed(job):
            self.api('PATCH', '/me/profile', {'nickname': '새이름'})
            return self.good()(job)
        self.fails('E-ME-32', changed, 'DB A 닉네임')

    def test_32_the_server_really_refuses_a_taken_nickname(self):
        def probe(job):
            reply = self.api('PATCH', '/me/profile', {'nickname': job['nickname']})
            self.assertEqual((reply[0], reply[1].get('detail')), (409, '이미 있는 닉네임이에요'))
            return self.good()(job)
        self.passes('E-ME-32', probe)


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundle_mixes_one_two_device_case_and_two_phone_cases(self):
        self.assertEqual(area1.BUNDLES['area5-more'], ['E-ME-05', 'E-ME-22', 'E-ME-32'])
        self.assertIs(twodev.TWO['E-ME-05'], area5_more.TWO['E-ME-05'])
        for case in ('E-ME-22', 'E-ME-32'):
            self.assertIs(area1.PHONE[case], area5_more.PHONE[case])
            self.assertNotIn(case, twodev.TWO)
        self.assertNotIn('E-ME-05', area1.PHONE)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-ME-05'], 900)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        self.assertIn('from e2e import area5_more', main.__loader__.get_source('e2e.__main__'))
        self.assertIn('E-ME-22', area1.PHONE)

    def test_the_app_registers_the_same_cases_and_the_part_is_wired(self):
        text = self.dart('area5_more.dart')
        self.assertEqual(re.findall(r"^\s*'(E-[A-Z]+-\d+(?:/[AB])?)':", text, re.M), ['E-ME-05/A', 'E-ME-05/B', 'E-ME-22', 'E-ME-32'])
        wiring = self.dart('area5.dart')
        self.assertIn("part 'area5_more.dart';", wiring)
        self.assertIn('...area5CasesMore', wiring)

    def test_every_key_the_pc_reads_is_a_key_the_app_says(self):
        said_keys = set(re.findall(r"'(\w+)':", self.dart('area5_more.dart')))
        source = (tools.ROOT / 'e2e' / 'area5_more.py').read_text(encoding='utf-8')
        read = set(re.findall(r"said\.get\('(\w+)'", source))
        self.assertGreater(len(read), 5)
        self.assertEqual(sorted(read - said_keys), [])

    def test_the_two_device_steps_the_app_says_have_handlers(self):
        text = self.dart('area5_more.dart')
        self.assertEqual(text.count("_moreSayTexts(tester, 'card')"), 2)
        self.assertEqual(re.findall(r"step\('(\w+)'", text), ['slow'])


if __name__ == '__main__':
    unittest.main()
