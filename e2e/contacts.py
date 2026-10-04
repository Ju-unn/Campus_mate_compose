"""에뮬 연락처 · 연락처 권한(READ_CONTACTS) 도우미. 전부 시리얼이 `emulator-` 일 때만 움직인다 — 실폰에는 연락처를 넣지 않는다.

넣은 연락처에는 `sourceid=e2e-NNNN` 표를 달아, 지울 때 우리 것만 지운다(기기에 원래 있던 연락처는 건드리지 않는다).
많이 넣으려고 스크립트를 한 번 올려 기기에서 돌린다 — `content insert` 를 adb 한 번씩 부르면 201명에 10분이 넘는다.
"""

import contextlib
import re
import subprocess
import tempfile
import time
from pathlib import Path

from e2e import emu, notify, tools
from e2e.tools import Blocked, PACKAGE

READ = 'android.permission.READ_CONTACTS'
TAG = 'e2e-'
RAW = 'content://com.android.contacts/raw_contacts'
DATA = 'content://com.android.contacts/data'
REMOTE = '/data/local/tmp/e2e-contacts.sh'
SCRIPT_PATIENCE = 900  # 연락처 스크립트 하나가 끝나기를 기다리는 최대 초
BIG_LIMIT = 1500  # 201명을 넣는 가설 하나(넣기 900 + 앱 + 지우기)에 줄 시간 — 가설이 tools.CASE_LIMITS 에 스스로 적는다
PARALLEL = 6  # content 명령(자바 기동)이 한 번에 1.8초라 하나씩 하면 603번에 18분 — 몇 개씩 같이 돌린다
NAME_TYPE, PHONE_TYPE = 'vnd.android.cursor.item/name', 'vnd.android.cursor.item/phone_v2'
# 권한 창 버튼 — 글자는 기기 언어를 타서 resource-id 로 찾는다.
ALLOW = 'com.android.permissioncontroller:id/permission_allow_button'
DENY = 'com.android.permissioncontroller:id/permission_deny_button'


# ── 권한 ─────────────────────────────────────────────────────────────────────────────────────────


def has_permission(serial):
    out = tools.adb(serial, 'shell', 'dumpsys', 'package', PACKAGE, check=False)
    return bool(re.search(r'READ_CONTACTS: granted=true', out))


def grant(serial):
    emu.require_emulator(serial)
    tools.adb(serial, 'shell', 'pm', 'grant', PACKAGE, READ)
    if not has_permission(serial):
        raise Blocked('연락처 권한을 줬는데 granted=true 가 아님')


def revoke(serial):
    """권한을 없는 상태로. 앞서 거부를 쌓아 "다시 묻지 않음" 이 되어 있으면 권한 창이 안 뜨므로 먼저 권한 상태를 처음으로 되돌린다
    (`pm reset-permissions` — 에뮬 전체의 런타임 권한이 처음 상태가 된다)."""
    emu.require_emulator(serial)
    tools.adb(serial, 'shell', 'pm', 'reset-permissions', check=False)
    tools.adb(serial, 'shell', 'pm', 'revoke', PACKAGE, READ, check=False)
    if has_permission(serial):
        raise Blocked('연락처 권한을 껐는데 granted=true 로 남음')


def _dump(serial):
    return tools.adb_bytes(serial, 'exec-out', 'uiautomator', 'dump', '/dev/tty').decode('utf-8', 'replace')


def tap_dialog(serial, allow, timeout=15, sleep=time.sleep):
    """OS 권한 창의 허용 · 거부 버튼을 누른다(uiautomator 로 위치를 찾아 `input tap`). 창이 안 뜨면 [Blocked]."""
    emu.require_emulator(serial)
    wanted = ALLOW if allow else DENY
    for _ in range(max(1, timeout // 2)):
        match = re.search(rf'resource-id="{re.escape(wanted)}"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', _dump(serial))
        if match:
            x1, y1, x2, y2 = map(int, match.groups())
            tools.adb(serial, 'shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
            return
        sleep(2)
    raise Blocked(f'{timeout}초 안에 권한 창이 안 뜸 — "다시 묻지 않음" 상태일 수 있다(`adb shell pm reset-permissions` 뒤 다시)')


# ── 연락처 ───────────────────────────────────────────────────────────────────────────────────────


def _run(serial, lines):
    """[lines] 를 기기 스크립트로 올려 한 번에 돌린다. 출력에 예외가 있으면 [Blocked]."""
    with tempfile.TemporaryDirectory() as folder:
        local = Path(folder) / 'e2e-contacts.sh'
        batches = []
        for start in range(0, len(lines), PARALLEL):
            batches += [f'{line} &' for line in lines[start:start + PARALLEL]] + ['wait']
        local.write_text('\n'.join(batches) + '\n', encoding='utf-8', newline='\n')
        tools.adb(serial, 'push', str(local), REMOTE)
    try:
        with tools.adb_patience(SCRIPT_PATIENCE):  # 201명이면 수 분 — 그래도 끝없이는 아니다
            out = tools.adb(serial, 'shell', 'sh', REMOTE)
    except tools.CaseTimeout:  # PC 쪽이 포기해도 기기에 남은 content 명령이 계속 넣으면 뒤처리 뒤에 연락처가 다시 생긴다
        tools.adb(serial, 'shell', 'pkill', '-f', REMOTE, check=False)
        raise
    tools.adb(serial, 'shell', 'rm', '-f', REMOTE, check=False)
    if 'Exception' in out or 'Error' in out:
        raise Blocked(f'연락처 스크립트 오류: {out.strip()[:200]}')


def _tagged(serial):
    """{표: raw_contact _id} — 우리가 넣은 연락처만."""
    out = tools.adb(serial, 'shell', f'content query --uri {RAW} --projection _id:sourceid --where "sourceid LIKE \'{TAG}%\'"', check=False)
    return {m.group(2): int(m.group(1)) for m in re.finditer(r'_id=(\d+), sourceid=(' + TAG + r'\d+)', out)}


def _safe(value):
    if "'" in value:
        raise ValueError(f'작은따옴표는 못 넣는다: {value!r}')
    return value


def insert(serial, people):
    """[people] = [(이름, (번호, ...)), ...] 를 기기 연락처에 넣는다. 먼저 앞 실행의 우리 연락처를 지운다."""
    emu.require_emulator(serial)
    for name, numbers in people:
        _safe(name)
        for number in numbers:
            _safe(number)
    remove_all(serial)
    _run(serial, [f'content insert --uri {RAW} --bind sourceid:s:{TAG}{i:04d}' for i in range(len(people))])
    ids = _tagged(serial)
    absent = [f'{TAG}{i:04d}' for i in range(len(people)) if f'{TAG}{i:04d}' not in ids]
    if absent:
        raise Blocked(f'연락처 {len(absent)}개가 안 만들어짐(예 {absent[0]})')
    lines = []
    for i, (name, numbers) in enumerate(people):
        raw = ids[f'{TAG}{i:04d}']
        lines.append(f"content insert --uri {DATA} --bind raw_contact_id:i:{raw} --bind mimetype:s:{NAME_TYPE} --bind 'data1:s:{name}'")
        for number in numbers:
            lines.append(f"content insert --uri {DATA} --bind raw_contact_id:i:{raw} --bind mimetype:s:{PHONE_TYPE} "
                         f"--bind 'data1:s:{number}' --bind data2:i:2")
    _run(serial, lines)


def _delete(serial, where):
    tools.adb(serial, 'shell', f'content delete --uri "{RAW}?caller_is_syncadapter=true" --where "{where}"', check=False)


def remove_all(serial):
    """우리가 넣은 연락처만 지운다 → 남은 개수(0 이어야 한다)."""
    emu.require_emulator(serial)
    _delete(serial, f"sourceid LIKE '{TAG}%'")
    return len(_tagged(serial))


def delete_person(serial, index):
    """[insert] 로 넣은 사람 하나(순서 번호)를 기기에서 지운다."""
    emu.require_emulator(serial)
    _delete(serial, f"sourceid='{TAG}{index:04d}'")


@contextlib.contextmanager
def on_device(serial, people, granted):
    """연락처를 넣고 권한을 [granted] 로 맞춘 채 본문을 돈다. 끝나면(실패해도) 연락처를 지우고 권한을 없는 상태로 돌린다."""
    emu.require_emulator(serial)
    try:
        insert(serial, people)
        (grant if granted else revoke)(serial)
        # 앱은 로그인하면 알림 권한 창도 띄운다 — 같은 resource-id 의 허용 버튼이라 PC 가 엉뚱한 창을 누르지 않게 미리 준다.
        # `pm reset-permissions`(revoke)가 알림 권한도 지우므로 연락처 권한을 맞춘 뒤에 준다. 이 권한이 없는 기기(안드로이드 12 이하)는 창도 없다.
        with contextlib.suppress(Blocked):
            notify.grant_notifications(serial)
        yield
    finally:
        tools.lift_deadline()
        try:
            remove_all(serial)
        finally:  # 연락처 지우기가 터져도 권한은 되돌린다(터진 오류는 그대로 올라가고 본문 오류는 그 __context__ 에 남는다)
            revoke(serial)
