"""영역 1 묶음 2(홈 계정 공장 · 탈퇴 · 정리 배치 · 온보딩 뒷단 · 추천 코드) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b2`."""

import json
import time
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from e2e import area1, area1_b2, tools
from e2e.test_area1 import Base
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Reply

ACCOUNT_DONE = ['/me/consents', '/school-info', '/profile-onboarding/basic-info', '/profile-onboarding/kakao-id',
                '/profile-onboarding/photos', '/profile-onboarding/photos', '/profile-onboarding/appearance-type',
                '/profile-onboarding/interests', '/profile-onboarding/my-traits', '/profile-onboarding/survey',
                '/profile-onboarding/ideal-conditions', '/profile-onboarding/ideal-traits',
                '/profile-onboarding/ideal-note', '/profile-onboarding/bio']


def _iso(moment):
    return moment.isoformat()


class HomeFactoryTest(Base):
    def test_home_account_walks_every_onboarding_step_in_server_order(self):
        fake = self.serve()
        account = self.run.account('home')
        self.assertEqual(account['stage'], 'home')
        api = [p for p in fake.paths('POST') if not p.startswith(('/auth/', '/rest/', '/storage/'))]
        self.assertEqual(api, ACCOUNT_DONE)
        # 아바타는 AI 대신 DB 완성 행 — 그림은 avatars 버킷 `{id}/` 아래(뒷정리가 지운다)
        self.assertTrue(any(p.startswith('/storage/v1/object/avatars/id-1/') for p in fake.paths('POST')))
        rows = [b for m, p, b in fake.calls if m == 'POST' and p == '/rest/v1/profile_avatars']
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['status'], 'ready')
        self.assertTrue(rows[0]['storage_path'].startswith('id-1/'))

    def test_photos_send_two_real_images_and_mark_the_first_as_avatar_source(self):
        fake = self.serve()
        self.run.account('photos')
        raws = [r for m, u, r in fake.raws if u.endswith('/profile-onboarding/photos')]
        self.assertEqual(len(raws), 2)
        self.assertIn(b'\x89PNG', raws[0])
        self.assertIn(b'name="is_avatar_source"\r\n\r\ntrue', raws[0])
        self.assertIn(b'name="is_avatar_source"\r\n\r\nfalse', raws[1])

    def test_each_stage_stops_where_it_should(self):
        fake = self.serve()
        self.run.account('survey')
        api = [p for p in fake.paths('POST') if not p.startswith(('/auth/', '/rest/', '/storage/'))]
        self.assertEqual(api, ACCOUNT_DONE[:ACCOUNT_DONE.index('/profile-onboarding/survey') + 1])

    def test_old_consent_account_inserts_old_rows_instead_of_agreeing(self):
        fake = self.serve()
        self.run.account('home', old_consent=True)
        self.assertNotIn('/me/consents', fake.paths('POST'))
        rows = [b for m, p, b in fake.calls if m == 'POST' and p == '/rest/v1/user_consents'][0]
        self.assertEqual(sorted((r['kind'], r['version']) for r in rows), [('privacy', '2026-09-01'), ('terms', '2026-09-01')])

    def test_basic_info_can_be_pinned(self):
        fake = self.serve()
        self.run.account('basic', phone_number='010-1111-2222')
        sent = [b for m, p, b in fake.calls if p == '/profile-onboarding/basic-info'][0]
        self.assertEqual(sent['phone_number'], '010-1111-2222')

    def test_screen_names_follow_the_server_steps(self):
        self.assertEqual(area1_b2.SCREEN_AFTER['basic'], '04-1b')
        self.assertEqual(area1_b2.SCREEN_AFTER['my_traits'], '05-01')
        self.assertEqual(area1_b2.SCREEN_AFTER['home'], 'home')
        self.assertEqual(list(area1_b2.SCREEN_AFTER), list(tools.STAGES[tools.STAGES.index('gate_done'):]))


class BatchTest(unittest.TestCase):
    def test_batch_runs_the_scheduler_job_in_seoul(self):
        with mock.patch.object(tools.subprocess, 'run') as run:
            tools.batch('cleanup')
        args = run.call_args.args[0]
        self.assertEqual(args, ['gcloud', 'scheduler', 'jobs', 'run', 'campus-mate-cleanup', '--location=asia-northeast3'])


class MidwayTest(Base):
    def test_app_step_lets_the_pc_act_then_go(self):
        hub = tools.Hub(0)
        self.addCleanup(hub.close)
        acted = []

        def app():  # 앱 대신 — 일감을 받아 중간에 멈췄다가 go 를 받고 결과를 말한다
            import urllib.request
            base = f'http://127.0.0.1:{hub.port}'
            urllib.request.urlopen(f'{base}/hear', timeout=5).read()
            post = lambda m: urllib.request.urlopen(urllib.request.Request(f'{base}/say', data=json.dumps(m).encode(), method='POST'), timeout=5)
            post({'case': 'X', 'step': 'home'})
            go = json.load(urllib.request.urlopen(f'{base}/hear', timeout=5))
            post({'case': 'X', 'result': 'pass', 'go': go, 'acted_before_go': list(acted)})

        with mock.patch.object(tools, 'adb', return_value=''):
            import threading
            threading.Thread(target=app, daemon=True).start()
            said = self.run.phone(hub, 'S', {'case': 'X'}, timeout=5, midway=lambda step: (time.sleep(0.3), acted.append(step['step'])))
        self.assertEqual(acted, ['home'])
        self.assertEqual(said['result'], 'pass')
        self.assertEqual(said['go'], {'go': True})
        self.assertEqual(said['acted_before_go'], ['home'])  # PC 가 하기 전에 앱이 이어 가면 안 된다


class MidwayExtraTest(Base):
    """midway 가 돌려준 dict 는 앱을 다시 보내는 go 에 실린다(E-SAFE-57 — 두 번째 로그인 토큰). 그 밖의 값은 지금과 똑같이 {'go': True}."""

    def go_the_app_heard(self, midway):
        hub = tools.Hub(0)
        self.addCleanup(hub.close)
        got = {}

        def app():
            import urllib.request
            base = f'http://127.0.0.1:{hub.port}'
            urllib.request.urlopen(f'{base}/hear', timeout=5).read()
            post = lambda m: urllib.request.urlopen(urllib.request.Request(f'{base}/say', data=json.dumps(m).encode(), method='POST'), timeout=5)
            post({'case': 'X', 'step': 'home'})
            got['go'] = json.load(urllib.request.urlopen(f'{base}/hear', timeout=5))
            post({'case': 'X', 'result': 'pass'})

        with mock.patch.object(tools, 'adb', return_value=''):
            import threading
            threading.Thread(target=app, daemon=True).start()
            self.assertEqual(self.run.phone(hub, 'S', {'case': 'X'}, timeout=5, midway=midway)['result'], 'pass')
        return got['go']

    def test_a_dict_from_midway_rides_on_the_go(self):
        self.assertEqual(self.go_the_app_heard(lambda step: {'token_hash': 'second'}), {'go': True, 'token_hash': 'second'})

    def test_none_or_a_non_dict_is_the_plain_go(self):
        for value in (None, ('a', 'b'), 'x', 0):
            self.assertEqual(self.go_the_app_heard(lambda step, value=value: value), {'go': True}, value)


class WithdrawTest(Base):
    def blocks(self, before, after):
        return {('GET', '/rest/v1/signup_blocks'): [Reply(200, before), Reply(200, after)]}

    def test_auth_07_new_block_is_two_months_after_the_tap(self):
        tapped = datetime(2026, 10, 4, 10, 0, tzinfo=timezone.utc)
        new = {'email_hmac': '\\x02', 'blocked_until': _iso(datetime(2026, 12, 4, 10, 0, 20, tzinfo=timezone.utc))}
        self.serve({**self.blocks([{'email_hmac': '\\x01', 'blocked_until': 'x'}], [{'email_hmac': '\\x01', 'blocked_until': 'x'}, new]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'withdrawn'}])})
        phone = FakePhone({'result': 'pass', 'tapped_at': _iso(tapped)})
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-07', phone), ('pass', ''))

    def test_auth_07_two_new_rows_cannot_be_told_apart_and_fails(self):
        tapped = datetime(2026, 10, 4, 10, 0, tzinfo=timezone.utc)
        right = {'email_hmac': '\x02', 'blocked_until': _iso(datetime(2026, 12, 4, 10, 0, 20, tzinfo=timezone.utc))}
        other = {'email_hmac': '\x03', 'blocked_until': _iso(datetime(2026, 12, 9, tzinfo=timezone.utc))}
        self.serve({**self.blocks([], [right, other]), ('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'withdrawn'}])})
        phone = FakePhone({'result': 'pass', 'tapped_at': _iso(tapped)})
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-07', phone)[0], 'fail')

    def test_two_months_after_clamps_to_month_end_like_postgres(self):
        from e2e.area1_b2 import _two_months_after
        self.assertEqual(_two_months_after(datetime(2026, 12, 30, 9, tzinfo=timezone.utc)), datetime(2027, 2, 28, 9, tzinfo=timezone.utc))
        self.assertEqual(_two_months_after(datetime(2026, 8, 31, tzinfo=timezone.utc)), datetime(2026, 10, 31, tzinfo=timezone.utc))

    def test_auth_07_wrong_length_or_no_new_row_fails(self):
        tapped = datetime(2026, 10, 4, 10, 0, tzinfo=timezone.utc)
        for after in ([], [{'email_hmac': '\\x02', 'blocked_until': _iso(tapped + timedelta(days=30))}]):
            self.serve({**self.blocks([], after), ('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'withdrawn'}])})
            phone = FakePhone({'result': 'pass', 'tapped_at': _iso(tapped)})
            self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-07', phone)[0], 'fail', after)

    def test_auth_08_suspended_withdraw_blocks_forever(self):
        fake = self.serve({**self.blocks([], [{'email_hmac': '\\x02', 'blocked_until': 'infinity'}]),
                           ('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'withdrawn'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-08', FakePhone())[0], 'pass')
        self.assertIn({'status': 'suspended'}, [b for m, p, b in fake.calls if m == 'PATCH'])

    def test_auth_09_withdraws_by_api_then_opens_the_app_with_a_new_login(self):
        fake = self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-AUTH-09', phone)[0], 'pass')
        self.assertIn('/account/withdraw', fake.paths('POST'))
        self.assertIn('token_hash', phone.jobs[0])


class CleanupBatchTest(Base):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(tools, 'batch')
        self.batch = patcher.start()
        self.addCleanup(patcher.stop)
        sleeper = mock.patch.object(area1_b2.time, 'sleep')
        sleeper.start()
        self.addCleanup(sleeper.stop)

    def gone_after_batch(self, extra=None):
        """정리 배치 뒤엔 auth 사용자가 없다."""
        fake = self.serve(extra)
        users = fake.users

        def batch(name):
            users.clear()
        self.batch.side_effect = batch
        return fake

    def test_auth_10_rejoining_after_cleanup_is_refused(self):
        fake = self.gone_after_batch({('POST', '/auth/v1/otp'): Reply(422, {'msg': '재가입이 제한된 이메일이에요'})})
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-10'), ('pass', ''))
        self.batch.assert_called_once_with('cleanup')
        withdrawn_at = [b['withdrawn_at'] for m, p, b in fake.calls if m == 'PATCH' and b and 'withdrawn_at' in b][0]
        self.assertLess(datetime.fromisoformat(withdrawn_at), datetime.now(timezone.utc) - timedelta(days=30))

    def test_auth_10_user_still_there_after_batch_is_blocked(self):
        self.serve()
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-10')[0], 'blocked')

    def test_auth_10_rejoin_accepted_fails(self):
        self.gone_after_batch()
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-10')[0], 'fail')

    def test_auth_11_expired_block_lets_the_same_mail_join_again(self):
        fake = self.gone_after_batch({('GET', '/rest/v1/signup_blocks'): [Reply(200, []), Reply(200, [{'email_hmac': '\\x0a'}])],
                                      ('GET', '/rest/v1/profiles'): Reply(200, [{'id': 'new'}])})
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-11'), ('pass', ''))
        expired = [b for m, p, b in fake.calls if m == 'PATCH' and b and 'blocked_until' in b]
        self.assertEqual(len(expired), 1)
        self.assertLess(datetime.fromisoformat(expired[0]['blocked_until']), datetime.now(timezone.utc))
        self.assertIn(('PATCH', 'https://sb.test/rest/v1/signup_blocks?email_hmac=eq.%5Cx0a'), fake.urls)

    def test_auth_12_expired_row_goes_and_forever_row_stays(self):
        fake = self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'blocked_until': 'infinity'}])})
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-12'), ('pass', ''))
        inserted = [b for m, p, b in fake.calls if m == 'POST' and p == '/rest/v1/signup_blocks'][0]
        self.assertEqual(sorted(r['blocked_until'] == 'infinity' for r in inserted), [False, True])
        self.batch.assert_called_once_with('cleanup')
        self.assertIn('/rest/v1/signup_blocks', fake.paths('DELETE'))  # 남긴 무기한 행은 시험이 지운다

    def test_auth_12_in_filter_has_no_quotes_around_bytea(self):
        # PostgREST 는 따옴표 안의 \ 를 이스케이프로 읽어 \x… 를 x… 로 깨뜨린다
        fake = self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'blocked_until': 'infinity'}])})
        area1.attempt(self.run, 'E-AUTH-12')
        filters = [u for m, u in fake.urls if m in ('GET', 'DELETE') and 'signup_blocks' in u]
        self.assertTrue(filters)
        for url in filters:
            self.assertNotIn('%22', url)

    def test_auth_12_expired_row_left_fails(self):
        self.serve({('GET', '/rest/v1/signup_blocks'): Reply(200, [{'blocked_until': 'infinity'}, {'blocked_until': '2026-01-01T00:00:00+00:00'}])})
        self.assertEqual(area1.attempt(self.run, 'E-AUTH-12')[0], 'fail')


class ConsentRenewalTest(Base):
    NEW = [{'kind': 'terms', 'version': '2026-09-29'}, {'kind': 'privacy', 'version': '2026-09-29'}]
    OLD = [{'kind': 'terms', 'version': '2026-09-01'}, {'kind': 'privacy', 'version': '2026-09-01'}]

    def test_gate_18_new_version_rows_are_added(self):
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, self.OLD + self.NEW)})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-18', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/user_consents'): Reply(200, self.OLD)})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-18', FakePhone())[0], 'fail')

    def test_gate_19_marketing_stays_on(self):
        fake = self.serve({('GET', '/rest/v1/notification_settings'): Reply(200, [{'marketing': True}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-19', FakePhone())[0], 'pass')
        self.assertIn('/rest/v1/notification_settings', fake.paths('POST'))
        self.serve({('GET', '/rest/v1/notification_settings'): Reply(200, [{'marketing': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-19', FakePhone())[0], 'fail')


class SuspendTest(Base):
    def test_gate_04_suspends_while_the_app_waits_on_home(self):
        fake = self.serve()
        phone = FakePhone(midway_step={'step': 'home'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-04', phone)[0], 'pass')
        self.assertEqual(phone.acted, ['home'])
        self.assertIn({'status': 'suspended'}, [b for m, p, b in fake.calls if m == 'PATCH'])

    def test_gate_05_lifts_the_suspension_between_two_runs(self):
        fake = self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-05', phone)[0], 'pass')
        patches = [b for m, p, b in fake.calls if m == 'PATCH' and b and 'status' in b]
        self.assertEqual(patches, [{'status': 'suspended'}, {'status': 'active'}])
        self.assertEqual([j.get('expect') for j in phone.jobs], ['suspended', 'home'])


class OnboardingTest(Base):
    def test_onb_30_nine_answers_on_the_scale_and_religion_smoker_saved(self):
        answers = [{'axis': a, 'value': v} for a, v in zip(range(1, 10), [-1, -0.5, 0, 0.5, 1, 0, 0, 0, 0])]
        self.serve({('GET', '/rest/v1/survey_answers'): Reply(200, answers),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'religion': 'none', 'is_smoker': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-30', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/survey_answers'): Reply(200, answers[:8] + [{'axis': 9, 'value': 0.3}]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'religion': 'none', 'is_smoker': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-30', FakePhone())[0], 'fail')

    def test_onb_33_avatar_row_is_added_while_the_app_waits_on_05_12(self):
        fake = self.serve()
        phone = FakePhone(midway_step={'step': '05-12'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-33', phone)[0], 'pass')
        self.assertEqual(phone.acted, ['05-12'])
        # 행이 없으면 05-12 가 실패 화면이 돼 폴링이 끊긴다 — 켜기 전에 pending 을 넣고 중간에 ready 로 바꾼다
        inserted = [b['status'] for m, p, b in fake.calls if m == 'POST' and p == '/rest/v1/profile_avatars']
        self.assertEqual(inserted, ['pending'])
        self.assertIn({'status': 'ready'}, [b for m, p, b in fake.calls if m == 'PATCH' and p == '/rest/v1/profile_avatars'])

    def test_onb_31_no_answers_saved_after_restart(self):
        self.serve({('GET', '/rest/v1/survey_answers'): Reply(200, [])})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-31', phone)[0], 'pass')
        self.assertEqual([j.get('fresh', True) for j in phone.jobs], [True, False])

    def test_onb_44_any_age_is_19_to_35_and_any_height_is_empty(self):
        good = {'preferred_age_min': 19, 'preferred_age_max': 35, 'preferred_height_min': None, 'preferred_height_max': None}
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [good])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-44', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{**good, 'preferred_height_min': 150}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-44', FakePhone())[0], 'fail')

    def test_onb_46_and_47_note_saved_as_the_app_counted(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'ideal_note': '가나다라마바사아자차'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-46', FakePhone({'result': 'pass', 'saved': '가나다라마바사아자차'}))[0], 'pass')
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'ideal_note': None}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-47', FakePhone({'result': 'pass', 'saved': '😀' * 10}))[0], 'fail')

    def test_onb_48_draft_is_saved_and_onb_50_does_not_regenerate(self):
        draft = {'bio_draft': '안녕하세요', 'bio_draft_generated_at': '2026-10-04T10:00:00+00:00'}
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [draft])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-48', FakePhone({'result': 'pass', 'draft': '안녕하세요'}))[0], 'pass')
        phone = FakePhone({'result': 'pass', 'draft': '안녕하세요'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-50', phone)[0], 'pass')
        self.assertEqual(phone.jobs[1]['draft'], '안녕하세요')
        self.assertEqual(phone.jobs[1]['fresh'], False)
        self.serve({('GET', '/rest/v1/profiles'): [Reply(200, [draft]), Reply(200, [{**draft, 'bio_draft_generated_at': '2026-10-04T10:05:00+00:00'}])]})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-50', FakePhone({'result': 'pass', 'draft': '안녕하세요'}))[0], 'fail')

    def test_onb_52_bio_saved_makes_the_profile_active(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'active'}]),
                    ('GET', '/profile-onboarding/next-step'): Reply(200, {'step': 'complete'})})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-52', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'status': 'pending'}]),
                    ('GET', '/profile-onboarding/next-step'): Reply(200, {'step': 'bio'})})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-52', FakePhone())[0], 'fail')

    def test_onb_53_one_restart_per_step_plus_complete(self):
        self.serve()
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-53', phone)[0], 'pass')
        self.assertEqual([j['expect'] for j in phone.jobs],
                         ['04-1', '04-1b', '04-2', '04-4', '04-5', '04-6', '05-01', '05-12', '06-1', '06-2', '06-2a', '06-3', 'home'])

    def test_onb_55_no_photo_rows_after_restart(self):
        self.serve({('GET', '/rest/v1/profile_photos'): Reply(200, [{'id': 'p'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-55', FakePhone())[0], 'fail')


class ReferralTest(Base):
    def hearts(self, rows):
        return {('GET', '/rest/v1/heart_transactions'): Reply(200, rows)}

    def test_onb_60_one_referral_row_and_fifty_hearts_each(self):
        fake = self.serve({('GET', '/rest/v1/referrals'): Reply(200, [{'referrer_id': 'id-1'}]),
                           **self.hearts([{'amount': 50}]),  # 가짜는 사람을 안 가른다 — 나 · 추천인 각각 50 한 줄
                           ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-60', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['code'], 'K7M2QX')
        self.assertTrue(any('reason=eq.referral' in u for m, u in fake.urls))

    def test_onb_60_missing_hearts_fail(self):
        self.serve({('GET', '/rest/v1/referrals'): Reply(200, [{'referrer_id': 'id-1'}]), **self.hearts([]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-60', FakePhone())[0], 'fail')

    def test_onb_62_code_is_given_lowercase_with_spaces(self):
        self.serve({('GET', '/rest/v1/referrals'): Reply(200, [{'referrer_id': 'id-1'}]),
                    **self.hearts([{'amount': 50}]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        phone = FakePhone()
        area1.attempt_phone(self.run, 'E-ONB-62', phone)
        self.assertEqual(phone.jobs[0]['code'], ' k7m2qx ')

    def test_onb_64_unknown_code_gives_no_hearts(self):
        self.serve(self.hearts([{'amount': 50}]))
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-64', FakePhone())[0], 'fail')

    def test_onb_66_suspended_and_withdrawn_referrers(self):
        fake = self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}])})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-66', phone)[0], 'pass')
        self.assertIn({'status': 'suspended'}, [b for m, p, b in fake.calls if m == 'PATCH'])
        self.assertIn('/account/withdraw', fake.paths('POST'))
        self.assertEqual(len(phone.jobs[0]['codes']), 2)

    def test_onb_67_same_phone_is_refused_twice(self):
        refused = Reply(422, {'detail': '이 코드는 쓸 수 없어요'})
        fake = self.serve({('POST', '/referral/redeem'): [refused, Reply(200, {'ok': True}), refused],
                           ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}]),
                           ('GET', '/rest/v1/referrals'): [Reply(200, [{'referee_id': 'c'}]), Reply(200, [])]})
        self.assertEqual(area1.attempt(self.run, 'E-ONB-67'), ('pass', ''))
        phones = [b['phone_number'] for m, p, b in fake.calls if p == '/profile-onboarding/basic-info']
        self.assertEqual(len(phones) - len(set(phones)), 2)  # A=B 한 쌍, A2=C 한 쌍

    def test_onb_68_second_code_is_409_and_no_more_hearts(self):
        self.serve({('POST', '/referral/redeem'): [Reply(200, {'ok': True}), Reply(409, {'detail': '추천 코드는 한 번만 입력할 수 있어요'})],
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX'}]),
                    **self.hearts([{'amount': 50}])})
        self.assertEqual(area1.attempt(self.run, 'E-ONB-68'), ('pass', ''))

    def test_onb_70_skipping_everything_leaves_no_trace(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'acquisition_channel': None}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-70', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/contact_blocks'): Reply(200, [{'id': 'x'}]),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'acquisition_channel': None}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-70', FakePhone())[0], 'fail')

    def test_onb_72_other_note_is_cut_at_30(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'acquisition_channel': 'other', 'acquisition_note': '가' * 30}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-72', FakePhone())[0], 'pass')
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'acquisition_channel': 'other', 'acquisition_note': '가' * 31}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-72', FakePhone())[0], 'fail')

    def test_onb_73_everytime_without_note(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'acquisition_channel': 'everytime', 'acquisition_note': None}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-73', FakePhone())[0], 'pass')


class NotificationTest(Base):
    def test_onb_61_referrer_gets_the_join_notification(self):
        dump = 'NotificationRecord(pkg=io.github.juunn.campusmate ...)\n  android.title=String (친구가 가입했어요)\n  android.text=String (Abcde 님이 가입했어요, 리뷰를 남겨 주세요)'
        fake = self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX', 'nickname': 'Abcde'}])})
        with mock.patch.object(tools, 'adb', return_value=dump), mock.patch.object(area1_b2.time, 'sleep'):
            phone = FakePhone()
            phone.serial = 'S'
            self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-61', phone)[0], 'pass')
        self.assertIn('/referral/redeem', fake.paths('POST'))

    def test_onb_61_no_notification_fails(self):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX', 'nickname': 'Abcde'}])})
        with mock.patch.object(tools, 'adb', return_value=''), mock.patch.object(area1_b2.time, 'sleep'):
            phone = FakePhone()
            phone.serial = 'S'
            self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-61', phone)[0], 'fail')


class BundleTest(unittest.TestCase):
    def test_bundle_two_lists_every_hypothesis_but_the_manual_and_already_done(self):
        b2 = area1.BUNDLES['area1-b2']
        self.assertEqual(len(b2), len(set(b2)))
        for case in b2:
            self.assertTrue(case in area1.PHONE or case in area1.CASES, case)
        for left_out in ('E-AUTH-15', 'E-ONB-32', 'E-ONB-45', 'E-ONB-69'):
            self.assertNotIn(left_out, b2)
            self.assertIn(left_out, area1_b2.LEFT_OUT)


if __name__ == '__main__':
    unittest.main()
