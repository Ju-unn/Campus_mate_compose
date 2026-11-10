"""휴대폰 문자 인증 가설의 PC 쪽 도구(e2e/phone_sms.py) 시험 — 운영 · 폰 · 로컬 서버 없이 가짜 HTTP 와 임시 파일로 돈다.
저장소 루트에서 `python -m unittest e2e.test_phone_sms`.

시험 번호는 가짜 값(FAKE_PHONE)이다 — 진짜 시험 번호는 이 저장소 어디에도 적지 않는다."""

import contextlib
import os
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from e2e import phone_sms, tools
from e2e.test_area1 import CFG, Base
from e2e.tools import Blocked, Reply

FAKE_PHONE = '010-9876-5432'
PROD = {**CFG, 'SUPABASE_URL': 'https://abcdefgh.supabase.co'}
LOCAL_DB = 'http://127.0.0.1:54321'
PROD_API = 'https://campusmate-abcdefgh-du.a.run.app'  # 운영 Cloud Run 모양(*.run.app)


def forbid_requests(test):
    """운영 주소 시험이 방어가 무너졌을 때 실제로 요청을 보내지 않게 한다 — 요청 함수와 urllib 을 막고, 부르면 그 자리에서 시험이 실패한다.
    돌려주는 목록은 막은 시도들(정상이면 늘 비어 있다)."""
    attempts = []

    def refuse(*args, **kwargs):
        attempts.append(args[:2])
        raise AssertionError(f'운영 주소로 요청이 나감: {args[:2]}')

    for target in (mock.patch.object(tools, 'call', refuse), mock.patch('urllib.request.urlopen', refuse)):
        target.start()
        test.addCleanup(target.stop)
    return attempts


def sms_line(code, last4='5432'):
    """서버 FakeSmsSender 가 남기는 줄(backend/app/phone_verification/sms.py) — 로거 이름 앞붙임까지 같다."""
    return f'INFO app.phone_verification.sms: 가짜 문자 발송(로컬) to=…{last4} text=[CampusMate] 인증번호 [{code}]을 입력해 주세요.\n'


@contextlib.contextmanager
def environment(**pairs):
    """E2E_* 환경값을 시험 동안만 바꾼다(None 이면 지운다). 시험 번호 파일은 없는 경로로 막아 두고, 쓰려면 PHONE_FILE 로 준다."""
    base = {'E2E_TEST_PHONE': None, 'E2E_TEST_PHONE_FILE': str(Path(tempfile.gettempdir()) / '없는-시험-번호.txt'), 'E2E_SERVER_LOG': None}
    merged = {**base, **pairs}
    with mock.patch.dict(os.environ):
        for key, value in merged.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        yield


class Texting:
    """가설 시험이 쓰는 가짜 시험 번호 + 가짜 서버 로그. [log] 에 줄을 더하면 서버가 문자를 보낸 것과 같다."""

    def start_texting(self, test, *codes):
        folder = tempfile.mkdtemp()
        self.log = Path(folder) / 'server.log'
        self.log.write_text(''.join(sms_line(code) for code in codes), encoding='utf-8')
        env = environment(E2E_TEST_PHONE=FAKE_PHONE, E2E_SERVER_LOG=str(self.log))
        env.__enter__()
        test.addCleanup(env.__exit__, None, None, None)
        poll = mock.patch.object(phone_sms, 'POLL', 0.02)
        poll.start()
        test.addCleanup(poll.stop)

    def sent(self, *codes):
        with self.log.open('a', encoding='utf-8') as out:
            out.write(''.join(sms_line(code) for code in codes))


class TestPhoneTest(unittest.TestCase):
    def test_it_reads_the_number_from_the_environment(self):
        with environment(E2E_TEST_PHONE=FAKE_PHONE):
            self.assertEqual(phone_sms.test_phone(), FAKE_PHONE)

    def test_it_reads_the_number_from_the_secrets_file_and_trims_it(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'e2e-test-phone.txt'
            path.write_text('\n 01098765432 \n', encoding='utf-8')
            with environment(E2E_TEST_PHONE_FILE=str(path)):
                self.assertEqual(phone_sms.test_phone(), FAKE_PHONE)

    def test_the_environment_wins_over_the_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'e2e-test-phone.txt'
            path.write_text('010-1111-2222', encoding='utf-8')
            with environment(E2E_TEST_PHONE=FAKE_PHONE, E2E_TEST_PHONE_FILE=str(path)):
                self.assertEqual(phone_sms.test_phone(), FAKE_PHONE)

    def test_the_default_file_is_in_the_secrets_folder_outside_the_repository(self):
        with mock.patch.dict(os.environ):
            os.environ.pop('E2E_TEST_PHONE_FILE', None)
            self.assertEqual(phone_sms.phone_file(), Path.home() / 'campusmate-secrets' / 'e2e-test-phone.txt')

    def test_a_missing_file_stops_with_a_clear_error_that_names_the_file(self):
        with environment():
            with self.assertRaises(Blocked) as caught:
                phone_sms.test_phone()
        self.assertIn('시험 번호', str(caught.exception))
        self.assertIn('E2E_TEST_PHONE', str(caught.exception))

    def test_an_empty_or_malformed_number_is_refused_without_echoing_it(self):
        for bad in ('', '   \n', '02-123-4567', '011-1234-5678', '010-123-4567', '01098765432123'):
            with self.subTest(bad), environment(E2E_TEST_PHONE=bad or ' '):
                with self.assertRaises(Blocked) as caught:
                    phone_sms.test_phone()
                digits = ''.join(ch for ch in bad if ch.isdigit())
                self.assertTrue(not digits or digits not in str(caught.exception))

    def test_the_number_never_appears_in_any_error_text(self):
        with environment(E2E_TEST_PHONE='010-9876-54'):
            with self.assertRaises(Blocked) as caught:
                phone_sms.test_phone()
        self.assertNotIn('9876', str(caught.exception))
        self.assertNotIn('54', str(caught.exception).replace('E2E_TEST_PHONE', ''))


class RequireLocalTest(unittest.TestCase):
    def test_a_production_server_is_refused_with_the_reason(self):
        with self.assertRaises(Blocked) as caught:
            phone_sms.require_local(PROD)
        self.assertIn('운영', str(caught.exception))
        self.assertIn('인증번호 받기', str(caught.exception))

    def test_a_local_server_is_fine(self):
        phone_sms.require_local({**CFG, 'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': 'http://127.0.0.1:8000'})
        phone_sms.require_local(CFG)

    def test_a_local_database_with_a_production_api_address_is_refused(self):
        """앱의 API 주소가 운영 Cloud Run 이면 DB 가 로컬이어도 받기를 누르지 않는다 — 앱이 운영 서버로 문자를 시킨다."""
        with self.assertRaises(Blocked) as caught:
            phone_sms.require_local({**CFG, 'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': PROD_API})
        self.assertIn('API', str(caught.exception))
        self.assertIn('운영', str(caught.exception))

    def test_the_production_api_check_looks_at_the_host_not_the_whole_text(self):
        for api in ('http://127.0.0.1:8000', 'http://10.0.2.2:8000', 'http://localhost:8000', 'https://api.test',
                    'http://127.0.0.1:8000/?x=a.run.app', 'https://a.run.app.evil.test'):
            with self.subTest(api):
                phone_sms.require_local({**CFG, 'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': api})
        with self.assertRaises(Blocked):
            phone_sms.require_local({**CFG, 'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': 'HTTPS://Svc-1.A.RUN.APP:443/x'})

    def test_an_api_address_that_is_missing_or_empty_is_refused_because_it_cannot_be_checked(self):
        """주소를 모르면 앱이 어디로 문자를 시키는지 알 수 없다 — 모르면 막는다(로컬 기본값은 없다)."""
        for cfg in ({'SUPABASE_URL': LOCAL_DB}, {'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': ''},
                    {'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': '   '}):
            with self.subTest(cfg), self.assertRaises(Blocked) as caught:
                phone_sms.require_local(cfg)
            self.assertIn('API_BASE_URL', str(caught.exception))


class CodesInTest(unittest.TestCase):
    def test_it_pulls_the_six_digits_out_of_the_servers_fake_sms_lines_in_order(self):
        text = 'INFO uvicorn: started\n' + sms_line('123456') + 'WARNING x: y\n' + sms_line('654321')
        self.assertEqual(phone_sms.codes_in(text, '5432'), ['123456', '654321'])

    def test_lines_to_another_number_are_not_ours(self):
        text = sms_line('111111', last4='0000') + sms_line('222222')
        self.assertEqual(phone_sms.codes_in(text, '5432'), ['222222'])

    def test_it_does_not_depend_on_how_the_korean_in_the_line_was_decoded(self):
        raw = sms_line('135790').encode('utf-8').decode('cp949', errors='replace')
        self.assertEqual(phone_sms.codes_in(raw, '5432'), ['135790'])

    def test_other_bracketed_numbers_are_not_codes(self):
        self.assertEqual(phone_sms.codes_in('INFO x: 가짜 문자 발송(로컬) to=…5432 text=[CampusMate] 안내 [12]\n', '5432'), [])


class ReadLogTest(unittest.TestCase):
    def test_a_missing_file_is_empty(self):
        self.assertEqual(phone_sms.read_log(Path(tempfile.gettempdir()) / '없는-서버-로그.log'), '')

    def test_a_utf16_log_from_a_powershell_redirect_is_read(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'server.log'
            path.write_bytes(sms_line('246810').encode('utf-16'))
            self.assertEqual(phone_sms.codes_in(phone_sms.read_log(path), '5432'), ['246810'])


class ServerLogTest(unittest.TestCase):
    def test_the_environment_names_the_file(self):
        with environment(E2E_SERVER_LOG='x.log'):
            self.assertEqual(phone_sms.server_log(CFG), Path('x.log'))

    def test_the_env_file_may_name_it_too(self):
        with environment():
            self.assertEqual(phone_sms.server_log({**CFG, 'E2E_SERVER_LOG': 'y.log'}), Path('y.log'))

    def test_without_one_the_case_is_blocked_and_told_how_to_start_the_server(self):
        with environment():
            with self.assertRaises(Blocked) as caught:
                phone_sms.server_log(CFG)
        self.assertIn('E2E_SERVER_LOG', str(caught.exception))
        self.assertIn('uvicorn', str(caught.exception))


class CodeLogTest(unittest.TestCase, Texting):
    def setUp(self):
        self.start_texting(self, '111111')

    def log_for(self, **kw):
        return phone_sms.CodeLog(self.log, '5432', poll=0.01, **kw)

    def test_codes_sent_before_it_started_are_old(self):
        log = self.log_for()
        with self.assertRaises(Blocked):
            log.next_code(timeout=0.05)

    def test_it_returns_the_next_new_code_and_then_the_one_after(self):
        log = self.log_for()
        self.sent('222222')
        self.assertEqual(log.next_code(timeout=1), '222222')
        self.sent('333333')
        self.assertEqual(log.next_code(timeout=1), '333333')

    def test_it_waits_for_a_code_that_arrives_late(self):
        log = self.log_for()
        threading.Timer(0.1, self.sent, args=('444444',)).start()
        self.assertEqual(log.next_code(timeout=2), '444444')

    def test_no_code_in_time_is_blocked_and_the_message_has_no_number(self):
        log = self.log_for()
        with self.assertRaises(Blocked) as caught:
            log.next_code(timeout=0.05)
        self.assertNotIn('5432', str(caught.exception))
        self.assertIn('E2E_SERVER_LOG', str(caught.exception))

    def test_a_log_that_was_cut_short_starts_counting_again(self):
        log = self.log_for()
        self.sent('222222')
        self.assertEqual(log.next_code(timeout=1), '222222')
        self.log.write_text(sms_line('555555'), encoding='utf-8')  # 서버를 다시 띄워 로그가 처음부터
        self.assertEqual(log.next_code(timeout=1), '555555')


class ResetTest(Base):
    def test_it_clears_the_send_limits_and_the_verified_binding_on_a_local_database(self):
        fake = self.serve()
        phone_sms.reset(self.run)
        deletes = [p for m, p in [(m, p) for m, p, _ in fake.calls] if m == 'DELETE']
        self.assertEqual(deletes, ['/rest/v1/phone_verifications'])
        self.assertIn('id=not.is.null', [u for m, u in fake.urls if m == 'DELETE'][0])
        patch = [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == 'PATCH']
        self.assertEqual(len(patch), 1)
        self.assertIn('/rest/v1/profile_private', patch[0][0])
        self.assertIn('phone_verified_at=not.is.null', patch[0][0])
        self.assertEqual(patch[0][1], {'phone_verified_at': None})

    def test_it_never_touches_a_production_database(self):
        attempts = forbid_requests(self)
        self.run.cfg = PROD
        with self.assertRaises(Blocked) as caught:
            phone_sms.reset(self.run)
        self.assertIn('운영', str(caught.exception))
        self.assertEqual(attempts, [])

    def test_a_production_api_address_alone_also_stops_the_reset(self):
        attempts = forbid_requests(self)
        self.run.cfg = {**CFG, 'SUPABASE_URL': LOCAL_DB, 'API_BASE_URL': PROD_API}
        with self.assertRaises(Blocked):
            phone_sms.reset(self.run)
        self.assertEqual(attempts, [])

    def test_a_database_without_the_table_is_blocked_with_a_hint(self):
        self.serve({('DELETE', '/rest/v1/phone_verifications'): Reply(404, {'message': 'relation does not exist'})})
        with self.assertRaises(Blocked) as caught:
            phone_sms.reset(self.run)
        self.assertIn('마이그레이션', str(caught.exception))

    def test_release_cooldown_moves_the_sent_time_back_so_the_same_number_can_be_sent_again(self):
        fake = self.serve()
        phone_sms.release_cooldown(self.run)
        patch = [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == 'PATCH']
        self.assertEqual(len(patch), 1)
        self.assertIn('/rest/v1/phone_verifications', patch[0][0])
        moved = datetime.fromisoformat(patch[0][1]['sent_at'])
        self.assertGreater((datetime.now(timezone.utc) - moved).total_seconds(), 61)

    def test_release_cooldown_never_touches_a_production_database(self):
        attempts = forbid_requests(self)
        self.run.cfg = PROD
        with self.assertRaises(Blocked):
            phone_sms.release_cooldown(self.run)
        self.assertEqual(attempts, [])


class FakeHub:
    """우편함 대신 — 앱이 다음에 말할 멈춤 이름을 차례로 준다. go 로 받은 값은 [went] 에 쌓인다."""

    def __init__(self, *steps):
        self.steps = [{'step': name} if isinstance(name, str) else name for name in steps]
        self.went = []

    def go(self, extra=None):
        self.went.append(extra)

    def wait(self, timeout):
        return self.steps.pop(0) if self.steps else None


class SteppingTest(unittest.TestCase):
    def test_each_stop_runs_its_handler_and_the_last_value_is_returned_for_the_runner_to_send(self):
        seen = []
        hub = FakeHub('code', 'typed')
        midway = phone_sms.stepping(
            hub,
            lambda said: seen.append(said['step']),
            lambda said: {'code': '123456'},
            lambda said: seen.append(said['step']) or {'done': True},
        )
        self.assertEqual(midway({'step': 'send'}), {'done': True})
        self.assertEqual(seen, ['send', 'typed'])
        self.assertEqual(hub.went, [None, {'code': '123456'}])  # 앞 단계의 값이 다음 go 에 실린다

    def test_an_app_that_ends_before_its_next_stop_is_blocked(self):
        for said in (None, {'result': 'fail'}):
            midway = phone_sms.stepping(FakeHub(*([said] if said else [])), lambda s: None, lambda s: None)
            with self.assertRaises(Blocked):
                midway({'step': 'send'})


class SendTurnTest(Base):
    def test_only_one_device_holds_the_turn_and_the_second_waits_until_it_is_given_back(self):
        self.serve()
        turn = phone_sms.SendTurn(self.run, wait=2)
        order = []
        turn.take('A')

        def second():
            turn.take('B')
            order.append('B took')
            turn.give_back('B')

        thread = threading.Thread(target=second)
        thread.start()
        thread.join(0.2)
        self.assertEqual(order, [])
        turn.give_back('A')
        thread.join(2)
        self.assertEqual(order, ['B took'])

    def test_taking_the_turn_releases_the_one_minute_cooldown_of_the_number(self):
        fake = self.serve()
        turn = phone_sms.SendTurn(self.run, wait=1)
        turn.take('A')
        self.assertTrue([u for m, u in fake.urls if m == 'PATCH' and 'phone_verifications' in u])
        turn.give_back('A')

    def test_a_partner_that_never_finishes_blocks_the_case_instead_of_hanging(self):
        self.serve()
        turn = phone_sms.SendTurn(self.run, wait=0.1)
        turn.take('A')
        with self.assertRaises(Blocked):
            turn.take('B')

    def test_giving_back_a_turn_one_does_not_hold_changes_nothing(self):
        self.serve()
        turn = phone_sms.SendTurn(self.run, wait=0.1)
        turn.take('A')
        turn.give_back('B')
        with self.assertRaises(Blocked):
            turn.take('C')  # A 가 아직 쥐고 있다
        turn.give_back('A')
        turn.give_back('A')  # 두 번 돌려줘도 탈이 없다
        turn.take('C')


if __name__ == '__main__':
    unittest.main()
