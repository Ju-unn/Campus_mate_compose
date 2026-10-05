"""영역 4 PUSH A3(앱이 앞에 있을 때 알림은 안 뜨고 화면만 바뀌는지 7개) 시험 — 폰 · 운영 없이 가짜 HTTP · 가짜 알림창 · 가짜 앱.
저장소 루트에서 `python -m unittest e2e.test_area4_push_front`.

계정은 만든 순서대로 id-1(폰 계정 · Mina) · id-2(상대 · Jiho) · id-3(대조 · Ctlx), 토큰은 tok-1 · tok-2 · tok-3.
"""

import re
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from e2e import area1, area4_push_front, notify, tools  # noqa: F401 — 가설을 area1.PHONE 에 등록한다
from e2e.test_area1_phone import FakePhone
from e2e.test_area4_push import ACCEPT, CTL, MATCH, PARTNER, REVIEW, PushBase
from e2e.tools import Blocked, Reply

NUMBERS = ('14', '20', '29', '30', '31', '53', '82')
OK = {'result': 'pass', 'front': True, 'row': True, 'body': True, 'badge': True, 'absent': True, 'present': True, 'ms': 800}


class FrontPhone(FakePhone):
    """가짜 앱 — 켜면 [midway] 를 한 번 부르고, 이어지는 멈춤은 가짜 hub 가 대신한다. 앱이 한 말은 [shown]."""

    def __init__(self, world, shown=None):
        super().__init__(dict(OK) if shown is None else shown)
        self.world = world
        self.hub = mock.Mock()
        self.hub.go.side_effect = lambda extra=None: world.log.append('go')
        self.hub.wait.side_effect = lambda timeout: {'step': 'x'}

    def __call__(self, midway=None, **job):
        self.world.log.append(f"app:{job.get('screen')}")
        return super().__call__(midway, **job)


class FrontBase(PushBase):
    def setUp(self):
        super().setUp()
        self.slept = []
        self.watched = []  # 지켜본 초(expect_none) · 기다린 초와 match 유무(wait_new) — PushBase 의 가짜가 안 남기는 값을 여기서 남긴다
        world = self.world
        for name, fake in (('expect_none', lambda s, before, seconds=0: self.watched.append(('watch', seconds)) or world.new(before)),
                           ('wait_new', lambda s, before, count=1, seconds=0, match=None: self.watched.append(('wait', seconds, match is not None)) or [
                               n for n in world.new(before) if match is None or match(n)])):
            patcher = mock.patch.object(notify, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)
        # 이 모듈이 쓰는 time 만 바꿔 잠잔 시간을 센다(공용 time.sleep 은 PushBase 가 이미 막았다 — 거기에 얹으면 덮어쓰인다)
        patcher = mock.patch.object(area4_push_front, 'time', SimpleNamespace(sleep=lambda s: self.slept.append(s)))
        patcher.start()
        self.addCleanup(patcher.stop)
        # 앞에 있는 동안은 알림이 안 뜨고, HOME 으로 내린 뒤에는 보낸 메시지가 알림으로 뜬다(대조) — 제목은 보낸 사람 닉네임
        self.default_rules()

    def default_rules(self):
        self.world.on('POST', '/messages', lambda b, u: [] if 'background' not in self.world.log else
                      [(PARTNER if self.world.callers[-1][2] == 'tok-2' else CTL, b['body'])])

    def second_message_only(self):
        """31 — 첫 메시지는 알림이 없고(30초 안), 두 번째(40초 뒤)부터 뜬다."""
        self.world.rules.clear()
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])] if len(self.fake.bodies('POST', '/messages')) >= 1 else [])

    def go_front(self, number, shown=None):
        phone = FrontPhone(self.world, shown)
        phone.case = f'E-PUSH-{number}'
        return self.go_push(f'E-PUSH-{number}', phone=phone)

    def at(self, prefix):
        return [i for i, line in enumerate(self.world.log) if line.startswith(prefix)]

    def callers_of(self, piece):
        return [who for m, p, who in self.world.callers if m == 'POST' and piece in p and who in ('tok-1', 'tok-2')]


class EachCaseTest(FrontBase):
    def test_all_seven_pass_when_nothing_pops_up_and_the_screen_changes(self):
        for number in NUMBERS:
            with self.subTest(number=number):
                self.world.reset()
                self.second_message_only() if number == '31' else self.default_rules()
                result = self.go_front(number)
                self.assertEqual(result[0], 'pass', (number, result))

    def test_the_room_cases_hand_the_app_the_room_id_and_the_others_do_not(self):
        for number in NUMBERS:
            with self.subTest(number=number):
                self.world.reset()
                phone = FrontPhone(self.world)
                phone.case = f'E-PUSH-{number}'
                self.go_push(f'E-PUSH-{number}', phone=phone)
                self.assertEqual('match_id' in phone.jobs[0], number in ('29', '30', '31'))

    def test_the_app_is_told_which_screen_to_stay_on(self):
        want = {'14': 'conversations', '20': 'conversations', '29': 'room', '30': 'room', '31': 'room', '53': 'reviews', '82': 'today'}
        for number, screen in want.items():
            with self.subTest(number=number):
                self.world.reset()
                phone = FrontPhone(self.world)
                phone.case = f'E-PUSH-{number}'
                self.go_push(f'E-PUSH-{number}', phone=phone)
                self.assertEqual(phone.jobs[0]['screen'], screen)
                self.assertEqual(phone.jobs[0]['nickname'], PARTNER)


class NothingPopsUpTest(FrontBase):
    """14 · 20 · 29 · 30 · 53 · 82 — 앞에 있는 동안 알림이 0개여야 하고, 그 뒤 HOME 에서 대조 알림이 와야 믿는다."""

    def test_the_partner_acts_while_the_app_is_in_front_then_the_app_goes_home_for_the_control(self):
        self.go_front('14')
        self.assertLess(self.at('read')[0], self.at('POST cards/')[-1] if self.at('POST cards/') else 10 ** 6)
        self.assertLess(self.at('POST cards/')[-1], self.at('background')[0])  # 상대 행동 → 앞에서 지켜보기 → HOME → 대조
        self.assertLess(self.at('background')[0], self.at('POST chat/')[-1])
        self.assertEqual(self.world.log[-1], 'revoke')

    def test_a_notice_that_pops_up_in_front_is_a_fail_and_no_control_is_needed(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{PARTNER} 님이 대화를 하고 싶어 해요')])
        result = self.go_front('14')
        self.assertEqual(result[0], 'fail')
        self.assertIn('안 와야 할', result[1])
        self.assertEqual(self.callers_of('/messages'), [])

    def test_a_control_that_never_arrives_is_blocked_not_a_pass(self):
        self.world.rules.clear()  # 대조 알림이 안 뜬다
        self.assertEqual(self.go_front('14')[0], 'blocked')

    def test_the_screen_not_changing_is_a_fail(self):
        for number, key in (('14', 'row'), ('20', 'row'), ('29', 'body'), ('82', 'badge')):
            with self.subTest(number=number):
                self.world.reset()
                self.default_rules()
                result = self.go_front(number, shown={**OK, key: False})
                self.assertEqual(result[0], 'fail', (number, result))
                self.assertIn(key, result[1])

    def test_an_app_that_left_the_screen_is_a_fail(self):
        result = self.go_front('14', shown={**OK, 'front': False})
        self.assertEqual(result[0], 'fail')
        self.assertIn('앞', result[1])

    def test_53_needs_both_no_live_update_and_the_card_after_reentering(self):
        for key in ('absent', 'present'):
            with self.subTest(key=key):
                self.world.reset()
                self.default_rules()
                self.assertEqual(self.go_front('53', shown={**OK, key: False})[0], 'fail')

    def test_the_room_waits_past_the_server_window_before_the_partner_sends_in_30(self):
        self.go_front('30')
        self.assertTrue(any(s >= 31 for s in self.slept), self.slept)  # 입장 후 31초 넘게

    def test_the_partner_sends_at_once_in_29_without_waiting(self):
        self.go_front('29')
        self.assertFalse(any(s >= 31 for s in self.slept), self.slept)

    def test_the_message_the_app_must_find_is_the_one_the_partner_sent_in_29(self):
        phone = FrontPhone(self.world)
        phone.case = 'E-PUSH-29'
        self.go_push('E-PUSH-29', phone=phone)
        sent = [b['body'] for b in self.fake.bodies('POST', '/messages') if b['body'].startswith('E2E-front')]
        self.assertEqual(len(sent), 1)

    def test_who_acts(self):
        for number, piece, who in (('14', '/decision', ['tok-2']), ('20', '/cards/acceptances/', ['tok-2']), ('53', '/friend-reviews', ['tok-2'])):
            with self.subTest(number=number):
                self.world.reset()
                self.default_rules()
                self.go_front(number)
                self.assertEqual(self.callers_of(piece), who)


class ThirtyOneTest(FrontBase):
    """31 — 방에서 나와 HOME 한 지 30초 안에 온 메시지는 알림이 없고, 40초 뒤 것은 온다."""

    def test_first_message_ten_seconds_after_home_is_silent_and_the_one_at_forty_comes(self):
        self.second_message_only()
        result = self.go_front('31')
        self.assertEqual(result[0], 'pass', result)
        sends = self.fake.bodies('POST', '/messages')
        self.assertEqual(len(sends), 2)
        self.assertEqual(self.callers_of('/messages'), ['tok-2', 'tok-2'])
        first, rest = self.slept[0], self.slept[1]
        self.assertEqual(first, 10)  # HOME 뒤 10초에 첫 메시지
        self.assertEqual(first + area4_push_front.FIRST_WATCH + rest, 40)  # 첫 메시지 뒤 지켜본 시간까지 합쳐 HOME 뒤 40초에 두 번째

    def test_the_first_message_is_watched_for_the_full_time_and_the_second_is_waited_for_by_its_own_text(self):
        self.second_message_only()
        self.go_front('31')
        self.assertIn(('watch', area4_push_front.FIRST_WATCH), self.watched)
        self.assertIn(('wait', area4_push_front.SECOND_WAIT, True), self.watched)  # 아무 알림이 아니라 그 글(match)을 기다린다

    def test_another_notification_instead_of_the_second_message_is_a_fail(self):
        self.world.rules.clear()
        self.world.on('POST', '/messages', lambda b, u: [(CTL, '엉뚱한 알림')] if len(self.fake.bodies('POST', '/messages')) >= 1 else [])
        self.assertEqual(self.go_front('31')[0], 'fail')

    def test_the_control_must_be_the_message_that_was_sent_not_any_new_notification(self):
        self.world.rules.clear()
        self.world.on('POST', '/messages', lambda b, u: [(CTL, '엉뚱한 알림')])  # 대조 메시지 대신 다른 알림이 뜬다
        self.assertEqual(self.go_front('14')[0], 'blocked')

    def test_a_notification_for_the_first_message_is_a_fail(self):
        self.world.rules.clear()
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])])  # 첫 것도 두 번째도 뜬다
        result = self.go_front('31')
        self.assertEqual(result[0], 'fail')
        self.assertIn('첫', result[1])

    def test_no_notification_for_the_second_message_is_a_fail(self):
        self.world.rules.clear()  # 둘 다 안 뜬다 — 연결이 죽었을 수도 있다
        result = self.go_front('31')
        self.assertEqual(result[0], 'fail')
        self.assertIn('40초', result[1])

    def test_it_goes_home_right_after_the_app_left_the_room(self):
        self.second_message_only()
        self.go_front('31')
        self.assertLess(self.at('go')[-1] if self.at('go') else -1, self.at('background')[0] + 1)
        self.assertLess(self.at('background')[0], self.at('POST chat/')[0])


class WiringTest(FrontBase):
    def test_at_night_it_is_blocked_before_the_phone_is_called(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))):
            result = self.go_front('14')
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.phone.jobs, [])

    def test_the_push_connection_is_checked_before_the_app_starts(self):
        self.go_front('14')
        self.assertEqual(self.delivery, [('S', 0)])

    def test_a_missing_device_token_is_blocked_before_the_partner_acts(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        result = self.go_front('14')
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.fake.bodies('POST', '/decision'), [])

    def test_the_bundle_is_exactly_the_seven_cases(self):
        ids = [f'E-PUSH-{n}' for n in NUMBERS]
        self.assertEqual(sorted(area1.BUNDLES['area4-push-a3']), sorted(ids))
        for case in ids:
            self.assertIn(case, area1.PHONE)

    def test_the_slow_cases_get_a_longer_limit(self):
        for number in ('29', '30', '31'):
            self.assertGreater(tools.CASE_LIMITS[f'E-PUSH-{number}'], tools.CASE_LIMIT)

    def test_the_app_side_knows_the_same_seven_numbers(self):
        dart = (Path(__file__).resolve().parent.parent / 'frontend' / 'integration_test' / 'area4_push_front.dart').read_text(encoding='utf-8')
        listed = re.search(r"_pushFrontCases\s*=\s*\[([^\]]*)\]", dart)
        self.assertIsNotNone(listed)
        self.assertEqual(sorted(re.findall(r"'(\d+)'", listed.group(1))), sorted(NUMBERS))


if __name__ == '__main__':
    unittest.main()
