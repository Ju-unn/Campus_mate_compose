# 관리자 웹 서버 상태 · 메뉴 숫자 배지 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자 웹에 "서버 상태" 화면(수동 새로고침)과 왼쪽 메뉴 빨간 숫자 배지(서버 새 이상 · 인증샷 검수 · 졸업생 · 신고 · 문의)를 단다.

**Architecture:** 서버(FastAPI)가 Cloud Monitoring REST API 를 읽어 5분 칸 3시간치 숫자와 이상 목록을 만들어 `GET /admin/server-status` 로 준다(저장 없음). 대기 건수는 `GET /admin/pending-counts`. 관리자 웹(Flutter 웹)은 처음 열 때 · [새로고침] 때만 둘을 읽고, 서버 이상 "확인" 시각은 브라우저 localStorage 에 둔다.

**Tech Stack:** FastAPI · httpx · google-auth(ADC) / Flutter 웹 · Riverpod · `dart:js_interop`

**Spec:** `docs/superpowers/specs/2026-11-17-admin-server-status-design.md`

## Global Constraints
- 자동 새로고침 · 타이머 · 주기 호출 금지. 읽기는 첫 진입 · [새로고침] 버튼 · 메뉴 이동(대기 건수만) 때만.
- 새 DB 표 · 마이그레이션 금지. 운영 DB 쓰기 없음.
- 코드 · 테스트 · 문서에 GCP 프로젝트 id · 서비스 계정 이메일 금지 — `settings.google_cloud_project` 사용. 서비스 이름 `campus-mate-backend` 는 이미 공개 문서(DEPLOY.md)에 있어 상수로 둔다.
- `backend/app/core/errors.py` 문구 변경 금지. 구글 읽기 실패는 `HTTPException(503, detail=errors.AUTH_UNAVAILABLE)`(문구 "잠시 후 다시 시도해 주세요").
- 화면 글자는 쉬운 우리말, 앱 띄어쓰기 규칙. 값은 pen A11 · SideNav 배지 시안(대장이 값표를 Task 4 · 5 에 붙인다).
- (사용자 11-17 「한번에 불러오지 말고 최적화, 보안 신경, 기존 문제없는지 확인」) 건수는 행을 가져오지 않고 Content-Range 건수로만 센다. 구글 숫자는 서버가 60초 저장해 두고 그 안의 새로고침은 저장본을 준다(여러 번 눌러도 구글 호출은 1분에 한 번). 화면의 무거운 읽기(서버 상태)는 그 화면 · 배지에 필요한 한 번뿐. 두 API 모두 `get_admin_caller` 로 관리자만, 응답에 프로젝트 id · 주소 · 구글 오류 본문을 싣지 않는다. 각 Task 끝에 기존 시험 전체(backend `uv run pytest -q` 차례 규칙 · admin_web `flutter test`)를 다시 돌려 기존 기능이 그대로인지 확인한다.
- 커밋 · PR 에 도구 표식(Co-Authored-By · Generated with · 🤖) 금지. 커밋은 campus-git 이 의미 단위로.

## Review Focus
1. 구글 숫자가 비어 있는 칸(요청 0 · 데이터 없음) — 그래프 0, 응답 속도 `null` → 화면 "—", 이상 아님. (Task 1 `test_empty_buckets_are_not_anomalies`)
2. 한산할 때 아바타 요청 하나(25초)가 낀 칸 — `slow` 로 잡히면 안 된다(요청 < 20). (Task 1 `test_lone_slow_request_is_not_slow`)
3. 구글 403 · 시간 초과 — 503 + 화면 오류 줄과 [다시 시도], 배지는 이전 값 유지 없이 숨김. (Task 1 `test_monitoring_failure_is_503`, Task 5 `server status error shows retry`)
4. localStorage 가 막힌 브라우저(사생활 모드) — 확인 시각을 못 읽어도 화면이 뜨고 배지는 창 안 이상 전체 수. (Task 4 `confirm store survives storage errors`)
5. 대기 건수 100 이상 · 0 — "99+" · 배지 숨김. (Task 4 `badge caps at 99+ and hides at 0`)

---

### Task 0: 기존 관리자 읽기 점검(읽기 전용, 대장 · 검토 담당)
- [ ] 관리자 서버 `GET` 라우트 전부에서 한계 없이 행을 다 읽는 곳(limit 없음 · 상한 없는 rpc), 관리자 웹에서 한 화면에 목록을 통째로 받는 곳을 찾아 표로 보고. 고치는 건 이 계획 밖 — 사용자에게 보여 주고 따로 정한다.

### Task 1: 서버 — `GET /admin/server-status`

**Files:**
- Create: `backend/app/admin/monitoring.py` (구글 읽기 + 칸 합치기 + 이상 판정)
- Create: `backend/app/admin/server_status.py` (라우터)
- Modify: `backend/app/admin/router.py` (include_router)
- Test: `backend/tests/admin/test_admin_server_status.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) Bucket(start: datetime, requests: int, errors_5xx: int, p50_ms: int | None, p95_ms: int | None, instances: int | None)`
  - `@dataclass(frozen=True) Anomaly(at: datetime, kind: Literal["errors", "error_rate", "slow"], value: float)`
  - `find_anomalies(buckets: list[Bucket]) -> list[Anomaly]` — 최신 순.
  - `summarize_now(buckets: list[Bucket]) -> dict` — 마지막 3칸(15분): `requests_per_min`(float, 소수 1자리), `error_rate`(0~1, 요청 0 이면 0), `p50_ms` · `p95_ms`(마지막 3칸 중 값 있는 가장 최근 칸, 없으면 None), `instances`(최근 값 있는 칸, 없으면 None).
  - `class MonitoringReader(client: httpx.AsyncClient, project: str, access_token: Callable[[], Awaitable[str]] = _monitoring_token)` · `async fetch_buckets(end: datetime) -> list[Bucket]` — 36칸, 오래된 순, 빈 칸도 채움(requests 0 · 나머지 None).
  - 의존성 `get_monitoring_reader(caller) -> MonitoringReader` (시험은 `app.dependency_overrides` 로 가짜를 끼운다).
  - 응답 JSON: `{"checked_at": iso, "bucket_minutes": 5, "buckets": [{"start", "requests", "errors_5xx", "p50_ms", "p95_ms", "instances"}], "now": {...summarize_now}, "anomalies": [{"at", "kind", "value"}]}`

상수(파일 위쪽): `CACHE_SECONDS = 60`(모듈 저장본, 인스턴스마다 따로 — shortcut 주석), `SERVICE = "campus-mate-backend"`, `WINDOW_MINUTES = 180`, `BUCKET_MINUTES = 5`, `ERRORS_MIN = 3`, `RATE_MIN_REQUESTS = 20`, `ERROR_RATE = 0.05`, `SLOW_P50_MS = 1000`.

구글 질의(`GET https://monitoring.googleapis.com/v3/projects/{project}/timeSeries`, 4개를 `asyncio.gather`, scope `https://www.googleapis.com/auth/monitoring.read`, 공통 filter `resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend"`, `aggregation.alignmentPeriod=300s`):
| 값 | metric.type | perSeriesAligner | crossSeriesReducer | groupByFields |
|---|---|---|---|---|
| 요청 · 5xx | `run.googleapis.com/request_count` | `ALIGN_DELTA` | `REDUCE_SUM` | `metric.labels.response_code_class` |
| p50 | `run.googleapis.com/request_latencies` | `ALIGN_DELTA` | `REDUCE_PERCENTILE_50` | — |
| p95 | `run.googleapis.com/request_latencies` | `ALIGN_DELTA` | `REDUCE_PERCENTILE_95` | — |
| 서버 수 | `run.googleapis.com/container/instance_count` | `ALIGN_MAX` | `REDUCE_SUM` | — |

토큰은 `billing/play.py` 의 `_adc_access_token` 과 같은 방식(모듈 전역 자격, `asyncio.to_thread` 로 default · refresh)으로 `_monitoring_token` 을 둔다. 점의 `interval.endTime` 을 칸 끝으로 보고 `start = end - 5분` 칸에 넣는다.

- [ ] **Step 1: 실패하는 시험 쓰기** — `test_admin_server_status.py`:
  - `test_errors_bucket_is_anomaly`: 칸 하나 requests 5 · errors_5xx 3 → `[Anomaly(kind="errors", value=3)]`.
  - `test_error_rate_needs_20_requests`: requests 19 · 5xx 2 → 없음; requests 40 · 5xx 2 → `error_rate` value 0.05.
  - `test_lone_slow_request_is_not_slow`: requests 3 · p50 25000 → 없음; requests 30 · p50 1200 → `slow` value 1200.
  - `test_empty_buckets_are_not_anomalies`: 36칸 모두 requests 0 · None → `[]`, `summarize_now` → `requests_per_min 0.0`, `error_rate 0`, `p50_ms None`.
  - `test_anomalies_newest_first`.
  - `test_fetch_buckets_maps_points`: `httpx.MockTransport` 로 4개 응답(요청 2xx 10 · 5xx 1 이 같은 칸, p50 120.4, p95 900, instances 2) → 그 칸 `Bucket(requests=11, errors_5xx=1, p50_ms=120, p95_ms=900, instances=2)`, 질의 params 에 위 filter · aligner 가 들어갔는지 확인. 토큰은 가짜 함수.
  - `test_server_status_route_shape`: 가짜 reader 로 `GET /admin/server-status` → 200, 키 `checked_at, bucket_minutes, buckets, now, anomalies`, buckets 36.
  - `test_monitoring_failure_is_503`: reader 가 `httpx.HTTPStatusError`(403) → 503, detail "잠시 후 다시 시도해 주세요"; `httpx.TimeoutException` 도 503.
  - `test_cached_within_60s`: 가짜 시계로 같은 분 안 두 번 부르면 reader 호출 1회, 61초 뒤엔 2회. 실패한 읽기는 저장하지 않는다.
  - `test_server_status_needs_admin`: 관리자 아님 → 기존 관리자 시험과 같은 거절 코드(`test_admin_health.py` 참고).
- [ ] **Step 2: 실행해 실패 확인** — `cd backend && uv run pytest tests/admin/test_admin_server_status.py -q` → import 오류로 FAIL.
- [ ] **Step 3: 구현** — 위 Interfaces · 상수 · 질의표대로 `monitoring.py` · `server_status.py`, `router.py` 에 include. 실패 로그는 `logger.warning("구글 모니터링 읽기 실패 %s", type(exc).__name__)` 만(주소 · 토큰 안 남김).
- [ ] **Step 4: 통과 확인** — 같은 명령 PASS, 이어서 `uv run pytest tests/admin -q` 전체 PASS, `uv run ruff check app/admin`.
- [ ] **Step 5: 커밋 단위 표시** — "서버 상태 읽기 API".

### Task 2: 서버 — `GET /admin/pending-counts`

**Files:**
- Modify: `backend/app/admin/stats.py` (라우트 추가), `backend/app/admin/stats_repository.py` (`count_pending_graduates`, `count_open_inquiries`)
- Test: `backend/tests/admin/test_admin_stats.py`

**Interfaces:**
- Produces: 응답 `{"heart_tasks": int, "graduates": int, "reports": int, "inquiries": int}`.
- `heart_tasks` = 기존 `overview()` 의 `pending_proofs`, `reports` = `open_reports`. `graduates` = `graduate_verification_requests` `status=eq.pending` 건수, `inquiries` = `inquiries` `status=in.(new,in_progress)` 건수. 건수는 `user_repository.py` `_count` 와 같은 Content-Range 방식(공통으로 쓰려면 `_count` 를 `AdminRepository` 로 올린다 — 옮기면 `AdminUserRepository` 는 상속으로 그대로 쓴다). 셋은 `asyncio.gather`.

- [ ] **Step 1: 실패하는 시험** — `test_pending_counts_shape`(overview 가짜 pending_proofs 2 · open_reports 3, 졸업생 Content-Range `0-0/1`, 문의 `0-0/4` → `{"heart_tasks": 2, "graduates": 1, "reports": 3, "inquiries": 4}`, 문의 요청 params `status=in.(new,in_progress)` 확인), `test_pending_counts_zero`(Content-Range `*/0` → 0), `test_pending_counts_needs_admin`. 가짜 세계는 `stats_world.py` 문법을 따른다.
- [ ] **Step 2: FAIL 확인** — `uv run pytest tests/admin/test_admin_stats.py -q`.
- [ ] **Step 3: 구현.**
- [ ] **Step 4: PASS 확인** — 같은 명령 + `uv run pytest tests/admin -q` + `uv run pytest -q`(전체, 차례 규칙 지킴).
- [ ] **Step 5: 커밋 단위 표시** — "메뉴 대기 건수 API".

### Task 3: 관리자 웹 — API 모델 · 호출

**Files:**
- Create: `admin_web/lib/server_status/server_status_models.dart`
- Modify: `admin_web/lib/api/admin_api.dart`
- Test: `admin_web/test/api/server_status_api_test.dart`

**Interfaces:**
- Produces:
  - `class StatusBucket { DateTime start; int requests; int errors5xx; int? p50Ms; int? p95Ms; int? instances; }`
  - `enum AnomalyKind { errors, errorRate, slow }` (서버 `errors` · `error_rate` · `slow`; 모르는 값은 그 줄을 버린다)
  - `class StatusAnomaly { DateTime at; AnomalyKind kind; double value; }`
  - `class StatusNow { double requestsPerMin; double errorRate; int? p50Ms; int? p95Ms; int? instances; }`
  - `class ServerStatus { DateTime checkedAt; List<StatusBucket> buckets; StatusNow now; List<StatusAnomaly> anomalies; }` 각 `fromJson`.
  - `class PendingCounts { int heartTasks; int graduates; int reports; int inquiries; }` + `fromJson`.
  - `AdminApi.serverStatus() -> Future<ServerStatus>`(`GET /admin/server-status`), `AdminApi.pendingCounts() -> Future<PendingCounts>`(`GET /admin/pending-counts`) — 기존 `health()` 와 같은 `_read` 방식.

- [ ] **Step 1: 실패하는 시험** — MockClient 로 두 응답을 주고 필드 값 확인, `kind: "unknown"` 줄은 버려지는지, `p50_ms: null` → `null`.
- [ ] **Step 2: FAIL 확인** — `cd admin_web && flutter test test/api/server_status_api_test.dart`.
- [ ] **Step 3: 구현.**
- [ ] **Step 4: PASS 확인.**
- [ ] **Step 5: 커밋 단위 표시** — "관리자 웹 서버 상태 · 대기 건수 모델".

### Task 4: 관리자 웹 — 메뉴 배지

**Files:**
- Create: `admin_web/lib/widgets/count_badge.dart`, `admin_web/lib/shell/nav_badges.dart`, `admin_web/lib/platform/confirm_store.dart` (+ `_web.dart` · `_stub.dart`, `page_reload` 와 같은 조건부 import)
- Modify: `admin_web/lib/widgets/side_nav.dart`, `admin_web/lib/shell/admin_shell.dart`, `admin_web/lib/shell/admin_section.dart`(`serverStatus('/server-status', '서버 상태', LucideIcons.activity)` 를 `actions` 바로 앞에 — 배지가 이 항목을 쓴다), 메뉴 개수 · 순서를 세는 기존 시험(`test/router/admin_section_title_test.dart`, `test/router/w4_routes_test.dart`, `test/app_flow_test.dart`)
- Test: `admin_web/test/widgets/count_badge_test.dart`, `admin_web/test/shell/nav_badges_test.dart`

**Interfaces:**
- Consumes: Task 3 `ServerStatus`, `PendingCounts`, `AdminApi.serverStatus/pendingCounts`.
- Produces:
  - `CountBadge({required int count})` — 0 이하 `SizedBox.shrink()`, 100 이상 "99+". 값은 pen 배지 값표.
  - `ConfirmStore { DateTime? read(); void write(DateTime at); }` — 키 `cm_admin_server_confirmed_at`, ISO 문자열. 읽기 · 쓰기 예외는 삼키고 `null` / 무시.
  - `serverStatusProvider` — `NotifierProvider.autoDispose`가 아니라 **keepAlive** `Notifier<AsyncValue<ServerStatus>>`(셸 배지와 화면이 같은 값을 쓴다), 메서드 `refresh()`. 첫 watch 때 한 번 읽고, 그 뒤엔 `refresh()` 때만.
  - `pendingCountsProvider` — keepAlive `Notifier<AsyncValue<PendingCounts>>`, `refresh()`. 셸이 메뉴 이동(위치 바뀜) 때 `refresh()`.
  - `serverConfirmedAtProvider` — `Notifier<DateTime?>`, `confirmNow(DateTime now)` 가 store 에 쓰고 상태 갱신.
  - `navBadgeCounts(AdminSection) -> int` 계산: 서버 상태 = `anomalies.where(at > confirmedAt).length`(confirmedAt null 이면 전체), 인증샷 검수 · 졸업생 · 신고 · 문의 = 대기 건수, 그 밖 0. 읽기 실패 · 로딩 = 0(숨김).
  - `SideNav` 에 `badgeOf: int Function(AdminSection)` 인자(기본 `(_) => 0`) — `_NavItem` 오른쪽 끝에 `CountBadge`.

- [ ] **Step 1: 실패하는 시험** — `badge caps at 99+ and hides at 0`(0 → 없음, 7 → "7", 100 → "99+"); `server badge counts only after confirm`(이상 3개 중 확인 시각 뒤 1개 → 1); `confirm store survives storage errors`(던지는 가짜 store → 배지 3, 화면 안 깨짐); `pending counts map to sections`(heartTasks 2 · graduates 1 · reports 3 · inquiries 1 → 각 메뉴 키 `nav-heartTasks` 안에 "2" 등); `navigating refreshes pending counts`(메뉴 이동 뒤 가짜 API pendingCounts 호출 2회); `no timer`(`tester.pump(const Duration(minutes: 5))` 뒤 호출 수 그대로).
- [ ] **Step 2: FAIL 확인** — `flutter test test/widgets/count_badge_test.dart test/shell/nav_badges_test.dart`.
- [ ] **Step 3: 구현.**
- [ ] **Step 4: PASS 확인** + `flutter analyze`.
- [ ] **Step 5: 커밋 단위 표시** — "관리자 메뉴 숫자 배지".

### Task 5: 관리자 웹 — "서버 상태" 화면(pen A11)

**Files:**
- Create: `admin_web/lib/server_status/server_status_screen.dart`
- Modify: `admin_web/lib/router/admin_router.dart`(Task 4 가 추가한 `AdminSection.serverStatus` 경로에 화면 연결)
- Test: `admin_web/test/server_status/server_status_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 `serverStatusProvider`, `serverConfirmedAtProvider`; 기존 `StatCard`, `ChartCard`, `charts/grouped_bar_chart.dart`, `AdminButton`, `load_states.dart`, `AdminLink`.
- 화면(위→아래, pen A11 값표대로): TopBar 제목 "서버 상태" · 오른쪽 "마지막 갱신 HH:mm"(한국 시간) + [새로고침](→ `serverStatusProvider.refresh()` 와 `pendingCountsProvider.refresh()`) / 이상 목록 패널(최신 순, 줄 = 빨간 점 + "HH:mm" + 문구, 오른쪽 위 [확인] → `confirmNow(DateTime.now())`, 확인 시각 이전 줄은 흐리게, 없으면 "최근 3시간 이상 없음") / 숫자 카드 4개 / 그래프 2개 / "앱 꺼짐은 Firebase Crashlytics 에서 보기 →" 링크(`https://console.firebase.google.com/` — 프로젝트 경로 넣지 않음).
- 이상 문구: `errors` → "서버 오류 {n}건 (5분)", `error_rate` → "오류 비율 {n}% (5분)", `slow` → "응답이 느려요 (보통 {n}초)".
- 카드: "요청 수" `{requestsPerMin}/분`, "오류 비율" `{errorRate*100 소수 1자리}%`, "응답 속도" `{p50 초 소수 2자리}초` + 보조 "100건 중 95번째 {p95}초", "켜진 서버" `{instances}대`; null → "—".

- [ ] **Step 1: 실패하는 시험** — `renders cards and anomalies`(가짜 상태 → 카드 4개 글자, 이상 2줄 문구); `confirm clears server badge`([확인] 뒤 `nav-serverStatus` 배지 없음, store 에 시각 기록); `refresh button reloads both`(가짜 API 호출 수 +1 씩); `server status error shows retry`(503 → 오류 줄 + [다시 시도], 배지 없음); `empty window shows no-anomaly text`; 메뉴 순서 시험은 "작업 기록" 앞에 "서버 상태".
- [ ] **Step 2: FAIL 확인** — `flutter test test/server_status`.
- [ ] **Step 3: 구현.**
- [ ] **Step 4: PASS 확인** — `flutter test`(admin_web 전체) + `flutter analyze` + `flutter build web --release` 성공.
- [ ] **Step 5: 커밋 단위 표시** — "관리자 서버 상태 화면".

### Task 6: 마무리(대장)
- [ ] campus-reviewer 전체 검토(시험 RED 재확인 · pen 값 대조 · 권한 실패 시 503).
- [ ] 로컬에서 서버를 띄워 실제 구글 숫자로 `/admin/server-status` 한 번 확인(운영 DB 쓰기 없음).
- [ ] campus-git draft PR(서버 · 관리자 웹 · 문서 커밋 분리) → CI 초록.
- [ ] **사용자 허락 받고** 서버 배포(새 리비전 0% → 태그 주소로 확인 → 100%) → 관리자 웹 merge(Vercel 배포).
- [ ] 문서: `backend/DEPLOY.md` 서버 권한(monitoring.viewer) 한 줄, 노션 진행 기록.

## 구현 편차 기록

(구현 중 계획과 달라진 점만 여기에 덧붙인다. 위 본문은 고치지 않는다. 2026-11-18 문서 정리.)

- **Task 4 확인 방식**: 계획의 "확인 시각 하나"(`ConfirmStore { DateTime? read(); void write(DateTime at); }` · 키 `cm_admin_server_confirmed_at`)는 **이상 열쇠 묶음**으로 바뀌었다. 이상 시각이 5분 칸의 시작이라 "확인 시각 뒤" 로 세면 확인 직후 같은 칸에 생긴 이상을 놓치기 때문이다. 키는 `cm_admin_server_seen`, 값은 "시각 UTC ISO|종류" 글자의 JSON 배열이고 지금 응답 창 밖의 열쇠는 [확인] 때 버려 저장 값이 자라지 않는다. `serverConfirmedAtProvider` 는 `serverSeenProvider`(`Set<String>`)가 됐다. 저장값은 로그아웃해도 지우지 않는다(운영 정보가 아님, 대장 11-18).
- **Task 4 상태 모양**: `serverStatusProvider` 는 계획의 `AsyncValue<ServerStatus>` 가 아니라 `ServerStatusState(status · failure · loading)` 를 든 `Notifier` 다 — 새로고침 중에도 앞 숫자를 그대로 두려는데 Riverpod 3 의 "앞 값을 든 로딩"이 밖에 열려 있지 않아서다. 도는 중 [새로고침]은 무시한다.
- **Task 4 관리자 바뀜**: 세 provider(서버 상태 · 대기 건수 · 본 이상)는 지금 들어온 관리자(메일)를 지켜본다. 로그아웃 · 다른 관리자 로그인 · 세션 끊김 때 처음부터 다시 만들어, 같은 브라우저의 다음 사람이 앞 사람의 숫자를 보지 않게 한다(계획에 없음, 대장 11-18).
- **Task 5 화면**: 이상 패널은 10줄까지 보이고 넘는 것은 "외 N건" 한 줄이다(pen 에 없음, 대장 판단). 확인한 줄은 흐리게(설명 muted · 점 `web-disabled`). 서버 오류 그래프에 "느린 요청" 선은 없다 — 서버가 칸마다 느린 요청 수를 주지 않는다(대장 결정 11-17). Crashlytics 링크는 프로젝트 경로 없이 콘솔 첫 화면으로 보낸다(실제 프로젝트 id 를 코드에 두지 않는다).
- **Task 6**: 서버 배포는 사용자 허락 뒤 새 리비전 `00135-haz`(태그 `s1118`)를 0% 로 점검하고 100% 로 옮겼다(2026-11-18, `backend/DEPLOY.md` §4-33 · §5 개정 6). 관리자 웹은 같은 PR 의 Vercel 자동 배포가 성공했다. 서버 계정의 `roles/monitoring.viewer` 한 줄은 `backend/DEPLOY.md` §1 에 이미 있다.
- **남은 것**: pen 이상 없음 변형 `siTuo` 의 메뉴 서버 상태 배지 "2" 숨기기 · `AnomalyRow` 확인함 · "외 N건" · 로딩 · 실패 변형 · 복사본 SideNav `BQyo6` 정리, 구글 Monitoring 질의 동시 호출의 가끔 429 — 모두 추후(사용자 「추후 일로 적어둬」).
