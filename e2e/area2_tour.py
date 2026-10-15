"""영역 2 앱 투어(pen 섹션 24 `vfrto`) — 소스 확인형 두 가설(묶음 area2-tour). 폰 없이 PC 만.

E2E 빌드는 투어 자동 시작을 끈다 — 하네스는 가설마다 새 계정을 만들어, 켜 두면 첫 홈마다 덮개가 떠 다른 가설을 막는다.
그래서 투어 자체는 기기에서 돌리지 않고 코드에서 확인한다(화면 동작 · 단계 이동 · 건너뛰기는 frontend/test/tour/ 위젯 시험).

E-HOME-34  E2E 진입점(frontend/integration_test/e2e_test.dart)이 app.main() 전에 `AppTourViewModel.autoStartEnabled = false` 를 둔다.
E-HOME-35  투어 단계(frontend/lib/tour/view/app_tour_steps.dart)가 6개이고 제목이 사용자 확정 문구 · 순서 그대로다.
"""

import re

from e2e import area1, tools
from e2e.area1 import Check
from e2e.tools import Blocked

ENTRY = tools.ROOT / 'frontend' / 'integration_test' / 'e2e_test.dart'
STEPS = tools.ROOT / 'frontend' / 'lib' / 'tour' / 'view' / 'app_tour_steps.dart'
OFF = 'AppTourViewModel.autoStartEnabled = false;'
MAIN = 'await app.main();'
# 사용자 확정 문구(대장 지시문 6단계) — 앱 문구가 바뀌면 여기와 함께 바꾼다.
TITLES = (
    '여기가 캠퍼스메이트의 시작이에요',
    '프로필부터 채워 보세요',
    '사람들과 이야기해요',
    '매주 월요일 오전 7시에 열려요',
    '하트로 여는 카드는 더 정밀해요',
    '하트는 무료로도 모아요',
)


def _read(path):
    if not path.exists():
        raise Blocked(f'{path.relative_to(tools.ROOT)} 가 없다 — 앱 쪽 모양이 바뀜')
    return path.read_text(encoding='utf-8')


def tour_off_problems(text):
    off, main = text.find(OFF), text.find(MAIN)
    if off == -1:
        return [f'E2E 진입점에 "{OFF}" 가 없다 — 새 계정마다 투어 덮개가 떠 가설이 막힌다']
    if main != -1 and off > main:
        return [f'"{OFF}" 가 "{MAIN}" 뒤에 있다 — 앱이 켜진 뒤라 첫 홈에서 이미 투어가 시작될 수 있다']
    return []


def steps_problems(text):
    titles = tuple(re.findall(r"title: '([^']+)'", text))
    return [] if titles == TITLES else [f'투어 제목 {titles} 가 확정 문구 {TITLES} 와 다르다']


def _result(problems):
    check = Check()
    for problem in problems:
        check.that(False, problem)
    return check.result()


def home_34(run):
    return _result(tour_off_problems(_read(ENTRY)))


def home_35(run):
    return _result(steps_problems(_read(STEPS)))


# 34 · 35 — 30 · 31 은 에뮬 대기 화면 가설(area2_emu_home.PHONE)이 먼저 썼다. 겹치면 once 가 API 쪽을 골라 그쪽이 안 돈다.
CASES = {'E-HOME-34': home_34, 'E-HOME-35': home_35}
area1.CASES.update(CASES)
area1.BUNDLES['area2-tour'] = list(CASES)
