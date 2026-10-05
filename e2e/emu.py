"""에뮬(B) — 준비 점검(`python -m e2e emu`)과, 에뮬에서만 하는 조작(네트워크 · 시계 · 브라우저).

조작은 전부 시리얼이 `emulator-` 로 시작해야 한다 — 실폰의 와이파이 · 시계 · 브라우저를 건드리지 않게 하는 문이다.
"""

import contextlib
import re
import time
from collections import namedtuple
from datetime import datetime, timedelta, timezone

from e2e import tools
from e2e.tools import Blocked, DEVICE_PORT, DEVICES, PACKAGE

Row = namedtuple('Row', 'name ok detail hard')

# 약관 "보기" 가 여는 주소와 같은 종류(https) — 이걸 받을 수 있는 앱이 곧 "브라우저".
VIEW_URL = 'https://www.notion.so/'


def require_emulator(serial):
    if not (serial or '').startswith('emulator-'):
        raise Blocked(f'에뮬에서만 돈다(--device B). 지금 기기: {serial or "없음"}')


def check(serial, wait=0, sleep=time.sleep):
    """에뮬이 실폰과 똑같이 쓸 수 있는지 읽기만 해서 본다. [wait] 초까지 부팅이 끝나기를 기다린다. hard 가 아닌 줄은 참고(blocked 예상 등)."""
    rows = []

    def add(name, ok, detail='', hard=True):
        rows.append(Row(name, ok, detail, hard))
        return ok

    if not add('연결', f'{serial}\tdevice' in tools.devices(), serial):
        return rows
    prop = lambda key: tools.adb(serial, 'shell', 'getprop', key, check=False).strip()
    booted = False
    for _ in range(wait // 2 + 1):
        booted = prop('sys.boot_completed') == '1'
        if booted:
            break
        sleep(2)
    if not add('부팅 끝남', booted, '' if booted else f'{wait}초 안에 sys.boot_completed 가 안 켜짐'):
        return rows
    add('이미지', True, f"Android API {prop('ro.build.version.sdk')} · {prop('ro.product.cpu.abi')} · 에뮬레이터={prop('ro.kernel.qemu') == '1'}", hard=False)
    installed = f'package:{PACKAGE}' in tools.adb(serial, 'shell', 'pm', 'list', 'packages', PACKAGE, check=False)
    add('앱 설치', installed, PACKAGE if installed else 'debug APK 를 설치해야 한다(flutter build apk --debug -t integration_test/e2e_test.dart)')
    uid = tools.adb(serial, 'shell', 'run-as', PACKAGE, 'id', check=False)
    add('run-as kill -9 가능(debug 빌드)', 'uid=' in uid, '' if 'uid=' in uid else uid.strip() or '설치 안 됨')
    forward = tools.adb(serial, 'reverse', '--list', check=False)
    add('adb reverse 우편함', f'tcp:{DEVICE_PORT}' in forward, '' if f'tcp:{DEVICE_PORT}' in forward else '아직 없음 — run 이 처음 폰 가설에서 연결한다', hard=False)
    debuggable = prop('ro.debuggable') == '1'
    add('시계 조작(E-AUTH-19)', debuggable,
        'ro.debuggable=1 — adb root 가 될 수 있다' if debuggable else 'ro.debuggable=0 — adb root 가 막혀 E-AUTH-19 는 blocked 예상', hard=False)
    svc = tools.adb(serial, 'shell', 'which', 'svc', check=False).strip()
    add('네트워크 끄기(E-AUTH-22 · E-GATE-47)', bool(svc), svc or 'svc 없음', hard=False)
    found = browsers(serial)
    add('브라우저(E-GATE-12)', bool(found), ', '.join(found) or 'https 를 받는 앱 없음 — 끌 것이 없다', hard=False)
    return rows


# ── 네트워크 ─────────────────────────────────────────────────────────────────────────────────────


def net(serial, on):
    require_emulator(serial)
    word = 'enable' if on else 'disable'
    # 에뮬은 모바일 데이터가 없어 `svc data` 가 종료 코드 20 으로 끝난다(10-05 첫 실행) — 명령 결과는 보지 않고,
    # 정말 끊겼는지 · 돌아왔는지는 호출한 쪽이 핑으로 다시 읽어 판정한다.
    tools.adb(serial, 'shell', 'svc', 'wifi', word, check=False)
    tools.adb(serial, 'shell', 'svc', 'data', word, check=False)


_NO_LOSS = re.compile(r'(?<!\d)0% packet loss')


def online(serial):
    """핑이 닿는지. "100% packet loss" 가 "0% packet loss" 로 읽히지 않게 앞 글자를 본다."""
    out = tools.adb(serial, 'shell', 'ping', '-c', '1', '-W', '2', '8.8.8.8', check=False)
    return bool(_NO_LOSS.search(out))


def wait_net(serial, on, timeout=40, sleep=time.sleep):
    for _ in range(max(1, timeout // 2)):
        if online(serial) == on:
            return True
        sleep(2)
    return False


def go_offline(serial, sleep=time.sleep):
    """와이파이 · 데이터를 끄고 정말 끊겼는지 본다 — 안 끊기면 다시 켜고 blocked."""
    net(serial, False)
    if not wait_net(serial, False, timeout=10, sleep=sleep):
        net(serial, True)
        raise Blocked('네트워크를 끄지 못함(핑이 계속 닿음)')


def go_online(serial, timeout=40, sleep=time.sleep):
    """켜고 닿을 때까지 기다린다 → 닿았는지."""
    net(serial, True)
    if not wait_net(serial, True, timeout=timeout, sleep=sleep):
        return False
    sleep(2)  # 핑은 IP 라 DNS 가 준비됐다는 보장이 없다 — 앱의 첫 요청이 이름 풀이에서 지지 않게 잠깐 둔다
    return True


# ── 시계 ─────────────────────────────────────────────────────────────────────────────────────────


def root(serial, hub=None, sleep=time.sleep):
    """adb root. adbd 가 다시 떠서 `adb reverse` 가 사라지므로 우편함 연결을 다시 건다."""
    require_emulator(serial)
    tools.adb(serial, 'root', check=False)
    tools.adb(serial, 'wait-for-device', check=False)
    for _ in range(10):
        if 'uid=0' in tools.adb(serial, 'shell', 'id', check=False):
            break
        sleep(1)
    else:
        raise Blocked('에뮬이 root 를 안 줌(google_apis_playstore 이미지는 user 빌드라 adb root 가 막힌다) — 시계를 못 바꾼다')
    port = hub.port if hub else DEVICES['B']
    tools.adb(serial, 'reverse', f'tcp:{DEVICE_PORT}', f'tcp:{port}')


def epoch(serial):
    return int(tools.adb(serial, 'shell', 'date', '+%s').strip() or 0)


def _set_date(serial, moment):
    tools.adb(serial, 'shell', 'date', '-u', moment.astimezone(timezone.utc).strftime('%m%d%H%M%Y.%S'))


@contextlib.contextmanager
def clock_shifted(serial, hours, now=lambda: datetime.now(timezone.utc)):
    """에뮬 시계를 지금(PC 시계)보다 [hours] 시간 앞으로 — root 필요. 끝나면(실패해도) PC 시계로 되돌리고 자동 시각을 켠다."""
    require_emulator(serial)
    target = now() + timedelta(hours=hours)
    try:
        tools.adb(serial, 'shell', 'settings', 'put', 'global', 'auto_time', '0')
        _set_date(serial, target)
        if abs(epoch(serial) - target.timestamp()) > 120:
            raise Blocked('에뮬 시계가 안 바뀜(date 가 거부됨 — root 확인)')
        yield
    finally:
        try:
            _set_date(serial, now())
        finally:  # date 가 거부돼도(root 아님) 자동 시각은 꼭 되돌린다
            tools.adb(serial, 'shell', 'settings', 'put', 'global', 'auto_time', '1')


# ── 시간대 ───────────────────────────────────────────────────────────────────────────────────────


SEOUL = 'Asia/Seoul'


def _zone(serial):
    return tools.adb(serial, 'shell', 'getprop', 'persist.sys.timezone', check=False).strip()


def _set_zone(serial, zone):
    tools.adb(serial, 'shell', 'service', 'call', 'alarm', '3', 's16', zone, check=False)  # root 없이 된다


@contextlib.contextmanager
def seoul_timezone(serial, sleep=time.sleep):
    """에뮬 시간대를 서울로 — 앱이 달력 날짜(D-숫자 · "M월 D일")를 PC 와 같게 세려면 필요하다(에뮬 기본은 GMT).
    이미 서울이면 아무것도 안 하고, 아니면 바꿔 둔 동안만 서울이다 — 끝나면(실패해도) 원래 값으로 되돌린다."""
    require_emulator(serial)
    before = _zone(serial)
    if before == SEOUL:
        yield
        return
    _set_zone(serial, SEOUL)
    try:
        for _ in range(5):  # 속성에 퍼지기까지 잠깐 걸린다
            if _zone(serial) == SEOUL:
                break
            sleep(1)
        else:
            raise Blocked(f'에뮬 시간대를 서울로 못 바꿈(지금 {_zone(serial) or "읽지 못함"}) — service call alarm 3 이 안 먹음')
        yield
    finally:
        if before:
            _set_zone(serial, before)


# ── 브라우저 ─────────────────────────────────────────────────────────────────────────────────────


def browsers(serial):
    """https 를 받을 수 있는 앱의 패키지들."""
    out = tools.adb(serial, 'shell', 'pm', 'query-activities', '--brief', '-a', 'android.intent.action.VIEW', '-d', VIEW_URL, check=False)
    return sorted({m.group(1) for line in out.splitlines() if 'priority=' not in line and (m := re.match(r'\s*([\w.]+)/\S+', line))})


@contextlib.contextmanager
def browsers_disabled(serial):
    """https 를 받는 앱을 모두 `pm disable-user` 로 끈다 — 끝나면(실패해도) 다시 켠다. 못 끄면 blocked."""
    require_emulator(serial)
    off = set()
    try:
        for _ in range(4):
            found = browsers(serial)
            if not found:
                break
            for package in found:
                out = tools.adb(serial, 'shell', 'pm', 'disable-user', '--user', '0', package, check=False)
                if 'disabled-user' not in out:
                    raise Blocked(f'브라우저 {package} 를 못 끔: {out.strip()}')
                off.add(package)
        else:
            raise Blocked(f'브라우저가 끈 뒤에도 남음: {", ".join(browsers(serial))}')
        yield
    finally:
        for package in sorted(off):
            tools.adb(serial, 'shell', 'pm', 'enable', package, check=False)
