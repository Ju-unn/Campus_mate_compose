"""영역 1 묶음 5 — 학생증 검토 이후(대기 · 통과 · 탈퇴) · 재부팅 · 식은 서버.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b5.dart 의 같은 번호.

대기(pending) 계정은 앱 대신 API 로 학생증을 한 번 낸다(Vision 1회) — 파일이 student-id-temp 에 실제로 올라가야 E-GATE-42 · 49 가 의미 있다.
사람 검토(대시보드)는 SUPABASE §7 순서(attempts 먼저 → profiles)를 이 계정 것만 흉내 낸다.
`python -m e2e run area1-b5` 한 번으로 돈다. E-AUTH-14 는 서버를 16분 쉬게 하므로 묶음 맨 끝이다.
"""

import re
import time
from datetime import datetime, timezone

from e2e import area1, area1_b2, area1_b3, notify, tools
from e2e.area1 import TINY_JPEG, Check, _app, _form, _otp, _patch, _rows, _signed_in, _signed_up
from e2e.area1_b3 import REAL_NAME, _allow_notifications, _attempts, _files, _photos, _profile_state
from e2e.tools import Blocked

# 서버 문구(backend/app/core/errors.py)
REAL_NAME_REQUIRED = '실명을 입력해 주세요'
REAL_NAME_INVALID = '이름은 한글이나 영문으로만 적어 주세요'
IN_REVIEW = '이미 검토 중이에요, 결과를 기다려 주세요'
ALREADY_DONE = '이미 인증이 완료됐어요'

# 사람 검토가 끝났을 때 오는 알림(backend/app/student_verification/review_hook.py) — 제목 · 본문 그대로
APPROVED = ('학생 인증이 끝났어요', '학과 정보를 입력하고 시작해 보세요')
REJECTED = ('학생 인증을 다시 해 주세요', '서류를 확인하지 못했어요. 앱에서 이유를 확인해 주세요')

PHOTO = 'id_name.jpg'  # 이름이 달라 사람 검토로 넘어가는 학생증(E-GATE-37 과 같다)
COLD_REST = 16 * 60  # 서버를 안 건드리는 시간(초) — 인스턴스가 0 이 되려면 15분 넘게 쉬어야 한다
DOWN_TRIES = 30  # 재부팅 명령 뒤 기기가 내려가기를 1초 간격으로 기다리는 횟수
BOOT_TRIES = 90  # 올라와서 부팅이 끝나기를 2초 간격으로 기다리는 횟수(3분)
TOKEN_TRIES = 15  # 기기 알림 토큰이 서버에 올라오기를 2초 간격으로 기다리는 횟수
NOTICE_SECONDS = 60  # 시나리오 E-GATE-43 의 기다리기 60초
LOCKED = re.compile(r'(?:mKeyguardShowing|isKeyguardShowing|mShowingLockscreen)=true')
# 기본 가설 상한(tools.CASE_LIMIT 420초)보다 오래 걸리는 폰 가설 — 최악의 경우를 더해 준다.
# E-GATE-43: 계정 둘 × (제출 · 앱 켜기 · 토큰 대기 30 + 알림 60 + 반영 35) = 약 400초 이상. E-AUTH-18: 내려감 30 + 부팅 180 + 잠금 3 + 앱 60 + 로그인 30 = 약 300초 이상.
CASE_LIMIT_SLOW = 900

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-AUTH-15': '실제 Gmail 6자리 코드 · 5분 만료 — 대장이 Gmail 커넥터로',
    'E-GATE-48': '사람 필요(Vision 고장은 운영에서 못 낸다) — 서버 단위 시험 backend/tests/student_verification/test_router.py(vision_error)로 대신',
    'E-ONB-09': '사람 필요(12/31 밤) — 서버가 시계를 직접 읽어(datetime.now(SEOUL)) 옮길 자리가 없다',
    'E-ONB-42': '사람 필요 — OpenAI 장애는 운영에서 못 낸다(E-ONB-38 의 깨진 파일 방식으로 대신 확인)',
    'E-ONB-05': '두 기기 — 묶음 6(area1-b6)',
    'E-ONB-74': 'B에뮬 — 묶음 6(area1-b6)',
}


# ── 공용 준비 ───────────────────────────────────────────────────────────────────────────────────


def _submitted(run):
    """동의까지 끝낸 새 계정이 [PHOTO] 로 학생증을 낸다 → 사람 검토 대기(pending) 계정. 앱이 낸 것과 같은 요청이다.
    Vision 을 부르므로 다시 보내지 않는다(retry=False) — 두 번째는 409 라 어차피 헛수고다."""
    path = _photos(run, PHOTO)[0]  # 계정을 만들기 전에 파일부터
    account = run.account('consented')
    reply = _form(run, '/student-verification', account['token'], {'real_name': REAL_NAME},
                  ('photo', PHOTO, path.read_bytes()), retry=False)
    if reply[0] >= 300:
        raise Blocked(f'학생증 제출 {reply[0]} {area1._detail(reply[1])}')
    state = _profile_state(run, account['id'])
    if state != 'pending':
        raise Blocked(f'{PHOTO} 가 사람 검토로 안 넘어감(profiles.student_verification={state}) — 사진 세트 확인')
    return account


def _approve(run, account_id):
    """대시보드에서 사람이 통과시키는 순서(docs/SUPABASE.md §7) — attempts 먼저, profiles 나중. 이 계정 것만."""
    _patch(run, f'student_verification_attempts?profile_id=eq.{account_id}&result=eq.pending',
           {'result': 'verified', 'reviewed_at': datetime.now(timezone.utc).isoformat()})
    _patch(run, f'profiles?id=eq.{account_id}', {'student_verification': 'verified'})


def _resubmit(run, account):
    return _form(run, '/student-verification', account['token'], {'real_name': REAL_NAME}, ('photo', 'id.jpg', TINY_JPEG),
                 retry=False)


# ── API ─────────────────────────────────────────────────────────────────────────────────────────


def gate_33(run):
    check = Check()
    account = run.account('consented')
    for label, name, detail in (('앞뒤 공백', ' 김 ', REAL_NAME_REQUIRED), ('자모 섞임', '김ㄱ', REAL_NAME_INVALID)):
        reply = _form(run, '/student-verification', account['token'], {'real_name': name}, ('photo', 'id.jpg', TINY_JPEG),
                      retry=False)
        check.reply(label, reply, 400, detail)
    files = _files(run, 'student-id-temp', account['id'])
    check.that(not files, f'student-id-temp 파일 {len(files)}개')
    rows = _attempts(run, account['id'])
    check.that(not rows, f'attempts {len(rows)}행')
    return check.result()


def gate_40(run):
    check = Check()
    account = _submitted(run)
    before = _attempts(run, account['id'])
    check.reply('검토 중 다시 제출', _resubmit(run, account), 409, IN_REVIEW)
    after = _attempts(run, account['id'])
    check.that(len(before) == 1 and after == before, f'attempts {before} → {after} — 1행 그대로여야 함')
    return check.result()


def gate_42(run):
    check = Check()
    account = _submitted(run)
    if not _files(run, 'student-id-temp', account['id']):
        raise Blocked('제출했는데 student-id-temp 에 파일이 없음 — 통과 뒤에 남는지 볼 수 없다')
    _approve(run, account['id'])
    files = _files(run, 'student-id-temp', account['id'])
    check.that(len(files) == 1, f'student-id-temp 파일 {len(files)}개 — 통과해도 1개가 그대로 남아야 함')
    return check.result('학생증 파일 1개가 남음 — 사람이 직접 지워야 한다(docs/SUPABASE.md §7-3)')


def gate_46(run):
    check = Check()
    account = run.account('verified')
    check.reply('통과 뒤 다시 제출', _resubmit(run, account), 409, ALREADY_DONE)
    files = _files(run, 'student-id-temp', account['id'])
    check.that(not files, f'student-id-temp 파일 {len(files)}개 — 올라가면 안 됨')
    return check.result()


def gate_49(run):
    check = Check()
    account = _submitted(run)
    if not _files(run, 'student-id-temp', account['id']):
        raise Blocked('제출했는데 student-id-temp 에 파일이 없음 — 탈퇴로 지워지는지 볼 수 없다')
    area1_b2._withdraw(run, account)
    files = _files(run, 'student-id-temp', account['id'])
    check.that(not files, f'student-id-temp 파일 {len(files)}개 — 탈퇴하면 바로 지워져야 함')
    return check.result()


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


def p_gate_39(run, phone):
    check = Check()
    _allow_notifications(phone)
    account = _submitted(run)
    _app(check, phone(token_hash=run.link(account['email']), phase='first'), '대기 화면')
    _app(check, phone(fresh=False, phase='again'), '다시 켬')
    rows = _attempts(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['result'] == 'pending', f'attempts {rows} — 대기 1행 그대로여야 함')
    return check.result()


def p_gate_41(run, phone):
    check = Check()
    _allow_notifications(phone)
    account = _submitted(run)
    _app(check, phone(midway=lambda said: _approve(run, account['id']), token_hash=run.link(account['email'])), '통과 처리')
    rows = _attempts(run, account['id'])
    check.that(rows and rows[-1]['result'] == 'verified' and rows[-1]['reviewed_at'], f'attempts {rows} — verified · reviewed_at 이어야 함')
    state = _profile_state(run, account['id'])
    check.that(state == 'verified', f'profiles.student_verification {state} — verified 이어야 함')
    return check.result()


def _notified(run, phone, check, verdict):
    """대기 계정이 3b 대기 화면에서 앱을 뒤로 둔 사이 사람이 [verdict] 처리한다 → 알림이 정해진 글로 오는지(눌러서 3b · 3c 로 가는 건 앱이 본다)."""
    title, body = APPROVED if verdict == 'approved' else REJECTED
    account = _submitted(run)

    def background(said):
        # 기기 토큰이 서버에 올라와야 알림이 이 폰에 닿는다(관문 앞에서도 토큰 등록은 열려 있다 — cards/router.py)
        if not _until(lambda: _rows(run, f"push_tokens?profile_id=eq.{account['id']}&select=token"), TOKEN_TRIES, 2):
            raise Blocked(f'{TOKEN_TRIES * 2}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
        before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너 없이 화면만 새로 고친다
        if verdict == 'approved':
            _approve(run, account['id'])
        else:
            area1_b3._reject(run, account['id'], check)
        new = notify.wait_new(phone.serial, before, seconds=NOTICE_SECONDS)
        got = [n for n in new if (n.title, n.text) == (title, body)]
        check.that(got, f'{verdict}: {NOTICE_SECONDS}초 안에 알림 "{title} / {body}" 없음(새 알림 {len(new)}건)')
        if got:
            notify.tap_notification(phone.serial, title)
            time.sleep(1)

    _app(check, phone(midway=background, token_hash=run.link(account['email']), verdict=verdict), verdict)


def p_gate_43(run, phone):
    notify.require_daytime()  # 밤에는 방해 금지 시간이라 pending_pushes 로 보류된다
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    _allow_notifications(phone)
    for verdict in ('approved', 'rejected'):
        _notified(run, phone, check, verdict)
    return check.result()


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

tools.CASE_LIMITS.update({'E-GATE-43': CASE_LIMIT_SLOW, 'E-AUTH-18': CASE_LIMIT_SLOW})


CASES = {'E-GATE-33': gate_33, 'E-GATE-40': gate_40, 'E-GATE-42': gate_42, 'E-GATE-46': gate_46, 'E-GATE-49': gate_49,
         'E-AUTH-14': auth_14}
PHONE = {'E-GATE-39': p_gate_39, 'E-GATE-41': p_gate_41, 'E-GATE-43': p_gate_43, 'E-AUTH-18': p_auth_18}

area1.CASES.update(CASES)
area1.PHONE.update(PHONE)
area1.BUNDLES['area1-b5'] = [case for case in CASES if case != 'E-AUTH-14'] + list(PHONE) + ['E-AUTH-14']
