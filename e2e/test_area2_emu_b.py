"""영역 2 B에뮬 단독 가설 11(수락함 3 · 투표 5 · 추천 코드 3)의 PC 쪽 시험 — 기기 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 adb 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_emu_b`.

가짜 서버 [EmuWorld] 는 e2e/test_area2_phone_b.py 의 World(표 · 투표 글 · 하트 원장 · 온보딩)에 수락함 · 투표 · 18a 를 얹은 것이다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 … — 가설마다 누가 몇 번인지는 시험 위쪽 주석에 적는다.
가짜 폰 [Phone] 은 앱을 켜기 직전(start) · 앱이 멈춘 사이(midway) · 앱이 서버에 남길 일(effect)을 따로 흉내 낸다."""

import itertools
import re
import subprocess
import sys
import unittest
from datetime import date
from unittest import mock

from e2e import area1, area2_emu_b, area2_phone3, notify, tools
from e2e.test_area1 import Base as FakeBase
from e2e.test_area1_phone import FakePhone
from e2e.test_area2_phone_b import PhoneBase, World
from e2e.tools import Blocked, Reply

BUNDLE = ('E-CARD-41 E-CARD-45 E-CARD-86 E-POLL-02 E-POLL-04 E-POLL-05 E-POLL-06 E-POLL-28 E-REF-07 E-REF-08 E-REF-17').split()
EMU = 'emulator-5554'
PASS = {'result': 'pass'}
ACCEPT_TITLE = '대화 신청이 왔어요'
NOT_FOUND = '수락을 찾을 수 없어요'


class EmuWorld(World):
    """World + 받은 수락함 · 투표 · 18a. 규칙은 backend cards/router.py · community/router.py · heart_tasks/router.py 를 그대로 옮겼다."""

    def __init__(self):
        super().__init__()
        self.options = []  # (메서드, 경로, 옵션) — 비멱등 호출이 retry=False 로 가는지 본다
        for method, pattern, reply in (
            ('POST', r'/community/polls/[^/]+/votes', self.cast_vote),
            ('GET', r'/cards/acceptances', self.acceptances),
            ('POST', r'/cards/acceptances/[^/]+', self.respond),
            ('POST', r'/cards/[^/]+/decision', self.decide),
            ('GET', r'/heart-tasks', self.heart_tasks),
        ):
            self.on(method, pattern, reply)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.options.append((method, url, options))
        return super().__call__(method, url, headers, body, raw, **options)

    # 수락함 ----------------------------------------------------------------------------------
    def status(self, who):
        return self.profile(who).get('status', 'active')

    def accepted_cards(self, who):
        """[who] 가 받은 수락 중 아직 답하지 않았고 보낸 사람이 active 인 카드."""
        answered = {r['card_id'] for r in self.rows('acceptance_responses')}
        accepted = {r['card_id'] for r in self.rows('card_decisions') if r['decision'] == 'accept'}
        return [c for c in self.rows('daily_cards')
                if c['target_id'] == who and c['id'] in accepted and c['id'] not in answered and self.status(c['owner_id']) == 'active']

    def decide(self, sent):
        who, card_id = self.caller(sent), sent['path'].split('/')[2]
        if not any(c['id'] == card_id and c['owner_id'] == who for c in self.rows('daily_cards')):
            return Reply(404, {'detail': '카드를 찾을 수 없어요'})
        self.rows('card_decisions').append({'card_id': card_id, 'decision': sent['body']['decision']})
        return Reply(200, {'ok': True})

    def acceptances(self, sent):
        return Reply(200, {'acceptances': [{'card_id': c['id']} for c in self.accepted_cards(self.caller(sent))]})

    def respond(self, sent):
        who, card_id = self.caller(sent), sent['path'].rsplit('/', 1)[1]
        card = next((c for c in self.accepted_cards(who) if c['id'] == card_id), None)
        if card is None:
            return Reply(404, {'detail': NOT_FOUND})
        self.rows('acceptance_responses').append({'card_id': card_id, 'decision': sent['body']['decision']})
        low, high = sorted((card['owner_id'], who))
        match_id = self.next_id('match')
        self.rows('matches').append({'id': match_id, 'profile_a': low, 'profile_b': high})
        self.rows('match_participants').extend({'match_id': match_id, 'profile_id': p} for p in (low, high))
        return Reply(200, {'matched': True, 'match_id': match_id})

    # 투표 · 18a ------------------------------------------------------------------------------
    def vote_as(self, voter, poll_id, choice='a'):
        """투표 한 표 + 하루 첫 투표면 원장 +10(cast_poll_vote) → 하트를 줬는가."""
        self.rows('poll_votes').append({'poll_id': poll_id, 'voter_id': voter, 'choice': choice})
        due = not any(t['profile_id'] == voter and t['reason'] == 'poll_vote' for t in self.rows('heart_transactions'))
        if due:
            self.rows('heart_transactions').append({'profile_id': voter, 'amount': 10, 'reason': 'poll_vote', 'ref_id': poll_id})
        return due

    def cast_vote(self, sent):
        poll_id = sent['path'].split('/')[3]
        if not any(p['id'] == poll_id for p in self.rows('polls')):
            return Reply(404, {'detail': '질문을 찾을 수 없어요'})
        return Reply(200, {'poll': {'id': poll_id}, 'rewarded': self.vote_as(self.caller(sent), poll_id, sent['body']['choice'])})

    def used(self, who):
        return len([t for t in self.rows('heart_transactions') if t['profile_id'] == who and t['reason'] == 'poll_vote'])

    def heart_tasks(self, sent):
        used = self.used(self.caller(sent))
        row = {'task': 'poll_vote', 'reward_hearts': 10, 'state': 'done' if used >= 3 else 'open', 'used': used, 'limit': 3,
               'reject_reason': None}
        return Reply(200, {'tasks': [row]})


class Phone(FakePhone):
    """앱 대신. 앱을 켜기 직전 [start](job), 앱이 멈춘 사이 [midway], 앱이 서버에 남길 일 [effect](job) 를 이 순서로 한다."""

    def __init__(self, *answers, start=None, effect=None, **kw):
        super().__init__(*answers, **kw)
        self.serial, self.start, self.effect = EMU, start, effect

    def __call__(self, midway=None, **job):
        if self.start:
            self.start(job)
        answer = super().__call__(midway, **job)
        if self.effect:
            self.effect(job)
        return answer


class EmuBase(PhoneBase):
    """PhoneBase 의 가짜 서버를 EmuWorld 로 바꾸고, adb 를 부르는 알림 도우미는 전부 가짜로 둔다."""

    def setUp(self):
        super().setUp()
        self.world = EmuWorld()
        patcher = mock.patch.object(tools, 'call', self.world)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ('grant_notifications', 'revoke_notifications'):
            granter = mock.patch.object(notify, name)
            granter.start()
            self.addCleanup(granter.stop)

    def attempt(self, case, phone):
        return area1.attempt_phone(self.run_, case, phone)

    def nick(self, who):
        return self.world.profile(who)['nickname']

    def card(self):
        """A(id-1)가 B(id-2)에게 낸 카드 — 이 가설들은 카드가 한 장뿐이다."""
        return self.world.rows('daily_cards')[0]


class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_11_in_order_and_every_case_is_a_phone_case(self):
        self.assertEqual(area1.BUNDLES['area2-emu-b'], BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_no_case_is_one_of_the_home_cases_another_window_owns(self):
        self.assertFalse([c for c in BUNDLE if c.startswith('E-HOME')])

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area2_emu_b 를 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m; print(m.BUNDLES.get("area2-emu-b"))'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), str(BUNDLE))


class EveryCaseTest(EmuBase):
    def test_a_real_phone_is_blocked_before_any_account_is_made(self):
        for case in BUNDLE:
            with self.subTest(case):
                phone = Phone()
                phone.serial = 'R5CR12345'
                result, note = self.attempt(case, phone)
                self.assertEqual(result, 'blocked', note)
                self.assertIn('에뮬', note)
                self.assertEqual(phone.jobs, [])
                self.assertNotIn('/auth/v1/admin/users', [s['path'] for s in self.world.sent])


# ── 수락함 ──────────────────────────────────────────────────────────────────────────────────────
# 계정: A = id-1(API 로 수락을 보낸다) · B = id-2(폰 계정, 토큰 tok-2). 카드는 A 가 주인 · B 가 대상.

class AcceptanceTest(EmuBase):
    def match_made(self, world, job):
        """앱이 "수락하기" 을 눌러 서버에 남기는 일."""
        card = world.rows('daily_cards')[0]
        self.assertEqual(world.respond({'auth': 'tok-2', 'path': f"/cards/acceptances/{card['id']}", 'body': {'decision': 'accept'}}).status, 200)

    def test_card_45_the_app_gets_the_senders_nickname_and_a_waiting_acceptance(self):
        seen = {}
        phone = Phone(start=lambda job: seen.update(waiting=[c['id'] for c in self.world.accepted_cards('id-2')]),
                      effect=lambda job: self.match_made(self.world, job))
        self.assertEqual(self.attempt('E-CARD-45', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['token_hash'], 'h')
        self.assertEqual(phone.jobs[0]['nickname'], self.nick('id-1'))
        self.assertEqual(seen['waiting'], [self.card()['id']])  # 앱을 켜기 전에 A 의 수락이 이미 있다

    def test_card_45_no_match_row_fails(self):
        result, note = self.attempt('E-CARD-45', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('matches', note)

    def test_card_45_a_match_with_one_participant_fails(self):
        def lopsided(job):
            self.world.rows('matches').append({'id': 'm', 'profile_a': 'id-1', 'profile_b': 'id-2'})
            self.world.rows('match_participants').append({'match_id': 'm', 'profile_id': 'id-2'})
        result, note = self.attempt('E-CARD-45', Phone(effect=lopsided))
        self.assertEqual(result, 'fail')
        self.assertIn('match_participants', note)

    def test_card_86_the_sender_is_suspended_while_the_app_waits_and_no_match_is_made(self):
        statuses = []
        phone = Phone(midway_step={'step': 'suspend'},
                      start=lambda job: statuses.append(self.world.status('id-1')),
                      effect=lambda job: statuses.append(self.world.status('id-1')))
        result, note = self.attempt('E-CARD-86', phone)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(statuses, ['active', 'suspended'])  # 앱을 켤 때는 active, 앱이 누를 때는 이미 정지
        self.assertEqual(phone.acted, ['suspend'])
        self.assertEqual(phone.jobs[0]['nickname'], self.nick('id-1'))
        self.assertEqual(self.world.rows('matches'), [])
        self.assertEqual(self.world.rows('acceptance_responses'), [])

    def test_card_86_a_match_made_for_a_suspended_sender_fails(self):
        def leaky(job):
            self.world.rows('matches').append({'id': 'm', 'profile_a': 'id-1', 'profile_b': 'id-2'})
        result, note = self.attempt('E-CARD-86', Phone(effect=leaky))
        self.assertEqual(result, 'fail')
        self.assertIn('matches', note)

    def test_card_86_a_server_that_still_lists_the_suspended_senders_acceptance_fails(self):
        self.world.handlers.insert(0, ('GET', re.compile(r'/cards/acceptances'),
                                       lambda sent: Reply(200, {'acceptances': [{'card_id': 'x'}]})))
        result, note = self.attempt('E-CARD-86', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('목록', note)

    def test_card_86_a_server_that_answers_something_else_than_404_fails(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/cards/acceptances/[^/]+'), Reply(409, {'detail': '이미 답한 수락이에요'})))
        result, note = self.attempt('E-CARD-86', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('404', note)

    def test_card_86_a_response_row_without_a_match_fails(self):
        def half(job):
            self.world.rows('acceptance_responses').append({'card_id': self.card()['id'], 'decision': 'accept'})
        result, note = self.attempt('E-CARD-86', Phone(effect=half))
        self.assertEqual(result, 'fail')
        self.assertIn('acceptance_responses', note)

    def test_card_86_a_404_with_another_message_fails(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/cards/acceptances/[^/]+'), Reply(404, {'detail': '다른 문구예요'})))
        result, note = self.attempt('E-CARD-86', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('다른 문구', note)

    def test_the_calls_that_cannot_be_repeated_are_sent_once(self):
        for case in ('E-CARD-45', 'E-CARD-86', 'E-POLL-04', 'E-POLL-06'):  # 05 는 투표를 앱이 한다
            with self.subTest(case):
                self.setUp()
                self.attempt(case, Phone())
                writes = [(m, u.split('?')[0], o) for m, u, o in self.world.options
                          if re.search(r'/cards/[^/]+/decision$|/cards/acceptances/[^/]+$|/community/polls/[^/]+/votes$', u.split('?')[0])]
                self.assertTrue(writes, f'{case}: 수락 · 투표 호출이 없다')
                self.assertTrue(all(o == {'retry': False} for _, _, o in writes), f'{case}: {writes}')

    def test_card_45_and_86_app_answers(self):
        for case in ('E-CARD-45', 'E-CARD-86'):
            with self.subTest(case):
                self.setUp()
                self.assertEqual(self.attempt(case, Phone({'result': 'blocked', 'note': '화면 없음'}))[0], 'blocked')
                self.setUp()
                self.assertEqual(self.attempt(case, Phone(None))[0], 'fail')
                self.setUp()
                result, note = self.attempt(case, Phone({'result': 'fail', 'note': '글자 없음'}))
                self.assertEqual(result, 'fail')
                self.assertIn('글자 없음', note)


class Card41Test(EmuBase):
    """B(id-2)가 홈에 켜 둔 채 HOME → A(id-1)가 카드를 수락 → B 에 알림 → 알림을 눌러 앱이 대화 탭을 본다."""

    def setUp(self):
        super().setUp()
        self.calls, self.notices = [], None  # notices 가 None 이면 A 의 수락 알림이 온다
        fakes = {'require_daytime': lambda now=None: self.calls.append('daytime'),
                 'read_notifications': lambda serial: self.calls.append('read') or [notify.Notice('old', '남은 알림', '', 'c')],
                 'background': lambda serial: self.calls.append('background'),
                 'wait_new': self.wait_new,
                 'tap_notification': lambda serial, text: self.calls.append(('tap', text))}
        for name, fake in fakes.items():
            patcher = mock.patch.object(notify, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)

    def body(self):
        return f"{self.nick('id-1')} 님이 대화를 신청했어요"

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        self.calls.append(('wait_new', seconds, match is not None, len(self.world.rows('card_decisions'))))
        return [notify.Notice('new', ACCEPT_TITLE, self.body(), 'c')] if self.notices is None else self.notices

    def go(self, *answers, tokens=1, **kw):
        def login(job):
            self.calls.append(('app', len(self.world.rows('card_decisions'))))  # 앱을 켤 때 A 의 수락은 아직 없다
            self.world.rows('push_tokens').extend({'profile_id': 'id-2', 'token': 't'} for _ in range(tokens))
        phone = Phone(*answers, start=login, midway_step={'step': 'background'}, **kw)
        return self.attempt('E-CARD-41', phone), phone

    def test_pass_path_reads_hides_the_app_accepts_waits_and_taps_the_notification(self):
        (result, note), phone = self.go()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.calls, ['daytime', ('app', 0), 'read', 'background', ('wait_new', 30, True, 1), ('tap', self.body())])
        self.assertEqual(phone.jobs[0]['token_hash'], 'h')
        self.assertEqual(phone.jobs[0]['nickname'], self.nick('id-1'))
        decision = self.world.rows('card_decisions')[0]
        self.assertEqual((decision['card_id'], decision['decision']), (self.card()['id'], 'accept'))
        self.assertEqual((self.card()['owner_id'], self.card()['target_id']), ('id-1', 'id-2'))

    def test_it_taps_the_text_with_the_senders_nickname_not_the_title_that_older_runs_share(self):
        self.go()
        self.assertEqual([c for c in self.calls if isinstance(c, tuple) and c[0] == 'tap'], [('tap', self.body())])

    def test_the_acceptance_notification_is_only_waited_for_after_the_accept(self):
        self.go()
        self.assertIn(('wait_new', 30, True, 1), self.calls)  # 기다릴 때는 수락(card_decisions 1)이 이미 서버에 있다

    def test_no_device_token_is_blocked_with_the_reason_and_nothing_is_accepted(self):
        with mock.patch.object(area2_phone3.time, 'monotonic', side_effect=itertools.count()):
            (result, note), _ = self.go(tokens=0)
        self.assertEqual(result, 'blocked')
        self.assertIn('30초', note)
        self.assertIn('FCM', note)
        self.assertNotIn('background', self.calls)
        self.assertEqual(self.world.rows('card_decisions'), [])

    def test_no_notification_is_blocked_not_a_fail_because_arrival_is_judged_by_card_40(self):
        self.notices = []
        (result, note), _ = self.go()
        self.assertEqual(result, 'blocked')
        self.assertIn('30초', note)
        self.assertIn('E-CARD-40', note)
        self.assertFalse([c for c in self.calls if isinstance(c, tuple) and c[0] == 'tap'])

    def test_an_older_notification_with_another_nickname_is_not_tapped(self):
        self.notices = [notify.Notice('old2', ACCEPT_TITLE, '다른닉 님이 대화를 신청했어요', 'c')]
        self.assertEqual(self.go()[0][0], 'blocked')
        self.assertFalse([c for c in self.calls if isinstance(c, tuple) and c[0] == 'tap'])

    def test_a_notification_that_cannot_be_tapped_is_blocked(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            (result, note), _ = self.go()
        self.assertEqual((result, '못 찾음' in note), ('blocked', True))

    def test_a_failed_accept_is_blocked_before_waiting_for_a_notification(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/cards/[^/]+/decision'), Reply(409, {'detail': '이미 결정한 카드예요'})))
        (result, note), _ = self.go()
        self.assertEqual(result, 'blocked')
        self.assertNotIn('wait_new', [c[0] for c in self.calls if isinstance(c, tuple)])

    def test_at_night_it_is_blocked_before_any_account_is_made(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('서울 시각 23:10 — 알림 시험은 08:00~21:59 에만'))):
            (result, note), phone = self.go()
        self.assertEqual(result, 'blocked')
        self.assertEqual(phone.jobs, [])
        self.assertNotIn('/auth/v1/admin/users', [s['path'] for s in self.world.sent])

    def test_app_answers(self):
        for answer, want in (({'result': 'fail', 'note': '받은 신청 없음'}, 'fail'), ({'result': 'blocked', 'note': '홈 아님'}, 'blocked'), (None, 'fail')):
            with self.subTest(answer):
                self.setUp()
                (result, note), _ = self.go(answer)
                self.assertEqual(result, want)
                if answer:
                    self.assertIn(answer['note'], note)



# ── 투표 5 ──────────────────────────────────────────────────────────────────────────────────────
# 계정: 글쓴이(A) = id-1, (E-POLL-04 만) 투표자(V) = id-2, 폰 계정(B) 은 늘 마지막(토큰 tok-N).

class PollTest(EmuBase):
    def poll_id(self, question):
        return next(p['id'] for p in self.world.rows('polls') if p['question'] == question)

    def questions(self):
        return [p['question'] for p in self.world.rows('polls')]

    def ledger(self, who):
        return [(t['amount'], t['ref_id']) for t in self.world.rows('heart_transactions') if t['profile_id'] == who and t['reason'] == 'poll_vote']

    # E-POLL-02 ---------------------------------------------------------------------------------
    def test_poll_02_only_the_anchor_exists_when_the_app_starts_and_the_new_post_comes_while_it_waits(self):
        seen = []
        phone = Phone(midway_step={'step': 'posted'}, start=lambda job: seen.append(self.questions()), effect=lambda job: seen.append(self.questions()))
        result, note = self.attempt('E-POLL-02', phone)
        self.assertEqual(result, 'pass', note)
        job = phone.jobs[0]
        self.assertEqual(seen, [[job['anchor']], [job['anchor'], job['question']]])
        self.assertTrue(job['anchor'].startswith('[E2E] ') and job['question'].startswith('[E2E] '))
        self.assertNotEqual(job['anchor'], job['question'])
        self.assertEqual(phone.acted, ['posted'])

    def test_poll_02_the_posts_are_made_by_another_account_than_the_phone_account(self):
        authors = []
        phone = Phone(effect=lambda job: authors.extend(p['author_id'] for p in self.world.rows('polls')))
        self.attempt('E-POLL-02', phone)
        self.assertEqual(set(authors), {'id-1'})  # 폰 계정은 id-2

    def test_poll_02_both_posts_are_deleted_even_when_the_app_fails(self):
        self.attempt('E-POLL-02', Phone({'result': 'fail', 'note': '새 글이 안 보임'}))
        self.assertEqual(self.world.rows('polls'), [])
        self.setUp()
        self.attempt('E-POLL-02', Phone())
        self.assertEqual(self.world.rows('polls'), [])

    # E-POLL-04 ---------------------------------------------------------------------------------
    def vote_a_by_phone(self, job):
        self.world.vote_as('id-3', self.poll_id(job['question']), 'a')

    def test_poll_04_another_account_has_already_voted_a_when_the_app_starts(self):
        seen = []
        phone = Phone(start=lambda job: seen.append(list(self.world.rows('poll_votes'))), effect=self.vote_a_by_phone)
        result, note = self.attempt('E-POLL-04', phone)
        self.assertEqual(result, 'pass', note)
        self.assertEqual([[(v['voter_id'], v['choice']) for v in votes] for votes in seen], [[('id-2', 'a')]])
        self.assertTrue(phone.jobs[0]['question'].startswith('[E2E] '))
        self.assertEqual(self.world.rows('polls'), [])

    def test_poll_04_a_missing_or_wrong_phone_vote_fails(self):
        for effect in (lambda job: None, lambda job: self.world.vote_as('id-3', self.poll_id(job['question']), 'b')):
            self.setUp()
            result, note = self.attempt('E-POLL-04', Phone(effect=effect))
            self.assertEqual(result, 'fail')
            self.assertIn('poll_votes', note)

    def test_poll_04_a_vote_that_cannot_be_prepared_is_blocked(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), Reply(404, {'detail': '질문을 찾을 수 없어요'})))
        self.assertEqual(self.attempt('E-POLL-04', Phone())[0], 'blocked')

    # E-POLL-05 ---------------------------------------------------------------------------------
    def test_poll_05_the_first_vote_of_the_day_pays_ten_hearts_with_the_poll_as_reference(self):
        seen = []
        phone = Phone(start=lambda job: seen.append(self.ledger('id-2')),
                      effect=lambda job: self.world.vote_as('id-2', self.poll_id(job['question'])))
        result, note = self.attempt('E-POLL-05', phone)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(seen, [[]])  # 앱을 켤 때 오늘 poll_vote 원장은 0
        self.assertEqual(self.world.rows('polls'), [])

    def test_poll_05_no_ledger_a_double_ledger_or_another_reference_fails(self):
        def double(job):
            pid = self.poll_id(job['question'])
            self.world.vote_as('id-2', pid)
            self.world.rows('heart_transactions').append({'profile_id': 'id-2', 'amount': 10, 'reason': 'poll_vote', 'ref_id': pid})

        def other_ref(job):
            self.world.vote_as('id-2', self.poll_id(job['question']))
            self.world.rows('heart_transactions')[-1]['ref_id'] = 'x'

        for label, effect in (('원장 없음', lambda job: None), ('두 줄', double), ('다른 ref', other_ref)):
            with self.subTest(label):
                self.setUp()
                result, note = self.attempt('E-POLL-05', Phone(effect=effect))
                self.assertEqual(result, 'fail')
                self.assertIn('poll_vote', note)

    # E-POLL-06 ---------------------------------------------------------------------------------
    def test_poll_06_the_posts_are_deleted_even_when_the_app_fails(self):
        self.attempt('E-POLL-06', Phone({'result': 'fail', 'note': '토스트가 뜸'}))
        self.assertEqual(self.world.rows('polls'), [])

    def second_vote(self, job):
        self.world.vote_as('id-2', self.poll_id(job['question']))  # 오늘 이미 받았으니 하트는 안 나간다

    def test_poll_06_the_phone_account_already_voted_through_the_api_and_got_hearts_today(self):
        seen = []
        phone = Phone(start=lambda job: seen.append((self.ledger('id-2'), self.poll_id(job['question']))), effect=self.second_vote)
        result, note = self.attempt('E-POLL-06', phone)
        self.assertEqual(result, 'pass', note)
        (first,), second = seen[0]
        self.assertEqual(first[0], 10)
        self.assertNotEqual(first[1], second)  # 앱이 누르는 글은 먼저 투표한 글과 다른 글이다

    def test_poll_06_a_second_reward_fails(self):
        def paid_again(job):
            self.second_vote(job)
            self.world.rows('heart_transactions').append({'profile_id': 'id-2', 'amount': 10, 'reason': 'poll_vote', 'ref_id': 'y'})
        result, note = self.attempt('E-POLL-06', Phone(effect=paid_again))
        self.assertEqual(result, 'fail')
        self.assertIn('원장', note)

    def test_poll_06_a_phone_that_never_voted_is_a_fail_not_a_pass_by_default(self):
        result, note = self.attempt('E-POLL-06', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('poll_votes', note)

    def test_poll_06_a_first_vote_that_pays_nothing_is_blocked_because_it_is_poll_05s_problem(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/community/polls/[^/]+/votes'), Reply(200, {'poll': {}, 'rewarded': False})))
        result, note = self.attempt('E-POLL-06', Phone())
        self.assertEqual(result, 'blocked')
        self.assertIn('E-POLL-05', note)

    def test_poll_06_crossing_midnight_is_blocked_not_a_wrong_second_reward(self):
        days = [date(2026, 10, 5), date(2026, 10, 6)]
        with mock.patch.object(area2_emu_b, '_seoul_today', side_effect=days):
            result, note = self.attempt('E-POLL-06', Phone(effect=self.second_vote))
        self.assertEqual(result, 'blocked')
        self.assertIn('자정', note)

    # E-POLL-28 ---------------------------------------------------------------------------------
    def test_poll_28_two_ledger_rows_this_week_the_server_says_used_2_open_and_the_app_is_told_so(self):
        phone = Phone()
        result, note = self.attempt('E-POLL-28', phone)
        self.assertEqual(result, 'pass', note)
        self.assertEqual((phone.jobs[0]['used'], phone.jobs[0]['limit']), (2, 3))
        self.assertEqual(self.ledger('id-1'), [(10, None), (10, None)])

    def test_poll_28_a_server_count_that_differs_from_the_ledger_fails(self):
        self.world.handlers.insert(0, ('GET', re.compile(r'/heart-tasks'), Reply(200, {'tasks': [
            {'task': 'poll_vote', 'reward_hearts': 10, 'state': 'open', 'used': 1, 'limit': 3, 'reject_reason': None}]})))
        result, note = self.attempt('E-POLL-28', Phone())
        self.assertEqual(result, 'fail')
        self.assertIn('used', note)

    def test_poll_28_a_ledger_that_cannot_be_seeded_is_blocked(self):
        self.world.handlers.insert(0, ('POST', re.compile(r'/rest/v1/rpc/grant_hearts'), Reply(400, {'code': '23514'})))
        self.assertEqual(self.attempt('E-POLL-28', Phone())[0], 'blocked')

    # 앱이 한 말 --------------------------------------------------------------------------------
    def test_app_answers(self):
        for case in ('E-POLL-02', 'E-POLL-04', 'E-POLL-05', 'E-POLL-06', 'E-POLL-28'):
            with self.subTest(case):
                self.setUp()
                self.assertEqual(self.attempt(case, Phone({'result': 'blocked', 'note': '커뮤니티 탭 없음'}))[0], 'blocked')
                self.setUp()
                self.assertEqual(self.attempt(case, Phone(None))[0], 'fail')
                self.setUp()
                result, note = self.attempt(case, Phone({'result': 'fail', 'note': '글자 없음'}))
                self.assertEqual(result, 'fail')
                self.assertIn('글자 없음', note)



# ── 추천 코드 3 ─────────────────────────────────────────────────────────────────────────────────
# 영역 1 의 E-ONB-62 · 64 · 70 · 71 과 같은 화면 동작 — 에뮬에서만 도는 이름으로 다시 올려 둔다. 가짜 서버는 영역 1 시험의 것(표는 기본 빈 목록).

class ReferralTest(FakeBase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(notify, 'grant_notifications')  # 에뮬 도우미가 알림 권한을 미리 준다 — 실제 adb 는 안 부른다
        patcher.start()
        self.addCleanup(patcher.stop)

    def phone(self, *answers):
        phone = FakePhone(*answers)
        phone.serial = EMU
        return phone

    def attempt(self, case, phone):
        return area1.attempt_phone(self.run, case, phone)

    def hearts(self, rows):
        return {('GET', '/rest/v1/heart_transactions'): Reply(200, rows)}

    def test_ref_07_the_app_pastes_the_code_in_lowercase_with_spaces_and_both_get_fifty(self):
        self.serve({('GET', '/rest/v1/referrals'): Reply(200, [{'referrer_id': 'id-1'}]), **self.hearts([{'amount': 50}]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        phone = self.phone()
        self.assertEqual(self.attempt('E-REF-07', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['code'], ' k7m2qx ')

    def test_ref_07_no_referral_row_fails(self):
        self.serve({**self.hearts([{'amount': 50}]), ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        self.assertEqual(self.attempt('E-REF-07', self.phone())[0], 'fail')

    def test_ref_08_a_code_nobody_has_gives_no_hearts(self):
        self.serve({**self.hearts([]), ('GET', '/rest/v1/profiles'): Reply(200, [])})
        phone = self.phone()
        self.assertEqual(self.attempt('E-REF-08', phone)[0], 'pass')
        self.assertRegex(phone.jobs[0]['code'], r'^[A-HJ-NP-Z2-9]{6}$')

    def test_ref_08_hearts_that_appear_fail(self):
        self.serve({**self.hearts([{'amount': 50}]), ('GET', '/rest/v1/profiles'): Reply(200, [])})
        self.assertEqual(self.attempt('E-REF-08', self.phone())[0], 'fail')

    def test_ref_17_skip_on_one_account_then_kill_at_20_and_relaunch_on_another(self):
        fake = self.serve()
        phone = self.phone()
        result, note = self.attempt('E-REF-17', phone)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'phase': 'skip'}, {'token_hash': 'h'}, {'fresh': False, 'expect': 'home', 'limit': 30}])
        self.assertEqual(len([u for m, u in fake.urls if m == 'POST' and u.endswith('/auth/v1/admin/users')]), 2)  # 계정 둘 — 건너뛰기용 · 강제 종료용

    def test_ref_17_a_skip_that_leaves_hearts_or_a_referral_fails(self):
        self.serve(self.hearts([{'amount': 50}]))
        result, note = self.attempt('E-REF-17', self.phone())
        self.assertEqual(result, 'fail')
        self.assertIn('하트', note)
        self.setUp()
        self.serve({('GET', '/rest/v1/referrals'): Reply(200, [{'referrer_id': 'x'}])})
        result, note = self.attempt('E-REF-17', self.phone())
        self.assertEqual(result, 'fail')
        self.assertIn('referrals', note)

    def test_ref_17_each_step_of_the_app_names_itself_when_it_fails(self):
        for n, label in enumerate(('건너뛰기', '20 도착', '다시 켬')):
            self.setUp()
            self.serve()
            answers = [PASS] * n + [{'result': 'fail', 'note': '화면 없음'}]
            result, note = self.attempt('E-REF-17', self.phone(*answers))
            self.assertEqual(result, 'fail')
            self.assertIn(label, note)

    def test_the_three_cases_answer_blocked_and_silence_like_the_others(self):
        for case in ('E-REF-07', 'E-REF-08', 'E-REF-17'):
            with self.subTest(case):
                code = {('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])} if case == 'E-REF-07' else {}  # 07 만 추천인 코드를 읽는다
                self.setUp()
                self.serve(code)
                self.assertEqual(self.attempt(case, self.phone({'result': 'blocked', 'note': '20 없음'}))[0], 'blocked')
                self.setUp()
                self.serve(code)
                self.assertEqual(self.attempt(case, self.phone(None))[0], 'fail')

if __name__ == '__main__':
    unittest.main()
