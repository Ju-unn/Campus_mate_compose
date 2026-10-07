"""영역 5 나 탭 빠진 가설 셋 — E-ME-05(두 기기) · 22 · 32(한 기기)(묶음 area5-more).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 5 의 그 줄이되, 코드가 다르면 코드가 기준이다. 앱 쪽은 frontend/integration_test/area5_more.dart 의 같은 번호.

E-ME-05  A 폰이 15-4 "남이 보는 내 프로필" 을, B 에뮬이 A 를 대상으로 한 카드의 10b 를 열어 둘의 카드 글자가 글자까지 같은지 본다. 두 화면은 같은 위젯
         (`ProfileCard`)이라 앱이 그 안의 글자 전부를 PC 에 말하고 PC 가 맞댄다 — 시나리오의 16개 값을 하나씩 찾지 않고 통째로 같은지 + A 의 닉네임 · 자기소개가
         든 것까지만 본다. A 는 폰 · B 는 에뮬(두 기기 가설은 늘 그렇다).
E-ME-22  15c 에서 자기소개를 고치고 에뮬 망을 느리게 한 채 "저장" 직후 시스템 뒤로 → 15-5 가 새 글을 보이고 DB 도 새 글. 자기소개 저장은 서버가 임베딩(유료)을 부르므로
         다른 저장 가설(area5_act ME-07)과 같이 `E2E_REAL_AI=1` 이 아니면 요청을 한 번도 보내지 않고 blocked. 망은 `adb emu network` 콘솔 명령으로 느리게 한다 —
         에뮬이 아니면(시리얼이 emulator- 로 안 시작하면) blocked. 얼마나 느리게 할지는 THROTTLE 에서 고친다(응답이 앱 제한 시간을 넘으면 저장이 실패한다).
E-ME-32  다른 사람이 쓰는 닉네임은 쓸 수 없다. 시나리오는 "둘다" 이지만 B 기기는 안 쓴다 — 중복은 서버 값이라 계정만 있으면 되고 B 의 닉네임은 PC 가 DB 에 적는다.
         입력 뒤 확인이 막으면(문구 + 저장 꺼짐) 통과, 확인이 안 막았으면 저장 뒤 서버 409 가 문구를 띄우고 15-6 에 머물러야 통과. 어느 쪽이든 DB 닉네임은 그대로.
"""

import contextlib

from e2e import area1, tools, twodev
from e2e.area1 import Check, _app, _one
from e2e.area2 import _card, _person
from e2e.area2_phone3 import _slow
from e2e.area2_two_accept import _after, _guarded
from e2e.area3_phone import MISSING
from e2e.area5_act import _bio_text, _free_nickname, _new_bio, _paid_case, _profile, _unlock, _write
from e2e.area5_read import TITLES, _home
from e2e.tools import Blocked

TAKEN = '이미 있는 닉네임이에요'
CASE_LIMIT_TWO = 1200  # 가설 하나 상한(초) — 계정 둘 + 두 기기
THROTTLE = {'speed': 'edge', 'delay': 'gprs'}  # adb emu network 의 느린 값(되돌릴 때는 full · none)
SLOW_WAIT = 420  # 느린 망에서 앱이 끝나기를 기다리는 상한(초) — 앱 안 기다림(60 + 120)보다 길게
LIMITS = {'side_timeout': {'A': 300, 'B': 300}, 'deadline': 700}


# ── 05 15-4 = 10b ─────────────────────────────────────────────────────────────────────────────────

def two_05(run, two):
    """A 의 15-4 카드 글자 목록 == B 의 10b 카드 글자 목록. 근거: me/router.py:95-105 · cards/router.py `profile_detail`(한 몸통), 앱은 둘 다 `ProfileCard`."""
    check, seen = Check(), {}
    a, b = _person(run, 'male'), _person(run, 'female')
    _card(run, b, a)  # B 의 오늘 카드에 A 한 장
    row = _one(run, f"profiles?id=eq.{a['id']}&select=nickname,bio")
    if not row.get('nickname') or not row.get('bio'):
        raise Blocked('준비: A 의 닉네임 · 자기소개를 못 읽음')

    def a_card(said, sync):
        seen['a'] = said.get('texts')
        sync.set('a-card')

    def b_card(said, sync):
        _after(sync, 'a-card', 'A')
        mine, theirs = seen.get('a'), said.get('texts')
        check.that(bool(mine) and bool(theirs), f'카드 글자를 못 받음 — A {mine!r} · B {theirs!r}')
        check.that(mine == theirs, f'15-4 와 10b 의 카드 글자가 다름 — A {mine} · B {theirs}')
        joined = ' '.join(theirs or [])
        check.that(row['nickname'] in joined, f"카드에 A 의 닉네임 {row['nickname']!r} 이 없음")
        check.that(row['bio'] in joined, f"카드에 A 의 자기소개 {row['bio']!r} 가 없음")

    result, memo = two({('A', 'card'): a_card, ('B', 'card'): b_card},
                       a_job={'token_hash': run.link(a['email'])}, b_job={'token_hash': run.link(b['email'])}, **LIMITS)
    if check.problems:
        return 'fail', '; '.join(check.problems) + f' [{memo}]'
    return result, memo


# ── 22 저장 직후 뒤로 ─────────────────────────────────────────────────────────────────────────────

def _throttle(serial, on):
    """에뮬 망을 느리게(on) · 되돌림(끔). 에뮬 콘솔이 거절하면 blocked."""
    if not serial.startswith('emulator-'):
        raise Blocked(f'에뮬 전용 가설 — {serial} 은 adb emu 로 망을 못 조절한다(--device 로 에뮬을 고른다)')
    for name, slow in THROTTLE.items():
        out = tools.adb(serial, 'emu', 'network', name, slow if on else ('full' if name == 'speed' else 'none'), check=False) or ''
        if 'KO' in out:
            raise Blocked(f'에뮬 콘솔이 망 {name} 설정을 거절: {out.strip()[:80]}')


def p_me_22(run, phone, paid):
    """15c 저장 직후 시스템 뒤로 — 저장은 끝까지 되고 15-5 가 새 글, DB 도 새 글. 근거: profile_edit_view_model.dart:26-40(keepAlive)."""
    check = Check()
    account, token = _home(run)
    serial = phone.serial
    phone = _slow(phone, SLOW_WAIT)  # 느린 망이라 앱이 저장 뒤 15-5 를 읽는 데 오래 걸린다
    new, tag = _new_bio()
    paid()
    try:
        said = _app(check, phone(midway=lambda said: _throttle(serial, True), token_hash=token, bio=new, tag=tag))
    finally:
        with contextlib.suppress(Blocked):
            _throttle(serial, False)
    got = _bio_text(run, account)
    check.that(got == new, f'DB 자기소개 {got!r}(기대 {new!r} — 화면을 나가도 저장은 끝까지 돼야 함)')
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"뒤로 간 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('manage_bios', MISSING) == [new], f"15-5 자기소개 {said.get('manage_bios', MISSING)}(기대 [{new!r}])")
    return check.result('망을 느리게 한 정도(edge · gprs)는 실기기에서 재 본 값이 아니다 — 저장이 시간 초과로 실패하면 THROTTLE 을 줄인다')


# ── 32 남이 쓰는 닉네임 ───────────────────────────────────────────────────────────────────────────

def p_me_32(run, phone):
    check = Check()
    account, token = _home(run)
    other = run.account('home')  # B — 기기는 안 쓰고 닉네임만 갖는다
    _unlock(run, account)
    taken = _free_nickname(run)
    _write(run, other, {'nickname': taken})
    before = _profile(run, account, 'nickname,nickname_changed_at')
    said = _app(check, phone(token_hash=token, nickname=taken))
    if said.get('taken') is True:
        check.that(said.get('save_enabled') is False, f"'{TAKEN}' 가 떴는데 저장 버튼 {said.get('save_enabled', MISSING)}(기대 꺼짐)")
    else:  # 입력 뒤 확인이 안 막았으면 저장 뒤 서버가 막아야 한다
        check.that(said.get('after_save_taken') is True, f"입력 뒤 '{TAKEN}' 도, 저장 뒤 서버의 막음도 안 보임(taken {said.get('taken', MISSING)} · 저장 뒤 {said.get('after_save_taken', MISSING)})")
        check.that(said.get('on_edit') is True, f"서버가 막은 뒤 15-6 에 머물러야 한다: {said.get('on_edit', MISSING)}")
    after = _profile(run, account, 'nickname,nickname_changed_at')
    check.that(after == before, f'DB A 닉네임 · 변경 시각 {after}(기대 그대로 {before})')
    mine = _one(run, f"profiles?id=eq.{other['id']}&select=nickname").get('nickname')
    check.that(mine == taken, f'B 의 닉네임 {mine!r}(기대 그대로 {taken!r})')
    return check.result('B 기기는 안 씀 — 닉네임 중복은 서버 값이라 계정만 있으면 된다')


# ── 등록 · 묶음 ────────────────────────────────────────────────────────────────────────────────────

PHONE = {'E-ME-22': _paid_case('E-ME-22', p_me_22), 'E-ME-32': p_me_32}
TWO = {'E-ME-05': _guarded(two_05)}

area1.PHONE.update(PHONE)
twodev.TWO.update(TWO)
area1.BUNDLES['area5-more'] = ['E-ME-05', 'E-ME-22', 'E-ME-32']
tools.CASE_LIMITS.update({'E-ME-05': CASE_LIMIT_TWO, 'E-ME-22': 900, 'E-ME-32': 600})
