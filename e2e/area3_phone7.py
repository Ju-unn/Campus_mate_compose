"""영역 3 밤 가설 E-CHAT-34 · E-CHAT-42 · E-REV-18(묶음 area3-phone-7) — 영역 4 알림 밤 판(area4_push_night)의 E-PUSH-33 · 86 · 52 와 **같은 판**이라
새로 만들지 않고 별칭으로 등록만 한다(대장 10-05: 같은 판을 한 번만 돌리고 결과를 두 번호에 같이 적는다). 앱 쪽은 frontend/integration_test/area3_b7.dart(영역 4 밤 판과 같은 동작).

  E-CHAT-34 = E-PUSH-33  방해 금지가 켜져 있어도 새 메시지는 밤에 온다(단일 단계, 22:00~23:59)
  E-CHAT-42 = E-PUSH-86  신뢰 수락이 둘 다 끝나면 먼저 수락한 쪽만 아침에 "카카오톡 아이디를 주고받았어요"(밤 단계 + 아침 단계)
  E-REV-18  = E-PUSH-52  밤에 받은 지인 리뷰는 아침에 한 건으로(밤 단계 + 아침 단계)

같은 판을 두 번 돌지 않게 하는 것은 영역 4 쪽이 이미 한다 — 상태 파일(`night_<영역 4 번호>.json`)과 배치 뒤 fail 의 기억(`_FAILED`)이 **영역 4 번호** 로 열쇠가 걸려 있어서,
어느 번호로 부르든 같은 상태를 읽고 쓴다(밤 단계를 E-CHAT-42 로 하고 아침 단계를 E-PUSH-86 으로 해도 이어진다). 결과는 부른 번호로 진행 프로그램이 적고, 이 별칭이 영역 4 번호 줄을 한 번 더 적는다.
시간 초과(진행 프로그램이 던지는 CaseTimeout)로 끝나면 영역 4 번호 줄은 적히지 않는다 — 그때는 부른 번호의 blocked 줄만 있다.

E-CHAT-34/42·E-REV-18 과 E-PUSH-33/86/52 는 같은 판이라 한 밤에 한 번만 — area3-phone-7 과 area4-push-night-a 를 함께 돌리지 말 것(같은 --bundle 이면 night_86.json 이 덮이고,
폴더가 다르면 폰과 시 슬롯을 이중으로 씀). 코드로 막지는 않는다(영역 4 파일은 고치지 않는 원칙).

시나리오와 다르게 도는 것: E-CHAT-42 의 밤 "A·B 모두 0건" 은 코드와 다르다. 먼저 수락한 쪽에는 상대의 수락이 "새 메시지"(예외 종류)로 밤에도 온다(chat/router.py 의 _notify_message).
판정은 제목 "카카오톡 아이디를 주고받았어요" 만 센다. 같은 번호를 두 번 돌리지 않는다 — 아침 단계의 시(時) 슬롯은 영역 4 규칙(08~21시, hh:06~hh:48, 같은 시 둘째는 심기 전에 blocked)이 그대로다.
"""

from e2e import area1, area3, tools
from e2e import area4_push_night as night
from e2e.tools import Blocked

ALIAS = {'E-CHAT-34': 'E-PUSH-33', 'E-CHAT-42': 'E-PUSH-86', 'E-REV-18': 'E-PUSH-52'}  # 영역 3 번호 → 같은 판인 영역 4 번호


def _twin(mine, theirs):
    night.PHONE[theirs]  # 영역 4 가설이 없어지면 등록하는 순간 바로 터진다(부를 때는 다시 찾아 부른다)

    def run_as_twin(run, phone):
        try:
            result, note = night.PHONE[theirs](run, phone)
        except Blocked as e:
            result, note = 'blocked', str(e)
        run.record(theirs, result, f'{mine} 로 돌린 같은 판' + (f' — {note}' if note else ''))
        return result, note
    return run_as_twin


PHONE7 = {mine: _twin(mine, theirs) for mine, theirs in ALIAS.items()}

tools.CASE_LIMITS.update({mine: tools.CASE_LIMITS[theirs] for mine, theirs in ALIAS.items()})
area1.PHONE.update(PHONE7)
area3.BUNDLES['area3-phone-7'] = list(PHONE7)
