"""E-SAFE-53("정지 계정에는 어떤 알림도 가지 않는다")의 PC 쪽 시험 — 폰 · 운영 · gcloud 없이 가짜 앱 · 가짜 서버 · 가짜 배치로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_safe_notice`.

바탕은 test_area3_phone5.py 의 Base5(가짜 폰 · notify · 시계 · gcloud · 배치 관문 기록)다. 여기에 알림 길을 더한다 — 가짜 서버가 메시지를 받으면
받는 사람이 정지가 아닐 때만 id-1(폰 계정)에게 알림이 간다(chat/router.py `_notify_message` → cards/push.py `notify`). 배치도 정지 방은 건너뛴다
(chat/batch_router.py `gate.is_gone`). 계정은 만든 순서대로 id-1(폰 계정 = 정지당하는 쪽 A) · id-2(상대 B) · id-3 · id-4(확인용 방).
"""

import unittest
from datetime import timedelta
from unittest import mock

from e2e import area1, area3_safe_phone, notify
from e2e.test_area3_phone5 import Base5, TITLE, at
from e2e.tools import Reply

CASE = 'E-SAFE-53'


class Notice53(Base5):
    def setUp(self):
        super().setUp()
        self.delivered = []  # 폰 계정(id-1)에 도착한 알림 — 폰 알림 목록 대신
        self.leak_message = False  # 정지 계정에도 메시지 알림을 보내는 서버(변이)
        self.leak_gate = False  # 정지 방도 리마인드하는 배치(변이)
        self.deliver = True  # 폰에 알림이 도착하는가(FCM · 토큰 문제를 흉내)
        self.ignore = lambda match: not self.leak_gate and any(self.suspended(p['profile_id']) for p in self.parts(match['id']))
        for name, fake in (('read_notifications', lambda s: self.events.append(('read', s)) or [*self.old, *self.delivered]),
                           ('ensure_delivery', lambda s: self.events.append('ensure'))):
            patcher = mock.patch.object(notify, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake.on('POST', r'/friend-reviews', self.review)
        self.fake.on('GET', r'/rest/v1/profiles', self.profile_row)
        self.profile_status = 'active'  # 폰 계정(id-1)이 정지 전에 가진 상태 — 계정 공장은 홈까지 끝낸 active 계정을 만든다

    def profile_row(self, sent):
        who = sent['query']['id'][3:]
        return Reply(200, [{'id': who, 'status': self.fake.statuses.get(who) or (self.profile_status if who == 'id-1' else 'active')}])

    def nick(self, who):
        """만든 순서대로(id-1 · id-2 …) 04-1 에 보낸 닉네임 — 알림 제목은 보낸 사람의 닉네임이다."""
        return [s['body']['nickname'] for s in self.fake.by('POST', '/profile-onboarding/basic-info')][int(who.removeprefix('id-')) - 1]

    def suspended(self, who):
        return self.fake.statuses.get(who) == 'suspended'

    def suspended_ids(self):
        return sorted(who for who, status in self.fake.statuses.items() if status == 'suspended')

    def post_message(self, sent):
        match, sender = self.match_of(sent), self.user_of(sent)
        other = next(p['profile_id'] for p in self.parts(match['id']) if p['profile_id'] != sender)
        stamp = 'suspended' if self.suspended(other) else 'active'
        if stamp == 'suspended' and not self.leak_message:
            self.events.append(('send', sender, sent['body']['body'], stamp))
            return Reply(409, {'detail': '상대가 대화를 나갔어요'})
        reply = super().post_message(sent)
        self.events[-1] = ('send', sender, sent['body']['body'], stamp)
        if reply[0] == 201 and other == 'id-1' and self.deliver and (stamp == 'active' or self.leak_message):
            self.delivered.append(notify.Notice(f'm{len(self.delivered)}', self.nick(sender), sent['body']['body'], 'c'))
        return reply

    def review(self, sent):
        target = sent['body']['reviewee_id']
        self.events.append(('review', self.user_of(sent), target))
        return Reply(404, {'detail': '프로필을 찾을 수 없어요'}) if self.suspended(target) else Reply(201, {'id': 'r'})

    def fresh(self, before):
        seen = {n.key for n in before}
        return [n for n in self.delivered if n.key not in seen]

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        self.events.append(('wait_new', seconds))
        return self.fresh(before) + self.notices()

    def expect_none(self, serial, before, seconds=0):
        self.events.append(('expect_none', seconds))
        return self.fresh(before) + self.notices()

    def run53(self):
        (result, note), phone = self.go(CASE, {'login': {}})
        return result, note, phone

    def named(self):
        return [e if isinstance(e, str) else e[0] for e in self.events]


class PassPathTest(Notice53):
    def test_the_control_arrives_then_the_account_is_suspended_then_nothing_comes_through_a_message_a_review_and_a_batch(self):
        result, note, phone = self.run53()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'phase': 'login'}])
        sends = [e for e in self.events if e[0] == 'send']
        self.assertEqual([(e[1], e[3]) for e in sends], [('id-2', 'active'), ('id-2', 'suspended')])  # 대조(정지 전) → 정지 뒤 시도
        self.assertEqual(self.statuses_of(), 'suspended')
        names = self.named()
        order = [names.index(n) for n in ('app', 'read', 'kill', 'send', 'wait_new', 'review', 'gcloud', 'expect_none')]
        self.assertEqual(order, sorted(order))  # 앱 로그인 → 알림 목록 · 앱 죽임 → 대조 보내기 → 대조 도착 → 정지 뒤 시도 → 배치 → 0건 지켜보기
        self.assertEqual(self.events.count(('gcloud', 'chat-gate')), 1)
        self.assertEqual(self.events.count(('wait_new', 60)), 1)
        self.assertIn(('expect_none', 60), self.events)
        self.assertEqual(self.fake.count('friend_reviews'), 0)  # 리뷰는 404 라 행이 안 생겼다
        self.assertIn('ensure', names)  # 푸시 연결 점검을 시작 때 한 번
        self.assertAge(self.target(), timedelta(hours=24, minutes=5))  # 정지 방도 리마인드 창에 둔다 — 정지만 아니면 알림이 갔을 방

    def statuses_of(self):
        return self.fake.statuses.get('id-1')

    def test_a_phone_account_that_is_not_active_before_the_suspension_is_blocked_before_the_suspension_and_the_batch(self):
        """리뷰 404 · 메시지 409 가 "정지 때문" 이라는 증거가 되려면 A 가 정지 전에 active 여야 한다 — 아니면 거짓 통과를 막는다."""
        self.profile_status = 'pending'
        result, note, _ = self.run53()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('active', note)
        self.assertEqual(self.suspended_ids(), [])
        self.assertNotIn('gcloud', self.named())
        self.assertEqual([e for e in self.events if isinstance(e, tuple) and e[0] == 'review'], [])

    def test_the_suspended_phone_account_is_the_only_one_suspended_and_never_the_partner(self):
        self.run53()
        self.assertEqual(self.suspended_ids(), ['id-1'])


class MutantTest(Notice53):
    def test_a_server_that_pushes_a_message_to_a_suspended_account_is_a_fail(self):
        self.leak_message = True
        result, note, _ = self.run53()
        self.assertEqual(result, 'fail')
        self.assertIn('알림이', note)
        self.assertIn('메시지', note)  # 메시지가 받아들여졌다는 것도 같이 잡힌다

    def test_a_batch_that_reminds_a_suspended_room_is_a_fail(self):
        self.leak_gate = True
        result, note, _ = self.run53()
        self.assertEqual(result, 'fail')
        self.assertIn(TITLE, note)

    def test_a_control_that_never_arrives_is_blocked_before_the_suspension_and_before_the_batch(self):
        self.deliver = False
        result, note, _ = self.run53()
        self.assertEqual(result, 'blocked')
        self.assertIn('대조', note)
        self.assertEqual(self.suspended_ids(), [])  # 정지를 걸기 전에 멈췄다
        self.assertNotIn('gcloud', self.named())

    def test_a_batch_that_never_runs_is_blocked_not_a_pass(self):
        self.batch_works = False
        result, note, _ = self.run53()
        self.assertEqual(result, 'blocked')
        self.assertIn('확인용 방', note)

    def test_a_silent_app_stops_before_the_suspension(self):
        (result, note), _ = self.go(CASE, {'login': {}}, tokens=0, on_app=None)
        self.assertEqual(result, 'blocked')  # 기기 토큰이 안 올라옴
        self.assertEqual(self.suspended_ids(), [])


class GateTest(Notice53):
    """chat-gate 를 부르는 가설이라 시각 관문 규칙을 그대로 지킨다(test_area3_phone5.ChatGateCommon 과 같은 것을 이 가설로)."""

    def test_the_gate_closing_after_the_preparation_blocks_with_zero_gcloud_calls_and_zero_moved_times(self):
        real = area3_safe_phone._sentinel
        with mock.patch.object(area3_safe_phone, '_sentinel', lambda run: (real(run), self.clock.__setitem__(0, at('14:57')))[0]):
            result, note, _ = self.run53()
        self.assertEqual(result, 'blocked')
        self.assertIn('15:06', note)
        self.assertNotIn('gcloud', self.named())
        self.assertTrue(all('created_at' not in m for m in self.fake.tables['matches']))

    def test_a_second_chat_gate_in_the_same_hour_is_blocked_before_any_account_is_made(self):
        from e2e import batch_gate
        batch_gate.HISTORY.write_text(at('14:10').isoformat() + chr(10), encoding='utf-8')
        result, note, _ = self.run53()
        self.assertEqual((result, self.fake.users), ('blocked', []))
        self.assertIn('15:06', note)

    def test_a_night_hour_is_blocked_before_any_account_is_made(self):
        self.clock[0] = at('23:10')
        result, note, _ = self.run53()
        self.assertEqual((result, self.fake.users), ('blocked', []))
        self.assertNotIn('gcloud', self.named())

    def test_a_closed_minute_inside_the_preparation_time_is_blocked_before_any_account_is_made(self):
        self.clock[0] = at('14:50')
        result, note, _ = self.run53()
        self.assertEqual((result, self.fake.users), ('blocked', []))
        self.assertIn('8분 뒤', note)

    def test_the_batch_never_touches_an_account_this_run_did_not_make(self):
        with mock.patch('e2e.area2._mine', lambda run: set()):
            result, note, _ = self.run53()
        self.assertEqual(result, 'blocked')
        self.assertNotIn('gcloud', self.named())


class SingleShotTest(Notice53):
    def test_a_fail_after_the_batch_is_remembered_and_not_rerun(self):
        self.leak_gate = True
        first = self.run53()[:2]
        calls, apps = self.events.count(('gcloud', 'chat-gate')), self.names().count('app')
        second = self.run53()[:2]
        self.assertEqual((first[0], second), ('fail', first))
        self.assertEqual(self.fake.users, [])  # 둘째는 계정을 안 만들었다(시험 틀이 먼저 비웠다)
        self.assertEqual(self.names().count('app'), apps)  # 앱도 안 켰다
        self.assertEqual(self.events.count(('gcloud', 'chat-gate')), calls)

    def test_the_case_is_registered_with_a_long_limit_and_in_the_bundle(self):
        from e2e import area3, tools
        self.assertIn(CASE, area1.PHONE)
        self.assertIn(CASE, area3.BUNDLES['area3-safe-phone'])
        self.assertGreaterEqual(tools.CASE_LIMITS[CASE], 900)


if __name__ == '__main__':
    unittest.main()
