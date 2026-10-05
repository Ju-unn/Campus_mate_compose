"""영역 3 폰 A 한 대 4차(E-CHAT-45 · 46 · 47 · 48 · 49 · 56 — 매칭 시각을 과거로 옮긴 방의 14f 시트)의 PC 쪽 시험 —
폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area3_phone4`.

가짜 서버는 e2e/test_area3.py 의 Fake, 가짜 앱은 test_area3_phone.py 의 App(47 은 멈춤을 흉내 내는 MidwayApp).
가짜 서버는 앱이 쓰는 행을 저절로 만들지 않으므로 "앱이 나갔다 · 저장했다" 는 시험이 가짜 앱 안에서 행을 직접 바꿔 흉내 낸다.
profile_private 는 계정 공장이 안 만들어 시험이 [private] 한 줄로 GET 에 답한다.
계정은 만든 순서대로 id-1(폰 계정) · id-2(상대), 토큰은 tok-1 · tok-2 …
"""

import re
import unittest
from datetime import datetime, timedelta, timezone

from e2e import area1, area3, area3_phone4, tools
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, Phone2
from e2e.tools import Reply

CASES = ['E-CHAT-45', 'E-CHAT-46', 'E-CHAT-47', 'E-CHAT-48', 'E-CHAT-49', 'E-CHAT-56']
GATE_OVER = '응답 기한이 지나 이 대화는 종료됐어요'
ENDING = '이 대화는 23시간 뒤 종료돼요'
DAY = timedelta(hours=24)


def iso(at):
    return at.isoformat().replace('+00:00', 'Z')  # 앱(Dart toUtc().toIso8601String())이 말하는 모양


def label(seconds):
    seconds = int(seconds)
    return f'{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}'


def left_line(nickname):
    return f'{nickname}님이 채팅방을 나갔어요'  # chat/repository.py:183


class Gate4Base(Phone2):
    def setUp(self):
        super().setUp()
        self.private = {'kakao_id': 'e2e1'}  # 폰 계정의 DB 카카오톡 아이디
        self.fake.on('GET', r'/rest/v1/profile_private', lambda sent: Reply(200, [dict(self.private)]))

    def patched(self, index=0):
        """PC 가 [index] 번째 매칭에 옮겨 적은 created_at(옮기지 않았으면 None)."""
        value = self.fake.tables['matches'][index].get('created_at')
        return datetime.fromisoformat(value) if value else None

    def age(self, index=0):
        return (datetime.now(timezone.utc) - self.patched(index)).total_seconds()

    def base_job(self):
        return {'token_hash': 'h', 'nickname': self.nick(2)}

    def mine(self):
        return self.rows('match_participants', profile_id='id-1')[0]


# ── E-CHAT-45 ────────────────────────────────────────────────────────────────────────────────────────

class Chat45Test(Gate4Base):
    def answer(self, job, off=0, **override):
        """앱이 방을 열어 시트의 아이디 · 남은 시간을 읽었다 — 남은 시간은 PC 가 옮긴 created_at + 48시간 − 그 순간(+ [off]초)."""
        now = datetime.now(timezone.utc)
        left = (self.patched() + 2 * DAY - now).total_seconds() + off
        return {**said(sheet=True, sheet_id=self.private['kakao_id'], countdown=label(left), shown_at=iso(now)), **override}

    def test_pass_path_opens_a_room_older_than_24_hours_by_one_minute(self):
        (result, note), app = self.case('E-CHAT-45', self.answer)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [self.base_job()])
        self.assertAlmostEqual(self.age(), 24 * 3600 + 60, delta=30)  # 지금 − 24시간 − 1분
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_the_sheet_must_show_and_carry_the_db_kakao_id(self):
        for override in ({'sheet': False}, {'sheet': None}, {'sheet_id': 'other'}, {'sheet_id': None}, {'sheet_id': '—'}):
            (result, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, **override))
            self.assertEqual(result, 'fail', override)

    def test_a_missing_sheet_names_the_title_a_wrong_id_names_both_values(self):
        (_, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, sheet=False))
        self.assertIn('시트', note)
        (_, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, sheet_id='zzz'))
        self.assertIn('zzz', note)
        self.assertIn('e2e1', note)

    def test_the_countdown_is_checked_within_a_minute_of_what_the_phone_clock_allows(self):
        (result, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, off=50))
        self.assertEqual(result, 'pass', note)  # 시나리오 ±1분
        (result, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, off=-50))
        self.assertEqual(result, 'pass', note)
        for off in (70, -70, 3600):
            (result, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, off=off))
            self.assertEqual(result, 'fail', off)
            self.assertIn('남은 시간', note)

    def test_a_countdown_the_app_did_not_say_or_garbled_is_a_fail(self):
        for override in ({'countdown': None}, {'countdown': '곧'}, {'countdown': '23:59'}, {'shown_at': None}, {'shown_at': '어제'}):
            (result, _), _ = self.case('E-CHAT-45', lambda job: self.answer(job, **override))
            self.assertEqual(result, 'fail', override)

    def test_the_countdown_is_not_the_scenario_literal_when_the_app_took_long(self):
        """앱이 방을 여는 데 40초 걸렸다면 남은 시간은 23:58:20 — 리터럴 23:59:00±1분 이 아니라 앱 시계로 계산한다(3분 걸리면 리터럴은 어긋난다)."""
        (result, note), _ = self.case('E-CHAT-45', lambda job: self.answer(job, off=-180))
        self.assertEqual(result, 'fail')
        self.assertIn('남은 시간', note)


# ── E-CHAT-46 ────────────────────────────────────────────────────────────────────────────────────────

class Chat46Test(Gate4Base):
    def answer(self, job, **override):
        return {**said(sheet=True, swipes=1, banners=[ENDING], again=True), **override}

    def test_pass_path(self):
        (result, note), app = self.case('E-CHAT-46', self.answer)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [self.base_job()])
        self.assertAlmostEqual(self.age(), 24 * 3600 + 60, delta=30)
        self.assert_all_home()

    def test_a_second_swipe_is_fine_but_the_note_says_it(self):
        (result, note), _ = self.case('E-CHAT-46', lambda job: self.answer(job, swipes=2))
        self.assertEqual(result, 'pass')
        self.assertIn('2번째', note)  # 첫 밀기가 안 먹었다는 기록(손잡이를 잡고 다시)

    def test_each_wrong_sight_is_a_fail_and_names_it(self):
        wrong = {
            'sheet': ({'sheet': False}, '시트'),
            'swipes': ({'swipes': 0}, '밀어'),
            'banner none': ({'banners': []}, '배너'),
            'banner hours': ({'banners': ['이 대화는 22시간 뒤 종료돼요']}, '22시간'),
            'banner twice': ({'banners': [ENDING, ENDING]}, '배너'),
            'again': ({'again': False}, '다시'),
        }
        for name, (override, word) in wrong.items():
            (result, note), _ = self.case('E-CHAT-46', lambda job: self.answer(job, **override))
            self.assertEqual(result, 'fail', name)
            self.assertIn(word, note, name)

    def test_an_app_that_says_nothing_about_the_banner_or_the_second_visit_is_a_fail(self):
        for key in ('banners', 'again', 'swipes', 'sheet'):
            (result, _), _ = self.case('E-CHAT-46', lambda job: {k: v for k, v in self.answer(job).items() if k != key})
            self.assertEqual(result, 'fail', key)

    def test_closing_the_sheet_by_swipe_must_not_accept(self):
        def accepted(job):
            self.text_sent('수락', kind='trust_accept')
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-46', accepted)
        self.assertEqual(result, 'fail')
        self.assertIn('수락', note)


# ── E-CHAT-47 ────────────────────────────────────────────────────────────────────────────────────────

class EdgeApp(MidwayApp):
    """멈추기 직전의 매칭 행을 [before] 에 남긴다 — 방을 열기 전에는 created_at 을 안 옮겼다는 증거."""

    def __init__(self, answer, events, fake):
        super().__init__(answer, 'move', events)
        self.fake, self.before = fake, None

    def __call__(self, midway=None, **job):
        self.before = [dict(row) for row in self.fake.tables.get('matches', [])]
        return super().__call__(midway, **job)


class Chat47Test(Gate4Base):
    def answer(self, job, off=0, **override):
        """앱이 방을 연 시각(앱 시계)과 시트가 뜰 때까지 걸린 ms — 기대는 PC 가 옮긴 created_at + 24시간 − 연 시각(+ [off]초)."""
        opened = datetime.now(timezone.utc)
        expected = (self.patched() + DAY - opened).total_seconds()
        return {**said(open_at=iso(opened), sheet_at_open=False, sheet=True, sheet_ms=round((expected + off) * 1000)), **override}

    def run_case(self, answer=None):
        """(결과, 메모, 앱, 멈춤 기록)."""
        events = []
        app = EdgeApp(answer or self.answer, events, self.fake)
        (result, note), _ = self.case('E-CHAT-47', None, app)
        return result, note, app, events

    def test_pass_path_moves_the_room_while_the_app_waits_on_the_list(self):
        result, note, app, events = self.run_case()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [self.base_job()])
        self.assertEqual(events, ['step', 'go'])
        self.assertEqual([row.get('created_at') for row in app.before], [None])  # 멈춘 순간엔 아직 안 옮김 — 방은 방금 만든 것
        self.assertAlmostEqual(self.age(), 23 * 3600 + 59 * 60, delta=30)  # 지금 − 23시간 59분
        self.assert_all_home()

    def test_the_note_carries_the_seconds_between_opening_and_the_sheet(self):
        result, note, _, _ = self.run_case()
        self.assertEqual(result, 'pass', note)
        self.assertRegex(note, r'방을 연 뒤 \d+(\.\d+)?초')

    def test_a_sheet_within_five_seconds_of_the_boundary_passes_and_beyond_fails(self):
        for off in (-3, 3):
            result, note, _, _ = self.run_case(lambda job: self.answer(job, off=off))
            self.assertEqual(result, 'pass', (off, note))
        for off in (-7, 7, 30):
            result, note, _, _ = self.run_case(lambda job: self.answer(job, off=off))
            self.assertEqual(result, 'fail', off)
            self.assertIn('경계', note)

    def test_a_sheet_already_up_when_the_room_opened_is_a_fail(self):
        result, note, _, _ = self.run_case(lambda job: self.answer(job, sheet_at_open=True))
        self.assertEqual(result, 'fail')
        self.assertIn('이미', note)

    def test_a_sheet_that_never_comes_is_a_fail(self):
        result, note, _, _ = self.run_case(lambda job: self.answer(job, sheet=False, sheet_ms=None))
        self.assertEqual(result, 'fail')
        self.assertIn('90초', note)

    def test_an_app_that_leaves_out_the_times_is_a_fail(self):
        for key in ('open_at', 'sheet_ms', 'sheet', 'sheet_at_open'):
            result, _, _, _ = self.run_case(lambda job: {k: v for k, v in self.answer(job).items() if k != key})
            self.assertEqual(result, 'fail', key)

    def test_an_app_that_never_stops_leaves_the_room_unmoved_and_is_a_fail(self):
        plain = said(open_at=iso(datetime.now(timezone.utc)), sheet_at_open=False, sheet=True, sheet_ms=60000)
        (result, note), _ = self.case('E-CHAT-47', plain)  # midway 를 안 부르는 앱
        self.assertEqual(result, 'fail')
        self.assertIn('멈추', note)


# ── E-CHAT-48 ────────────────────────────────────────────────────────────────────────────────────────

class Chat48Test(Gate4Base):
    def answer(self, job, saved=True, **override):
        before = self.private['kakao_id']
        if saved:
            self.private['kakao_id'] = job['value']  # 앱이 16e-1 에서 저장했다
        return {**said(sheet_before=before, sheet_after=job['value']), **override}

    def test_pass_path_sends_the_stored_id_and_a_fresh_value(self):
        (result, note), app = self.case('E-CHAT-48', self.answer)
        self.assertEqual(result, 'pass', note)
        job = app.jobs[0]
        self.assertEqual({k: v for k, v in job.items() if k != 'value'}, {**self.base_job(), 'kakao': 'e2e1'})
        self.assertRegex(job['value'], r'^e2e\d+c[0-9a-f]{6}$')  # 형식 제약 없음 — 영문 · 숫자만
        self.assertNotEqual(job['value'], 'e2e1')
        self.assertAlmostEqual(self.age(), 24 * 3600 + 60, delta=30)
        self.assert_all_home()

    def test_the_new_value_differs_every_run(self):
        tails = set()
        for _ in range(3):
            self.private['kakao_id'] = 'e2e1'
            tails.add(re.search(r'c([0-9a-f]{6})$', self.case('E-CHAT-48', self.answer)[1].jobs[0]['value'])[1])
        self.assertEqual(len(tails), 3)  # 계정 번호가 달라서가 아니라 무작위 꼬리가 달라서

    def test_the_db_must_hold_the_new_value(self):
        (result, note), _ = self.case('E-CHAT-48', lambda job: self.answer(job, saved=False))
        self.assertEqual(result, 'fail')
        self.assertIn('kakao_id', note)

        def other(job):
            said_ = self.answer(job)
            self.private['kakao_id'] = 'zzz'
            return said_
        (result, note), _ = self.case('E-CHAT-48', other)
        self.assertEqual(result, 'fail')
        self.assertIn('zzz', note)

    def test_the_sheet_must_show_the_old_id_before_and_the_new_one_after(self):
        wrong = {
            'old after': lambda job: self.answer(job, sheet_after='e2e1'),
            'none after': lambda job: self.answer(job, sheet_after=None),
            'other before': lambda job: self.answer(job, sheet_before='zzz'),
            'no before': lambda job: self.answer(job, sheet_before=None),
        }
        for name, answer in wrong.items():
            self.private['kakao_id'] = 'e2e1'
            (result, note), _ = self.case('E-CHAT-48', answer)
            self.assertEqual(result, 'fail', name)
            self.assertIn('시트', note, name)

    def test_an_empty_stored_id_is_blocked_not_a_fail(self):
        self.private['kakao_id'] = None
        (result, note), app = self.case('E-CHAT-48', self.answer)
        self.assertEqual(result, 'blocked')
        self.assertEqual(app.jobs, [])


# ── E-CHAT-49 ────────────────────────────────────────────────────────────────────────────────────────

class Chat49Test(Gate4Base):
    def answer(self, job, leave=True, line=True, **override):
        """앱이 "거절하고 나가기" → "나가기" 를 눌러 서버가 나가기를 처리한 것처럼 — left_at 과 나감 줄."""
        if leave:
            self.mine()['left_at'] = '2026-10-05T03:00:00+00:00'
        if line:
            self.text_sent(left_line(self.nick(1)), kind='left')
        return {**said(sheet=True, confirm=True, row_gone=True), **override}

    def test_pass_path(self):
        (result, note), app = self.case('E-CHAT-49', self.answer)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [self.base_job()])
        self.assertAlmostEqual(self.age(), 24 * 3600 + 60, delta=30)
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_each_wrong_sight_is_a_fail(self):
        for override in ({'sheet': False}, {'confirm': False}, {'row_gone': False}, {'row_gone': None}):
            (result, _), _ = self.case('E-CHAT-49', lambda job: self.answer(job, **override))
            self.assertEqual(result, 'fail', override)

    def test_left_at_is_required_and_the_trust_response_stays_null(self):
        (result, note), _ = self.case('E-CHAT-49', lambda job: self.answer(job, leave=False))
        self.assertEqual(result, 'fail')
        self.assertIn('left_at', note)

        def accepted(job):
            self.mine()['trust_response'] = 'accept'
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-49', accepted)
        self.assertEqual(result, 'fail')
        self.assertIn('trust_response', note)

    def test_the_partner_side_is_untouched_and_gets_exactly_one_left_line(self):
        (result, note), _ = self.case('E-CHAT-49', lambda job: self.answer(job, line=False))
        self.assertEqual(result, 'fail')
        self.assertIn('나감 줄', note)

        def twice(job):
            self.text_sent(left_line(self.nick(1)), kind='left')
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-49', twice)
        self.assertEqual(result, 'fail')
        self.assertIn('나감 줄', note)

        def wrong_words(job):
            self.text_sent('누군가 나갔어요', kind='left')
            return self.answer(job, line=False)
        (result, note), _ = self.case('E-CHAT-49', wrong_words)
        self.assertEqual(result, 'fail')
        self.assertIn('누군가 나갔어요', note)

        def partner_left_too(job):
            self.rows('match_participants', profile_id='id-2')[0]['left_at'] = '2026-10-05T03:00:00+00:00'
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-49', partner_left_too)
        self.assertEqual(result, 'fail')
        self.assertIn('상대', note)

    def test_a_trust_accept_line_means_the_wrong_button_was_pressed(self):
        def accept_line(job):
            self.text_sent('수락', kind='trust_accept')
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-49', accept_line)
        self.assertEqual(result, 'fail')
        self.assertIn('수락', note)


# ── E-CHAT-56 ────────────────────────────────────────────────────────────────────────────────────────

class Chat56Test(Gate4Base):
    def answer(self, job, **override):
        return {**said(sheet=True, error=GATE_OVER, error_now=GATE_OVER), **override}

    def test_pass_path_opens_a_room_older_than_48_hours_and_leaves_the_batch_alone(self):
        (result, note), app = self.case('E-CHAT-56', self.answer)
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [self.base_job()])
        self.assertAlmostEqual(self.age(), 48 * 3600 + 60, delta=30)  # 지금 − 48시간 − 1분
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_the_note_says_when_the_error_line_vanished_after_showing(self):
        (result, note), _ = self.case('E-CHAT-56', lambda job: self.answer(job, error_now=None))
        self.assertEqual(result, 'pass')  # 처음 뜬 문구로 판정 — 끝 값은 기록만
        self.assertIn('사라', note)
        (result, note), _ = self.case('E-CHAT-56', self.answer)
        self.assertEqual((result, note), ('pass', ''))

    def test_the_words_must_be_the_scenario_not_the_server_raw_text(self):
        for error in (None, '응답 기한이 지났어요', '종료된 대화예요', '네트워크 연결을 확인해 주세요'):
            (result, note), _ = self.case('E-CHAT-56', lambda job: self.answer(job, error=error))
            self.assertEqual(result, 'fail', error)
            self.assertIn('문구', note)

    def test_no_sheet_means_the_accept_button_was_never_pressed(self):
        (result, note), _ = self.case('E-CHAT-56', lambda job: self.answer(job, sheet=False))
        self.assertEqual(result, 'fail')
        self.assertIn('시트', note)

    def test_nothing_is_saved_by_a_late_accept(self):
        def accepted(job):
            self.mine()['trust_response'] = 'accept'
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-56', accepted)
        self.assertEqual(result, 'fail')
        self.assertIn('trust_response', note)

        def line(job):
            self.text_sent('수락', kind='trust_accept')
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-56', line)
        self.assertEqual(result, 'fail')
        self.assertIn('수락 줄', note)

        def passed(job):
            self.fake.tables['matches'][0]['trust_passed_at'] = '2026-10-05T03:00:00+00:00'
            return self.answer(job)
        (result, note), _ = self.case('E-CHAT-56', passed)
        self.assertEqual(result, 'fail')
        self.assertIn('trust_passed_at', note)


# ── 등록부 · 안전망 ──────────────────────────────────────────────────────────────────────────────────

class PermissionTest(Gate4Base):
    def test_every_case_grants_before_and_revokes_after(self):
        self.assertEqual(list(area3_phone4.PHONE4), CASES)
        for name in CASES:
            self.assertTrue(hasattr(area3_phone4.PHONE4[name], '__wrapped__'), name)
            self.assertIs(area1.PHONE[name], area3_phone4.PHONE4[name], name)
        self.case('E-CHAT-46', said(sheet=True, swipes=1, banners=[ENDING], again=True))
        self.assertEqual([p[0] for p in self.perm], ['grant', 'revoke'])


class RegistryTest(Gate4Base):
    """이 시험 모듈이 area3_phone4 를 직접 import 하므로 __main__ 의 import 가 빠져도 BUNDLES 는 차 보인다 —
    그래서 __main__.py 원문과 Dart 원문을 직접 읽어 등록 줄을 본다(형제 RegistryTest 와 같은 방법)."""

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def source(self):
        return (tools.ROOT / 'e2e' / 'area3_phone4.py').read_text(encoding='utf-8')

    def test_main_imports_the_module_and_runs_the_bundle_through_area1_phone(self):
        from e2e import __main__ as main
        self.assertRegex((tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'), r'(?m)^from e2e import area3_phone4\b')  # 주석 처리된 줄은 안 센다
        self.assertEqual(area3.BUNDLES['area3-phone-4'], CASES)
        self.assertEqual(main.BUNDLES['area3-phone-4'], CASES)
        self.assertFalse(set(CASES) & set(main.API_CASES))
        self.assertLessEqual(set(CASES), set(area1.PHONE))
        for other in ('area3-phone-1', 'area3-phone-2', 'area3-phone-3'):
            self.assertFalse(set(CASES) & set(main.BUNDLES.get(other, [])), other)

    def test_the_app_part_is_declared_and_merged_into_the_case_map_like_its_siblings(self):
        part = self.dart('area3_b4.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), CASES)
        main = self.dart('area3.dart')
        self.assertRegex(main, r"(?m)^part 'area3_b4\.dart';")
        self.assertRegex(main, r'(?m)^  \.\.\.area3Cases4,')  # 주석 처리된 줄은 안 센다
        self.assertLess(main.index('...area3CasesSafe,'), main.index('...area3Cases4,'))  # area3Cases 맵 끝에서 합친다
        if '...area3Cases3,' in main:  # 3차(E-CHAT-32)가 먼저 들어와 있으면 그 뒤
            self.assertLess(main.index('...area3Cases3,'), main.index('...area3Cases4,'))
        self.assertNotIn('area3Cases4', self.dart('e2e_test.dart'))  # e2e_test.dart 는 area3Cases 하나만 펼친다

    def function(self, case):
        """이 번호의 Dart 함수 본문 — area3Cases4 표에서 `'E-CHAT-45': _session(함수)` 의 함수."""
        dart = self.dart('area3_b4.dart')
        name = re.search(rf"'{case}': _session\((\w+)\)", dart)[1]
        return re.search(rf"^Future<[^\n]*> {name}\(.*?^}}", dart, re.S | re.M)[0]

    def test_each_app_function_reads_the_job_keys_its_case_sends(self):
        sent = {}
        for name in CASES:  # 가설마다 한 번씩 — 앱이 받는 일감의 키를 모은다
            self.private['kakao_id'] = 'e2e1'
            sent[name] = set(self.case(name, lambda job: said(), MidwayApp(lambda job: said(), 'move', []))[1].jobs[0])
        self.assertEqual({k for keys in sent.values() for k in keys}, {'token_hash', 'nickname', 'kakao', 'value'})
        self.assertEqual({n for n, keys in sent.items() if 'kakao' in keys}, {'E-CHAT-48'})
        for name, keys in sent.items():
            body = self.function(name)
            for key in keys - {'token_hash'}:
                self.assertIn(f"job['{key}']", body, (name, key))  # 다른 함수가 읽어도 이 가설의 앱은 못 받는다
        self.assertIn("job['token_hash']", self.dart('area3.dart'))  # 로그인은 _session 이 한다

    def test_each_app_function_says_the_keys_its_pc_case_reads(self):
        import inspect
        for name in CASES:
            source = inspect.getsource(area3_phone4.PHONE4[name].__wrapped__)
            if '_sheet_up(' in source:
                source += inspect.getsource(area3_phone4._sheet_up)
            keys = set(re.findall(r"said(?:\.get\(|\[)'(\w+)'", source))
            self.assertTrue(keys, name)
            body = self.function(name)
            for key in keys:
                self.assertIn(f"'{key}':", body, (name, key))

    def test_the_midway_case_stops_once_in_the_app_and_only_that_case_does(self):
        dart = self.dart('area3_b4.dart')
        self.assertEqual(len(re.findall(r"await step\('", dart)), 1)
        self.assertIn("await step('move');", dart)
        self.assertEqual(self.source().count('midway='), 1)  # PC 쪽도 한 가설뿐(E-CHAT-47)


if __name__ == '__main__':
    unittest.main()
