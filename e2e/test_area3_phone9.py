"""영역 3 지인 리뷰 알림 4개(E-REV-16 · 17 · 26 · 41)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 HTTP · 가짜 알림창 · 가짜 앱.
저장소 루트에서 `python -m unittest e2e.test_area3_phone9`.

단일 폰(16 · 17 · 26)은 영역 4 알림 시험의 가짜 알림창(test_area4_push.World)과 가짜 앱(test_area4_push_tap.TapPhone)을 그대로 쓴다.
두 기기(41)는 [ThreadTwo] — 두 쪽 차례를 스레드 둘에서 진짜 twodev.Sync 로 돌려, 서로 기다리는 핸들러가 실제로 풀리는지 본다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 …(16 · 26 은 폰 계정 Mina 가 먼저, 상대 Jiho 가 둘째).
"""

import re
import threading
import unittest
from datetime import datetime
from unittest import mock

from e2e import area1, area3, area3_phone9, batch_gate, notify, tools, twodev
from e2e.area1 import SEOUL
from e2e.test_area4_push import PARTNER, REVIEW, WorldFake
from e2e.test_area4_push_tap import FOUND, TapBase, TapPhone
from e2e.tools import Blocked, Reply

FRIEND = '친구가 가입했어요'
SINGLE = ['E-REV-16', 'E-REV-17', 'E-REV-26']
REVIEW_BODY = f'{PARTNER} 님이 리뷰를 남겼어요'
NOON = datetime(2026, 10, 7, 12, 0, tzinfo=SEOUL)


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


# ── E-REV-16 남기면 알림 1건 · 누르면 받은 리뷰 ──────────────────────────────────────────────────────────

class Rev16Test(TapBase):
    def go16(self, shown=None, notices=1):
        if notices:
            self.world.on('POST', '/friend-reviews', lambda b, u: [(REVIEW, REVIEW_BODY)] * notices)
        phone = TapPhone(self.world, shown)
        phone.case = 'E-REV-16'
        return self.go_push('E-REV-16', phone=phone), phone

    def test_one_notice_then_a_tap_opens_the_received_list_with_the_writer(self):
        result, phone = self.go16()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.jobs[0]['phase'], 'hold')
        self.assertEqual((phone.jobs[0]['dest'], phone.jobs[0]['nickname']), ('reviews', PARTNER))
        self.assertEqual(self.at(f'tap:{REVIEW}'), [self.at('tap:')[0]])
        self.assertEqual(self.tap_bodies, [REVIEW_BODY])  # 같은 제목의 옛 알림이 아닌 이 알림을 누른다

    def test_the_partner_writes_after_the_phone_went_to_the_back_and_the_tap_comes_after(self):
        self.go16()
        self.assertLess(self.at('background')[0], self.at('POST friend-reviews')[0])
        self.assertLess(self.at('POST friend-reviews')[0], self.at('tap:')[0])
        self.assertEqual([who for m, p, who in self.world.callers if p == '/friend-reviews'], ['tok-2'])  # 상대가 쓴다

    def test_two_copies_of_the_notice_is_a_fail(self):
        result, _ = self.go16(notices=2)
        self.assertEqual(result[0], 'fail')
        self.assertIn('2개', result[1])

    def test_no_notice_is_a_fail_and_nothing_is_tapped(self):
        result, _ = self.go16(notices=0)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.at('tap:'), [])

    def test_a_list_that_never_opens_or_lacks_the_writer_is_a_fail(self):
        for shown in ({**FOUND, 'dest': False, 'who': False, 'screen': ['home']}, {**FOUND, 'who': False}):
            with self.subTest(shown=shown):
                self.world.reset()
                self.assertEqual(self.go16(shown=shown)[0][0], 'fail')

    def test_a_missing_device_token_is_blocked_before_the_review_is_written(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        result, _ = self.go16()
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.fake.bodies('POST', '/friend-reviews'), [])

    def test_at_night_it_is_blocked_before_the_phone_is_called(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=notify.Blocked('밤'))):
            result, phone = self.go16()
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(phone.jobs, [])


# ── E-REV-17 스위치 끔 = E-PUSH-51 ──────────────────────────────────────────────────────────────────

class Rev17Test(TapBase):
    RULES = [('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r1'})), ('GET', 'friend_reviews', lambda b, u: Reply(200, [{'id': 'r1'}]))]

    def test_it_runs_the_switch_off_case_once_and_writes_both_numbers(self):
        self.control_arrives()
        result = self.go_push('E-REV-17', self.RULES)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'new_friend_review': False}])
        lines = [r for r in self.run.records() if r['case'] == 'E-PUSH-51']
        self.assertEqual([r['result'] for r in lines], ['pass'])
        self.assertTrue(lines[0]['note'].startswith('E-REV-17 로 돌린'))

    def test_a_notice_with_the_switch_off_is_a_fail_in_both_numbers(self):
        self.world.on('POST', '/friend-reviews', lambda b, u: [(REVIEW, REVIEW_BODY)])
        result = self.go_push('E-REV-17', self.RULES)
        self.assertEqual(result[0], 'fail')
        self.assertEqual([r['result'] for r in self.run.records() if r['case'] == 'E-PUSH-51'], ['fail'])

    def test_it_borrows_the_originals_time_limit(self):
        self.assertEqual(tools.CASE_LIMITS['E-REV-17'], tools.CASE_LIMITS['E-PUSH-51'])


# ── E-REV-26 지워도 알림 0건 ────────────────────────────────────────────────────────────────────────

class Rev26Test(TapBase):
    def go26(self, written=True, delete=204, left=(), on_delete=()):
        if written:
            self.world.on('POST', '/friend-reviews', lambda b, u: [(REVIEW, REVIEW_BODY)])
        self.world.on('DELETE', '/friend-reviews/', lambda b, u: list(on_delete))
        rules = [('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r1'})),
                 ('DELETE', '/friend-reviews/r1', lambda b, u: Reply(delete, None if delete == 204 else {'detail': 'x'})),
                 ('GET', 'friend_reviews', lambda b, u: Reply(200, list(left)))]
        return self.go_push('E-REV-26', rules)

    def test_the_writer_deletes_and_nothing_comes(self):
        result = self.go26()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual([who for m, p, who in self.world.callers if p.startswith('/friend-reviews')], ['tok-2', 'tok-2'])  # 상대가 쓰고 지운다
        self.assertLess(self.at('POST friend-reviews')[0], self.at('DELETE friend-reviews/r1')[0])

    def test_a_notice_after_the_delete_is_a_fail(self):
        for notice in ((REVIEW, '리뷰가 지워졌어요'), ('아무 제목', '아무 본문')):
            with self.subTest(notice=notice):
                self.world.reset()
                result = self.go26(on_delete=[notice])
                self.assertEqual(result[0], 'fail')
                self.assertIn('안 와야 할 알림', result[1])

    def test_no_write_notice_is_blocked_because_nothing_proves_the_path(self):
        self.assertEqual(self.go26(written=False)[0], 'blocked')

    def test_a_delete_that_is_not_204_or_leaves_the_row_is_a_fail(self):
        self.assertEqual(self.go26(delete=404)[0], 'fail')
        self.world.reset()
        self.assertEqual(self.go26(left=[{'id': 'r1'}])[0], 'fail')

    def test_the_delete_is_watched_from_after_the_write_notice(self):
        self.go26()
        reads = self.at('read')
        self.assertLess(self.at('POST friend-reviews')[0], reads[-1])
        self.assertLess(reads[-1], self.at('DELETE friend-reviews/r1')[0])


# ── E-REV-41 두 기기: B 가 코드 → A 알림 → A 누르면 20b ────────────────────────────────────────────────────

class ThreadTwo:
    """twodev.bound 의 `two` 대신 — [scripts] {'A' · 'B': [(step, effect)]} 를 스레드 둘에서 돌며 plan 핸들러를 부른다(진짜 Sync).
    effect 는 앱이 그 step 에 닿기 전에 화면에서 한 일(서버에 남는 것)이다. 핸들러가 던지면 그쪽은 blocked(twodev 와 같다)."""

    def __init__(self, scripts):
        self.scripts, self.jobs, self.limit, self.went = scripts, {}, None, []

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.jobs, self.limit = {'A': a_job, 'B': b_job}, limit
        sync, said = twodev.Sync(), {}

        def side(name):
            try:
                for step, effect in self.scripts[name]:
                    if effect:
                        effect()
                    handler = plan.get((name, step))
                    self.went.append((name, step, handler({'step': step}, sync) if handler else None))
                said[name] = {'result': 'pass'}
            except Exception as e:
                said[name] = {'result': 'blocked', 'note': f'{type(e).__name__}: {e}'}
            sync.abort()

        threads = [threading.Thread(target=side, args=(n,)) for n in ('A', 'B')]
        for t in threads:
            t.start()
        for t in threads:
            t.join(10)
        return twodev.merge(said.get('A'), said.get('B'))


class Rev41Test(TapBase):
    def setUp(self):
        super().setUp()
        self.phone = TapPhone(self.world)
        for patcher in (mock.patch.object(batch_gate, 'now_seoul', lambda: NOON), mock.patch.object(area3_phone9, 'PEER', 2)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def notice(self, nickname, copies=1):
        """B 앱이 코드를 확인하면 서버가 A 에게 보내는 알림(referral/router.py → notify_review_request)."""
        def effect():
            for _ in range(copies):
                self.world.shade.append(notify.Notice(f'f{len(self.world.shade)}', FRIEND, f'{nickname} 님이 가입했어요, 리뷰를 남겨 주세요', 'c'))
        return effect

    def go41(self, copies=1, referrals=None, nickname=PARTNER):
        rules = [self.TOKEN, ('GET', 'select=referral_code', lambda b, u: Reply(200, [{'referral_code': 'ABCDE2'}])),
                 ('GET', 'referrals?', lambda b, u: Reply(200, [{'referrer_id': 'id-1'}] if referrals is None else referrals))]
        fake = WorldFake(self.world, rules)
        for patcher in (mock.patch.object(tools, 'call', fake), mock.patch.object(area3_phone9.time, 'sleep', lambda s: None)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake = fake
        self.two = ThreadTwo({'A': [('holding', None)], 'B': [('code', None), ('redeemed', self.notice(nickname, copies))]})
        return twodev.TWO['E-REV-41'](self.run, self.two)

    def test_b_enters_the_code_a_gets_one_notice_and_taps_it(self):
        result = self.go41()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.tap_bodies, [f'{PARTNER} 님이 가입했어요, 리뷰를 남겨 주세요'])
        self.assertEqual([n for side, n, extra in self.two.went if side == 'A'], ['holding'])
        a_go = next(extra for side, n, extra in self.two.went if side == 'A')
        self.assertEqual(a_go, {'tapped': True})  # 앱은 눌린 뒤에만 20b 를 찾는다

    def test_each_app_is_told_who_the_sheet_must_be_for_and_b_gets_the_code(self):
        self.go41()
        a_job, b_job = self.two.jobs['A'], self.two.jobs['B']
        self.assertEqual(a_job['friend_id'], 'id-2')  # A 의 20b 는 B 에게 쓰는 것
        self.assertEqual((b_job['referrer_id'], b_job['code']), ('id-1', 'ABCDE2'))  # B 의 20b 는 A 에게 쓰는 것
        self.assertIn('token_hash', a_job)
        self.assertIn('token_hash', b_job)

    def test_b_is_an_onboarding_account_named_in_the_notice(self):
        self.go41()
        onboarding = [b for b in self.fake.bodies('POST', '/profile-onboarding/basic-info')]
        self.assertEqual([b['nickname'] for b in onboarding], ['Mina', PARTNER])  # A(홈) 먼저, B(06-3 직전) 둘째
        self.assertEqual(self.fake.bodies('POST', '/profile-onboarding/bio'), [{'bio': '주말엔 카페에서 책을 읽어요.'}])  # A 만 bio 까지

    def test_a_is_at_the_back_before_b_enters_the_code(self):
        self.go41()
        self.assertLess(self.at('read')[0], self.at('background')[0])
        self.assertLess(self.at('background')[0], self.at('GET referrals')[0])

    def test_two_copies_is_a_fail(self):
        result = self.go41(copies=2)
        self.assertEqual(result[0], 'fail')
        self.assertIn('2개', result[1])

    def test_no_notice_is_a_fail_and_nothing_is_tapped(self):
        result = self.go41(copies=0)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.tap_bodies, [])
        self.assertEqual(next(extra for side, n, extra in self.two.went if side == 'A'), {'tapped': False})

    def test_a_notice_naming_someone_else_is_a_fail(self):
        self.assertEqual(self.go41(nickname='Other')[0], 'fail')

    def test_no_referral_row_after_b_confirms_is_a_fail(self):
        result = self.go41(referrals=[])
        self.assertEqual(result[0], 'fail')
        self.assertIn('referrals', result[1])

    def test_a_missing_device_token_is_blocked(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        self.assertEqual(self.go41()[0], 'blocked')
        self.assertEqual(self.tap_bodies, [])

    def test_outside_10_to_20_it_is_blocked_before_any_account(self):
        for hour in (9, 19, 21):  # 19시대는 준비가 끝날 즈음 20시를 넘을 수 있다
            with self.subTest(hour=hour), mock.patch.object(batch_gate, 'now_seoul', lambda: NOON.replace(hour=hour, minute=50)):
                self.world.reset()
                two = mock.Mock(side_effect=AssertionError('기기까지 가면 안 된다'))
                with mock.patch.object(tools, 'call', mock.Mock(side_effect=AssertionError('계정을 만들면 안 된다'))):
                    result = twodev.TWO['E-REV-41'](self.run, two)
                self.assertEqual(result[0], 'blocked')

    def test_an_old_android_without_the_permission_still_runs_and_still_takes_it_back(self):
        # 안드로이드 12 이하는 알림 권한이 없다(pm grant 가 Blocked) = 권한 창도 없다 — area3_phone._permitted 와 같이 그대로 진행하고 끝에 되돌린다
        with mock.patch.object(notify, 'grant_notifications', mock.Mock(side_effect=Blocked('권한 없음'))):
            result = self.go41()
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.world.log[-1], 'revoke')

    def test_the_notification_permission_is_given_to_the_phone_and_taken_back(self):
        self.go41()
        self.assertEqual(self.world.log[0], 'grant')
        self.assertEqual(self.world.log[-1], 'revoke')


# ── 등록 · 앱 계약 ──────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_single_phone_cases_are_phone_cases_in_one_bundle_and_41_is_a_two_device_case(self):
        self.assertEqual(area3.BUNDLES['area3-phone-9'], SINGLE)
        self.assertEqual(area3.BUNDLES['area3-two-rev'], ['E-REV-41'])
        for case in SINGLE:
            self.assertIn(case, area1.PHONE)
            self.assertNotIn(case, twodev.TWO)
        self.assertIn('E-REV-41', twodev.TWO)
        self.assertNotIn('E-REV-41', area1.PHONE)

    def test_no_other_bundle_already_has_these_numbers(self):
        from e2e import __main__ as main
        mine = {'area3-phone-9', 'area3-two-rev'}
        for name, cases in main.BUNDLES.items():
            if name not in mine:
                self.assertFalse(set(cases) & {*SINGLE, 'E-REV-41'}, name)
        self.assertEqual(main.BUNDLES['area3-phone-9'], SINGLE)
        self.assertFalse({*SINGLE, 'E-REV-41'} & set(main.API_CASES))

    def test_slow_cases_get_more_than_the_default_limit(self):
        for case in [*SINGLE, 'E-REV-41']:
            self.assertGreater(tools.CASE_LIMITS[case], tools.CASE_LIMIT, case)

    def test_the_app_runs_the_same_app_side_as_the_original_for_the_single_phone_cases(self):
        main = dart('e2e_test.dart')
        self.assertIn("'E-REV-16': area4Cases['E-PUSH-50']!", main)  # 홈에서 멈춰 기다리다 눌린 뒤 받은 리뷰를 본다
        for case in ('E-REV-17', 'E-REV-26'):
            self.assertIn(f"'{case}': area1Cases['E-ONB-61']!", main)  # 홈까지 켜 두기만
        self.assertIn('...area3Cases9', main)

    def test_the_app_has_both_sides_of_41_and_every_step_the_pc_waits_for(self):
        text = dart('area3_b9.dart')
        for side, steps in (('A', ['holding']), ('B', ['code', 'redeemed'])):
            found = re.search(rf"(?ms)^  'E-REV-41/{side}':(.*?)(?=^  '|^\}};)", text)
            self.assertIsNotNone(found, side)
            for step in steps:
                self.assertRegex(found.group(1), rf"step\('{step}'", f'{side} {step}')

    def test_the_app_reads_every_key_the_pc_sends(self):
        text = dart('area3_b9.dart')
        for key in ('friend_id', 'referrer_id', 'code', 'tapped'):
            self.assertIn(f"['{key}']", text, key)


if __name__ == '__main__':
    unittest.main()
