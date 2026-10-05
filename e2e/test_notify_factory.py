"""알림 공장(`e2e/notify_factory.py`)의 시험 — 운영 대신 가짜 서버. `python -m unittest e2e.test_notify_factory`."""
import json
from unittest import mock
from urllib.parse import urlsplit

from e2e import notify_factory as factory
from e2e import tools
from e2e.test_area1 import Base, FakeServer
from e2e.tools import Blocked, Reply

A = {'id': 'id-a', 'token': 'tok-a'}
B = {'id': 'id-b', 'token': 'tok-b'}
STRANGER = {'id': 'id-x', 'token': 'tok-x'}


class Recorder(FakeServer):
    """누가(Authorization) 무엇을 불렀는지까지 남긴다."""

    def __init__(self, routes=None):
        super().__init__(routes)
        self.bearers = []

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.bearers.append((headers or {}).get('Authorization'))
        return super().__call__(method, url, headers, body, raw)


class FactoryTest(Base):
    def setUp(self):
        super().setUp()
        self.run.out.mkdir(parents=True, exist_ok=True)
        (self.run.out / 'accounts.json').write_text(json.dumps([A, B]), encoding='utf-8')

    def serve(self, routes=None):
        fake = Recorder(routes)
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    def paths(self, fake):
        return [(m, p) for m, p, _ in fake.calls]

    # ── 계정 ──
    def test_pair_makes_two_home_accounts(self):
        made = []
        self.run.account = lambda stage, **kw: made.append(stage) or {'id': f'n{len(made)}', 'token': 't'}
        receiver, sender = factory.pair(self.run)
        self.assertEqual(made, ['home', 'home'])
        self.assertNotEqual(receiver['id'], sender['id'])

    # ── 카드 · 수락 ──
    def test_card_inserts_a_live_card_from_owner_to_target_and_returns_its_id(self):
        fake = self.serve()
        card_id = factory.card(self.run, A, B)
        method, path, body = fake.calls[0]
        self.assertEqual((method, path), ('POST', '/rest/v1/daily_cards'))
        self.assertEqual((body[0]['id'], body[0]['owner_id'], body[0]['target_id']), (card_id, 'id-a', 'id-b'))
        self.assertTrue(body[0]['expires_at'])

    def test_card_refuses_an_account_this_run_did_not_make(self):
        fake = self.serve()
        with self.assertRaises(Blocked):
            factory.card(self.run, STRANGER, B)
        self.assertEqual(fake.calls, [])

    def test_accept_card_is_the_owners_accept_decision(self):
        fake = self.serve()
        factory.accept_card(self.run, A, 'card-1')
        self.assertEqual(fake.calls, [('POST', '/cards/card-1/decision', {'decision': 'accept'})])
        self.assertIn('tok-a', fake.bearers[0])

    def test_reject_card_is_the_owners_reject_decision(self):
        fake = self.serve()
        factory.reject_card(self.run, A, 'card-1')
        self.assertEqual(fake.calls, [('POST', '/cards/card-1/decision', {'decision': 'reject'})])

    def test_accept_back_is_the_targets_accept_on_the_acceptances_path(self):
        fake = self.serve()
        factory.accept_back(self.run, B, 'card-1')
        self.assertEqual(fake.calls, [('POST', '/cards/acceptances/card-1', {'decision': 'accept'})])
        self.assertIn('tok-b', fake.bearers[0])

    def test_accept_back_returns_the_server_answer_so_a_case_can_check_matched(self):
        self.serve({('POST', '/cards/acceptances/card-1'): Reply(200, {'matched': True, 'match_id': 'm1'})})
        self.assertEqual(factory.accept_back(self.run, B, 'card-1'), {'matched': True, 'match_id': 'm1'})

    def test_a_server_refusal_is_blocked_with_the_status_not_a_silent_pass(self):
        self.serve({('POST', '/cards/card-1/decision'): Reply(409, {'detail': '이미 결정'})})
        with self.assertRaises(Blocked) as why:
            factory.accept_card(self.run, A, 'card-1')
        self.assertIn('409', str(why.exception))

    # ── 매칭 · 채팅 ──
    def test_match_inserts_the_match_and_both_participants(self):
        fake = self.serve()
        match_id = factory.match(self.run, B, A)
        tables = [p for _, p in self.paths(fake)]
        self.assertEqual(tables, ['/rest/v1/matches', '/rest/v1/match_participants'])
        self.assertEqual(fake.calls[0][2]['profile_a'], 'id-a')  # matches_pair_order: 작은 id 가 a
        self.assertEqual(fake.calls[0][2]['id'], match_id)

    def test_match_refuses_an_account_this_run_did_not_make(self):
        fake = self.serve()
        with self.assertRaises(Blocked):
            factory.match(self.run, A, STRANGER)
        self.assertEqual(fake.calls, [])

    def test_send_posts_the_message_as_the_sender(self):
        fake = self.serve({('POST', '/chat/matches/m1/messages'): Reply(201, {'id': 'x'})})
        factory.send(self.run, A, 'm1', '반가워요')
        self.assertEqual(fake.calls, [('POST', '/chat/matches/m1/messages', {'body': '반가워요'})])
        self.assertIn('tok-a', fake.bearers[0])

    def test_send_that_is_not_201_is_blocked(self):
        self.serve({('POST', '/chat/matches/m1/messages'): Reply(409, {'detail': '나감'})})
        with self.assertRaises(Blocked):
            factory.send(self.run, A, 'm1')

    def test_trust_posts_the_trust_accept_as_that_account(self):
        fake = self.serve()
        factory.trust(self.run, B, 'm1')
        self.assertEqual([(m, p) for m, p, _ in fake.calls], [('POST', '/chat/matches/m1/trust')])
        self.assertIn('tok-b', fake.bearers[0])

    # ── 지인 리뷰 · 추천 ──
    def test_link_inserts_the_referral_and_activates_the_referee(self):
        fake = self.serve()
        factory.link(self.run, A, B)
        self.assertEqual(self.paths(fake), [('POST', '/rest/v1/referrals'), ('PATCH', '/rest/v1/profiles')])
        self.assertEqual(fake.calls[0][2], {'referee_id': 'id-b', 'referrer_id': 'id-a'})

    def test_link_refuses_an_account_this_run_did_not_make(self):
        fake = self.serve()
        with self.assertRaises(Blocked):
            factory.link(self.run, STRANGER, B)
        self.assertEqual(fake.calls, [])

    def test_review_posts_to_the_reviewee_as_the_reviewer(self):
        fake = self.serve({('POST', '/friend-reviews'): Reply(201, {'id': 'r1'})})
        factory.review(self.run, A, B)
        method, path, body = fake.calls[0]
        self.assertEqual((method, path, body['reviewee_id']), ('POST', '/friend-reviews', 'id-b'))
        self.assertIn('tok-a', fake.bearers[0])

    def test_redeem_posts_the_code_as_the_new_account(self):
        fake = self.serve()
        factory.redeem(self.run, A, 'K7M2QX')
        self.assertEqual(fake.calls, [('POST', '/referral/redeem', {'code': 'K7M2QX'})])
        self.assertIn('tok-a', fake.bearers[0])

    # ── 알림 스위치 ──
    def test_switches_patches_only_what_was_asked(self):
        fake = self.serve()
        factory.switches(self.run, B, new_message=False, quiet_hours=True)
        self.assertEqual(fake.calls, [('PATCH', '/cards/notification-settings', {'new_message': False, 'quiet_hours': True})])
        self.assertIn('tok-b', fake.bearers[0])

    def test_switches_rejects_an_unknown_name_before_calling_the_server(self):
        fake = self.serve()
        with self.assertRaises(ValueError):
            factory.switches(self.run, B, new_mesage=False)
        self.assertEqual(fake.calls, [])

    def test_default_switches_deletes_the_settings_row_of_that_account(self):
        fake = self.serve()
        factory.default_switches(self.run, B)
        self.assertEqual([(m, urlsplit(u).path, urlsplit(u).query) for m, u in fake.urls],
                         [('DELETE', '/rest/v1/notification_settings', 'profile_id=eq.id-b')])

    def test_default_switches_refuses_an_account_this_run_did_not_make(self):
        fake = self.serve()
        with self.assertRaises(Blocked):
            factory.default_switches(self.run, STRANGER)
        self.assertEqual(fake.calls, [])
