"""일시적인 통신 끊김에 하네스가 버티는지 — 가짜 소켓으로, 기기 · 운영 없이 돈다."""

import http.client
import io
import ssl
import unittest
import urllib.error
from unittest import mock

from e2e import __main__ as cli
from e2e import tools


class Response(io.BytesIO):
    """urlopen 이 돌려주는 것 — with 로 열고 status · headers 를 가진다."""

    def __init__(self, body=b'{"ok": true}', status=200):
        super().__init__(body)
        self.status, self.headers = status, {}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def flaky(*errors, then=None):
    """errors 를 차례로 던지고, 다 던지면 then(기본 200 JSON)을 돌려주는 urlopen 대역."""
    queue = list(errors)
    calls = []

    def urlopen(req, timeout=None):
        calls.append(req.full_url)
        if queue:
            raise queue.pop(0)
        return then or Response()
    urlopen.calls = calls
    return urlopen


class CallRetryTest(unittest.TestCase):
    def setUp(self):
        tools.take_retries()
        sleeps = mock.patch.object(tools.time, 'sleep')
        self.sleep = sleeps.start()
        self.addCleanup(sleeps.stop)

    def call(self, *errors):
        urlopen = flaky(*errors)
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen):
            reply = tools.call('POST', 'https://x.test/a', body={'a': 1})
        return reply, urlopen

    def test_two_resets_then_success_returns_the_reply(self):
        reply, urlopen = self.call(ConnectionResetError(10054, 'reset'), ConnectionResetError(10054, 'reset'))
        self.assertEqual((reply.status, reply.body), (200, {'ok': True}))
        self.assertEqual(len(urlopen.calls), 3)
        self.assertEqual(tools.take_retries(), 2)

    def test_backoff_doubles_between_tries(self):
        self.call(ConnectionResetError(), ssl.SSLError('bad record mac'), TimeoutError())
        self.assertEqual([c.args[0] for c in self.sleep.call_args_list], [1, 2, 4])

    def test_every_kind_of_transient_error_is_retried(self):
        for error in (ConnectionResetError(), ssl.SSLError('bad record mac'), TimeoutError(), urllib.error.URLError('dns'),
                      http.client.RemoteDisconnected('closed'), http.client.IncompleteRead(b'')):
            tools.take_retries()
            reply, _ = self.call(error)
            self.assertEqual(reply.status, 200, error)
            self.assertEqual(tools.take_retries(), 1, error)

    def test_gives_up_after_three_retries_and_raises_the_last_error(self):
        urlopen = flaky(*[ConnectionResetError(10054, f'reset {i}') for i in range(9)])
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen), self.assertRaises(ConnectionResetError) as ctx:
            tools.call('GET', 'https://x.test/a')
        self.assertEqual(len(urlopen.calls), 4)  # 처음 + 재시도 3번
        self.assertIn('reset 3', str(ctx.exception))
        self.assertEqual(tools.retry_paths(), ['GET /a'] * 3)  # 마지막(네 번째) 실패는 다시 보낸 게 아니라 올라간 예외다
        self.assertEqual(tools.take_retries(), 3)

    def test_an_http_error_status_is_a_reply_not_a_retry(self):
        error = urllib.error.HTTPError('https://x.test/a', 503, 'down', {}, io.BytesIO(b'{"detail": "x"}'))
        reply, urlopen = self.call(error)
        self.assertEqual(reply.status, 503)
        self.assertEqual(len(urlopen.calls), 1)
        self.assertEqual(tools.take_retries(), 0)

    def test_other_errors_are_not_swallowed(self):
        urlopen = flaky(ValueError('bad url'))
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen), self.assertRaises(ValueError):
            tools.call('GET', 'https://x.test/a')
        self.assertEqual(len(urlopen.calls), 1)

    def test_take_retries_counts_since_the_last_take(self):
        self.call(ConnectionResetError())
        self.assertEqual(tools.take_retries(), 1)
        self.assertEqual(tools.take_retries(), 0)

    def test_a_retried_request_is_remembered_by_method_and_path_only(self):
        urlopen = flaky(ConnectionResetError())
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen):
            tools.call('POST', 'https://sb.test/rest/v1/profiles?select=id&token=SECRET', {'Authorization': 'Bearer SECRET'}, body={'a': 1})
        self.assertEqual(tools.retry_paths(), ['POST /rest/v1/profiles'])
        self.assertNotIn('SECRET', ' '.join(tools.retry_paths()))
        self.assertNotIn('sb.test', ' '.join(tools.retry_paths()))

    def test_ids_in_the_path_are_masked(self):
        urlopen = flaky(ConnectionResetError())
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen):
            tools.call('GET', 'https://api.test/chat/matches/6f1d2c3e-0a4b-4c5d-8e9f-1a2b3c4d5e6f/messages')
        self.assertEqual(tools.retry_paths(), ['GET /chat/matches/:id/messages'])

    def test_a_request_that_is_not_retried_leaves_no_path(self):
        urlopen = flaky(ConnectionResetError(), then=Response())
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen), self.assertRaises(ConnectionResetError):
            tools.call('POST', 'https://x.test/send', body={'a': 1}, retry=False)
        self.assertEqual(tools.retry_paths(), [])

    def test_a_request_that_succeeds_first_leaves_no_path(self):
        with mock.patch.object(tools.urllib.request, 'urlopen', flaky()):
            tools.call('GET', 'https://x.test/a')
        self.assertEqual(tools.retry_paths(), [])

    def test_reading_the_paths_does_not_clear_them(self):
        self.call(ConnectionResetError())
        self.assertEqual(tools.retry_paths(), tools.retry_paths())
        self.assertEqual(tools.retry_paths(), ['POST /a'])

    def test_take_retries_also_clears_the_paths(self):
        self.call(ConnectionResetError())
        self.assertEqual(tools.retry_paths(), ['POST /a'])
        tools.take_retries()
        self.assertEqual(tools.retry_paths(), [])


class RunCaseTest(unittest.TestCase):
    def setUp(self):
        tools.take_retries()

    def test_an_unexpected_exception_blocks_only_that_case(self):
        def once(case):
            if case == 'E-A-01':
                raise ConnectionResetError(10054, 'reset')
            return 'pass', ''
        results = [cli.run_case(once, case) for case in ('E-A-01', 'E-A-02')]
        self.assertEqual(results[0][1], 'blocked')
        self.assertIn('진행 프로그램 예외 ConnectionResetError', results[0][2])
        self.assertEqual(results[1][1:], ('pass', ''))  # 다음 가설은 그대로

    def test_a_fail_gets_a_second_try_and_the_attempt_number_is_reported(self):
        answers = iter([('fail', 'x'), ('pass', '')])
        self.assertEqual(cli.run_case(lambda case: next(answers), 'E-A-01'), (2, 'pass', ''))

    def test_an_exception_on_the_second_try_is_still_blocked_not_a_crash(self):
        answers = [('fail', 'x'), ConnectionResetError()]

        def once(case):
            answer = answers.pop(0)
            if isinstance(answer, Exception):
                raise answer
            return answer
        attempt, result, note = cli.run_case(once, 'E-A-01')
        self.assertEqual((attempt, result), (2, 'blocked'))

    def test_keyboard_interrupt_and_exit_still_stop_the_run(self):
        for stop in (KeyboardInterrupt, SystemExit):
            with self.assertRaises(stop):
                cli.run_case(mock.Mock(side_effect=stop), 'E-A-01')

    def test_retried_requests_are_written_in_the_note(self):
        def once(case):
            tools.RETRIES[0] += 2
            return 'pass', ''
        self.assertEqual(cli.run_case(once, 'E-A-01')[2], '통신 재시도 2번')

    def test_the_note_names_which_request_was_retried(self):
        def once(case):
            tools.RETRIES[0] += 1
            tools.RETRIED.append('GET /rest/v1/profiles')
            return 'pass', ''
        self.assertEqual(cli.run_case(once, 'E-A-01')[2], '통신 재시도 1번: GET /rest/v1/profiles')

    def test_the_same_request_retried_twice_is_counted_not_repeated(self):
        def once(case):
            tools.RETRIES[0] += 3
            tools.RETRIED.extend(['GET /rest/v1/profiles', 'POST /auth/v1/verify', 'GET /rest/v1/profiles'])
            return 'pass', ''
        self.assertEqual(cli.run_case(once, 'E-A-01')[2], '통신 재시도 3번: GET /rest/v1/profiles ×2, POST /auth/v1/verify')

    def test_the_paths_follow_the_existing_note_text(self):
        def once(case):
            tools.RETRIES[0] += 1
            tools.RETRIED.append('GET /me/profile')
            return 'pass', '메모'
        self.assertEqual(cli.run_case(once, 'E-A-01')[2], '메모 (통신 재시도 1번: GET /me/profile)')

    def test_paths_of_one_case_do_not_leak_into_the_next(self):
        def once(case):
            if case == 'E-A-01':
                tools.RETRIES[0] += 1
                tools.RETRIED.append('GET /me/profile')
            return 'pass', ''
        cli.run_case(once, 'E-A-01')
        self.assertEqual(cli.run_case(once, 'E-A-02')[2], '')

    def test_retries_made_between_cases_do_not_leak_into_the_next_note(self):
        tools.RETRIES[0] = 5  # 가설 밖(가설 사이 정리 등)에서 쌓인 재시도
        self.assertEqual(cli.run_case(lambda case: ('pass', ''), 'E-A-01')[2], '')

    def test_retries_of_one_case_do_not_leak_into_the_next(self):
        def once(case):
            if case == 'E-A-01':
                tools.RETRIES[0] += 1
            return 'pass', ''
        cli.run_case(once, 'E-A-01')
        self.assertEqual(cli.run_case(once, 'E-A-02')[2], '')


class NoRetryTest(unittest.TestCase):
    """비멱등 요청(메시지 보내기 · 하트 차감 · 신고 · 투표)은 두 번 적용되면 안 되므로 가설이 재시도를 끈다 — retry=False."""

    def setUp(self):
        tools.take_retries()
        sleeps = mock.patch.object(tools.time, 'sleep')
        sleeps.start()
        self.addCleanup(sleeps.stop)

    def test_call_without_retry_sends_once_and_raises_the_first_error(self):
        urlopen = flaky(ConnectionResetError(10054, 'reset'), then=Response())
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen), self.assertRaises(ConnectionResetError):
            tools.call('POST', 'https://x.test/send', body={'a': 1}, retry=False)
        self.assertEqual(len(urlopen.calls), 1)
        self.assertEqual(tools.take_retries(), 0)

    def test_retry_stays_on_by_default(self):
        urlopen = flaky(ConnectionResetError())
        with mock.patch.object(tools.urllib.request, 'urlopen', urlopen):
            self.assertEqual(tools.call('POST', 'https://x.test/a').status, 200)
        self.assertEqual(len(urlopen.calls), 2)

    def test_every_wrapper_hands_retry_through_to_call(self):
        cfg = {'SUPABASE_URL': 'https://sb.test', 'API_BASE_URL': 'https://api.test'}
        for name, call in (('rest', lambda **kw: tools.rest(cfg, 'k', 'POST', 'x', {}, **kw)),
                           ('admin', lambda **kw: tools.admin(cfg, 'k', 'POST', 'x', {}, **kw)),
                           ('api', lambda **kw: tools.api(cfg, 'POST', '/x', 't', {}, **kw)),
                           ('form', lambda **kw: tools.form('https://api.test/x', 't', {'a': 'b'}, ('f', 'f.png', b'x', 'image/png'), **kw))):
            with mock.patch.object(tools, 'call', return_value=tools.Reply(200, None)) as sent:
                call(retry=False)
                self.assertIs(sent.call_args.kwargs.get('retry'), False, name)
                call()
                self.assertIsNot(sent.call_args.kwargs.get('retry'), False, name)  # 안 주면 켜진 채

    def test_message_review_form_and_direct_table_helpers_hand_retry_through(self):
        from e2e import area1, area3
        run = mock.Mock(cfg={'API_BASE_URL': 'https://api.test', 'SUPABASE_URL': 'https://sb.test', 'SUPABASE_ANON_KEY': 'anon'})
        account = {'token': 't', 'id': 'u'}
        helpers = {
            '_send': lambda **kw: area3._send(run, account, 'm1', 'hi', **kw),  # E-CHAT-08 의 메시지 보내기
            '_review_post': lambda **kw: area3._review_post(run, account, {'id': 'r'}, **kw),
            '_as_user': lambda **kw: area3._as_user(run, account, 'POST', 'x', {}, **kw),
            '_form': lambda **kw: area1._form(run, '/x', 't', {'a': 'b'}, ('photo', 'p.jpg', b'x'), **kw),
        }
        for name, helper in helpers.items():
            with mock.patch.object(tools, 'call', return_value=tools.Reply(200, None)) as sent:
                helper(retry=False)
                self.assertIs(sent.call_args.kwargs.get('retry'), False, name)
                helper()
                self.assertIsNot(sent.call_args.kwargs.get('retry'), False, name)

    def test_phone_case_helper_hands_retry_through(self):
        from e2e import area1
        run = mock.Mock(cfg={'API_BASE_URL': 'https://api.test'})
        with mock.patch.object(tools, 'call', return_value=tools.Reply(200, None)) as sent:
            area1._api(run, 'POST', '/send', 't', {'a': 1}, retry=False)
        self.assertIs(sent.call_args.kwargs.get('retry'), False)


if __name__ == '__main__':
    unittest.main()
