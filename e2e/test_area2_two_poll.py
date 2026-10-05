"""영역 2 두 기기 투표 글 8(E-POLL-11 · 12 · 19 · 20 · 21 · 22 · 23 · 29)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이
진짜 Hub 둘 + 가짜 앱 스레드 둘(HTTP 로 /hear · /say) + 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area2_two_poll`.

가짜 서버 [World] 는 e2e/test_area2_phone_b.py 의 World(글 올리기 · 지우기 · 피드 · 잔액)에 투표(409 · 404 · 하루 첫 투표 하트) ·
글 한 개 읽기 · 신고 · 1회용 토큰(받을 때마다 새 것)을 얹은 것이다. 가짜 앱 [Phone] 은 진짜 앱이 `step` 에서 멈추는 순서대로
말하고, 말하기 직전에 앱이 서버에 남길 일([effect])을 한다 — step 이름은 frontend/integration_test/area2_two_poll.dart 와 같아야 한다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 … 이다(각 가설의 준비 순서는 area2_two_poll.py 의 주석).
"""

import http.client
import json
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area2_two_poll, tools, twodev
from e2e.test_area1 import CFG
from e2e.test_area2_phone_b import World as PollWorld
from e2e.test_twodev import App, FakeAdb, drain
from e2e.tools import Hub, Reply, Run

CASES = 'E-POLL-11 E-POLL-12 E-POLL-19 E-POLL-20 E-POLL-21 E-POLL-22 E-POLL-23 E-POLL-29'.split()
PASS = {'result': 'pass', 'note': ''}
FAIL = {'result': 'fail', 'note': '화면이 다름'}
NOT_FOUND = '질문을 찾을 수 없어요'
ALREADY_VOTED = '이미 투표했어요'
HUBS = {}


def setUpModule():
    HUBS.update(A=Hub(0), B=Hub(0))


def tearDownModule():
    for hub in HUBS.values():
        hub.close()


class World(PollWorld):
    def __init__(self):
        super().__init__()
        self.links, self.log, self.status_log, self.options = [], [], [], []
        for method, pattern, reply in (
            ('POST', r'/auth/v1/admin/generate_link', self.generate_link),
            ('POST', r'/community/polls/[^/]+/votes', self.cast_vote),
            ('GET', r'/community/polls/[^/]+', self.read_poll),
            ('POST', r'/reports', self.report),
        ):
            self.on(method, pattern, reply)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        path = urlsplit(url).path
        self.options.append((method, path, options))  # retry=False 같은 호출 옵션 — 한 번만 보내는지 본다
        if method == 'PATCH' and path == '/rest/v1/polls' and (body or {}).get('status') == 'blinded':
            self.log.append('blinded')
        return super().__call__(method, url, headers, body, raw, **options)

    def once(self, method, suffix):
        """[suffix] 로 끝나는 경로로 간 [method] 호출들의 옵션."""
        return [options for m, path, options in self.options if m == method and path.endswith(suffix)]

    # 규칙 ------------------------------------------------------------------------------------
    def status_of(self, pid):
        return self.statuses.get(pid, 'active')

    def poll(self, pid):
        return next((p for p in self.rows('polls') if p['id'] == pid), None)

    def shown(self, poll):
        """피드 · 상세 · 투표 · 신고가 "있는 글" 로 보는 것 — 가려지지 않았고 글쓴이가 active 다."""
        return poll is not None and poll['status'] == 'visible' and self.status_of(poll['author_id']) == 'active'

    def generate_link(self, sent):
        token = f'link-{len(self.links) + 1}'
        self.links.append((sent['body']['email'], token))
        self.log.append(('link', sent['body']['email'], token))
        return Reply(200, {'hashed_token': token})

    def cast_vote(self, sent):
        voter, pid = self.caller(sent), sent['path'].split('/')[3]
        if not self.shown(self.poll(pid)):
            return Reply(404, {'detail': NOT_FOUND})
        if any(v['poll_id'] == pid and v['voter_id'] == voter for v in self.rows('poll_votes')):
            return Reply(409, {'detail': ALREADY_VOTED})
        self.rows('poll_votes').append({'poll_id': pid, 'voter_id': voter, 'choice': sent['body']['choice']})
        rewarded = not any(t['profile_id'] == voter and t['reason'] == 'poll_vote' for t in self.rows('heart_transactions'))
        if rewarded:
            self.rows('heart_transactions').append({'profile_id': voter, 'amount': 10, 'reason': 'poll_vote', 'ref_id': pid})
        return Reply(200, {'poll': {'id': pid}, 'rewarded': rewarded})

    def read_poll(self, sent):
        pid = sent['path'].split('/')[3]
        return Reply(200, {'poll': {'id': pid}}) if self.shown(self.poll(pid)) else Reply(404, {'detail': NOT_FOUND})

    def report(self, sent):
        me, body = self.caller(sent), sent['body']
        poll = self.poll(body['target_id'])
        if not self.shown(poll) or poll['author_id'] == me:
            return Reply(404, {'detail': NOT_FOUND})
        if any(r['reporter_id'] == me and r['target_id'] == poll['id'] for r in self.rows('reports')):
            return Reply(409, {'detail': '이미 신고를 완료했어요'})
        self.rows('reports').append({'reporter_id': me, 'target_type': body['target_type'], 'target_id': poll['id'],
                                     'target_profile_id': poll['author_id'], 'reason': body['reason']})
        return Reply(201, {'ok': True})

    def delete_poll(self, sent):
        if self.status_of(self.caller(sent)) != 'active':  # 정지 계정은 글도 못 지운다(get_verified_caller)
            return Reply(403, {'detail': '이용이 제한된 계정이에요'})
        self.log.append('delete-' + self.caller(sent))
        reply = super().delete_poll(sent)
        alive = {p['id'] for p in self.rows('polls')}
        self.tables['poll_votes'] = [v for v in self.rows('poll_votes') if v['poll_id'] in alive]  # 투표는 cascade
        return reply

    def patch_profile(self, sent):
        reply = super().patch_profile(sent)
        if 'status' in sent['body']:
            who = sent['query']['id'].removeprefix('eq.')
            self.statuses[who] = sent['body']['status']
            self.status_log.append((who, sent['body']['status']))
            self.log.append('status-' + sent['body']['status'])
        return reply

    # 앱이 서버에 남기는 일 -----------------------------------------------------------------------
    def vote_as(self, voter, question, choice='a'):
        pid = next(p['id'] for p in self.rows('polls') if p['question'] == question)
        return self.cast_vote({'auth': 'tok-' + voter.removeprefix('id-'), 'path': f'/community/polls/{pid}/votes',
                               'body': {'choice': choice}})

    def delete_as(self, author, question):
        pid = next(p['id'] for p in self.rows('polls') if p['question'] == question)
        return self.delete_poll({'auth': 'tok-' + author.removeprefix('id-'), 'path': f'/community/polls/{pid}', 'body': None})


class Phone(App):
    """진짜 앱 흉내 — 일감을 듣고, [script] = [(step, effect)] 차례로 effect(job) 를 한 뒤 step 을 말하고 go 를 듣는다. 끝에 [finish] 후 [result]."""

    def __init__(self, hub, script=(), result=PASS, finish=None):
        super().__init__(hub, steps=[name for name, _ in script], result=result)
        self.script, self.finish = list(script), finish

    def _call(self, method, path, body=None):
        """부하가 큰 PC 에서 Hub 가 2초 넘게 늦으면 일감이 닫힌 소켓에 쓰여 사라진다(test_twodev.App 은 2초) — 10초까지 기다린다."""
        conn = http.client.HTTPConnection('127.0.0.1', self.hub.port, timeout=10)
        try:
            conn.request(method, path, body=json.dumps(body) if body is not None else None)
            res = conn.getresponse()
            return json.loads(res.read() or 'null') if res.status == 200 else None
        finally:
            conn.close()

    def run(self):
        try:
            self.job = self.hear()
            for name, effect in self.script:
                if effect:
                    effect(self.job)
                self._call('POST', '/say', {'step': name})
                self.heard.append(self.hear())
            if self.finish:
                self.finish(self.job)
            if self.result is not None and not self.halt.is_set():
                self._call('POST', '/say', self.result)
        except Exception:
            if not self.halt.is_set():  # 시험이 끝난 뒤의 끊김만 삼킨다
                raise


def steps(*names):
    return [(name, None) for name in names]


class Base(unittest.TestCase):
    def setUp(self):
        for phone in getattr(self, 'phones', []):  # setUp 을 다시 부르는 시험 — 앞 가짜 앱이 다음 일감을 가로채지 않게
            self._stop(phone)
        self.phones = []
        for hub in HUBS.values():
            drain(hub)
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area2-two-poll', 'b', cfg={**CFG}, key='svc')
        self.world = World()
        for patcher in (mock.patch.object(tools, 'call', self.world), mock.patch.object(tools, 'screencap', return_value=b''),
                        mock.patch.object(tools, 'adb', FakeAdb()), mock.patch.object(twodev, 'KILL_PAUSE', 0),
                        mock.patch.object(twodev, 'SLICE', 0.05), mock.patch.object(twodev, 'GRACE', 0.3)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def go(self, case, a=(), b=(), a_result=PASS, b_result=PASS, a_finish=None, b_finish=None):
        """가설 하나를 가짜 앱 둘로 돈다 → ((결과, 메모), 폰 A, 에뮬 B)."""
        phones = (Phone(HUBS['A'], a, a_result, a_finish), Phone(HUBS['B'], b, b_result, b_finish))
        for phone in phones:
            self.addCleanup(self._stop, phone)
            self.phones.append(phone)
            phone.start()
        two = twodev.bound(self.run_, case, twodev.Side(HUBS['A'], 'SER-A'), twodev.Side(HUBS['B'], 'SER-B'))
        return (twodev.TWO[case](self.run_, two), *phones)

    @staticmethod
    def _stop(phone):
        phone.halt.set()
        phone.join(2)

    def votes(self):
        return [(v['voter_id'], v['choice']) for v in self.world.rows('poll_votes')]

    def calls(self, method, prefix):
        return [s for s in self.world.sent if s['method'] == method and s['path'].startswith(prefix)]

    def answer(self, outcome, expected):
        (result, memo) = outcome
        self.assertEqual(result, expected, memo)
        return memo


class RegistryTest(unittest.TestCase):
    def test_the_bundle_is_the_eight_in_order_and_every_case_is_a_two_device_case(self):
        self.assertEqual(area1.BUNDLES['area2-two-poll'], CASES)
        self.assertEqual(list(area2_two_poll.TWO_POLL), CASES)
        self.assertLessEqual(set(CASES), set(twodev.TWO))

    def test_none_of_the_numbers_is_also_an_api_or_a_single_phone_case(self):
        for case in CASES:
            self.assertNotIn(case, area2.CASES)
            self.assertNotIn(case, area1.PHONE)
            self.assertNotIn(case, area2.SKIPPED)

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area2_two_poll 을 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m, twodev; print(m.BUNDLES.get("area2-two-poll"), "E-POLL-29" in twodev.TWO)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{CASES} True')

    def test_a_missing_account_is_blocked_not_a_crash(self):
        # 준비(계정 만들기)가 안 되면 예외가 아니라 blocked 로 닫힌다.
        for case in CASES:
            with self.subTest(case):
                world = World()
                world.on('POST', r'/auth/v1/admin/users', Reply(500, {'msg': '서버 오류'}))
                with mock.patch.object(tools, 'call', world):
                    run = Run(Path(tempfile.mkdtemp()) / 'x', 'b', cfg={**CFG}, key='svc')
                    result, memo = twodev.TWO[case](run, mock.Mock(side_effect=AssertionError('앱을 열면 안 된다')))
                self.assertEqual(result, 'blocked')
                self.assertIn('계정 만들기', memo)


class CommonTest(Base):
    PLANS = {
        'E-POLL-11': (steps('after-vote'), steps('voted')),
        'E-POLL-12': (steps('signed-in', 'voted'), steps('need-login', 'ready')),
        'E-POLL-19': (steps('wait-vote', 'deleted'), steps('voted')),
        'E-POLL-20': (steps('seen'), steps('seen')),
        'E-POLL-21': (steps('seen', 'after'), steps('seen')),
        'E-POLL-22': (steps('seen', 'after'), steps('detail')),
        'E-POLL-23': (steps('seen'), steps('suspended', 'restored')),
        'E-POLL-29': (steps('checked'), steps('checked')),
    }

    def test_each_side_is_told_its_own_case_key(self):
        for case, (a, b) in self.PLANS.items():
            with self.subTest(case):
                self.setUp()
                outcome, phone_a, phone_b = self.go(case, a, b)
                # 앱 효과가 없어 DB 판정은 어긋날 수 있다 — 여기서는 일감 이름만 본다
                self.assertEqual(phone_a.job['case'], f'{case}/A')
                self.assertEqual(phone_b.job['case'], f'{case}/B')

    def test_a_failing_app_is_a_fail_and_every_poll_the_case_made_is_still_deleted_by_its_author(self):
        for case, (a, b) in self.PLANS.items():
            with self.subTest(case):
                self.setUp()
                (result, memo), *_ = self.go(case, a, b, b_result=FAIL)
                self.assertEqual(result, 'fail', memo)
                self.assertEqual(self.world.rows('polls'), [])
                self.assertEqual(self.world.status_of('id-1'), 'active')

    def test_a_blocked_app_is_blocked_and_the_polls_are_still_deleted(self):
        for case, (a, b) in self.PLANS.items():
            with self.subTest(case):
                self.setUp()
                (result, memo), *_ = self.go(case, a, b, a_result={'result': 'blocked', 'note': '앱이 막힘'})
                self.assertEqual(result, 'blocked', memo)
                self.assertEqual(self.world.rows('polls'), [])

    def test_writes_go_only_to_accounts_this_run_made(self):
        # 서비스 키로 바꾸거나 지우는 행은 이번 실행이 만든 계정(id-1 · id-2) 것뿐이다. 시험 글 지우기는 글쓴이 토큰이다.
        for case, (a, b) in self.PLANS.items():
            with self.subTest(case):
                self.setUp()
                self.go(case, a, b)
                touched = {s['query'].get('id') or s['query'].get('profile_id') for s in self.world.sent
                           if s['method'] in ('PATCH', 'DELETE') and s['path'] == '/rest/v1/profiles'}
                self.assertLessEqual(touched, {'eq.id-1', 'eq.id-2'})


class Poll11Test(Base):
    def run11(self, **kw):
        voted = lambda job: self.world.vote_as('id-2', job['question'], 'a')
        return self.go('E-POLL-11', steps('after-vote'), [('voted', voted)], **kw)

    def test_the_voter_gets_409_on_the_other_choice_and_the_first_choice_stays(self):
        outcome, a, b = self.run11()
        self.answer(outcome, 'pass')
        again = self.calls('POST', '/community/polls/')[-1]
        self.assertEqual((again['auth'], again['body']), ('tok-2', {'choice': 'b'}))  # B 의 토큰으로, 반대표
        self.assertEqual(a.job['question'], b.job['question'])
        self.assertTrue(a.job['question'].startswith('[E2E] '))
        self.assertEqual((a.job['token_hash'], b.job['token_hash']), ('link-2', 'link-4'))  # 계정마다 자기 1회용 토큰

    def test_the_api_vote_is_sent_once_and_never_resent_after_a_cut_connection(self):
        self.run11()
        self.assertEqual(self.world.once('POST', '/votes'), [{'retry': False}])

    def test_a_server_that_takes_the_second_vote_is_a_fail(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), Reply(200, {'poll': {}, 'rewarded': False})))
        result, memo = self.run11()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('409', memo)

    def test_a_first_choice_that_was_overwritten_is_a_fail(self):
        def flip(sent):
            self.world.rows('poll_votes')[0]['choice'] = 'b'
            return Reply(409, {'detail': ALREADY_VOTED})
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), flip))
        result, memo = self.run11()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('poll_votes', memo)

    def test_a_409_with_another_sentence_is_a_fail(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), Reply(409, {'detail': '다른 문구'})))
        result, memo = self.run11()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('문구', memo)


class LimitsTest(unittest.TestCase):
    def test_the_whole_case_limit_is_shorter_than_the_runners_and_the_wait_is_shorter_than_the_apps_three_minutes(self):
        self.assertLess(area2_two_poll.DEADLINE, tools.CASE_LIMIT)  # 두 기기 실행기가 먼저 이유를 적고 끝낸다
        self.assertLess(area2_two_poll.WAIT, 180)  # 앱 step 의 기다림(area2_two_poll.dart _waitOther 3분)보다 짧게


class Poll12Test(Base):
    """같은 계정 둘을 두 기기에 — U(id-1)는 두 기기가 쓰고, 글쓴이 V(id-2)는 PC 가 글을 올린다."""

    def run12(self, **kw):
        a_in = lambda job: (time.sleep(0.4), self.world.log.append('A-signed-in'))  # A 가 느려도 B 의 토큰은 그 뒤에 받는다
        a_vote = lambda job: self.world.vote_as('id-1', job['question'], 'a')
        return self.go('E-POLL-12', [('signed-in', a_in), ('voted', a_vote)], steps('need-login', 'ready'), **kw)

    def test_b_gets_its_own_token_only_after_a_has_signed_in_and_a_votes_first(self):
        kept = []
        outcome, a, b = self.run12(b_finish=lambda job: kept.append(self.votes()))  # 끝 정리가 글(과 표)을 지우기 전에
        self.answer(outcome, 'pass')
        email = self.world.users[0]['email']
        links = [(i, entry[2]) for i, entry in enumerate(self.world.log) if isinstance(entry, tuple) and entry[1] == email]
        signed_in = self.world.log.index('A-signed-in')
        last_index, last_token = links[-1]
        self.assertGreater(last_index, signed_in)  # 새 토큰을 받으면 앞의 것이 죽는다 — A 가 다 쓴 뒤에
        self.assertEqual(b.heard[0]['token_hash'], last_token)
        self.assertNotEqual(a.job['token_hash'], last_token)
        self.assertNotIn('token_hash', b.job)  # B 는 시작할 때 토큰이 없다
        self.assertEqual(kept, [[('id-1', 'a')]])

    def test_both_apps_get_the_same_question_and_it_is_the_authors_poll(self):
        outcome, a, b = self.run12()
        self.assertEqual(a.job['question'], b.job['question'])

    def test_b_votes_only_after_a_has_voted(self):
        # B 의 'ready' 는 A 가 투표했다고 말한(a-voted) 뒤에야 풀린다 — 풀리기 전까지 B 는 아무것도 못 한다.
        seen = []
        outcome, a, b = self.run12(b_finish=lambda job: seen.append(list(self.votes())))
        self.assertEqual(seen, [[('id-1', 'a')]])

    def test_a_first_vote_that_changed_to_the_second_devices_choice_is_a_fail(self):
        def overwrite(job):
            self.world.rows('poll_votes')[0]['choice'] = 'b'
        outcome, a, b = self.run12(b_finish=overwrite)
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('poll_votes', outcome[1])

    def test_a_token_that_cannot_be_made_blocks_b_and_names_the_cause(self):
        original = self.world.generate_link
        self.world.handlers.insert(0, ('POST', re.compile(r'/auth/v1/admin/generate_link'),
                                       lambda sent: Reply(500, {'msg': 'x'}) if len(self.world.links) >= 3 else original(sent)))
        outcome, a, b = self.run12()
        self.assertEqual(outcome[0], 'blocked')
        self.assertIn('generate_link 500', outcome[1])


class Poll19Test(Base):
    """A = 글쓴이(id-1), B = 투표하는 사람(id-2)."""

    def run19(self, voted=None, deleted=None, **kw):
        def b_vote(job):
            time.sleep(0.3)  # B 가 느려도 A 는 B 가 투표한 뒤에야 지운다
            self.world.log.append('B-vote')
            (voted or (lambda: self.world.vote_as('id-2', job['question'])))()

        def a_delete(job):
            self.world.log.append('A-delete')
            (deleted or (lambda: self.world.delete_as('id-1', job['question'])))()

        return self.go('E-POLL-19', [('wait-vote', None), ('deleted', a_delete)], [('voted', b_vote)], **kw)

    def test_the_author_deletes_after_b_voted_votes_go_with_it_and_the_hearts_stay(self):
        outcome, a, b = self.run19()
        self.answer(outcome, 'pass')
        self.assertLess(self.world.log.index('B-vote'), self.world.log.index('A-delete'))
        self.assertEqual(self.votes(), [])
        self.assertEqual([(t['profile_id'], t['amount']) for t in self.world.rows('heart_transactions')], [('id-2', 10)])
        self.assertEqual(a.job['question'], b.job['question'])

    def test_votes_that_survive_the_delete_are_a_fail(self):
        def only_the_poll(question=None):
            self.world.tables['polls'] = []
        outcome, a, b = self.run19(deleted=only_the_poll)
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('poll_votes', outcome[1])

    def test_hearts_taken_back_by_the_delete_are_a_fail(self):
        def delete_and_claw_back():
            self.world.delete_as('id-1', self.world.rows('polls')[0]['question'])
            self.world.tables['heart_transactions'] = []
        outcome, a, b = self.run19(deleted=delete_and_claw_back)
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('잔액', outcome[1])

    def test_a_vote_that_paid_no_hearts_is_a_fail_with_the_balance_named(self):
        def vote_without_reward():
            self.world.vote_as('id-2', self.world.rows('polls')[0]['question'])
            self.world.tables['heart_transactions'] = []
        outcome, a, b = self.run19(voted=vote_without_reward)
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('+10', outcome[1])


class Poll20Test(Base):
    """A(id-1) = 보는 사람, B(id-2) = 글쓴이. A 의 토큰으로 지우려 한다."""

    def test_an_app_that_never_says_a_step_leaves_the_delete_uncalled_and_is_a_fail(self):
        (result, memo), *_ = self.go('E-POLL-20', (), ())
        self.assertEqual(result, 'fail', memo)
        self.assertIn('호출 안 됨', memo)

    def test_deleting_someone_elses_poll_is_the_same_404_as_a_missing_one_and_the_poll_stays(self):
        outcome, a, b = self.go('E-POLL-20', steps('seen'), steps('seen'))
        self.answer(outcome, 'pass')
        delete = [s for s in self.world.sent if s['method'] == 'DELETE' and s['path'].startswith('/community/polls/') and s['auth'] == 'tok-1']
        self.assertEqual(len(delete), 1)  # 보는 사람(A)의 토큰으로 한 번
        self.assertEqual(a.job['question'], b.job['question'])

    def test_a_server_that_lets_the_viewer_delete_is_a_fail(self):
        def lenient(sent):
            self.world.tables['polls'] = []
            return Reply(204, None)
        self.world.handlers.insert(0, ('DELETE', re.compile(r'/community/polls/[^/]+'), lambda s: lenient(s) if s['auth'] == 'tok-1' else self.world.delete_poll(s)))
        outcome, a, b = self.go('E-POLL-20', steps('seen'), steps('seen'))
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('404', outcome[1])

    def test_a_poll_that_was_removed_even_though_the_server_said_404_is_a_fail(self):
        def quiet(sent):
            if sent['auth'] == 'tok-1':
                self.world.tables['polls'] = []
                return Reply(404, {'detail': NOT_FOUND})
            return self.world.delete_poll(sent)
        self.world.handlers.insert(0, ('DELETE', re.compile(r'/community/polls/[^/]+'), quiet))
        outcome, a, b = self.go('E-POLL-20', steps('seen'), steps('seen'))
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('남의 글이 지워짐', outcome[1])


class Poll21Test(Base):
    """A(id-1) = 글쓴이, B(id-2) = 열어 둔 사람. B 가 글을 띄운 뒤 PC 가 글쓴이 토큰으로 지운다."""

    def run21(self, **kw):
        def a_seen(job):
            time.sleep(0.4)  # A 가 느려도 PC 는 A 가 글을 띄운 것을 본 뒤에 지운다
            self.world.log.append('A-seen')

        return self.go('E-POLL-21', [('seen', a_seen), ('after', None)], steps('seen'), **kw)

    def test_the_author_deletes_after_a_has_the_poll_on_screen_and_the_deleted_poll_pays_nothing(self):
        outcome, a, b = self.run21()
        self.answer(outcome, 'pass')
        deletes = [s for s in self.world.sent if s['method'] == 'DELETE' and s['path'].startswith('/community/polls/')]
        self.assertEqual([s['auth'] for s in deletes], ['tok-1'])  # 글쓴이 토큰으로 한 번 — 끝 정리는 지울 글이 이미 없다
        self.assertLess(self.world.log.index('A-seen'), self.world.log.index('delete-id-1'))
        self.assertEqual(self.world.rows('polls'), [])
        self.assertEqual(a.job['question'], b.job['question'])

    def test_hearts_given_for_a_vote_on_the_deleted_poll_are_a_fail(self):
        def paid(job):
            self.world.rows('heart_transactions').append({'profile_id': 'id-2', 'amount': 10, 'reason': 'poll_vote', 'ref_id': 'x'})
        outcome, a, b = self.run21(b_finish=paid)
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('원장', outcome[1])

    def test_a_delete_the_author_could_not_make_is_blocked_not_a_pass(self):
        self.world.handlers.insert(0, ('DELETE', re.compile(r'/community/polls/[^/]+'), lambda s: Reply(500, {'detail': 'x'})))
        outcome, a, b = self.run21()
        self.assertEqual(outcome[0], 'blocked')
        self.assertIn('500', outcome[1])


class Poll22Test(Base):
    """A(id-1) = 글쓴이, B(id-2) = 보는 사람. 운영자가 글을 가린다(status=blinded)."""

    def run22(self, **kw):
        def a_seen(job):
            time.sleep(0.4)  # A 가 느려도 PC 는 A 가 글을 띄운 것을 본 뒤에 가린다
            self.world.log.append('A-seen')

        return self.go('E-POLL-22', [('seen', a_seen), ('after', None)], steps('detail'), **kw)

    def test_a_blinded_poll_is_not_found_by_vote_and_by_detail_and_gets_no_votes(self):
        outcome, a, b = self.run22()
        self.answer(outcome, 'pass')
        patches = [s for s in self.world.sent if s['method'] == 'PATCH' and s['path'] == '/rest/v1/polls']
        self.assertEqual([(s['body'], s['query']['id'].startswith('eq.poll-')) for s in patches], [({'status': 'blinded'}, True)])
        vote = [s for s in self.world.sent if s['path'].endswith('/votes')]
        self.assertEqual([(s['auth'], s['body']) for s in vote], [('tok-2', {'choice': 'a'})])  # 보는 사람(B)의 토큰
        self.assertEqual(self.votes(), [])
        self.assertEqual(self.world.once('POST', '/votes'), [{'retry': False}])
        self.assertEqual(self.world.rows('polls'), [])  # 가려진 글도 끝에 글쓴이가 지운다

    def test_a_server_that_still_takes_votes_on_a_blinded_poll_is_a_fail(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), Reply(200, {'poll': {}, 'rewarded': False})))
        outcome, a, b = self.run22()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('404', outcome[1])

    def test_a_detail_that_still_opens_is_a_fail(self):
        self.world.handlers.insert(0, ('GET', re.compile(r'/community/polls/[^/]+'), Reply(200, {'poll': {}})))
        outcome, a, b = self.run22()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('상세', outcome[1])

    def test_the_poll_is_blinded_only_after_a_has_it_on_screen(self):
        outcome, a, b = self.run22()
        self.answer(outcome, 'pass')
        self.assertLess(self.world.log.index('A-seen'), self.world.log.index('blinded'))


class Poll23Test(Base):
    """A(id-1) = 글쓴이(정지당함), B(id-2) = 보는 사람."""

    def run23(self, **kw):
        def a_seen(job):
            time.sleep(0.4)  # A 가 느려도 PC 는 A 가 글을 띄운 것을 본 뒤에 정지한다
            self.world.log.append('A-seen')

        return self.go('E-POLL-23', [('seen', a_seen)], steps('suspended', 'restored'), **kw)

    def test_the_author_is_suspended_then_restored_and_the_poll_is_deleted_at_the_end(self):
        outcome, a, b = self.run23()
        self.answer(outcome, 'pass')
        self.assertEqual(self.world.status_log, [('id-1', 'suspended'), ('id-1', 'active'), ('id-1', 'active')])  # 가설 중 정지 · 복원, 끝에 한 번 더(finally)
        self.assertEqual(self.world.rows('polls'), [])

    def test_an_app_that_stops_while_the_author_is_suspended_still_gets_the_author_back_and_the_poll_deleted(self):
        # B 가 'suspended' 에서 실패하면 'restored' 는 안 온다 — 끝에 계정을 active 로 되돌려야 글쓴이 토큰으로 글을 지울 수 있다.
        (result, memo), *_ = self.go('E-POLL-23', [('seen', None)], steps('suspended'), b_result=FAIL)
        self.assertEqual(result, 'fail', memo)
        self.assertEqual(self.world.status_of('id-1'), 'active')
        self.assertEqual(self.world.rows('polls'), [])

    def test_an_app_that_never_reaches_the_suspend_and_restore_steps_is_a_fail_not_a_pass(self):
        (result, memo), *_ = self.go('E-POLL-23', (), ())
        self.assertEqual(result, 'fail', memo)
        self.assertIn('정지', memo)

    def test_the_suspension_is_set_only_after_a_has_the_poll_on_screen(self):
        outcome, a, b = self.run23()
        self.answer(outcome, 'pass')
        self.assertLess(self.world.log.index('A-seen'), self.world.log.index('status-suspended'))

    def test_only_this_runs_author_is_ever_suspended(self):
        self.run23()
        self.assertEqual({who for who, _ in self.world.status_log}, {'id-1'})


class Poll29Test(Base):
    """A(id-1)와 B(id-2)가 각자 글이 있다. B 의 글(보이는 것 · 가려진 것)과 A 의 글에 A 의 토큰으로 신고를 보낸다."""

    def run29(self, **kw):
        return self.go('E-POLL-29', steps('checked'), steps('checked'), **kw)

    def reports(self):
        return [s for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/reports']

    def test_reporting_someone_elses_poll_is_accepted_and_my_own_and_a_blinded_one_are_404(self):
        outcome, a, b = self.run29()
        self.answer(outcome, 'pass')
        sent = self.reports()
        self.assertEqual(len(sent), 3)
        self.assertEqual({s['auth'] for s in sent}, {'tok-1'})
        self.assertEqual({s['body']['target_type'] for s in sent}, {'poll'})
        self.assertEqual({s['body']['reason'] for s in sent}, {'spam'})
        self.assertEqual(len({s['body']['target_id'] for s in sent}), 3)  # 남의 글 · 내 글 · 가려진 글 서로 다른 글
        self.assertEqual(self.world.rows('polls'), [])

    def test_the_two_apps_get_mirrored_jobs(self):
        outcome, a, b = self.run29()
        self.assertEqual((a.job['mine'], a.job['other']), (b.job['other'], b.job['mine']))
        self.assertNotEqual(a.job['mine'], a.job['other'])

    def test_a_server_that_takes_a_report_on_my_own_poll_is_a_fail(self):
        def lenient(sent):
            body = sent['body']
            if self.world.poll(body['target_id'])['author_id'] == self.world.caller(sent):
                return Reply(201, {'ok': True})
            return self.world.report(sent)
        self.world.handlers.insert(0, ('POST', re.compile(r'/reports'), lenient))
        outcome, a, b = self.run29()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('내 글', outcome[1])

    def test_a_server_that_takes_a_report_on_a_blinded_poll_is_a_fail(self):
        def lenient(sent):
            if self.world.poll(sent['body']['target_id'])['status'] == 'blinded':
                return Reply(201, {'ok': True})
            return self.world.report(sent)
        self.world.handlers.insert(0, ('POST', re.compile(r'/reports'), lenient))
        outcome, a, b = self.run29()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('가려진 글', outcome[1])

    def test_a_report_that_also_blocks_or_hides_is_a_fail(self):
        original = self.world.report

        def block_too(sent):
            reply = original(sent)
            if reply[0] == 201:
                self.world.rows('blocks').append({'blocker_id': self.world.caller(sent), 'blocked_id': 'id-2'})
            return reply
        self.world.handlers.insert(0, ('POST', re.compile(r'/reports'), block_too))
        outcome, a, b = self.run29()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('blocks', outcome[1])

    def test_an_author_that_got_auto_hidden_is_a_fail(self):
        original = self.world.report

        def hide(sent):
            reply = original(sent)
            if reply[0] == 201:
                self.world.profile('id-2')['auto_hidden_at'] = '2026-10-05T00:00:00+00:00'
            return reply
        self.world.handlers.insert(0, ('POST', re.compile(r'/reports'), hide))
        outcome, a, b = self.run29()
        self.assertEqual(outcome[0], 'fail')
        self.assertIn('auto_hidden_at', outcome[1])

    def test_the_reports_are_sent_once_each_and_never_resent_after_a_cut_connection(self):
        self.run29()
        self.assertEqual(self.world.once('POST', '/reports'), [{'retry': False}] * 3)


if __name__ == '__main__':
    unittest.main()
