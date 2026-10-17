"""영역 1 묶음 3(사진 세트) 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 HTTP 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area1_b3`."""

import contextlib
import io
import unittest
from unittest import mock

from e2e import area1, area1_b3
from e2e.test_area1 import Base
from e2e.test_area1_phone import FakePhone
from e2e.tools import Reply

CASES = ['E-ONB-26']
PHONE = ['E-ONB-20', 'E-ONB-21', 'E-ONB-22', 'E-ONB-23']
# 3b 학생증 제출 가설 — 학생증 제거(10-17)로 앱 화면 · 서버 경로와 함께 뺐다. 앱이 이 번호를 모르면 "모르는 가설" 로 실패한다.
GONE = ['E-GATE-34', 'E-GATE-35', 'E-GATE-36', 'E-GATE-37', 'E-GATE-38', 'E-GATE-44', 'E-GATE-45']
INVALID = '사진을 다시 확인해 주세요'


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

    def test_student_id_cases_are_registered_nowhere(self):
        for case in GONE:
            self.assertNotIn(case, area1.PHONE)
            self.assertNotIn(case, area1_b3.LEFT_OUT)

    def test_cases_already_in_other_bundles_are_not_repeated(self):
        for case in ('E-ONB-33', 'E-ONB-55'):
            self.assertNotIn(case, area1.BUNDLES['area1-b3'])
        self.assertIn('E-ONB-25', area1_b3.LEFT_OUT)  # 04-3 "다음" 이 아바타 작업까지 등록한다 — 묶음 4
        self.assertIn('E-ONB-24', area1_b3.LEFT_OUT)


class PhotoSetTest(PhotoBase):
    def test_missing_files_block_with_every_missing_name(self):
        self.put('face1.jpg')
        with self.assertRaises(area1_b3.Blocked) as caught:
            area1_b3._photos(self.run, 'face1.jpg', 'scenery.jpg', 'unsafe.jpg')
        self.assertIn('scenery.jpg', str(caught.exception))
        self.assertIn('unsafe.jpg', str(caught.exception))
        self.assertNotIn('face1.jpg', str(caught.exception))

    def test_the_set_asks_for_no_student_id_or_certificate_photo(self):
        # 학생증 · 졸업증명서 사진은 3b 가설만 썼다(학생증 제거 10-17) — 대장이 더 준비하지 않게 목록에서 뺀다.
        self.assertEqual([n for n in area1_b3.PHOTO_SET if n.startswith(('id_', 'cert_'))], [])

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

    def test_push_grants_notifications_before_the_app_starts(self):
        # 앞 묶음이 알림 권한을 revoke 한 채 끝나면 권한 창이 앱을 가린다 — 사진을 옮기는 자리에서 늘 다시 준다.
        self.put('face1.jpg')
        phone = FakePhone()
        phone.serial = 'S1'
        area1_b3._push(phone, self.run, 'face1.jpg')
        calls = [c.args for c in self.adb_calls.call_args_list]
        grants = [i for i, a in enumerate(calls) if a == (
            'S1', 'shell', 'pm', 'grant', area1_b3.tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS')]
        self.assertEqual(len(grants), 1, calls)

    def test_push_still_copies_when_notification_grant_is_refused(self):
        # 안드로이드 12 이하는 알림 권한이 없어 pm grant 가 실패한다 — 권한 창도 없으니 그대로 옮긴다(area1_emu 와 같은 규칙).
        self.put('face1.jpg')
        phone = FakePhone()
        phone.serial = 'S1'

        def refuse(serial, *args, **kwargs):
            if 'grant' in args:
                raise area1_b3.notify.subprocess.CalledProcessError(1, 'adb')
            return ''

        self.adb_calls.side_effect = refuse
        area1_b3._push(phone, self.run, 'face1.jpg')
        self.assertTrue(any(any(str(a).startswith('run-as') for a in c.args) for c in self.adb_calls.call_args_list))

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
