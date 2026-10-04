"""영역 1 B에뮬 가설 — 네트워크를 끊고 · 시계를 앞당기고 · 브라우저를 끄는 것은 실폰에 못 하므로 에뮬에서만 돈다.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_emu.dart 의 같은 번호.

돌릴 때: 에뮬을 켜고 `python -m e2e emu` 로 점검한 뒤 `python -m e2e run area1-emu --device B`. 실폰(--device A)에서는 전부 blocked 다.

시나리오에 있지만 이 묶음에 안 넣은 것: 연락처가 필요한 SET-29~42 · SAFE-35~46 — 에뮬 연락처에 `adb shell content insert` 로 넣는
도우미가 먼저 필요하다(이번에는 목록만).
"""

from e2e import area1, area1_b3, emu
from e2e.area1 import Check, _app, _signed_in

# 시나리오와 다른 점: E-GATE-47 은 "제출 누르자마자" 끊는 대신 제출 직전(사진 · 실명을 다 넣은 뒤)에 끊는다 — 누른 뒤에 끊으면
# 요청이 이미 나갔는지가 매번 달라 판정이 흔들린다. 문구와 버튼 복귀는 같은 코드 경로(NetworkFailure)로 본다.


def _emulator(phone):
    emu.require_emulator(getattr(phone, 'serial', None))
    return phone.serial


def _back_online(serial):
    if not emu.go_online(serial):
        raise emu.Blocked('네트워크를 다시 켰는데 닿지 않음')


def p_auth_22(run, phone):
    """홈까지 로그인 → 네트워크를 끈 채 다시 켬(01-1) → 앱이 멈춘 사이 켜고 "다시 시도" → 홈. 끝에 한 번 더 다시 실행해도 홈."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    try:
        _app(check, phone(token_hash=token, phase='login'), '로그인')
        emu.go_offline(serial)
        _app(check, phone(fresh=False, phase='offline', midway=lambda said: _back_online(serial)), '끈 채 켜기')
        _app(check, phone(fresh=False, phase='restart', expect='home'), '다시 실행')
    finally:
        emu.go_online(serial)
    return check.result()


def p_auth_19(run, phone):
    """홈까지 로그인 → 에뮬 시계 +2시간 → 앱을 다시 열면 로그인 화면 없이 홈, 홈 API 가 값을 받는다. root 가 안 되면 blocked."""
    serial = _emulator(phone)
    check = Check()
    emu.root(serial, getattr(phone, 'hub', None))
    _, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token, phase='login'), '로그인')
    with emu.clock_shifted(serial, hours=2):
        _app(check, phone(fresh=False, phase='later', expect='home'), '+2시간 뒤 다시 열기')
    return check.result()


def p_gate_12(run, phone):
    """https 를 받는 앱을 모두 끈 에뮬에서 약관 "보기" → 토스트 3초."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'new')
    with emu.browsers_disabled(serial):
        _app(check, phone(token_hash=token))
    return check.result()


def p_gate_47(run, phone):
    """동의까지 끝낸 계정이 학생증 사진 · 실명을 다 넣고 멈춘 사이 네트워크를 끊는다 → 제출 → 문구 · 버튼 복귀, 서버엔 제출 행 0."""
    serial = _emulator(phone)
    check = Check()
    try:
        account = area1_b3._submit(run, phone, 'id_ok.jpg', check, on_step=lambda account: emu.go_offline(serial))
    finally:
        emu.go_online(serial)
    rows = area1_b3._attempts(run, account['id'])
    check.that(not rows, f'네트워크가 끊겼는데 서버에 제출 행 {len(rows)}개')
    return check.result()


# AUTH-19 가 마지막 — adb root 가 이후 가설에까지 남지 않게(run-as 가 root 에서 되는지는 실물 미확인).
PHONE = {'E-AUTH-22': p_auth_22, 'E-GATE-12': p_gate_12, 'E-GATE-47': p_gate_47, 'E-AUTH-19': p_auth_19}

area1.PHONE.update(PHONE)
area1.BUNDLES['area1-emu'] = list(PHONE)
