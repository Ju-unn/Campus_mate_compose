"""영역 5 폰 A · 탈퇴 흐름 9개(E-WD-02 · 04 · 12 · 13 · 14 · 15 · 16 · 18 · E-EDGE-20)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_wd`.

가짜 서버([WdFake])는 area5_read 시험의 [ReadFake] 에 이 묶음이 쓰는 서버 규칙을 더했다 — 탈퇴(account/router.py · SQL withdraw_account: 멱등 ·
정지면 무기한 · 아니면 2개월 · 푸시 토큰 · 학생증 임시 파일 지우기 · logout scope=global), 로그인 확인(GoTrue /user — 끊긴 세션은 403),
재가입 제한 훅(auth_hooks/router.py · signup_policy.py), 정리 배치(account/batch_router.py run_cleanup), 저장소 파일, 매칭 일시중지.
"앱이 눌렀다" 는 가짜 앱 안에서 같은 서버 API 를 불러 흉내 낸다. 정리 배치(gcloud)는 tools.batch 를 가짜로 바꿔 가짜 서버의 규칙을 돌린다.
[ServerFactsTest] 가 가짜의 규칙이 진짜 코드(backend · supabase · frontend/lib)의 그 줄과 같은지 글자로 맞대 본다.
시험의 글자는 모듈에서 가져오지 않고 그대로 적었다 — 모듈의 상수가 틀려도 시험이 잡는다.
"""

import ast
import calendar
import hashlib
import inspect
import json
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area3_phone5, area5_wd, batch_gate, tools
from e2e.test_area1 import CFG
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, as_fn
from e2e.test_area3_safe import _who
from e2e.test_area5_read import ReadBase, ReadFake, server_keys
from e2e.tools import Reply, Run

REAL_GUARD = area2._guard  # WdBase 가 가드를 끄기 전의 진짜 가드

BUNDLE = ['E-WD-02', 'E-WD-04', 'E-WD-12', 'E-WD-13', 'E-WD-14', 'E-WD-15', 'E-WD-16', 'E-WD-18', 'E-EDGE-20']
PHONE_CASES = [c for c in BUNDLE if c != 'E-WD-12']  # E-WD-12 는 앱이 없는 API 가설
PRESSING = ['E-WD-04', 'E-WD-16', 'E-WD-18', 'E-EDGE-20']  # 앱이 "정말 영구 삭제" 를 누르는 넷
BATCHED = ['E-WD-12', 'E-WD-14', 'E-WD-15', 'E-WD-16']  # 운영 cleanup 을 부르는 넷
WITHDRAWN = '탈퇴한 계정이에요'
EXPIRED = '세션이 만료됐어요, 다시 로그인해 주세요'
REJOIN = '재가입이 제한된 이메일이에요'
BUCKETS = ('avatars', 'profile-photos', 'student-id-temp', 'heart-task-proofs')
BACKEND = tools.ROOT / 'backend' / 'app'
MIGRATIONS = tools.ROOT / 'supabase' / 'migrations'


def now():
    return datetime.now(timezone.utc)


def hmac_of(email):
    """가짜 서버의 이메일 HMAC — 진짜 키는 없다. PC 는 HMAC 을 만들지 않고 앞뒤 행 목록을 견줘 새 행을 찾는다."""
    return '\\x' + hashlib.sha256(email.strip().lower().encode()).hexdigest()


def add_months(moment, months):
    """Postgres `+ interval 'N months'` — 그 달에 없는 날은 말일로."""
    month = moment.month - 1 + months
    year, month = moment.year + month // 12, month % 12 + 1
    return moment.replace(year=year, month=month, day=min(moment.day, calendar.monthrange(year, month)[1]))


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


def lib(*parts):
    return (tools.ROOT / 'frontend' / 'lib' / Path(*parts)).read_text(encoding='utf-8')


def backend(*parts):
    return BACKEND.joinpath(*parts).read_text(encoding='utf-8')


def code_of(text):
    """주석을 뺀 dart 코드."""
    return '\n'.join(re.sub(r'//.*$', '', line) for line in text.replace('\r\n', '\n').split('\n'))


class WdFake(ReadFake):
    """ReadFake + 탈퇴 · 재가입 제한 · 정리 배치 · 저장소 · 로그인 끊기 · 일시중지. 시험이 아래 칸을 바꿔 규칙 하나를 어긴 서버를 만든다."""

    def __init__(self):
        super().__init__()
        self.logout = True  # False: 탈퇴 뒤 로그인을 못 끊은 서버(account/router.py ③ logout 이 실패)
        self.clears_tokens = True
        self.clears_id_files = True
        self.forever_when_suspended = True
        self.last_stamp = datetime.min.replace(tzinfo=timezone.utc)  # 가짜 서버가 마지막으로 준 탈퇴 시각 — withdraw 가 늘 앞서가게
        self.idempotent = True  # False: 이미 탈퇴한 계정도 다시 탈퇴시키는 서버(제한 기간이 바뀐다)
        self.block_months = 2
        self.retention = timedelta(days=30)
        self.deletes_users = True  # False: 파일만 지우고 auth 사용자는 남기는 정리 배치
        self.drops_expired_blocks = True
        self.drops_forever_blocks = False
        self.hook_blocks = True
        self.hook_strict = False  # True: 끝난(blocked_until 이 지난) 제한도 막는 훅
        self.pause_saves = True
        self.paused_from_start = False
        self.reset()
        for method, pattern, handler in (
                ('POST', r'/account/withdraw', self._withdraw_api), ('GET', r'/auth/v1/user', self._user),
                ('POST', r'/auth/v1/otp', self._otp), ('POST', r'/storage/v1/object/list/[^/]+', self._list),
                ('POST', r'/storage/v1/object/(?!list/)[^/]+/.+', self._upload), ('PATCH', r'/cards/matching-paused', self._pause)):
            self.on(method, pattern, handler)

    def reset(self):
        """가설 하나를 깨끗한 세상에서 — 규칙 칸은 그대로 둔다."""
        for table in (self.tables, self.statuses, self.profiles, self.phones):
            table.clear()
        self.sent.clear()
        self.users.clear()
        self.verifies = self._ids = 0
        self.files = {bucket: set() for bucket in BUCKETS}
        self.cut, self.gone, self.cleanups, self.options = set(), set(), [], []

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self.options.append((method, urlsplit(url).path, options))
        return super().__call__(method, url, headers, body, raw)

    def profile(self, pid):
        fresh = pid not in self.profiles
        row = super().profile(pid)
        if fresh:
            row['matching_paused'] = self.paused_from_start
        return row

    def email(self, who):
        return next(u['email'] for u in self.users if u['id'] == who)

    def block(self, email):
        return next((b for b in self.rows('signup_blocks') if b['email_hmac'] == hmac_of(email)), None)

    # ── 탈퇴(account/router.py · SQL withdraw_account) ──
    def withdraw(self, who):
        row = self.profile(who)
        if row['status'] == 'withdrawn' and self.idempotent:
            return
        stamp = max(now(), self.last_stamp + timedelta(microseconds=1))  # 시계가 안 움직여도(윈도 15.6ms) 두 번째 탈퇴는 더 늦은 시각 — 진짜 서버의 now() 는 문마다 다르다
        self.last_stamp = stamp
        until = 'infinity' if row['status'] == 'suspended' and self.forever_when_suspended else add_months(stamp, self.block_months).isoformat()
        row.update(status='withdrawn', withdrawn_at=stamp.isoformat())
        old = self.block(self.email(who))
        if old is None:
            self.rows('signup_blocks').append({'email_hmac': hmac_of(self.email(who)), 'blocked_until': until, 'key_version': 1})
        elif old['blocked_until'] != 'infinity':  # greatest — infinity 는 줄지 않는다
            old['blocked_until'] = until if until == 'infinity' else max(old['blocked_until'], until)
        if self.clears_tokens:
            self.tables['push_tokens'] = [t for t in self.rows('push_tokens') if t['profile_id'] != who]
        if self.clears_id_files:
            self.files['student-id-temp'] = {p for p in self.files['student-id-temp'] if not p.startswith(f'{who}/')}
        if self.logout:
            self.cut.add(who)

    def _withdraw_api(self, sent):
        who = _who(sent)
        if who in self.cut:  # current_user.py: GoTrue /user 가 200 이 아니면 헤더 없는 401
            return Reply(401, {'detail': EXPIRED})
        if self.profile(who)['status'] == 'withdrawn' and self.idempotent:
            return Reply(401, {'detail': WITHDRAWN}, {'X-Account-Status': 'withdrawn'})
        self.withdraw(who)
        return Reply(200, {'ok': True})

    def _user(self, sent):
        who = _who(sent)
        if who in self.cut:
            return Reply(403, {'code': 403, 'error_code': 'session_not_found', 'msg': 'Session from session_id claim in JWT does not exist'})
        return Reply(200, {'id': who})

    def _otp(self, sent):
        """앱의 인증코드 요청 — 없는 사람이면 before-user-created 훅이 재가입 제한을 본다(blocked_until > now 만)."""
        email = sent['body']['email']
        if any(u['email'].lower() == email.lower() for u in self.users):
            return Reply(200, {})
        block = self.block(email)
        if self.hook_blocks and block and (self.hook_strict or block['blocked_until'] == 'infinity'
                                           or datetime.fromisoformat(block['blocked_until']) > now()):
            return Reply(422, {'code': 422, 'error_code': 'hook', 'msg': REJOIN})
        self._ids += 1
        self.users.append({'id': f'id-{self._ids}', 'email': email})
        return Reply(200, {})

    # ── 저장소 ──
    def _list(self, sent):
        bucket = sent['path'].rsplit('/', 1)[1]
        prefix = sent['body']['prefix'].rstrip('/') + '/'
        return Reply(200, [{'name': p[len(prefix):], 'id': p} for p in sorted(self.files[bucket]) if p.startswith(prefix)])

    def _upload(self, sent):
        bucket, path = sent['path'].removeprefix('/storage/v1/object/').split('/', 1)
        self.files[bucket].add(path)
        return Reply(200, {'Key': f'{bucket}/{path}'})

    def _pause(self, sent):
        if self.pause_saves:
            self.profile(_who(sent))['matching_paused'] = sent['body']['paused']
        return Reply(200, {'ok': True})

    # ── 표 ──
    def _table(self, method, name, sent):
        query = sent['query']
        if name == 'signup_blocks' and 'id' in query.get('select', '').split(','):
            return Reply(400, {'code': '42703', 'message': 'column signup_blocks.id does not exist'})  # 키는 email_hmac 이다
        if name == 'profiles' and query.get('id', '')[3:] in self.gone:
            return Reply(200, [] if method == 'GET' else None)
        return super()._table(method, name, sent)

    # ── 정리 배치(account/batch_router.py run_cleanup) ──
    def cleanup(self):
        stamp = now()
        deleted = 0
        for pid, row in list(self.profiles.items()):
            if pid in self.gone or row.get('status') != 'withdrawn' or not row.get('withdrawn_at'):
                continue
            if datetime.fromisoformat(row['withdrawn_at']) >= stamp - self.retention:
                continue
            for bucket in BUCKETS:
                self.files[bucket] = {p for p in self.files[bucket] if not p.startswith(f'{pid}/')}
            if self.deletes_users:
                self.users[:] = [u for u in self.users if u['id'] != pid]
                self.gone.add(pid)
                deleted += 1
        blocks = self.rows('signup_blocks')

        def expired(b):
            if b['blocked_until'] == 'infinity':
                return self.drops_forever_blocks
            return self.drops_expired_blocks and datetime.fromisoformat(b['blocked_until']) < stamp
        kept = [b for b in blocks if not expired(b)]
        result = {'deleted_accounts': deleted, 'skipped_accounts': 0, 'deleted_reports': 0,
                  'deleted_signup_blocks': len(blocks) - len(kept), 'stale_key_rows': 0, 'deleted_heart_proofs': 0}
        self.tables['signup_blocks'] = kept
        self.cleanups.append(result)
        return result


class KillApp(App):
    """E-EDGE-20 의 앱 — 첫 켬(phase=press)은 [press] 로 서버에 할 일을 한 뒤 midway({'step': 'pressed'}) 를 부른다(PC 가 여기서 죽인다).
    둘째 켬(phase=after)은 [after] 의 말을 돌려준다."""

    def __init__(self, press, after):
        super().__init__(after)
        self.press = press

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if job.get('phase') == 'press':
            self.press(job)
            if midway:
                midway({'step': 'pressed'})
            return said()  # PC 가 못 죽였을 때만 닿는다
        return self.answer(job)


class WdBase(ReadBase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / 'KEEP.txt').write_text('MANUAL 00000000-0000-4000-8000-00000000000a\n', encoding='utf-8')
        self.run_ = Run(self.root / 'area5-wd', 'b', cfg={**CFG}, key='svc')
        self.fake = WdFake()
        self.events, self.adb_calls, self.batches = [], [], []
        self.pids = ['4242']  # pidof 가 돌려줄 값 — kill 을 받으면 비운다
        self.kill_takes = True

        def fake_adb(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            if 'pidof' in args:
                return ' '.join(self.pids)
            if 'kill' in args and self.kill_takes:
                self.pids.clear()
            return ''

        def fake_batch(name):
            self.batches.append(name)
            if name == 'cleanup':
                self.fake.cleanup()

        self.sleep = mock.patch('time.sleep').start()
        self.addCleanup(mock.patch.stopall)
        for patcher in (mock.patch.object(tools, 'call', lambda *a, **k: self.fake(*a, **k)), mock.patch.object(tools, 'adb', fake_adb),
                        mock.patch.object(tools, 'batch', side_effect=fake_batch), mock.patch.object(Run, 'shot'),
                        mock.patch.object(Run, 'remember'), mock.patch.object(area2, '_guard'),
                        mock.patch.object(batch_gate, 'now_seoul', return_value=datetime(2026, 10, 6, 12, 0, tzinfo=area1.SEOUL)),
                        mock.patch.object(area5_wd, 'BATCH_WAIT', 0), mock.patch.object(area5_wd, 'PAUSE_WAIT', 0)):
            patcher.start()
        area3_phone5._FAILED.clear()
        self.addCleanup(area3_phone5._FAILED.clear)

    def case(self, name, answer=None, app=None):
        self.fake.reset()
        area3_phone5._FAILED.clear()  # 시험마다 새 가설 — "배치 뒤 fail" 기억이 다음 부름으로 새지 않게(다시 돌기는 NoRerunTest 가 본다)
        self.events.clear()
        self.adb_calls.clear()
        self.batches.clear()
        self.pids[:] = ['4242']
        if name == 'E-WD-12':
            return area1.attempt(self.run_, name), None
        app = app or App(as_fn(answer))
        return area1.attempt_phone(self.run_, name, app), app

    # ── 앱이 한 일 흉내 ──
    def api(self, method, path, body=None, n=1):
        return tools.api(CFG, method, path, f'tok-{n}', body)

    def press(self):
        """앱이 "정말 영구 삭제" 를 눌렀다 — 앱의 토큰으로 POST /account/withdraw. 앱이 로그인한 계정은 마지막으로 만든 계정이다(토큰 tok-마지막)."""
        return self.api('POST', '/account/withdraw', None, self.fake.verifies)

    def otp(self, email):
        """앱이 02 에서 "인증 메일 받기" 를 눌렀다 — 공개 키로 GoTrue /otp."""
        return tools.call('POST', f"{CFG['SUPABASE_URL']}/auth/v1/otp", {'apikey': CFG['SUPABASE_ANON_KEY']}, {'email': email, 'create_user': True})

    # ── 읽기 ──
    def sent(self, method, path):
        return [s for s in self.fake.sent if s['method'] == method and s['path'] == path]

    def account_email(self, n=1):
        return next(s['body']['email'] for s in self.fake.sent if s['path'] == '/auth/v1/admin/users' and s['method'] == 'POST')

    def writes_only_mine(self):
        """DB · 저장소 쓰기가 가짜 서버가 만든 계정 id 만 가리킨다 — 정리 배치가 지운 계정도 이번 실행 것이다."""
        mine = {f'id-{i}' for i in range(1, self.fake._ids + 1)}
        for sent in self.fake.sent:
            if sent['method'] in ('POST', 'PATCH', 'DELETE') and sent['path'].startswith(('/rest/v1/', '/storage/v1/object/')) \
                    and '/object/list/' not in sent['path']:
                ids = set(re.findall(r'id-\d+', json.dumps([sent['path'], sent['query'], sent['body']], ensure_ascii=False, default=str)))
                self.assertLessEqual(ids, mine, sent['path'])

    def stop_app(self, answer, step='final'):
        return MidwayApp(as_fn(answer), step, self.events)


# ── 묶음 등록 · 시간 상한 ────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_nine_in_the_order_of_the_scenario(self):
        self.assertEqual(area1.BUNDLES['area5-wd'], BUNDLE)
        self.assertEqual(list(area5_wd.PHONE), PHONE_CASES)
        self.assertEqual(list(area5_wd.CASES), ['E-WD-12'])
        self.assertLessEqual(set(PHONE_CASES), set(area1.PHONE))
        self.assertIn('E-WD-12', area1.CASES)
        self.assertNotIn('E-WD-12', area1.PHONE)

    def test_the_runner_sees_the_bundle_and_runs_e_wd_12_as_an_api_case(self):
        # 새 인터프리터로 — 이 시험 파일이 area5_wd 를 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = ('from e2e import __main__ as m, area1; print(m.BUNDLES.get("area5-wd"), "E-WD-04" in area1.PHONE, '
                 'm.API_CASES.get("E-WD-12").__name__)')
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{BUNDLE} True e2e.area1')

    def test_no_case_is_an_alias_of_area1_b2(self):
        # 겹침 표: WD 줄이 모두 E-AUTH-07 ~ 12 보다 더 본다 — 같은 함수를 다시 등록하지 않는다.
        from e2e import area1_b2
        theirs = {id(f) for f in (*area1_b2.PHONE.values(), *area1_b2.CASES.values())}
        for name in BUNDLE:
            self.assertNotIn(id(area1.PHONE.get(name) or area1.CASES.get(name)), theirs, name)

    def test_the_long_cases_get_their_worst_wait_plus_room(self):
        app = inspect.signature(Run.phone).parameters['timeout'].default  # 앱의 말 하나를 기다리는 한도
        self.assertEqual(area5_wd.APP_WAIT, app)
        batch, settle, room = area5_wd.BATCH_WAIT, area5_wd.SETTLE, 300
        worst = {'E-WD-14': batch + app, 'E-WD-15': 2 * batch + app, 'E-WD-16': 2 * app + batch, 'E-WD-18': 2 * app,
                 'E-EDGE-20': 2 * app + settle}
        for case, wait in worst.items():
            with self.subTest(case):
                self.assertGreaterEqual(tools.CASE_LIMITS[case], wait + room)
        for case in ('E-WD-02', 'E-WD-04', 'E-WD-13'):
            self.assertNotIn(case, tools.CASE_LIMITS)  # 앱 한 번 — 기본 420초
        self.assertNotIn('E-WD-12', tools.CASE_LIMITS)  # API 가설 — 진행 프로그램이 상한을 안 건다

    def test_the_waits_are_the_scenario_numbers(self):
        self.assertEqual(area5_wd.BATCH_WAIT, 120)  # area1_b2 · area3_phone5 와 같은 "2분"
        self.assertEqual(area5_wd.KILL_AFTER, 0.3)
        self.assertEqual(area5_wd.LOGIN_MS, 5000)  # 3초 + 임시 스플래시 붙잡기 2초
        self.assertEqual(area5_wd.KEPT_AGE, timedelta(days=29))
        self.assertEqual(area5_wd.GONE_AGE, timedelta(days=31))


# ── 앱 쪽 약속 ───────────────────────────────────────────────────────────────────────────────────────

def app_dart():
    return dart('area5_wd.dart')


def top_functions(code):
    """맨 앞 칸에서 시작하는 dart 함수 → 본문(다음 맨 앞 줄 전까지)."""
    out, name, body = {}, None, []
    for line in code.split('\n'):
        head = re.match(r'^(?:Future<[^(]*>|String\??|bool|void|Map<[^(]*>|Finder)\s+(_\w+)\(', line)
        if line[:1].strip() and line[:1] != '}':
            if name:
                out[name] = '\n'.join(body)
            name, body = (head.group(1), [line]) if head else (None, [])
        elif name:
            body.append(line)
    if name:
        out[name] = '\n'.join(body)
    return out


def case_bodies(code):
    """area5CasesWd 맵의 가설 번호 → 그 줄부터 다음 번호 전까지."""
    found = re.split(r"(?m)^  '(E-[A-Z]+-\d+)':", code.split('area5CasesWd = {', 1)[1])
    return dict(zip(found[1::2], found[2::2]))


class AppContractTest(unittest.TestCase):
    """PC 가 읽는 앱 Map 키와 앱이 만드는 키가 한 글자도 다르지 않은지(양쪽으로) — 오타 한 글자는 늘 FAIL 이라 기계로 맞댄다."""

    def pc_keys(self):
        tree = ast.parse(Path(area5_wd.__file__).read_text(encoding='utf-8'))
        return {node.args[0].value for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get'
                and isinstance(node.func.value, ast.Name) and node.func.value.id == 'said'
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)}

    def test_the_app_registers_the_eight_phone_cases(self):
        self.assertEqual(re.findall(r"^\s*'(E-[A-Z]+-\d+)':", app_dart(), re.M), PHONE_CASES)

    def test_area5_dart_adds_the_part_the_spread_and_the_two_imports_the_new_file_needs(self):
        text = dart('area5.dart')
        self.assertIn("part 'area5_wd.dart';", text)
        self.assertIn('...area5CasesWd', text)
        self.assertIn("import 'package:campus_mate/common/widgets/app_toast.dart';", text)
        self.assertIn("import 'package:campus_mate/core/theme/app_colors.dart';", text)

    def test_the_keys_the_pc_reads_are_exactly_the_keys_the_app_says(self):
        said_keys = set(re.findall(r"'(\w+)':", app_dart())) - {'step'}  # step 은 멈춤 신호(우편함 약속)
        read = self.pc_keys()
        self.assertGreaterEqual(len(read), 14)  # 읽는 키를 못 찾았다면 이 시험이 빈 껍데기다
        self.assertEqual(sorted(read - said_keys), [], '앱이 말하지 않는 키를 PC 가 읽는다')
        self.assertEqual(sorted(said_keys - read), [], 'PC 가 읽지 않는 키를 앱이 말한다')

    def test_every_key_the_app_reads_from_the_job_is_one_the_pc_sends_and_the_reverse(self):
        wanted = set(re.findall(r"job\['(\w+)'\]", app_dart()))
        tree = ast.parse(Path(area5_wd.__file__).read_text(encoding='utf-8'))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'phone' for kw in node.keywords if kw.arg}
        self.assertEqual(sorted(wanted - sent), [])
        self.assertEqual(sorted(sent - wanted - {'midway', 'token_hash'}), [])  # token_hash 는 area5.dart 의 _session 이 읽는다
        self.assertEqual(wanted, {'email', 'phase'})
        self.assertIn("if (job['token_hash'] case final String hash) await signIn(hash);", dart('area5.dart'))

    def test_the_final_delete_button_is_pressed_in_one_helper_that_only_the_four_cases_reach(self):
        code = code_of(app_dart())
        self.assertEqual([line.strip() for line in code.split('\n') if '정말 영구 삭제' in line], ["const _wdForever = '정말 영구 삭제';"])
        functions = top_functions(code)
        self.assertIn('_wdWithdraw', functions)
        users = [name for name, body in functions.items() if '_wdForever' in body]
        self.assertEqual(users, ['_wdWithdraw'])
        self.assertEqual(code.count('_wdForever'), 2)  # 선언 + _wdWithdraw 안 한 번
        reach = {'_wdWithdraw'}
        for _ in range(5):  # 도우미가 도우미를 부르는 것까지 따라간다
            reach |= {name for name, body in functions.items() if any(f'{r}(' in body for r in reach)}
        cases = case_bodies(code)
        self.assertEqual(list(cases), PHONE_CASES)
        pressing = [case for case, body in cases.items() if any(re.search(rf'\b{r}\b', body) for r in reach)]
        self.assertEqual(pressing, PRESSING)

    def test_no_other_app_file_reaches_the_withdraw_helpers_or_the_final_delete_label(self):
        # area5_read · act · photo 는 같은 part 라이브러리라 _wd 도우미를 부를 수 있다 — 그 길을 막는다.
        # "정말 영구 삭제" 글자는 area5 라이브러리(area5.dart 와 그 part 들)만 본다 — area1_b2 · area4_set2 는 다른 라이브러리의 탈퇴 가설이다.
        helpers = re.compile(r'\b(_wdWithdraw|_wdRace|_wdOpenFinal|_wdPressThenDie|_wdForever)\b')
        folder = tools.ROOT / 'frontend' / 'integration_test'
        # area5_two.dart 의 A 쪽(두 기기 탈퇴 E-WD-05 ~ 09)은 _wdOpenFinal · _wdWithdraw · _wdToLogin 을 부른다 — 그 다섯 `/A` 만 닿는지는
        # e2e/test_area5_two.py 가 본다. 그래도 "정말 영구 삭제" 글자는 거기에도 없어야 한다(아래 area5 검사).
        # area5_new.dart 의 E-WD-19 · 20 도 _wdOpenFinal · _wdWithdraw 를 부른다 — 그 둘만 닿는지는 e2e/test_area5_new.py 가 본다.
        reaching = {'area5_wd.dart', 'area5_two.dart', 'area5_new.dart'}
        others = [p for p in folder.glob('*.dart') if p.name != 'area5_wd.dart']
        self.assertGreater(len(others), 10)
        area5 = [p for p in others if p.name == 'area5.dart' or "part of 'area5.dart';" in p.read_text(encoding='utf-8')]
        self.assertIn('area5_read.dart', [p.name for p in area5])
        for path in others:
            with self.subTest(path.name):
                code = code_of(path.read_text(encoding='utf-8'))
                if path.name not in reaching:
                    self.assertEqual(helpers.findall(code), [])
                else:
                    self.assertNotIn('_wdForever', code)
                    self.assertNotIn('_wdRace', code)
                    self.assertNotIn('_wdPressThenDie', code)
                if path in area5:
                    self.assertNotIn('정말 영구 삭제', code)

    def test_the_first_sheet_delete_and_no_other_wide_button_is_tapped_by_type(self):
        code = code_of(app_dart())
        self.assertNotRegex(code, r'tester\.tap\(find\.byType')
        self.assertNotRegex(code, r'\btap\(tester, find\.byType')
        self.assertNotRegex(code, r'\bbutton\(')  # 버튼은 안의 글자로 누른다(#282) — AppButton 전체 가운데가 아니라
        self.assertNotIn("'영구 삭제'", code)  # 1차 시트 버튼은 area5.dart 의 _openFinalSheet 가 누른다

    def test_the_literals_the_app_looks_for_are_in_the_real_screens(self):
        screens = '\n'.join(path.read_text(encoding='utf-8') for path in (tools.ROOT / 'frontend' / 'lib').rglob('*.dart'))
        for literal in ('정말 영구 삭제', '일시중지', '매칭 활성화', '인증 메일 받기', 'hong@snu.ac.kr', '정말 삭제할까요?', '대학 이메일로 시작해요',
                        '탈퇴한 계정이에요', '세션이 만료됐어요, 다시 로그인해 주세요'):
            with self.subTest(literal):
                self.assertIn(f"'{literal}'", screens)
        for literal in ('정말 영구 삭제', '일시중지', '매칭 활성화', '인증 메일 받기', 'hong@snu.ac.kr'):
            with self.subTest('app ' + literal):
                self.assertIn(f"'{literal}'", app_dart())

    def test_the_screens_say_the_numbers_the_module_counts_on(self):
        self.assertIn('static const _defaultDuration = Duration(seconds: 2);', lib('core', 'router', 'splash_hold.dart'))  # LOGIN_MS 의 2초
        sign_up = lib('auth', 'view', 'sign_up_screen.dart')
        self.assertIn('_notice = LoginNotice.take();', sign_up)  # 02 가 처음 그려질 때 한 번 꺼낸다
        self.assertIn('Timer(const Duration(seconds: 3)', sign_up)  # 3초 뒤 사라진다
        self.assertIn('if (state.event == AuthChangeEvent.signedOut) {', lib('core', 'auth', 'session_scope.dart'))  # 다시 들어가기
        self.assertIn('setState(() => _generation++);', lib('core', 'auth', 'session_scope.dart'))
        self.assertIn('color: AppColors.error', sign_up)  # 02 의 거절 문구 색 — 앱이 이 색으로 찾는다


# ── 서버 규칙: 가짜가 진짜 서버를 따라가는지 ──────────────────────────────────────────────────────────

class ServerFactsTest(unittest.TestCase):
    def test_the_cleanup_answer_has_the_keys_of_the_real_server(self):
        self.assertEqual(server_keys('account/batch_router.py', 'run_cleanup'),
                         ['deleted_accounts', 'skipped_accounts', 'deleted_reports', 'deleted_signup_blocks', 'stale_key_rows'])
        self.assertIn('result["deleted_heart_proofs"] =', backend('account', 'batch_router.py'))
        fake = WdFake()
        self.assertEqual(sorted(fake.cleanup()), sorted(['deleted_accounts', 'skipped_accounts', 'deleted_reports', 'deleted_signup_blocks',
                                                          'stale_key_rows', 'deleted_heart_proofs']))

    def test_the_retention_is_thirty_days_and_the_module_stands_one_day_on_each_side(self):
        self.assertIn('WITHDRAWN_RETENTION = timedelta(days=30)', backend('account', 'batch_router.py'))
        self.assertEqual(WdFake().retention, timedelta(days=30))
        self.assertLess(area5_wd.KEPT_AGE, timedelta(days=30))
        self.assertGreater(area5_wd.GONE_AGE, timedelta(days=30))
        repo = backend('account', 'repository.py')
        self.assertIn('"status": "eq.withdrawn", "withdrawn_at": f"lt.{cutoff.isoformat()}"', repo)
        self.assertIn('"blocked_until": f"lt.{now.isoformat()}"', repo)  # infinity 는 어떤 시각보다 커 안 지워진다

    def test_withdraw_account_is_idempotent_forever_when_suspended_and_two_months_otherwise(self):
        sql = (MIGRATIONS / '20260927030100_create_withdraw_account.sql').read_text(encoding='utf-8')
        self.assertIn("if not found or v_status = 'withdrawn' then\n    return;", sql.replace('\r\n', '\n'))
        self.assertIn("case when v_status = 'suspended' then 'infinity'::timestamptz else now() + interval '2 months' end", sql)
        self.assertIn('set blocked_until = greatest(public.signup_blocks.blocked_until, excluded.blocked_until)', sql)
        self.assertIn("set status = 'withdrawn', withdrawn_at = now()", sql)

    def test_the_withdraw_route_takes_any_signed_in_caller_and_then_cuts_every_login(self):
        router = backend('account', 'router.py')
        self.assertIn('async def withdraw(caller: Caller = Depends(get_caller),', router)  # 정지 · 미인증도 받는다(E-WD-16)
        order = [router.index(word) for word in ('accounts.withdraw(', '"push_tokens"', '"student_id_files"', '"logout"')]
        self.assertEqual(order, sorted(order))
        self.assertIn('admin.empty_folder("student-id-temp", profile_id)', router)
        self.assertIn('params={"scope": "global"}', backend('account', 'repository.py'))

    def test_a_cut_login_is_a_401_without_the_withdrawn_mark_and_a_live_one_is_marked(self):
        gate = backend('student_verification', 'current_user.py')
        self.assertIn('f"{settings.auth_url}/user"', gate)
        self.assertIn('if response.status_code != 200:\n        raise HTTPException(status_code=401, detail=errors.SESSION_EXPIRED)',
                      gate.replace('\r\n', '\n'))
        self.assertIn('headers={"X-Account-Status": "withdrawn"}', gate)
        errors = backend('core', 'errors.py')
        self.assertIn(f'SESSION_EXPIRED = "{EXPIRED}"', errors)
        self.assertIn(f'ACCOUNT_WITHDRAWN = "{WITHDRAWN}"', errors)
        self.assertEqual((area5_wd.WITHDRAWN, area5_wd.EXPIRED), (WITHDRAWN, EXPIRED))

    def test_the_app_shows_the_expired_notice_for_an_unmarked_401_and_the_withdrawn_one_for_the_mark(self):
        send = lib('core', 'http', 'http_send.dart')
        self.assertIn("'withdrawn' => const WithdrawnFailure(),", send)
        self.assertIn('if (response.statusCode == 401) {\n    return const FailureResult(SessionRejectedFailure());', send.replace('\r\n', '\n'))
        status = lib('core', 'auth', 'account_status_listenable.dart')
        self.assertIn('case SessionRejectedFailure() when _status != AccountStatus.withdrawn:', status)
        notice = lib('account', 'model', 'login_notice.dart')
        self.assertIn('AccountStatus.withdrawn => const WithdrawnFailure(),', notice)
        self.assertIn('AccountStatus.expired => const SessionRejectedFailure(),', notice)
        failure = lib('common', 'failure.dart')
        self.assertIn(f"return '{EXPIRED}';", failure)
        self.assertIn(f"String toDisplayMessage() => '{WITHDRAWN}';", failure)
        self.assertIn('if (failure is WithdrawnFailure) {', lib('account', 'viewmodel', 'withdraw_view_model.dart'))

    def test_the_hook_blocks_only_until_the_end_and_says_the_rejoin_text(self):
        self.assertIn('"blocked_until": "gt.now()"', backend('signup_policy.py'))
        self.assertIn(f'return HookDecision.reject("{REJOIN}")', backend('auth_hooks', 'router.py'))
        self.assertIn("if (error.statusCode == '422') {\n      return SignUpRejectedFailure(error.message);",
                      lib('auth', 'model', 'supabase_auth_repository.dart').replace('\r\n', '\n'))
        self.assertEqual(area5_wd.REJOIN_BLOCKED, REJOIN)

    def test_signup_blocks_has_no_id_column_and_the_fake_says_so(self):
        sql = (MIGRATIONS / '20260919092934_create_signup_blocks.sql').read_text(encoding='utf-8')
        self.assertIn('email_hmac bytea primary key', sql)
        self.assertNotRegex(sql, r'\bid\s+uuid')
        reply = WdFake()('GET', 'https://sb.test/rest/v1/signup_blocks?select=id', {'apikey': 'svc', 'Authorization': 'Bearer svc'})
        self.assertEqual(reply[0], 400)

    def test_the_pause_route_is_the_one_the_fake_answers(self):
        self.assertIn('@router.patch("/cards/matching-paused")', backend('cards', 'router.py'))
        self.assertIn("_api.send('PATCH', '/cards/matching-paused'", lib('matching', 'model', 'http_card_repository.dart'))


class PaidFactsTest(unittest.TestCase):
    """유료 호출(OpenAI · Vision) · 디스코드 표가 기대는 서버 코드의 모양 — 코드가 바뀌면 표를 다시 쓰게 여기서 걸린다."""

    PATHS = (('account', 'router.py'), ('account', 'repository.py'), ('account', 'batch_router.py'), ('auth_hooks', 'router.py'),
             ('signup_policy.py',), ('heart_tasks', 'cleanup.py'), ('heart_tasks', 'storage.py'),
             ('student_verification', 'current_user.py'), ('cards', 'router.py'))

    def test_the_server_paths_of_the_nine_never_reach_openai_vision_or_discord(self):
        for parts in self.PATHS:
            with self.subTest(parts):
                text = backend(*parts).lower()
                for word in ('openai', 'vision', 'discord'):
                    self.assertNotIn(word, text)

    def test_the_module_and_the_app_side_never_call_the_three_discord_routes(self):
        # 설명(docstring · 주석)은 그 길을 이름으로 적는다 — 코드의 글자만 본다.
        tree = ast.parse(Path(area5_wd.__file__).read_text(encoding='utf-8'))
        doc = ast.get_docstring(tree, clean=False)
        module = '\n'.join(n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value != doc)
        self.assertIn('/account/withdraw', module)  # 코드 글자를 제대로 모았다는 대조
        for text in (module, code_of(app_dart())):
            for route in ('/reports', '/heart-tasks', '/student-verification'):
                self.assertNotIn(route, text)


# ── E-WD-02 일시중지 ─────────────────────────────────────────────────────────────────────────────────

class PauseTest(WdBase):
    def good(self, **over):
        def answer(job):
            self.api('PATCH', '/cards/matching-paused', {'paused': True})  # 앱의 setPaused(true)
            return said(**{'sheet_closed': True, 'toggle_on': False, **over})
        return answer

    def test_02_pause_closes_the_sheet_turns_the_toggle_off_and_only_pauses(self):
        _, app = self.passes('E-WD-02', self.good())
        self.assertIs(self.profile()['matching_paused'], True)
        self.assertEqual(self.profile()['status'], 'active')
        self.assertEqual(self.fake.rows('signup_blocks'), [])
        self.assertIn('token_hash', app.jobs[0])

    def test_02_the_pc_turns_matching_on_first_when_it_starts_paused(self):
        self.fake.paused_from_start = True
        self.passes('E-WD-02', self.good())
        turned = [s for s in self.sent('PATCH', '/rest/v1/profiles') if s['body'] == {'matching_paused': False}]
        self.assertEqual(len(turned), 1)

    def test_02_is_blocked_when_matching_cannot_be_turned_on_first(self):
        self.fake.paused_from_start = True
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-WD-02', self.good(), '준비')

    def test_02_fails_on_a_sheet_left_open_or_a_toggle_still_on_or_unread(self):
        for over, word in (({'sheet_closed': False}, '시트'), ({'toggle_on': True}, '토글'), ({'toggle_on': None}, '토글')):
            with self.subTest(over):
                self.fails('E-WD-02', self.good(**over), word)
        self.fails('E-WD-02', lambda job: {k: v for k, v in self.good()(job).items() if k != 'toggle_on'}, '토글')

    def test_02_fails_when_the_server_does_not_save_the_pause(self):
        self.fake.pause_saves = False
        self.fails('E-WD-02', self.good(), 'matching_paused')

    def test_02_fails_when_the_app_withdrew_instead(self):
        def answer(job):
            self.press()
            return self.good()(job)
        note = self.fails('E-WD-02', answer, 'status')
        self.assertIn('signup_blocks', note)

    def test_02_writes_only_to_the_account_it_made(self):
        self.passes('E-WD-02', self.good())
        self.writes_only_mine()


# ── E-WD-04 영구 삭제 ────────────────────────────────────────────────────────────────────────────────

class WithdrawTest(WdBase):
    def good(self, tapped=None, press=True, **over):
        def answer(job):
            at = tapped or now()
            if press:
                self.assertEqual(self.press()[0], 200)
            return said(**{'tapped_at': at.isoformat(), 'login_ms': 3400, 'notice': WITHDRAWN, 'notice_gone': True, 'reentered': True,
                           'notice_again': None, **over})
        return answer

    def test_04_withdraws_shows_02_and_the_notice_once_and_clears_the_token_and_the_file(self):
        self.passes('E-WD-04', self.good())
        self.assertEqual(self.profile()['status'], 'withdrawn')
        planted = [s for s in self.sent('POST', '/rest/v1/push_tokens')]
        self.assertEqual([s['body'][0]['profile_id'] for s in planted], ['id-1'])
        self.assertEqual(self.fake.rows('push_tokens'), [])
        uploads = [s['path'] for s in self.fake.sent if s['path'].startswith('/storage/v1/object/student-id-temp/')]
        self.assertEqual(len(uploads), 1)
        self.assertTrue(uploads[0].startswith('/storage/v1/object/student-id-temp/id-1/'))
        self.assertEqual(self.fake.files['student-id-temp'], set())
        self.assertEqual(len(self.fake.rows('signup_blocks')), 1)

    def test_04_fails_on_each_wrong_thing_the_app_saw(self):
        for over, word in (({'notice': EXPIRED}, '알림'), ({'notice': None}, '알림'), ({'login_ms': 5600}, '5000ms'), ({'login_ms': None}, '02'),
                           ({'notice_gone': False}, '3초'), ({'reentered': False}, '다시 들어'), ({'notice_again': WITHDRAWN}, '다시 들어간 02')):
            with self.subTest(over):
                self.fails('E-WD-04', self.good(**over), word)

    def test_04_a_missing_answer_is_not_the_same_as_none(self):
        for key, word in (('notice_again', '다시 들어간 02'), ('notice', '알림'), ('tapped_at', 'tapped_at')):
            with self.subTest(key):
                self.fails('E-WD-04', lambda job, key=key: {k: v for k, v in self.good()(job).items() if k != key}, word)

    def test_04_fails_when_the_server_leaves_the_token_or_the_file(self):
        for flag, word in (('clears_tokens', 'push_tokens'), ('clears_id_files', 'student-id-temp')):
            with self.subTest(flag):
                setattr(self.fake, flag, False)
                self.fails('E-WD-04', self.good(), word)
                setattr(self.fake, flag, True)

    def test_04_fails_when_the_block_is_not_two_months_after_the_tap(self):
        self.fake.block_months = 3
        self.fails('E-WD-04', self.good(), 'blocked_until')

    def test_04_fails_when_the_tap_is_far_from_the_withdrawal(self):
        note = self.fails('E-WD-04', self.good(tapped=now() - timedelta(minutes=5)), 'withdrawn_at')
        self.assertIn('blocked_until', note)

    def test_04_the_minute_on_each_side_holds(self):
        self.passes('E-WD-04', self.good(tapped=now() - timedelta(seconds=50)))

    def test_04_fails_when_the_app_did_not_withdraw(self):
        note = self.fails('E-WD-04', self.good(press=False), 'status')
        self.assertIn('새 재가입 제한 0행', note)

    def test_04_fails_when_two_new_block_rows_cannot_be_told_apart(self):
        def answer(job):
            reply = self.good()(job)
            self.fake.rows('signup_blocks').append({'email_hmac': '\\xff', 'blocked_until': 'infinity', 'key_version': 1})
            return reply
        self.fails('E-WD-04', answer, '새 재가입 제한 2행')

    def test_04_is_blocked_when_the_token_or_the_file_cannot_be_planted(self):
        self.fail_next('POST', r'/rest/v1/push_tokens')
        self.blocked('E-WD-04', self.good(), 'push_tokens')
        self.fake.handlers.pop(0)
        self.fail_next('POST', r'/storage/v1/object/student-id-temp/.+')
        self.blocked('E-WD-04', self.good(), 'student-id-temp')

    def test_04_is_blocked_when_the_planted_things_do_not_show(self):
        self.swallow('POST', r'/rest/v1/push_tokens')
        self.blocked('E-WD-04', self.good(), '준비')

    def test_04_writes_only_to_the_account_it_made(self):
        self.passes('E-WD-04', self.good())
        self.writes_only_mine()


# ── E-WD-12 29일째 ───────────────────────────────────────────────────────────────────────────────────

class KeptTest(WdBase):
    def test_12_a_29_day_withdrawal_keeps_the_user_the_row_and_the_files_after_a_cleanup_that_ran(self):
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.batches, ['cleanup'])
        moved = [s['body']['withdrawn_at'] for s in self.sent('PATCH', '/rest/v1/profiles') if 'withdrawn_at' in (s['body'] or {})]
        self.assertEqual(len(moved), 1)
        self.assertLess(abs(datetime.fromisoformat(moved[0]) - (now() - timedelta(days=29))), timedelta(seconds=5))
        for bucket in BUCKETS:
            self.assertEqual(len([p for p in self.fake.files[bucket] if p.startswith('id-1/')]), 1, bucket)
        sentinel = self.sent('POST', '/rest/v1/signup_blocks')
        self.assertEqual(len(sentinel), 1)
        self.assertNotEqual(sentinel[0]['body'][0]['blocked_until'], 'infinity')
        self.assertTrue(self.sent('DELETE', '/rest/v1/signup_blocks'))  # 확인용 행은 시험이 지운다
        self.assertEqual(self.fake.rows('signup_blocks')[0]['email_hmac'], hmac_of(self.account_email()))  # 남은 것은 탈퇴로 생긴 행뿐
        self.assertEqual(len(self.fake.rows('signup_blocks')), 1)

    def test_12_uses_an_account_without_paid_onboarding(self):
        self.case('E-WD-12')
        for path in ('/profile-onboarding/photos', '/profile-onboarding/bio', '/profile-onboarding/ideal-conditions'):
            self.assertEqual(self.sent('POST', path), [], path)

    def test_12_fails_when_the_server_cleans_after_28_days(self):
        self.fake.retention = timedelta(days=28)
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'fail', note)
        for word in ('auth 사용자', 'profiles', 'avatars'):
            self.assertIn(word, note)

    def test_12_fails_when_the_server_drops_the_files_but_keeps_the_user(self):
        self.fake.retention, self.fake.deletes_users = timedelta(days=28), False
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'fail', note)
        self.assertNotIn('auth 사용자', note)
        self.assertIn('heart-task-proofs', note)

    def test_12_is_blocked_when_the_batch_did_not_run(self):
        self.fake.drops_expired_blocks = False
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('확인용', note)
        self.assertTrue(self.sent('DELETE', '/rest/v1/signup_blocks'))  # 막혀도 확인용 행은 지운다

    def test_12_is_blocked_at_four_without_making_an_account_or_calling_the_batch(self):
        with mock.patch.object(batch_gate, 'now_seoul', return_value=datetime(2026, 10, 6, 4, 0, tzinfo=area1.SEOUL)):
            (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked')
        self.assertIn('04:06', note)
        self.assertEqual(self.fake.users, [])
        self.assertEqual(self.batches, [])

    def test_14_15_16_are_blocked_at_four_before_making_an_account_or_starting_the_app(self):
        # 준비(계정 · 탈퇴 · 앱)를 다 하고서야 관문에 막히면 헛수고 — 04:00 ± 5분이면 준비 전에 멈춘다(WD-12 와 같다)
        for name in ('E-WD-14', 'E-WD-15', 'E-WD-16'):
            with self.subTest(name):
                app = self.stop_app(lambda job: said())
                with mock.patch.object(batch_gate, 'now_seoul', return_value=datetime(2026, 10, 6, 4, 0, tzinfo=area1.SEOUL)):
                    (result, note), _ = self.case(name, None, app=app)
                self.assertEqual(result, 'blocked', note)
                self.assertIn('04:06', note)
                self.assertEqual(self.fake.users, [])
                self.assertEqual(self.batches, [])
                self.assertEqual(app.jobs, [])

    def test_12_is_blocked_when_withdrawn_at_cannot_be_moved(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked')
        self.assertIn('29일', note)
        self.assertEqual(self.batches, [])

    def test_12_the_sentinel_row_is_deleted_even_when_gcloud_fails(self):
        tools.batch.side_effect = subprocess.CalledProcessError(1, 'gcloud', stderr='denied')
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked')
        self.assertTrue(self.sent('DELETE', '/rest/v1/signup_blocks'))

    def test_12_writes_only_to_the_account_it_made(self):
        self.case('E-WD-12')
        self.writes_only_mine()

    def test_12_is_blocked_before_the_batch_when_the_sentinel_cannot_be_put_or_does_not_show(self):
        # 확인용 행이 처음부터 없으면 "지워졌다" 가 배치가 돈 증거가 못 된다 — 배치를 부르기 전에 멈춘다.
        for broken, word in ((lambda: self.fail_next('POST', r'/rest/v1/signup_blocks'), '500'),
                             (lambda: self.swallow('POST', r'/rest/v1/signup_blocks'), '안 보인다')):
            with self.subTest(word):
                broken()
                (result, note), _ = self.case('E-WD-12')
                self.fake.handlers.pop(0)
                self.assertEqual(result, 'blocked', note)
                self.assertIn('확인용', note)
                self.assertIn(word, note)
                self.assertEqual(self.batches, [])

    def test_12_the_sentinel_row_is_deleted_even_when_its_insert_landed_but_the_answer_was_lost(self):
        # 행은 들어갔는데 답이 끊겨(재전송이 409) — 또는 끊김 그대로 — 끝나도 그 확인용 행은 지운다
        def landed_then(outcome):
            def handler(sent):
                self.fake._table('POST', 'signup_blocks', sent)
                if outcome == 'conflict':
                    return Reply(409, {'code': '23505', 'message': 'duplicate key value violates unique constraint "signup_blocks_pkey"'})
                raise ConnectionResetError('끊김')
            return handler
        for outcome in ('conflict', 'dropped'):
            with self.subTest(outcome):
                self.fake.handlers.insert(0, ('POST', re.compile(r'/rest/v1/signup_blocks'), landed_then(outcome)))
                if outcome == 'conflict':
                    (result, note), _ = self.case('E-WD-12')
                    self.assertEqual(result, 'blocked', note)
                    self.assertIn('409', note)
                else:
                    with self.assertRaises(ConnectionResetError):  # 진행 프로그램(run_case)이 blocked 로 적는다
                        self.case('E-WD-12')
                self.fake.handlers.pop(0)
                self.assertTrue(self.sent('DELETE', '/rest/v1/signup_blocks'))
                left = [r for r in self.fake.rows('signup_blocks') if r['email_hmac'] != hmac_of(self.account_email())]
                self.assertEqual(left, [])  # 탈퇴로 생긴 행 말고는 남지 않는다
                self.assertEqual(self.batches, [])

    def test_12_is_blocked_not_stopped_when_a_bucket_list_cannot_be_read(self):
        # tools.storage_paths 는 SystemExit 를 던진다 — 그대로 두면 묶음 전체가 멈춘다
        self.fail_next('POST', r'/storage/v1/object/list/avatars')
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('avatars 목록을 못 읽음', note)

    def test_12_is_blocked_when_the_planted_files_do_not_show(self):
        self.swallow('POST', r'/storage/v1/object/(?!list/).+')
        (result, note), _ = self.case('E-WD-12')
        self.assertEqual(result, 'blocked', note)
        self.assertIn('넣은 파일이 안 보이는 버킷', note)
        self.assertEqual(self.batches, [])


# ── E-WD-13 탈퇴 뒤 로그인 ───────────────────────────────────────────────────────────────────────────

class LoginAfterWithdrawTest(WdBase):
    def good(self, **over):
        return said(**{'notice': WITHDRAWN, 'login_seen': True, 'home_seen': False, 'notice_ms': 2600, **over})

    def test_13_a_new_login_to_a_withdrawn_account_goes_back_to_02_without_home(self):
        note, app = self.passes('E-WD-13', self.good())
        self.assertIn('2600ms', note)
        self.assertEqual(self.profile()['status'], 'withdrawn')
        self.assertIn('token_hash', app.jobs[0])
        withdraw = [o for m, p, o in self.fake.options if p == '/account/withdraw']
        self.assertEqual(withdraw, [{'retry': False}])  # 탈퇴는 한 번만 보낸다

    def test_13_fails_on_a_wrong_or_missing_notice_home_seen_or_no_02(self):
        for over, word in (({'notice': EXPIRED}, '알림'), ({'notice': None}, '알림'), ({'home_seen': True}, '홈'), ({'login_seen': False}, '02')):
            with self.subTest(over):
                self.fails('E-WD-13', self.good(**over), word)

    def test_13_is_blocked_when_the_pc_cannot_withdraw(self):
        self.fail_next('POST', r'/account/withdraw')
        self.blocked('E-WD-13', self.good(), '탈퇴 500')  # 메모에 진짜 까닭(서버 답)이 남는다

    def test_13_is_blocked_when_the_account_is_not_withdrawn_before_the_app(self):
        self.swallow('POST', r'/account/withdraw')  # 204 — 받았다고만 하고 아무것도 안 한 서버
        app = App(as_fn(self.good()))
        self.blocked('E-WD-13', None, '탈퇴 상태', app=app)
        self.assertEqual(app.jobs, [])  # 앱을 켜지 않는다


# ── E-WD-14 · 15 재가입 ───────────────────────────────────────────────────────────────────────────────

class RejoinTest(WdBase):
    def asks(self, **over):
        """앱이 02 에 일감의 메일을 넣고 "인증 메일 받기" — 거절이면 그 문구, 아니면 03(코드 화면)."""
        def answer(job):
            reply = self.otp(job['email'])
            seen = {'code_screen': reply[0] == 200, 'error': None if reply[0] == 200 else reply[1]['msg']}
            return said(**{**seen, **over})
        return answer

    def test_14_the_cleaned_mail_is_refused_on_02_and_no_user_is_made(self):
        _, app = self.passes('E-WD-14', self.asks())
        self.assertEqual(self.batches, ['cleanup'])
        self.assertEqual(app.jobs[0]['email'], self.account_email())
        self.assertNotIn('token_hash', app.jobs[0])  # 로그아웃 상태의 02 에서 시작
        self.assertEqual(self.fake.users, [])
        self.assertEqual(self.sent('POST', '/profile-onboarding/photos'), [])  # 계정은 유료 온보딩 없는 basic

    def test_14_fails_when_the_hook_lets_the_mail_in_and_the_new_user_is_removed(self):
        self.fake.hook_blocks = False
        note = self.fails('E-WD-14', self.asks(), REJOIN)
        self.assertIn('만들어졌다', note)
        self.assertTrue(self.sent('DELETE', '/auth/v1/admin/users/id-2'))

    def test_14_fails_on_a_wrong_text_or_a_code_screen(self):
        for over, word in (({'error': None}, REJOIN), ({'error': EXPIRED}, REJOIN), ({'code_screen': True}, '03')):
            with self.subTest(over):
                self.fails('E-WD-14', self.asks(**over), word)

    def test_14_is_blocked_when_the_cleanup_does_not_remove_the_31_day_account(self):
        self.fake.retention = timedelta(days=40)
        self.blocked('E-WD-14', self.asks(), '정리 배치')

    def test_14_the_withdrawn_at_is_31_days_back(self):
        self.passes('E-WD-14', self.asks())
        moved = [s['body']['withdrawn_at'] for s in self.sent('PATCH', '/rest/v1/profiles') if 'withdrawn_at' in (s['body'] or {})]
        self.assertLess(abs(datetime.fromisoformat(moved[0]) - (now() - timedelta(days=31))), timedelta(seconds=5))

    def test_15_an_ended_block_lets_the_mail_in_and_the_next_cleanup_drops_the_row(self):
        _, app = self.passes('E-WD-15', self.asks())
        self.assertEqual(self.batches, ['cleanup', 'cleanup'])
        self.assertEqual(self.fake.rows('signup_blocks'), [])
        self.assertEqual([u['id'] for u in self.fake.users], ['id-2'])  # 새 사람(새 id)
        moved = [s for s in self.fake.sent if s['method'] == 'PATCH' and s['path'] == '/rest/v1/signup_blocks']
        self.assertEqual(len(moved), 1)
        self.assertLess(datetime.fromisoformat(moved[0]['body']['blocked_until']), now())
        self.assertEqual(moved[0]['query']['email_hmac'], f"eq.{hmac_of(self.account_email())}")

    def test_15_fails_when_the_hook_still_blocks_an_ended_row(self):
        self.fake.hook_strict = True
        self.fails('E-WD-15', self.asks(), '03')
        self.assertEqual(self.batches, ['cleanup'])  # ① 이 안 되면 ② 의 운영 cleanup 은 부르지 않는다(준비 쪽 한 번뿐)

    def test_15_fails_on_a_shown_error_or_no_code_screen(self):
        for over, word in (({'error': REJOIN}, '빨간'), ({'code_screen': False}, '03')):
            with self.subTest(over):
                self.fails('E-WD-15', self.asks(**over), word)
                self.assertEqual(self.batches, ['cleanup'])  # ① 이 안 되면 ② 의 운영 cleanup 은 부르지 않는다

    def test_15_fails_when_the_cleanup_keeps_the_ended_row(self):
        self.fake.drops_expired_blocks = False
        self.fake.retention = timedelta(days=30)
        note = self.fails('E-WD-15', self.asks(), '남음')
        self.assertEqual(self.batches, ['cleanup', 'cleanup'])
        self.assertNotIn('03', note)

    def test_15_is_blocked_when_the_row_is_gone_before_the_app_asks(self):
        def answer(job):
            self.fake.tables['signup_blocks'] = []
            return self.asks()(job)
        self.blocked('E-WD-15', answer, '먼저 지워')

    def test_15_is_blocked_when_the_block_cannot_be_ended(self):
        self.swallow('PATCH', r'/rest/v1/signup_blocks')
        self.blocked('E-WD-15', self.asks(), '어제')
        self.fake.handlers.pop(0)
        self.fail_next('PATCH', r'/rest/v1/signup_blocks')
        self.blocked('E-WD-15', self.asks(), '옮기기 500')  # 서버가 거절한 까닭이 메모에 남는다

    def test_15_fails_when_the_new_user_has_the_old_id(self):
        def answer(job):
            self.fake._ids -= 1  # 지운 사람의 id 를 다시 내주는 서버
            return self.asks()(job)
        self.fails('E-WD-15', answer, '같은 id')

    def test_14_15_are_blocked_before_the_batch_when_the_withdrawal_block_cannot_be_told_apart(self):
        real = self.fake.withdraw

        def two_rows(who):
            real(who)
            self.fake.rows('signup_blocks').append({'email_hmac': '\\xfe', 'blocked_until': 'infinity', 'key_version': 1})
        self.fake.withdraw = two_rows
        for name in ('E-WD-14', 'E-WD-15'):
            with self.subTest(name):
                self.blocked(name, self.asks(), '못 가림(2행)')
                self.assertEqual(self.batches, [])

    def test_14_15_write_only_to_the_account_they_made(self):
        for name in ('E-WD-14', 'E-WD-15'):
            with self.subTest(name):
                self.case(name, self.asks())
                self.writes_only_mine()


# ── E-WD-16 정지 중 탈퇴 ─────────────────────────────────────────────────────────────────────────────

class SuspendedRaceTest(WdBase):
    def good(self, **over):
        def answer(job):
            self.assertEqual(self.press()[0], 200)
            return said(**{'tapped_at': now().isoformat(), 'login_ms': 4100, 'notice': WITHDRAWN, 'normal_sheet': True, **over})
        return answer

    def test_16_suspended_while_the_final_sheet_is_open_withdraws_forever_and_the_cleanup_keeps_it(self):
        _, app = self.passes('E-WD-16', None, app=self.stop_app(self.good()))
        self.assertEqual(self.events, ['step', 'go'])
        rows = self.fake.rows('signup_blocks')
        self.assertEqual([r['blocked_until'] for r in rows], ['infinity'])
        self.assertEqual(self.batches, ['cleanup'])
        suspended = [s for s in self.sent('PATCH', '/rest/v1/profiles') if s['body'] == {'status': 'suspended'}]
        self.assertEqual(len(suspended), 1)
        self.assertEqual(self.fake.sent.index(suspended[0]) < self.fake.sent.index(self.sent('POST', '/account/withdraw')[0]), True)

    def test_16_fails_on_a_two_month_block_and_then_does_not_call_the_batch(self):
        self.fake.forever_when_suspended = False
        self.fails('E-WD-16', None, 'infinity', app=self.stop_app(self.good()))
        self.assertEqual(self.batches, [])

    def test_16_fails_when_the_cleanup_drops_the_forever_row(self):
        self.fake.drops_forever_blocks = True
        self.fails('E-WD-16', None, '정리 배치 뒤', app=self.stop_app(self.good()))

    def test_16_fails_on_each_wrong_thing_the_app_saw(self):
        for over, word in (({'notice': EXPIRED}, '알림'), ({'login_ms': None}, '02'), ({'normal_sheet': False}, '최종 시트')):
            with self.subTest(over):
                self.fails('E-WD-16', None, word, app=self.stop_app(self.good(**over)))

    def test_16_fails_when_the_app_ended_before_stopping(self):
        self.fails('E-WD-16', self.good(), '멈추지')
        self.assertEqual(self.batches, [])

    def test_16_is_blocked_when_the_suspension_cannot_be_set(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-WD-16', None, '정지', app=self.stop_app(self.good()))

    def test_16_is_blocked_when_the_batch_did_not_run(self):
        self.fake.drops_expired_blocks = False
        self.blocked('E-WD-16', None, '확인용', app=self.stop_app(self.good()))

    def test_16_writes_only_to_the_account_it_made(self):
        self.passes('E-WD-16', None, app=self.stop_app(self.good()))
        self.writes_only_mine()


# ── E-WD-18 두 번 누르기 ─────────────────────────────────────────────────────────────────────────────

class TwiceTest(WdBase):
    def again(self, **over):
        """앱의 두 번째 누름 — 서버가 무엇을 주든 앱이 본 것을 말한다(시험이 정한 알림)."""
        def answer(job):
            self.second = self.press()
            return said(**{'tapped_at': now().isoformat(), 'login_ms': 4300, 'notice': EXPIRED, 'normal_sheet': True, **over})
        return answer

    def test_18_the_first_withdrawal_cut_the_login_so_the_second_press_shows_the_expired_notice_and_changes_nothing(self):
        note, _ = self.passes('E-WD-18', None, app=self.stop_app(self.again()))
        self.assertEqual(self.second[0], 401)
        self.assertNotIn('x-account-status', self.second.headers)
        self.assertEqual(len(self.fake.rows('signup_blocks')), 1)
        self.assertIn('세션', note)
        withdraw = [o for m, p, o in self.fake.options if p == '/account/withdraw']
        self.assertEqual(withdraw[0], {'retry': False})  # PC 의 첫 탈퇴

    def test_18_the_withdrawn_notice_is_wrong_when_the_login_was_cut(self):
        self.fails('E-WD-18', None, EXPIRED, app=self.stop_app(self.again(notice=WITHDRAWN)))

    def test_18_with_a_live_login_the_second_press_is_the_marked_401_and_the_withdrawn_notice(self):
        self.fake.logout = False
        self.passes('E-WD-18', None, app=self.stop_app(self.again(notice=WITHDRAWN)))
        self.assertEqual(self.second.headers.get('x-account-status'), 'withdrawn')
        self.fails('E-WD-18', None, WITHDRAWN, app=self.stop_app(self.again(notice=EXPIRED)))

    def test_18_fails_when_the_second_press_changes_the_block(self):
        self.fake.logout, self.fake.idempotent = False, False
        self.fails('E-WD-18', None, 'signup_blocks', app=self.stop_app(self.again(notice=WITHDRAWN)))

    def test_18_fails_when_the_second_press_changes_the_block_even_when_the_clock_does_not_tick(self):
        # 윈도 + 파이썬 3.12 의 시계 해상도는 15.6ms — 가짜 서버의 두 탈퇴(PC 첫 탈퇴 · 앱 두 번째 누름)가 같은 tick 이면 제한 기간이 같은 값이 돼
        # "두 번째 누름이 제한을 바꿨다" 가 안 보였다(간헐 실패의 뿌리). 가짜 서버는 시계가 멈춰 있어도 두 번째 탈퇴를 늦은 시각으로 쳐야 한다.
        frozen = now()
        with mock.patch(f'{__name__}.now', return_value=frozen):
            self.fake.logout, self.fake.idempotent = False, False
            self.fails('E-WD-18', None, 'signup_blocks', app=self.stop_app(self.again(notice=WITHDRAWN)))

    def test_18_fails_when_the_withdrawn_at_moves(self):
        def answer(job):
            reply = self.again()(job)
            self.profile()['withdrawn_at'] = (now() + timedelta(seconds=3)).isoformat()
            return reply
        self.fails('E-WD-18', None, 'withdrawn_at', app=self.stop_app(answer))

    def test_18_fails_on_no_02_or_no_notice(self):
        for over, word in (({'login_ms': None}, '02'), ({'notice': None}, '알림')):
            with self.subTest(over):
                self.fails('E-WD-18', None, word, app=self.stop_app(self.again(**over)))

    def test_18_fails_when_the_app_ended_before_stopping(self):
        self.fails('E-WD-18', self.again(), '멈추지')

    def test_18_is_blocked_when_the_pc_cannot_withdraw_first(self):
        self.fail_next('POST', r'/account/withdraw')
        self.blocked('E-WD-18', None, '탈퇴 500', app=self.stop_app(self.again()))

    def test_18_is_blocked_when_the_first_withdrawal_leaves_no_block_row(self):
        self.fake.withdraw = lambda who: self.fake.profile(who).update(status='withdrawn', withdrawn_at=now().isoformat())
        self.blocked('E-WD-18', None, '첫 탈퇴', app=self.stop_app(self.again(notice=WITHDRAWN)))

    def test_18_is_blocked_when_gotrue_cannot_say_whether_the_login_was_cut(self):
        # 5xx · 429 는 "끊김" 이 아니다 — 기대 알림을 정할 수 없다
        for status in (503, 429):
            with self.subTest(status):
                self.fake.handlers.insert(0, ('GET', re.compile(r'/auth/v1/user'), Reply(status, {'msg': 'busy'})))
                self.blocked('E-WD-18', None, 'GoTrue', app=self.stop_app(self.again()))
                self.fake.handlers.pop(0)


# ── E-EDGE-20 누른 직후 강제 종료 ────────────────────────────────────────────────────────────────────

class KillTest(WdBase):
    def after(self, **over):
        return lambda job: said(**{'home_seen': False, 'login_seen': True, 'notice': EXPIRED, **over})

    def app(self, press=True, **over):
        return KillApp(lambda job: self.press() if press else None, self.after(**over))

    def test_edge_20_a_withdrawal_that_reached_the_server_comes_back_on_02(self):
        app = self.app()
        note, _ = self.passes('E-EDGE-20', None, app=app)
        self.assertEqual([job.get('phase') for job in app.jobs], ['press', 'after'])
        self.assertIn('token_hash', app.jobs[0])
        self.assertNotIn('token_hash', app.jobs[1])  # 저장된 세션 그대로 다시 켠다
        self.assertIn('withdrawn', note)

    def test_edge_20_the_kill_is_run_as_kill_about_a_third_of_a_second_after_the_press_never_force_stop(self):
        self.passes('E-EDGE-20', None, app=self.app())
        commands = [args[1:] for args in self.adb_calls]
        self.assertIn(('shell', 'run-as', tools.PACKAGE, 'kill', '-9', '4242'), commands)
        self.assertNotIn('force-stop', ' '.join(' '.join(c) for c in commands))
        first_kill = commands.index(('shell', 'run-as', tools.PACKAGE, 'kill', '-9', '4242'))
        self.assertIn(('shell', 'pidof', tools.PACKAGE), commands[:first_kill])
        waits = [c.args[0] for c in self.sleep.call_args_list if c.args and 0 < c.args[0] <= 0.3]
        self.assertTrue(waits, self.sleep.call_args_list)  # pidof 를 읽은 뒤 0.3초까지 남은 만큼 쉰다

    def test_edge_20_on_02_the_notice_may_be_gone_but_never_the_withdrawn_one_when_the_login_was_cut(self):
        self.passes('E-EDGE-20', None, app=self.app(notice=None))  # 응답을 받고 로그아웃까지 한 뒤 죽었다 — 알림은 프로세스와 같이 사라진다
        self.fails('E-EDGE-20', None, '알림', app=self.app(notice=WITHDRAWN))

    def test_edge_20_with_a_live_login_the_withdrawn_notice_is_the_right_one(self):
        self.fake.logout = False
        self.passes('E-EDGE-20', None, app=self.app(notice=WITHDRAWN))
        self.fails('E-EDGE-20', None, '알림', app=self.app(notice=EXPIRED))

    def test_edge_20_withdrawn_fails_on_home_or_no_02(self):
        for over, word in (({'home_seen': True}, '홈'), ({'login_seen': False}, '02')):
            with self.subTest(over):
                self.fails('E-EDGE-20', None, word, app=self.app(**over))

    def test_edge_20_a_withdrawal_that_never_reached_the_server_comes_back_home(self):
        note, _ = self.passes('E-EDGE-20', None, app=self.app(press=False, home_seen=True, login_seen=False, notice=None))
        self.assertIn('active', note)
        self.assertEqual(self.profile()['status'], 'active')

    def test_edge_20_active_fails_on_02_no_home_or_a_notice(self):
        for over, word in (({'login_seen': True}, '02'), ({'home_seen': False}, '홈'), ({'notice': WITHDRAWN}, '알림')):
            with self.subTest(over):
                base = {'home_seen': True, 'login_seen': False, 'notice': None, **over}
                self.fails('E-EDGE-20', None, word, app=self.app(press=False, **base))

    def test_edge_20_active_with_a_new_block_row_fails(self):
        def block_only(job):
            self.fake.rows('signup_blocks').append({'email_hmac': '\\xfd', 'blocked_until': 'infinity', 'key_version': 1})  # 상태는 그대로 · 제한만 생긴 서버
        after = self.after(home_seen=True, login_seen=False, notice=None)
        self.fails('E-EDGE-20', None, '탈퇴 안 됐는데 새 재가입 제한 1행', app=KillApp(block_only, after))

    def test_edge_20_withdrawn_without_a_block_row_fails(self):
        def half(job):
            self.profile().update(status='withdrawn', withdrawn_at=now().isoformat())  # 상태만 바뀐 서버
        self.fails('E-EDGE-20', None, '재가입 제한', app=KillApp(half, self.after(notice=None)))

    def test_edge_20_is_blocked_when_the_server_state_moves_while_judging(self):
        def late(job):
            self.press()
            return self.after()(job)
        self.blocked('E-EDGE-20', None, '바뀜', app=KillApp(lambda job: None, late))

    def test_edge_20_is_blocked_when_the_process_cannot_be_found_or_killed(self):
        def gone(job):
            self.pids.clear()
        self.blocked('E-EDGE-20', None, 'pidof', app=KillApp(gone, self.after()))
        self.kill_takes = False
        self.blocked('E-EDGE-20', None, '안 죽음', app=self.app())

    def test_edge_20_fails_when_the_app_ends_without_pressing(self):
        app = App(as_fn(said()))
        self.fails('E-EDGE-20', None, '누른 뒤', app=app)
        self.assertEqual(len(app.jobs), 1)  # 다시 켜지 않는다

    def test_edge_20_is_blocked_when_the_state_is_neither_active_nor_withdrawn(self):
        def suspend(job):
            self.profile()['status'] = 'suspended'
        self.blocked('E-EDGE-20', None, 'suspended', app=KillApp(suspend, self.after()))


# ── 앱의 말 · 가드 · 다시 돌기 ────────────────────────────────────────────────────────────────────────

class AppAnswerTest(WdBase):
    def test_a_blocked_app_is_blocked_and_a_silent_or_failed_app_is_a_fail(self):
        for case in PHONE_CASES:
            with self.subTest(case):
                app = (lambda answer: self.stop_app(answer)) if case in ('E-WD-16', 'E-WD-18') else (lambda answer: App(as_fn(answer)))
                area3_phone5._FAILED.clear()
                self.blocked(case, None, '못 찾음', app=app({'result': 'blocked', 'note': '못 찾음'}))
                area3_phone5._FAILED.clear()
                self.fails(case, None, '답하지 않음', app=app(lambda job: None))
                area3_phone5._FAILED.clear()
                self.fails(case, None, '앱이 본 것과 다름', app=app({'result': 'fail', 'note': '앱이 본 것과 다름'}))


class GuardTest(WdBase):
    def real_guard(self):
        """진짜 가드로 — 이번 실행이 만든 계정 목록(accounts.json)은 비어 있다."""
        patcher = mock.patch.object(area2, '_guard', REAL_GUARD)
        patcher.start()
        self.addCleanup(patcher.stop)
        return {'id': 'stranger-1', 'token': 'tok-9', 'email': 'x@y.z', 'n': 9}

    def test_every_write_helper_refuses_an_account_this_run_did_not_make_and_sends_nothing(self):
        stranger = self.real_guard()
        for helper in (lambda: area5_wd._withdraw_once(self.run_, stranger), lambda: area5_wd._plant_file(self.run_, stranger, 'avatars'),
                       lambda: area5_wd._plant_token(self.run_, stranger), lambda: area5_wd._expire(self.run_, stranger, '\\x01')):
            with self.subTest(helper):
                self.fake.sent.clear()
                with self.assertRaises(tools.Blocked) as caught:
                    helper()
                self.assertIn('stranger-1', str(caught.exception))
                self.assertEqual(self.fake.sent, [])

    def test_the_helpers_go_through_for_an_account_this_run_made(self):
        mine = self.real_guard()
        self.run_.out.mkdir(parents=True, exist_ok=True)
        (self.run_.out / 'accounts.json').write_text(json.dumps([mine]), encoding='utf-8')
        area5_wd._plant_file(self.run_, mine, 'avatars')
        area5_wd._plant_token(self.run_, mine)
        self.assertEqual(len(self.fake.files['avatars']), 1)
        self.assertEqual(len(self.fake.rows('push_tokens')), 1)

    def test_the_four_pressing_cases_never_start_the_app_for_a_stranger(self):
        self.real_guard()
        stranger = {'n': 9, 'email': 'x@y.z', 'id': 'stranger-1', 'stage': 'home', 'at': 'now', 'token': 'tok-9'}
        with mock.patch.object(Run, 'account', return_value=stranger):
            for case in PRESSING:
                with self.subTest(case):
                    app = KillApp(lambda job: None, lambda job: said()) if case == 'E-EDGE-20' else self.stop_app(lambda job: said())
                    (result, note), _ = self.case(case, None, app=app)
                    self.assertEqual(result, 'blocked', note)
                    self.assertIn('stranger-1', note)
                    self.assertEqual(app.jobs, [])
                    self.assertEqual(self.sent('POST', '/account/withdraw'), [])


class NoRerunTest(WdBase):
    """진행 프로그램(run_case)은 fail 이면 같은 가설을 한 번 더 돈다 — 운영 cleanup 을 이미 부른 뒤의 fail 은 기억해 두고 다시 안 돈다
    (다시 돌면 운영 배치를 또 부르고 계정을 또 만든다). 배치 전의 fail 은 그대로 다시 돈다."""

    def run_twice(self, name, app_of):
        from e2e import __main__ as cli
        apps = []

        def once(case):
            app = app_of()
            apps.append(app)
            if case == 'E-WD-12':
                return area1.attempt(self.run_, case)
            return area1.attempt_phone(self.run_, case, app)
        self.fake.reset()
        self.batches.clear()
        attempts, result, note = cli.run_case(once, name)
        return attempts, result, note, apps

    def test_a_fail_after_the_cleanup_is_not_run_again(self):
        setups = {
            'E-WD-12': (lambda: setattr(self.fake, 'retention', timedelta(days=28)), lambda: None, 1),
            'E-WD-14': (lambda: setattr(self.fake, 'hook_blocks', False), lambda: App(RejoinTest.asks(self)), 1),
            'E-WD-15': (lambda: setattr(self.fake, 'drops_expired_blocks', False), lambda: App(RejoinTest.asks(self)), 2),
            'E-WD-16': (lambda: setattr(self.fake, 'drops_forever_blocks', True),
                        lambda: self.stop_app(SuspendedRaceTest.good(self)), 1),
        }
        for name, (breaks, app_of, calls) in setups.items():
            with self.subTest(name):
                area3_phone5._FAILED.clear()
                self.fake = WdFake()
                breaks()
                attempts, result, note, apps = self.run_twice(name, app_of)
                self.assertEqual((attempts, result), (2, 'fail'), note)
                self.assertEqual(self.batches.count('cleanup'), calls)  # 두 번째 시도는 배치를 안 부른다
                if name != 'E-WD-12':
                    self.assertEqual(sum(len(a.jobs) for a in apps), 1)  # 앱도 한 번만 켰다

    def test_a_fail_before_the_cleanup_is_run_again(self):
        self.fake.forever_when_suspended = False  # 무기한이 안 나오면 배치 전에 끝난다
        attempts, result, note, apps = self.run_twice('E-WD-16', lambda: self.stop_app(SuspendedRaceTest.good(self)))
        self.assertEqual((attempts, result), (2, 'fail'), note)
        self.assertEqual(self.batches, [])
        self.assertEqual(sum(len(a.jobs) for a in apps), 2)


if __name__ == '__main__':
    unittest.main()
