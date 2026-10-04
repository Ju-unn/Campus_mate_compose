"""영역 1 폰 가설의 PC 쪽(계정 준비 · 앱에 넘길 일감 · DB 판정) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_phone`."""

import unittest
from unittest import mock

from e2e import area1
from e2e.test_area1 import Base
from e2e.tools import Reply

APP_PASS = {'result': 'pass'}
CHROME = 'topResumedActivity=ActivityRecord{1 u0 com.android.chrome/.Main t9}'
OURS = 'topResumedActivity=ActivityRecord{1 u0 io.github.juunn.campusmate/.MainActivity t9}'


class FakePhone:
    """앱 대신 답한다. [answers] 를 차례로(마지막은 계속) 돌려주고, 받은 일감을 [jobs] 에 남긴다."""

    def __init__(self, *answers, top=CHROME):
        self.answers = list(answers) or [APP_PASS]
        self.jobs = []
        self._tops = list(top) if isinstance(top, list) else [top]

    def __call__(self, **job):
        self.jobs.append(job)
        return self.answers.pop(0) if len(self.answers) > 1 else self.answers[0]

    def top(self):
        """[top] 이 목록이면 부를 때마다 다음 것(마지막은 계속) — 브라우저가 늦게 뜨는 경우."""
        return self._tops.pop(0) if len(self._tops) > 1 else self._tops[0]


class PhoneBundleTest(Base):
    def test_bundle_is_the_37_phone_hypotheses_but_the_two_device_one(self):
        plan = ('E-AUTH-05 16 17 20 21 E-GATE-01 02 03 07 08 09 10 11 13 14 30 31 32 52 53 54 56 '
                'E-ONB-01 02 03 04 05 06 07 10 11 12 13 15 16 17 18').split()
        cases, prefix = [], None
        for word in plan:
            if word.startswith('E-'):
                prefix, word = word.rsplit('-', 1)
            cases.append(f'{prefix}-{word}')
        self.assertEqual(len(cases), 37)
        self.assertEqual(area1.BUNDLES['area1-b1-phone'], [c for c in cases if c != 'E-ONB-05'])
        self.assertEqual(set(area1.PHONE), set(area1.BUNDLES['area1-b1-phone']))
        self.assertIn('E-ONB-05', area1.PHONE_SKIPPED)


class PhoneAnswerTest(Base):
    def test_app_pass_is_pass_and_the_app_gets_a_sign_in_token(self):
        self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-01', phone), ('pass', ''))
        self.assertEqual(phone.jobs, [{'token_hash': 'h'}])

    def test_app_fail_note_is_kept(self):
        self.serve()
        result, note = area1.attempt_phone(self.run, 'E-GATE-01', FakePhone({'result': 'fail', 'note': '뒤로 버튼 1개'}))
        self.assertEqual(result, 'fail')
        self.assertIn('뒤로 버튼 1개', note)

    def test_app_silence_is_fail(self):
        self.serve()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-01', FakePhone(None))[0], 'fail')

    def test_app_blocked_is_blocked(self):
        self.serve()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-01', FakePhone({'result': 'blocked', 'note': 'x'}))[0],
                         'blocked')

    def test_account_setup_failure_is_blocked_before_the_app_runs(self):
        self.serve({('POST', '/me/consents'): Reply(500, None)})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-30', phone)[0], 'blocked')
        self.assertEqual(phone.jobs, [])


class ConsentTest(Base):
    GOOD = [{'kind': 'terms', 'version': '2026-09-29'}, {'kind': 'privacy', 'version': '2026-09-29'}]

    def test_gate_08_two_rows_and_marketing_off(self):
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, self.GOOD),
                    ('GET', '/rest/v1/notification_settings'): Reply(200, [{'marketing': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-08', FakePhone())[0], 'pass')

    def test_gate_08_marketing_on_fails(self):
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, self.GOOD),
                    ('GET', '/rest/v1/notification_settings'): Reply(200, [{'marketing': True}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-08', FakePhone())[0], 'fail')

    def test_gate_09_consent_time_within_a_minute_of_the_tap(self):
        settings = [{'marketing': True, 'marketing_consented_at': '2026-10-04T10:00:30+00:00'}]
        self.serve({('GET', '/rest/v1/notification_settings'): Reply(200, settings)})
        tapped = {'result': 'pass', 'tapped_at': '2026-10-04T10:00:00Z'}
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-09', FakePhone(tapped))[0], 'pass')
        late = {'result': 'pass', 'tapped_at': '2026-10-04T09:55:00Z'}
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-09', FakePhone(late))[0], 'fail')

    def test_gate_13_three_rows_fail(self):
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, self.GOOD + [self.GOOD[0]])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-13', FakePhone())[0], 'fail')

    def test_gate_11_browser_on_top_passes_and_our_app_on_top_fails(self):
        self.serve()
        with mock.patch.object(area1.time, 'sleep'):
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-11', FakePhone())[0], 'pass')
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-11', FakePhone(top=OURS))[0], 'fail')

    def test_gate_11_waits_for_a_browser_that_opens_late(self):
        self.serve()
        with mock.patch.object(area1.time, 'sleep'):
            late = FakePhone(top=[OURS, OURS, CHROME])
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-11', late)[0], 'pass')

    def test_gate_08_old_version_rows_fail(self):
        old = [{'kind': 'terms', 'version': '2026-09-01'}, {'kind': 'privacy', 'version': '2026-09-01'}]
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, old),
                    ('GET', '/rest/v1/notification_settings'): Reply(200, [{'marketing': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-08', FakePhone())[0], 'fail')


class SessionTest(Base):
    def test_auth_05_sends_an_example_com_address_without_signing_in(self):
        self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-05', phone)[0], 'pass')
        self.assertEqual(list(phone.jobs[0]), ['email'])
        self.assertTrue(phone.jobs[0]['email'].endswith('@example.com'))

    def test_auth_05_account_made_anyway_is_deleted_and_fails(self):
        fake = self.serve({('GET', '/auth/v1/admin/users'): Reply(200, {'users': [
            {'id': '11111111-1111-4111-8111-111111111111', 'email': 'base+e2e1001@example.com'}]})})
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-05', FakePhone())[0], 'fail')
        self.assertIn('/auth/v1/admin/users/11111111-1111-4111-8111-111111111111', fake.paths('DELETE'))

    def test_auth_17_restarts_each_stage_without_signing_in_again(self):
        self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-17', phone)[0], 'pass')
        self.assertEqual([(j.get('fresh', True), 'token_hash' in j) for j in phone.jobs], [(True, True), (False, False)] * 3)
        self.assertEqual([j['expect'] for j in phone.jobs[::2]], ['consent', '3c', '04-1b'])

    def test_auth_20_logs_out_everywhere_between_the_two_runs(self):
        fake = self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-20', phone)[0], 'pass')
        self.assertIn('/auth/v1/logout', fake.paths('POST'))
        self.assertEqual([j.get('fresh', True) for j in phone.jobs], [True, False])
        self.assertEqual(phone.jobs[1]['expect'], 'login')

    def test_auth_20_logout_failure_is_blocked(self):
        self.serve({('POST', '/auth/v1/logout'): Reply(401, None)})
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-20', FakePhone())[0], 'blocked')

    def test_auth_21_gives_the_app_two_accounts(self):
        self.serve()
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-AUTH-21', phone)
        self.assertEqual(sorted(phone.jobs[0]), ['second', 'token_hash'])

    def test_gate_03_suspends_three_stages_before_opening_the_app(self):
        fake = self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-03', phone)[0], 'pass')
        self.assertEqual([b for m, p, b in fake.calls if m == 'PATCH' and b == {'status': 'suspended'}], [{'status': 'suspended'}] * 3)
        self.assertEqual(len(phone.jobs), 3)


class GateTest(Base):
    def test_gate_52_tells_the_app_the_school_name(self):
        self.serve({('GET', '/rest/v1/universities'): Reply(200, [{'name': '테스트대학교'}])})
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-GATE-52', phone)
        self.assertEqual(phone.jobs[0]['university'], '테스트대학교')

    def test_gate_54_checks_what_was_saved(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'major': '컴퓨터공학과', 'student_number': '21'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-54', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'major': None, 'student_number': None}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-54', FakePhone())[0], 'fail')

    def test_gate_56_one_token_row_before_and_after_saving(self):
        one = Reply(200, [{'token': 't1'}])
        self.serve({('GET', '/rest/v1/push_tokens'): one})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-56', phone)[0], 'pass')
        self.assertEqual([j.get('fresh', True) for j in phone.jobs], [True, False])
        self.serve({('GET', '/rest/v1/push_tokens'): [one, Reply(200, [{'token': 't1'}, {'token': 't2'}])]})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-56', FakePhone())[0], 'fail')

    def test_gate_56_no_token_before_saving_fails(self):
        self.serve({('GET', '/rest/v1/push_tokens'): Reply(200, [])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-56', FakePhone())[0], 'fail')


class OnboardingTest(Base):
    def test_onb_03_someone_else_holds_the_nickname_the_app_types(self):
        fake = self.serve()
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-ONB-03', phone)
        held = [b['nickname'] for m, p, b in fake.calls if p == '/profile-onboarding/basic-info']
        self.assertIn(phone.jobs[0]['nickname'], held)
        self.assertRegex(phone.jobs[0]['nickname'], r'^[A-Z][a-z]{4}$')

    def test_onb_04_clears_the_phone_so_the_account_is_back_on_04_1(self):
        fake = self.serve()
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-ONB-04', phone)
        self.assertIn({'phone_number': None}, [b for m, p, b in fake.calls if m == 'PATCH' and p == '/rest/v1/profile_private'])
        self.assertIn(phone.jobs[0]['nickname'], [b['nickname'] for m, p, b in fake.calls if p == '/profile-onboarding/basic-info'])

    def test_onb_06_gives_the_app_the_youngest_birth_year(self):
        self.serve()
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-ONB-06', phone)
        self.assertEqual(phone.jobs[0]['year'], area1.datetime.now(area1.SEOUL).year - 19)

    def test_onb_11_phone_is_stored_encrypted_with_its_hmac(self):
        stored = Reply(200, [{'phone_number': '\\x9f3a', 'phone_hmac': '\\x01'}])
        self.serve({('GET', '/rest/v1/profile_private'): stored})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-11', FakePhone())[0], 'pass')

    def test_onb_11_plain_number_or_missing_hmac_fails(self):
        with mock.patch.object(area1, '_phone_number', lambda: '010-1234-5678'):
            for row in ({'phone_number': '+821012345678', 'phone_hmac': '\\x01'}, {'phone_number': '\\x9f3a', 'phone_hmac': None}):
                self.serve({('GET', '/rest/v1/profile_private'): Reply(200, [row])})
                phone = FakePhone()
                self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-11', phone)[0], 'fail', row)
                self.assertEqual(phone.jobs[0]['phone'], '010-1234-5678')

    def test_onb_13_api_takes_the_old_ten_digit_number(self):
        fake = self.serve({('GET', '/rest/v1/profile_private'): Reply(200, [{'phone_number': '\\x9f', 'phone_hmac': '\\x01'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-13', FakePhone())[0], 'pass')
        sent = [b['phone_number'] for m, p, b in fake.calls if p == '/profile-onboarding/basic-info']
        self.assertIn('011-123-4567', sent)

    def test_onb_16_and_17_need_an_empty_mbti(self):
        for case in ('E-ONB-16', 'E-ONB-17'):
            self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'mbti': None}])})
            self.assertEqual(area1.attempt_phone(self.run, case, FakePhone())[0], 'pass', case)
            self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'mbti': 'ENTP'}])})
            self.assertEqual(area1.attempt_phone(self.run, case, FakePhone())[0], 'fail', case)

    def test_onb_18_kakao_id_is_trimmed(self):
        self.serve({('GET', '/rest/v1/profile_private'): Reply(200, [{'kakao_id': 'cm_test'}])})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-18', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['kakao'], '  cm_test  ')
        self.serve({('GET', '/rest/v1/profile_private'): Reply(200, [{'kakao_id': '  cm_test  '}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-18', FakePhone())[0], 'fail')


if __name__ == '__main__':
    unittest.main()
