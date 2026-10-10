"""영역 2 두 기기 카드 수락 6개(E-CARD-33 · 42 · 47 · 49 · 85 · 87)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 서버 · 가짜 `two` 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_two_accept`.

가짜 서버 [World] 는 영역 3 안전 시험의 SafeFake(후보 · 카드 · 수락함 · 카드 대상)에 일시중지 · 수락 응답 · 매칭을 얹은 것이다 —
올바른 서버면 pass, 규칙 하나를 어긴 서버([World.rules])면 fail 이어야 한다.
가짜 `two`([FakeTwo])는 앱이 말하는 차례(script)대로 가설이 건 핸들러를 부른다 — 앱이 서버에 남기는 일은 차례마다 effect 로 흉내 낸다.
진짜 twodev(우편함 둘 + 가짜 앱 스레드)로 도는 시험은 두 기기 사이 Sync 순서가 실제 스레드에서 맞는지 본다.
계정은 만든 순서대로 id-1(A · 폰) · id-2(B · 에뮬), 토큰은 tok-1 · tok-2 …
"""

import re
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area2_two_accept, tools, twodev
from e2e import test_twodev as t2
from e2e.test_area1 import CFG
from e2e.test_area3_safe import SafeFake, _who
from e2e.tools import Hub, Reply, Run

CASES = ['E-CARD-33', 'E-CARD-42', 'E-CARD-47', 'E-CARD-49', 'E-CARD-85', 'E-CARD-87']
A, B = 'id-1', 'id-2'
UNIQUE = {'retry': False}  # 두 번 가면 안 되는 요청 — tools.call 이 한 번만 보낸다


class World(SafeFake):
    """SafeFake + 일시중지(후보 · 카드 대상에서 빠짐) · 수락 응답(POST /cards/acceptances/{card}) · 매칭 · 수락함에서 매칭된 사람 빼기."""

    def __init__(self):
        super().__init__()
        self.options = []
        self.new_rooms = []  # 새로 만든 방 — 서버는 이때만 "매칭됐어요!" 알림을 둘에게 보낸다
        self.rules.update(paused_candidates=False, paused_owners=False, matched_in_inbox=False, split_room=False,
                          candidate_stays_out=False, owner_stays_out=False)
        self.on('POST', r'/cards/acceptances/[^/]+', self._respond)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.options.append((method, urlsplit(url).path, options))
        return super().__call__(method, url, headers, body, raw, **options)

    def _basic(self, sent):
        self.profile(_who(sent))['nickname'] = sent['body']['nickname']
        return super()._basic(sent)

    def card(self, card_id):
        return next((c for c in self.rows('daily_cards') if c['id'] == card_id), None)

    def responded(self, card_id):
        return any(r['card_id'] == card_id for r in self.rows('acceptance_responses'))

    def _candidates(self, sent):
        reply = super()._candidates(sent)
        if self.rules['paused_candidates']:
            return reply

        def out(profile):  # 다시 켜도 돌아오지 않는 서버는 한 번이라도 껐던 사람(was_paused)을 계속 뺀다
            return profile.get('matching_paused') or (self.rules['candidate_stays_out'] and profile.get('was_paused'))
        return Reply(200, {'candidates': [c for c in reply[1]['candidates'] if not out(self.profile(c['profile_id']))]})

    def _owners(self, sent):
        reply = super()._owners(sent)
        profile = self.profile(sent['query']['profile_id'][3:])
        if (profile.get('matching_paused') and not self.rules['paused_owners']) or (self.rules['owner_stays_out'] and profile.get('was_paused')):
            return Reply(200, [])
        return reply

    def _acceptances(self, sent):
        me = _who(sent)
        rows = []
        for row in super()._acceptances(sent)[1]['acceptances']:
            if self.responded(row['card_id']):
                continue
            if self._match_of(me, self.card(row['card_id'])['owner_id']) and not self.rules['matched_in_inbox']:
                continue
            rows.append(row)
        return Reply(200, {'acceptances': rows})

    def _respond(self, sent):
        me, card_id = _who(sent), sent['path'].rsplit('/', 1)[1]
        card = self.card(card_id)
        if card is None or card['target_id'] != me or (self.decided(card_id) or {}).get('decision') != 'accept':
            return Reply(404, {'detail': '수락을 찾을 수 없어요'})
        if self.responded(card_id):
            return Reply(409, {'detail': '이미 답했어요'})
        decision = sent['body']['decision']
        self.rows('acceptance_responses').append({'card_id': card_id, 'responder_id': me, 'decision': decision})
        if decision != 'accept':
            return Reply(200, {'matched': False})
        match = self._match_of(me, card['owner_id'])
        if match is None or self.rules['split_room']:
            low, high = sorted((me, card['owner_id']))
            match = {'id': str(uuid.uuid4()), 'profile_a': low, 'profile_b': high}
            self.rows('matches').append(match)
            self.rows('match_participants').extend([{'match_id': match['id'], 'profile_id': low},
                                                    {'match_id': match['id'], 'profile_id': high}])
            self.new_rooms.append(match['id'])
        return Reply(200, {'matched': True, 'match_id': match['id']})

    # 앱이 화면에서 누른 일 — 서버가 받아 DB 에 남기는 것을 그대로 부른다 ----------------------------------------------------
    def app_decides(self, who, card_id, decision):
        self._decide({'path': f'/cards/{card_id}/decision', 'body': {'decision': decision}, 'auth': f'tok-{who.removeprefix("id-")}'})

    def app_responds(self, who, card_id, decision):
        return self._respond({'path': f'/cards/acceptances/{card_id}', 'body': {'decision': decision},
                              'auth': f'tok-{who.removeprefix("id-")}'})

    def card_between(self, owner, target):
        return next(c['id'] for c in self.rows('daily_cards') if (c['owner_id'], c['target_id']) == (owner, target))

    def nickname(self, who):
        return self.profile(who)['nickname']


class FakeTwo:
    """twodev.bound 가 주는 `two` 대신 — 앱이 말하는 차례(script = [(쪽, step 이름, effect)])대로 plan 의 핸들러를 부른다.
    effect 는 앱이 그 step 에 닿기 전에 서버에 남기는 일(없으면 None). plan 의 열쇠와 script 가 한 치도 다르면 시험이 깨진다."""

    def __init__(self, test, script, result=('pass', 'A: pass  B: pass')):
        self.test, self.script, self.result = test, script, result
        self.went, self.limit, self.a_job, self.b_job = [], None, None, None

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.a_job, self.b_job, self.limit = a_job, b_job, limit
        self.test.assertEqual(sorted(plan), sorted((side, step) for side, step, _ in self.script))
        sync = twodev.Sync()
        for side, step, effect in self.script:
            if effect:
                effect()
            self.went.append((side, step, plan[(side, step)]({'step': step, 't': 0}, sync)))
        return self.result


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area2-two-accept', 'b', cfg={**CFG}, key='svc')
        self.world = World()
        patchers = [mock.patch.object(tools, 'call', self.world),
                    mock.patch.object(area2_two_accept, 'POLL', 0),
                    mock.patch.object(area2_two_accept, 'SAVED', 0.05),
                    mock.patch.object(area2_two_accept, 'PEER', 0.05)]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def go(self, case, *script, result=('pass', 'A: pass  B: pass')):
        self.two = FakeTwo(self, script, result)
        return twodev.TWO[case](self.run_, self.two)

    def passes(self, case, *script):
        result, memo = self.go(case, *script)
        self.assertEqual(result, 'pass', memo)
        return memo

    def fails(self, case, *script, words=()):
        result, memo = self.go(case, *script)
        self.assertEqual(result, 'fail', memo)
        for word in words:
            self.assertIn(word, memo)
        return memo

    def decided(self, card, decision):
        return [d['decision'] for d in self.world.rows('card_decisions') if d['card_id'] == card] == [decision]


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_six_cases_are_two_device_hypotheses_in_one_bundle(self):
        self.assertEqual(area1.BUNDLES['area2-two-accept'], CASES)
        self.assertEqual(sorted(area2_two_accept.CASES), sorted(CASES))
        for case in CASES:
            self.assertIs(twodev.TWO[case], area2_two_accept.TWO[case], case)
            self.assertNotIn(case, area1.PHONE)
            self.assertNotIn(case, area2.CASES)

    def test_the_unlisted_notification_and_single_device_lines_are_not_taken(self):
        for other in ['E-CARD-40', 'E-CARD-41', 'E-CARD-43', 'E-CARD-45', 'E-CARD-46', 'E-CARD-48', 'E-CARD-86']:
            self.assertNotIn(other, area2_two_accept.CASES)

    def test_every_case_has_room_for_two_accounts_and_two_devices(self):
        for case in CASES:
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 900, case)

    def test_main_registers_the_module_before_it_builds_the_bundle_table(self):
        from e2e import __main__ as main
        text = Path(main.__file__).read_text(encoding='utf-8')
        self.assertIn('from e2e import area2_two_accept', text)
        self.assertLess(text.index('from e2e import area2_two_accept'), text.index('BUNDLES = {'))
        self.assertEqual(main.BUNDLES['area2-two-accept'], CASES)
        self.assertFalse(set(CASES) & set(main.API_CASES))

    def test_the_app_has_both_sides_of_every_case_and_every_step_the_pc_waits_for(self):
        dart = self.dart('area2_two_accept.dart')
        steps = {'E-CARD-33': {'A': [], 'B': ['paused', 'resumed']}, 'E-CARD-42': {'A': ['rejected'], 'B': ['wait']},
                 'E-CARD-47': {'A': ['open'], 'B': ['matched']}, 'E-CARD-49': {'A': ['wait'], 'B': ['rejected']},
                 'E-CARD-85': {'A': ['accepted'], 'B': ['wait']}, 'E-CARD-87': {'A': ['matched'], 'B': ['wait', 'opened']}}
        for case, sides in steps.items():
            for side, names in sides.items():
                found = re.search(rf"(?ms)^  '{case}/{side}':(.*?)(?=^  '|^\}};)", dart)
                self.assertIsNotNone(found, f'{case}/{side}')
                for name in names:
                    self.assertRegex(found.group(1), rf"(step|_loginAfter)\('{name}'", f'{case}/{side} {name}')

    def test_e2e_test_merges_the_app_cases(self):
        main = self.dart('e2e_test.dart')
        self.assertIn("import 'area2_two_accept.dart';", main)
        self.assertIn('...area2TwoAcceptCases', main)

    def test_no_notification_is_read_here_that_is_the_last_bundle(self):
        self.assertFalse(hasattr(area2_two_accept, 'notify'))
        self.assertNotIn('firebase', self.dart('area2_two_accept.dart').lower())


class SafetyNetTest(Base):
    def test_every_case_ends_blocked_when_the_server_is_down_and_never_reaches_a_device(self):
        down = World()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        two = mock.Mock(side_effect=AssertionError('기기까지 가면 안 된다'))
        with mock.patch.object(tools, 'call', down):
            for case in CASES:
                result, memo = twodev.TWO[case](self.run_, two)
                self.assertEqual(result, 'blocked', case)
                self.assertIsInstance(memo, str, case)
        two.assert_not_called()

    def test_every_write_stays_inside_the_accounts_this_run_made(self):
        scripts = {
            'E-CARD-33': [('B', 'paused', lambda: self.pause(True)), ('B', 'resumed', lambda: self.pause(False))],
            'E-CARD-42': [('A', 'rejected', lambda: self.decide('reject')), ('B', 'wait', None)],
            'E-CARD-47': [('B', 'matched', lambda: self.respond(B, 'accept')), ('A', 'open', None)],
            'E-CARD-49': [('B', 'rejected', lambda: self.respond(B, 'reject')), ('A', 'wait', None)],
            'E-CARD-85': [('A', 'accepted', lambda: self.decide('accept')), ('B', 'wait', None)],
            'E-CARD-87': [('A', 'matched', lambda: self.respond(A, 'accept')), ('B', 'wait', None), ('B', 'opened', None)],
        }
        for case, script in scripts.items():
            self.world = World()
            with mock.patch.object(tools, 'call', self.world):
                self.go(case, *script)
            made = {u['id'] for u in self.world.users}
            self.assertEqual(made, {A, B}, case)
            for sent in self.world.sent:
                if sent['method'] not in ('POST', 'PATCH', 'DELETE') or not sent['path'].startswith('/rest/v1/'):
                    continue
                table = sent['path'].split('/')[-1]
                if table in ('daily_cards', 'profiles', 'profile_vectors', 'profile_private'):
                    rows = sent['body'] if isinstance(sent['body'], list) else [sent['body']]
                    owners = {r[k] for r in rows if isinstance(r, dict) for k in ('owner_id', 'target_id', 'profile_id') if k in r}
                    # 계정 공장이 넣는 프로필 행(POST profiles)은 본문의 id 가 주인이다
                    owners |= {r['id'] for r in rows if table == 'profiles' and isinstance(r, dict) and 'id' in r}
                    owners |= {sent['query'][k][3:] for k in ('owner_id', 'id', 'profile_id') if k in sent['query']}
                    self.assertTrue(owners and owners <= made, (case, sent))

    # 앱이 서버에 남기는 일 — 카드는 가설이 만든 것(A→B 는 첫 카드, B→A 는 둘째)을 찾아 쓴다
    def pause(self, value):
        self.world.profile(B)['matching_paused'] = value

    def decide(self, decision):
        self.world.app_decides(A, self.world.card_between(A, B), decision)

    def respond(self, who, decision):
        other = B if who == A else A
        self.world.app_responds(who, self.world.card_between(other, who), decision)


class PauseTest(Base):
    def pause(self, value):
        return lambda: self.world.profile(B).update(matching_paused=value, was_paused=True)

    def script(self, off=True, on=True):
        return [('B', 'paused', self.pause(True) if off else None), ('B', 'resumed', self.pause(False) if on else None)]

    def test_off_hides_b_from_a_and_from_the_card_batch_and_on_brings_b_back(self):
        memo = self.passes('E-CARD-33', *self.script())
        self.assertIn('card_issue_owners', memo)  # 배치를 부르지 않고 배치가 쓰는 대상 함수로 본 것을 밝힌다
        self.assertEqual(self.two.went[0][:2], ('B', 'paused'))

    def test_the_relaunch_is_a_fresh_sign_in_with_a_one_time_token_made_after_the_first_was_used(self):
        self.passes('E-CARD-33', *self.script())
        self.assertEqual(self.two.went[0][2], {'token_hash': 'h'})  # off 뒤 go 에 실려 앱이 다시 로그인한다
        self.assertIsNone(self.two.went[1][2])
        self.assertEqual(self.two.a_job, {'token_hash': 'h'})
        self.assertEqual(self.two.b_job, {'token_hash': 'h'})
        links = [s for s in self.world.sent if s['path'] == '/auth/v1/admin/generate_link']
        self.assertEqual([s['body']['email'] for s in links][-3:], [
            self.world.users[0]['email'], self.world.users[1]['email'], self.world.users[1]['email']])  # A 첫 로그인 · B 첫 로그인 · B 다시 로그인

    def test_a_paused_b_still_in_the_candidates_is_a_fail(self):
        self.world.rules['paused_candidates'] = True
        self.fails('E-CARD-33', *self.script(), words=['후보'])

    def test_a_paused_b_still_a_card_owner_is_a_fail(self):
        self.world.rules['paused_owners'] = True
        self.fails('E-CARD-33', *self.script(), words=['card_issue_owners'])

    def test_a_b_who_does_not_come_back_into_the_candidates_after_the_resume_is_a_fail(self):
        self.world.rules['candidate_stays_out'] = True
        self.fails('E-CARD-33', *self.script(), words=['다시 켠 뒤', '후보'])

    def test_a_b_who_does_not_come_back_as_a_card_owner_after_the_resume_is_a_fail(self):
        self.world.rules['owner_stays_out'] = True
        self.fails('E-CARD-33', *self.script(), words=['다시 켠 뒤', 'card_issue_owners'])

    def test_a_switch_that_never_reached_the_server_is_a_fail(self):
        self.fails('E-CARD-33', *self.script(off=False, on=False), words=['저장'])

    def test_a_resume_that_does_not_bring_b_back_is_a_fail(self):
        self.fails('E-CARD-33', ('B', 'paused', self.pause(True)), ('B', 'resumed', None), words=['저장'])

    def test_b_not_a_candidate_before_the_switch_is_blocked_not_a_pass(self):
        with mock.patch.object(area2_two_accept, '_candidates', lambda run, account: {}):
            result, memo = self.go('E-CARD-33', *self.script())
        self.assertEqual(result, 'blocked')
        self.assertIn('준비가 틀림', memo)
        self.assertIsNone(self.two.a_job)  # 기기를 켜기 전에 멈춘다 — two 는 불리지 않았다

    def test_the_app_failure_is_kept_and_a_pc_finding_wins_over_a_blocked_side(self):
        self.world.rules['paused_candidates'] = True
        result, memo = self.go('E-CARD-33', *self.script(), result=('blocked', 'A: pass  B: blocked - 앱 막힘'))
        self.assertEqual(result, 'fail')
        self.assertIn('앱 막힘', memo)


class RejectTest(Base):
    def reject(self):
        self.world.app_decides(A, self.world.card_between(A, B), 'reject')

    def accept(self):
        self.world.app_decides(A, self.world.card_between(A, B), 'accept')

    def test_a_reject_is_one_reject_row_and_b_gets_nothing(self):
        memo = self.passes('E-CARD-42', ('A', 'rejected', self.reject), ('B', 'wait', None))
        self.assertIn('알림', memo)  # 알림 0 은 이 묶음 몫이 아니라고 밝힌다
        card = self.world.card_between(A, B)
        self.assertTrue(self.decided(card, 'reject'))
        self.assertEqual(self.two.went[1][2], {'token_hash': 'h'})  # B 는 거절 뒤에 로그인한다 — 수락함을 새로 읽게

    def test_b_logs_in_only_after_a_has_decided(self):
        order = []
        self.passes('E-CARD-42', ('A', 'rejected', lambda: (self.reject(), order.append('A'))), ('B', 'wait', lambda: order.append('B')))
        self.assertEqual(order, ['A', 'B'])
        self.assertEqual(self.two.a_job, {'token_hash': 'h'})
        self.assertNotIn('token_hash', self.two.b_job or {})  # B 의 토큰은 go 에 실린다 — 일감에는 없다

    def test_an_accept_saved_instead_of_a_reject_is_a_fail_and_b_sees_a_row(self):
        self.fails('E-CARD-42', ('A', 'rejected', self.accept), ('B', 'wait', None), words=['reject', '수락함'])

    def test_a_reject_that_never_reached_the_server_is_a_fail(self):
        self.fails('E-CARD-42', ('A', 'rejected', None), ('B', 'wait', None), words=['저장'])

    def test_the_cards_decision_is_sent_by_the_server_path_the_app_uses(self):
        self.passes('E-CARD-42', ('A', 'rejected', self.reject), ('B', 'wait', None))
        self.assertEqual(len(self.world.by('POST', '/rest/v1/daily_cards')), 1)  # 카드는 한 장만 심는다


class MatchTest(Base):
    def b_accepts(self):
        self.world.app_responds(B, self.world.card_between(A, B), 'accept')

    def test_after_b_accepts_one_room_with_two_members_exists_and_a_signs_in_after_it(self):
        self.passes('E-CARD-47', ('B', 'matched', self.b_accepts), ('A', 'open', None))
        self.assertEqual(len(self.world.rows('matches')), 1)
        self.assertEqual(self.two.went[1][2], {'token_hash': 'h'})  # A 는 방이 생긴 뒤 로그인 — 목록이 처음부터 그 상태로 읽힌다
        self.assertEqual(self.two.went[0][2], None)

    def test_the_pass_memo_says_a_signed_in_after_the_room_and_the_kept_open_app_path_is_not_seen(self):
        memo = self.passes('E-CARD-47', ('B', 'matched', self.b_accepts), ('A', 'open', None))
        self.assertIn('켜 둔 앱', memo)

    def test_each_app_is_told_the_other_ones_nickname(self):
        self.passes('E-CARD-47', ('B', 'matched', self.b_accepts), ('A', 'open', None))
        self.assertEqual(self.two.b_job['nickname'], self.world.nickname(A))  # B 의 수락 대기 줄 · 방 이름
        self.assertEqual(self.two.a_job['nickname'], self.world.nickname(B))  # A 의 대화 중 줄
        self.assertIn('token_hash', self.two.b_job)
        self.assertNotIn('token_hash', self.two.a_job)

    def test_the_card_is_accepted_by_a_through_the_decision_route_once_and_never_resent(self):
        self.passes('E-CARD-47', ('B', 'matched', self.b_accepts), ('A', 'open', None))
        sent = [o for m, p, o in self.world.options if m == 'POST' and p.endswith('/decision')]
        self.assertEqual(sent, [UNIQUE])

    def test_no_room_after_the_accept_is_a_fail(self):
        self.fails('E-CARD-47', ('B', 'matched', None), ('A', 'open', None), words=['matches'])

    def test_a_room_with_one_member_is_a_fail(self):
        def one_member():
            self.b_accepts()
            self.world.tables['match_participants'].pop()
        self.fails('E-CARD-47', ('B', 'matched', one_member), ('A', 'open', None), words=['match_participants'])


class InboxRejectTest(Base):
    def prepared(self):
        return lambda: None

    def b_rejects(self):
        self.world.app_responds(B, self.world.card_between(A, B), 'reject')

    def test_a_reject_from_the_inbox_makes_no_room_and_b_list_is_empty(self):
        memo = self.passes('E-CARD-49', ('B', 'rejected', self.b_rejects), ('A', 'wait', None))
        self.assertIn('알림', memo)
        self.assertEqual(self.world.rows('matches'), [])
        self.assertEqual([r['decision'] for r in self.world.rows('acceptance_responses')], ['reject'])
        self.assertEqual(self.two.went[1][2], {'token_hash': 'h'})  # A 는 거절 뒤에 로그인 — 아무 신호가 없었는지 새로 읽는다

    def test_the_inbox_row_exists_before_the_app_starts(self):
        # 시작 전에 A 의 수락이 서버에 있어야 B 의 앱이 첫 읽기에서 "받은 신청 1명" 을 본다
        seen = []
        self.passes('E-CARD-49', ('B', 'rejected', lambda: (seen.append(self.world.decided(self.world.card_between(A, B))), self.b_rejects())),
                    ('A', 'wait', None))
        self.assertEqual(seen[0]['decision'], 'accept')

    def test_an_accept_instead_of_a_reject_is_a_fail(self):
        self.fails('E-CARD-49', ('B', 'rejected', lambda: self.world.app_responds(B, self.world.card_between(A, B), 'accept')),
                   ('A', 'wait', None), words=['reject', 'matches'])

    def test_no_saved_reject_is_a_fail(self):
        self.fails('E-CARD-49', ('B', 'rejected', None), ('A', 'wait', None), words=['저장'])


class DoubleTapTest(Base):
    def accept_once(self):
        self.world.app_decides(A, self.world.card_between(A, B), 'accept')

    def test_one_accept_row_and_b_sees_exactly_one_inbox_line(self):
        memo = self.passes('E-CARD-85', ('A', 'accepted', self.accept_once), ('B', 'wait', None))
        self.assertIn('알림', memo)
        self.assertEqual(self.two.went[1][2], {'token_hash': 'h'})

    def test_the_pass_memo_says_either_of_the_two_guards_is_enough(self):
        memo = self.passes('E-CARD-85', ('A', 'accepted', self.accept_once), ('B', 'wait', None))
        self.assertIn('버튼 비활성화', memo)
        self.assertIn('VM 가드', memo)

    def test_the_prepared_card_is_alive_and_undecided_when_the_apps_start(self):
        seen = []
        self.passes('E-CARD-85', ('A', 'accepted', lambda: (seen.append(self.world.decided(self.world.card_between(A, B))), self.accept_once())),
                    ('B', 'wait', None))
        self.assertIsNone(seen[0])  # 카드는 있고 결정은 아직 없다 — 앱의 연타가 첫 결정이다

    def test_two_decision_rows_are_a_fail(self):
        def twice():
            self.accept_once()
            self.accept_once()
        self.fails('E-CARD-85', ('A', 'accepted', twice), ('B', 'wait', None), words=['2행'])

    def test_a_reject_row_is_a_fail(self):
        self.fails('E-CARD-85', ('A', 'accepted', lambda: self.world.app_decides(A, self.world.card_between(A, B), 'reject')),
                   ('B', 'wait', None), words=['accept'])

    def test_no_row_is_a_fail(self):
        self.fails('E-CARD-85', ('A', 'accepted', None), ('B', 'wait', None), words=['저장'])


class AlreadyMatchedTest(Base):
    def a_accepts_inbox(self):
        self.world.app_responds(A, self.world.card_between(B, A), 'accept')

    def script(self, a_effect=None):
        return [('A', 'matched', a_effect or self.a_accepts_inbox), ('B', 'wait', None), ('B', 'opened', None)]

    def test_the_other_inbox_loses_the_line_and_the_late_api_answer_is_the_same_room(self):
        memo = self.passes('E-CARD-87', *self.script())
        self.assertIn('알림', memo)
        self.assertEqual(len(self.world.rows('matches')), 1)
        self.assertEqual(len(self.world.new_rooms), 1)  # 늦은 응답은 새 방 · 새 알림이 아니다
        self.assertEqual(self.two.went[1][2], {'token_hash': 'h'})  # B 는 매칭 뒤에 로그인해 수락함을 연다

    def test_both_cards_are_accepted_before_the_apps_start(self):
        seen = []
        self.passes('E-CARD-87', ('A', 'matched', lambda: (seen.append((self.world.decided(self.world.card_between(A, B))['decision'],
                                                                         self.world.decided(self.world.card_between(B, A))['decision'])),
                                                          self.a_accepts_inbox())),
                    ('B', 'wait', None), ('B', 'opened', None))
        self.assertEqual(seen, [('accept', 'accept')])
        self.assertEqual(len(self.world.rows('matches')), 1)

    def test_the_late_answer_goes_through_the_route_with_the_card_of_a_and_is_never_resent(self):
        self.passes('E-CARD-87', *self.script())
        late = [s for s in self.world.sent if s['method'] == 'POST' and s['path'] == f"/cards/acceptances/{self.world.card_between(A, B)}"]
        self.assertEqual(len(late), 1)
        self.assertEqual(late[0]['auth'], 'tok-2')  # B 의 토큰
        sent = [o for m, p, o in self.world.options if m == 'POST' and p.startswith('/cards/acceptances/')]
        self.assertEqual(sent, [UNIQUE])

    def test_a_server_that_keeps_the_matched_person_in_the_inbox_is_a_fail(self):
        self.world.rules['matched_in_inbox'] = True
        self.fails('E-CARD-87', *self.script(), words=['수락함'])

    def test_a_late_answer_that_opens_a_second_room_is_a_fail(self):
        def first_room_then_split():
            self.a_accepts_inbox()
            self.world.rules['split_room'] = True  # 늦은 응답부터 새 방을 만드는 서버
        self.fails('E-CARD-87', *self.script(first_room_then_split), words=['matches', 'match_id'])

    def test_no_room_after_a_accepts_is_a_fail(self):
        self.fails('E-CARD-87', ('A', 'matched', None), ('B', 'wait', None), ('B', 'opened', None), words=['matches'])


class RealTwoTest(unittest.TestCase):
    """진짜 twodev(우편함 둘 + 가짜 앱 스레드 둘 + 가짜 adb)로 한 가설 — 두 기기가 서로 기다리는 순서가 실제 스레드에서 맞는지."""

    @classmethod
    def setUpClass(cls):
        cls.hubs = {'A': Hub(0), 'B': Hub(0)}

    @classmethod
    def tearDownClass(cls):
        for hub in cls.hubs.values():
            hub.close()

    def setUp(self):
        for hub in self.hubs.values():
            t2.drain(hub)
        self.root = Path(tempfile.mkdtemp())
        self.run_ = Run(self.root / 'area2-two-accept', 'b', cfg={**CFG}, key='svc')
        self.world = World()
        patchers = [mock.patch.object(tools, 'call', self.world), mock.patch.object(tools, 'adb', t2.FakeAdb()),
                    mock.patch.object(twodev, 'KILL_PAUSE', 0), mock.patch.object(twodev, 'SLICE', 0.05),
                    mock.patch.object(twodev, 'GRACE', 0.3), mock.patch.object(area2_two_accept, 'POLL', 0),
                    mock.patch.object(area2_two_accept, 'SAVED', 0.5)]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.apps = []

    def app(self, name, steps, effects=None, **kw):
        world_effects = effects or {}

        class Scripted(t2.App):
            def run(app):
                try:
                    app.job = app.hear()
                    for step in app.steps:
                        time.sleep(app.pause)
                        if world_effects.get(step):
                            world_effects[step]()
                        app._call('POST', '/say', {'step': step})
                        app.heard.append(app.hear())
                        if app.log is not None:
                            app.log.append(f'{app.name}-resume-{step}')
                    if app.result is not None and not app.halt.is_set():
                        app._call('POST', '/say', app.result)
                except OSError:
                    pass

        made = Scripted(self.hubs[name], steps=steps, name=name, **kw)
        self.apps.append(made)
        made.start()
        self.addCleanup(t2.Base._stop, made)
        return made

    def run_case(self, case):
        sides = [twodev.Side(self.hubs[n], f'SER-{n}', {}) for n in 'AB']
        return twodev.TWO[case](self.run_, twodev.bound(self.run_, case, *sides))

    def test_a_waits_for_b_to_make_the_room_and_only_then_signs_in_with_the_fresh_token(self):
        log = []

        def b_accepts():
            self.world.app_responds(B, self.world.card_between(A, B), 'accept')
            log.append('room-made')

        a = self.app('A', ['open'], log=log)  # A 는 시작하자마자 "open" 에서 멈춘다 — B 가 느려도 방이 생긴 뒤에야 풀려야 한다
        b = self.app('B', ['matched'], {'matched': b_accepts}, pause=0.6, log=log)
        result, memo = self.run_case('E-CARD-47')
        self.assertEqual(result, 'pass', memo)
        self.assertLess(log.index('room-made'), log.index('A-resume-open'))
        self.assertEqual(a.job['case'], 'E-CARD-47/A')
        self.assertEqual(b.job['case'], 'E-CARD-47/B')
        self.assertNotIn('token_hash', a.job)
        self.assertEqual(a.heard[0]['token_hash'], 'h')  # go 에 실려 온 로그인 토큰
        self.assertEqual(b.job['token_hash'], 'h')
        self.assertEqual(len(self.world.rows('matches')), 1)

    def test_when_b_never_matches_the_pc_finding_is_a_fail_and_a_is_released_not_hung(self):
        a = self.app('A', ['open'])
        self.app('B', ['matched'])  # 서버에 아무것도 안 남기고 말한다
        started = time.monotonic()
        with mock.patch.object(self.run_, 'shot', lambda serial, case: None):
            result, memo = self.run_case('E-CARD-47')
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual(result, 'fail', memo)
        self.assertIn('matches', memo)


if __name__ == '__main__':
    unittest.main()
