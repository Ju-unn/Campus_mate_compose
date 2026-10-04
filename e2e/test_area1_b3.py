"""영역 1 묶음 3(사진 세트) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b3`."""

import contextlib
import io
import unittest
from datetime import datetime, timezone
from unittest import mock

from e2e import area1, area1_b3
from e2e.test_area1 import Base
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Reply

CASES = ['E-ONB-26']
PHONE = ['E-GATE-34', 'E-GATE-35', 'E-GATE-36', 'E-GATE-37', 'E-GATE-38', 'E-GATE-44', 'E-GATE-45',
         'E-ONB-20', 'E-ONB-21', 'E-ONB-22', 'E-ONB-23']
INVALID = '사진을 다시 확인해 주세요'
NOW = datetime.now(timezone.utc).isoformat()


class PhotoBase(Base):
    """사진 세트 폴더(E2E_결과/사진/)를 임시 폴더에 만든다 — 가설이 올리는 파일이 거기 있어야 한다."""

    def setUp(self):
        super().setUp()
        self.folder = self.root / '사진'
        self.folder.mkdir()
        self.adb = mock.patch.object(area1_b3.tools, 'adb', return_value='')
        self.adb_calls = self.adb.start()
        self.addCleanup(self.adb.stop)

    def put(self, *names):
        for name in names:
            (self.folder / name).write_bytes(b'\xff\xd8\xff' + name.encode())


class BundleTest(unittest.TestCase):
    def test_bundle_has_the_api_case_then_the_phone_cases(self):
        self.assertEqual(area1.BUNDLES['area1-b3'], CASES + PHONE)
        self.assertLessEqual(set(CASES), set(area1.CASES))
        self.assertLessEqual(set(PHONE), set(area1.PHONE))

    def test_cases_already_in_other_bundles_are_not_repeated(self):
        for case in ('E-GATE-30', 'E-ONB-33', 'E-ONB-55'):
            self.assertNotIn(case, area1.BUNDLES['area1-b3'])
        self.assertIn('E-ONB-25', area1_b3.LEFT_OUT)  # 04-3 "다음" 이 아바타 작업까지 등록한다 — 묶음 4
        self.assertIn('E-ONB-24', area1_b3.LEFT_OUT)


class PhotoSetTest(PhotoBase):
    def test_missing_files_block_with_every_missing_name(self):
        self.put('face1.jpg')
        with self.assertRaises(area1_b3.Blocked) as caught:
            area1_b3._photos(self.run, 'face1.jpg', 'scenery.jpg', 'id_ok.jpg')
        self.assertIn('scenery.jpg', str(caught.exception))
        self.assertIn('id_ok.jpg', str(caught.exception))
        self.assertNotIn('face1.jpg', str(caught.exception))

    def test_push_copies_each_file_once_into_the_app_cache(self):
        self.put('face1.jpg', 'face2.jpg')
        phone = FakePhone()
        phone.serial = 'S1'
        area1_b3._push(phone, self.run, 'face1.jpg', 'face2.jpg', 'face1.jpg')
        pushed = [c.args for c in self.adb_calls.call_args_list if 'push' in c.args]
        self.assertEqual([a[-1].rsplit('/', 1)[1] for a in pushed], ['face1.jpg', 'face2.jpg'])
        self.assertTrue(all(a[0] == 'S1' for a in pushed))
        # adb shell 은 뒤 인자를 따옴표 없이 이어 붙여 기기 셸에 넘긴다 — 한 문자열로 줘야 sh -c 가 통째로 간다.
        copied = [c.args for c in self.adb_calls.call_args_list if any(str(a).startswith('run-as') for a in c.args)]
        self.assertEqual(len(copied), 1)
        self.assertEqual(copied[0][:2], ('S1', 'shell'))
        self.assertEqual(len(copied[0]), 3)
        command = copied[0][2]
        self.assertTrue(command.startswith(f"run-as {area1_b3.tools.PACKAGE} sh -c '"), command)
        self.assertIn('mkdir -p cache/e2e-photos', command)
        for name in ('face1.jpg', 'face2.jpg'):  # 글롭 대신 이름별로 — 폴더를 앱이 못 읽어도 되지 않게 chmod 도
            self.assertIn(f'cp {area1_b3.REMOTE}/{name} cache/e2e-photos/', command)
        self.assertEqual(command.count('cp '), 2)
        chmod = [c.args for c in self.adb_calls.call_args_list if 'chmod' in c.args]
        self.assertTrue(chmod and area1_b3.REMOTE in chmod[0])

    def test_check_lists_what_is_missing(self):
        self.put('face1.jpg')
        missing = area1_b3.missing(self.folder)
        self.assertNotIn('face1.jpg', missing)
        self.assertIn('unsafe.jpg', missing)
        self.assertEqual(set(missing) | {'face1.jpg'}, set(area1_b3.PHOTO_SET))


class PhotoApiTest(PhotoBase):
    def test_onb_26_rejects_slot_4_gif_and_big_jpeg_and_saves_nothing(self):
        fake = self.serve({('POST', '/profile-onboarding/photos'): [
            Reply(422, {'detail': [{'msg': 'less than or equal to 3'}]}),
            Reply(400, {'detail': INVALID}), Reply(400, {'detail': INVALID})]})
        self.assertEqual(area1.attempt(self.run, 'E-ONB-26'), ('pass', ''))
        sent = [len(b) for m, u, b in fake.raws if u.endswith('/profile-onboarding/photos')]
        self.assertEqual(len(sent), 3)
        self.assertGreater(sent[2], 10 * 1024 * 1024 + 1)  # 10MB 보다 딱 1바이트 큰 사진 + multipart 껍데기
        self.assertIn(b'name="position"\r\n\r\n4', [r for m, u, r in fake.raws][0])
        self.assertIn(b'GIF89a', [r for m, u, r in fake.raws][1])

    def test_onb_26_fails_when_a_gif_is_accepted_or_a_file_is_left(self):
        self.serve({('POST', '/profile-onboarding/photos'): [
            Reply(422, {'detail': []}), Reply(200, {'ok': True}), Reply(400, {'detail': INVALID})]})
        result, note = area1.attempt(self.run, 'E-ONB-26')
        self.assertEqual(result, 'fail')
        self.assertIn('GIF', note)

    def test_onb_26_fails_when_a_row_or_file_remains(self):
        self.serve({('POST', '/profile-onboarding/photos'): [
            Reply(422, {'detail': []}), Reply(400, {'detail': INVALID}), Reply(400, {'detail': INVALID})],
            ('GET', '/rest/v1/profile_photos'): Reply(200, [{'position': 0}])})
        result, note = area1.attempt(self.run, 'E-ONB-26')
        self.assertEqual(result, 'fail')
        self.assertIn('profile_photos', note)


class VerificationPhoneTest(PhotoBase):
    def attempts(self, *rows):
        return {('GET', '/rest/v1/student_verification_attempts'): Reply(200, list(rows))}

    def run_phone(self, case, routes=None, phone=None):
        self.serve(routes)
        phone = phone or FakePhone()
        phone.serial = 'S1'
        return area1.attempt_phone(self.run, case, phone), phone

    def test_missing_photo_blocks_before_any_account_is_made(self):
        fake = self.serve()
        result, note = area1.attempt_phone(self.run, 'E-GATE-34', FakePhone())
        self.assertEqual(result, 'blocked')
        self.assertIn('scenery.jpg', note)
        self.assertEqual(fake.users, [])

    def test_gate_34_sends_the_scenery_and_wants_no_attempt_row(self):
        self.put('scenery.jpg')
        (result, _), phone = self.run_phone('E-GATE-34', self.attempts())
        self.assertEqual(result, 'pass')
        self.assertEqual(phone.jobs[0]['photo'], 'scenery.jpg')
        self.assertEqual(phone.jobs[0]['real_name'], area1_b3.REAL_NAME)
        self.assertIn('token_hash', phone.jobs[0])

    def test_gate_34_fails_when_the_server_was_called(self):
        self.put('scenery.jpg')
        (result, note), _ = self.run_phone('E-GATE-34', self.attempts({'result': 'pending'}))
        self.assertEqual(result, 'fail')
        self.assertIn('attempts', note)

    def test_gate_35_wants_one_attempt_row(self):
        self.put('cert_noface.jpg')
        (result, _), phone = self.run_phone('E-GATE-35', self.attempts({'result': 'verified'}))
        self.assertEqual(result, 'pass')
        self.assertEqual(phone.jobs[0]['tab'], '졸업증명서')
        (result, _), _ = self.run_phone('E-GATE-35', self.attempts())
        self.assertEqual(result, 'fail')

    def test_gate_36_wants_verified_row_profile_and_no_file_left(self):
        self.put('id_ok.jpg')
        row = {'result': 'verified', 'reviewed_at': NOW}
        self.serve({**self.attempts(row), ('GET', '/rest/v1/profiles'): Reply(200, [{'student_verification': 'verified'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-36', FakePhone())[0], 'pass')

    def test_gate_36_fails_when_the_photo_is_still_in_the_bucket(self):
        self.put('id_ok.jpg')
        self.serve({**self.attempts({'result': 'verified', 'reviewed_at': NOW}),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'student_verification': 'verified'}]),
                    ('POST', '/storage/v1/object/list/student-id-temp'): Reply(200, [{'name': 'a.jpg', 'id': 'x'}])})
        result, note = area1.attempt_phone(self.run, 'E-GATE-36', FakePhone())
        self.assertEqual(result, 'fail')
        self.assertIn('student-id-temp', note)

    def test_gate_37_wants_pending_and_one_file_kept(self):
        self.put('id_name.jpg')
        self.serve({**self.attempts({'result': 'pending'}),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'student_verification': 'pending'}]),
                    ('POST', '/storage/v1/object/list/student-id-temp'): Reply(200, [{'name': 'a.jpg', 'id': 'x'}])})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-37', FakePhone())[0], 'pass')

    def test_gate_38_runs_two_accounts_one_per_photo(self):
        self.put('id_school.jpg', 'id_blank.jpg')
        self.serve({**self.attempts({'result': 'pending'}),
                    ('GET', '/rest/v1/profiles'): Reply(200, [{'student_verification': 'pending'}]),
                    ('POST', '/storage/v1/object/list/student-id-temp'): Reply(200, [{'name': 'a.jpg', 'id': 'x'}])})
        phone = FakePhone()
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-38', phone)[0], 'pass')
        self.assertEqual([j['photo'] for j in phone.jobs], ['id_school.jpg', 'id_blank.jpg'])

    def test_gate_44_rejects_only_this_accounts_pending_attempt_while_the_app_waits(self):
        self.put('id_name.jpg')
        fake = self.serve(self.attempts({'result': 'rejected', 'reject_reason': area1_b3.REJECT_REASON}))
        phone = FakePhone(midway_step={'step': 'pending'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-44', phone)[0], 'pass')
        patches = [(u, b) for (m, u), (_, _, b) in zip(fake.urls, fake.calls) if m == 'PATCH']
        urls = [u for u, _ in patches]
        self.assertTrue(any('student_verification_attempts?profile_id=eq.id-1' in u and 'result=eq.pending' in u for u in urls), urls)
        bodies = [b for _, b in patches]
        self.assertIn({'result': 'rejected', 'reject_reason': area1_b3.REJECT_REASON, 'reviewed_at': mock.ANY}, bodies)
        self.assertIn({'student_verification': 'rejected'}, bodies)
        self.assertTrue(all('id-1' in u for u in urls), urls)  # 다른 계정은 건드리지 않는다
        self.assertEqual(phone.acted, ['pending'])

    def test_gate_44_fails_when_no_attempt_could_be_rejected(self):
        self.put('id_name.jpg')
        self.serve(self.attempts())
        phone = FakePhone(midway_step={'step': 'pending'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-44', phone)[0], 'fail')

    def test_gate_45_submits_three_times_and_rejects_each_time(self):
        self.put('id_name.jpg')
        self.serve(self.attempts({'result': 'rejected'}, {'result': 'rejected'}, {'result': 'rejected'}))
        phone = FakePhone(midway_step={'step': 'pending'})
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-45', phone)[0], 'pass')
        self.assertEqual(len(phone.jobs), 3)
        self.assertEqual(phone.acted, ['pending'] * 3)

    def test_gate_45_fails_when_a_row_is_still_pending(self):
        self.put('id_name.jpg')
        self.serve(self.attempts({'result': 'rejected'}, {'result': 'rejected'}, {'result': 'pending'}))
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-45', FakePhone(midway_step={'step': 'pending'}))[0], 'fail')

    def test_gate_44_names_the_cause_when_there_was_nothing_to_reject(self):
        self.put('id_name.jpg')
        self.serve(self.attempts())
        result, note = area1.attempt_phone(self.run, 'E-GATE-44', FakePhone(midway_step={'step': 'pending'}))
        self.assertEqual(result, 'fail')
        self.assertIn('반려할 대기', note)

    def test_gate_45_fails_with_fewer_than_three_rows(self):
        self.put('id_name.jpg')
        self.serve(self.attempts({'result': 'rejected'}, {'result': 'rejected'}))
        self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-45', FakePhone(midway_step={'step': 'pending'}))[0], 'fail')


class ProfilePhotoPhoneTest(PhotoBase):
    def test_onb_20_gives_the_app_two_faces_at_the_photo_step(self):
        self.put('face1.jpg', 'face2.jpg')
        fake = self.serve()
        phone = FakePhone()
        phone.serial = 'S1'
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-20', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['photos'], ['face1.jpg', 'face2.jpg'])
        self.assertIn('/profile-onboarding/kakao-id', fake.paths('POST'))
        self.assertNotIn('/profile-onboarding/photos', fake.paths('POST'))  # 04-2 계정은 사진 전까지만

    def test_onb_21_gives_five_picks_from_four_faces(self):
        self.put('face1.jpg', 'face2.jpg', 'face3.jpg', 'face4.jpg')
        self.serve()
        phone = FakePhone()
        phone.serial = 'S1'
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-21', phone)[0], 'pass')
        self.assertEqual(len(phone.jobs[0]['photos']), 5)

    def test_onb_22_mixes_scenery_in(self):
        self.put('face1.jpg', 'face2.jpg', 'scenery.jpg')
        self.serve()
        phone = FakePhone()
        phone.serial = 'S1'
        self.assertEqual(area1.attempt_phone(self.run, 'E-ONB-22', phone)[0], 'pass')
        self.assertEqual(phone.jobs[0]['photos'], ['face1.jpg', 'face2.jpg', 'scenery.jpg'])

    def onb_23(self, photo_rows, files):
        self.put('face1.jpg', 'unsafe.jpg')
        self.serve({('GET', '/rest/v1/profile_photos'): Reply(200, photo_rows),
                    ('POST', '/storage/v1/object/list/profile-photos'): Reply(200, [{'name': f'f{i}', 'id': f'x{i}'} for i in range(files)])})
        phone = FakePhone()
        phone.serial = 'S1'
        return area1.attempt_phone(self.run, 'E-ONB-23', phone)

    def test_onb_23_passes_when_only_the_face_photo_was_saved(self):
        self.assertEqual(self.onb_23([{'position': 0}], 1)[0], 'pass')

    def test_onb_23_fails_when_the_rejected_slot_was_saved(self):
        result, note = self.onb_23([{'position': 0}, {'position': 1}], 2)
        self.assertEqual(result, 'fail')
        self.assertIn('profile_photos', note)

    def test_onb_23_fails_when_slot_1_holds_a_row_even_alone(self):
        self.assertEqual(self.onb_23([{'position': 1}], 1)[0], 'fail')

    def test_onb_23_is_blocked_without_the_rejection_photo(self):
        self.put('face1.jpg')
        fake = self.serve()
        result, note = area1.attempt_phone(self.run, 'E-ONB-23', FakePhone())
        self.assertEqual(result, 'blocked')
        self.assertIn('unsafe.jpg', note)
        self.assertEqual(fake.users, [])


class PhotosCommandTest(PhotoBase):
    def run_command(self):
        from e2e import __main__ as cli
        out = io.StringIO()
        with mock.patch.object(cli, 'RESULTS', self.root), contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as code:
            cli.cmd_photos(None)
        return code.exception.code, out.getvalue()

    def test_photos_lists_the_missing_names_and_exits_1(self):
        self.put('face1.jpg')
        code, text = self.run_command()
        self.assertEqual(code, 1)
        self.assertIn('unsafe.jpg', text)
        self.assertNotIn('face1.jpg', text)

    def test_photos_exits_0_when_the_set_is_complete(self):
        self.put(*area1_b3.PHOTO_SET)
        self.assertEqual(self.run_command()[0], 0)


if __name__ == '__main__':
    unittest.main()
