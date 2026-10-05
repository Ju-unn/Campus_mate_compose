"""영역 3 E-CHAT-53(리마인드가 밤에 걸리면 아침 8시로 밀린다 — 07시대 0건 · 08시대 1건, 묶음 area3-phone-6)의 PC 쪽 시험.
폰 · 운영 · gcloud 없이 가짜 앱 · 가짜 서버 · 가짜 배치로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3_phone6`.

바탕은 test_area3_phone5.Base5(가짜 서버 · 폰 · 관문 시계)이고, 이 가설은 **시각이 규칙 자체**라서 아래를 더했다.
  시계      배치마다 서울 시각이 달라야 하므로 가짜 시계(self.clock)를 `_nap`(1시간 기다림)이 흘린다. 정각을 지날 때는 **예약 실행**(Cloud Scheduler 매시 정각)도 돈다.
  가짜 배치  `sim_gate` 는 운영 규칙(chat/gate.py reminder_at · push.py 조용한 시간)을 그 시계로 복제한다. 버그 변형: shift(밤 이동) · quiet_check · due(창 무시) · dup(두 번 보냄).
  알림함    폰(id-1)에 간 알림. 대조 알림(상대가 보낸 글)도 같은 곳에 쌓인다. dead_from 이후는 푸시 길이 죽은 것(아무것도 안 옴).
"""

import re
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from e2e import area1, area3, area3_phone5, area3_phone6, batch_gate, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area3_phone5 import BODY, TITLE, Base5, Phone5, at, when
from e2e.tools import Blocked

CASE = 'E-CHAT-53'
YESTERDAY_THREE = datetime(2026, 10, 5, 3, 0, tzinfo=SEOUL)  # 시계가 10-06 일 때 "어제 03:00(서울)"


class Base6(Base5):
    def setUp(self):
        super().setUp()
        self.clock[0] = at('07:10')
        self.inbox, self.snaps, self.sched, self.nap_calls = [], [], [], []
        self.shift, self.quiet_check, self.scheduler, self.dup = True, True, True, False
        self.due = None  # 창 무시 버그 흉내: (created, now) → bool
        self.dead_from = None  # 이 시각부터 푸시 길이 죽는다
        self.jump = None  # 첫 기다림에서 시계가 이 시각으로 튄다(PC 절전)
        self.works_for = lambda n: True  # n 번째 gcloud 호출이 배치를 도는가
        self.delivery_fails = False
        self.drop_control = False  # 상대가 보낸 글(대조 알림)만 안 온다
        clock = self.clock

        class FakeDT(datetime):  # area3_phone5._ages 가 "지금" 을 가짜 시계에서 읽게
            @classmethod
            def now(cls, tz=None):
                return clock[0].astimezone(tz) if tz else clock[0].replace(tzinfo=None)

        for patcher in (mock.patch.object(area3_phone5, 'datetime', FakeDT),
                        mock.patch.object(area3_phone6, '_nap', self.nap),
                        mock.patch.object(notify, 'ensure_delivery', self.ensure_delivery),
                        mock.patch.object(notify, 'read_notifications', lambda serial: list(self.inbox))):
            patcher.start()
            self.addCleanup(patcher.stop)

    # ── 가짜 푸시 · 알림함 ───────────────────────────────────────────────────────────────────────────
    def ensure_delivery(self, serial):
        self.events.append('delivery')
        if self.delivery_fails:
            raise Blocked('GCM 연결 횟수가 안 늘었음')

    def deliver(self, profile_id, title, text):
        if profile_id != 'id-1' or (self.dead_from is not None and self.clock[0] >= self.dead_from):
            return
        for _ in range(2 if self.dup else 1):
            self.inbox.append(notify.Notice(f'n{len(self.inbox)}', title, text, 'c'))

    def fresh(self, before):
        seen = {n.key for n in before}
        return [n for n in self.inbox if n.key not in seen]

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        self.events.append(('wait_new', seconds))
        return self.fresh(before)

    def expect_none(self, serial, before, seconds=0):
        self.events.append(('expect_none', seconds))
        return self.fresh(before)

    def post_message(self, sent):
        reply = super().post_message(sent)
        sender, match = self.user_of(sent), self.match_of(sent)
        if not self.drop_control and reply[0] == 201 and sender != 'id-1' and 'id-1' in {p['profile_id'] for p in self.parts(match['id'])}:
            self.deliver('id-1', self.nick(int(sender.removeprefix('id-'))), sent['body']['body'])
        return reply

    # ── 가짜 시계 · 예약 실행 ────────────────────────────────────────────────────────────────────────
    def nap(self, seconds):
        self.nap_calls.append(seconds)
        before = self.clock[0]
        after = self.jump if self.jump and not self.sched_jumped() else before + timedelta(seconds=seconds)
        if after.hour != before.hour and self.scheduler:  # 정각을 지난다 — 진짜 예약 chat-gate 가 그 시각에 먼저 돈다
            boundary = after.replace(minute=0, second=0, microsecond=0)
            self.clock[0] = boundary
            self.sched.append((boundary, {m['id']: m.get('created_at') for m in self.fake.tables['matches']}))
            self.sim_gate()
        self.clock[0] = after

    def sched_jumped(self):
        return self.clock[0] == self.jump

    # ── 가짜 gcloud(운영 규칙을 가짜 시계로) ─────────────────────────────────────────────────────────
    def gcloud(self, name):
        self.snaps.append((self.clock[0], {m['id']: m.get('created_at') for m in self.fake.tables.get('matches', [])}))
        self.batch_works = self.works_for(len(self.snaps))
        super().gcloud(name)

    def reminder_at(self, created):
        base = (created + timedelta(hours=24)).astimezone(SEOUL)
        if self.shift and base.hour >= 22:
            base = (base + timedelta(days=1)).replace(hour=8, minute=0, second=0, microsecond=0)
        elif self.shift and base.hour < 8:
            base = base.replace(hour=8, minute=0, second=0, microsecond=0)
        return base

    def sim_gate(self):
        now = self.clock[0]
        for match in self.fake.tables.get('matches', []):
            parts = self.parts(match['id'])
            if match.get('trust_passed_at') or match.get('chat_closed_at') or any(p.get('left_at') for p in parts):
                continue
            created = when(match.get('created_at') or now.isoformat())
            if now - created >= timedelta(hours=48):
                match['chat_closed_at'] = now.isoformat()
                continue
            start = self.reminder_at(created)
            due = self.due(created, now) if self.due else start <= now < start + timedelta(hours=1)
            quiet = now.hour >= 22 or now.hour < 8
            if due and not (self.quiet_check and quiet):
                for part in parts:
                    if not part.get('trust_response'):
                        self.deliver(part['profile_id'], TITLE, BODY)

    # ── 한 판 ────────────────────────────────────────────────────────────────────────────────────────
    def run53(self, **kw):
        return self.go(CASE, {'login': {}}, **kw)

    def reminders(self):
        return [n for n in self.inbox if (n.title, n.text) == (TITLE, BODY)]

    def case_match(self):
        return self.matches()[1]  # 맨 앞은 07시대 확인용 방(sentinel)

    def snap_created(self, index):
        return when(self.snaps[index][1][self.case_match()['id']])


class StartTest(Base6):
    def test_it_only_starts_in_the_seven_oclock_hour_and_makes_nothing_otherwise(self):
        for hhmm in ('06:50', '08:10', '14:10', '23:30'):
            with self.subTest(hhmm=hhmm):
                self.setUp()
                self.clock[0] = at(hhmm)
                result, note = self.run53()[0]
                self.assertEqual(result, 'blocked')
                self.assertIn(hhmm, note)
                self.assertIn('07', note)
                self.assertEqual(self.fake.users, [])  # 준비 전에 막는다
                self.assertNotIn('gcloud', self.names())
                self.assertNotIn('delivery', self.names())

    def test_closed_minutes_and_a_preparation_that_reaches_eight_are_blocked_before_any_account(self):
        for hhmm in ('07:03', '07:50', '07:56'):  # 관문이 닫힌 분 · 준비가 끝날 즈음 08:00 에 걸림 · 55분 이후
            with self.subTest(hhmm=hhmm):
                self.setUp()
                self.clock[0] = at(hhmm)
                result, note = self.run53()[0]
                self.assertEqual(result, 'blocked')
                self.assertEqual(self.fake.users, [])
                self.assertNotIn('gcloud', self.names())

    def test_the_first_open_start_is_zero_seven_zero_six_and_the_last_is_zero_seven_forty(self):
        for hhmm in ('07:06', '07:40'):
            with self.subTest(hhmm=hhmm):
                self.setUp()
                self.clock[0] = at(hhmm)
                result, note = self.run53()[0]
                self.assertEqual(result, 'pass', note)

    def test_delivery_is_prepared_before_any_account_is_made_and_a_dead_one_is_blocked(self):
        self.delivery_fails = True
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.fake.users, [])
        self.assertEqual(self.names()[0], 'delivery')


class PassPathTest(Base6):
    def test_two_batches_one_in_each_hour_and_the_order_of_everything(self):
        (result, note), phone = self.run53()
        self.assertEqual(result, 'pass', note)
        gcloud = [e for e in self.events if isinstance(e, tuple) and e[0] == 'gcloud']
        self.assertEqual(gcloud, [('gcloud', 'chat-gate')] * 2)
        self.assertEqual([s[0].hour for s in self.snaps], [7, 8])
        flow = [e if isinstance(e, str) else e[0] for e in self.events]
        flow = [n for n in flow if n in ('delivery', 'app', 'kill', 'gcloud', 'expect_none', 'send', 'wait_new')]
        self.assertEqual(flow, ['delivery', 'app', 'kill', 'gcloud', 'expect_none', 'send', 'wait_new', 'gcloud', 'wait_new', 'wait_new'])
        self.assertEqual(len(self.reminders()), 1)
        self.assertIn('07', note)
        self.assertIn('08', note)

    def test_the_phone_account_logs_in_once_and_the_app_is_dead_while_the_batches_run(self):
        (_, _), phone = self.run53()
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'phase': 'login'}])

    def test_the_room_is_yesterday_three_seoul_at_both_batches(self):
        self.run53()
        self.assertEqual(self.snap_created(0), YESTERDAY_THREE)
        self.assertEqual(self.snap_created(1), YESTERDAY_THREE)
        self.assertEqual(self.snap_created(0).utcoffset(), timedelta(0))  # UTC 로 보낸다 — 서울 시각과 같은 순간
        self.assertEqual(self.snap_created(0).astimezone(SEOUL).hour, 3)

    def test_the_sentinels_are_two_different_rooms_each_aged_past_forty_eight_hours(self):
        self.run53()
        rooms = self.matches()
        sentinels = [rooms[0], rooms[3]]
        self.assertEqual(len({s['id'] for s in sentinels}), 2)
        self.assertTrue(all(s.get('chat_closed_at') for s in sentinels))
        self.assertFalse(self.case_match().get('chat_closed_at'))

    def test_the_second_batch_never_goes_before_zero_eight_zero_six(self):
        self.run53()
        self.assertGreaterEqual(self.snaps[1][0], at('08:06'))
        self.assertLess(self.snaps[1][0], at('08:10'))
        self.assertLessEqual(max(self.nap_calls), 30)  # 서울 시계를 30초 단위로 다시 읽는다

    def test_the_room_is_young_when_the_scheduled_zero_eight_run_looks_at_it(self):
        self.run53()
        self.assertEqual([b.hour for b, _ in self.sched], [8])
        boundary, created = self.sched[0]
        age = boundary - when(created[self.case_match()['id']])
        self.assertLess(age, timedelta(hours=1))  # 예약 실행이 보낼 수 없는 젊은 방

    def test_without_making_the_room_young_the_scheduled_run_would_send_a_second_reminder(self):
        """이 편차가 왜 필요한지 — 안 하면 08:00 예약 실행 1건 + 수동 배치 1건 = 2건이라 가설이 fail 이다."""
        with mock.patch.object(area3_phone6, '_make_young', lambda run, match_id: None):
            result, note = self.run53()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('2건', note)
        self.assertEqual(len(self.reminders()), 2)

    def test_the_account_guard_stops_before_the_first_batch_for_accounts_this_run_did_not_make(self):
        with mock.patch('e2e.area2._mine', lambda run: {u['id'] for u in self.fake.users if u['id'] != 'id-2'}):
            result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('id-2', note)
        self.assertNotIn('gcloud', self.names())

    def test_notification_permission_is_given_before_and_taken_back_after_even_on_blocked(self):
        self.clock[0] = at('09:10')
        self.run53()
        self.assertEqual(self.perm, [('grant', 'S'), ('revoke', 'S')])


class SevenHourTest(Base6):
    def test_a_reminder_in_the_seven_hour_is_a_fail_and_the_eight_hour_is_still_judged(self):
        self.due = lambda created, now: now - created >= timedelta(hours=24)  # 창을 무시하고
        self.quiet_check = False  # 조용한 시간도 무시하는 서버
        result, note = self.run53()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('07시대', note)
        self.assertIn(TITLE, note)  # 틀린 알림의 실제 글이 메모에
        self.assertEqual([s[0].hour for s in self.snaps], [7, 8])  # 배치는 이미 불렀으니 08시대까지 본다

    def test_the_quiet_hour_check_alone_also_gives_zero_so_zero_is_weak_evidence_and_the_note_says_so(self):
        self.shift = False  # 밤 이동이 없는 서버: 07시대는 창 밖이라 0, 08시대도 창 밖이라 0
        result, note = self.run53()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('08시대', note)

    def test_a_dead_push_path_in_the_seven_hour_is_blocked_not_a_pass_of_zero(self):
        self.dead_from = at('00:00')
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('대조', note)
        self.assertEqual(len(self.snaps), 1)  # 08시대 배치는 안 부른다
        self.assertEqual(self.nap_calls, [])  # 기다림도 시작 안 함

    def test_a_batch_that_never_runs_in_the_seven_hour_is_blocked_and_stops_there(self):
        self.works_for = lambda n: False
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('확인용 방', note)
        self.assertEqual(len(self.snaps), 1)
        self.assertNotIn('send', self.names())  # 대조 알림도 안 보냄

    def test_the_control_message_is_sent_by_a_third_person_in_a_young_room(self):
        self.run53()
        sends = [e for e in self.events if isinstance(e, tuple) and e[0] == 'send']
        self.assertEqual(len(sends), 1)
        self.assertEqual(sends[0][1], 'id-3')  # 폰 계정(id-1) · 상대(id-2) 와 다른 대조 계정
        control_room = self.matches()[2]
        self.assertFalse(when(control_room.get('created_at') or at('07:10').isoformat()) < at('07:00'))


class SevenHourFailureTest(Base6):
    """07시대가 중간에 끊겨도 방이 어제 03:00 으로 남지 않는다 — 남으면 08:00 예약 실행이 B 에게 리마인드를 보내고, 시험이 끝난 방이 실계정처럼 알림을 쏜다."""

    def assert_room_not_left_old(self):
        created = when(self.case_match()['created_at'])
        self.assertNotEqual(created, YESTERDAY_THREE)
        self.assertGreater(created, at('07:00'))  # 지금(07시대)으로 되돌아와 있다

    def test_a_sentinel_that_never_closes_still_makes_the_room_young_again(self):
        self.works_for = lambda n: False
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('확인용 방', note)  # 원래 이유가 그대로
        self.assert_room_not_left_old()

    def test_a_gcloud_failure_still_makes_the_room_young_again(self):
        with mock.patch.object(tools, 'batch', side_effect=subprocess.CalledProcessError(1, 'gcloud')):
            result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('호출 실패', note)
        self.assert_room_not_left_old()

    def test_a_failing_rejuvenation_does_not_hide_the_original_blocked(self):
        self.works_for = lambda n: False
        with mock.patch.object(area3_phone6, '_make_young', side_effect=Blocked('matches 바꾸기 500')):
            result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('확인용 방', note)
        self.assertNotIn('500', note)

    def test_a_rejuvenation_that_fails_on_the_pass_path_is_blocked_not_swallowed(self):
        with mock.patch.object(area3_phone6, '_make_young', side_effect=Blocked('matches 바꾸기 500')):
            result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('500', note)  # 08시대를 판정할 수 없는 것이므로 숨기지 않는다
        self.assertEqual(len(self.snaps), 1)

    def test_a_clock_that_passes_zero_eight_during_the_seven_hour_is_blocked_with_the_room_young(self):
        jump = lambda seconds: self.clock.__setitem__(0, at('08:01')) if self.snaps else None  # 첫 배치 뒤의 기다림에서 시계가 튄다
        with mock.patch('time.sleep', side_effect=jump):
            result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('08:00', note)
        self.assertEqual(len(self.snaps), 1)
        self.assertNotIn('send', self.names())  # 07시대 판정도 대조도 안 한다
        self.assertNotEqual(when(self.case_match()['created_at']), YESTERDAY_THREE)

    def test_a_seven_hour_fail_is_kept_in_the_note_when_the_control_never_comes(self):
        self.due = lambda created, now: now - created >= timedelta(hours=24)
        self.quiet_check = False  # 07시대에 리마인드가 와 버리는 서버
        self.drop_control = True  # 그런데 대조 알림은 안 온다
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('대조', note)
        self.assertIn('07시대', note)
        self.assertIn('1건(fail)', note)
        self.assertIn('기대 0', note)  # check.problems 의 실제 글


class EightHourTest(Base6):
    def test_no_reminder_in_the_eight_hour_with_a_live_push_path_is_a_fail(self):
        self.shift = False  # 서버가 밤 이동을 안 한다 — 창이 03:00~04:00 에 머문다
        result, note = self.run53()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('08시대', note)
        self.assertIn('0건', note)
        self.assertEqual([e[0] for e in self.events if isinstance(e, tuple) and e[0] == 'send'], ['send', 'send'])  # 07시대 · 08시대 대조

    def test_no_reminder_and_no_control_in_the_eight_hour_is_blocked_not_a_fail(self):
        self.dead_from = at('08:00')  # 한 시간 놀던 푸시 길이 죽었다
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('08시대', note)
        self.assertIn('07시대', note)  # 07시대 판정을 같이 남긴다

    def test_two_reminders_in_the_eight_hour_is_a_fail(self):
        self.dup = True
        result, note = self.run53()[0]
        self.assertEqual(result, 'fail')
        self.assertIn('2건', note)

    def test_a_batch_that_never_runs_in_the_eight_hour_is_blocked_with_the_seven_hour_result(self):
        self.works_for = lambda n: n == 1
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('확인용 방', note)
        self.assertIn('07시대', note)
        self.assertEqual(len(self.snaps), 2)

    def test_waking_up_after_zero_eight_fifty_five_is_blocked_by_the_gate_with_the_seven_hour_result(self):
        self.jump = at('08:57')
        result, note = self.run53()[0]
        self.assertEqual(result, 'blocked')
        self.assertIn('금지', note)
        self.assertIn('07시대', note)
        self.assertEqual(len(self.snaps), 1)  # 두 번째 gcloud 는 안 불림


class NoRerunTest(Base6):
    def test_a_fail_after_the_batches_is_not_run_again(self):
        self.shift = False
        phone = self.phone()
        first = area1.attempt_phone(self.run_, CASE, phone)
        users, batches = len(self.fake.users), len(self.snaps)
        second = area1.attempt_phone(self.run_, CASE, phone)
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second, first)
        self.assertEqual(len(self.snaps), batches)
        self.assertEqual(len(self.fake.users), users)
        self.assertEqual(len(phone.jobs), 1)

    def phone(self):
        return Phone5(self.events, {'login': {}}, lambda job: [self.put('push_tokens', profile_id=u['id'], token='t') for u in self.fake.users])


class LimitTest(Base6):
    def test_the_phone_case_limit_covers_the_wait_for_the_eight_hour(self):
        wait = 61 * 60  # 07:06 시작 → 08:07
        after = area3_phone5.BATCH_WAIT + area3_phone5.SETTLE + area3_phone5.NOTICE_WAIT + area3_phone5.WATCH_MORE + 30 + 300
        self.assertGreaterEqual(tools.CASE_LIMITS[CASE], wait + 8 * 60 + after)
        self.assertGreater(tools.CASE_LIMITS[CASE], tools.CASE_LIMIT)


class ServerContractTest(unittest.TestCase):
    """이 가설의 전제를 진짜 서버 코드(backend/app/chat/gate.py)에 직접 붙여 둔다 — 서버가 밤 이동 규칙을 바꾸면 여기서 먼저 안다."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(tools.ROOT / 'backend'))
        try:
            from app.chat import gate
        finally:
            sys.path.remove(str(tools.ROOT / 'backend'))
        cls.gate = gate

    def test_yesterday_three_is_reminded_in_the_zero_eight_hour_not_before(self):
        created = area3_phone6._yesterday_three(at('07:10'))
        self.assertEqual(created, YESTERDAY_THREE)
        self.assertEqual(self.gate.reminder_at(created), at('08:00'))
        self.assertFalse(self.gate.needs_reminder(created, at('07:30'), responded=False))
        self.assertTrue(self.gate.needs_reminder(created, at('08:10'), responded=False))
        self.assertFalse(self.gate.needs_reminder(created, at('09:10'), responded=False))
        self.assertGreater(self.gate.remaining(created, at('08:10')).total_seconds(), 0)  # 48시간이 아직 안 지났다

    def test_the_title_and_body_are_the_servers(self):
        text = (tools.ROOT / 'backend' / 'app' / 'chat' / 'batch_router.py').read_text(encoding='utf-8')
        self.assertIn(f'"{TITLE}", "{BODY}"', text)


class RegistryTest(Base6):
    """__main__.py 원문과 Dart 원문을 직접 읽어 등록 줄을 본다(형제 RegistryTest 와 같은 방법)."""

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundle_is_the_one_case_on_the_phone(self):
        self.assertEqual(area3.BUNDLES['area3-phone-6'], [CASE])
        self.assertEqual(list(area3_phone6.PHONE6), [CASE])
        self.assertLessEqual({CASE}, set(area1.PHONE))
        self.assertFalse({CASE} & set(area3.CASES))

    def test_main_imports_the_module_and_runs_the_bundle(self):
        from e2e import __main__ as main
        self.assertRegex((tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'), r'(?m)^from e2e import area3_phone6\b')
        self.assertEqual(main.BUNDLES['area3-phone-6'], [CASE])
        self.assertNotIn(CASE, main.API_CASES)  # 폰 가설이다
        self.assertEqual(main.BUNDLES['area3-phone-5'], area3.BUNDLES['area3-phone-5'])  # 앞 묶음은 그대로

    def test_the_numbers_do_not_collide_with_the_other_bundles(self):
        for name, bundle in area3.BUNDLES.items():
            if name != 'area3-phone-6':
                self.assertNotIn(CASE, bundle, name)

    def test_the_app_part_is_declared_and_merged_into_the_case_map_like_its_siblings(self):
        part = self.dart('area3_b6.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), [CASE])
        main = self.dart('area3.dart')
        self.assertRegex(main, r"(?m)^part 'area3_b6\.dart';")
        merge = re.search(r'(?m)^  \.\.\.area3Cases6,', main)
        self.assertTrue(merge, '...area3Cases6, 줄이 없거나 주석 처리됨')
        self.assertLess(re.search(r'(?m)^  \.\.\.area3Cases5,', main).start(), merge.start())
        self.assertNotIn('area3Cases6', self.dart('e2e_test.dart'))

    def test_the_app_reads_the_phase_and_keys_the_pc_sends(self):
        part = self.dart('area3_b6.dart')
        (_, _), phone = self.run53()
        keys = {key for job in phone.jobs for key in job}
        self.assertEqual(keys, {'token_hash', 'phase'})
        self.assertIn('_homeAfterLogin', part)  # login 판은 홈까지 가는 기존 함수 — 새 앱 로직 없음


if __name__ == '__main__':
    unittest.main()
