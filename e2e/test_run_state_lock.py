"""Run.remember(accounts.json) · Run.alias(별칭_번호표.txt)가 스레드 여럿이 동시에 불려도 온전한가 — 파일만 쓰고 운영 · 기기 · 네트워크는 안 쓴다.
저장소 루트에서 `python -m unittest e2e.test_run_state_lock`.

배경: E-CHAT-38 첫 실행이 "JSONDecodeError: Extra data" 로 막혔다 — 두 곳에서 동시에 remember 를 불러 짧은 쪽 내용 위에 긴 쪽 꼬리(`]`)가 남은 것.
스레드가 쉽게 갈아타도록 전환 간격을 아주 작게 줄이고(sys.setswitchinterval) 읽기와 쓰기 사이에 끼어들 틈을 크게 만들어 잠금이 없으면 거의 매번 깨지게 한다."""

import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from e2e import tools
from e2e.tools import Run

CFG = {'SUPABASE_URL': 'https://sb.test', 'SUPABASE_ANON_KEY': 'anon', 'API_BASE_URL': 'https://api.test', 'E2E_MAIL_BASE': 'base@gmail.com'}
EACH = 50


def account(n):
    return {'n': n, 'email': f'e{n}@x.test', 'id': f'id-{n}', 'stage': 'new', 'at': '2026-10-07T00:00:00+00:00'}


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.run = Run(self.root / 'bundle', 'b', cfg=CFG, key='svc')
        old = sys.getswitchinterval()
        sys.setswitchinterval(1e-6)
        self.addCleanup(sys.setswitchinterval, old)

    def together(self, work):
        """[work](스레드 번호) 를 두 스레드가 동시에 시작해 끝까지 돈다. 스레드 안의 예외는 모아서 돌려준다."""
        errors, start = [], threading.Barrier(2)

        def go(who):
            try:
                start.wait()
                work(who)
            except Exception as e:  # noqa: BLE001 — 시험이 원인을 그대로 보여 주려고 모은다
                errors.append(e)
        threads = [threading.Thread(target=go, args=(who,)) for who in (0, 1)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        return errors


class RememberTest(Base):
    def test_two_threads_remembering_fifty_each_leave_a_whole_json_with_every_n(self):
        errors = self.together(lambda who: [self.run.remember(account(who * 1000 + i)) for i in range(EACH)])
        self.assertEqual(errors, [])
        written = json.loads((self.run.out / 'accounts.json').read_text(encoding='utf-8'))  # 깨졌으면 여기서 JSONDecodeError
        self.assertEqual(sorted(a['n'] for a in written), sorted([w * 1000 + i for w in (0, 1) for i in range(EACH)]))

    def test_the_same_account_remembered_again_replaces_its_line_instead_of_doubling(self):
        self.run.remember(account(7))
        self.run.remember({**account(7), 'stage': 'basic'})
        written = json.loads((self.run.out / 'accounts.json').read_text(encoding='utf-8'))
        self.assertEqual([(a['n'], a['stage']) for a in written], [(7, 'basic')])

    def test_the_file_is_swapped_in_whole_by_os_replace_and_no_temp_file_is_left(self):
        swaps = []
        real = os.replace
        with mock.patch.object(tools.os, 'replace', lambda src, dst: (swaps.append((Path(src).name, Path(dst).name)), real(src, dst))[1]):
            self.run.remember(account(1))
        self.assertEqual(len(swaps), 1)
        self.assertTrue(swaps[0][0].startswith('accounts.json.') and swaps[0][0].endswith('.tmp'), swaps)
        self.assertEqual(swaps[0][1], 'accounts.json')
        self.assertEqual([p.name for p in self.run.out.iterdir()], ['accounts.json'])

    def test_a_write_that_dies_halfway_leaves_the_old_file_untouched(self):
        self.run.remember(account(1))
        before = (self.run.out / 'accounts.json').read_text(encoding='utf-8')
        with mock.patch.object(tools.os, 'replace', side_effect=OSError('디스크')):
            with self.assertRaises(OSError):
                self.run.remember(account(2))
        self.assertEqual((self.run.out / 'accounts.json').read_text(encoding='utf-8'), before)

    def test_a_replace_that_windows_refuses_while_a_reader_has_the_file_open_is_tried_again(self):
        real, calls = os.replace, []

        def flaky(src, dst):
            calls.append(1)
            if len(calls) < 3:
                raise PermissionError('다른 쪽이 읽는 중')
            return real(src, dst)
        with mock.patch.object(tools.os, 'replace', flaky), mock.patch.object(tools.time, 'sleep'):
            self.run.remember(account(1))
        self.assertEqual(len(calls), 3)
        self.assertEqual(json.loads((self.run.out / 'accounts.json').read_text(encoding='utf-8'))[0]['n'], 1)


class AliasTest(Base):
    def test_two_threads_taking_fifty_numbers_each_never_get_the_same_number(self):
        got = [[], []]
        errors = self.together(lambda who: [got[who].append(self.run.alias()[0]) for _ in range(EACH)])
        self.assertEqual(errors, [])
        every = got[0] + got[1]
        self.assertEqual(len(every), len(set(every)), '같은 번호를 두 번 받음')
        self.assertEqual(sorted(every), list(range(1001, 1001 + 2 * EACH)))
        self.assertEqual((self.root / '별칭_번호표.txt').read_text(encoding='utf-8'), str(1001 + 2 * EACH))

    def test_the_ticket_is_swapped_in_whole_and_leaves_no_temp_file(self):
        self.run.alias()
        self.assertEqual(sorted(p.name for p in self.root.iterdir() if p.is_file()), ['별칭_번호표.txt'])


if __name__ == '__main__':
    unittest.main()
