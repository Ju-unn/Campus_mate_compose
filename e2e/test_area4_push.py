"""영역 4 PUSH A1(받는 사람 폰 한 대 + 상대 행동은 API) 시험 — 폰 · 운영 없이 가짜 HTTP · 가짜 알림창.
저장소 루트에서 `python -m unittest e2e.test_area4_push`.

가짜 알림창(World): 가설이 부르는 API 에 맞춰 알림이 "뜬다". 뜨지 않으면 안 온 것이다.
"""

import itertools
import unittest
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area4_push, notify, tools
from e2e.test_area1_phone import FakePhone
from e2e.test_area2 import Fake
from e2e.test_area2_phone3 import CaseBase
from e2e.tools import Blocked, Reply

ACCEPT = '대화 신청이 왔어요'
MATCH = '매칭됐어요!'
PUBLIC = '카카오톡 아이디를 주고받았어요'
REVIEW = '새 지인 리뷰가 도착했어요'
TRUST = '카카오톡 아이디·실사진 공개를 수락했어요'
ME, PARTNER, CTL = 'Mina', 'Jiho', 'Ctlx'  # 계정을 만드는 차례 — 받는 사람 · 상대 · 대조 상대


class World:
    """가짜 알림창 — [on] 으로 정한 API 가 불리면 그 알림이 뜬다. 가설이 한 일의 순서는 [log] 에 남는다."""

    def __init__(self):
        self.shade = [notify.Notice('old', '남은 알림', '', 'c')]
        self.rules = []
        self.log = []
        self.callers = []  # (메서드, 경로, 부른 사람의 토큰)
        self._keys = itertools.count()

    def reset(self):
        """제자리 초기화 — patch 된 알림 함수들이 이 객체를 붙들고 있어 새로 만들면 안 된다."""
        self.shade[:] = [notify.Notice('old', '남은 알림', '', 'c')]
        self.rules.clear()
        self.log.clear()
        self.callers.clear()

    def on(self, method, piece, make):
        """[make](body, url) → 알림 목록(Notice 의 (제목, 본문[, 채널]) 튜플)."""
        self.rules.append((method, piece, make))

    def hook(self, method, url, body, headers=None):
        self.callers.append((method, urlsplit(url).path, ((headers or {}).get('Authorization') or '').replace('Bearer ', '')))
        self.log.append(f'{method} {urlsplit(url).path.replace("/rest/v1/", "").lstrip("/")}')
        for want_method, piece, make in self.rules:
            if method == want_method and piece in url:
                for made in make(body, url):
                    channel = made[2] if len(made) > 2 else 'campus_mate_default'
                    self.shade.append(notify.Notice(f'k{next(self._keys)}', made[0], made[1], channel))

    def new(self, before):
        seen = {n.key for n in before}
        return [n for n in self.shade if n.key not in seen]


class WorldFake(Fake):
    def __init__(self, world, rules):
        super().__init__(rules)
        self.world = world

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.world.hook(method, url, body, headers)
        return super().__call__(method, url, headers, body, raw, **options)


class PushBase(CaseBase):
    TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, [{'token': 't'}]))

    def setUp(self):
        super().setUp()
        self.world = World()
        self.reset_names()
        world = self.world
        patches = [
            mock.patch.object(area1, '_nickname', lambda: next(self.names)),
            mock.patch.object(notify, 'require_daytime', lambda now=None: None),
            mock.patch.object(notify, 'ensure_delivery', lambda s: self.delivery.append((s, len(self.phone.jobs)))),  # 푸시 연결 점검 — 실제 adb 는 불리지 않는다
            mock.patch.object(notify, 'grant_notifications', lambda s: world.log.append('grant')),
            mock.patch.object(notify, 'revoke_notifications', lambda s: world.log.append('revoke')),
            mock.patch.object(notify, 'background', lambda s: world.log.append('background')),
            mock.patch.object(notify, 'read_notifications', lambda s: world.log.append('read') or list(world.shade)),
            mock.patch.object(notify, 'wait_new', lambda s, before, count=1, seconds=0, match=None: world.new(before)),
            mock.patch.object(notify, 'expect_none', lambda s, before, seconds=0: world.new(before)),
            mock.patch.object(area4_push.time, 'monotonic', side_effect=itertools.count()),
        ]
        for patcher in patches:
            patcher.start()
            self.addCleanup(patcher.stop)

    def reset_names(self):
        self.delivery = []  # (시리얼, 그때까지 앱이 받은 일감 수)
        self.names = itertools.chain([ME, PARTNER, CTL], (f'Ex{i}' for i in itertools.count()))  # 계정을 만드는 차례 — 받는 사람 · 상대 · 대조 상대

    def go_push(self, case, rules=(), phone=None):
        self.reset_names()
        tokens = itertools.count(1)
        created = [('POST', '/auth/v1/verify', lambda b, u: Reply(200, {'access_token': f'tok-{next(tokens)}'})),
                   ('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'})),
                   ('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'})), ('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r'}))]
        fake = WorldFake(self.world, [*rules, self.TOKEN, *created])  # 가설이 정한 응답이 먼저, 없으면 서버가 만들어 준 것(201)
        for patcher in (mock.patch.object(tools, 'call', fake), mock.patch.object(area4_push.time, 'sleep', lambda s: None)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake = fake
        self.phone = phone or FakePhone()
        self.phone.serial = 'S'
        return area1.attempt_phone(self.run, case, self.phone)

    def control_arrives(self):
        """대조 — 상대가 메시지를 보내면 그 글이 알림으로 뜬다."""
        self.world.on('POST', '/messages', lambda b, u: [(CTL, b['body'])])

    def index(self, prefix):
        return next(i for i, line in enumerate(self.world.log) if line.startswith(prefix))

    def last(self, prefix):
        return max(i for i, line in enumerate(self.world.log) if line.startswith(prefix))

    def card_id(self):
        return self.fake.bodies('POST', 'daily_cards')[0][0]['id']


class AcceptTest(PushBase):
    BODY = f'{PARTNER} 님이 대화를 신청했어요'

    def test_10_the_accept_notification_arrives_and_the_phone_went_to_the_back_first(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, self.BODY)] if b == {'decision': 'accept'} else [])
        result = self.go_push('E-PUSH-10')
        self.assertEqual(result[0], 'pass', result)
        log = self.world.log
        # 폰: 홈까지 → HOME → 앞 알림을 읽어 두고(새것만 보려고) → 상대가 수락
        self.assertTrue(self.index('background') < self.index('read') < self.index('POST cards/'), log)
        self.assertIn('token_hash', self.phone.jobs[0])
        self.assertEqual(self.fake.bodies('POST', '/decision'), [{'decision': 'accept'}])

    def test_10_other_words_are_a_fail_that_names_what_arrived(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, '다른 님이 대화를 신청했어요')])
        result = self.go_push('E-PUSH-10')
        self.assertEqual(result[0], 'fail')
        self.assertIn('다른 님이', result[1])

    def test_10_no_notification_is_a_fail(self):
        self.assertEqual(self.go_push('E-PUSH-10')[0], 'fail')

    def test_10_two_of_the_same_notification_is_a_fail(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, self.BODY)] * 2)
        result = self.go_push('E-PUSH-10')
        self.assertEqual(result[0], 'fail')
        self.assertIn('2', result[1])

    def test_a_phone_that_never_reaches_home_does_not_go_on_to_call_the_partner(self):
        phone = FakePhone()
        phone.answers = [{'result': 'fail', 'note': '홈 못 감'}]
        result = self.go_push('E-PUSH-10', phone=phone)
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.fake.bodies('POST', '/decision'), [])

    def test_17_the_owner_on_the_phone_gets_the_match_notification_when_the_target_accepts_back(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')])
        rules = [('GET', 'matches?', lambda b, u: Reply(200, [{'id': 'm1'}]))]
        result = self.go_push('E-PUSH-17', rules)
        self.assertEqual(result[0], 'pass', result)

    def test_17_a_second_copy_of_the_match_notification_is_a_fail(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')] * 2)
        rules = [('GET', 'matches?', lambda b, u: Reply(200, [{'id': 'm1'}]))]
        self.assertEqual(self.go_push('E-PUSH-17', rules)[0], 'fail')

    def test_17_a_match_row_count_other_than_one_is_a_fail(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')])
        self.assertEqual(self.go_push('E-PUSH-17', [('GET', 'matches?', lambda b, u: Reply(200, []))])[0], 'fail')

    def test_17_not_matched_is_a_fail_even_if_the_notification_came(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')])
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': False}))]
        self.assertEqual(self.go_push('E-PUSH-17', rules)[0], 'fail')

    def test_18_the_target_accepting_back_gets_the_start_a_chat_notification(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님과 대화를 시작해 보세요')])
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'}))]
        result = self.go_push('E-PUSH-18', rules)
        self.assertEqual(result[0], 'pass', result)
        # 폰 계정이 직접 받은 수락을 수락한다 — 앞서 온 "대화 신청이 왔어요" 알림은 이 가설의 판정에 들어가지 않는다
        self.assertEqual(self.fake.bodies('POST', '/cards/acceptances/'), [{'decision': 'accept'}])

    def test_21_two_directions_still_give_one_match_notification_and_one_match(self):
        def make(body, url):
            return [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')] if not self.fake.bodies('POST', '/cards/acceptances/') else []
        self.world.on('POST', '/cards/acceptances/', make)
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'})),
                 ('GET', 'matches?', lambda b, u: Reply(200, [{'id': 'm1'}]))]
        result = self.go_push('E-PUSH-21', rules)
        self.assertEqual(result[0], 'pass', result)

    def test_21_a_second_match_notification_is_a_fail(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')])
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'})),
                 ('GET', 'matches?', lambda b, u: Reply(200, [{'id': 'm1'}]))]
        self.assertEqual(self.go_push('E-PUSH-21', rules)[0], 'fail')


class SilentTest(PushBase):
    def test_12_a_reject_sends_nothing_and_then_a_control_notification_proves_the_path_is_alive(self):
        self.control_arrives()
        rules = [('GET', 'card_decisions', lambda b, u: Reply(200, [{'decision': 'reject'}]))]
        result = self.go_push('E-PUSH-12', rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('POST', '/decision'), [{'decision': 'reject'}])
        self.assertTrue(self.index('POST cards/') < self.index('POST chat/'), self.world.log)  # 안 옴을 본 "뒤에" 대조

    def test_12_a_notification_after_a_reject_is_a_fail_and_needs_no_control(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, '누군가')])
        self.control_arrives()
        result = self.go_push('E-PUSH-12', [('GET', 'card_decisions', lambda b, u: Reply(200, [{'decision': 'reject'}]))])
        self.assertEqual(result[0], 'fail')
        self.assertEqual(self.fake.bodies('POST', '/messages'), [])

    def test_12_a_control_that_never_arrives_is_blocked_not_a_pass(self):
        # 대조 알림도 안 오면 "안 옴" 은 아무것도 증명하지 못한다(파서 · 토큰 · FCM 이 죽어 있을 수 있다)
        result = self.go_push('E-PUSH-12', [('GET', 'card_decisions', lambda b, u: Reply(200, [{'decision': 'reject'}]))])
        self.assertEqual(result[0], 'blocked', result)

    def test_12_no_reject_row_is_a_fail(self):
        self.control_arrives()
        self.assertEqual(self.go_push('E-PUSH-12', [('GET', 'card_decisions', lambda b, u: Reply(200, []))])[0], 'fail')

    def test_13_the_switch_is_turned_off_before_the_partner_accepts(self):
        self.control_arrives()
        result = self.go_push('E-PUSH-13', [('GET', '/cards/acceptances', lambda b, u: Reply(200, {'acceptances': [{'card_id': self.card_id()}]}))])
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'acceptance_received': False}])
        self.assertTrue(self.index('PATCH cards/') < self.index('POST cards/'), self.world.log)

    def test_13_an_accept_that_is_missing_from_the_list_is_a_fail(self):
        self.control_arrives()
        result = self.go_push('E-PUSH-13', [('GET', '/cards/acceptances', lambda b, u: Reply(200, {'acceptances': []}))])
        self.assertEqual(result[0], 'fail')

    def test_22_only_the_match_notification_is_watched_and_the_off_switch_is_set_first(self):
        self.control_arrives()
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(ACCEPT, '무관한 다른 알림')])  # 매칭 알림이 아니면 이 가설의 몫이 아니다
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'}))]
        result = self.go_push('E-PUSH-22', rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'match_made': False}])

    def test_22_a_match_notification_with_the_switch_off_is_a_fail(self):
        self.world.on('POST', '/cards/acceptances/', lambda b, u: [(MATCH, f'{PARTNER} 님이 신청을 수락했어요.')])
        rules = [('POST', '/cards/acceptances/', lambda b, u: Reply(200, {'matched': True, 'match_id': 'm1'}))]
        self.assertEqual(self.go_push('E-PUSH-22', rules)[0], 'fail')

    def test_32_new_message_off_means_no_message_notification_and_the_control_is_an_accept(self):
        # 새 메시지 스위치를 껐으니 메시지로는 대조할 수 없다 — 수락 알림으로 대조한다
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{CTL} 님이 대화를 신청했어요')])
        result = self.go_push('E-PUSH-32', [('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'}))])
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'new_message': False}])
        self.assertEqual(len(self.fake.bodies('POST', '/messages')), 1)  # 대조가 아니라 시험 본 메시지 하나

    def test_32_a_message_notification_with_the_switch_off_is_a_fail(self):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'])])
        self.assertEqual(self.go_push('E-PUSH-32', [('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'}))])[0], 'fail')

    def test_34_after_the_receiver_leaves_the_send_is_409_and_nothing_comes(self):
        self.control_arrives()
        rules = [('POST', '/leave', lambda b, u: Reply(200, {'ok': True})),
                 ('POST', '/messages', lambda b, u: Reply(409, {'detail': '이미 나간 대화예요'}) if len(self.fake.bodies('POST', '/messages')) == 1 else Reply(201, {'id': 'x'}))]
        result = self.go_push('E-PUSH-34', rules)
        self.assertEqual(result[0], 'pass', result)

    def test_34_a_send_that_goes_through_is_a_fail(self):
        self.control_arrives()
        rules = [('POST', '/leave', lambda b, u: Reply(200, {'ok': True})), ('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'}))]
        self.assertEqual(self.go_push('E-PUSH-34', rules)[0], 'fail')

    def test_36_trust_accept_with_new_message_off_is_silent_and_the_control_is_an_accept(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{CTL} 님이 대화를 신청했어요')])
        result = self.go_push('E-PUSH-36')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'new_message': False}])
        self.assertEqual(len(self.fake.bodies('POST', '/trust')), 1)

    def test_51_review_with_the_switch_off_is_saved_and_silent(self):
        self.control_arrives()
        rules = [('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r1'})),
                 ('GET', 'friend_reviews', lambda b, u: Reply(200, [{'id': 'r1'}]))]
        result = self.go_push('E-PUSH-51', rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'new_friend_review': False}])

    def test_39_the_public_notification_is_silent_while_the_message_notification_still_comes(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST)])  # 새 메시지 알림은 온다 — 그게 대조를 겸한다
        result = self.go_push('E-PUSH-39')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'match_made': False}])

    def test_39_a_public_notification_with_the_switch_off_is_a_fail(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST), (PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')])
        self.assertEqual(self.go_push('E-PUSH-39')[0], 'fail')

    def test_39_without_the_message_notification_nothing_proves_the_path_so_it_is_blocked(self):
        self.assertEqual(self.go_push('E-PUSH-39')[0], 'blocked')

    def test_70_a_suspended_receiver_gets_nothing_and_the_path_was_proven_before_the_suspension(self):
        self.suspended = False

        def suspend(body, url):
            if body == {'status': 'suspended'}:
                self.suspended = True
            return []
        self.world.on('PATCH', '/rest/v1/profiles', suspend)
        self.world.on('POST', '/messages', lambda b, u: [] if self.suspended else [(CTL, b['body'])])  # 대조는 정지 전에만 뜬다
        rules = [('POST', '/messages', lambda b, u: Reply(409, {'detail': 'x'}) if self.suspended else Reply(201, {'id': 'x'})),
                 ('POST', '/friend-reviews', lambda b, u: Reply(404, {'detail': 'x'}))]
        result = self.go_push('E-PUSH-70', rules)
        self.assertEqual(result[0], 'pass', result)
        # 대조 알림 → 정지 → 상대 행동 순서 — 정지 뒤에는 대조 알림도 못 받으니 정지 "전에" 길을 증명해야 한다
        self.assertTrue(self.index('POST chat/') < self.last('PATCH profiles'), self.world.log)
        self.assertEqual(self.fake.bodies('PATCH', '/rest/v1/profiles')[-1], {'status': 'suspended'})

    def test_70_a_review_or_message_that_goes_through_to_a_suspended_account_is_a_fail(self):
        self.control_arrives()
        rules = [('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'})), ('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r'}))]
        self.assertEqual(self.go_push('E-PUSH-70', rules)[0], 'fail')


class MessageTest(PushBase):
    def run_message(self, case, body_notice, **kw):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, body_notice(b['body']))])
        return self.go_push(case, [('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'}))], **kw)

    def test_24_the_message_text_is_the_notification_body_under_the_senders_nickname(self):
        result = self.run_message('E-PUSH-24', lambda body: body)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('POST', '/messages')[0]['body'], '안녕하세요')

    def test_25_a_45_character_message_is_cut_to_the_first_40(self):
        result = self.run_message('E-PUSH-25', lambda body: body[:40])
        self.assertEqual(result[0], 'pass', result)
        sent = self.fake.bodies('POST', '/messages')[0]['body']
        self.assertEqual(len(sent), 45)

    def test_25_an_uncut_body_is_a_fail(self):
        self.assertEqual(self.run_message('E-PUSH-25', lambda body: body)[0], 'fail')

    def test_26_a_line_break_becomes_a_space(self):
        result = self.run_message('E-PUSH-26', lambda body: body.replace('\n', ' '))
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('POST', '/messages')[0]['body'], '첫줄\n둘째줄')

    def test_26_a_line_break_kept_is_a_fail(self):
        self.assertEqual(self.run_message('E-PUSH-26', lambda body: body)[0], 'fail')

    def test_a_second_copy_of_the_same_notification_is_a_fail(self):
        saved = [('GET', 'friend_reviews', lambda b, u: Reply(200, [{'id': 'r1'}]))]  # 중복 말고는 어긋남이 없게 — 저장된 리뷰 1행
        for case, route, notice, rules in (('E-PUSH-24', '/messages', (PARTNER, '안녕하세요'), []), ('E-PUSH-35', '/trust', (PARTNER, TRUST), []),
                                           ('E-PUSH-18', '/cards/acceptances/', (MATCH, f'{PARTNER} 님과 대화를 시작해 보세요'), []),
                                           ('E-PUSH-49', '/friend-reviews', (REVIEW, f'{PARTNER} 님이 리뷰를 남겼어요'), saved)):
            with self.subTest(case=case):
                self.world.reset()
                self.world.on('POST', route, lambda b, u, notice=notice: [notice] * 2)
                result = self.go_push(case, rules)
                self.assertEqual(result[0], 'fail')
                self.assertIn('2개', result[1])

    def test_35_the_trust_accept_arrives_as_a_message_under_the_partners_nickname(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST)])
        self.assertEqual(self.go_push('E-PUSH-35')[0], 'pass')

    def test_37_when_both_accept_the_phone_gets_the_public_notification_and_the_trust_row_is_stamped(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST), (PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')]
                      if len(self.fake.bodies('POST', '/trust')) == 1 else [])
        result = self.go_push('E-PUSH-37', [('GET', 'matches?', lambda b, u: Reply(200, [{'trust_passed_at': '2026-10-05T03:00:00+00:00'}]))])
        self.assertEqual(result[0], 'pass', result)

    def test_37_an_unstamped_trust_row_is_a_fail(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST), (PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')])
        result = self.go_push('E-PUSH-37', [('GET', 'matches?', lambda b, u: Reply(200, [{'trust_passed_at': None}]))])
        self.assertEqual(result[0], 'fail')


class ReviewTest(PushBase):
    def test_49_a_linked_friends_review_arrives_and_the_row_is_saved(self):
        self.world.on('POST', '/friend-reviews', lambda b, u: [(REVIEW, f'{PARTNER} 님이 리뷰를 남겼어요')])
        rules = [('POST', '/friend-reviews', lambda b, u: Reply(201, {'id': 'r1'})), ('GET', 'friend_reviews', lambda b, u: Reply(200, [{'id': 'r1'}]))]
        result = self.go_push('E-PUSH-49', rules)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual([p for m, p, _ in self.fake.calls if p == '/rest/v1/referrals'], ['/rest/v1/referrals'])


class RoleTest(PushBase):
    """누가 부르는지 — 폰 계정은 tok-1, 상대는 tok-2(대조 상대는 tok-3). 가짜 알림창은 주소로만 반응해 방향이 뒤집혀도 모르니 토큰으로 고정한다."""
    ME, PARTNER_ = 'tok-1', 'tok-2'

    def callers(self, case, method, piece):
        self.world.reset()
        self.go_push(case)
        return [who for m, path, who in self.world.callers if m == method and piece in path]

    def test_who_decides_and_who_accepts_back(self):
        want = {'E-PUSH-10': ([self.PARTNER_], []), 'E-PUSH-12': ([self.PARTNER_], []), 'E-PUSH-13': ([self.PARTNER_], []),
                'E-PUSH-17': ([self.ME], [self.PARTNER_]), 'E-PUSH-18': ([self.PARTNER_], [self.ME]),
                'E-PUSH-21': ([self.ME, self.PARTNER_], [self.PARTNER_, self.ME]), 'E-PUSH-22': ([self.ME], [self.PARTNER_])}
        for case, (decisions, backs) in want.items():
            with self.subTest(case=case):
                self.world.reset()
                self.go_push(case)
                got = lambda piece: [who for m, path, who in self.world.callers if m == 'POST' and piece in path and who in (self.ME, self.PARTNER_)]
                self.assertEqual(got('/decision'), decisions)
                self.assertEqual(got('/cards/acceptances/'), backs)

    def test_who_sends_leaves_trusts_and_reviews(self):
        for case, piece, who in (('E-PUSH-24', '/messages', [self.PARTNER_]), ('E-PUSH-25', '/messages', [self.PARTNER_]),
                                 ('E-PUSH-26', '/messages', [self.PARTNER_]), ('E-PUSH-32', '/messages', [self.PARTNER_]),
                                 ('E-PUSH-34', '/leave', [self.ME]), ('E-PUSH-35', '/trust', [self.PARTNER_]),
                                 ('E-PUSH-36', '/trust', [self.PARTNER_]), ('E-PUSH-37', '/trust', [self.ME, self.PARTNER_]),
                                 ('E-PUSH-39', '/trust', [self.ME, self.PARTNER_]), ('E-PUSH-49', '/friend-reviews', [self.PARTNER_]),
                                 ('E-PUSH-51', '/friend-reviews', [self.PARTNER_])):
            with self.subTest(case=case):
                got = [w for w in self.callers(case, 'POST', piece) if w in (self.ME, self.PARTNER_)]
                self.assertEqual(got, who)

    def test_34_the_first_send_after_leaving_is_the_partners(self):
        sends = self.callers('E-PUSH-34', 'POST', '/messages')
        self.assertEqual(sends[0], self.PARTNER_)


class WiringTest(PushBase):
    def test_the_push_connection_is_checked_once_per_case_before_the_app_is_started(self):
        self.go_push('E-PUSH-10')
        self.assertEqual(self.delivery, [('S', 0)])  # 앱 일감이 0개일 때 — 앱을 켜기 전

    def test_at_night_it_is_blocked_before_the_phone_is_called(self):
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))):
            result = self.go_push('E-PUSH-10')
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.phone.jobs, [])
        self.assertEqual(self.fake.users, [])

    def test_no_device_token_blocks_before_the_partner_acts(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        result = self.go_push('E-PUSH-10')
        self.assertEqual(result[0], 'blocked', result)
        self.assertEqual(self.fake.bodies('POST', '/decision'), [])

    def test_the_notification_permission_is_given_before_the_app_starts_and_taken_back_even_when_blocked(self):
        self.TOKEN = ('GET', 'push_tokens', lambda b, u: Reply(200, []))
        self.go_push('E-PUSH-10')
        self.assertEqual(self.world.log[0], 'grant')
        self.assertEqual(self.world.log[-1], 'revoke')

    def test_the_friend_signup_case_is_the_existing_referral_case(self):
        from e2e import area2_phone3
        self.assertIs(area1.PHONE['E-PUSH-54'].__wrapped__, area2_phone3.p_ref_18)  # 알림 권한만 미리 주는 껍질


class ChannelTest(PushBase):
    DUMP = ("  Notification channels:\n    NotificationChannel{mId='campus_mate_default', mName=CampusMate 알림, mImportance=%s}\n"
            "    NotificationChannel{mId='miscellaneous', mName=기타, mImportance=3}\n")

    def go_channel(self, channel, importance=4, dump=None):
        self.world.on('POST', '/messages', lambda b, u: [(PARTNER, b['body'], channel)])
        text = self.DUMP % importance if dump is None else dump
        with mock.patch.object(tools, 'adb', return_value=text):
            return self.go_push('E-PUSH-74', [('POST', '/messages', lambda b, u: Reply(201, {'id': 'x'}))])

    def test_74_the_app_made_channel_with_high_importance_passes(self):
        self.assertEqual(self.go_channel('campus_mate_default')[0], 'pass')

    def test_74_the_fcm_fallback_channel_is_the_regression_and_a_fail(self):
        result = self.go_channel('fcm_fallback_notification_channel')
        self.assertEqual(result[0], 'fail')
        self.assertIn('fcm_fallback_notification_channel', result[1])

    def test_74_a_channel_with_the_wrong_importance_is_a_fail(self):
        self.assertEqual(self.go_channel('campus_mate_default', importance=3)[0], 'fail')

    def test_74_a_dump_shape_that_hides_the_channel_list_is_blocked_for_a_human_not_a_pass(self):
        result = self.go_channel('campus_mate_default', dump='아무 모양')
        self.assertEqual(result[0], 'blocked')
        self.assertIn('채널 목록', result[1])
        self.assertIn(area4_push.CHANNEL, result[1])  # 알림이 들어간 채널 id 는 맞았다는 것도 남긴다

    def test_74_the_wrong_channel_is_a_fail_even_when_the_list_cannot_be_read(self):
        self.assertEqual(self.go_channel('fcm_fallback_notification_channel', dump='아무 모양')[0], 'fail')


class RegistryTest(unittest.TestCase):
    A1 = ('10 12 13 17 18 21 22 24 25 26 32 34 35 36 37 39 49 51 54 70 74').split()

    def test_the_bundle_is_the_21_a1_cases_and_each_is_a_phone_case(self):
        ids = [f'E-PUSH-{n}' for n in self.A1]
        self.assertEqual(area1.BUNDLES['area4-push-a1'], ids)
        for case in ids:
            self.assertIn(case, area1.PHONE)

    def test_the_slow_cases_get_a_longer_limit_than_the_default(self):
        for case in ('E-PUSH-12', 'E-PUSH-39', 'E-PUSH-70'):
            self.assertGreater(tools.CASE_LIMITS[case], tools.CASE_LIMIT)


if __name__ == '__main__':
    unittest.main()
