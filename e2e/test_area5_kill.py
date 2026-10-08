"""영역 5 아바타 만드는 중 앱 죽이기 둘(E-EDGE-17 · 18)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_kill`.

가짜 앱 [ScriptApp](test_area5_edge)은 정한 멈춤을 차례로 말하고, 멈춤마다 앱 · 서버가 한 일을 on_step 이 흉내 낸다 — 누름이 서버에 닿으면 pending 행이 생기고,
워커가 끝나면 그 행이 ready 가 되며 하트가 빠지고 원장이 한 줄 생긴다. 죽이기는 EdgeBase 의 가짜 adb(pidof · run-as kill)가 받는다.
"""

import re
import unittest
from unittest import mock

from e2e import area1, area5_kill, tools
from e2e.area5_photo import COST, HEARTS, _paid_body
from e2e.test_area5_edge import EdgeBase, now
from e2e.fake_regen_photo import patch_regen_photo

CASES = ['E-EDGE-17', 'E-EDGE-18']


class KillBase(EdgeBase):
    def setUp(self):
        super().setUp()
        self.regen_calls = patch_regen_photo(self, area5_kill, when=lambda: len(self.fake.sent))  # 사진 옮기기 대신 부른 때만 적는다
        patcher = mock.patch.object(area5_kill, 'REGISTER_WAIT', 0.2)  # 새 시도 행을 기다리는 시간 — 닿지 않는 누름은 짧게 기다리고 막힌다
        patcher.start()
        self.addCleanup(patcher.stop)
        self.reached = True  # 누름이 서버에 닿는가
        self.worker_first = False  # 18: 다시 켠 앱이 15 를 열기 전에 워커가 끝났다
        self.second = 'same'  # 18: 두 번째 누름 — 'same' 같은 202(새 행 없음) · 'new' 새 시도 행을 또 만듦

    def who(self):
        return 'id-1'

    def avatars(self, status=None):
        return [a for a in self.fake.rows('profile_avatars') if a['profile_id'] == self.who() and (status is None or a['status'] == status)]

    def pending(self):
        if not self.reached:
            return
        row = {'id': f'new-{len(self.fake.rows("profile_avatars"))}', 'profile_id': self.who(), 'status': 'pending', 'storage_path': None,
               'created_at': now().isoformat()}
        self.fake.rows('profile_avatars').append(row)
        return row

    def finish(self, row, status='ready'):
        if row is None:
            return
        row.update(status=status, storage_path=f"{self.who()}/e2e-{row['id']}.png", created_at=now().isoformat())
        if status == 'ready':
            ent = next(e for e in self.fake.rows('entitlements') if e['profile_id'] == self.who())
            ent['heart_balance'] -= COST
            self.fake.rows('heart_transactions').append({'profile_id': self.who(), 'amount': -COST, 'reason': 'avatar_regen', 'ref_id': row['id']})

    def newest_name(self):
        return max(self.avatars('ready'), key=lambda a: a['created_at'])['storage_path'].rsplit('/', 1)[-1]

    def balance(self):
        return next(e for e in self.fake.rows('entitlements') if e['profile_id'] == self.who())['heart_balance']


class Edge17Test(KillBase):
    def run17(self, after=None, press=None, **over):
        state = {}

        def on_step(name, job):
            if name == 'pressed':
                state['row'] = self.pending()
                if state['row'] is not None:
                    self.finish(state['row'])  # 앱이 죽은 사이 워커가 끝난다

        def after_says(job):
            return {'avatar_file': self.newest_name(), 'sheet_body': _paid_body(self.balance()), **over}

        plan = {'press': (['pressed'], {}), 'after': ([], after or after_says)}
        return self.go('E-EDGE-17', plan, on_step)[0]

    def test_pass_the_worker_finishes_without_the_app_and_the_restarted_app_sees_it(self):
        result, note = self.run17()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.balance(), HEARTS - COST)
        self.assertIn('kill', ' '.join(map(str, self.adb_calls)))
        self.assertEqual(self.pids, [])  # 죽었다

    def test_the_kill_comes_right_after_the_server_has_the_attempt_row_and_not_by_force_stop(self):
        with mock.patch('time.sleep', lambda seconds: self.events.append(('sleep', seconds))):
            self.run17()
        waits = [e[1] for e in self.events if isinstance(e, tuple) and e[0] == 'sleep']
        self.assertTrue(any(area5_kill.KILL_AFTER - 0.1 <= w <= area5_kill.KILL_AFTER for w in waits), waits)
        self.assertFalse([c for c in self.adb_calls if 'force-stop' in c])

    def test_a_press_that_never_reached_the_server_is_blocked_not_failed(self):
        self.reached = False
        result, note = self.run17()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('안 닿았다', note)

    def test_a_worker_that_failed_is_blocked(self):
        def failing(name, job):
            if name == 'pressed':
                self.finish(self.pending(), 'failed')
        result, note = self.go('E-EDGE-17', {'press': (['pressed'], {}), 'after': ([], {})}, failing)[0]
        self.assertEqual(result, 'blocked', note)

    def test_the_old_picture_after_restart_is_a_fail(self):
        old = {'avatar_file': 'old.png'}
        result, note = self.run17(after=lambda job: {**old, 'sheet_body': _paid_body(HEARTS - COST)})
        self.assertEqual(result, 'fail', note)
        self.assertIn('히어로 그림', note)

    def test_the_old_hearts_after_restart_are_a_fail(self):
        result, note = self.run17(after=lambda job: {'avatar_file': self.newest_name(), 'sheet_body': _paid_body(HEARTS)})
        self.assertEqual(result, 'fail', note)
        self.assertIn('줄어든 하트', note)

    def test_a_charge_that_happened_twice_is_a_fail(self):
        def twice(name, job):
            if name == 'pressed':
                row = self.pending()
                self.finish(row)
                self.fake.rows('heart_transactions').append({'profile_id': self.who(), 'amount': -COST, 'reason': 'avatar_regen', 'ref_id': row['id']})
                self.fake.rows('entitlements')[0]['heart_balance'] -= COST
        result, note = self.go('E-EDGE-17', {'press': (['pressed'], {}), 'after': ([], lambda job: {'avatar_file': self.newest_name(), 'sheet_body': ''})}, twice)[0]
        self.assertEqual(result, 'fail', note)
        self.assertIn('두 번 안 빠짐', note)


class Edge18Test(KillBase):
    def run18(self, **over):
        state = {}

        def on_step(name, job):
            if name == 'pressed':
                state['row'] = self.pending()
            if name == 'opened':
                if self.worker_first:
                    self.finish(state['row'])
                    return
            if name == 'finished':
                if self.second == 'new':
                    state['second'] = self.pending()  # 두 번째 누름이 새 시도를 만들었다
                self.finish(state['row'])
                if state.get('second'):
                    self.finish(state['second'])

        def after(job):
            return {'sheet_body': _paid_body(self.balance() + COST), 'generating_seen': True, 'avatar_changed': True, 'generating_gone': True,
                    'regen_state': 'ready', 'waited_ms': 60000, **over}

        plan = {'press': (['pressed'], {}), 'after': (['opened', 'finished'], after)}
        return self.go('E-EDGE-18', plan, on_step)[0]

    def test_pass_the_second_press_joins_the_running_attempt_and_the_hearts_go_once(self):
        result, note = self.run18()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(len(self.avatars()), 3)  # 처음 2장 + 새 행 1개
        self.assertEqual(self.balance(), HEARTS - COST)

    def test_it_waits_ten_seconds_after_the_kill_before_the_app_starts(self):
        sleeps = []
        with mock.patch('time.sleep', lambda seconds: sleeps.append(seconds)):
            self.run18()
        self.assertTrue(any(s >= area5_kill.LATE - 1 for s in sleeps), sleeps)

    def test_a_second_attempt_row_is_a_fail(self):
        self.second = 'new'
        result, note = self.run18()
        self.assertEqual(result, 'fail', note)
        self.assertIn('작업이 하나만', note)

    def test_an_attempt_that_finished_before_the_app_pressed_again_is_blocked(self):
        self.worker_first = True
        result, note = self.run18()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('이미 끝났', note)

    def test_a_press_that_never_reached_the_server_is_blocked(self):
        self.reached = False
        result, note = self.run18()
        self.assertEqual(result, 'blocked', note)

    def test_a_screen_without_the_generating_notice_is_a_fail(self):
        result, note = self.run18(generating_seen=False)
        self.assertEqual(result, 'fail', note)


class RegistryTest(unittest.TestCase):
    def dart(self, name='area5_kill.dart'):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_two_are_phone_cases_in_one_bundle_with_room_for_the_worker(self):
        self.assertEqual(area1.BUNDLES['area5-kill'], CASES)
        for case in CASES:
            self.assertIs(area1.PHONE[case], area5_kill.PHONE[case])
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 1200)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        self.assertIn('area5_kill', main.__loader__.get_source('e2e.__main__'))

    def test_the_app_registers_the_two_and_the_part_is_wired(self):
        self.assertEqual(re.findall(r"^\s*'(E-EDGE-\d+)':", self.dart(), re.M), CASES)
        self.assertIn("part 'area5_kill.dart';", self.dart('area5.dart'))
        self.assertIn('...area5CasesKill', self.dart('area5.dart'))

    def test_every_key_the_pc_reads_is_a_key_the_app_says(self):
        said = set(re.findall(r"'(\w+)':", self.dart())) | {'generating_seen', 'avatar_changed', 'generating_gone', 'regen_state', 'waited_ms'}  # 뒤 다섯은 _photoRegenWait 가 말한다
        source = (tools.ROOT / 'e2e' / 'area5_kill.py').read_text(encoding='utf-8')
        read = set(re.findall(r"said\.get\('(\w+)'", source))
        self.assertGreater(len(read), 1)
        self.assertEqual(sorted(read - said), [])

    def test_the_press_phase_stops_at_pressed_and_after_phase_stops_at_opened_for_18_only(self):
        text = self.dart()
        self.assertEqual(re.findall(r"say\(\{'step': '(\w+)'\}\)", text), ['pressed'])
        self.assertEqual(re.findall(r"step\('(\w+)'\)", text), ['opened'])
        self.assertIn("'E-EDGE-18'", text.split("await step('opened')")[0])

    def test_nothing_in_the_app_files_taps_a_free_or_charge_button_or_withdraws(self):
        text = self.dart()
        self.assertNotIn('_wdWithdraw', text)
        self.assertNotIn('_photoCharge', text)
        self.assertEqual(text.count('_photoPaidCta'), 2)  # 누르는 곳은 press 단계 · 18 의 다시 켠 뒤 둘뿐

    def test_the_kill_helper_is_shared_with_edge_20_and_keeps_its_default(self):
        from e2e import area5_wd
        import inspect
        self.assertEqual(inspect.signature(area5_wd._kill_soon).parameters['after'].default, area5_wd.KILL_AFTER)
