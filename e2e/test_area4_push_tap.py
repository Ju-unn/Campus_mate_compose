"""영역 4 PUSH A2(알림을 눌러 화면이 열리는지 10개) 시험 — 폰 · 운영 없이 가짜 HTTP · 가짜 알림창 · 가짜 앱.
저장소 루트에서 `python -m unittest e2e.test_area4_push_tap`.

계정은 만든 순서대로 id-1(폰 계정 · Mina) · id-2(상대 · Jiho), 토큰은 tok-1 · tok-2.
"""

import re
import unittest
from pathlib import Path
from unittest import mock

from e2e import area1, area4_push_tap, notify, tools  # noqa: F401 — 가설을 area1.PHONE 에 등록한다
from e2e.test_area1_phone import FakePhone
from e2e.test_area4_push import ACCEPT, MATCH, PARTNER, PUBLIC, REVIEW, TRUST, PushBase
from e2e.tools import Blocked, Reply

NUMBERS = {  # 번호 → (알림 종류, 앱 상태)
    '11': ('accept', 'back'), '19': ('match', 'back'), '27': ('message', 'back'), '38': ('public', 'back'), '50': ('review', 'back'),
    '28': ('message', 'killed'), '76': ('accept', 'killed'), '77': ('match', 'killed'), '78': ('trust', 'killed'), '81': ('review', 'killed'),
}
FOUND = {'result': 'pass', 'dest': True, 'who': True, 'body': True, 'screen': ['home'], 'ms': 1200}


class TapPhone(FakePhone):
    """가짜 폰 — 켜는 판(`phone(...)`)과 알림 누름 판(`hub.tell` → `hub.result`)을 같은 [world.log] 에 남긴다."""

    def __init__(self, world, shown=None):
        super().__init__(dict(FOUND) if shown is None else shown)
        self.world, self.tapped = world, dict(FOUND) if shown is None else shown
        self.hub = mock.Mock()
        self.hub.tell.side_effect = lambda job: world.log.append(f"tell:{job.get('phase')}")
        self.hub.result.side_effect = lambda timeout: self.tapped
        self.case = None

    def __call__(self, midway=None, **job):
        self.world.log.append(f"app:{job.get('phase')}")
        return super().__call__(midway, **job)


class TapBase(PushBase):
    def setUp(self):
        super().setUp()
        world = self.world
        self.tap_bodies = []  # 알림을 누를 때 넘긴 본문(같은 제목의 옛 알림을 피하려고)
        self.delivery = []  # (시리얼, 그때까지 앱이 받은 일감 수) — 푸시 연결 점검(실제 adb 는 불리지 않는다)
        for patcher in (mock.patch.object(notify, 'ensure_delivery', lambda s: self.delivery.append((s, len(self.phone.jobs)))),
                        mock.patch.object(notify, 'kill_app', lambda s: world.log.append('kill')),
                        mock.patch.object(notify, 'tap_notification', lambda s, title, body=None: (world.log.append(f'tap:{title}'), self.tap_bodies.append(body)))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def routes(self, kind):
        """상대의 행동이 부르는 API 에 맞춰 알림이 뜨게 한다."""
        on = self.world.on
        if kind == 'accept':
            on('POST', '/decision', lambda b, u: [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')])
        elif kind == 'match':
            on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님도 수락했어요')])
        elif kind == 'message':
            on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])])
        elif kind == 'public':
            on('POST', '/trust', lambda b, u: [(PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')] if len(self.fake.bodies('POST', '/trust')) == 1 else [])
        elif kind == 'trust':
            on('POST', '/trust', lambda b, u: [(PARTNER, TRUST)])
        elif kind == 'review':
            on('POST', '/friend-reviews', lambda b, u: [(REVIEW, f'{PARTNER} 님이 리뷰를 남겼어요')])

    def go_tap(self, number, shown=None, notice=True):
        kind, _ = NUMBERS[number]
        if notice:
            self.routes(kind)
        phone = TapPhone(self.world, shown)
        phone.case = f'E-PUSH-{number}'
        return self.go_push(f'E-PUSH-{number}', phone=phone)

    def at(self, prefix):
        return [i for i, line in enumerate(self.world.log) if line.startswith(prefix)]


class EachCaseTest(TapBase):
    def test_all_ten_pass_when_the_notice_comes_it_is_tapped_and_the_app_sees_the_screen(self):
        for number in NUMBERS:
            with self.subTest(number=number):
                self.world.reset()
                result = self.go_tap(number)
                self.assertEqual(result[0], 'pass', (number, result))
                self.assertEqual(len([line for line in self.world.log if line.startswith('tap:')]), 1)

    def test_the_tapped_title_is_the_one_the_server_sends_for_that_kind(self):
        want = {'accept': ACCEPT, 'match': MATCH, 'message': PARTNER, 'public': PUBLIC, 'trust': PARTNER, 'review': REVIEW}
        for number, (kind, _) in NUMBERS.items():
            with self.subTest(number=number):
                self.world.reset()
                self.go_tap(number)
                self.assertIn(f'tap:{want[kind]}', self.world.log)

    def test_the_app_is_told_which_screen_and_who_to_look_for(self):
        want = {'accept': ('conversations', 'acceptance'), 'match': ('conversations', 'chat'), 'message': ('room', None), 'public': ('room', None),
                'trust': ('room', None), 'review': ('reviews', None)}
        for number, (kind, state) in NUMBERS.items():
            with self.subTest(number=number):
                self.world.reset()
                phone = TapPhone(self.world)
                phone.case = f'E-PUSH-{number}'
                self.routes(kind)
                self.go_push(f'E-PUSH-{number}', phone=phone)
                job = phone.jobs[0] if state == 'back' else phone.hub.tell.call_args.args[0]
                self.assertEqual((job['dest'], job.get('section')), want[kind])
                self.assertEqual(job['nickname'], PARTNER)
                self.assertEqual('body' in job, kind == 'message')  # 방금 메시지가 보여야 하는 건 메시지 알림뿐

    def test_the_message_text_the_app_must_find_is_the_one_the_partner_sent(self):
        self.routes('message')
        phone = TapPhone(self.world)
        phone.case = 'E-PUSH-27'
        self.go_push('E-PUSH-27', phone=phone)
        sent = self.fake.bodies('POST', '/messages')[0]['body']
        self.assertEqual(phone.jobs[0]['body'], sent)


class BackCaseTest(TapBase):
    def test_the_tap_is_given_the_notice_body_so_an_older_notice_with_the_same_title_is_not_tapped(self):
        for number in NUMBERS:
            with self.subTest(number=number):
                self.world.reset()
                self.tap_bodies.clear()
                self.go_tap(number)
                self.assertEqual(len(self.tap_bodies), 1)
                self.assertTrue(self.tap_bodies[0], number)  # 비어 있지 않은 본문 — 제목만으로 고르지 않는다

    def test_the_app_is_sent_home_before_the_partner_acts_and_the_tap_comes_after_the_notice(self):
        self.go_tap('11')
        log = self.world.log
        self.assertLess(self.at('grant')[0], self.at('app:hold')[0])
        self.assertLess(self.at('read')[0], self.at('background')[0])
        self.assertLess(self.at('background')[0], self.at('POST cards/')[-1])
        self.assertLess(self.at('POST cards/')[-1], self.at('tap:')[0])
        self.assertEqual(self.at('kill'), [])  # 뒤에 있는 앱은 죽이지 않는다
        self.assertEqual(log[-1], 'revoke')

    def test_the_partner_is_the_one_who_acts(self):
        self.go_tap('11')
        self.assertEqual([who for m, p, who in self.world.callers if '/decision' in p and who in ('tok-1', 'tok-2')], ['tok-2'])

    def test_a_missing_device_token_is_blocked_before_anything_is_sent(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        result = self.go_tap('11')
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.fake.bodies('POST', '/decision'), [])

    def test_no_notice_is_a_fail_and_nothing_is_tapped(self):
        result = self.go_tap('11', notice=False)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.at('tap:'), [])

    def test_a_screen_that_never_opens_is_a_fail_naming_where_the_app_was(self):
        result = self.go_tap('11', shown={**FOUND, 'dest': False, 'who': False, 'screen': ['consent']})
        self.assertEqual(result[0], 'fail')
        self.assertIn('약관', result[1])

    def test_the_screen_without_the_person_is_a_fail(self):
        result = self.go_tap('11', shown={**FOUND, 'who': False})
        self.assertEqual(result[0], 'fail')
        self.assertIn(PARTNER, result[1])

    def test_the_room_without_the_message_is_a_fail(self):
        self.assertEqual(self.go_tap('27', shown={**FOUND, 'body': False})[0], 'fail')

    def test_the_room_opened_by_a_public_notice_does_not_need_a_message(self):
        self.assertEqual(self.go_tap('38', shown={k: v for k, v in FOUND.items() if k != 'body'})[0], 'pass')

    def test_the_push_connection_is_checked_before_the_app_starts(self):
        self.go_tap('11')
        self.assertEqual(self.delivery, [('S', 0)])


class KilledCaseTest(TapBase):
    def test_login_then_kill_then_the_partner_acts_then_tell_then_tap(self):
        self.go_tap('76')
        log = self.world.log
        self.assertLess(self.at('grant')[0], self.at('app:login')[0])
        self.assertLess(self.at('app:login')[0], self.at('kill')[0])
        self.assertLess(self.at('kill')[0], self.at('POST cards/')[-1])
        self.assertLess(self.at('POST cards/')[-1], self.at('tell:tap')[0])  # 누르기 전에 일감을 넣는다
        self.assertLess(self.at('tell:tap')[0], self.at('tap:')[0])
        self.assertEqual(log[-1], 'revoke')

    def test_the_tap_job_carries_the_case_and_no_login_token(self):
        phone = TapPhone(self.world)
        phone.case = 'E-PUSH-76'
        self.routes('accept')
        self.go_push('E-PUSH-76', phone=phone)
        job = phone.hub.tell.call_args.args[0]
        self.assertEqual((job['case'], job['phase']), ('E-PUSH-76', 'tap'))
        self.assertNotIn('token_hash', job)  # 앞 판이 저장한 세션이 살아 있어야 한다

    def test_no_notice_is_a_fail_and_the_app_is_never_told_to_look(self):
        result = self.go_tap('76', notice=False)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.at('tell:tap'), [])
        self.assertEqual(self.at('tap:'), [])

    def test_a_login_that_never_reaches_home_stops_before_the_kill(self):
        phone = TapPhone(self.world, shown={'result': 'fail', 'note': '홈 못 감'})
        phone.case = 'E-PUSH-76'
        self.routes('accept')
        result = self.go_push('E-PUSH-76', phone=phone)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.at('kill'), [])

    def test_a_screen_that_never_opens_after_the_cold_start_is_a_fail(self):
        result = self.go_tap('76', shown={**FOUND, 'dest': False, 'who': False, 'screen': ['consent']})
        self.assertEqual(result[0], 'fail')

    def test_the_note_has_the_milliseconds_the_app_took(self):
        result = self.go_tap('28')
        self.assertIn('1200', result[1])

    def test_the_partner_acts_after_the_kill_in_every_killed_case(self):
        for number in ('28', '76', '77', '78', '81'):
            with self.subTest(number=number):
                self.world.reset()
                self.go_tap(number)
                api = [i for i, line in enumerate(self.world.log) if re.match(r'POST (cards|chat|friend-reviews)', line)]
                self.assertLess(self.at('kill')[0], api[-1])


class WiringTest(TapBase):
    def test_at_night_it_is_blocked_before_the_phone_is_called(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))):
            result = self.go_tap('11')
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.phone.jobs, [])

    def test_the_bundle_is_exactly_the_ten_cases_and_each_is_a_phone_case(self):
        ids = [f'E-PUSH-{n}' for n in NUMBERS]
        self.assertEqual(sorted(area1.BUNDLES['area4-push-a2']), sorted(ids))
        for case in ids:
            self.assertIn(case, area1.PHONE)

    def test_the_slow_killed_cases_get_a_longer_limit(self):
        for number in ('28', '76', '77', '78', '81'):
            self.assertGreater(tools.CASE_LIMITS[f'E-PUSH-{number}'], tools.CASE_LIMIT)

    def test_the_app_side_knows_the_same_ten_numbers(self):
        dart = (Path(__file__).resolve().parent.parent / 'frontend' / 'integration_test' / 'area4_push_tap.dart').read_text(encoding='utf-8')
        listed = re.search(r"_pushTapCases\s*=\s*\[([^\]]*)\]", dart)
        self.assertIsNotNone(listed)
        self.assertEqual(sorted(re.findall(r"'(\d+)'", listed.group(1))), sorted(NUMBERS))


if __name__ == '__main__':
    unittest.main()
