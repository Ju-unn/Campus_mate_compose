"""영역 3 API 가설(채팅 · 지인 리뷰) 시험 — 운영 없이 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3`.

가짜 서버는 표(`/rest/v1/<표>`)를 메모리에 들고 있어서 가설이 "DB 에 새 행 0" 을 실제로 센다.
API(FastAPI) 쪽 답은 시험마다 [Fake.on] 으로 정한다 — 올바른 서버면 pass, 어긋난 서버면 fail 이어야 한다.
"""

import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib.parse import parse_qsl, urlsplit

from e2e import area3, tools
from e2e.test_area1 import CFG, FakeServer
from e2e.tools import Reply, Run

NOT_FOUND = '대화를 찾을 수 없어요'
CHAT_LEFT = '이미 나간 대화예요'
PROFILE_GONE = '프로필을 찾을 수 없어요'
REVIEW_GONE = '리뷰를 찾을 수 없어요'
ALREADY_WRITTEN = '이미 리뷰를 남겼어요'
PERMISSION = Reply(401, {'code': '42501', 'message': 'permission denied for table'})
RACE_TABLES = {'user_consents', 'university_email_domains'}
# 기본키가 여러 칸이라 id 칸이 없는 표 — 운영은 select=id 를 400(42703)으로 돌려준다.
NO_ID_TABLES = {'blocks', 'poll_votes', 'referrals', 'push_tokens', 'notification_settings'}


class Fake(FakeServer):
    """표 저장소 + 시험이 정한 API 답. 계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 …"""

    def __init__(self):
        super().__init__()
        self.handlers = []
        self.sent = []
        self.tables = {}
        self.statuses = {}  # PATCH profiles {status} 가 남긴 것 — 리뷰 서버가 정지 · 탈퇴를 본다
        self.verifies = 0

    def on(self, method, pattern, reply):
        """[reply] 는 Reply 또는 (보낸 것 dict) → Reply. 먼저 등록한 것이 먼저 맞는다."""
        self.handlers.append((method, re.compile(pattern), reply))

    def __call__(self, method, url, headers=None, body=None, raw=None):
        parts, headers = urlsplit(url), headers or {}
        sent = {'method': method, 'path': parts.path, 'query': dict(parse_qsl(parts.query)), 'body': body,
                'auth': headers.get('Authorization', '').removeprefix('Bearer '), 'apikey': headers.get('apikey')}
        self.sent.append(sent)
        if parts.path == '/auth/v1/verify':
            self.verifies += 1
            return Reply(200, {'access_token': f'tok-{self.verifies}'})
        for want, pattern, reply in self.handlers:
            if want == method and pattern.fullmatch(parts.path):
                return reply(sent) if callable(reply) else reply
        if parts.path.startswith('/rest/v1/') and parts.path.split('/')[-1] not in RACE_TABLES:
            return self._table(method, parts.path.split('/')[-1], sent)
        return super().__call__(method, url, headers, body, raw)

    def _table(self, method, name, sent):
        rows = self.tables.setdefault(name, [])
        if name in NO_ID_TABLES and 'id' in sent['query'].get('select', '').split(','):
            return Reply(400, {'code': '42703', 'message': f'column {name}.id does not exist'})
        match = [r for r in rows if all(str(r.get(k)) == v[3:] for k, v in sent['query'].items()
                                        if v.startswith('eq.') and k != 'select')]
        if method == 'POST':
            rows += sent['body'] if isinstance(sent['body'], list) else [sent['body']]
            return Reply(201, None)
        if method == 'PATCH':
            if name == 'profiles' and 'status' in sent['body']:
                self.statuses[sent['query']['id'][3:]] = sent['body']['status']
            for row in match:
                row.update(sent['body'])
            return Reply(200, None)
        if method == 'DELETE':
            self.tables[name] = [r for r in rows if r not in match]
            return Reply(204, None)
        return Reply(200, [dict(r) for r in match])

    def count(self, table, **where):
        return len([r for r in self.tables.get(table, []) if all(r.get(k) == v for k, v in where.items())])

    def by(self, method, path_prefix):
        return [s for s in self.sent if s['method'] == method and s['path'].startswith(path_prefix)]


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area3-api', 'b', cfg={**CFG}, key='svc')
        self.fake = Fake()
        patcher = mock.patch.object(tools, 'call', self.fake)
        patcher.start()
        self.addCleanup(patcher.stop)

    def case(self, name):
        return area3.attempt(self.run_, name)


class ChatCasesTest(Base):
    def test_14_over_limit_is_422_and_nothing_is_saved(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(422, {'detail': [{'msg': 'too long'}]}))
        self.assertEqual(self.case('E-CHAT-14')[0], 'pass')
        sent = self.fake.by('POST', '/chat/matches/')[0]
        self.assertEqual(len(sent['body']['body']), 1001)
        self.assertEqual(sent['auth'], 'tok-1')  # A 의 토큰
        self.assertEqual(self.fake.count('messages'), 0)

    def test_14_fails_when_server_accepts_1001(self):
        def accept(sent):
            self.fake.tables.setdefault('messages', []).append({'body': 'x'})
            return Reply(201, {'message': {}})
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', accept)
        result, note = self.case('E-CHAT-14')
        self.assertEqual(result, 'fail')
        self.assertIn('201', note)

    def test_21_limit_bounds(self):
        def page(sent):
            limit = int(sent['query']['limit'])
            return Reply(422, {'detail': 'ge'}) if limit < 1 else Reply(200, {'messages': [{}] * min(limit, 50), 'has_more': True})
        self.fake.on('GET', r'/chat/matches/[^/]+/messages', page)
        self.assertEqual(self.case('E-CHAT-21')[0], 'pass')
        self.assertEqual(self.fake.count('messages'), 51)  # 한 페이지(50)를 넘겨 심어야 500 이 50 으로 잘리는 것이 보인다
        self.assertEqual([s['query']['limit'] for s in self.fake.by('GET', '/chat/matches/')], ['0', '500'])

    def test_21_fails_when_500_returns_more_than_50(self):
        self.fake.on('GET', r'/chat/matches/[^/]+/messages',
                     lambda s: Reply(422, {}) if s['query']['limit'] == '0' else Reply(200, {'messages': [{}] * 51}))
        result, note = self.case('E-CHAT-21')
        self.assertEqual(result, 'fail')
        self.assertIn('51', note)

    def _left_server(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', lambda s: self._leave(s))
        self.fake.on('GET', r'/chat/matches/[^/]+', Reply(404, {'detail': NOT_FOUND}))
        self.fake.on('GET', r'/chat/matches/[^/]+/messages', Reply(404, {'detail': NOT_FOUND}))

    def _leave(self, sent):
        left = self.fake.count('messages', kind='left')
        if left:
            return Reply(409, {'detail': CHAT_LEFT})
        self.fake.tables.setdefault('messages', []).append({'kind': 'left', 'match_id': sent['path'].split('/')[3]})
        return Reply(200, {'ok': True})

    def test_63_left_user_cannot_read_room_messages_or_table(self):
        self._left_server()
        # RLS: 공개 키 + 사용자 토큰으로 읽으면 0행, 서비스 키로 센 것은 실제 내용이다.
        self.fake.on('GET', r'/rest/v1/messages',
                     lambda s: Reply(200, []) if s['apikey'] == 'anon' else self.fake._table('GET', 'messages', s))
        self.assertEqual(self.case('E-CHAT-63')[0], 'pass')
        reads = [s for s in self.fake.by('GET', '/rest/v1/messages') if s['apikey'] == 'anon']
        self.assertEqual([s['auth'] for s in reads], ['tok-1'])  # 나간 A 의 토큰, 공개 키로

    def test_63_fails_when_left_user_still_reads_table(self):
        self._left_server()
        result, note = self.case('E-CHAT-63')  # 표 읽기가 실제 행을 돌려준다
        self.assertEqual(result, 'fail')
        self.assertIn('messages', note)

    def test_64_second_leave_is_409_and_one_left_line(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', lambda s: self._leave(s))
        self.assertEqual(self.case('E-CHAT-64')[0], 'pass')
        self.assertEqual(self.fake.count('messages', kind='left'), 1)

    def test_64_fails_when_second_leave_adds_another_line(self):
        def always(sent):
            self.fake.tables.setdefault('messages', []).append({'kind': 'left'})
            return Reply(200, {})
        self.fake.on('POST', r'/chat/matches/[^/]+/leave', always)
        result, note = self.case('E-CHAT-64')
        self.assertEqual(result, 'fail')

    def test_70_outsider_sees_nothing(self):
        # 당사자(A · B)에게는 열리고 제3자 C(tok-3)에게만 404 — 토큰을 바꿔 보내면 시험이 잡아야 한다.
        self.fake.on('GET', r'/chat/matches/[^/]+(/messages)?',
                     lambda s: Reply(404, {'detail': NOT_FOUND}) if s['auth'] == 'tok-3' else Reply(200, {}))
        self.fake.on('GET', r'/rest/v1/messages',
                     lambda s: Reply(200, []) if s['apikey'] == 'anon' else self.fake._table('GET', 'messages', s))
        self.assertEqual(self.case('E-CHAT-70')[0], 'pass')
        reads = [s for s in self.fake.by('GET', '/rest/v1/messages') if s['apikey'] == 'anon']
        self.assertEqual([s['auth'] for s in reads], ['tok-3'])  # 매칭 밖 C 의 토큰
        pair = [s['body'] for s in self.fake.by('POST', '/rest/v1/matches')][0]
        self.assertLess(pair['profile_a'], pair['profile_b'])  # matches_pair_order
        self.assertEqual({pair['profile_a'], pair['profile_b']}, {'id-1', 'id-2'})  # C(id-3) 는 당사자가 아니다

    def test_70_fails_when_outsider_gets_the_room(self):
        self.fake.on('GET', r'/chat/matches/[^/]+', Reply(200, {'room': 1}))
        self.fake.on('GET', r'/chat/matches/[^/]+/messages', Reply(404, {'detail': NOT_FOUND}))
        result, note = self.case('E-CHAT-70')
        self.assertEqual(result, 'fail')
        self.assertIn('200', note)

    def test_71_app_cannot_insert_messages(self):
        self.fake.on('POST', r'/rest/v1/messages',
                     lambda s: PERMISSION if s['apikey'] == 'anon' else self.fake._table('POST', 'messages', s))
        self.assertEqual(self.case('E-CHAT-71')[0], 'pass')
        attempt = [s for s in self.fake.by('POST', '/rest/v1/messages') if s['apikey'] == 'anon'][0]
        self.assertEqual((attempt['auth'], attempt['body']['sender_id']), ('tok-1', 'id-1'))
        self.assertEqual(self.fake.count('messages', body='E2E-앱직접쓰기'), 0)

    def test_71_fails_when_insert_goes_through(self):
        result, note = self.case('E-CHAT-71')
        self.assertEqual(result, 'fail')


class ReviewCasesTest(Base):
    def review_server(self):
        """리뷰 쓰기 서버: 규칙 위반은 422, 연결 없음 · 자기 자신 · 차단 · 정지 · 탈퇴는 404, 이미 씀은 409."""
        fake = self.fake
        tags = {'약속을 잘 지켜요', '대화가 편해요', '성실해요', '솔직해요'}

        def post(sent):
            body, me_id = sent['body'], f"id-{sent['auth'].removeprefix('tok-')}"
            if (not body['tags'] or len(body['tags']) > 3 or len(set(body['tags'])) != len(body['tags'])
                    or any(t not in tags for t in body['tags'])):
                return Reply(422, {'detail': 'tags'})
            comment = (body.get('comment') or '').strip() or None
            if comment and len(comment) > 100:
                return Reply(422, {'detail': 'comment'})
            target = body['reviewee_id']
            linked = any({r['referee_id'], r['referrer_id']} == {me_id, target} for r in fake.tables.get('referrals', []))
            blocked = any({r['blocker_id'], r['blocked_id']} == {me_id, target} for r in fake.tables.get('blocks', []))
            # 운영 기본값은 pending 이다 — active 는 온보딩을 마치거나 시험이 서비스 키로 올려야 된다(is_active).
            if me_id == target or not linked or blocked or fake.statuses.get(target, 'pending') != 'active':
                return Reply(404, {'detail': PROFILE_GONE})
            rows = fake.tables.setdefault('friend_reviews', [])
            if any(r['reviewer_id'] == me_id and r['reviewee_id'] == target for r in rows):
                return Reply(409, {'detail': ALREADY_WRITTEN})
            rows.append({'id': f'r{len(rows)}-{me_id}', 'reviewer_id': me_id, 'reviewee_id': target,
                         'tags': body['tags'], 'comment': comment})
            return Reply(201, {'id': rows[-1]['id']})
        fake.on('POST', r'/friend-reviews', post)

    def test_reviewee_is_made_active_so_the_404_comes_from_the_rule_under_test(self):
        # 리뷰 상대가 pending 이면 서버가 어떤 가설에서든 404 라 차단 · 정지 가설이 거짓 pass 가 된다.
        self.review_server()
        self.assertEqual(self.case('E-REV-08')[0], 'pass')
        self.assertEqual(self.fake.statuses, {'id-2': 'active'})

    def test_14_and_15_fail_when_a_plain_active_target_is_also_404(self):
        # 서버가 누구에게나 404 면(예: 상대가 pending) 차단 가설의 404 는 아무것도 증명하지 못한다.
        self.fake.on('POST', r'/friend-reviews', Reply(404, {'detail': PROFILE_GONE}))
        self.fake.on('POST', r'/blocks/[^/]+', Reply(200, {'ok': True}))
        for name in ('E-REV-14', 'E-REV-15'):
            self.assertEqual(self.case(name)[0], 'fail', name)

    def test_38_and_39_remove_a_report_a_wrong_server_created(self):
        for name in ('E-REV-38', 'E-REV-39'):
            self.fake.tables.clear()
            self.fake.handlers.clear()
            self.fake.on('POST', r'/reports', lambda s: (self.fake.tables.setdefault('reports', []).append(
                {'target_id': s['body']['target_id']}), Reply(201, {'ok': True}))[1])
            self.assertEqual(self.case(name)[0], 'fail', name)
            self.assertEqual(self.fake.count('reports'), 0, f'{name}: 만들어진 신고를 지워야 고아가 안 남는다')

    def test_08_trailing_space_is_cut_and_100_passes(self):
        self.review_server()
        self.assertEqual(self.case('E-REV-08')[0], 'pass')
        sent = self.fake.by('POST', '/friend-reviews')[0]
        self.assertEqual(sent['body']['comment'], '가' * 100 + ' ')
        self.assertEqual(self.fake.tables['referrals'], [{'referee_id': 'id-2', 'referrer_id': 'id-1'}])
        self.assertEqual(self.fake.statuses['id-2'], 'active')

    def test_08_fails_when_server_keeps_the_trailing_space(self):
        self.fake.on('POST', r'/friend-reviews', lambda s: (
            self.fake.tables.setdefault('friend_reviews', []).append({'comment': s['body']['comment']}), Reply(201, {'id': 'x'}))[1])
        result, note = self.case('E-REV-08')
        self.assertEqual(result, 'fail')

    def test_09_every_rule_violation_is_422_and_no_row(self):
        self.review_server()
        self.assertEqual(self.case('E-REV-09')[0], 'pass')
        sent = [s['body'] for s in self.fake.by('POST', '/friend-reviews')]
        self.assertEqual([len(b['tags']) for b in sent], [0, 4, 1, 2, 1])
        self.assertEqual(len(sent[-1]['comment']), 101)
        self.assertIn('잘생겼어요', sent[2]['tags'])
        self.assertEqual(sent[3]['tags'][0], sent[3]['tags'][1])  # 같은 태그 두 번

    def test_09_fails_when_one_of_them_is_accepted(self):
        self.review_server()
        self.fake.handlers.pop(0)
        self.fake.on('POST', r'/friend-reviews', lambda s: Reply(201, {'id': 'x'}) if s['body']['tags'] == ['잘생겼어요'] else Reply(422, {}))
        result, note = self.case('E-REV-09')
        self.assertEqual(result, 'fail')
        self.assertIn('201', note)

    def test_13_self_review_is_404(self):
        self.review_server()
        self.assertEqual(self.case('E-REV-13')[0], 'pass')
        self.assertEqual(self.fake.by('POST', '/friend-reviews')[0]['body']['reviewee_id'], 'id-1')

    def test_14_blocked_either_way_is_404(self):
        self.review_server()
        self.fake.on('POST', r'/blocks/[^/]+', lambda s: (
            self.fake.tables.setdefault('blocks', []).append(
                {'blocker_id': f"id-{s['auth'].removeprefix('tok-')}", 'blocked_id': s['path'].rsplit('/', 1)[1]}), Reply(200, {'ok': True}))[1])
        self.assertEqual(self.case('E-REV-14')[0], 'pass')
        blocks = self.fake.tables['blocks']
        self.assertEqual(sorted((b['blocker_id'], b['blocked_id']) for b in blocks), [('id-1', 'id-3'), ('id-2', 'id-1')])
        # 매칭이 있어야 차단이 된다 — 두 쌍 모두.
        self.assertEqual(len(self.fake.tables['matches']), 2)

    def test_14_fails_when_blocked_user_can_still_write(self):
        self.fake.on('POST', r'/blocks/[^/]+', Reply(200, {'ok': True}))
        self.fake.on('POST', r'/friend-reviews', Reply(201, {'id': 'x'}))
        result, note = self.case('E-REV-14')
        self.assertEqual(result, 'fail')

    def test_15_suspended_and_withdrawn_targets_are_404(self):
        self.review_server()
        self.assertEqual(self.case('E-REV-15')[0], 'pass')
        patches = [s['body'] for s in self.fake.by('PATCH', '/rest/v1/profiles') if s['body'].get('status') not in (None, 'active')]
        self.assertEqual(patches[0], {'status': 'suspended'})
        self.assertEqual(patches[1]['status'], 'withdrawn')
        self.assertIn('withdrawn_at', patches[1])
        self.assertEqual(self.fake.count('friend_reviews'), 1)  # 대조군 한 줄뿐 — 정지 · 탈퇴 상대에게는 안 들어갔다  # profiles_withdrawn_at_check — 둘이 함께여야 한다

    def test_28_cannot_delete_gone_or_others_reviews(self):
        deleted = set()

        def delete(sent):
            review_id = sent['path'].rsplit('/', 1)[1]
            row = next((r for r in self.fake.tables.get('friend_reviews', []) if r['id'] == review_id), None)
            if not row or review_id in deleted or row['reviewer_id'] != f"id-{sent['auth'].removeprefix('tok-')}":
                return Reply(404, {'detail': REVIEW_GONE})
            deleted.add(review_id)
            self.fake.tables['friend_reviews'].remove(row)
            return Reply(204, None)
        self.review_server()
        self.fake.on('DELETE', r'/friend-reviews/[^/]+', delete)
        self.assertEqual(self.case('E-REV-28')[0], 'pass')
        # 남의 리뷰 두 개(C 가 쓴 것, A 가 쓴 것)는 지운 시도 뒤에도 그대로 있다.
        self.assertEqual(self.fake.count('friend_reviews'), 2)

    def test_28_fails_when_receiver_can_delete(self):
        self.review_server()
        self.fake.on('DELETE', r'/friend-reviews/[^/]+', Reply(204, None))
        result, note = self.case('E-REV-28')
        self.assertEqual(result, 'fail')

    def test_38_only_the_receiver_can_report_a_review(self):
        self.fake.on('POST', r'/reports', Reply(404, {'detail': REVIEW_GONE}))
        self.assertEqual(self.case('E-REV-38')[0], 'pass')
        bodies = [(s['auth'], s['body']['target_type']) for s in self.fake.by('POST', '/reports')]
        self.assertEqual(bodies, [('tok-1', 'friend_review'), ('tok-3', 'friend_review')])  # 작성자 A, B 의 매칭 상대 C
        self.assertEqual(self.fake.count('reports'), 0)
        row = self.fake.tables['friend_reviews'][0]
        self.assertEqual((row['reviewer_id'], row['reviewee_id']), ('id-1', 'id-2'))

    def test_38_fails_when_author_can_report(self):
        self.fake.on('POST', r'/reports', lambda s: Reply(201, {'ok': True}) if s['auth'] == 'tok-1' else Reply(404, {'detail': REVIEW_GONE}))
        result, note = self.case('E-REV-38')
        self.assertEqual(result, 'fail')

    def test_39_blinded_review_cannot_be_reported(self):
        self.fake.on('POST', r'/reports', Reply(404, {'detail': REVIEW_GONE}))
        self.assertEqual(self.case('E-REV-39')[0], 'pass')
        self.assertEqual(self.fake.tables['friend_reviews'][0]['status'], 'blinded')
        self.assertEqual(self.fake.by('POST', '/reports')[0]['auth'], 'tok-2')  # 받은 사람 B

    def test_40_app_cannot_touch_the_review_table(self):
        self.fake.handlers.append(('GET', re.compile(r'/rest/v1/friend_reviews'),
                                   lambda s: PERMISSION if s['apikey'] == 'anon' else self.fake._table('GET', 'friend_reviews', s)))
        self.fake.handlers.append(('POST', re.compile(r'/rest/v1/friend_reviews'),
                                   lambda s: PERMISSION if s['apikey'] == 'anon' else self.fake._table('POST', 'friend_reviews', s)))
        self.assertEqual(self.case('E-REV-40')[0], 'pass')
        self.assertEqual(self.fake.count('friend_reviews'), 1)  # 준비로 심은 한 행뿐 — 앱의 insert 는 안 들어갔다

    def test_40_fails_when_select_returns_empty_instead_of_denying(self):
        # 0행(200)은 거부가 아니다 — 권한이 아니라 RLS 가 걸렀다는 뜻이라 계약과 다르다.
        self.fake.handlers.append(('GET', re.compile(r'/rest/v1/friend_reviews'),
                                   lambda s: Reply(200, []) if s['apikey'] == 'anon' else self.fake._table('GET', 'friend_reviews', s)))
        self.fake.handlers.append(('POST', re.compile(r'/rest/v1/friend_reviews'),
                                   lambda s: PERMISSION if s['apikey'] == 'anon' else self.fake._table('POST', 'friend_reviews', s)))
        result, note = self.case('E-REV-40')
        self.assertEqual(result, 'fail')
        self.assertIn('select', note)


class RegistryTest(Base):
    def test_bundle_lists_exactly_the_api_only_chat_and_review_cases(self):
        self.assertEqual(area3.BUNDLES['area3-api'], [
            'E-CHAT-14', 'E-CHAT-21', 'E-CHAT-63', 'E-CHAT-64', 'E-CHAT-70', 'E-CHAT-71',
            'E-REV-08', 'E-REV-09', 'E-REV-13', 'E-REV-14', 'E-REV-15', 'E-REV-28', 'E-REV-38', 'E-REV-39', 'E-REV-40'])
        self.assertEqual(sorted(area3.CASES), sorted(area3.BUNDLES['area3-api']))

    def test_match_is_stored_in_pair_order_whatever_order_it_is_given(self):
        area3._match(self.run_, {'id': 'id-9'}, {'id': 'id-1'})
        row = self.fake.tables['matches'][0]
        self.assertEqual((row['profile_a'], row['profile_b']), ('id-1', 'id-9'))
        self.assertEqual({r['profile_id'] for r in self.fake.tables['match_participants']}, {'id-1', 'id-9'})

    def test_main_runs_area3_cases_next_to_area1_and_area2(self):
        from e2e import __main__ as main
        self.assertEqual({main.API_CASES[c] for c in area3.CASES}, {area3})
        self.assertEqual(main.BUNDLES['area3-api'], area3.BUNDLES['area3-api'])
        self.assertIn('area1-b1', main.BUNDLES)  # 다른 영역의 묶음이 안 사라졌다
        self.assertTrue(any(name.startswith('area2') for name in main.BUNDLES))

    def test_blocked_preparation_is_blocked_not_fail(self):
        self.fake.on('POST', r'/auth/v1/admin/users', Reply(500, {'msg': 'down'}))
        result, note = self.case('E-CHAT-14')
        self.assertEqual(result, 'blocked')
        self.assertIn('계정 만들기', note)

    def test_failed_seed_insert_is_blocked(self):
        self.fake.handlers.append(('POST', re.compile(r'/rest/v1/matches'), Reply(409, {'message': 'dup'})))
        result, note = self.case('E-CHAT-14')
        self.assertEqual(result, 'blocked')
        self.assertIn('matches', note)


if __name__ == '__main__':
    unittest.main()
