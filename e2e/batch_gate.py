"""운영 배치(Cloud Scheduler job)를 손으로 부를 수 있는 시각 — 통합대장 안전 규칙(10-05). 시각은 서울.

  daily-cards  00:00~07:10 금지 · 월요일 하루 종일 금지(서울 지급일에 실사용자 카드가 더 나갈 수 있다)
  chat-gate    정각 ±5분 금지 · 같은 시(時)에 두 번 금지(예약 실행과 겹친다)
  cleanup      04:00 ±5분 금지

가장자리는 안전한 쪽(금지 끝 분까지 포함)으로 읽는다. 어긴 시각이면 [Blocked] — 결과는 fail 이 아니라 blocked 이고,
메모에 "언제 다시" 가 나온다. `area2._batch` 가 gcloud 를 부르기 전에 [check] 를 지난다.
"""

import tempfile
from datetime import datetime, timedelta
from pathlib import Path

from e2e.area1 import SEOUL
from e2e.tools import Blocked

WEEKDAY_NAMES = '월화수목금토일'
# 통과한 chat-gate 호출 시각(한 줄에 하나) — 묶음 폴더가 달라도, 프로그램을 다시 켜도 "같은 시 두 번" 을 막으려고 임시 폴더 한 곳에 둔다.
HISTORY = Path(tempfile.gettempdir()) / 'campus_mate_e2e_chat_gate_runs.jsonl'
_LOOK_AHEAD_MINUTES = 8 * 24 * 60  # 다음 열린 분을 찾는 한계 — 한 주 안에 반드시 열린다


def now_seoul():
    return datetime.now(SEOUL)


def _closed(job, t, ran):
    minutes = t.hour * 60 + t.minute
    if job == 'daily-cards':
        return t.weekday() == 0 or minutes <= 7 * 60 + 10
    if job == 'cleanup':
        return 3 * 60 + 55 <= minutes <= 4 * 60 + 5
    if job == 'chat-gate':
        return t.minute >= 55 or t.minute <= 5 or any((r.date(), r.hour) == (t.date(), t.hour) for r in ran)
    raise ValueError(f'{job} — 손으로 부르는 규칙이 없는 job(daily-cards · chat-gate · cleanup 만)')


def refusal(job, now, ran=()):
    """[now] 에 [job] 을 부르면 안 되면 "지금은 실행 금지 시간 — HH:MM 에 다시"(다른 날이면 요일까지), 괜찮으면 None.
    [ran] 은 chat-gate 를 앞서 부른 서울 시각들."""
    if not _closed(job, now, ran):
        return None
    t = now.replace(second=0, microsecond=0)
    for _ in range(_LOOK_AHEAD_MINUTES):
        t += timedelta(minutes=1)
        if not _closed(job, t, ran):
            break
    when = t.strftime('%H:%M') if t.date() == now.date() else f'{WEEKDAY_NAMES[t.weekday()]}요일 {t:%H:%M}'
    return f'지금은 실행 금지 시간 — {when} 에 다시'


def _ran():
    if not HISTORY.exists():
        return []
    return [datetime.fromisoformat(line) for line in HISTORY.read_text(encoding='utf-8').splitlines() if line.strip()]


def check(job):
    """지금 [job] 을 불러도 되면 돌아오고(chat-gate 면 기록), 아니면 [Blocked]."""
    now = now_seoul()
    said = refusal(job, now, _ran() if job == 'chat-gate' else ())
    if said:
        raise Blocked(said)
    if job == 'chat-gate':
        with HISTORY.open('a', encoding='utf-8') as f:
            f.write(now.isoformat() + '\n')
