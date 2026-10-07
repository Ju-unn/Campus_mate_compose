"""영역 5 새 5개(E-EDGE-04 · 10 · 12, E-WD-19 · 20)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_new`.

가짜 서버는 area5_wd 시험의 [WdFake](탈퇴 · GoTrue /user · 로그인 끊기)에 logout scope=global 을 더했다. 가짜 앱은 area5_edge 시험의 [ScriptApp]
(phase 마다 멈춤을 차례로 말하고 끝에 말을 돌려준다). 가짜 adb 는 에뮬 콘솔(network delay) · svc wifi · 글자 배율(settings system font_scale) ·
adb root(shell id) · 시계(date)를 흉내 내 [events] 에 남긴다 — 시계 · 망 · 글자 배율이 어떤 끝에서도 되돌아오는지는 이 기록으로 본다.
시험의 글자는 모듈에서 가져오지 않고 그대로 적었다.
"""

import ast
import os
import re
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2_phone3, area5_new, emu, notify, tools
from e2e.test_area3_safe import _who
from e2e.test_area5_edge import ScriptApp
from e2e.test_area5_wd import WdBase, code_of, dart, top_functions
from e2e.tools import Reply

CASES = ['E-EDGE-04', 'E-EDGE-12', 'E-WD-19', 'E-WD-20', 'E-EDGE-10', 'E-EDGE-09']
EMULATOR = ['E-EDGE-04', 'E-WD-20', 'E-EDGE-10', 'E-EDGE-09']
NETWORK = '네트워크 연결을 확인해 주세요'
WITHDRAWN = '탈퇴한 계정이에요'
EXPIRED = '세션이 만료됐어요, 다시 로그인해 주세요'
EMU = 'emulator-5554'
SCREENS = ['15', '15-4', '15-5', '06-1', '15-6', '15-6-2', '15-7']


def now():
    return datetime.now(timezone.utc)


class App(ScriptApp):
    port = 8765  # area2_phone3.offline 이 끝에 adb reverse 를 다시 걸 때 읽는다


class NewBase(WdBase):
    def setUp(self):
        super().setUp()
        self.font = '1.0'  # 기기의 지금 글자 배율
        self.font_takes = True
        self.rooted = True
        self.wifi = True
        self.wifi_drops = True  # False: svc wifi disable 이 안 먹는 에뮬(핑이 계속 닿음)
        self.clock = None  # 에뮬 시계(epoch) — None 이면 PC 시계
        self.logout_cuts = True

        def fake_adb(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            line = ' '.join(args)
            if args[:1] == ('emu',):
                self.events.append(line)
            elif 'pidof' in args:
                return ' '.join(self.pids)
            elif 'kill' in args:
                self.pids.clear()
            elif line == 'shell settings get system font_scale':
                return self.font + '\n'
            elif line.startswith('shell settings put system font_scale'):
                self.events.append(f'font {args[-1]}')
                if self.font_takes:
                    self.font = args[-1]
            elif line == 'shell id':
                return 'uid=0(root)' if self.rooted else 'uid=2000(shell)'
            elif line.startswith('shell svc wifi'):
                self.wifi = args[-1] == 'enable' or not self.wifi_drops
                self.events.append(f'wifi {self.wifi}')
            elif args[:3] == ('shell', 'date', '-u'):
                moment = datetime.strptime(args[3], '%m%d%H%M%Y.%S').replace(tzinfo=timezone.utc)
                self.clock = moment.timestamp()
                self.events.append(('clock', moment))
            elif line == 'shell date +%s':
                return str(int(self.clock if self.clock is not None else now().timestamp()))
            elif line.startswith('shell settings put global auto_time'):
                self.events.append(f'auto_time {args[-1]}')
            return ''

        def logout(sent):
            if self.logout_cuts:
                self.fake.cut.add(_who(sent))
            return Reply(204, None)

        self.fake.on('POST', r'/auth/v1/logout', logout)
        for patcher in (mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(emu, 'online', lambda serial: self.wifi),
                        mock.patch.object(notify, 'airplane', lambda serial, on, settle=None: self.events.append(('airplane', on))),
                        mock.patch.object(notify, 'ensure_online', lambda serial: self.events.append('ensure_online')),
                        mock.patch.object(area2_phone3, '_guard'), mock.patch.dict(os.environ, {'E2E_REAL_AI': '1'})):
            patcher.start()
            self.addCleanup(patcher.stop)
        area2_phone3._PAID.clear()
        self.addCleanup(area2_phone3._PAID.clear)

    def go(self, name, plan, on_step=None, serial=EMU):
        app = App(plan, self.events, on_step, serial=serial)
        (result, note), _ = self.case(name, None, app)
        return result, note, app

    def emu_lines(self):
        return [e for e in self.events if isinstance(e, str) and e.startswith('emu ')]

    def avatars(self, n=1):
        return [r for r in self.fake.rows('profile_avatars') if r['profile_id'] == f'id-{n}']


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_the_five_are_phone_cases_in_one_bundle_with_the_rooted_one_last(self):
        self.assertEqual(area1.BUNDLES['area5-new'], CASES)
        self.assertEqual(list(area5_new.PHONE), CASES)
        self.assertLessEqual(set(CASES), set(area1.PHONE))
        self.assertEqual(area5_new.EMULATOR, EMULATOR)

    def test_the_runner_sees_the_bundle(self):
        probe = 'from e2e import __main__ as m; print(m.BUNDLES.get("area5-new"))'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), str(CASES))

    def test_the_long_cases_get_room(self):
        for case in CASES:
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 600, case)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-EDGE-04'], area2_phone3.AI_WAIT + 600)

    def test_edge_04_lets_the_image_read_errors_of_the_cut_network_pass_and_always_restores_the_handler(self):
        # 망을 끊은 사이 히어로(DecorationImage · 오류 처리 없음)가 던지는 이미지 읽기 오류가 시험 실패가 되어 가설이 끝났다(2026-10-07 실행).
        body = dart('area5_new.dart').split('Future<Map<String, Object?>> _nwRegenOffline(')[1].split('Future<Map<String, Object?>> _nwRegenOfflineBody(')[0]
        self.assertIn("details.library == 'image resource service'", body)
        self.assertIn('previous?.call(details)', body)  # 그 밖의 오류는 그대로 시험 바탕으로
        self.assertIn("'image_errors'", body)
        self.assertIn('finally {', body)
        self.assertIn('FlutterError.onError = previous;', body.split('finally {')[1])

    def test_the_app_registers_the_five_and_the_keys_match(self):
        text = dart('area5_new.dart')
        self.assertEqual(re.findall(r"^\s*'(E-[A-Z]+-\d+)':", text, re.M), CASES)
        area5 = dart('area5.dart')
        self.assertIn("part 'area5_new.dart';", area5)
        self.assertIn('...area5CasesNew', area5)
        tree = ast.parse(Path(area5_new.__file__).read_text(encoding='utf-8'))
        read = {node.args[0].value for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get'
                and isinstance(node.func.value, ast.Name) and node.func.value.id in ('said', 'row')
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)}
        self.assertGreaterEqual(len(read), 15)
        self.assertEqual(sorted(read - set(re.findall(r"'(\w+)':", text))), [])
        wanted = set(re.findall(r"job\['(\w+)'\]", text))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) for kw in node.keywords if kw.arg}
        self.assertEqual(sorted(wanted - sent), [])

    def test_the_final_delete_button_is_pressed_only_through_the_wd_helper_in_wd_19_and_20(self):
        code = code_of(dart('area5_new.dart'))
        self.assertNotIn('정말 영구 삭제', code)
        self.assertNotIn('_wdForever', code)
        bodies = dict(zip(*[iter(re.split(r"(?m)^  '(E-[A-Z]+-\d+)':", code.split('area5CasesNew = {', 1)[1])[1:])] * 2))
        functions = top_functions(code)
        reach = {'_wdWithdraw'}
        for _ in range(5):  # 도우미가 도우미를 부르는 것까지 따라간다
            reach |= {name for name, body in functions.items() if any(f'{r}(' in body for r in reach)}
        pressing = [case for case, body in bodies.items() if any(re.search(rf'\b{r}\b', body) for r in reach)]
        self.assertEqual(pressing, ['E-WD-19', 'E-WD-20'])
        self.assertEqual(code.count('_wdWithdraw('), 4)  # 19 · 20 이 두 번씩

    def test_the_known_overflows_are_the_scenario_ones(self):
        self.assertEqual(area5_new.KNOWN, (('06-1', 'appearance_pickers.dart', 1.3), ('06-1', 'mbti_pole_toggle.dart', 2.0)))
        self.assertEqual(area5_new.SCALES, (1.3, 2.0))
        self.assertEqual(area5_new.SCREENS, SCREENS)
        lib = tools.ROOT / 'frontend' / 'lib'
        self.assertIn('class AnimalTypePicker', (lib / 'profile' / 'view' / 'appearance_pickers.dart').read_text(encoding='utf-8'))
        self.assertIn('class MbtiPoleToggle', (lib / 'common' / 'widgets' / 'mbti_pole_toggle.dart').read_text(encoding='utf-8'))


# ── E-EDGE-04 응답만 놓친 다시 만들기 ─────────────────────────────────────────────────────────────────

class Edge04Test(NewBase):
    CASE = 'E-EDGE-04'

    def answer(self, **over):
        return {'generating_seen': True, 'generating_ms': 40000, 'failed_toast': False, 'avatar_changed': True,
                'regen_state': 'ready', **over}

    def run04(self, reached=True, answer=None, serial=EMU):
        def step(name, job):
            if name == 'pressed' and reached:
                self.fake.rows('profile_avatars').append({'id': 'new', 'profile_id': f'id-{self.fake.verifies}', 'status': 'pending',
                                                          'storage_path': 'x/new.png', 'created_at': now().isoformat()})

        def finish(job):
            for row in self.fake.rows('profile_avatars'):
                if row['id'] == 'new':
                    row['status'] = 'ready'
            return answer or self.answer(**({} if reached else {'avatar_changed': False}))
        return self.go(self.CASE, {None: (['ready', 'pressed'], finish)}, step, serial=serial)

    def test_pass_a_request_that_reached_keeps_the_spinner_and_ends_in_the_new_picture(self):
        result, note, _ = self.run04()
        self.assertEqual(result, 'pass', note)
        self.assertIn('닿음', note)
        lines = self.emu_lines()
        self.assertEqual(lines[0], 'emu network delay 5000')
        self.assertEqual(lines[-1], 'emu network delay none')
        wifi = [e for e in self.events if isinstance(e, str) and e.startswith('wifi')]
        self.assertEqual(wifi[:2], ['wifi False', 'wifi True'])
        self.assertTrue(self.wifi)

    def test_pass_a_request_that_never_reached_is_recorded(self):
        result, note, _ = self.run04(reached=False)
        self.assertEqual(result, 'pass', note)
        self.assertIn('안 닿음', note)

    def test_a_failure_toast_or_a_spinner_that_drops_during_the_outage_is_a_fail(self):
        for over in ({'failed_toast': True}, {'generating_ms': 3000}, {'generating_seen': False}):
            with self.subTest(over):
                self.setUp()
                result, note, _ = self.run04(answer=self.answer(**over))
                self.assertEqual(result, 'fail', note)

    def test_a_reached_request_without_the_new_picture_is_a_fail(self):
        result, note, _ = self.run04(answer=self.answer(avatar_changed=False))
        self.assertEqual(result, 'fail', note)

    def test_the_network_comes_back_even_when_the_app_blocks(self):
        result, note, _ = self.run04(answer={'result': 'blocked', 'note': '앱 막힘'})
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.emu_lines()[-1], 'emu network delay none')
        self.assertTrue(self.wifi)

    def test_a_network_that_will_not_drop_is_blocked_and_turned_back_on(self):
        self.wifi_drops = False
        result, note, _ = self.run04()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('끊', note)
        wifi = [e for e in self.events if isinstance(e, str) and e.startswith('wifi')]
        self.assertEqual(wifi[-1], 'wifi True')
        self.assertEqual(self.emu_lines()[-1], 'emu network delay none')

    def test_the_network_comes_back_when_the_case_limit_hits_during_the_outage(self):
        def sleep(seconds):
            if seconds > 5 and not self.wifi:  # 10초 단절 쉬기(이미 잰 만큼 뺀 값)
                raise tools.CaseTimeout('상한')
        with mock.patch('time.sleep', sleep):
            with self.assertRaises(tools.CaseTimeout):
                self.run04()
        self.assertTrue(self.wifi)
        self.assertEqual(self.emu_lines()[-1], 'emu network delay none')

    def test_it_is_blocked_without_the_paid_switch_before_any_account(self):
        with mock.patch.dict(os.environ, {'E2E_REAL_AI': ''}):
            result, note, _ = self.run04()
        self.assertEqual(result, 'blocked', note)
        self.assertFalse(self.fake.users)

    def test_it_runs_only_on_the_emulator(self):
        result, note, _ = self.run04(serial='R5CT')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('에뮬', note)
        self.assertEqual(self.emu_lines(), [])

    def test_a_paid_fail_is_not_run_again(self):
        result, note, app = self.run04(answer=self.answer(failed_toast=True))
        self.assertEqual(result, 'fail', note)
        again = App({None: ([], {})}, self.events)
        (result2, note2), _ = self.case(self.CASE, None, again)
        self.assertEqual(result2, 'fail')
        self.assertIn('다시 하지 않음', note2)
        self.assertEqual(again.jobs, [])


# ── E-EDGE-10 세션을 전부 끊은 뒤 ────────────────────────────────────────────────────────────────────

class Edge10Test(NewBase):
    CASE = 'E-EDGE-10'

    def run10(self, steps, answer, on_step=None, serial=EMU):
        return self.go(self.CASE, {None: (steps, answer)}, on_step, serial=serial)

    def saved(self, name, job):
        if name == '15-5:saved':
            self.profile(self.fake.verifies).update(height_cm=int(job['height']))

    def clock_moves(self):
        return [e[1] for e in self.events if isinstance(e, tuple) and e[0] == 'clock']

    def test_pass_a_cut_session_sends_the_first_save_to_02_with_the_expired_notice(self):
        result, note, _ = self.run10(['15-6:opened', 'end'], {'login_after_save': True, 'notice': EXPIRED, 'saved_title': None})
        self.assertEqual(result, 'pass', note)
        logout = [s for s in self.fake.sent if s['path'] == '/auth/v1/logout']
        self.assertEqual([s['query'] for s in logout], [{'scope': 'global'}])
        self.assertEqual(self.clock_moves(), [])
        self.assertIn('시나리오', note)
        self.assertEqual(self.profile()['height_cm'], 178)

    def test_a_save_that_lands_on_a_cut_session_is_a_fail(self):
        result, note, _ = self.run10(['15-6:opened', 'end'], {'login_after_save': False, 'notice': None, 'saved_title': '프로필 편집'})
        self.assertEqual(result, 'fail', note)

    def test_pass_a_live_session_saves_then_the_clock_jump_sends_it_to_02_and_the_clock_comes_back(self):
        self.logout_cuts = False
        answer = {'login_after_save': False, 'notice': None, 'saved_title': '프로필 편집', 'login_ms': 30000, 'late_notice': None}
        result, note, _ = self.run10(['15-6:opened', '15-5:saved', 'end'], answer, self.saved)
        self.assertEqual(result, 'pass', note)
        moves = self.clock_moves()
        self.assertEqual(len(moves), 2)
        self.assertAlmostEqual((moves[0] - now()).total_seconds(), 65 * 60, delta=60)
        self.assertAlmostEqual((moves[1] - now()).total_seconds(), 0, delta=60)
        self.assertEqual([e for e in self.events if isinstance(e, str) and e.startswith('auto_time')], ['auto_time 0', 'auto_time 1'])

    def test_02_later_than_60_seconds_after_the_jump_is_a_fail_and_the_clock_still_comes_back(self):
        self.logout_cuts = False
        answer = {'login_after_save': False, 'notice': None, 'saved_title': '프로필 편집', 'login_ms': 90000, 'late_notice': None}
        result, note, _ = self.run10(['15-6:opened', '15-5:saved', 'end'], answer, self.saved)
        self.assertEqual(result, 'fail', note)
        self.assertAlmostEqual((self.clock_moves()[-1] - now()).total_seconds(), 0, delta=60)

    def test_the_clock_comes_back_when_the_app_blocks_after_the_jump(self):
        self.logout_cuts = False
        result, note, _ = self.run10(['15-6:opened', '15-5:saved', 'end'], {'result': 'blocked', 'note': '앱 막힘'}, self.saved)
        self.assertEqual(result, 'blocked', note)
        self.assertAlmostEqual((self.clock_moves()[-1] - now()).total_seconds(), 0, delta=60)
        self.assertEqual([e for e in self.events if isinstance(e, str) and e.startswith('auto_time')][-1], 'auto_time 1')

    def test_no_root_is_blocked_before_any_account(self):
        self.rooted = False
        result, note, _ = self.run10(['15-6:opened', 'end'], {})
        self.assertEqual(result, 'blocked', note)
        self.assertIn('root', note)
        self.assertFalse(self.fake.users)

    def test_it_runs_only_on_the_emulator(self):
        result, note, _ = self.run10(['15-6:opened', 'end'], {}, serial='R5CT')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('에뮬', note)


class Edge09Test(NewBase):
    CASE = 'E-EDGE-09'

    GOOD = {'login_seen': False, 'expired_seen': False, 'saved_title': '프로필 편집'}

    def run09(self, answer=None, serial=EMU, steps=('15-6:opened', 'end')):
        def finish(job):
            if answer is None or answer.get('result') != 'blocked':
                self.profile(self.fake.verifies).update(height_cm=int(job['height']))  # 앱이 저장을 눌렀다
            return answer if answer is not None else dict(self.GOOD)
        return self.go(self.CASE, {None: (list(steps), finish)}, serial=serial)

    def clock_moves(self):
        return [e[1] for e in self.events if isinstance(e, tuple) and e[0] == 'clock']

    def test_pass_the_first_save_lands_on_15_5_with_no_02_and_no_expired_notice(self):
        result, note, _ = self.run09()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.profile()['height_cm'], 181)
        moves = self.clock_moves()
        self.assertEqual(len(moves), 2)
        self.assertAlmostEqual((moves[0] - now()).total_seconds(), 65 * 60, delta=60)
        self.assertAlmostEqual((moves[1] - now()).total_seconds(), 0, delta=60)
        self.assertEqual([e for e in self.events if isinstance(e, str) and e.startswith('auto_time')], ['auto_time 0', 'auto_time 1'])

    def test_a_trip_to_02_or_an_expired_notice_or_a_wrong_screen_is_a_fail(self):
        for over, word in (({'login_seen': True}, '02'), ({'expired_seen': True}, '알림'), ({'saved_title': '기본 정보 수정'}, '저장 뒤 화면')):
            with self.subTest(over):
                result, note, _ = self.run09({**self.GOOD, **over})
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_a_save_that_did_not_reach_the_db_is_a_fail(self):
        def finish(job):
            return dict(self.GOOD)  # 앱은 15-5 라는데 DB 는 그대로
        result, note, _ = self.go(self.CASE, {None: (['15-6:opened', 'end'], finish)}, serial=EMU)
        self.assertEqual(result, 'fail', note)
        self.assertIn('DB 키', note)

    def test_the_clock_comes_back_when_the_app_blocks_after_the_jump(self):
        result, note, _ = self.run09({'result': 'blocked', 'note': '앱 막힘'})
        self.assertEqual(result, 'blocked', note)
        self.assertAlmostEqual((self.clock_moves()[-1] - now()).total_seconds(), 0, delta=60)
        self.assertEqual([e for e in self.events if isinstance(e, str) and e.startswith('auto_time')][-1], 'auto_time 1')

    def test_an_app_that_never_stops_at_15_6_is_a_fail_without_a_clock_jump(self):
        result, note, _ = self.run09(steps=())
        self.assertEqual(result, 'fail', note)
        self.assertEqual(self.clock_moves(), [])

    def test_no_root_is_blocked_before_any_account(self):
        self.rooted = False
        result, note, _ = self.run09()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('root', note)
        self.assertFalse(self.fake.users)

    def test_it_runs_only_on_the_emulator(self):
        result, note, _ = self.run09(serial='R5CT')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('에뮬', note)

    def test_it_goes_after_the_other_rooted_case_so_root_never_leaks_into_a_phone_case(self):
        self.assertEqual(CASES[-2:], ['E-EDGE-10', 'E-EDGE-09'])


# ── E-EDGE-12 큰 글자에서 넘침 ───────────────────────────────────────────────────────────────────────

class Edge12Test(NewBase):
    CASE = 'E-EDGE-12'

    def run12(self, overflows=None, answer=None, serial='R5CT'):
        """[overflows] = 배율 → [(화면, 위치)]."""
        def finish(job):
            if answer is not None:
                return answer
            found = [{'screen': s, 'where': w} for s, w in (overflows or {}).get(job['scale'], [])]
            return {'overflows': found, 'visited': SCREENS, 'locked': True, 'scale_seen': job['scale']}
        return self.go(self.CASE, {None: (['lock'], finish)}, serial=serial)

    def fonts(self):
        return [e for e in self.events if isinstance(e, str) and e.startswith('font ')]

    def test_pass_no_overflow_at_either_scale_and_the_font_comes_back(self):
        result, note, app = self.run12()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.fonts(), ['font 1.3', 'font 1.0', 'font 2.0', 'font 1.0'])
        self.assertEqual([j['scale'] for j in app.jobs], [1.3, 2.0])
        self.assertEqual(self.font, '1.0')

    def test_pass_the_known_ones_are_marked_not_failed(self):
        known = {1.3: [('06-1', 'profile/view/appearance_pickers.dart:120')],
                 2.0: [('06-1', 'profile/view/appearance_pickers.dart:120'), ('06-1', 'common/widgets/mbti_pole_toggle.dart:43')]}
        result, note, _ = self.run12(known)
        self.assertEqual(result, 'pass', note)
        self.assertIn('알려진', note)

    def test_any_other_overflow_is_a_fail(self):
        for overflows in ({1.3: [('15-5', 'me/view/profile_manage_screen.dart:227')]},
                          {1.3: [('06-1', 'common/widgets/mbti_pole_toggle.dart:43')]},  # MBTI 는 2.0 배부터 알려진 것
                          {2.0: [('15-7', 'Exception: A RenderFlex overflowed')]}):
            with self.subTest(overflows):
                self.setUp()
                result, note, _ = self.run12(overflows)
                self.assertEqual(result, 'fail', note)
                self.assertIn(next(iter(overflows.values()))[0][0], note)

    def test_the_font_comes_back_when_the_app_blocks(self):
        result, note, _ = self.run12(answer={'result': 'blocked', 'note': '배율이 안 먹음'})
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.font, '1.0')

    def test_an_unset_font_comes_back_as_one(self):
        self.font = 'null'
        result, note, _ = self.run12()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.fonts()[-1], 'font 1.0')

    def test_a_font_that_will_not_change_is_blocked_and_restored(self):
        self.font_takes = False
        result, note, _ = self.run12()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('font_scale', note)
        self.assertEqual(self.fonts()[-1], 'font 1.0')

    def test_a_skipped_screen_or_an_unlocked_15_6_2_is_a_fail(self):
        for answer in ({'overflows': [], 'visited': SCREENS[:-1], 'locked': True, 'scale_seen': 1.3},
                       {'overflows': [], 'visited': SCREENS, 'locked': False, 'scale_seen': 1.3}):
            with self.subTest(answer):
                self.setUp()
                result, note, _ = self.run12(answer=answer)
                self.assertEqual(result, 'fail', note)

    def test_it_locks_the_nickname_mid_run_for_15_6_2(self):
        result, note, _ = self.run12()
        self.assertEqual(result, 'pass', note)
        self.assertIsNotNone(self.profile()['nickname_changed_at'])


# ── E-WD-19 끊긴 망에서 탈퇴 ─────────────────────────────────────────────────────────────────────────

class Wd19Test(NewBase):
    CASE = 'E-WD-19'

    def answer(self, **over):
        def finish(job):
            tapped = now().isoformat()
            self.press()  # 망을 되돌린 뒤 두 번째 누름
            return {'error': NETWORK, 'sheet_open': True, 'login_seen': False, 'tapped_at': tapped, 'login_ms': 4000,
                    'notice': WITHDRAWN, **over}
        return finish

    def run19(self, answer=None, offline_lands=False):
        def step(name, job):
            if name == 'failed' and offline_lands:
                self.press()
        return self.go(self.CASE, {None: (['final', 'failed'], answer or self.answer())}, step, serial='R5CT')

    def test_pass_the_offline_press_keeps_the_account_and_the_restored_press_withdraws(self):
        result, note, _ = self.run19()
        self.assertEqual(result, 'pass', note)
        self.assertEqual([e for e in self.events if isinstance(e, tuple) and e[0] == 'airplane'], [('airplane', True), ('airplane', False)])
        self.assertIn('ensure_online', self.events)
        self.assertEqual(self.profile()['status'], 'withdrawn')

    def test_a_withdrawal_that_lands_while_offline_is_a_fail(self):
        result, note, _ = self.run19(offline_lands=True)
        self.assertEqual(result, 'fail', note)
        self.assertIn('active', note)

    def test_no_network_line_in_the_sheet_or_a_closed_sheet_is_a_fail(self):
        for over in ({'error': None}, {'sheet_open': False}, {'login_seen': True}):
            with self.subTest(over):
                self.setUp()
                result, note, _ = self.run19(self.answer(**over))
                self.assertEqual(result, 'fail', note)

    def test_the_network_comes_back_when_the_app_blocks(self):
        result, note, _ = self.run19({'result': 'blocked', 'note': '시트가 닫힘'})
        self.assertEqual(result, 'blocked', note)
        self.assertIn('ensure_online', self.events)


# ── E-WD-20 느린 망에서 두 번 누르기 ─────────────────────────────────────────────────────────────────

class Wd20Test(NewBase):
    CASE = 'E-WD-20'

    def run20(self, twice=False, serial=EMU, **over):
        def finish(job):
            tapped = now().isoformat()
            self.press()
            if twice:
                self.press()
            return {'second_blocked': not twice, 'tapped_at': tapped, 'login_ms': 12000, 'notice': WITHDRAWN, **over}
        return self.go(self.CASE, {None: (['final'], finish)}, serial=serial)

    def test_pass_the_second_press_hits_a_disabled_button_and_one_withdrawal_lands(self):
        result, note, _ = self.run20()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.emu_lines(), ['emu network delay 5000', 'emu network speed full', 'emu network delay none'])
        self.assertEqual(len(self.fake.rows('signup_blocks')), 1)

    def test_a_second_press_that_was_not_blocked_is_a_fail(self):
        result, note, _ = self.run20(twice=True)
        self.assertEqual(result, 'fail', note)
        self.assertIn('두 번째', note)

    def test_it_runs_only_on_the_emulator_before_any_account(self):
        result, note, _ = self.run20(serial='R5CT')
        self.assertEqual(result, 'blocked', note)
        self.assertFalse(self.fake.users)

    def test_the_delay_comes_back_when_the_app_blocks(self):
        result, note, _ = self.run20(result='blocked', note='앱 막힘')
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.emu_lines()[-1], 'emu network delay none')


if __name__ == '__main__':
    unittest.main()
