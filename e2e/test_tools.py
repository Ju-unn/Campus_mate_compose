"""하네스 자체 시험 — 기기 · 운영 없이 돈다. 저장소 루트에서 `python -m unittest e2e.test_tools`."""

import json
import unittest
import urllib.request

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
