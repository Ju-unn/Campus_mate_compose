"""영역 4 SET-29~42 연락처 가설의 PC 쪽 — 가짜 서버 · 가짜 폰 · 가짜 adb, 기기 · 운영 없이 돈다."""

import contextlib
import unittest
from unittest import mock

from e2e import area1, area4_contacts, contacts, tools
from e2e.test_area1 import Base, Reply
from e2e.test_area1_phone import FakePhone

S = 'emulator-5554'
CASES = [f'E-SET-{n}' for n in range(29, 43)]


class Recorder:
    """contacts.on_device 대신 — 무엇을 넣고 어떤 권한으로 앱을 켰는지만 남긴다."""

    def __init__(self):
        self.runs = []

    @contextlib.contextmanager
    def on_device(self, serial, crowd, granted):
        self.runs.append((serial, list(crowd), granted))
        yield


class CaseTest(Base):
    def setUp(self):
        super().setUp()
        self.recorder = Recorder()
        patcher = mock.patch.object(contacts, 'on_device', self.recorder.on_device)
        patcher.start()
        self.addCleanup(patcher.stop)
        granter = mock.patch('e2e.notify.grant_notifications')  # 에뮬 도우미가 알림 권한을 미리 준다 — 실제 adb 는 안 부른다
        granter.start()
        self.addCleanup(granter.stop)
        deleter = mock.patch.object(contacts, 'delete_person')  # 기기에서 지우는 일은 가짜로
        self.delete_person = deleter.start()
        self.addCleanup(deleter.stop)

    def phone(self, **kw):
        phone = FakePhone(**kw)
        phone.serial = S
        return phone

    def blocks(self, count):
        return self.serve({('GET', '/rest/v1/contact_blocks'): Reply(200, [{'id': str(i)} for i in range(count)])})

    def attempt(self, case, phone=None):
        return area1.attempt_phone(self.run, case, phone or self.phone())

    def test_bundle_is_set_29_to_42_in_order(self):
        self.assertEqual(area1.BUNDLES['area4-contacts'], CASES)
        self.assertTrue(set(CASES) <= set(area1.PHONE))

    def test_every_case_refuses_a_real_phone_before_touching_anything(self):
        self.serve()
        for case in CASES:
            phone = FakePhone()
            phone.serial = 'R5CR12345'
            self.assertEqual(self.attempt(case, phone)[0], 'blocked', case)
        self.assertEqual(self.recorder.runs, [])

    def test_permission_per_case(self):
        self.blocks(0)
        granted = {}
        for case in CASES:
            self.recorder.runs.clear()
            with mock.patch.object(contacts, 'tap_dialog'), mock.patch.object(contacts, 'delete_person'), mock.patch.object(area4_contacts.time, 'sleep'):
                self.attempt(case, self.phone(midway_step={'step': 'dialog'}))
            granted[case] = self.recorder.runs[0][2]
        self.assertEqual([c for c, g in granted.items() if not g], ['E-SET-29', 'E-SET-30', 'E-SET-31', 'E-SET-32'])

    def test_dialog_cases_tap_the_dialog_while_the_app_waits(self):
        self.serve()
        with mock.patch.object(contacts, 'tap_dialog') as tap:
            self.attempt('E-SET-30', self.phone(midway_step={'step': 'dialog'}))
            self.attempt('E-SET-32', self.phone(midway_step={'step': 'dialog'}))
        self.assertEqual([c.args[1] for c in tap.call_args_list], [True, False])

    def test_a_dialog_that_never_shows_is_blocked_not_fail(self):
        self.serve()
        with mock.patch.object(contacts, 'tap_dialog', side_effect=tools.Blocked('권한 창이 안 뜸')):
            self.assertEqual(self.attempt('E-SET-30', self.phone(midway_step={'step': 'dialog'}))[0], 'blocked')

    def test_set_31_needs_the_settings_app_on_top(self):
        self.serve()
        settings = 'mResumedActivity: ActivityRecord{1 u0 com.android.settings/.Settings$AppInfoActivity}'
        with mock.patch.object(area4_contacts.time, 'sleep'):
            self.assertEqual(self.attempt('E-SET-31', self.phone(top=settings))[0], 'pass')
            result, note = self.attempt('E-SET-31', self.phone())  # 크롬이 맨 위
        self.assertEqual(result, 'fail')
        self.assertIn('설정 앱이 아님', note)

    def test_set_40_deletes_the_first_contact_while_the_app_waits(self):
        self.blocks(2)
        with mock.patch.object(contacts, 'delete_person') as delete:
            self.assertEqual(self.attempt('E-SET-40', self.phone(midway_step={'step': 'delete'}))[0], 'pass')
        delete.assert_called_once_with(S, 0)

    KNOWN = ('앱은 이름표를 앱 파일에 저장해 16b 가 그것만 읽음 → 기기 연락처를 지워도 "이전에 차단한 연락처"로 안 바뀜')

    def test_set_40_name_label_kept_is_known_not_fail(self):
        # 시나리오 기대와 앱 동작이 다른 제품 결정 — fail 이 아니라 known(결과 종류)으로 기록하고 이유를 메모에 남긴다
        self.blocks(2)
        phone = self.phone(midway_step={'step': 'delete'})
        phone.answers = [{'result': 'pass', 'known': self.KNOWN}]
        result, note = self.attempt('E-SET-40', phone)
        self.assertEqual(result, 'known')
        self.assertIn('이름표를 앱 파일에 저장', note)
        self.assertIn('이전에 차단한 연락처', note)

    def test_set_40_known_still_needs_the_server_side_blocks_to_stay(self):
        self.blocks(1)  # 지운 뒤 서버 차단이 줄었으면 known 이 아니라 fail
        phone = self.phone(midway_step={'step': 'delete'})
        phone.answers = [{'result': 'pass', 'known': self.KNOWN}]
        self.assertEqual(self.attempt('E-SET-40', phone)[0], 'fail')

    def test_set_40_matching_the_scenario_is_a_plain_pass(self):
        self.blocks(2)
        self.assertEqual(self.attempt('E-SET-40', self.phone(midway_step={'step': 'delete'}))[0], 'pass')

    def test_set_40_app_failure_stays_fail_even_with_a_known_flag_elsewhere(self):
        self.blocks(2)
        phone = self.phone(midway_step={'step': 'delete'})
        phone.answers = [{'result': 'fail', 'note': '16b 가 안 열림', 'known': self.KNOWN}]
        self.assertEqual(self.attempt('E-SET-40', phone)[0], 'fail')

    def test_only_set_40_may_be_known(self):
        self.blocks(2)
        phone = self.phone(midway_step={'step': 'x'})
        phone.answers = [{'result': 'pass', 'known': 'x'}]
        self.assertEqual(self.attempt('E-SET-33', phone)[0], 'pass')  # 다른 가설은 known 표시를 무시한다

    def test_db_counts(self):
        for case, rows, expected in [('E-SET-34', 0, 'pass'), ('E-SET-34', 1, 'fail'), ('E-SET-35', 2, 'pass'), ('E-SET-35', 1, 'fail'),
                                     ('E-SET-37', 0, 'pass'), ('E-SET-37', 1, 'fail'), ('E-SET-38', 1, 'pass'), ('E-SET-38', 2, 'fail'),
                                     ('E-SET-39', 201, 'pass'), ('E-SET-39', 200, 'fail'), ('E-SET-41', 1, 'pass'), ('E-SET-41', 2, 'fail'),
                                     ('E-SET-42', 3, 'pass'), ('E-SET-42', 2, 'fail')]:
            self.blocks(rows)
            self.assertEqual(self.attempt(case)[0], expected, (case, rows))

    def test_app_failure_is_a_fail_and_contacts_are_still_cleaned(self):
        self.serve()
        self.assertEqual(self.attempt('E-SET-33', self.phone(midway_step={'step': 'x'}))[0], 'pass')
        phone = self.phone()
        phone.answers = [{'result': 'fail', 'note': 'x'}]
        self.assertEqual(self.attempt('E-SET-33', phone)[0], 'fail')

    def test_jobs_carry_the_names_and_what_to_pick(self):
        self.blocks(1)
        phone = self.phone()
        self.attempt('E-SET-42', phone)
        job = phone.jobs[0]
        self.assertEqual((job['pick'], job['add']), (2, 1))
        self.assertEqual(job['names'], [name for name, _ in self.recorder.runs[0][1]])
        phone = self.phone()
        self.blocks(201)
        self.attempt('E-SET-39', phone)
        self.assertEqual((phone.jobs[0]['pick'], len(phone.jobs[0]['names'])), ('all', 201))

    def test_people_are_what_each_case_needs(self):
        self.blocks(0)
        self.attempt('E-SET-37')
        self.assertEqual(self.recorder.runs[-1][1][0][1], ('02-123-4567',))  # 유선 번호
        self.recorder.runs.clear()
        self.blocks(1)
        self.attempt('E-SET-38')
        first, second = [numbers[0] for _, numbers in self.recorder.runs[-1][1]]
        self.assertTrue(first.startswith('010-') and second == '+82 ' + first[1:])  # 같은 번호 두 모양
        self.recorder.runs.clear()
        self.blocks(201)
        self.attempt('E-SET-39')
        crowd = self.recorder.runs[-1][1]
        self.assertEqual(len(crowd), 201)
        self.assertEqual(len({name for name, _ in crowd}), 201)  # 이름이 서로 달라야 앱에서 골라 누른다


if __name__ == '__main__':
    unittest.main()
