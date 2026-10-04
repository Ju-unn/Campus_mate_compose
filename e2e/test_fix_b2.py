"""묶음 2 운영 실행에서 나온 하네스 결함 — 기기 · 운영 없이 돈다."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from e2e import area1, area1_b2, tools
from e2e.test_area1 import Base, Reply
from e2e.test_area1_phone import FakePhone


class Utf8Test(unittest.TestCase):
    """윈도 기본 cp949 로 읽으면 dumpsys 의 한글(UTF-8)에서 UnicodeDecodeError — stdout 이 None 이 된다."""

    def kwargs_of(self, call):
        with mock.patch.object(tools.subprocess, 'run') as run:
            run.return_value.stdout = ''
            call()
        return run.call_args.kwargs

    def test_adb_decodes_utf8_and_never_raises_on_bad_bytes(self):
        kwargs = self.kwargs_of(lambda: tools.adb('S', 'shell', 'dumpsys', 'notification'))
        self.assertEqual((kwargs['encoding'], kwargs['errors']), ('utf-8', 'replace'))

    def test_gcloud_calls_decode_utf8_too(self):
        for call in (tools.service_key, lambda: tools.batch('cleanup')):
            kwargs = self.kwargs_of(call)
            self.assertEqual((kwargs['encoding'], kwargs['errors']), ('utf-8', 'replace'))


DUMP = '''  NotificationRecord(0x1 pkg=com.other.app user=UserHandle{0} id=1)
      android.title=String (다른 앱 제목)
      android.text=String (다른 앱 본문 비밀)
  NotificationRecord(0x2 pkg=io.github.juunn.campusmate user=UserHandle{0} id=2)
      android.title=String (친구가 가입했어요)
      android.text=String (Zzzzz 님이 가입했어요, 리뷰를 남겨 주세요)
'''


class Onb61Test(Base):
    def run61(self, *dumps):
        self.serve({('GET', '/rest/v1/profiles'): Reply(200, [{'referral_code': 'K7M2QX', 'nickname': 'Abcde'}])})
        with mock.patch.object(tools, 'adb', side_effect=list(dumps) + [dumps[-1]] * 20),                 mock.patch.object(tools, 'screencap', return_value=b'x'), mock.patch.object(area1_b2.time, 'sleep'):
            phone = FakePhone()
            phone.serial = 'S'
            return area1.attempt_phone(self.run, 'E-ONB-61', phone)

    def test_wrong_body_leaves_our_title_and_text_lines_in_the_note(self):
        result, note = self.run61(DUMP)
        self.assertEqual(result, 'fail')
        self.assertIn('Zzzzz 님이 가입했어요', note)  # 우리 앱이 실제로 띄운 글자
        self.assertIn('Abcde', note)  # 기대한 닉네임

    def test_other_apps_notifications_are_never_copied_into_the_note(self):
        result, note = self.run61(DUMP)
        self.assertNotIn('비밀', note)
        self.assertNotIn('다른 앱', note)

    def test_other_apps_lines_do_not_count_as_ours(self):
        dump = DUMP.split('  NotificationRecord(0x2')[0].replace('다른 앱 제목', '친구가 가입했어요')
        result, note = self.run61(dump)
        self.assertEqual(result, 'fail')
        self.assertIn('30초 안에', note)  # 다른 앱의 같은 제목이 우리 알림으로 세어지지 않았다

    def test_an_old_notification_with_the_same_title_does_not_end_the_wait(self):
        # 앞 시도의 알림이 아직 창에 남아 있다 — 새 푸시(이 시도의 닉네임)가 올 때까지 기다려야 한다
        old = DUMP.replace('Zzzzz', 'Oldie')
        new = DUMP.replace('Zzzzz', 'Abcde')
        self.assertEqual(self.run61(old, old, new), ('pass', ''))


class ShotTest(Base):
    def phone(self, serial='S'):
        phone = FakePhone(area1.APP_FAIL if hasattr(area1, 'APP_FAIL') else {'result': 'fail', 'note': 'x'})
        phone.serial = serial
        return phone

    def test_shot_writes_png_under_shots_named_after_the_case(self):
        with mock.patch.object(tools, 'screencap', return_value=b'\x89PNG'):
            path = self.run.shot('S', 'E-AUTH-07')
        self.assertEqual(path, self.run.out / 'shots' / 'E-AUTH-07.png')
        self.assertEqual(path.read_bytes(), b'\x89PNG')

    def test_shot_failure_is_swallowed(self):
        with mock.patch.object(tools, 'screencap', side_effect=OSError('no adb')):
            self.assertIsNone(self.run.shot('S', 'E-AUTH-07'))

    def test_failed_phone_case_takes_a_shot_but_a_pass_does_not(self):
        self.serve()
        with mock.patch.object(tools, 'screencap', return_value=b'x') as cap:
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-04', self.phone())[0], 'fail')
            self.assertEqual(cap.call_count, 1)
            passing = FakePhone()
            passing.serial = 'S'
            self.assertEqual(area1.attempt_phone(self.run, 'E-GATE-04', passing)[0], 'pass')
            self.assertEqual(cap.call_count, 1)

    def test_no_serial_means_no_shot(self):
        self.serve()
        with mock.patch.object(tools, 'screencap') as cap:
            area1.attempt_phone(self.run, 'E-GATE-04', self.phone(serial=None))
        cap.assert_not_called()


if __name__ == '__main__':
    unittest.main()
