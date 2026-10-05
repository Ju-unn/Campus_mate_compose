"""영역 4 PUSH 카드 배치 9개(area4_push_card.py)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 알림창 · 가짜 배치 · 가짜 시계로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_card`.

바탕은 e2e/test_area2_time_device.py 의 [DeviceBase](열 이름까지 검사하는 가짜 서버 [World] + 알림창 + 배치 + 시계)다.
계정은 만든 순서대로 A(폰 계정, id-1) · B(상대, id-2) · 대조군(id-3), 토큰은 tok-1 · tok-2 …
"""

import re
import unittest
from unittest import mock

from e2e import area1, area2, area2_phone3, area2_time_batch as tb, area2_time_device as td, area4_push_card as pc, notify, tools
from e2e.test_area1_phone import OURS
from e2e.test_area2_time_device import CARD, MON, ROW, TUE, AppPhone, DeviceBase, World
from e2e.tools import Blocked, Reply

CASES = [f'E-PUSH-0{n}' for n in range(1, 10)]
DELEGATES = {'E-PUSH-01': td.p_card_01, 'E-PUSH-04': td.p_card_03, 'E-PUSH-05': td.p_card_18, 'E-PUSH-06': td.p_card_17}
OPENED = {'result': 'pass', 'today': True, 'cards': 1, 'today_ms': 4200, 'screen': ['home', 'today'], 'opened_at': '2026-10-06T03:00:07Z'}
LIVE = {'step': 'live'}
INSIDE = {'E-PUSH-06': TUE(22, 30)}  # 시각 창이 있는 가설 — 나머지는 화요일 낮이면 열려 있다


class CardPhone(AppPhone):
    """실제 [area1.Phone] 처럼 일감에 가설 번호를 싣고, 로그인 판 · 우편함(tell · result)을 [events] 줄에 남긴다."""

    def __init__(self, world, case, events, tapped=None, **kw):
        super().__init__(world, **kw)
        self.case, self.events, self.tapped = case, events, tapped
        self.hub.tell.side_effect = lambda job: events.append(f"tell:{job.get('phase')}")
        self.hub.result.side_effect = lambda timeout: events.append(f'result:{timeout}') or self.tapped

    def __call__(self, midway=None, **job):
        self.events.append(f"app:{job.get('phase')}")
        return super().__call__(midway, case=self.case, **job)


class CardBase(DeviceBase):
    """DeviceBase + 알림 누르기 · 앱 죽이기 · 다중 일치 기다리기."""

    def setUp(self):
        super().setUp()
        self.sticky = False  # 참이면 알림을 눌러도 알림창에서 안 사라진다
        for name, fake in (('tap_notification', self.tap), ('kill_app', self.kill)):
            patcher = mock.patch.object(notify, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        return super().wait_new(serial, before, count, seconds)

    def adb(self, serial, *args, check=True):
        if args[:3] == ('shell', 'dumpsys', 'activity'):
            return OURS  # 실제 Phone.top() 이 읽는 맨 위 화면 — 우리 앱
        return super().adb(serial, *args, check=check)

    def tap(self, serial, title):
        self.log.append(f'tap:{title}')
        if not self.sticky:  # 안드로이드는 누른 알림을 지운다
            self.world.shade[:] = [n for n in self.world.shade if n.title != title]

    def kill(self, serial):
        self.log.append('kill')

    def card_phone(self, case, **kw):
        return CardPhone(self.world, case, self.log, **kw)

    def pauses(self, owner):
        """[owner] 의 matching_paused 를 바꾼 PATCH 들의 값 — 차례대로."""
        return [s['body']['matching_paused'] for s in self.world.by('PATCH', '/rest/v1/profiles')
                if s['query'].get('id') == f'eq.{owner}' and 'matching_paused' in s['body']]

    def region_row(self):
        return self.world.tables['region_group_settings'][0]


# ── 시각 관문 ───────────────────────────────────────────────────────────────────────────────────────

class GateTest(CardBase):
    DAILY = {MON(12): '지금은 실행 금지 시간 — 화요일 07:11 에 다시', TUE(3, 0): '지금은 실행 금지 시간 — 07:11 에 다시',
             TUE(7, 10): '지금은 실행 금지 시간 — 07:11 에 다시'}
    NIGHT = {MON(12): '지금은 실행 금지 시간 — 화요일 22:00 에 다시', MON(22, 30): '지금은 실행 금지 시간 — 화요일 22:00 에 다시',
             TUE(3, 0): '지금은 실행 금지 시간 — 22:00 에 다시', TUE(12): '지금은 실행 금지 시간 — 22:00 에 다시',
             TUE(21, 59): '지금은 실행 금지 시간 — 22:00 에 다시'}

    def test_all_nine_are_refused_before_any_account_app_permission_or_batch_on_a_monday_or_through_0710(self):
        for case in CASES:
            for now, said in (self.NIGHT if case == 'E-PUSH-06' else self.DAILY).items():
                with self.subTest(case=case, now=now):
                    self.reset()
                    self.world.users.clear()
                    self.clock.now = now
                    phone = self.card_phone(case, serial='emulator-5554')
                    self.assertEqual(self.go(case, phone), ('blocked', said))
                    self.assertEqual((self.world.users, phone.jobs, self.batches, self.log), ([], [], [], []))  # 계정 · 앱 · 권한 · 배치 0

    def test_the_night_case_runs_inside_2200_to_2359_and_the_others_run_on_a_tuesday_noon(self):
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')
        self.assertEqual(self.go('E-PUSH-01', self.card_phone('E-PUSH-01'))[0], 'pass')
        self.reset()
        self.world = World()
        self.world.permitted = lambda: self.granted
        self.clock.now = TUE(22, 30)
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')
        with mock.patch.object(tools, 'call', self.world):
            self.assertEqual(self.go('E-PUSH-06', self.card_phone('E-PUSH-06'))[0], 'pass')


# ── 기존 가설에 맡기는 4개 ───────────────────────────────────────────────────────────────────────────

class DelegateTest(CardBase):
    def real_phone(self, case, step=None):
        """진짜 [area1.Phone] — Run.phone 만 가짜 앱으로 바꿔 끼워 일감에 실제로 어떤 번호가 실리는지 본다."""
        app = AppPhone(self.world, midway_step=step or {'step': 'x'})
        self.app = app
        patcher = mock.patch.object(self.run, 'phone', lambda hub, serial, job, timeout=180, midway=None: app(midway, **job))
        patcher.start()
        self.addCleanup(patcher.stop)
        return area1.Phone(self.run, mock.Mock(), 'S', case)

    def test_each_delegate_is_the_existing_case_function_itself(self):
        for number, function in DELEGATES.items():
            self.assertIs(pc.PHONE[number], function, number)

    def test_the_jobs_the_phone_gets_carry_the_push_number_not_the_card_number(self):
        for number, scripts, kw in (
            ('E-PUSH-01', self.issue_to('id-1', 'id-3'), {}),
            ('E-PUSH-04', self.issue_to('id-1', notice=False), {'step': LIVE}),
            ('E-PUSH-05', self.issue_to('id-1', notice=False), {}),
        ):
            with self.subTest(case=number):
                self.reset()
                self.world = World()
                self.world.permitted = lambda: self.granted
                self.scripts['daily-cards'] = scripts
                with mock.patch.object(tools, 'call', self.world):
                    result = self.go(number, self.real_phone(number, **kw))
                    self.assertEqual(result[0], 'pass', (number, result))
                    self.assertTrue(self.app.jobs and all(job['case'] == number for job in self.app.jobs), (number, self.app.jobs))

    def test_the_night_delegate_also_carries_its_own_number(self):
        self.clock.now = TUE(22, 30)
        self.scripts['daily-cards'] = self.issue_to('id-1')
        result = self.go('E-PUSH-06', self.real_phone('E-PUSH-06'))
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual([job['case'] for job in self.app.jobs], ['E-PUSH-06'])
        self.assertEqual(self.world.by('PATCH', '/cards/notification-settings'), [])  # 방해 금지는 기본값(켬) 그대로 — 예외를 본다

    def test_a_delegate_judges_exactly_like_the_original(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.post(CARD[0], '다른 본문'))
        self.assertEqual(self.go('E-PUSH-01', self.card_phone('E-PUSH-01'))[0], 'fail')
        self.reset()
        self.world = World()
        self.world.permitted = lambda: self.granted
        self.scripts['daily-cards'] = self.issue_to('id-1')  # 알림을 껐는데 알림이 오는 05
        with mock.patch.object(tools, 'call', self.world):
            self.assertEqual(self.go('E-PUSH-05', self.card_phone('E-PUSH-05'))[0], 'fail')

    def test_the_app_wait_of_the_front_screen_case_is_shorter_than_its_limit(self):
        self.assertGreater(tools.CASE_LIMITS['E-PUSH-04'], 600)  # td.p_card_03 이 앱을 최대 600초 기다린다


# ── E-PUSH-02 눌러서 열기 + 알림이 사라짐 ───────────────────────────────────────────────────────────

class Push02Test(CardBase):
    CASE = 'E-PUSH-02'

    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1')

    def phone_02(self):
        return self.phone(midway_step={'step': 'background'})

    def test_the_card_notice_is_gone_from_the_list_after_the_tap_and_the_case_passes(self):
        result = self.go(self.CASE, self.phone_02())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.world.tables['daily_cards']), 1)

    def test_the_list_is_read_after_the_tap_and_before_the_permission_is_taken_away(self):
        self.go(self.CASE, self.phone_02())
        # 권한을 빼면 이미 뜬 알림이 지워질 수 있다 — 지워진 뒤에 읽으면 거짓 통과
        self.assertEqual(self.log, ['grant', 'read', 'home', 'batch:daily-cards', f'tap:{CARD[0]}', 'read', 'revoke'])

    def test_a_notice_that_stays_after_the_tap_is_a_fail(self):
        self.sticky = True
        result = self.go(self.CASE, self.phone_02())
        self.assertEqual(result[0], 'fail')
        self.assertIn('알림 목록', result[1])

    def test_an_older_notice_with_the_same_words_is_not_blamed_on_this_runs_tap(self):
        self.world.post(*CARD)  # 앞 실행이 남긴 같은 글의 알림 — 이번 알림만 본다
        old = list(self.world.shade)

        def tap_only_this_one(serial, title):
            self.log.append(f'tap:{title}')
            self.world.shade[:] = [n for n in self.world.shade if n in old]  # 이번에 온 것만 사라진다

        with mock.patch.object(notify, 'tap_notification', tap_only_this_one):
            result = self.go(self.CASE, self.phone_02())
        self.assertEqual(result[0], 'pass', result)

    def test_no_notice_means_no_tap_and_no_list_read_afterwards(self):
        self.scripts['daily-cards'] = lambda: self.world.give_card('id-1')
        result = self.go(self.CASE, self.phone_02())
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.log, ['grant', 'read', 'home', 'batch:daily-cards', 'revoke'])

    def test_the_original_e2e_card_02_is_the_same_function_and_still_has_no_hook(self):
        self.assertIs(area1.PHONE['E-CARD-02'], area2_phone3.p_card_02)
        result = self.go('E-CARD-02', self.phone_02())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.log.count('read'), 1)  # 훅이 없으면 누른 뒤에 알림창을 다시 읽지 않는다

    def test_the_permission_is_taken_away_even_when_the_tap_blocks(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            self.assertEqual(self.go(self.CASE, self.phone_02())[0], 'blocked')
        self.assertEqual(self.log[-1], 'revoke')


# ── E-PUSH-03 꺼진 앱에서 눌러 오늘 탭 ──────────────────────────────────────────────────────────────

class Push03Test(CardBase):
    CASE = 'E-PUSH-03'
    LOG = ['grant', 'app:login', 'read', 'kill', 'batch:daily-cards', 'tell:tap', f'tap:{CARD[0]}', 'result:90', 'revoke']

    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')

    def go_03(self, tapped=OPENED, **kw):
        phone = self.card_phone(self.CASE, tapped=tapped, **kw)
        return self.go(self.CASE, phone), phone

    def again(self, **kw):
        """같은 시험 안에서 한 번 더 — 세계 · 로그 · 배치를 처음부터."""
        self.reset()
        self.world = World()
        self.world.permitted = lambda: self.granted
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')
        with mock.patch.object(tools, 'call', self.world):
            return self.go_03(**kw)

    def test_login_then_kill_then_batch_then_the_tap_job_is_posted_before_the_notice_is_tapped(self):
        (result, note), phone = self.go_03()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.log, self.LOG)  # tap 일감이 우편함에 먼저 — 알림 누름으로 켜진 앱이 가져간다
        phone.hub.tell.assert_called_once_with({'case': self.CASE, 'phase': 'tap'})
        self.assertEqual(phone.jobs[0]['phase'], 'login')
        self.assertEqual(phone.jobs[0]['case'], self.CASE)
        self.assertEqual(phone.jobs[0]['token_hash'], 'h-' + self.world.users[0]['email'])

    def test_the_memo_keeps_the_ms_the_app_said_and_stays_a_pass_up_to_30_seconds(self):
        (result, note), _ = self.go_03(tapped={**OPENED, 'today_ms': 4200})
        self.assertEqual(result, 'pass')
        self.assertIn('4200ms', note)
        self.assertNotIn('확인 필요', note)
        (result, note), _ = self.again(tapped={**OPENED, 'today_ms': 29000})  # 앱이 30초 안에 열었다
        self.assertEqual(result, 'pass')

    def test_over_10_seconds_is_a_pass_with_a_warning_in_the_memo(self):
        (result, note), _ = self.go_03(tapped={**OPENED, 'today_ms': 12000})
        self.assertEqual(result, 'pass', note)
        self.assertIn('확인 필요', note)
        self.assertIn('10초', note)

    def test_the_today_tab_that_did_not_open_is_a_fail_and_the_note_names_the_screens_seen(self):
        (result, note), _ = self.go_03(tapped={**OPENED, 'today': False, 'cards': 0, 'screen': ['consent']})
        self.assertEqual(result, 'fail')
        self.assertIn('약관 동의', note)  # A10 회귀 — 약관으로 튕김
        self.assertIn('오늘 탭', note)

    def test_the_app_that_landed_on_home_instead_names_home(self):
        (result, note), _ = self.go_03(tapped={**OPENED, 'today': False, 'cards': 0, 'screen': ['home']})
        self.assertEqual(result, 'fail')
        self.assertIn('홈', note)

    def test_other_than_one_card_is_a_fail(self):
        for cards in (0, 2):
            with self.subTest(cards=cards):
                (result, note), _ = self.again(tapped={**OPENED, 'cards': cards})
                self.assertEqual(result, 'fail', note)
                self.assertIn(f'{cards}장', note)

    def test_an_app_that_never_answers_after_the_tap_is_a_fail(self):
        (result, note), _ = self.go_03(tapped=None)
        self.assertEqual(result, 'fail')
        self.assertIn('시간 안에 답하지 않음', note)

    def test_an_app_that_says_blocked_makes_the_case_blocked(self):
        (result, note), _ = self.go_03(tapped={'result': 'blocked', 'note': '준비가 틀림'})
        self.assertEqual(result, 'blocked')

    def test_no_notice_is_a_fail_and_nothing_is_tapped_or_posted(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.give_card('id-3'))
        (result, note), phone = self.go_03()
        self.assertEqual(result, 'fail')
        self.assertNotIn('tell:tap', self.log)
        self.assertFalse([e for e in self.log if e.startswith('tap:')])
        phone.hub.tell.assert_not_called()

    def test_two_card_notices_are_a_fail_and_nothing_is_tapped(self):
        self.scripts['daily-cards'] = lambda: (self.issue_to('id-1', 'id-3')(), self.world.post(*CARD))
        (result, note), _ = self.go_03()
        self.assertEqual(result, 'fail')
        self.assertIn('2건', note)
        self.assertFalse([e for e in self.log if e.startswith('tap:')])

    def test_no_card_at_all_is_blocked_because_a_slow_batch_looks_the_same(self):
        self.scripts['daily-cards'] = lambda: None
        (result, note), _ = self.go_03()
        self.assertEqual(result, 'blocked')
        self.assertIn('느린 배치인지 결함인지 구분 못 함', note)
        self.assertNotIn('tell:tap', self.log)

    def test_a_control_that_got_a_card_while_the_target_did_not_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: self.world.give_card('id-3')
        (result, note), _ = self.go_03()
        self.assertEqual(result, 'fail')
        self.assertIn(td.CONTROL_MISSED, note)

    def test_a_login_that_never_reached_home_stops_before_the_app_is_killed(self):
        phone = self.card_phone(self.CASE, tapped=OPENED)
        phone.answers = [{'result': 'fail', 'note': '홈에 못 닿음'}]
        result = self.go(self.CASE, phone)
        self.assertEqual(result[0], 'fail')
        self.assertNotIn('kill', self.log)
        self.assertEqual(self.batches, [])

    def test_no_device_token_is_blocked_before_the_app_is_killed_and_before_the_batch(self):
        result = self.go(self.CASE, self.card_phone(self.CASE, tapped=OPENED, push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertNotIn('kill', self.log)
        self.assertEqual(self.batches, [])
        self.assertEqual(self.log[-1], 'revoke')

    def test_the_permission_and_the_region_row_are_put_back_when_the_tap_cannot_find_the_notice(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            (result, _), _ = self.go_03()
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.log[-1], 'revoke')
        patches = [s['body'] for s in self.world.by('PATCH', '/rest/v1/region_group_settings')]
        self.assertEqual(patches[-1], {k: ROW[k] for k in patches[0]})
        self.assertEqual(patches[0]['issue_weekdays'], [1, 2, 3, 4, 5, 6, 7])


# ── E-PUSH-07 일시중지 ──────────────────────────────────────────────────────────────────────────────

class Push07Test(CardBase):
    CASE = 'E-PUSH-07'

    def setUp(self):
        super().setUp()
        carded = set()

        def issue():
            """후보가 있는 사람만 — 일시중지한 A(id-1)는 못 받는다. 대조군(id-3)은 늘 받는다. 하루에 한 번."""
            for owner in ('id-1', 'id-3'):
                if owner in carded or (owner == 'id-1' and self.paused()):
                    continue
                carded.add(owner)
                self.world.give_card(owner)
                if owner == 'id-1' and self.granted:
                    self.world.post(*CARD)

        self.scripts['daily-cards'] = issue

    def paused(self):
        values = self.pauses('id-1')
        return bool(values and values[-1])

    def test_paused_a_gets_no_card_and_no_notice_then_after_resuming_one_card_and_one_notice(self):
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.pauses('id-1'), [True, False])
        self.assertEqual(self.batches, ['daily-cards', 'daily-cards'])
        self.assertEqual([c['owner_id'] for c in self.world.tables['daily_cards']], ['id-3', 'id-1'])  # 1회 대조군만, 2회 A
        self.assertEqual(len(self.world.shade), 1)
        self.assertIn(('none', td.ABSENCE_WAIT), self.windows)

    def test_the_log_order_is_login_home_pause_batch_resume_batch(self):
        self.go(self.CASE, self.phone())
        self.assertEqual(self.log, ['grant', 'read', 'home', 'batch:daily-cards', 'batch:daily-cards', 'revoke'])

    def test_only_this_runs_phone_account_is_ever_paused(self):
        self.go(self.CASE, self.phone())
        patched = {s['query']['id'] for s in self.world.by('PATCH', '/rest/v1/profiles') if 'matching_paused' in s['body']}
        self.assertEqual(patched, {'eq.id-1'})

    def test_a_paused_account_that_still_gets_a_card_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: [self.world.give_card(o) for o in ('id-1', 'id-3')]
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('일시중지한 A 가 카드를 받음', result[1])

    def test_a_paused_account_that_gets_a_notice_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-3'), self.world.post(*CARD))
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'fail')

    def test_a_control_without_a_card_means_the_batch_did_not_run_so_blocked_and_the_pause_is_lifted(self):
        self.scripts['daily-cards'] = lambda: None
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, ['daily-cards'])
        self.assertEqual(self.pauses('id-1'), [True, False])

    def test_the_pause_is_lifted_even_when_the_batch_call_fails(self):
        def broken():
            raise Blocked('배치 호출 실패')

        self.scripts['daily-cards'] = broken
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'blocked')
        self.assertEqual(self.pauses('id-1'), [True, False])

    def test_after_resuming_no_card_is_a_fail_because_the_control_proved_the_batch_ran(self):
        self.scripts['daily-cards'] = lambda: self.world.give_card('id-3') if not self.world.tables.get('daily_cards') else None
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.batches, ['daily-cards', 'daily-cards'])

    def test_after_resuming_a_card_without_a_notice_is_a_fail(self):
        calls = []

        def issue():
            calls.append(1)
            self.world.give_card('id-3' if len(calls) == 1 else 'id-1')

        self.scripts['daily-cards'] = issue
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'fail')

    def test_no_device_token_is_blocked_before_anyone_is_paused(self):
        result = self.go(self.CASE, self.phone(push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual((self.pauses('id-1'), self.batches), ([], []))


# ── E-PUSH-08 같은 날 두 번 ─────────────────────────────────────────────────────────────────────────

class Push08Test(CardBase):
    CASE = 'E-PUSH-08'

    def setUp(self):
        super().setUp()
        self.seen_at_second = []
        self.second = lambda: None  # 두 번째 배치가 하는 일(기본: 설정 행을 새로 적고 아무것도 안 준다)

        def first():
            self.issue_to('id-1', 'id-3')()

        def rewrite():
            self.seen_at_second.append(list(self.region_row()['issue_weekdays']))
            if self.region_row()['issue_weekdays'] == tb.SENTINEL:  # 사다리가 못 내는 값을 배치가 새로 적는다 = 돌았다는 증거
                self.region_row()['issue_weekdays'] = [1, 2, 3, 4, 5, 6, 7]
            self.second()

        calls = []

        def batch():
            calls.append(1)
            first() if len(calls) == 1 else rewrite()

        self.scripts['daily-cards'] = batch

    def test_two_batches_one_card_one_notice_and_the_sentinel_was_planted_before_the_second(self):
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['daily-cards', 'daily-cards'])
        self.assertEqual(self.seen_at_second, [tb.SENTINEL])  # 두 번째 배치가 돌 때 행에는 증거 심기가 들어 있었다
        self.assertEqual(len(self.world.live_cards('id-1')), 1)
        self.assertEqual(len(self.world.live_cards('id-3')), 1)
        self.assertEqual(len(self.world.shade), 1)

    def test_the_second_batch_without_the_proof_is_blocked_not_a_pass_of_nothing_happened(self):
        self.scripts['daily-cards'] = lambda: self.issue_to('id-1', 'id-3')() if len(self.batches) == 1 else None  # 행을 안 고치는 배치
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertIn('안 돌았', result[1])

    def test_the_region_row_is_put_back_to_the_original_after_the_proof_and_after_the_blocked_case(self):
        self.go(self.CASE, self.phone())
        self.assertEqual(self.region_row()['issue_weekdays'], ROW['issue_weekdays'])
        self.assertEqual(self.region_row()['ladder_daily_min'], ROW['ladder_daily_min'])

    def test_a_second_card_for_a_is_a_fail(self):
        self.second = lambda: self.world.give_card('id-1', target='id-8')
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('2장', result[1])

    def test_a_second_notice_is_a_fail(self):
        self.second = lambda: self.world.post(*CARD)
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')

    def test_a_second_card_for_the_control_is_a_fail_too(self):
        self.second = lambda: self.world.give_card('id-3', target='id-8')
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('대조군', result[1])

    def test_no_card_after_the_first_batch_is_blocked_and_no_second_batch_is_called(self):
        self.scripts['daily-cards'] = lambda: None
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, ['daily-cards'])

    def test_no_device_token_is_blocked_before_any_batch(self):
        result = self.go(self.CASE, self.phone(push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_the_watch_after_the_second_batch_is_the_absence_time(self):
        self.go(self.CASE, self.phone())
        self.assertIn(('none', td.ABSENCE_WAIT), self.windows)


# ── E-PUSH-09 후보 0명 ──────────────────────────────────────────────────────────────────────────────

class Push09Test(CardBase):
    CASE = 'E-PUSH-09'

    def setUp(self):
        super().setUp()

        def batch():
            for owner in ('id-1', 'id-3'):  # 후보가 있는 사람만 카드를 받는다
                if self.world.candidates_of(owner):
                    self.world.give_card(owner)
                    if owner == 'id-1' and self.granted:
                        self.world.post(*CARD)

        self.scripts['daily-cards'] = batch

    def test_with_no_candidates_a_gets_no_card_and_no_notice_and_the_control_got_one(self):
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['daily-cards'])
        self.assertEqual((self.world.live_cards('id-1'), len(self.world.live_cards('id-3'))), ([], 1))
        self.assertEqual(self.world.shade, [])
        self.assertIn(('none', td.ABSENCE_WAIT), self.windows)
        self.assertIn('no_candidate', result[1])  # 응답 수치는 스케줄러 호출이라 못 읽는다는 메모

    def test_the_log_order_is_login_home_rest_the_pool_batch(self):
        self.go(self.CASE, self.phone())
        self.assertEqual(self.log, ['grant', 'read', 'home', 'batch:daily-cards', 'revoke'])

    def test_writes_are_only_expired_cards_owned_by_a(self):
        self.go(self.CASE, self.phone())
        rows = self.world.by('POST', '/rest/v1/daily_cards')[0]['body']
        self.assertEqual({r['owner_id'] for r in rows}, {'id-1'})
        now = area2._now()
        for row in rows:
            self.assertLess(area1._at(row['expires_at']), now)

    def test_a_live_card_for_a_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.give_card('id-3'))
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'fail')

    def test_a_notice_for_a_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-3'), self.world.post(*CARD))
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'fail')

    def test_a_control_without_a_card_is_blocked_because_the_batch_may_not_have_run(self):
        self.scripts['daily-cards'] = lambda: None
        self.assertEqual(self.go(self.CASE, self.phone())[0], 'blocked')

    def test_a_pool_that_cannot_be_emptied_is_blocked_before_the_batch(self):
        self.world.ignore_rest = True
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_a_today_screen_that_does_not_say_the_pool_is_empty_is_a_fail(self):
        self.world.handlers.insert(0, ('GET', re.compile(r'/cards/today'), Reply(200, {'cards': [], 'candidate_pool_empty': False})))
        result = self.go(self.CASE, self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('/cards/today', result[1])

    def test_no_device_token_is_blocked_before_the_batch(self):
        result = self.go(self.CASE, self.phone(push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_the_helper_that_rests_the_pool_is_shared_with_e2e_card_13(self):
        self.assertTrue(callable(td._rest_pool))  # p_card_13 도 이 함수를 쓴다(동작은 Card13Test 가 그대로 본다)
        import inspect
        self.assertIn('_rest_pool(', inspect.getsource(td.p_card_13))


# ── 안전망 ──────────────────────────────────────────────────────────────────────────────────────────

class DeliveryTest(CardBase):
    """푸시 연결 점검(notify.ensure_delivery)은 새로 만든 가설 02 · 03 · 07 · 08 · 09 도 시작에서 — 계정을 만들기 전에, 죽은 연결이면 blocked.
    (01 · 04 · 05 · 06 은 기존 가설에 맡기며 그쪽이 이미 점검한다.)"""
    OWN = ['E-PUSH-02', 'E-PUSH-03', 'E-PUSH-07', 'E-PUSH-08', 'E-PUSH-09']

    def test_a_dead_push_link_blocks_before_any_account_app_or_batch(self):
        for case in self.OWN:
            with self.subTest(case=case):
                self.reset()
                self.world.users.clear()
                self.prepare_error = Blocked('GCM 연결 횟수를 못 읽음 — 푸시 연결을 점검할 수 없음')
                phone = self.card_phone(case)
                result = self.go(case, phone)
                self.assertEqual(result[0], 'blocked', (case, result))
                self.assertIn('푸시 연결', result[1])
                self.assertEqual((self.world.users, phone.jobs, self.batches), ([], [], []))

    def test_the_check_runs_once_per_case_on_the_phone_with_no_account_yet(self):
        for case in self.OWN:
            with self.subTest(case=case):
                self.reset()
                self.world.users.clear()
                self.scripts['daily-cards'] = lambda: None
                self.go(case, self.card_phone(case))
                self.assertEqual(self.prepared, [('S', 0)], case)


class SafetyNetTest(CardBase):
    def test_every_case_ends_blocked_or_fail_when_the_server_is_down(self):
        down = World()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down):
            for case in CASES:
                self.clock.now = INSIDE.get(case, TUE(12))
                result = area1.attempt_phone(self.run, case, self.card_phone(case, tapped=OPENED, serial='emulator-5554'))
                self.assertIn(result[0], ('blocked', 'fail'), case)
                self.assertIsInstance(result[1], str, case)

    def test_every_write_in_every_case_stays_inside_this_runs_accounts_the_test_school_and_the_test_region(self):
        allowed = {'region_group_settings': ('region_group', 'e2e'), 'universities': ('id', 'U')}
        for case in CASES:
            world = World()
            self.reset()
            self.world = world
            self.clock.now = INSIDE.get(case, TUE(12))
            self.scripts['daily-cards'] = self.issue_to('id-1', 'id-2', 'id-3')
            phone = self.card_phone(case, tapped=OPENED, top=OURS, midway_step={'step': 'background' if case == 'E-PUSH-02' else 'live'})
            with mock.patch.object(tools, 'call', world):
                self.go(case, phone)
            made = {u['id'] for u in world.users}
            self.assertTrue(made, case)
            for sent in world.sent:
                if sent['method'] not in ('POST', 'PATCH', 'DELETE') or not sent['path'].startswith('/rest/v1/'):
                    continue
                table = sent['path'].split('/')[-1]
                if table in allowed:
                    key, value = allowed[table]
                    self.assertEqual(sent['query'].get(key), f'eq.{value}', (case, sent))
                elif table in ('daily_cards', 'profiles', 'pending_pushes', 'push_tokens'):
                    rows = sent['body'] if isinstance(sent['body'], list) else [sent['body']]
                    owners = {r['owner_id'] for r in rows if isinstance(r, dict) and 'owner_id' in r}
                    owners |= {sent['query'][k][3:] for k in ('owner_id', 'id', 'profile_id') if k in sent['query']}
                    self.assertTrue(owners and owners <= made, (case, sent))


# ── 등록부 ──────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundle_is_the_nine_push_card_cases_in_order_and_each_is_a_phone_case(self):
        self.assertEqual(area1.BUNDLES['area4-push-card'], CASES)
        self.assertEqual(list(pc.PHONE), CASES)
        for case in CASES:
            self.assertIs(area1.PHONE[case], pc.PHONE[case], case)

    def test_none_of_the_nine_is_in_another_push_bundle_and_none_is_an_api_case(self):
        from e2e import __main__ as main
        for name in ('area4-push-a1', 'area4-push-a4'):
            self.assertFalse(set(CASES) & set(area1.BUNDLES[name]), name)
        self.assertFalse(set(CASES) & set(main.API_CASES))
        self.assertEqual(main.BUNDLES['area4-push-card'], CASES)

    def test_main_imports_the_module(self):
        self.assertRegex((tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'), r'(?m)^from e2e import area4_push_card\b')

    def test_the_slow_cases_get_a_longer_limit_than_the_default(self):
        for case in ('E-PUSH-02', 'E-PUSH-03', 'E-PUSH-04', 'E-PUSH-07', 'E-PUSH-08', 'E-PUSH-09'):
            self.assertGreater(tools.CASE_LIMITS[case], tools.CASE_LIMIT, case)
            self.assertGreater(tools.CASE_LIMITS[case], td.APP_WAIT - 1, case)  # 앱이 PC 일을 기다리는 가장 긴 시간(900)보다 작지 않다

    def test_the_docstring_lists_what_runs_differently_from_the_scenario(self):
        self.assertIn('시나리오와 다르게 도는 것', pc.__doc__)

    def test_the_app_part_is_declared_in_area4_and_its_cases_are_merged(self):
        part = self.dart('area4_push_card.dart')
        self.assertTrue(part.startswith("part of 'area4.dart';"))
        main = self.dart('area4.dart')
        self.assertIn("part 'area4_push_card.dart';", main)
        self.assertIn('..._pushCardCases,', main)

    def test_the_app_knows_all_nine_numbers_between_the_part_and_e2e_test_dart(self):
        part, e2e = self.dart('area4_push_card.dart'), self.dart('e2e_test.dart')
        for case in CASES:
            self.assertRegex(part + e2e, rf"(?m)^\s*'{case}':", case)
        self.assertRegex(e2e, r"'E-PUSH-02': area2cCases\['E-CARD-02'\]!")  # 02 · 04 는 이미 있는 앱 가설 별칭 — 라이브러리가 e2e_test 에서만 같이 보인다
        self.assertRegex(e2e, r"'E-PUSH-04': area2dCases\['E-CARD-03'\]!")
        for case in ('E-PUSH-01', 'E-PUSH-05', 'E-PUSH-06', 'E-PUSH-07', 'E-PUSH-08', 'E-PUSH-09'):
            self.assertRegex(part, rf"'{case}': area1Cases\['E-ONB-61'\]!")  # 알림만 보는 가설은 홈까지 켜 두는 앱

    def test_the_app_reads_the_phases_the_pc_sends_and_the_pc_reads_the_keys_the_app_says(self):
        part = self.dart('area4_push_card.dart')
        for phase in ('login', 'tap'):
            self.assertIn(f"'{phase}' =>", part)
        self.assertIn("job['phase']", part)
        for key in pc.APP_KEYS:  # PC 가 읽는 앱 말
            self.assertIn(f"'{key}':", part, key)
        self.assertNotIn("_session(_cardOpened", part)  # tap 판은 새 로그인을 하지 않는다 — 앞 판의 세션을 쓴다

    def test_screen_names_the_app_can_say_are_exactly_the_labels_the_pc_knows(self):
        part = self.dart('area4_push_card.dart')
        listed = re.search(r"in const \[([^\]]*)\]", part).group(1)
        named = set(re.findall(r"'([\w-]+)'", listed)) | set(re.findall(r"^\s*'([\w-]+)': find\.", part, re.M))
        self.assertEqual(named, set(pc.SCREEN_LABELS))
        screens = self.dart('area1.dart')
        for name in named - {'home', 'today'}:  # 나머지는 area1.dart screens 표의 키여야 screen(name) 이 찾는다
            self.assertRegex(screens, rf"(?m)^  '{re.escape(name)}':", name)


if __name__ == '__main__':
    unittest.main()
