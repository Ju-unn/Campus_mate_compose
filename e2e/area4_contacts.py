"""영역 4 SET-29~42 — 연락처 권한 · 연락처 차단 8a/8a-2/8d/16b. 기기 연락처를 넣고 빼야 해서 B에뮬(--device B)에서만 돈다.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area4_contacts.dart 의 같은 번호.

`python -m e2e run area4-contacts --device B`. 가설마다 연락처를 넣고 권한을 맞춘 채 앱을 켜고, 끝나면 연락처를 지우고 권한을 없는 상태로 되돌린다.
실폰(--device A)에서는 전부 blocked 다.

주의 — E-SET-40: 시나리오는 "기기에서 연락처를 지우면 16b 가 '이전에 차단한 연락처' 로 보인다" 인데, 앱은 이름표를 차단할 때 앱 파일에 저장하고
(contact_name_store.dart) 16b 는 그 파일만 읽는다(contact_block_list_view_model.dart load). 기기 연락처를 지워도 이름표는 남으므로
이 가설은 코드대로면 fail 이 나온다 — 시나리오 확인이 필요하다(이름표가 없는 줄은 앱 데이터를 지웠거나 API 로 막았을 때뿐, E-SAFE-46).
"""

import itertools
import random
import time

from e2e import area1, contacts, tools
from e2e.area1 import Check, _app, _rows, _signed_in
from e2e.area1_emu import _emulator


_SEQ = itertools.count(random.randint(1000, 9000) * 10000)


def _number():
    """순번으로 만든다 — 무작위면 201명 중 번호가 겹쳐 차단 행 수가 어긋날 수 있다."""
    n = next(_SEQ)
    return f'010-{n // 10000 % 10000:04d}-{n % 10000:04d}'


def people(count=3):
    """이름이 서로 다른 휴대전화 연락처 [count]명."""
    return [(f'지인{i + 1:03d}', (_number(),)) for i in range(count)]


def _blocks(run, account):
    return _rows(run, f"contact_blocks?owner_id=eq.{account['id']}&select=id")


def _dialog(allow):
    return lambda serial: (lambda said: contacts.tap_dialog(serial, allow))


def _count(expected, label):
    def judge(run, phone, check, account, crowd):
        got = len(_blocks(run, account))
        check.that(got == expected, f'{label}: contact_blocks {got}행(기대 {expected})')
    return judge


def _settings_on_top(run, phone, check, account, crowd):
    top = ''
    for _ in range(10):
        top = phone.top()
        if 'com.android.settings' in top:
            return
        time.sleep(1)
    check.that(False, f'맨 위 화면이 설정 앱이 아님: {top or "못 읽음"}')


def _scenario(crowd=None, granted=True, judge=None, midway=None, known_ok=False, **job):
    """연락처 [crowd]({이름, 번호들} 목록, 함수여도 됨)를 기기에 넣고 권한을 [granted] 로 맞춘 채 새 계정으로 앱을 한 번 켠다.
    [known_ok] 가설에서 앱이 pass 와 함께 `known`(시나리오 기대와 앱 동작이 다른 제품 결정의 설명)을 말하면, DB 판정까지 맞을 때 결과를 fail 이 아니라 `known` 으로 남긴다."""
    def case(run, phone):
        serial = _emulator(phone)
        check = Check()
        account, token = _signed_in(run, 'home')
        persons = crowd() if callable(crowd) else (crowd if crowd is not None else people())
        extra = {'names': [name for name, _ in persons], **job}
        with contacts.on_device(serial, persons, granted):
            said = phone(token_hash=token, midway=midway(serial) if midway else None, **extra)
            _app(check, said)
            if judge:
                judge(run, phone, check, account, persons)
        result = check.result()
        if known_ok and result[0] == 'pass' and said and said.get('known'):
            return 'known', said['known']
        return result
    return case


def _same_number():
    number = _number()
    return [('같은번호가', (number,)), ('같은번호나', ('+82 ' + number[1:],))]  # 010-1234-5678 / +82 10-1234-5678


def _delete_first(serial):
    return lambda said: contacts.delete_person(serial, 0)


PHONE = {
    'E-SET-29': _scenario(granted=False),
    'E-SET-30': _scenario(granted=False, midway=_dialog(True)),
    'E-SET-31': _scenario(granted=False, judge=_settings_on_top),
    'E-SET-32': _scenario(granted=False, midway=_dialog(False)),
    'E-SET-33': _scenario(),
    'E-SET-34': _scenario(judge=_count(0, '빈 목록')),
    'E-SET-35': _scenario(judge=_count(2, '2명'), pick=2),
    'E-SET-36': _scenario(),
    'E-SET-37': _scenario([('유선지인', ('02-123-4567',))], judge=_count(0, '유선 번호'), pick=1),
    'E-SET-38': _scenario(_same_number, judge=_count(1, '같은 번호 두 형식'), pick=2),
    'E-SET-39': _scenario(lambda: people(201), judge=_count(201, '201명'), pick='all'),
    'E-SET-40': _scenario(judge=_count(2, '지운 뒤에도 차단은 유지'), pick=2, midway=_delete_first, known_ok=True),
    'E-SET-41': _scenario(judge=_count(1, '해제 뒤'), pick=2),
    'E-SET-42': _scenario(judge=_count(3, '추가 뒤'), pick=2, add=1),
}

area1.PHONE.update(PHONE)
tools.CASE_LIMITS['E-SET-39'] = contacts.BIG_LIMIT  # 201명
area1.BUNDLES['area4-contacts'] = list(PHONE)
