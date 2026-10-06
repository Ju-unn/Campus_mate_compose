"""영역 3 안전 API 가설 시험 — 운영 없이 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3_safe`.

가짜 서버([SafeFake])는 영역 3 시험의 표 저장소에 신고 · 차단 · 지인 차단 · 카드 · 후보 · 정지 관문을 서버 규칙 그대로 얹었다.
올바른 서버면 pass, 규칙 하나를 어긴 서버(시험마다 [SafeFake] 를 한 군데 바꿈)면 fail 이어야 한다.
"""

import itertools
import re
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area2, area3_phone5, area3_safe, batch_gate, tools
from e2e.area1 import SEOUL
from e2e.test_area3 import PERMISSION, Base, Fake, mismatched_keys
from e2e.tools import ROOT, Reply

PROFILE_GONE = '프로필을 찾을 수 없어요'
MESSAGE_GONE = '메시지를 찾을 수 없어요'
REVIEW_GONE = '리뷰를 찾을 수 없어요'
ALREADY = '이미 신고를 완료했어요'
SUSPENDED = '이용이 제한된 계정이에요'
REASONS = {'abuse', 'sexual', 'spam', 'fake', 'other'}
# 정지를 보지 않는 문(로그인만 보는 get_caller). 나머지 API 는 전부 정지 403.
OPEN_FOR_SUSPENDED = ('/me/verification-status', '/me/consents', '/account/withdraw', '/cards/push-tokens')

API_ONLY = ('E-SAFE-10 E-SAFE-12 E-SAFE-14 E-SAFE-16 E-SAFE-19 E-SAFE-20 E-SAFE-21 E-SAFE-23 E-SAFE-24 E-SAFE-29 E-SAFE-33 '
            'E-SAFE-34 E-SAFE-44 E-SAFE-47 E-SAFE-48 E-SAFE-49 E-SAFE-51 E-SAFE-52 E-SAFE-54 E-SAFE-56 E-SAFE-58 '
            'E-SAFE-59 E-SAFE-62').split()


def _who(sent):
    return f"id-{sent['auth'].removeprefix('tok-')}"


class SafeFake(Fake):
    """영역 3 의 가짜 서버 + 안전 규칙. 프로필은 {id: 칸} 으로 들고, 온보딩 끝(bio)에서 active 가 된다(운영과 같다).
    번호는 04-1 저장 때 그대로 기억해 HMAC 대신 쓴다. 시험이 [rules] 의 값을 바꿔 어긋난 서버를 만든다."""

    def __init__(self):
        super().__init__()
        self.profiles = {}
        self.phones = {}
        self.rules = {'hide_at': 3, 'auto_hide': True, 'gate_open': set(OPEN_FOR_SUSPENDED), 'gate_header': True,
                      'blocks_rematch': False, 'suspended_cards': True, 'active_candidates': True, 'contact_both_ways': True,
                      'note_kept': False, 'foreign_contact_delete': False,
                      'owner_contact_delete': True, 'reported_leave_candidates': False, 'owners_see_hidden': False,
                      'gate_writes': False, 'block_every_report': False,
                      'report_limit': 10, 'report_window_hours': 24}
        for method, pattern, handler in (
                ('POST', r'/profile-onboarding/basic-info', self._basic), ('POST', r'/profile-onboarding/bio', self._bio),
                ('POST', r'/reports', self._report), ('POST', r'/blocks/[^/]+', self._block),
                ('DELETE', r'/blocks/[^/]+', self._unblock), ('POST', r'/contact-blocks', self._contact_add),
                ('DELETE', r'/contact-blocks/[^/]+', self._contact_remove), ('GET', r'/matching/candidates', self._candidates),
                ('GET', r'/cards/today', self._today), ('GET', r'/cards/acceptances', self._acceptances),
                ('POST', r'/cards/[^/]+/decision', self._decide), ('POST', r'/rest/v1/rpc/card_issue_owners', self._owners),
                ('GET', r'/rest/v1/rpc/card_issue_owners', self._owners)):
            self.on(method, pattern, handler)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        path = url.split('://', 1)[-1].split('/', 1)[-1].split('?')[0]
        token = (headers or {}).get('Authorization', '').removeprefix('Bearer ')
        if url.startswith('https://api.test') and token.startswith('tok-'):
            me = self.profile(f"id-{token.removeprefix('tok-')}")
            if me['status'] == 'suspended' and not any(f'/{path}'.startswith(p) for p in self.rules['gate_open']):
                if self.rules['gate_writes']:  # 막으면서도 쓰는 서버
                    self.rows('push_tokens').append({'profile_id': me['id'], 'token': path})
                self.sent.append({'method': method, 'path': f'/{path}', 'query': {}, 'body': body, 'auth': token,
                                  'apikey': None, 'gated': True})
                head = {'X-Account-Status': 'suspended'} if self.rules['gate_header'] else {}
                return Reply(403, {'detail': SUSPENDED}, head)
        return super().__call__(method, url, headers, body, raw)

    # ── 표 ──
    def profile(self, pid):
        return self.profiles.setdefault(pid, {'id': pid, 'status': 'pending', 'auto_hidden_at': None, 'gender': None})

    def _table(self, method, name, sent):
        query, body = sent['query'], sent['body']
        if name == 'profiles' and 'id' in query:
            row = self.profile(query['id'][3:])
            if method == 'PATCH':
                row.update(body)
                return Reply(200, None)
            return Reply(200, [dict(row)])
        if name == 'profile_private' and method == 'PATCH' and body.get('phone_hmac', 1) is None:
            self.phones.pop(query['profile_id'][3:], None)
            return Reply(200, None)
        if method == 'POST':
            if mismatched_keys(body):
                return mismatched_keys(body)
            for row in body if isinstance(body, list) else [body]:
                row.setdefault('id', str(uuid.uuid4()))
                if name == 'messages':
                    row.setdefault('kind', 'text')
                if name == 'friend_reviews':
                    row.setdefault('status', 'visible')
        return super()._table(method, name, sent)

    def rows(self, table):
        return self.tables.setdefault(table, [])

    def matched(self, x, y):
        return any({m['profile_a'], m['profile_b']} == {x, y} for m in self.rows('matches'))

    def blocked(self, x, y):
        return any({b['blocker_id'], b['blocked_id']} == {x, y} for b in self.rows('blocks'))

    def contact_blocked(self, x, y):
        def one_way(owner, other):
            return other in self.phones and any(c['owner_id'] == owner and c['number'] == self.phones[other]
                                                for c in self.rows('contact_blocks'))
        return one_way(x, y) or (self.rules['contact_both_ways'] and one_way(y, x))

    def hidden(self, me, other):
        p = self.profile(other)
        return (self.blocked(me, other) or self.contact_blocked(me, other) or p['auto_hidden_at']
                or (p['status'] != 'active' and self.rules['suspended_cards']))

    def reporters(self, target):
        return len({r['reporter_id'] for r in self.rows('reports') if r['target_profile_id'] == target and r['status'] == 'open'})

    def decided(self, card_id):
        return next((d for d in self.rows('card_decisions') if d['card_id'] == card_id), None)

    # ── 온보딩 ──
    def _basic(self, sent):
        self.phones[_who(sent)] = sent['body'].get('phone_number')
        return Reply(200, {})

    def _bio(self, sent):
        self.profile(_who(sent))['status'] = 'active'
        return Reply(200, {})

    # ── 신고 · 차단 ──
    def _leave(self, me, match):
        if not any(m.get('kind') == 'left' and m['sender_id'] == me and m['match_id'] == match['id'] for m in self.rows('messages')):
            self.rows('messages').append({'id': str(uuid.uuid4()), 'match_id': match['id'], 'sender_id': me, 'kind': 'left'})

    def _match_of(self, x, y):
        return next((m for m in self.rows('matches') if {m['profile_a'], m['profile_b']} == {x, y}), None)

    def _report(self, sent):
        me, body = _who(sent), sent['body']
        note = (body.get('reason_note') or '').strip()
        if body['reason'] not in REASONS or (body['reason'] == 'other' and not 1 <= len(note) <= 200):
            return Reply(422, {'detail': 'reason'})
        if body['reason'] != 'other' and not self.rules['note_kept']:
            note = None
        kind, target_id = body['target_type'], body['target_id']
        if kind == 'profile':
            target, match = target_id, self._match_of(me, target_id)
            if target == me or not match:
                return Reply(404, {'detail': PROFILE_GONE})
        elif kind == 'message':
            msg = next((m for m in self.rows('messages') if m['id'] == target_id), None)
            match = msg and next((m for m in self.rows('matches') if m['id'] == msg['match_id']), None)
            if not match or me not in (match['profile_a'], match['profile_b']) or msg['sender_id'] == me or msg['kind'] != 'text':
                return Reply(404, {'detail': MESSAGE_GONE})
            target = msg['sender_id']
        else:
            review = next((r for r in self.rows('friend_reviews') if r['id'] == target_id), None)
            if not review or review['reviewee_id'] != me or review['status'] != 'visible':
                return Reply(404, {'detail': REVIEW_GONE})
            target, match = review['reviewer_id'], None
        if any((r['reporter_id'], r['target_type'], r['target_id']) == (me, kind, target_id) for r in self.rows('reports')):
            return Reply(409, {'detail': ALREADY})
        since = datetime.now(timezone.utc) - timedelta(hours=self.rules['report_window_hours'])
        if sum(r['reporter_id'] == me and datetime.fromisoformat(r['created_at']) >= since
               for r in self.rows('reports') if r.get('created_at')) >= self.rules['report_limit']:
            return Reply(429, {'detail': '오늘은 더 신고할 수 없어요'})
        if match:
            if self.rules['block_every_report'] or not any((b['blocker_id'], b['blocked_id']) == (me, target)
                                                           for b in self.rows('blocks')):
                self.rows('blocks').append({'blocker_id': me, 'blocked_id': target})
            self._leave(me, match)
        self.rows('reports').append({'id': str(uuid.uuid4()), 'reporter_id': me, 'target_type': kind, 'target_id': target_id,
                                     'target_profile_id': target, 'reason': body['reason'], 'reason_note': note,
                                     'status': 'open', 'resolved_at': None, 'created_at': datetime.now(timezone.utc).isoformat()})
        if (match or not self.rules['auto_hide']) and self.reporters(target) >= self.rules['hide_at'] \
                and self.profile(target)['auto_hidden_at'] is None:
            self.profile(target)['auto_hidden_at'] = datetime.now(timezone.utc).isoformat()
        return Reply(201, {'ok': True})

    def _block(self, sent):
        me, target = _who(sent), sent['path'].rsplit('/', 1)[1]
        match = self._match_of(me, target) if target != me else None
        if not match:
            return Reply(404, {'detail': PROFILE_GONE})
        if not any((b['blocker_id'], b['blocked_id']) == (me, target) for b in self.rows('blocks')):
            self.rows('blocks').append({'blocker_id': me, 'blocked_id': target})
        self._leave(me, match)
        return Reply(200, {'ok': True})

    def _unblock(self, sent):
        me, target = _who(sent), sent['path'].rsplit('/', 1)[1]
        self.tables['blocks'] = [b for b in self.rows('blocks') if (b['blocker_id'], b['blocked_id']) != (me, target)]
        return Reply(200, {'ok': True})

    def _contact_add(self, sent):
        numbers = sent['body']['numbers']
        if not 1 <= len(numbers) <= 200:
            return Reply(422, {'detail': 'numbers'})
        out = []
        for number in numbers:
            if not number.startswith('010'):
                out.append(None)
                continue
            row = next((c for c in self.rows('contact_blocks') if c['owner_id'] == _who(sent) and c['number'] == number), None)
            if row is None:
                row = {'id': str(uuid.uuid4()), 'owner_id': _who(sent), 'number': number}
                self.rows('contact_blocks').append(row)
            out.append({'id': row['id'], 'created_at': 'now'})
        return Reply(200, {'blocks': out})

    def _contact_remove(self, sent):
        block_id = sent['path'].rsplit('/', 1)[1]
        self.tables['contact_blocks'] = [c for c in self.rows('contact_blocks') if not (
            c['id'] == block_id and ((c['owner_id'] == _who(sent) and self.rules['owner_contact_delete']) or self.rules['foreign_contact_delete']))]
        return Reply(200, {'ok': True})

    # ── 후보 · 카드 ──
    def _candidates(self, sent):
        me = _who(sent)
        mine = self.profile(me)
        vectors = {v['profile_id'] for v in self.rows('profile_vectors')}
        out = []
        for pid, p in self.profiles.items():
            if pid == me or pid not in vectors or p['gender'] == mine['gender'] \
                    or (p['status'] != 'active' and self.rules['active_candidates']):
                continue
            if self.matched(me, pid) and not (self.rules['blocks_rematch'] and not self.blocked(me, pid)):
                continue
            # 후보 SQL 은 정지를 status 로 따로 본다(위) — 카드 숨김([hidden])과 같은 규칙이지만 다른 코드다.
            if self.blocked(me, pid) or self.contact_blocked(me, pid) or p['auto_hidden_at'] or any(c['owner_id'] == me and c['target_id'] == pid and not self.decided(c['id'])
                                           for c in self.rows('daily_cards')):
                continue
            if self.rules['reported_leave_candidates'] and self.reporters(pid):
                continue
            out.append({'profile_id': pid, 'score': 0.5})
        return Reply(200, {'candidates': out})

    def _today(self, sent):
        me = _who(sent)
        cards = [c for c in self.rows('daily_cards') if c['owner_id'] == me and not self.decided(c['id'])
                 and not self.hidden(me, c['target_id'])]
        return Reply(200, {'cards': [{'card_id': c['id'], 'profile': {'profile_id': c['target_id']}} for c in cards]})

    def _acceptances(self, sent):
        me = _who(sent)
        rows = [c for c in self.rows('daily_cards') if c['target_id'] == me and (self.decided(c['id']) or {}).get('decision') == 'accept'
                and not self.hidden(me, c['owner_id'])]
        return Reply(200, {'acceptances': [{'card_id': c['id'], 'profile': {'profile_id': c['owner_id']}} for c in rows]})

    def _decide(self, sent):
        self.rows('card_decisions').append({'card_id': sent['path'].split('/')[2], 'decision': sent['body']['decision']})
        return Reply(200, {'ok': True})

    def _owners(self, sent):
        pid = sent['query']['profile_id'][3:]
        p = self.profile(pid)
        live = any(c['owner_id'] == pid and not self.decided(c['id']) for c in self.rows('daily_cards'))
        ok = p['status'] == 'active' and (not p['auto_hidden_at'] or self.rules['owners_see_hidden']) and not live \
            and any(v['profile_id'] == pid for v in self.rows('profile_vectors'))
        return Reply(200, [{'profile_id': pid, 'region_group': 'e2e'}] if ok else [])


class SafeBase(Base):
    def setUp(self):
        super().setUp()
        self.fake = SafeFake()
        patcher = mock.patch.object(tools, 'call', self.fake)
        patcher.start()
        self.addCleanup(patcher.stop)

    def case(self, name):
        return area3_safe.attempt(self.run_, name)

    def passes(self, name):
        result, note = self.case(name)
        self.assertEqual(result, 'pass', note)
        return note

    def fails(self, name, *words):
        result, note = self.case(name)
        self.assertEqual(result, 'fail', note)
        for word in words:
            self.assertIn(word, note)
        return note


class RegistryTest(unittest.TestCase):
    def test_bundle_is_exactly_the_23_api_only_safety_hypotheses(self):
        self.assertEqual(area3_safe.BUNDLES, {'area3-safe-api': API_ONLY})
        self.assertEqual(sorted(area3_safe.CASES), sorted(API_ONLY))


class SafetyNetTest(SafeBase):
    def test_every_case_ends_as_fail_or_blocked_when_the_server_is_down(self):
        down = Fake()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down):
            for name in API_ONLY:
                result, note = self.case(name)
                self.assertIn(result, ('fail', 'blocked'), name)
                self.assertIsInstance(note, str, name)


class ReportRulesTest(SafeBase):
    def test_10_note_rules(self):
        self.passes('E-SAFE-10')
        sent = [s['body'] for s in self.fake.by('POST', '/reports')]
        self.assertEqual([(b['reason'], b.get('reason_note')) for b in sent],
                         [('other', None), ('other', '가' * 201), ('hate', None), ('spam', 'x')])
        self.assertEqual([r['reason_note'] for r in self.fake.rows('reports')], [None])

    def test_10_fails_when_a_note_on_another_reason_is_kept(self):
        self.fake.rules['note_kept'] = True
        self.fails('E-SAFE-10', 'reason_note')

    def test_10_fails_when_an_empty_other_is_accepted(self):
        self.fake.on('POST', r'/reports', Reply(201, {'ok': True}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        self.fails('E-SAFE-10', '201')

    def test_10_fails_when_a_rejected_report_still_blocks(self):
        original = self.fake._report

        def blocks_first(sent):
            reply = original(sent)
            if reply[0] == 422:  # 차단을 먼저 하고 사유 검사에서 멈추는 서버
                self.fake.rows('blocks').append({'blocker_id': _who(sent), 'blocked_id': sent['body']['target_id']})
            return reply
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), blocks_first))
        self.fails('E-SAFE-10', 'blocks')

    def test_10_fails_when_a_rejected_report_is_still_saved(self):
        original = self.fake._report

        def leaky(sent):
            reply = original(sent)
            if reply[0] == 422:  # 거절하고도 행을 남기는 서버
                self.fake.rows('reports').append({'id': str(uuid.uuid4()), 'reporter_id': _who(sent), 'reason': 'other',
                                                  'target_type': 'leak', 'target_id': str(uuid.uuid4()),
                                                  'reason_note': None, 'target_profile_id': sent['body']['target_id'],
                                                  'status': 'open'})
            return reply
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), leaky))
        self.fails('E-SAFE-10', '422 뒤')

    def test_12_unmatched_and_self_are_404_and_a_matched_control_is_201(self):
        self.passes('E-SAFE-12')
        bodies = [(s['auth'], s['body']['target_id']) for s in self.fake.by('POST', '/reports')]
        self.assertEqual(bodies[:2], [('tok-1', 'id-2'), ('tok-1', 'id-1')])  # 매칭 없는 C, 나 자신
        self.assertEqual(len(self.fake.rows('reports')), 1)  # 대조군 한 건뿐

    def test_12_fails_when_every_report_is_404(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), Reply(404, {'detail': PROFILE_GONE})))
        self.fails('E-SAFE-12', '대조군')

    def test_14_profile_and_two_messages_are_three_reports_one_block_one_left_line(self):
        self.passes('E-SAFE-14')
        kinds = [s['body']['target_type'] for s in self.fake.by('POST', '/reports')]
        self.assertEqual(kinds, ['profile', 'message', 'message'])
        self.assertEqual(len(self.fake.rows('reports')), 3)

    def test_14_fails_when_a_second_report_on_the_same_person_is_409(self):
        original = self.fake._report

        def per_person(sent):
            if any(r['reporter_id'] == _who(sent) for r in self.fake.rows('reports')):
                return Reply(409, {'detail': ALREADY})
            return original(sent)
        self.fake.handlers.insert(0, ('POST', re.compile(r'/reports'), per_person))
        self.fails('E-SAFE-14', '409')

    def test_14_fails_when_every_report_adds_a_block_row(self):
        self.fake.rules['block_every_report'] = True
        self.fails('E-SAFE-14', 'blocks')

    def test_14_fails_when_every_report_adds_a_left_line(self):
        original = self.fake._leave
        self.fake._leave = lambda me, match: (self.fake.rows('messages').append(
            {'id': str(uuid.uuid4()), 'match_id': match['id'], 'sender_id': me, 'kind': 'left'}))
        self.addCleanup(setattr, self.fake, '_leave', original)
        self.fails('E-SAFE-14', '나감 줄')


class DailyReportLimitTest(SafeBase):
    def test_16_the_eleventh_is_429_until_one_of_the_ten_passes_24_hours_then_201(self):
        self.passes('E-SAFE-16')
        self.assertEqual(self.fake.count('reports', reporter_id='id-1'), 1)  # 넣은 열 건은 지워지고 API 로 낸 한 건만 남는다

    def test_16_fails_when_the_limit_never_applies(self):
        self.fake.rules['report_limit'] = 10 ** 6
        self.fails('E-SAFE-16', '429')

    def test_16_fails_when_a_report_past_24_hours_still_counts(self):
        self.fake.rules['report_window_hours'] = 10 ** 6
        self.fails('E-SAFE-16', '201')

    def test_16_fails_when_the_window_is_shorter_than_a_day(self):
        self.fake.rules['report_window_hours'] = 0.5
        self.fails('E-SAFE-16', '429')


class AutoHideTest(SafeBase):
    def test_19_two_reporters_do_not_hide(self):
        self.passes('E-SAFE-19')
        self.assertIsNone(self.fake.profile('id-1')['auto_hidden_at'])

    def test_19_fails_when_two_reporters_hide(self):
        self.fake.rules['hide_at'] = 2
        self.fails('E-SAFE-19', 'auto_hidden_at')

    def test_19_is_blocked_when_the_target_is_not_a_candidate_to_begin_with(self):
        self.fake.on('GET', r'/matching/candidates', Reply(200, {'candidates': []}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        self.assertEqual(self.case('E-SAFE-19')[0], 'blocked')

    def test_19_fails_when_reports_alone_drop_the_target_from_candidates(self):
        self.fake.rules['reported_leave_candidates'] = True
        self.fails('E-SAFE-19', 'F 의 후보')

    def test_20_one_person_counts_once(self):
        self.passes('E-SAFE-20')
        self.assertEqual(len(self.fake.rows('reports')), 4)

    def test_20_fails_when_every_report_counts(self):
        self.fake.reporters = lambda target: len([r for r in self.fake.rows('reports') if r['target_profile_id'] == target])
        self.fails('E-SAFE-20', 'auto_hidden_at')

    def test_21_review_report_counts_but_does_not_hide(self):
        self.passes('E-SAFE-21')
        kinds = [s['body']['target_type'] for s in self.fake.by('POST', '/reports')]
        self.assertEqual(kinds, ['profile', 'profile', 'friend_review', 'profile'])

    def test_21_fails_when_the_profile_report_after_it_does_not_hide(self):
        self.fake.rules['hide_at'] = 99
        self.fails('E-SAFE-21', 'G 의 프로필')

    def test_21_fails_when_the_review_report_hides(self):
        self.fake.rules['auto_hide'] = False  # match 없는 신고도 가린다
        self.fails('E-SAFE-21', 'auto_hidden_at')

    def test_23_hidden_person_leaves_cards_inbox_and_issue_list(self):
        self.passes('E-SAFE-23')
        self.assertTrue(self.fake.profile('id-1')['auto_hidden_at'])

    def test_23_fails_when_the_inbox_still_shows_the_hidden_person(self):
        self.fake.on('GET', r'/cards/acceptances', lambda s: Reply(200, {'acceptances': [
            {'card_id': c['id'], 'profile': {'profile_id': c['owner_id']}} for c in self.fake.rows('daily_cards')
            if c['target_id'] == _who(s) and self.fake.decided(c['id'])]}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        self.fails('E-SAFE-23', '수락함')

    def test_23_fails_when_the_hidden_person_still_gets_cards(self):
        self.fake.rules['owners_see_hidden'] = True
        self.fails('E-SAFE-23', '지급 대상')

    def test_24_dismissed_reports_stop_counting(self):
        self.passes('E-SAFE-24')
        statuses = {r['status'] for r in self.fake.rows('reports')}
        self.assertEqual(statuses, {'dismissed', 'open'})

    def test_24_fails_when_dismissed_reports_still_count(self):
        self.fake.reporters = lambda target: len({r['reporter_id'] for r in self.fake.rows('reports') if r['target_profile_id'] == target})
        self.fails('E-SAFE-24', 'auto_hidden_at')


class BlockTest(SafeBase):
    def test_29_block_needs_a_match_and_twice_is_one_row(self):
        self.passes('E-SAFE-29')
        self.assertEqual(self.fake.rows('blocks'), [{'blocker_id': 'id-1', 'blocked_id': 'id-2'}])

    def test_29_fails_when_second_block_adds_a_row(self):
        self.fake.on('POST', r'/blocks/[^/]+', lambda s: (self.fake.rows('blocks').append(
            {'blocker_id': _who(s), 'blocked_id': s['path'].rsplit('/', 1)[1]}), Reply(200, {}))[1])
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        self.fails('E-SAFE-29')

    def test_33_unblocked_matched_pair_stays_out_of_candidates(self):
        note = self.passes('E-SAFE-33')
        self.assertIn('문구', note)
        self.assertEqual(self.fake.rows('blocks'), [])

    def test_33_fails_when_unblock_brings_them_back(self):
        self.fake.rules['blocks_rematch'] = True
        self.fails('E-SAFE-33', '후보')

    def test_34_app_cannot_touch_safety_tables(self):
        for table in ('blocks', 'reports', 'contact_blocks'):
            for method in ('GET', 'POST'):
                self.fake.handlers.insert(0, (method, re.compile(f'/rest/v1/{table}'), lambda s, t=table, m=method: (
                    PERMISSION if s['apikey'] == 'anon' else self.fake._table(m, t, s))))
        self.passes('E-SAFE-34')
        anon = [s['path'].rsplit('/', 1)[1] for s in self.fake.sent if s['apikey'] == 'anon' and s['path'].startswith('/rest/')]
        self.assertEqual(sorted(set(anon)), ['blocks', 'contact_blocks', 'reports'])
        self.assertEqual(len(anon), 6)

    def test_34_fails_when_select_returns_empty_instead_of_denying(self):
        self.fails('E-SAFE-34', 'select')


class ContactBlockTest(SafeBase):
    def test_44_201_and_empty_are_422(self):
        self.passes('E-SAFE-44')
        sizes = [len(s['body']['numbers']) for s in self.fake.by('POST', '/contact-blocks')]
        self.assertEqual(sizes, [201, 0, 1])

    def test_44_fails_when_201_is_accepted(self):
        self.fake.on('POST', r'/contact-blocks', Reply(200, {'blocks': []}))
        self.fake.handlers.insert(0, self.fake.handlers.pop())
        self.fails('E-SAFE-44', '201')

    def test_47_someone_elses_delete_leaves_the_row(self):
        self.passes('E-SAFE-47')
        deletes = [s['auth'] for s in self.fake.by('DELETE', '/contact-blocks/')]
        self.assertEqual(deletes, ['tok-2', 'tok-1'])  # C 먼저, 대조군으로 주인 B
        self.assertEqual(self.fake.rows('contact_blocks'), [])

    def test_47_fails_when_a_stranger_can_delete(self):
        self.fake.rules['foreign_contact_delete'] = True
        self.fails('E-SAFE-47', '지워짐')

    def test_47_fails_when_nobody_can_delete_so_untouched_proves_nothing(self):
        self.fake.rules['owner_contact_delete'] = False
        self.fails('E-SAFE-47', '대조군')

    def test_48_no_phone_hash_is_not_filtered_but_a_hashed_control_is(self):
        self.passes('E-SAFE-48')
        self.assertEqual(len(self.fake.by('POST', '/contact-blocks')[0]['body']['numbers']), 2)

    def test_48_fails_when_contact_blocks_filter_nobody(self):
        self.fake.contact_blocked = lambda x, y: False
        self.fails('E-SAFE-48', '대조군')

    def test_49_cards_and_acceptances_disappear_on_both_sides(self):
        self.passes('E-SAFE-49')
        self.assertEqual(len(self.fake.rows('daily_cards')), 4)

    def test_49_fails_when_only_the_blocker_side_is_hidden(self):
        self.fake.rules['contact_both_ways'] = False
        self.fails('E-SAFE-49', 'F')


class SuspendedTest(SafeBase):
    def test_51_every_verified_route_is_403_with_the_header(self):
        self.passes('E-SAFE-51')
        hits = {(s['method'], s['path']) for s in self.fake.sent if s.get('gated')}  # 관문이 막은 요청 — 경로마다 하나
        self.assertEqual(len(hits), len(area3_safe.VERIFIED_ROUTES))

    def test_51_fails_naming_the_route_that_lets_a_suspended_account_in(self):
        self.fake.rules['gate_open'] |= {'/blocks'}
        self.fails('E-SAFE-51', 'GET /blocks')

    def test_51_fails_when_a_suspended_request_still_writes(self):
        self.fake.rules['gate_writes'] = True
        self.fails('E-SAFE-51', 'DB 가 바뀜')

    def test_51_fails_without_the_header(self):
        self.fake.rules['gate_header'] = False
        self.fails('E-SAFE-51', 'X-Account-Status')

    @unittest.skipUnless((ROOT / 'backend' / 'app' / 'main.py').exists(), '백엔드 코드가 없다')
    def test_51_route_list_is_exactly_the_servers_verified_routes(self):
        # 서버에 새 경로가 생기면 여기서 걸린다 — "모든 경로" 가 조용히 줄지 않게.
        sys.path.insert(0, str(ROOT / 'backend'))
        self.addCleanup(sys.path.remove, str(ROOT / 'backend'))
        try:
            from app.core.deps import get_verified_caller
            from app.main import app
            from fastapi.routing import APIRoute
        except ImportError as e:
            self.skipTest(f'백엔드 의존성이 없다: {e}')

        def flat(routes):
            for r in routes:
                if isinstance(r, APIRoute):
                    yield r
                else:
                    # fastapi 0.14x 는 include_router 를 _IncludedRouter 로 감싼다(원래 라우터는 original_router).
                    yield from flat(getattr(r, 'routes', None) or getattr(getattr(r, 'original_router', None), 'routes', []))

        def gated(dep):
            return any(d.call is get_verified_caller or gated(d) for d in dep.dependencies)
        server = {f'{m} {r.path}' for r in flat(app.routes) if gated(r.dependant) for m in r.methods}
        self.assertEqual(set(area3_safe.VERIFIED_ROUTES), server)

    def test_52_three_doors_open_and_two_closed(self):
        note = self.passes('E-SAFE-52')
        self.assertIn('설계 확인', note)
        order = [s['path'] for s in self.fake.sent if s['auth'] == 'tok-1' and not s['path'].startswith(('/rest/', '/auth/', '/storage/'))
                 and s['path'] in ('/student-verification', '/school-info', '/me/verification-status', '/me/consents', '/account/withdraw')][-5:]  # 앞은 계정 공장의 동의 · 학과 저장
        self.assertEqual(order[-1], '/account/withdraw')  # 탈퇴는 마지막 — 그 뒤로는 토큰이 401
        self.assertEqual(sorted(order), sorted(['/student-verification', '/school-info', '/me/verification-status',
                                                '/me/consents', '/account/withdraw']))

    def test_52_fails_when_school_info_lets_a_suspended_account_in(self):
        self.fake.rules['gate_open'] |= {'/school-info'}
        self.fails('E-SAFE-52', 'school-info')

    def test_54_suspended_person_leaves_candidates_issue_list_and_cards(self):
        self.passes('E-SAFE-54')
        self.assertEqual(self.fake.profile('id-1')['status'], 'suspended')
        self.assertEqual(self.fake.rows('daily_cards'), [])  # 후보를 볼 때 카드가 섞이지 않게 지웠다

    def test_54_fails_when_candidates_still_show_the_suspended_person(self):
        # 살아 있는 카드도 후보를 막으므로, 카드를 지우지 않고 보면 이 어긋남을 못 잡는다.
        self.fake.rules['active_candidates'] = False
        self.fails('E-SAFE-54', 'F 의 후보')

    def test_54_fails_when_cards_still_show_the_suspended_person(self):
        self.fake.rules['suspended_cards'] = False
        self.fails('E-SAFE-54', '오늘 카드')


class BatchBase(SafeBase):
    """운영 배치(chat-gate · cleanup)를 흉내 내는 가짜 gcloud · 시계(화요일 14:20) · 통과 기록 파일. 실제 호출은 0건이다.
    서버 규칙은 chat/batch_router.py run_chat_gate(한쪽이라도 정지 · 탈퇴면 건너뜀)와 account/batch_router.py run_cleanup(탈퇴 30일 · 처리 끝난 지 1년 신고 · 만료된 재가입 제한)."""

    def setUp(self):
        super().setUp()
        area3_phone5._FAILED.clear()  # 배치 뒤 fail 의 기억은 시험끼리 새지 않게
        self.clock, self.calls, self.batch_works, self.cleanups = [datetime(2026, 10, 6, 14, 20, tzinfo=SEOUL)], [], True, 0
        self.fake.rules.update({'gate_skips_gone': True, 'report_by_created': False, 'report_days': 365, 'rerun_eats': False,
                                'sweeps_blocks': True, 'report_cascade': False, 'keep_reporter': False, 'snapshot_wiped': False})
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        for patcher in (mock.patch.object(batch_gate, 'now_seoul', lambda: self.clock[0]),
                        mock.patch.object(batch_gate, 'HISTORY', Path(folder.name) / 'runs.jsonl'),
                        mock.patch.object(tools, 'batch', self.gcloud),
                        mock.patch.object(area2, '_mine', lambda run: {u['id'] for u in self.fake.users}),
                        mock.patch('time.monotonic', side_effect=itertools.count()),  # 기다림이 진짜 시간을 안 쓴다
                        mock.patch('time.sleep')):
            patcher.start()
            self.addCleanup(patcher.stop)

    def gcloud(self, name):
        self.calls.append(name)
        if self.batch_works:
            {'chat-gate': self.sim_gate, 'cleanup': self.sim_cleanup}[name]()

    def sim_gate(self):
        now = datetime.now(timezone.utc)
        for match in self.fake.rows('matches'):
            ids = [p['profile_id'] for p in self.fake.rows('match_participants') if p['match_id'] == match['id']]
            gone = any(self.fake.profile(i)['status'] in ('suspended', 'withdrawn') for i in ids)
            if match.get('chat_closed_at') or (gone and self.fake.rules['gate_skips_gone']) or not match.get('created_at'):
                continue
            if now - datetime.fromisoformat(match['created_at']) >= timedelta(hours=48):
                match['chat_closed_at'] = now.isoformat()

    def sim_cleanup(self):
        rules, now = self.fake.rules, datetime.now(timezone.utc)
        for pid, row in list(self.fake.profiles.items()):
            if row['status'] == 'withdrawn' and now - datetime.fromisoformat(row['withdrawn_at']) >= timedelta(days=30):
                del self.fake.profiles[pid]
                self.fake.users[:] = [u for u in self.fake.users if u['id'] != pid]
                if rules['report_cascade']:
                    self.fake.tables['reports'] = [r for r in self.fake.rows('reports') if r['reporter_id'] != pid]
                for r in self.fake.rows('reports'):
                    if r['reporter_id'] == pid and not rules['keep_reporter']:
                        r['reporter_id'] = None
                        if rules['snapshot_wiped']:
                            r['target_snapshot'] = {}
        column = 'created_at' if rules['report_by_created'] else 'resolved_at'
        cutoff = now - timedelta(days=rules['report_days'])
        eat = rules['rerun_eats'] and self.cleanups > 0
        self.fake.tables['reports'] = [r for r in self.fake.rows('reports')
                                       if not ((r.get(column) and datetime.fromisoformat(r[column]) < cutoff) or (eat and r['status'] != 'open'))]
        if rules['sweeps_blocks']:
            self.fake.tables['signup_blocks'] = [b for b in self.fake.rows('signup_blocks')
                                                 if datetime.fromisoformat(b['blocked_until']) >= now]
        self.cleanups += 1

    def at(self, hour, minute):
        self.clock[0] = self.clock[0].replace(hour=hour, minute=minute)

    def assertBlocked(self, name, *words):
        result, note = self.case(name)
        self.assertEqual(result, 'blocked', note)
        for word in words:
            self.assertIn(word, note)


class SuspendedRoomGateTest(BatchBase):
    def test_56_passes_and_calls_the_gate_once(self):
        self.passes('E-SAFE-56')
        self.assertEqual(self.calls, ['chat-gate'])

    def test_56_fails_when_the_gate_closes_a_room_with_a_suspended_person(self):
        self.fake.rules['gate_skips_gone'] = False
        self.fails('E-SAFE-56', '닫힘')

    def test_56_fails_when_the_room_row_is_gone_instead_of_passing_as_not_closed(self):
        real = self.sim_gate

        def eat():
            real()
            self.fake.tables['matches'] = [m for m in self.fake.rows('matches') if m.get('chat_closed_at')]  # 확인용 방만 남긴다

        with mock.patch.object(self, 'sim_gate', eat):
            self.fails('E-SAFE-56', 'matches 행')

    def test_56_is_blocked_by_the_clock_and_never_calls_gcloud(self):
        self.at(14, 57)
        self.assertBlocked('E-SAFE-56', '15:06')
        self.assertEqual(self.calls, [])

    def test_56_is_blocked_when_the_batch_did_not_run(self):
        self.batch_works = False
        self.assertBlocked('E-SAFE-56', '확인용 방')


class ReportCleanupTest(BatchBase):
    def test_58_passes_and_leaves_no_test_reports(self):
        self.passes('E-SAFE-58')
        self.assertEqual(self.calls, ['cleanup'])
        self.assertEqual(self.fake.rows('reports'), [])

    def test_58_fails_when_the_cutoff_is_created_at(self):
        self.fake.rules['report_by_created'] = True
        self.fails('E-SAFE-58', '364일')

    def test_58_fails_when_processed_reports_go_before_a_year(self):
        self.fake.rules['report_days'] = 300
        self.fails('E-SAFE-58', '364일')

    def test_58_is_blocked_when_the_batch_did_not_run(self):
        self.batch_works = False
        self.assertBlocked('E-SAFE-58', '배치')
        self.assertEqual(self.fake.rows('reports'), [])

    def test_58_is_blocked_at_the_cleanup_window(self):
        self.at(4, 0)
        self.assertBlocked('E-SAFE-58', '04:')
        self.assertEqual(self.calls, [])

    def test_59_passes_and_runs_the_batch_twice(self):
        self.passes('E-SAFE-59')
        self.assertEqual(self.calls, ['cleanup', 'cleanup'])
        self.assertEqual(self.fake.rows('reports'), [])

    def test_59_fails_when_the_second_run_deletes_more(self):
        self.fake.rules['rerun_eats'] = True
        self.fails('E-SAFE-59', '두 번째')

    def test_59_is_blocked_when_the_second_run_leaves_no_trace(self):
        self.fake.rules['sweeps_blocks'] = False
        self.assertBlocked('E-SAFE-59', '배치')


class SeedCutOffTest(BatchBase):
    def test_a_cut_off_answer_after_the_rows_went_in_still_removes_them(self):
        """넣기는 서버에 됐는데 답이 끊겨 Blocked — 신고 행이 운영에 고아로 남으면 안 된다."""
        real = area3_safe._insert

        def cut(run, table, rows):
            real(run, table, rows)
            raise tools.Blocked('답이 끊김')
        for name in ('E-SAFE-58', 'E-SAFE-59', 'E-SAFE-62'):
            with self.subTest(name), mock.patch.object(area3_safe, '_insert', cut):
                self.assertBlocked(name, '끊김')
                self.assertEqual(self.fake.rows('reports'), [], name)
                self.assertEqual(self.calls, [], name)


class WithdrawnReporterTest(BatchBase):
    def test_62_passes_and_calls_cleanup_once(self):
        self.passes('E-SAFE-62')
        self.assertEqual(self.calls, ['cleanup'])

    def test_62_fails_when_the_report_goes_with_the_reporter(self):
        self.fake.rules['report_cascade'] = True
        self.fails('E-SAFE-62', '신고가 지워짐')

    def test_62_fails_when_reporter_id_stays(self):
        self.fake.rules['keep_reporter'] = True
        self.fails('E-SAFE-62', 'reporter_id')

    def test_62_fails_when_the_snapshot_is_wiped(self):
        self.fake.rules['snapshot_wiped'] = True
        self.fails('E-SAFE-62', 'target_snapshot')


if __name__ == '__main__':
    unittest.main()
