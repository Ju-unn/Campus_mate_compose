"""기기 쪽 공용 도우미 — 영역 4 가 쓴다. tools.py 는 다른 창이 같이 고쳐 여기에 둔다."""

import subprocess
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


def grant_notifications(serial):
    """이 앱에만 알림 권한을 미리 준다 — 첫 실행의 권한 창이 앱을 멈춰 세우지 않게. 끝나면 [revoke_notifications].
    안드로이드 12 이하처럼 이 권한이 없는 기기는 pm 이 오류를 내므로 [Blocked]."""
    try:
        tools.adb(serial, 'shell', 'pm', 'grant', tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS')
    except subprocess.CalledProcessError as error:
        raise Blocked(f'알림 권한을 줄 수 없음(안드로이드 13 이상인가) — pm grant 가 {error.returncode} 로 끝남') from error


def revoke_notifications(serial):
    """[grant_notifications] 를 되돌린다 — 실패해도 시험 결과를 덮지 않는다."""
    tools.adb(serial, 'shell', 'pm', 'revoke', tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS', check=False)


def screen_has(serial, text):
    """지금 화면에 [text] 가 있는지. 화면 글자 원문은 돌려주지도 저장하지도 않는다(실폰 화면에는 남의 내용이 있을 수 있다).
    바이트로 받아 utf-8 로 읽는다 — 윈도 로케일(cp949)에 맡기면 한글 덤프에서 읽기가 죽는다."""
    done = subprocess.run(['adb', '-s', serial, 'shell', 'uiautomator', 'dump', '/dev/tty'], capture_output=True)
    return text in done.stdout.decode('utf-8', 'replace')
