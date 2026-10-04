"""기기 쪽 공용 도우미 — 영역 4 가 쓴다. tools.py 는 다른 창이 같이 고쳐 여기에 둔다."""

import time

from e2e import tools
from e2e.tools import Blocked

# 껐다 켠 뒤 망이 돌아오기를 기다리는 시간 — 기기마다 달라 정해진 값이 없다. 모자라면 가설이 "망 없음" 으로 틀리게 본다.
SETTLE_SECONDS = 8


def airplane(serial, on, settle=None):
    """비행기 모드 켜기 · 끄기. 바뀐 상태를 다시 읽어 확인한다 — 안 바뀌면(권한이 없는 기기) [Blocked].
    끌 때는 망이 돌아올 때까지 [settle] 초 기다린다(기본 [SETTLE_SECONDS])."""
    tools.adb(serial, 'shell', 'cmd', 'connectivity', 'airplane-mode', 'enable' if on else 'disable')
    state = tools.adb(serial, 'shell', 'cmd', 'connectivity', 'airplane-mode').strip()
    if state != ('enabled' if on else 'disabled'):
        raise Blocked(f"비행기 모드가 {'켜지' if on else '꺼지'}지 않음(상태 {state!r}) — shell 권한으로 안 되는 기기인가")
    if not on:
        time.sleep(SETTLE_SECONDS if settle is None else settle)


def ensure_online(serial):
    """망이 어떤 이유로든 꺼진 채 남지 않게 — 아직 비행기 모드면 끄고 망이 돌아올 때까지 기다린다. 이미 꺼져 있으면 아무것도 안 한다."""
    if tools.adb(serial, 'shell', 'cmd', 'connectivity', 'airplane-mode').strip() == 'enabled':
        airplane(serial, False)
