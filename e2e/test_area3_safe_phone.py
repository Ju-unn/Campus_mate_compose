"""영역 3 안전 폰 A 한 대(E-SAFE 18개)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_safe_phone`.

가짜 서버는 test_area3_safe.py 의 SafeFake(신고 · 차단 · 후보 · 정지 규칙)에 폰 가설이 읽는 것(닉네임 · 나감 시각 · 스냅샷 ·
투표 글 신고)만 더한 [PhoneFake] 다. 가짜 앱은 test_area3_phone.py 의 App — "앱이 눌렀다" 는 시험이 가짜 앱 안에서
서버 규칙을 그대로 불러(`fake._report` · `fake._block`) 흉내 낸다. 계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 ….
"""

import re
import unittest
import uuid
from datetime import datetime, timezone
from unittest import mock

from e2e import area1, area2, area3, area3_safe_phone, area4, notify, tools
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, as_fn
from e2e.test_area3_safe import SafeBase, SafeFake, _who
from e2e.tools import Reply, Run

BUNDLE = ['E-SAFE-01', 'E-SAFE-05', 'E-SAFE-07', 'E-SAFE-08', 'E-SAFE-09', 'E-SAFE-11', 'E-SAFE-13', 'E-SAFE-15',
          'E-SAFE-18', 'E-SAFE-26', 'E-SAFE-27', 'E-SAFE-28', 'E-SAFE-30', 'E-SAFE-31', 'E-SAFE-50', 'E-SAFE-57',
          'E-SAFE-60', 'E-SAFE-61']
REPORTED = '신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요.'
POLL_REPORTED = '신고했어요. 운영팀이 확인할게요'
ALREADY_REPORTED = '이미 신고를 완료했어요'
LIMITED = '오늘은 더 신고할 수 없어요'
PROFILE_GONE = '프로필을 찾을 수 없어요'
MESSAGE_GONE = '메시지를 찾을 수 없어요'
POLL_GONE = '질문을 찾을 수 없어요'
NETWORK = '네트워크 연결을 확인해 주세요'
REASONS = ['욕설·비방·혐오', '성적 불쾌감', '광고·스팸', '사칭·허위', '기타']
SUSPENDED_TITLE = '이용이 제한된 계정이에요'
SUPPORT = 'appmailerl4538@gmail.com'
NOTICE = '연락처로 차단한 지인은 여기가 아니라 설정 > 연락처 차단에서 관리해요.'
ON_LIST = dict(toast=REPORTED, on_list=True, room_listed=False)


def tok(account):
    return 'tok-' + account.removeprefix('id-')


class PhoneFake(SafeFake):
    """SafeFake + 폰 가설이 읽는 것: 닉네임 · 나감 시각(left_at) · 신고 스냅샷 · 투표 글 신고(서버 `_poll_target` 규칙)."""

    def _basic(self, sent):
        self.profile(_who(sent))['nickname'] = sent['body']['nickname']
        return super()._basic(sent)

    def _leave(self, me, match):
        super()._leave(me, match)
        for row in self.rows('match_participants'):
            if row['match_id'] == match['id'] and row['profile_id'] == me:
                row['left_at'] = datetime.now(timezone.utc).isoformat()

    def _report(self, sent):
        body, me = sent['body'], _who(sent)
        if body['target_type'] not in ('profile', 'message', 'friend_review', 'poll'):
            return Reply(422, {'detail': 'target_type'})
        if body['target_type'] == 'poll':
            poll = next((p for p in self.rows('polls') if p['id'] == body['target_id']), None)
            if not poll or poll['author_id'] == me:
                return Reply(404, {'detail': POLL_GONE})
            if any((r['reporter_id'], r['target_id']) == (me, poll['id']) for r in self.rows('reports')):
                return Reply(409, {'detail': ALREADY_REPORTED})
            self.rows('reports').append({'id': str(uuid.uuid4()), 'reporter_id': me, 'target_type': 'poll', 'target_id': poll['id'],
                                         'target_profile_id': poll['author_id'], 'reason': body['reason'], 'reason_note': None,
                                         'status': 'open', 'target_snapshot': {'question': poll['question']}})
            return Reply(201, {'ok': True})
        reply = super()._report(sent)
        if reply[0] == 201 and body['target_type'] == 'profile':
            row = self.rows('reports')[-1]
            row['target_snapshot'] = {'nickname': self.profile(row['target_profile_id']).get('nickname'), 'bio': 'b',
                                      'avatar_path': None, 'photo_paths': []}
        return reply


class SafePhone(SafeBase):
    def setUp(self):
        super().setUp()
        self.fake = PhoneFake()
        for patcher in (mock.patch.object(tools, 'call', self.fake),
                        mock.patch.object(Run, 'remember'),  # accounts.json 을 계정 단계마다 열고 쓰는 것이 느리다(가설은 읽지 않는다)
                        mock.patch.object(area2, '_guard')):  # 그 accounts.json 으로 "이번 실행이 만든 계정" 을 보는 쓰기 가드
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake.on('POST', r'/community/polls', self.post_poll)
        self.fake.on('DELETE', r'/community/polls/[^/]+', self.delete_poll)

    def post_poll(self, sent):
        poll = {'id': str(uuid.uuid4()), 'author_id': _who(sent), 'question': sent['body']['question']}
        self.fake.rows('polls').append(poll)
        return Reply(201, {'id': poll['id']})

    def delete_poll(self, sent):
        poll_id = sent['path'].rsplit('/', 1)[1]
        self.fake.tables['polls'] = [p for p in self.fake.rows('polls') if p['id'] != poll_id]
        return Reply(200, {'ok': True})

    def case(self, name, answer, app=None):
        """가설 하나를 깨끗한 가짜 서버에서(시험이 정한 API 답은 둔다) — 계정은 늘 id-1 부터."""
        fake = self.fake
        for table in (fake.tables, fake.statuses, fake.profiles, fake.phones):
            table.clear()
        fake.sent.clear()
        fake.users.clear()
        fake.verifies = fake._ids = 0
        app = app or App(as_fn(answer))
        return area1.attempt_phone(self.run_, name, app), app

    # ── 읽기 ──
    def rows(self, table, **where):
        return [r for r in self.fake.tables.get(table, []) if all(r.get(k) == v for k, v in where.items())]

    def nick(self, account):
        return self.fake.profiles[account]['nickname']

    def match(self, n=0):
        return self.fake.tables['matches'][n]['id']

    def left_at(self, account, n=0):
        return self.rows('match_participants', match_id=self.match(n), profile_id=account)[0].get('left_at')

    def assert_no_reports_left(self):
        self.assertEqual(self.fake.tables.get('reports', []), [])  # 시험이 만든 신고는 pass 여도 지운다

    # ── 앱이 한 일 흉내 ──
    def report_by(self, account, target, reason='spam', note=None, kind='profile'):
        body = {'target_type': kind, 'target_id': target, 'reason': reason}
        if note is not None:
            body['reason_note'] = note
        reply = self.fake._report({'auth': tok(account), 'body': body})
        self.assertEqual(reply[0], 201, reply)
        self.last_reports = [dict(r) for r in self.rows('reports')]  # 정리 전에 본 신고 행들

    def app_reports(self, me='id-1', target='id-2', reason='spam', note=None, **extra):
        """앱이 신고를 눌렀다 — 서버가 신고 1 · 차단 1 · 나감을 남기고, 앱은 [extra] 를 말한다."""
        def answer(job):
            self.report_by(me, target, reason, note)
            return said(**extra)
        return answer

    def passes(self, name, answer, app=None):
        (result, note), app = self.case(name, answer, app)
        self.assertEqual(result, 'pass', note)
        return note, app

    def fails(self, name, answer, *words, app=None):
        (result, note), app = self.case(name, answer, app)
        self.assertEqual(result, 'fail', note)
        for word in words:
            self.assertIn(word, note)
        self.assert_no_reports_left()
        return note, app


# ── 신고 시트 · 방 안 ────────────────────────────────────────────────────────────────────────────────

class SheetTest(SafePhone):
    def sheet(self, **over):
        return said(**{'title': '무엇을 신고할까요?', 'reasons': REASONS, 'rows': 5, 'submit_before': False, 'submit_after': True, **over})

    def test_01_five_reasons_in_order_and_the_button_is_off_until_one_is_picked(self):
        _, app = self.passes('E-SAFE-01', self.sheet())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])
        self.assertEqual(self.rows('reports'), [])
        self.assertEqual(self.rows('blocks'), [])

    def test_01_fails_on_the_wrong_order_count_title_or_a_button_that_is_on(self):
        for over in ({'reasons': REASONS[::-1]}, {'reasons': REASONS[:4]}, {'rows': 4}, {'title': '신고'},
                     {'submit_before': True}, {'submit_after': False}):
            self.fails('E-SAFE-01', self.sheet(**over))

    def test_01_fails_when_the_app_sent_a_report_or_a_block(self):
        def sends(job):
            self.report_by('id-1', 'id-2')
            return self.sheet()
        self.fails('E-SAFE-01', sends, 'reports')

    def test_01_fails_when_the_app_does_not_say_what_it_saw(self):
        self.fails('E-SAFE-01', said())

    def test_08_other_opens_a_note_box_and_needs_at_least_one_letter(self):
        answer = self.app_reports(reason='other', note='불편했어요', note_box_before=False, note_box=True, submit_empty=False,
                                  submit_blank=False, submit_filled=True, **ON_LIST)
        _, app = self.passes('E-SAFE-08', answer)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'note': '불편했어요'}])
        self.assertEqual(self.fake.tables['reports'], [])

    def test_08_fails_when_the_box_the_button_or_the_saved_note_is_wrong(self):
        ok = dict(note_box_before=False, note_box=True, submit_empty=False, submit_blank=False, submit_filled=True, **ON_LIST)
        for over in ({'note_box': False}, {'note_box_before': True}, {'submit_empty': True}, {'submit_blank': True},
                     {'submit_filled': False}):
            self.fails('E-SAFE-08', self.app_reports(reason='other', note='불편했어요', **{**ok, **over}))
        self.fails('E-SAFE-08', self.app_reports(reason='other', note='다른 말', **ok), 'reason_note')
        self.fails('E-SAFE-08', self.app_reports(reason='spam', **ok), 'reason')

    def test_09_201_letters_stop_at_200_in_the_box_the_counter_and_the_row(self):
        note = '가' * 200
        answer = self.app_reports(reason='other', note=note, input_len=200, counter='200 / 200', **ON_LIST)
        _, app = self.passes('E-SAFE-09', answer)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'paste': {'runes': [0xAC00], 'count': 201}}])

    def test_09_fails_on_201_in_the_box_a_wrong_counter_or_a_cut_row(self):
        note = '가' * 200
        for over in ({'input_len': 201}, {'input_len': 199}, {'counter': '201 / 200'}, {'counter': None}):
            self.fails('E-SAFE-09', self.app_reports(reason='other', note=note, **{'input_len': 200, 'counter': '200 / 200', **ON_LIST, **over}))
        self.fails('E-SAFE-09', self.app_reports(reason='other', note='가' * 199, input_len=200, counter='200 / 200', **ON_LIST), 'reason_note')


class AfterReportTest(SafePhone):
    """07 · 18 · 60 이 같이 보는 "신고하면 신고 + 차단 + 나감, 대화 목록으로" — 07 로 대표해 본다."""

    def good(self, **extra):
        return self.app_reports(**{**ON_LIST, **extra})

    def test_07_profile_report_is_one_row_one_block_a_left_room_and_the_list(self):
        _, app = self.passes('E-SAFE-07', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'profile_id': 'id-2'}])
        self.assertEqual([(r['reporter_id'], r['target_type'], r['target_id'], r['target_profile_id']) for r in self.last_reports],
                         [('id-1', 'profile', 'id-2', 'id-2')])
        self.assertEqual(len(self.rows('blocks', blocker_id='id-1', blocked_id='id-2')), 1)
        self.assertTrue(self.left_at('id-1'))
        self.assert_no_reports_left()

    def test_07_fails_on_toast_list_or_a_room_that_is_still_listed(self):
        for over in ({'toast': '신고했어요'}, {'toast': None}, {'on_list': False}, {'room_listed': True}):
            self.fails('E-SAFE-07', self.good(**over))

    def test_07_fails_when_there_is_no_report_no_block_or_the_room_is_not_left(self):
        _, _ = self.fails('E-SAFE-07', said(**ON_LIST), 'reports')
        original = self.fake._leave
        self.fake._leave = lambda me, match: None
        self.addCleanup(setattr, self.fake, '_leave', original)
        self.fails('E-SAFE-07', self.good(), 'left_at')

    def test_07_fails_when_the_snapshot_misses_the_nickname_or_a_key(self):
        def thin(job):
            self.report_by('id-1', 'id-2')
            self.fake.rows('reports')[-1]['target_snapshot'] = {'nickname': 'x'}
            return said(**ON_LIST)
        self.fails('E-SAFE-07', thin, '스냅샷')

    def test_07_fails_on_a_second_report_a_wrong_reason_or_a_wrong_target(self):
        def twice(job):
            self.report_by('id-1', 'id-2')
            self.fake.rows('reports').append({**self.fake.rows('reports')[0], 'id': 'dup'})
            return said(**ON_LIST)
        self.fails('E-SAFE-07', twice, 'reports')
        self.fails('E-SAFE-07', self.app_reports(reason='abuse', **ON_LIST), 'reason')

    def test_07_removes_the_reports_even_when_the_app_is_silent_or_blocked(self):
        for answer in (lambda job: (self.report_by('id-1', 'id-2'), None)[1], lambda job: {'result': 'blocked', 'note': '못 찾음'}):
            (result, _), _ = self.case('E-SAFE-07', answer)
            self.assertIn(result, ('fail', 'blocked'))
            self.assert_no_reports_left()
        deletes = [s['query'] for s in self.fake.by('DELETE', '/rest/v1/reports')]
        self.assertEqual(sorted(k for q in deletes for k in q), ['reporter_id', 'reporter_id', 'target_profile_id', 'target_profile_id'])

    def test_07_a_failed_cleanup_is_a_problem(self):
        self.fake.on('DELETE', r'/rest/v1/reports', Reply(500, {'message': 'down'}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        (result, note), _ = self.case('E-SAFE-07', self.good())
        self.assertEqual(result, 'fail')
        self.assertIn('reports 지우기', note)


class MessageMenuTest(SafePhone):
    def good(self, **over):
        return said(**{'menu_on_mine': False, 'menu_on_system': False, 'menu_on_theirs': True, **over})

    def test_05_no_menu_on_mine_or_a_system_line_and_the_api_refuses_both_ids(self):
        _, app = self.passes('E-SAFE-05', self.good())
        job = app.jobs[0]
        self.assertEqual(set(job), {'token_hash', 'nickname', 'mine', 'system', 'theirs'})
        sent = self.fake.by('POST', '/reports')
        ids = [s['body']['target_id'] for s in sent]
        lines = {m['id']: m for m in self.rows('messages')}
        self.assertEqual([(lines[i]['sender_id'], lines[i]['kind']) for i in ids], [('id-1', 'text'), ('id-1', 'trust_accept')])
        self.assertEqual({s['auth'] for s in sent}, {'tok-1'})
        self.assertEqual(lines[ids[0]]['body'], job['mine'])
        self.assertEqual(lines[ids[1]]['body'], job['system'])
        self.assertEqual(self.rows('messages', sender_id='id-2')[0]['body'], job['theirs'])
        self.assertEqual(self.rows('reports'), [])
        self.assertEqual(self.rows('blocks'), [])

    def test_05_fails_when_a_menu_opens_on_mine_or_the_system_line_or_never_on_theirs(self):
        for over in ({'menu_on_mine': True}, {'menu_on_system': True}, {'menu_on_theirs': False}):
            self.fails('E-SAFE-05', self.good(**over))
        self.fails('E-SAFE-05', said())  # 앱이 말하지 않으면 판정할 수 없다

    def test_05_fails_when_the_server_accepts_a_report_on_my_own_message(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), Reply(201, {'ok': True})))
        self.fails('E-SAFE-05', self.good(), 'API')


class RoomFlowTest(SafePhone):
    def test_13_the_second_report_is_already_reported_and_one_row_stays(self):
        events = []
        app = MidwayApp(lambda job: said(toast=ALREADY_REPORTED, on_list=True, room_listed=False), 'api', events)
        _, app = self.passes('E-SAFE-13', None, app)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])
        self.assertEqual(events, ['step', 'go'])
        self.assertEqual([s['auth'] for s in self.fake.by('POST', '/reports')], ['tok-1'])  # 첫 신고는 PC 가 API 로
        self.assert_no_reports_left()

    def test_13_fails_on_a_second_row_a_wrong_toast_or_a_silent_midway(self):
        events = []
        def doubled(job):
            self.fake.rows('reports').append({**self.fake.rows('reports')[0], 'id': 'dup'})
            return said(toast=ALREADY_REPORTED, on_list=True)
        self.fails('E-SAFE-13', None, 'reports', app=MidwayApp(doubled, 'api', events))
        self.fails('E-SAFE-13', None, '토스트', app=MidwayApp(lambda job: said(toast='이미 신고한 사용자예요', on_list=True), 'api', events))
        self.fails('E-SAFE-13', None, '목록', app=MidwayApp(lambda job: said(toast=ALREADY_REPORTED, on_list=False), 'api', events))

    def test_13_fails_when_the_first_report_left_no_block(self):
        def unblocked(job):
            self.fake.tables['blocks'] = []  # PC 의 첫 신고 뒤 차단 행이 비어 있는 서버
            return said(toast=ALREADY_REPORTED, on_list=True)
        self.fails('E-SAFE-13', None, 'blocks', app=MidwayApp(unblocked, 'api', []))

    def test_13_a_first_report_the_api_refuses_is_blocked(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), Reply(404, {'detail': PROFILE_GONE})))
        (result, note), _ = self.case('E-SAFE-13', None, MidwayApp(lambda job: said(), 'api', []))
        self.assertEqual(result, 'blocked')
        self.assertIn('API', note)

    def room_kept(self, **over):
        return said(**{'toast': LIMITED, 'in_room': True, 'on_list': False, **over})

    def test_15_ten_reports_in_the_last_day_stop_the_eleventh_and_nothing_else_changes(self):
        _, app = self.passes('E-SAFE-15', self.room_kept())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])
        seeds = self.fake.by('POST', '/rest/v1/reports')[0]['body']
        self.assertEqual(len(seeds), 10)  # 계정 열 개 대신 DB 로 — 서로 다른 대상, 모두 폰 계정이 낸 것
        self.assertEqual({s['reporter_id'] for s in seeds}, {'id-1'})
        self.assertEqual(len({s['target_id'] for s in seeds}), 10)
        self.assertNotIn('id-2', {s['target_id'] for s in seeds})
        self.assertTrue(all(s['target_profile_id'] is None and s['reason'] == 'spam' for s in seeds))
        ages = [(datetime.now(timezone.utc) - datetime.fromisoformat(s['created_at'])).total_seconds() for s in seeds]
        self.assertTrue(all(3000 < age < 4200 for age in ages), ages)  # 1시간 전 — 24시간 안
        self.assert_no_reports_left()

    def test_15_fails_on_a_new_report_a_block_a_left_room_or_another_toast(self):
        def goes_through(job):
            self.report_by('id-1', 'id-2')
            return self.room_kept()
        self.fails('E-SAFE-15', goes_through, 'reports', 'blocks')
        self.fails('E-SAFE-15', self.room_kept(toast=REPORTED), '토스트')
        self.fails('E-SAFE-15', self.room_kept(in_room=False), '방')
        def left(job):
            self.fake.rows('match_participants')[0]['left_at'] = 'now'
            return self.room_kept()
        self.fails('E-SAFE-15', left, 'left_at')

    def test_15_fails_when_a_new_row_appears_for_another_target(self):
        def other_target(job):
            self.fake.rows('reports').append({'id': 'x', 'reporter_id': 'id-1', 'target_type': 'profile', 'target_id': str(uuid.uuid4()),
                                              'target_profile_id': None, 'reason': 'spam', 'status': 'open'})
            return self.room_kept()
        self.fails('E-SAFE-15', other_target, 'reports')

    def test_15_a_failed_seed_is_blocked(self):
        self.fake.on('POST', r'/rest/v1/reports', Reply(400, {'message': 'bad'}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        (result, note), app = self.case('E-SAFE-15', self.room_kept())
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])

    def test_26_cancel_in_the_block_sheet_changes_nothing(self):
        _, app = self.passes('E-SAFE-26', said(sheet_seen=True, sheet_closed=True, in_room=True, on_list=False))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])

    def test_26_fails_when_the_room_was_left_without_a_block_row(self):
        def left(job):
            self.fake.rows('match_participants')[0]['left_at'] = 'now'  # 차단 행 없이 나감만 일어난 서버
            return said(sheet_seen=True, sheet_closed=True, in_room=True, on_list=False)
        self.fails('E-SAFE-26', left, 'left_at')

    def test_26_fails_on_an_open_sheet_a_block_row_or_a_left_room(self):
        ok = dict(sheet_seen=True, sheet_closed=True, in_room=True, on_list=False)
        for over in ({'sheet_seen': False}, {'sheet_closed': False}, {'in_room': False}, {'on_list': True}):
            self.fails('E-SAFE-26', said(**{**ok, **over}))
        def blocks(job):
            self.fake._block({'auth': 'tok-1', 'path': '/blocks/id-2'})
            return said(**ok)
        self.fails('E-SAFE-26', blocks, 'blocks')


class PollReportTest(SafePhone):
    """E-SAFE-11 — 폰 계정=id-1 · 글쓴이=id-2."""

    def good(self, snapshot=True):
        def answer(job):
            poll = next(p for p in self.fake.rows('polls') if p['question'] == job['question'])
            self.report_by('id-1', poll['id'], reason='abuse', kind='poll')
            if not snapshot:
                self.fake.rows('reports')[-1]['target_snapshot'] = {}  # 스냅샷이 빈 서버
            return said(entry=True, own_entry=False, own_more=True, toast=POLL_REPORTED, card=True)
        return answer

    def test_11_other_peoples_poll_is_reportable_with_no_block_and_the_own_poll_is_404(self):
        self.passes('E-SAFE-11', self.good())
        self.assertEqual(self.rows('polls'), [])  # 시험 글은 끝에 작성자가 지운다

    def test_11_fails_when_the_snapshot_has_no_question(self):
        self.fails('E-SAFE-11', self.good(snapshot=False), '스냅샷')


class ProfileTest(SafePhone):
    def test_27_block_from_the_profile_matches_the_room_block(self):
        def answer(job):
            self.fake._block({'auth': 'tok-1', 'path': '/blocks/id-2'})
            return said(on_list=True, room_listed=False)
        _, app = self.passes('E-SAFE-27', answer)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'profile_id': 'id-2'}])
        self.assertTrue(self.left_at('id-1'))
        self.assertEqual(self.rows('reports'), [])  # 차단만 — 신고는 없다

    def test_27_fails_without_a_block_row_a_left_room_the_list_or_with_a_report(self):
        def block_only(job):
            self.fake._block({'auth': 'tok-1', 'path': '/blocks/id-2'})
            return said(on_list=True, room_listed=False)
        self.fails('E-SAFE-27', said(on_list=True, room_listed=False), 'blocks')
        self.fails('E-SAFE-27', lambda job: (block_only(job), said(on_list=False, room_listed=False))[1], '목록')
        self.fails('E-SAFE-27', lambda job: (block_only(job), said(on_list=True, room_listed=True))[1], '방')
        def with_report(job):
            self.report_by('id-1', 'id-2')
            return said(on_list=True, room_listed=False)
        self.fails('E-SAFE-27', with_report, 'reports')

    def good28(self, **over):
        return said(**{'toast': PROFILE_GONE, 'profile_open': False, 'on_home': True, **over})

    def test_28_the_blocked_side_cannot_open_the_blockers_profile(self):
        _, app = self.passes('E-SAFE-28', self.good28())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'profile_id': 'id-2'}])
        self.assertEqual([(s['auth'], s['path']) for s in self.fake.by('POST', '/blocks/')], [('tok-2', '/blocks/id-1')])  # 상대가 폰 계정을 막았다
        self.assertEqual(self.rows('blocks'), [{'blocker_id': 'id-2', 'blocked_id': 'id-1'}])

    def test_28_fails_on_another_toast_an_open_profile_or_a_missing_home(self):
        for over in ({'toast': None}, {'toast': '차단된 사용자예요'}, {'profile_open': True}, {'on_home': False}):
            self.fails('E-SAFE-28', self.good28(**over))

    def test_28_fails_when_the_phone_account_got_a_block_row_too(self):
        def both(job):
            self.fake.rows('blocks').append({'blocker_id': 'id-1', 'blocked_id': 'id-2'})
            return self.good28()
        self.fails('E-SAFE-28', both, 'blocks')

    def test_28_is_blocked_when_the_partner_cannot_block(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/blocks/[^/]+'), Reply(404, {'detail': PROFILE_GONE})))
        (result, note), app = self.case('E-SAFE-28', self.good28())
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])


class AutoHideTest(SafePhone):
    """T=id-1 · F=id-2 · 폰 계정=id-3 · C=id-4 · D=id-5."""

    def good(self, **over):
        return self.app_reports(me='id-3', target='id-1', reason='spam', **{**ON_LIST, **over})

    def test_18_the_third_reporter_hides_the_target_from_the_candidates(self):
        _, app = self.passes('E-SAFE-18', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-1')}])
        self.assertEqual([s['auth'] for s in self.fake.by('POST', '/reports')], ['tok-4', 'tok-5'])  # C · D 는 PC 가 API 로
        self.assertEqual([r['reporter_id'] for r in self.last_reports], ['id-4', 'id-5', 'id-3'])  # 셋째가 앱(폰 계정)
        self.assertIsNotNone(self.fake.profile('id-1')['auto_hidden_at'])
        self.assert_no_reports_left()

    def test_18_fails_when_the_target_is_not_hidden_or_still_a_candidate(self):
        self.fake.rules['hide_at'] = 4
        self.fails('E-SAFE-18', self.good(), 'auto_hidden_at')

    def test_18_fails_when_hidden_early_by_the_second_reporter(self):
        self.fake.rules['hide_at'] = 2
        (result, note), _ = self.case('E-SAFE-18', self.good())
        self.assertEqual(result, 'blocked')  # 두 명에 이미 가려지면 "가려지기 전 후보에 있음" 을 못 본다 — 준비 실패
        self.assertIn('준비', note)

    def test_18_is_blocked_when_the_target_was_never_a_candidate(self):
        self.fake.on('GET', r'/matching/candidates', Reply(200, {'candidates': []}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        (result, _), app = self.case('E-SAFE-18', self.good())
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])

    def test_18_fails_when_the_hidden_target_is_still_a_candidate_of_F(self):
        original = self.fake._candidates

        def leaky(sent):
            reply = original(sent)
            if self.fake.profile('id-1')['auto_hidden_at']:  # 가려졌는데도 후보에 남기는 서버
                reply[1]['candidates'].append({'profile_id': 'id-1', 'score': 0.5})
            return reply
        self.fake.handlers.insert(0, ('GET', re.compile(r'/matching/candidates'), leaky))
        self.fails('E-SAFE-18', self.good(), 'F 의 후보')

    def test_18_fails_on_the_app_side_wrong_toast(self):
        self.fails('E-SAFE-18', self.good(toast='신고했어요'), '토스트')


class SuspendedTest(SafePhone):
    def good(self, **over):
        return said(**{'title': True, 'support': True, 'buttons': ['로그아웃'], 'stays': {'/home': True, '/conversations': True}, **over})

    def midway_app(self, answer, events=None):
        return MidwayApp(answer, 'suspend', events if events is not None else [])

    def test_50_suspended_screen_after_the_next_request_and_the_other_routes_bounce_back(self):
        seen = {}

        def answer(job):
            seen['status'] = self.fake.profile('id-1')['status']  # PC 는 앱이 멈춘 사이 정지를 걸었다
            return self.good()
        events = []
        _, app = self.passes('E-SAFE-50', None, self.midway_app(answer, events))
        self.assertEqual(seen['status'], 'suspended')
        self.assertEqual(events, ['step', 'go'])
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])

    def test_50_fails_on_a_missing_title_mail_extra_buttons_or_a_route_that_does_not_bounce(self):
        for over in ({'title': False}, {'support': False}, {'buttons': ['로그아웃', '문의']}, {'buttons': []},
                     {'stays': {'/home': False, '/conversations': True}}, {'stays': {'/home': True}}):
            self.fails('E-SAFE-50', None, app=self.midway_app(lambda job, over=over: self.good(**over)))

    def test_50_withdraw_link_beside_the_logout_button_is_allowed(self):
        _, _ = self.passes('E-SAFE-50', None, self.midway_app(lambda job: self.good(withdraw_link=True)))

    def test_50_a_silent_app_is_a_fail(self):
        self.fails('E-SAFE-50', None, app=self.midway_app(lambda job: None))


class ReloginApp(App):
    """같은 프로세스 안에서 로그아웃 → 다시 로그인: midway 가 돌려준 값(새 토큰)을 앱이 go 와 함께 듣는다."""

    def __init__(self, answer):
        super().__init__(answer)
        self.extra = 'unset'

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        self.extra = midway({'step': 'relogin'}) if midway else None
        return self.answer(job)


class ReloginTest(SafePhone):
    def sends(self, text='E2E-57', **over):
        def answer(job):
            self.fake.rows('messages').append({'id': str(uuid.uuid4()), 'match_id': self.match(), 'sender_id': 'id-1', 'kind': 'text', 'body': text})
            return said(**{'suspended_first': True, 'home_after': True, **over})
        return answer

    def test_57_after_release_a_second_login_in_the_same_process_sends_a_message(self):
        _, app = self.passes('E-SAFE-57', None, ReloginApp(self.sends()))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2'), 'text': 'E2E-57'}])
        self.assertEqual(app.extra, {'token_hash': 'h'})  # 새 토큰이 go 에 실려 간다
        self.assertEqual(self.fake.profile('id-1')['status'], 'active')
        sent = self.fake.sent
        patches = [i for i, s in enumerate(sent) if s['method'] == 'PATCH' and s['query'].get('id') == 'eq.id-1' and 'status' in (s['body'] or {})]
        self.assertEqual([sent[i]['body']['status'] for i in patches][-2:], ['suspended', 'active'])  # 정지 → 해제 순서
        email = self.fake.users[0]['email']
        links = [i for i, s in enumerate(sent) if s['path'].endswith('/generate_link') and s['body']['email'] == email]
        self.assertGreater(links[-1], patches[-1])  # 두 번째 토큰은 정지를 푼 뒤에 받는다(앞 토큰은 이미 썼다)

    def test_57_the_account_is_suspended_before_the_app_starts(self):
        seen = {}
        class Peek(ReloginApp):
            def __call__(inner, midway=None, **job):
                seen['before'] = self.fake.profile('id-1')['status']
                return super().__call__(midway, **job)
        self.passes('E-SAFE-57', None, Peek(self.sends()))
        self.assertEqual(seen['before'], 'suspended')

    def test_57_fails_without_the_sent_row_the_suspended_screen_or_the_home(self):
        for over in ({'suspended_first': False}, {'home_after': False}):
            self.fails('E-SAFE-57', None, app=ReloginApp(self.sends(**over)))
        self.fails('E-SAFE-57', None, 'messages', app=ReloginApp(lambda job: said(suspended_first=True, home_after=True)))
        self.fails('E-SAFE-57', None, 'messages', app=ReloginApp(self.sends(text='다른 글')))

    def test_57_fails_when_the_message_was_sent_twice(self):
        send = self.sends()
        def twice(job):
            send(job)
            return send(job)
        self.fails('E-SAFE-57', None, 'messages', app=ReloginApp(twice))


class BlockListTest(SafePhone):
    def rows_said(self, nicks, **over):
        dated = f'{area4._today()[0]} 차단'
        return said(**{'rows': [{'nickname': n, 'date': dated, 'button': '해제'} for n in nicks], 'avatars': len(nicks),
                       'notice': True, 'reason_words': False, **over})

    def test_30_both_blocks_newest_first_with_a_date_and_the_contact_notice(self):
        # 폰 계정=id-1 · B=id-2(직접 차단) · C=id-3(신고로 차단)
        _, app = self.passes('E-SAFE-30', lambda job: self.rows_said([self.nick('id-3'), self.nick('id-2')]))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual([r['blocked_id'] for r in self.rows('blocks')], ['id-2', 'id-3'])  # B 가 먼저, C 가 나중
        self.assertEqual([s['body']['target_type'] for s in self.fake.by('POST', '/reports')], ['profile'])
        self.assert_no_reports_left()

    def test_30_fails_on_the_wrong_order_a_missing_date_a_reason_a_missing_avatar_or_notice(self):
        def names(first):
            return [self.nick('id-3'), self.nick('id-2')][::first]
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(-1)), '순서')
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(1)[:1]), '줄')
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(1), rows=[{'nickname': n, 'date': '차단', 'button': '해제'} for n in names(1)]), '날짜')
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(1), reason_words=True), '사유')
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(1), avatars=1), '아바타')
        self.fails('E-SAFE-30', lambda job: self.rows_said(names(1), notice=False), '안내')

    def test_31_no_blocks_shows_the_empty_text(self):
        _, app = self.passes('E-SAFE-31', said(empty=True, sub=True, rows=0))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.rows('blocks'), [])

    def test_31_fails_on_a_missing_text_or_a_row(self):
        for over in ({'empty': False}, {'sub': False}, {'rows': 1}):
            self.fails('E-SAFE-31', said(**{'empty': True, 'sub': True, 'rows': 0, **over}))


# ── 망 끊기 ──────────────────────────────────────────────────────────────────────────────────────────

class TwoStageApp(App):
    """stepper 가 부르는 phone.hub(go · wait) 와 serial 을 가진 가짜 앱 — step 을 둘 말한다(cut → restore)."""

    def __init__(self, answer, events):
        super().__init__(answer)
        self.events, self.serial, self.hub = events, 'S', self
        self.later = ['restore']

    def go(self, extra=None):
        self.events.append('go')

    def wait(self, timeout):
        self.events.append('step')
        return {'step': self.later.pop(0)}

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if midway:
            self.events.append('step')
            midway({'step': 'cut'})
            self.events.append('go')  # 마지막 go 는 Run.phone 이 넣는다
        return self.answer(job)


class OfflineBase(SafePhone):
    def setUp(self):
        super().setUp()
        self.events = []
        self.state = {'airplane': 'disabled'}

        def fake_adb(serial, *args, check=True):
            self.events.append(('adb', serial, args))
            if args[-1] in ('enable', 'disable'):
                self.state['airplane'] = args[-1] + 'd'
            return self.state['airplane'] + '\n' if args[-1] == 'airplane-mode' else ''

        for patcher in (mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(notify.time, 'sleep'), mock.patch.object(Run, 'shot')):
            patcher.start()
            self.addCleanup(patcher.stop)

    def names(self):
        return [e if isinstance(e, str) else e[2][-1] for e in self.events]


class OfflineReportTest(OfflineBase):
    def answer(self, first=None, second=None):
        first = {'error': True, 'sheet_open': True, 'toast': None, 'in_room': True, **(first or {})}
        second = {**ON_LIST, **(second or {})}

        def answer(job):
            self.report_by('id-1', 'id-2')  # 망이 돌아온 뒤 두 번째 누름이 서버에 닿았다
            return said(first=first, second=second)
        return answer

    def test_60_first_try_keeps_the_sheet_and_the_second_try_saves_once(self):
        _, app = self.passes('E-SAFE-60', None, TwoStageApp(self.answer(), self.events))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])
        names = self.names()
        enable, disable = names.index('enable'), names.index('disable')
        gos = [i for i, n in enumerate(names) if n == 'go']
        self.assertLess(enable, gos[0])  # 끊기 → (앱이 첫 시도) → 켜기 → (앱이 두 번째 시도)
        self.assertLess(gos[0], disable)
        self.assertLess(disable, gos[1])
        self.assertEqual(self.state['airplane'], 'disabled')
        self.assert_no_reports_left()

    def test_60_checks_that_nothing_reached_the_server_while_the_network_was_off(self):
        def reached(job):
            return said(first={'error': True, 'sheet_open': True, 'toast': None, 'in_room': True}, second=ON_LIST)
        class EarlyRow(TwoStageApp):
            def wait(inner, timeout):
                self.report_by('id-1', 'id-2')  # 망이 없는데 신고가 서버에 들어갔다
                return super().wait(timeout)
        (result, note), _ = self.case('E-SAFE-60', None, EarlyRow(reached, self.events))
        self.assertEqual(result, 'fail')
        self.assertIn('망이 없는데', note)
        self.assertEqual(self.state['airplane'], 'disabled')

    def test_60_fails_when_the_first_try_closes_the_sheet_or_shows_no_message(self):
        for first in ({'sheet_open': False}, {'error': False}, {'toast': REPORTED}, {'in_room': False}):
            self.fails('E-SAFE-60', None, app=TwoStageApp(self.answer(first=first), self.events))
            self.assertEqual(self.state['airplane'], 'disabled')

    def test_60_fails_when_the_second_try_shows_another_result_or_saves_nothing(self):
        self.fails('E-SAFE-60', None, '토스트', app=TwoStageApp(self.answer(second={'toast': NETWORK}), self.events))
        self.fails('E-SAFE-60', None, 'reports', app=TwoStageApp(lambda job: said(first={'error': True, 'sheet_open': True, 'toast': None, 'in_room': True},
                                                                                   second=ON_LIST), self.events))

    def test_60_restores_the_network_when_the_app_crashes_or_is_blocked(self):
        (result, _), _ = self.case('E-SAFE-60', None, TwoStageApp(lambda job: {'result': 'blocked', 'note': '못 찾음'}, self.events))
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.state['airplane'], 'disabled')

        def crash(job):
            raise RuntimeError('앱이 죽음')
        with self.assertRaises(RuntimeError):
            self.case('E-SAFE-60', None, TwoStageApp(crash, self.events))
        self.assertEqual(self.state['airplane'], 'disabled')
        self.assert_no_reports_left()

    def block_answer(self, **over):
        return lambda job: said(**{'error': True, 'in_room': True, 'confirm_closed': True, 'above_input': True, **over})

    def offline_block(self, answer):
        app = MidwayApp(answer, 'cut', self.events)
        return self.case('E-SAFE-61', None, app)

    def test_61_a_failed_block_stays_in_the_room_with_one_line_above_the_input(self):
        (result, note), app = self.offline_block(self.block_answer())
        self.assertEqual((result, note), ('pass', ''))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick('id-2')}])
        names = self.names()
        self.assertLess(names.index('enable'), names.index('go'))
        self.assertLess(names.index('go'), names.index('disable'))
        self.assertEqual(self.state['airplane'], 'disabled')

    def test_61_fails_without_the_line_on_a_left_room_a_block_row_or_a_line_below_the_input(self):
        for over in ({'error': False}, {'in_room': False}, {'confirm_closed': False}, {'above_input': False}):
            (result, _), _ = self.offline_block(self.block_answer(**over))
            self.assertEqual(result, 'fail', over)
            self.assertEqual(self.state['airplane'], 'disabled')

        def blocks(job):
            self.fake._block({'auth': 'tok-1', 'path': '/blocks/id-2'})
            return self.block_answer()(job)
        (result, note), _ = self.offline_block(blocks)
        self.assertEqual(result, 'fail')
        self.assertIn('blocks', note)


# ── 등록부 · 안전망 ──────────────────────────────────────────────────────────────────────────────────

class RegistryTest(SafePhone):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_bundle_is_the_18_safety_phone_cases_and_none_of_the_api_ones(self):
        self.assertEqual(area3.BUNDLES['area3-safe-phone'], BUNDLE)
        self.assertEqual(list(area3_safe_phone.SAFE_PHONE), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))
        from e2e import area3_safe
        self.assertFalse(set(BUNDLE) & set(area3_safe.CASES))
        for other in ('area3-phone-1', 'area3-phone-2'):
            self.assertFalse(set(BUNDLE) & set(area3.BUNDLES[other]))

    def test_main_runs_the_bundle_through_area1_phone(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area3-safe-phone'], BUNDLE)
        self.assertFalse(set(BUNDLE) & set(main.API_CASES))
        self.assertIn("from e2e import area3_safe_phone", (tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'))

    def test_the_app_has_the_same_numbers_in_order_and_area3_merges_them(self):
        part = self.dart('area3_safe.dart')
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), BUNDLE)
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        main = self.dart('area3.dart')
        self.assertIn("part 'area3_safe.dart';", main)
        self.assertIn('...area3CasesSafe', main)

    def test_every_job_key_the_pc_sends_is_read_by_the_app(self):
        dart = self.dart('area3_safe.dart')
        for key in ('nickname', 'profile_id', 'note', 'mine', 'system', 'theirs', 'question', 'own', 'text'):
            self.assertIn(f"job['{key}']", dart, key)
        self.assertIn('_pasted(job)', dart)  # 붙여 넣을 글(`paste`)은 area3_b2.dart 의 _pasted 가 읽는다
        self.assertIn("again['token_hash']", dart)  # 두 번째 로그인 토큰은 step 이 돌려준 값에서

    def test_the_app_never_builds_or_runs_anything_on_its_own_network(self):
        # 망 끊기는 PC 몫 — 앱 쪽은 step 으로 멈추기만 한다.
        dart = self.dart('area3_safe.dart')
        self.assertNotIn('airplane', dart)
        self.assertIn("step('cut')", dart)
        self.assertIn("step('restore')", dart)

    def test_silent_app_is_a_fail_and_a_blocked_app_is_blocked(self):
        (result, _), _ = self.case('E-SAFE-26', lambda job: None)
        self.assertEqual(result, 'fail')
        (result, note), _ = self.case('E-SAFE-26', lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual((result, note), ('blocked', '앱: 못 찾음'))

    def test_every_case_is_blocked_before_the_app_when_the_server_is_down(self):
        down = PhoneFake()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down):
            for name in BUNDLE:
                app = App(lambda job: said())
                result, note = area1.attempt_phone(self.run_, name, app)
                self.assertEqual(result, 'blocked', f'{name}: {note}')
                self.assertEqual(app.jobs, [], name)


if __name__ == '__main__':
    unittest.main()
