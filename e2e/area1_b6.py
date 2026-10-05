"""영역 1 묶음 6 — 두 기기가 같이 하는 것(E-ONB-05)과 에뮬 네트워크(E-ONB-74).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b6.dart 의 같은 번호.

돌릴 때: A폰과 B에뮬을 둘 다 연결하고 `python -m e2e run area1-b6 --device B`. E-ONB-74 는 에뮬에서만 돈다(실폰은 blocked).
E-ONB-05 는 지금 `--device` 로 고른 기기와 나머지 한 기기(A ↔ B)를 함께 쓴다 — 나머지 기기용 우편함을 이 가설이 열고 닫는다.

시나리오와 다른 점: E-ONB-74 는 "확인 누르자마자" 끊는 대신 코드를 다 넣은 뒤 누르기 직전에 끊는다 — 누른 뒤에 끊으면 요청이 이미
나갔는지가 매번 달라 판정이 흔들린다(E-GATE-47 과 같은 이유, e2e/area1_emu.py). 문구는 같은 코드 경로(NetworkFailure)로 본다.
"""

import subprocess
import threading

from e2e import area1, area1_b2, area1_emu, emu, notify, tools
from e2e.area1 import Check, _app, _nickname, _rows, _signed_in
from e2e.tools import Blocked

RELEASE_WAIT = 120  # 두 앱이 다 멈출 때까지 기다리는 초 — 로그인 · 04-1 채우기가 느린 에뮬에서 넉넉히


# ── E-ONB-74 (B에뮬) ───────────────────────────────────────────────────────────────────────────


def p_onb_74(run, phone):
    """추천인(홈 계정)의 코드를 넣고 멈춤 → 네트워크를 끔 → 확인 → 문구 · 20 에 머묾 · 서버에 추천 행 · 하트 0."""
    serial = area1_emu._emulator(phone)
    check = Check()
    referrer, code = area1_b2._referrer(run)
    referee, token = _signed_in(run, 'ideal_note')
    try:
        _app(check, phone(midway=lambda said: emu.go_offline(serial), token_hash=token, code=code))
    finally:
        restored = emu.go_online(serial)
    area1_emu._must_be_online(restored)
    rows = _rows(run, f"referrals?referee_id=eq.{referee['id']}&select=referrer_id")
    check.that(not rows, f'네트워크가 끊겼는데 추천 행 {len(rows)}개')
    for who, account in (('나', referee), ('추천인', referrer)):
        hearts = area1_b2._hearts(run, account['id'])
        check.that(not hearts, f'{who} 하트가 {[h["amount"] for h in hearts]} 바뀜 — 변화 0 이어야 함')
    return check.result()


# ── E-ONB-05 (두 기기) ─────────────────────────────────────────────────────────────────────────


def _other_phone(run, phone, case):
    """지금 가설을 돌리는 기기의 짝(A ↔ B)을 쓸 수 있게 한다 → (그 기기용 Phone, 우편함). 우편함은 부른 쪽이 닫는다."""
    mine = 'A' if phone.serial == tools.serial('A', run.cfg) else 'B'
    name = 'B' if mine == 'A' else 'A'
    serial = tools.serial(name, run.cfg)
    if not serial:
        raise Blocked(f'e2e.env 에 E2E_DEVICE_{name} 가 없다 — 두 기기가 필요한 가설')
    if f'{serial}	device' not in tools.devices():  # offline · unauthorized 로 목록에만 있는 기기는 못 쓴다
        raise Blocked(f'{serial} 가 adb 에서 쓸 수 있는 상태가 아님 — 두 기기를 다 연결해야 한다')
    hub = tools.Hub(tools.DEVICES[name])
    try:
        tools.adb(serial, 'reverse', f'tcp:{tools.DEVICE_PORT}', f'tcp:{hub.port}')
    except BaseException:  # CalledProcessError · CaseTimeout — 부른 쪽의 try 에 들어가기 전이라 여기서 닫는다
        hub.close()
        raise
    return area1.Phone(run, hub, serial, case), hub


def p_onb_05(run, phone):
    """04-1 에서 두 기기가 같은 새 닉네임을 채우고 멈춤 → 둘이 다 멈추면 같이 보냄 → 한쪽만 저장되고 다른 쪽은 409 로 04-1 에 남는다.
    두 앱이 거의 동시에 "다음" 을 누르게 하려는 것이고, 시각이 조금 엇갈려도 결과(한쪽만 저장)는 같다 — 닉네임이 유일해야 하므로."""
    other, hub = _other_phone(run, phone, 'E-ONB-05')
    try:
        for device in (phone, other):
            if getattr(device, 'serial', None):
                try:
                    notify.grant_notifications(device.serial)
                except Blocked:
                    pass  # 안드로이드 12 이하는 권한 창이 없다
        check = Check()
        nickname = _nickname()
        people = [_signed_in(run, 'gate_done') for _ in (phone, other)]
        results = _race(check, [phone, other], [token for _, token in people], nickname)
        check.that(sorted(r for r in results if r) == ['saved', 'taken'],
                   f'두 기기 결과 {results} — 한쪽만 저장되고 다른 쪽은 "이미 있는 닉네임" 이어야 함')
        rows = _rows(run, f'profiles?nickname=eq.{nickname}&select=id')
        check.that(len(rows) == 1, f'닉네임 "{nickname}" 인 프로필 {len(rows)}개 — 1개여야 함')
        if len(rows) == 1 and 'saved' in results:  # 저장했다는 쪽이 정말 그 닉네임을 가진 계정이어야 한다(서로 바뀌면 앱 화면이 거짓)
            winner = people[results.index('saved')][0]['id']
            check.that(rows[0]['id'] == winner, f'닉네임을 가진 계정 {rows[0]["id"]} 가 저장했다는 쪽({winner})이 아님')
        return check.result()
    finally:
        hub.close()


def _race(check, devices, tokens, nickname):
    """두 기기를 따로 돌려 둘 다 멈출 때까지 기다렸다가 같이 보낸다 → 기기 순서대로 앱의 결과(outcome, 못 받았으면 None)."""
    barrier = threading.Barrier(len(devices), timeout=RELEASE_WAIT)
    outcomes = [None] * len(devices)
    errors = [None] * len(devices)
    stopped = []  # 준비 부족(Blocked) · 시간 초과(CaseTimeout)는 제품 실패가 아니다 — 러너가 가르도록 그대로 올린다
    released = [False] * len(devices)

    def release(index):
        def midway(stopped):
            barrier.wait()
            released[index] = True
        return midway

    def drive(index):
        try:
            said = devices[index](midway=release(index), token_hash=tokens[index], nickname=nickname)
            outcomes[index] = _app(check, said, f'기기 {index + 1}').get('outcome')
        except threading.BrokenBarrierError:
            errors[index] = '짝 기기가 멈추기 전에 끝났거나 답하지 않음'
        except (Blocked, tools.CaseTimeout) as error:
            stopped.append(error)
        except Exception as error:  # 한 기기의 예외가 다른 기기를 영영 기다리게 두지 않는다
            errors[index] = f'{type(error).__name__}: {error}'
        if not released[index]:
            barrier.abort()  # 멈추지 못하고 끝났으면 기다리는 짝을 풀어 준다 — 멈춘 뒤 끝난 쪽은 건드리지 않는다(짝이 막 깨어나는 중일 수 있다)

    threads = [threading.Thread(target=drive, args=(index,)) for index in range(len(devices))]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    if stopped:
        raise stopped[0]
    for index, error in enumerate(errors):
        if error:
            check.problems.append(f'기기 {index + 1}: {error}')
    return outcomes


PHONE = {'E-ONB-74': p_onb_74, 'E-ONB-05': p_onb_05}

area1.PHONE.update(PHONE)
area1.BUNDLES['area1-b6'] = list(PHONE)
