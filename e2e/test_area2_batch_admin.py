"""E-BATCH-01~03 판 시험 — gcloud · API · DB 를 전부 가짜로 바꾼다. 저장소 루트에서 `python -m unittest e2e.test_area2_batch_admin`."""

import datetime as dt
import json
import subprocess
import unittest
from types import SimpleNamespace
from unittest import mock

from e2e import area2_batch_admin as mod
from e2e.tools import Blocked, Reply

RUN = SimpleNamespace(cfg={'API_BASE_URL': 'https://api.test', 'SUPABASE_ANON_KEY': 'anon-jwt'}, key='service')


def job(name, path, **over):
    """gcloud describe 가 돌려주는 모양 — E-BATCH-01 이 읽는 칸만."""
    http = {'httpMethod': 'POST', 'uri': f'https://run.test{path}',
            'oidcToken': {'serviceAccountEmail': f'scheduler@proj.iam.gserviceaccount.com',
                          'audience': 'https://run.test'}}
    http.update(over.pop('http', {}))
    base = {'schedule': mod.JOBS[name][0], 'timeZone': 'Asia/Seoul', 'httpTarget': http}
    base.update(over)
    return base


class DescribeTest(unittest.TestCase):
    def test_it_reads_json_from_gcloud(self):
        with mock.patch.object(mod.subprocess, 'run', return_value=SimpleNamespace(stdout='{"schedule":"0 7 * * *"}')) as run:
            self.assertEqual(mod._describe('daily-cards'), {'schedule': '0 7 * * *'})
        # 문자열 하나로 부른다 — shell=True 에 리스트를 주면 POSIX 에서 첫 낱말만 실행된다.
        self.assertEqual(run.call_args[0], ('gcloud scheduler jobs describe campus-mate-daily-cards '
                                            '--location=asia-northeast3 --format=json',))

    def test_no_gcloud_is_blocked_not_failed(self):
        with mock.patch.object(mod.subprocess, 'run', side_effect=OSError('gcloud 없음')):
            with self.assertRaises(Blocked):
                mod._describe('daily-cards')

    def test_non_json_output_is_blocked(self):
        with mock.patch.object(mod.subprocess, 'run', return_value=SimpleNamespace(stdout='ERROR: not logged in')):
            with self.assertRaises(Blocked):
                mod._describe('daily-cards')


class Batch01Test(unittest.TestCase):
    def run_it(self, **overrides):
        def fake(name):
            path = mod.JOBS[name][1]
            return overrides.get(name) or job(name, path)
        with mock.patch.object(mod, '_describe', fake):
            return mod.batch_01(RUN)

    def test_the_real_shape_passes(self):
        self.assertEqual(self.run_it()[0], 'pass')

    def test_a_wrong_schedule_fails(self):
        result, note = self.run_it(**{'cleanup': job('cleanup', '/batch/cleanup', schedule='0 5 * * *')})
        self.assertEqual(result, 'fail')
        self.assertIn('스케줄', note)

    def test_a_utc_zone_fails(self):
        result, note = self.run_it(**{'chat-gate': job('chat-gate', '/batch/chat-gate', timeZone='UTC')})
        self.assertEqual(result, 'fail')
        self.assertIn('timeZone', note)

    def test_the_old_shared_secret_header_fails(self):
        broken = job('daily-cards', '/batch/daily-cards')
        broken['httpTarget']['headers'] = {'X-Batch-Secret': 's'}
        result, note = self.run_it(**{'daily-cards': broken})
        self.assertEqual(result, 'fail')
        self.assertIn('공유 열쇠', note)

    def test_an_audience_with_a_path_fails(self):
        # DEPLOY.md:319 — 경로가 섞이면 구글이 job 의 --uri 전체를 audience 로 삼아 정상 실행이 401 이 된다.
        broken = job('cleanup', '/batch/cleanup')
        broken['httpTarget']['oidcToken']['audience'] = 'https://run.test/batch/cleanup'
        result, note = self.run_it(**{'cleanup': broken})
        self.assertEqual(result, 'fail')
        self.assertIn('audience', note)

    def test_a_missing_oidc_account_fails(self):
        broken = job('chat-gate', '/batch/chat-gate')
        broken['httpTarget']['oidcToken'] = {}
        result, note = self.run_it(**{'chat-gate': broken})
        self.assertEqual(result, 'fail')
        self.assertIn('serviceAccountEmail', note)

    def test_a_wrong_uri_fails(self):
        result, note = self.run_it(**{'daily-cards': job('daily-cards', '/batch/other')})
        self.assertEqual(result, 'fail')
        self.assertIn('uri', note)


class Batch02Test(unittest.TestCase):
    def record(self, status=401, body=None):
        seen = []

        def fake(method, url, headers=None, **options):
            seen.append((url, headers))
            return Reply(status, body if body is not None else {'detail': mod.UNAUTHORIZED})

        with mock.patch.object(mod.tools, 'call', fake):
            return mod.batch_02(RUN), seen

    def test_all_twelve_wrong_identities_are_401(self):
        (result, _), seen = self.record()
        self.assertEqual(result, 'pass')
        self.assertEqual(len(seen), 12)  # 문 셋 × 틀린 신원 넷

    def test_every_path_and_probe_is_covered(self):
        _, seen = self.record()
        self.assertEqual({url.rsplit('/', 1)[-1] for url, _ in seen}, {'daily-cards', 'chat-gate', 'cleanup'})
        self.assertEqual({tuple(sorted(h)) for _, h in seen},
                         {(), ('Authorization',), ('X-Batch-Secret',)})

    def test_the_old_shared_secret_is_sent_but_dead(self):
        _, seen = self.record()
        self.assertTrue(any(h.get('X-Batch-Secret') for _, h in seen))

    def test_the_anon_key_is_sent_as_a_signed_but_wrong_token(self):
        _, seen = self.record()
        self.assertTrue(any(h.get('Authorization') == 'Bearer anon-jwt' for _, h in seen))

    def test_a_200_is_a_fail(self):
        (result, note), _ = self.record(status=200, body={'ok': True})
        self.assertEqual(result, 'fail')
        self.assertIn('200', note)

    def test_a_401_with_the_wrong_message_is_a_fail(self):
        (result, note), _ = self.record(body={'detail': 'forbidden'})
        self.assertEqual(result, 'fail')
        self.assertIn('문구', note)


class Batch03Test(unittest.TestCase):
    def run_it(self, counts):
        """counts = _rows 가 돌려줄 장수 순서대로 — 첫 읽기(두드리기 전) · 둘째(뒤)."""
        left = list(counts)
        with mock.patch.object(mod, '_rows', lambda run, path: [{}] * left.pop(0)), \
             mock.patch.object(mod.tools, 'call', lambda *a, **k: Reply(401, {'detail': mod.UNAUTHORIZED})):
            return mod.batch_03(RUN)

    def test_no_new_cards_is_a_pass(self):
        self.assertEqual(self.run_it([0, 0])[0], 'pass')

    def test_a_new_card_after_the_probes_is_a_fail(self):
        result, note = self.run_it([0, 3])
        self.assertEqual(result, 'fail')
        self.assertIn('3장', note)

    def test_the_since_time_has_no_plus_that_the_url_would_turn_into_a_space(self):
        paths = []
        with mock.patch.object(mod, '_rows', lambda run, path: paths.append(path) or []), \
             mock.patch.object(mod.tools, 'call', lambda *a, **k: Reply(401, {'detail': mod.UNAUTHORIZED})):
            mod.batch_03(RUN)
        self.assertTrue(paths and all('+' not in path for path in paths), paths)

    def test_cards_already_growing_before_the_probes_is_blocked(self):
        with self.assertRaises(Blocked):
            self.run_it([1, 1])


class Batch11Test(unittest.TestCase):
    def test_existing_pass_stamp_is_preserved_after_one_gated_batch(self):
        before = [{'trust_passed_at': '2026-10-06T01:00:00Z', 'chat_closed_at': None}]
        reads = iter((before, before))
        with mock.patch.object(mod.area3, '_pair', return_value=({'id': 'a'}, {'id': 'b'}, 'match')), \
             mock.patch.object(mod.area3_phone5, '_sentinel', return_value=({'id': 'sa'}, {'id': 'sb'}, 'sentinel')), \
             mock.patch.object(mod.area3_phone5.batch_gate, 'peek'), \
             mock.patch.object(mod.area2, '_guard'), \
             mock.patch.object(mod, '_patch'), \
             mock.patch.object(mod, '_rows', side_effect=lambda *a: next(reads)), \
             mock.patch.object(mod.area3_phone5, '_gated_batch') as gated:
            result, note = mod.batch_11(RUN)
        self.assertEqual(result, 'pass')
        self.assertIn('두 번째 POST', note)
        gated.assert_called_once()

    def test_batch11_refuses_if_gate_window_is_closed_before_preparation(self):
        with mock.patch.object(mod.area3_phone5.batch_gate, 'peek', side_effect=Blocked('닫힘')):
            with self.assertRaises(Blocked):
                mod.batch_11(RUN)


NOW = dt.datetime(2026, 10, 7, 12, 30, tzinfo=mod.SEOUL)


def runs(skip=(), status=None, extra=()):
    """지난 하루 예약 실행 줄 전부(chat-gate 24 · cleanup 1 · daily-cards 1) — [skip] 은 빼고, [status] 는 {(경로, 시각 'MM-DD HH'): 상태} 로 바꾼다."""
    out = []
    for job, (hour, day) in [('chat-gate', (h, 6 if h >= 13 else 7)) for h in list(range(13, 24)) + list(range(0, 13))] \
            + [('cleanup', (4, 7)), ('daily-cards', (7, 7))]:
        at = dt.datetime(2026, 10, day, hour, 0, 2, tzinfo=mod.SEOUL)
        path = mod.JOBS[job][1]
        key = (path, f'{at:%m-%d %H}')
        if key not in skip:
            out.append((at, path, (status or {}).get(key, 200)))
    return out + list(extra)


class Batch26JudgeTest(unittest.TestCase):
    def test_every_slot_with_a_200_passes(self):
        problems, summary = mod.judge_scheduled_runs(runs(), NOW)
        self.assertEqual(problems, [])
        self.assertIn('chat-gate 24/24', summary)
        self.assertIn('cleanup 1/1', summary)
        self.assertIn('daily-cards 1/1', summary)

    def test_a_missing_hour_of_chat_gate_is_a_problem_that_names_it(self):
        problems, _ = mod.judge_scheduled_runs(runs(skip={('/batch/chat-gate', '10-07 03')}), NOW)
        self.assertEqual(len(problems), 1)
        self.assertIn('chat-gate', problems[0])
        self.assertIn('10-07 03:00', problems[0])

    def test_a_500_is_a_problem_even_when_the_slot_has_another_200(self):
        retry = (dt.datetime(2026, 10, 7, 7, 0, 30, tzinfo=mod.SEOUL), '/batch/daily-cards', 500)
        problems, _ = mod.judge_scheduled_runs(runs(extra=[retry]), NOW)
        self.assertEqual(len(problems), 1)
        self.assertIn('daily-cards', problems[0])
        self.assertIn('500', problems[0])

    def test_a_slot_whose_only_run_is_a_500_is_both_a_bad_run_and_a_missing_slot(self):
        problems, _ = mod.judge_scheduled_runs(runs(status={('/batch/cleanup', '10-07 04'): 500}), NOW)
        self.assertEqual(len(problems), 2)
        self.assertTrue(all('cleanup' in x for x in problems))

    def test_the_hour_that_just_passed_is_not_expected_yet(self):
        just_after = dt.datetime(2026, 10, 7, 12, 5, tzinfo=mod.SEOUL)  # 12시 예약은 5분 전 — 로그가 아직 없을 수 있다
        rows = [r for r in runs() if not (r[1] == '/batch/chat-gate' and r[0].hour == 12 and r[0].day == 7)]
        self.assertEqual(mod.judge_scheduled_runs(rows, just_after)[0], [])

    def test_a_run_before_the_window_does_not_count_and_is_not_blamed(self):
        old = (dt.datetime(2026, 10, 5, 4, 0, 2, tzinfo=mod.SEOUL), '/batch/cleanup', 500)
        self.assertEqual(mod.judge_scheduled_runs(runs(extra=[old]), NOW)[0], [])

    def test_a_manual_extra_run_with_a_200_is_fine(self):
        extra = (dt.datetime(2026, 10, 7, 9, 41, tzinfo=mod.SEOUL), '/batch/chat-gate', 200)
        self.assertEqual(mod.judge_scheduled_runs(runs(extra=[extra]), NOW)[0], [])

    def test_a_late_log_inside_the_ten_minute_slot_still_counts(self):
        late = [(dt.datetime(2026, 10, 7, 4, 9, tzinfo=mod.SEOUL), '/batch/cleanup', 200)]
        rows = [r for r in runs() if r[1] != '/batch/cleanup'] + late
        self.assertEqual(mod.judge_scheduled_runs(rows, NOW)[0], [])

    def test_a_run_at_a_wrong_time_does_not_fill_the_slot(self):
        wrong = [(dt.datetime(2026, 10, 7, 5, 0, 2, tzinfo=mod.SEOUL), '/batch/cleanup', 200)]
        rows = [r for r in runs() if r[1] != '/batch/cleanup'] + wrong
        problems, _ = mod.judge_scheduled_runs(rows, NOW)
        self.assertEqual(len(problems), 1)
        self.assertIn('cleanup', problems[0])


def entry(at, path, status):
    return {'timestamp': at.astimezone(dt.timezone.utc).isoformat().replace('+00:00', 'Z'),
            'httpRequest': {'requestUrl': f'https://run.test{path}?x=1', 'status': status, 'userAgent': mod.SCHEDULER_AGENT}}


def gcloud_says(project='my-proj', logs=None, fail=None):
    """subprocess.run 가짜 — config get-value project 와 logging read 를 구분해 답한다. [fail] = 어느 호출이 실패하는지('config' · 'logging')."""
    calls = []

    def run(command, **options):
        calls.append(command)
        which = 'logging' if ' logging ' in command else 'config'
        if fail == which:
            raise subprocess.CalledProcessError(1, command, stderr=f'ERROR: (gcloud.logging.read) PERMISSION_DENIED on {project}')
        return SimpleNamespace(stdout=json.dumps(logs or []) if which == 'logging' else f'{project}\n')
    return run, calls


class Batch26ReadTest(unittest.TestCase):
    def go(self, **says):
        run, calls = gcloud_says(**says)
        with mock.patch.object(mod.subprocess, 'run', run), mock.patch.object(mod, '_now', return_value=NOW):
            return mod.batch_26(RUN), calls

    def test_the_real_shape_of_log_entries_passes(self):
        logs = [entry(at, path, status) for at, path, status in runs()]
        (result, note), _ = self.go(logs=logs)
        self.assertEqual(result, 'pass', note)

    def test_a_bad_status_in_the_logs_is_a_fail_naming_the_job(self):
        logs = [entry(at, path, status) for at, path, status in runs(status={('/batch/daily-cards', '10-07 07'): 503})]
        (result, note), _ = self.go(logs=logs)
        self.assertEqual(result, 'fail')
        self.assertIn('daily-cards', note)

    def test_it_only_reads_the_project_comes_from_gcloud_config_and_only_scheduler_lines_are_asked_for(self):
        _, calls = self.go(logs=[entry(at, path, status) for at, path, status in runs()])
        self.assertEqual(len(calls), 2)
        self.assertIn('config get-value project', calls[0])
        self.assertIn('--project=my-proj', calls[1])
        self.assertIn('logging read', calls[1])
        self.assertIn(mod.SCHEDULER_AGENT, calls[1])
        self.assertTrue(all(c.startswith('gcloud config get-value') or c.startswith('gcloud logging read') for c in calls))  # 읽기 말고 다른 gcloud 는 안 부른다

    def test_without_permission_it_is_blocked_with_the_reason_and_without_the_project_id(self):
        with self.assertRaises(Blocked) as got:
            self.go(fail='logging')
        note = str(got.exception)
        self.assertIn('PERMISSION_DENIED', note)
        self.assertIn('logging.logEntries.list', note)
        self.assertNotIn('my-proj', note)

    def test_an_unset_project_is_blocked(self):
        with self.assertRaises(Blocked) as got:
            self.go(project='(unset)')
        self.assertIn('프로젝트', str(got.exception))

    def test_no_gcloud_is_blocked(self):
        with mock.patch.object(mod.subprocess, 'run', side_effect=OSError('gcloud 없음')):
            with self.assertRaises(Blocked):
                mod.batch_26(RUN)

    def test_a_log_that_is_not_json_is_blocked(self):
        with mock.patch.object(mod.subprocess, 'run', return_value=SimpleNamespace(stdout='not json')):
            with self.assertRaises(Blocked):
                mod._scheduler_requests(NOW)

    def test_the_case_is_registered_in_the_batch_admin_bundle(self):
        self.assertIn('E-BATCH-26', mod.CASES)
        self.assertIn('E-BATCH-26', mod.BUNDLES['area2-batch-admin'])


if __name__ == '__main__':
    unittest.main()
