"""별칭(area2_aliases · area3_batch)의 같은 폴더 방어 — 원본과 같은 배치가 두 번 나가지 않게.
별칭은 원본 번호 줄도 결과 폴더에 적는다. 그래서 그 폴더에 원본 줄이 이미 있으면 다른 실행이 원본을 돌렸다는 뜻이고, 별칭이 또 돌리면 운영 배치가 한 번 더 나간다.
"""

from e2e.tools import Blocked


def already_ran(run, mine, theirs):
    """원본 [theirs] 가 이 결과 폴더에 이미 기록돼 있으면 [Blocked] — 같은 배치를 두 번 부르지 않는다.
    단 그 줄을 **이 별칭([mine])이 직접 적었고 fail** 이면 (결과, 메모)를 돌려준다: 진행 프로그램(run_case)이 fail 을 한 번 더 부르는데, 그때 fail 을 blocked 로 덮지 않고
    첫 결과를 그대로 돌려줘 원본을 다시 부르지 않는다(원본의 `_FAILED` · `_PAID` 기억과 같은 일). 통과 · blocked 줄은 돌려주지 않는다 — 같은 폴더 재실행은 막힌다.
    없으면 None. 별칭이 적는 메모는 `'{mine} 로 돌린'` 으로 시작해야 한다."""
    last = next((r for r in reversed(run.records()) if r['case'] == theirs), None)
    if last is None:
        return None
    if last['result'] == 'fail' and last['note'].startswith(f'{mine} 로 돌린'):
        return last['result'], last['note']
    raise Blocked(f'{mine}: 원본 {theirs} 를 이 실행(같은 --bundle 폴더)에서 이미 돌렸다 — 같은 배치가 두 번 나가므로 안 돈다')
