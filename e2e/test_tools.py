"""하네스 자체 시험 — 기기 · 운영 없이 돈다. 저장소 루트에서 `python -m unittest e2e.test_tools`."""

import json
import tempfile
import unittest
import urllib.request
from email.parser import BytesParser
from email.policy import default
from pathlib import Path
from unittest import mock

from e2e import tools
from e2e.__main__ import build_parser
from e2e.tools import Hub, call, latest, scenario_rows, verdict


class HubTest(unittest.TestCase):
    def setUp(self):
        self.hub = Hub(0)  # 0 = 빈 포트 아무거나
        self.addCleanup(self.hub.close)
        self.base = f'http://127.0.0.1:{self.hub.port}'

    def test_job_goes_to_device_and_result_comes_back(self):
        self.hub.tell({'case': 'SMOKE'})
        with urllib.request.urlopen(f'{self.base}/hear', timeout=5) as res:
            self.assertEqual(json.load(res), {'case': 'SMOKE'})

        body = json.dumps({'case': 'SMOKE', 'result': 'pass'}).encode()
        urllib.request.urlopen(urllib.request.Request(f'{self.base}/say', data=body, method='POST'), timeout=5)
        self.assertEqual(self.hub.wait(5), {'case': 'SMOKE', 'result': 'pass'})

    def test_new_job_drops_leftovers_from_last_attempt(self):
        self.hub.tell({'case': 'OLD'})
        body = json.dumps({'case': 'OLD', 'result': 'fail'}).encode()
        urllib.request.urlopen(urllib.request.Request(f'{self.base}/say', data=body, method='POST'), timeout=5)

        self.hub.tell({'case': 'NEW'})
        with urllib.request.urlopen(f'{self.base}/hear', timeout=5) as res:
            self.assertEqual(json.load(res), {'case': 'NEW'})
        self.assertIsNone(self.hub.wait(0.1))

    def test_go_without_extra_is_just_go_true(self):
        self.hub.go()
        with urllib.request.urlopen(f'{self.base}/hear', timeout=5) as res:
            self.assertEqual(json.load(res), {'go': True})

    def test_go_carries_the_values_the_pc_gives(self):
        self.hub.go({'token_hash': 'second'})
        with urllib.request.urlopen(f'{self.base}/hear', timeout=5) as res:
            self.assertEqual(json.load(res), {'go': True, 'token_hash': 'second'})

    def test_go_values_cannot_turn_go_off(self):
        self.hub.go({'go': False})
        with urllib.request.urlopen(f'{self.base}/hear', timeout=5) as res:
            self.assertEqual(json.load(res), {'go': True})

    def test_hear_with_nothing_queued_is_204(self):
        with urllib.request.urlopen(f'{self.base}/hear?wait=0', timeout=5) as res:
            self.assertEqual(res.status, 204)

    def test_wait_gives_none_when_device_says_nothing(self):
        self.assertIsNone(self.hub.wait(0.1))

    def test_result_skips_messages_in_between(self):
        for message in ({'case': 'X', 'step': '로그인'}, {'case': 'X', 'result': 'pass'}):
            body = json.dumps(message).encode()
            urllib.request.urlopen(urllib.request.Request(f'{self.base}/say', data=body, method='POST'), timeout=5)
        self.assertEqual(self.hub.result(5), {'case': 'X', 'result': 'pass'})

    def test_call_keeps_non_json_error_body_as_text(self):
        # 우편함의 404 는 HTML 이다 — Cloud Run · 게이트웨이 502 처럼 JSON 아닌 본문도 실행을 멈추지 않는다.
        status, body = call('GET', f'{self.base}/nope')
        self.assertEqual(status, 404)
        self.assertIsInstance(body, str)


class LatestTest(unittest.TestCase):
    def test_last_line_per_case_wins(self):
        records = [
            {'case': 'E-AUTH-01', 'result': 'fail'},
            {'case': 'SMOKE', 'result': 'pass'},
            {'case': 'E-AUTH-01', 'result': 'pass'},
        ]
        self.assertEqual(latest(records), {
            'E-AUTH-01': {'case': 'E-AUTH-01', 'result': 'pass'},
            'SMOKE': {'case': 'SMOKE', 'result': 'pass'},
        })


class ScenarioRowsTest(unittest.TestCase):
    def test_reads_only_hypothesis_rows(self):
        md = '\n'.join([
            '## 1-1. 계정 만들기 (AUTH)',
            '| 번호 | 가설(○○하면 △△된다) | 기기 | 준비(진행 프로그램) | 누르는 것 | 통과 조건(숫자 기준) | 방식 | 근거 |',
            '|---|---|---|---|---|---|---|---|',
            '| E-AUTH-01 | 가입하면 프로필이 생긴다 | 없음(진행만) | 메일 1개 | 없음 | 200 | 자동 | `a.py:1` |',
            '| E-GATE-07 | 정지면 막힌다 | 폰 | 계정 | 버튼 | 문구 | 폰 | `b.dart:2` |',
            '| E-GATE-99 | 칸이 모자란 줄 |',
            '| 1 | 139 | 129 |',
        ])
        self.assertEqual(scenario_rows(md), [
            {'case': 'E-AUTH-01', 'hypothesis': '가입하면 프로필이 생긴다', 'device': '없음(진행만)', 'method': '자동'},
            {'case': 'E-GATE-07', 'hypothesis': '정지면 막힌다', 'device': '폰', 'method': '폰'},
        ])


class VerdictTest(unittest.TestCase):
    def test_app_answer_without_note_has_empty_note(self):
        self.assertEqual(verdict({'case': 'SMOKE', 'result': 'pass'}), ('pass', ''))

    def test_app_answer_keeps_its_note(self):
        self.assertEqual(verdict({'case': 'X', 'result': 'fail', 'note': '안 나타남'}), ('fail', '안 나타남'))

    def test_silence_is_fail_with_timeout_note(self):
        self.assertEqual(verdict(None), ('fail', '앱이 시간 안에 답하지 않음'))


class FormTest(unittest.TestCase):
    """tools.form — 학생증 · 사진 올리기(POST, 파일 하나)는 그대로, PUT · 파일 없음이 새로 된다(영역 5 PUT /me/photos)."""

    def sent(self, *args, **kwargs):
        with mock.patch.object(tools, 'call') as fake, mock.patch.object(tools.uuid, 'uuid4', return_value=mock.Mock(hex='B')):
            tools.form('https://api.test/x', 't', *args, **kwargs)
        (method, url, headers), options = fake.call_args.args[:3], dict(fake.call_args.kwargs)
        return method, url, headers, options.pop('raw'), options

    def test_a_file_upload_is_still_a_post_with_the_exact_bytes_it_always_had(self):
        method, url, headers, raw, options = self.sent({'a': 'b'}, ('f', 'f.png', b'xyz', 'image/png'))
        self.assertEqual((method, url, headers, options), ('POST', 'https://api.test/x', {'Authorization': 'Bearer t'}, {}))
        self.assertEqual(raw, (b'--B\r\nContent-Disposition: form-data; name="a"\r\n\r\nb\r\n'
                               b'--B\r\nContent-Disposition: form-data; name="f"; filename="f.png"\r\n'
                               b'Content-Type: image/png\r\n\r\nxyz\r\n--B--\r\n', 'multipart/form-data; boundary=B'))

    def test_options_still_reach_call(self):
        *_, options = self.sent({'a': 'b'}, ('f', 'f.png', b'x', 'image/png'), retry=False)
        self.assertEqual(options, {'retry': False})

    def test_put_without_a_file_is_a_closed_multipart_of_only_the_fields(self):
        method, _, _, (data, kind), _ = self.sent({'layout': '[1]', 'avatar_source': 0}, method='PUT')
        self.assertEqual(method, 'PUT')
        message = BytesParser(policy=default).parsebytes(f'Content-Type: {kind}\r\n\r\n'.encode() + data)
        parts = {p.get_param('name', header='content-disposition'): (p.get_filename(), p.get_content()) for p in message.iter_parts()}
        self.assertEqual(parts, {'layout': (None, '[1]'), 'avatar_source': (None, '0')})


class PrivateTest(unittest.TestCase):
    """Run.read_private · seed_private — 실명 · 카톡 아이디는 암호문 열뿐이라(M2 로 평문 열 삭제) 복호화 · 암호화 RPC 로만 읽고 쓴다.
    키는 환경 변수 PHONE_ENCRYPTION_KEY 에서 받아 JSON 바디로만 보낸다(주소 · 메모에 안 싣는다)."""

    KEY = 'secret-k'

    def setUp(self):
        self.run = tools.Run(Path(tempfile.mkdtemp()) / 'b', 'b', cfg={'SUPABASE_URL': 'https://sb.test'}, key='svc')
        self.sent, self.replies = [], []
        patcher = mock.patch.object(tools, 'call', self.fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        env = mock.patch.dict(tools.os.environ, {'PHONE_ENCRYPTION_KEY': self.KEY})
        env.start()
        self.addCleanup(env.stop)

    def fake(self, method, url, headers=None, body=None, **options):
        self.sent.append((method, url, body))
        return self.replies.pop(0) if self.replies else tools.Reply(204, None)

    def test_read_decrypts_through_the_rpc_with_the_key_only_in_the_body(self):
        self.replies.append(tools.Reply(200, [{'real_name': '홍길동', 'kakao_id': 'e2e1'}]))
        self.assertEqual(self.run.read_private('id-1'), {'real_name': '홍길동', 'kakao_id': 'e2e1'})
        [(method, url, body)] = self.sent
        self.assertEqual((method, url), ('POST', 'https://sb.test/rest/v1/rpc/decrypt_profile_private'))
        self.assertEqual(body, {'p_profile': 'id-1', 'p_key': self.KEY})

    def test_read_of_a_missing_row_is_two_nones(self):
        self.replies.append(tools.Reply(200, []))
        self.assertEqual(self.run.read_private('id-1'), {'real_name': None, 'kakao_id': None})

    def test_without_the_key_reading_or_writing_is_blocked_before_any_request(self):
        with mock.patch.dict(tools.os.environ, {}, clear=True):
            for act in (lambda: self.run.read_private('id-1'), lambda: self.run.seed_private('id-1', kakao_id='k')):
                with self.assertRaises(tools.Blocked) as caught:
                    act()
                self.assertIn('PHONE_ENCRYPTION_KEY', str(caught.exception))
        self.assertEqual(self.sent, [])

    def test_a_failed_rpc_is_blocked_with_the_code_but_never_the_key(self):
        for act in (lambda: self.run.read_private('id-1'), lambda: self.run.seed_private('id-1', real_name='A')):
            self.replies.append(tools.Reply(400, {'code': '39000', 'message': f'Wrong key {self.KEY}'}))
            with self.assertRaises(tools.Blocked) as caught:
                act()
            self.assertIn('39000', str(caught.exception))
            self.assertNotIn(self.KEY, str(caught.exception))
        for reply in (tools.Reply(503, {'message': 'down'}), tools.Reply(502, None)):  # 코드가 없으면 상태만
            self.replies.append(reply)
            with self.assertRaises(tools.Blocked) as caught:
                self.run.read_private('id-1')
            self.assertEqual(str(caught.exception), f'decrypt_profile_private {reply.status}')

    def test_seed_writes_each_given_field_through_its_rpc_and_leaves_none_alone(self):
        self.run.seed_private('id-1', real_name='E2E실명', kakao_id='kk1')
        self.run.seed_private('id-2', kakao_id='kk2')
        self.assertEqual(self.sent, [
            ('POST', 'https://sb.test/rest/v1/rpc/set_real_name', {'p_profile': 'id-1', 'p_real_name': 'E2E실명', 'p_key': self.KEY}),
            ('POST', 'https://sb.test/rest/v1/rpc/set_kakao_id', {'p_profile': 'id-1', 'p_kakao_id': 'kk1', 'p_key': self.KEY}),
            ('POST', 'https://sb.test/rest/v1/rpc/set_kakao_id', {'p_profile': 'id-2', 'p_kakao_id': 'kk2', 'p_key': self.KEY})])

    def test_seed_with_an_empty_string_clears_the_field(self):
        self.run.seed_private('id-1', real_name='')  # DB 함수가 빈 문자열을 암호문 null 로 저장한다
        self.assertEqual(self.sent, [('POST', 'https://sb.test/rest/v1/rpc/set_real_name',
                                      {'p_profile': 'id-1', 'p_real_name': '', 'p_key': self.KEY})])


class ParserTest(unittest.TestCase):
    def test_common_options_work_before_or_after_the_command(self):
        for argv in (['--bundle', 'b1', '--revision', 'r1', 'run', 'SMOKE'],
                     ['run', 'SMOKE', '--bundle', 'b1', '--revision', 'r1']):
            args = build_parser().parse_args(argv)
            self.assertEqual((args.bundle, args.revision, args.case), ('b1', 'r1', ['SMOKE']), argv)

    def test_default_bundle_when_not_given(self):
        self.assertEqual(build_parser().parse_args(['report']).bundle, 'area1-1')


if __name__ == '__main__':
    unittest.main()
