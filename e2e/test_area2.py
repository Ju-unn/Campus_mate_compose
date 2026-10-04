"""영역 2 API 가설 시험 — 운영 없이 가짜 HTTP 로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area2`.

가설마다 시험을 두지는 않는다 — 가족마다 대표 가설(통과 · 어긋남 메모)과, 모든 가설이 서버가 다 500 이어도 예외 없이
fail · blocked 로 끝나는지(전수)를 본다. 실제 운영 값은 대장이 돌려 본다."""

import http.client
import json
import ssl
import unittest
from datetime import datetime
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from e2e import area2, batch_gate, test_area1 as t1, tools
from e2e.area1 import SEOUL
from e2e.tools import Blocked, Reply, Run

# 시나리오 영역 2 "묶음 범위" 표의 API만 50 — 가설을 빼먹거나 늘리면 여기서 걸린다.
API_ONLY = (
    'E-HOME-27 E-CARD-30 E-CARD-31 E-CARD-34 E-CARD-37 E-CARD-38 E-CARD-39 E-CARD-55 E-CARD-60 E-CARD-61 E-CARD-62 '
    'E-CARD-63 E-CARD-64 E-CARD-65 E-CARD-66 E-CARD-67 E-CARD-69 E-CARD-70 E-CARD-71 E-CARD-73 E-CARD-82 E-CARD-83 '
    'E-CARD-88 E-CARD-89 E-POLL-03 E-POLL-10 E-POLL-17 E-POLL-24 E-HEART-07 E-HEART-08 E-HEART-10 E-HEART-11 '
    'E-HEART-15 E-HEART-19 E-HEART-20 E-HEART-24 E-HEART-25 E-HEART-40 E-HEART-41 E-HEART-46 E-HEART-48 E-REF-09 '
    'E-REF-10 E-REF-11 E-REF-12 E-REF-13 E-REF-14 E-REF-15 E-REF-16 E-REF-19').split()


class Fake(t1.FakeServer):
    """t1.FakeServer + 가설이 보는 응답을 정하는 [rules] — (메서드, 경로 조각) → 함수(body, url) → Reply. 먼저 맞는 규칙이 이긴다."""

    def __init__(self, rules=None, routes=None):
        super().__init__(routes)
        self.rules = rules or []
        self.options = []  # (메서드, 경로, call 에 더 넘긴 키워드 — retry=False 등)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.options.append((method, urlsplit(url).path, options))
        for want_method, piece, answer in self.rules:
            if method == want_method and piece in url:
                self.calls.append((method, urlsplit(url).path, body))
                return answer(body, url)
        return super().__call__(method, url, headers, body, raw)

    def bodies(self, method, piece):
        return [b for m, p, b in self.calls if m == method and piece in p]


class Base(t1.Base):
    @staticmethod
    def seeded(fake):
        """가설이 프로필에 넣은 값(gender 가 든 PATCH) — 계정 공장이 student_verification 을 쓰는 PATCH 는 뺀다."""
        return [b for b in fake.bodies('PATCH', '/rest/v1/profiles') if 'gender' in b]

    """계정은 진짜 계정 공장(`Run.account('home')`, 나탭2 #243)이 가짜 서버 위에서 만든다 — 만든 순서대로 id-1, id-2 …."""

    def setUp(self):
        super().setUp()
        self.run = Run(self.root / 'area2-api', 'b', cfg=t1.CFG, key='svc')
        # 배치 가설이 실제 시각(월요일 · 04:00 근처)에 막히지 않게 — 관문 자체는 test_batch_gate 가 본다
        patcher = mock.patch.object(batch_gate, 'now_seoul', return_value=datetime(2026, 10, 6, 12, 0, tzinfo=SEOUL))
        patcher.start()
        self.addCleanup(patcher.stop)


class RegistryTest(unittest.TestCase):
    def test_cases_plus_skipped_are_exactly_the_50_api_only_hypotheses(self):
        self.assertEqual(sorted([*area2.CASES, *area2.SKIPPED]), sorted(API_ONLY))
        self.assertEqual(len(API_ONLY), 50)

    def test_skipped_carry_a_reason(self):
        self.assertEqual(sorted(area2.SKIPPED), ['E-CARD-73', 'E-HEART-46'])
        self.assertTrue(all(len(reason) > 10 for reason in area2.SKIPPED.values()))

    def test_bundle_lists_every_case_but_not_the_skipped(self):
        self.assertEqual(area2.BUNDLES['area2-api'], list(area2.CASES))


class SafetyNetTest(Base):
    def test_the_real_factory_knows_the_home_stage(self):
        self.assertIn('home', tools.STAGES)

    def test_every_case_ends_as_fail_or_blocked_when_the_server_is_down(self):
        down = Fake([(m, '', lambda b, u: Reply(500, {'detail': '서버'})) for m in ('GET', 'POST', 'PATCH', 'DELETE')])
        patcher = mock.patch.object(tools, 'call', down)
        patcher.start()
        self.addCleanup(patcher.stop)
        mock.patch.object(tools, 'batch', lambda name: None).start()
        self.addCleanup(mock.patch.stopall)
        for case in area2.CASES:
            result, memo = area2.attempt(self.run, case)
            self.assertIn(result, ('fail', 'blocked'), case)
            self.assertIsInstance(memo, str, case)

    def test_writes_to_an_account_this_run_did_not_make_are_refused(self):
        self.serve()
        with self.assertRaises(Blocked):
            area2._guard(self.run, 'someone-elses-id')
        made = self.run.account('home')
        area2._guard(self.run, made['id'])


class Home27Test(Base):
    def test_all_four_values_rejected_and_value_untouched(self):
        fake = Fake([
            ('GET', 'universities?id=eq', lambda b, u: Reply(200, [{'card_opens_at': None}])),
            ('PATCH', 'universities', lambda b, u: Reply(400, {'code': '23514', 'message': 'check'})),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(area2.attempt(self.run, 'E-HOME-27')[0], 'pass')
        sent = [b['card_opens_at'] for b in fake.bodies('PATCH', '/rest/v1/universities')]
        self.assertEqual(len(sent), 4)
        self.assertIn('infinity', sent)
        self.assertTrue(any(s.startswith('2026-10-05 07:00') and '+' not in s for s in sent))

    def test_an_accepted_value_fails_and_the_original_is_put_back(self):
        answers = [Reply(204, None), Reply(400, {'code': '23514'}), Reply(400, {'code': '23514'}), Reply(400, {'code': '23514'}),
                   Reply(204, None)]  # 첫 값이 받아들여짐 → 마지막은 원복
        fake = Fake([
            ('GET', 'universities?id=eq', lambda b, u: Reply(200, [{'card_opens_at': '2026-10-05T07:00:00+09:00'}])),
            ('PATCH', 'universities', lambda b, u: answers.pop(0)),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-HOME-27')
        self.assertEqual(result, 'fail')
        self.assertEqual(fake.bodies('PATCH', '/rest/v1/universities')[-1], {'card_opens_at': '2026-10-05T07:00:00+09:00'})


def _candidates_of(scores):
    return lambda b, u: Reply(200, {'candidates': [{'profile_id': pid, 'score': s} for pid, s in scores()]})


class ScoringTest(Base):
    def world(self, expected_for):
        """후보 응답을 [expected_for](키 → 점수)로 만든다 — 계정 id 는 만든 순서(O, C0 … C9)로 id-1 …"""
        names = ['O', *[f'C{i}' for i in range(10)]]
        ids = {name: f'id-{1 + i}' for i, name in enumerate(names)}
        fake = Fake([('GET', '/matching/candidates', _candidates_of(lambda: [(ids[n], expected_for(n)) for n in names[1:]]))])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    TRUE = {'C0': 1.0, 'C1': 0.7, 'C2': 0.8, 'C3': 0.5, 'C4': 0.5, 'C5': 0.8, 'C6': 0.4, 'C7': 0.9464, 'C8': 0.9220, 'C9': 0.8367}

    def test_every_score_case_passes_with_the_documented_numbers(self):
        self.world(self.TRUE.get)
        for case in ('E-CARD-60', 'E-CARD-61', 'E-CARD-62', 'E-CARD-63', 'E-CARD-64', 'E-CARD-66', 'E-CARD-67',
                     'E-CARD-69', 'E-CARD-70', 'E-CARD-71'):
            self.assertEqual(area2.attempt(self.run, case)[0], 'pass', case)

    def test_a_wrong_score_names_the_candidate_and_both_numbers(self):
        self.world(lambda n: 0.99 if n == 'C1' else self.TRUE[n])
        result, memo = area2.attempt(self.run, 'E-CARD-61')
        self.assertEqual(result, 'fail')
        self.assertIn('0.99', memo)
        self.assertIn('0.7', memo)

    def test_tag_score_of_the_perfect_candidate_is_really_one_and_c2_really_zero(self):
        """태그 점수 = (관심사 자카드 + (O.나는↔C.원해 + C.나는↔O.원해) / 2) / 2 — 서버 SQL 과 같은 식으로 시험 값에서 직접 계산한다."""
        fake = self.world(self.TRUE.get)
        area2.attempt(self.run, 'E-CARD-60')
        profiles = self.seeded(fake)
        owner, c0, c2 = profiles[0], profiles[1], profiles[3]

        def jaccard(x, y):
            return len(set(x) & set(y)) / len(set(x) | set(y))

        def tag_score(me, other):
            return (jaccard(me['interest_tags'], other['interest_tags'])
                    + (jaccard(me['my_traits'], other['ideal_traits']) + jaccard(other['my_traits'], me['ideal_traits'])) / 2) / 2

        self.assertEqual(tag_score(owner, c0), 1.0)
        self.assertEqual(tag_score(owner, c2), 0.0)

    def test_world_is_built_once_and_candidates_are_female_with_the_planned_vectors(self):
        fake = self.world(self.TRUE.get)
        area2.attempt(self.run, 'E-CARD-60')
        area2.attempt(self.run, 'E-CARD-61')
        profiles = self.seeded(fake)
        self.assertEqual(len(profiles), 11)  # O + C0~C9 — 두 번째 가설이 다시 만들지 않는다
        self.assertEqual([p['gender'] for p in profiles], ['male'] + ['female'] * 10)
        vectors = {b['profile_id']: b for b in fake.bodies('POST', '/rest/v1/profile_vectors')}
        self.assertEqual(vectors['id-1']['self_survey'], '[' + ','.join(['1'] * 8) + ']')
        self.assertEqual(vectors['id-3']['self_survey'], '[' + ','.join(['-1'] * 8) + ']')  # C1 = 정반대
        self.assertEqual(json.loads(vectors['id-1']['self_embedding'])[:2], [1, 0])
        self.assertEqual(json.loads(vectors['id-5']['self_embedding'])[:2], [0, 1])  # C3 = 직교


class ReferralTest(Base):
    def test_own_code_is_422_and_leaves_no_ledger_rows(self):
        fake = Fake([
            ('GET', '/referral/my-code', lambda b, u: Reply(200, {'code': 'ABC234'})),
            ('POST', '/referral/redeem', lambda b, u: Reply(422, {'detail': '이 코드는 쓸 수 없어요'})),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(area2.attempt(self.run, 'E-REF-09')[0], 'pass')
        self.assertEqual(fake.bodies('POST', '/referral/redeem'), [{'code': 'ABC234'}])

    def test_a_200_is_a_fail(self):
        fake = Fake([
            ('GET', '/referral/my-code', lambda b, u: Reply(200, {'code': 'ABC234'})),
            ('POST', '/referral/redeem', lambda b, u: Reply(200, {'referrer_id': 'x'})),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-REF-09')
        self.assertEqual(result, 'fail')
        self.assertIn('422', memo)


class HeartTest(Base):
    def test_overdraft_is_refused_by_the_database_and_ledger_stays(self):
        rows = {'ledger': 1}

        def grant(body, url):
            if body['p_amount'] < 0:
                return Reply(400, {'code': '23514'})
            return Reply(200, None)

        fake = Fake([
            ('POST', 'rpc/grant_hearts', grant),
            ('GET', 'heart_transactions', lambda b, u: Reply(200, [{'amount': 5}] * rows['ledger'])),
            ('GET', 'entitlements', lambda b, u: Reply(200, [{'heart_balance': 5}])),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(area2.attempt(self.run, 'E-HEART-41')[0], 'pass')
        amounts = [b['p_amount'] for b in fake.bodies('POST', 'rpc/grant_hearts')]
        self.assertEqual(amounts, [5, -10])

    def test_an_accepted_overdraft_is_a_fail(self):
        fake = Fake([
            ('POST', 'rpc/grant_hearts', lambda body, url: Reply(200, None)),  # −10 도 받아들임 = 음수 방어가 없다
            ('GET', 'heart_transactions', lambda body, url: Reply(200, [{'amount': 5}, {'amount': -10}])),
            ('GET', 'entitlements', lambda body, url: Reply(200, [{'heart_balance': -5}])),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-HEART-41')
        self.assertEqual(result, 'fail')
        self.assertIn('23514', memo)

    def _cleanup_world(self, after_batch, calls):
        """정리 배치를 흉내 내는 가짜 — [after_batch](번째) 가 그 배치 뒤 오래된 줄이 어떻게 보일지 정한다."""
        state = {'old_path': 'id-1/OLD.jpg', 'fresh_path': 'id-1/FRESH.jpg', 'files': ['OLD.jpg', 'FRESH.jpg']}

        def batch(name):
            calls.append(name)
            after_batch(len(calls), state)

        def row(path_key):
            return lambda b, u: Reply(200, [{'storage_path': state[path_key], 'status': 'approved'}])

        fake = Fake([
            ('GET', 'heart_task_submissions?id=eq.OLD', row('old_path')),
            ('GET', 'heart_task_submissions?id=eq.FRESH', row('fresh_path')),
            ('POST', '/storage/v1/object/list/', lambda b, u: Reply(200, [{'id': 'x', 'name': n} for n in state['files']])),
        ])
        return fake, batch

    def test_cleanup_twice_deletes_the_old_proof_once_keeps_the_fresh_one_and_goes_through_tools_batch(self):
        calls = []

        def after(n, state):
            if n == 1:  # 첫 배치가 61일 된 것을 지운다 — 두 번째는 지울 것이 없다
                state['old_path'] = None
                state['files'] = ['FRESH.jpg']

        fake, batch = self._cleanup_world(after, calls)
        ids = iter(['OLD', 'FRESH'])
        with mock.patch.object(tools, 'call', fake), mock.patch.object(tools, 'batch', batch),                 mock.patch.object(area2, 'SETTLE_SECONDS', 0), mock.patch.object(area2, '_new_id', lambda: next(ids)):
            result, memo = area2.attempt(self.run, 'E-HEART-24')
        self.assertEqual((result, calls), ('pass', ['cleanup', 'cleanup']))
        self.assertIn('deleted_heart_proofs', memo)  # 스케줄러 호출이라 개수는 못 읽는다는 한계를 메모에 남긴다

    def test_a_second_batch_that_deletes_the_fresh_proof_is_a_fail(self):
        calls = []

        def after(n, state):
            state['old_path'] = None
            state['files'] = ['FRESH.jpg']
            if n == 2:  # 59일 된 것까지 지우면 멱등이 아니다
                state['fresh_path'] = None
                state['files'] = []

        fake, batch = self._cleanup_world(after, calls)
        ids = iter(['OLD', 'FRESH'])
        with mock.patch.object(tools, 'call', fake), mock.patch.object(tools, 'batch', batch),                 mock.patch.object(area2, 'SETTLE_SECONDS', 0), mock.patch.object(area2, '_new_id', lambda: next(ids)):
            result, memo = area2.attempt(self.run, 'E-HEART-24')
        self.assertEqual(result, 'fail')
        self.assertEqual(memo, '두 번째 배치가 59일 된 줄을 지움(멱등이 아님)')  # 이것 하나만 어긋난다

    def test_a_failed_scheduler_call_is_blocked_not_a_crash(self):
        import subprocess

        def boom(name):
            raise subprocess.CalledProcessError(1, 'gcloud')

        fake, _ = self._cleanup_world(lambda n, s: None, [])
        with mock.patch.object(tools, 'call', fake), mock.patch.object(tools, 'batch', boom),                 mock.patch.object(area2, '_new_id', lambda: 'OLD'):
            result, memo = area2.attempt(self.run, 'E-HEART-24')
        self.assertEqual(result, 'blocked')
        self.assertIn('배치 cleanup 호출 실패', memo)  # 시험 쪽 예외가 아니라 배치 호출 실패로 말한다

    def test_a_batch_that_never_deletes_the_old_proof_is_a_fail(self):
        fake, batch = self._cleanup_world(lambda n, state: None, [])
        ids = iter(['OLD', 'FRESH'])
        with mock.patch.object(tools, 'call', fake), mock.patch.object(tools, 'batch', batch),                 mock.patch.object(area2, 'SETTLE_SECONDS', 0), mock.patch.object(area2, 'FIRST_BATCH_WAIT', 0),                 mock.patch.object(area2, '_new_id', lambda: next(ids)):
            result, memo = area2.attempt(self.run, 'E-HEART-24')
        self.assertEqual(result, 'fail')
        self.assertIn('첫 배치 뒤 61일', memo)
        self.assertIn('두 번째 배치 뒤 61일', memo)


class WithdrawnTest(Base):
    """탈퇴 상태는 짝 칸(withdrawn_at)을 같이 채워야 한다 — DB 제약 profiles_withdrawn_pair(20260927010100)."""

    def test_withdrawn_is_written_together_with_withdrawn_at(self):
        fake = Fake([('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': [
            {'profile_id': 'id-2', 'score': 1}, {'profile_id': 'id-3', 'score': 1}]}))])
        with mock.patch.object(tools, 'call', fake):
            area2.attempt(self.run, 'E-CARD-39')
        gone = [b for b in fake.bodies('PATCH', '/rest/v1/profiles') if b.get('status') == 'withdrawn']
        self.assertEqual(len(gone), 1)
        self.assertTrue(gone[0].get('withdrawn_at'))
        away = [b for b in fake.bodies('PATCH', '/rest/v1/profiles') if b.get('status') == 'suspended']
        self.assertNotIn('withdrawn_at', away[0])  # 정지는 짝 칸이 없다

    def test_referral_case_also_pairs_the_withdrawal(self):
        fake = Fake([('GET', 'profiles?id=eq', lambda b, u: Reply(200, [{'referral_code': 'ABC234'}])),
                     ('POST', '/referral/redeem', lambda b, u: Reply(404, {'detail': '없는 코드예요, 다시 확인해 주세요'}))])
        with mock.patch.object(tools, 'call', fake):
            area2.attempt(self.run, 'E-REF-11')
        gone = [b for b in fake.bodies('PATCH', '/rest/v1/profiles') if b.get('status') == 'withdrawn']
        self.assertEqual(len(gone), 1)
        self.assertTrue(gone[0].get('withdrawn_at'))


class RetryTest(Base):
    def test_one_connection_reset_is_retried_and_the_second_try_decides(self):
        import urllib.error
        tries = []

        def flaky(run):
            tries.append(1)
            if len(tries) == 1:
                raise ConnectionResetError(10054, '연결 끊김')
            return 'pass', ''

        with mock.patch.dict(area2.CASES, {'E-HEART-48': flaky}):
            self.assertEqual(area2.attempt(self.run, 'E-HEART-48'), ('pass', ''))
        self.assertEqual(len(tries), 2)

    def test_a_second_reset_is_blocked_after_exactly_two_tries(self):
        tries = []

        def down(run):
            tries.append(1)
            raise ConnectionResetError(10054, '연결 끊김')

        with mock.patch.dict(area2.CASES, {'E-HEART-48': down}):
            result, memo = area2.attempt(self.run, 'E-HEART-48')
        self.assertEqual((result, len(tries)), ('blocked', 2))
        self.assertIn('연결', memo)

    def test_ssl_and_http_client_errors_are_retried_once_like_the_other_drops(self):
        for error in (ssl.SSLError('bad record mac'), http.client.RemoteDisconnected('끊김'), http.client.IncompleteRead(b'')):
            tries = []

            def flaky(run, error=error, tries=tries):
                tries.append(1)
                if len(tries) == 1:
                    raise error
                return 'pass', ''

            with mock.patch.dict(area2.CASES, {'E-HEART-48': flaky}):
                self.assertEqual(area2.attempt(self.run, 'E-HEART-48'), ('pass', ''), repr(error))
            self.assertEqual(len(tries), 2, repr(error))

    def test_two_ssl_or_http_client_drops_are_blocked_after_exactly_two_tries(self):
        for error in (ssl.SSLError('bad record mac'), http.client.RemoteDisconnected('끊김')):
            tries = []

            def down(run, error=error, tries=tries):
                tries.append(1)
                raise error

            with mock.patch.dict(area2.CASES, {'E-HEART-48': down}):
                result, memo = area2.attempt(self.run, 'E-HEART-48')
            self.assertEqual((result, len(tries)), ('blocked', 2), repr(error))
            self.assertIn('연결', memo)

    def test_a_real_assertion_failure_is_not_retried(self):
        tries = []

        def wrong(run):
            tries.append(1)
            return 'fail', '값이 다르다'

        with mock.patch.dict(area2.CASES, {'E-HEART-48': wrong}):
            self.assertEqual(area2.attempt(self.run, 'E-HEART-48'), ('fail', '값이 다르다'))
        self.assertEqual(len(tries), 1)


class PollTest(Base):
    def test_two_parallel_votes_reward_exactly_once(self):
        rewarded = iter([True, False])
        fake = Fake([
            ('POST', '/votes', lambda b, u: Reply(200, {'poll': {}, 'rewarded': next(rewarded)})),
            ('POST', '/community/polls', lambda b, u: Reply(201, {'id': 'p1'})),
            ('GET', 'heart_transactions', lambda b, u: Reply(200, [{'amount': 10}])),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(area2.attempt(self.run, 'E-POLL-10')[0], 'pass')

    def test_two_rewards_is_a_fail(self):
        fake = Fake([
            ('POST', '/votes', lambda b, u: Reply(200, {'poll': {}, 'rewarded': True})),
            ('POST', '/community/polls', lambda b, u: Reply(201, {'id': 'p1'})),
            ('GET', 'heart_transactions', lambda b, u: Reply(200, [{'amount': 10}, {'amount': 10}])),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-POLL-10')
        self.assertEqual(result, 'fail')
        self.assertIn('rewarded', memo)


class PollLedgerTest(Base):
    def test_one_reward_flag_but_two_ledger_rows_is_a_fail(self):
        rewarded = iter([True, False])
        fake = Fake([
            ('POST', '/votes', lambda b, u: Reply(200, {'poll': {}, 'rewarded': next(rewarded)})),
            ('POST', '/community/polls', lambda b, u: Reply(201, {'id': 'p1'})),
            ('GET', 'heart_transactions', lambda b, u: Reply(200, [{'amount': 10}, {'amount': 10}])),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-POLL-10')
        self.assertEqual(result, 'fail')
        self.assertIn('원장', memo)


class CleanupTest(Base):
    def test_moved_account_goes_back_to_the_test_school_even_when_a_check_fails(self):
        fake = Fake([
            ('GET', 'university_email_domains', lambda b, u: Reply(200, [{'university_id': 'TEST-U'}])),
            ('GET', 'universities?region_group=eq.seoul', lambda b, u: Reply(200, [{'id': 'SEOUL-U'}])),
            ('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': []})),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        area2.attempt(self.run, 'E-CARD-31')
        moves = [b for b in fake.bodies('PATCH', '/rest/v1/profiles') if 'university_id' in b]
        self.assertEqual([m['university_id'] for m in moves], ['SEOUL-U', 'TEST-U'])  # 옮겼다가 돌려놓는다

    def test_every_poll_a_case_made_is_deleted_by_its_author(self):
        fake = Fake([
            ('POST', '/community/polls', lambda b, u: Reply(201, {'id': 'p1'})),
            ('GET', 'rest/v1/polls?author_id', lambda b, u: Reply(200, [{'id': 'p1'}, {'id': 'p2'}])),
            ('GET', '/community/polls', lambda b, u: Reply(200, {'polls': []})),
        ])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        area2.attempt(self.run, 'E-POLL-03')
        self.assertEqual(sorted(p for m, p, _ in fake.calls if m == 'DELETE'),
                         ['/community/polls/p1', '/community/polls/p2'])


class PhoneTest(Base):
    def test_a_chosen_phone_goes_into_the_one_basic_info_save_of_the_factory(self):
        fake = self.serve()
        account = area2._home(self.run, 'female', phone='010-1234-5678')
        saves = [b for m, p, b in fake.calls if m == 'POST' and p == '/profile-onboarding/basic-info']
        self.assertEqual([b['phone_number'] for b in saves], ['010-1234-5678'])  # 다시 저장하지 않는다
        self.assertEqual(account['phone'], '010-1234-5678')


class ReviewGuardTest(Base):
    def test_review_writes_refuse_a_stranger_account(self):
        with self.assertRaises(Blocked):
            area2._review(self.run, {'id': 'not-mine'}, 'sub-1', status='approved')


class FilterTest(Base):
    def test_same_gender_is_not_a_candidate_and_opposite_is(self):
        # 계정은 만든 순서: A(남) · 같은 성별 · 반대 성별 → id-1 · id-2 · id-3
        fake = Fake([('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': [{'profile_id': 'id-3', 'score': 1}]}))])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(area2.attempt(self.run, 'E-CARD-30')[0], 'pass')
        genders = [b['gender'] for b in self.seeded(fake)]
        self.assertEqual(genders, ['male', 'male', 'female'])

    def test_a_same_gender_candidate_is_a_fail_with_the_name_of_the_problem(self):
        fake = Fake([('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': [
            {'profile_id': 'id-2', 'score': 1}, {'profile_id': 'id-3', 'score': 1}]}))])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        result, memo = area2.attempt(self.run, 'E-CARD-30')
        self.assertEqual(result, 'fail')
        self.assertIn('같은 성별', memo)


class NoRetryTest(Base):
    """두 번 적용되면 결과가 달라지는 요청은 `retry=False` 로 한 번만 보낸다 — 읽기 · 멱등 요청은 기본(키워드 없음)."""

    def run_case(self, case, rules=()):
        fake = Fake(list(rules))
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        area2.attempt(self.run, case)
        return fake

    def assertOnce(self, fake, method, piece):
        got = [o for m, p, o in fake.options if m == method and piece in p]
        self.assertTrue(got, f'{method} {piece} 호출이 없다')
        self.assertTrue(all(o == {'retry': False} for o in got), f'{method} {piece}: {got}')

    def assertDefault(self, fake, method, piece):
        got = [o for m, p, o in fake.options if m == method and piece in p]
        self.assertTrue(got, f'{method} {piece} 호출이 없다')
        self.assertTrue(all(o == {} for o in got), f'{method} {piece}: {got}')

    POLL = ('POST', '/community/polls', lambda b, u: Reply(201, {'id': 'p1'}))
    CODE = ('GET', 'select=referral_code', lambda b, u: Reply(200, [{'referral_code': 'ABCDE2'}]))

    def test_card_decision_and_acceptance_answer_are_sent_once(self):
        self.assertOnce(self.run_case('E-CARD-83'), 'POST', '/decision')
        fake = self.run_case('E-CARD-82')
        self.assertOnce(fake, 'POST', '/decision')
        self.assertOnce(fake, 'POST', '/cards/acceptances/')

    def test_a_strangers_card_decision_is_sent_once(self):
        fake = self.run_case('E-CARD-89')
        self.assertOnce(fake, 'POST', '/decision')

    def test_the_contact_block_hypothesis_sends_its_decisions_and_answer_once_but_the_block_itself_by_default(self):
        fake = self.run_case('E-CARD-37', [('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': []}))])
        self.assertOnce(fake, 'POST', '/decision')
        self.assertOnce(fake, 'POST', '/cards/acceptances/')
        self.assertDefault(fake, 'POST', '/contact-blocks')

    def test_the_acceptance_that_opens_the_inbox_is_sent_once(self):
        self.assertOnce(self.run_case('E-CARD-88'), 'POST', '/decision')

    def test_posting_a_poll_and_voting_are_sent_once(self):
        fake = self.run_case('E-POLL-24', [self.POLL])
        self.assertOnce(fake, 'POST', '/community/polls')
        self.assertOnce(fake, 'POST', '/votes')

    def test_the_parallel_poll_hypotheses_send_every_request_once(self):
        fake = self.run_case('E-POLL-17', [self.POLL])
        self.assertEqual(len([1 for m, p, o in fake.options if m == 'POST' and p == '/community/polls']), 11)
        self.assertOnce(fake, 'POST', '/community/polls')
        self.assertOnce(self.run_case('E-POLL-10', [self.POLL]), 'POST', '/votes')

    def test_heart_task_submissions_are_sent_once_also_in_the_parallel_hypothesis(self):
        self.assertOnce(self.run_case('E-HEART-07'), 'POST', '/submissions')
        self.assertOnce(self.run_case('E-HEART-08'), 'POST', '/submissions')

    def test_redeem_is_sent_once_also_in_the_parallel_hypothesis(self):
        self.assertOnce(self.run_case('E-REF-15', [self.CODE]), 'POST', '/referral/redeem')
        self.assertOnce(self.run_case('E-REF-10', [self.CODE]), 'POST', '/referral/redeem')

    def test_a_heart_grant_is_sent_once(self):
        self.assertOnce(self.run_case('E-HEART-41'), 'POST', 'rpc/grant_hearts')

    def test_the_operator_review_patch_is_sent_once_because_the_resent_reviewed_at_is_refused(self):
        fake = self.run_case('E-HEART-10', [('GET', 'heart_task_submissions', lambda b, u: Reply(200, [{'id': 's1'}]))])
        self.assertOnce(fake, 'PATCH', '/rest/v1/heart_task_submissions')

    def test_the_candidate_read_and_the_school_time_patch_keep_the_default(self):
        fake = self.run_case('E-CARD-30', [('GET', '/matching/candidates', lambda b, u: Reply(200, {'candidates': []}))])
        self.assertDefault(fake, 'GET', '/matching/candidates')
        fake = self.run_case('E-HOME-27', [('GET', 'universities?id=eq', lambda b, u: Reply(200, [{'card_opens_at': None}]))])
        self.assertDefault(fake, 'PATCH', '/rest/v1/universities')

    def test_reads_deletes_patches_and_idempotent_posts_keep_the_default(self):
        fake = self.run_case('E-POLL-24', [self.POLL, ('GET', 'polls?author_id', lambda b, u: Reply(200, [{'id': 'p1'}]))])
        self.assertDefault(fake, 'GET', '/community/polls/')
        self.assertDefault(fake, 'DELETE', '/community/polls/')
        account = self.run.account('home')
        fake = Fake()
        with mock.patch.object(tools, 'call', fake):
            area2._contact_block(self.run, account, '010-0000-0000')
            area2._patch(self.run, 'profiles?id=eq.x', {'a': 1})
            area2._card(self.run, account, account)
        self.assertDefault(fake, 'POST', '/contact-blocks')
        self.assertDefault(fake, 'PATCH', '/rest/v1/profiles')
        self.assertDefault(fake, 'POST', 'daily_cards')  # id 를 이쪽이 정해 두 번 가면 23505 — 한 번 더 가도 판정이 바뀌지 않아 기본(재시도)


if __name__ == '__main__':
    unittest.main()
