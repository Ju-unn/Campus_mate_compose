"""영역 2 별칭 9개 — 시나리오 번호만 다르고 같은 판인 가설을, 이미 있는 판에 이름만 더 달아 등록한다(새 판 없음).

폰 5개(area1.PHONE): E-CARD-40 · 43 · 46 · 48 = E-PUSH-10 · 13 · 18 · 22(수락 알림 · "받은 수락" 끔 · 매칭 알림 · "매칭 성립" 끔),
                     E-BATCH-09 = E-CARD-13(후보를 다 쉬게 한 뒤 배치 → 카드 0 · 오늘 탭 11b).
배치 4개(API):       E-BATCH-05 · 06 · 07 · 08 = E-CARD-04 · 09 · 08 · 11(area2_time_batch.attempt 에 맡긴다).

불러 준 번호와 원본 번호 둘 다 results 에 적는다(area3_phone7 과 같다). 그래서:
- 별칭 묶음 `area2-alias` 와 원본(E-CARD-13 · 04 · 08 · 09 · 11 · E-PUSH-10 · 13 · 18 · 22)을 **같은 실행에서 함께 돌리지 않는다** —
  배치를 부르는 판이라 별칭이 이미 돌려 놓은 걸 원본이 또 부른다. 배치 4개는 area2_time_batch 가 같은 실행 안에서는 한 번만 부르게 막지만,
  폰 별칭(E-BATCH-09 ↔ E-CARD-13)은 막지 못한다.
- E-BATCH-08 은 E-CARD-11 과 **같지 않다** — 시나리오는 "멈춘 사람 · 14일 · 결정 안 한 카드가 남은 사람 · 자동 가림 · 아직 안 열린 학교" 다섯인데
  card_11 은 정지 · 일시중지 · 14일 · 벡터 없음 · 자동 가림 · 학교 미개방을 보고, "결정 안 한 카드" 는 E-CARD-05 가 본다. 가장 가까운 판일 뿐이다.
- E-BATCH-05~09 의 응답 본문(`issued` · `skipped_regions` · `no_candidate`)은 못 읽는다 — 배치를 `gcloud scheduler jobs run` 으로 불러 stdout 이 없다.
  원본이 보는 DB 행 · /cards/today · 앱 화면으로만 판정한다.
못 하는 것: E-BATCH-04(기대값이 응답 본문 그 자체) · E-BATCH-10/12/13(직접 POST 2번이라 IAM tokenCreator 가 필요하고 chat-gate 관문은 같은 시 두 번을 막는다).
"""

from e2e import area1, area2_time_batch, tools
from e2e import area2_time_device, area4_push  # noqa: F401 — 원본 폰 판(E-CARD-13 · E-PUSH-10 · 13 · 18 · 22)이 area1.PHONE 에 먼저 올라 있어야 한다
from e2e.tools import Blocked

PHONE_ALIAS = {'E-CARD-40': 'E-PUSH-10', 'E-CARD-43': 'E-PUSH-13', 'E-CARD-46': 'E-PUSH-18', 'E-CARD-48': 'E-PUSH-22',
               'E-BATCH-09': 'E-CARD-13'}
BATCH_ALIAS = {'E-BATCH-05': 'E-CARD-04', 'E-BATCH-06': 'E-CARD-09', 'E-BATCH-07': 'E-CARD-08', 'E-BATCH-08': 'E-CARD-11'}


def _note(mine, note):
    return f'{mine} 로 돌린 같은 판' + (f' — {note}' if note else '')


def _twin(mine, theirs):
    source = area1.PHONE[theirs]  # 원본이 먼저 등록돼 있어야 한다 — 없으면 import 때 바로 KeyError

    def run_as_twin(run, phone):
        try:
            result, note = source(run, phone)
        except Blocked as e:
            result, note = 'blocked', str(e)  # CaseTimeout 은 일부러 안 잡는다 — 시간 초과는 진행 프로그램이 처리한다
        run.record(theirs, result, _note(mine, note))
        return result, note

    return run_as_twin


PHONE = {mine: _twin(mine, theirs) for mine, theirs in PHONE_ALIAS.items()}
area1.PHONE.update(PHONE)

CASES = dict(BATCH_ALIAS)  # API case → 원본 case — __main__.API_CASES 가 이 모듈의 attempt 로 보낸다
BUNDLES = {'area2-alias': [*PHONE, *CASES]}
tools.CASE_LIMITS.update({mine: tools.CASE_LIMITS[theirs]
                          for mine, theirs in {**PHONE_ALIAS, **BATCH_ALIAS}.items() if theirs in tools.CASE_LIMITS})


def attempt(run, case):
    """배치 별칭 하나 — 원본을 area2_time_batch.attempt 로 돌리고(배치는 거기서 한 번만 나간다) 원본 번호로도 적는다."""
    result, note = area2_time_batch.attempt(run, BATCH_ALIAS[case])
    run.record(BATCH_ALIAS[case], result, _note(case, note))
    return result, note
