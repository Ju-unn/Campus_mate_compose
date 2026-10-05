"""영역 2 에뮬 홈 가설 7개 — 19 코호트 대기 화면(E-HOME-20 · 21 · 22)과 "친구에게 초대 링크 보내기"(30 · 31 · 32), 글자 확대 · 좁은 폭(33).
묶음 area2-emu-home, B에뮬 전용(`python -m e2e run area2-emu-home --device B`) — 실폰(--device A)에서는 전부 blocked 다.
기대값은 바탕화면 시나리오가 아니라 지금 코드 기준이다. 앱 쪽은 frontend/integration_test/area2_emu_home.dart 의 같은 번호.

닫힌 학교 만들기는 area2_time_device(HOME-23 · 26 · 29)와 같다 — 시험대학 행의 `card_opens_at` 을 다음 월요일 07:00 으로 옮기고
끝나면(예외여도) 처음 값으로 되돌린다(`td.opens_at_set`, 원래 값 파일로 PC 가 꺼져도 다음 실행이 되돌림). 실사용자 학교는 만지지 않는다.
계정은 닫기 전에 만든다. 시나리오의 "G2 학교" 는 둘째 시험학교지만 코드는 시험대학 하나를 닫았다 되돌린다(HOME-23 과 같은 방식) —
닫혀 있는 몇 분 동안은 이 에뮬 · 시험대학을 쓰는 다른 묶음을 돌리지 않는다(어차피 에뮬 B 는 한 번에 하나).

모집 인원은 시험대학에 원래 있던 활성 계정(KEEP 등)까지 센다 — 시나리오의 "4명 → 3명" 은 가짜 학교 기준이라, 여기서는 DB 에서 센 값을
앱이 그대로 보여 주는지, V 한 명이 탈퇴하면 정확히 하나 줄어드는지를 본다(요약 API 도 DB 와 같게 세는지 함께).

시간을 만지는 가설은 없다 — 7개 모두 에뮬에서 된다. 에뮬 설정을 바꾸는 것은 둘이다: HOME-31 은 네트워크를 끈다(끝나면 켠다),
HOME-33 은 화면 밀도와 글자 배율을 바꾼다(끝나면 `wm density reset` · 원래 배율). PC 가 중간에 꺼지면 에뮬이 360dp · 1.3배로 남을 수 있다 —
그때는 `adb shell wm density reset` 과 `adb shell settings delete system font_scale`.
"""

import re
import time
from contextlib import contextmanager

from e2e import area1, area4_set2, emu, notify, tools
from e2e import area2_time_device as td
from e2e.area1 import Check, _api, _app, _rows, _signed_in
from e2e.area1_emu import _emulator, _must_be_online
from e2e.area2 import _set_status
from e2e.area2_phone3 import SHARE_LABELS, _tap_label
from e2e.tools import Blocked

SHEET_WAIT = 3  # 버튼을 누른 뒤 공유 창이 뜨기를 기다리는 시간(초) — 먼저 코드를 서버에서 받아 온다
FONT_SCALE, WIDTH_DP = 1.3, 360  # 시나리오 E-HOME-33 "글자 1.3배 · 360 폭"
LEAVERS = 3  # E-HOME-22 의 V — 같은 학교에서 가입을 끝낸 다른 사람 3명
SHEET = re.compile(r'ActivityRecord\{(\w+) u\d+ \S*(?:Chooser|Resolver)Activity')


# ── 순수 도우미 ─────────────────────────────────────────────────────────────────────────────────────

def days_until(now, opens):
    """앱의 D-숫자 — 달력 날짜의 차이(cohortDayLabel). 시각 차이로 세면 06:59 와 07:00 사이에서 하루가 틀린다."""
    return (opens.date() - now.date()).days


def date_label(opens):
    """큰 줄 "10월 12일" — 0 을 안 붙인다(cohortDateLabel)."""
    return f'{opens.month}월 {opens.day}일'


def invite_text(code):
    """공유 글 — frontend/lib/referral/model/invite_share.dart inviteShareText. 하트 숫자 · 스토어 링크 없음."""
    return f'CampusMate 에서 같이 해요! 가입할 때 추천 코드 {code} 를 넣어 줘.'


def chooser_count(dump):
    """`dumpsys activity activities` 에 있는 공유 창(Chooser · Resolver)의 개수 — 같은 창이 여러 줄에 나오므로 기록 해시로 센다."""
    return len(set(SHEET.findall(dump or '')))


def is_chooser(top):
    return 'Chooser' in top or 'Resolver' in top


def density_for(width_px, width_dp):
    """화면 폭이 정확히 [width_dp] 가 되는 밀도(dpi) — dp = px × 160 ÷ dpi."""
    return round(width_px * 160 / width_dp)


# ── 에뮬 · 서버 도우미 ───────────────────────────────────────────────────────────────────────────────

def _shell(serial, *args):
    return tools.adb(serial, 'shell', *args, check=False)


@contextmanager
def display_big(serial, scale, width_dp, sleep=time.sleep):
    """에뮬 글자 배율을 [scale] 로, 화면 밀도를 바꿔 폭을 [width_dp] 로 — 끝나면(예외여도) 밀도를 되돌리고 배율을 원래대로.
    앱은 이 안에서 새로 켜야 설정이 먹는다(Run.phone 이 앞 프로세스를 죽이고 켠다)."""
    emu.require_emulator(serial)
    size = re.search(r'Physical size: (\d+)x\d+', _shell(serial, 'wm', 'size'))
    if not size:
        raise Blocked('화면 크기를 못 읽음(wm size)')
    density = density_for(int(size.group(1)), width_dp)
    before = _shell(serial, 'settings', 'get', 'system', 'font_scale').strip()
    try:
        _shell(serial, 'settings', 'put', 'system', 'font_scale', str(scale))
        _shell(serial, 'wm', 'density', str(density))
        sleep(3)  # 설정이 퍼져 시스템 화면이 다시 그려지기를
        if f'Override density: {density}' not in _shell(serial, 'wm', 'density'):
            raise Blocked(f'화면 밀도를 {density} 로 못 바꿈(wm density)')
        if _shell(serial, 'settings', 'get', 'system', 'font_scale').strip() != str(scale):
            raise Blocked(f'글자 배율을 {scale} 로 못 바꿈(settings put system font_scale)')
        yield
    finally:
        _shell(serial, 'wm', 'density', 'reset')
        if before in ('', 'null'):
            _shell(serial, 'settings', 'delete', 'system', 'font_scale')
        else:
            _shell(serial, 'settings', 'put', 'system', 'font_scale', before)


def _recruits(run, check, school, account):
    """시험대학의 활성 계정 수(DB) — 앱이 "현재 모집 인원" 으로 보여 줄 값. 요약 API 가 같게 세는지도 본다.
    ponytail: PostgREST 기본 상한 1000행 — 시험대학이 그만큼 커지면 세는 방법을 바꾼다(count=exact)."""
    count = len(_rows(run, f'profiles?university_id=eq.{school}&status=eq.active&select=id'))
    status, body = _api(run, 'GET', '/home/summary', account['token'])[:2]
    said = ((body or {}).get('cohort') or {}).get('recruit_count') if status == 200 else None
    check.that(said == count, f'요약 API 의 recruit_count {said!r} ≠ DB 활성 수 {count}(/home/summary {status})')
    return count


def _opens(now):
    return td.future_monday(now)


# ── 19 코호트 대기 화면 ──────────────────────────────────────────────────────────────────────────────

def p_home_20(run, phone):
    """닫힌 학교(다음 월요일 07:00)의 메인 탭 = 대기 화면 — "우리 학교 첫 카드까지 · D-N" · 큰 날짜 "M월 D일" · 모집 인원 · 초대 버튼."""
    serial = _emulator(phone)
    check = Check()
    account, token = _signed_in(run, 'home')
    now = td.now_seoul()
    opens = _opens(now)
    with emu.seoul_timezone(serial), td.opens_at_set(run, opens) as school:
        recruit = _recruits(run, check, school, account)
        _app(check, phone(token_hash=token, days=days_until(now, opens), date=date_label(opens), recruit=recruit,
                          today=now.date().isoformat()))
    return check.result(f'여는 시각 {opens:%m-%d %H:%M} · D-{days_until(now, opens)} · 모집 {recruit}명(DB)')


def p_home_21(run, phone):
    """모집 중에는 오늘 탭도 같은 대기 화면 — "우리 학교 첫 카드까지" 1개, 카드 목록 0."""
    _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    with td.opens_at_set(run, _opens(td.now_seoul())):
        _app(check, phone(token_hash=token))
    return check.result()


def p_home_22(run, phone):
    """같은 학교에 가입을 끝낸 V 3명 + B → 앱을 켜 모집 인원을 보고, V 한 명을 탈퇴시킨 뒤 다시 켜면 정확히 하나 줄어 있다."""
    _emulator(phone)
    check = Check()
    account, token = _signed_in(run, 'home')
    leavers = [run.account('home') for _ in range(LEAVERS)]  # 학교를 닫기 전에 — 닫힌 학교에서 계정 만들기는 가설 밖이다
    with td.opens_at_set(run, _opens(td.now_seoul())) as school:
        before = _recruits(run, check, school, account)
        _app(check, phone(token_hash=token, recruit=before), '첫 실행')
        _set_status(run, leavers[0], 'withdrawn')
        after = _recruits(run, check, school, account)
        if after != before - 1:
            raise Blocked(f'V 1명을 탈퇴 처리했는데 DB 활성 수가 {before} → {after}(기대 N-1 = {before - 1}) — 다른 계정이 같은 때 바뀌었나')
        _app(check, phone(fresh=False, recruit=after), '재시작')
    return check.result(f'모집 {before}명 → {after}명(DB · 요약 API · 앱 화면)')


# ── "친구에게 초대 링크 보내기" ─────────────────────────────────────────────────────────────────────

def _copy_from_sheet(phone, check, text, notes):
    """공유 창이 맨 앞인지 보고, 창의 "복사" 를 누른다 — 앱이 이어서 클립보드를 읽는다(E-REF-04 와 같은 방식).
    복사 칸이 없으면 창을 닫고 blocked(이 기기 공유 창 모양 — 사람 필요)."""
    time.sleep(SHEET_WAIT)
    top = phone.top()
    if tools.PACKAGE in top:
        check.that(False, f'공유 창이 안 뜸 — 맨 앞이 아직 우리 앱({top[:80]})')
        return
    notes.append('공유 창 확인' if is_chooser(top) else f'맨 앞이 공유 창 이름은 아님: {top[:80]}')
    if notify.screen_has(phone.serial, text):
        notes.append('창에서 초대 글 확인')
    if not _tap_label(phone.serial, SHARE_LABELS):
        tools.adb(phone.serial, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
        raise Blocked('공유 창에 "복사" 칸이 없음(이 기기 공유 창) — 사람 필요')
    time.sleep(1)


def p_home_30(run, phone):
    """대기 화면 버튼 → 휴대폰 공유 창 → "복사" → 클립보드 = "CampusMate 에서 같이 해요! 가입할 때 추천 코드 {내 코드} 를 넣어 줘."(하트 숫자 없음)."""
    _emulator(phone)
    check = Check()
    account, token = _signed_in(run, 'home')
    text = invite_text(area4_set2._code(run, account['id']))
    notes = []
    with td.opens_at_set(run, _opens(td.now_seoul())):
        said = _app(check, phone(midway=lambda said: _copy_from_sheet(phone, check, text, notes), token_hash=token))
    if said.get('result') == 'pass':
        check.that(said.get('clipboard') == text, f'클립보드 {said.get("clipboard")!r} ≠ 초대 글 {text!r}')
    return check.result('; '.join(notes))


def _no_sheet(check, phone):
    """공유 창 0 — 맨 앞이 공유 창이면 fail(그리고 닫는다)."""
    top = phone.top()
    if is_chooser(top):
        tools.adb(phone.serial, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
        check.that(False, f'공유 창이 떠 있음({top[:80]})')


def p_home_31(run, phone):
    """대기 화면이 뜬 뒤 네트워크를 끄고 버튼 → 오류 토스트 1개(3초), 공유 창 0, 앱은 안 죽는다. 끝나면 네트워크를 켠다."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    try:
        with td.opens_at_set(run, _opens(td.now_seoul())):
            _app(check, phone(midway=lambda said: emu.go_offline(serial), token_hash=token))
            _no_sheet(check, phone)
    finally:
        restored = emu.go_online(serial)
    _must_be_online(restored)
    return check.result()


def _two_taps(check, serial):
    """앱이 0.2초 간격으로 두 번 누른 뒤 — 공유 창 기록이 하나여야 한다. 하나라도 있으면 BACK 으로 닫는다(없을 때는 앱을 나가게 되므로 안 누른다)."""
    time.sleep(SHEET_WAIT)
    count = chooser_count(tools.adb(serial, 'shell', 'dumpsys', 'activity', 'activities'))
    check.that(count == 1, f'공유 창 {count}개(기대 1)')
    if count:
        tools.adb(serial, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
        time.sleep(1)


def p_home_32(run, phone):
    """버튼을 0.2초 간격으로 두 번 눌러도 공유 창은 한 번. 누르기는 앱이 한다(adb input 은 한 번에 0.3초 넘게 걸려 0.2초를 못 맞춘다)."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    with td.opens_at_set(run, _opens(td.now_seoul())):
        _app(check, phone(midway=lambda said: _two_taps(check, serial), token_hash=token))
    return check.result('서버가 코드를 주는 시간이 0.2초보다 짧으면 두 번째 누름이 "이미 열림" 이 아니라 끝난 뒤에 닿는다 — 그때 2개면 앱 결함 후보')


# ── 글자 확대 · 좁은 폭 ──────────────────────────────────────────────────────────────────────────────

def p_home_33(run, phone):
    """글자 1.3배 · 360dp 에서 48px 날짜 줄이 넘치지 않고, 끝까지 스크롤하면 초대 버튼이 보인다."""
    serial = _emulator(phone)
    check = Check()
    _, token = _signed_in(run, 'home')
    opens = _opens(td.now_seoul())
    with emu.seoul_timezone(serial), td.opens_at_set(run, opens), display_big(serial, FONT_SCALE, WIDTH_DP):
        _app(check, phone(token_hash=token, font_scale=FONT_SCALE, width_dp=WIDTH_DP, date=date_label(opens)))
    return check.result()


PHONE = {'E-HOME-20': p_home_20, 'E-HOME-21': p_home_21, 'E-HOME-22': p_home_22, 'E-HOME-30': p_home_30,
         'E-HOME-31': p_home_31, 'E-HOME-32': p_home_32, 'E-HOME-33': p_home_33}

tools.CASE_LIMITS['E-HOME-22'] = 900  # 계정 4개 + 앱 두 번 — 기본 420초로는 계정 만들기가 느린 날 모자란다

area1.PHONE.update(PHONE)
area1.BUNDLES['area2-emu-home'] = list(PHONE)
