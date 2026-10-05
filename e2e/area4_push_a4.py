"""영역 4 알림(PUSH) A4 — 토큰 · 권한 · 로그인/로그아웃 11개(55 · 58~63 · 66~69). 폰 A 한 대 + API.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area4_push_a4.dart 의 같은 번호.
분류표는 바탕화면 E2E_결과/영역갱신/push_분류표.md 의 A4.

`python -m e2e run area4-push-a4` 한 번으로 돈다. 서울 08~22시에만 돈다(알림이 가는 가설은 밤에 방해 금지 시간이라 결과가 달라진다).
"알림 하나 보내기" 는 시나리오 4-2 가 정한 대로 "받은 수락" 알림이다 — 새 계정이 받는 사람에게 카드를 만들어 수락한다(e2e/notify_factory.py).

권한 가설(59 · 60 · 62)은 앱 데이터를 지워(`pm clear`) 새로 설치한 상태를 만들고, 첫 권한 창을 uiautomator 로 "허용 안 함" 누른다.
이미 권한을 정한 폰이라 창이 안 뜨면 blocked 로 알린다 — 앱을 지웠다 다시 설치해야 한다. 첫 실행에서 되는지 먼저 보라고 분류표가 적어 둔 자리다.

알려진 한계: E-PUSH-59 는 알림이 한 번도 안 오는 가설이라 "읽기가 깨져서 0개" 와 구별이 안 된다 — 같은 묶음의 E-PUSH-60 · 61 이 오는 알림을 읽어 파서가 살아 있음을 보인다.
"""

import contextlib
import re
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

from e2e import area1, area4, notify, notify_factory, tools
from e2e.area1 import Check, _api, _app, _one, _patch, _rows, _signed_in
from e2e.area4 import stepper
from e2e.tools import Blocked

TITLE = '나를 수락한 사람이 있어요'  # backend/app/cards/router.py 의 받은 수락 알림 제목 — 본문은 "{닉네임} 님이 대화를 하고 싶어 해요"
TOKEN_WAIT = 30  # 로그인 뒤 기기 토큰이 서버에 올라오기를 기다리는 시간(초) — 시나리오 E-PUSH-58 의 30초
GONE_WAIT = 10  # 로그아웃 · 거부 뒤 토큰 행이 (안) 생기기를 지켜보는 시간(초)
MARKETING_WAIT = 10  # 스위치를 누른 뒤 서버 저장이 끝나기를 기다리는 시간(초)
DIALOG_WAIT = 20  # 로그인 뒤 권한 창이 뜨기를 기다리는 시간(초)
SETTINGS_WAIT = 10  # 설정 앱이 맨 앞에 오기를 기다리는 시간(초)
DISCARD_WAIT = 75  # 망을 켠 뒤 앱이 기기 토큰 버리기를 다시 하기를 기다리는 시간(초) — 재시도 간격 1분(push_registrar.dart `_retryDelay`) + 여유
SETTINGS_PACKAGE = 'com.android.settings'
PERMISSION = 'android.permission.POST_NOTIFICATIONS'
DENY_TEXTS = ('허용 안 함', '허용 안함', "Don't allow", 'Don’t allow')
CASE_LIMIT_PUSH = 900  # 가설 하나 상한(tools.CASE_LIMIT 420초)보다 오래 걸린다 — 알림 60초 기다림이 한두 번에서 세 번 든다

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-PUSH-56': '막힘 — FCM 직접 발송 권한이 없다(분류표: blocked 로 남김)',
    'E-PUSH-57': '막힘 — FCM 직접 발송 권한이 없다(분류표: blocked 로 남김)',
    'E-PUSH-64': '기기 둘 — 같은 계정 두 기기에 알림(B에뮬이 필요, 분류표 B)',
    'E-PUSH-65': '기기 둘 — 한 기기가 로그아웃해도 다른 기기는 받음(B에뮬이 필요, 분류표 B)',
    'E-PUSH-71': '기기 둘 — 탈퇴하면 토큰 전부 삭제 · 다른 기기 로그아웃(B에뮬이 필요, 분류표 B)',
}


# ── 서버 · 알림 ──────────────────────────────────────────────────────────────────────────────────


def _tokens(run, account_id):
    return _rows(run, f'push_tokens?profile_id=eq.{account_id}&select=token,platform')


def _wait(until, seconds):
    deadline = time.monotonic() + seconds
    while True:
        if until():
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(2)


def _send_one(run, receiver):
    """"알림 하나 보내기" — 새 계정이 [receiver] 에게 카드를 만들어 수락한다 → 보낸 사람 닉네임(알림 본문에 든다)."""
    sender = run.account('home')
    nickname = _one(run, f"profiles?id=eq.{sender['id']}&select=nickname").get('nickname')
    if not nickname:
        raise Blocked('보낸 계정의 닉네임을 못 읽음')
    notify_factory.accept_card(run, sender, notify_factory.card(run, sender, receiver))
    return nickname


def _is(nickname):
    return lambda notice: notice.title == TITLE and nickname in notice.text


def _arrived(serial, before, nickname):
    """[nickname] 이 보낸 알림이 올 때까지(최대 T) — 온 것만."""
    got = notify.wait_new(serial, before, seconds=notify.NOTICE_WAIT, match=_is(nickname))
    return [n for n in got if _is(nickname)(n)]


def _quiet(serial, before):
    """T 동안 우리 앱 알림이 새로 생기는지 — 생긴 것을 돌려준다(빈 목록이어야 "안 온다")."""
    return notify.expect_none(serial, before, seconds=notify.NOTICE_WAIT)


def _need_token(run, account, why):
    """토큰이 안 올라오면 이 가설은 판정할 수 없다 → blocked."""
    if not _wait(lambda: _tokens(run, account['id']), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — {why}(알림 권한 · FCM 확인)')


def _seconds_from_now(text):
    if not text:
        return None
    return abs((datetime.fromisoformat(text) - datetime.now(timezone.utc)).total_seconds())


# ── 기기: 권한 · 창 · 앞으로 ───────────────────────────────────────────────────────────────────────


def _granted(serial):
    """이 앱의 알림 권한이 허용인지 — 읽지 못하면(안드로이드 12 이하 · 형식이 다름) None."""
    dump = tools.adb(serial, 'shell', 'dumpsys', 'package', tools.PACKAGE, check=False) or ''
    found = re.search(r'android\.permission\.POST_NOTIFICATIONS: granted=(true|false)', dump)
    return None if not found else found.group(1) == 'true'


def _forget_permission(serial):
    """새로 설치한 것과 같게 — 앱 데이터를 지우면 알림 권한도 "아직 안 물어봄" 으로 돌아간다. 안 돌아가면 blocked."""
    tools.adb(serial, 'shell', 'pm', 'clear', tools.PACKAGE)
    state = _granted(serial)
    if state is None:
        raise Blocked('알림 권한 상태를 못 읽음 — 안드로이드 13 이상에서만 도는 가설')
    if state:
        raise Blocked('앱 데이터를 지웠는데도 알림 권한이 허용으로 남음 — 새로 설치한 상태를 못 만듦(앱을 지웠다 다시 설치해야 함)')


def _tap_node(serial, matches):
    """uiautomator 화면 덤프에서 [matches] 에 맞는 첫 노드의 가운데를 누른다 → 눌렀는지."""
    dump = notify._ui_dump(serial)
    start, end = dump.find('<?xml'), dump.find('</hierarchy>')
    if start < 0 or end < 0:
        return False
    for node in ET.fromstring(dump[start:end + len('</hierarchy>')]).iter('node'):
        if matches(node):
            left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
            tools.adb(serial, 'shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
            return True
    return False


def _is_deny(node):
    return (node.get('resource-id') or '').endswith('permission_deny_button') or (node.get('text') or '').strip() in DENY_TEXTS


def _deny_dialog(serial):
    """로그인 뒤 뜨는 첫 알림 권한 창에서 "허용 안 함" 을 누른다. 창이 안 뜨면 이미 권한을 정한 폰이다 → blocked."""
    deadline = time.monotonic() + DIALOG_WAIT
    while not _tap_node(serial, _is_deny):
        if time.monotonic() >= deadline:
            raise Blocked(f'{DIALOG_WAIT}초 안에 알림 권한 창이 안 뜸 — 이미 권한을 정한 폰이다(첫 실행이 아님). 앱을 지웠다 다시 설치해야 한다')
        time.sleep(1)


def _front(serial):
    """앱을 다시 앞으로(이미 떠 있으면 그대로 이어진다) — 알림을 읽으려 HOME 으로 내렸거나 설정 앱에 다녀온 뒤."""
    tools.adb(serial, 'shell', 'monkey', '-p', tools.PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')


# ── E-PUSH-55 · 58 ───────────────────────────────────────────────────────────────────────────────


def p_push_55(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')

    def row():
        return area4._settings(run, account['id'])

    def turned_on(said):
        _wait(lambda: row().get('marketing') is True, MARKETING_WAIT)
        got = row()
        check.that(got.get('marketing') is True, f"켠 뒤 marketing {got.get('marketing')!r} — true 이어야 함")
        gap = _seconds_from_now(got.get('marketing_consented_at'))
        check.that(gap is not None and gap <= 60, f"동의 시각 {got.get('marketing_consented_at')!r} — 누른 시각 ±60초 안이어야 함")

    def turned_off(said):
        _wait(lambda: row().get('marketing') is False, MARKETING_WAIT)
        got = row()
        check.that(got.get('marketing') is False and got.get('marketing_consented_at') is None,
                   f"끈 뒤 marketing {got.get('marketing')!r} · 동의 시각 {got.get('marketing_consented_at')!r} — false · null 이어야 함")

    notify.grant_notifications(phone.serial)  # 앞 묶음이 끝에서 권한을 거두면 권한 창이 16d 를 가린다
    try:
        _app(check, phone(midway=stepper(phone, turned_on, turned_off), token_hash=token))
    finally:
        notify.revoke_notifications(phone.serial)
    return check.result()


def p_push_58(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    notify.grant_notifications(phone.serial)
    try:
        _app(check, phone(midway=lambda said: _wait(lambda: _tokens(run, account['id']), TOKEN_WAIT), token_hash=token))
    finally:
        notify.revoke_notifications(phone.serial)
    rows = _tokens(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['platform'] == 'android', f'{TOKEN_WAIT}초 뒤 push_tokens {rows} — platform=android 1행이어야 함')
    return check.result()


# ── 첫 실행 거부 — E-PUSH-59 · 60 · 62 ────────────────────────────────────────────────────────────


def _first_run_denied(run, phone, check, token):
    """새로 설치한 상태로 만들고, 로그인한 앱이 멈춘 사이 첫 권한 창을 거부한다 — 앱은 그대로 홈까지 간다."""
    _forget_permission(phone.serial)
    _app(check, phone(midway=lambda said: _deny_dialog(phone.serial), token_hash=token, phase='deny'), '권한 거부')


def p_push_59(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    try:
        _first_run_denied(run, phone, check, token)
        registered = _wait(lambda: _tokens(run, account['id']), GONE_WAIT)
        check.that(not registered, f'권한을 거부했는데 push_tokens {_tokens(run, account["id"])}')
        check.that(_granted(phone.serial) is False, '거부한 뒤 알림 권한이 허용으로 바뀜')
        before = notify.read_notifications(phone.serial)
        _send_one(run, account)
        got = _quiet(phone.serial, before)
        check.that(not got, f'권한을 거부했는데 알림 {len(got)}개가 옴')
    finally:
        notify.revoke_notifications(phone.serial)
    return check.result()


def p_push_60(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    try:
        _first_run_denied(run, phone, check, token)
        check.that(not _tokens(run, account['id']), '거부한 상태인데 이미 push_tokens 행이 있음')
        notify.grant_notifications(phone.serial)
        _app(check, phone(fresh=False, expect='home', phase='again', limit=30), '권한을 켜고 다시 켬')
        _wait(lambda: _tokens(run, account['id']), TOKEN_WAIT)
        rows = _tokens(run, account['id'])
        check.that(len(rows) == 1, f'권한을 켜고 다시 켠 뒤 {TOKEN_WAIT}초 안 push_tokens {rows} — 1행이어야 함')
        notify.background(phone.serial)
        before = notify.read_notifications(phone.serial)
        nickname = _send_one(run, account)
        check.that(_arrived(phone.serial, before, nickname), f'권한을 켠 뒤 {notify.NOTICE_WAIT}초 안에 알림이 안 옴')
    finally:
        notify.revoke_notifications(phone.serial)
    return check.result()


def p_push_62(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')

    def settings_opened(said):
        top = []

        def settings_in_front():
            top[:] = [phone.top()]
            return SETTINGS_PACKAGE in top[0]

        front = _wait(settings_in_front, SETTINGS_WAIT)
        check.that(front, f'"기기 알림 설정 열기" 를 눌렀는데 {SETTINGS_WAIT}초 안에 설정 앱이 맨 앞에 안 옴: {top[0] if top else ""}')
        notify.grant_notifications(phone.serial)  # 사람이 설정 앱에서 알림을 켠 것과 같다
        _front(phone.serial)

    _forget_permission(phone.serial)
    try:
        _app(check, phone(midway=stepper(phone, lambda said: _deny_dialog(phone.serial), settings_opened), token_hash=token, phase='deny'))
    finally:
        notify.revoke_notifications(phone.serial)
    return check.result('설정 앱의 어느 화면이 열리는지(앱 정보 화면이어야 함)는 사람이 본다')


# ── 권한을 켜고 끄기 — E-PUSH-61 ──────────────────────────────────────────────────────────────────


def p_push_61(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    serial = phone.serial
    notify.grant_notifications(serial)
    try:
        _app(check, phone(token_hash=token), '로그인')
        _need_token(run, account, '끄고 켜기 전에 등록이 안 됨')
        notify.background(serial)
        notify.revoke_notifications(serial)  # 앱 프로세스도 같이 죽는다 — 서버는 그대로 보낸다
        before = notify.read_notifications(serial)
        _send_one(run, account)
        got = _quiet(serial, before)
        check.that(not got, f'권한을 끈 동안 알림 {len(got)}개가 옴')
        check.that(len(_tokens(run, account['id'])) == 1, '권한을 끈 뒤 토큰 행이 1개가 아님')
        notify.grant_notifications(serial)
        before = notify.read_notifications(serial)
        nickname = _send_one(run, account)
        check.that(_arrived(serial, before, nickname), f'권한을 다시 켠 뒤 {notify.NOTICE_WAIT}초 안에 알림이 안 옴')
    finally:
        notify.revoke_notifications(serial)
    return check.result()


# ── 게이트 앞 · 로그아웃 · 계정 바꾸기 — E-PUSH-63 · 66 · 67 · 68 · 69 ────────────────────────────────


def p_push_63(run, phone):
    check = Check()
    account, token = _signed_in(run, 'pending')
    seen = {}

    def before_gate(said):
        _wait(lambda: _tokens(run, account['id']), TOKEN_WAIT)
        seen['rows'] = _tokens(run, account['id'])
        check.that(len(seen['rows']) == 1, f'인증 전(3b)인데 {TOKEN_WAIT}초 안 push_tokens {seen["rows"]} — 1행이어야 함')
        _patch(run, f"profiles?id=eq.{account['id']}", {'student_verification': 'verified'})  # 사람 검토가 끝난 것과 같다

    def after_gate(said):
        rows = _tokens(run, account['id'])
        check.that(rows == seen['rows'] and len(rows) == 1, f'게이트가 열린 뒤 push_tokens {rows}(앞 {seen["rows"]}) — 같은 토큰 1행 그대로여야 함')

    notify.grant_notifications(phone.serial)
    try:
        _app(check, phone(midway=stepper(phone, before_gate, after_gate), token_hash=token))
    finally:
        notify.revoke_notifications(phone.serial)
    return check.result()


def p_push_66(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    serial = phone.serial

    def logged_in(said):
        _need_token(run, account, '로그아웃 전에 등록이 안 됨')
        notify.background(serial)
        before = notify.read_notifications(serial)
        nickname = _send_one(run, account)
        # 로그인 중에 알림이 오는 것을 먼저 봐야 로그아웃 뒤의 "0개" 가 읽기가 깨진 탓이 아님을 안다.
        if not _arrived(serial, before, nickname):
            raise Blocked('로그인 중인데도 알림이 안 옴 — 로그아웃 뒤 0개가 아무것도 증명하지 못한다(알림 권한 · FCM 확인)')
        _front(serial)

    notify.grant_notifications(serial)
    try:
        _app(check, phone(midway=logged_in, token_hash=token))
        _wait(lambda: not _tokens(run, account['id']), GONE_WAIT)
        check.that(not _tokens(run, account['id']), '로그아웃했는데 push_tokens 행이 남음')
        before = notify.read_notifications(serial)
        _send_one(run, account)
        got = _quiet(serial, before)
        check.that(not got, f'로그아웃한 폰에 옛 계정 알림 {len(got)}개가 옴')
    finally:
        notify.revoke_notifications(serial)
    return check.result()


def p_push_67(run, phone):
    notify.require_daytime()
    check = Check()
    first, token = _signed_in(run, 'home')
    second = run.account('home')
    serial = phone.serial
    seen = {}

    def first_ready(said):
        _need_token(run, first, '계정을 바꾸기 전에 등록이 안 됨')
        seen['token'] = _tokens(run, first['id'])[0]['token']

    def second_ready(said):
        _wait(lambda: _tokens(run, second['id']), TOKEN_WAIT)
        mine, old = _tokens(run, second['id']), _tokens(run, first['id'])
        check.that(len(mine) == 1 and mine[0]['token'] == seen['token'], f'새 계정 push_tokens {mine} — 같은 토큰 1행이어야 함')
        check.that(not old, f'앞 계정 push_tokens {old} — 0행이어야 함(토큰 주인이 바뀜)')
        notify.background(serial)
        before = notify.read_notifications(serial)
        to_first, to_second = _send_one(run, first), _send_one(run, second)
        check.that(_arrived(serial, before, to_second), f'새 계정에게 보낸 알림이 {notify.NOTICE_WAIT}초 안에 안 옴')
        extra = _quiet_for(serial, before, 10)
        check.that(not [n for n in extra if _is(to_first)(n)], '앞 계정에게 보낸 알림이 같은 폰에 뜸')

    notify.grant_notifications(serial)
    try:
        _app(check, phone(midway=stepper(phone, first_ready, second_ready), token_hash=token, second=run.link(second['email'])))
    finally:
        notify.revoke_notifications(serial)
    return check.result()


def _quiet_for(serial, before, seconds):
    """[seconds] 초 더 지켜본 새 알림 전부(이미 온 것 포함)."""
    return notify.expect_none(serial, before, seconds=seconds)


def p_push_68(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    serial = phone.serial

    def logged_in(said):
        _need_token(run, account, '비행기 모드로 로그아웃하기 전에 등록이 안 됨')
        notify.background(serial)
        before = notify.read_notifications(serial)
        nickname = _send_one(run, account)
        if not _arrived(serial, before, nickname):
            raise Blocked('로그인 중인데도 알림이 안 옴 — 로그아웃 뒤 0개가 아무것도 증명하지 못한다(알림 권한 · FCM 확인)')
        _front(serial)
        notify.airplane(serial, True)

    def logged_out(said):
        rows = _tokens(run, account['id'])
        check.that(len(rows) == 1, f'망이 없는 사이 로그아웃했는데 서버 push_tokens {len(rows)}개 — 처음엔 1개가 남아야 함')
        notify.airplane(serial, False)
        time.sleep(DISCARD_WAIT)  # 앱을 끄지 않은 채 기기 토큰 버리기 재시도(1분)가 끝나기를
        before = notify.read_notifications(serial)
        _send_one(run, account)
        got = _quiet(serial, before)
        check.that(not got, f'망을 켠 뒤 로그아웃한 폰에 옛 계정 알림 {len(got)}개가 옴 — 결함(⚠ 목록 7 풀림의 회귀)')

    notify.grant_notifications(serial)
    try:
        _app(check, phone(midway=stepper(phone, logged_in, logged_out), token_hash=token, phase='offline'))
    finally:
        notify.ensure_online(serial)
        notify.revoke_notifications(serial)
    left = _tokens(run, account['id'])
    return check.result(f'서버 push_tokens {len(left)}개 남음(죽은 토큰에 FCM 이 404 를 주면 지워진다 — 운영 첫 실측)')


def p_push_69(run, phone):
    notify.require_daytime()
    check = Check()
    account, token = _signed_in(run, 'home')
    serial = phone.serial
    fake = f"e2e-fake-{account['n']}"
    notify.grant_notifications(serial)
    try:
        _app(check, phone(token_hash=token), '로그인')
        _need_token(run, account, '가짜 토큰을 넣기 전에 등록이 안 됨')
        reply = _api(run, 'POST', '/cards/push-tokens', account['token'], {'token': fake, 'platform': 'android'})
        if reply[0] != 200:
            raise Blocked(f'가짜 토큰 넣기 {reply[0]} {area1._detail(reply[1])}')
        notify.background(serial)
        before = notify.read_notifications(serial)
        nickname = _send_one(run, account)
        check.that(_arrived(serial, before, nickname), f'가짜 토큰이 섞여 있어 진짜 기기에 알림이 {notify.NOTICE_WAIT}초 안에 안 옴')
        kept = [row['token'] for row in _tokens(run, account['id'])]
        check.that(fake in kept, '가짜 토큰 행이 지워짐 — 400 이라 남아야 한다(404 면 지워진다)')
    finally:
        with contextlib.suppress(Exception):  # 판정과 상관없다 — 못 지워도 뒷정리가 계정째 지운다
            _api(run, 'DELETE', f'/cards/push-tokens/{fake}', account['token'])
        notify.revoke_notifications(serial)
    return check.result()


PHONE = {'E-PUSH-55': p_push_55, 'E-PUSH-58': p_push_58, 'E-PUSH-59': p_push_59, 'E-PUSH-60': p_push_60, 'E-PUSH-61': p_push_61,
         'E-PUSH-62': p_push_62, 'E-PUSH-63': p_push_63, 'E-PUSH-66': p_push_66, 'E-PUSH-67': p_push_67, 'E-PUSH-68': p_push_68,
         'E-PUSH-69': p_push_69}

tools.CASE_LIMITS.update({case: CASE_LIMIT_PUSH for case in ('E-PUSH-59', 'E-PUSH-60', 'E-PUSH-61', 'E-PUSH-66', 'E-PUSH-67', 'E-PUSH-68')})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-a4'] = list(PHONE)
