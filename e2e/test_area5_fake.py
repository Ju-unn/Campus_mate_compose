"""영역 5 가짜 응답 가설 넷(E-EDGE-05 · 06 · 07 · 08)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 서버 · 가짜 앱으로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_fake`.

가짜 앱은 일감을 받아 앱이 말할 만한 것(문구 · 대신 답한 요청 목록)을 돌려준다 — 서버가 가짜를 지나 DB 를 바꾼 경우는 답 안에서 가짜 서버를 직접 고쳐 만든다.
"""

import re
from pathlib import Path

from e2e import area1, area5_fake, tools
from e2e.area5_fake import LOAD_FAIL, MESSAGE, PLACES, ROUTES
from e2e.area5_read import TITLES
from e2e.test_area5_edge import EdgeBase

PREFIX = '/api'  # 서버 주소에 경로 접두가 붙어도 판정이 같아야 한다


def faked(places, status):
    return [f"{ROUTES[place].split(' ')[0]} {PREFIX}{ROUTES[place].split(' ')[1]}={status}" for place in places]


def saves(status, places=PLACES, **over):
    walks = []
    for place in places:
        if place in ('15-6', '15-7'):
            walk = {'place': place, 'error': MESSAGE[status], 'kept': True, 'stayed': TITLES[place]}
        elif place == 'withdraw':
            walk = {'place': place, 'error': MESSAGE[status], 'sheet_open': True, 'login': False}
        else:
            walk = {'place': place, 'error': MESSAGE[status], 'generating_gone': True}
        walk.update(over.get(place, {}))
        walks.append(walk)
    return {'walks': walks, 'faked': faked(places, status), 'passed': [], **over.get('top', {})}


def reads(status, **over):
    rows = [{'place': place, 'error': LOAD_FAIL, 'retry': True, 'recovered_ms': 800} for place in area5_fake.READS]
    for row in rows:
        row.update(over.get(row['place'], {}))
    entries = [f"{route.split(' ')[0]} {PREFIX}{route.split(' ')[1]}={status}" for route in set(area5_fake.READS.values())]
    return {'walks': rows, 'faked': entries, 'passed': []}


class FakeBase(EdgeBase):
    def run_case(self, case, answer):
        return self.go(case, {None: ([], answer)})[0]

    def verdict(self, case, answer, expect='pass', *words):
        result, note = self.run_case(case, answer)
        self.assertEqual(result, expect, note)
        for word in words:
            self.assertIn(word, note)
        return note


class SavesTest(FakeBase):
    def test_05_a_502_that_never_reaches_the_server_passes_on_all_four_places(self):
        self.verdict('E-EDGE-05', lambda job: saves(502))

    def test_06_a_500_shows_the_other_message(self):
        self.verdict('E-EDGE-06', lambda job: saves(500))
        self.assertNotEqual(MESSAGE[500], MESSAGE[502])

    def test_08_a_429_on_the_basic_info_save_only(self):
        job = {}

        def answer(sent):
            job.update(sent)
            return saves(429, ['15-6'])
        self.verdict('E-EDGE-08', answer)
        self.assertEqual((job['status'], job['places'], job['expect']), (429, ['15-6'], MESSAGE[429]))

    def test_the_app_is_told_the_status_the_message_and_the_places(self):
        job = {}

        def answer(sent):
            job.update(sent)
            return saves(502)
        self.verdict('E-EDGE-05', answer)
        self.assertEqual((job['status'], job['expect'], job['places']), (502, MESSAGE[502], PLACES))
        self.assertIn('token_hash', job)

    def test_a_wrong_message_a_lost_value_or_a_left_screen_is_a_fail(self):
        for over in ({'15-6': {'error': None}}, {'15-7': {'error': MESSAGE[500]}}, {'15-6': {'kept': False}}, {'15-7': {'stayed': TITLES['15-5']}},
                     {'avatar': {'error': None}}, {'avatar': {'generating_gone': False}}, {'withdraw': {'sheet_open': False}},
                     {'withdraw': {'login': True}}):
            with self.subTest(over):
                self.verdict('E-EDGE-05', lambda job: saves(502, **over), 'fail')

    def test_a_request_that_slipped_past_the_fake_to_the_server_is_a_fail(self):
        for place in PLACES:
            with self.subTest(place):
                method, path = ROUTES[place].split(' ')
                self.verdict('E-EDGE-05', lambda job: saves(502, top={'passed': [f'{method} {PREFIX}{path}']}), 'fail', '서버로 그냥')

    def test_a_route_the_fake_never_answered_is_a_fail(self):
        answer = saves(502)
        answer['faked'] = [entry for entry in answer['faked'] if 'photos' not in entry]
        self.verdict('E-EDGE-05', lambda job: answer, 'fail', '/me/photos')

    def test_the_status_the_fake_gave_must_be_the_one_asked_for(self):
        answer = saves(500)
        self.verdict('E-EDGE-05', lambda job: answer, 'fail')

    def test_a_change_in_the_db_is_a_fail_even_when_the_screen_looked_right(self):
        def changed(job):
            self.profile().update(height_cm=181)  # 서버가 저장을 받아 버렸다
            return saves(502)
        self.verdict('E-EDGE-05', changed, 'fail', 'DB')

    def test_a_withdrawn_account_is_a_fail(self):
        def withdrawn(job):
            self.profile().update(status='withdrawn')
            return saves(502)
        self.verdict('E-EDGE-05', withdrawn, 'fail', '계정 상태')

    def test_a_blocked_app_is_blocked(self):
        result, note = self.run_case('E-EDGE-05', lambda job: {'result': 'blocked', 'note': '가짜 응답 끼우기가 안 먹음'})
        self.assertEqual(result, 'blocked', note)
        self.assertIn('안 먹음', note)


class ReadsTest(FakeBase):
    def test_07_both_statuses_show_the_same_message_and_recover_in_three_seconds(self):
        seen = []

        def answer(job):
            seen.append(job['status'])
            return reads(job['status'])
        self.verdict('E-EDGE-07', answer)
        self.assertEqual(seen, [500, 502])

    def test_07_each_status_gets_a_fresh_login_token(self):
        links = []
        original = self.run_.link
        self.run_.link = lambda email: links.append(email) or f'tok-{len(links)}'  # 1회용 토큰은 같은 계정이 새로 받으면 앞 것이 죽는다
        self.addCleanup(setattr, self.run_, 'link', original)
        tokens = []

        def answer(job):
            tokens.append(job['token_hash'])
            return reads(job['status'])
        self.verdict('E-EDGE-07', answer)
        self.assertEqual(len(set(tokens)), 2)

    def test_07_a_missing_message_retry_button_or_slow_recovery_is_a_fail(self):
        for over in ({'15': {'error': None}}, {'15-5': {'retry': False}}, {'15-4': {'recovered_ms': None}}, {'15-4': {'recovered_ms': 3001}}):
            with self.subTest(over):
                self.verdict('E-EDGE-07', lambda job: reads(job['status'], **over), 'fail')

    def test_07_a_read_the_fake_never_answered_is_a_fail(self):
        def answer(job):
            out = reads(job['status'])
            out['faked'] = [entry for entry in out['faked'] if 'card-preview' not in entry]
            return out
        self.verdict('E-EDGE-07', answer, 'fail', 'card-preview')


class RegistryTest(FakeBase):
    def dart(self, name='area5_fake.dart'):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_four_are_phone_cases_in_one_bundle(self):
        cases = ['E-EDGE-05', 'E-EDGE-06', 'E-EDGE-07', 'E-EDGE-08']
        self.assertEqual(area1.BUNDLES['area5-fake'], cases)
        for case in cases:
            self.assertIs(area1.PHONE[case], area5_fake.PHONE[case])
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 600)

    def test_main_imports_the_module(self):
        from e2e import __main__ as main
        self.assertIn('area5_fake', main.__loader__.get_source('e2e.__main__'))

    def test_the_app_registers_the_four_and_the_part_is_wired(self):
        text = self.dart()
        self.assertEqual(re.findall(r"^\s*'(E-EDGE-\d+)':", text, re.M), ['E-EDGE-05', 'E-EDGE-06', 'E-EDGE-08', 'E-EDGE-07'])
        self.assertIn("part 'area5_fake.dart';", self.dart('area5.dart'))
        self.assertIn('...area5CasesFake', self.dart('area5.dart'))

    def test_every_key_the_pc_reads_is_a_key_the_app_says(self):
        said = set(re.findall(r"'(\w+)':", self.dart()))
        source = Path(area5_fake.__file__).read_text(encoding='utf-8')
        read = set(re.findall(r"(?:walk|said)\.get\('(\w+)'", source))
        self.assertGreater(len(read), 6)
        self.assertEqual(sorted(read - said), [])

    def test_the_routes_the_fake_watches_are_the_ones_the_pc_checks(self):
        watched = set(re.findall(r"'((?:GET|PUT|POST|PATCH) /[\w/-]+)'", self.dart().split('class _FkClient')[0]))
        self.assertEqual(watched, set(ROUTES.values()) | set(area5_fake.READS.values()))

    def test_the_withdraw_route_is_never_sent_to_the_server_even_without_a_rule(self):
        client = self.dart().split('class _FkClient')[1].split('/// 앱을 apiClientProvider')[0]
        self.assertIn("_matches('POST /account/withdraw', request) ? 502 : null", client)

    def test_the_server_is_reached_only_when_no_rule_matched(self):
        send = self.dart().split('Future<http.StreamedResponse> send(')[1].split('/// 앱을 apiClientProvider')[0]
        self.assertEqual(send.count('_inner.send('), 1)
        self.assertLess(send.index('if (status == null)'), send.index('_inner.send('))
        self.assertLess(send.index('_inner.send('), send.index('faked.add('))  # 대신 답하는 길은 서버를 부르지 않고 바로 돌려준다

    def test_only_one_helper_presses_the_final_delete_and_it_is_answered_by_the_fake(self):
        code = re.sub(r'(?m)^\s*//.*$', '', self.dart())  # 머리 주석은 빼고 코드만
        self.assertEqual(re.findall(r'_wdWithdraw\(', code), ['_wdWithdraw('])
        self.assertNotIn('정말 영구 삭제', code)
        self.assertNotIn('_wdForever', code)
        withdraw = code.split('Future<Map<String, Object?>> _fkWithdraw(')[1].split('const _fkLoadFail')[0]
        self.assertIn('_wdWithdraw(tester)', withdraw)
        self.assertEqual(re.findall(r'_fkWithdraw\(', code), ['_fkWithdraw(', '_fkWithdraw('])  # 선언 + _fkSaves 안 한 번
        self.assertIn("POST /account/withdraw", code.split('Future<Map<String, Object?>> _fkSaves(')[1].split('final Map<String, Area1Case>')[0])
        self.assertIn("job['status']", code)  # 규칙은 늘 502 · 500 같은 실패 코드 — 200 을 줄 길이 없다
