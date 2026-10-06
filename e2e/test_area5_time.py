"""영역 5 시간조작 2개(E-WD-10 · 11)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 gcloud 로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_time`.

바탕은 영역 3 배치 시험의 Base5(가짜 chat-gate · cleanup · 관문 시계 · 알림)다. 여기에 탈퇴(POST /account/withdraw) · 저장소(버킷 넷) ·
profile_private 를 더하고, 가짜 chat-gate 가 탈퇴한 사람이 있는 방도 건너뛰게(gate.is_gone) 한다. 시험이 규칙 하나를 어긴 서버를 만들면 fail 이어야 한다.
계정은 만든 순서대로 id-1 · id-2 … — 두 가설 모두 폰 계정(남는 쪽 B)이 id-1 이다.
"""

import ast
import re
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area5_time, tools
from e2e.test_area3_phone5 import Base5
from e2e.tools import Reply

CASES = ['E-WD-10', 'E-WD-11']
BUCKETS = ('avatars', 'profile-photos', 'student-id-temp', 'heart-task-proofs')
LEFT = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'


def now():
    return datetime.now(timezone.utc)


def when(value):
    return datetime.fromisoformat(value) if isinstance(value, str) else value


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


class TimeBase(Base5):
    def setUp(self):
        super().setUp()
        self.files = {bucket: set() for bucket in BUCKETS}
        self.withdraws = []
        self.gate_sees_withdrawn = True  # False: 탈퇴한 사람이 있는 방을 48시간에 닫는 chat-gate(spec §2.6 문단대로)
        self.cleanup_drops_files = True
        self.cleanup_drops_users = True
        self.fake.on('POST', r'/account/withdraw', self.withdraw)
        self.fake.on('POST', r'/storage/v1/object/list/[^/]+', self.listing)
        self.fake.on('POST', r'/storage/v1/object/(?!list/)[^/]+/.+', self.upload)

    # ── 가짜 서버 ──
    def profile_row(self, pid):
        rows = self.fake.tables.setdefault('profiles', [])
        row = next((r for r in rows if r['id'] == pid), None)
        if row is None:
            row = {'id': pid, 'status': 'active', 'withdrawn_at': None}
            rows.append(row)
        return row

    def withdraw(self, sent):
        who = self.user_of(sent)
        self.withdraws.append(who)
        row = self.profile_row(who)
        if row['status'] != 'withdrawn':
            row.update(status='withdrawn', withdrawn_at=now().isoformat())
            self.files['student-id-temp'] = {p for p in self.files['student-id-temp'] if not p.startswith(f'{who}/')}
        return Reply(200, {'ok': True})

    def listing(self, sent):
        bucket = sent['path'].rsplit('/', 1)[1]
        prefix = sent['body']['prefix'].rstrip('/') + '/'
        return Reply(200, [{'name': p[len(prefix):], 'id': p} for p in sorted(self.files[bucket]) if p.startswith(prefix)])

    def upload(self, sent):
        bucket, path = sent['path'].removeprefix('/storage/v1/object/').split('/', 1)
        self.files[bucket].add(path)
        return Reply(200, {'Key': f'{bucket}/{path}'})

    def withdrawn(self, pid):
        return any(r['id'] == pid and r.get('status') == 'withdrawn' for r in self.fake.tables.get('profiles', []))

    def sim_gate(self):
        """chat/batch_router.py — 나갔거나 정지 · 탈퇴한 사람이 한 명이라도 있으면 그 방을 통째로 건너뛴다(gate.is_gone)."""
        real = self.ignore
        if self.gate_sees_withdrawn:
            self.ignore = lambda match: real(match) or any(self.withdrawn(p['profile_id']) for p in self.parts(match['id']))
        try:
            super().sim_gate()
        finally:
            self.ignore = real

    def sim_cleanup(self):
        """Base5 의 정리(계정 · cascade 매칭 · 메시지)에 파일 넷 · profile_private 를 더한다."""
        gone = [r['id'] for r in self.fake.tables.get('profiles', []) if r.get('status') == 'withdrawn'
                and now() - when(r['withdrawn_at']) >= timedelta(days=30)]
        users = list(self.fake.users)
        super().sim_cleanup()
        if not self.cleanup_drops_users:
            self.fake.users[:] = users
        for pid in gone:
            if self.cleanup_drops_files:
                for bucket in BUCKETS:
                    self.files[bucket] = {p for p in self.files[bucket] if not p.startswith(f'{pid}/')}
            self.fake.tables['profile_private'] = [r for r in self.fake.tables.get('profile_private', []) if r['profile_id'] != pid]

    def go(self, case, says=None, **kw):
        for pid in ('id-1', 'id-2', 'id-3'):
            self.profile_row(pid)
            self.put('profile_private', profile_id=pid, kakao_id=f'k{pid}')
        return super().go(case, says, **kw)

    def partner(self):
        return 'id-2'


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_the_two_are_phone_cases_in_their_own_bundle(self):
        self.assertEqual(area1.BUNDLES['area5-time'], CASES)
        self.assertEqual(list(area5_time.PHONE), CASES)
        self.assertLessEqual(set(CASES), set(area1.PHONE))
        self.assertFalse(set(CASES) & set(area1.CASES))

    def test_the_runner_imports_the_module_and_sees_the_bundle(self):
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area5-time"), all(c in area1.PHONE for c in %r))' % CASES
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{CASES} True')

    def test_each_case_has_room_for_the_batch_wait_and_the_app(self):
        for case in CASES:
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 900, case)

    def test_the_app_registers_both_and_reads_the_keys_the_pc_sends(self):
        text = dart('area5_time.dart')
        self.assertEqual(re.findall(r"^\s*'(E-WD-\d+)':", text, re.M), CASES)
        self.assertIn("part 'area5_time.dart';", dart('area5.dart'))
        self.assertIn('...area5CasesTime', dart('area5.dart'))
        wanted = set(re.findall(r"job\['(\w+)'\]", text))
        tree = ast.parse(Path(area5_time.__file__).read_text(encoding='utf-8'))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'phone' for kw in node.keywords if kw.arg}
        self.assertEqual(sorted(wanted), sorted(sent - {'token_hash'}))

    def test_the_keys_the_pc_reads_are_the_keys_the_app_says(self):
        said = set(re.findall(r"'(\w+)':", dart('area5_time.dart')))
        tree = ast.parse(Path(area5_time.__file__).read_text(encoding='utf-8'))
        read = {node.args[0].value for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get'
                and isinstance(node.func.value, ast.Name) and node.func.value.id == 'said'
                and node.args and isinstance(node.args[0], ast.Constant)}
        self.assertGreaterEqual(len(read), 3)
        self.assertEqual(sorted(read - said), [])

    def test_the_app_text_is_the_real_left_room_notice(self):
        room = (tools.ROOT / 'frontend' / 'lib' / 'chat' / 'view' / 'chat_room_screen.dart').read_text(encoding='utf-8')
        self.assertIn(f"'{LEFT}'", room)
        self.assertIn("AppButton(label: '채팅방 나가기'", room)
        self.assertIn(f"'{LEFT}'", dart('area5_time.dart'))
        self.assertEqual(area5_time.LEFT_NOTICE, LEFT)

    def test_the_gate_code_still_skips_a_room_with_anyone_gone(self):
        batch = (tools.ROOT / 'backend' / 'app' / 'chat' / 'batch_router.py').read_text(encoding='utf-8')
        self.assertIn('if any(gate.is_gone(p) for p in participants):\n            continue', batch.replace('\r\n', '\n'))
        gate = (tools.ROOT / 'backend' / 'app' / 'chat' / 'gate.py').read_text(encoding='utf-8')
        self.assertIn('status in ("suspended", "withdrawn")', gate)


# ── E-WD-10 ─────────────────────────────────────────────────────────────────────────────────────────

OPEN_ROOM = {'room': True, 'gone_notice': True, 'leave_button': True, 'input': False}


class Wd10Test(TimeBase):
    CASE = 'E-WD-10'

    def run10(self, said=None):
        return self.go(self.CASE, {None: OPEN_ROOM if said is None else said})

    def test_pass_the_withdrawn_partners_room_stays_open_past_48_hours_and_shows_the_left_notice(self):
        (result, note), phone = self.run10()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.events.count(('gcloud', 'chat-gate')), 1)
        self.assertEqual(self.withdraws, ['id-2'])  # 탈퇴는 상대(A) 한 번
        target = self.target()
        self.assertIsNone(target.get('chat_closed_at'))
        self.assertAge(target, timedelta(hours=49))
        self.assertIsNotNone(self.matches()[0].get('chat_closed_at'))  # 확인용 방은 닫혔다 — 배치가 돌았다
        self.assertEqual(phone.jobs[-1]['nickname'], self.nick(2))

    def test_the_partner_withdraws_before_the_batch(self):
        seen = []
        real = self.gcloud
        with mock.patch.object(tools, 'batch', lambda name: (seen.append(self.withdrawn('id-2')), real(name))[1]):
            self.run10()
        self.assertEqual(seen, [True])

    def test_a_gate_that_closes_the_withdrawn_room_is_a_fail(self):
        self.gate_sees_withdrawn = False
        (result, note), _ = self.run10()
        self.assertEqual(result, 'fail', note)
        self.assertIn('chat_closed_at', note)

    def test_a_room_the_batch_left_gone_is_a_fail_not_a_pass_of_not_closed(self):
        """방 행이 없으면 chat_closed_at 이 null 인지 읽을 수가 없다 — "안 닫혔다" 로 헛통과하면 안 된다."""
        real = self.sim_gate

        def eat():
            real()
            self.fake.tables['matches'] = self.matches()[:1]  # 확인용 방(닫힘)만 남기고 시험 방을 지운다

        with mock.patch.object(self, 'sim_gate', eat):
            (result, note), _ = self.run10()
        self.assertEqual(result, 'fail', note)
        self.assertIn('matches 행', note)

    def test_an_app_that_shows_an_input_or_no_notice_is_a_fail(self):
        for key, bad in (('gone_notice', False), ('leave_button', False), ('input', True)):
            with self.subTest(key):
                self.setUp()
                (result, note), _ = self.run10({**OPEN_ROOM, key: bad})
                self.assertEqual(result, 'fail', note)

    def test_an_app_that_never_opened_the_room_is_a_fail(self):
        (result, note), _ = self.run10({'room': False, 'gone_notice': None, 'leave_button': None, 'input': None})
        self.assertEqual(result, 'fail', note)
        self.assertIn('방', note)

    def test_a_dead_batch_is_blocked(self):
        self.batch_works = False
        (result, note), _ = self.run10()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('확인용 방', note)

    def test_a_closed_gate_is_blocked_before_any_account(self):
        self.clock[0] = self.clock[0].replace(minute=57)
        (result, note), _ = self.run10()
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.fake.users, [])


# ── E-WD-11 ─────────────────────────────────────────────────────────────────────────────────────────

class Wd11Test(TimeBase):
    CASE = 'E-WD-11'

    def list_said(self, job):
        return {'waited': True, 'rows': [job['control']]}

    def run11(self, said=None):
        return self.go(self.CASE, {None: said or self.list_said})

    def test_pass_files_user_rows_room_and_messages_are_gone_and_the_room_leaves_the_list(self):
        (result, note), phone = self.run11()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.events.count(('gcloud', 'cleanup')), 1)
        self.assertEqual(self.withdraws, ['id-2'])
        self.assertNotIn('id-2', [u['id'] for u in self.fake.users])
        self.assertIn('id-1', [u['id'] for u in self.fake.users])
        for bucket in BUCKETS:
            self.assertFalse([p for p in self.files[bucket] if p.startswith('id-2/')], bucket)
        job = phone.jobs[-1]
        self.assertEqual((job['nickname'], job['control']), (self.nick(2), self.nick(3)))

    def test_every_bucket_had_a_file_and_withdrawn_at_was_31_days_back_at_the_batch(self):
        seen = {}
        real = self.gcloud

        def batch(name):
            seen['files'] = {b: len([p for p in self.files[b] if p.startswith('id-2/')]) for b in BUCKETS}
            seen['at'] = next(r['withdrawn_at'] for r in self.fake.tables['profiles'] if r['id'] == 'id-2')
            seen['messages'] = len(self.fake.tables.get('messages', []))
            real(name)
        with mock.patch.object(tools, 'batch', batch):
            self.run11()
        self.assertTrue(all(n >= 1 for n in seen['files'].values()), seen['files'])
        self.assertLess(abs((now() - when(seen['at'])).total_seconds() - 31 * 86400), 120)
        self.assertGreater(seen['messages'], 0)

    def test_a_cleanup_that_keeps_files_is_a_fail_naming_the_bucket(self):
        self.cleanup_drops_files = False
        (result, note), _ = self.run11()
        self.assertEqual(result, 'fail', note)
        self.assertIn('avatars', note)

    def test_a_cleanup_that_keeps_the_room_is_a_fail(self):
        real = TimeBase.sim_cleanup

        def keep(s):
            rooms = list(s.fake.tables['matches'])
            real(s)
            s.fake.tables['matches'] = rooms
        with mock.patch.object(TimeBase, 'sim_cleanup', keep):
            (result, note), _ = self.run11()
        self.assertEqual(result, 'fail', note)
        self.assertIn('matches', note)

    def test_a_cleanup_that_never_deletes_the_user_is_blocked(self):
        self.cleanup_drops_users = False
        (result, note), _ = self.run11()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('auth 사용자', note)

    def test_the_room_still_in_the_list_is_a_fail_and_an_undrawn_list_is_blocked(self):
        (result, note), _ = self.run11(lambda job: {'waited': True, 'rows': [job['control'], job['nickname']]})
        self.assertEqual(result, 'fail', note)
        self.setUp()
        (result, note), _ = self.run11({'waited': False, 'rows': []})
        self.assertEqual(result, 'blocked', note)

    def test_the_cleanup_gate_is_checked_before_any_account(self):
        self.clock[0] = self.clock[0].replace(hour=4, minute=0)
        (result, note), _ = self.run11()
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.fake.users, [])


if __name__ == '__main__':
    unittest.main()
