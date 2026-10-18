# 관리자 신고 후속(D2b) — 본 신고 범위만 닫기 · 목록 신고자 수 · 투표 요약 · 관리자 정지 막기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** D2(신고 검수)와 D3(사용자 · 결제)가 남긴 서버 후속 네 가지를 닫는다 — 같은 대상 함께 닫기 · 가림 해제가 운영자가 **본 신고**만 닫게, 신고 목록 줄마다 신고자 수, 투표 글 신고 줄의 질문 앞부분, 관리자 계정은 정지할 수 없게.

**Architecture:** DB 는 새 마이그레이션 한 파일(`20261018140000_admin_report_followups.sql`)에서 `admin_resolve_report` · `admin_unhide_profile` 을 "본 신고 id 배열"(`p_seen uuid[]`)을 받는 꼴로 다시 만들고(인자가 늘어 옛 시그니처는 `drop function`), `admin_suspend_profile` 에 관리자 대상 `CM404` 를 더한다. 서버는 본문의 `seen_report_ids` 를 `p_seen` 으로 넘기고, 목록은 PostgREST 한 번을 더해(열린 신고의 신고자 묶음) 줄마다 `open_reporters` 를 채우며 `target_snapshot->>question` 별칭 한 칸으로 투표 질문 앞부분(`preview`)을 싣는다. 기존 응답 필드는 지우지 않고 더하기만 한다.

**Tech Stack:** Postgres(plpgsql, pgTAP) · FastAPI + httpx(PostgREST 가짜 `backend/tests/admin/admin_world.py`).

**Spec:** 바탕화면 `C:/Users/user/OneDrive/Desktop/관리자_대시보드_설계_10-18.md` §8-2 의 "W2 주의(보안 검토 10-18, 낮음 8)" 줄 · "후속(D3 계획 10-18)" 줄. 모양 · 관례의 기준: `2026-10-18-admin-report-review.md`(D2) · `2026-10-18-admin-users-billing.md`(D3).

**범위:** 서버 · DB 만. 웹(`admin_web/`)은 이번에 고치지 않는다(W3 작업 중) — 아래 "웹 후속(W2b)"에 바꿀 곳만 적는다.

## Global Constraints

- 새 마이그레이션 **한 파일** `supabase/migrations/20261018140000_admin_report_followups.sql`(가장 최근 `20261018130100` 은 다른 PR). 함수는 모두 `security invoker` + `set search_path = ''` + `revoke all … from public, anon, authenticated` 뒤 `grant execute … to service_role` 만, 맨 앞 `perform public.admin_assert(p_admin)`, 0줄 예외 약속 그대로(없음 `CM404` · 이미 그 상태 `CM409` · 규칙 위반 `22023`).
- 기존 응답 필드는 지우지 않는다(웹 W2 가 이미 쓴다). 신고 목록 줄 · 상세에 칸을 **더하기만** 한다.
- 새 외부 의존성 금지. 공유 파일(`main.py` · `settings.py` · `core/errors.py`) 무변경. 운영 적용 · 배포 금지.
- 신고자 id · 채팅 본문은 응답 · 로그에 싣지 않는다(목록 신고자 수는 숫자만).

## 설계 결정 (코더가 정한 안 — 끝의 "대장 결정 필요"에 같이 모음)

**① 본 신고 범위: "본 신고 id 목록"(`seen_report_ids`)을 고른다. 상세가 서버 시각(`fetched_at`)을 주는 안은 버린다.**
- 시각 안은 신고 `created_at`(DB `now()`)과 `fetched_at`(API 서버 시계)을 비교하게 된다 — 두 시계가 어긋나면 새 신고를 놓치거나(닫음) 본 신고를 남긴다. 트랜잭션 시작 시각으로 찍히는 `created_at` 은 긴 트랜잭션이 늦게 커밋될 때도 `fetched_at` 보다 앞설 수 있다. DB 시각을 상세에서 받으려면 서버가 DB 시각 조회를 따로 해야 한다.
- id 안은 시계가 없고, DB 함수가 "이 id 들 중 이 사람의 열린 신고"만 닫으니 결과가 결정적이다. 작업 기록에도 "운영자가 본 것"이 그대로 남는다. 웹은 이미 상세의 `other_reports`(id · status 가 있다)를 가지고 있어 열린 것의 id 를 모으면 된다 — 서버 응답 변경 없음.
- 상세의 `other_reports` 는 20건까지만 싣는다(웹 shortcut). 그보다 많으면 못 본 신고는 열린 채로 남는다 — "본 것만 닫는다"와 같은 방향이라 안전하다(가림 해제 뒤 그 신고가 다시 가림 기준을 채울 수 있다).
- `resolve` 의 `same_target=true` 는 `seen_report_ids` 에 든 것 + 이 신고만 닫는다(이 신고 id 는 목록에 없어도 된다). `same_target=false` 면 `seen_report_ids` 를 보지 않는다. `unhide` 는 `seen_report_ids` 에 든 열린 신고만 기각한다(빈 배열 `[]` = 가림만 풀고 기각 없음).
- 이 신고 id 말고 다른 대상 신고 id 가 섞여 와도 DB 는 `target_profile_id = 이 사람` 으로 한 번 더 거른다 — 남의 신고가 닫히지 않는다.

**② 값이 없을 때(옛 웹): 거절한다.** `same_target=true` 인데 `seen_report_ids` 가 없거나(null), `unhide` 인데 없으면 서버 `422 seen_reports_required`, DB 도 `p_seen is null` 이면 `22023`. 이유: 하위 호환으로 "없으면 전부 닫기"를 남기면 보안 검토 지적이 기본값으로 살아 있고 웹 고치는 것을 잊어도 아무 신호가 없다. D2 마이그레이션이 운영 미적용이고 W2 웹도 배포 전이라 깨질 사용자가 없다. (뒤집으려면: 서버 한 줄 + DB 한 줄 — 결정 필요 ①.)

**③ 목록 신고자 수: 열린 신고 기준, 칸 이름 `open_reporters`(상세와 같은 이름).** 상세의 `open_reporters` 와 자동 가림(`count_open_reporters`)과 같은 정의 — 대상 한 사람에게 열린 신고를 낸 서로 다른 신고자 수, 탈퇴해 비게 된 신고자(`reporter_id` null)는 세지 않는다. 그래야 목록 숫자 = 상세 제목 "n명 신고" = 가림 기준 3 이 한 말이다. 닫힌 목록(조치/기각)에서는 그 사람의 **지금** 열린 신고자 수가 보인다(보통 0). 대상 계정이 지워진 줄(target_profile null)은 0. 구현은 목록 줄들의 대상 id 를 모아 `reports?target_profile_id=in.(…)&status=eq.open&select=target_profile_id,reporter_id` 한 번 더(사용자 목록 `count_reports_by_target` 과 같은 방식, 1000줄 상한 shortcut 주석).

**④ 목록 투표 요약: `preview` 칸. 투표 글 신고만 질문 앞 40자(넘으면 `…`), 그 밖은 `null`.** 현재 `_summary` 에는 대상 요약 칸이 없다(웹은 "{닉네임} 의 투표 글"로 대신 그린다). PostgREST 별칭 `preview_question:target_snapshot->>question` 한 칸만 골라 목록이 사본(사진 경로 포함)을 통째로 읽지 않게 한다. **메시지 본문은 싣지 않는다**(사유를 적고 열람 기록을 남기는 D 경로로만 본다). 지인 리뷰 한마디도 싣지 않는다(결정 필요 ③). 상세에도 같은 `_summary` 라 `preview` 가 따라온다.

**⑤ 관리자 정지 막기: `CM404`(D3 하트 조정 · 탈퇴 대행과 같은 방식).** `admin_suspend_profile` 이 대상이 `admin_users` 에 있으면 "없는 프로필"과 같은 `CM404`(서버 404 `not_found`). 해제(`unsuspend`)는 그대로(관리자는 정지될 수 없으니 해제할 일이 없다).

---

### Task 1: DB — 본 신고 범위 · 관리자 정지 막기 (pgTAP 먼저)

**Files:**
- Create: `supabase/migrations/20261018140000_admin_report_followups.sql`
- Test: `supabase/tests/admin_report_followups_test.sql` (새 파일 — 기존 `admin_report_review_test.sql` 은 시그니처 호환이라 6인자 호출이 그대로 통과하도록 `p_seen` 기본값 null 을 둔다. unhide 는 5인자가 되므로 그 파일의 unhide 호출들을 5인자로 고친다.)

**Interfaces:**
- Produces: `public.admin_resolve_report(p_admin uuid, p_report uuid, p_outcome public.report_status, p_note text, p_same_target boolean, p_ip inet, p_seen uuid[] default null) returns jsonb` · `public.admin_unhide_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet, p_seen uuid[]) returns jsonb` · `public.admin_suspend_profile`(시그니처 그대로, 관리자 대상 CM404).

- [ ] **Step 1 (RED): pgTAP 을 쓴다.** 사람 · 신고 준비 후 다음을 본다 — (a) 함께 닫기에서 `p_seen` 에 든 같은 사람의 열린 신고만 닫히고, 안 든 열린 신고는 열린 채 · 기록 없음 (b) 함께 닫기인데 `p_seen` null → `22023` (c) `p_seen` 에 다른 사람의 신고 id 가 섞여도 닫히지 않음 (d) `p_seen` 에 이 신고가 없어도 이 신고는 닫힘 (e) `same_target=false` 면 `p_seen` 을 무시 (f) 가림 해제가 `p_seen` 에 든 열린 신고만 기각하고 안 든 새 신고는 열린 채 · 가림 시각은 비워짐 (g) 가림 해제 `p_seen` null → `22023`, `[]` → 기각 0건으로 성공 (h) 함수 모양(invoker · search_path · service_role 만) (i) 관리자 대상 정지 → `CM404` + 상태 · 기록 변화 없음, 일반 대상 정지는 그대로.
- [ ] **Step 2: RED 확인.** `supabase db reset` → `supabase test db`. Expected: 새 파일이 실패(함수 인자 수 · 관리자 정지 통과).
- [ ] **Step 3: 마이그레이션을 쓴다.** `drop function` 두 옛 시그니처 → `create function` 새 시그니처(본문은 `20261018035204` 의 것 + 아래 바뀐 점) → `create or replace` 정지 → revoke/grant. 바뀐 점: resolve 의 잠금 · 갱신 조건 `(coalesce(p_same_target,false) and target_profile_id = v_target and id = any(p_seen))`, `p_same_target and p_seen is null` → `22023`; unhide 의 잠금 · 갱신 조건에 `and id = any(p_seen)`, `p_seen is null` → `22023`; 정지는 `if not found or exists (select 1 from public.admin_users where user_id = p_profile)` → CM404.
- [ ] **Step 4: GREEN 확인.** `supabase db reset` → `supabase test db` 전체. 기존 `admin_report_review_test.sql` 의 unhide 호출을 5인자로 고쳐 통과시킨다.

### Task 2: 서버 — 본 신고 id 를 DB 로 넘기기

**Files:**
- Modify: `backend/app/admin/report_review.py`(`ResolveBody.seen_report_ids` · resolve 핸들러 검사) · `backend/app/admin/moderation.py`(본문 모델 · unhide 검사) · `backend/app/admin/repository.py`(`resolve_report` · `act_on_profile` 의 `p_seen`, 상수 `SEEN_REPORTS_REQUIRED`)
- Test: `backend/tests/admin/test_admin_reports.py` · `test_admin_moderation.py`

**Interfaces:**
- Consumes: Task 1 의 DB 함수 시그니처.
- Produces: `POST /admin/reports/{id}/resolve` 본문에 `seen_report_ids: list[UUID] | null`(최대 100), `POST /admin/profiles/{id}/unhide` 본문에 같은 칸. 없으면 `422 {"detail": "seen_reports_required"}`(함께 닫기 / 가림 해제일 때만).

- [ ] **Step 1 (RED):** 시험 — resolve 가 `same_target=true` 에서 `p_seen` 으로 id 문자열 배열을 보낸다 / `same_target=true` 인데 `seen_report_ids` 없음 → 422 `seen_reports_required` 이고 DB 함수를 부르지 않음 / `same_target=false` 는 `seen_report_ids` 없이 통과 / unhide 가 `p_seen` 을 보내고, 없으면 422 / `[]` 는 통과 / 101개 · UUID 아님 → 422 / suspend · unsuspend 의 DB 본문에는 `p_seen` 이 없다.
- [ ] **Step 2:** `pytest tests/admin -q` → 새 시험이 실패하는 것을 눈으로 본다.
- [ ] **Step 3 (GREEN):** 본문 모델 · 핸들러 검사 · 레포지토리 인자 구현. 기존 시험의 unhide 호출에 `seen_report_ids` 를 더한다.
- [ ] **Step 4:** `pytest tests/admin -q` 통과.

### Task 3: 서버 — 목록 신고자 수

**Files:** Modify `backend/app/admin/report_review.py`(`list_reports`) · `repository.py`(`count_open_reporters_by_target`). Test `test_admin_reports.py` · `admin_world.py`(가짜가 새 조회를 받는다).

- [ ] **Step 1 (RED):** 시험 — 목록 줄마다 `open_reporters`(같은 사람의 두 줄은 같은 수, 같은 신고자의 중복 · 탈퇴한 신고자(null) 제외, 대상 없는 줄은 0), 요청은 `reports` 목록 + 신고자 묶음 둘뿐이고 신고자 묶음은 `status=eq.open` · `target_profile_id=in.(…)` · `select=target_profile_id,reporter_id`, 대상이 하나도 없으면 두 번째 조회를 보내지 않음, 신고자 id 는 응답에 없음.
- [ ] **Step 2:** 실패를 본다. **Step 3:** 구현(대상 id 는 순서 유지 · 중복 없이 모은다). **Step 4:** 통과.

### Task 4: 서버 — 투표 요약(preview)

**Files:** Modify `repository.py`(`_REPORT_SELECT` 에 `preview_question:target_snapshot->>question`) · `report_review.py`(`_summary` 의 `preview`). Test `test_admin_reports.py` · `admin_world.report()` 헬퍼.

- [ ] **Step 1 (RED):** 시험 — 투표 글 신고 줄은 질문 앞 40자(40자 이하는 그대로, 넘으면 40자 + `…`), 프로필 · 메시지 · 지인 리뷰는 `null`(메시지 본문이 목록에 오지 않음을 사본에 `body` 가 있는 줄로 확인), select 에 별칭이 있고 `target_snapshot` 통째는 없음, 질문이 빈 문자열 · null 이면 `null`.
- [ ] **Step 2:** 실패를 본다. **Step 3:** 구현. **Step 4:** 통과 + 전체 `pytest -q`.

### Task 5: 전체 검증 · 계획서 편차 기록

- [ ] backend `pytest -q` 전체, `supabase db reset` → `supabase test db` 전체, 바뀐 파일 md5 보고.

---

## 웹 후속(W2b) — 바꿀 곳 (대장 결정 10-18: 같은 워크트리 · 같은 PR 에서 구현 — 아래 "구현 편차 기록" 끝)

- `admin_web/lib/api/admin_api.dart` `resolveReport`: `sameTarget` 이 참이면 `'seen_report_ids': [...]` 를 같이 보낸다(인자 `seenReportIds` 추가). `actOnProfile` 은 `ProfileAction.unhide` 일 때 `seen_report_ids` 를 보낸다.
- `admin_web/lib/reports/report_controller.dart` `resolve(...)` · `actOnProfile(...)`: 상세 `otherReports` 중 `isOpen` 인 것의 id 를 모아(+ 사용자가 이 신고를 닫는 경로면 이 신고) 넘긴다. 상세를 다시 받은 뒤에는 목록이 바뀌었으니 확인 대화상자에 보이는 수와 보내는 id 를 같은 값에서 만든다.
- `admin_web/lib/reports/report_item.dart`: `ReportSummary.openReporters`(`open_reporters`, 목록에서도 옴) · `preview`(`preview`) 파싱. `targetSummary` 가 투표 글에서 `preview` 가 있으면 그것을 쓴다.
- `admin_web/lib/reports/report_list_screen.dart:172`: `missingValue` 대신 `item.openReporters`(대상 없으면 `—`).
- `ReportDetail` 의 `open_reporters` 는 그대로.

## 대장 결정 필요 (정한 안 포함) — **확정 10-18: 아래 1~4 와 설계 결정 ⑤(관리자 정지 CM404) 다섯 건 모두 정한 안대로**

1. **옛 웹(값 없음) 처리** — 정한 안: **거절**(422 `seen_reports_required`, DB `22023`). 대안: 값이 없으면 지금처럼 전부 닫기(하위 호환, 구멍이 기본값으로 남음). W2 웹이 이미 배포되어 있으면 W2b 가 머지될 때까지 "함께 닫기 · 가림 해제"가 막히니 순서를 맞춘다.
2. **본 신고 범위의 방법** — 정한 안: **id 목록**. 대안: 서버 시각 `fetched_at`(시계 어긋남 위험, 위 ① 참고).
3. **목록 `preview` 범위** — 정한 안: 투표 질문만. 지인 리뷰 한마디(`comment`)도 싣고 싶으면 별칭 한 칸 더(리뷰는 사람 대 사람 평이라 목록에 드러내기 부담스러워 뺐다). 메시지 본문은 싣지 않는 것을 권장(열람 기록 경로 유지).
4. **목록 신고자 수의 기준** — 정한 안: **열린 신고 기준**(상세 · 자동 가림과 같은 정의). 닫힌 목록에서는 "지금 열린" 수가 보인다. 대안: 그 줄의 상태와 같은 신고들만 센 수.

## 구현 편차 기록 (코더가 이 아래에 덧붙임)

- **Task 1 — 기존 시험 파일도 맞췄다**: `admin_report_review_test.sql` 의 `admin_unhide_profile` 호출 7곳을 5인자로, 함께 닫기(`true`) 호출 4곳에 본 신고 목록(`p_seen`)을 더했다(기대값 · plan(63) 그대로 — 시험 12번만 `array[ea03]` 를 넘겨 같은 두 건이 닫힌다). `admin_resolve_report` 는 `p_seen uuid[] default null` 이라 `same_target=false` 6인자 호출은 그대로다.
- **Task 1 — RED/GREEN**: 마이그레이션 전 `supabase test db` 는 새 파일이 `Bad plan 27 vs 3`(함수 7인자 · 5인자 없음), 기존 파일이 `63 vs 30` 으로 중단(Files=37 중 2 실패). 마이그레이션 뒤 Files=37 Tests=1084 PASS(새 파일 27). 변이 확인: 마이그레이션의 `id = any(p_seen)` 조건을 지우면 새 파일 23/27 이 실패(4 · 5 · 6 · 8번 등)하고 되돌리면 통과.
- **Task 2 — `SeenReportIds` 정의 위치**: `report_review.py` 에 두고 `moderation.py` 가 가져온다(둘 다 같은 `admin` 패키지, 순환 없음). 상수 `SEEN_REPORTS_REQUIRED` 는 `repository.py`(다른 이유 코드 상수와 같은 자리). 검사는 `HTTPException(422, "seen_reports_required")` — pydantic 검증 오류(`detail` 이 목록)와 모양이 갈리지 않게 핸들러에서 했다. 서버 단 시험은 18건이 RED(`KeyError: 'p_seen'` · 200 vs 422) → 통과.
- **Task 3 — 목록은 이제 PostgREST 두 번**: 기존 시험 `test_list_asks_for_open_reports…` 의 `(query,) = world.calls(...)` 를 `[0]` 으로, `test_list_is_one_read…` 를 "목록 + 신고자 묶음 둘"로 고쳤다. 대상 계정이 하나도 없으면 두 번째 조회를 보내지 않는다. 가짜 세상(`admin_world.py`)은 `select=target_profile_id,reporter_id` 조회를 `open_reporters` 로 답한다.
- **Task 4 — `preview` 는 상세에도 따라온다**: `_summary` 가 목록 · 상세 공용이라 상세 응답에도 `preview`(null 가능)가 있다. 가짜 세상 `report()` 헬퍼는 PostgREST 별칭처럼 `preview_question` 을 사본의 `question` 에서 만든다.
- **PostgREST 별칭 문법 확인**: 로컬 PostgREST 에 같은 `select`(별칭 + 임베드) · 신고자 묶음 조회를 보내 둘 다 HTTP 200 을 받았다. 로컬 DB 에 신고 행이 없어 `->>` 값이 실제로 문자열로 오는 것까지는 보지 못했다(pytest 가짜는 PostgREST 가 돌려줄 모양을 가정한다).
- **웹 W2 와의 호환**: 웹 W2(`admin_api.dart` `resolveReport` · `actOnProfile`)는 아직 `seen_report_ids` 를 보내지 않는다 → 함께 닫기 · 가림 해제가 422 `seen_reports_required` 로 막힌다. W2b 가 머지될 때까지 서버만 먼저 배포하지 말 것(위 "웹 후속(W2b)").
- **전체 확인(10-18 코더)**: 루트 `.venv` 파이썬 `pytest -q`(backend) 2767 passed(`tests/admin` 398 → 432). pgTAP `supabase db reset` 뒤 `supabase test db` Files=37 Tests=1084 PASS. 프런트엔드 · `admin_web` 은 건드리지 않아 `flutter` 명령은 돌리지 않았다.
- **W2b 웹 구현(같은 PR, 대대장 지시 10-18)**: `admin_api.dart`(`resolveReport` · `actOnProfile` 에 `seenReportIds` 인자, 함께 닫기 / 가림 해제일 때만 `seen_report_ids` 를 본문에 싣고 목록을 안 주면 `[]`), `report_item.dart`(`ReportSummary.openReporters` · `preview` — 칸이 없는 옛 응답은 null, `targetSummary` 는 투표 글만 `preview` 우선, `ReportDetail.openOtherIds` 와 `openOthers = openOtherIds.length`), `report_controller.dart`(`resolve(..., seenReportIds)` 가 함께 닫기와 이어 부르는 가림 해제에 같은 목록을 보냄, `actOnProfile` 의 가림 해제는 "이 신고(열려 있으면) + 열린 다른 신고"), `report_detail_screen.dart`(`_resolve` 가 대화상자를 열 때 목록을 한 번 뽑아 "열린 신고 n건"의 n 과 보내는 id 를 같은 값에서 만듦), `report_list_screen.dart`(신고자 수 칸 = `open_reporters`, 대상이 없거나 칸이 없으면 "—"). W3 가 같은 파일을 고쳤으므로 필요한 줄만 건드렸다(이름 바꾸기 · 줄 옮기기 · 포맷 정리 없음).
- **W2b 시험**: RED = 컴파일 실패(`seenReportIds` · `openReporters` · `openOtherIds` 없음), GREEN = `flutter test test/reports test/api` 전부 통과. 변이 확인: `openOtherIds` 가 닫힌 신고까지 모으면 세 시험이 떨어진다. 가짜 서버(`test/helpers/report_fakes.dart`)는 서버 약속대로 `seen_report_ids` 가 없으면 422 `seen_reports_required` 를 돌리고 본 신고만 닫는다.
- **W2b 알아둘 점**: 가림 해제 대화상자 본문 "이 사람의 열린 신고는 모두 기각돼요"(pen 문구)는 손대지 않았다 — 이제는 "본 신고"만 기각되므로 문구가 정확하지 않다(pen 수정 필요 시 campus-pen). 신고자 수 칸은 숫자만 그린다(단위 "명" 없음, pen 값 확인 필요). `ReportSummary` 위 주석("신고자 수는 없다")은 그대로 남아 낡았다(W3 충돌을 피해 안 고침).
- **W2b 문구 확정(대장 10-18)**: 가림 해제 대화상자 본문 → "…이 화면에서 본 열린 신고만 기각돼요(그 뒤 들어온 신고는 남아요)…", 기각 대화상자 안내 줄 → "가림을 풀면 이 화면에서 본 열린 신고도 함께 기각돼요", 목록 신고자 수 칸 → "n명"(대상 없음 · 옛 응답은 "—")으로 고쳤다. **남은 정리(W3 위로 올린 뒤 코더가)**: `admin_web/lib/reports/report_item.dart` 의 `ReportSummary` 위 주석 "사본 · 사진 · 신고자 수는 없다"는 낡았다 — 목록 줄에 `open_reporters` · `preview` 가 오므로 "사본 · 사진은 없다(신고자 수 · 투표 질문 앞부분은 있다)"로 고친다.
