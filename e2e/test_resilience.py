"""일시적인 통신 끊김에 하네스가 버티는지 — 가짜 소켓으로, 기기 · 운영 없이 돈다."""

import http.client
import io
import ssl
import unittest
import urllib.error
from unittest import mock

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
