"""로컬 시험 안전장치 — SUPABASE_URL 이 운영(`*.supabase.co`)이 아니면 gcloud(운영 프로젝트)를 부르는 길이 전부 막힌다.

로컬 Docker 로 앱 시험을 돌릴 때 `tools.batch`(운영 Cloud Scheduler)나 서비스 키(운영 Secret Manager)가 운영으로 새지 않게 한다.
"""

import contextlib
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from e2e import area2_batch_admin, area4_push_fcm, area5_edge, tools
from e2e.tools import Blocked

PROD = 'https://abcdefgh.supabase.co'
LOCAL = 'http://127.0.0.1:54321'


@contextlib.contextmanager
def using(url, service_key=None):
    """E2E_ENV 가 [url] 이 적힌 임시 파일을 가리키는 동안. E2E_SERVICE_KEY 는 [service_key] 일 때만 있다."""
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'e2e.local.env'
        path.write_text(f'# 시험용\nSUPABASE_URL={url}\nAPI_BASE_URL=http://127.0.0.1:8000\n', encoding='utf-8')
        pairs = {'E2E_ENV': str(path), **({'E2E_SERVICE_KEY': service_key} if service_key else {})}
        with mock.patch.dict(os.environ, pairs):
            if not service_key:
                os.environ.pop('E2E_SERVICE_KEY', None)
            yield path


class EnvFileTest(unittest.TestCase):
    def test_without_E2E_ENV_it_is_the_frontend_e2e_env_as_always(self):
        with mock.patch.dict(os.environ):
            os.environ.pop('E2E_ENV', None)
            self.assertEqual(tools.env_file(), tools.ROOT / 'frontend' / 'e2e.env')

    def test_E2E_ENV_points_the_harness_at_another_file(self):
        with using(LOCAL) as path:
            self.assertEqual(tools.env_file(), path)
            self.assertEqual(tools.env()['SUPABASE_URL'], LOCAL)


class IsLocalTest(unittest.TestCase):
    def test_a_supabase_cloud_url_is_not_local(self):
        self.assertFalse(tools.is_local({'SUPABASE_URL': PROD}))

    def test_anything_else_is_local(self):
        for url in (LOCAL, 'http://localhost:54321', 'https://abcdefgh.supabase.co.evil.com', 'https://evilsupabase.co',
                    'https://abcdefgh.supabase.co@127.0.0.1:54321', ''):
            with self.subTest(url):
                self.assertTrue(tools.is_local({'SUPABASE_URL': url}))

    def test_it_reads_the_env_file_when_it_is_not_given_one(self):
        with using(LOCAL):
            self.assertTrue(tools.is_local())
        with using(PROD):
            self.assertFalse(tools.is_local())

    def test_no_env_file_at_all_keeps_the_old_behaviour(self):
        with mock.patch.dict(os.environ), mock.patch.object(tools, 'ENV_FILE', Path(tempfile.gettempdir()) / '없는파일.env'):
            os.environ.pop('E2E_ENV', None)
            self.assertFalse(tools.is_local())

    def test_an_E2E_ENV_that_points_nowhere_is_not_taken_for_production(self):
        with mock.patch.dict(os.environ, {'E2E_ENV': str(Path(tempfile.gettempdir()) / '없는파일.env')}):
            self.assertTrue(tools.is_local())


class ServiceKeyTest(unittest.TestCase):
    def test_E2E_SERVICE_KEY_is_used_without_calling_gcloud(self):
        with using(LOCAL, service_key='local-key'), mock.patch.object(tools.subprocess, 'run') as run:
            self.assertEqual(tools.service_key(), 'local-key')
        run.assert_not_called()

    def test_local_without_a_key_is_blocked_before_gcloud_is_called(self):
        with using(LOCAL), mock.patch.object(tools.subprocess, 'run') as run:
            with self.assertRaises(Blocked) as raised:
                tools.service_key()
        run.assert_not_called()
        self.assertIn('E2E_SERVICE_KEY', str(raised.exception))

    def test_production_without_the_variable_still_asks_secret_manager(self):
        with using(PROD), mock.patch.object(tools.subprocess, 'run', return_value=SimpleNamespace(stdout=' secret \n')) as run:
            self.assertEqual(tools.service_key(), 'secret')
        self.assertIn('supabase-service-role-key', run.call_args.args[0][-1])


class CloudCallsTest(unittest.TestCase):
    """운영 프로젝트로 가는 호출(스케줄러 · 로그 · FCM · 서비스 키)은 로컬이면 gcloud 를 부르기 전에 멈춘다."""

    NOW = datetime(2026, 11, 2, 12, 0, tzinfo=timezone.utc)
    CALLS = {
        'tools.batch': lambda: tools.batch('cleanup'),
        'batch_admin._describe': lambda: area2_batch_admin._describe('daily-cards'),
        'batch_admin._gcloud': lambda: area2_batch_admin._gcloud(['config', 'get-value', 'project'], '프로젝트'),
        'fcm.credentials': lambda: area4_push_fcm.credentials(),
        'edge._requests': lambda: area5_edge._requests(CloudCallsTest.NOW, CloudCallsTest.NOW),
    }

    def test_each_one_is_blocked_locally_and_never_reaches_gcloud(self):
        for name, call in self.CALLS.items():
            with self.subTest(name), using(LOCAL), mock.patch('subprocess.run') as run, \
                    mock.patch.object(area4_push_fcm.shutil, 'which', return_value='gcloud'):
                with self.assertRaises(Blocked):
                    call()
                run.assert_not_called()

    def test_production_batch_is_unchanged(self):
        with using(PROD), mock.patch.object(tools.subprocess, 'run') as run:
            tools.batch('cleanup')
        self.assertEqual(run.call_args.args[0], ['gcloud', 'scheduler', 'jobs', 'run', 'campus-mate-cleanup', '--location=asia-northeast3'])

    def test_production_describe_is_unchanged(self):
        with using(PROD), mock.patch.object(area2_batch_admin.subprocess, 'run', return_value=SimpleNamespace(stdout='{"a": 1}')) as run:
            self.assertEqual(area2_batch_admin._describe('daily-cards'), {'a': 1})
        run.assert_called_once()


class CleanupStaysLocalTest(unittest.TestCase):
    """뒷정리(cleanup)는 cfg 의 SUPABASE_URL 로만 요청하고 gcloud 를 부르지 않는다 — 로컬에서 돌려도 운영으로 가지 않는다."""

    def test_every_request_goes_to_the_local_url_and_gcloud_is_never_called(self):
        urls = []

        def fake_call(method, url, *args, **kwargs):
            urls.append(url)
            ghost = {'id': 'f' * 8 + '-0000-0000-0000-' + '0' * 12, 'email': 'me+e2e1001@gmail.com'}
            return (200, {'users': [ghost]} if '/auth/v1/admin/users?' in url else [])

        cfg = {'SUPABASE_URL': LOCAL, 'E2E_MAIL_BASE': 'me@gmail.com'}
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / tools.KEEP_FILE).write_text('', encoding='utf-8')
            with mock.patch.object(tools, 'call', fake_call), mock.patch('subprocess.run') as run, \
                    contextlib.redirect_stdout(open(os.devnull, 'w')):
                tools.cleanup(cfg, 'local-key', root)
        self.assertTrue(urls)
        self.assertTrue(all(url.startswith(LOCAL) for url in urls), urls)
        run.assert_not_called()


class ResultsRootTest(unittest.TestCase):
    BASE = Path('E2E_결과')

    def test_production_results_stay_where_they_were(self):
        with using(PROD):
            self.assertEqual(tools.results_root(self.BASE), self.BASE)

    def test_local_results_get_their_own_dated_folder_so_they_never_mix_with_production_ones(self):
        with using(LOCAL):
            self.assertEqual(tools.results_root(self.BASE, date(2026, 11, 2)), self.BASE / '로컬_2026-11-02')


class MainWiringTest(unittest.TestCase):
    """진행 프로그램(`python -m e2e`)이 시작할 때 RESULTS 를 이 규칙으로 고른다 — 새 프로세스로 import 해서 본다."""

    def results_of(self, url):
        with using(url) as path:
            done = subprocess.run([sys.executable, '-c', 'from e2e.__main__ import RESULTS; print(RESULTS.name)'], cwd=tools.ROOT,
                                  env={**os.environ, 'E2E_ENV': str(path), 'PYTHONIOENCODING': 'utf-8'}, **tools.TEXT, check=True)
        return done.stdout.strip()

    def test_local_run_writes_under_its_own_dated_folder(self):
        self.assertEqual(self.results_of(LOCAL), f'로컬_{date.today()}')

    def test_production_run_keeps_the_old_folder(self):
        self.assertEqual(self.results_of(PROD), 'E2E_결과')


if __name__ == '__main__':
    unittest.main()
