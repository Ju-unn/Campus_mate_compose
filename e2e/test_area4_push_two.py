"""영역 4 알림 두 기기 3개(E-PUSH-64 · 65 · 71)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 서버 · 가짜 알림 · 가짜 `two` 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_two`.

가짜 세계 [World] 는 기기(A · B)마다 로그인한 토큰 · 알림 창을 들고 있다 — 올바른 서버면 pass, 규칙 하나를 어긴 서버([World.rules])면 fail 이어야 한다.
가짜 `two`([FakeTwo])는 앱이 말하는 차례(script)대로 가설이 건 핸들러를 부른다 — 앱이 서버에 남기는 일은 차례마다 effect 로 흉내 낸다.
"""

import unittest
from unittest import mock

from e2e import area1, area2_two_accept, area4_push_two as two_mod, tools, twodev
from e2e.tools import Blocked

CASES = ['E-PUSH-64', 'E-PUSH-65', 'E-PUSH-71']
SERIALS = {'A': 'phone-A', 'B': 'emu-B'}
ACCOUNT = {'id': 'id-1', 'email': 'a@e2e.test', 'n': 1}


class World:
    """기기별 서버 토큰 · 알림 창. rules 는 서버가 어기는 규칙(기본은 올바른 서버)."""

    def __init__(self):
        self.tokens = {}  # 기기 → 서버에 올라간 토큰
        self.shown = {serial: [] for serial in SERIALS.values()}
        self.rules = dict(replace_on_login=False, only_last_device=False, logout_clears_all=False, logout_keeps_token=False,
                          withdraw_keeps=False, ignore_denied=False)
        self.sent = 0

    def login(self, device):
        if self.rules['replace_on_login']:
            self.tokens.clear()
        self.tokens[device] = f'token-{device}'

    def logout(self, device):
        if self.rules['logout_clears_all']:
            self.tokens.clear()
        elif not self.rules['logout_keeps_token']:
            self.tokens.pop(device, None)

    def withdraw(self):
        if not self.rules['withdraw_keeps']:
            self.tokens.clear()

    def rows(self):
        return [{'token': token, 'platform': 'android'} for token in self.tokens.values()]

    def send(self):
        self.sent += 1
        devices = list(self.tokens)[-1:] if self.rules['only_last_device'] else list(self.tokens)
        for device in devices:
            self.shown[SERIALS[device]].append('NICK')
        return 'NICK'


class FakeRun:
    def account(self, kind):
        return dict(ACCOUNT)


    def link(self, email):
        return f'link-{email}'


class FakeTwo:
    """twodev.bound 가 주는 `two` 대신 — script = [(쪽, step 이름, effect)] 차례대로 plan 의 핸들러를 부른다."""

    serials = SERIALS

    def __init__(self, test, script, result=('pass', 'A: pass  B: pass')):
        self.test, self.script, self.result = test, script, result
        self.a_job = self.limit = None
        self.sync = twodev.Sync()

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.a_job, self.limit = a_job, limit
        self.test.assertEqual(sorted(plan), sorted((side, step) for side, step, _ in self.script))
        for side, step, effect in self.script:
            if effect:
                effect()
            plan[(side, step)]({'step': step, 't': 0}, self.sync)
        return self.result


class Base(unittest.TestCase):
    def setUp(self):
        self.world = World()
        world = self.world
        patchers = [
            mock.patch.object(two_mod, '_tokens', lambda run, account_id: world.rows()),
            mock.patch.object(two_mod, '_send_from', lambda run, sender, account: world.send()),
            mock.patch.object(two_mod, '_need_token', lambda run, account, why: None if world.rows() else self.fail('토큰 없음')),
            mock.patch.object(two_mod, '_wait', lambda until, seconds: until()),
            mock.patch.object(two_mod, '_arrived', lambda serial, before, nick: world.shown[serial][len(before):] == [nick]),
            mock.patch.object(two_mod, '_quiet', lambda serial, before: world.shown[serial][len(before):]),
            mock.patch.object(two_mod.notify, 'require_daytime', lambda: None),
            mock.patch.object(two_mod.notify, 'ensure_delivery', lambda serial: None),
            mock.patch.object(two_mod.notify, 'background', lambda serial: None),
            mock.patch.object(two_mod.notify, 'read_notifications', lambda serial: list(world.shown[serial])),
            mock.patch.object(area2_two_accept, 'PEER', 0.05),
        ]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def go(self, case, script, result=('pass', 'A: pass  B: pass')):
        self.two = FakeTwo(self, script, result)
        return twodev.TWO[case](FakeRun(), self.two)

    def login(self, device):
        return lambda: self.world.login(device)

    def joined(self):
        """둘이 로그인하는 앞 차례 — A in · B wait · B in."""
        return [('A', 'in', self.login('A')), ('B', 'wait', None), ('B', 'in', self.login('B'))]

    def script(self, case):
        tail = {'E-PUSH-64': [('A', 'hold', None)],
                'E-PUSH-65': [('A', 'both', None), ('A', 'out', lambda: self.world.logout('A')), ('B', 'stay', None)],
                'E-PUSH-71': [('A', 'both', None), ('A', 'withdrawn', self.world.withdraw), ('B', 'stay', None)]}
        return self.joined() + tail[case]

    def passes(self, case):
        result, memo = self.go(case, self.script(case))
        self.assertEqual(result, 'pass', memo)

    def fails(self, case, rule, *words):
        self.world.rules[rule] = True
        result, memo = self.go(case, self.script(case))
        self.assertEqual(result, 'fail', memo)
        for word in words:
            self.assertIn(word, memo)


class Push64Test(Base):
    def test_both_devices_get_the_notice(self):
        self.passes('E-PUSH-64')
        self.assertEqual(self.world.shown, {'phone-A': ['NICK'], 'emu-B': ['NICK']})

    def test_a_second_login_that_replaces_the_first_token_fails(self):
        self.fails('E-PUSH-64', 'replace_on_login', 'push_tokens')

    def test_a_notice_that_reaches_only_one_device_fails(self):
        self.fails('E-PUSH-64', 'only_last_device', 'A 에 알림이')

    def test_b_logs_in_with_a_fresh_token_only_after_a_is_in(self):
        self.go('E-PUSH-64', self.script('E-PUSH-64'))
        self.assertEqual(self.two.a_job, {'token_hash': 'link-a@e2e.test'})


class Push65Test(Base):
    def test_only_the_logged_out_device_stops_getting_notices(self):
        self.passes('E-PUSH-65')
        self.assertEqual(self.world.shown, {'phone-A': [], 'emu-B': ['NICK']})

    def test_a_server_that_keeps_the_logged_out_token_fails(self):
        self.fails('E-PUSH-65', 'logout_keeps_token', 'push_tokens')

    def test_a_server_that_clears_every_token_on_logout_fails(self):
        self.fails('E-PUSH-65', 'logout_clears_all', 'push_tokens')


class Push71Test(Base):
    def test_withdrawing_clears_every_token(self):
        self.passes('E-PUSH-71')
        self.assertEqual(self.world.sent, 0)  # 탈퇴한 계정에는 알림을 보내지 않는다

    def test_tokens_left_after_withdrawal_fail(self):
        self.fails('E-PUSH-71', 'withdraw_keeps', '탈퇴했는데')


class VerdictTest(Base):
    def test_an_app_result_passes_through_when_the_pc_saw_nothing_wrong(self):
        self.assertEqual(self.go('E-PUSH-71', self.script('E-PUSH-71'), ('blocked', 'B: 막힘')), ('blocked', 'B: 막힘'))

    def test_what_the_pc_found_beats_a_blocked_app(self):
        self.world.rules['withdraw_keeps'] = True
        result, memo = self.go('E-PUSH-71', self.script('E-PUSH-71'), ('blocked', 'B: 막힘'))
        self.assertEqual(result, 'fail')
        self.assertIn('B: 막힘', memo)

    def test_a_missing_serial_blocks(self):
        two = FakeTwo(self, [])
        two.serials = {}
        with self.assertRaises(Blocked):
            twodev.TWO['E-PUSH-64'](FakeRun(), two)


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_three_cases_are_two_device_hypotheses_in_one_bundle(self):
        self.assertEqual(area1.BUNDLES['area4-push-two'], CASES)
        for case in CASES:
            self.assertIs(twodev.TWO[case], two_mod.TWO[case])
            self.assertNotIn(case, area1.PHONE)
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 900)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        self.assertIn('area4_push_two', main.__loader__.get_source('e2e.__main__'))
        self.assertEqual(main.BUNDLES['area4-push-two'], CASES)

    def test_bound_hands_over_both_serials(self):
        run = object()
        a, b = twodev.Side(None, 'phone-A'), twodev.Side(None, 'emu-B')
        self.assertEqual(twodev.bound(run, 'E-PUSH-64', a, b).serials, SERIALS)

    def test_the_app_has_an_a_and_a_b_side_for_each_case(self):
        text = self.dart('area4_push_two.dart')
        for case in CASES:
            for side in 'AB':
                self.assertIn(f"'{case}/{side}':", text)
        self.assertIn("part 'area4_push_two.dart';", self.dart('area4.dart'))
        self.assertIn('..._pushTwoCases,', self.dart('area4.dart'))

    def test_every_step_the_app_says_has_a_handler_and_the_other_way_round(self):
        import re
        text = self.dart('area4_push_two.dart')
        for case, mod in (('E-PUSH-64', 'push_64'), ('E-PUSH-65', 'push_65'), ('E-PUSH-71', 'push_71')):
            heard = set()
            for side in 'AB':
                body = text.split(f"'{case}/{side}':")[1].split("}),")[0]
                heard |= {(side, name) for name in re.findall(r"step\('(\w+)'", body) + re.findall(r"_joinAfter\(tester, '(\w+)'", body)}
            keys = []
            fake = lambda plan, *a, **k: keys.extend(plan) or ('pass', '')  # noqa: E731
            fake.serials = SERIALS
            with mock.patch.object(two_mod.notify, 'require_daytime', lambda: None), \
                    mock.patch.object(two_mod.notify, 'ensure_delivery', lambda serial: None):
                getattr(two_mod, mod)(FakeRun(), fake)
            self.assertEqual(heard, set(keys), case)


if __name__ == '__main__':
    unittest.main()
