"""영역 3 SAFE-35~46 — 연락처 차단(8a/8a-2/8d/16b)과 서버 쪽 효과. 기기 연락처를 넣고 권한을 껐다 켜야 해서 B에뮬(--device B)에서만 돈다.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area3_contacts.dart 의 같은 번호.

`python -m e2e run area3-contacts --device B`. 연락처 넣기 · 권한 · 권한 창은 영역 4 SET-29~42 와 같은 도우미(e2e/contacts.py)를 쓴다.
실폰(--device A)에서는 전부 blocked 다. SAFE-44(서버가 201개 · 0개를 막는다)는 API 만이라 e2e/area3_safe.py 에 있다.

시나리오와 다른 점(그대로 두면 판정할 수 없는 것):
- SAFE-37 "Cloud Run 로그에 번호 0회" — 로그는 gcloud 로만 읽을 수 있어 이 묶음에서 안 본다. DB 행에 번호가 없는지만 본다.
- SAFE-43 "서버 요청 2번(200 + 1)" — 요청 수를 직접 못 센다. 한 요청은 한 트랜잭션이라 created_at 이 하나이므로, 서로 다른 created_at 이 둘이면 두 요청으로 본다.
- SAFE-45 · 46 의 준비("E-SAFE-38 뒤")는 38 의 흐름을 그 가설 안에서 다시 한다(가설 하나 = 앱 한 번 켜기 규칙).
"""

import time

from e2e import area1, contacts, emu
from e2e.area1 import Check, _app, _rows
from e2e.area1_emu import _emulator
from e2e.area2 import _candidates, _person, _phone
from e2e.area4_contacts import _dialog, _number, _settings_on_top, people
from e2e.tools import Blocked, PACKAGE, ROOT

import e2e.tools as tools

APK = ROOT / 'frontend' / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-debug.apk'
FRIEND = '차단지인'


def _blocks(run, account):
    return _rows(run, f"contact_blocks?owner_id=eq.{account['id']}&select=id,contact_hmac,created_at")


def reinstall(serial):
    """앱을 지우고 다시 깐다(`adb uninstall` → `install -r -g`). 파일을 지우기 전에 깔 APK 가 있는지부터 본다 — 지운 뒤에 없으면 에뮬이 빈 채로 남는다."""
    emu.require_emulator(serial)
    if not APK.is_file():
        raise Blocked(f'깔 APK 가 없음({APK}) — flutter build apk --debug -t integration_test/e2e_test.dart')
    tools.adb(serial, 'uninstall', PACKAGE, check=False)
    out = tools.adb(serial, 'install', '-r', '-g', str(APK))
    if 'Success' not in out:
        raise Blocked(f'앱을 다시 깔지 못함: {out.strip()[:120]}')
    time.sleep(2)


def _friends(run):
    """B(남, 앱 사용자)와 F(여, 번호 있음) — 서로 후보가 아니면 준비 실패(blocked)."""
    b, f = _person(run, 'male'), _person(run, 'female', phone=_phone())
    if f['id'] not in _candidates(run, b) or b['id'] not in _candidates(run, f):
        raise Blocked('준비: 지인 차단 전부터 B 와 F 가 서로 후보가 아님')
    return b, f


def _mutually_excluded(check, run, b, f, label=''):
    check.that(f['id'] not in _candidates(run, b), f'{label}B 의 후보에 F 가 그대로 있음')
    check.that(b['id'] not in _candidates(run, f), f'{label}F 의 후보에 B 가 그대로 있음')


def _session(run, phone, who, crowd, granted, check, midway=None, **job):
    """[who] 로 로그인한 앱을 [crowd] 연락처 · [granted] 권한으로 한 번 켠다."""
    serial = phone.serial
    with contacts.on_device(serial, crowd, granted):
        return _app(check, phone(token_hash=run.link(who['email']), midway=midway, names=[n for n, _ in crowd], **job))


def _case(crowd=None, granted=True, judge=None, midway=None, **job):
    """새 홈 계정 하나(남)로 [crowd] 연락처를 가지고 앱을 한 번 켜고, [judge](run, phone, check, account, crowd) 가 DB 를 본다."""
    def case(run, phone):
        _emulator(phone)
        check = Check()
        account = run.account('home')
        persons = crowd() if callable(crowd) else (crowd if crowd is not None else people())
        with contacts.on_device(phone.serial, persons, granted):
            _app(check, phone(token_hash=run.link(account['email']), midway=midway(phone.serial) if midway else None,
                              names=[n for n, _ in persons], **job))
            if judge:
                judge(run, phone, check, account, persons)
        return check.result()
    return case


def _rows_is(count, label):
    def judge(run, phone, check, account, crowd):
        got = len(_blocks(run, account))
        check.that(got == count, f'{label}: contact_blocks {got}행(기대 {count})')
    return judge


# ── 권한 안내 ────────────────────────────────────────────────────────────────────────────────────

p_safe_35 = _case(granted=False, midway=_dialog(True), judge=_rows_is(0, '권한만 받았을 뿐'))


def p_safe_36(run, phone):
    """두 판 — "나중에 할게요" 와 (OS 창 "허용 안 함") 모두 8a-2, 그리고 "기기 설정 열기" 뒤 설정 앱이 맨 위."""
    _emulator(phone)
    check = Check()
    account = run.account('home')
    for phase, midway in (('later', None), ('deny', lambda serial: _dialog(False)(serial))):
        persons = people()
        with contacts.on_device(phone.serial, persons, False):
            _app(check, phone(token_hash=run.link(account['email']), midway=midway(phone.serial) if midway else None,
                              names=[n for n, _ in persons], phase=phase), phase)
            _settings_on_top(run, phone, check, account, persons)
    return check.result()


# ── 차단하기 ─────────────────────────────────────────────────────────────────────────────────────


def _hash_only(run, phone, check, account, crowd):
    rows = _blocks(run, account)
    check.that(len(rows) == 1, f'contact_blocks {len(rows)}행(기대 1)')
    number = crowd[0][1][0]
    dump = str(rows)
    for form in (number, number.replace('-', '')):
        check.that(form not in dump, f'서버 행에 번호 원문이 있음({form[:3]}…)')
    check.that(all(r.get('contact_hmac') for r in rows), 'contact_hmac 이 비어 있음')


def p_safe_37(run, phone):
    number = _number()
    return _case([('테스트지인', (number,))], judge=_hash_only, pick_names=['테스트지인'], rows=1)(run, phone)


def _friend_block(shape):
    """F 의 번호를 B 연락처에 [shape] 모양으로 넣고 B 앱에서 차단한다 → 서로 후보에서 빠져야 한다."""
    def case(run, phone):
        _emulator(phone)
        check = Check()
        b, f = _friends(run)
        crowd = people(2) + [(FRIEND, (shape(f['phone']),))]
        _session(run, phone, b, crowd, True, check, pick_names=[FRIEND], rows=1)
        check.that(len(_blocks(run, b)) == 1, f"contact_blocks {len(_blocks(run, b))}행(기대 1)")
        _mutually_excluded(check, run, b, f, '차단 뒤 ')
        return check.result()
    return case


p_safe_38 = _friend_block(lambda number: number)
p_safe_39 = _friend_block(lambda number: '+82 ' + number[1:])  # 010-1234-5678 → +82 10-1234-5678

p_safe_40 = _case([('유선지인', ('02-123-4567',))], judge=_rows_is(0, '유선 번호만'), pick_names=['유선지인'], rows=0)


def p_safe_41(run, phone):
    return _case([('휴대폰두개', (_number(), _number()))], judge=_rows_is(2, '번호 두 개'), pick_names=['휴대폰두개'], rows=2)(run, phone)


def p_safe_42(run, phone):
    """한 사람을 차단한 뒤 16b "추가" 로 같은 사람을 또 차단해도 한 줄(같은 id)."""
    first = []

    def midway(serial):
        return lambda said: first.extend(r['id'] for r in _blocks(run, account))
    _emulator(phone)
    check = Check()
    account = run.account('home')
    crowd = [('같은사람', (_number(),))]
    with contacts.on_device(phone.serial, crowd, True):
        _app(check, phone(token_hash=run.link(account['email']), midway=midway(phone.serial), names=['같은사람'], pick_names=['같은사람'], rows=1))
        got = [r['id'] for r in _blocks(run, account)]
    check.that(len(got) == 1, f'두 번 막았더니 contact_blocks {len(got)}행(기대 1)')
    check.that(got == first, f'같은 사람인데 id 가 바뀜(처음 {first} → 끝 {got})')
    return check.result()


def p_safe_43(run, phone):
    def judge(run, phone, check, account, crowd):
        rows = _blocks(run, account)
        check.that(len(rows) == 201, f'contact_blocks {len(rows)}행(기대 201)')
        batches = len({r['created_at'] for r in rows})
        check.that(batches == 2, f'서버 요청이 {batches}번으로 보임(200 + 1 이면 2번 — 요청마다 created_at 이 하나)')
    return _case(lambda: people(201), judge=judge, pick='all')(run, phone)


# ── 풀기 · 지우고 다시 깔기 ─────────────────────────────────────────────────────────────────────


def p_safe_45(run, phone):
    """38 의 흐름으로 차단 → (PC 가 서로 후보에서 빠진 것을 확인) → 앱이 16b 에서 풀면 줄이 사라지고 DB 0행, 서로 다시 후보."""
    _emulator(phone)
    check = Check()
    b, f = _friends(run)
    held = []

    def midway(said):
        held.append((f['id'] not in _candidates(run, b), b['id'] not in _candidates(run, f)))
    crowd = people(2) + [(FRIEND, (f['phone'],))]
    _session(run, phone, b, crowd, True, check, midway=midway, pick_names=[FRIEND], rows=1)
    if not held and check.result()[0] == 'fail':
        return check.result()  # 앱이 'blocked' 에 닿기 전에 실패 — 준비 탓이 아니라 앱의 실패 사유를 보인다
    if held != [(True, True)]:
        raise Blocked('준비: 차단 뒤에도 서로 후보 — 해제를 확인할 수 없음(SAFE-38 이 먼저 통과해야 함)')
    check.that(not _blocks(run, b), f'해제했는데 contact_blocks {len(_blocks(run, b))}행')
    check.that(f['id'] in _candidates(run, b), '해제 뒤 B 의 후보에 F 가 다시 안 나옴')
    check.that(b['id'] in _candidates(run, f), '해제 뒤 F 의 후보에 B 가 다시 안 나옴')
    return check.result()


def p_safe_46(run, phone):
    """38 의 흐름으로 차단 → 앱을 지우고 다시 깔아 새로 로그인 → 16b 에 이름 없는 줄이 남고 F 는 여전히 후보가 아니다."""
    serial = _emulator(phone)
    check = Check()
    b, f = _friends(run)
    crowd = people(2) + [(FRIEND, (f['phone'],))]
    with contacts.on_device(serial, crowd, True):
        _app(check, phone(token_hash=run.link(b['email']), names=[n for n, _ in crowd], pick_names=[FRIEND], rows=1, phase='block'), '차단')
        check.that(len(_blocks(run, b)) == 1, f'차단 뒤 contact_blocks {len(_blocks(run, b))}행(기대 1)')
        reinstall(serial)
        contacts.grant(serial)  # 다시 깔면 권한이 처음 상태 — 연락처 차단 줄이 8a 를 건너뛰고 16b 로 가게
        _app(check, phone(token_hash=run.link(b['email']), names=[n for n, _ in crowd], phase='after'), '다시 깐 뒤')
    check.that(len(_blocks(run, b)) == 1, f'다시 깐 뒤 contact_blocks {len(_blocks(run, b))}행(기대 1)')
    _mutually_excluded(check, run, b, f, '다시 깐 뒤 ')
    return check.result()


PHONE = {'E-SAFE-35': p_safe_35, 'E-SAFE-36': p_safe_36, 'E-SAFE-37': p_safe_37, 'E-SAFE-38': p_safe_38, 'E-SAFE-39': p_safe_39,
         'E-SAFE-40': p_safe_40, 'E-SAFE-41': p_safe_41, 'E-SAFE-42': p_safe_42, 'E-SAFE-43': p_safe_43, 'E-SAFE-45': p_safe_45,
         'E-SAFE-46': p_safe_46}

area1.PHONE.update(PHONE)
area1.BUNDLES['area3-contacts'] = list(PHONE)
