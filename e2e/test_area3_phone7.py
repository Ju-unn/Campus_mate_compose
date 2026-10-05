"""영역 3 밤 가설 E-CHAT-34 · E-CHAT-42 · E-REV-18(묶음 area3-phone-7)의 PC 쪽 시험. 세 가설은 영역 4 밤 판(area4_push_night)의
E-PUSH-33 · 86 · 52 와 같은 판이라 별칭으로 등록만 한다 — 새 로직 시험이 아니라 "별칭이 같은 판을 부른다 · 등록 줄 네 곳이 다 있다 · 서버 문구가 그대로다" 시험이다.
폰 · 운영 · gcloud 없이 영역 4 밤 시험의 가짜 세계(NightBase)를 그대로 쓴다. 저장소 루트에서 `python -m unittest e2e.test_area3_phone7`.
기대 표(ALIAS)는 이 시험이 따로 적는다 — 가설 코드가 읽는 표와 같은 곳에서 가져오지 않는다.
"""

import re
import subprocess
import sys
import unittest
from unittest import mock

from e2e import __main__ as cli
from e2e import area1, area3, area3_phone7, tools
from e2e import area4_push_night as night
from e2e.tools import Blocked
from e2e.test_area4_push_night import PARTNER, PUBLIC, REVIEW, TRUST, TUESDAY, WED, NightBase, TUE

ALIAS = {'E-CHAT-34': 'E-PUSH-33', 'E-CHAT-42': 'E-PUSH-86', 'E-REV-18': 'E-PUSH-52'}  # 영역 3 번호 → 같은 판인 영역 4 번호
TWO_STAGE = {'E-CHAT-42': '86', 'E-REV-18': '52'}  # 밤 단계 + 아침 단계가 있는 둘(상태 파일 night_<영역 4 번호>.json)
WANT = {'E-CHAT-42': [(PUBLIC, f'{PARTNER} 님의 프로필이 공개됐어요')], 'E-REV-18': [(REVIEW, f'{PARTNER} 님이 리뷰를 남겼어요')]}
BUNDLE = 'area3-phone-7'


def read(*parts):
    return tools.ROOT.joinpath(*parts).read_text(encoding='utf-8')


class RegistryTest(unittest.TestCase):
    """__main__.py · Dart 원문을 직접 읽어 등록 줄을 본다(형제 RegistryTest 와 같은 방법)."""

    def test_the_bundle_is_the_three_aliases_and_all_are_phone_cases(self):
        self.assertEqual(area3.BUNDLES[BUNDLE], list(ALIAS))
        for case in ALIAS:
            self.assertIn(case, area1.PHONE)
            self.assertNotIn(case, area3.CASES)  # area3-api 묶음이 그대로다
        self.assertEqual(len(area3.CASES), len(set(area3.CASES)))

    def test_the_runner_registers_the_bundle_and_never_treats_the_aliases_as_api_cases(self):
        self.assertEqual(cli.BUNDLES[BUNDLE], list(ALIAS))
        for case in ALIAS:
            self.assertNotIn(case, cli.API_CASES)

    def test_a_fresh_interpreter_that_only_imports_the_program_entry_sees_the_aliases(self):
        # 새 인터프리터로 — 이 시험 파일이 area3_phone7 을 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = ('from e2e import __main__ as m, area1; '
                 f'print(m.BUNDLES.get("{BUNDLE}"), all(c in area1.PHONE for c in {list(ALIAS)}))')
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{list(ALIAS)} True')

    def test_the_program_entry_imports_the_module_uncommented_after_the_area4_night_module(self):
        text = read('e2e', '__main__.py')
        mine = re.search(r'(?m)^from e2e import area3_phone7\b', text)
        self.assertTrue(mine, 'from e2e import area3_phone7 줄이 없거나 주석 처리됨')
        self.assertLess(re.search(r'(?m)^from e2e import area4_push_night\b', text).start(), mine.start())

    def test_the_limits_are_the_area4_ones_and_longer_than_the_default(self):
        for mine, theirs in ALIAS.items():
            self.assertEqual(tools.CASE_LIMITS[mine], tools.CASE_LIMITS[theirs], mine)
            self.assertGreater(tools.CASE_LIMITS[mine], tools.CASE_LIMIT, mine)

    def test_the_numbers_collide_with_no_other_bundle_and_never_with_their_own_target(self):
        for name, bundle in {**area1.BUNDLES, **area3.BUNDLES}.items():
            if name != BUNDLE:
                self.assertFalse(set(ALIAS) & set(bundle), name)
        self.assertFalse(set(ALIAS) & set(ALIAS.values()))
        self.assertNotIn(BUNDLE, area1.BUNDLES)

    def test_the_dart_piece_has_exactly_the_three_keys_each_the_area4_night_app_case(self):
        part = read('frontend', 'integration_test', 'area3_b7.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)': (.+),$", part, re.M),
                         [(case, "area1Cases['E-ONB-61']!") for case in ALIAS])  # 영역 4 밤 판 앱과 같은 동작(로그인해 홈, 3초)
        self.assertIn("area1Cases['E-ONB-61']", read('frontend', 'integration_test', 'area4_push_night.dart'))

    def test_the_dart_main_declares_the_part_and_merges_it_after_the_sixth_and_e2e_test_does_not_list_it(self):
        main = read('frontend', 'integration_test', 'area3.dart')
        self.assertRegex(main, r"(?m)^part 'area3_b7\.dart';")
        merge = re.search(r'(?m)^  \.\.\.area3Cases7,', main)
        self.assertTrue(merge, '...area3Cases7, 줄이 없거나 주석 처리됨')
        self.assertLess(re.search(r'(?m)^  \.\.\.area3Cases6,', main).start(), merge.start())
        self.assertNotIn('area3Cases7', read('frontend', 'integration_test', 'e2e_test.dart'))

    def test_the_app_keys_are_the_keys_the_pc_runs_and_the_pc_job_carries_only_the_token(self):
        part = read('frontend', 'integration_test', 'area3_b7.dart')
        self.assertEqual(set(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M)), set(ALIAS))
        self.assertEqual(set(area1.PHONE) & set(ALIAS), set(ALIAS))


class AliasRunTest(NightBase):
    """영역 3 번호로 불러도 영역 4 판이 돈다 — 같은 단계 함수, 같은 상태 파일, 두 번호 모두에 결과 기록."""

    def results(self):
        return {r['case']: r for r in self.run.records()}

    def test_34_runs_the_night_message_case_and_passes_with_the_token_login_only(self):
        (result, note), phone = self.alias('E-CHAT-34')
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + self.world.users[0]['email']}])
        sent = self.world.by('POST', '/chat/matches/')
        self.assertEqual(self.arrived(0, {PARTNER}), [(PARTNER, sent[0]['body']['body'])])  # 새 메시지는 밤에도 온다
        self.assertEqual(self.pending(), [])
        self.assertEqual(self.batches, [], 'E-CHAT-34 는 chat-gate 를 부르지 않는다')
        self.assertEqual(list(self.run.out.glob('night_*.json')), [], 'E-CHAT-34 는 단계가 하나라 상태 파일이 없다')

    def test_34_in_daytime_is_blocked_before_any_account_is_made(self):
        self.clock.now = TUE(12)
        (result, note), phone = self.alias('E-CHAT-34')
        self.assertEqual((result, note), ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual((self.world.users, phone.jobs, self.batches), ([], [], []))

    def night_contract(self, case):
        number = TWO_STAGE[case]
        (result, note), phone = self.alias(case)
        self.assertEqual(result, 'blocked', (result, note))
        self.assertEqual(note, night.night_note(number))
        self.assertEqual(self.state(number)['night_date'], TUESDAY)
        self.assertEqual(sorted(p.name for p in self.run.out.glob('night_*.json')), [f'night_{number}.json'], '상태 파일은 영역 4 번호 것 하나뿐')
        self.assertEqual(self.pending(), [], '08시 예약이 먹지 못하게 밤에 만든 보관 행은 지운다')
        self.assertEqual(self.batches, [])
        self.assertFalse(self.granted)

    def morning_after(self, first, second):
        """[first] 번호로 밤 단계를, 이튿날 낮에 [second] 번호로 아침 단계를."""
        case = next(c for c in TWO_STAGE if first in (c, ALIAS[c]))
        self.assertEqual(self.alias(first)[0][0], 'blocked')
        made = len(self.world.users)
        self.clock.now, shade = WED(9, 20), len(self.world.shade)
        (result, note), _ = self.alias(second)
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(len(self.world.users), made, '아침 단계는 새 밤 단계를 시작하지 않고 계정도 새로 만들지 않는다')
        titles = {t for t, _ in WANT[case]}
        self.assertEqual(sorted((n.title, n.text) for n in self.world.shade[shade:] if n.title in titles), sorted(WANT[case]))
        self.assertTrue(self.state(TWO_STAGE[case])['done'])
        self.assertEqual(self.batches, ['chat-gate'], '손 호출은 한 번 — 같은 판을 두 번 돌지 않는다')

    def recorded_twice(self, case):
        (result, note), _ = self.alias(case)
        said = self.results()[ALIAS[case]]
        self.assertEqual(said['result'], result)
        self.assertIn(case, said['note'])  # 어느 번호로 돌린 결과인지
        self.assertIn(note, said['note'])

    def test_a_blocked_before_anything_is_recorded_for_both_numbers_as_blocked(self):
        self.clock.now = TUE(12)
        self.alias('E-CHAT-42')
        self.assertEqual(self.results()['E-PUSH-86']['result'], 'blocked')

    def test_a_fail_after_the_batch_is_remembered_once_for_both_numbers_so_the_retry_does_not_run_it_again(self):
        self.assertEqual(self.alias('E-CHAT-42')[0][0], 'blocked')
        self.clock.now = WED(9, 20)

        def wrong():
            title = self.pending()[0]['title']
            self.world.tables['pending_pushes'] = []
            self.world.post(title, '다른 문구')
        self.scripts['chat-gate'] = wrong

        def once(case):
            return area1.attempt_phone(self.run, case, self.phone())
        first = cli.run_case(once, 'E-CHAT-42')
        self.assertEqual(first[1], 'fail', first)
        self.assertEqual(first[0], 2, '진행 프로그램은 fail 이면 한 번 더 부른다')
        self.assertEqual(self.batches, ['chat-gate'], '둘째 시도는 배치를 다시 부르지 않고 첫 fail 을 돌려준다')

    def test_a_time_out_passes_through_untouched_and_the_area4_number_gets_no_line(self):
        """CaseTimeout 은 진행 프로그램(run_case)이 잡아 blocked(시간 초과)로 적는다 — 별칭이 삼키면 시간 상한이 사라진다."""
        def late(run, phone):
            raise tools.CaseTimeout('가설 하나가 900초를 넘김')
        with mock.patch.dict(night.PHONE, {'E-PUSH-33': late}):
            with self.assertRaises(tools.CaseTimeout):
                area3_phone7.PHONE7['E-CHAT-34'](self.run, self.phone())
        self.assertNotIn('E-PUSH-33', self.results())

    def test_a_blocked_raised_by_the_area4_case_becomes_a_blocked_result_recorded_for_the_area4_number(self):
        def refused(run, phone):
            raise Blocked('지금은 실행 금지 시간 — 22:00 에 다시')
        with mock.patch.dict(night.PHONE, {'E-PUSH-33': refused}):
            got = area1.attempt_phone(self.run, 'E-CHAT-34', self.phone())
        self.assertEqual(got, ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))
        said = self.results()['E-PUSH-33']
        self.assertEqual(said['result'], 'blocked')
        self.assertIn('E-CHAT-34', said['note'])
        self.assertIn('지금은 실행 금지 시간', said['note'])
        self.run.record('E-CHAT-34', *got)  # 부른 번호 줄은 진행 프로그램(cmd_run)이 적는다 — 두 번호 모두 blocked 로 남는다
        self.assertEqual({c: r['result'] for c, r in self.results().items()}, {'E-PUSH-33': 'blocked', 'E-CHAT-34': 'blocked'})

    def test_a_night_result_never_counts_the_trust_new_message_the_first_accepter_gets_at_night(self):
        """E-CHAT-42 시나리오의 "밤 A·B 모두 0건" 은 코드와 다르다 — 먼저 수락한 쪽에는 새 메시지가 밤에도 온다(chat/router.py _notify_message).
        판정은 제목 "카카오톡 아이디를 주고받았어요" 만 세므로 그 알림이 와도 결과는 fail 이 아니라 밤 단계 blocked(다음 단계 안내)다."""
        (result, _), _ = self.alias('E-CHAT-42')
        self.assertEqual(result, 'blocked')
        shade = [(n.title, n.text) for n in self.world.shade]
        self.assertIn((PARTNER, TRUST), shade)
        self.assertEqual([t for t in shade if t[0] == PUBLIC], [])

    # 도우미
    def alias(self, case, phone=None):
        phone = phone or self.phone()
        return self.go(case, phone), phone


for _case in ALIAS:
    setattr(AliasRunTest, f'test_{_case[2:].replace("-", "_").lower()}_result_is_recorded_under_the_area4_number_too',
            lambda self, c=_case: self.recorded_twice(c))


for _case, _theirs in ((c, ALIAS[c]) for c in TWO_STAGE):
    setattr(AliasRunTest, f'test_{_case[2:].replace("-", "_").lower()}_night_stage_writes_the_area4_state_file_and_none_of_its_own',
            lambda self, c=_case: self.night_contract(c))
    setattr(AliasRunTest, f'test_{_case[2:].replace("-", "_").lower()}_morning_by_the_area4_number_finishes_the_area3_nights_work',
            lambda self, c=_case, t=_theirs: self.morning_after(c, t))
    setattr(AliasRunTest, f'test_{_case[2:].replace("-", "_").lower()}_morning_by_the_area3_number_finishes_the_area4_nights_work',
            lambda self, c=_case, t=_theirs: self.morning_after(t, c))


class ServerContractTest(unittest.TestCase):
    """별칭이 기대하는 서버 문구 · 보관 쌍이 서버 소스에 그대로 있다 — 서버가 바꾸면 여기서 먼저 죽는다(push.py 는 google.auth 가 없어 소스 글자로 본다)."""

    @classmethod
    def setUpClass(cls):
        cls.chat = read('backend', 'app', 'chat', 'router.py')
        cls.push = read('backend', 'app', 'cards', 'push.py')
        cls.review = read('backend', 'app', 'friend_reviews', 'router.py')

    def test_the_public_notice_is_deferred_for_the_first_accepter_and_dropped_for_the_last(self):
        self.assertIn('"카카오톡 아이디를 주고받았어요"', self.chat)
        self.assertIn('(partner["profile_id"], nickname, True)', self.chat)
        self.assertIn('(wiring.profile_id, partner_nickname, False)', self.chat)
        self.assertIn('님의 프로필이 공개됐어요', self.chat)

    def test_the_trust_accept_message_goes_to_the_first_accepter_as_a_new_message_that_the_night_lets_through(self):
        self.assertRegex(self.chat, r'(?s)_notify_message\(wiring, partner, nickname,\s+"카카오톡 아이디·실사진 공개를 수락했어요"')
        self.assertRegex(self.push, r'_QUIET_HOURS_EXEMPT = \{[^}]*"new_message"')

    def test_the_review_notice_is_a_deferred_kind_with_the_texts_and_route_the_alias_expects(self):
        self.assertIn('"새 지인 리뷰가 도착했어요"', self.review)
        self.assertIn('님이 리뷰를 남겼어요', self.review)
        self.assertIn('{"route": "friend_reviews"}', self.review)
        self.assertRegex(self.push, r'_DEFERRED = \{[^}]*"match_made"[^}]*\}')
        self.assertRegex(self.push, r'_DEFERRED = \{[^}]*"new_friend_review"[^}]*\}')


if __name__ == '__main__':
    unittest.main()
