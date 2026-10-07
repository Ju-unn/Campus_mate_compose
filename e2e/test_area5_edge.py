"""영역 5 경계 7개(E-EDGE-01 · 11 · 15 · 19 폰 A, 21 · 24 · 25 B에뮬)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 · gcloud 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_edge`.

가짜 서버는 area5_read 시험의 ReadFake(프로필 칸 · 사진 행 · 계정 공장)에 관리자 사용자 삭제를 더했다. 가짜 앱 [ScriptApp] 은 켤 때마다 일감의 phase 로
정한 멈춤(step)을 차례로 말하고, 멈춤마다 앱이 서버에 한 일(저장 · 요청 기록)을 on_step 으로 흉내 낸 뒤 끝에 말(answer)을 돌려준다 — 알림을 눌러 콜드 스타트한
판은 hub.tell · wait · go · result 로 같은 일을 한다. 비행기 모드 · 에뮬 망 · iptables · gcloud 요청 로그는 가짜로 바꿔 [events] 에 남긴다.
계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 …
"""

import ast
import contextlib
import io
import os
import re
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2_phone3, area5_edge, emu, notify, tools
from e2e.test_area5_read import OURS, LAUNCHER, ReadBase
from e2e.tools import Blocked, Reply

CASES = ['E-EDGE-01', 'E-EDGE-11', 'E-EDGE-15', 'E-EDGE-19', 'E-EDGE-21', 'E-EDGE-24', 'E-EDGE-25']
SCREENS = ['15-6', '15c', '06-1', 'tag', '15-7']
TITLES = {'15': '내 프로필', '15-5': '프로필 편집', '15c': '자기소개·태그 수정', '06-1': '이상형 조건 수정', 'tag': '관심사 수정',
          '15-6': '기본 정보 수정', '15-7': '사진 수정'}
ARRIVAL = {'15-6': '15-5', '15c': '15-5', '06-1': '15-5', 'tag': '15c', '15-7': '15-5'}
PATHS = {'15-6': ('PATCH', '/me/profile'), '15c': ('PATCH', '/me/profile'), '06-1': ('POST', '/profile-onboarding/ideal-conditions'),
         'tag': ('POST', '/profile-onboarding/interests'), '15-7': ('PUT', '/me/photos')}
NETWORK = '네트워크 연결을 확인해 주세요'
EXPIRED = '세션이 만료됐어요, 다시 로그인해 주세요'
REVIEW_TITLE = '새 지인 리뷰가 도착했어요'


_LAST = [datetime.now(timezone.utc)]


def now():
    """늘어나는 시계 — 윈도 시계는 해상도가 15.6ms 라 빠른 가짜 앱에서 서로 다른 순간이 같은 값이 되어, 창(window)과 로그가 서로의 것을 센다.
    가설 쪽 `area5_edge._now` 도 같은 시계로 바꿔(EdgeBase.setUp) 읽는다."""
    _LAST[0] = max(datetime.now(timezone.utc), _LAST[0] + timedelta(microseconds=1))
    return _LAST[0]


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


class ScriptApp:
    """앱 대신. [plan] = phase → (멈춤 이름들, 말). 멈춤마다 on_step(이름, 일감) 을 먼저 부른다(앱이 그 멈춤 전에 한 일)."""

    def __init__(self, plan, events, on_step=None, serial='S', top=OURS):
        self.plan, self.events, self.on_step = plan, events, on_step or (lambda name, job: None)
        self.serial, self.hub, self.case, self.jobs, self._top = serial, self, 'case', [], top
        self.queue, self.job = [], {}

    def top(self):
        return self._top

    def _load(self, job):
        self.jobs.append(job)
        self.job = job
        self.queue = list(self.plan[job.get('phase')][0])

    def _answer(self):
        answer = self.plan[self.job.get('phase')][1]
        return {'result': 'pass', **(answer(self.job) if callable(answer) else answer)}

    # 우편함(hub) 흉내
    def tell(self, job):
        self.events.append(('tell', job.get('phase')))
        self._load(job)

    def go(self, extra=None):
        self.events.append('go')

    def wait(self, timeout):
        if not self.queue:
            return self._answer()
        name = self.queue.pop(0)
        self.on_step(name, self.job)
        self.events.append(f'step:{name}')
        return {'step': name}

    def result(self, timeout):
        while self.queue:
            self.wait(timeout)
        return self._answer()

    def __call__(self, midway=None, **job):
        self._load(job)
        if midway and self.queue:
            midway(self.wait(0))
            self.events.append('go')
        return self.result(0)


class EdgeBase(ReadBase):
    def setUp(self):
        super().setUp()
        self.logs = []  # 가짜 Cloud Run 요청 로그 — (시각, 메서드, 경로)
        self.offline = False
        self.pids = ['4242']
        self.rules = {'iptables': 0, 'ip6tables': 0}  # 가짜 에뮬에 걸린 "나가는 패킷 버림" 규칙 개수 — 표마다
        self.stubborn = set()  # -D 를 해도 규칙이 안 지워지는 표
        self.fake.on('DELETE', r'/auth/v1/admin/users/[^/]+', self._delete_user)
        self.gone = set()
        self.fake.on('GET', r'/rest/v1/profiles', lambda sent: Reply(200, []) if sent['query'].get('id', '')[3:] in self.gone
                     else self.fake._table('GET', 'profiles', sent))

        def fake_adb(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            if args[-1] == 'KEYCODE_BACK':
                self.events.append('back')
            if 'pidof' in args:
                return ' '.join(self.pids)
            if 'kill' in args:
                self.pids.clear()
            table = next((t for t in self.rules if t in args), None)
            if args[:1] == ('emu',) or table:
                self.events.append(' '.join(args))
            if table:
                return self.iptables(table, [a for a in args[args.index(table) + 1:] if a != '-w'])
            return ''

        for patcher in (mock.patch.object(tools, 'adb', fake_adb), mock.patch('time.sleep'),
                        mock.patch.object(notify, 'airplane', lambda serial, on, settle=None: self.airplane(on)),
                        mock.patch.object(notify, 'ensure_online', lambda serial: self.events.append('ensure_online')),
                        mock.patch.object(notify, 'require_daytime', lambda now=None: None),  # 실제 시각에 안 흔들리게 — 밤인 경우는 Edge15Test 가 따로 본다
                        mock.patch.object(notify, 'ensure_delivery', lambda serial: None),
                        mock.patch.object(notify, 'grant_notifications', lambda serial: None),
                        mock.patch.object(notify, 'revoke_notifications', lambda serial: None),
                        mock.patch.object(notify, 'read_notifications', lambda serial: []),
                        mock.patch.object(notify, 'kill_app', lambda serial: self.events.append('kill')),
                        mock.patch.object(notify, 'wait_new', self.wait_new),
                        mock.patch.object(notify, 'tap_notification', lambda serial, title: self.events.append(('tap', title))),
                        mock.patch.object(emu, 'root', lambda serial, hub=None: self.events.append('root')),
                        mock.patch.object(emu, 'online', lambda serial: not self.dropped()),
                        mock.patch.object(area5_edge, '_now', now),
                        mock.patch.object(area5_edge, '_photos', lambda run, *names: None),
                        mock.patch.object(area5_edge, '_push', lambda phone, run, *names: None),
                        mock.patch.object(area5_edge, '_requests', lambda since, until: [r for r in self.logs if since <= r[0] <= until]),
                        mock.patch.object(area2_phone3, '_guard'), mock.patch.dict(os.environ, {'E2E_REAL_AI': '1'})):
            patcher.start()
            self.addCleanup(patcher.stop)
        area2_phone3._PAID.clear()
        self.addCleanup(area2_phone3._PAID.clear)
        self.notices = []

    def _delete_user(self, sent):
        uid = sent['path'].rsplit('/', 1)[1]
        self.fake.users[:] = [u for u in self.fake.users if u['id'] != uid]
        self.fake.profiles.pop(uid, None)
        self.gone.add(uid)  # 프로필 이하는 cascade 로 사라진다
        return Reply(200, {})

    def airplane(self, on):
        self.offline = on
        self.events.append(('airplane', on))

    def iptables(self, table, rest):
        """-I 는 규칙을 하나 더 걸고, -D 는 하나 지우며(막힌 표는 그대로), -S 는 규칙을 줄마다 읽어 준다."""
        if rest[0] == '-I':
            self.rules[table] += 1
        elif rest[0] == '-D' and table not in self.stubborn:
            self.rules[table] = max(0, self.rules[table] - 1)
        elif rest[0] == '-S':
            return '\n'.join(['-P OUTPUT ACCEPT'] + ['-A OUTPUT ! -o lo -j DROP'] * self.rules[table])
        return ''

    def dropped(self):
        return any(self.rules.values())

    def wait_new(self, serial, before, count=1, seconds=0, match=None):
        return [notify.Notice(f'n{i}', title, '', 'c') for i, title in enumerate(self.notices)]

    def log(self, screen, times=1):
        method, path = PATHS[screen]
        self.logs += [(now(), method, path)] * times

    def go(self, name, plan, on_step=None, serial='S'):
        self.fake.handlers = [h for h in self.fake.handlers if h[1].pattern != r'/auth/v1/admin/users/[^/]+']
        self.fake.on('DELETE', r'/auth/v1/admin/users/[^/]+', self._delete_user)
        app = ScriptApp(plan, self.events, on_step, serial=serial)
        return self.case(name, None, app)

    def case(self, name, answer, app=None):
        self.gone.clear()  # 지운 계정은 가설마다 새로 — 계정 id 는 늘 id-1 부터다
        return super().case(name, answer, app)

    def save_all(self, job):
        """앱이 다섯 화면을 다 저장했다 — 서버에 남는 것."""
        me = self.profile()
        me.update(height_cm=int(job['height']), bio=job['bio'], preferred_age_min=19, preferred_age_max=35,
                  interest_tags=[*me['interest_tags'], job['extra']])
        photos = self.photo_rows()
        photos[0]['position'], photos[1]['position'] = photos[1]['position'], photos[0]['position']

    def photo_rows(self, n=1):
        return sorted((p for p in self.fake.rows('profile_photos') if p['profile_id'] == f'id-{n}'), key=lambda p: p['position'])


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_the_seven_are_phone_cases_in_one_bundle_with_the_rooted_one_last(self):
        self.assertEqual(area1.BUNDLES['area5-edge'], CASES)
        self.assertEqual(list(area5_edge.PHONE), CASES)
        self.assertLessEqual(set(CASES), set(area1.PHONE))
        self.assertEqual(area5_edge.EMULATOR, ['E-EDGE-21', 'E-EDGE-24', 'E-EDGE-25'])

    def test_the_runner_sees_the_bundle(self):
        probe = 'from e2e import __main__ as m; print(m.BUNDLES.get("area5-edge"))'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), str(CASES))

    def test_the_long_cases_get_room(self):
        for case in CASES:
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 600, case)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-EDGE-25'], area5_edge.WATCH + 2 * area5_edge.APP_WAIT)

    def test_the_paths_and_titles_are_the_real_ones(self):
        self.assertEqual(area5_edge.PATHS, PATHS)
        self.assertEqual(dict(area5_edge.SCREENS), ARRIVAL)
        me = (tools.ROOT / 'frontend' / 'lib' / 'me' / 'model' / 'http_me_repository.dart').read_text(encoding='utf-8')
        self.assertIn("'/me/profile'", me)
        self.assertIn("http.MultipartRequest('PUT', _api.uri('/me/photos'))", me)
        tags = (tools.ROOT / 'frontend' / 'lib' / 'profile' / 'model' / 'http_tag_picker_repository.dart').read_text(encoding='utf-8')
        self.assertIn("'/profile-onboarding/$endpoint'", tags)
        failure = (tools.ROOT / 'frontend' / 'lib' / 'common' / 'failure.dart').read_text(encoding='utf-8')
        self.assertIn(f"return '{NETWORK}';", failure)
        self.assertEqual(area5_edge.NETWORK, NETWORK)

    def test_there_is_still_no_request_timeout_in_the_app(self):
        lib = tools.ROOT / 'frontend' / 'lib'
        timeouts = [p.name for p in lib.rglob('*.dart') if '.timeout(' in p.read_text(encoding='utf-8')]
        self.assertEqual(timeouts, [], 'E-EDGE-25 의 "요청 시간 제한 없음" 이 바뀌었다 — 기대값을 다시 본다')

    def test_the_app_registers_the_seven_and_the_keys_match(self):
        text = dart('area5_edge.dart')
        self.assertEqual(re.findall(r"^\s*'(E-EDGE-\d+)':", text, re.M), CASES)
        self.assertIn("part 'area5_edge.dart';", dart('area5.dart'))
        self.assertIn('...area5CasesEdge', dart('area5.dart'))
        tree = ast.parse(Path(area5_edge.__file__).read_text(encoding='utf-8'))
        read = {node.args[0].value for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get'
                and isinstance(node.func.value, ast.Name) and node.func.value.id in ('said', 'walk')
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)}
        said = set(re.findall(r"'(\w+)':", text))
        self.assertGreaterEqual(len(read), 15)
        self.assertEqual(sorted(read - said - {'note'}), [])  # note 는 e2e_test.dart 가 결과에 붙이는 메모(앱 Map 키가 아니다)
        wanted = set(re.findall(r"job\['(\w+)'\]", text))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'phone' for kw in node.keywords if kw.arg} | {'phase', 'nickname'}
        self.assertEqual(sorted(wanted - sent), [])

    def test_the_app_never_presses_a_withdraw_or_delete_button(self):
        text = dart('area5_edge.dart')
        for word in ('정말 영구 삭제', '_wdWithdraw', '채팅방 나가기', 'force-stop'):
            self.assertNotIn(word, text)


# ── E-EDGE-01 끊긴 망에서 저장 ───────────────────────────────────────────────────────────────────────

def edge01_steps():
    return [name for screen in SCREENS for name in (f'{screen}:edited', f'{screen}:failed')] + ['end']


class Edge01Test(EdgeBase):
    CASE = 'E-EDGE-01'

    def walks(self, **over):
        rows = [{'screen': s, 'error': NETWORK, 'error_above': True, 'kept': True, 'stayed': TITLES[s], 'saved_title': TITLES[ARRIVAL[s]]}
                for s in SCREENS]
        for row in rows:
            row.update(over.get(row['screen'], {}))
        return {'walks': rows}

    def on_step(self, early=None):
        def step(name, job):
            screen, _, kind = name.rpartition(':')
            if kind == 'failed' and screen == early:
                self.profile().update(height_cm=999)  # 끊긴 망인데 저장된 서버
            if name == 'end':
                self.save_all(job)
        return step

    def run01(self, answer=None, early=None):
        return self.go(self.CASE, {None: (edge01_steps(), answer or self.walks())}, self.on_step(early))[0]

    def test_pass_each_screen_fails_offline_keeps_the_value_and_saves_after_the_network_returns(self):
        result, note = self.run01()
        self.assertEqual(result, 'pass', note)
        airplanes = [e for e in self.events if isinstance(e, tuple) and e[0] == 'airplane']
        self.assertEqual(airplanes, [('airplane', True), ('airplane', False)] * 5)
        self.assertIn('ensure_online', self.events)
        self.assertEqual(self.profile()['height_cm'], 181)

    def test_it_waits_for_the_network_to_really_drop_before_the_app_saves(self):
        # 비행기 모드를 켠 직후 바로 앱이 저장을 누르면 망이 아직 살아 있어 첫 저장이 성공해 버린다 — 켠 바로 다음에 1~2초 쉰다.
        with mock.patch('time.sleep', lambda seconds: self.events.append(('sleep', seconds))):
            self.assertEqual(self.run01()[0], 'pass')
        cuts = [i for i, e in enumerate(self.events) if e == ('airplane', True)]
        self.assertEqual(len(cuts), 5)
        for i in cuts:
            nxt = self.events[i + 1]
            self.assertEqual(nxt[0], 'sleep', f'비행기 모드를 켠 뒤 바로 {nxt!r}')
            self.assertTrue(1 <= nxt[1] <= 2, nxt)

    def test_a_save_that_lands_while_offline_is_a_fail(self):
        result, note = self.run01(early='15-6')
        self.assertEqual(result, 'fail', note)
        self.assertIn('15-6', note)

    def test_a_wrong_message_a_lost_value_or_a_left_screen_is_a_fail(self):
        for over in ({'15c': {'error': '알 수 없는 오류'}}, {'tag': {'kept': False}}, {'06-1': {'stayed': TITLES['15-5']}},
                     {'15-7': {'error_above': False}}, {'tag': {'saved_title': TITLES['15-5']}}):
            with self.subTest(over):
                result, note = self.run01(self.walks(**over))
                self.assertEqual(result, 'fail', note)

    def test_it_is_blocked_without_the_paid_ai_switch(self):
        with mock.patch.dict(os.environ, {'E2E_REAL_AI': ''}):
            result, note = self.run01()
        self.assertEqual(result, 'blocked', note)
        self.assertFalse(self.fake.users)


# ── E-EDGE-11 계정이 사라진 뒤 저장 ──────────────────────────────────────────────────────────────────

class Edge11Test(EdgeBase):
    CASE = 'E-EDGE-11'

    def run11(self, said):
        return self.go(self.CASE, {None: (['opened'], said)})[0]

    def test_pass_the_user_is_deleted_mid_edit_and_save_lands_on_02_with_the_expired_notice(self):
        result, note = self.run11({'login': True, 'notice': EXPIRED, 'stayed': False})
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.fake.users, [])
        deletes = [s for s in self.fake.sent if s['method'] == 'DELETE' and s['path'].startswith('/auth/v1/admin/users/')]
        self.assertEqual([s['path'] for s in deletes], ['/auth/v1/admin/users/id-1'])

    def test_staying_on_15_6_or_a_missing_notice_is_a_fail(self):
        for said in ({'login': False, 'notice': None, 'stayed': True}, {'login': True, 'notice': None, 'stayed': False},
                     {'login': True, 'notice': '탈퇴한 계정이에요', 'stayed': False}):
            with self.subTest(said):
                result, note = self.run11(said)
                self.assertEqual(result, 'fail', note)

    def test_a_user_that_will_not_go_is_blocked(self):
        self.fake.handlers.insert(0, ('DELETE', re.compile(r'/auth/v1/admin/users/[^/]+'), Reply(500, {})))
        app = ScriptApp({None: (['opened'], {'login': True, 'notice': EXPIRED, 'stayed': False})}, self.events)
        result, note = self.case(self.CASE, None, app)[0]
        self.assertEqual(result, 'blocked', note)


# ── E-EDGE-15 알림으로 연 화면의 시스템 뒤로 ────────────────────────────────────────────────────────

class Edge15Test(EdgeBase):
    CASE = 'E-EDGE-15'

    def plan(self, chat='conversations', review='me'):
        return {'login': ([], {}), 'chat': (['opened'], {'opened': True, 'where': chat}),
                'review': (['opened'], {'opened': True, 'where': review})}

    def nick_of(self, n):
        return [s['body']['nickname'] for s in self.fake.sent if s['path'] == '/profile-onboarding/basic-info'][n - 1]

    def run15(self, plan=None, top=OURS):
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(201, {'id': 'm'}))
        self.fake.on('POST', r'/friend-reviews', Reply(201, {'id': 'r'}))
        self.fake.on('GET', r'/rest/v1/push_tokens', Reply(200, [{'token': 't'}]))
        new = lambda serial, before, **kw: [notify.Notice('a', self.nick_of(2), 'E2E', 'c'), notify.Notice('b', REVIEW_TITLE, '', 'c')]
        with mock.patch.object(notify, 'wait_new', new):
            app = ScriptApp(plan or self.plan(), self.events, top=top)
            return self.case(self.CASE, None, app)[0]

    def test_pass_both_opened_screens_go_where_the_arrow_goes_and_the_app_stays(self):
        result, note = self.run15()
        self.assertEqual(result, 'pass', note)
        self.assertEqual([e for e in self.events if e == 'back'], ['back', 'back'])
        self.assertEqual([e[1] for e in self.events if isinstance(e, tuple) and e[0] == 'tell'], ['chat', 'review'])
        self.assertEqual([e[1] for e in self.events if isinstance(e, tuple) and e[0] == 'tap'], [self.nick_of(2), REVIEW_TITLE])
        self.assertEqual(self.events.count('kill'), 2)

    def test_at_night_it_is_blocked_before_any_account_or_phone_work(self):
        # 방해 금지(22~08시)에는 "새 지인 리뷰가 도착했어요" 가 안 와 "알림이 안 옴" 으로 헛 blocked — 알림 시험은 서울 08~22시에만(notify.require_daytime).
        # 계정을 만들기 전에 막혀야 밤에 운영 계정 · 앱 준비를 낭비하지 않는다.
        order = []
        with mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=lambda now=None: (_ for _ in ()).throw(Blocked('서울 시각 07:00 알림 시험은 08:00~21:59 에만')))):
            with mock.patch.object(notify, 'ensure_delivery', lambda serial: order.append('delivery')):
                app = ScriptApp(self.plan(), self.events, top=OURS)
                result, note = self.case(self.CASE, None, app)[0]
        self.assertEqual(result, 'blocked', note)
        self.assertIn('08:00', note)
        self.assertEqual(order, [])  # 푸시 연결 점검보다 앞
        self.assertEqual(self.fake.sent, [])  # 계정 · 매칭 · 앱 어느 것도 안 만들었다
        self.assertEqual(self.events, [])

    def test_landing_elsewhere_or_a_closed_app_is_a_fail(self):
        result, note = self.run15(self.plan(chat='home'))
        self.assertEqual(result, 'fail', note)
        self.setUp()
        result, note = self.run15(top=LAUNCHER)
        self.assertEqual(result, 'fail', note)
        self.assertIn('닫힘', note)


# ── E-EDGE-19 저장 직후 강제 종료 ────────────────────────────────────────────────────────────────────

class Edge19Test(EdgeBase):
    CASE = 'E-EDGE-19'

    def run19(self, saved=True, shows=None, age=23, tail=''):
        def press(name, job):
            self.pids[:] = ['4242']  # 켤 때마다 새 프로세스
            if not saved:
                return
            n = self.fake.verifies
            if job.get('part') == 'nickname':
                self.profile(n).update(nickname=job['nickname'])
            else:
                rows = self.photo_rows(n)
                rows[0]['position'], rows[1]['position'] = rows[1]['position'], rows[0]['position']

        def after(job):
            n = self.fake.verifies
            if job['part'] == 'nickname':
                name = shows or self.profile(n)['nickname']
                return {'name_line': (name if age is None else f'{name}, {age}') + tail}  # 앱은 나이가 없으면 닉네임만 그린다(profile_hero.dart)
            return {'photos': [p['storage_path'].rsplit('/', 1)[1] for p in self.photo_rows(n)]}
        app = ScriptApp({'press': (['pressed'], {}), 'after': ([], after)}, self.events, press)
        return self.case(self.CASE, None, app)[0]

    def test_pass_the_screen_shows_what_the_db_holds_saved_or_not(self):
        for saved in (True, False):
            with self.subTest(saved=saved):
                self.setUp()
                result, note = self.run19(saved)
                self.assertEqual(result, 'pass', note)
                self.assertEqual(len([c for c in self.adb_calls if 'kill' in c]), 2)
                self.assertIn('저장됨' if saved else '옛 값', note)

    def test_pass_an_account_without_an_age_shows_the_bare_nickname(self):
        result, note = self.run19(True, age=None)
        self.assertEqual(result, 'pass', note)

    def test_a_screen_that_disagrees_with_the_db_is_a_fail(self):
        for age in (23, None):
            with self.subTest(age=age):
                self.setUp()
                result, note = self.run19(True, shows='반쯤', age=age)
                self.assertEqual(result, 'fail', note)
                self.assertIn('닉네임', note)

    def test_a_nickname_that_only_starts_with_the_db_value_is_a_fail(self):
        # 나이가 없는 줄은 DB 닉네임과 **같아야** 한다 — 닉네임으로 "시작" 만 하는 더 긴 이름은 다른 이름이다.
        result, note = self.run19(True, age=None, tail='다')
        self.assertEqual(result, 'fail', note)


# ── E-EDGE-21 두 번 누르기 ────────────────────────────────────────────────────────────────────────────

def edge21_steps():
    return [name for screen in SCREENS for name in (f'{screen}:start', f'{screen}:done')] + ['end']


class Edge21Test(EdgeBase):
    CASE = 'E-EDGE-21'

    def answer(self, **over):
        rows = [{'screen': s, 'second_blocked': True, 'saved_title': TITLES[ARRIVAL[s]]} for s in SCREENS]
        for row in rows:
            row.update(over.get(row['screen'], {}))
        return {'walks': rows}

    def run21(self, twice=(), answer=None, silent=()):
        def step(name, job):
            screen, _, kind = name.rpartition(':')
            if kind == 'done':
                self.log(screen, 0 if screen in silent else 2 if screen in twice else 1)
                if screen == '15-6':
                    self.profile().update(nickname=job['nickname'], nickname_changed_at=now().isoformat())
            if name == 'end':
                self.save_all(job)
        return self.go(self.CASE, {None: (edge21_steps(), answer or self.answer())}, step, serial='emulator-5554')[0]

    def test_pass_each_screen_sends_one_request_on_a_slow_network(self):
        result, note = self.run21()
        self.assertEqual(result, 'pass', note)
        emu_calls = [e for e in self.events if isinstance(e, str) and e.startswith('emu ')]
        self.assertEqual(emu_calls[0], 'emu network delay 2000')
        self.assertIn('emu network delay none', emu_calls)

    def test_two_requests_from_one_screen_is_a_fail(self):
        result, note = self.run21(twice=('tag',))
        self.assertEqual(result, 'fail', note)
        self.assertIn('tag', note)
        self.assertIn('2건', note)

    def test_it_runs_only_on_the_emulator(self):
        result, note = self.go(self.CASE, {None: (edge21_steps(), self.answer())})[0]
        self.assertEqual(result, 'blocked', note)
        self.assertIn('에뮬', note)


class LogDelayTest(EdgeBase):
    """Cloud Run 요청 로그는 늦게 들어온다 — 늦은 것(다시 읽기 · 끝내 없으면 blocked)과 진짜 0건(그 화면의 fail)을 가른다.
    창 시각이 서로 다르게 가짜 시계를 늘어나게 한다(윈도 시계 해상도로 창이 겹치는 것과 상관없이 돌게)."""
    CASE = 'E-EDGE-21'
    answer, run21 = Edge21Test.answer, Edge21Test.run21

    def setUp(self):
        super().setUp()
        self.reads, self.settles, self.late = [], [], 0  # 처음 [late] 번의 읽기는 아직 로그가 안 들어온 빈 답
        tick = [now()]

        def clock():
            tick[0] += timedelta(milliseconds=1)
            return tick[0]

        for patcher in (mock.patch.object(area5_edge, '_now', clock), mock.patch.object(sys.modules[__name__], 'now', clock),
                        mock.patch.object(area5_edge, '_requests', self.read),
                        mock.patch('time.sleep', lambda seconds: self.settles.append(seconds) if seconds == area5_edge.LOG_SETTLE else None)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def read(self, since, until):
        self.reads.append((since, until))
        return [] if len(self.reads) <= self.late else [r for r in self.logs if since <= r[0] <= until]

    def test_logs_that_come_late_are_read_again_and_then_judged(self):
        self.late = 2
        result, note = self.run21()
        self.assertEqual(result, 'pass', note)
        self.assertEqual((len(self.reads), len(self.settles)), (3, 3))  # 읽을 때마다 LOG_SETTLE 초 쉰다

    def test_logs_that_never_come_are_blocked_not_a_fail(self):
        self.late = 99
        result, note = self.run21()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('로그', note)
        self.assertEqual(len(self.reads), area5_edge.LOG_READS)

    def test_a_screen_with_no_request_after_every_read_is_still_a_fail(self):
        result, note = self.run21(silent=('tag',))
        self.assertEqual(result, 'fail', note)
        self.assertIn('tag', note)
        self.assertIn('0건', note)
        self.assertEqual(len(self.reads), area5_edge.LOG_READS)  # 늦은 것일 수 있어 끝까지 읽어 본 뒤의 fail

    def test_a_double_request_is_judged_at_the_first_read(self):
        result, note = self.run21(twice=('tag',))
        self.assertEqual(result, 'fail', note)
        self.assertIn('2건', note)
        self.assertEqual(len(self.reads), 1)  # 더 읽어도 늘기만 한다

    def test_one_screen_with_two_requests_and_another_with_none_is_a_fail_for_both_not_a_blocked(self):
        result, note = self.run21(twice=('tag',), silent=('15-6',))
        self.assertEqual(result, 'fail', note)
        self.assertIn('tag', note)
        self.assertIn('2건', note)
        self.assertIn('15-6', note)
        self.assertEqual(len(self.reads), area5_edge.LOG_READS)  # 0건인 창 때문에 끝까지 읽어 본 뒤의 판정

    def test_the_case_limits_hold_every_log_wait(self):
        for case in ('E-EDGE-21', 'E-EDGE-24'):
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 900 + area5_edge.LOG_READS * area5_edge.LOG_SETTLE, case)


# ── E-EDGE-24 느린 망에서 사진 4장 ────────────────────────────────────────────────────────────────────

class Edge24Test(EdgeBase):
    CASE = 'E-EDGE-24'

    def run24(self, said=None, requests=1):
        def step(name, job):
            if name == '15-7:done':
                self.log('15-7', requests)
                n = self.fake.verifies
                self.fake.tables['profile_photos'] = [p for p in self.fake.rows('profile_photos') if p['profile_id'] != f'id-{n}']
                for i in range(4):
                    self.fake.rows('profile_photos').append({'id': f'new{i}', 'profile_id': f'id-{n}', 'position': i,
                                                             'storage_path': f'id-{n}/new{i}.jpg', 'is_avatar_source': i == 0})
        good = {'loading_kept': True, 'extra_tap_blocked': True, 'title': TITLES['15-5'], 'photos': 4}
        return self.go(self.CASE, {None: (['15-7:start', '15-7:done', 'end'], {**good, **(said or {})})}, step, serial='emulator-5554')[0]

    def test_pass_the_spinner_holds_and_four_new_photos_land_with_one_request(self):
        result, note = self.run24()
        self.assertEqual(result, 'pass', note)
        emu_calls = [e for e in self.events if isinstance(e, str) and e.startswith('emu ')]
        self.assertEqual(emu_calls[:2], ['emu network speed edge', 'emu network delay gprs'])
        self.assertEqual(emu_calls[-2:], ['emu network speed full', 'emu network delay none'])

    def test_a_dropped_spinner_or_two_requests_is_a_fail(self):
        for said, requests in (({'loading_kept': False}, 1), ({'extra_tap_blocked': False}, 1), ({}, 2), ({'photos': 3}, 1)):
            with self.subTest(said=said, requests=requests):
                self.setUp()
                result, note = self.run24(said, requests)
                self.assertEqual(result, 'fail', note)


# ── E-EDGE-25 응답 없는 망 ────────────────────────────────────────────────────────────────────────────

class Edge25Test(EdgeBase):
    CASE = 'E-EDGE-25'

    def run25(self, said=None):
        good = {'loading_at_end': True, 'error': None, 'title': TITLES['15-6'], 'waited_ms': 120000}
        return self.go(self.CASE, {None: (['15-6:ready', '15-6:watched', 'end'], {**good, **(said or {})})}, serial='emulator-5554')[0]

    def test_pass_records_what_the_screen_showed_after_two_minutes_and_restores_the_network(self):
        result, note = self.run25()
        self.assertEqual(result, 'pass', note)
        self.assertIn('root', self.events)
        self.assertFalse(self.dropped())
        self.assertIn('로딩', note)
        self.assertIn('시간 제한', note)

    def test_a_spinner_that_ended_is_still_recorded_not_failed(self):
        result, note = self.run25({'loading_at_end': False, 'error': NETWORK})
        self.assertEqual(result, 'pass', note)
        self.assertIn(NETWORK, note)

    def test_an_app_that_did_not_wait_the_two_minutes_is_a_fail(self):
        result, note = self.run25({'waited_ms': 5000})
        self.assertEqual(result, 'fail', note)

    def test_a_network_that_still_answers_is_blocked(self):
        with mock.patch.object(emu, 'online', lambda serial: True):
            result, note = self.run25()
        self.assertEqual(result, 'blocked', note)
        self.assertFalse(self.dropped())

    def iptables_calls(self):
        return [e for e in self.events if isinstance(e, str) and 'tables ' in e]

    def test_every_iptables_call_waits_for_the_xtables_lock(self):
        self.run25()
        calls = self.iptables_calls()
        for verb in ('-I', '-D', '-S'):
            self.assertTrue([c for c in calls if f' {verb} ' in c], f'{verb} 호출이 없음 — {calls}')
        self.assertEqual([c for c in calls if ' -w ' not in c], [])

    def test_a_rule_hung_twice_is_removed_until_none_is_left(self):
        self.rules = {'iptables': 2, 'ip6tables': 2}  # 앞선 판들이 남긴 규칙 — 이번 판이 하나씩 더 건다(-D 한 번씩으로는 다 못 지운다)
        result, note = self.run25()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.rules, {'iptables': 0, 'ip6tables': 0})

    def test_a_rule_that_cannot_be_removed_is_recorded_loudly_with_the_cold_boot_hint(self):
        self.stubborn = {'ip6tables'}
        with contextlib.redirect_stderr(io.StringIO()) as shown:
            result, note = self.run25()
        self.assertEqual(result, 'fail', note)
        self.assertIn('cold boot', note)
        self.assertIn('ip6tables', note)
        self.assertIn('cold boot', shown.getvalue())

    def run25_that_throws(self):
        def boom(name, job):
            if name == '15-6:watched':
                raise RuntimeError('boom')
        with contextlib.redirect_stderr(io.StringIO()):
            self.go(self.CASE, {None: (['15-6:ready', '15-6:watched', 'end'], {})}, on_step=boom, serial='emulator-5554')

    def test_a_body_that_throws_still_removes_the_rules_and_its_own_error_survives(self):
        with self.assertRaisesRegex(RuntimeError, 'boom'):
            self.run25_that_throws()
        self.assertFalse(self.dropped())

    def test_the_original_error_survives_even_when_a_rule_cannot_be_removed(self):
        self.stubborn = {'iptables'}
        with self.assertRaisesRegex(RuntimeError, 'boom'):
            self.run25_that_throws()


if __name__ == '__main__':
    unittest.main()
