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

from e2e import area1, area2_time_batch, area2_two_accept, area5_two, tools, twodev
from e2e.test_area1 import CFG
from e2e.test_area2_two_accept import FakeTwo, World
from e2e.test_area3_safe import _who
from e2e.test_area5_wd import code_of
from e2e.tools import Reply, Run

REAL_ISSUE_CARDS = area5_two._issue_cards  # setUp 이 모듈의 것을 가짜로 바꾸기 전에 쥔다
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
        self.issued, self.subjects = [], []
        self.cut_after_fire, self.give_subjects = False, True
        area2_time_batch._FIRED.clear()
        self.addCleanup(area2_time_batch._FIRED.clear)
        patchers = [mock.patch.object(tools, 'call', self.world),
                    mock.patch.object(area2_two_accept, 'POLL', 0), mock.patch.object(area2_two_accept, 'SAVED', 0.05),
                    mock.patch.object(area2_two_accept, 'PEER', 0.05),
                    mock.patch.object(area5_two, '_region', lambda run: 'e2e'),
                    mock.patch.object(area5_two, '_issue_cards', self.fire)]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)
        from e2e import area3_phone5
        area3_phone5._FAILED.clear()
        self.addCleanup(area3_phone5._FAILED.clear)

    def fire(self, run, region, control, subjects=()):
        """가짜 daily-cards — 부른 것(대조군 · 대상)을 적고 배치가 나갔다고 [_FIRED] 에도 적는다(진짜 `_batch` 가 하는 일). 카드는 대조군 · 대상 모두에게."""
        self.issued.append(control)
        self.subjects.append(subjects)
        area2_time_batch._FIRED.append('daily-cards')
        if self.cut_after_fire:
            raise ConnectionResetError('끊김')
        self.world.issue([*control, *subjects] if self.give_subjects else list(control))

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
        steps = set(re.findall(r"(?:step|_twoLoginAfter)\('([\w-]+)'", text))
        for name in ('home', 'ready', 'login', 'withdrawn', 'tap', 'wait', 'room'):
            self.assertIn(name, steps)

    def test_only_the_a_side_reaches_the_final_delete_helper(self):
        text = dart('area5_two.dart')
        bodies = dict(zip(*[iter(re.split(r"(?m)^  '(E-WD-\d+/[AB])':", text.split('area5CasesTwo = {', 1)[1])[1:])] * 2))
        for key, body in bodies.items():
            with self.subTest(key):
                presses = '_twoWithdrawA' in body or '_twoA()' in body  # _twoA 는 _twoWithdrawA 를 부른다
                self.assertEqual(presses, key.endswith('/A'))
        self.assertNotIn('정말 영구 삭제', code_of(text))  # 글자는 area5_wd.dart 의 _wdForever 한 곳뿐
        helpers = re.split(r'(?m)^final Map', text)[0]
        self.assertIn('_wdWithdraw(tester)', helpers.split('Future<void> _twoWithdrawA', 1)[1].split('\n}\n', 1)[0])
        self.assertEqual(text.count('_wdWithdraw('), 1)  # 탈퇴 버튼은 _twoWithdrawA 안 한 곳에서만
        self.assertIn('await _twoWithdrawA(tester);', text.split('Area1Case _twoA()', 1)[1].split('});', 1)[0])

    def test_the_room_bubbles_are_counted_only_after_the_first_message_page_has_drawn(self):
        """방 머리말(닉네임 · 안내)은 메시지 첫 쪽보다 먼저 그려져 그 전에 세면 0건이다 — 세기 앞에 첫 말풍선을 기다린다."""
        body = dart('area5_two.dart').split("'E-WD-06/B'", 1)[1].split("'E-WD-07/A'", 1)[0]
        count = body.index('.evaluate().length')
        wait = body.index('await pumpUntil(tester, find.descendant(of: room, matching: find.byType(MessageBubble)));')
        self.assertLess(wait, count)
        self.assertLess(body.index('find.byType(TrustRevealBubble)'), body.index("step('room')"))
        self.assertLess(wait, body.index('find.byType(TrustRevealBubble)'))  # 카드 없음도 로딩이 끝난 뒤에 본다

    def test_each_case_limit_covers_the_deadline_plus_the_accounts_it_prepares(self):
        """가설 하나의 상한(CASE_LIMITS)은 두 기기 deadline 앞에 계정 준비가 더해진 시간을 담아야 한다 — 아니면 탈퇴(되돌릴 수 없음) 뒤에 시간 초과로 끊긴다."""
        accounts = {'E-WD-05': 1, 'E-WD-06': 2, 'E-WD-07': 2, 'E-WD-08': 3, 'E-WD-09': 2}
        deadline = {**{case: area5_two.LIMITS['deadline'] for case in accounts}, 'E-WD-08': area5_two.BATCH_LIMITS['deadline']}
        for case, count in accounts.items():
            with self.subTest(case):
                self.assertGreaterEqual(tools.CASE_LIMITS[case] - deadline[case], count * area5_two.PREP_ACCOUNT)

    def test_the_app_waits_for_the_pc_longer_than_the_pc_waits_for_the_app(self):
        """PC 가 B 를 기다리는 상한(BATCH_PEER · PEER)보다 B 앱의 `wait` 멈춤이 길어야 앱이 먼저 포기하지 않는다 — 08 은 배치라 900초."""
        text = dart('area5_two.dart')
        minutes = lambda name: int(re.search(rf'const {name} = Duration\(minutes: (\d+)\)', text).group(1)) * 60  # noqa: E731
        self.assertGreater(minutes('_twoBatchWait'), area5_two.BATCH_PEER)
        self.assertGreater(minutes('_twoLongWait'), area2_two_accept.PEER)
        body = text.split("'E-WD-08/B'", 1)[1].split("'E-WD-09/A'", 1)[0]
        self.assertIn('wait: _twoBatchWait', body)
        for case in ('E-WD-06/B', 'E-WD-07/B', 'E-WD-09/B'):  # 배치가 없는 가설은 기본 대기 그대로
            self.assertNotIn('wait: _twoBatchWait', text.split(f"'{case}'", 1)[1].split("'E-WD-", 1)[0], case)

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
        sends = [s for s in self.world.sent if s['path'].startswith('/chat/') and s['method'] == 'POST']
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

    def test_b_is_asked_to_get_a_card_too_so_a_zero_for_a_means_the_batch_served_b(self):
        self.passes('E-WD-08', *self.script())
        self.assertEqual([[s['id'] for s in subjects] for subjects in self.subjects], [[B]])  # 대상 B 를 _issue 에 넘긴다
        self.assertTrue([c for c in self.world.rows('daily_cards') if c['owner_id'] == B])  # B 는 카드를 받았다

    def test_a_batch_that_gave_b_nothing_is_a_fail_even_though_a_has_no_card(self):
        """대조군은 받았는데 B 는 한 장도 못 받았다 — "A 대상 0장" 은 참이어도 배치가 B 를 안 돌았다는 뜻이라 통과 아님."""
        self.give_subjects = False
        self.fails('E-WD-08', *self.script(), words=('B',))

    def test_b_waits_for_a_longer_for_the_batch_case_than_for_the_others(self):
        seen = []
        with mock.patch.object(twodev.Sync, 'wait', autospec=True, side_effect=lambda sync, name, seconds: seen.append((name, seconds)) or True):
            self.passes('E-WD-08', *self.script())
            self.setUp()  # 두 번째 가설은 깨끗한 가짜 서버에서
            self.passes('E-WD-09', *self.script())
        self.assertEqual(seen, [('a-out', 900), ('a-out', area2_two_accept.PEER)])  # 배치(A 흐름 + 최대 120 + 90 + 30초)는 420초에 빠듯하다
        self.assertEqual(area5_two.BATCH_PEER, 900)

    def test_a_cut_after_the_batch_went_out_is_blocked_and_never_calls_the_batch_again(self):
        self.cut_after_fire = True
        result, memo = self.go('E-WD-08', *self.retry_script())
        self.assertEqual(result, 'blocked', memo)
        self.assertIn(area2_time_batch.ALREADY, memo)
        self.assertEqual(len(self.issued), 1)  # daily-cards 는 하루 1장 — 두 번째 배치는 나가지 않는다

    def test_the_real_issue_cards_passes_the_subjects_on_to_the_batch_helper(self):
        """setUp 이 `_issue_cards` 를 가짜로 바꾸므로 진짜가 대상(subjects)을 `_issue` 로 넘기는지는 따로 본다."""
        calls = []
        with mock.patch.object(area2_time_batch, '_issue', lambda run, region, weekdays, **kw: calls.append(kw)):
            REAL_ISSUE_CARDS(self.run_, 'e2e', ['c'], ['b'])
        self.assertEqual(calls, [{'control': ['c'], 'subjects': ['b']}])

    def retry_script(self):
        """다시 하면 계정을 새로 만든다(A · B · 대조군 셋씩) — 앱이 탈퇴시키는 것은 그 시도의 A 다."""
        def withdraw_this_attempts_a():
            made = len([s for s in self.world.sent if s['path'] == '/auth/v1/admin/users' and s['method'] == 'POST'])
            self.world.app_withdraws(f'id-{made - 2}')
        return [('A', 'withdrawn', withdraw_this_attempts_a), ('B', 'wait', None)]

    def test_a_cut_before_the_batch_is_tried_once_more(self):
        calls = []
        real = self.fire

        def cut_first(run, region, control, subjects=()):
            calls.append(1)
            if len(calls) == 1:
                raise ConnectionResetError('끊김')  # 배치를 부르기 전(_FIRED 에 안 적힘)
            return real(run, region, control, subjects)
        with mock.patch.object(area5_two, '_issue_cards', cut_first):
            self.passes('E-WD-08', *self.retry_script())
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(self.issued), 1)

    def test_two_cuts_before_the_batch_are_blocked(self):
        def always_cut(run, region, control, subjects=()):
            raise ConnectionResetError('끊김')
        with mock.patch.object(area5_two, '_issue_cards', always_cut):
            self.blocked('E-WD-08', *self.retry_script(), words=('두 번',))

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
