"""영역 5 두 기기(폰 A + 에뮬 B) 탈퇴 5개(E-WD-05 · 06 · 07 · 08 · 09)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 서버 · 가짜 `two` 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_two`.

가짜 서버 [TwoWorld] 는 영역 2 두 기기 수락 시험의 World(후보 · 카드 · 수락함 · 매칭)에 탈퇴(logout scope=global) · GoTrue /user ·
채팅 보내기 409 · 카드 상세 404 · 내가 쓴 리뷰를 얹었다. 올바른 서버면 pass, [rules] 하나를 어긴 서버면 fail 이어야 한다.
가짜 `two` 는 test_area2_two_accept.FakeTwo — 앱이 말하는 차례(script)대로 핸들러를 부르고, 앱이 서버에 남기는 일(A 가 "정말 영구 삭제" 를 누름)은
그 차례의 effect 로 흉내 낸다. 계정은 만든 순서대로 id-1(A · 폰) · id-2(B · 에뮬) · id-3(대조군) …, 토큰은 tok-1 ….
"""

import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from e2e import area1, area2, area2_two_accept, area5_two, tools, twodev
from e2e.test_area1 import CFG
from e2e.test_area2_two_accept import FakeTwo, World
from e2e.test_area3_safe import _who
from e2e.tools import Reply, Run

CASES = ['E-WD-05', 'E-WD-06', 'E-WD-07', 'E-WD-08', 'E-WD-09']
A, B, C = 'id-1', 'id-2', 'id-3'
WITHDRAWN = '탈퇴한 계정이에요'
EXPIRED = '세션이 만료됐어요, 다시 로그인해 주세요'
PARTNER_LEFT = '상대가 대화를 나갔어요'
CARD_GONE = '카드를 찾을 수 없어요'


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


class TwoWorld(World):
    def __init__(self):
        super().__init__()
        self.cut = set()
        self.rules.update(logout=True, send_blocked=True, detail_hidden=True, written_hides=True)
        for method, pattern, handler in (('POST', r'/account/withdraw', self._withdraw), ('GET', r'/auth/v1/user', self._user),
                                         ('POST', r'/chat/matches/[^/]+/messages', self._send),
                                         ('GET', r'/friend-reviews/written', self._written), ('GET', r'/cards/(?!today|acceptances)[^/]+', self._detail)):
            self.on(method, pattern, handler)

    # 앱이 "정말 영구 삭제" 를 누른 일 — account/router.py: 탈퇴 + 로그인 모두 끊기
    def app_withdraws(self, who=A):
        self.profile(who).update(status='withdrawn', withdrawn_at='now')
        if self.rules['logout']:
            self.cut.add(who)

    def _withdraw(self, sent):
        self.app_withdraws(_who(sent))
        return Reply(200, {'ok': True})

    def _user(self, sent):
        return Reply(403, {'msg': 'session_not_found'}) if _who(sent) in self.cut else Reply(200, {'id': _who(sent)})

    def gone(self, pid):
        return self.profile(pid)['status'] in ('withdrawn', 'suspended')

    def _send(self, sent):
        me, match_id = _who(sent), sent['path'].split('/')[3]
        match = next(m for m in self.rows('matches') if m['id'] == match_id)
        partner = match['profile_b'] if match['profile_a'] == me else match['profile_a']
        if self.rules['send_blocked'] and self.gone(partner):
            return Reply(409, {'detail': PARTNER_LEFT})
        self.rows('messages').append({'id': 'new', 'match_id': match_id, 'sender_id': me, 'kind': 'text', 'body': sent['body']['body']})
        return Reply(201, {'id': 'new'})

    def _detail(self, sent):
        card = self.card(sent['path'].rsplit('/', 1)[1])
        if card is None or card['owner_id'] != _who(sent) or (self.rules['detail_hidden'] and self.hidden(_who(sent), card['target_id'])):
            return Reply(404, {'detail': CARD_GONE})
        return Reply(200, {'card_id': card['id']})

    def _written(self, sent):
        me = _who(sent)
        rows = [r for r in self.rows('friend_reviews') if r['reviewer_id'] == me and r.get('status', 'visible') == 'visible'
                and not (self.rules['written_hides'] and self.profile(r['reviewee_id'])['status'] == 'withdrawn')]
        return Reply(200, {'reviews': [{'id': r['id'], 'reviewee': {'nickname': self.nickname(r['reviewee_id'])}} for r in rows]})

    def issue(self, owners):
        """가짜 daily-cards — 주인마다 후보(탈퇴한 사람은 후보 SQL 이 뺀다 — World._candidates 의 active 규칙) 첫 사람에게 한 장."""
        for owner in owners:
            picks = self._candidates({'auth': f"tok-{owner['id'].removeprefix('id-')}"})[1]['candidates']
            if picks:
                self.rows('daily_cards').append({'id': f"daily-{owner['id']}", 'owner_id': owner['id'], 'target_id': picks[0]['profile_id'],
                                                 'source': 'daily'})


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area5-two', 'b', cfg={**CFG}, key='svc')
        self.world = TwoWorld()
        self.issued = []
        patchers = [mock.patch.object(tools, 'call', self.world),
                    mock.patch.object(area2_two_accept, 'POLL', 0), mock.patch.object(area2_two_accept, 'SAVED', 0.05),
                    mock.patch.object(area2_two_accept, 'PEER', 0.05),
                    mock.patch.object(area5_two, '_region', lambda run: 'e2e'),
                    mock.patch.object(area5_two, '_issue_cards', lambda run, region, control: self.issued.append(control) or
                                      self.world.issue([*control, {'id': B}]))]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)
        from e2e import area3_phone5
        area3_phone5._FAILED.clear()
        self.addCleanup(area3_phone5._FAILED.clear)

    def go(self, case, *script):
        self.two = FakeTwo(self, script)
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

    def blocked(self, case, *script, words=()):
        result, memo = self.go(case, *script)
        self.assertEqual(result, 'blocked', memo)
        for word in words:
            self.assertIn(word, memo)
        return memo

    def went(self, side, step):
        return next(extra for s, name, extra in self.two.went if (s, name) == (side, step))


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_the_five_are_two_device_cases_in_one_bundle(self):
        self.assertEqual(area1.BUNDLES['area5-two'], CASES)
        for case in CASES:
            self.assertIs(twodev.TWO[case], area5_two.TWO[case], case)
            self.assertNotIn(case, area1.PHONE)
            self.assertNotIn(case, area1.CASES)
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 1200, case)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        text = Path(main.__file__).read_text(encoding='utf-8')
        self.assertIn('from e2e import area5_two', text)
        self.assertLess(text.index('from e2e import area5_two'), text.index('BUNDLES = {'))

    def test_the_app_has_both_sides_of_every_case_and_the_steps_the_pc_waits_for(self):
        text = dart('area5_two.dart')
        keys = re.findall(r"^\s*'(E-WD-\d+/[AB])':", text, re.M)
        self.assertEqual(keys, [f'{c}/{s}' for c in CASES for s in 'AB'])
        self.assertIn("part 'area5_two.dart';", dart('area5.dart'))
        self.assertIn('...area5CasesTwo', dart('area5.dart'))
        steps = set(re.findall(r"step\('([\w-]+)'", text))
        for name in ('home', 'ready', 'login', 'withdrawn', 'tap', 'wait', 'room'):
            self.assertIn(name, steps)

    def test_only_the_a_side_reaches_the_final_delete_helper(self):
        text = dart('area5_two.dart')
        bodies = dict(zip(*[iter(re.split(r"(?m)^  '(E-WD-\d+/[AB])':", text.split('area5CasesTwo = {', 1)[1])[1:])] * 2))
        for key, body in bodies.items():
            with self.subTest(key):
                presses = '_twoWithdrawA' in body
                self.assertEqual(presses, key.endswith('/A'))
        self.assertNotIn('정말 영구 삭제', text)  # 글자는 area5_wd.dart 의 _wdForever 한 곳뿐

    def test_the_literals_the_app_looks_for_are_in_the_real_screens(self):
        screens = '\n'.join(p.read_text(encoding='utf-8') for p in (tools.ROOT / 'frontend' / 'lib').rglob('*.dart'))
        for literal in ('상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.', '채팅방 나가기', '내가 쓴 리뷰', '아직 쓴 리뷰가 없어요'):
            with self.subTest(literal):
                self.assertIn(f"'{literal}'", screens)
                self.assertIn(f"'{literal}'", dart('area5_two.dart') + dart('area5_time.dart'))


# ── E-WD-05 같은 계정 두 기기 ────────────────────────────────────────────────────────────────────────

class Wd05Test(Base):
    def script(self):
        return [('A', 'home', None), ('B', 'login', None), ('B', 'home', None), ('A', 'ready', None),
                ('A', 'withdrawn', self.world.app_withdraws), ('B', 'tap', None)]

    def test_pass_both_devices_log_in_to_one_account_and_b_hears_the_notice_for_a_cut_login(self):
        self.passes('E-WD-05', *self.script())
        self.assertEqual(self.went('B', 'tap'), {'notice': EXPIRED})  # 로그인이 끊겼으면 탈퇴 표시 없는 401 — 세션 만료 알림
        login = self.went('B', 'login')
        self.assertEqual(set(login), {'token_hash'})
        self.assertEqual(self.two.a_job.keys(), {'token_hash'})
        self.assertEqual(len([s for s in self.world.sent if s['path'] == '/auth/v1/admin/users' and s['method'] == 'POST']), 1)

    def test_a_server_that_keeps_the_login_wants_the_withdrawn_notice(self):
        self.world.rules['logout'] = False
        memo = self.passes('E-WD-05', *self.script())
        self.assertEqual(self.went('B', 'tap'), {'notice': WITHDRAWN})
        self.assertIn('살아', memo)

    def test_a_withdraw_that_never_lands_is_a_fail(self):
        script = [(s, n, None) for s, n, _ in self.script()]
        self.fails('E-WD-05', *script, words=('withdrawn',))


# ── E-WD-06 채팅 상대 ───────────────────────────────────────────────────────────────────────────────

class Wd06Test(Base):
    def script(self):
        return [('A', 'withdrawn', self.world.app_withdraws), ('B', 'wait', None), ('B', 'room', None)]

    def test_pass_the_room_has_five_messages_the_gate_passed_and_the_send_is_409_with_no_left_line(self):
        self.passes('E-WD-06', *self.script())
        match = self.world.rows('matches')[0]
        self.assertIsNotNone(match.get('trust_passed_at'))
        self.assertEqual(len([m for m in self.world.rows('messages') if m['match_id'] == match['id']]), 5)
        self.assertEqual(self.two.b_job, {'nickname': self.world.nickname(A), 'count': 5})
        self.assertIn('token_hash', self.went('B', 'wait'))
        sends = [s for s in self.world.sent if s['path'].endswith('/messages') and s['method'] == 'POST']
        self.assertEqual([s['auth'] for s in sends], ['tok-2'])

    def test_a_server_that_lets_b_send_is_a_fail(self):
        self.world.rules['send_blocked'] = False
        self.fails('E-WD-06', *self.script(), words=('201',))

    def test_a_left_line_or_left_at_is_a_fail(self):
        def leave():
            self.world.app_withdraws()
            match = self.world.rows('matches')[0]
            self.world.rows('messages').append({'id': 'l', 'match_id': match['id'], 'sender_id': A, 'kind': 'left'})
        self.fails('E-WD-06', ('A', 'withdrawn', leave), ('B', 'wait', None), ('B', 'room', None), words=('나가기',))


# ── E-WD-07 오늘 카드 · 받은 수락 ────────────────────────────────────────────────────────────────────

class Wd07Test(Base):
    def script(self):
        return [('A', 'withdrawn', self.world.app_withdraws), ('B', 'wait', None)]

    def test_pass_a_leaves_b_today_and_inbox_and_the_card_detail_is_404(self):
        self.passes('E-WD-07', *self.script())
        details = [s for s in self.world.sent if re.fullmatch(r'/cards/[^/]+', s['path']) and s['path'] not in ('/cards/today', '/cards/acceptances')]
        self.assertEqual([s['auth'] for s in details], ['tok-2'])
        self.assertEqual(self.two.b_job, {'nickname': self.world.nickname(A)})

    def test_cards_that_still_show_the_withdrawn_person_are_a_fail(self):
        self.world.rules['suspended_cards'] = False
        self.fails('E-WD-07', *self.script(), words=('오늘',))

    def test_a_card_detail_that_still_opens_is_a_fail(self):
        self.world.rules['detail_hidden'] = False
        self.fails('E-WD-07', *self.script(), words=('404',))

    def test_it_is_blocked_when_the_card_or_the_acceptance_was_never_there(self):
        self.world.rules['suspended_cards'] = True
        with mock.patch.object(area5_two, '_today_cards', lambda run, account: set()):
            self.blocked('E-WD-07', *self.script(), words=('준비',))


# ── E-WD-08 새 카드 후보 ────────────────────────────────────────────────────────────────────────────

class Wd08Test(Base):
    def script(self):
        return [('A', 'withdrawn', self.world.app_withdraws), ('B', 'wait', None)]

    def test_pass_the_batch_gives_b_no_card_of_a(self):
        self.passes('E-WD-08', *self.script())
        self.assertEqual([[c['id'] for c in control] for control in self.issued], [[C]])
        self.assertFalse([c for c in self.world.rows('daily_cards') if c['owner_id'] == B and c['target_id'] == A])

    def test_a_candidate_query_that_keeps_the_withdrawn_is_a_fail(self):
        self.world.rules['active_candidates'] = False
        self.fails('E-WD-08', *self.script(), words=('후보',))

    def test_a_first_fail_is_not_run_again_after_the_batch(self):
        self.world.rules['active_candidates'] = False
        first = self.go('E-WD-08', *self.script())
        again = twodev.TWO['E-WD-08'](self.run_, FakeTwo(self, []))
        self.assertEqual(again, first)
        self.assertEqual(len(self.issued), 1)


# ── E-WD-09 내가 쓴 리뷰 ─────────────────────────────────────────────────────────────────────────────

class Wd09Test(Base):
    def script(self):
        return [('A', 'withdrawn', self.world.app_withdraws), ('B', 'wait', None)]

    def test_pass_the_review_leaves_bs_written_list(self):
        self.passes('E-WD-09', *self.script())
        review = self.world.rows('friend_reviews')[0]
        self.assertEqual((review['reviewer_id'], review['reviewee_id']), (B, A))
        self.assertEqual(self.two.b_job, {'nickname': self.world.nickname(A)})

    def test_a_written_list_that_keeps_the_withdrawn_is_a_fail(self):
        self.world.rules['written_hides'] = False
        self.fails('E-WD-09', *self.script(), words=('20e',))


if __name__ == '__main__':
    unittest.main()
