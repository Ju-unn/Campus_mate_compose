"""E-BATCH-01~03 판 시험 — gcloud · API · DB 를 전부 가짜로 바꾼다. 저장소 루트에서 `python -m unittest e2e.test_area2_batch_admin`."""

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


if __name__ == '__main__':
    unittest.main()
