"""영역 4 알림(PUSH) A4 — 토큰 · 권한 · 로그인/로그아웃 PC 쪽 시험. 폰 · 운영 없이 가짜 앱 · 가짜 DB · 가짜 알림 헬퍼로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area4_push_a4`."""

import subprocess
import tempfile
import unittest
from pathlib import Path
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from e2e import area1, area4_push_a4 as push, notify, tools
from e2e.test_area1 import Base, FakeServer
from e2e.test_area1_phone import APP_PASS
from e2e.tools import Blocked, Reply

CASES = ['E-PUSH-55', 'E-PUSH-58', 'E-PUSH-59', 'E-PUSH-60', 'E-PUSH-61', 'E-PUSH-62', 'E-PUSH-63', 'E-PUSH-66', 'E-PUSH-67',
         'E-PUSH-68', 'E-PUSH-69']
TOKEN = {'token': 'DEVICE-TOKEN', 'platform': 'android'}


def now():
    return datetime.now(timezone.utc)


def notice(nick, title=push.TITLE):
    return notify.Notice(key=f'k-{nick}', title=title, text=f'{nick} 님이 대화를 하고 싶어 해요', channel='c')


class Db(FakeServer):
    """FakeServer + 계정별 push_tokens · 알림 스위치 행(시험이 바꾼다)."""

    def __init__(self):
        super().__init__()
        self.tokens = {}
        self.settings = []
        self.deleted = []

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        parts = urlsplit(url)
        query = parse_qs(parts.query)
        if method == 'GET' and parts.path == '/rest/v1/push_tokens':
            self.calls.append((method, parts.path, body))
            self.urls.append((method, url))
            who = query['profile_id'][0].removeprefix('eq.')
            return Reply(200, [dict(row) for row in self.tokens.get(who, [])])
        if method == 'GET' and parts.path == '/rest/v1/notification_settings':
            self.calls.append((method, parts.path, body))
            self.urls.append((method, url))
            return Reply(200, [dict(row) for row in self.settings])
        if method == 'POST' and parts.path == '/cards/push-tokens':  # 받는 사람(id-1) 계정으로 가짜 토큰을 넣는 API
            self.calls.append((method, parts.path, body))
            self.urls.append((method, url))
            self.tokens.setdefault('id-1', []).append({'token': body['token'], 'platform': body['platform']})
            return Reply(200, {'ok': True})
        if method == 'DELETE' and parts.path.startswith('/cards/push-tokens/'):
            self.calls.append((method, parts.path, body))
            self.urls.append((method, url))
            gone = parts.path.rsplit('/', 1)[1]
            self.tokens['id-1'] = [r for r in self.tokens.get('id-1', []) if r['token'] != gone]
            return Reply(200, {'ok': True})
        return super().__call__(method, url, headers, body, raw)


class App:
    """가짜 앱. 켤 때마다 [scripts] 의 한 줄(= 멈출 때마다 PC 가 하기 전에 일어나는 일들)을 따른다. 일감은 [jobs] 에 쌓인다."""

    def __init__(self, *scripts, top='', after=None):
        self.serial = 'S1'
        self.jobs = []
        self.top_line = top
        self._after = after
        self.launched = None  # PushBase.go 가 로그에 "앱을 켰다" 를 남기도록 건다
        self._scripts = list(scripts)
        self._queue = []
        self.hub = SimpleNamespace(go=mock.Mock(), wait=mock.Mock(side_effect=self._next))

    def _next(self, timeout):
        self._queue.pop(0)()
        return {'step': 'next'}

    def top(self):
        return self.top_line

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if self.launched:
            self.launched()
        script = self._scripts.pop(0) if self._scripts else []
        if midway and script:
            self._queue = list(script[1:])
            script[0]()
            midway({'step': 'first'})
        elif script:
            script[0]()
        if self._after:
            self._after()  # 앱이 끝난 뒤 서버에서 일어난 일(로그아웃으로 행이 지워짐 등)
        return APP_PASS


class PushBase(Base):
    def setUp(self):
        super().setUp()
        self.db = Db()
        patcher = mock.patch.object(tools, 'call', self.db)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.log = []
        self.sent = []
        self.arrivals = []  # wait_new 가 차례로 돌려줄 알림 목록
        self.silence = []  # expect_none 이 차례로 돌려줄 알림 목록
        record = lambda name, result=None: mock.Mock(side_effect=lambda *a, **k: self.log.append(name) or result)
        names = dict(require_daytime=record('daytime'), grant_notifications=record('grant'), revoke_notifications=record('revoke'),
                     background=record('background'), read_notifications=record('read', []), airplane=mock.Mock(side_effect=lambda s, on, *a, **k: self.log.append('airplane_on' if on else 'airplane_off')),
                     ensure_online=record('online'), ensure_delivery=record('delivery'),
                     wait_new=mock.Mock(side_effect=lambda *a, **k: self.log.append('wait_new') or (self.arrivals.pop(0) if self.arrivals else [])),
                     expect_none=mock.Mock(side_effect=lambda *a, **k: self.log.append('expect_none') or (self.silence.pop(0) if self.silence else [])))
        self.m = names  # patch.multiple 은 명시한 가짜를 돌려주지 않으니 직접 쥔다
        self.notify = mock.patch.multiple(push.notify, **names)
        self.notify.start()
        self.addCleanup(self.notify.stop)
        mine = dict(_forget_permission=record('forget'), _deny_dialog=record('deny'), _front=record('front'),
                    _granted=mock.Mock(return_value=False))
        self.p = mine
        self.mine = mock.patch.multiple(push, **mine)
        self.mine.start()
        self.addCleanup(self.mine.stop)
        send = mock.patch.object(push, '_send_one', side_effect=self._send)
        send.start()
        self.addCleanup(send.stop)
        for name, value in (('TOKEN_WAIT', 0.05), ('GONE_WAIT', 0.05), ('MARKETING_WAIT', 0.05), ('SETTINGS_WAIT', 0.05), ('DISCARD_WAIT', 0)):
            patcher = mock.patch.object(push, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        sleep = mock.patch.object(push.time, 'sleep')
        self.sleep = sleep.start()
        self.addCleanup(sleep.stop)

    def _send(self, run, receiver):
        nick = f'Nick{len(self.sent) + 1}'
        self.sent.append((receiver['id'], nick))
        self.log.append(f'send:{receiver["id"]}')
        return nick

    def go(self, case, app):
        app.launched = lambda: self.log.append('launch')
        self.db._ids = 0  # 한 시험에서 여러 번 돌려도 받는 계정이 늘 id-1 이다(토큰 행을 id-1 로 둔다)
        self.db.users.clear()
        self.sent.clear()  # 보낸 사람 닉네임도 Nick1 부터
        return area1.attempt_phone(self.run, case, app)

    def has_token(self, who='id-1'):
        self.db.tokens[who] = [dict(TOKEN)]


class BundleTest(unittest.TestCase):
    def test_bundle_is_the_eleven_push_a4_cases_and_each_has_a_longer_limit_only_when_slow(self):
        self.assertEqual(area1.BUNDLES['area4-push-a4'], CASES)
        self.assertLessEqual(set(CASES), set(area1.PHONE))
        for case in ('E-PUSH-59', 'E-PUSH-60', 'E-PUSH-61', 'E-PUSH-66', 'E-PUSH-67', 'E-PUSH-68'):
            self.assertGreater(tools.CASE_LIMITS[case], tools.CASE_LIMIT, case)

    def test_the_wait_for_the_apps_token_discard_retry_is_longer_than_its_one_minute_interval(self):
        self.assertGreater(push.DISCARD_WAIT, 60)  # push_registrar.dart `_retryDelay` 1분 — 시나리오의 "최대 1분 기다린 뒤"

    def test_cases_left_out_of_the_bundle_say_why(self):
        for case in ('E-PUSH-56', 'E-PUSH-57', 'E-PUSH-64', 'E-PUSH-65', 'E-PUSH-71'):
            self.assertTrue(push.LEFT_OUT[case], case)


class DeviceHelperTest(unittest.TestCase):
    DUMP = ('Package [x] (1):\n    runtime permissions:\n      android.permission.CAMERA: granted=true\n'
            '      android.permission.POST_NOTIFICATIONS: granted={}, flags=[ USER_SET]\n')

    install_reply = 'Performing Streamed Install' + chr(10) + 'Success' + chr(10)

    def adb(self, *texts):
        replies = list(texts)
        calls = []
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        apk = Path(folder.name) / 'app-debug.apk'
        apk.write_bytes(b'apk')
        self.apk = apk
        patcher = mock.patch.object(push, 'APK', apk)
        patcher.start()
        self.addCleanup(patcher.stop)

        def run(serial, *args, check=True):
            calls.append(args)
            if args[0] == 'install':
                return self.install_reply
            return replies.pop(0) if replies and args[:3] == ('shell', 'dumpsys', 'package') else ''

        patcher = mock.patch.object(push.tools, 'adb', side_effect=run)
        patcher.start()
        self.addCleanup(patcher.stop)
        return calls

    def test_granted_reads_the_notification_permission_from_dumpsys(self):
        self.adb(self.DUMP.format('true'), self.DUMP.format('false'), 'no runtime permissions here')
        self.assertEqual([push._granted('S1') for _ in range(3)], [True, False, None])

    def test_forget_permission_uninstalls_then_installs_without_granting_and_checks_it_is_not_granted(self):
        calls = self.adb(self.DUMP.format('false'))
        push._forget_permission('S1')
        # 삼성 · 안드로이드 14 는 `pm clear` 로는 알림 권한이 "안 물어봄" 으로 안 돌아온다 — 앱을 지웠다 다시 깐다. `-g` 를 주면 권한이 켜진다
        self.assertEqual([c for c in calls if c[0] in ('uninstall', 'install')],
                         [('uninstall', push.tools.PACKAGE), ('install', '-r', str(self.apk))])
        self.assertNotIn(('shell', 'pm', 'clear', push.tools.PACKAGE), calls)

    def test_forget_permission_without_a_built_apk_blocks_before_uninstalling(self):
        calls = self.adb(self.DUMP.format('false'))
        self.apk.unlink()
        with self.assertRaises(Blocked) as caught:
            push._forget_permission('S1')
        self.assertIn('APK', str(caught.exception))
        self.assertEqual([c for c in calls if c[0] in ('uninstall', 'install')], [])

    def test_forget_permission_blocks_with_the_reason_when_adb_install_exits_nonzero(self):
        # 실제 adb install 은 실패하면 종료 코드 1 + 사유는 stderr — tools.adb 는 stdout 만 돌려주므로 예외로 온다
        calls = self.adb(self.DUMP.format('false'))
        error = subprocess.CalledProcessError(1, ['adb', 'install'], output='', stderr='adb: failed to install: Failure [INSTALL_FAILED_USER_RESTRICTED]')
        real = push.tools.adb.side_effect
        push.tools.adb.side_effect = lambda serial, *a, **k: (_ for _ in ()).throw(error) if a[0] == 'install' else real(serial, *a, **k)
        with self.assertRaises(Blocked) as caught:
            push._forget_permission('S1')
        self.assertIn('INSTALL_FAILED_USER_RESTRICTED', str(caught.exception))
        self.assertIn('앱이 지워진 채', str(caught.exception))  # 폰에 앱이 없을 수 있다 — 다음 가설이 엉뚱한 사유로 막히지 않게 알린다
        self.assertIn(('uninstall', push.tools.PACKAGE), calls)

    def test_forget_permission_blocks_when_the_install_does_not_succeed(self):
        self.adb(self.DUMP.format('false'))
        self.install_reply = 'Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]'
        with self.assertRaises(Blocked) as caught:
            push._forget_permission('S1')
        self.assertIn('INSTALL_FAILED_USER_RESTRICTED', str(caught.exception))

    def test_forget_permission_blocks_when_it_is_still_granted_or_unreadable(self):
        for dump, word in ((self.DUMP.format('true'), '허용'), ('nothing', '13')):
            self.adb(dump)
            with self.assertRaises(Blocked) as caught:
                push._forget_permission('S1')
            self.assertIn(word, str(caught.exception))

    NODE = '<node text="{text}" resource-id="{rid}" bounds="[{box}]" />'
    ALLOW, DENY = '10,20][30,40', '100,200][300,400'  # 허용 버튼과 거부 버튼은 자리가 다르다 — 누른 좌표로 구분한다

    def dialog(self, *nodes):
        xml = '<?xml version="1.0"?><hierarchy>' + ''.join(nodes) + '</hierarchy>'
        patcher = mock.patch.object(push.notify, '_ui_dump', return_value=xml)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.taps = self.adb()
        patcher = mock.patch.object(push.time, 'sleep')
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_deny_dialog_taps_the_deny_button_found_by_its_resource_id(self):
        self.dialog(self.NODE.format(text='허용', rid='com.android.permissioncontroller:id/permission_allow_button', box=self.ALLOW),
                    self.NODE.format(text='거부함', rid='com.android.permissioncontroller:id/permission_deny_button', box=self.DENY))
        push._deny_dialog('S1')
        taps = [c for c in self.taps if c[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [('shell', 'input', 'tap', '200', '300')])  # 거부 자리만, 허용 자리는 한 번도 안 누른다

    def test_deny_dialog_falls_back_to_the_button_text(self):
        self.dialog(self.NODE.format(text='허용', rid='', box=self.ALLOW), self.NODE.format(text='허용 안 함', rid='', box=self.DENY))
        push._deny_dialog('S1')
        taps = [c for c in self.taps if c[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [('shell', 'input', 'tap', '200', '300')])

    def test_deny_dialog_blocks_when_no_dialog_shows_up_so_the_phone_is_not_a_first_run(self):
        self.dialog(self.NODE.format(text='다른 글', rid='x', box=self.ALLOW))
        with mock.patch.object(push, 'DIALOG_WAIT', 0.05):
            with self.assertRaises(Blocked) as caught:
                push._deny_dialog('S1')
        self.assertIn('권한 창', str(caught.exception))

    def test_front_launches_the_app_again(self):
        calls = self.adb()
        push._front('S1')
        self.assertTrue(any(c[:3] == ('shell', 'monkey', '-p') and push.tools.PACKAGE in c for c in calls))


WAITS_FOR_NOTICES = ['E-PUSH-59', 'E-PUSH-60', 'E-PUSH-61', 'E-PUSH-66', 'E-PUSH-67', 'E-PUSH-68', 'E-PUSH-69']


class DeliveryTest(PushBase):
    """알림을 기다리는 가설은 시작 때 푸시 연결을 한 번 점검한다 — 연결이 죽은 폰의 "안 옴" 이 결함처럼 보이지 않게."""

    def test_every_case_that_waits_for_a_notice_checks_delivery_once_right_after_the_daytime_gate(self):
        for case in WAITS_FOR_NOTICES:
            self.log.clear()
            self.go(case, App())
            self.assertEqual(self.log.count('delivery'), 1, case)
            self.assertEqual(self.log[:2], ['daytime', 'delivery'], case)

    def test_a_broken_delivery_blocks_before_touching_the_phone_or_the_account(self):
        self.m['ensure_delivery'].side_effect = Blocked('GCM 연결 횟수를 못 읽음')
        for case in WAITS_FOR_NOTICES:
            self.log.clear()
            self.db.urls.clear()
            self.assertEqual(self.go(case, App())[0], 'blocked', case)
            self.assertFalse({'forget', 'grant', 'launch'} & set(self.log), case)
            self.assertFalse([u for m, u in self.db.urls if m == 'POST' and 'admin/users' in u], case)  # 계정도 안 만든다

    def test_cases_that_never_wait_for_a_notice_do_not_touch_delivery(self):
        for case in ('E-PUSH-55', 'E-PUSH-58', 'E-PUSH-62', 'E-PUSH-63'):
            self.log.clear()
            self.go(case, App())
            self.assertNotIn('delivery', self.log, case)


class Push55Test(PushBase):
    def settings(self, marketing, at):
        self.db.settings = [{'marketing': marketing, 'marketing_consented_at': at}]

    def test_marketing_on_stamps_the_server_time_and_off_clears_it(self):
        app = App([lambda: self.settings(True, now().isoformat()), lambda: self.settings(False, None)])
        self.assertEqual(self.go('E-PUSH-55', app)[0], 'pass')
        self.assertNotIn('daytime', self.log)  # 보내는 알림이 없다
        # 앞 묶음이 끝에서 권한을 거두면 권한 창이 앱을 가린다 — 켜기 전에 주고 끝에 되돌린다
        self.assertEqual((self.log[0], self.log[1], self.log[-1]), ('grant', 'launch', 'revoke'))

    def test_fails_when_the_time_is_far_from_now_or_missing_or_not_cleared(self):
        for on, off in (((True, (now() - timedelta(minutes=5)).isoformat()), (False, None)),
                        ((True, None), (False, None)),
                        ((True, now().isoformat()), (False, now().isoformat())),
                        ((True, now().isoformat()), (True, None))):
            app = App([lambda on=on: self.settings(*on), lambda off=off: self.settings(*off)])
            self.assertEqual(self.go('E-PUSH-55', app)[0], 'fail', (on, off))

    def test_fails_when_marketing_never_turned_on(self):
        app = App([lambda: self.settings(False, None), lambda: self.settings(False, None)])
        result, note = self.go('E-PUSH-55', app)
        self.assertEqual(result, 'fail')
        self.assertIn('marketing', note)


class Push58Test(PushBase):
    def test_login_registers_one_android_row_within_thirty_seconds(self):
        app = App([lambda: self.has_token()])
        self.assertEqual(self.go('E-PUSH-58', app)[0], 'pass')
        self.assertEqual(self.log[0], 'grant')
        self.assertEqual(self.log[-1], 'revoke')

    def test_fails_when_no_row_or_a_non_android_row_or_two_rows(self):
        for rows in ([], [{'token': 'T', 'platform': 'ios'}], [dict(TOKEN), {'token': 'T2', 'platform': 'android'}]):
            app = App([lambda rows=rows: self.db.tokens.__setitem__('id-1', rows)])
            self.assertEqual(self.go('E-PUSH-58', app)[0], 'fail', rows)

    def test_the_permission_goes_back_even_when_the_app_says_blocked(self):
        app = App()
        app.__class__ = type('B', (App,), {'__call__': lambda this, midway=None, **job: {'result': 'blocked', 'note': 'x'}})
        self.assertEqual(self.go('E-PUSH-58', app)[0], 'blocked')
        self.assertEqual(self.log[-1], 'revoke')


class Push59Test(PushBase):
    def test_denying_the_first_permission_dialog_keeps_the_app_usable_and_registers_nothing(self):
        app = App([lambda: None])
        self.assertEqual(self.go('E-PUSH-59', app)[0], 'pass')
        # 새로 설치한 것처럼 만든 뒤 → 권한 창을 거부 → 알림 하나 보냄 → 60초 동안 0개
        self.assertEqual([e for e in self.log if e in ('daytime', 'forget', 'deny', 'read', 'send:id-1', 'expect_none')],
                         ['daytime', 'forget', 'deny', 'read', 'send:id-1', 'expect_none'])
        self.assertEqual(app.jobs[0]['phase'], 'deny')

    def test_fails_when_a_token_row_was_registered_anyway(self):
        app = App([lambda: self.has_token()])
        result, note = self.go('E-PUSH-59', app)
        self.assertEqual(result, 'fail')
        self.assertIn('push_tokens', note)

    def test_fails_when_a_notice_arrived_or_the_permission_ended_granted(self):
        self.silence = [[notice('Nick1')]]
        self.assertEqual(self.go('E-PUSH-59', App([lambda: None]))[0], 'fail')
        self.p['_granted'].return_value = True
        self.assertEqual(self.go('E-PUSH-59', App([lambda: None]))[0], 'fail')

    def test_blocks_at_night_before_touching_the_phone(self):
        self.m['require_daytime'].side_effect = Blocked('서울 시각 23:00')
        self.assertEqual(self.go('E-PUSH-59', App([lambda: None]))[0], 'blocked')
        self.assertNotIn('forget', self.log)

    def test_the_permission_is_given_back_when_the_dialog_never_shows(self):
        self.p['_deny_dialog'].side_effect = Blocked('권한 창이 안 뜸')
        self.assertEqual(self.go('E-PUSH-59', App([lambda: None]))[0], 'blocked')
        self.assertEqual(self.log[-1], 'grant')  # 앱을 새로 깐 폰은 허용 상태로 돌려 둔다


class Push60Test(PushBase):
    def test_granting_after_the_denial_and_relaunching_registers_then_the_notice_arrives(self):
        self.arrivals = [[notice('Nick1')]]
        app = App([lambda: None], [lambda: self.has_token()])
        self.assertEqual(self.go('E-PUSH-60', app)[0], 'pass')
        self.assertEqual([j.get('phase') for j in app.jobs], ['deny', 'again'])
        self.assertIs(app.jobs[1]['fresh'], False)
        order = [e for e in self.log if e in ('forget', 'launch', 'deny', 'grant', 'background', 'send:id-1', 'wait_new')]
        self.assertEqual(order, ['forget', 'launch', 'deny', 'grant', 'launch', 'background', 'send:id-1', 'wait_new', 'grant'])  # 권한은 다시 켜기 전에, 끝에서 한 번 더(허용으로 돌려 둠)

    def test_fails_when_no_row_after_the_relaunch_or_the_notice_does_not_come(self):
        self.arrivals = [[notice('Nick1')]]
        self.assertEqual(self.go('E-PUSH-60', App([lambda: None], [lambda: None]))[0], 'fail')
        self.arrivals = [[]]
        self.assertEqual(self.go('E-PUSH-60', App([lambda: None], [lambda: self.has_token()]))[0], 'fail')

    def test_a_notice_with_another_senders_name_is_not_the_one(self):
        self.arrivals = [[notice('Someone')]]
        self.assertEqual(self.go('E-PUSH-60', App([lambda: None], [lambda: self.has_token()]))[0], 'fail')


class Push60EndTest(PushBase):
    def test_the_phone_is_left_with_the_permission_granted_whether_the_case_passes_or_fails(self):
        self.arrivals = [[notice('Nick1')]]
        self.go('E-PUSH-60', App([lambda: None], [lambda: self.has_token()]))
        self.assertEqual(self.log[-1], 'grant')
        self.go('E-PUSH-60', App([lambda: None], []))
        self.assertEqual(self.log[-1], 'grant')

    def test_a_restore_that_cannot_grant_does_not_change_the_result(self):
        self.arrivals = [[notice('Nick1')]]

        def grant(*args, **kwargs):
            self.log.append('grant')
            if self.log.count('grant') > 1:  # 권한을 다시 켜는 첫 번째는 되고, 끝에서 허용으로 돌려 두는 두 번째가 실패
                raise Blocked('pm grant 실패')

        self.m['grant_notifications'].side_effect = grant
        self.assertEqual(self.go('E-PUSH-60', App([lambda: None], [lambda: self.has_token()]))[0], 'pass')


class Push61Test(PushBase):
    def test_revoking_keeps_the_row_but_silences_and_granting_again_brings_the_notice(self):
        self.silence = [[]]
        self.arrivals = [[notice('Nick2')]]
        app = App([lambda: self.has_token()])
        self.assertEqual(self.go('E-PUSH-61', app)[0], 'pass')
        order = [e for e in self.log if e in ('grant', 'background', 'revoke', 'send:id-1', 'expect_none', 'wait_new')]
        self.assertEqual(order, ['grant', 'background', 'revoke', 'send:id-1', 'expect_none', 'grant', 'send:id-1', 'wait_new', 'revoke'])

    def test_fails_when_a_notice_shows_while_revoked_or_none_after_granting_or_the_row_vanished(self):
        self.silence = [[notice('Nick1')]]
        self.arrivals = [[notice('Nick2')]]
        self.assertEqual(self.go('E-PUSH-61', App([lambda: self.has_token()]))[0], 'fail')
        self.silence, self.arrivals = [[]], [[]]
        self.assertEqual(self.go('E-PUSH-61', App([lambda: self.has_token()]))[0], 'fail')
        self.silence, self.arrivals = [[]], [[notice('Nick2')]]
        app = App([lambda: self.has_token()])
        self.m['revoke_notifications'].side_effect = lambda *a: self.db.tokens.clear()  # 끈 순간 행이 사라짐
        self.assertEqual(self.go('E-PUSH-61', app)[0], 'fail')

    def test_blocks_when_no_row_ever_registers(self):
        self.assertEqual(self.go('E-PUSH-61', App([lambda: None]))[0], 'blocked')


class Push62Test(PushBase):
    SETTINGS = 'mResumedActivity: ActivityRecord{1 u0 com.android.settings/.Settings$AppNotificationSettingsActivity t5}'

    def test_the_box_and_button_open_the_apps_settings_and_coming_back_after_granting_hides_the_box(self):
        app = App([lambda: None, lambda: None], top=self.SETTINGS)
        result, note = self.go('E-PUSH-62', app)
        self.assertEqual(result, 'pass')
        self.assertIn('사람', note)  # 설정 앱의 어느 화면인지는 사람이 본다
        order = [e for e in self.log if e in ('daytime', 'forget', 'deny', 'grant', 'front')]
        self.assertEqual(order, ['forget', 'deny', 'grant', 'front', 'grant'])  # 끝에서 허용으로 돌려 둔다. 보내는 알림이 없어 낮시간 확인도 없다
        self.assertEqual(app.jobs[0]['phase'], 'deny')

    def test_fails_when_the_settings_app_never_comes_to_the_front(self):
        result, note = self.go('E-PUSH-62', App([lambda: None, lambda: None], top='mResumedActivity: com.example/.Main'))
        self.assertEqual(result, 'fail')
        self.assertIn('설정 앱', note)

    def test_the_permission_is_given_back_at_the_end(self):
        self.go('E-PUSH-62', App([lambda: None, lambda: None], top=self.SETTINGS))
        self.assertEqual(self.log[-1], 'grant')


class Push63Test(PushBase):
    def stage(self, tokens_after_login, tokens_after_gate):
        return App([lambda: self.db.tokens.__setitem__('id-1', tokens_after_login), lambda: self.db.tokens.__setitem__('id-1', tokens_after_gate)])

    def test_the_token_registers_before_the_gate_and_stays_one_row_after_the_gate_opens(self):
        app = self.stage([dict(TOKEN)], [dict(TOKEN)])
        self.assertEqual(self.go('E-PUSH-63', app)[0], 'pass')
        patches = [(u, b) for (m, u), (_, _, b) in zip(self.db.urls, self.db.calls) if m == 'PATCH']
        self.assertEqual(len(patches), 2)  # pending 계정 만들기 · 통과 처리
        self.assertTrue(patches[-1][0].endswith('id=eq.id-1') and patches[-1][1] == {'student_verification': 'verified'})

    def test_fails_when_no_row_before_the_gate_or_more_rows_or_another_token_after(self):
        for first, second in (([], [dict(TOKEN)]), ([dict(TOKEN)], [dict(TOKEN), {'token': 'T2', 'platform': 'android'}]),
                              ([dict(TOKEN)], [{'token': 'OTHER', 'platform': 'android'}]), ([dict(TOKEN)], [])):
            self.assertEqual(self.go('E-PUSH-63', self.stage(first, second))[0], 'fail', (first, second))

    def test_the_permission_goes_back_at_the_end(self):
        self.go('E-PUSH-63', self.stage([dict(TOKEN)], [dict(TOKEN)]))
        self.assertEqual((self.log[0], self.log[-1]), ('grant', 'revoke'))


class Push66Test(PushBase):
    def test_a_notice_arrives_while_logged_in_then_after_logout_none_and_the_row_is_gone(self):
        self.arrivals = [[notice('Nick1')]]
        self.silence = [[]]
        app = App([lambda: self.has_token()], after=self.db.tokens.clear)  # 앱이 로그아웃 → 서버가 행을 지움
        self.assertEqual(self.go('E-PUSH-66', app)[0], 'pass')
        order = [e for e in self.log if e in ('daytime', 'grant', 'background', 'send:id-1', 'wait_new', 'front', 'expect_none')]
        self.assertEqual(order, ['daytime', 'grant', 'background', 'send:id-1', 'wait_new', 'front', 'send:id-1', 'expect_none'])
        self.assertEqual(self.log[-1], 'revoke')

    def test_fails_when_the_row_stays_or_a_notice_comes_after_logout_or_none_came_before(self):
        for clear, silence, arrivals in ((False, [[]], [[notice('Nick1')]]), (True, [[notice('Nick2')]], [[notice('Nick1')]])):
            self.db.tokens = {}
            self.silence, self.arrivals = list(silence), list(arrivals)
            app = App([lambda: self.has_token()], after=self.db.tokens.clear if clear else None)
            self.assertEqual(self.go('E-PUSH-66', app)[0], 'fail', (clear, silence, arrivals))

    def test_blocks_when_no_notice_arrives_even_while_logged_in_because_a_later_zero_would_prove_nothing(self):
        self.arrivals = [[]]
        app = App([lambda: self.has_token()], after=self.db.tokens.clear)
        result, note = self.go('E-PUSH-66', app)
        self.assertEqual(result, 'blocked')
        self.assertIn('로그인', note)


class Push67Test(PushBase):
    def moved(self, first, second):
        return App([lambda: self.db.tokens.__setitem__('id-1', first),
                    lambda: (self.db.tokens.clear(), self.db.tokens.update(second))])

    def test_the_same_device_token_moves_to_the_new_account_and_only_that_account_gets_the_notice(self):
        self.arrivals = [[notice('Nick2')]]
        self.silence = [[notice('Nick2')]]  # 그 뒤에도 새로 생긴 우리 앱 알림은 새 계정 것 하나뿐
        app = self.moved([dict(TOKEN)], {'id-2': [dict(TOKEN)]})
        self.assertEqual(self.go('E-PUSH-67', app)[0], 'pass')
        self.assertIn('second', app.jobs[0])
        self.assertEqual(self.sent, [('id-1', 'Nick1'), ('id-2', 'Nick2')])

    def test_fails_when_the_token_stays_with_the_old_account_or_changed_or_the_old_account_gets_a_notice(self):
        c_notice = [[notice('Nick2')]]
        for second, arrivals, silence in (
                ({'id-1': [dict(TOKEN)]}, c_notice, c_notice),  # 옛 계정 행이 그대로
                ({'id-2': [{'token': 'OTHER', 'platform': 'android'}]}, c_notice, c_notice),  # 토큰이 달라짐
                ({'id-2': [dict(TOKEN)]}, c_notice, [[notice('Nick1'), notice('Nick2')]]),  # 옛 계정에도 알림이 옴
                ({'id-2': [dict(TOKEN)]}, [[]], [[]])):  # 새 계정은 알림이 안 옴
            self.db.tokens = {}
            self.arrivals, self.silence = [list(a) for a in arrivals], [list(a) for a in silence]
            self.assertEqual(self.go('E-PUSH-67', self.moved([dict(TOKEN)], second))[0], 'fail', (second, silence))

    def test_blocks_when_the_first_account_never_registers_a_token(self):
        self.assertEqual(self.go('E-PUSH-67', self.moved([], {}))[0], 'blocked')


class Push68Test(PushBase):
    def test_logging_out_offline_keeps_the_server_row_then_after_the_network_returns_the_dead_token_gets_nothing(self):
        patcher = mock.patch.object(push, 'DISCARD_WAIT', 77)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.arrivals = [[notice('Nick1')]]
        self.silence = [[]]
        seen = {}

        def offline_logged_out():
            seen['row_while_offline'] = len(self.db.tokens.get('id-1', []))

        def first():
            self.has_token()

        app = App([first, offline_logged_out])
        # 두 번째 멈춤 뒤 서버가 죽은 토큰으로 보내 404 를 받아 행을 지운다
        self.m['expect_none'].side_effect = lambda *a, **k: (self.log.append('expect_none'), self.db.tokens.clear(), [])[2]
        self.assertEqual(self.go('E-PUSH-68', app)[0], 'pass')
        self.assertEqual(seen['row_while_offline'], 1)
        order = [e for e in self.log if e in ('airplane_on', 'airplane_off', 'send:id-1', 'wait_new', 'expect_none', 'online')]
        self.assertEqual(order, ['send:id-1', 'wait_new', 'airplane_on', 'airplane_off', 'send:id-1', 'expect_none', 'online'])
        self.assertEqual(self.log[-1], 'revoke')  # 망을 되돌린 뒤 권한도 되돌린다
        self.assertIn(mock.call(77), self.sleep.call_args_list)  # 망을 켠 뒤 재시도 간격 넘게 기다린다(DISCARD_WAIT)

    def test_fails_when_a_notice_still_comes_to_the_logged_out_phone(self):
        self.arrivals = [[notice('Nick1')]]
        self.silence = [[notice('Nick2')]]
        result, note = self.go('E-PUSH-68', App([lambda: self.has_token(), lambda: None]))
        self.assertEqual(result, 'fail')
        self.assertIn('결함', note)

    def test_the_network_is_restored_even_when_the_app_blows_up(self):
        app = App([lambda: self.has_token()])
        app.__class__ = type('Boom', (App,), {'__call__': lambda this, midway=None, **job: 1 / 0})
        with self.assertRaises(ZeroDivisionError):  # 러너(run_case)가 잡아 blocked 로 끝낸다
            self.go('E-PUSH-68', app)
        self.assertIn('online', self.log)

    def test_the_known_limit_that_a_dead_token_row_may_remain_is_a_note_not_a_fail(self):
        # 시나리오: FCM 이 죽은 토큰에 404 를 주는지는 운영 첫 실측 — 알림 0개가 판정이고 행은 메모로만 남긴다.
        self.arrivals = [[notice('Nick1')]]
        self.silence = [[]]
        result, note = self.go('E-PUSH-68', App([lambda: self.has_token(), lambda: None]))
        self.assertEqual(result, 'pass')
        self.assertIn('push_tokens', note)


class Push69Test(PushBase):
    def test_a_fake_token_in_the_account_is_kept_while_the_real_device_still_gets_the_notice(self):
        self.arrivals = [[notice('Nick1')]]
        self.assertEqual(self.go('E-PUSH-69', App([lambda: self.has_token()]))[0], 'pass')
        posts = [b for (m, p, b) in self.db.calls if m == 'POST' and p == '/cards/push-tokens']
        self.assertEqual(len(posts), 1)
        self.assertTrue(posts[0]['token'].startswith('e2e-fake-') and posts[0]['platform'] == 'android')
        deletes = [p for (m, p, b) in self.db.calls if m == 'DELETE' and p.startswith('/cards/push-tokens/')]
        self.assertEqual(len(deletes), 1)  # 가짜 토큰은 끝에 지운다
        self.assertEqual(self.log[-1], 'revoke')

    def test_fails_when_the_notice_does_not_come(self):
        self.arrivals = [[]]
        self.assertEqual(self.go('E-PUSH-69', App([lambda: self.has_token()]))[0], 'fail')

    def test_fails_when_the_server_deleted_the_fake_row(self):
        def server_deletes_the_fake_row(*args, **kwargs):
            self.db.tokens['id-1'] = [r for r in self.db.tokens['id-1'] if not r['token'].startswith('e2e-fake-')]
            return [notice('Nick1')]

        self.m['wait_new'].side_effect = server_deletes_the_fake_row
        result, note = self.go('E-PUSH-69', App([lambda: self.has_token()]))
        self.assertEqual(result, 'fail')
        self.assertIn('가짜', note)

    def test_the_fake_row_is_removed_even_when_the_notice_check_blows_up(self):
        self.m['wait_new'].side_effect = RuntimeError('adb 끊김')
        with self.assertRaises(RuntimeError):  # 러너(run_case)가 잡아 blocked 로 끝낸다
            self.go('E-PUSH-69', App([lambda: self.has_token()]))
        self.assertTrue(any(m == 'DELETE' for (m, p, b) in self.db.calls))


if __name__ == '__main__':
    unittest.main()
