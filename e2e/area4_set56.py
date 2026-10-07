"""영역 4 E-SET-56 — 설정 "지원" 카드의 이용약관 · 개인정보처리방침 줄(묶음 area4-set56). 앱 쪽은 frontend/integration_test/area4_set56.dart.
자동으로 보는 것: 줄 순서("자주 묻는 질문" → "이용약관" → "개인정보처리방침" → "로그아웃")와 두 줄을 누르면 맨 앞이 우리 앱이 아닌 다른 앱(기기 브라우저)이 되는지(dumpsys),
그리고 돌아왔을 때 설정 화면에 남아 있는지. 누르는 순간의 Intent 주소가 노션 약관 페이지인지는 dumpsys 에 남아 있으면 메모에 적는다(없어도 판정에 안 쓴다).
사람이 봐야 하는 것(결과 메모에 "사람 필요"): 기기 브라우저가 실제로 그 노션 페이지를 로그인 없이 보여 주는지 · 이용약관은 1부 위치 · 처리방침은 맨 위(1부 · 2부가 다 보임) · 3D 아이콘 모양.
"""

import time

from e2e import area1, tools
from e2e.area1 import Check, _app, _signed_in
from e2e.area4 import stepper
from e2e.tools import Blocked

PAGE = '3e9d998f0dee8082be84e126630b02a7'  # frontend/lib/consent/model/consent_links.dart 의 노션 페이지 id
FRONT_WAIT = 10  # 줄을 누른 뒤 맨 앞 앱이 바뀌기를 기다리는 시간(초)
HUMAN = '사람 필요: 기기 브라우저가 노션 약관 페이지를 로그인 없이 여는지 · 이용약관은 1부 위치 · 처리방침은 맨 위(1부 · 2부 모두 보임) · 3D 아이콘 모양은 눈으로'


def _front(serial):
    """앱을 다시 맨 앞으로 — 브라우저에 다녀온 뒤."""
    tools.adb(serial, 'shell', 'monkey', '-p', tools.PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')


def _intent_seen(serial):
    """dumpsys 에 노션 약관 페이지 주소가 남아 있는지(남아 있으면 True)."""
    return PAGE in (tools.adb(serial, 'shell', 'dumpsys', 'activity', 'activities', check=False) or '')


def p_set_56(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    seen = {}

    def opened(label):
        def handler(said):
            top = ''
            for _ in range(FRONT_WAIT):
                top = phone.top()
                if top and tools.PACKAGE not in top:
                    break
                time.sleep(1)
            check.that(bool(top) and tools.PACKAGE not in top, f'{label} 을 눌렀는데 맨 앞이 우리 앱 그대로(기기 브라우저가 안 뜸): {top or "못 읽음"}')
            seen[label] = _intent_seen(phone.serial)
            _front(phone.serial)
        return handler

    _app(check, phone(midway=stepper(phone, opened('이용약관'), opened('개인정보처리방침')), token_hash=token))
    if not all(seen.get(label) for label in ('이용약관', '개인정보처리방침')):
        found = [label for label, ok in seen.items() if ok]
        note = f'노션 주소는 dumpsys 에서 확인한 줄 {found or "없음"}(남아 있지 않아도 판정에 안 씀)'
    else:
        note = '노션 주소를 dumpsys 에서 두 줄 모두 확인'
    return check.result(f'{note}. {HUMAN}')


PHONE = {'E-SET-56': p_set_56}
area1.PHONE.update(PHONE)
area1.BUNDLES['area4-set56'] = list(PHONE)
tools.CASE_LIMITS['E-SET-56'] = 600
