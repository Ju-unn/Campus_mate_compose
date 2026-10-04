"""영역 2 폰 A 2차 18(투표 9 · 하트 제출 흐름 8 · 카드 상세 1)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_phone_b`.

가짜 서버 [World] 는 e2e/test_area3.py 의 Fake(표를 메모리에 든다)에 투표 · 하트 제출 · 온보딩 API 를 얹은 것이다.
가짜 앱 [App] 은 받은 일감을 남기고, 앱이 실제로 DB 에 남길 일([EFFECTS])을 흉내 낸 뒤 시험이 정한 말을 돌려준다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 …(폰 계정이 늘 먼저다).

가설마다 일감에 무엇을 싣는지 · DB 준비 값 · 앱이 pass 면 통과 · fail/blocked 면 그 결과 · 말이 없으면 fail 을 본다."""

import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from e2e import area1, area2_phone_b, tools
from e2e.test_area1 import CFG
from e2e.test_area3 import Fake
from e2e.tools import Reply, Run

BUNDLE = ('E-POLL-01 E-POLL-13 E-POLL-14 E-POLL-15 E-POLL-18 E-POLL-25 E-POLL-26 E-POLL-27 E-POLL-31 '
          'E-HEART-04 E-HEART-05 E-HEART-09 E-HEART-12 E-HEART-13 E-HEART-14 E-HEART-16 E-HEART-21 E-CARD-90').split()
POLLS = [c for c in BUNDLE if c.startswith('E-POLL')]
PASS = {'result': 'pass'}
THUMB = '\U0001F44D'
DAILY_LIMIT = '오늘은 질문을 더 올릴 수 없어요'
MONTHLY_LIMIT = '이번 달에는 더 인증할 수 없어요'
SEOUL = area1.SEOUL


class World(Fake):
    """표 저장소 + 투표 · 하트 제출 · 온보딩 서버. 규칙은 가설이 기대하는 서버(시나리오)대로 흉내 낸다."""

    LIMIT = {'everytime_post': 1, 'kakao_share': 3}
    REWARD = {'everytime_post': 50, 'kakao_share': 25}
    STEP_COLUMNS = {'interests': ('interest_tags', 'tags'), 'my-traits': ('my_traits', 'tags'),
                    'ideal-traits': ('ideal_traits', 'tags'), 'ideal-note': ('ideal_note', 'note'), 'bio': ('bio', 'bio')}

    def __init__(self):
        super().__init__()
        self.files, self.counter, self.inserted = [], 0, []
        self.tables['universities'] = [{'id': 'U', 'name': '테스트대학', 'card_opens_at': None}]
        for method, pattern, reply in (
            ('POST', r'/community/polls', self.create_poll),
            ('DELETE', r'/community/polls/[^/]+', self.delete_poll),
            ('POST', r'/heart-tasks/[^/]+/submissions', self.submit),
            ('POST', r'/rest/v1/heart_task_submissions', self.insert_submission),
            ('PATCH', r'/rest/v1/heart_task_submissions', self.review),
            ('POST', r'/rest/v1/rpc/grant_hearts', self.grant),
            ('GET', r'/rest/v1/entitlements', self.balance),
            ('GET', r'/rest/v1/polls', self.read_polls),
            ('POST', r'/storage/v1/object/list/heart-task-proofs', self.listing),
            ('POST', r'/profile-onboarding/[^/]+', self.onboarding),
            ('POST', r'/school-info', self.school_info),
            ('PATCH', r'/rest/v1/profiles', self.patch_profile),
        ):
            self.on(method, pattern, reply)

    # 도우미 ------------------------------------------------------------------------------------
    def rows(self, table):
        return self.tables.setdefault(table, [])

    def next_id(self, prefix):
        self.counter += 1
        return f'{prefix}-{self.counter}'

    @staticmethod
    def caller(sent):
        return 'id-' + sent['auth'].removeprefix('tok-')

    def profile(self, pid):
        found = next((r for r in self.rows('profiles') if r['id'] == pid), None)
        if found is None:
            found = {'id': pid}
            self.rows('profiles').append(found)
        return found

    def add_poll(self, author, question, a='찬성', b='반대'):
        poll = {'id': self.next_id('poll'), 'author_id': author, 'question': question, 'option_a_label': a, 'option_b_label': b}
        self.rows('polls').append(poll)
        return poll

    def vote(self, voter, question, choice='a'):
        poll = next(p for p in self.rows('polls') if p['question'] == question)
        self.rows('poll_votes').append({'poll_id': poll['id'], 'voter_id': voter, 'choice': choice})

    def add_submission(self, who, task, status='submitted', created_at=None):
        sid = self.next_id('sub')
        row = {'id': sid, 'profile_id': who, 'task': task, 'status': status, 'reward_hearts': self.REWARD[task],
               'storage_path': f'{who}/{sid}.jpg', 'reject_reason': None, 'created_at': created_at}
        self.rows('heart_task_submissions').append(row)
        self.files.append(row['storage_path'])
        return row

    # 투표 ------------------------------------------------------------------------------------
    def create_poll(self, sent):
        who, body = self.caller(sent), sent['body']
        question = body['question']
        a, b = body.get('option_a_label', '찬성'), body.get('option_b_label', '반대')
        if (not 1 <= len(question) <= 80 or not question.strip() or not 1 <= len(a) <= 6 or not 1 <= len(b) <= 6
                or not a.strip() or not b.strip() or a == b):
            return Reply(422, {'detail': '입력한 값을 다시 확인해 주세요'})
        if len([p for p in self.rows('polls') if p['author_id'] == who]) >= 10:
            return Reply(429, {'detail': DAILY_LIMIT})
        return Reply(201, {'id': self.add_poll(who, question.strip(), a, b)['id']})

    def delete_poll(self, sent):
        who, pid = self.caller(sent), sent['path'].rsplit('/', 1)[1]
        mine = [p for p in self.rows('polls') if p['id'] == pid and p['author_id'] == who]
        if not mine:
            return Reply(404, {'detail': '질문을 찾을 수 없어요'})
        self.tables['polls'] = [p for p in self.rows('polls') if p not in mine]
        return Reply(204, None)

    def read_polls(self, sent):
        if 'limit' in sent['query']:  # PC 가 건수를 셀 때(Prefer count=exact) — 본문은 안 보고 Content-Range 만 본다
            return Reply(200, [], {'Content-Range': f"0-0/{len(self.rows('polls'))}"})
        return self._table('GET', 'polls', sent)

    # 하트 ------------------------------------------------------------------------------------
    def submit(self, sent):
        who, task = self.caller(sent), sent['path'].split('/')[2]
        mine = [r for r in self.rows('heart_task_submissions') if r['profile_id'] == who and r['task'] == task]
        if any(r['status'] == 'submitted' for r in mine):
            return Reply(409, {'detail': '이미 확인 중이에요, 결과를 기다려 주세요'})
        if len([r for r in mine if r['status'] in ('submitted', 'approved')]) >= self.LIMIT[task]:
            return Reply(429, {'detail': MONTHLY_LIMIT})
        self.add_submission(who, task)
        return Reply(201, {'task': {'task': task}})

    def insert_submission(self, sent):
        self.inserted += [dict(row) for row in sent['body']]  # 넣은 그대로(뒤 승인으로 줄이 바뀌기 전)를 남긴다
        return self._table('POST', 'heart_task_submissions', sent)

    def review(self, sent):
        sid, body = sent['query']['id'].removeprefix('eq.'), sent['body']
        row = next((r for r in self.rows('heart_task_submissions') if r['id'] == sid), None)
        if row is None:
            return Reply(204, None)
        if row['status'] != 'submitted' and body.get('status', row['status']) != row['status']:
            return Reply(400, {'code': 'CM409', 'message': 'heart task submission already reviewed'})
        was = row['status']
        row.update({k: v for k, v in body.items()})
        if was == 'submitted' and row['status'] == 'approved':
            self.rows('heart_transactions').append({'profile_id': row['profile_id'], 'amount': row['reward_hearts'],
                                                    'reason': 'free_task', 'ref_id': sid})
        return Reply(204, None)

    def grant(self, sent):
        body = sent['body']
        self.rows('heart_transactions').append({'profile_id': body['p_profile_id'], 'amount': body['p_amount'],
                                                'reason': body['p_reason'], 'ref_id': body['p_ref_id']})
        return Reply(200, None)

    def balance(self, sent):
        pid = sent['query']['profile_id'].removeprefix('eq.')
        return Reply(200, [{'heart_balance': sum(r['amount'] for r in self.rows('heart_transactions') if r['profile_id'] == pid)}])

    def listing(self, sent):
        prefix = sent['body']['prefix']
        return Reply(200, [{'id': 'f', 'name': p.split('/', 1)[1]} for p in self.files if p.startswith(prefix + '/')])

    # 온보딩 · 프로필 ----------------------------------------------------------------------------
    def onboarding(self, sent):
        who, step, body = self.caller(sent), sent['path'].rsplit('/', 1)[1], sent['body'] or {}
        row = self.profile(who)
        if step == 'basic-info':
            row.update({k: body[k] for k in ('nickname', 'height_cm', 'gender', 'mbti') if k in body})
        elif step in self.STEP_COLUMNS:
            column, key = self.STEP_COLUMNS[step]
            row[column] = body[key]
        elif step == 'appearance-type':
            row.update(animal_type=body['animal_type'], impression_type=body['impression_type'])
        elif step == 'survey':
            row.update(religion=body['religion'], is_smoker=body['is_smoker'])
            for axis, value in body['answers'].items():
                self.rows('survey_answers').append({'profile_id': who, 'axis': int(axis), 'value': value})
        return Reply(200, None)

    def school_info(self, sent):
        self.profile(self.caller(sent)).update(student_number=sent['body']['student_number'], major=sent['body']['department'])
        return Reply(200, None)

    def patch_profile(self, sent):
        self.profile(sent['query']['id'].removeprefix('eq.')).update(sent['body'])
        return Reply(204, None)


class App:
    """앱 대신 — 받은 일감을 [jobs] 에 남기고, midway 를 부르고, 앱이 DB 에 남길 일([effect])을 한 뒤 [answers] 를 차례로(마지막은 계속) 말한다."""

    def __init__(self, world, effect=None, *answers, serial=None):
        self.world, self.effect, self.answers, self.jobs, self.serial = world, effect, list(answers) or [PASS], [], serial

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if midway:
            midway({'step': 'x'})
        if self.effect:
            self.effect(self.world, job)
        return self.answers.pop(0) if len(self.answers) > 1 else self.answers[0]


# 가설마다 앱이 실제로 서버에 남기는 일 — 일감을 받은 뒤 한 번씩.
EFFECTS = {
    'E-POLL-01': lambda w, job: w.add_poll('id-1', job['question']),
    'E-POLL-13': lambda w, job: w.vote('id-1', job['question']),
    'E-POLL-14': lambda w, job: w.add_poll('id-1', job['tenth']),
    'E-POLL-15': lambda w, job: w.add_poll('id-1', job['question']),
    'E-POLL-31': lambda w, job: w.add_poll('id-1', job['base'] + THUMB),
    'E-HEART-04': lambda w, job: w.add_submission('id-1', 'everytime_post'),
    'E-HEART-05': lambda w, job: w.add_submission('id-1', 'everytime_post'),
    'E-HEART-14': lambda w, job: w.add_submission('id-1', 'everytime_post'),
}


class PhoneBase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area2-phone-b', 'b', cfg={**CFG}, key='svc')
        self.world = World()
        for patcher in (mock.patch.object(tools, 'call', self.world), mock.patch.object(tools, 'screencap', return_value=b''),
                        mock.patch.object(area2_phone_b.time, 'sleep')):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.sleeps = area2_phone_b.time.sleep

    def attempt(self, case, app=None):
        return area1.attempt_phone(self.run_, case, app or self.app(case))

    def app(self, case, *answers, **kw):
        return App(self.world, EFFECTS.get(case), *answers, **kw)


class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_18_in_order_and_every_case_is_a_phone_case(self):
        self.assertEqual(area1.BUNDLES['area2-phone-b'], BUNDLE)
        self.assertEqual(list(area2_phone_b.PHONE_B), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area2_phone_b 를 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area2-phone-b"), "E-POLL-01" in area1.PHONE)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{BUNDLE} True')


class AppAnswerTest(PhoneBase):
    """모든 가설 — 앱의 pass 는 pass, fail 은 메모를 남긴 fail, blocked 는 blocked, 말이 없으면 fail."""

    def fresh(self):
        self.setUp()

    def test_app_pass_is_pass(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.fresh()
                outcome = self.attempt(case)
                self.assertEqual(outcome[0], 'pass', outcome)

    def test_app_fail_is_fail_and_keeps_the_note(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.fresh()
                result, note = self.attempt(case, self.app(case, {'result': 'fail', 'note': '글자 없음'}))
                self.assertEqual(result, 'fail')
                self.assertIn('글자 없음', note)

    def test_app_blocked_is_blocked(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.fresh()
                self.assertEqual(self.attempt(case, self.app(case, {'result': 'blocked', 'note': '대기 화면'}))[0], 'blocked')

    def test_app_silence_is_fail(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.fresh()
                self.assertEqual(self.attempt(case, self.app(case, None))[0], 'fail')

    def test_first_job_signs_the_app_in_with_a_one_time_token_and_later_jobs_keep_the_session(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.fresh()
                app = self.app(case)
                self.attempt(case, app)
                self.assertEqual(app.jobs[0]['token_hash'], 'h')
                self.assertTrue(all(job.get('fresh') is False and 'token_hash' not in job for job in app.jobs[1:]))

    def test_every_poll_a_case_made_is_deleted_by_its_author_even_when_the_app_fails(self):
        for case in POLLS:
            with self.subTest(case):
                self.fresh()
                self.attempt(case, self.app(case, {'result': 'fail', 'note': 'x'}))
                self.assertEqual(self.world.rows('polls'), [])
                self.fresh()
                self.attempt(case)
                self.assertEqual(self.world.rows('polls'), [])


class PollPostTest(PhoneBase):
    def test_poll_01_one_row_with_the_typed_question_and_default_options(self):
        app = self.app('E-POLL-01')
        self.assertEqual(self.attempt('E-POLL-01', app)[0], 'pass')
        self.assertTrue(app.jobs[0]['question'].startswith('[E2E] '))

    def test_poll_01_two_rows_or_a_different_question_fail(self):
        def twice(world, job):
            world.add_poll('id-1', job['question'])
            world.add_poll('id-1', job['question'])
        self.assertEqual(self.attempt('E-POLL-01', App(self.world, twice))[0], 'fail')
        self.setUp()
        self.assertEqual(self.attempt('E-POLL-01', App(self.world, lambda w, job: w.add_poll('id-1', '다른 글')))[0], 'fail')
        self.setUp()
        self.assertEqual(self.attempt('E-POLL-01', App(self.world, lambda w, job: w.add_poll('id-1', job['question'], '예', '아니오')))[0], 'fail')

    def test_poll_01_no_row_fails(self):
        result, note = self.attempt('E-POLL-01', App(self.world))
        self.assertEqual(result, 'fail')
        self.assertIn('polls', note)

    def test_poll_14_nine_are_posted_before_the_app_and_the_eleventh_is_not_saved(self):
        seen = []

        def effect(world, job):
            seen.append(len(world.rows('polls')))  # 앱이 켜지기 전 준비
            EFFECTS['E-POLL-14'](world, job)

        app = App(self.world, effect)
        self.assertEqual(self.attempt('E-POLL-14', app)[0], 'pass')
        self.assertEqual(seen, [9])
        self.assertTrue(app.jobs[0]['tenth'].startswith('[E2E] '))
        self.assertNotEqual(app.jobs[0]['tenth'], app.jobs[0]['eleventh'])

    def test_poll_14_the_eleventh_saved_is_a_fail(self):
        def both(world, job):
            world.add_poll('id-1', job['tenth'])
            world.add_poll('id-1', job['eleventh'])
        result, note = self.attempt('E-POLL-14', App(self.world, both))
        self.assertEqual(result, 'fail')
        self.assertIn('11', note)

    def test_poll_14_the_tenth_missing_is_a_fail(self):
        result, note = self.attempt('E-POLL-14', App(self.world))
        self.assertEqual(result, 'fail')
        self.assertIn('9', note)

    def test_poll_14_a_server_that_accepts_a_twelfth_is_a_fail(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls'), lambda sent: Reply(201, {'id': 'x'})
                                       if self.world.rows('polls') and len(self.world.rows('polls')) >= 10 else self.world.create_poll(sent)))
        result, note = self.attempt('E-POLL-14')
        self.assertEqual(result, 'fail')
        self.assertIn('429', note)

    def test_poll_15_ten_are_full_one_is_deleted_before_the_app_posts(self):
        seen = []

        def effect(world, job):
            seen.append(len(world.rows('polls')))
            EFFECTS['E-POLL-15'](world, job)

        self.assertEqual(self.attempt('E-POLL-15', App(self.world, effect))[0], 'pass')
        self.assertEqual(seen, [9])
        # "10개 찬 상태" 는 11번째가 막히는 것으로 확인한다 — 글 올리기 요청이 10 + 1(막힌 것).
        posts = [s for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/community/polls']
        self.assertEqual(len(posts), 11)

    def test_poll_15_a_full_day_that_was_not_full_is_a_fail(self):
        # 서버가 11번째를 받아 주면 "10개 찬 상태" 를 만들지 못한 것이다 — 준비가 어긋났다는 메모가 남는다.
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls'), lambda sent: Reply(201, {'id': 'x'})
                                       if len([p for p in self.world.rows('polls') if p['author_id'] == self.world.caller(sent)]) >= 10
                                       else self.world.create_poll(sent)))
        result, note = self.attempt('E-POLL-15')
        self.assertEqual(result, 'fail')
        self.assertIn('429', note)

    def test_poll_15_the_deleted_one_is_gone_by_its_author(self):
        self.attempt('E-POLL-15')
        deletes = [s for s in self.world.sent if s['method'] == 'DELETE' and s['path'].startswith('/community/polls/')]
        self.assertEqual(deletes[0]['auth'], 'tok-1')  # 글쓴이 본인의 토큰으로 지운다

    def test_poll_18_four_api_calls_all_422_and_nothing_is_saved(self):
        self.assertEqual(self.attempt('E-POLL-18')[0], 'pass')
        bodies = [s['body'] for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/community/polls']
        self.assertEqual(len(bodies), 4)
        lengths = sorted(len(b['question']) for b in bodies)
        self.assertIn(81, lengths)
        self.assertTrue(any(len(b.get('option_a_label', '')) == 7 for b in bodies))
        self.assertTrue(any(not b['question'].strip() for b in bodies))
        self.assertTrue(any(b.get('option_a_label') and b.get('option_a_label') == b.get('option_b_label') for b in bodies))

    def test_poll_18_a_server_that_accepts_one_is_a_fail_with_its_name(self):
        def lenient(sent):
            if len(sent['body']['question']) == 81:
                return Reply(201, {'id': self.world.add_poll(self.world.caller(sent), sent['body']['question'])['id']})
            return self.world.create_poll(sent)
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls'), lenient))
        result, note = self.attempt('E-POLL-18')
        self.assertEqual(result, 'fail')
        self.assertIn('질문 81자', note)
        self.assertIn('polls', note)

    def test_poll_31_eighty_code_points_cut_at_the_thumb_pass(self):
        app = self.app('E-POLL-31')
        self.assertEqual(self.attempt('E-POLL-31', app)[0], 'pass')
        self.assertEqual(len(app.jobs[0]['base']), 79)
        self.assertTrue(app.jobs[0]['base'].startswith('[E2E] '))

    def test_poll_31_a_stored_question_that_is_not_80_or_lost_its_thumb_fails(self):
        for stored in ('a' * 81, 'a' * 79, 'a' * 79 + 'b'):
            with self.subTest(stored[-2:] + str(len(stored))):
                self.setUp()
                result, note = self.attempt('E-POLL-31', App(self.world, lambda w, job, s=stored: w.add_poll('id-1', s)))
                self.assertEqual(result, 'fail')


class PollReadTest(PhoneBase):
    def test_poll_13_the_author_votes_on_their_own_poll(self):
        app = self.app('E-POLL-13')
        self.assertEqual(self.attempt('E-POLL-13', app)[0], 'pass')
        self.assertEqual(app.jobs[0]['question'], '[E2E] 작성자 투표')

    def test_poll_13_no_vote_row_or_a_stranger_vote_fails(self):
        self.assertEqual(self.attempt('E-POLL-13', App(self.world))[0], 'fail')
        self.setUp()
        self.assertEqual(self.attempt('E-POLL-13', App(self.world, lambda w, job: w.vote('id-9', job['question'])))[0], 'fail')
        self.setUp()
        self.assertEqual(self.attempt('E-POLL-13', App(self.world, lambda w, job: w.vote('id-1', job['question'], 'b')))[0], 'fail')

    def test_poll_25_three_accounts_post_10_10_5_into_an_empty_feed(self):
        seen = []
        app = App(self.world, lambda w, job: seen.append(sorted(
            (a, len([p for p in w.rows('polls') if p['author_id'] == a])) for a in ('id-1', 'id-2', 'id-3'))))
        self.assertEqual(self.attempt('E-POLL-25', app)[0], 'pass')
        self.assertEqual(seen, [[('id-1', 10), ('id-2', 10), ('id-3', 5)]])

    def test_poll_25_posts_carry_the_e2e_prefix(self):
        self.attempt('E-POLL-25')
        questions = [s['body']['question'] for s in self.world.sent if s['method'] == 'POST' and s['path'] == '/community/polls']
        self.assertEqual(len(questions), 25)
        self.assertEqual(len(set(questions)), 25)
        self.assertTrue(all(q.startswith('[E2E] ') for q in questions))

    def test_poll_25_a_feed_that_already_has_polls_is_blocked_before_any_account(self):
        self.world.add_poll('id-9', '남의 글')
        app = App(self.world)
        result, note = self.attempt('E-POLL-25', app)
        self.assertEqual(result, 'blocked')
        self.assertIn('1', note)
        self.assertEqual(app.jobs, [])
        self.assertEqual(self.world.users, [])

    def test_poll_26_one_poll_is_prepared_for_the_detail_screen(self):
        seen = []
        app = App(self.world, lambda w, job: seen.append([p['question'] for p in w.rows('polls')]))
        self.assertEqual(self.attempt('E-POLL-26', app)[0], 'pass')
        self.assertEqual(seen, [[app.jobs[0]['question']]])
        self.assertTrue(app.jobs[0]['question'].startswith('[E2E] '))

    def test_poll_27_the_poll_has_its_own_option_labels(self):
        seen = []
        app = App(self.world, lambda w, job: seen.append([(p['question'], p['option_a_label'], p['option_b_label']) for p in w.rows('polls')]))
        self.assertEqual(self.attempt('E-POLL-27', app)[0], 'pass')
        job = app.jobs[0]
        self.assertEqual((job['a'], job['b']), ('짜장', '짬뽕'))
        self.assertEqual(seen, [[(job['question'], '짜장', '짬뽕')]])

    def test_poll_27_a_prepared_poll_that_was_refused_is_blocked(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls'), Reply(422, {'detail': '안 됨'})))
        app = App(self.world)
        self.assertEqual(self.attempt('E-POLL-27', app)[0], 'blocked')
        self.assertEqual(app.jobs, [])


class SubmitFlowTest(PhoneBase):
    def rows(self):
        return self.world.rows('heart_task_submissions')

    def test_heart_04_one_submitted_row_50_hearts_and_a_proof_file_at_the_documented_path(self):
        self.assertEqual(self.attempt('E-HEART-04')[0], 'pass')
        self.assertEqual([(r['status'], r['task'], r['reward_hearts']) for r in self.rows()], [('submitted', 'everytime_post', 50)])
        self.assertEqual(self.world.files, [f"id-1/{self.rows()[0]['id']}.jpg"])

    def test_heart_04_wrong_row_or_missing_file_fails(self):
        for label, effect in (
            ('두 행', lambda w, job: [w.add_submission('id-1', 'everytime_post') for _ in range(2)]),
            ('단톡방', lambda w, job: w.add_submission('id-1', 'kakao_share')),
            ('이미 승인', lambda w, job: w.add_submission('id-1', 'everytime_post', 'approved')),
            ('행 없음', lambda w, job: None),
            ('파일 없음', lambda w, job: (w.add_submission('id-1', 'everytime_post'), w.files.clear())),
            ('경로 다름', lambda w, job: w.add_submission('id-1', 'everytime_post').update(storage_path='id-1/x.png')),
        ):
            with self.subTest(label):
                self.setUp()
                result, note = self.attempt('E-HEART-04', App(self.world, effect))
                self.assertEqual(result, 'fail')
                self.assertTrue(note)

    def test_heart_05_after_going_back_the_row_is_still_one_submitted_row(self):
        self.assertEqual(self.attempt('E-HEART-05')[0], 'pass')
        self.setUp()
        result, note = self.attempt('E-HEART-05', App(self.world, lambda w, job: w.add_submission('id-1', 'everytime_post', 'approved')))
        self.assertEqual(result, 'fail')

    def test_heart_09_approval_happens_while_the_app_is_stopped_and_gives_50_once(self):
        app = self.app('E-HEART-09')
        self.assertEqual(self.attempt('E-HEART-09', app)[0], 'pass')
        ledger = self.world.rows('heart_transactions')
        self.assertEqual([(r['amount'], r['reason'], r['ref_id']) for r in ledger], [(50, 'free_task', self.rows()[0]['id'])])
        self.assertEqual(self.rows()[0]['status'], 'approved')
        self.assertEqual(app.jobs[0]['token_hash'], 'h')

    def test_heart_09_waits_out_the_60_seconds_before_the_second_notification_read(self):
        self.attempt('E-HEART-09')
        waited = [call.args[0] for call in self.sleeps.call_args_list]
        self.assertEqual(len(waited), 1)
        self.assertTrue(55 <= waited[0] <= 60, waited)

    def test_heart_09_a_new_notification_in_the_window_fails_and_old_ones_do_not(self):
        old = 'NotificationRecord(pkg=io.github.juunn.campusmate ...)\n  android.title=String (친구가 가입했어요)\n  android.text=String (Abcde 님이 가입했어요)'
        new = old + '\nNotificationRecord(pkg=io.github.juunn.campusmate ...)\n  android.title=String (하트가 들어왔어요)'
        reads = [old, new]
        with mock.patch.object(tools, 'adb', side_effect=lambda *a, **k: reads.pop(0)):
            result, note = self.attempt('E-HEART-09', self.app('E-HEART-09', serial='S'))
        self.assertEqual(result, 'fail')
        self.assertIn('하트가 들어왔어요', note)
        self.setUp()
        with mock.patch.object(tools, 'adb', return_value=old):
            self.assertEqual(self.attempt('E-HEART-09', self.app('E-HEART-09', serial='S'))[0], 'pass')

    def test_heart_09_notification_dump_only_reads_our_app(self):
        other = 'NotificationRecord(pkg=com.kakao.talk ...)\n  android.title=String (홍길동)\n  android.text=String (비밀 내용)'
        reads = ['', other]
        with mock.patch.object(tools, 'adb', side_effect=lambda *a, **k: reads.pop(0)):
            self.assertEqual(self.attempt('E-HEART-09', self.app('E-HEART-09', serial='S'))[0], 'pass')

    def test_heart_09_ledger_with_two_rows_or_a_wrong_balance_fails(self):
        def twice(world, job):
            world.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': 50, 'reason': 'free_task', 'ref_id': 'zzz'})
        result, note = self.attempt('E-HEART-09', App(self.world, twice))
        self.assertEqual(result, 'fail')
        self.assertIn('원장', note)

    def test_heart_09_a_ledger_row_that_points_at_another_submission_fails(self):
        def other_ref(world, job):
            world.rows('heart_transactions')[0]['ref_id'] = 'another-submission'
        result, note = self.attempt('E-HEART-09', App(self.world, other_ref))
        self.assertEqual(result, 'fail')
        self.assertIn('원장', note)

    def test_heart_09_the_app_that_never_stops_is_a_fail(self):
        class Quick(App):
            def __call__(self, midway=None, **job):  # midway 를 부르지 않고 바로 끝낸다
                self.jobs.append(job)
                return PASS
        result, note = self.attempt('E-HEART-09', Quick(self.world))
        self.assertEqual(result, 'fail')
        self.assertIn('멈추지', note)

    def test_heart_12_one_reviewing_row_is_rejected_with_date_missing_in_one_save(self):
        app = self.app('E-HEART-12')
        self.assertEqual(self.attempt('E-HEART-12', app)[0], 'pass')
        self.assertEqual([(r['status'], r['reject_reason']) for r in self.rows()], [('rejected', 'date_missing')])
        saves = [s['body'] for s in self.world.sent if s['method'] == 'PATCH' and s['path'] == '/rest/v1/heart_task_submissions']
        self.assertEqual(len(saves), 1)
        self.assertEqual((saves[0]['status'], saves[0]['reject_reason']), ('rejected', 'date_missing'))

    def test_heart_13_three_reasons_each_prepared_before_its_own_job(self):
        seen = []
        app = App(self.world, lambda w, job: seen.append((job['reason'], [r['reject_reason'] for r in w.rows('heart_task_submissions')])))
        self.assertEqual(self.attempt('E-HEART-13', app)[0], 'pass')
        self.assertEqual(seen, [('date_missing', ['date_missing']),
                                ('not_verified', ['date_missing', 'not_verified']),
                                ('reused', ['date_missing', 'not_verified', 'reused'])])
        self.assertEqual([j.get('fresh') for j in app.jobs], [None, False, False])

    def test_heart_13_a_failing_middle_job_is_named_by_its_reason(self):
        app = self.app('E-HEART-13', PASS, {'result': 'fail', 'note': '문구 다름'}, PASS)
        result, note = self.attempt('E-HEART-13', app)
        self.assertEqual(result, 'fail')
        self.assertIn('not_verified', note)
        self.assertIn('문구 다름', note)
        self.assertEqual(len(app.jobs), 3)  # 한 번 어긋나도 나머지 사유를 계속 본다

    def test_heart_14_a_rejected_one_then_a_new_submitted_row(self):
        self.assertEqual(self.attempt('E-HEART-14')[0], 'pass')
        self.assertEqual(sorted(r['status'] for r in self.rows()), ['rejected', 'submitted'])

    def test_heart_14_no_new_row_or_a_second_rejected_one_fails(self):
        self.assertEqual(self.attempt('E-HEART-14', App(self.world))[0], 'fail')
        self.setUp()
        self.assertEqual(self.attempt('E-HEART-14', App(self.world, lambda w, job: w.add_submission('id-1', 'everytime_post', 'rejected')))[0], 'fail')

    def test_heart_16_three_approved_this_month_pay_25_each_and_the_fourth_is_429(self):
        self.assertEqual(self.attempt('E-HEART-16')[0], 'pass')
        rows = self.rows()
        self.assertEqual([(r['task'], r['status']) for r in rows], [('kakao_share', 'approved')] * 3)
        self.assertEqual([r['amount'] for r in self.world.rows('heart_transactions')], [25, 25, 25])
        month_start = datetime.now(SEOUL).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        for row in rows:  # 이번 달 안(한국 시간)이고 지금보다 늦지 않아야 한도에 센다
            created = datetime.fromisoformat(row['created_at'])
            self.assertTrue(month_start <= created <= datetime.now(SEOUL) + timedelta(seconds=5), row['created_at'])
        fourth = [s for s in self.world.sent if s['path'] == '/heart-tasks/kakao_share/submissions']
        self.assertEqual(len(fourth), 1)

    def test_heart_16_the_rows_are_inserted_in_the_past_one_at_a_time_never_two_reviewing_together(self):
        self.attempt('E-HEART-16')
        inserts = self.world.inserted
        self.assertEqual(len(inserts), 3)
        self.assertEqual({row['status'] for row in inserts}, {'submitted'})  # 검수 중 줄은 하나씩만 — 곧바로 승인한다
        now = datetime.now(SEOUL)
        self.assertTrue(all(datetime.fromisoformat(row['created_at']) < now for row in inserts))  # 과거 시각
        order = [(s['method'], s['path']) for s in self.world.sent if s['path'] == '/rest/v1/heart_task_submissions']
        self.assertEqual(order, [('POST', '/rest/v1/heart_task_submissions'), ('PATCH', '/rest/v1/heart_task_submissions')] * 3)

    def test_heart_16_a_server_that_accepts_the_fourth_fails(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/heart-tasks/kakao_share/submissions'), Reply(201, {'task': {}})))
        result, note = self.attempt('E-HEART-16')
        self.assertEqual(result, 'fail')
        self.assertIn('4번째', note)

    def test_heart_16_a_ledger_that_is_not_25_three_times_fails(self):
        original = self.world.review

        def no_ledger(sent):
            reply = original(sent)
            self.world.tables['heart_transactions'] = []
            return reply
        self.world.handlers.insert(0, ('PATCH', re.compile(r'/rest/v1/heart_task_submissions'), no_ledger))
        result, note = self.attempt('E-HEART-16')
        self.assertEqual(result, 'fail')
        self.assertIn('원장', note)

    def test_heart_21_two_votes_then_three_each_with_its_own_app_start(self):
        seen = []
        app = App(self.world, lambda w, job: seen.append((job['expect'], len([r for r in w.rows('heart_transactions') if r['reason'] == 'poll_vote']))))
        self.assertEqual(self.attempt('E-HEART-21', app)[0], 'pass')
        self.assertEqual(seen, [('open', 2), ('done', 3)])
        self.assertEqual([j.get('fresh') for j in app.jobs], [None, False])
        self.assertEqual([r['amount'] for r in self.world.rows('heart_transactions')], [10, 10, 10])

    def test_heart_21_a_refused_ledger_credit_is_blocked(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/rest/v1/rpc/grant_hearts'), Reply(400, {'code': '22023'})))
        app = App(self.world)
        self.assertEqual(self.attempt('E-HEART-21', app)[0], 'blocked')
        self.assertEqual(app.jobs, [])


class CardDetailTest(PhoneBase):
    SURVEY = [-1, -0.5, 0, 0.5, 1, -1, -0.5, 0.5, 1]

    def test_card_90_two_people_one_full_one_with_dashes_expected_values_come_from_the_db(self):
        app = self.app('E-CARD-90')
        self.assertEqual(self.attempt('E-CARD-90', app)[0], 'pass')
        full, sparse = app.jobs[0]['people']
        sn = {p['id']: p['student_number'] for p in self.world.rows('profiles') if 'student_number' in p}
        self.assertEqual(full['facts'], [['키', '172cm'], ['MBTI', 'INTJ'], ['학번', f"{sn['id-2']}학번"], ['종교', '천주교'], ['흡연', '흡연']])
        self.assertEqual(full['look'], ['고양이상', '시크상'])
        self.assertEqual(full['survey'], self.SURVEY)
        self.assertEqual(sparse['facts'], [['키', '170cm'], ['MBTI', '—'], ['학번', '—'], ['종교', '무교'], ['흡연', '비흡연']])
        self.assertEqual(sparse['look'], ['강아지상', '선한상'])
        self.assertEqual(sparse['survey'], [0.5] * 9)
        self.assertEqual(sparse['tags'], {'관심사': ['카페가기', '자전거', '패션'], '특징': ['깨끗한 피부', '좋은 비율', '달달한 목소리'],
                                          '이상형 특징': ['연상', '연하', '동갑']})
        self.assertEqual((sparse['bio'], sparse['note']), (None, None))
        self.assertTrue(full['bio'] and full['note'])  # 계정 공장이 채운 값을 DB 에서 읽은 것
        self.assertEqual(full['nickname'], self.world.profile('id-2')['nickname'])
        self.assertNotEqual(full['nickname'], sparse['nickname'])

    def test_card_90_one_card_per_person_for_the_phone_account_and_the_opposite_gender(self):
        self.attempt('E-CARD-90')
        cards = self.world.rows('daily_cards')
        self.assertEqual([(c['owner_id'], c['target_id']) for c in cards], [('id-1', 'id-2'), ('id-1', 'id-3')])
        genders = {p['id']: p.get('gender') for p in self.world.rows('profiles')}
        self.assertEqual((genders['id-1'], genders['id-2'], genders['id-3']), ('male', 'female', 'female'))
        self.assertTrue(all(c['expires_at'] for c in cards))

    def test_card_90_values_are_written_only_to_accounts_this_run_made(self):
        self.attempt('E-CARD-90')
        written = {s['query'].get('id') or s['query'].get('profile_id') for s in self.world.sent
                   if s['method'] == 'PATCH' and s['path'] in ('/rest/v1/profiles', '/rest/v1/survey_answers')}
        written.discard(None)
        self.assertTrue(written <= {'eq.id-1', 'eq.id-2', 'eq.id-3'}, written)

    def test_card_90_school_not_open_is_blocked_before_any_account(self):
        self.world.tables['universities'][0]['card_opens_at'] = '2026-10-05T07:00:00+09:00'
        app = App(self.world)
        result, note = self.attempt('E-CARD-90', app)
        self.assertEqual(result, 'blocked')
        self.assertIn('card_opens_at', note)
        self.assertEqual((app.jobs, self.world.users), ([], []))


if __name__ == '__main__':
    unittest.main()
