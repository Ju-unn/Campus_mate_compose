"""기기 쪽 공용 도우미 — 영역 4 가 쓴다. tools.py 는 다른 창이 같이 고쳐 여기에 둔다."""

import subprocess
import re
import time
import xml.etree.ElementTree as ET
from collections import namedtuple
from datetime import datetime, timedelta, timezone

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
    return text in _ui_dump(serial)


DUMP_TRIES = 3
DUMP_PAUSE = 1  # 앱이 애니메이션 중이면 uiautomator 가 한순간 XML 을 못 준다 — 곧 다시 읽는다


def _ui_dump(serial):
    """uiautomator dump 를 바이트로 받아 utf-8 로 읽은 글. 윈도 로케일(cp949)에 맡기면 한글에서 죽는다.
    `exec-out` 이어야 한다 — `shell` 은 파이프로 받으면 XML 없이 "UI hierchary dumped" 한 줄만 준다(실기기 확인).
    XML 이 아니면 [Blocked]: 빈 화면을 읽고 "없음" 으로 판정하면 안 온다 · 안 보인다 가설이 헛통과한다."""
    for attempt in range(DUMP_TRIES):
        dump = tools.adb_bytes(serial, 'exec-out', 'uiautomator', 'dump', '/dev/tty').decode('utf-8', 'replace')
        if '<hierarchy' in dump:
            return dump
        if attempt < DUMP_TRIES - 1:
            time.sleep(DUMP_PAUSE)
    raise Blocked(f'화면 덤프를 못 읽음(uiautomator) — XML 이 안 옴({DUMP_TRIES}번 시도)')


# ── 알림 읽기 · 누르기 ──────────────────────────────────────────────────────────────────────────

Notice = namedtuple('Notice', 'key title text channel')

POLL_SECONDS = 2
NOTICE_WAIT = 60  # 알림 기다리는 시간(시나리오 4-1 의 T). 제품 규칙이 아니라 진행 프로그램 기본값 — FCM 이 늦는 기기면 늘린다.
_WRAPPED = re.compile(r'^\w+ \((.*)\)$', re.S)  # 안드로이드 13+ 는 값을 `String (글)` 로 싼다


def _value(text):
    value = text.split('=', 1)[1].strip()
    wrapped = _WRAPPED.match(value)
    return wrapped.group(1) if wrapped else value


# 다음 칸의 시작 — `android.reduced.images=` 처럼 점이 든 키, 그리고 `androidx.…=` · `google.sent_time=` 처럼 android. 로 안 시작해도
# 점이 든 키 + `종류 (값)` 이거나 null 인 줄. 본문 줄의 `a=b` 는 종류 모양이 아니라 본문으로 남는다.
_NEXT_FIELD = re.compile(r'\s*(android\.[\w.]+=|[a-z][\w$]*(\.[\w$]+)+=(\w+ \(|null\s*$)|\}\s*$)')


def _field(lines, name):
    """`android.<name>=` 줄부터 다음 `android.xxx=` 줄(또는 닫는 `}`) 직전까지 — 본문에 줄바꿈이 있으면 여러 줄이다."""
    for i, line in enumerate(lines):
        if line.strip().startswith(f'android.{name}='):
            rest = []
            for follow in lines[i + 1:]:
                if re.match(_NEXT_FIELD, follow):
                    break
                rest.append(follow)
            return _value('\n'.join([line.strip(), *rest]).rstrip())
    return ''


def parse_notifications(dump):
    """dumpsys notification 에서 **우리 앱** 알림만 key · 제목 · 본문 · 채널로. 다른 앱 알림은 원문이 남의 것이라 읽지도 남기지도 않는다."""
    found = []
    for rec in (dump or '').split('NotificationRecord(')[1:]:
        if f'pkg={tools.PACKAGE} ' not in rec.splitlines()[0]:
            continue
        lines = rec.splitlines()
        key = re.search(r'key=(.+?): Notification\(', lines[0])
        channel = re.search(r'channel=(\S+)', lines[0])
        found.append(Notice(key.group(1) if key else '', _field(lines, 'title'), _field(lines, 'text'), channel.group(1) if channel else ''))
    return found


def read_notifications(serial):
    """지금 우리 앱 알림 목록. 목록 자체를 못 읽으면(권한 · 모양이 다른 기기) [Blocked] — 그러지 않으면 "안 온다" 가 헛통과한다.
    폰에는 USB 디버깅 알림 같은 남의 알림이 늘 있어서, 기록이 하나도 없으면 읽기가 깨진 것이다."""
    dump = tools.adb(serial, 'shell', 'dumpsys', 'notification', '--noredact', check=False)
    if 'NotificationRecord(' not in (dump or ''):
        raise Blocked('알림 목록을 못 읽음(dumpsys notification) — 권한 · 기기 형식 확인')
    return parse_notifications(dump)


def _fresh(now, before):
    seen = {n.key for n in before}
    return [n for n in now if n.key not in seen]


def wait_new(serial, before, count=1, seconds=NOTICE_WAIT, match=None):
    """[before] 에 없던 새 알림이 [count] 개 될 때까지(최대 [seconds] 초). 모자라도 그때까지 온 것을 돌려준다.
    [match] 가 있으면 개수 대신 "그 알림이 올 때까지" — 우리 앱 알림이 다른 것 하나 먼저 와도 기다리던 알림을 놓치지 않는다."""
    deadline = time.monotonic() + seconds
    while True:
        new = _fresh(read_notifications(serial), before)
        if (any(match(n) for n in new) if match else len(new) >= count) or time.monotonic() >= deadline:
            return new
        time.sleep(POLL_SECONDS)


def expect_none(serial, before, seconds=NOTICE_WAIT):
    """[seconds] 초 내내 지켜보고 새로 생긴 알림을 돌려준다(빈 목록이어야 "안 온다"). 중간에 와도 끝까지 본다 — 한 번 오고 사라지는 것도 잡는다."""
    deadline = time.monotonic() + seconds
    seen = {}
    while True:
        for n in _fresh(read_notifications(serial), before):
            seen.setdefault(n.key, n)
        if time.monotonic() >= deadline:
            return list(seen.values())
        time.sleep(POLL_SECONDS)


def tap_notification(serial, title):
    """알림창을 내려 [title] 글자의 알림을 누른다. 못 찾으면 [Blocked](알림이 안 온 것은 읽기 쪽 판정이다)."""
    tools.adb(serial, 'shell', 'cmd', 'statusbar', 'expand-notifications')
    try:
        time.sleep(1.5)
        dump = _ui_dump(serial)
        start, end = dump.find('<?xml'), dump.find('</hierarchy>')
        if start < 0 or end < 0:
            raise Blocked('화면 덤프를 못 읽음(uiautomator)')
        root = ET.fromstring(dump[start:end + len('</hierarchy>')])
        for node in root.iter('node'):
            if title in (node.get('text') or ''):
                left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
                tools.adb(serial, 'shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
                return
        raise Blocked(f'알림창에서 "{title}" 줄을 못 찾음')
    except Exception:
        tools.adb(serial, 'shell', 'cmd', 'statusbar', 'collapse', check=False)
        raise


# ── 앱 상태(앞 · 뒤 · 꺼짐) ─────────────────────────────────────────────────────────────────────

def background(serial):
    """앱을 뒤로(HOME 키)."""
    tools.adb(serial, 'shell', 'input', 'keyevent', 'KEYCODE_HOME')


def alive(serial):
    return bool(tools.adb(serial, 'shell', 'pidof', tools.PACKAGE, check=False).strip())


def kill_app(serial):
    """앱을 뒤로 내린 뒤 프로세스만 죽인다. `force-stop` 은 쓰지 않는다 — 안드로이드가 "멈춘 앱" 으로 표시해 FCM 이 아예 안 온다."""
    background(serial)
    time.sleep(1)
    for _ in range(5):
        tools.adb(serial, 'shell', 'am', 'kill', tools.PACKAGE, check=False)
        time.sleep(1)
        if not alive(serial):
            return
    pid = tools.adb(serial, 'shell', 'pidof', tools.PACKAGE, check=False).split()  # 디버그 빌드는 run-as 로 같은 프로세스를 죽일 수 있다
    if pid:
        tools.adb(serial, 'shell', 'run-as', tools.PACKAGE, 'kill', '-9', pid[0], check=False)
        time.sleep(1)
    if alive(serial):
        raise Blocked('앱 프로세스가 안 죽음(am kill · run-as kill)')


# ── 푸시 연결 ──────────────────────────────────────────────────────────────────────────────────

DELIVERY_WAIT = 30  # Wi-Fi 를 켠 뒤 GCM 이 다시 연결하기를 기다리는 초
_GCM = 'com.google.android.gms/.gcm.GcmService'
_DELIVERY_READY = set()  # 이 프로세스에서 이미 점검한 기기


def gcm_connects(serial):
    """GCM 서비스가 지금까지 연결한 횟수. 못 읽으면 None(기기마다 dumpsys 모양이 다르다)."""
    found = re.search(r'connects\W+(\d+)', tools.adb(serial, 'shell', 'dumpsys', 'activity', 'service', _GCM, check=False) or '')
    return int(found.group(1)) if found else None


def prepare_delivery(serial):
    """재부팅 뒤에는 푸시 연결이 죽어 FCM 이 200 인데도 폰에 안 뜬다 — Wi-Fi 를 껐다 켜 GCM 이 다시 연결하게 하고 연결 횟수가 늘었는지 읽는다.
    연결 횟수를 못 읽거나 Wi-Fi 가 꺼진 기기(껐다 켜면 새로 켜 버린다)는 건드리지 않고 [Blocked]. 안 늘어도 Wi-Fi 는 켜 둔다."""
    before = gcm_connects(serial)
    if before is None:
        raise Blocked('GCM 연결 횟수를 못 읽음(dumpsys activity service GcmService) — 푸시 연결을 점검할 수 없음')
    if tools.adb(serial, 'shell', 'settings', 'get', 'global', 'wifi_on', check=False).strip() != '1':
        raise Blocked('Wi-Fi 가 꺼져 있음 — 껐다 켜는 방법으로는 푸시 연결을 되살릴 수 없음')
    tools.adb(serial, 'shell', 'svc', 'wifi', 'disable')
    try:
        time.sleep(3)
        tools.adb(serial, 'shell', 'svc', 'wifi', 'enable')
        deadline = time.monotonic() + DELIVERY_WAIT
        while True:
            time.sleep(POLL_SECONDS)
            now = gcm_connects(serial)
            if now is not None and now > before:
                return
            if time.monotonic() >= deadline:
                raise Blocked(f'Wi-Fi 를 껐다 켠 뒤 {DELIVERY_WAIT}초 안에 GCM 연결 횟수가 안 늘었음({before} → {now}) — 푸시 연결 확인')
    except BaseException:
        tools.adb(serial, 'shell', 'svc', 'wifi', 'enable', check=False)  # 실패 · 시간 상한으로 끝나도 Wi-Fi 는 켜 둔다 — 이미 켜져 있으면 무해
        raise


def ensure_delivery(serial):
    """[prepare_delivery] 를 이 프로세스에서 기기당 한 번만 — 알림 가설이 시작할 때 부른다. 실패는 기억하지 않는다."""
    if serial not in _DELIVERY_READY:
        prepare_delivery(serial)
        _DELIVERY_READY.add(serial)


# ── 낮에만 ─────────────────────────────────────────────────────────────────────────────────────

SEOUL = timezone(timedelta(hours=9))


def require_daytime(now=None):
    """알림 시험은 서울 08~22시에만 — 밤에는 방해 금지 시간 때문에 결과가 달라지고, 밤 보관 알림이 실제 아침 배치에 섞인다."""
    now = (now or datetime.now(SEOUL)).astimezone(SEOUL)
    if not 8 <= now.hour < 22:
        raise Blocked(f'서울 시각 {now:%H:%M} — 알림 시험은 08:00~21:59 에만')
