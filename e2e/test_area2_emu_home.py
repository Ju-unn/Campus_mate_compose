"""영역 2 에뮬 홈 가설 7개(area2_emu_home.py)의 PC 쪽 시험 — 에뮬 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 adb 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_emu_home`.

가짜 서버는 test_area2_time_device 의 [World](없는 열 · 표를 운영처럼 400 · 404 로 막는다)에 홈 요약(`/home/summary`)과
시험대학 활성 인원(원래 있던 [KEPT] 명 + 이번 실행 계정 중 active)만 더한다. 가짜 에뮬은 화면 크기 · 밀도 · 글자 배율 · 공유 창 목록을 흉내 낸다."""

import re
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

from e2e import area1, area2_emu_home as eh, area2_time_device as td, emu, tools
from e2e import test_area2_time_device as tt
from e2e.area1 import SEOUL
from e2e.test_area1_phone import CHROME, OURS
from e2e.tools import Blocked, Reply

EMU = 'emulator-5554'
CODE = 'K7QMX2'
CASES = ['E-HOME-20', 'E-HOME-21', 'E-HOME-22', 'E-HOME-30', 'E-HOME-31', 'E-HOME-32', 'E-HOME-33']
SHEET = 'topResumedActivity=ActivityRecord{2 u0 android/com.android.internal.app.ChooserActivity t9}'
COPY_UI = '<hierarchy><node text="복사" bounds="[100,200][300,240]" /></hierarchy>'
NO_COPY_UI = '<hierarchy><node text="카카오톡" bounds="[100,200][300,240]" /></hierarchy>'


def dump(*chooser_hashes):
    """`dumpsys activity activities` 의 모양 — 공유 창 기록은 같은 해시가 여러 줄에 나온다(작업 목록 · 맨 위 · 기록)."""
    lines = ['  * Task{aa #12 type=standard A=10150:io.github.juunn.campusmate}',
             '    * Hist #0: ActivityRecord{c0ffee u0 io.github.juunn.campusmate/.MainActivity t12}']
    for n, h in enumerate(chooser_hashes):
        record = f'ActivityRecord{{{h} u0 android/com.android.internal.app.ChooserActivity t13}}'
        lines += [f'  * Task{{bb #13 type=standard}}', f'    * Hist #{n}: {record}', f'    topResumedActivity={record}']
    return '\n'.join(lines)


class PureTest(unittest.TestCase):
    def test_days_until_counts_calendar_days_in_seoul_not_hours(self):
        now = tt.WED(23, 59)
        self.assertEqual(eh.days_until(now, tt.seoul(10, 12, 7)), 5)  # 시각 차이는 4일 7시간이다 — 달력 날짜로 센다
        self.assertEqual(eh.days_until(tt.MON(6, 0), tt.MON(7, 0)), 0)

    def test_date_label_is_month_and_day_without_zero_padding(self):
        self.assertEqual(eh.date_label(tt.seoul(10, 12, 7)), '10월 12일')
        self.assertEqual(eh.date_label(tt.seoul(1, 5, 7)), '1월 5일')

    def test_invite_text_is_the_share_text_of_lib_referral_invite_share(self):
        self.assertEqual(eh.invite_text(CODE), 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.')

    def test_chooser_count_is_the_number_of_distinct_chooser_records_not_the_number_of_lines(self):
        self.assertEqual(eh.chooser_count(dump()), 0)
        self.assertEqual(eh.chooser_count(dump('a1')), 1)  # 한 개가 세 줄에 나온다
        self.assertEqual(eh.chooser_count(dump('a1', 'b2')), 2)
        self.assertEqual(eh.chooser_count(''), 0)
        self.assertEqual(eh.chooser_count(None), 0)

    def test_chooser_count_reads_android_14_component_names_too(self):
        text = '* ActivityRecord{9f u0 com.android.intentresolver/.ChooserActivity t4}\n* ActivityRecord{9f u0 com.android.intentresolver/.ChooserActivity t4}'
        self.assertEqual(eh.chooser_count(text), 1)

    def test_is_chooser_looks_at_the_resumed_activity_name(self):
        self.assertTrue(eh.is_chooser(SHEET))
        self.assertTrue(eh.is_chooser('mResumedActivity: ActivityRecord{1 u0 android/com.android.internal.app.ResolverActivity t9}'))
        self.assertFalse(eh.is_chooser(OURS))
        self.assertFalse(eh.is_chooser(CHROME))

    def test_density_for_makes_the_width_exactly_the_wanted_dp(self):
        self.assertEqual(eh.density_for(1080, 360), 480)
        self.assertEqual(eh.density_for(1440, 360), 640)
        self.assertEqual(eh.density_for(1080, 411), 420)


class HomeWorld(tt.World):
    """World + 홈 요약 + 시험대학 활성 인원. [skew] 는 요약 API 가 DB 와 다르게 세는 고장을 흉내 낸다."""

    KEPT = 5  # 시험대학에 원래 있던 활성 계정(KEEP 등)

    def __init__(self):
        super().__init__()
        self.skew = 0
        self.on('GET', r'/home/summary', self.summary)

    def active(self):
        return self.KEPT + sum(1 for u in self.users if self.statuses.get(u['id'], 'active') == 'active')

    def _table(self, method, name, sent):
        if name == 'profiles' and method == 'GET':
            if sent['query'].get('select') == 'referral_code':  # 운영 profiles 에 있는 열 — 열 목록(World.COLUMNS)에는 없다
                return Reply(200, [{'referral_code': CODE}])
            if 'university_id' in sent['query']:
                # status=eq.active 가 없거나 다르면 탈퇴한 계정까지 센다 — 질의에서 그 조건이 빠지는 고장을 잡는다
                n = self.active() if sent['query'].get('status') == 'eq.active' else self.KEPT + len(self.users)
                return Reply(200, [{'id': f'p{i}'} for i in range(n)])
        return super()._table(method, name, sent)

    def summary(self, sent):
        opens = self.tables['universities'][0]['card_opens_at']
        cohort = {'first_card_at': opens, 'recruit_count': self.active() + self.skew} if opens else None
        return Reply(200, {'cohort': cohort})


class SeeingPhone(tt.AppPhone):
    """앱을 켜는 순간까지 adb 로 무엇을 했는지 남긴다 — 화면을 키운 뒤에 앱을 켜는지 본다."""

    test = None

    def __call__(self, midway=None, **job):
        self.adb_at_launch = list(self.test.adb_log)
        return super().__call__(midway, **job)


class EmuHomeBase(tt.DeviceBase):
    START = tt.WED(12)  # 2026-10-07 수요일 — 다음 월요일은 10월 12일(D-5)

    def setUp(self):
        patcher = mock.patch.object(tt, 'World', HomeWorld)
        patcher.start()
        self.addCleanup(patcher.stop)
        super().setUp()
        for patcher in (
            mock.patch.object(tools, 'adb_bytes', lambda serial, *args, check=False: self.ui.encode('utf-8')),
            mock.patch.object(emu, 'go_offline', lambda serial: self.net.append('off')),
            mock.patch.object(emu, 'go_online', lambda serial: self.net.append('on') or self.online),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def reset(self):
        super().reset()
        self.adb_log, self.ui, self.net, self.online = [], COPY_UI, [], True
        self.sheets, self.density, self.font, self.display_ignored = (), None, None, False

    def adb(self, serial, *args, check=True):
        line = ' '.join(args)
        self.adb_log.append(line)
        if line == 'shell wm size':
            return 'Physical size: 1080x2400\n'
        if line == 'shell wm density':
            return 'Physical density: 420\n' + (f'Override density: {self.density}\n' if self.density else '')
        if line == 'shell wm density reset':
            self.density = None
        elif line.startswith('shell wm density ') and not self.display_ignored:
            self.density = int(args[-1])
        if line == 'shell settings get system font_scale':
            return f'{self.font}\n' if self.font else 'null\n'
        if line.startswith('shell settings put system font_scale'):
            self.font = args[-1]
        if line.startswith('shell settings delete system font_scale'):
            self.font = None
        if line == 'shell dumpsys activity activities':
            return dump(*self.sheets)
        return super().adb(serial, *args, check=check)

    def emu_phone(self, *answers, **kw):
        kw.setdefault('serial', EMU)
        phone = SeeingPhone(self.world, *answers, **kw)
        phone.test = self
        return phone

    def tapped(self):
        return [line for line in self.adb_log if line.startswith('shell input tap')]


class RealPhoneTest(EmuHomeBase):
    def test_every_case_refuses_a_real_phone_before_any_account_or_write(self):
        for case in CASES:
            with self.subTest(case=case):
                phone = self.emu_phone(serial='R5CR12345')
                self.assertEqual(self.go(case, phone)[0], 'blocked')
                self.assertEqual((self.world.users, phone.jobs, self.opens_patches(), self.adb_log, self.net), ([], [], [], [], []))


class Home20Test(EmuHomeBase):
    def test_the_device_is_in_seoul_when_the_app_starts_and_the_zone_it_had_is_put_back(self):
        phone = self.emu_phone()
        self.assertEqual(self.go('E-HOME-20', phone)[0], 'pass')
        self.assertIn('shell service call alarm 3 s16 Asia/Seoul', phone.adb_at_launch)
        self.assertEqual(self.zone, 'GMT')

    def test_the_zone_is_put_back_when_the_app_blocks(self):
        self.assertEqual(self.go('E-HOME-20', self.emu_phone({'result': 'blocked', 'note': 'x'}))[0], 'blocked')
        self.assertEqual(self.zone, 'GMT')

    def test_a_zone_that_will_not_change_is_blocked_and_the_app_is_never_started(self):
        self.zone_stuck = True
        phone = self.emu_phone()
        result = self.go('E-HOME-20', phone)
        self.assertEqual(result[0], 'blocked')
        self.assertIn('시간대', result[1])
        self.assertEqual(phone.jobs, [])

    def test_the_job_carries_the_days_the_date_and_the_headcount_the_screen_must_show_and_the_school_is_put_back(self):
        phone = self.emu_phone()
        result = self.go('E-HOME-20', phone)
        self.assertEqual(result[0], 'pass', result)
        job = phone.jobs[0]
        self.assertEqual((job['days'], job['date']), (5, '10월 12일'))  # 수요일 10-07 → 월요일 10-12
        self.assertEqual(job['recruit'], HomeWorld.KEPT + 1)  # 이번 실행 계정 B 하나만 더 — 시험대학의 활성 수를 DB 에서 센 값
        self.assertEqual(job['today'], '2026-10-07')  # 기기 날짜가 PC 와 같은지 앱이 대조한다
        self.assertIn('token_hash', job)
        opens = datetime.fromisoformat(self.opens_patches()[0]).astimezone(SEOUL)
        self.assertEqual((opens.weekday(), opens.hour, opens.minute), (0, 7, 0))  # universities_card_opens_monday_0700 check
        self.assertGreater(opens, self.clock.now)
        self.assertIsNone(self.opens_patches()[-1])

    def test_the_headcount_is_the_database_count_so_a_summary_api_that_counts_otherwise_is_a_fail(self):
        self.world.skew = 1
        result = self.go('E-HOME-20', self.emu_phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('요약 API', result[1])

    def test_an_app_that_shows_other_text_is_a_fail_and_the_school_is_still_put_back(self):
        self.assertEqual(self.go('E-HOME-20', self.emu_phone({'result': 'fail', 'note': '"D-5" 0개'}))[0], 'fail')
        self.assertIsNone(self.opens_patches()[-1])

    def test_an_app_that_blocks_is_blocked_and_the_school_is_put_back(self):
        self.assertEqual(self.go('E-HOME-20', self.emu_phone({'result': 'blocked', 'note': '기기 시간대가 서울이 아님'}))[0], 'blocked')
        self.assertIsNone(self.opens_patches()[-1])


class Home21Test(EmuHomeBase):
    def test_the_today_tab_case_closes_the_school_logs_in_and_puts_the_school_back(self):
        phone = self.emu_phone()
        self.assertEqual(self.go('E-HOME-21', phone)[0], 'pass')
        self.assertEqual(len(phone.jobs), 1)
        self.assertIn('token_hash', phone.jobs[0])
        self.assertGreater(datetime.fromisoformat(self.opens_patches()[0]), self.clock.now)
        self.assertIsNone(self.opens_patches()[-1])

    def test_an_app_fail_is_a_fail(self):
        self.assertEqual(self.go('E-HOME-21', self.emu_phone({'result': 'fail', 'note': '카드 1장'}))[0], 'fail')


class Home22Test(EmuHomeBase):
    def test_three_leavers_plus_b_then_one_withdraws_between_two_launches_and_the_count_drops_by_one(self):
        phone = self.emu_phone()
        result = self.go('E-HOME-22', phone)
        self.assertEqual(result[0], 'pass', result)
        first, second = phone.jobs
        self.assertEqual(first['recruit'], HomeWorld.KEPT + 4)  # B + V 3명
        self.assertEqual(second['recruit'], HomeWorld.KEPT + 3)
        self.assertIn('token_hash', first)
        self.assertIs(second['fresh'], False)  # 같은 세션으로 강제 종료 → 재시작
        self.assertNotIn('token_hash', second)
        self.assertEqual(self.world.statuses['id-2'], 'withdrawn')  # id-1 = B, id-2 = 첫 V
        self.assertNotIn('withdrawn', [self.world.statuses.get(i) for i in ('id-1', 'id-3', 'id-4')])
        self.assertIsNone(self.opens_patches()[-1])

    def test_the_accounts_are_made_before_the_school_is_closed(self):
        self.world.on_link = lambda: self.assertEqual(self.opens_patches(), [])
        self.assertEqual(self.go('E-HOME-22', self.emu_phone())[0], 'pass')

    def test_the_case_gets_a_longer_limit_than_the_default_for_four_accounts_and_two_launches(self):
        self.assertGreaterEqual(tools.CASE_LIMITS['E-HOME-22'], 600)

    def test_a_withdrawal_that_did_not_lower_the_database_count_is_blocked_not_a_false_pass(self):
        with mock.patch.object(eh, '_set_status'):
            result = self.go('E-HOME-22', self.emu_phone())
        self.assertEqual(result[0], 'blocked')
        self.assertIn('N-1', result[1])
        self.assertIsNone(self.opens_patches()[-1])

    def test_a_summary_api_that_counts_wrongly_is_a_fail(self):
        self.world.skew = 2
        self.assertEqual(self.go('E-HOME-22', self.emu_phone())[0], 'fail')

    def test_a_restart_that_still_shows_the_old_count_is_a_fail_and_the_school_is_put_back(self):
        result = self.go('E-HOME-22', self.emu_phone({'result': 'pass'}, {'result': 'fail', 'note': '"8명" 0개'}))
        self.assertEqual(result[0], 'fail')
        self.assertIsNone(self.opens_patches()[-1])


class Home30Test(EmuHomeBase):
    def test_the_sheet_is_in_front_copy_is_tapped_and_the_clipboard_must_be_the_invite_text(self):
        phone = self.emu_phone({'result': 'pass', 'clipboard': eh.invite_text(CODE)}, top=SHEET)
        result = self.go('E-HOME-30', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.tapped(), ['shell input tap 200 220'])  # "복사" 칸의 가운데
        self.assertIn('token_hash', phone.jobs[0])
        self.assertIsNone(self.opens_patches()[-1])

    def test_another_clipboard_text_is_a_fail(self):
        for wrong in ('CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘. 하트 50개', None, ''):
            with self.subTest(clipboard=wrong):
                result = self.go('E-HOME-30', self.emu_phone({'result': 'pass', 'clipboard': wrong}, top=SHEET))
                self.assertEqual(result[0], 'fail')
                self.assertIn('클립보드', result[1])

    def test_the_app_still_in_front_means_no_sheet_so_fail_and_nothing_is_tapped(self):
        result = self.go('E-HOME-30', self.emu_phone({'result': 'pass', 'clipboard': eh.invite_text(CODE)}, top=OURS))
        self.assertEqual(result[0], 'fail')
        self.assertIn('공유 창이 안 뜸', result[1])
        self.assertEqual(self.tapped(), [])

    def test_a_sheet_without_a_copy_entry_is_blocked_and_closed_with_back(self):
        self.ui = NO_COPY_UI
        result = self.go('E-HOME-30', self.emu_phone(top=SHEET))
        self.assertEqual(result[0], 'blocked')
        self.assertIn('복사', result[1])
        self.assertIn('shell input keyevent KEYCODE_BACK', self.adb_log)
        self.assertIsNone(self.opens_patches()[-1])

    def test_the_account_code_is_read_from_the_profile_row_of_this_runs_account(self):
        reads = [s for s in self.world.sent if s['path'] == '/rest/v1/profiles' and s['query'].get('select') == 'referral_code']
        self.assertEqual(reads, [])  # 아직 안 돌렸다
        self.go('E-HOME-30', self.emu_phone({'result': 'pass', 'clipboard': eh.invite_text(CODE)}, top=SHEET))
        reads = [s for s in self.world.sent if s['path'] == '/rest/v1/profiles' and s['query'].get('select') == 'referral_code']
        self.assertEqual([r['query']['id'] for r in reads], ['eq.id-1'])


class Home31Test(EmuHomeBase):
    def test_the_network_is_cut_while_the_app_waits_and_always_turned_back_on(self):
        phone = self.emu_phone(top=OURS)
        result = self.go('E-HOME-31', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.net, ['off', 'on'])
        self.assertIsNone(self.opens_patches()[-1])

    def test_the_network_is_turned_back_on_even_when_the_app_blocks(self):
        self.assertEqual(self.go('E-HOME-31', self.emu_phone({'result': 'blocked', 'note': 'x'}, top=OURS))[0], 'blocked')
        self.assertEqual(self.net, ['off', 'on'])

    def test_the_network_is_turned_back_on_even_when_the_phone_blows_up(self):
        phone = self.emu_phone(top=OURS)
        with mock.patch.object(type(phone), '__call__', side_effect=ZeroDivisionError):
            with self.assertRaises(ZeroDivisionError):
                self.go('E-HOME-31', phone)
        self.assertEqual(self.net[-1], 'on')
        self.assertIsNone(self.opens_patches()[-1])

    def test_a_network_that_does_not_come_back_is_blocked_so_the_next_case_is_not_blamed(self):
        self.online = False
        result = self.go('E-HOME-31', self.emu_phone(top=OURS))
        self.assertEqual(result[0], 'blocked')
        self.assertIn('네트워크', result[1])

    def test_a_share_sheet_in_front_after_the_toast_is_a_fail(self):
        result = self.go('E-HOME-31', self.emu_phone(top=SHEET))
        self.assertEqual(result[0], 'fail')
        self.assertIn('공유 창', result[1])

    def test_an_app_fail_is_a_fail(self):
        self.assertEqual(self.go('E-HOME-31', self.emu_phone({'result': 'fail', 'note': '토스트 0개'}, top=OURS))[0], 'fail')


class Home32Test(EmuHomeBase):
    def test_exactly_one_sheet_after_two_quick_taps_is_a_pass_and_back_closes_it(self):
        self.sheets = ('a1',)
        phone = self.emu_phone()
        result = self.go('E-HOME-32', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('shell input keyevent KEYCODE_BACK', self.adb_log)
        self.assertIn('token_hash', phone.jobs[0])
        self.assertIsNone(self.opens_patches()[-1])

    def test_two_sheets_is_a_fail_and_both_are_named_in_the_note(self):
        self.sheets = ('a1', 'b2')
        result = self.go('E-HOME-32', self.emu_phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('2개', result[1])

    def test_no_sheet_is_a_fail_and_back_is_not_pressed_because_it_would_leave_the_app(self):
        result = self.go('E-HOME-32', self.emu_phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('0개', result[1])
        self.assertNotIn('shell input keyevent KEYCODE_BACK', self.adb_log)

    def test_the_taps_are_made_by_the_app_so_the_pc_taps_nothing(self):
        self.sheets = ('a1',)
        self.go('E-HOME-32', self.emu_phone())
        self.assertEqual(self.tapped(), [])  # adb 는 느려 0.2초 간격을 못 맞춘다


class Home33Test(EmuHomeBase):
    def test_the_device_is_in_seoul_when_the_app_starts_and_the_zone_it_had_is_put_back(self):
        phone = self.emu_phone()
        self.assertEqual(self.go('E-HOME-33', phone)[0], 'pass')
        self.assertIn('shell service call alarm 3 s16 Asia/Seoul', phone.adb_at_launch)
        self.assertEqual(self.zone, 'GMT')

    def test_the_screen_is_made_360dp_and_1_3x_before_the_app_starts_and_put_back_after(self):
        phone = self.emu_phone()
        result = self.go('E-HOME-33', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertIn('shell wm density 480', phone.adb_at_launch)  # 1080px ÷ 360dp = 3x = 480dpi
        self.assertIn('shell settings put system font_scale 1.3', phone.adb_at_launch)
        self.assertEqual((self.density, self.font), (None, None))
        self.assertIsNone(self.opens_patches()[-1])
        job = phone.jobs[0]
        self.assertEqual((job['font_scale'], job['width_dp'], job['date']), (1.3, 360, '10월 12일'))  # 앱이 기기 설정이 먹었는지 대조한다

    def test_the_display_is_put_back_even_when_the_app_fails_or_the_phone_blows_up(self):
        self.assertEqual(self.go('E-HOME-33', self.emu_phone({'result': 'fail', 'note': '넘침'}))[0], 'fail')
        self.assertEqual((self.density, self.font), (None, None))
        phone = self.emu_phone()
        with mock.patch.object(type(phone), '__call__', side_effect=ZeroDivisionError):
            with self.assertRaises(ZeroDivisionError):
                self.go('E-HOME-33', phone)
        self.assertEqual((self.density, self.font), (None, None))

    def test_the_font_scale_that_was_set_before_is_written_back_not_deleted(self):
        self.font = '1.15'
        self.go('E-HOME-33', self.emu_phone())
        self.assertEqual(self.font, '1.15')

    def test_a_density_that_did_not_take_is_blocked_and_still_reset(self):
        self.display_ignored = True
        phone = self.emu_phone()
        result = self.go('E-HOME-33', phone)
        self.assertEqual(result[0], 'blocked')
        self.assertIn('밀도', result[1])
        self.assertEqual(phone.jobs, [])  # 앱을 켜지 않았다
        self.assertIn('shell wm density reset', self.adb_log)
        self.assertIsNone(self.font)

    def test_the_helper_refuses_a_real_phone_without_touching_it(self):
        with self.assertRaises(Blocked):
            with eh.display_big('R5CR12345', 1.3, 360):
                pass
        self.assertEqual(self.adb_log, [])

    def test_a_screen_size_that_cannot_be_read_is_blocked_before_anything_is_changed(self):
        with mock.patch.object(tools, 'adb', lambda serial, *args, check=True: ''):
            with self.assertRaises(Blocked):
                with eh.display_big(EMU, 1.3, 360):
                    pass


class SafetyNetTest(EmuHomeBase):
    def test_every_case_ends_blocked_or_fail_when_the_server_is_down(self):
        down = HomeWorld()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down):
            for case in CASES:
                result = area1.attempt_phone(self.run, case, self.emu_phone(top=OURS))
                self.assertIn(result[0], ('blocked', 'fail'), case)

    def test_every_write_stays_inside_this_runs_accounts_and_the_test_school(self):
        for case in CASES:
            world = HomeWorld()
            self.reset()
            self.world = world
            self.sheets = ('a1',)
            with mock.patch.object(tools, 'call', world):
                self.go(case, self.emu_phone({'result': 'pass', 'clipboard': eh.invite_text(CODE)}, top=SHEET))
            made = {u['id'] for u in world.users}
            self.assertTrue(made, case)
            for sent in world.sent:
                if sent['method'] not in ('POST', 'PATCH', 'DELETE') or not sent['path'].startswith('/rest/v1/'):
                    continue
                table = sent['path'].split('/')[-1]
                if table == 'universities':
                    self.assertEqual(sent['query'].get('id'), 'eq.U', (case, sent))
                elif table == 'profiles' and sent['method'] == 'POST':  # 계정 공장이 넣는 프로필 행 — 본문의 id 가 주인
                    rows = sent['body'] if isinstance(sent['body'], list) else [sent['body']]
                    self.assertTrue({r['id'] for r in rows} <= made, (case, sent))
                elif table == 'profiles':
                    self.assertIn(sent['query']['id'][3:], made, (case, sent))
                else:
                    rows = sent['body'] if isinstance(sent['body'], list) else [sent['body']]
                    owners = {r[k] for r in rows if isinstance(r, dict) for k in ('owner_id', 'profile_id') if k in r}
                    owners |= {sent['query'][k][3:] for k in ('owner_id', 'profile_id') if k in sent['query']}
                    self.assertTrue(owners <= made, (case, sent))


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundle_is_the_seven_cases_in_number_order_and_all_are_phone_cases(self):
        self.assertEqual(area1.BUNDLES['area2-emu-home'], CASES)
        for case in CASES:
            self.assertIs(area1.PHONE[case], eh.PHONE[case], case)

    def test_main_registers_the_module_and_none_is_an_api_case(self):
        from e2e import __main__ as main
        self.assertIn('from e2e import area2_emu_home', Path(main.__file__).read_text(encoding='utf-8'))
        self.assertEqual(main.BUNDLES['area2-emu-home'], CASES)
        self.assertFalse(set(CASES) & set(main.API_CASES))

    def test_no_case_number_of_the_other_emulator_bundle_is_taken(self):
        theirs = 'E-CARD-41 E-CARD-45 E-CARD-86 E-POLL-02 E-POLL-04 E-POLL-05 E-POLL-06 E-POLL-28 E-REF-07 E-REF-08 E-REF-17'.split()
        self.assertFalse(set(theirs) & set(eh.PHONE))

    def test_the_app_has_every_number_and_reads_every_key_the_pc_sends(self):
        dart = self.dart('area2_emu_home.dart')
        for case in CASES:
            self.assertRegex(dart, rf"(?m)^  '{case}':", case)
        for key in ('days', 'date', 'recruit', 'today', 'font_scale', 'width_dp'):
            self.assertIn(f"job['{key}']", dart, key)

    def test_e2e_test_merges_the_app_cases(self):
        main = self.dart('e2e_test.dart')
        self.assertIn("import 'area2_emu_home.dart';", main)
        self.assertIn('...area2EmuHomeCases', main)

    def test_the_app_side_changes_no_lib_code_and_uses_the_texts_of_the_screen(self):
        dart = self.dart('area2_emu_home.dart')
        for text in ('우리 학교 첫 카드까지', '현재 모집 인원', '친구에게 초대 링크 보내기', '네트워크 연결을 확인해 주세요'):
            self.assertIn(text, dart)
            self.assertIn(text, (tools.ROOT / 'frontend' / 'lib').joinpath('home/view/cohort_wait_view.dart').read_text(encoding='utf-8')
                          + (tools.ROOT / 'frontend' / 'lib' / 'common' / 'failure.dart').read_text(encoding='utf-8'))

    def test_the_new_files_use_crlf_like_their_neighbours(self):
        for path in ('e2e/area2_emu_home.py', 'e2e/test_area2_emu_home.py', 'frontend/integration_test/area2_emu_home.dart'):
            raw = (tools.ROOT / path).read_bytes()
            self.assertEqual(raw.count(b'\n'), raw.count(b'\r\n'), path)


if __name__ == '__main__':
    unittest.main()
