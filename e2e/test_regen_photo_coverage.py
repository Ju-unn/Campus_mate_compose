"""다시 만들기 알약을 거치는 모든 기기 가설이 PC 쪽에서 `regen_photo` 를 계정을 만들기 전에 부르는지 — 소스에서 모아 한 번에 본다.
저장소 루트에서 `python -m unittest e2e.test_regen_photo_coverage`.

알약은 사진 고르기부터 연다(15b-4 → 15b-5). 앱은 갤러리 훅에 PC 가 앱 캐시에 넣어 둔 `face1.jpg` 를 꽂으므로, PC 프로브가 `regen_photo` 를 빠뜨리면
앱 캐시에 사진이 없어 기기에서 E2eBlocked 가 나거나(앞 가설이 남긴 사진이 있으면) 옛 흐름을 가정한 판정이 틀린다 — PC 시험은 앱을 목으로 대신해 둘 다 못 잡는다.
그래서 손으로 쓴 목록 대신 `frontend/integration_test/*.dart` 에서 `e2eRegenToSheet` 를 (바로 또는 도우미를 거쳐) 부르는 케이스를 모으고,
그 케이스를 등록한 PC 프로브가 (바로 또는 같은 모듈의 도우미를 거쳐) 계정을 만들기 전에 `regen_photo` 를 부르는지 AST 로 본다.
"""

import ast
import re
import unittest
from pathlib import Path

from e2e import tools

SEED = 'e2eRegenToSheet'  # frontend/integration_test/regen_pick.dart — 알약 → 사진 고르기 → 시트
ACCOUNT_CALLS = {'_home', '_signed_in'}  # PC 프로브가 계정을 만드는 도우미(area2/area5_read 의 _home, area1 의 _signed_in)
CASE_ID = re.compile(r'E-[A-Z]+-\d+')
CASE_KEY = re.compile(r"^\s{2}'(E-[A-Z]+-\d+)':")
DECLARATION = re.compile(r'^[A-Za-z_@]')
NAME = re.compile(r'^[^(=]*?(\w+)\s*(?:\(|=)')


def _dart_files():
    return sorted((tools.ROOT / 'frontend' / 'integration_test').glob('*.dart'))


def _code_only(text):
    return '\n'.join(line.split('//', 1)[0] for line in text.split('\n'))


def _chunks(text):
    """맨 왼쪽 칸에서 시작하는 선언 하나(함수 · 가설 표)마다 (이름, 몸통)."""
    lines = _code_only(text).split('\n')
    starts = [i for i, line in enumerate(lines) if DECLARATION.match(line) and not line.startswith(('import ', 'part ', 'export ', 'library '))]
    for begin, end in zip(starts, starts[1:] + [len(lines)]):
        found = NAME.match(lines[begin])
        if found:
            yield found.group(1), '\n'.join(lines[begin:end])


def _case_blocks(chunk):
    """가설 표 안의 `  'E-XX-NN': …` 항목마다 (케이스 번호, 항목 글)."""
    lines = chunk.split('\n')
    starts = [(i, CASE_KEY.match(line).group(1)) for i, line in enumerate(lines) if CASE_KEY.match(line)]
    for (begin, case), (end, _) in zip(starts, starts[1:] + [(len(lines), None)]):
        yield case, '\n'.join(lines[begin:end])


def cases_through_the_pill():
    """`e2eRegenToSheet` 를 직접 · 도우미를 거쳐 부르는 기기 가설 번호."""
    functions, tables = {}, []
    for path in _dart_files():
        for name, body in _chunks(path.read_text(encoding='utf-8')):
            if any(CASE_KEY.match(line) for line in body.split('\n')):
                tables.append(body)
            else:
                functions[name] = body
    reaches = {SEED}
    grew = True
    while grew:
        grew = False
        for name, body in functions.items():
            if name not in reaches and any(re.search(rf'\b{re.escape(known)}\b', body) for known in reaches):
                reaches.add(name)
                grew = True
    return {case for table in tables for case, block in _case_blocks(table)
            if any(re.search(rf'\b{re.escape(known)}\b', block) for known in reaches)}


def _pc_modules():
    return {path: ast.parse(path.read_text(encoding='utf-8')) for path in sorted((tools.ROOT / 'e2e').glob('area*.py'))}


def _registrations(tree):
    """모듈 안 어느 dict 든 `'E-XX-NN': …` 항목의 값이 가리키는 이 모듈의 함수 이름들 — {케이스: {함수 이름}}."""
    functions = {node.name for node in tree.body if isinstance(node, ast.FunctionDef)}
    found = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        for key, value in zip(node.keys, node.values):
            if not (isinstance(key, ast.Constant) and isinstance(key.value, str) and CASE_ID.fullmatch(key.value)):
                continue
            names = {n.id for n in ast.walk(value) if isinstance(n, ast.Name) and n.id in functions}
            if names:
                found.setdefault(key.value, set()).update(names)
    return found


def _events(node, functions, seen=()):
    """함수 몸통에서 `regen_photo` · 계정 만들기 호출의 차례 — 같은 모듈의 도우미는 부른 자리에서 펼친다."""
    calls = sorted((n for n in ast.walk(node) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)), key=lambda n: (n.lineno, n.col_offset))
    out = []
    for call in calls:
        name = call.func.id
        if name == 'regen_photo':
            out.append('regen')
        elif name in ACCOUNT_CALLS:
            out.append('account')
        elif name in functions and name not in seen:
            out.extend(_events(functions[name], functions, (*seen, name)))
    return out


class RegenPhotoCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.needed = cases_through_the_pill()
        cls.probes = {}  # 케이스 → [(모듈 이름, 함수 이름, 차례)]
        for path, tree in _pc_modules().items():
            functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
            for case, names in _registrations(tree).items():
                for name in sorted(names):
                    cls.probes.setdefault(case, []).append((path.name, name, _events(functions[name], functions)))

    def test_the_collector_finds_the_pill_cases_it_should(self):
        # 모으는 쪽이 빈 껍데기가 아니라는 바닥 — 알약을 거치는 줄 알려진 케이스는 늘 잡혀야 한다(새 케이스가 늘면 이 목록 밖에서도 아래 시험이 본다).
        known = {'E-HEART-42', 'E-HEART-43', 'E-HEART-44', 'E-HEART-45', 'E-ME-01', 'E-ME-02', 'E-ME-10', 'E-ME-11', 'E-ME-12', 'E-ME-13', 'E-ME-14',
                 'E-ME-16', 'E-ME-40', 'E-EDGE-04', 'E-EDGE-14', 'E-EDGE-17', 'E-EDGE-18', 'E-EDGE-05', 'E-EDGE-06'}
        self.assertLessEqual(known, self.needed, sorted(known - self.needed))

    def test_cases_that_never_touch_the_pill_are_not_collected(self):
        # E-EDGE-07 은 읽기 실패 화면, E-EDGE-08 은 15-6 저장 한 곳만 본다 — 같은 area5_fake 라도 알약(avatar 걷기)은 05 · 06 만 지난다.
        for case in ('E-ME-38', 'E-ME-39', 'E-ME-41', 'E-ME-42', 'E-ME-43', 'E-ME-44', 'E-EDGE-07', 'E-EDGE-08'):
            self.assertNotIn(case, self.needed)

    def test_every_pill_case_has_a_pc_probe(self):
        self.assertEqual(sorted(case for case in self.needed if case not in self.probes), [])

    def test_every_pc_probe_of_a_pill_case_pushes_the_photo_before_it_makes_the_account(self):
        bad = []
        for case in sorted(self.needed):
            for module, name, events in self.probes.get(case, []):
                if 'regen' not in events:
                    bad.append(f'{case}: {module} {name} 이(가) regen_photo 를 안 부름')
                elif 'account' not in events:
                    bad.append(f'{case}: {module} {name} 에서 계정 만들기({sorted(ACCOUNT_CALLS)}) 호출을 못 찾음 — ACCOUNT_CALLS 에 더해야 하나')
                elif events.index('regen') > events.index('account'):
                    bad.append(f'{case}: {module} {name} 이(가) regen_photo 를 계정을 만든 뒤에 부름')
        self.assertEqual(bad, [])

    def test_the_ordering_check_itself_catches_a_missing_call_and_a_late_call(self):
        tree = ast.parse('def a(run, phone):\n    _home(run)\n\ndef b(run, phone):\n    regen_photo(run, phone)\n    _home(run)\n\n'
                         'def c(run, phone):\n    _home(run)\n    regen_photo(run, phone)\n\ndef d(run, phone):\n    b(run, phone)\n')
        functions = {node.name: node for node in tree.body}
        self.assertEqual(_events(functions['a'], functions), ['account'])
        self.assertEqual(_events(functions['b'], functions), ['regen', 'account'])
        self.assertEqual(_events(functions['c'], functions), ['account', 'regen'])
        self.assertEqual(_events(functions['d'], functions), ['regen', 'account'])  # 도우미를 거쳐도 차례가 이어진다


if __name__ == '__main__':
    unittest.main()
