"""영역 3 폰 A 한 대 3차(E-CHAT-32 — 꺼진 앱에서 알림을 눌러 방 열기)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_phone3`.

가짜 서버는 e2e/test_area3.py 의 Fake, 가짜 폰은 [Phone] — 로그인 판(`phone(...)`)과 알림 누름 판(`phone.hub.tell` → `phone.hub.result`)을
같은 [events] 줄에 남겨 순서를 센다. adb 를 부르는 notify 함수는 전부 가짜(운영 · 폰 0).
계정은 만든 순서대로 id-1(폰 계정) · id-2(상대), 토큰은 tok-1 · tok-2 …
"""

import itertools
import re
import unittest
from unittest import mock

from e2e import area1, area3, area3_phone3, notify, tools
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import Phone2
from e2e.tools import Blocked, Reply

CASE = 'E-CHAT-32'
OPENED = {'room': True, 'nickname': True, 'message': True, 'screen': ['home'], 'room_ms': 1200, 'opened_at': '2026-10-05T03:00:07Z'}


class Phone(App):
    """앱 + 우편함 대신. 로그인 판은 `phone(...)` 호출, 알림 누름 판은 hub.tell · hub.result — 전부 [events] 에 남긴다."""

    case = CASE

    def __init__(self, events, login=None, tapped=None):
        super().__init__(lambda job: login if login is not None else said())
        self.events, self.tapped, self.on_login = events, tapped, lambda: None
        self.hub = mock.Mock()
        self.hub.tell.side_effect = lambda job: events.append(('tell', job))
        self.hub.result.side_effect = self._result

    def __call__(self, midway=None, **job):
        self.events.append(('app', job))
        self.on_login()  # 앱이 로그인하면 기기 토큰을 서버에 올린다(표는 가설이 시작할 때 비워지므로 앱 호출 안에서)
        return super().__call__(midway, **job)

    def _result(self, timeout):
        self.events.append(('result', timeout))
        return self.tapped


class Chat32Base(Phone2):
    """가짜 폰 · 가짜 서버 · 가짜 notify 를 갖춘 바탕 — 시험은 Chat32Test, 등록부 시험은 RegistryTest."""

    def setUp(self):
        super().setUp()
        self.events = []
        self.old = [notify.Notice('old', '남은 알림', '', 'c')]
        self.notices = None  # None 이면 보낸 글 그대로의 알림이 온다
        fakes = {'read_notifications': lambda s: self.events.append(('read', s)) or self.old,
                 'kill_app': lambda s: self.events.append(('kill', len(self.sends()))),
                 'wait_new': self.wait_new,
                 'tap_notification': lambda s, title: self.events.append(('tap', title))}
        for name, fake in fakes.items():
            patcher = mock.patch.object(notify, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)

    def sends(self):
        return self.fake.by('POST', '/chat/matches/')

    def sent_body(self):
        return self.sends()[0]['body']['body']

    def wait_new(self, serial, before, count=1, seconds=0):
        self.events.append(('wait_new', before is self.old, seconds, len(self.sends())))
        if self.notices is not None:
            return self.notices
        return [notify.Notice('new', self.nick(2), self.sent_body(), 'c')]

    def go(self, phone=None, tokens=1):
        phone = phone or Phone(self.events, tapped={'result': 'pass', **OPENED})
        phone.on_login = lambda: [self.put('push_tokens', profile_id='id-1', token='t') for _ in range(tokens)]
        return self.case(CASE, None, phone)[0], phone

    def names(self):
        return [e if isinstance(e, str) else e[0] for e in self.events]


class Chat32Test(Chat32Base):

    # ── 통과 경로 ───────────────────────────────────────────────────────────────────────────────────

    def test_pass_path_logs_in_kills_sends_waits_tells_taps_and_listens(self):
        (result, note), phone = self.go()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.names(), ['app', 'read', 'kill', 'wait_new', 'tell', 'tap', 'result'])
        self.assertEqual(self.events[0], ('app', {'token_hash': 'h', 'phase': 'login'}))
        body = self.sent_body()
        self.assertRegex(body, r'^E2E-32-\w+$')
        self.assertEqual([s['auth'] for s in self.sends()], ['tok-2'])  # 상대(id-2)가 보낸다
        self.assertEqual(self.sends()[0]['path'], f"/chat/matches/{self.match()}/messages")
        self.assertIn(('wait_new', True, 60, 1), self.events)  # 앞 알림 목록 기준 · 60초 · 보낸 뒤에
        self.assertIn(('tell', {'case': CASE, 'phase': 'tap', 'nickname': self.nick(2), 'body': body}), self.events)
        self.assertIn(('tap', self.nick(2)), self.events)
        self.assertIn(('result', 90), self.events)  # 앱 안의 30 + 10 + 10초 기다림이 끝나도 남는 여유
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_pass_note_has_seconds_to_arrive_and_when_the_app_opened_the_room(self):
        (result, note), _ = self.go()
        self.assertEqual(result, 'pass')
        self.assertRegex(note, r'알림 도착까지 \d+초')
        self.assertIn('2026-10-05T03:00:07Z', note)
        self.assertIn('일감 받은 뒤 1200ms', note)  # 눌린 시각이 아니라 앱이 부팅해 일감을 받은 시각부터 센 값
        self.assertNotIn('누른 뒤', note)

    def test_the_app_is_killed_before_the_message_is_sent_and_never_force_stopped(self):
        self.go()
        self.assertIn(('kill', 0), self.events)  # 죽인 순간 보낸 글 0건 — 보내기는 그 뒤
        self.assertLess(self.names().index('kill'), self.names().index('wait_new'))
        self.assertLess(self.names().index('read'), self.names().index('kill'))  # 앞 알림은 죽이기 전에 읽어 둔다

    def test_the_job_is_told_before_the_notification_is_tapped(self):
        """누르기 전에 일감이 안 들어가면 콜드 스타트한 앱이 hear() 로 일감을 못 받는다."""
        self.go()
        self.assertLess(self.names().index('tell'), self.names().index('tap'))
        self.assertLess(self.names().index('tap'), self.names().index('result'))

    def test_the_tap_job_carries_no_login_token_and_no_dead_keys(self):
        """tap 판은 _session 으로 안 감싸 새 로그인을 하지 않는다 — 토큰도, 앱이 안 읽는 fresh 도 일감에 없다."""
        self.go()
        job = next(e[1] for e in self.events if e[0] == 'tell')
        self.assertEqual(set(job), {'case', 'phase', 'nickname', 'body'})

    # ── 알림 ────────────────────────────────────────────────────────────────────────────────────────

    def test_no_new_notification_is_a_fail_and_nothing_is_told_or_tapped(self):
        self.notices = []
        (result, note), _ = self.go()
        self.assertEqual(result, 'fail')
        self.assertIn('60초', note)
        self.assertNotIn('tell', self.names())
        self.assertNotIn('tap', self.names())

    def test_a_notification_with_other_words_is_a_fail(self):
        for notice in (notify.Notice('k', '다른 사람', 'E2E-32-x', 'c'), notify.Notice('k', 'Abcde', '다른 본문', 'c')):
            self.events.clear()
            self.notices = [notice]
            self.assertEqual(self.go()[0][0], 'fail', notice)
            self.assertNotIn('tap', self.names())

    # ── 앱이 본 것 ──────────────────────────────────────────────────────────────────────────────────

    def test_each_missing_sight_is_a_fail_and_names_what_is_missing(self):
        for key in ('room', 'nickname', 'message'):
            self.events.clear()
            seen = {**OPENED, key: False}
            (result, note), _ = self.go(Phone(self.events, tapped={'result': 'pass', **seen}))
            self.assertEqual(result, 'fail', key)
            self.assertIn(key, note)

    def test_stuck_on_consent_or_onboarding_names_the_screen_in_the_note(self):
        stuck = {'room': False, 'nickname': False, 'message': False, 'screen': ['consent', '04-1']}
        (result, note), _ = self.go(Phone(self.events, tapped={'result': 'pass', **stuck}))
        self.assertEqual(result, 'fail')
        self.assertIn('consent', note)
        self.assertIn('04-1', note)

    def test_an_app_that_never_answers_is_a_fail(self):
        (result, note), _ = self.go(Phone(self.events, tapped=None))
        self.assertEqual(result, 'fail')
        self.assertIn('시간 안에 답하지 않음', note)

    def test_an_app_that_reports_fail_is_a_fail(self):
        (result, note), _ = self.go(Phone(self.events, tapped={'result': 'fail', 'note': '터짐'}))
        self.assertEqual(result, 'fail')
        self.assertIn('터짐', note)

    def test_an_app_that_reports_nothing_about_the_room_is_a_fail(self):
        (result, _), _ = self.go(Phone(self.events, tapped={'result': 'pass'}))
        self.assertEqual(result, 'fail')

    # ── 막힘 ────────────────────────────────────────────────────────────────────────────────────────

    def test_it_runs_at_night_too_because_new_message_is_exempt_from_quiet_hours(self):
        """backend push.py _QUIET_HOURS_EXEMPT 에 new_message — 밤이라고 막으면 E-CHAT-34 와 어긋난다."""
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))) as night:
            (result, note), _ = self.go()
        self.assertEqual(result, 'pass', note)
        night.assert_not_called()

    def test_a_missing_device_token_is_blocked_before_the_app_is_killed(self):
        with mock.patch('time.monotonic', side_effect=itertools.count()):
            (result, note), _ = self.go(tokens=0)
        self.assertEqual(result, 'blocked')
        self.assertIn('30초', note)
        self.assertNotIn('kill', self.names())
        self.assertEqual(self.sends(), [])

    def test_a_notification_that_cannot_be_tapped_is_blocked_not_a_fail(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            (result, note), phone = self.go()
        self.assertEqual(result, 'blocked')
        self.assertIn('못 찾음', note)
        self.assertNotIn('result', [e[0] for e in phone.events])  # 눌리지 않았으니 앱 말을 기다리지 않는다

    def test_a_failed_send_is_blocked_before_the_wait(self):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(500, {'detail': 'down'}))
        (result, _), _ = self.go()
        self.assertEqual(result, 'blocked')
        self.assertNotIn('wait_new', self.names())

    def test_a_blocked_login_turn_stops_before_the_kill(self):
        (result, note), _ = self.go(Phone(self.events, login={'result': 'blocked', 'note': '앱 준비 안 됨'}))
        self.assertEqual(result, 'blocked')
        self.assertNotIn('kill', self.names())

    def test_a_login_turn_that_never_reaches_home_is_a_fail_before_the_kill(self):
        (result, note), _ = self.go(Phone(self.events, login={'result': 'fail', 'note': '홈 안 나옴'}))
        self.assertEqual(result, 'fail')
        self.assertIn('홈 안 나옴', note)
        self.assertNotIn('kill', self.names())

    # ── 알림 권한 · 등록 ────────────────────────────────────────────────────────────────────────────

    def test_permission_is_granted_before_the_app_and_revoked_after(self):
        self.go()
        self.assertEqual(self.perm, [('grant', 'S'), ('revoke', 'S')])
        self.assertEqual(self.names()[0], 'app')

    def test_permission_is_revoked_even_when_blocked(self):
        with mock.patch.object(notify, 'tap_notification', mock.Mock(side_effect=Blocked('알림창에서 줄을 못 찾음'))):
            self.go()
        self.assertEqual(self.perm, [('grant', 'S'), ('revoke', 'S')])

    def test_the_case_is_registered_in_its_own_bundle(self):
        self.assertEqual(area3.BUNDLES['area3-phone-3'], [CASE])
        self.assertIn(CASE, area1.PHONE)
        self.assertEqual(list(area3_phone3.PHONE3), [CASE])

# ── 등록부 · 안전망 ──────────────────────────────────────────────────────────────────────────────────

class RegistryTest(Chat32Base):
    """이 시험 모듈이 area3_phone3 를 직접 import 하므로 __main__ 의 import 가 빠져도 BUNDLES 는 차 보인다 —
    그래서 __main__.py 원문과 Dart 원문을 직접 읽어 등록 줄을 본다(형제 RegistryTest 와 같은 방법)."""

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_main_imports_the_module_and_runs_the_bundle_through_area1_phone(self):
        from e2e import __main__ as main
        self.assertRegex((tools.ROOT / 'e2e' / '__main__.py').read_text(encoding='utf-8'), r'(?m)^from e2e import area3_phone3\b')  # 주석 처리된 줄은 안 센다
        self.assertEqual(main.BUNDLES['area3-phone-3'], [CASE])
        self.assertNotIn(CASE, main.API_CASES)
        self.assertIn(CASE, area1.PHONE)
        self.assertFalse({CASE} & set(main.BUNDLES['area3-phone-2']) | {CASE} & set(main.BUNDLES['area3-phone-1']))

    def test_the_app_part_is_declared_and_merged_into_the_case_map_like_its_siblings(self):
        part = self.dart('area3_b3.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        self.assertEqual(re.findall(r"^  '(E-[A-Z]+-\d+)'", part, re.M), [CASE])
        main = self.dart('area3.dart')
        self.assertIn("part 'area3_b3.dart';", main)
        self.assertIn('...area3Cases3,', main)  # area3Cases 맵 끝에서 합친다(area3Cases2 · area3CasesSafe 와 같다)
        self.assertLess(main.index('...area3CasesSafe,'), main.index('...area3Cases3,'))
        self.assertNotIn('area3Cases3', self.dart('e2e_test.dart'))  # e2e_test.dart 는 area3Cases 하나만 펼친다

    def test_the_app_reads_the_phases_and_keys_the_pc_sends_and_the_pc_reads_the_keys_the_app_says(self):
        self.go()
        dart = self.dart('area3_b3.dart')
        sent = [e[1] for e in self.events if e[0] in ('app', 'tell')]
        for job in sent:
            self.assertIn(f"'{job['phase']}' =>", dart, job)  # login · tap 두 판이 앱 switch 에 있다
        for key in set(sent[1]) - {'case', 'phase'}:  # tap 일감의 키(nickname · body)
            self.assertIn(f"job['{key}']", dart, key)
        self.assertIn("job['phase']", dart)
        for key in ('room', 'nickname', 'message', 'screen', 'room_ms', 'opened_at'):  # PC 가 읽는 앱 말
            self.assertIn(f"'{key}':", dart, key)

    def test_screen_names_the_app_can_say_are_exactly_the_labels_the_pc_knows(self):
        dart = self.dart('area3_b3.dart')
        listed = re.search(r"in const \[([^\]]*)\]", dart).group(1)
        named = set(re.findall(r"'([\w-]+)'", listed)) | set(re.findall(r"^\s*'([\w-]+)': find\.", dart, re.M))
        self.assertEqual(named, set(area3_phone3.SCREEN_LABELS))
        screens = self.dart('area1.dart')
        for name in named - {'home', 'conversations'}:  # 나머지는 area1.dart screens 표의 키여야 screen(name) 이 찾는다
            self.assertRegex(screens, rf"(?m)^  '{re.escape(name)}':", name)


if __name__ == '__main__':
    unittest.main()
