"""두 기기(폰 A + 에뮬 B)를 동시에 돌리는 E2E 실행기 — 한 가설을 두 앱이 서로 기다려 가며 같이 돈다. 표준 라이브러리만 쓴다.

[tools.Run.phone] 은 앱을 켜고 `step` 에서 한 번만 멈출 수 있고 기기도 하나다. 여기서는 기기마다 스레드 하나가
앱을 켜고, 앱이 `step` 을 말할 때마다 [plan] 의 핸들러를 부른 뒤 go 를 보낸다(몇 번이든). 두 스레드는 [Sync] 로 서로를 기다린다.

사용법(가설 하나 = `(run, two) -> (결과, 메모)` 함수를 [TWO] 에 번호로 등록):

    def e_chat_09(run, two):
        # 계정 · DB 준비는 이 함수(메인 스레드)에서
        def b_sends(said, sync):                      # said = 앱 말 + 't'(PC 가 받은 time.monotonic)
            send_message_by_api()
            sync.set('b-sent')
        def a_waits(said, sync):
            if not sync.wait('b-sent', 60):           # 시간 안에 안 오면 False, 상대가 끝났으면 Aborted
                raise Blocked('B 가 안 보냄')
            return {'token_hash': new_token}          # dict 를 돌려주면 go 에 실려 앱의 step() 이 받는다
        return two({('A', 'wait_b'): a_waits, ('B', 'send'): b_sends},
                   a_job={'token_hash': ta}, b_job={'token_hash': tb}, side_timeout={'B': 300})
    twodev.TWO['E-CHAT-09'] = e_chat_09

- 앱 키: 일감의 case 는 `E-CHAT-09/A` · `E-CHAT-09/B` 로 자동 붙는다 — e2e_test.dart 의 `cases` 에 두 키를 모두 등록한다.
- 핸들러가 없는 step 은 그냥 go. 앱 쪽 `step(name, timeout: Duration(minutes: 5))` 로 앱의 기다림 상한도 늘릴 수 있다.
- 상한: `side_timeout` 은 "다음 말까지 기다리는 시간"(기본 A 120초 · B 240초, 숫자 하나 또는 `{'B': 300}`), `deadline` 은 전체(기본 합 + [MARGIN]초).
  어떤 기다림이든 상한이 있고, 한쪽이 실패 · 상한 초과 · 예외로 끝나면 상대가 풀린다. 한쪽이 pass 로 끝난 것은 상대를 끊지 않는다(안 오는 Sync 이름만 풀린다).
- 스레드는 Hub · adb 만 쓴다. 기록 · 계정 목록(Run)은 메인 스레드([two] 호출 전후)에서만 만진다.

한계: 앱 재기동은 [tools.Run.phone] 앞부분의 복사본이다(합치기는 백로그). 푸시 알림은 에뮬 FCM 이 안 되면 blocked 로 다룬다.
"""

import threading
import time
from typing import NamedTuple

from e2e import tools
from e2e.tools import PACKAGE

KILL_PAUSE = 0.5  # 앞 앱 프로세스가 꺼졌는지 다시 보기까지(시험이 0 으로 낮춘다)
SLICE = 0.2  # 말을 기다리는 한 토막 — 토막마다 중단 신호를 본다
GRACE = 2  # 전체 상한 뒤 스레드가 스스로 끝나기를 기다려 주는 시간
MARGIN = 60  # 전체 상한 기본값 = side_timeout 합 + 이만큼
DEFAULT_TIMEOUT = {'A': 120, 'B': 240}
TWO = {}  # 가설 번호 → (run, two) -> (결과, 메모). __main__ 이 이 번호를 보고 두 기기를 연다.


class Aborted(Exception):
    """상대 쪽이 끝나 기다리던 것이 영영 안 온다."""


class Side(NamedTuple):
    """기기 하나 — 우편함 · adb 시리얼 · 일감에 더할 값(case 는 [two] 가 붙인다)."""
    hub: object
    serial: str
    job: dict = {}


class Sync:
    """두 스레드가 서로 기다리는 이름표. 어떤 [wait] 든 상한이 있고 [abort] 에 풀린다."""

    def __init__(self):
        self._cond = threading.Condition()
        self._names = set()
        self._aborted = False

    def set(self, name):
        with self._cond:
            self._names.add(name)
            self._cond.notify_all()

    def wait(self, name, timeout):
        """[name] 이 서면 True, [timeout] 초 안에 안 서면 False, 그 전에 [abort] 가 서고 [name] 도 없으면 [Aborted]."""
        with self._cond:
            self._cond.wait_for(lambda: name in self._names or self._aborted, timeout)
            if name in self._names:  # abort 보다 먼저 선 이름은 그대로 들린다
                return True
            if self._aborted:
                raise Aborted(f"상대 쪽이 끝나 '{name}' 를 받지 못함")
            return False

    def abort(self):
        with self._cond:
            self._aborted = True
            self._cond.notify_all()

    def now(self):
        return time.monotonic()


class _Stopped(Exception):
    """이 쪽 기다림을 그만둔다(상대 실패 · 시간 초과). 메시지가 결과 메모가 된다."""


def limits(side_timeout, deadline):
    """→ ({'A': 초, 'B': 초}, 전체 상한 초). 숫자 하나는 두 쪽 다, dict 는 준 쪽만 덮는다."""
    per = dict(DEFAULT_TIMEOUT)
    if isinstance(side_timeout, dict):
        per.update(side_timeout)
    elif side_timeout is not None:
        per = {'A': side_timeout, 'B': side_timeout}
    return per, deadline if deadline is not None else sum(per.values()) + MARGIN


def merge(a, b):
    """두 쪽 결과(dict · 말이 없으면 None) → (결과, 메모). 한쪽이라도 fail → fail, 아니면 blocked 하나라도 → blocked, 둘 다 pass → pass."""
    rows = {}
    for name, said in (('A', a), ('B', b)):
        rows[name] = said or {'result': 'blocked', 'note': f'{name} 쪽이 상한 안에 말하지 않음'}
    results = [r['result'] for r in rows.values()]
    result = 'fail' if 'fail' in results else 'pass' if results == ['pass', 'pass'] else 'blocked'
    memo = '  '.join(f"{n}: {r['result']}" + (f" - {r['note']}" if r.get('note') else '') for n, r in rows.items())
    return result, memo.replace('\n', ' ')


def _launch(serial):
    """앱을 새로 켠다 — [tools.Run.phone] 앞부분의 복사. 안 꺼지면 이유(str), 켰으면 None."""
    tools.adb(serial, 'shell', 'input', 'keyevent', 'KEYCODE_HOME')
    for _ in range(10):
        pid = tools.adb(serial, 'shell', 'pidof', PACKAGE, check=False).strip()
        if not pid:
            break
        tools.adb(serial, 'shell', 'run-as', PACKAGE, 'kill', '-9', pid, check=False)
        time.sleep(KILL_PAUSE)
    else:
        return '앞 앱 프로세스가 꺼지지 않음(debug 빌드인가 — run-as 는 debug 만 된다)'
    tools.adb(serial, 'shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
    return None


class Two:
    """가설 하나를 두 기기에서 같이 돈다. [go] 가 (결과, 메모)."""

    def __init__(self, run, case, a, b, plan, side_timeout=None, deadline=None):
        self.run, self.case, self.sides, self.plan = run, case, {'A': a, 'B': b}, plan
        self.timeout, self.deadline = limits(side_timeout, deadline)
        self.sync, self._halt = Sync(), threading.Event()
        self.results = {}

    def go(self):
        self.end = time.monotonic() + self.deadline
        threads = [threading.Thread(target=self._side, args=(n,), daemon=True) for n in self.sides]
        for t in threads:
            t.start()
        for t in threads:
            t.join(max(0, self.end - time.monotonic()))
        if any(t.is_alive() for t in threads):  # 핸들러가 Sync 밖에서 매달린 경우 — 스레드는 두고 결과만 막힘으로 닫는다
            self._halt.set()
            self.sync.abort()
            for t in threads:
                t.join(GRACE)
        for name, side in self.sides.items():
            said = self.results.get(name) or self._blocked(name, '전체 상한 초과로 끊음')
            self.results[name] = said
            if said['result'] == 'fail':  # 스레드는 Run 을 안 만지므로 화면 캡처는 여기서
                self.run.shot(side.serial, f'{self.case}-{name}')
        return merge(self.results['A'], self.results['B'])

    def _blocked(self, name, note):
        return {'case': f'{self.case}/{name}', 'result': 'blocked', 'note': note}

    def _side(self, name):
        try:
            result = self._drive(name, self.sides[name])
        except _Stopped as e:
            result = self._blocked(name, str(e))
        except Exception as e:  # 핸들러 · adb 의 예외는 이 쪽 blocked 로 — 스레드가 조용히 죽으면 상대가 매달린다
            result = self._blocked(name, f'{type(e).__name__}: {e}')
        self.results[name] = result
        if result['result'] != 'pass':
            self._halt.set()  # 상대의 기다림 · 말 듣기를 끊는다
        self.sync.abort()  # 끝난 쪽이 앞으로 세울 이름은 없다 — 안 오는 이름을 기다리는 상대를 푼다

    def _drive(self, name, side):
        job = {**side.job, 'case': f'{self.case}/{name}'}
        why = _launch(side.serial)
        if why:
            return self._blocked(name, why)
        side.hub.tell(job)
        while True:
            said = self._hear(name, side.hub)
            if 'result' in said:
                return said
            if 'step' not in said:  # 중간 값(로그인 됨 등)은 건너뛴다
                continue
            handler = self.plan.get((name, said['step']))
            extra = handler({**said, 't': time.monotonic()}, self.sync) if handler else None
            if self._halt.is_set():
                raise _Stopped('상대 쪽이 먼저 실패해 멈춤')
            side.hub.go(extra if isinstance(extra, dict) else None)

    def _hear(self, name, hub):
        """앱의 다음 말. 이 쪽 상한 · 전체 상한 · 상대 실패 중 먼저 오는 것에 [_Stopped]."""
        until = time.monotonic() + self.timeout[name]
        while True:
            left = min(until, self.end) - time.monotonic()
            if left <= 0:  # 전체 상한을 먼저 본다 — 그래야 둘 다 같은 이유로 적힌다
                raise _Stopped(f'{name} 쪽이 상한 안에 말하지 않음' if until <= self.end else '전체 상한 초과')
            if self._halt.is_set():
                raise _Stopped('상대 쪽이 먼저 실패해 멈춤')
            said = hub.wait(min(SLICE, left))
            if said is not None:
                return said


def two(run, case, a, b, plan, side_timeout=None, deadline=None):
    """[plan] = {('A'|'B', step 이름): fn(said, sync) -> dict | None}. → (결과, 메모)."""
    return Two(run, case, a, b, plan, side_timeout, deadline).go()


def bound(run, case, a, b):
    """가설 함수가 받는 `two` — 가설 번호 · 기기는 묶어 두고 계획 · 기기별 일감 · 상한만 받는다."""
    def call(plan, a_job=None, b_job=None, **limit):
        return two(run, case, a._replace(job=a_job or {}), b._replace(job=b_job or {}), plan, **limit)
    return call
