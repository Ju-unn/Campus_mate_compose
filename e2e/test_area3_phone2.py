"""영역 3 폰 A 한 대 2차(채팅 · 지인 리뷰 상호작용 19개)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_phone2`.

가짜 서버는 e2e/test_area3.py 의 Fake, 가짜 앱은 test_area3_phone.py 의 App 을 쓴다. 가짜 서버는 API 가 쓰는 행을 저절로 만들지 않으므로
"앱이 보냈다" 는 시험이 가짜 앱 안에서 messages · friend_reviews · reports 행을 직접 넣어 흉내 낸다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 …(폰 계정이 늘 먼저다).
"""

import re
import unittest
from datetime import datetime, timezone
from unittest import mock

from e2e import area1, area3, area3_phone2, notify, tools
from e2e.test_area3_phone import App, PhoneBase, said
from e2e.tools import Reply, Run

SMILE = chr(0x1F600)
FAMILY = ''.join(map(chr, [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]))
ONE_TAG = ['대화가 편해요']
THREE = ['약속을 잘 지켜요', '대화가 편해요', '성실해요']
FOUR = THREE + ['배려가 깊어요']
SUBMITTED = '리뷰를 남겼어요'
ALREADY = '이미 리뷰를 남겼어요'
REPORTED = '신고했어요. 운영팀이 확인할게요'
ALREADY_REPORTED = '이미 신고를 완료했어요'
NETWORK = '네트워크 연결을 확인해 주세요'
BUNDLE = ['E-CHAT-04', 'E-CHAT-05', 'E-CHAT-11', 'E-CHAT-12', 'E-CHAT-13', 'E-CHAT-15', 'E-CHAT-25', 'E-CHAT-43',
          'E-REV-01', 'E-REV-02', 'E-REV-03', 'E-REV-04', 'E-REV-05', 'E-REV-06', 'E-REV-07', 'E-REV-11', 'E-REV-25',
          'E-REV-36', 'E-REV-37']


def paste(char, count):
    runes = [ord(c) for c in char]
    return {'runes': runes, 'count': count}


class MidwayApp(App):
    """앱이 `step` 에서 멈췄다가 PC 가 일을 하고 go 를 넣으면 이어 가는 것을 흉내 낸다 — [events] 에 'step' · 'go' 를 남긴다."""

    def __init__(self, answer, step, events):
        super().__init__(answer)
        self.step, self.events, self.serial = step, events, 'S'

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        self.midway_given = midway is not None
        if midway:
            self.events.append('step')
            midway({'step': self.step})
            self.events.append('go')
        return self.answer(job)


class Phone2(PhoneBase):
    def setUp(self):
        super().setUp()
        for patcher in (mock.patch('time.sleep'),  # 계정 공장의 기다림은 가짜 서버라 필요 없다
                        mock.patch.object(Run, 'remember')):  # accounts.json 을 계정마다 열고 쓰는 것이 느리다(가설은 읽지 않는다)
            patcher.start()
            self.addCleanup(patcher.stop)

    def case(self, name, answer, app=None):
        self.fake.tables.clear()
        self.fake.sent.clear()
        self.fake.statuses.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        app = app or App(as_fn(answer))
        return area1.attempt_phone(self.run_, name, app), app

    def match(self):
        return self.fake.tables['matches'][0]['id']

    def put(self, table, **row):
        self.fake.tables.setdefault(table, []).append(row)

    def text_sent(self, body, kind='text', sender='id-1'):
        self.put('messages', match_id=self.match(), sender_id=sender, kind=kind, body=body)

    def sending(self, bodies, **extra):
        """앱이 보내서 messages 에 [bodies](목록, 또는 일감 → 목록) 가 들어간 것처럼 — 그리고 [extra] 를 말한다."""
        def answer(job):
            for body in bodies(job) if callable(bodies) else bodies:
                self.text_sent(body)
            return said(**extra)
        return answer

    def reviews(self, reviewer='id-1', reviewee='id-2'):
        return self.rows('friend_reviews', reviewer_id=reviewer, reviewee_id=reviewee)


def as_fn(answer):
    """앱이 늘 같은 말을 하는 시험은 dict 로 쓴다."""
    return (lambda job: dict(answer)) if isinstance(answer, dict) else answer


def pasted(job):
    return ''.join(map(chr, job['paste']['runes'])) * job['paste']['count']


# ── 채팅 ─────────────────────────────────────────────────────────────────────────────────────────────

class ChatSendTest(Phone2):
    def base_job(self):
        return {'token_hash': 'h', 'nickname': self.nick(2)}

    def test_04_one_message_is_one_bubble_and_one_row(self):
        (result, note), app = self.case('E-CHAT-04', self.sending(['E2E-04'], lines=1))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{**self.base_job(), 'text': 'E2E-04'}])
        self.assertEqual(len(self.rows('matches')), 1)
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_04_fails_on_a_doubled_bubble_a_missing_row_or_a_second_row(self):
        for answer in (self.sending(['E2E-04'], lines=2), self.sending(['E2E-04'], lines=0),
                       self.sending(['E2E-04'] * 2, lines=1), self.sending([], lines=1),
                       self.sending(['다른 글'], lines=1), self.sending(['E2E-04'])):
            (result, _), _ = self.case('E-CHAT-04', answer)
            self.assertEqual(result, 'fail')

    def test_04_only_my_text_rows_count(self):
        def answer(job):  # 상대가 쓴 글 · 시스템 줄은 내 보내기가 아니다
            self.text_sent('E2E-04')
            self.text_sent('E2E-04', sender='id-2')
            self.text_sent('수락', kind='trust_accept')
            return said(lines=1)
        (result, note), _ = self.case('E-CHAT-04', answer)
        self.assertEqual((result, note), ('pass', ''))

    def test_05_five_fast_taps_leave_one_row(self):
        (result, note), app = self.case('E-CHAT-05', self.sending(['연타']))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{**self.base_job(), 'text': '연타'}])
        self.assert_all_home()

    def test_05_fails_on_five_rows_or_none(self):
        for rows in (['연타'] * 5, ['연타'] * 2, []):
            (result, note), _ = self.case('E-CHAT-05', self.sending(rows))
            self.assertEqual(result, 'fail', rows)
            self.assertIn('messages', note)

    def long_case(self, name, unit, count):
        want = (unit * count)[:1000]
        (result, note), app = self.case(name, self.sending(lambda job: [pasted(job)[:1000]], input_len=1000, error=None))
        self.assertEqual((result, note), ('pass', ''), name)
        self.assertEqual(app.jobs, [{**self.base_job(), 'paste': paste(unit, count)}])
        self.assertEqual([r['body'] for r in self.rows('messages')], [want])
        self.assertEqual(len(want), 1000)  # 코드포인트로 천 자
        self.assert_all_home()

    def test_11_1001_korean_letters_are_cut_to_1000(self):
        self.long_case('E-CHAT-11', '가', 1001)

    def test_12_smiles_are_counted_by_code_point(self):
        self.long_case('E-CHAT-12', SMILE, 1001)

    def test_13_family_emoji_201_are_cut_at_1000_code_points(self):
        self.long_case('E-CHAT-13', FAMILY, 201)
        self.assertEqual(len(FAMILY), 5)  # 코드포인트 5개짜리 합성 글자

    def test_long_cases_fail_when_the_field_or_db_is_wrong(self):
        for name, unit, count in (('E-CHAT-11', '가', 1001), ('E-CHAT-12', SMILE, 1001), ('E-CHAT-13', FAMILY, 201)):
            good = (unit * count)[:1000]
            wrong = (
                self.sending([good], input_len=1001, error=None),  # 입력칸이 안 잘림
                self.sending([good], input_len=999, error=None),
                self.sending([good], error=None),  # 앱이 글자 수를 안 말함
                self.sending([good], input_len=1000, error='서버가 거절'),  # 화면 오류 문구(422)
                self.sending([good], input_len=1000),  # 오류 칸을 안 말함
                self.sending([unit * count], input_len=1000, error=None),  # DB 에 안 잘린 글
                self.sending([good[:-1]], input_len=1000, error=None),  # DB 에 999
                self.sending([], input_len=1000, error=None),  # 안 저장됨
                self.sending([good, good], input_len=1000, error=None),  # 두 줄
            )
            for i, answer in enumerate(wrong):
                (result, _), _ = self.case(name, answer)
                self.assertEqual(result, 'fail', f'{name} #{i}')

    def test_15_blank_text_is_disabled_in_the_app_and_422_in_the_api(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(422, {'detail': [{'msg': 'blank'}]}))
        (result, note), app = self.case('E-CHAT-15', said(send_enabled=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{**self.base_job(), 'paste': paste(' ', 5)}])
        sent = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([(s['auth'], s['body']) for s in sent], [('tok-1', {'body': '   \n '})])  # 공백 셋 · 줄바꿈 · 공백
        self.assertEqual(self.rows('messages'), [])
        self.assert_all_home()

    def test_15_fails_when_the_button_is_on_the_api_accepts_or_a_row_appears(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(422, {'detail': 'x'}))
        for answer in (said(send_enabled=True), said(), self.sending(['x'], send_enabled=False)):
            (result, _), _ = self.case('E-CHAT-15', answer)
            self.assertEqual(result, 'fail')
        self.fake.handlers.clear()  # 서버가 공백을 받아 버린다
        (result, note), _ = self.case('E-CHAT-15', said(send_enabled=False))
        self.assertEqual(result, 'fail')
        self.assertIn('API', note)


class OfflineSendTest(Phone2):
    """E-CHAT-25 — 망을 끊고 보낸다. 실제 adb 는 부르지 않고 가짜 adb 가 부른 순서를 남긴다."""

    def setUp(self):
        super().setUp()
        self.events = []
        self.state = {'airplane': 'disabled'}

        def fake_adb(serial, *args, check=True):
            self.events.append(('adb', serial, args))
            if args[-1] in ('enable', 'disable'):
                self.state['airplane'] = args[-1] + 'd'
            return self.state['airplane'] + '\n' if args[-1] == 'airplane-mode' else ''

        for patcher in (mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(notify.time, 'sleep'),
                        mock.patch.object(Run, 'shot')):
            patcher.start()
            self.addCleanup(patcher.stop)

    def offline(self, answer):
        app = MidwayApp(as_fn(answer), 'cut', self.events)
        return self.case('E-CHAT-25', answer, app)

    def good(self, job):
        return said(error=NETWORK, error_cleared=True, input='테스트', disconnected=True)

    def airplane_calls(self):
        return [(i, e[2][-1]) for i, e in enumerate(self.events) if e[0] == 'adb' and e[2][-2:-1] == ('airplane-mode',)]

    def test_cut_then_go_then_restore_and_the_message_stays_in_the_input(self):
        (result, note), app = self.offline(self.good)
        self.assertEqual(result, 'pass')
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'text': '테스트'}])
        self.assertTrue(app.midway_given)
        names = [e if isinstance(e, str) else e[2][-1] for e in self.events]
        enable, go, disable = names.index('enable'), names.index('go'), names.index('disable')
        self.assertLess(enable, go)
        self.assertLess(go, disable)  # 끊기 → go → 켜기
        first = next(e for e in self.events if e != 'step')
        self.assertEqual(first, ('adb', 'S', ('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')))
        self.assertIn(('adb', 'S', ('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable')), self.events)
        self.assertEqual(self.state['airplane'], 'disabled')
        self.assertEqual(self.rows('messages'), [])
        self.assert_all_home()

    def test_note_tells_whether_realtime_cut_cleared_the_error_line(self):
        for cleared, banner in ((True, True), (False, False)):
            (result, note), _ = self.offline(lambda job: said(error=NETWORK, error_cleared=cleared, input='테스트', disconnected=banner))
            self.assertEqual(result, 'pass')
            self.assertIn(f'지우는지: {cleared}, 끊김 배너 {banner}', note)
            self.assertIn('chat_room_ui_state.dart:106', note)

    def test_fails_when_the_first_error_is_missing_even_if_cleared_later(self):
        (result, _), _ = self.offline(said(error=None, error_cleared=True, input='테스트', disconnected=True))
        self.assertEqual(result, 'fail')

    def test_fails_when_the_text_is_gone_the_message_differs_or_a_row_was_saved(self):
        for answer in (said(error=NETWORK, input=''), said(error=NETWORK), said(error='잠시 뒤 다시', input='테스트'),
                       said(input='테스트'), self.sending(['테스트'], error=NETWORK, input='테스트')):
            (result, _), _ = self.offline(answer)
            self.assertEqual(result, 'fail')
            self.assertEqual(self.state['airplane'], 'disabled')  # 어떻게 끝나도 망은 돌아와 있다

    def test_network_is_restored_when_the_app_is_blocked_or_crashes(self):
        (result, _), _ = self.offline(lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.state['airplane'], 'disabled')

        def crash(job):
            raise RuntimeError('앱이 죽음')
        with self.assertRaises(RuntimeError):
            self.offline(crash)
        self.assertEqual(self.state['airplane'], 'disabled')
        self.assertIn(('adb', 'S', ('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable')), self.events)

    def test_network_is_restored_when_the_app_crashes_with_the_airplane_still_on(self):
        class Dies(MidwayApp):
            def __call__(self, midway=None, **job):
                midway({'step': 'cut'})
                raise RuntimeError('끊은 채로 죽음')
        with self.assertRaises(RuntimeError):
            self.case('E-CHAT-25', self.good, Dies(self.good, 'cut', self.events))
        self.assertEqual(self.state['airplane'], 'disabled')

    def test_account_failure_never_cuts_the_network(self):
        self.fake.on('POST', r'/auth/v1/admin/users', Reply(500, {'msg': 'down'}))
        (result, _), app = self.offline(self.good)
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])
        self.assertEqual([e for e in self.events if e[0] == 'adb' if 'enable' in e[2]], [])


class AcceptTest(Phone2):
    def good(self, job):
        me = {'banner': 'id-1', 'sheet': 'id-3'}[job['variant']]  # 판마다 새 계정 둘 — 폰 계정은 1 · 3
        match = self.fake.tables['matches'][-1]['id']
        self.put('messages', match_id=match, sender_id=me, kind='trust_accept', body='나님이 카카오톡 아이디·실사진 공개를 수락했어요')
        for row in self.rows('match_participants', match_id=match, profile_id=me):
            row['trust_response'] = 'accept'  # 서버가 폰 계정의 참가자 줄을 고친다
        return said(error=None)

    def test_43_double_tap_leaves_one_accept_line_for_banner_and_sheet(self):
        (result, note), app = self.case('E-CHAT-43', self.good)
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'variant': 'banner'},
                                    {'token_hash': 'h', 'nickname': self.nick(4), 'variant': 'sheet'}])
        self.assert_all_home()

    def test_43_sheet_room_is_older_than_24_hours_and_banner_room_is_not(self):
        self.case('E-CHAT-43', self.good)
        banner, sheet = self.fake.tables['matches']
        self.assertNotIn('created_at', banner)
        patch = [s['body'] for s in self.fake.by('PATCH', '/rest/v1/matches') if s['query']['id'] == f"eq.{sheet['id']}"]
        self.assertEqual(len(patch), 1)
        age = datetime.now(timezone.utc) - datetime.fromisoformat(patch[0]['created_at'])
        self.assertGreater(age.total_seconds(), 24 * 3600)  # 24시간이 지나 시트가 뜨는 방
        self.assertLess(age.total_seconds(), 48 * 3600)  # 48시간은 안 지나 아직 수락할 수 있다

    def test_43_fails_when_a_variant_has_two_lines_none_or_an_error(self):
        def second_accept(job):
            result = self.good(job)
            if job['variant'] == 'sheet':
                self.put('messages', match_id=self.fake.tables['matches'][-1]['id'], sender_id='id-3', kind='trust_accept', body='두 번째')
            return result
        (result, note), _ = self.case('E-CHAT-43', second_accept)
        self.assertEqual(result, 'fail')
        self.assertIn('sheet', note)
        self.assertNotIn('banner', note)  # 판마다 따로 판정한다
        (result, note), _ = self.case('E-CHAT-43', lambda job: said(error=None))  # 아무 줄도 안 생김
        self.assertEqual(result, 'fail')
        self.assertIn('banner', note)
        (result, note), _ = self.case('E-CHAT-43', lambda job: {**self.good(job), 'error': '이미 수락했어요'})
        self.assertEqual(result, 'fail')
        self.assertIn('오류', note)
        (result, _), _ = self.case('E-CHAT-43', lambda job: {k: v for k, v in self.good(job).items() if k != 'error'})
        self.assertEqual(result, 'fail')  # 앱이 오류 칸을 말하지 않으면 판정할 수 없다

    def test_43_fails_when_the_accept_is_not_saved_for_the_phone_account(self):
        def only_the_line(job):
            me = {'banner': 'id-1', 'sheet': 'id-3'}[job['variant']]
            self.put('messages', match_id=self.fake.tables['matches'][-1]['id'], sender_id=me, kind='trust_accept', body='수락')
            return said(error=None)
        (result, note), _ = self.case('E-CHAT-43', only_the_line)
        self.assertEqual(result, 'fail')
        self.assertIn('trust_response', note)

    def test_43_silent_app_is_a_fail_for_each_variant(self):
        (result, note), app = self.case('E-CHAT-43', lambda job: None)
        self.assertEqual(result, 'fail')
        self.assertIn('banner', note)
        self.assertIn('sheet', note)
        self.assertEqual(len(app.jobs), 2)


# ── 지인 리뷰 쓰기 ───────────────────────────────────────────────────────────────────────────────────

class ComposeTest(Phone2):
    def wrote(self, tags, comment, **extra):
        def answer(job):
            self.put('friend_reviews', reviewer_id='id-1', reviewee_id='id-2', tags=list(tags), comment=comment)
            return said(toast=SUBMITTED, closed=True, **extra)
        return answer

    def job(self, **extra):
        return {'token_hash': 'h', 'profile_id': 'id-2', **extra}

    def check_pass(self, name, answer, job, rows):
        (result, note), app = self.case(name, answer)
        self.assertEqual((result, note), ('pass', ''), name)
        self.assertEqual(app.jobs, [job])
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-2', 'referrer_id': 'id-1'}])  # 추천 연결
        self.assertEqual(self.fake.statuses['id-2'], 'active')  # 상대는 active
        self.assertEqual([(r['tags'], r['comment']) for r in self.reviews()], rows)
        self.assert_all_home()

    def test_01_one_tag_without_comment(self):
        self.check_pass('E-REV-01', self.wrote(ONE_TAG, None), self.job(tags=ONE_TAG), [(ONE_TAG, None)])

    def test_01_fails_on_toast_open_sheet_tags_comment_or_rows(self):
        wrong = (said(toast='남겼어요', closed=True), said(closed=True), said(toast=SUBMITTED, closed=False),
                 said(toast=SUBMITTED), self.wrote(['성실해요'], None), self.wrote(ONE_TAG, ''), self.wrote(ONE_TAG, '가'),
                 lambda job: (self.wrote(ONE_TAG, None)(job), self.wrote(ONE_TAG, None)(job))[1], said(toast=SUBMITTED, closed=True))
        for i, answer in enumerate(wrong):
            (result, _), _ = self.case('E-REV-01', answer)
            self.assertEqual(result, 'fail', i)

    def test_02_three_tags_in_chosen_order_and_100_letters(self):
        self.check_pass('E-REV-02', self.wrote(THREE, '가' * 100), self.job(tags=THREE, paste=paste('가', 100)),
                        [(THREE, '가' * 100)])

    def test_02_fails_on_order_count_or_length(self):
        for answer in (self.wrote(THREE[::-1], '가' * 100), self.wrote(THREE[:2], '가' * 100), self.wrote(THREE, '가' * 99),
                       self.wrote(THREE, None)):
            (result, _), _ = self.case('E-REV-02', answer)
            self.assertEqual(result, 'fail')

    def test_03_no_tag_keeps_the_button_off_and_nothing_is_written(self):
        (result, note), app = self.case('E-REV-03', said(submit_enabled=False, selected=0))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [self.job(paste=paste('가', 5))])
        self.assertEqual(self.reviews(), [])
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-2', 'referrer_id': 'id-1'}])
        self.assert_all_home()

    def test_03_fails_when_the_button_is_on_or_a_row_appears(self):
        for answer in (said(submit_enabled=True, selected=0), said(selected=0), said(submit_enabled=False, selected=1),
                       self.wrote(ONE_TAG, '가가가가가')):
            (result, _), _ = self.case('E-REV-03', answer)
            self.assertEqual(result, 'fail')

    def test_04_fourth_tag_is_ignored_and_three_are_saved(self):
        self.check_pass('E-REV-04', self.wrote(THREE, None, selected=3, marks=3), self.job(tags=FOUR), [(THREE, None)])

    def test_04_fails_on_four_marks_four_saved_or_a_different_third(self):
        for answer in (self.wrote(THREE, None, selected=4, marks=3), self.wrote(THREE, None, selected=3, marks=4),
                       self.wrote(THREE, None, selected=3), self.wrote(FOUR, None, selected=3, marks=3),
                       self.wrote(THREE[:2] + ['배려가 깊어요'], None, selected=3, marks=3)):
            (result, _), _ = self.case('E-REV-04', answer)
            self.assertEqual(result, 'fail')

    def test_05_101st_letter_is_dropped_and_the_counter_stops_at_100(self):
        (result, note), app = self.case('E-REV-05', said(input_len=100, counter='100 / 100'))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [self.job(tags=ONE_TAG, paste=paste('가', 101))])
        self.assertEqual(self.reviews(), [])  # 쓰기만 하고 남기지 않는다
        self.assert_all_home()

    def test_05_fails_on_101_counter_text_or_a_saved_row(self):
        for answer in (said(input_len=101, counter='100 / 100'), said(input_len=100, counter='101 / 100'),
                       said(input_len=100), said(counter='100 / 100'), self.wrote(ONE_TAG, '가' * 100)):
            (result, _), _ = self.case('E-REV-05', answer)
            self.assertEqual(result, 'fail')

    def test_06_hundred_smiles_are_saved(self):
        self.check_pass('E-REV-06', self.wrote(ONE_TAG, SMILE * 100), self.job(tags=ONE_TAG, paste=paste(SMILE, 100)),
                        [(ONE_TAG, SMILE * 100)])

    def test_06_fails_on_99_smiles_or_no_comment(self):
        for answer in (self.wrote(ONE_TAG, SMILE * 99), self.wrote(ONE_TAG, None), self.wrote(ONE_TAG, SMILE * 50),
                       said(toast='실패', closed=False)):
            (result, _), _ = self.case('E-REV-06', answer)
            self.assertEqual(result, 'fail')

    def test_07_blank_comment_is_saved_as_no_comment(self):
        self.check_pass('E-REV-07', self.wrote(ONE_TAG, None), self.job(tags=ONE_TAG, paste=paste(' ', 5)), [(ONE_TAG, None)])

    def test_07_fails_when_the_spaces_are_kept(self):
        for answer in (self.wrote(ONE_TAG, '     '), self.wrote(ONE_TAG, ''), said(toast=SUBMITTED, closed=True)):
            (result, _), _ = self.case('E-REV-07', answer)
            self.assertEqual(result, 'fail')

    def test_account_failure_is_blocked_before_the_app(self):
        self.fake.on('POST', r'/auth/v1/admin/users', Reply(500, {'msg': 'down'}))
        for name in BUNDLE:
            (result, _), app = self.case(name, said())
            self.assertEqual(result, 'blocked', name)
            self.assertEqual(app.jobs, [], name)

    def test_link_failure_is_blocked_before_the_app(self):
        self.fake.on('POST', r'/rest/v1/referrals', Reply(400, {'message': 'bad'}))
        for name in ('E-REV-01', 'E-REV-02', 'E-REV-03', 'E-REV-04', 'E-REV-05', 'E-REV-06', 'E-REV-07', 'E-REV-11', 'E-REV-25'):
            (result, note), app = self.case(name, said())
            self.assertEqual(result, 'blocked', name)
            self.assertIn('referrals', note)
            self.assertEqual(app.jobs, [], name)


class RaceTest(Phone2):
    """E-REV-11 — 앱이 시트에서 step 에 멈춘 사이 PC 가 API 로 같은 상대에게 먼저 쓰고, 앱이 남기기를 눌러 409 를 읽는다."""

    def api_writes(self, status=201):
        def post(sent):
            if status < 300:
                self.put('friend_reviews', reviewer_id='id-1', reviewee_id=sent['body']['reviewee_id'], tags=sent['body']['tags'])
            return Reply(status, {'id': 'r1'} if status < 300 else {'detail': ALREADY})
        self.fake.on('POST', r'/friend-reviews', post)

    def run_case(self, answer):
        events = []
        return self.case('E-REV-11', answer, MidwayApp(as_fn(answer), 'api', events)), events

    def test_api_writes_while_the_app_waits_then_the_app_gets_409(self):
        self.api_writes()
        ((result, note), app), events = self.run_case(said(toast=ALREADY, closed=False))
        self.assertEqual(result, 'pass')
        self.assertIn('같은 순간 경합은 못 만든다', note)  # 시나리오와 다른 점을 메모에 남긴다
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'profile_id': 'id-2', 'tags': ONE_TAG}])
        post = self.fake.by('POST', '/friend-reviews')
        self.assertEqual([(s['auth'], s['body']['reviewee_id']) for s in post], [('tok-1', 'id-2')])  # 폰 계정의 토큰
        self.assertEqual(events, ['step', 'go'])
        self.assertEqual(len(self.reviews()), 1)
        self.assert_all_home()

    def test_fails_on_a_second_row_or_a_wrong_toast(self):
        self.api_writes()
        for answer in (said(toast='리뷰를 남겼어요', closed=True), said(closed=False),
                       lambda job: (self.put('friend_reviews', reviewer_id='id-1', reviewee_id='id-2', tags=ONE_TAG),
                                    said(toast=ALREADY))[1]):
            ((result, _), _), _ = self.run_case(answer)
            self.assertEqual(result, 'fail')

    def test_api_that_does_not_accept_the_first_write_is_blocked(self):
        self.api_writes(409)
        ((result, note), app), _ = self.run_case(said(toast=ALREADY))
        self.assertEqual(result, 'blocked')
        self.assertIn('409', note)

    def test_the_api_write_happens_between_the_app_stop_and_go(self):
        events = []
        self.api_writes()
        post = self.fake.handlers[0]
        self.fake.handlers[0] = (post[0], post[1], lambda sent: (events.append('api'), post[2](sent))[1])
        self.case('E-REV-11', said(toast=ALREADY), MidwayApp(as_fn(said(toast=ALREADY)), 'api', events))
        self.assertEqual(events, ['step', 'api', 'go'])


# ── 쓴 리뷰 지우기 · 받은 리뷰 신고 ──────────────────────────────────────────────────────────────────

class WrittenTest(Phone2):
    def test_25_cancel_keeps_the_card_and_the_row(self):
        (result, note), app = self.case('E-REV-25', said(cards=1, confirm_open=False, toast=None))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.fake.tables['friend_reviews'][0]
        self.assertEqual((row['reviewer_id'], row['reviewee_id'], row['tags']), ('id-1', 'id-2', ONE_TAG))
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-2', 'referrer_id': 'id-1'}])
        self.assert_all_home()

    def test_25_fails_when_the_card_leaves_the_sheet_stays_a_toast_shows_or_the_row_goes(self):
        good = dict(cards=1, confirm_open=False, toast=None)
        for bad in ({'cards': 0}, {'confirm_open': True}, {'toast': '리뷰를 지웠어요'}, {'cards': None}):
            (result, _), _ = self.case('E-REV-25', said(**{**good, **bad}))
            self.assertEqual(result, 'fail', bad)

        def deletes(job):
            self.fake.tables['friend_reviews'].clear()
            return said(**good)
        (result, note), _ = self.case('E-REV-25', deletes)
        self.assertEqual(result, 'fail')
        self.assertIn('friend_reviews', note)


class ReportTest(Phone2):
    COMMENT = '고마웠어요'
    TAGS = ['대화가 편해요', '성실해요']

    def review_id(self):
        return self.fake.tables['friend_reviews'][0]['id']

    def reported(self, reason='abuse', snapshot=True, **extra):
        def answer(job):
            self.put('reports', id='rp1', reporter_id='id-1', target_type='friend_review', target_id=self.review_id(),
                     target_profile_id='id-2', reason=reason,
                     target_snapshot=({'review_id': self.review_id(), 'tags': self.TAGS, 'comment': self.COMMENT,
                                       'created_at': '2026-10-04T00:00:00+00:00'} if snapshot else {'tags': []}))
            return said(**{'toast': REPORTED, 'cards': 1, 'sheet_open': False, **extra})
        return answer

    def test_36_report_is_one_row_with_snapshot_no_block_and_the_card_stays(self):
        (result, note), app = self.case('E-REV-36', self.reported())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        review = self.fake.tables['friend_reviews'][0]
        self.assertEqual((review['reviewer_id'], review['reviewee_id'], review['tags'], review['comment']),
                         ('id-2', 'id-1', self.TAGS, self.COMMENT))
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-1', 'referrer_id': 'id-2'}])  # 받는 쪽이 폰 계정
        self.assertEqual(self.fake.statuses['id-1'], 'active')
        self.assert_all_home()

    def test_36_removes_the_reports_it_caused_even_on_pass(self):
        self.case('E-REV-36', self.reported())
        deletes = self.fake.by('DELETE', '/rest/v1/reports')
        self.assertEqual([s['query'] for s in deletes], [{'target_id': f'eq.{self.review_id()}'}])
        self.assertEqual(self.fake.tables['reports'], [])  # 계정을 지워도 set null 로 남는 표 — PC 가 지운다

    def test_36_removes_the_reports_on_fail_and_when_the_app_is_blocked(self):
        (result, _), _ = self.case('E-REV-36', self.reported(toast='다른 문구'))
        self.assertEqual(result, 'fail')
        self.assertEqual(self.fake.tables['reports'], [])

        def blocked(job):
            self.reported()(job)
            return {'result': 'blocked', 'note': '깃발이 없음'}
        (result, _), _ = self.case('E-REV-36', blocked)
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.fake.tables['reports'], [])

    def test_36_failed_report_cleanup_is_a_problem(self):
        self.fake.on('DELETE', r'/rest/v1/reports', Reply(500, {'message': 'down'}))
        (result, note), _ = self.case('E-REV-36', self.reported())
        self.assertEqual(result, 'fail')
        self.assertIn('reports', note)

    def test_36_fails_on_toast_card_sheet_or_wrong_reason(self):
        for answer in (self.reported(toast='이미 신고를 완료했어요'), self.reported(toast=None), self.reported(cards=0),
                       self.reported(sheet_open=True), self.reported(reason='spam'), self.reported(snapshot=False),
                       said(toast=REPORTED, cards=1, sheet_open=False)):
            (result, _), _ = self.case('E-REV-36', answer)
            self.assertEqual(result, 'fail')

    def test_36_fails_on_two_reports_a_block_or_the_wrong_target_type(self):
        def twice(job):
            self.reported()(job)
            return self.reported()(job)
        for answer in (twice,):
            (result, note), _ = self.case('E-REV-36', answer)
            self.assertEqual(result, 'fail')
            self.assertIn('reports', note)

        def blocks(job):
            self.put('blocks', blocker_id='id-1', blocked_id='id-2')
            return self.reported()(job)
        (result, note), _ = self.case('E-REV-36', blocks)
        self.assertEqual(result, 'fail')
        self.assertIn('blocks', note)

        def profile_report(job):
            result = self.reported()(job)
            self.fake.tables['reports'][0]['target_type'] = 'profile'
            return result
        (result, _), _ = self.case('E-REV-36', profile_report)
        self.assertEqual(result, 'fail')

    def first_report_by_api(self):
        def post(sent):
            self.put('reports', id='rp1', reporter_id='id-1', target_type=sent['body']['target_type'], target_id=sent['body']['target_id'],
                     reason=sent['body']['reason'])
            return Reply(201, {'ok': True})
        self.fake.on('POST', r'/reports', post)

    def test_37_second_report_is_already_reported_and_one_row_stays(self):
        self.first_report_by_api()
        (result, note), app = self.case('E-REV-37', said(toast=ALREADY_REPORTED, cards=1, sheet_open=False))
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        first = self.fake.by('POST', '/reports')
        self.assertEqual([(s['auth'], s['body']) for s in first],
                         [('tok-1', {'target_type': 'friend_review', 'target_id': self.review_id(), 'reason': 'abuse'})])
        self.assertEqual(self.fake.tables['reports'], [])  # 끝에서 지운다
        self.assert_all_home()

    def test_37_fails_on_toast_second_row_or_card(self):
        self.first_report_by_api()
        for answer in (said(toast=REPORTED, cards=1, sheet_open=False), said(toast=None, cards=1, sheet_open=False),
                       said(toast=ALREADY_REPORTED, cards=0, sheet_open=False),
                       said(toast=ALREADY_REPORTED, cards=1, sheet_open=True),
                       lambda job: (self.put('reports', id='rp2', target_id=self.review_id()),
                                    said(toast=ALREADY_REPORTED, cards=1, sheet_open=False))[1]):
            (result, _), _ = self.case('E-REV-37', answer)
            self.assertEqual(result, 'fail')
            self.assertEqual(self.fake.tables['reports'], [])

    def test_37_first_report_that_the_api_refuses_is_blocked_and_cleans_up(self):
        self.fake.on('POST', r'/reports', Reply(404, {'detail': '리뷰를 찾을 수 없어요'}))
        (result, note), app = self.case('E-REV-37', said())
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])
        self.assertTrue(self.fake.by('DELETE', '/rest/v1/reports'))  # 어떻게 끝나도 지우기는 한다


# ── 등록부 ───────────────────────────────────────────────────────────────────────────────────────────

APP_KEYS = {'nickname', 'text', 'paste', 'variant', 'profile_id', 'tags'}


class PermissionTest(Phone2):
    def test_every_phone_2_case_grants_before_and_revokes_after(self):
        self.assertEqual(list(area3_phone2.PHONE2), BUNDLE)
        for name in BUNDLE:  # 가설마다 돌리면 오프라인 가설이 실폰 adb 를 부른다 — 꾸밈을 거쳤는지만 보고, 한 건은 실제로 돌린다
            self.assertTrue(hasattr(area3_phone2.PHONE2[name], '__wrapped__'), name)
            self.assertIs(area1.PHONE[name], area3_phone2.PHONE2[name], name)
        self.case('E-REV-07', said())
        self.assertEqual([p[0] for p in self.perm], ['grant', 'revoke'])


class RegistryTest(Phone2):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_bundle_is_the_19_interaction_cases_after_phone_1(self):
        self.assertEqual(area3.BUNDLES['area3-phone-2'], BUNDLE)
        self.assertEqual(list(area3_phone2.PHONE2), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))
        self.assertFalse(set(BUNDLE) & set(area3.BUNDLES['area3-phone-1']))

    def test_main_runs_the_bundle_through_area1_phone(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area3-phone-2'], BUNDLE)
        self.assertFalse(set(BUNDLE) & set(main.API_CASES))
        self.assertTrue(set(main.BUNDLES['area3-phone-1']) and set(main.BUNDLES['area3-api']))  # 앞 묶음은 그대로

    def test_every_job_key_is_read_by_the_app(self):
        dart = self.dart('area3_b2.dart')
        for key in sorted(APP_KEYS):
            self.assertIn(f"job['{key}']", dart, key)

    def test_the_app_has_the_same_19_numbers_in_order_and_area3_merges_them(self):
        part = self.dart('area3_b2.dart')
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), BUNDLE)
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        main = self.dart('area3.dart')
        self.assertIn("part 'area3_b2.dart';", main)
        self.assertIn('...area3Cases2', main)

    def test_app_silence_is_fail_and_app_blocked_is_blocked(self):
        (result, _), _ = self.case('E-REV-07', lambda job: None)
        self.assertEqual(result, 'fail')
        (result, note), _ = self.case('E-REV-03', lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual((result, note), ('blocked', '앱: 못 찾음'))


if __name__ == '__main__':
    unittest.main()
