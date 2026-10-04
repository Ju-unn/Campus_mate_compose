"""영역 2 폰 A 1차 16(홈 · 추천 시트 · 알림 설정 · 하트 목록)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_phone`.

가설마다 일감에 실어 보내는 것 · DB 준비 값 · 앱이 pass 를 말할 때 · fail/blocked 를 말할 때를 본다."""

import subprocess
import sys
import unittest
from unittest import mock

from e2e import area1, area2_phone, tools
from e2e.test_area1_phone import FakePhone
from e2e.test_area2 import Base, Fake
from e2e.tools import Reply

FIRST = ('E-HOME-01 E-HOME-02 E-HOME-03 E-HOME-04 E-HOME-05 E-HOME-06 E-HOME-10 E-HOME-11 E-HOME-12 '
         'E-REF-01 E-REF-02 E-REF-03 E-CARD-21 E-HEART-01 E-HEART-02 E-HEART-03').split()
CODE = 'ABCDE2'


def _counted(total):
    return lambda b, u: Reply(200, [], {'Content-Range': f'0-0/{total}'})


def _summary(delivered=0, signups=0, conversations=0):
    return lambda b, u: Reply(200, {'delivered_cards': delivered, 'signups': signups, 'conversations_started': conversations})


def _neutral(**over):
    """모든 가설의 준비가 맞는 서버 — [over] 로 한 규칙씩 바꾼다(키 = 규칙 이름)."""
    rules = {
        'school': ('GET', 'universities?id=eq', lambda b, u: Reply(200, [{'card_opens_at': None, 'name': '테스트대학'}])),
        'campuses': ('GET', 'universities?select=name', lambda b, u: Reply(200, [{'name': '가대학'}, {'name': '테스트대학'}])),
        'cards': ('GET', 'daily_cards?', _counted(0)),
        'active': ('GET', 'profiles?select=id&status', _counted(0)),
        'talks': ('GET', 'messages.kind=eq.text', _counted(0)),
        'summary': ('GET', '/home/summary', _summary()),
        'code': ('GET', 'select=referral_code', lambda b, u: Reply(200, [{'referral_code': CODE}])),
        'materials': ('GET', 'select=mbti', lambda b, u: Reply(200, [{
            'mbti': None, 'preferred_height_min': None, 'preferred_height_max': None,
            'interest_tags': ['카페가기', '자전거', '패션'], 'profile_photos': [{'count': 2}]}])),
        'settings': ('GET', 'notification_settings?', lambda b, u: Reply(200, [])),
    }
    rules.update(over)
    return Fake(list(rules.values()))


# 가설마다 앱이 pass 와 함께 말하는 값(판정 재료) — 준비가 맞는 서버(_neutral)와 짝이 맞는다.
APP_SAYS = {
    'E-HOME-02': {'empty': True},
    'E-HOME-03': {'campuses': ['가대학', '테스트대학']},
    'E-HOME-12': {'rail': ['assets/images/person-f1-blind-v1.png']},
    'E-REF-01': {'code': CODE},
    'E-REF-02': {'codes': [CODE, CODE]},
    'E-REF-03': {'code': CODE, 'clipboard': CODE},
}


class PhoneBase(Base):
    def serve_fake(self, fake):
        patcher = mock.patch.object(tools, 'call', fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    def attempt(self, case, phone, fake=None):
        self.serve_fake(fake or _neutral())
        return area1.attempt_phone(self.run, case, phone)


class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_first_16_and_every_case_is_a_phone_case(self):
        self.assertEqual(area1.BUNDLES['area2-phone-a'], FIRST)
        self.assertEqual(set(area2_phone.PHONE), set(FIRST))
        self.assertLessEqual(set(FIRST), set(area1.PHONE))

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area2_phone 을 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area2-phone-a"), "E-HOME-01" in area1.PHONE)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{FIRST} True')


class AppAnswerTest(PhoneBase):
    """모든 가설 — 앱의 pass 는 pass, fail 은 메모를 남긴 fail, blocked 는 blocked, 말이 없으면 fail."""

    def test_app_pass_is_pass(self):
        for case in FIRST:
            with self.subTest(case):
                said = {'result': 'pass', **APP_SAYS.get(case, {})}
                self.assertEqual(self.attempt(case, FakePhone(said))[0], 'pass')

    def test_app_fail_is_fail_and_keeps_the_note(self):
        for case in FIRST:
            with self.subTest(case):
                result, note = self.attempt(case, FakePhone({'result': 'fail', 'note': '글자 없음'}))
                self.assertEqual(result, 'fail')
                self.assertIn('글자 없음', note)

    def test_app_blocked_is_blocked(self):
        for case in FIRST:
            with self.subTest(case):
                self.assertEqual(self.attempt(case, FakePhone({'result': 'blocked', 'note': '대기 화면'}))[0], 'blocked')

    def test_app_silence_is_fail(self):
        for case in FIRST:
            with self.subTest(case):
                self.assertEqual(self.attempt(case, FakePhone(None))[0], 'fail')

    def test_first_job_signs_the_app_in_with_a_one_time_token(self):
        for case in FIRST:
            with self.subTest(case):
                phone = FakePhone({'result': 'pass', **APP_SAYS.get(case, {})})
                self.attempt(case, phone)
                self.assertEqual(phone.jobs[0]['token_hash'], 'h')


class HomeOpenTest(PhoneBase):
    def test_home_01_school_not_open_is_blocked_before_any_account(self):
        fake = _neutral(school=('GET', 'universities?id=eq', lambda b, u: Reply(200, [{'card_opens_at': '2026-10-05T07:00:00+09:00'}])))
        phone = FakePhone()
        result, note = self.attempt('E-HOME-01', phone, fake)
        self.assertEqual(result, 'blocked')
        self.assertIn('card_opens_at', note)
        self.assertEqual(phone.jobs, [])
        self.assertNotIn('/auth/v1/admin/users', fake.paths('POST'))  # 운영 값도 계정도 건드리지 않는다
        self.assertEqual(fake.paths('PATCH'), [])

    def test_home_01_open_school_runs_the_app(self):
        phone = FakePhone()
        self.assertEqual(self.attempt('E-HOME-01', phone), ('pass', ''))
        self.assertEqual(phone.jobs, [{'token_hash': 'h'}])


class HomeStatsTest(PhoneBase):
    def stats(self, cards, active, talks, summary=None):
        return _neutral(cards=('GET', 'daily_cards?', _counted(cards)), active=('GET', 'profiles?select=id&status', _counted(active)),
                        talks=('GET', 'messages.kind=eq.text', _counted(talks)),
                        summary=('GET', '/home/summary', summary or _summary(cards, active, talks)))

    def test_home_02_screen_numbers_match_db_with_thousands_commas(self):
        said = {'result': 'pass', 'stats': {'전달된 카드': '1,234', '가입 수': '56', '시작된 대화': '7'}}
        self.assertEqual(self.attempt('E-HOME-02', FakePhone(said), self.stats(1234, 56, 7))[0], 'pass')

    def test_home_02_a_different_number_fails(self):
        said = {'result': 'pass', 'stats': {'전달된 카드': '1234', '가입 수': '56', '시작된 대화': '7'}}
        result, note = self.attempt('E-HOME-02', FakePhone(said), self.stats(1234, 56, 7))
        self.assertEqual(result, 'fail')
        self.assertIn('전달된 카드', note)

    def test_home_02_all_zero_wants_the_empty_panel(self):
        self.assertEqual(self.attempt('E-HOME-02', FakePhone({'result': 'pass', 'empty': True}), self.stats(0, 0, 0))[0], 'pass')
        said = {'result': 'pass', 'stats': {'전달된 카드': '0', '가입 수': '0', '시작된 대화': '0'}}
        self.assertEqual(self.attempt('E-HOME-02', FakePhone(said), self.stats(0, 0, 0))[0], 'fail')

    def test_home_02_summary_response_must_match_db_too(self):
        said = {'result': 'pass', 'stats': {'전달된 카드': '3', '가입 수': '2', '시작된 대화': '1'}}
        result, note = self.attempt('E-HOME-02', FakePhone(said), self.stats(3, 2, 1, summary=_summary(3, 9, 1)))
        self.assertEqual(result, 'fail')
        self.assertIn('/home/summary', note)

    def test_home_02_counts_the_three_tables_the_way_the_hypothesis_says(self):
        urls = []
        fake = self.stats(0, 0, 0)
        fake.rules = [(m, piece, lambda b, u, answer=answer: (urls.append(u), answer(b, u))[1]) for m, piece, answer in fake.rules]
        self.attempt('E-HOME-02', FakePhone({'result': 'pass', 'empty': True}), fake)
        self.assertTrue(any('/rest/v1/daily_cards?' in u for u in urls))
        self.assertTrue(any('/rest/v1/profiles?select=id&status=eq.active' in u for u in urls))
        self.assertTrue(any('/rest/v1/matches?' in u and 'messages!inner' in u and 'messages.kind=eq.text' in u for u in urls))

    def test_home_02_missing_count_header_is_blocked(self):
        fake = _neutral(cards=('GET', 'daily_cards?', lambda b, u: Reply(200, [])))
        self.assertEqual(self.attempt('E-HOME-02', FakePhone({'result': 'pass', 'empty': True}), fake)[0], 'blocked')

    def test_home_03_campus_chips_follow_the_db_order_and_include_the_test_school(self):
        self.assertEqual(self.attempt('E-HOME-03', FakePhone({'result': 'pass', 'campuses': ['가대학', '테스트대학']}))[0], 'pass')
        result, note = self.attempt('E-HOME-03', FakePhone({'result': 'pass', 'campuses': ['테스트대학', '가대학']}))
        self.assertEqual(result, 'fail')

    def test_home_03_test_school_missing_from_db_list_fails(self):
        fake = _neutral(campuses=('GET', 'universities?select=name', lambda b, u: Reply(200, [{'name': '가대학'}])))
        result, note = self.attempt('E-HOME-03', FakePhone({'result': 'pass', 'campuses': ['가대학']}), fake)
        self.assertEqual(result, 'fail')
        self.assertIn('테스트대학', note)


class CompletionTest(PhoneBase):
    def test_home_04_starts_at_60_from_the_home_account(self):
        phone = FakePhone()
        self.assertEqual(self.attempt('E-HOME-04', phone)[0], 'pass')
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'percent': 60}])

    def test_home_04_account_not_at_the_start_values_is_blocked(self):
        fake = _neutral(materials=('GET', 'select=mbti', lambda b, u: Reply(200, [{
            'mbti': 'ENFP', 'preferred_height_min': None, 'preferred_height_max': None,
            'interest_tags': ['카페가기', '자전거', '패션'], 'profile_photos': [{'count': 2}]}])))
        phone = FakePhone()
        self.assertEqual(self.attempt('E-HOME-04', phone, fake)[0], 'blocked')
        self.assertEqual(phone.jobs, [])

    def test_home_05_fills_one_thing_before_each_restart(self):
        fake = _neutral()
        seen = []

        class Watch(FakePhone):
            def __call__(self, midway=None, **job):
                photos = [r for m, u, r in fake.raws if u.endswith('/profile-onboarding/photos')]
                patches = [b for m, p, b in fake.calls if m == 'PATCH' and p == '/rest/v1/profiles' and 'student_verification' not in b]
                seen.append((len(photos), [sorted(b) for b in patches]))
                return super().__call__(midway, **job)

        phone = Watch()
        self.assertEqual(self.attempt('E-HOME-05', phone, fake)[0], 'pass')
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'percent': 70}, {'fresh': False, 'percent': 80},
                                      {'fresh': False, 'percent': 90}])
        # 계정 공장이 사진 2장을 올린 뒤 → 셋째 장(70) → MBTI(80) → 선호 키(90)
        self.assertEqual(seen, [(3, []), (3, [['mbti']]), (3, [['mbti'], ['preferred_height_max', 'preferred_height_min']])])
        third = [r for m, u, r in fake.raws if u.endswith('/profile-onboarding/photos')][2]
        self.assertIn(b'name="position"\r\n\r\n2', third)

    def test_home_05_the_third_photo_upload_keeps_the_default_retry(self):
        # 같은 자리(position)에 다시 올리면 서버가 먼저 있던 행을 바꾼다 — 두 번 가도 결과가 같아 retry=False 를 붙이지 않는다.
        fake = _neutral()
        self.assertEqual(self.attempt('E-HOME-05', FakePhone(), fake)[0], 'pass')
        sent = [o for m, p, o in fake.options if p == '/profile-onboarding/photos']
        self.assertEqual(sent, [{}, {}, {}])

    def test_home_06_fills_all_four_then_wants_the_card_gone(self):
        fake = _neutral()
        phone = FakePhone()
        self.assertEqual(self.attempt('E-HOME-06', phone, fake)[0], 'pass')
        self.assertEqual(phone.jobs, [{'token_hash': 'h', 'percent': 100}])
        patched = {}
        for m, p, b in fake.calls:
            if m == 'PATCH' and p == '/rest/v1/profiles':
                patched.update(b)
        self.assertEqual(len(patched['interest_tags']), 5)
        self.assertEqual(patched['mbti'], 'ENFP')
        self.assertIsNotNone(patched['preferred_height_min'])

    def test_home_05_a_failed_fill_is_blocked(self):
        fake = _neutral()
        answers = [Reply(200, {'ok': True}), Reply(200, {'ok': True}), Reply(422, {'detail': '사진'})]  # 공장 2장은 되고 셋째 장만 막힘
        fake.rules.insert(0, ('POST', '/profile-onboarding/photos', lambda b, u: answers.pop(0)))
        phone = FakePhone()
        self.assertEqual(self.attempt('E-HOME-05', phone, fake)[0], 'blocked')
        self.assertEqual(phone.jobs, [])


class HomeMockValuesTest(PhoneBase):
    def test_home_12_visible_mock_review_is_pass_with_the_known_note(self):
        said = {'result': 'pass', 'rail': ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png']}
        self.assertEqual(self.attempt('E-HOME-12', FakePhone(said)), ('pass', '목값이 운영에 나가 있음(known A2)'))

    def test_home_12_rail_from_the_network_fails(self):
        said = {'result': 'pass', 'rail': ['https://cdn.test/a.png']}
        self.assertEqual(self.attempt('E-HOME-12', FakePhone(said))[0], 'fail')


class NotificationDefaultsTest(PhoneBase):
    def test_card_21_account_with_a_settings_row_is_blocked(self):
        fake = _neutral(settings=('GET', 'notification_settings?', lambda b, u: Reply(200, [{'profile_id': 'id-1'}])))
        phone = FakePhone()
        self.assertEqual(self.attempt('E-CARD-21', phone, fake)[0], 'blocked')
        self.assertEqual(phone.jobs, [])

    def test_card_21_new_account_runs_the_app(self):
        phone = FakePhone()
        self.assertEqual(self.attempt('E-CARD-21', phone), ('pass', ''))
        self.assertEqual(phone.jobs, [{'token_hash': 'h'}])


class ReferralSheetTest(PhoneBase):
    def test_ref_01_sheet_code_is_the_db_code(self):
        self.assertEqual(self.attempt('E-REF-01', FakePhone({'result': 'pass', 'code': CODE}))[0], 'pass')
        result, note = self.attempt('E-REF-01', FakePhone({'result': 'pass', 'code': 'ZZZZZ2'}))
        self.assertEqual(result, 'fail')

    def test_ref_01_db_code_with_confusable_characters_fails(self):
        for bad in ('ABCD10', 'ABCDEO', 'abcde2', 'ABCDE'):
            with self.subTest(bad):
                fake = _neutral(code=('GET', 'select=referral_code', lambda b, u, bad=bad: Reply(200, [{'referral_code': bad}])))
                self.assertEqual(self.attempt('E-REF-01', FakePhone({'result': 'pass', 'code': bad}), fake)[0], 'fail')

    def test_ref_02_three_opens_across_a_restart_show_one_code(self):
        phone = FakePhone({'result': 'pass', 'codes': [CODE, CODE]}, {'result': 'pass', 'codes': [CODE, CODE]})
        self.assertEqual(self.attempt('E-REF-02', phone)[0], 'pass')
        self.assertEqual(phone.jobs, [{'token_hash': 'h'}, {'fresh': False}])

    def test_ref_02_a_changed_code_fails(self):
        phone = FakePhone({'result': 'pass', 'codes': [CODE, CODE]}, {'result': 'pass', 'codes': ['ZZZZZ2', 'ZZZZZ2']})
        self.assertEqual(self.attempt('E-REF-02', phone)[0], 'fail')

    def test_ref_02_too_few_opens_fails(self):
        phone = FakePhone({'result': 'pass', 'codes': [CODE]}, {'result': 'pass', 'codes': []})
        self.assertEqual(self.attempt('E-REF-02', phone)[0], 'fail')

    def test_ref_03_clipboard_must_be_the_code(self):
        self.assertEqual(self.attempt('E-REF-03', FakePhone({'result': 'pass', 'code': CODE, 'clipboard': CODE}))[0], 'pass')
        said = {'result': 'pass', 'code': CODE, 'clipboard': f'{CODE} '}
        self.assertEqual(self.attempt('E-REF-03', FakePhone(said))[0], 'fail')


if __name__ == '__main__':
    unittest.main()
