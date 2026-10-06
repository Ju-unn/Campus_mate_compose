"""영역 3 배치 가설 E-BATCH-14 · 15 · 16 · 17 · 22 · 23 — 이미 있는 판의 별칭(묶음 area3-batch).
새 판을 만들지 않는다: 같은 일을 하는 기존 가설을 부르고 결과를 두 번호에 같이 적는다(area3_phone7 과 같은 방식, 대장 10-05).
  E-BATCH-14 = E-PUSH-40  리마인드는 24시간 창 안 · 아직 수락 안 한 사람에게만(폰)
  E-BATCH-15 = E-PUSH-46  같은 시간 안 chat-gate 두 번 → 리마인드 두 번(⚠ 알려진 한계. 손 호출 1번 + 예약 실행 1번)
  E-BATCH-16 = E-PUSH-44  밤이면 아침 8시 창으로 밀림(07시대엔 안 옴, 08시대엔 옴)
  E-BATCH-17 = E-PUSH-47  나간 방은 리마인드 안 감 — ⚠ 시나리오는 나감 · 정지 · 탈퇴 세 방이고 E-PUSH-47 은 "나감" 하나라 정지 · 탈퇴 방은 안 본다(메모에 남김)
  E-BATCH-22 = E-AUTH-12  기한 지난 재가입 제한 행은 지우고 infinity 행은 남김(정리 배치)
  E-BATCH-23 = E-HEART-22 검수 끝난 지 61일 인증샷은 지움 — 59일 · 검수 중이 남는 것은 E-HEART-23 이 본다(메모에 남김)
⚠ 별칭 묶음(area3-batch)과 원본(E-PUSH-40 · 46 · 44 · 47 · E-AUTH-12 · E-HEART-22)을 **한 실행에서 같이 돌리지 말 것** — 같은 배치가 두 번 나간다(chat-gate 는 같은 시 두 번 리마인드, cleanup 은 전역).
코드가 막는 것: 별칭은 같은 결과 폴더(--bundle)에 원본 기록이 이미 있으면 돌지 않고 blocked 로 끝난다(원본을 먼저 돌린 경우). 원본을 별칭 뒤에 돌리는 것은 원본 파일을 안 고치므로 못 막는다 — 별칭 뒤 원본 금지.
이 파일은 배치를 직접 부르지 않는다 — 부르는 것은 별칭이 가리키는 기존 가설뿐이고, 실행 시각 관문(batch_gate)도 그쪽이 그대로 지난다.
안 만든 것(못 함): 18 · 19 · 24(응답 본문의 칸 값 — 스케줄러 호출은 본문을 못 읽는다, 직접 POST 권한 필요) · 20(E-WD-11 · 12 와 같은 판 — 안전 담당 몫) ·
21(신고 3건 준비가 새로 필요 — 별도 작업) · 25(운영에서 저장소 삭제 실패를 못 냄) · 26(다음 날 gcloud logging read).
"""

from e2e import area1, area1_b2, area2_time_batch, area3, tools  # noqa: F401 — area1_b2 는 E-AUTH-12 를 area1.CASES 에 더한다
from e2e.area4_push_gate import PHONE as GATE_PHONE
from e2e.tools import Blocked

PHONE_ALIAS = {'E-BATCH-14': 'E-PUSH-40', 'E-BATCH-15': 'E-PUSH-46', 'E-BATCH-16': 'E-PUSH-44', 'E-BATCH-17': 'E-PUSH-47'}
API_ALIAS = {'E-BATCH-22': (area1, 'E-AUTH-12'), 'E-BATCH-23': (area2_time_batch, 'E-HEART-22')}  # 모듈의 attempt 로 부른다 — 배치를 부른 뒤 fail 은 다시 안 돈다(area2_time_batch._PAID)
NOTES = {'E-BATCH-17': '정지 · 탈퇴 방은 안 봄(나감만)', 'E-BATCH-23': '59일 · 검수 중 경계는 E-HEART-23 이 본다'}


def _noted(mine, note):
    return f'{mine} 로 돌린 같은 판' + (f' — {note}' if note else '') + (f' ⚠ {NOTES[mine]}' if mine in NOTES else '')


def _already_ran(run, mine, theirs):
    """원본이 이 결과 폴더에 이미 기록돼 있으면 [Blocked] — 같은 배치를 두 번 부르지 않는다."""
    if any(r['case'] == theirs for r in run.records()):
        raise Blocked(f'{mine}: 원본 {theirs} 를 이 실행(같은 --bundle 폴더)에서 이미 돌렸다 — 같은 배치가 두 번 나가므로 안 돈다')


def _twin(mine, theirs):
    def run_as_twin(run, phone):
        try:
            _already_ran(run, mine, theirs)
        except Blocked as e:
            return 'blocked', str(e)  # 원본 줄은 건드리지 않는다
        try:
            result, note = GATE_PHONE[theirs](run, phone)  # 없어지면 부를 때 바로 KeyError — 조용히 넘어가지 않는다
        except Blocked as e:
            result, note = 'blocked', str(e)
        run.record(theirs, result, _noted(mine, note))
        return result, _noted(mine, note)
    return run_as_twin


PHONE = {mine: _twin(mine, theirs) for mine, theirs in PHONE_ALIAS.items()}
tools.CASE_LIMITS.update({mine: tools.CASE_LIMITS.get(theirs, tools.CASE_LIMIT) for mine, theirs in PHONE_ALIAS.items()})
CASES = {mine: None for mine in API_ALIAS}  # __main__ 이 키만 본다 — 실제 함수는 attempt 가 고른다
area1.PHONE.update(PHONE)
area3.BUNDLES['area3-batch'] = [*PHONE, *CASES]


def attempt(run, case):
    """API 별칭 하나(22 · 23). 기존 가설을 그대로 부르고 결과를 그쪽 번호에도 적는다."""
    module, theirs = API_ALIAS[case]
    try:
        _already_ran(run, case, theirs)
    except Blocked as e:
        return 'blocked', str(e)
    result, note = module.attempt(run, theirs)  # attempt 는 Blocked 를 이미 ('blocked', 이유)로 바꾼다
    run.record(theirs, result, _noted(case, note))
    return result, _noted(case, note)
