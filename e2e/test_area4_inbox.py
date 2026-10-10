"""영역 4 알림함 E-INBOX-01~04 시험 — 폰 · 운영 없이 가짜 HTTP · 가짜 앱으로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area4_inbox`.

가짜 서버(Inbox)는 카드 수락 · 지인 리뷰가 불리면 받는 사람의 알림함에 줄을 쌓고(운영 backend/app/cards/push.py 가 하는 일),
알림함 API 4개와 알림 스위치 저장에 답한다. 계정은 만든 순서대로 id-1(받는 사람 Mina) · id-2(Aa) · id-3(Bb) · id-4(Cc …), 토큰은 tok-1 · tok-2 …
"""

import itertools
import re
import subprocess
import sys
import unittest
from urllib.parse import urlsplit
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area4_inbox, notify, tools
from e2e.test_area1_phone import FakePhone
from e2e.test_area2 import Base, Fake
from e2e.test_area4_push import ACCEPT, REVIEW
from e2e.tools import Reply

NAMES = ['Mina', 'Aa', 'Bb', 'Cc', 'Dd', 'Ee']
RECEIVED = '받은 리뷰'


def read(*parts):
    return tools.ROOT.joinpath(*parts).read_text(encoding='utf-8')


def nick(account_id):
    return NAMES[int(account_id.split('-')[1]) - 1]


class Inbox:
    """계정별 알림함 줄(최신이 앞) — 운영 notifications 표와 알림함 API 의 흉내."""

    def __init__(self):
        self.rows = {}  # 받는 사람 id → 줄 목록(최신순)
        self.cards = {}  # 카드 id → (주인 id, 상대 id)
        self.ids = itertools.count(1)
        self.switches = {}
        self.calls = []
        self.wrong = set()  # 일부러 틀리게 만드는 스위치(시험이 켠다)

    def add(self, owner, kind, title, body):
        n = next(self.ids)
        self.rows.setdefault(owner, []).insert(0, {'id': f'00000000-0000-4000-8000-{n:012d}', 'kind': kind, 'title': title, 'body': body,
                                                    'data': {}, 'created_at': f'2026-10-10T12:00:{n:02d}+00:00', 'read': False})

    def who(self, headers):
        token = (headers or {}).get('Authorization', '').replace('Bearer ', '')
        return f"id-{token.split('-')[1]}" if token.startswith('tok-') else None

    def serve(self, method, url, headers):
        """알림함 API 한 번 — 몰라서 못 답하면 None."""
        path, me = urlsplit(url).path, self.who(headers)
        self.calls.append((method, path, me))
        mine = self.rows.get(me, [])
        if (method, path) == ('GET', '/notifications'):
            unread = sum(1 for r in mine if not r['read'])
            return Reply(200, {'items': [dict(r) for r in mine], 'unread_count': unread, 'next_before': None})
        if (method, path) == ('GET', '/notifications/unread-count'):
            return Reply(200, {'unread_count': sum(1 for r in mine if not r['read'])})
        if (method, path) == ('POST', '/notifications/read-all'):
            if 'read_all_deletes' in self.wrong:
                mine.clear()
            for r in mine:
                r['read'] = True
            return Reply(200, {'unread_count': 0})
        found = re.fullmatch(r'/notifications/([0-9a-f-]+)/read', path)
        if method == 'POST' and found:
            row = next((r for r in mine if r['id'] == found.group(1)), None)
            if row is None and 'strangers_read' in self.wrong:
                row = next((r for rows in self.rows.values() for r in rows if r['id'] == found.group(1)), None)
            if row is None:
                return Reply(404, {'detail': '알림을 찾을 수 없어요'})
            row['read'] = True
            return Reply(200, {'read': True})
        return None


def make_fake(inbox, skip_record_when_off=False):
    """계정 공장 위에 알림함 · 카드 · 리뷰 · 스위치를 얹은 가짜 서버."""
    tokens = itertools.count(1)

    class InboxFake(Fake):
        last_headers = None

        def __call__(self, method, url, headers=None, body=None, raw=None, **options):
            self.last_headers = headers
            served = inbox.serve(method, url, headers)
            if served is not None:
                return served
            return super().__call__(method, url, headers, body, raw, **options)

    def card_made(body, url):
        for row in body if isinstance(body, list) else [body]:
            inbox.cards[row['id']] = (row['owner_id'], row['target_id'])
        return Reply(201, body)

    def decision(body, url):
        owner, target = inbox.cards[re.search(r'/cards/([^/]+)/decision', url).group(1)]
        off = inbox.switches.get(target, {}).get('acceptance_received') is False
        if not (off and skip_record_when_off):
            inbox.add(target, 'chat_request', ACCEPT, f'{nick(owner)} 님이 대화를 신청했어요')
        return Reply(200, {})

    def review(body, url):
        inbox.add(body['reviewee_id'], 'friend_review', REVIEW, f'{nick(inbox.who(fake.last_headers))} 님이 리뷰를 남겼어요')
        return Reply(201, {'id': 'r'})

    def switch(body, url):
        inbox.switches.setdefault(inbox.who(fake.last_headers), {}).update(body)
        return Reply(200, {})

    fake = InboxFake([
        ('POST', '/auth/v1/verify', lambda b, u: Reply(200, {'access_token': f'tok-{next(tokens)}'})),
        ('POST', 'daily_cards', card_made),
        ('POST', '/decision', decision),
        ('POST', '/friend-reviews', review),
        ('PATCH', '/cards/notification-settings', switch),
    ])
    return fake


class InboxBase(Base):
    def setUp(self):
        super().setUp()
        self.inbox = Inbox()
        names = itertools.chain(NAMES, (f'Ex{i}' for i in itertools.count()))
        for patcher in (mock.patch.object(area1, '_nickname', lambda: next(names)),
                        mock.patch.object(notify, 'grant_notifications', lambda s: None),
                        mock.patch.object(notify, 'revoke_notifications', lambda s: None)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def fake(self, **kw):
        fake = make_fake(self.inbox, **kw)
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.server = fake
        return fake

    def phone_case(self, case, answer, app=None):
        """폰 가설을 가짜 앱으로 돌린다 — [app](일감) 은 앱이 서버에 한 일(읽음 처리)을 흉내 낸다."""
        self.fake()
        outer = self

        class App(FakePhone):
            def __call__(self, midway=None, **job):
                if app:
                    app(outer.inbox, job)
                return super().__call__(midway, **job)

        phone = App(answer)
        phone.serial = 'S'
        return area1.attempt_phone(self.run, case, phone), phone

    def api_case(self, case, **kw):
        self.fake(**kw)
        return area1.attempt(self.run, case)


ROWS = [[REVIEW, 'Cc 님이 리뷰를 남겼어요'], [ACCEPT, 'Bb 님이 대화를 신청했어요'], [ACCEPT, 'Aa 님이 대화를 신청했어요']]
APP_01 = {'result': 'pass', 'badge': 3, 'rows': ROWS, 'landed': RECEIVED, 'badge_after': 2}
APP_02 = {'result': 'pass', 'badge': 3, 'button_gone': True, 'rows_after': 3, 'badge_after': 0}


def tapped_first(inbox, job):
    """앱이 첫 줄을 눌렀다 → 서버에서 그 줄만 읽음."""
    inbox.rows['id-1'][0]['read'] = True


def read_all(inbox, job):
    for row in inbox.rows['id-1']:
        row['read'] = True


class PhoneCaseTest(InboxBase):
    def test_01_passes_when_the_app_sees_the_badge_rows_and_screen_and_only_the_tapped_row_is_read(self):
        (result, note), phone = self.phone_case('E-INBOX-01', APP_01, tapped_first)
        self.assertEqual(result, 'pass', note)
        self.assertIn('token_hash', phone.jobs[0])

    def test_01_each_wrong_thing_the_app_says_is_a_fail_that_names_it(self):
        for label, change, word in (('배지', {'badge': 2}, '종 배지'), ('줄 순서', {'rows': ROWS[::-1]}, '알림함 줄'),
                                    ('문구', {'rows': [[REVIEW, '다른 글'], *ROWS[1:]]}, '알림함 줄'),
                                    ('이동', {'landed': None}, '화면'), ('돌아온 배지', {'badge_after': 3}, '돌아온')):
            with self.subTest(label):
                self.setUp()
                (result, note), _ = self.phone_case('E-INBOX-01', {**APP_01, **change}, tapped_first)
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_01_a_server_that_did_not_mark_the_tapped_row_read_is_a_fail(self):
        (result, note), _ = self.phone_case('E-INBOX-01', APP_01, None)
        self.assertEqual(result, 'fail', note)
        self.assertIn('읽음 표시', note)

    def test_01_a_server_that_marked_every_row_read_is_a_fail(self):
        (result, note), _ = self.phone_case('E-INBOX-01', APP_01, read_all)
        self.assertEqual(result, 'fail', note)

    def test_02_passes_when_the_button_goes_the_rows_stay_the_badge_is_gone_and_everything_is_read(self):
        (result, note), _ = self.phone_case('E-INBOX-02', APP_02, read_all)
        self.assertEqual(result, 'pass', note)

    def test_02_each_wrong_thing_is_a_fail(self):
        for label, change in (('버튼', {'button_gone': False}), ('줄이 지워짐', {'rows_after': 0}), ('배지', {'badge_after': 2})):
            with self.subTest(label):
                self.setUp()
                (result, note), _ = self.phone_case('E-INBOX-02', {**APP_02, **change}, read_all)
                self.assertEqual(result, 'fail', note)

    def test_02_a_server_that_deleted_the_rows_or_left_some_unread_is_a_fail(self):
        for label, app in (('안 읽음 남음', tapped_first), ('앱이 아무것도 안 함', None)):
            with self.subTest(label):
                self.setUp()
                (result, note), _ = self.phone_case('E-INBOX-02', APP_02, app)
                self.assertEqual(result, 'fail', note)

    def test_an_app_that_says_blocked_makes_both_cases_blocked(self):
        for case in ('E-INBOX-01', 'E-INBOX-02'):
            with self.subTest(case):
                self.setUp()
                (result, _), _ = self.phone_case(case, {'result': 'blocked', 'note': '홈에 못 닿음'})
                self.assertEqual(result, 'blocked')

    def test_the_prepared_inbox_is_checked_before_the_app_starts_and_a_wrong_one_is_blocked(self):
        original = self.inbox.add

        def lose_the_review(owner, kind, title, body):
            if kind != 'friend_review':
                original(owner, kind, title, body)

        self.inbox.add = lose_the_review
        (result, note), phone = self.phone_case('E-INBOX-01', APP_01, tapped_first)
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(phone.jobs, [])  # 앱은 켜지도 않았다

    def test_the_phone_cases_ask_for_the_notification_permission_first_and_give_it_back(self):
        calls = []
        with mock.patch.object(notify, 'grant_notifications', lambda s: calls.append('grant')), \
                mock.patch.object(notify, 'revoke_notifications', lambda s: calls.append('revoke')):
            self.phone_case('E-INBOX-02', APP_02, read_all)
        self.assertEqual(calls, ['grant', 'revoke'])


class ApiCaseTest(InboxBase):
    def test_03_a_switched_off_kind_still_leaves_an_inbox_row_and_a_second_one_after_turning_it_on(self):
        result, note = self.api_case('E-INBOX-03')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.inbox.switches['id-1'], {'acceptance_received': True})  # 끄고 → 다시 켬(마지막 값이 켬)
        self.assertEqual([r['kind'] for r in self.inbox.rows['id-1']], ['chat_request', 'chat_request'])

    def test_03_a_server_that_skips_the_row_while_the_switch_is_off_is_a_fail(self):
        result, note = self.api_case('E-INBOX-03', skip_record_when_off=True)
        self.assertEqual(result, 'fail', note)
        self.assertIn('스위치를 끈 채', note)

    def test_04_passes_on_the_documented_shape_and_read_rules(self):
        result, note = self.api_case('E-INBOX-04')
        self.assertEqual(result, 'pass', note)

    def test_04_read_all_that_deletes_rows_is_a_fail(self):
        self.inbox.wrong.add('read_all_deletes')
        result, note = self.api_case('E-INBOX-04')
        self.assertEqual(result, 'fail', note)

    def test_04_reading_someone_elses_notification_must_be_404(self):
        self.inbox.wrong.add('strangers_read')
        result, note = self.api_case('E-INBOX-04')
        self.assertEqual(result, 'fail', note)
        self.assertIn('남의 알림', note)


class RegistryTest(unittest.TestCase):
    def test_two_phone_cases_and_two_api_cases_in_their_own_bundles(self):
        self.assertEqual(cli.BUNDLES['area4-inbox'], ['E-INBOX-01', 'E-INBOX-02'])
        self.assertEqual(cli.BUNDLES['area4-inbox-api'], ['E-INBOX-03', 'E-INBOX-04'])
        for case in ('E-INBOX-01', 'E-INBOX-02'):
            self.assertIn(case, area1.PHONE)
            self.assertNotIn(case, cli.API_CASES)
        for case in ('E-INBOX-03', 'E-INBOX-04'):
            self.assertIn(case, cli.API_CASES)
            self.assertNotIn(case, area1.PHONE)
        self.assertFalse(any(case in bundle for name, bundle in cli.BUNDLES.items() if not name.startswith('area4-inbox')
                             for case in ('E-INBOX-01', 'E-INBOX-02', 'E-INBOX-03', 'E-INBOX-04')))

    def test_the_phone_cases_get_a_case_limit_that_covers_two_screens_of_waiting(self):
        for case in ('E-INBOX-01', 'E-INBOX-02'):
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 600)

    def test_a_fresh_interpreter_that_only_imports_the_program_entry_sees_them(self):
        probe = 'from e2e import __main__ as m; print(m.BUNDLES.get("area4-inbox"), m.BUNDLES.get("area4-inbox-api"))'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), "['E-INBOX-01', 'E-INBOX-02'] ['E-INBOX-03', 'E-INBOX-04']")

    def test_the_program_entry_imports_the_module_uncommented(self):
        self.assertTrue(re.search(r'(?m)^from e2e import area4_inbox\b', read('e2e', '__main__.py')))

    def test_the_app_side_registers_both_phone_cases(self):
        dart = read('frontend', 'integration_test', 'e2e_test.dart')
        self.assertIn("import 'area4_inbox.dart';", dart)
        self.assertIn('...area4InboxCases,', dart)
        inbox = read('frontend', 'integration_test', 'area4_inbox.dart')
        for case in ('E-INBOX-01', 'E-INBOX-02'):
            self.assertIn(f"'{case}': _session(", inbox)

    def test_the_words_the_cases_expect_are_the_ones_the_app_and_server_really_use(self):
        inbox_dart = read('frontend', 'integration_test', 'area4_inbox.dart')
        screen = read('frontend', 'lib', 'notifications', 'view', 'notifications_screen.dart')
        for word in ('모두 읽음', "Text('알림'"):
            self.assertIn(word, screen)
        self.assertIn("const _markAllRead = '모두 읽음';", inbox_dart)
        self.assertIn(f"const _receivedReviews = '{RECEIVED}';", inbox_dart)
        self.assertIn(f"'{RECEIVED}'", read('frontend', 'lib', 'friend_review', 'view', 'received_reviews_screen.dart'))
        self.assertEqual(area4_inbox.RECEIVED_REVIEWS, RECEIVED)

    def test_the_app_reads_the_badge_from_the_widget_not_from_text_and_waits_for_the_server_value(self):
        inbox_dart = read('frontend', 'integration_test', 'area4_inbox.dart')
        self.assertIn('tester.widget<NotifyIconButton>(bell.first).count', inbox_dart)
        self.assertIn('_badgeBecomes(tester, 3, _badgeWait)', inbox_dart)  # 홈이 그려진 직후 0 이 아니라 서버 값 3 을 기다린다


if __name__ == '__main__':
    unittest.main()
