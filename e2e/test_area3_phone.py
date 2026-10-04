"""영역 3 폰 A 한 대 1차(채팅 · 지인 리뷰 화면 읽기 19개)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_phone`.

가짜 서버는 e2e/test_area3.py 의 Fake(표를 메모리에 든다), 가짜 앱은 [App] — 받은 일감을 남기고 시험이 정한 말을 돌려준다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 …(폰 계정이 늘 먼저다).
"""

import re
import unittest

from e2e import area1, area3, area3_phone  # noqa: F401 — area3_phone 이 가설을 area1.PHONE 에 더한다
from e2e.test_area3 import Base, PROFILE_GONE
from e2e import tools
from e2e.tools import Reply

ALREADY = '이미 리뷰를 남겼어요'
EARLY = '카카오톡 아이디를 먼저 공유해도 돼요'
THREE = ['약속을 잘 지켜요', '대화가 편해요', '성실해요']
BUNDLE = ['E-CHAT-06', 'E-CHAT-08', 'E-CHAT-09', 'E-CHAT-18', 'E-CHAT-19', 'E-CHAT-20', 'E-CHAT-36', 'E-CHAT-60',
          'E-CHAT-62', 'E-REV-10', 'E-REV-12', 'E-REV-19', 'E-REV-21', 'E-REV-22', 'E-REV-23', 'E-REV-29', 'E-REV-30',
          'E-REV-32', 'E-REV-33']


class App:
    """앱 대신 — 받은 일감을 [jobs] 에 남기고 [answer](일감) 을 돌려준다."""

    def __init__(self, answer):
        self.answer, self.jobs = answer, []

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        return self.answer(job)


def said(**extra):
    return {'result': 'pass', **extra}


def bodies(count):
    return [f'E2E-{i}' for i in range(count)]


class PhoneBase(Base):
    def case(self, name, answer):
        """가설 하나를 깨끗한 가짜 서버에서(시험이 정한 API 답은 둔다) — 계정은 늘 id-1 부터."""
        self.fake.tables.clear()
        self.fake.sent.clear()
        self.fake.statuses.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        if isinstance(answer, dict):
            answer = (lambda fixed: lambda job: dict(fixed))(answer)
        app = App(answer)
        return area1.attempt_phone(self.run_, name, app), app

    def nicks(self):
        """만든 순서대로의 닉네임(04-1 에 보낸 것) — 0번이 id-1."""
        return [s['body']['nickname'] for s in self.fake.by('POST', '/profile-onboarding/basic-info')]

    def nick(self, n):
        return self.nicks()[n - 1]

    def assert_all_home(self):
        """폰 계정 · 상대 모두 홈(bio)까지 — 계정 단계가 바뀌면 잡는다."""
        made = len(self.fake.by('POST', '/auth/v1/admin/users'))
        self.assertGreater(made, 0)
        self.assertEqual(len(self.fake.by('POST', '/profile-onboarding/bio')), made)

    def rows(self, table, **where):
        return [r for r in self.fake.tables.get(table, []) if all(r.get(k) == v for k, v in where.items())]

    def assert_pair(self, match_id, x, y):
        match = self.rows('matches', id=match_id)[0]
        self.assertEqual((match['profile_a'], match['profile_b']), tuple(sorted((x, y))))


class ChatListTest(PhoneBase):
    def answer_06(self, job):
        return said(order=[self.nick(2), self.nick(4), self.nick(3)])

    def test_06_recent_room_comes_first(self):
        (result, note), app = self.case('E-CHAT-06', self.answer_06)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nicknames': [self.nick(2), self.nick(3), self.nick(4)]}])
        matches = [r['id'] for r in self.fake.tables['matches']]
        for match_id, partner in zip(matches, ('id-2', 'id-3', 'id-4')):
            self.assert_pair(match_id, 'id-1', partner)
        sends = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([s['path'].split('/')[3] for s in sends], [matches[2], matches[0]])  # 방3 → 방1
        self.assertEqual({s['auth'] for s in sends}, {'tok-1'})  # 폰 계정이 보낸다
        self.assert_all_home()

    def test_06_fails_when_list_keeps_match_order(self):
        (result, note), _ = self.case('E-CHAT-06', lambda job: said(order=job['nicknames']))
        self.assertEqual(result, 'fail')
        self.assertIn('목록 순서', note)

    def test_06_failed_send_is_blocked_before_the_app(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(500, {'detail': 'down'}))
        (result, _), app = self.case('E-CHAT-06', self.answer_06)
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])

    def test_08_my_own_messages_leave_no_badge(self):
        (result, note), app = self.case('E-CHAT-08', said(row_badge=None, nav_badge=None))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        match_id = self.fake.tables['matches'][0]['id']
        sends = self.fake.by('POST', f'/chat/matches/{match_id}/messages')
        self.assertEqual([s['auth'] for s in sends], ['tok-1'] * 3)  # 폰 계정이 세 건
        self.assert_all_home()

    def test_08_fails_when_my_messages_count_as_unread(self):
        for key in ('row_badge', 'nav_badge'):
            (result, note), _ = self.case('E-CHAT-08', said(**{'row_badge': None, 'nav_badge': None, key: '3'}))
            self.assertEqual(result, 'fail', key)
        (result, _), _ = self.case('E-CHAT-08', said())  # 앱이 뱃지를 안 말하면 판정할 수 없다
        self.assertEqual(result, 'fail')

    def test_09_hundred_unread_stops_at_99_plus(self):
        (result, note), app = self.case('E-CHAT-09', said(row_badge='99+', nav_badge='99+'))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        self.assertEqual(len(self.rows('messages', sender_id='id-2')), 100)  # 상대가 보낸 100건
        self.assertTrue(all('last_read_at' not in r for r in self.fake.tables['match_participants']))  # 안 읽은 채로
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])

    def test_09_fails_when_a_badge_is_not_99_plus(self):
        for answer in (said(row_badge='100', nav_badge='99+'), said(row_badge='99+', nav_badge=None)):
            (result, _), _ = self.case('E-CHAT-09', answer)
            self.assertEqual(result, 'fail', answer)

    def test_09_failed_seed_is_blocked(self):
        self.fake.on('POST', r'/rest/v1/messages', Reply(400, {'message': 'bad'}))
        (result, note), app = self.case('E-CHAT-09', said(row_badge='99+', nav_badge='99+'))
        self.assertEqual(result, 'blocked')
        self.assertIn('messages', note)
        self.assertEqual(app.jobs, [])


class PagingTest(PhoneBase):
    def good(self, count, stages, requests):
        return said(stages=stages, requests=requests, seen=bodies(count)[::-1], overlap=0)

    def test_18_pages_of_50_up_to_120(self):
        (result, note), app = self.case('E-CHAT-18', self.good(120, [50, 100, 120], 2))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        rows = self.fake.tables['messages']
        self.assertEqual([r['body'] for r in rows], bodies(120))
        self.assertEqual(len({r['created_at'] for r in rows}), 120)  # 1초씩 다르게
        self.assert_all_home()

    def test_18_fails_on_a_wrong_stage_overlap_gap_or_extra_request(self):
        good = dict(stages=[50, 100, 120], requests=2, seen=bodies(120), overlap=0)
        for bad in ({'stages': [50, 100]}, {'stages': [50, 120]}, {'overlap': 1}, {'seen': bodies(119)},
                    {'seen': bodies(120) + ['E2E-120']}, {'requests': 3}, {'requests': None}):
            (result, _), _ = self.case('E-CHAT-18', said(**{**good, **bad}))
            self.assertEqual(result, 'fail', bad)

    def test_19_exactly_50_asks_once_more_and_stops(self):
        (result, note), _ = self.case('E-CHAT-19', self.good(50, [50], 1))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(len(self.fake.tables['messages']), 50)

    def test_19_fails_when_it_never_asks_again_or_shows_more(self):
        for bad in ({'requests': 0}, {'stages': [50, 50]}):
            (result, _), _ = self.case('E-CHAT-19', said(**{**dict(stages=[50], requests=1, seen=bodies(50), overlap=0),
                                                            **bad}))
            self.assertEqual(result, 'fail', bad)

    def test_20_same_time_120_are_all_shown(self):
        (result, note), _ = self.case('E-CHAT-20', self.good(120, [50, 100, 120], 2))
        self.assertEqual((result, note), ('pass', ''))
        rows = self.fake.tables['messages']
        self.assertEqual(len(rows), 120)
        self.assertEqual(len({r['created_at'] for r in rows}), 1)  # created_at 이 모두 같다
        self.assertEqual(len({r['body'] for r in rows}), 120)

    def test_20_fails_when_a_page_border_drops_a_line(self):
        (result, note), _ = self.case('E-CHAT-20', said(stages=[50, 100, 119], requests=2, seen=bodies(119), overlap=0))
        self.assertEqual(result, 'fail')
        self.assertIn('빠진', note)


class RoomTest(PhoneBase):
    def left_line(self):
        return f'{self.nick(2)}님이 채팅방을 나갔어요'

    def good_60(self, job):
        return said(input=False, notice=True, leave_button=True, bodies=bodies(3), system=[self.left_line()],
                    banners=[], sheet=False)

    def test_36_fresh_match_shows_the_early_banner_only(self):
        (result, note), app = self.case('E-CHAT-36', said(banners=[EARLY], sheet=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        self.assertNotIn('created_at', self.fake.tables['matches'][0])  # 매칭 시각 = 지금(DB 기본값)
        self.assert_all_home()

    def test_36_fails_on_sheet_or_missing_banner(self):
        for bad in (said(banners=[EARLY], sheet=True), said(banners=[], sheet=False)):
            (result, _), _ = self.case('E-CHAT-36', bad)
            self.assertEqual(result, 'fail', bad)

    def test_60_partner_left_room_locks_input_and_keeps_history(self):
        (result, note), app = self.case('E-CHAT-60', self.good_60)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])
        match_id = self.fake.tables['matches'][0]['id']
        leave = self.fake.by('POST', f'/chat/matches/{match_id}/leave')
        self.assertEqual([s['auth'] for s in leave], ['tok-2'])  # 상대가 나간다
        self.assertEqual(len(self.rows('messages', sender_id='id-2')), 3)
        self.assert_all_home()

    def test_60_fails_when_input_stays_or_history_is_short(self):
        for bad in ({'input': True}, {'notice': False}, {'leave_button': False}, {'bodies': bodies(2)},
                    {'system': []}, {'banners': [EARLY]}, {'sheet': True}):
            (result, _), _ = self.case('E-CHAT-60', lambda job, bad=bad: {**self.good_60(job), **bad})
            self.assertEqual(result, 'fail', bad)

    def test_60_failed_leave_is_blocked(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', Reply(409, {'detail': '이미 나간 대화예요'}))
        (result, _), app = self.case('E-CHAT-60', self.good_60)
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])

    def test_62_left_room_stays_with_the_left_line(self):
        (result, note), app = self.case('E-CHAT-62', lambda job: said(preview=self.left_line()))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2)}])

    def test_62_fails_when_preview_is_not_the_left_line(self):
        for preview in ('E2E-2', None):
            (result, _), _ = self.case('E-CHAT-62', said(preview=preview))
            self.assertEqual(result, 'fail', preview)


class ComposeTest(PhoneBase):
    def test_10_second_open_is_a_toast_not_a_sheet_and_no_new_row(self):
        (result, note), app = self.case('E-REV-10', said(toast=ALREADY, form=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2'}])
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-2', 'referrer_id': 'id-1'}])
        self.assertEqual(len(self.rows('friend_reviews', reviewer_id='id-1', reviewee_id='id-2')), 1)
        self.assert_all_home()

    def test_10_fails_on_sheet_wrong_toast_or_new_row(self):
        for bad in (said(toast=ALREADY, form=True), said(toast='리뷰를 남겼어요', form=False)):
            (result, _), _ = self.case('E-REV-10', bad)
            self.assertEqual(result, 'fail', bad)

        def writes(job):  # 앱은 pass 라는데 DB 에 한 줄이 더 생겼다
            self.fake.tables['friend_reviews'].append({'reviewer_id': 'id-1', 'reviewee_id': 'id-2'})
            return said(toast=ALREADY, form=False)
        (result, note), _ = self.case('E-REV-10', writes)
        self.assertEqual(result, 'fail')
        self.assertIn('friend_reviews', note)

    def test_12_unlinked_person_gets_profile_gone_and_api_404(self):
        self.fake.on('POST', r'/friend-reviews', Reply(404, {'detail': PROFILE_GONE}))
        (result, note), app = self.case('E-REV-12', said(toast=PROFILE_GONE, form=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2'}])
        self.assertNotIn('referrals', self.fake.tables)  # 추천 연결 없음
        post = self.fake.by('POST', '/friend-reviews')
        self.assertEqual([(s['auth'], s['body']['reviewee_id']) for s in post], [('tok-1', 'id-2')])

    def test_12_fails_when_the_api_accepts_or_the_toast_differs(self):
        (result, note), _ = self.case('E-REV-12', said(toast=PROFILE_GONE, form=False))  # 서버 기본 200
        self.assertEqual(result, 'fail')
        self.assertIn('API', note)
        self.fake.on('POST', r'/friend-reviews', Reply(404, {'detail': PROFILE_GONE}))
        (result, _), _ = self.case('E-REV-12', said(toast=ALREADY, form=False))
        self.assertEqual(result, 'fail')


class ReviewListTest(PhoneBase):
    def card(self, n, **extra):
        return {'nickname': self.nick(n), 'tags': ['대화가 편해요'], 'comment': None, 'school': '테스트대학', **extra}

    def listing(self, cards=(), received=True, **extra):
        return said(cards=list(cards), relations=len(cards), notice=True, empty=not cards,
                    trash=0 if received else len(cards), flags=len(cards) if received else 0, waiting=False, **extra)

    def good_19(self, job):
        return self.listing([self.card(2, tags=THREE, comment='가' * 100)])

    def test_19_receiver_sees_the_card_with_flag_and_no_trash(self):
        (result, note), app = self.case('E-REV-19', self.good_19)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'received'}])
        row = self.fake.tables['friend_reviews'][0]
        self.assertEqual((row['reviewer_id'], row['reviewee_id'], row['tags'], row['comment']),
                         ('id-2', 'id-1', THREE, '가' * 100))
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-1', 'referrer_id': 'id-2'}])
        self.assert_all_home()

    def test_19_fails_on_tag_order_school_relation_trash_or_flag(self):
        cases = [
            lambda job: {**self.good_19(job), 'cards': [self.card(2, tags=THREE[::-1], comment='가' * 100)]},
            lambda job: {**self.good_19(job), 'cards': [self.card(2, tags=THREE, comment='가' * 99)]},
            lambda job: {**self.good_19(job), 'cards': [self.card(2, tags=THREE, comment='가' * 100, school=None)]},
            lambda job: {**self.good_19(job), 'relations': 0},
            lambda job: {**self.good_19(job), 'notice': False},
            lambda job: {**self.good_19(job), 'trash': 1},
            lambda job: {**self.good_19(job), 'flags': 0},
        ]
        for i, answer in enumerate(cases):
            (result, _), _ = self.case('E-REV-19', answer)
            self.assertEqual(result, 'fail', i)

    def test_21_no_received_reviews_is_the_empty_text(self):
        (result, note), app = self.case('E-REV-21', self.listing())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'received'}])
        self.assertNotIn('friend_reviews', self.fake.tables)
        self.assert_all_home()
        (result, _), _ = self.case('E-REV-21', {**self.listing(), 'empty': False})
        self.assertEqual(result, 'fail')

    def test_22_writer_sees_one_card_with_trash_and_no_waiting_friends(self):
        (result, note), app = self.case('E-REV-22', lambda job: self.listing([self.card(2)], received=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'written'}])
        row = self.fake.tables['friend_reviews'][0]
        self.assertEqual((row['reviewer_id'], row['reviewee_id'], row['tags']), ('id-1', 'id-2', ['대화가 편해요']))
        self.assert_all_home()

    def test_22_fails_on_waiting_section_or_missing_trash(self):
        for bad in ({'waiting': True}, {'trash': 0}, {'cards': []}):
            (result, _), _ = self.case('E-REV-22', lambda job, bad=bad: {**self.listing([self.card(2)], received=False), **bad})
            self.assertEqual(result, 'fail', bad)

    def test_23_no_written_reviews_is_the_empty_text_without_waiting_friends(self):
        (result, note), app = self.case('E-REV-23', self.listing(received=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'written'}])
        self.assertNotIn('referrals', self.fake.tables)  # 추천 연결 0 — "기다리는 친구" 칸이 없는 판
        for bad in ({'empty': False}, {'waiting': True}):
            (result, _), _ = self.case('E-REV-23', {**self.listing(received=False), **bad})
            self.assertEqual(result, 'fail', bad)

    def test_32_withdrawn_writer_review_disappears_but_the_row_stays(self):
        (result, note), app = self.case('E-REV-32', self.listing())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'received'}])
        patch = [s['body'] for s in self.fake.by('PATCH', '/rest/v1/profiles') if s['query']['id'] == 'eq.id-2'
                 and s['body'].get('status') == 'withdrawn']
        self.assertEqual(len(patch), 1)
        self.assertTrue(patch[0].get('withdrawn_at'))  # profiles_withdrawn_at_check — 키만이 아니라 값이 비어 있지 않아야 DB 가 받는다
        self.assertEqual(len(self.rows('friend_reviews', reviewer_id='id-2', reviewee_id='id-1')), 1)
        self.assert_all_home()

    def test_32_fails_when_the_card_still_shows_or_the_row_is_gone(self):
        (result, _), _ = self.case('E-REV-32', lambda job: self.listing([self.card(2)]))
        self.assertEqual(result, 'fail')

        def drops(job):
            self.fake.tables['friend_reviews'].clear()
            return self.listing()
        (result, note), _ = self.case('E-REV-32', drops)
        self.assertEqual(result, 'fail')
        self.assertIn('friend_reviews', note)

    def good_33(self, job):
        if job['variant'] == 'withdrawn':
            return self.listing(received=False)
        return self.listing([self.card(4)], received=False)

    def test_33_withdrawn_receiver_drops_out_but_suspended_stays(self):
        (result, note), app = self.case('E-REV-33', self.good_33)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'list': 'written', 'variant': 'withdrawn'},
                                    {'token_hash': 'h', 'list': 'written', 'variant': 'suspended'}])
        self.assertEqual(self.fake.statuses['id-2'], 'withdrawn')
        withdrawn = [s['body'] for s in self.fake.by('PATCH', '/rest/v1/profiles') if s['body'].get('status') == 'withdrawn']
        self.assertTrue(withdrawn and all(b.get('withdrawn_at') for b in withdrawn))  # profiles_withdrawn_at_check
        self.assertEqual(self.fake.statuses['id-4'], 'suspended')
        self.assertEqual([(r['reviewer_id'], r['reviewee_id']) for r in self.fake.tables['friend_reviews']],
                         [('id-1', 'id-2'), ('id-3', 'id-4')])
        self.assert_all_home()

    def test_33_fails_when_either_variant_is_wrong(self):
        swapped = lambda job: (self.listing([self.card(2)], received=False) if job['variant'] == 'withdrawn'
                               else self.listing(received=False))
        (result, note), _ = self.case('E-REV-33', swapped)
        self.assertEqual(result, 'fail')
        self.assertIn('withdrawn', note)
        self.assertIn('suspended', note)


class PartnerReviewsTest(PhoneBase):
    def test_29_three_reviews_show_two_cards_and_a_link_to_all(self):
        (result, note), app = self.case('E-REV-29', said(cards=2, link='3개 모두 보기', sheet=3, flags=0))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2', 'nickname': self.nick(2), 'open_sheet': True}])
        self.assert_pair(self.fake.tables['matches'][0]['id'], 'id-1', 'id-2')
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': f'id-{n}', 'referrer_id': 'id-2'} for n in (3, 4, 5)])
        posts = self.fake.by('POST', '/friend-reviews')
        self.assertEqual([(s['auth'], s['body']['reviewee_id']) for s in posts], [(f'tok-{n}', 'id-2') for n in (3, 4, 5)])
        self.assert_all_home()

    def test_29_fails_on_cards_link_sheet_or_flags(self):
        good = dict(cards=2, link='3개 모두 보기', sheet=3, flags=0)
        for bad in ({'cards': 3}, {'link': None}, {'sheet': 2}, {'flags': 1}):
            (result, _), _ = self.case('E-REV-29', said(**{**good, **bad}))
            self.assertEqual(result, 'fail', bad)

    def test_29_failed_review_post_is_blocked(self):
        self.fake.on('POST', r'/friend-reviews', Reply(500, {'detail': 'down'}))
        (result, _), app = self.case('E-REV-29', said(cards=2, link='3개 모두 보기', sheet=3, flags=0))
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])

    def test_30_two_reviews_have_no_link(self):
        (result, note), app = self.case('E-REV-30', said(cards=2, link=None, flags=0))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2', 'nickname': self.nick(2), 'open_sheet': False}])
        self.assertEqual(len(self.fake.by('POST', '/friend-reviews')), 2)
        (result, _), _ = self.case('E-REV-30', said(cards=2, link='2개 모두 보기', flags=0))
        self.assertEqual(result, 'fail')


class RegistryTest(PhoneBase):
    def test_bundle_is_the_19_screen_reading_cases(self):
        self.assertEqual(area3.BUNDLES['area3-phone-1'], BUNDLE)
        self.assertEqual(list(area3_phone.PHONE), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_main_runs_the_phone_bundle_through_area1_phone(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area3-phone-1'], BUNDLE)
        self.assertEqual(main.BUNDLES['area3-api'], area3.BUNDLES['area3-api'])
        self.assertFalse(set(BUNDLE) & set(main.API_CASES))

    def test_app_silence_is_fail_and_app_blocked_is_blocked(self):
        (result, _), _ = self.case('E-REV-21', lambda job: None)
        self.assertEqual(result, 'fail')
        (result, note), _ = self.case('E-REV-21', lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual((result, note), ('blocked', '앱: 못 찾음'))

    def test_account_failure_is_blocked_before_the_app(self):
        self.fake.on('POST', r'/auth/v1/admin/users', Reply(500, {'msg': 'down'}))
        for name in BUNDLE:
            (result, note), app = self.case(name, said())
            self.assertEqual(result, 'blocked', name)
            self.assertEqual(app.jobs, [], name)

    def test_every_job_names_its_screen_in_the_app(self):
        dart = (tools.ROOT / 'frontend' / 'integration_test' / 'area3.dart').read_text(encoding='utf-8')
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", dart, re.M), BUNDLE)  # 앱 쪽 area3Cases 도 같은 19개

    def test_my_tab_is_awaited_until_loaded_before_scrolling(self):
        # 나 탭은 GET /me/profile 이 끝나야 Scrollable 이 생긴다 — 화면 위젯만 기다리고 .first 를 부르면 "No element" 로 죽는다.
        for name in ('area3.dart', 'area3_b2.dart'):
            dart = (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')
            self.assertNotIn('pumpUntil(tester, find.byType(MyProfileScreen))', dart, name)
        main = (tools.ROOT / 'frontend' / 'integration_test' / 'area3.dart').read_text(encoding='utf-8')
        body = main[main.index('Future<void> _openMyTab'):]
        self.assertIn('find.byType(Scrollable)', body[:900])
        self.assertIn('Duration(seconds: 60)', body[:900])
        self.assertIn('MeLoadError', body[:1200])
        self.assertEqual(main.count('await _openMyTab(tester)'), 1)
        self.assertEqual((tools.ROOT / 'frontend' / 'integration_test' / 'area3_b2.dart').read_text(encoding='utf-8')
                         .count('await _openMyTab(tester)'), 1)


if __name__ == '__main__':
    unittest.main()
