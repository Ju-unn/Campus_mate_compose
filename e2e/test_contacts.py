"""에뮬 연락처 · 연락처 권한 도우미 — adb 는 가짜, 기기 · 운영 없이 돈다."""

import unittest
from unittest import mock

from e2e import contacts, tools
from e2e.test_emu import FakeAdb, patched

S = 'emulator-5554'
PEOPLE = [('테스트지인A', ('010-1111-2222',)), ('테스트지인B', ('010-3333-4444', '+82 10-5555-6666'))]
ROWS = 'Row: 0 _id=41, sourceid=e2e-0000\nRow: 1 _id=42, sourceid=e2e-0001\n'


class ScriptAdb(FakeAdb):
    """push 하는 순간의 스크립트 내용을 남긴다 — 임시 파일은 곧 지워지므로."""

    def __init__(self, answers=None):
        super().__init__(answers)
        self.scripts = []

    def __call__(self, serial, *args, check=True):
        if args and args[0] == 'push':
            with open(args[1], encoding='utf-8') as f:
                self.scripts.append(f.read())
        return super().__call__(serial, *args, check=check)


class PermissionTest(unittest.TestCase):
    def test_grant_and_revoke_refuse_a_real_phone_without_touching_it(self):
        adb = FakeAdb()
        with patched(adb):
            for call in (contacts.grant, contacts.revoke, lambda s: contacts.tap_dialog(s, True), contacts.remove_all,
                         lambda s: contacts.delete_person(s, 0), lambda s: contacts.insert(s, PEOPLE)):
                with self.assertRaises(tools.Blocked):
                    call('R5CR12345')
        self.assertEqual(adb.calls, [])

    def test_grant_uses_pm_grant_for_read_contacts_only(self):
        adb = FakeAdb({'dumpsys package': 'android.permission.READ_CONTACTS: granted=true, flags=[ USER_SET]'})
        with patched(adb):
            contacts.grant(S)
        self.assertTrue(adb.ran(f'pm grant {tools.PACKAGE} android.permission.READ_CONTACTS'))
        self.assertFalse(adb.ran('reset-permissions'))

    def test_revoke_resets_the_denial_count_then_revokes_and_checks(self):
        adb = FakeAdb({'dumpsys package': 'android.permission.READ_CONTACTS: granted=false, flags=[ ]'})
        with patched(adb):
            contacts.revoke(S)
        self.assertLess(adb.calls.index(adb.ran('reset-permissions')[0]), adb.calls.index(adb.ran('pm revoke')[0]))

    def test_revoke_that_leaves_it_granted_is_blocked(self):
        with patched(FakeAdb({'dumpsys package': 'android.permission.READ_CONTACTS: granted=true'})), self.assertRaises(tools.Blocked):
            contacts.revoke(S)

    def test_grant_that_does_not_stick_is_blocked(self):
        with patched(FakeAdb({'dumpsys package': 'android.permission.READ_CONTACTS: granted=false'})), self.assertRaises(tools.Blocked):
            contacts.grant(S)


def dump(button_id, bounds='[100,200][300,260]'):
    return f'<hierarchy><node text="x" resource-id="{button_id}" class="android.widget.Button" bounds="{bounds}" /></hierarchy>'


class DialogTest(unittest.TestCase):
    def tap(self, allow, xml):
        adb = FakeAdb()
        with patched(adb), mock.patch.object(contacts, '_dump', side_effect=xml if isinstance(xml, list) else [xml] * 20):
            contacts.tap_dialog(S, allow, timeout=6, sleep=lambda s: None)
        return adb

    def test_allow_taps_the_middle_of_the_allow_button(self):
        adb = self.tap(True, dump(contacts.ALLOW))
        self.assertTrue(adb.ran('input tap 200 230'))

    def test_deny_taps_the_deny_button(self):
        adb = self.tap(False, dump(contacts.DENY, '[10,20][30,40]'))
        self.assertTrue(adb.ran('input tap 20 30'))

    def test_waits_until_the_dialog_shows(self):
        adb = self.tap(True, ['<hierarchy/>', '<hierarchy/>', dump(contacts.ALLOW)])
        self.assertEqual(len(adb.ran('input tap')), 1)

    def test_no_dialog_is_blocked_and_says_how_to_reset(self):
        with patched(FakeAdb()), mock.patch.object(contacts, '_dump', return_value='<hierarchy/>'), self.assertRaises(tools.Blocked) as ctx:
            contacts.tap_dialog(S, True, timeout=4, sleep=lambda s: None)
        self.assertIn('reset-permissions', str(ctx.exception))


class InsertTest(unittest.TestCase):
    def insert(self, people=PEOPLE, rows=ROWS):
        adb = ScriptAdb({'content query': rows})
        with patched(adb):
            contacts.insert(S, people)
        return adb

    def test_refuses_a_real_phone(self):
        adb = FakeAdb()
        with patched(adb), self.assertRaises(tools.Blocked):
            contacts.insert('R5CR12345', PEOPLE)
        self.assertEqual(adb.calls, [])

    def test_starts_clean_then_inserts_tagged_raw_contacts_then_names_and_numbers(self):
        adb = self.insert()
        self.assertTrue(adb.calls[0].startswith('shell content delete'))  # 앞 실행의 찌꺼기부터
        first, second = adb.scripts
        self.assertEqual(first.count('raw_contacts --bind sourceid:s:e2e-'), 2)
        self.assertIn('raw_contact_id:i:41', second)
        self.assertIn('raw_contact_id:i:42', second)
        self.assertIn("'data1:s:테스트지인A'", second)
        self.assertEqual(second.count('vnd.android.cursor.item/phone_v2'), 3)  # 1 + 2
        self.assertIn("'data1:s:+82 10-5555-6666'", second)

    def test_scripts_are_removed_from_the_device(self):
        self.assertTrue(self.insert().ran(f'rm -f {contacts.REMOTE}'))

    def test_a_quote_in_a_value_is_refused_before_anything_runs(self):
        adb = ScriptAdb()
        with patched(adb), self.assertRaises(ValueError):
            contacts.insert(S, [("이'름", ('010-1111-2222',))])
        self.assertEqual(adb.calls, [])

    def test_provider_error_in_the_output_is_blocked(self):
        adb = ScriptAdb({'content query': ROWS, 'sh': 'java.lang.SecurityException: denied'})
        with patched(adb), self.assertRaises(tools.Blocked):
            contacts.insert(S, PEOPLE)

    def test_missing_raw_contact_ids_after_the_first_script_is_blocked(self):
        with patched(ScriptAdb({'content query': 'Row: 0 _id=41, sourceid=e2e-0000\n'})), self.assertRaises(tools.Blocked):
            contacts.insert(S, PEOPLE)


class RemoveTest(unittest.TestCase):
    def test_removes_only_tagged_contacts_as_a_sync_adapter_and_reports_what_is_left(self):
        adb = FakeAdb({'content query': ''})
        with patched(adb):
            self.assertEqual(contacts.remove_all(S), 0)
        cmd = adb.ran('content delete')[0]
        self.assertIn('caller_is_syncadapter=true', cmd)
        self.assertIn("sourceid LIKE 'e2e-%'", cmd)

    def test_leftovers_are_counted(self):
        with patched(FakeAdb({'content query': ROWS})):
            self.assertEqual(contacts.remove_all(S), 2)

    def test_delete_one_person_by_index(self):
        adb = FakeAdb()
        with patched(adb):
            contacts.delete_person(S, 1)
        self.assertIn("sourceid='e2e-0001'", adb.ran('content delete')[0])

    def test_context_manager_cleans_up_even_when_the_body_fails(self):
        # 권한 상태는 부르는 차례대로 — 줬더니 true(grant 확인), 끝에 껐더니 false(revoke 확인)
        adb = ScriptAdb({'content query': ROWS, 'dumpsys package': ['android.permission.READ_CONTACTS: granted=true',
                                                                     'android.permission.READ_CONTACTS: granted=false']})
        with patched(adb), self.assertRaises(RuntimeError):
            with contacts.on_device(S, PEOPLE, granted=True):
                raise RuntimeError('app failed')
        self.assertGreaterEqual(len(adb.ran('content delete')), 2)  # 시작 전 + 끝
        self.assertTrue(adb.ran('pm revoke'))  # 권한도 없던 상태로


class OnDeviceTest(unittest.TestCase):
    GRANTED = 'android.permission.READ_CONTACTS: granted=true'
    REVOKED = 'android.permission.READ_CONTACTS: granted=false'

    def test_notification_permission_is_given_before_the_body_so_its_dialog_cannot_steal_the_tap(self):
        # 앱은 로그인하면 알림 권한 창을 띄운다 — 같은 resource-id 의 버튼이라 PC 가 연락처 창 대신 알림 창을 누를 수 있다
        adb = ScriptAdb({'content query': ROWS, 'dumpsys package': [self.REVOKED]})
        seen = []
        with patched(adb):
            with contacts.on_device(S, PEOPLE, granted=False):
                seen.extend(adb.calls)
        grant = [i for i, c in enumerate(seen) if 'pm grant' in c and 'POST_NOTIFICATIONS' in c]
        revoke = [i for i, c in enumerate(seen) if 'pm revoke' in c and 'READ_CONTACTS' in c]
        self.assertTrue(grant and revoke)
        self.assertGreater(grant[0], revoke[-1])  # reset-permissions 가 알림 권한도 지우므로 연락처 권한을 맞춘 뒤에 준다

    def test_devices_without_the_notification_permission_still_run(self):
        def adb(serial, *args, check=True):
            if 'POST_NOTIFICATIONS' in ' '.join(args):
                raise tools.subprocess.CalledProcessError(1, 'adb')  # 안드로이드 12 이하
            return 'android.permission.READ_CONTACTS: granted=false' if 'dumpsys' in args else ''
        with patched(adb):
            with contacts.on_device(S, [], granted=False):
                pass

    def test_a_failing_cleanup_does_not_skip_the_permission_reset(self):
        calls = []

        def adb(serial, *args, check=True):
            line = ' '.join(args)
            calls.append(line)
            if 'content delete' in line and len([c for c in calls if 'content delete' in c]) > 1:  # 시작 청소는 지나고 끝 정리에서 터진다
                raise tools.subprocess.CalledProcessError(1, 'adb')
            return 'Row: 0 _id=41, sourceid=e2e-0000' if 'content query' in line else self.REVOKED
        with patched(adb), self.assertRaises(tools.subprocess.CalledProcessError) as ctx:
            with contacts.on_device(S, [], granted=False):
                raise RuntimeError('app failed')
        self.assertIsInstance(ctx.exception.__context__, RuntimeError)  # 본문 오류는 잃지 않고 이어 붙는다
        self.assertEqual(len([c for c in calls if 'pm revoke' in c]), 2, '시작에 한 번, 정리가 터져도 끝에 한 번 더')


class PeopleTest(unittest.TestCase):
    def test_numbers_never_repeat_so_201_people_stay_201_blocks(self):
        from e2e import area4_contacts
        numbers = [n for _ in range(6) for _, (n,) in area4_contacts.people(201)]
        self.assertEqual(len(numbers), len(set(numbers)))


if __name__ == '__main__':
    unittest.main()
