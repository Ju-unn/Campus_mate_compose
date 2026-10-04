"""두 기기 동시 실행기(twodev)의 시험 — 폰 · 에뮬 · 운영 없이 진짜 Hub 둘 + 가짜 앱 스레드 둘(HTTP 로 /hear · /say) + 가짜 adb 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_twodev`."""

import contextlib
import http.client
import io
import json
import threading
import time
import unittest
from types import SimpleNamespace
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, twodev, tools
from e2e.tools import Hub, PACKAGE

PASS = {'result': 'pass', 'note': ''}
HUBS = {}


def setUpModule():
    HUBS.update(A=Hub(0), B=Hub(0))  # Hub 를 닫는 데 0.5초 가까이 걸려 시험마다 새로 열지 않는다


def tearDownModule():
    for hub in HUBS.values():
        hub.close()


def drain(hub):
    for q in (hub._jobs, hub._said):
        while not q.empty():
            q.get_nowait()


class App(threading.Thread):
    """실제 앱 흉내 — 일감을 듣고, [steps] 마다 `step` 을 말하고 멈춰 go 를 듣고, 끝에 [result] 를 말한다([result] 가 None 이면 말이 없다)."""

    def __init__(self, hub, steps=(), result=PASS, pause=0, log=None, name=''):
        super().__init__(daemon=True)
        self.hub, self.steps, self.result, self.pause, self.log, self.name = hub, steps, result, pause, log, name
        self.job, self.heard = None, []
        self.halt = threading.Event()

    def _call(self, method, path, body=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.hub.port, timeout=2)
        try:
            conn.request(method, path, body=json.dumps(body) if body is not None else None)
            res = conn.getresponse()
            return json.loads(res.read() or 'null') if res.status == 200 else None
        finally:
            conn.close()

    def hear(self):
        while not self.halt.is_set():
            got = self._call('GET', '/hear?wait=0.05')
            if got is not None:
                return got
        return None

    def run(self):
        try:
            self.job = self.hear()
            for step in self.steps:
                time.sleep(self.pause)
                self._call('POST', '/say', {'step': step})
                self.heard.append(self.hear())
                if self.log is not None:
                    self.log.append(f'{self.name}-resume-{step}')
            if self.result is not None and not self.halt.is_set():
                self._call('POST', '/say', self.result)
        except OSError:
            pass


class FakeAdb:
    """adb 대신 — 부른 것을 (시리얼, 인자)로 남긴다. [running] 의 기기는 앱 프로세스가 떠 있고 kill 로 꺼진다([stubborn] 은 안 꺼진다)."""

    def __init__(self, running=(), stubborn=()):
        self.calls, self.running, self.stubborn = [], set(running), set(stubborn)

    def __call__(self, serial, *args, check=True):
        self.calls.append((serial, args))
        if args == ('shell', 'pidof', PACKAGE):
            return '4242\n' if serial in self.running else ''
        if args[:3] == ('shell', 'run-as', PACKAGE) and serial not in self.stubborn:
            self.running.discard(serial)
        return ''

    def of(self, serial):
        return [args for s, args in self.calls if s == serial]


class FakeRun:
    def __init__(self):
        self.shots = []
        self.cfg, self.key, self.recorded = {}, None, []

    def shot(self, serial, case):
        self.shots.append((serial, case))

    def record(self, case, result, note=''):
        self.recorded.append((case, result, note))
        return {'case': case, 'result': result, 'note': note}


class Base(unittest.TestCase):
    def setUp(self):
        for hub in HUBS.values():
            drain(hub)
        self.adb = FakeAdb()
        for patcher in (mock.patch.object(tools, 'adb', self.adb), mock.patch.object(twodev, 'KILL_PAUSE', 0),
                        mock.patch.object(twodev, 'SLICE', 0.05), mock.patch.object(twodev, 'GRACE', 0.3)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.run_ = FakeRun()
        self.log = []
        self.apps = []

    def app(self, name, **kw):
        app = App(HUBS[name], log=self.log, name=name, **kw)
        self.apps.append(app)
        app.start()
        self.addCleanup(self._stop, app)
        return app

    @staticmethod
    def _stop(app):
        app.halt.set()
        app.join(2)

    def sides(self, a_job=None, b_job=None):
        return twodev.Side(HUBS['A'], 'SER-A', a_job or {}), twodev.Side(HUBS['B'], 'SER-B', b_job or {})

    def two(self, plan=None, a_job=None, b_job=None, case='E-X-01', **limits):
        a, b = self.sides(a_job, b_job)
        return twodev.two(self.run_, case, a, b, plan or {}, **limits)


class SyncTest(unittest.TestCase):
    def test_wait_returns_true_once_set_and_false_on_timeout(self):
        sync = twodev.Sync()
        self.assertFalse(sync.wait('x', 0.05))
        sync.set('x')
        self.assertTrue(sync.wait('x', 0.05))

    def test_abort_releases_a_waiter_at_once_with_aborted(self):
        sync, seen = twodev.Sync(), []

        def waiter():
            try:
                sync.wait('never', 10)
            except twodev.Aborted as e:
                seen.append(e)

        t = threading.Thread(target=waiter, daemon=True)
        t.start()
        time.sleep(0.05)
        started = time.monotonic()
        sync.abort()
        t.join(2)
        self.assertEqual(len(seen), 1)
        self.assertLess(time.monotonic() - started, 1)

    def test_a_name_set_before_the_abort_is_still_heard(self):
        sync = twodev.Sync()
        sync.set('done')
        sync.abort()
        self.assertTrue(sync.wait('done', 1))
        with self.assertRaises(twodev.Aborted):
            sync.wait('other', 1)

    def test_now_is_the_monotonic_clock(self):
        before = time.monotonic()
        self.assertGreaterEqual(twodev.Sync().now(), before)


class LimitsTest(unittest.TestCase):
    def test_defaults_are_120_for_a_240_for_b_and_a_deadline_with_slack(self):
        side, deadline = twodev.limits(None, None)
        self.assertEqual(side, {'A': 120, 'B': 240})
        self.assertEqual(deadline, 120 + 240 + twodev.MARGIN)

    def test_one_number_or_a_dict_overrides_and_so_does_the_deadline(self):
        self.assertEqual(twodev.limits(0.5, 3), ({'A': 0.5, 'B': 0.5}, 3))
        self.assertEqual(twodev.limits({'B': 10}, None)[0], {'A': 120, 'B': 10})


class MergeTest(unittest.TestCase):
    def test_any_fail_is_fail_even_with_a_blocked_other(self):
        result, memo = twodev.merge({'result': 'fail', 'note': '버튼 없음'}, {'result': 'blocked', 'note': '막힘'})
        self.assertEqual(result, 'fail')
        self.assertIn('A:', memo)
        self.assertIn('버튼 없음', memo)
        self.assertIn('B:', memo)
        self.assertIn('막힘', memo)

    def test_blocked_with_pass_is_blocked(self):
        self.assertEqual(twodev.merge(PASS, {'result': 'blocked', 'note': 'x'})[0], 'blocked')
        self.assertEqual(twodev.merge({'result': 'blocked', 'note': 'x'}, PASS)[0], 'blocked')

    def test_pass_and_pass_is_pass(self):
        self.assertEqual(twodev.merge(PASS, PASS)[0], 'pass')

    def test_a_missing_word_is_blocked_and_names_the_side(self):
        result, memo = twodev.merge(PASS, None)
        self.assertEqual(result, 'blocked')
        self.assertIn('B 쪽이 상한 안에 말하지 않음', memo)

    def test_memo_is_one_line(self):
        self.assertNotIn('\n', twodev.merge(PASS, PASS)[1])


class RunTest(Base):
    def test_a_waits_at_its_step_until_b_has_acted(self):
        def a_step(said, sync):
            self.assertTrue(sync.wait('b-acted', 5))

        def b_step(said, sync):
            self.log.append('B-act')
            sync.set('b-acted')

        self.app('A', steps=['x'])
        self.app('B', steps=['y'], pause=0.3)
        result, memo = self.two({('A', 'x'): a_step, ('B', 'y'): b_step}, side_timeout=5)
        self.assertEqual(result, 'pass', memo)
        self.assertLess(self.log.index('B-act'), self.log.index('A-resume-x'))

    def test_several_stops_per_device_are_all_handled(self):
        called = []
        plan = {(side, step): (lambda said, sync, k=(side, step): called.append(k))
                for side, step in [('A', 's1'), ('A', 's2'), ('B', 't1')]}
        a, b = self.app('A', steps=['s1', 's2']), self.app('B', steps=['t1'])
        result, memo = self.two(plan, side_timeout=5)
        self.assertEqual(result, 'pass', memo)
        self.assertEqual(sorted(called), [('A', 's1'), ('A', 's2'), ('B', 't1')])
        self.assertEqual(len(a.heard), 2)
        self.assertEqual(len(b.heard), 1)

    def test_a_handler_dict_rides_on_go_and_a_missing_handler_is_a_plain_go(self):
        a, b = self.app('A', steps=['x']), self.app('B', steps=['y'])
        result, memo = self.two({('A', 'x'): lambda said, sync: {'token_hash': 'abc'}}, side_timeout=5)
        self.assertEqual(result, 'pass', memo)
        self.assertEqual(a.heard, [{'token_hash': 'abc', 'go': True}])
        self.assertEqual(b.heard, [{'go': True}])

    def test_handler_gets_the_app_word_with_the_pc_receive_time(self):
        seen = []
        self.app('A', steps=['x'])
        self.app('B')
        before = time.monotonic()
        self.two({('A', 'x'): lambda said, sync: seen.append(said)}, side_timeout=5)
        self.assertEqual(seen[0]['step'], 'x')
        self.assertGreaterEqual(seen[0]['t'], before)
        self.assertLessEqual(seen[0]['t'], time.monotonic())

    def test_mailboxes_stay_apart_and_jobs_carry_the_side_key(self):
        a, b = self.app('A'), self.app('B')
        self.two(a_job={'token_hash': 'tA'}, b_job={'token_hash': 'tB'}, case='E-SAFE-09', side_timeout=5)
        self.assertEqual(a.job, {'case': 'E-SAFE-09/A', 'token_hash': 'tA'})
        self.assertEqual(b.job, {'case': 'E-SAFE-09/B', 'token_hash': 'tB'})

    def test_app_results_are_merged_and_a_fail_takes_a_screenshot_of_that_device(self):
        self.app('A', result={'case': 'E-X-01/A', 'result': 'fail', 'note': '목록이 비었다'})
        self.app('B')
        result, memo = self.two(side_timeout=5)
        self.assertEqual(result, 'fail')
        self.assertIn('목록이 비었다', memo)
        self.assertEqual(self.run_.shots, [('SER-A', 'E-X-01-A')])

    def test_when_b_never_speaks_a_is_released_and_the_whole_is_blocked_without_hanging(self):
        self.app('A', steps=['x'])
        self.app('B', result=None)  # 일감만 듣고 말이 없다

        def a_step(said, sync):
            sync.wait('b-acted', 30)  # B 가 영영 안 하면 abort 가 풀어 준다

        started = time.monotonic()
        result, memo = self.two({('A', 'x'): a_step}, side_timeout=0.5)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'blocked', memo)
        self.assertIn('B 쪽이 상한 안에 말하지 않음', memo)
        self.assertIn('Aborted', memo)

    def test_a_handler_exception_is_blocked_with_its_name_and_the_other_side_is_freed(self):
        def boom(said, sync):
            raise ValueError('boom')

        self.app('A', steps=['x'])
        self.app('B', steps=['y'])
        started = time.monotonic()
        result, memo = self.two({('A', 'x'): boom, ('B', 'y'): lambda said, sync: sync.wait('never', 30)}, side_timeout=5)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'blocked')
        self.assertIn('ValueError', memo)
        self.assertIn('boom', memo)

    def test_a_failing_side_stops_the_other_from_waiting_out_its_limit(self):
        self.app('A', result={'result': 'fail', 'note': '실패'})
        self.app('B', result=None)
        started = time.monotonic()
        result, memo = self.two(side_timeout=30)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'fail')

    def test_a_side_that_passed_does_not_cut_the_other_that_is_still_working(self):
        self.app('A')
        self.app('B', steps=['y'], pause=0.4)
        result, memo = self.two({('B', 'y'): lambda said, sync: None}, side_timeout=5)
        self.assertEqual(result, 'pass', memo)

    def test_the_overall_deadline_blocks_both_when_nobody_speaks(self):
        self.app('A', result=None)
        self.app('B', result=None)
        started = time.monotonic()
        result, memo = self.two(side_timeout=30, deadline=0.5)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'blocked')
        self.assertIn('전체 상한', memo)

    def test_a_handler_stuck_outside_sync_is_cut_at_the_deadline(self):
        release = threading.Event()
        self.addCleanup(release.set)
        self.app('A', steps=['x'])
        self.app('B', result=None)
        started = time.monotonic()
        result, memo = self.two({('A', 'x'): lambda said, sync: release.wait(10)}, side_timeout=30, deadline=0.5)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'blocked')
        self.assertIn('전체 상한', memo)


class AdbTest(Base):
    def test_each_side_drives_only_its_own_serial(self):
        self.adb.running = {'SER-A', 'SER-B'}
        self.app('A')
        self.app('B')
        result, memo = self.two(side_timeout=5)
        self.assertEqual(result, 'pass', memo)
        for serial in ('SER-A', 'SER-B'):
            self.assertEqual(self.adb.of(serial), [
                ('shell', 'input', 'keyevent', 'KEYCODE_HOME'),
                ('shell', 'pidof', PACKAGE),
                ('shell', 'run-as', PACKAGE, 'kill', '-9', '4242'),
                ('shell', 'pidof', PACKAGE),
                ('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1'),
            ])
        self.assertEqual({s for s, _ in self.adb.calls}, {'SER-A', 'SER-B'})

    def test_an_app_that_will_not_die_blocks_that_side_and_the_other_stops(self):
        self.adb.running, self.adb.stubborn = {'SER-A'}, {'SER-A'}
        a, b = self.app('A'), self.app('B', result=None)
        started = time.monotonic()
        result, memo = self.two(side_timeout=30)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result, 'blocked')
        self.assertIn('꺼지지 않음', memo)
        self.assertNotIn(('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1'), self.adb.of('SER-A'))
        self.assertIsNone(a.job)


class BoundTest(Base):
    def test_bound_two_builds_the_per_side_jobs(self):
        a, b = self.sides()
        a_app, b_app = self.app('A'), self.app('B')
        call = twodev.bound(self.run_, 'E-SAFE-09', a, b)
        result, memo = call({}, a_job={'token_hash': 'tA'}, side_timeout=5)
        self.assertEqual(result, 'pass', memo)
        self.assertEqual(a_app.job, {'case': 'E-SAFE-09/A', 'token_hash': 'tA'})
        self.assertEqual(b_app.job, {'case': 'E-SAFE-09/B'})


class CmdRunTest(unittest.TestCase):
    """cmd_run 이 두 기기 가설일 때만 A · B 를 연다 — 가짜 Hub · adb · env 로."""

    def setUp(self):
        self.hubs, self.reverses, self.closed = [], [], []
        outer = self

        class FakeHub:
            def __init__(self, port):
                self.port = port
                outer.hubs.append(port)

            def close(self):
                outer.closed.append(self.port)

        self.run_ = FakeRun()
        self.fake_two = mock.Mock(return_value=('pass', 'ok'))
        self.fake_api = SimpleNamespace(attempt=mock.Mock(return_value=('pass', '')))
        patches = [
            mock.patch.object(cli, 'Hub', FakeHub),
            mock.patch.object(cli, 'adb', lambda sn, *args, **kw: self.reverses.append((sn, args))),
            mock.patch.object(cli, 'env', lambda: {'E2E_DEVICE_A': 'PHONE-A'}),
            mock.patch.object(cli, '_run', lambda args: self.run_),
            mock.patch.object(cli, 'service_key', lambda: 'k'),
            mock.patch.object(cli, 'ensure_no_real_users', lambda *a: 0),
            mock.patch.dict(twodev.TWO, {'E-TWO-01': self.fake_two}),
            mock.patch.dict(cli.API_CASES, {'E-API-01': self.fake_api}),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def args(self, *cases, device='A'):
        return SimpleNamespace(case=list(cases), device=device, bundle='t', build='b', revision=None)

    def test_a_two_device_case_opens_both_hubs_with_reverses_and_closes_them(self):
        with contextlib.redirect_stdout(io.StringIO()):
            cli.cmd_run(self.args('E-TWO-01'))
        self.assertEqual(sorted(self.hubs), [tools.DEVICES['A'], tools.DEVICES['B']])
        self.assertEqual(sorted(self.closed), sorted(self.hubs))
        self.assertEqual(sorted(self.reverses), [
            ('PHONE-A', ('reverse', f'tcp:{tools.DEVICE_PORT}', f'tcp:{tools.DEVICES["A"]}')),
            (tools.DEFAULT_SERIALS['B'], ('reverse', f'tcp:{tools.DEVICE_PORT}', f'tcp:{tools.DEVICES["B"]}')),
        ])
        run, pair = self.fake_two.call_args.args
        self.assertIs(run, self.run_)
        self.assertEqual(self.run_.recorded[0][:2], ('E-TWO-01', 'pass'))
        self.assertEqual(self.run_.key, 'k')  # 운영 쓰기 전 실사용자 점검(서비스 키)을 두 기기 가설도 거친다

    def test_an_api_case_prepares_no_device_at_all(self):
        with contextlib.redirect_stdout(io.StringIO()):
            cli.cmd_run(self.args('E-API-01'))
        self.assertEqual((self.hubs, self.reverses), ([], []))

    def test_a_phone_case_opens_only_its_own_device(self):
        with mock.patch.dict(area1.PHONE, {'E-PH-01': lambda run, phone: ('pass', '')}), \
                contextlib.redirect_stdout(io.StringIO()):
            cli.cmd_run(self.args('E-PH-01'))
        self.assertEqual(self.hubs, [tools.DEVICES['A']])
        self.assertEqual(len(self.reverses), 1)

    def test_a_phone_case_and_a_two_device_case_share_the_a_hub(self):
        with mock.patch.dict(area1.PHONE, {'E-PH-01': lambda run, phone: ('pass', '')}), \
                contextlib.redirect_stdout(io.StringIO()):
            cli.cmd_run(self.args('E-PH-01', 'E-TWO-01'))
        self.assertEqual(sorted(self.hubs), [tools.DEVICES['A'], tools.DEVICES['B']])  # A 는 한 번만

    def test_a_missing_phone_serial_exits_before_any_hub_opens(self):
        with mock.patch.object(cli, 'env', lambda: {}), self.assertRaises(SystemExit) as stop:
            cli.cmd_run(self.args('E-TWO-01'))
        self.assertIn('E2E_DEVICE_A', str(stop.exception))
        self.assertEqual(self.hubs, [])


if __name__ == '__main__':
    unittest.main()
