"""영역 2 배치 운영 가설 — Cloud Scheduler 설정과 `/batch/*` 의 신원 확인만 본다(묶음 area2-batch-admin, 폰 없음).

배치를 **돌리는** 가설은 area2_time_batch · area3_phone5 · area4_push_card 가 맡는다. 여기서는 부르지 않는다 —
E-BATCH-01 은 gcloud 로 설정만 읽고, E-BATCH-02 는 틀린 신원으로 두드려 401 만 보고, E-BATCH-03 은 그 뒤에 새 카드가 안 생겼는지 본다.
기대값 근거: `backend/app/core/batch_auth.py` · `backend/DEPLOY.md` §4-3 · 세 `batch_router.py`.
"""

import datetime as dt
import json
import subprocess
from datetime import timedelta, timezone
from urllib.parse import urlsplit

from e2e import area2, area3, area3_phone5, tools
from e2e.area1 import SEOUL, Check, _patch, _rows
from e2e.tools import Blocked

LOCATION = 'asia-northeast3'  # 세 job 다 같은 지역(DEPLOY.md §4-3)
# job 이름 → (스케줄, 경로). 스케줄 · Asia/Seoul · OIDC 는 DEPLOY.md §4-3 · §정리 배치 그대로다.
JOBS = {
    'daily-cards': ('0 7 * * *', '/batch/daily-cards'),
    'chat-gate': ('0 * * * *', '/batch/chat-gate'),
    'cleanup': ('0 4 * * *', '/batch/cleanup'),
}
UNAUTHORIZED = 'unauthorized'  # errors.UNAUTHORIZED — batch_auth 가 401 에 실어 보내는 문구


def _describe(name):
    """job 하나의 설정(gcloud describe --format=json). 못 부르면 blocked — 이 판은 gcloud 없이는 아무것도 못 가린다."""
    # 문자열로 넘긴다 — shell=True 에 리스트를 주면 윈도만 되고 POSIX 에서는 첫 낱말만 실행된다(tools.batch 와 다른 점).
    command = f'gcloud scheduler jobs describe campus-mate-{name} --location={LOCATION} --format=json'
    try:
        out = subprocess.run(command, **tools.TEXT, check=True, shell=True).stdout  # 윈도는 gcloud 가 .cmd 라 shell 로 부른다
    except (subprocess.CalledProcessError, OSError) as e:
        raise Blocked(f'gcloud 를 못 부름({type(e).__name__}: {getattr(e, "stderr", "") or e}) — '
                      '설치 · 로그인 · 권한이 있어야 E-BATCH-01 을 볼 수 있다') from e
    try:
        return json.loads(out)
    except ValueError as e:
        raise Blocked(f'gcloud describe 출력이 JSON 이 아님: {out[:200]!r}') from e


def _probe(run, path, headers):
    """틀린 신원으로 `/batch/*` 한 번 — 한 번만 보낸다(401 이라 안전하지만 규칙대로 retry=False)."""
    return tools.call('POST', f"{run.cfg['API_BASE_URL']}{path}", headers, retry=False)


def _probes(run):
    """틀린 신원 넷. 문구(라벨) → 헤더. 넷 다 `batch_auth` 를 통과하면 안 된다 —
    마지막 둘은 특히 "옛 조각 4·5 의 공유 열쇠는 이제 죽었다" 를 가리는 자리다."""
    return {
        '헤더 없음': {},
        '쓰레기 베어러': {'Authorization': 'Bearer not-a-google-id-token'},
        # anon 키도 **진짜 서명된 JWT** 다 — 다만 구글이 서명한 ID 토큰이 아니라서 서명 검증에서 걸린다.
        '구글 밖 서명 토큰(anon 키)': {'Authorization': f"Bearer {run.cfg['SUPABASE_ANON_KEY']}"},
        '옛 공유 열쇠 헤더': {'X-Batch-Secret': 'card-batch-secret'},
    }


def _issued_since(run, since):
    """[since] 뒤에 발급된 daily_cards 수 — 셋 중 새 행을 만드는 배치가 이것뿐이라 이걸 센다."""
    return len(_rows(run, f'daily_cards?issued_at=gte.{since}&select=id'))


def batch_01(run):
    """E-BATCH-01 — 세 job 이 서울 시각 스케줄 · OIDC(ID 토큰) 로 서 있고 옛 공유 열쇠 헤더가 없다."""
    check = Check()
    for name, (schedule, path) in JOBS.items():
        job = _describe(name)
        http = job.get('httpTarget') or {}
        oidc = http.get('oidcToken') or {}
        audience = oidc.get('audience', '')
        headers = {k.lower() for k in (http.get('headers') or {})}

        check.that(job.get('schedule') == schedule, f'{name}: 스케줄 {job.get("schedule")!r}(기대 {schedule!r})')
        check.that(job.get('timeZone') == 'Asia/Seoul', f'{name}: timeZone {job.get("timeZone")!r}')
        check.that(http.get('httpMethod') == 'POST', f'{name}: httpMethod {http.get("httpMethod")!r}')
        check.that(http.get('uri', '').split('?')[0].endswith(path),
                   f'{name}: uri {http.get("uri")!r} 가 {path!r} 를 안 가리킴')
        check.that('x-batch-secret' not in headers,
                   f'{name}: 옛 공유 열쇠 헤더가 아직 붙어 있음 {sorted(headers)} — 지금 서버는 이 헤더를 안 본다')
        check.that(bool(oidc.get('serviceAccountEmail')),
                   f'{name}: oidcToken.serviceAccountEmail 없음 — 구글이 서명한 ID 토큰이 아니라 문이 안 열린다')
        # audience 는 **경로 없는** 서비스 URL 이어야 한다(DEPLOY.md:319). 경로가 섞이면 구글이 job 의 --uri 전체를
        # audience 로 삼아 서버의 BATCH_AUDIENCE 와 어긋나고, 정상 실행이 401 이 된다(E-BATCH-02 와 같은 문).
        check.that(audience and http.get('uri', '') == audience + path,
                   f'{name}: audience {audience!r} + {path!r} 가 uri {http.get("uri")!r} 와 다름 — audience 에 경로가 섞였다')
    return check.result('gcloud describe 로 설정만 읽음 — 배치는 안 돌렸다')


def batch_02(run):
    """E-BATCH-02 — 세 문 다 구글 ID 토큰만 받는다: 틀린 신원 넷 × 문 셋 = 12번 모두 401 unauthorized."""
    check = Check()
    for name, (_, path) in JOBS.items():
        for label, headers in _probes(run).items():
            check.reply(f'{name} ← {label}', _probe(run, path, headers), 401, detail=UNAUTHORIZED)
    return check.result('틀린 신원 넷(헤더 없음 · 쓰레기 토큰 · 구글 밖 서명 토큰 · 옛 공유 열쇠) × 문 셋')


def batch_03(run):
    """E-BATCH-03 — 401 로 막힌 문은 일을 안 한다: 두드린 뒤에도 새 daily_cards 가 0장이다."""
    check = Check()
    start = dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')  # `+` 는 주소줄에서 빈칸이 되어 PostgREST 가 400 을 준다
    if _issued_since(run, start):
        raise Blocked('두드리기 전인데 이미 새 daily_cards 가 있다 — 다른 창이 배치를 돌리는 중이라 이 판은 아무것도 못 가린다')
    for _, path in JOBS.values():
        for headers in _probes(run).values():
            _probe(run, path, headers)
    after = _issued_since(run, start)
    check.that(after == 0, f'401 로 막힌 뒤 daily_cards 가 {after}장 늘었다 — 문이 뚫렸거나 다른 창이 배치를 돌렸다')
    return check.result('daily-cards 만 셈 — 셋 중 새 행을 만드는 배치가 그것뿐이고 chat-gate · cleanup 의 쓰기 대상은 이 판이 안 본다')


def batch_11(run):
    """E-BATCH-11 — trust_passed_at 이 이미 찍힌 방은 다음 chat-gate 에서 다시 세지 않는다.

    이 대체 검사는 시나리오의 "PC POST 2번" 을 글자 그대로 하지 않는다 — 관문이 같은 시 두 번을 막는다.
    대신 첫 실행 뒤의 DB 상태(trust_passed_at 가 채워진 방)를 미리 만들고, chat-gate 한 번 뒤 값이 그대로인지 본다.
    동일한 `trust_passed_at is null` 조건이 다음 실행에서 이 방을 건너뛰게 하는 핵심인 `pass_trust_gate`(:196-201) 를 본다.
    """
    check = Check()
    batch_gate = area3_phone5.batch_gate
    batch_gate.peek('chat-gate', ahead=area3_phone5.PREP_MINUTES)
    account_a, account_b, match_id = area3._pair(run)
    area2._guard(run, account_a['id'], account_b['id'])
    sentinel_a, sentinel_b, sentinel_id = area3_phone5._sentinel(run)
    area2._guard(run, sentinel_a['id'], sentinel_b['id'])

    now = dt.datetime.now(timezone.utc)
    stamp = now.isoformat().replace('+00:00', 'Z')
    _patch(run, f'match_participants?match_id=eq.{match_id}',
           {'trust_response': 'accept', 'responded_at': stamp})
    # 두 사람의 accept 는 준비하되, 매칭은 이미 통과한 상태로 둬서 다음 chat-gate 에서 건너뛰는지 본다.
    _patch(run, f'matches?id=eq.{match_id}', {'trust_passed_at': stamp})
    before = _rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at,chat_closed_at')
    if len(before) != 1 or not before[0].get('trust_passed_at') or before[0].get('chat_closed_at'):
        raise Blocked(f'기준 방 준비 실패: {before!r}')

    # area3_phone5._gated_batch 는 관문을 지난 다음 기준 방과 sentinel 시각을 확정하고, gcloud 를 한 번만 부른다.
    area3_phone5._gated_batch(run, [account_a, account_b], [(match_id, timedelta(hours=50))],
                              (sentinel_a, sentinel_b, sentinel_id))
    after = _rows(run, f'matches?id=eq.{match_id}&select=trust_passed_at,chat_closed_at')
    check.that(len(after) == 1 and after[0].get('trust_passed_at') == before[0]['trust_passed_at'],
               f"이미 찍힌 방의 trust_passed_at 이 바뀜: 전 {before[0].get('trust_passed_at')!r} 후 {after!r}")
    check.that(len(after) == 1 and after[0].get('chat_closed_at') is None,
               f'이미 통과한 방이 닫힘: {after!r}')
    return check.result('DB 기준점 대체 — trust_passed_at 이 이미 있는 방을 한 번의 chat-gate 가 건너뜀. '
                        '시나리오의 "두 번째 POST" 자체는 아님; 두 번째 호출은 같은 시 관문이 막는다.')


# ── E-BATCH-26 — 지난 하루 예약 실행이 전부 200 ─────────────────────────────────────────────────────────

SCHEDULER_AGENT = 'Google-Cloud-Scheduler'  # 예약 실행의 User-Agent — E-BATCH-02 가 틀린 신원으로 두드린 401 은 이 이름이 아니라 세지 않는다
LOG_WINDOW = timedelta(hours=24)
LOG_GRACE = timedelta(minutes=10)  # 방금 지난 예약 시각은 아직 로그가 안 올라왔을 수 있어 이만큼 지난 것부터 센다
LOG_SLOT = timedelta(minutes=10)   # 예약 시각 뒤 이 안에 찍힌 줄을 그 칸의 실행으로 본다
LOG_FILTER = f"resource.type='cloud_run_revision' AND httpRequest.requestUrl:'/batch/' AND httpRequest.userAgent:'{SCHEDULER_AGENT}'"
# 따옴표는 홑따옴표만 — 윈도 gcloud 는 .cmd 라 shell 로 부르는데 큰따옴표 · % 가 섞이면 깨진다.


def _now():
    return dt.datetime.now(SEOUL)


def _gcloud(args, what, hide=''):
    """읽기 전용 gcloud 한 번. 못 부르거나 권한이 없으면 blocked — 이 판은 로그를 못 읽으면 아무것도 못 가린다."""
    command = subprocess.list2cmdline(['gcloud', *args])  # 문자열로 넘긴다(_describe 와 같은 이유)
    try:
        return subprocess.run(command, **tools.TEXT, check=True, shell=True).stdout
    except (subprocess.CalledProcessError, OSError) as e:
        why = (getattr(e, 'stderr', '') or str(e)).strip()[:300]
        raise Blocked(f'{what} 을(를) gcloud 로 못 읽음({type(e).__name__}: {why.replace(hide, "<프로젝트>") if hide else why}) — '
                      '설치 · 로그인 · 로그 읽기 권한(logging.logEntries.list)이 있어야 E-BATCH-26 을 볼 수 있다') from e


def _project():
    """gcloud 설정의 프로젝트 — 코드 · 메모에 식별자를 적지 않는다."""
    project = _gcloud(['config', 'get-value', 'project'], 'gcloud 프로젝트 설정').strip()
    if not project or project == '(unset)':
        raise Blocked('gcloud 설정에 프로젝트가 없다(gcloud config set project …)')
    return project


def _scheduler_requests(now):
    """지난 하루 `/batch/*` 예약 실행 줄 → [(시각(서울), 경로, 상태)]. 읽기만 한다."""
    project = _project()
    out = _gcloud(['logging', 'read', LOG_FILTER, f'--project={project}', '--freshness=2d', '--limit=1000', '--format=json'], '로그', hide=project)
    try:
        entries = json.loads(out or '[]')
    except ValueError as e:
        raise Blocked(f'gcloud logging read 출력이 JSON 이 아님: {out[:200]!r}') from e
    rows = []
    for entry in entries:
        http = entry.get('httpRequest') or {}
        stamp = entry.get('timestamp') or entry.get('receiveTimestamp')
        if not stamp or not http.get('requestUrl'):
            continue
        rows.append((dt.datetime.fromisoformat(stamp.replace('Z', '+00:00')).astimezone(SEOUL),
                     urlsplit(http['requestUrl']).path, int(http.get('status') or 0)))
    return rows


def _slots(now):
    """지난 하루(끝은 [LOG_GRACE] 전까지)에 있어야 하는 예약 시각 → {job: [서울 시각]}. 스케줄은 [JOBS] 와 같다."""
    start, end = now - LOG_WINDOW, now - LOG_GRACE
    slots = {name: [] for name in JOBS}
    t = start.replace(minute=0, second=0, microsecond=0)
    while t <= end:
        if t >= start:
            slots['chat-gate'].append(t)
            if t.hour == 4:
                slots['cleanup'].append(t)
            if t.hour == 7:
                slots['daily-cards'].append(t)
        t += timedelta(hours=1)
    return slots


def judge_scheduled_runs(rows, now):
    """예약 실행 줄들이 스케줄대로 있고 전부 200 인지 → (문제 목록, 한 줄 요약). 예약 칸마다 200 이 한 건 이상, 지난 하루 안의 비-200 은 0건.
    손으로 부른 실행(gcloud scheduler jobs run)도 같은 User-Agent 라 칸 밖에 있는 줄은 200 이면 그냥 둔다."""
    problems, summary = [], []
    since = now - LOG_WINDOW
    for name, slots in _slots(now).items():
        path = JOBS[name][1]
        mine = [(at, status) for at, p, status in rows if p == path and at >= since]
        bad = sorted(f'{at:%m-%d %H:%M} {status}' for at, status in mine if status != 200)
        if bad:
            problems.append(f'{name}: 200 이 아닌 예약 실행 {len(bad)}건({", ".join(bad[:5])})')
        missing = [slot for slot in slots if not any(slot <= at < slot + LOG_SLOT and status == 200 for at, status in mine)]
        if missing:
            problems.append(f'{name}: 200 이 없는 칸 {len(missing)}/{len(slots)}개({", ".join(f"{m:%m-%d %H:%M}" for m in missing[:5])})')
        summary.append(f'{name} {len(slots) - len(missing)}/{len(slots)}')
    return problems, ' · '.join(summary)


def batch_26(run):
    """E-BATCH-26 — 예약 실행이 200 으로 돌았다: 지난 하루 cleanup(04시) 1 · daily-cards(07시) 1 · chat-gate(매시) 24 가 전부 200. 로그 읽기만 한다."""
    check = Check()
    now = _now()
    problems, summary = judge_scheduled_runs(_scheduler_requests(now), now)
    for problem in problems:
        check.that(False, problem)
    return check.result(f'Cloud Run 요청 로그를 gcloud 로 읽기만 함(예약 실행 줄만) — 200 이 있는 칸: {summary}')


CASES = {'E-BATCH-01': batch_01, 'E-BATCH-02': batch_02, 'E-BATCH-03': batch_03,
         'E-BATCH-11': batch_11, 'E-BATCH-26': batch_26}
BUNDLES = {'area2-batch-admin': list(CASES)}


def attempt(run, case):
    """가설 하나 — 준비가 안 되면 blocked, 끊김은 처음부터 한 번 더(area2.attempt_with)."""
    return area2.attempt_with(run, CASES[case])
