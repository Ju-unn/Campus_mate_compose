"""영역 3 폰 A 한 대 8차(채팅 · 지인 리뷰 8개 + API E-CHAT-68)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_phone8`.

가짜 서버(test_area3.Fake)는 표만 들고 있어 채팅 · 리뷰 API 는 이 파일이 [Phone8.serve_chat] · [serve_reviews] 로 단다 —
올바른 서버면 pass, 어긋난 서버(공백을 안 깎음 · 나가면 글을 지움 · 가린 리뷰를 지움)면 fail 이어야 한다.
가짜 앱은 test_area3_phone.App, 계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 …(폰 계정이 늘 먼저다).
"""

import re
import unittest
from datetime import datetime, timedelta, timezone

from e2e import area1, area3, area3_phone8, tools
from e2e.test_area3_phone import said
from e2e.test_area3_phone2 import MidwayApp, Phone2, as_fn
from e2e.tools import Reply

ONE_TAG = ['대화가 편해요']
SUBMITTED = '리뷰를 남겼어요'
DELETED = '리뷰를 지웠어요'
REVIEW_GONE = '리뷰를 찾을 수 없어요'
NOT_FOUND = '대화를 찾을 수 없어요'
BUNDLE = ['E-CHAT-10', 'E-CHAT-16', 'E-REV-20', 'E-REV-24', 'E-REV-27', 'E-REV-31', 'E-REV-34', 'E-REV-35']
APP_KEYS = ['body', 'nickname', 'paste', 'profile_id', 'tags', 'list', 'about']  # PC 가 일감에 실어 보내는 키 — 앱이 읽어야 한다
BODY = '가' * 1000


def now():
    return datetime.now(timezone.utc)


class Phone8(Phone2):
    def setUp(self):
        super().setUp()
        self.made = 0

    # ── 가짜 서버 ────────────────────────────────────────────────────────────────────────────────────

    @staticmethod
    def who(sent):
        return sent['auth'].replace('tok-', 'id-')

    def serve_chat(self, trim=True, leave_deletes=False, leave_line=True):
        def send(sent):
            body = sent['body']['body']
            self.put('messages', match_id=sent['path'].split('/')[3], sender_id=self.who(sent), kind='text',
                     body=body.strip() if trim else body, created_at=now().isoformat())
            return Reply(201, {})

        def read(sent):
            match_id = sent['path'].split('/')[3]
            if any(p.get('left_at') for p in self.rows('match_participants', match_id=match_id, profile_id=self.who(sent))):
                return Reply(404, {'detail': NOT_FOUND})
            return Reply(200, {'messages': [dict(m) for m in self.rows('messages', match_id=match_id)]})

        def leave(sent):
            match_id = sent['path'].split('/')[3]
            for row in self.rows('match_participants', match_id=match_id, profile_id=self.who(sent)):
                row['left_at'] = now().isoformat()
            if leave_deletes:
                self.fake.tables['messages'] = [m for m in self.fake.tables['messages'] if m.get('match_id') != match_id]
            if leave_line:
                self.put('messages', match_id=match_id, sender_id=self.who(sent), kind='left', body='나갔어요', created_at=now().isoformat())
            return Reply(200, {})

        self.fake.on('POST', r'/chat/matches/[^/]+/messages', send)
        self.fake.on('GET', r'/chat/matches/[^/]+/messages', read)
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', leave)

    def serve_reviews(self, delete_blinded=False):
        def live(row):
            return row.get('status', 'active') == 'active'

        def create(sent):
            self.made += 1
            self.put('friend_reviews', id=f'r{self.made}', reviewer_id=self.who(sent), reviewee_id=sent['body']['reviewee_id'],
                     tags=sent['body']['tags'])
            return Reply(201, {'id': f'r{self.made}'})

        def received(sent):
            return Reply(200, {'reviews': [dict(r) for r in self.rows('friend_reviews', reviewee_id=self.who(sent)) if live(r)]})

        def delete(sent):
            review_id = sent['path'].rsplit('/', 1)[1]
            for row in self.rows('friend_reviews', id=review_id, reviewer_id=self.who(sent)):
                if live(row) or delete_blinded:
                    self.fake.tables['friend_reviews'].remove(row)
                    return Reply(204, None)
            return Reply(404, {'detail': REVIEW_GONE})

        def block(sent):
            self.put('blocks', blocker_id=self.who(sent), blocked_id=sent['path'].rsplit('/', 1)[1])
            return Reply(200, {})

        self.fake.on('POST', r'/friend-reviews', create)
        self.fake.on('GET', r'/friend-reviews/received', received)
        self.fake.on('DELETE', r'/friend-reviews/[^/]+', delete)
        self.fake.on('POST', r'/blocks/[^/]+', block)

    def api_case(self, name):
        """폰 없는 API 가설 하나를 깨끗한 가짜 서버에서(시험이 단 API 는 둔다)."""
        self.fake.tables.clear()
        self.fake.sent.clear()
        self.fake.statuses.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        return area3_phone8.attempt(self.run_, name)

    def delay(self, seconds, **extra):
        """앱이 방 뷰모델에서 그 글을 본 시각 = 서버가 찍은 보낸 시각 + [seconds]."""
        sent = self.rows('messages')[0]
        return said(seen_at=(datetime.fromisoformat(sent['created_at']) + timedelta(seconds=seconds)).isoformat(),
                    **{'loaded': True, **extra})


# ── E-CHAT-10 · 16 ───────────────────────────────────────────────────────────────────────────────────

class LongTest(Phone8):
    def run10(self, answer):
        events = []
        return self.case('E-CHAT-10', answer, MidwayApp(as_fn(answer), 'ready', events)), events

    def test_10_partner_sends_1000_hangul_while_the_app_waits_and_b_shows_it_in_time(self):
        self.serve_chat()
        ((result, note), app), events = self.run10(lambda job: self.delay(1.2, bubble=True))
        self.assertEqual((result, note[:3]), ('pass', '지연 '))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'body': BODY}])
        self.assertEqual(events, ['step', 'go'])
        sends = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([(s['auth'], len(s['body']['body'])) for s in sends], [('tok-2', 1000)])  # A(상대)가 보낸다
        self.assertEqual([len(r['body']) for r in self.rows('messages', sender_id='id-2')], [1000])
        self.assert_all_home()

    def test_10_fails_on_a_missing_bubble_a_slow_display_or_a_cut_body(self):
        self.serve_chat()
        for answer in (lambda job: self.delay(1.0, bubble=False), lambda job: self.delay(3.0, bubble=True),
                       lambda job: said(bubble=True), lambda job: said(seen_at='not a time', bubble=True)):
            (result, _), _ = self.run10(answer)[0]
            self.assertEqual(result, 'fail')

    def test_10_a_room_that_never_finished_loading_is_blocked_and_nothing_is_sent(self):
        """앱이 방 읽기를 못 끝냈다고 하면(구독 전에 보내면 가짜 실패) 글을 보내기 전에 멈춘다 — 실제 앱은 이때 step 을 부르지 않는다."""
        self.serve_chat()
        (result, note), _ = self.case('E-CHAT-10', lambda job: said(loaded=False, error=None, seen_at=None, bubble=False))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('안 읽힘', note)
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])

    def test_10_an_app_that_does_not_say_loaded_fails(self):
        self.serve_chat()
        (result, note), _ = self.run10(lambda job: self.delay(1.0, bubble=True, loaded=None))[0]
        self.assertEqual(result, 'fail', note)
        self.assertIn('방 읽기', note)

    def test_10_a_negative_delay_is_set_aside_as_a_clock_difference_not_judged(self):
        self.serve_chat()
        (result, note), _ = self.run10(lambda job: self.delay(-3.0, bubble=True))[0]
        self.assertEqual(result, 'pass', note)
        self.assertIn('판정 불가', note)
        self.assertIn('시계 차', note)

    def test_10_a_slow_display_is_still_a_fail_next_to_the_clock_rule(self):
        self.serve_chat()
        (result, note), _ = self.run10(lambda job: self.delay(2.5, bubble=True))[0]
        self.assertEqual(result, 'fail', note)
        self.assertIn('2.0', note)

    def test_10_fails_when_the_server_stores_a_shorter_body(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', lambda sent: (self.put(
            'messages', match_id=self.match(), sender_id='id-2', kind='text', body=sent['body']['body'][:999],
            created_at=now().isoformat()), Reply(201, {}))[1])
        (result, note), _ = self.run10(lambda job: self.delay(1.0, bubble=True))[0]
        self.assertEqual(result, 'fail')
        self.assertIn('DB body', note)

    def test_10_a_rejected_send_fails_before_judging_the_screen(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(422, {'detail': 'too long'}))
        (result, note), _ = self.run10(said(bubble=True, seen_at=now().isoformat()))[0]
        self.assertEqual(result, 'fail')
        self.assertIn('A 보내기', note)


class TrimTest(Phone8):
    def sending(self, text='안녕', **extra):
        def answer(job):
            self.text_sent(text)
            return said(**{'bubbles': [text], 'error': None, **extra})
        return answer

    def test_16_app_and_server_both_trim_and_b_reads_the_trimmed_text(self):
        self.serve_chat()
        (result, note), app = self.case('E-CHAT-16', self.sending())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'paste': {'runes': [32, 32, 0xC548, 0xB155, 32, 32], 'count': 1}}])
        self.assertEqual([r['body'] for r in self.rows('messages', kind='text')], ['안녕', '안녕'])
        read = self.fake.by('GET', '/chat/matches/')
        self.assertEqual([s['auth'] for s in read], ['tok-2'])  # B 의 토큰으로 읽는다
        self.assert_all_home()

    def test_16_fails_when_the_app_keeps_the_spaces_or_shows_them(self):
        self.serve_chat()
        (result, note), _ = self.case('E-CHAT-16', self.sending('  안녕  '))
        self.assertEqual(result, 'fail')
        self.assertIn('앱이 보낸 글', note)
        (result, note), _ = self.case('E-CHAT-16', self.sending(bubbles=['  안녕  ']))
        self.assertEqual(result, 'fail')
        self.assertIn('내 화면 말풍선', note)

    def test_16_fails_when_the_server_stores_the_spaces(self):
        self.serve_chat(trim=False)
        (result, note), _ = self.case('E-CHAT-16', self.sending())
        self.assertEqual(result, 'fail')
        self.assertIn('DB body', note)

    def test_16_a_screen_error_fails(self):
        self.serve_chat()
        (result, note), _ = self.case('E-CHAT-16', self.sending(error='메시지를 보내지 못했어요'))
        self.assertEqual(result, 'fail')
        self.assertIn('오류 문구', note)


# ── E-CHAT-68 (API) ──────────────────────────────────────────────────────────────────────────────────

class KeptTest(Phone8):
    def test_68_closed_room_keeps_its_rows_and_left_room_gains_one_left_line(self):
        self.serve_chat()
        result, note = self.api_case('E-CHAT-68')
        self.assertEqual(result, 'pass', note)
        self.assertIn('chat_closed_at', note)
        self.assertEqual([bool(m.get('chat_closed_at')) for m in self.rows('matches')], [True, False])  # 닫힘은 한 방에만
        closed, left = [m['id'] for m in self.rows('matches')]
        self.assertEqual((len(self.rows('messages', match_id=closed)), len(self.rows('messages', match_id=left))), (3, 4))
        self.assertEqual([m['match_id'] for m in self.rows('messages', kind='left')], [left])
        self.assertEqual(self.fake.by('POST', '/chat/matches/')[0]['auth'], 'tok-3')  # 나간 방 쪽 계정이 나간다

    def test_68_fails_when_leaving_deletes_messages(self):
        self.serve_chat(leave_deletes=True)
        result, note = self.api_case('E-CHAT-68')
        self.assertEqual(result, 'fail')
        self.assertIn('나간 방', note)

    def test_68_fails_when_leaving_leaves_no_line(self):
        self.serve_chat(leave_line=False)
        result, note = self.api_case('E-CHAT-68')
        self.assertEqual(result, 'fail')
        self.assertIn('나감 줄', note)

    def test_68_a_failed_leave_fails_with_its_status(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', Reply(500, {'detail': 'down'}))
        self.fake.on('GET', r'/chat/matches/[^/]+/messages', Reply(200, {'messages': []}))
        result, note = self.api_case('E-CHAT-68')
        self.assertEqual(result, 'fail')
        self.assertIn('나가기', note)

    def test_68_a_setup_failure_is_blocked(self):
        self.fake.on('POST', r'/rest/v1/matches', Reply(500, {'message': 'down'}))
        result, note = self.api_case('E-CHAT-68')
        self.assertEqual(result, 'blocked')
        self.assertIn('matches', note)


# ── 지인 리뷰 ────────────────────────────────────────────────────────────────────────────────────────

class CountTest(Phone8):
    def test_20_one_account_has_two_received_and_one_written_and_the_tab_says_so(self):
        (result, note), app = self.case('E-REV-20', said(received='받은 리뷰 2개', written='쓴 리뷰 1개'))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(len(self.rows('friend_reviews', reviewee_id='id-1')), 2)
        self.assertEqual(len(self.rows('friend_reviews', reviewer_id='id-1')), 1)
        self.assert_all_home()

    def test_20_fails_on_a_wrong_or_missing_count(self):
        for answer in (said(received='받은 리뷰 1개', written='쓴 리뷰 1개'), said(received='받은 리뷰 2개', written='쓴 리뷰 2개'),
                       said(received='받은 리뷰 2개'), said()):
            (result, _), _ = self.case('E-REV-20', answer)
            self.assertEqual(result, 'fail')


class DeleteTest(Phone8):
    def deleting(self, **extra):
        def answer(job):
            self.fake.tables['friend_reviews'].clear()
            return said(**{'toast': DELETED, 'cards': 0, 'received': '받은 리뷰 0개', 'written': '쓴 리뷰 0개', **extra})
        return answer

    def test_24_deleting_clears_the_card_the_tab_the_row_and_the_receivers_list(self):
        self.serve_reviews()
        (result, note), app = self.case('E-REV-24', self.deleting())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual([s['auth'] for s in self.fake.by('GET', '/friend-reviews/received')], ['tok-2'])  # B 의 토큰으로 읽는다
        self.assert_all_home()

    def test_24_fails_on_a_wrong_toast_card_count_or_tab_count(self):
        self.serve_reviews()
        for extra in ({'toast': '삭제했어요'}, {'cards': 1}, {'written': '쓴 리뷰 1개'}):
            (result, _), _ = self.case('E-REV-24', self.deleting(**extra))
            self.assertEqual(result, 'fail', extra)

    def test_24_fails_when_the_row_or_the_receivers_copy_survives(self):
        self.serve_reviews()
        (result, note), _ = self.case('E-REV-24', said(toast=DELETED, cards=0, written='쓴 리뷰 0개'))  # 앱이 화면만 지움
        self.assertEqual(result, 'fail')
        self.assertIn('friend_reviews', note)
        self.assertIn('B 의 받은 리뷰', note)


class WriteAgainTest(Phone8):
    def writing(self, review_id='new', **extra):
        def answer(job):
            self.put('friend_reviews', id=review_id, reviewer_id='id-1', reviewee_id='id-2', tags=ONE_TAG)
            return said(**{'toast': SUBMITTED, 'closed': True, **extra})
        return answer

    def test_27_after_delete_the_same_person_can_be_written_again_with_a_new_id(self):
        self.serve_reviews()
        (result, note), app = self.case('E-REV-27', self.writing())
        self.assertEqual(result, 'pass')
        self.assertIn('알림', note)  # 알림 반쪽을 안 본다는 메모
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2', 'tags': ONE_TAG}])
        self.assertEqual([r['id'] for r in self.rows('friend_reviews')], ['new'])
        self.assertEqual([s['method'] for s in self.fake.sent if s['path'].startswith('/friend-reviews')], ['POST', 'DELETE'])
        self.assert_all_home()

    def test_27_fails_on_the_old_id_a_missing_row_a_second_row_or_a_wrong_toast(self):
        self.serve_reviews()
        for answer in (self.writing('r1'), said(toast=SUBMITTED, closed=True), self.writing(toast='이미 리뷰를 남겼어요'),
                       lambda job: (self.writing('a')(job), self.writing('b')(job))[1]):
            (result, _), _ = self.case('E-REV-27', answer)
            self.assertEqual(result, 'fail')

    def test_27_a_failed_first_write_fails_with_the_status(self):
        self.fake.on('POST', r'/friend-reviews', Reply(404, {'detail': '프로필을 찾을 수 없어요'}))
        (result, note), _ = self.case('E-REV-27', self.writing())
        self.assertEqual(result, 'fail')
        self.assertIn('첫 작성', note)


class HiddenTest(Phone8):
    """E-REV-31 · 34 · 35 — 앱이 켜질 때마다 가짜 앱이 서버 상태(정지 · 차단)에 맞게 0장 또는 1장을 말한다."""

    def card_count(self, shown):
        return lambda job: (said(cards=shown, loaded=True, error=None) if 'about' in job
                            else said(cards=[{}] * shown, empty=shown == 0))

    def test_31_a_suspended_author_hides_the_cards_and_active_brings_them_back(self):
        def app(job):
            return self.card_count(0 if self.fake.statuses.get('id-2') == 'suspended' else 1)(job)
        (result, note), phone = self.case('E-REV-31', app)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual([j.get('list') or 'about' for j in phone.jobs], ['received', 'about', 'received', 'about'])
        self.assertEqual({j['token_hash'] for j in phone.jobs}, {'h'})
        self.assertEqual(phone.jobs[1]['about'], 'id-3')  # 폰 계정과 매칭된 X 의 14c
        self.assertEqual(self.fake.statuses['id-2'], 'active')  # 어떻게 끝나도 작성자는 active
        self.assert_all_home()

    def test_31_fails_when_the_suspended_author_is_still_shown_or_the_restore_is_not(self):
        for shown in ((1, 1), (0, 0)):  # (정지 중, 해제 뒤)
            def app(job, shown=shown):
                return self.card_count(shown[0] if self.fake.statuses.get('id-2') == 'suspended' else shown[1])(job)
            (result, _), _ = self.case('E-REV-31', app)
            self.assertEqual(result, 'fail', shown)
            self.assertEqual(self.fake.statuses['id-2'], 'active')

    def test_31_an_unfinished_14c_read_fails_instead_of_passing_as_zero(self):
        (result, note), _ = self.case('E-REV-31', lambda job: said(cards=0, loaded=False, error=None) if 'about' in job else said(cards=[], empty=True))
        self.assertEqual(result, 'fail')
        self.assertIn('읽기 끝', note)

    def test_34_a_blinded_review_vanishes_everywhere_and_cannot_be_deleted(self):
        self.serve_reviews()
        (result, note), app = self.case('E-REV-34', self.card_count(0))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual([j.get('list') or 'about' for j in app.jobs], ['written', 'received', 'about'])
        self.assertEqual(self.rows('friend_reviews')[0]['status'], 'blinded')
        self.assertEqual([(s['method'], s['auth']) for s in self.fake.sent if s['path'].startswith('/friend-reviews/')],
                         [('GET', 'tok-2'), ('DELETE', 'tok-1')])  # 가리기 전 대조군(B 가 받은 목록) → 작성자 지우기
        self.assert_all_home()

    def test_34_is_blocked_when_the_review_is_not_visible_to_b_before_it_is_blinded(self):
        """가리기 전에 B 의 받은 목록에 그 리뷰가 1장 있어야 "0장" 이 가림 때문이라는 증거가 된다."""
        self.serve_reviews()
        self.fake.handlers.insert(0, ('GET', re.compile(r'/friend-reviews/received'), Reply(200, {'reviews': []})))
        (result, note), app = self.case('E-REV-34', self.card_count(0))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('가리기 전', note)
        self.assertEqual(app.jobs, [])  # 앱을 켜지 않는다
        self.assertEqual(self.rows('friend_reviews')[0].get('status'), None)  # 가리지도 않았다

    def test_34_fails_when_a_card_shows_the_delete_goes_through_or_the_empty_text_is_missing(self):
        self.serve_reviews()
        (result, _), _ = self.case('E-REV-34', self.card_count(1))
        self.assertEqual(result, 'fail')
        (result, note), _ = self.case('E-REV-34', lambda job: said(cards=[], empty=False) if 'list' in job else said(cards=0, loaded=True, error=None))
        self.assertEqual((result, '빈 문구' in note), ('fail', True))
        self.fake.handlers.clear()
        self.serve_reviews(delete_blinded=True)
        (result, note), _ = self.case('E-REV-34', self.card_count(0))
        self.assertEqual(result, 'fail')
        self.assertIn('작성자 지우기', note)

    def test_34_fails_when_the_delete_is_a_404_but_the_row_is_gone(self):
        def delete(sent):  # 404 를 말하면서 행은 지운다
            self.fake.tables['friend_reviews'].clear()
            return Reply(404, {'detail': REVIEW_GONE})
        self.serve_reviews()
        self.fake.handlers.insert(0, ('DELETE', re.compile(r'/friend-reviews/[^/]+'), delete))
        (result, note), _ = self.case('E-REV-34', self.card_count(0))
        self.assertEqual(result, 'fail')
        self.assertIn('friend_reviews 0행', note)

    def test_35_blocking_the_author_hides_it_only_from_the_blocker(self):
        self.serve_reviews()

        def app(job):
            if 'list' in job:
                return said(cards=[{}], empty=False)  # B 는 C 와 차단이 없다 — 1장
            return self.card_count(0 if self.rows('blocks') else 1)(job)
        (result, note), phone = self.case('E-REV-35', app)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual([j.get('list') or 'about' for j in phone.jobs], ['about', 'about', 'received'])
        self.assertEqual(self.rows('blocks'), [{'blocker_id': 'id-1', 'blocked_id': 'id-3'}])  # A 가 C 를 차단
        self.assert_all_home()

    def test_35_fails_without_a_control_or_with_a_hidden_receiver_or_a_block_that_hides_nothing(self):
        self.serve_reviews()
        for label, app in (('대조군', lambda job: self.card_count(0)(job) if 'about' in job else said(cards=[{}], empty=False)),
                           ('안 가려짐', lambda job: self.card_count(1)(job) if 'about' in job else said(cards=[{}], empty=False)),
                           ('B 도 가려짐', lambda job: self.card_count(0 if self.rows('blocks') else 1)(job) if 'about' in job
                            else said(cards=[], empty=True))):
            (result, _), _ = self.case('E-REV-35', app)
            self.assertEqual(result, 'fail', label)

    def test_35_a_failed_block_fails_with_its_status(self):
        self.fake.on('POST', r'/blocks/[^/]+', Reply(409, {'detail': 'no match'}))
        (result, note), _ = self.case('E-REV-35', self.card_count(1))
        self.assertEqual(result, 'fail')
        self.assertIn('A 가 C 차단', note)


class PhoneContractTest(Phone8):
    def test_app_silence_is_fail_and_app_blocked_is_blocked(self):
        self.serve_chat()
        self.serve_reviews()
        for name in BUNDLE:
            (result, _), _ = self.case(name, lambda job: None)
            self.assertEqual(result, 'fail', name)
        (result, note), _ = self.case('E-REV-20', lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual((result, note), ('blocked', '앱: 못 찾음'))

    def test_notification_permission_is_granted_and_revoked_around_each_phone_case(self):
        self.case('E-REV-20', said(received='받은 리뷰 2개', written='쓴 리뷰 1개'))
        self.assertEqual([n for n, _ in self.perm], ['grant', 'revoke'])


# ── 등록 ─────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(Phone8):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_bundle_is_the_eight_phone_cases_plus_the_api_case(self):
        self.assertEqual(area3.BUNDLES['area3-phone-8'], BUNDLE + ['E-CHAT-68'])
        self.assertEqual(list(area3_phone8.PHONE8), BUNDLE)
        self.assertEqual(list(area3_phone8.CASES), ['E-CHAT-68'])
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))
        self.assertNotIn('E-CHAT-68', area1.PHONE)
        for name, cases in area3.BUNDLES.items():
            if name != 'area3-phone-8':
                self.assertFalse(set(cases) & set(BUNDLE + ['E-CHAT-68']), name)  # 다른 묶음과 안 겹친다

    def test_main_runs_the_phone_cases_through_the_phone_and_the_api_case_through_the_module(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area3-phone-8'], BUNDLE + ['E-CHAT-68'])
        self.assertIs(main.API_CASES['E-CHAT-68'], area3_phone8)
        self.assertFalse(set(BUNDLE) & set(main.API_CASES))

    def test_the_cases_that_open_the_app_several_times_get_more_time(self):
        for name in ('E-REV-31', 'E-REV-34', 'E-REV-35'):
            self.assertEqual(tools.CASE_LIMITS[name], area3_phone8.CASE_LIMIT)

    def test_every_job_key_is_read_by_the_app(self):
        dart = ''.join(self.dart(n) for n in ('area3.dart', 'area3_b2.dart', 'area3_b8.dart'))
        for key in APP_KEYS:
            self.assertIn(f"job['{key}']", dart, key)

    def test_the_app_has_the_same_eight_numbers_in_order_and_area3_merges_them(self):
        part = self.dart('area3_b8.dart')
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), BUNDLE)
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        main = self.dart('area3.dart')
        self.assertIn("part 'area3_b8.dart';", main)
        self.assertIn('...area3Cases8', main)

    def test_the_app_does_not_redeclare_helpers_of_the_other_parts(self):
        names = lambda text: set(re.findall(r'^(?=\S)[A-Za-z<>?,\' ]+? (_[A-Za-z0-9]+)\b', text, re.M))  # noqa: E731 — 줄 맨 앞(최상위) 선언만
        mine = names(self.dart('area3_b8.dart'))
        for other in ('area3.dart', 'area3_b2.dart', 'area3_b3.dart', 'area3_b4.dart', 'area3_b5.dart', 'area3_safe.dart'):
            self.assertFalse(mine & names(self.dart(other)), other)


if __name__ == '__main__':
    unittest.main()
