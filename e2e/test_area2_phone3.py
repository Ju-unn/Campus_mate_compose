"""영역 2 폰 A 3차(망 끊기 · 카드 · 알림 · 공유 창 · 하트 다시 만들기)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP.
저장소 루트에서 `python -m unittest e2e.test_area2_phone3`."""

import unittest
from datetime import datetime
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from e2e import area1, area2_phone3, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area1_phone import FakePhone
from e2e.test_area2 import Base, Fake
from e2e.tools import Blocked, Reply

# 2026-10-05(월) 부터 한 주 — 요일마다 정오(서울)
WEEK = {name: datetime(2026, 10, 5 + i, 12, 0, tzinfo=SEOUL) for i, name in enumerate('월화수목금토일')}


class SubtitleTest(unittest.TestCase):
    def test_twice_a_week_follows_the_scenario_weekday_table(self):
        want = {
            '월': '목요일 오전 7시에 새로운 사람을 찾아볼게요',
            '화': '목요일 오전 7시에 새로운 사람을 찾아볼게요',
            '수': '내일 오전 7시에 새로운 한 명이 도착해요',
            '목': '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요',
            '금': '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요',
            '토': '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요',
            '일': '내일 오전 7시에 새로운 한 명이 도착해요',  # 일요일 → 월요일은 "내일"(사용자 확정 10-04)
        }
        got = {name: area2_phone3.expected_subtitle(now, [1, 4]) for name, now in WEEK.items()}
        self.assertEqual(got, want)

    def test_every_day_is_always_tomorrow(self):
        for now in WEEK.values():
            self.assertEqual(area2_phone3.expected_subtitle(now, [1, 2, 3, 4, 5, 6, 7]), '내일 오전 7시에 새로운 한 명이 도착해요')

    def test_issue_hour_comes_from_the_settings_row_and_afternoon_reads_pm(self):
        self.assertEqual(area2_phone3.expected_subtitle(WEEK['화'], [1, 4], hour=19), '목요일 오후 7시에 새로운 사람을 찾아볼게요')


class GuardsTest(unittest.TestCase):
    def test_real_ai_gate_stays_shut_unless_the_flag_is_exactly_one(self):
        for env in ({}, {'E2E_REAL_AI': ''}, {'E2E_REAL_AI': '0'}, {'E2E_REAL_AI': 'yes'}):
            with self.assertRaises(Blocked):
                area2_phone3.real_ai_gate(env)
        area2_phone3.real_ai_gate({'E2E_REAL_AI': '1'})


DUMP = (
    '<hierarchy>'
    '<node text="다른 앱 알림" content-desc="" bounds="[0,100][500,200]" />'
    '<node text="오늘의 카드가 도착했어요" content-desc="" bounds="[40,300][440,360]" />'
    '<node text="" content-desc="복사" bounds="[10,20][110,60]" />'
    '</hierarchy>'
)
class DeviceTextTest(unittest.TestCase):
    def test_tap_point_is_the_centre_of_the_node_that_has_the_label_in_text_or_description(self):
        self.assertEqual(area2_phone3.tap_point(DUMP, ['오늘의 카드가 도착했어요']), (240, 330))
        self.assertEqual(area2_phone3.tap_point(DUMP, ['Copy', '복사']), (60, 40))
        self.assertIsNone(area2_phone3.tap_point(DUMP, ['없는 글']))
        self.assertIsNone(area2_phone3.tap_point('<hierarchy>', ['복사']))


class OfflineTest(unittest.TestCase):
    def test_network_and_mailbox_are_restored_even_when_the_app_blows_up(self):
        calls = []

        def boom(midway=None, **job):
            raise RuntimeError('앱 죽음')

        boom.serial, boom.hub = 'S', mock.Mock(port=8765)
        with mock.patch.object(area2_phone3.notify, 'ensure_online', lambda s: calls.append(('online', s))), \
                mock.patch.object(tools, 'adb', lambda s, *a, check=True: calls.append(('adb', a)) or ''):
            with self.assertRaises(RuntimeError):
                area2_phone3.offline(boom, area1.Check())
        self.assertEqual(calls, [('online', 'S'), ('adb', ('reverse', f'tcp:{tools.DEVICE_PORT}', 'tcp:8765'))])


ROW = {'issue_weekdays': [1], 'issue_time': '07:00:00', 'ladder_twice_per_week_min': 50, 'ladder_three_per_week_min': 100,
       'ladder_four_per_week_min': 200, 'ladder_daily_min': 300}


class RegionTest(Base):
    def serve(self):
        fake = Fake([('GET', 'region_group_settings', lambda b, u: Reply(200, [dict(ROW)]))])
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    def test_region_values_are_changed_and_put_back_exactly(self):
        fake = self.serve()
        with area2_phone3.region_set(self.run, 'e2e', issue_weekdays=[1, 4]):
            pass
        self.assertEqual(fake.bodies('PATCH', 'region_group_settings'), [{'issue_weekdays': [1, 4]}, {'issue_weekdays': [1]}])

    def test_restore_runs_even_when_the_body_raises(self):
        fake = self.serve()
        with self.assertRaises(ValueError):
            with area2_phone3.region_set(self.run, 'e2e', ladder_daily_min=0):
                raise ValueError
        self.assertEqual(fake.bodies('PATCH', 'region_group_settings')[-1], {'ladder_daily_min': 300})

    def test_only_the_e2e_region_is_ever_written(self):
        for region in ('seoul', 'busan', '', None):
            fake = self.serve()
            with self.assertRaises(Blocked):
                with area2_phone3.region_set(self.run, region, issue_weekdays=[1]):
                    pass
            self.assertEqual(fake.bodies('PATCH', 'region_group_settings'), [], region)


class CaseBase(Base):
    def go(self, case, phone, rules=()):
        fake = Fake(list(rules))
        for patcher in (mock.patch.object(tools, 'call', fake), mock.patch.object(area2_phone3.time, 'sleep', lambda s: None)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake = fake
        return area1.attempt_phone(self.run, case, phone)


class LowHeartsTest(CaseBase):
    RULES = [('GET', 'profile_avatars', lambda b, u: Reply(200, [{'id': 'a1', 'status': 'ready'}, {'id': 'a2', 'status': 'ready'}])),
             ('GET', 'entitlements', lambda b, u: Reply(200, [{'heart_balance': 9}]))]

    def test_balance_nine_with_two_avatars_gets_402_and_no_new_attempt(self):
        rules = [('POST', '/me/avatar/regenerate', lambda b, u: Reply(402, {'detail': '하트가 모자라요'})), *self.RULES]
        phone = FakePhone()
        result = self.go('E-HEART-44', phone, rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual([b['p_amount'] for b in self.fake.bodies('POST', 'rpc/grant_hearts')], [9])
        self.assertEqual(len(self.fake.bodies('POST', '/me/avatar/regenerate')), 1)
        self.assertIn('token_hash', phone.jobs[0])

    def test_the_regeneration_request_is_sent_only_once_even_when_the_link_drops(self):
        rules = [('POST', '/me/avatar/regenerate', lambda b, u: Reply(402, {'detail': '하트가 모자라요'})), *self.RULES]
        self.go('E-HEART-44', FakePhone(), rules)
        sent = [o for m, path, o in self.fake.options if (m, path) == ('POST', '/me/avatar/regenerate')]
        self.assertEqual(sent, [{'retry': False}])  # 서버에 닿았는지 모호해도 다시 보내지 않는다 — 열려 있으면 유료 호출이다

    def test_a_balance_other_than_nine_is_a_fail(self):
        rules = [('POST', '/me/avatar/regenerate', lambda b, u: Reply(402, {'detail': '하트가 모자라요'})),
                 self.RULES[0], ('GET', 'entitlements', lambda b, u: Reply(200, [{'heart_balance': 8}]))]
        self.assertEqual(self.go('E-HEART-44', FakePhone(), rules)[0], 'fail')

    def test_a_server_that_accepts_the_regeneration_is_a_fail(self):
        rules = [('POST', '/me/avatar/regenerate', lambda b, u: Reply(202, {'status': 'pending'})), *self.RULES]
        self.assertEqual(self.go('E-HEART-44', FakePhone(), rules)[0], 'fail')


class BlockedCardTest(CaseBase):
    def test_blocker_is_the_card_target_and_the_decision_table_stays_empty(self):
        phone = FakePhone(midway_step={'step': 'blocked'})
        result = self.go('E-CARD-35', phone)
        self.assertEqual(result[0], 'pass', result)
        blocks = self.fake.bodies('POST', '/rest/v1/blocks')
        self.assertEqual(blocks, [[{'blocker_id': 'id-2', 'blocked_id': 'id-1'}]])  # B 가 A 를 차단
        self.assertEqual(phone.acted, ['blocked'])

    def test_a_decision_row_is_a_fail(self):
        rules = [('GET', 'card_decisions', lambda b, u: Reply(200, [{'card_id': 'd'}]))]
        self.assertEqual(self.go('E-CARD-35', FakePhone(midway_step={'step': 'blocked'}), rules)[0], 'fail')

    def test_only_columns_the_table_has_are_selected(self):
        # card_decisions 의 기본키는 card_id — id 칸이 없어 select=id 는 운영에서 400(10-05 폰 실행에서 blocked)
        def strict(body, url):
            columns = parse_qs(urlsplit(url).query)['select'][0].split(',')
            unknown = set(columns) - {'card_id', 'decision', 'decided_at'}
            return Reply(400, {'message': f'column card_decisions.{sorted(unknown)[0]} does not exist'}) if unknown else Reply(200, [])

        result = self.go('E-CARD-35', FakePhone(midway_step={'step': 'blocked'}), [('GET', 'card_decisions', strict)])
        self.assertEqual(result[0], 'pass', result)


class WaitingCardTest(CaseBase):
    def rules(self):
        return [('GET', 'region_group_settings', lambda b, u: Reply(200, [dict(ROW)])),
                ('GET', 'universities(region_group)', lambda b, u: Reply(200, [{'universities': {'region_group': 'e2e'}}]))]

    def test_every_day_run_tells_the_app_the_tomorrow_text_and_puts_the_row_back(self):
        phone = FakePhone()
        result = self.go('E-CARD-15', phone, self.rules())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.jobs[0]['subtitle'], '내일 오전 7시에 새로운 한 명이 도착해요')
        self.assertEqual(self.fake.bodies('PATCH', 'region_group_settings'),
                         [{'issue_weekdays': [1, 2, 3, 4, 5, 6, 7]}, {'issue_weekdays': [1]}])

    def test_twice_a_week_run_sends_the_text_for_todays_weekday(self):
        phone = FakePhone()
        with mock.patch.object(area2_phone3, 'now_seoul', lambda: WEEK['화']):
            result = self.go('E-CARD-14', phone, self.rules())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.jobs[0]['subtitle'], '목요일 오전 7시에 새로운 사람을 찾아볼게요')
        self.assertEqual(self.fake.bodies('PATCH', 'region_group_settings')[0], {'issue_weekdays': [1, 4]})

    def test_crossing_midnight_is_blocked_not_a_wrong_text(self):
        times = iter([datetime(2026, 10, 6, 23, 59, tzinfo=SEOUL), datetime(2026, 10, 7, 0, 1, tzinfo=SEOUL)])
        with mock.patch.object(area2_phone3, 'now_seoul', lambda: next(times)):
            self.assertEqual(self.go('E-CARD-14', FakePhone(), self.rules())[0], 'blocked')


CARD = notify.Notice('k1', '오늘의 카드가 도착했어요', '지금 확인해 보세요', 'cards')


class CardNotificationTest(CaseBase):
    def rules(self, tokens=1):
        return [('GET', 'region_group_settings', lambda b, u: Reply(200, [dict(ROW)])),
                ('GET', 'universities(region_group)', lambda b, u: Reply(200, [{'universities': {'region_group': 'e2e'}}])),
                ('GET', 'push_tokens', lambda b, u: Reply(200, [{'token': 't'}] * tokens)),
                ('GET', 'select=nickname', lambda b, u: Reply(200, [{'nickname': 'Abcde', 'birth_year': 2004, 'universities': {'name': '테스트대학'}}])),
                ('GET', 'daily_cards', lambda b, u: Reply(200, [{'id': 'c1', 'source': 'daily'}]))]

    def run_case(self, new=(CARD,), tokens=1):
        calls = []
        before = [notify.Notice('old', '남은 알림', '', 'c')]
        patches = [mock.patch.object(area2_phone3.area2, '_batch', lambda name: calls.append(('batch', name))),
                   mock.patch.object(notify, 'grant_notifications', lambda s: None),
                   mock.patch.object(notify, 'revoke_notifications', lambda s: None),
                   mock.patch.object(notify, 'read_notifications', lambda s: calls.append('read') or before),
                   mock.patch.object(notify, 'background', lambda s: calls.append('background')),
                   mock.patch.object(notify, 'wait_new', lambda s, b, count=1, seconds=0, match=None: calls.append(('wait_new', b == before, seconds, match is not None)) or list(new)),
                   mock.patch.object(notify, 'tap_notification', lambda s, title: calls.append(('tap', title)))]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)
        phone = FakePhone(midway_step={'step': 'background'})
        phone.serial = 'S'
        phone.hub = mock.Mock()
        with mock.patch.object(area2_phone3.time, 'monotonic', side_effect=iter(range(0, 10000))):
            return self.go('E-CARD-02', phone, self.rules(tokens)), phone, calls

    def test_batch_runs_after_the_device_token_is_up_and_the_notification_is_tapped(self):
        result, phone, calls = self.run_case()
        self.assertEqual(result[0], 'pass', result)
        # 알림 목록을 먼저 읽어 두고(앞 알림과 섞이지 않게) → HOME → 배치 → 새 알림 → 누르기
        self.assertEqual([c for c in calls if c != 'read'], ['background', ('batch', 'daily-cards'), ('wait_new', True, 30, True), ('tap', '오늘의 카드가 도착했어요')])
        self.assertLess(calls.index('read'), calls.index('background'))
        self.assertEqual(phone.jobs[0]['name_age'], f'Abcde, {area2_phone3.now_seoul().year - 2004 + 1}')
        self.assertEqual(phone.jobs[0]['school'], '테스트대학')
        patches = self.fake.bodies('PATCH', 'region_group_settings')
        self.assertEqual(patches[0]['issue_weekdays'], [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual(patches[0]['ladder_daily_min'], 0)
        self.assertEqual(patches[-1], {key: ROW[key] for key in patches[0]})

    def test_no_device_token_means_no_batch(self):
        result, _, calls = self.run_case(tokens=0)
        self.assertEqual(result[0], 'blocked')
        self.assertNotIn(('batch', 'daily-cards'), calls)

    def test_no_new_notification_is_a_fail_and_nothing_is_tapped(self):
        result, _, calls = self.run_case(new=())
        self.assertEqual(result[0], 'fail')
        self.assertFalse([c for c in calls if isinstance(c, tuple) and c[0] == 'tap'])

    def test_a_notification_with_other_words_is_a_fail(self):
        other = notify.Notice('k2', '오늘의 카드가 도착했어요', '다른 본문', 'cards')
        self.assertEqual(self.run_case(new=(other,))[0][0], 'fail')


class ReferralNotificationTest(CaseBase):
    BODY = 'Abcde 님이 가입했어요, 리뷰를 남겨 주세요'

    def run_case(self, new, daytime=True, tokens=1):
        calls = []
        before = [notify.Notice('old', '남은 알림', '', 'c')]
        patches = [mock.patch.object(area2_phone3.time, 'monotonic', side_effect=iter(range(0, 10000))),
                   mock.patch.object(notify, 'require_daytime', (lambda now=None: None) if daytime else mock.Mock(side_effect=Blocked('밤'))),
                   mock.patch.object(notify, 'read_notifications', lambda s: calls.append('read') or before),
                   mock.patch.object(notify, 'background', lambda s: calls.append('background')),
                   mock.patch.object(notify, 'wait_new', lambda s, b, count=1, seconds=0, match=None: calls.append(('wait_new', b == before, seconds, match is not None)) or list(new))]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)
        rules = [('GET', 'push_tokens', lambda b, u: Reply(200, [{'token': 't'}] * tokens)),
                 ('POST', '/referral/redeem', lambda b, u: calls.append('redeem') or Reply(200, {'referrer_id': 'x'})),
                 ('GET', 'select=nickname', lambda b, u: Reply(200, [{'nickname': 'Abcde'}])),
                 ('GET', 'select=referral_code', lambda b, u: Reply(200, [{'referral_code': 'ABCDE2'}]))]
        phone = FakePhone()
        phone.serial = 'S'
        return self.go('E-REF-18', phone, rules), phone, calls

    def test_referrer_phone_goes_to_background_and_gets_the_friend_notification(self):
        got = notify.Notice('k', '친구가 가입했어요', self.BODY, 'c')
        result, phone, calls = self.run_case([got])
        self.assertEqual(result[0], 'pass', result)
        # 코드 입력 전에 앞 알림을 읽어 두고(새 알림만 보려고) → HOME → 코드 입력 → 그 목록을 기준으로 새 알림 대기
        self.assertEqual(calls, ['read', 'background', 'redeem', ('wait_new', True, 30, True)])  # 기다리던 알림이 올 때까지(match) 기다린다
        self.assertEqual(self.fake.bodies('POST', '/referral/redeem'), [{'code': 'ABCDE2'}])
        self.assertIn('token_hash', phone.jobs[0])

    def test_no_device_token_blocks_before_the_friend_signs_up(self):
        # 추천인 폰의 기기 토큰이 서버에 없으면 가입 알림은 아예 안 간다 — 알림 시험이 아니라 준비 실패다
        result, _, calls = self.run_case([], tokens=0)
        self.assertEqual(result[0], 'blocked', result)
        self.assertNotIn('redeem', calls)
        self.assertNotIn('background', calls)

    def test_a_long_run_of_wrong_notifications_is_cut_to_five_in_the_memo(self):
        many = [notify.Notice(f'k{i}', f'제목{i}', 'x' * 300, 'c') for i in range(7)]
        result, _, _ = self.run_case(many)
        self.assertEqual(result[0], 'fail')
        self.assertIn('제목4', result[1])
        self.assertNotIn('제목5', result[1])
        self.assertIn('외 2건', result[1])
        self.assertLess(len(result[1]), 1500)  # 알림 하나의 본문이 길어도(경계가 샌 경우) 메모가 끝없이 길어지지 않는다

    def test_a_wrong_nickname_or_no_notification_is_a_fail(self):
        wrong = notify.Notice('k', '친구가 가입했어요', '다른 님이 가입했어요, 리뷰를 남겨 주세요', 'c')
        result = self.run_case([wrong])[0]
        self.assertEqual(result[0], 'fail')
        self.assertIn('다른 님이 가입했어요, 리뷰를 남겨 주세요', result[1])  # 틀릴 때 우리 앱 알림의 실제 제목 · 본문을 메모에 남긴다
        self.assertIn('친구가 가입했어요', result[1])
        self.assertEqual(self.run_case([])[0][0], 'fail')

    def test_at_night_it_is_blocked_before_the_phone_is_called(self):
        result, phone, _ = self.run_case([], daytime=False)
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(phone.jobs, [])
        self.assertEqual(self.fake.users, [])


class RealAiTest(CaseBase):
    def test_with_the_gate_shut_nothing_is_made_and_the_phone_is_not_called(self):
        phone = FakePhone()
        with mock.patch.dict(area2_phone3.os.environ, {}, clear=True):
            result = self.go('E-HEART-42', phone)
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(phone.jobs, [])
        self.assertEqual(self.fake.users, [])

    def test_charged_run_checks_balance_during_and_ledger_after(self):
        two = [{'id': 'a1', 'status': 'ready'}, {'id': 'a2', 'status': 'ready'}]
        three = two + [{'id': 'a3', 'status': 'ready'}]
        states = iter([two, three])
        balances = iter([[{'heart_balance': 10}], [{'heart_balance': 10}], [{'heart_balance': 0}]])
        rules = [('GET', 'profile_avatars', lambda b, u: Reply(200, next(states, three))),
                 ('GET', 'entitlements', lambda b, u: Reply(200, next(balances, [{'heart_balance': 0}]))),
                 ('GET', 'heart_transactions', lambda b, u: Reply(200, [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'a3'}]))]
        phone = FakePhone(midway_step={'step': 'started'})
        with mock.patch.dict(area2_phone3.os.environ, {'E2E_REAL_AI': '1'}):
            result = self.go('E-HEART-45', phone, rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.jobs[0]['balance'], 10)

    def setUp(self):
        super().setUp()
        area2_phone3._PAID.clear()
        self.addCleanup(area2_phone3._PAID.clear)

    def charged(self, balances, ledger, case='E-HEART-45'):
        two = [{'id': 'a1', 'status': 'ready'}, {'id': 'a2', 'status': 'ready'}]
        three = two + [{'id': 'a3', 'status': 'ready'}]
        states = iter([two, three])
        values = iter(balances)
        rules = [('GET', 'profile_avatars', lambda b, u: Reply(200, next(states, three))),
                 ('GET', 'entitlements', lambda b, u: Reply(200, [{'heart_balance': next(values, balances[-1])}])),
                 ('GET', 'heart_transactions', lambda b, u: Reply(200, ledger))]
        phone = FakePhone(midway_step={'step': 'started'})
        with mock.patch.dict(area2_phone3.os.environ, {'E2E_REAL_AI': '1'}):
            return self.go(case, phone, rules), phone

    def test_a_balance_that_moves_while_it_is_being_made_is_a_fail(self):
        (result, _) = self.charged([7, 7, 0], [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'a3'}])
        self.assertEqual(result[0], 'fail', result)

    def test_a_ledger_ref_that_is_not_the_new_attempt_is_a_fail(self):
        (result, _) = self.charged([10, 10, 0], [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'other'}])
        self.assertEqual(result[0], 'fail', result)

    def test_after_one_paid_start_the_same_case_is_never_called_again(self):
        ledger = [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'a3'}]
        (first, _) = self.charged([10, 10, 0], ledger)
        self.assertEqual(first[0], 'pass', first)
        (second, phone) = self.charged([10, 10, 0], ledger)
        self.assertEqual(second[0], 'blocked')
        self.assertIn('재시도', second[1])
        self.assertEqual(phone.jobs, [])

    def test_a_paid_fail_comes_back_as_that_same_fail_on_the_second_call_without_the_phone(self):
        wrong = [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'other'}]
        (first, _) = self.charged([10, 10, 0], wrong)
        self.assertEqual(first[0], 'fail', first)
        (second, phone) = self.charged([10, 10, 0], wrong)
        self.assertEqual(second[0], 'fail', second)  # 러너가 fail 을 한 번 더 돌려도 첫 시도의 이유가 사라지지 않는다
        self.assertIn('ref_id', second[1])
        self.assertIn('다시 하지 않음', second[1])
        self.assertEqual(phone.jobs, [])

    def test_the_note_counts_the_paid_calls_as_new_attempt_rows(self):
        (passed, _) = self.charged([10, 10, 0], [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'a3'}])
        self.assertIn('유료 호출 1번', passed[1])
        area2_phone3._PAID.clear()
        (failed, _) = self.charged([7, 7, 0], [{'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'a3'}])
        self.assertEqual(failed[0], 'fail')
        self.assertIn('유료 호출 1번', failed[1])

    def test_a_paid_blocked_keeps_its_reason_and_count_on_the_second_call(self):
        one = [{'id': 'a1', 'status': 'ready'}]
        states = iter([one, one + [{'id': 'a9', 'status': 'failed'}]])
        rules = [('GET', 'profile_avatars', lambda b, u: Reply(200, next(states, one)))]
        with mock.patch.dict(area2_phone3.os.environ, {'E2E_REAL_AI': '1'}):
            first = self.go('E-HEART-42', FakePhone(midway_step={'step': 'started'}), rules)
            second = self.go('E-HEART-42', FakePhone(), rules)
        self.assertEqual(first[0], 'blocked')
        self.assertIn('유료 호출 1번', first[1])
        self.assertEqual(second[0], 'blocked')
        self.assertIn('실패', second[1])  # 첫 시도가 왜 막혔는지가 두 번째 메모에도 남는다

    def test_a_timeout_before_any_new_row_does_not_read_as_no_cost(self):
        one = [{'id': 'a1', 'status': 'ready'}]
        rules = [('GET', 'profile_avatars', lambda b, u: Reply(200, one))]
        with mock.patch.dict(area2_phone3.os.environ, {'E2E_REAL_AI': '1'}), mock.patch.object(area2_phone3, 'AI_WAIT', 0):
            result = self.go('E-HEART-42', FakePhone(midway_step={'step': 'started'}), rules)
        self.assertEqual(result[0], 'blocked')
        self.assertIn('서버에 닿았는지 확인 필요', result[1])  # 앱이 이미 눌렀다 — 새 행이 아직 0개여도 비용이 안 나갔다는 뜻이 아니다

    def test_a_failed_generation_is_blocked_so_the_runner_does_not_pay_twice(self):
        one = [{'id': 'a1', 'status': 'ready'}]
        states = iter([one, one + [{'id': 'a9', 'status': 'failed'}]])
        rules = [('GET', 'profile_avatars', lambda b, u: Reply(200, next(states, one)))]
        phone = FakePhone(midway_step={'step': 'started'})
        with mock.patch.dict(area2_phone3.os.environ, {'E2E_REAL_AI': '1'}):
            self.assertEqual(self.go('E-HEART-42', phone, rules)[0], 'blocked')


class RegistryTest(unittest.TestCase):
    def test_bundles_are_twelve_plus_three_and_every_case_is_registered(self):
        plain = ['E-HOME-09', 'E-CARD-16', 'E-POLL-30', 'E-HEART-26', 'E-REF-05', 'E-CARD-14', 'E-CARD-15', 'E-CARD-35',
                 'E-CARD-02', 'E-REF-18', 'E-REF-04', 'E-HEART-44']
        self.assertEqual(sorted(area1.BUNDLES['area2-phone3']), sorted(plain))
        self.assertEqual(sorted(area1.BUNDLES['area2-phone3-ai']), ['E-HEART-42', 'E-HEART-43', 'E-HEART-45'])
        for case in [*plain, 'E-HEART-42', 'E-HEART-43', 'E-HEART-45']:
            self.assertIn(case, area1.PHONE)


if __name__ == '__main__':
    unittest.main()
