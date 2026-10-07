"""영역 1 B에뮬 가설 — 네트워크를 끊고 · 시계를 앞당기고 · 브라우저를 끄는 것은 실폰에 못 하므로 에뮬에서만 돈다.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_emu.dart 의 같은 번호.

돌릴 때: 에뮬을 켜고 `python -m e2e emu` 로 점검한 뒤 `python -m e2e run area1-emu --device B`. 실폰(--device A)에서는 전부 blocked 다.

시나리오에 있지만 이 묶음에 안 넣은 것: 연락처가 필요한 SET-29~42 · SAFE-35~46 — 에뮬 연락처에 `adb shell content insert` 로 넣는
도우미가 먼저 필요하다(이번에는 목록만).
"""

import contextlib

from e2e import area1, area1_b3, emu, notify
from e2e.area1 import Check, _app, _signed_in

# 시나리오와 다른 점: E-GATE-47 은 "제출 누르자마자" 끊는 대신 제출 직전(사진 · 실명을 다 넣은 뒤)에 끊는다 — 누른 뒤에 끊으면
# 요청이 이미 나갔는지가 매번 달라 판정이 흔들린다. 문구와 버튼 복귀는 같은 코드 경로(NetworkFailure)로 본다.


def _emulator(phone):
    """에뮬이어야 하고, 첫 로그인의 알림 권한 창이 가설 도중 앱 앞을 가리지 않게 미리 준다(영역 4 SET 도 같은 이유로 준다).
    이 권한이 없는 기기(안드로이드 12 이하)는 창도 없으니 못 줘도 그대로 간다."""
    emu.require_emulator(getattr(phone, 'serial', None))
    with contextlib.suppress(emu.Blocked):
        notify.grant_notifications(phone.serial)
    return phone.serial


def _back_online(serial):
    if not emu.go_online(serial):
        raise emu.Blocked('네트워크를 다시 켰는데 닿지 않음')


def _must_be_online(restored):
    """가설이 끝난 뒤 핑으로 다시 읽은 결과가 안 닿으면 blocked — 안 그러면 다음 가설이 엉뚱하게 틀린다.
    (가설이 예외로 끝난 경우엔 이 줄에 오지 않고 그 예외가 그대로 올라간다.)"""
    if not restored:
        raise emu.Blocked('끝난 뒤 네트워크를 켰는데 핑이 안 닿음 — 다음 가설 전에 에뮬 네트워크 확인')


def p_auth_22(run, phone):
    """홈까지 로그인 → 네트워크를 끈 채 다시 켬(01-1) → 앱이 멈춘 사이 켜고 "다시 시도" → 홈. 끝에 한 번 더 다시 실행해도 홈."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    try:
        _app(check, phone(token_hash=token, phase='login'), '로그인')
        emu.go_offline(serial)
        retry = _app(check, phone(fresh=False, phase='offline', midway=lambda said: _back_online(serial)), '끈 채 켜기')
        restart = _app(check, phone(fresh=False, phase='restart', expect='home', limit=30), '다시 실행')
    finally:
        restored = emu.go_online(serial)
    _must_be_online(restored)
    # 앱이 잰 시간(느린 에뮬 탓인지 가리는 단서)을 통과해도 남긴다 — 5초를 넘기면 앱이 그 사실을 적는다
    return check.result(' · '.join(n for n in (retry.get('note'), restart.get('note')) if n))


def p_auth_19(run, phone):
    """홈까지 로그인 → 에뮬 시계 +2시간 → 앱을 다시 열면 로그인 화면 없이 홈, 홈 API 가 값을 받는다. root 가 안 되면 blocked.
    다시 열기는 홈을 30초까지 기다린다(limit=30) — 에뮬은 실폰보다 느려 5초가 모자란다(E-AUTH-22 와 같은 이유)."""
    serial = _emulator(phone)
    check = Check()
    emu.root(serial, getattr(phone, 'hub', None))
    _, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token, phase='login'), '로그인')
    with emu.clock_shifted(serial, hours=2):
        _app(check, phone(fresh=False, phase='later', expect='home', limit=30), '+2시간 뒤 다시 열기')
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
        restored = emu.go_online(serial)
    _must_be_online(restored)
    rows = area1_b3._attempts(run, account['id'])
    check.that(not rows, f'네트워크가 끊겼는데 서버에 제출 행 {len(rows)}개')
    return check.result()


# AUTH-19 가 마지막 — adb root 가 이후 가설에까지 남지 않게(run-as 가 root 에서 되는지는 실물 미확인).
PHONE = {'E-AUTH-22': p_auth_22, 'E-GATE-12': p_gate_12, 'E-GATE-47': p_gate_47, 'E-AUTH-19': p_auth_19}

area1.PHONE.update(PHONE)
area1.BUNDLES['area1-emu'] = list(PHONE)
