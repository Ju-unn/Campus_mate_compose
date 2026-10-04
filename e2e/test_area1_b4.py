"""영역 1 묶음 4(아바타) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b4`."""

import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area1_b4
from e2e.test_area1_b3 import PhotoBase
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Reply

CASES = ['E-ONB-40']
PHONE = ['E-ONB-24', 'E-ONB-25', 'E-ONB-34', 'E-ONB-35', 'E-ONB-36', 'E-ONB-37', 'E-ONB-38', 'E-ONB-39', 'E-ONB-41']
AVATARS = ('GET', '/rest/v1/profile_avatars')
HEARTS = ('GET', '/rest/v1/heart_transactions')
PHOTOS = ('GET', '/rest/v1/profile_photos')
SOURCE = Reply(200, [{'storage_path': 'id-1/src.jpg'}])
DEFAULTS = ('POST', '/storage/v1/object/list/avatars')
HAS_FALLBACK_SOURCE = Reply(200, [{'name': 'fallback-avatar.png', 'id': 'o1'}])


def failed(count):
    return [{'status': 'failed', 'is_fallback': False}] * count


FALLBACK = {'status': 'ready', 'is_fallback': True}
PENDING = {'status': 'pending', 'is_fallback': False}


class BundleTest(unittest.TestCase):
    def test_bundle_is_the_api_case_then_the_phone_cases(self):
        self.assertEqual(area1.BUNDLES['area1-b4'], CASES + PHONE)
        self.assertLessEqual(set(CASES), set(area1.CASES))
        self.assertLessEqual(set(PHONE), set(area1.PHONE))

    def test_cases_in_other_bundles_are_not_repeated_and_the_reason_is_written(self):
        self.assertNotIn('E-ONB-33', area1.BUNDLES['area1-b4'])
        self.assertIn('E-ONB-33', area1_b4.LEFT_OUT)
        self.assertIn('E-ONB-42', area1_b4.LEFT_OUT)

    def test_fnv_matches_the_published_vectors_the_app_uses(self):
        self.assertEqual(area1_b4._fnv(b'a'), 'e40c292c')
        self.assertEqual(area1_b4._fnv(b'foobar'), 'bf9cf968')
        self.assertEqual(area1_b4._fnv(b''), '811c9dc5')


class Base4(PhotoBase):
    def phone(self, *answers, **kw):
        phone = FakePhone(*answers, **kw)
        phone.serial = 'S1'
        return phone

    def writes(self, fake, method, table):
        return [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == method and f'/{table}' in urlsplit(u).path]

    def seeded(self, fake):
        return [b for _, b in self.writes(fake, 'POST', 'rest/v1/profile_avatars')]


class RegisterTest(Base4):
    """E-ONB-24 · 41 — 실제 생성이 한 번씩 나가는 두 가설."""

    ONE_SOURCE = Reply(200, [{'position': 0, 'is_avatar_source': True}, {'position': 1, 'is_avatar_source': False}])

    def test_onb_24_passes_with_two_photos_one_source_and_one_job_row(self):
        self.put('face1.jpg', 'face2.jpg')
        self.serve({PHOTOS: self.ONE_SOURCE, AVATARS: Reply(200, [PENDING])})
        phone = self.phone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-24', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['photos'], ['face1.jpg', 'face2.jpg'])

    def test_onb_24_fails_without_a_job_row_or_with_two_sources(self):
        self.put('face1.jpg', 'face2.jpg')
        two = Reply(200, [{'position': 0, 'is_avatar_source': True}, {'position': 1, 'is_avatar_source': True}])
        self.serve({PHOTOS: two, AVATARS: Reply(200, [])})
        result, note = area1.attempt_phone(self.run, 'E-ONB-24', self.phone())
        self.assertEqual(result, 'fail')
        self.assertIn('원본', note)
        self.assertIn('아바타', note)

    def test_onb_24_fails_when_two_job_rows_exist(self):
        self.put('face1.jpg', 'face2.jpg')
        self.serve({PHOTOS: self.ONE_SOURCE, AVATARS: Reply(200, [PENDING, PENDING])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-24', self.phone())[0], 'fail')

    def test_onb_24_without_the_photo_set_blocks_before_making_an_account(self):
        fake = self.serve()
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-24', self.phone())[0], 'blocked')
        self.assertNotIn('/auth/v1/admin/users', fake.paths('POST'))

    def run41(self, avatar_replies):
        self.put('face1.jpg', 'face2.jpg')
        fake = self.serve({AVATARS: avatar_replies})
        phone = self.phone(APP_PASS)
        with mock.patch.object(area1_b4.time, 'sleep') as nap:
            result = area1.attempt_phone(self.run, 'E-ONB-41', phone)
        return result, fake, phone, nap

    def test_onb_41_finishes_the_survey_by_api_waits_for_ready_then_relaunches_the_app(self):
        pending, ready = Reply(200, [PENDING]), Reply(200, [{'status': 'ready', 'is_fallback': False}])
        result, fake, phone, nap = self.run41([pending, pending, ready])
        self.assertEqual(result[0], 'pass', result)
        for path in ('/profile-onboarding/appearance-type', '/profile-onboarding/interests', '/profile-onboarding/my-traits',
                     '/profile-onboarding/survey'):
            self.assertIn(path, fake.paths('POST'))
        self.assertEqual(len(phone.jobs), 2)
        self.assertIs(phone.jobs[1].get('fresh'), False)  # 다시 켠다 — 로그인은 앱에 남아 있다
        self.assertEqual(phone.jobs[1].get('expect'), '06-1')  # 완성 행이 있으면 서버 다음 단계가 이상형(06-1)이라 05-12 는 건너뛴다
        self.assertGreaterEqual(nap.call_count, 1)

    def test_onb_41_fails_when_the_job_ends_failed_and_does_not_relaunch_the_app(self):
        result, _, phone, _ = self.run41([Reply(200, [PENDING]), Reply(200, [{'status': 'failed'}])])
        self.assertEqual(result[0], 'fail')
        self.assertIn('failed', result[1])
        self.assertEqual(len(phone.jobs), 1)

    def test_onb_41_fails_when_ready_row_count_is_not_one_after_relaunch(self):
        ready = Reply(200, [{'status': 'ready', 'is_fallback': False}])
        result, *_ = self.run41([Reply(200, [PENDING]), ready, Reply(200, [{'status': 'ready'}, PENDING])])
        self.assertEqual(result[0], 'fail')

    def test_onb_41_fails_on_zero_or_two_ready_rows_after_relaunch(self):
        ready = Reply(200, [{'status': 'ready', 'is_fallback': False}])
        for after in ([], [{'status': 'ready'}, {'status': 'ready'}]):
            result, *_ = self.run41([Reply(200, [PENDING]), ready, Reply(200, after)])
            self.assertEqual(result[0], 'fail', after)

    def test_onb_41_fails_when_ready_never_arrives(self):
        result, _, _, nap = self.run41(Reply(200, [PENDING]))
        self.assertEqual(result[0], 'fail')
        self.assertGreaterEqual(nap.call_count, 20)  # 오래 기다렸다 — 무한히는 아니다
        self.assertLessEqual(nap.call_count, 40)


class OrderTest(Base4):
    DRAGGED = {'before': ['a1', 'b2', 'c3'], 'hashes': ['c3', 'b2', 'a1']}

    def run25(self, said, stored, avatars=()):
        self.put('face1.jpg', 'face2.jpg', 'face3.jpg')
        rows = [{'position': i, 'storage_path': f'id-1/{i}.jpg'} for i in range(len(stored))]
        self.serve({PHOTOS: Reply(200, rows), AVATARS: Reply(200, list(avatars))})
        phone = self.phone({'result': 'pass', **said})
        with mock.patch.object(area1_b4, '_download', side_effect=lambda run, bucket, path: stored[int(path.split('/')[1][0])]), \
                mock.patch.object(area1_b4, '_fnv', side_effect=lambda data: data):
            return area1.attempt_phone(self.run, 'E-ONB-25', phone), phone

    def test_onb_25_passes_when_stored_order_equals_the_dragged_order(self):
        result, phone = self.run25(self.DRAGGED, ['c3', 'b2', 'a1'])
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(phone.jobs[0]['photos'], ['face1.jpg', 'face2.jpg', 'face3.jpg'])

    def test_onb_25_fails_when_the_server_kept_the_old_order(self):
        self.assertEqual(self.run25(self.DRAGGED, ['a1', 'b2', 'c3'])[0][0], 'fail')

    def test_onb_25_fails_when_the_drag_did_not_move_the_third_photo_first(self):
        result, note = self.run25({'before': ['a1', 'b2', 'c3'], 'hashes': ['a1', 'b2', 'c3']}, ['a1', 'b2', 'c3'])[0]
        self.assertEqual(result, 'fail')
        self.assertIn('끌', note)

    def test_onb_25_fails_when_an_avatar_job_was_registered_anyway(self):
        result, note = self.run25(self.DRAGGED, ['c3', 'b2', 'a1'], avatars=[PENDING])[0]
        self.assertEqual(result, 'fail')
        self.assertIn('유료', note)

    def test_onb_25_fails_with_fewer_than_three_rows(self):
        self.assertEqual(self.run25(self.DRAGGED, ['c3', 'b2'])[0][0], 'fail')


class ResultScreenTest(Base4):
    """05-12 에서 시작하는 가설 — 계정은 설문까지, 아바타 기록은 가설마다 DB 로 만든다."""

    def serve(self, routes=None):
        # 운영 avatars 버킷에 기본 아바타 원본(defaults/fallback-avatar.png)이 있는 보통의 경우.
        return super().serve({DEFAULTS: HAS_FALLBACK_SOURCE, **(routes or {})})

    def test_onb_34_waits_with_a_pending_row_then_marks_only_this_accounts_row_ready(self):
        fake = self.serve()
        phone = self.phone(midway_step={'step': 'ready'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-34', phone)[0], 'pass')
        self.assertEqual(self.seeded(fake)[0]['status'], 'pending')
        (url, body), = self.writes(fake, 'PATCH', 'rest/v1/profile_avatars')
        self.assertEqual(body, {'status': 'ready'})
        self.assertIn('profile_id=eq.id-1', url)
        self.assertEqual(phone.acted, ['ready'])

    def test_onb_35_moves_the_pending_row_11_minutes_back_for_this_account_only(self):
        fake = self.serve({AVATARS: Reply(200, [PENDING])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-35', self.phone())[0], 'pass')
        (url, body), = self.writes(fake, 'PATCH', 'rest/v1/profile_avatars')
        self.assertIn('profile_id=eq.id-1', url)
        self.assertIn('status=eq.pending', url)
        age = datetime.now(timezone.utc) - datetime.fromisoformat(body['created_at'])
        self.assertTrue(timedelta(minutes=10, seconds=30) < age < timedelta(minutes=12), age)

    def test_cases_starting_at_the_result_screen_grant_notifications_first(self):
        # 사진을 안 옮기는 05-12 시작 가설도 앞 묶음이 revoke 한 채면 권한 창이 화면을 가린다 — 앱을 켜기 **전에** 줘야 한다.
        self.serve({AVATARS: Reply(200, [PENDING])})
        adb = self.adb_calls

        class Marking(FakePhone):
            def __call__(this, *args, **job):
                adb('APP')  # 앱을 켠 순간을 adb 기록에 같이 남긴다
                return super().__call__(*args, **job)

        phone = Marking()
        phone.serial = 'S1'
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-35', phone)[0], 'pass')
        calls = [c.args for c in adb.call_args_list]
        grant = ('S1', 'shell', 'pm', 'grant', area1_b4.tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS')
        self.assertEqual(calls.count(grant), 1)
        self.assertLess(calls.index(grant), calls.index(('APP',)))

    def test_onb_35_fails_when_the_screen_check_changed_the_row(self):
        self.serve({AVATARS: Reply(200, [{'status': 'failed', 'is_fallback': False}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-35', self.phone())[0], 'fail')

    def test_onb_36_has_no_avatar_rows_and_a_broken_source_so_no_paid_call_goes_out(self):
        fake = self.serve({PHOTOS: SOURCE, AVATARS: Reply(200, [PENDING])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-36', self.phone())[0], 'pass')
        self.assertEqual(self.seeded(fake), [])  # 가설 준비로는 아바타 행을 넣지 않는다
        self.assertTrue(self.writes(fake, 'POST', 'storage/v1/object/profile-photos/id-1/src.jpg'))

    def test_onb_36_fails_when_the_tap_made_no_row_or_two(self):
        for rows in ([], [PENDING, PENDING]):
            self.serve({PHOTOS: SOURCE, AVATARS: Reply(200, rows)})
            self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-36', self.phone())[0], 'fail', rows)

    def test_broken_source_refuses_a_path_outside_this_account(self):
        fake = self.serve({PHOTOS: Reply(200, [{'storage_path': 'other-id/src.jpg'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-36', self.phone())[0], 'blocked')
        self.assertFalse(self.writes(fake, 'POST', 'storage/v1/object/profile-photos'))

    def test_broken_source_blocks_when_the_account_has_no_source_photo(self):
        self.serve({PHOTOS: Reply(200, [])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-36', self.phone())[0], 'blocked')

    def test_onb_37_seeds_five_failed_rows_and_wants_one_fallback_row_with_ten_hearts(self):
        fake = self.serve({AVATARS: Reply(200, failed(5) + [FALLBACK]), HEARTS: Reply(200, [{'amount': 10}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-37', self.phone())[0], 'pass')
        seeded = self.seeded(fake)[0]
        self.assertEqual([r['status'] for r in seeded], ['failed'] * 5)
        self.assertTrue(all(r['profile_id'] == 'id-1' and r['storage_path'] is None for r in seeded))

    def test_onb_37_fails_on_double_hearts_no_fallback_row_or_no_hearts(self):
        for rows, hearts in ((failed(5) + [FALLBACK], [{'amount': 10}, {'amount': 10}]),
                             (failed(5), [{'amount': 10}]),
                             (failed(5) + [FALLBACK], [])):
            self.serve({AVATARS: Reply(200, rows), HEARTS: Reply(200, hearts)})
            self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-37', self.phone())[0], 'fail', (rows, hearts))

    def test_onb_38_seeds_four_failed_rows_breaks_the_source_and_wants_the_workers_fifth_failure_to_pay_once(self):
        fake = self.serve({PHOTOS: SOURCE, AVATARS: Reply(200, failed(5) + [FALLBACK]), HEARTS: Reply(200, [{'amount': 10}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-38', self.phone())[0], 'pass')
        self.assertEqual(len(self.seeded(fake)[0]), 4)
        self.assertTrue(self.writes(fake, 'POST', 'storage/v1/object/profile-photos/id-1/src.jpg'))

    def test_onb_38_fails_when_hearts_went_out_twice_or_a_pending_row_is_left(self):
        for rows, hearts in ((failed(5) + [FALLBACK], [{'amount': 10}, {'amount': 10}]),
                             (failed(4) + [PENDING], [])):
            self.serve({PHOTOS: SOURCE, AVATARS: Reply(200, rows), HEARTS: Reply(200, hearts)})
            self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-38', self.phone())[0], 'fail', (rows, hearts))

    def test_onb_37_and_38_block_before_touching_anything_when_the_fallback_source_is_missing(self):
        # 결함 D-02 — 운영 버킷에 defaults/fallback-avatar.png 가 없으면 5번째 실패 보상이 복사에서 멈춘다.
        for case in ('E-ONB-37', 'E-ONB-38'):
            fake = self.serve({DEFAULTS: Reply(200, []), PHOTOS: SOURCE})
            result, note = area1.attempt_phone(self.run, case, self.phone())[:2]
            self.assertEqual(result, 'blocked', case)
            self.assertIn('defaults/fallback-avatar.png', note)
            self.assertIn('D-02', note)
            self.assertEqual(self.seeded(fake), [], case)
            self.assertFalse(self.writes(fake, 'POST', 'storage/v1/object/profile-photos/id-1/src.jpg'), case)

    def test_onb_37_blocks_when_only_other_files_are_in_defaults(self):
        self.serve({DEFAULTS: Reply(200, [{'name': 'other.png', 'id': 'o2'}])})
        result, note = area1.attempt_phone(self.run, 'E-ONB-37', self.phone())[:2]
        self.assertEqual(result, 'blocked')
        self.assertIn('D-02', note)

    def test_onb_37_blocks_when_the_bucket_list_cannot_be_read(self):
        self.serve({DEFAULTS: Reply(500, {'message': 'x'})})
        result, note = area1.attempt_phone(self.run, 'E-ONB-37', self.phone())[:2]
        self.assertEqual(result, 'blocked')
        self.assertIn('avatars', note)

    def test_other_result_screen_cases_do_not_look_for_the_fallback_source(self):
        fake = self.serve({DEFAULTS: Reply(200, []), AVATARS: Reply(200, [PENDING])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-35', self.phone())[0], 'pass')
        self.assertNotIn('/storage/v1/object/list/avatars', fake.paths())

    def run39(self, rows, hearts):
        self.serve({PHOTOS: SOURCE, AVATARS: Reply(200, rows), HEARTS: Reply(200, hearts)})
        return area1.attempt_phone(self.run, 'E-ONB-39', self.phone(midway_step={'step': 'registered'}))

    def test_onb_39_passes_with_one_new_pending_row_and_no_hearts(self):
        self.assertEqual(self.run39(failed(4) + [PENDING], [])[0], 'pass')

    def test_onb_39_fails_when_hearts_moved_without_a_fallback_row(self):
        self.assertEqual(self.run39(failed(4) + [PENDING], [{'amount': 10}])[0], 'fail')

    def test_onb_39_fails_when_no_new_row_or_two_were_added(self):
        self.assertEqual(self.run39(failed(4), [])[0], 'fail')
        self.assertEqual(self.run39(failed(4) + [PENDING, PENDING], [])[0], 'fail')

    def test_onb_39_blocks_instead_of_failing_when_the_worker_already_paid_before_we_looked(self):
        result, note = self.run39(failed(5) + [FALLBACK], [{'amount': 10}])
        self.assertEqual(result, 'blocked')
        self.assertIn('먼저', note)


class DuplicateTest(Base4):
    OK = Reply(202, {'status': 'pending'})
    CONFLICT = Reply(409, {'detail': area1_b4.ALREADY})
    READY = [{'status': 'ready', 'is_fallback': False}]

    def api(self, posts, first, second):
        self.serve({('POST', '/profile-onboarding/avatar/generate'): posts, PHOTOS: SOURCE,
                    AVATARS: [Reply(200, first), Reply(200, second)]})
        return area1.attempt(self.run, 'E-ONB-40')

    def test_onb_40_three_taps_make_one_row_and_a_finished_avatar_gets_409(self):
        result = self.api([self.OK, self.OK, self.OK, self.CONFLICT], failed(1) + [PENDING], self.READY)
        self.assertEqual(result[0], 'pass', result)

    def test_onb_40_fails_when_taps_made_a_second_pending_row(self):
        result = self.api([self.OK, self.OK, self.OK, self.CONFLICT], failed(1) + [PENDING, PENDING], self.READY)
        self.assertEqual(result[0], 'fail')

    def test_onb_40_fails_on_a_reply_other_than_202_for_a_tap(self):
        result = self.api([self.OK, self.OK, Reply(500, {'detail': 'x'}), self.CONFLICT], failed(1) + [PENDING], self.READY)
        self.assertEqual(result[0], 'fail')

    def test_onb_40_fails_on_wrong_409_text(self):
        result = self.api([self.OK, self.OK, self.OK, Reply(409, {'detail': '다른 말'})], failed(1) + [PENDING], self.READY)
        self.assertEqual(result[0], 'fail')

    def test_onb_40_tolerates_a_fast_worker_failure_between_taps_but_not_two_pending_rows(self):
        result = self.api([self.OK, self.OK, self.OK, self.CONFLICT], failed(2) + [PENDING], self.READY)
        self.assertEqual(result[0], 'pass', result)

    def test_onb_40_fails_when_the_finished_avatar_got_a_new_row(self):
        result = self.api([self.OK, self.OK, self.OK, self.CONFLICT], failed(1) + [PENDING], self.READY + [PENDING])
        self.assertEqual(result[0], 'fail')


if __name__ == '__main__':
    unittest.main()
