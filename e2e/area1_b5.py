"""영역 1 묶음 5 — 재부팅 · 식은 서버.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b5.dart 의 같은 번호.

학생증 검토 이후 가설(대기 · 통과 · 반려 알림 · 탈퇴 때 학생증 파일 — E-GATE-33 · 39~43 · 46 · 49)은 학생증 제거(10-17)로
서버 제출 경로(POST /student-verification) · 앱 3b 화면과 함께 뺐다.
`python -m e2e run area1-b5` 한 번으로 돈다. E-AUTH-14 는 서버를 16분 쉬게 하므로 묶음 맨 끝이다.
"""

import re
import time

from e2e import area1, tools
from e2e.area1 import Check, _app, _otp, _signed_in, _signed_up
from e2e.area1_b3 import _allow_notifications
from e2e.tools import Blocked

COLD_REST = 16 * 60  # 서버를 안 건드리는 시간(초) — 인스턴스가 0 이 되려면 15분 넘게 쉬어야 한다
DOWN_TRIES = 30  # 재부팅 명령 뒤 기기가 내려가기를 1초 간격으로 기다리는 횟수
BOOT_TRIES = 90  # 올라와서 부팅이 끝나기를 2초 간격으로 기다리는 횟수(3분)
LOCKED = re.compile(r'(?:mKeyguardShowing|isKeyguardShowing|mShowingLockscreen)=true')
# 기본 가설 상한(tools.CASE_LIMIT 420초)보다 오래 걸리는 폰 가설 — 최악의 경우를 더해 준다.
# E-AUTH-18: 내려감 30 + 부팅 180 + 잠금 3 + 앱 60 + 로그인 30 = 약 300초 이상.
CASE_LIMIT_SLOW = 900

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-AUTH-15': '실제 Gmail 6자리 코드 · 5분 만료 — 대장이 Gmail 커넥터로',
    'E-ONB-09': '사람 필요(12/31 밤) — 서버가 시계를 직접 읽어(datetime.now(SEOUL)) 옮길 자리가 없다',
    'E-ONB-42': '사람 필요 — OpenAI 장애는 운영에서 못 낸다(E-ONB-38 의 깨진 파일 방식으로 대신 확인)',
    'E-ONB-05': '두 기기 — 묶음 6(area1-b6)',
    'E-ONB-74': 'B에뮬 — 묶음 6(area1-b6)',
}


# ── API ─────────────────────────────────────────────────────────────────────────────────────────


def auth_14(run):
    """서버를 16분 쉬게 한 뒤 첫 가입 요청의 시간을 잰다. 인스턴스가 정말 0 이었는지는 콘솔(Cloud Run)로만 안다 — 대장이 본다."""
    check = Check()
    n, email = run.alias()
    time.sleep(COLD_REST)
    started = time.monotonic()
    reply = _otp(run, email)
    took = time.monotonic() - started
    check.reply('식은 서버 첫 가입 요청', reply, 200)
    _signed_up(run, n, email, check)
    # 판정은 "가입 성공(훅 시간 초과 오류 0건)" — 훅이 5초를 넘기면 Supabase 가 오류를 내 위 200 이 깨진다.
    # 잰 시간은 메일 발송까지 든 요청 전체라 5초로 자르면 훅이 빨라도 틀리게 fail 이 난다. 메모로만 남긴다.
    return check.result(f'가입 요청 {took:.1f}초(서버를 {COLD_REST // 60}분 쉬게 함 — 인스턴스 0 은 콘솔로 확인)')


# ── 폰 A ────────────────────────────────────────────────────────────────────────────────────────


def _until(done, tries, pause):
    for _ in range(tries):
        if done():
            return True
        time.sleep(pause)
    return False


def _locked(serial):
    return bool(LOCKED.search(tools.adb(serial, 'shell', 'dumpsys', 'window', check=False) or ''))


def _reboot(phone):
    """폰을 다시 켜고 앱이 다시 쓸 수 있을 때까지 — 내려가는 걸 먼저 보지 않으면 옛 부팅의 boot_completed=1 을 새 부팅으로 읽는다.
    재부팅하면 adb reverse 가 사라지므로 앱 우편함을 다시 이어 준다. PIN · 패턴 잠금이 걸린 폰은 사람이 풀어야 해서 blocked."""
    serial = phone.serial
    tools.adb(serial, 'reboot', check=False)
    if not _until(lambda: not tools.adb(serial, 'shell', 'getprop', 'sys.boot_completed', check=False).strip(), DOWN_TRIES, 1):
        raise Blocked('재부팅 명령 뒤에도 기기가 내려가지 않음')
    if not _until(lambda: tools.adb(serial, 'shell', 'getprop', 'sys.boot_completed', check=False).strip() == '1', BOOT_TRIES, 2):
        raise Blocked(f'{BOOT_TRIES * 2}초 안에 부팅이 안 끝남')
    tools.adb(serial, 'shell', 'wm', 'dismiss-keyguard', check=False)  # 모양 없는(밀기) 잠금만 풀린다
    time.sleep(3)
    if _locked(serial):
        raise Blocked('재부팅 뒤 잠금 화면(PIN · 패턴)이 남음 — 사람이 풀어야 함. 이 가설은 잠금 없는 폰에서만 돈다')
    tools.adb(serial, 'reverse', f'tcp:{tools.DEVICE_PORT}', f'tcp:{phone.hub.port}')


def p_auth_18(run, phone):
    check = Check()
    _allow_notifications(phone)
    _, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token, phase='login', expect='home'), '로그인')
    if check.problems:
        return check.result()  # 로그인부터 틀렸으면 재부팅해도 소용없다
    _reboot(phone)
    _app(check, phone(fresh=False, phase='rebooted', expect='home', limit=60), '재부팅 뒤')
    return check.result()

tools.CASE_LIMITS.update({'E-AUTH-18': CASE_LIMIT_SLOW})


CASES = {'E-AUTH-14': auth_14}
PHONE = {'E-AUTH-18': p_auth_18}

area1.CASES.update(CASES)
area1.PHONE.update(PHONE)
area1.BUNDLES['area1-b5'] = list(PHONE) + ['E-AUTH-14']
