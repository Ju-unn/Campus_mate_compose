"""영역 1 계정 공장 · 뒷정리 · API 가설 시험 — 운영 없이 가짜 HTTP 로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area1`."""

import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, tools
from e2e.tools import Blocked, Reply, Run

CFG = {'SUPABASE_URL': 'https://sb.test', 'SUPABASE_ANON_KEY': 'anon', 'API_BASE_URL': 'https://api.test',
       'E2E_MAIL_BASE': 'base@gmail.com'}
SV = '학생증 인증을 먼저 끝내 주세요'
INVALID = '입력한 값을 다시 확인해 주세요'
REJECT = {'msg': '허용되지 않은 학교 이메일이에요'}


class FakeServer:
    """운영 대신 답한다. routes[(메서드, 경로)] = Reply 또는 Reply 목록(차례로, 마지막은 계속). 나머지는 성공 기본값."""

    def __init__(self, routes=None):
        self.routes = {k: list(v) if isinstance(v, list) else v for k, v in (routes or {}).items()}
        self.calls = []
        self.urls = []
        self.raws = []  # (메서드, 주소, 바이트) — multipart · 파일 올리기
        self.users = []
        self._ids = 0  # 사용자를 지워도 id 가 다시 안 나오게

    def __call__(self, method, url, headers=None, body=None, raw=None):
        path = urlsplit(url).path
        self.calls.append((method, path, body))
        self.urls.append((method, url))
        if raw:
            self.raws.append((method, url, raw[0]))
        route = self.routes.get((method, path))
        if isinstance(route, list):
            return route.pop(0) if len(route) > 1 else route[0]
        if route is not None:
            return route
        if (method, path) in (('POST', '/auth/v1/admin/users'), ('POST', '/auth/v1/otp')):
            self._ids += 1
            user = {'id': f'id-{self._ids}', 'email': body['email']}
            self.users.append(user)
            return Reply(200, user)
        if (method, path) == ('GET', '/auth/v1/admin/users'):
            return Reply(200, {'users': self.users})
        if path == '/auth/v1/admin/generate_link':
            return Reply(200, {'hashed_token': 'h'})
        if (method, path) == ('PATCH', '/rest/v1/user_consents'):
            # 운영과 같게 — service_role 은 select · insert 만 있다(20260929010000_create_user_consents.sql:22-23).
            return Reply(403, {'code': '42501', 'message': 'permission denied for table user_consents'})
        if path == '/auth/v1/verify':
            return Reply(200, {'access_token': 'tok'})
        if path == '/rest/v1/university_email_domains':
            return Reply(200, [{'university_id': 'U'}])
        if method == 'GET' and path.startswith('/rest/v1/') or path.startswith('/storage/v1/object/list/'):
            return Reply(200, [])
        return Reply(200, None)

    def paths(self, method=None):
        return [p for m, p, _ in self.calls if method in (None, m)]


class Base(unittest.TestCase):
    KEPT = '00000000-0000-4000-8000-00000000000a'

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text(f'MANUAL {self.KEPT}\n', encoding='utf-8')
        self.run = Run(self.root / 'area1-b1', 'b', cfg=CFG, key='svc')

    def serve(self, routes=None):
        fake = FakeServer(routes)
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake


class ReplyTest(unittest.TestCase):
    def test_unpacks_as_status_and_body_and_keeps_headers_case_insensitive(self):
        reply = Reply(403, {'detail': 'x'}, {'X-Account-Status': 'suspended'})
        status, body = reply
        self.assertEqual((status, body), (403, {'detail': 'x'}))
        self.assertEqual(reply.headers.get('x-account-status'), 'suspended')


class AliasTest(Base):
    def test_first_alias_is_1001_and_numbers_are_never_reused(self):
        self.assertEqual(self.run.alias(), (1001, 'base+e2e1001@gmail.com'))
        self.assertEqual(self.run.alias('example.com'), (1002, 'base+e2e1002@example.com'))
        # 다른 묶음 폴더 · 새 실행도 같은 번호표를 이어 쓴다.
        again = Run(self.root / 'area1-b2', 'b', cfg=CFG, key='svc')
        self.assertEqual(again.alias()[0], 1003)


class AccountTest(Base):
    def test_basic_account_walks_every_step_and_is_written_down_without_token(self):
        fake = self.serve()
        account = self.run.account('basic')

        self.assertEqual((account['email'], account['stage'], account['token']), ('base+e2e1001@gmail.com', 'basic', 'tok'))
        self.assertEqual(fake.paths('POST'), ['/auth/v1/admin/users', '/auth/v1/admin/generate_link', '/auth/v1/verify',
                                              '/me/consents', '/school-info', '/profile-onboarding/basic-info'])
        self.assertEqual([b for m, p, b in fake.calls if p == '/rest/v1/profiles'], [{'student_verification': 'verified'}])
        nickname = [b for m, p, b in fake.calls if p == '/profile-onboarding/basic-info'][0]['nickname']
        self.assertRegex(nickname, r'^[A-Za-z]{5}$')
        written = json.loads((self.run.out / 'accounts.json').read_text(encoding='utf-8'))
        self.assertEqual(written, [{'n': 1001, 'email': 'base+e2e1001@gmail.com', 'id': 'id-1', 'stage': 'basic',
                                    'at': written[0]['at']}])
        self.assertNotIn('tok', json.dumps(written))

    def test_pending_account_stops_at_pending(self):
        fake = self.serve()
        self.assertEqual(self.run.account('pending')['stage'], 'pending')
        self.assertEqual([b for m, p, b in fake.calls if p == '/rest/v1/profiles'], [{'student_verification': 'pending'}])
        self.assertNotIn('/school-info', fake.paths())

    def test_failed_step_is_blocked_but_the_created_account_is_already_written(self):
        self.serve({('POST', '/me/consents'): Reply(500, None)})
        with self.assertRaises(Blocked):
            self.run.account('consented')
        written = json.loads((self.run.out / 'accounts.json').read_text(encoding='utf-8'))
        self.assertEqual([(a['id'], a['stage']) for a in written], [('id-1', 'new')])

    def test_unknown_stage_is_refused(self):
        with self.assertRaises(ValueError):
            self.run.account('chat')


class PatternTest(unittest.TestCase):
    def test_only_numbered_e2e_aliases_of_the_base_match(self):
        pattern = tools.e2e_pattern(CFG)
        self.assertTrue(pattern.match('base+e2e1001@gmail.com'))
        self.assertTrue(pattern.match('base+e2e1@gmail.com'))
        for email in ('base@gmail.com', 'base+e2e@gmail.com', 'base+e2e1x@gmail.com', 'other+e2e1@gmail.com',
                      'xbase+e2e1@gmail.com', 'base+e2e1@example.com', 'base+e2e1@gmail.com.evil', 'base+e2e1@gmailxcom'):
            self.assertIsNone(pattern.match(email), email)

    def test_keep_ids_are_every_uuid_in_the_file(self):
        text = ('KEEP e40f107a-0000-4000-8000-000000000001 (원래 테스트대학)\n'
                'MANUAL f9ea5e1e-0000-4000-8000-000000000002 (손 가입)\n')
        self.assertEqual(tools.keep_ids(text), {'e40f107a-0000-4000-8000-000000000001', 'f9ea5e1e-0000-4000-8000-000000000002'})

    def test_real_users_are_neither_e2e_aliases_nor_kept(self):
        users = [{'id': 'k', 'email': 'teacher@gmail.com'}, {'id': 'a', 'email': 'base+e2e1001@gmail.com'},
                 {'id': 'r', 'email': 'student@snu.ac.kr'}, {'id': 'p', 'phone': '821000000000'}]
        self.assertEqual([u['id'] for u in tools.real_users(users, tools.e2e_pattern(CFG), {'k'})], ['r', 'p'])


class CleanupTest(Base):
    def setUp(self):
        super().setUp()
        self.keep = self.KEPT

    def test_failed_storage_delete_stops_before_the_account_is_deleted(self):
        # 파일이 남은 채 계정을 지우면 `{id}/` 가 고아가 되고, 다음 뒷정리는 그 사용자를 못 본다.
        fake = self.serve({('POST', '/storage/v1/object/list/avatars'): Reply(200, [{'name': 'a.png', 'id': 'f1'}]),
                           ('DELETE', '/storage/v1/object/avatars'): Reply(500, None)})
        with self.assertRaises(SystemExit):
            tools.delete_user(CFG, 'svc', 'gone', set())
        self.assertNotIn('/auth/v1/admin/users/gone', fake.paths('DELETE'))

    def test_no_real_users_passes_and_any_real_user_stops(self):
        fake = self.serve()
        fake.users = [{'id': self.keep, 'email': 'teacher@gmail.com'}, {'id': 'a', 'email': 'base+e2e1001@gmail.com'}]
        self.assertEqual(tools.ensure_no_real_users(CFG, 'svc', self.root), 0)
        fake.users.append({'id': 'r', 'email': 'student@snu.ac.kr'})
        with self.assertRaises(SystemExit):
            tools.ensure_no_real_users(CFG, 'svc', self.root)

    def test_storage_then_admin_delete_only_for_unkept_e2e_aliases(self):
        fake = self.serve({('POST', '/storage/v1/object/list/avatars'): Reply(200, [{'name': 'a.png', 'id': 'f1'}])})
        fake.users = [{'id': self.keep, 'email': 'base+e2e1@gmail.com'}, {'id': 'gone', 'email': 'base+e2e1001@gmail.com'}]

        tools.cleanup(CFG, 'svc', self.root)

        deletes = [(p, b) for m, p, b in fake.calls if m == 'DELETE']
        self.assertEqual(deletes, [('/storage/v1/object/avatars', {'prefixes': ['gone/a.png']}),
                                   ('/auth/v1/admin/users/gone', None)])
        listed = [p for m, p, b in fake.calls if p.startswith('/storage/v1/object/list/')]
        self.assertEqual(sorted(listed), sorted(f'/storage/v1/object/list/{b}' for b in tools.BUCKETS))

    def test_delete_user_refuses_a_kept_id(self):
        fake = self.serve()
        with self.assertRaises(SystemExit):
            tools.delete_user(CFG, 'svc', self.keep, {self.keep})
        self.assertEqual(fake.paths('DELETE'), [])

    def test_stops_before_touching_anything_when_a_real_user_exists(self):
        fake = self.serve()
        fake.users = [{'id': 'gone', 'email': 'base+e2e1001@gmail.com'}, {'id': 'r', 'email': 'student@snu.ac.kr'}]
        with self.assertRaises(SystemExit):
            tools.cleanup(CFG, 'svc', self.root)
        self.assertEqual(fake.paths('DELETE'), [])

    def test_signup_blocks_outside_the_start_snapshot_are_deleted(self):
        (self.root / tools.BLOCKS_SNAPSHOT).write_text(json.dumps(['\\x01']), encoding='utf-8')
        fake = self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'email_hmac': '\\x01'}, {'email_hmac': '\\x02'}])})

        tools.cleanup(CFG, 'svc', self.root)

        self.assertEqual([p for m, p, b in fake.calls if m == 'DELETE'], ['/rest/v1/signup_blocks'])
        self.assertIn('eq.%5Cx02', [u for m, u in fake.urls if m == 'DELETE'][0])

    def test_signup_blocks_are_left_alone_without_a_snapshot(self):
        fake = self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'email_hmac': '\\x02'}])})
        tools.cleanup(CFG, 'svc', self.root)
        self.assertEqual(fake.paths('DELETE'), [])

    def test_snapshot_is_taken_once(self):
        self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'email_hmac': '\\x01'}])})
        tools.snapshot_blocks(CFG, 'svc', self.root)
        self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'email_hmac': '\\x09'}])})
        tools.snapshot_blocks(CFG, 'svc', self.root)
        self.assertEqual(json.loads((self.root / tools.BLOCKS_SNAPSHOT).read_text(encoding='utf-8')), ['\\x01'])


# 가설마다 (통과 응답, 하나만 어긋난 응답). 어긋난 쪽은 fail 이어야 한다 — 기대 판단이 실제로 무언가를 본다는 증거.
YEAR = datetime.now(area1.SEOUL).year
PROFILE_OK = Reply(200, [{'status': 'pending', 'student_verification': 'none', 'university_id': 'U', 'referral_code': 'ABC234'}])
CASES = {
    'E-AUTH-01': ({('GET', '/rest/v1/profiles'): PROFILE_OK},
                  {('GET', '/rest/v1/profiles'): Reply(200, [{**PROFILE_OK.body[0], 'referral_code': 'ABC10O'}])}),
    'E-AUTH-02': ({('GET', '/rest/v1/profiles'): PROFILE_OK},
                  {('GET', '/rest/v1/profiles'): Reply(200, [])}),
    'E-AUTH-03': ({('POST', '/auth/v1/otp'): Reply(422, REJECT)}, {}),
    'E-AUTH-04': ({('POST', '/auth/v1/otp'): Reply(422, REJECT)},
                  {('POST', '/auth/v1/otp'): Reply(422, {'msg': '재가입이 제한된 이메일이에요'})}),
    'E-AUTH-06': ({('POST', '/hooks/before-user-created'): Reply(401, {'detail': 'invalid signature'})},
                  {('POST', '/hooks/before-user-created'): [Reply(401, {'detail': 'invalid signature'}), Reply(200, {})]}),
    'E-AUTH-13': ({('POST', '/auth/v1/admin/users'): Reply(422, REJECT)}, {}),
    'E-GATE-06': ({('GET', '/cards/today'): Reply(403, {'detail': '이용이 제한된 계정이에요'}, {'X-Account-Status': 'suspended'})},
                  {('GET', '/cards/today'): Reply(403, {'detail': '이용이 제한된 계정이에요'})}),
    'E-GATE-15': ({('POST', '/me/consents'): [Reply(400, {'detail': '필수 항목에 모두 동의해 주세요'}), Reply(422, {'detail': []})]},
                  {('POST', '/me/consents'): [Reply(400, {'detail': '필수 항목에 모두 동의해 주세요'}), Reply(200, {'ok': True})]}),
    'E-GATE-16': ({('POST', '/student-verification'): Reply(403, {'detail': '약관 동의를 먼저 해 주세요'})},
                  {('POST', '/student-verification'): Reply(403, {'detail': '약관 동의를 먼저 해 주세요'}, {'X-Account-Status': 'pending'})}),
    'E-GATE-20': ({('GET', '/profile-onboarding/next-step'): Reply(403, {'detail': '약관 동의를 먼저 해 주세요'})},
                  {('GET', '/profile-onboarding/next-step'): Reply(200, {})}),
    'E-GATE-50': ({('GET', p): Reply(403, {'detail': SV}) for p in ('/cards/today', '/home/summary', '/profile-onboarding/next-step')}
                  | {('POST', '/cards/push-tokens'): Reply(200, {'ok': True})},
                  {('GET', p): Reply(403, {'detail': SV}) for p in ('/cards/today', '/profile-onboarding/next-step')}
                  | {('POST', '/cards/push-tokens'): Reply(200, {'ok': True})}),
    'E-GATE-51': ({('POST', '/school-info'): Reply(403, {'detail': SV}), ('GET', '/rest/v1/profiles'): Reply(200, [{'major': None}])},
                  {('POST', '/school-info'): Reply(403, {'detail': SV}), ('GET', '/rest/v1/profiles'): Reply(200, [{'major': '컴공'}])}),
    'E-GATE-55': ({('GET', '/cards/today'): Reply(403, {'detail': '학과 정보를 먼저 입력해 주세요'})},
                  {('GET', '/cards/today'): Reply(403, {'detail': SV})}),
    'E-ONB-14': ({('POST', '/profile-onboarding/basic-info'): [Reply(400, {'detail': '전화번호를 다시 확인해 주세요'}), Reply(200, {'ok': True})],
                  ('GET', '/rest/v1/profile_private'): Reply(200, [{'phone_number': '\\xdeadbeef'}])},
                 {('POST', '/profile-onboarding/basic-info'): [Reply(400, {'detail': '전화번호를 다시 확인해 주세요'}), Reply(200, {'ok': True})],
                  ('GET', '/rest/v1/profile_private'): Reply(200, [{'phone_number': None}])}),
    'E-ONB-29': ({('POST', '/profile-onboarding/interests'): [
                      Reply(422, {'detail': "목록에 없는 태그: ['없는태그']"}), Reply(422, {'detail': '같은 태그를 두 번 고를 수 없어요'}),
                      Reply(422, {'detail': '최소 3개를 골라야 해요'}), Reply(422, {'detail': '최대 5개까지 고를 수 있어요'})],
                  ('GET', '/rest/v1/profiles'): Reply(200, [{'interest_tags': None}])},
                 {('POST', '/profile-onboarding/interests'): [
                      Reply(422, {'detail': "목록에 없는 태그: ['없는태그']"}), Reply(422, {'detail': '같은 태그를 두 번 고를 수 없어요'}),
                      Reply(422, {'detail': '최소 3개를 골라야 해요'}), Reply(200, {'ok': True})],
                  ('GET', '/rest/v1/profiles'): Reply(200, [{'interest_tags': None}])}),
    'E-ONB-32': ({('POST', '/profile-onboarding/survey'): Reply(422, {'detail': INVALID})},
                 {('POST', '/profile-onboarding/survey'): Reply(422, {'detail': INVALID}),
                  ('GET', '/rest/v1/survey_answers'): [Reply(200, []), Reply(200, []), Reply(200, [{'axis': 1}])]}),
    'E-ONB-45': ({('POST', '/profile-onboarding/ideal-conditions'): [Reply(422, {'detail': INVALID}), Reply(422, {'detail': []})],
                  ('GET', '/rest/v1/profiles'): Reply(200, [{'preferred_age_min': None}])},
                 {('POST', '/profile-onboarding/ideal-conditions'): [Reply(200, {'ok': True}), Reply(422, {'detail': []})],
                  ('GET', '/rest/v1/profiles'): Reply(200, [{'preferred_age_min': None}])}),
    'E-ONB-69': ({('POST', '/referral/redeem'): Reply(403, {'detail': SV})},
                 {('POST', '/referral/redeem'): Reply(404, {'detail': '없는 코드예요, 다시 확인해 주세요'})}),
}
# E-ONB-08 은 올해에 따라 문구가 바뀌어 위 표 밖에서 만든다.
CASES['E-ONB-08'] = (
    {('POST', '/profile-onboarding/basic-info'): [Reply(422, {'detail': [{'msg': f'Value error, {YEAR - 19}년생부터 가입할 수 있어요'}]}),
                                                   Reply(422, {'detail': INVALID})],
     ('GET', '/rest/v1/profiles'): Reply(200, [{'nickname': None}])},
    {('POST', '/profile-onboarding/basic-info'): [Reply(422, {'detail': [{'msg': f'Value error, {YEAR - 19}년생부터 가입할 수 있어요'}]}),
                                                   Reply(200, {'ok': True})],
     ('GET', '/rest/v1/profiles'): Reply(200, [{'nickname': None}])},
)


class HypothesisTest(Base):
    def test_bundle_is_the_19_api_hypotheses_of_the_plan(self):
        self.assertEqual(area1.BUNDLES['area1-b1'], [
            'E-AUTH-01', 'E-AUTH-02', 'E-AUTH-03', 'E-AUTH-04', 'E-AUTH-06', 'E-AUTH-13',
            'E-GATE-06', 'E-GATE-15', 'E-GATE-16', 'E-GATE-20', 'E-GATE-50', 'E-GATE-51', 'E-GATE-55',
            'E-ONB-08', 'E-ONB-14', 'E-ONB-29', 'E-ONB-32', 'E-ONB-45', 'E-ONB-69'])
        self.assertLessEqual(set(CASES), set(area1.CASES))  # 묶음 2(area1_b2)가 더한 것은 빼고

    def test_expected_answers_pass_and_one_changed_answer_fails(self):
        for case, (good, bad) in CASES.items():
            with self.subTest(case=case):
                self.serve(good)
                result, note = area1.CASES[case](self.run)
                self.assertEqual(result, 'pass', note)
                self.serve(bad)
                result, note = area1.CASES[case](self.run)
                self.assertEqual(result, 'fail')
                self.assertTrue(note)

    def test_rejected_domain_that_got_through_is_deleted_at_once(self):
        # example.com 은 뒷정리 정규식 밖이라, 잘못 만들어진 계정은 그 자리에서 지워야 남지 않는다.
        for case in ('E-AUTH-03', 'E-AUTH-13'):
            with self.subTest(case=case):
                fake = self.serve()
                self.assertEqual(area1.CASES[case](self.run)[0], 'fail')
                self.assertEqual(fake.paths('DELETE'), ['/auth/v1/admin/users/id-1'])

    def test_fake_push_token_is_deleted_even_when_the_hypothesis_fails(self):
        fake = self.serve(CASES['E-GATE-50'][1])
        area1.CASES['E-GATE-50'](self.run)
        self.assertEqual(len([p for p in fake.paths('DELETE') if p.startswith('/cards/push-tokens/')]), 2)

    def test_auth_13_notes_which_defence_stopped_it(self):
        self.serve({('POST', '/auth/v1/admin/users'): Reply(422, REJECT)})
        self.assertEqual(area1.CASES['E-AUTH-13'](self.run), ('pass', '가입 훅이 막음'))
        self.serve({('POST', '/auth/v1/admin/users'): Reply(500, {'msg': 'Database error creating new user'})})
        self.assertEqual(area1.CASES['E-AUTH-13'](self.run), ('pass', '트리거가 막음'))

    def test_setup_failure_is_blocked(self):
        self.serve({('POST', '/me/consents'): Reply(503, None)})
        self.assertEqual(area1.attempt(self.run, 'E-GATE-55')[0], 'blocked')

    def test_gate_20_inserts_old_consents_instead_of_updating(self):
        # user_consents 는 고치지 않는 기록이라 update 권한이 없다 — 옛 판 행을 처음부터 넣어 재동의 전 계정을 만든다.
        fake = self.serve(CASES['E-GATE-20'][0])
        area1.CASES['E-GATE-20'](self.run)
        inserted = [b for m, p, b in fake.calls if (m, p) == ('POST', '/rest/v1/user_consents')]
        self.assertEqual(inserted, [[{'profile_id': 'id-1', 'kind': k, 'version': '2026-09-01'} for k in ('privacy', 'terms')]])
        self.assertNotIn('/me/consents', fake.paths())
        self.assertLess(fake.paths().index('/rest/v1/user_consents'), fake.paths().index('/school-info'))

    def test_wrongly_created_account_on_the_keep_list_is_not_deleted(self):
        fake = self.serve()
        fake.users = [{'id': self.KEPT, 'email': 'base+e2e1001@example.com'}]
        self.assertEqual(area1.CASES['E-AUTH-03'](self.run)[0], 'fail')
        self.assertEqual(fake.paths('DELETE'), [])


if __name__ == '__main__':
    unittest.main()
