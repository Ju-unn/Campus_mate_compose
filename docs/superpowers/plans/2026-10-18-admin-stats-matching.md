# 관리자 대시보드 D4 — 통계 · 그래프 · 운영 상태판 · 학교별 현황 · 미등록 도메인 · 매칭 현황 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자 홈(A2) · 미등록 학교 메일(A6) · 매칭 현황(A9) 화면이 읽는 서버 경로를 만든다 — 숫자 카드, 30일 그래프 데이터(가입 남/여 · 신고 · 인증샷 · 수락 · 매칭 · 카톡 공유), 운영 상태판 5개, 학교별 현황, 미등록 도메인 목록, 누가 누구랑 매칭됐나 목록.

**Architecture:** 전부 읽기만 한다(쓰기 · 작업 기록 없음). PostgREST 로는 날짜 묶음 · 조건부 개수 · 두 표 비교를 못 하므로 **읽기 전용 DB 함수(security invoker · `search_path ''` · service_role 만 execute)** 8개 + 인덱스 1개를 마이그레이션 **한 파일**에 둔다(D3 `admin_billing_daily` 와 같은 모양). 서버는 함수를 RPC 로 부르고 응답 모양과 상태판 기준값(임계값)만 다룬다 — 기준값은 서버 상수라 마이그레이션 없이 바꾼다. 작업 기록 보기(A7)는 D3 의 `GET /admin/actions` 를 그대로 쓴다(새 코드 없음).

**Tech Stack:** Postgres(plpgsql, pgTAP) · FastAPI + httpx(PostgREST RPC) · pytest(MockTransport 가짜).

**Spec:** 바탕화면 `C:/Users/user/OneDrive/Desktop/관리자_대시보드_설계_10-18.md` §8-4 · §8-4b · §8-4c · §8-5(작업 기록은 D3 에 이미 있음) · §11 D4 · §14. 화면 모양 근거(PNG 를 읽기만 함, pen 값은 W4 몫): `…/CampusMate_문서/디자인_pen/관리자_대시보드/` 의 `A2_홈` · `A6_미등록_학교_메일` · `A7_작업_기록` · `A9_매칭_현황`. 모양 · 관례의 기준: D3 `docs/superpowers/plans/2026-10-18-admin-users-billing.md`(구현 편차 기록 포함), `backend/app/admin/{billing,billing_repository,action_log}.py`, 마이그레이션 `20261018120000_admin_users_billing.sql` 의 `admin_billing_daily`.

**범위:** 서버 · DB 만. 웹 화면(W4)은 아래 응답 JSON 모양만 정하고 구현하지 않는다.

## Global Constraints

- 운영 DB 적용 · 서버 배포 금지. 코더는 로컬 DB 명령(`supabase db reset` · `test db` · `start`)도 돌리지 않는다 — pgTAP 은 대장 차례. 그래서 DB 쪽 Task 1~3 의 RED/GREEN 은 대장 pgTAP 한 번에서 본다(함수가 없다 → 있다). 서버 Task 4~6 은 pytest 로 직접 RED → GREEN 을 본다.
- 새 마이그레이션은 **한 파일** `supabase/migrations/20261018150000_admin_stats_matching.sql`(D2b 가 `20261018140000` 을 쓴다). 새 외부 의존성 금지. 공유 파일(`backend/app/main.py` · `settings.py` · `core/errors.py`)은 고치지 않는다 — 라우터는 `backend/app/admin/router.py` 에 붙인다.
- **D2b 창이 `backend/app/admin/repository.py` · `backend/tests/admin/admin_world.py` 를 고치는 중** → 이 조각은 두 파일을 **고치지 않는다**. 저장소는 `AdminRepository` 를 상속하고(`_rpc` 만 호출), 시험 가짜는 새 파일 `tests/admin/stats_world.py`(`AdminWorld` 를 상속해 새 RPC 이름만 먼저 가로챔)에 둔다.
- 함수는 전부 `language plpgsql` · `stable` · `security invoker` · `set search_path = ''`(모든 객체에 `public.`), 파일 끝에 `revoke all on function … from public, anon, authenticated;` 뒤 `grant execute … to service_role;`(`security definer` 금지). 읽기 함수라 `admin_assert` 는 부르지 않는다(D3 `admin_billing_daily` · `admin_billing_shortfall` 과 같다 — 관문은 서버 `get_admin_caller`, 함수는 service_role 만 부를 수 있다).
- DB 오류 약속(D3 와 같음): 규칙 위반 `22023` → 서버 422(`AdminRepository._rpc` 가 처리). 읽기라 `CM404` · `CM409` 는 없다.
- **관리자 계정(`admin_users`)은 통계에서 제외**(D0 결정 · 설계 §6-5): 프로필을 세는 모든 곳(상태별 인원 · 가입 · 학교별 활성)과 신고자 · 제출자를 보는 곳(신고 · 인증샷)에서 `not exists (select 1 from public.admin_users …)`. 매칭은 관리자가 카드를 받지 못해 자연히 빠진다(설계 §8-4c) — 따로 거르지 않는다.
- **날짜는 한국 시간(`Asia/Seoul`) 하루 단위, 항상 `p_days` 줄(없는 날 0), 오래된 순, 마지막 = 오늘(KST)**. `p_days` 는 1~90(null · 범위 밖 22023), 서버 기본 30. DB 의 `day` 칸은 서버가 JSON `date` 로 바꾼다(D3 `billing.py::_day` 와 같다).
- 경로 이름: `/admin/stats` · `/admin/stats/daily` · `/admin/unknown-domains` · `/admin/universities` · `/admin/health` · `/admin/matching/summary` · `/admin/matching/daily` · `/admin/matching/pairs`. `e2e/area4_extra.py:38-44` 금지어(`refund` · `cashout` · `transfer` · `gift` · `send_heart` · `send-heart` · `exchange` · `heart_withdraw` · `heart-withdraw` · `hearts/withdraw`)와 구매 단어(`purchase` · `buy` · `unlock` · `heart_store` · `heart-store`) · `withdraw` 를 **부분 문자열로도** 쓰지 않는다. `tests/admin/test_admin_route_names.py` 와 `test_admin_caller.py::test_every_admin_route_goes_through_the_admin_gate` 가 자동으로 검사한다(Task 4~6 끝에서 돌린다). `get_verified_caller` 금지.
- **읽기 화면이라 작업 기록(`admin_actions`)에 쓰지 않는다**(설계 §8-4c). 매칭 목록도 마찬가지 — 대신 "운영자의 매칭 관계 열람 범위"를 법률 확인 목록에 올리는 일은 campus-docs 몫(이 조각 밖, 대장에게 알림).
- **매칭 목록(`pairs`)은 사진 · 카톡 아이디 · 대화 내용 · 전화를 DB 함수 반환 칸에도 서버 응답에도 싣지 않는다**(닉네임 · 학교 이름 · 프로필 id · 시각 · 상태뿐).
- 필터 값은 **DB 함수의 타입 있는 인자**(uuid · timestamptz · 고정 글자)로만 간다 — PostgREST 필터 문법(`or=` · `in.(…)` · 쉼표 · 괄호)이 끼어들 길 자체가 없다. 서버는 그 앞에서 `Literal` · `UUID` · 커서 검사로 한 번 더 걸러 422 로 돌린다(입력 반사 없음).
- 커밋 · PR 에 도구 표식 금지. 디스코드 알림 · 로그에 번호만(이 조각은 알림을 건드리지 않음).

## Review Focus

1. **관리자 계정 제외** — 상태별 인원 · 가입 남/여 · 학교별 활성에 관리자 프로필이 끼면 숫자가 어긋난다(성별을 고른 관리자라면 가입 1명이 더 보임). 신고자 · 제출자가 관리자인 줄도 뺀다. → Task 1 pgTAP `overview excludes admin profiles` · `daily excludes admin signups reporters and submitters`.
2. **한국 날짜 경계 · 빈 날 0 채움** — KST 00:30 과 직전 23:30 이 UTC 로는 같은 날이다. 데이터 없는 날 · 가입이 0 인 날 그래프가 끊기면 안 된다. 수락 · 매칭 · 카톡 공유는 **서로 다른 시각 칸**(`decided_at` · `created_at` · `trust_passed_at`)이라 같은 사건이 다른 날에 잡히는 것이 정상이다. → Task 1 `daily buckets by kst midnight`, Task 3 `matching daily counts each event on its own kst day`.
3. **상태판 오탐(거짓 경고)** — 카드가 안 나가는 게 정상인 날(지급 요일 아님 · 지급 시각 + 여유 전 · 아직 안 열린 학교뿐이라 받을 사람 없음 = **11/2 전 코호트**)에 "카드 0건" 경고가 뜨면 안 된다. 한쪽이 나갔거나 정지 · 탈퇴한 방은 배치가 일부러 안 닫으므로 "안 닫힌 방"에 세지 않는다. → Task 2 `cards check skips ...` 3개 · `stuck rooms ignore ...`.
4. **매칭 목록 개인 정보 · 필터 주입** — 함수 반환 칸이 정확히 허용 목록이고, 서버가 그 밖의 칸을 흘리지 않으며, 필터 값에 `,` `(` `or=` 를 넣어도 DB 로 가지 않는다. → Task 3 `pairs result columns are exactly the allowed list`, Task 6 `test_pairs_never_pass_through_unlisted_columns` · `test_bad_filters_never_reach_the_db`.
5. **큰 표 훑기 성능** — 아래 표 참고. 홈을 열 때마다 도는 읽기라, 제일 빨리 자라는 `daily_cards` 의 "오늘 지급분" 조회에만 인덱스를 더하고 나머지는 지금 규모에서 전체 훑기로 둔다(코드 주석 `shortcut:` 에 올릴 기준을 적는다). 실제 실행 계획(`explain`)은 로컬 DB 명령 금지라 **확인하지 못했다** — 대장 pgTAP 때 한 번 보면 좋다. → Task 1 `has_index`.

| 읽는 표 | 무엇을 | 지금 있는 인덱스 | 판단 |
|---|---|---|---|
| `profiles` | 가입(`created_at` 범위) · 상태별 개수 · 학교별 활성 | `profiles_university_id_index`(학교별만) | 가입 · 상태 개수는 전체 훑기 — 수천 줄은 ms 단위. 5만 줄 넘으면 `created_at` 인덱스(`shortcut:` 주석) |
| `reports` | 접수(`created_at` 범위) · 열린 개수 | `reports_created_at_index` | 그대로 |
| `heart_task_submissions` | 접수(`created_at` 범위) · `submitted` 개수 | 부분 유일 인덱스(`(profile_id, task) where status='submitted'`)가 개수에 쓰임 | 날짜 범위는 훑기(월 수백 건) |
| `card_decisions` | 수락(`decision='accept'` · `decided_at` 범위) | `card_decisions_decided_at_index`(accept 부분) | 그대로. 누적 "수락한 사람 수"는 accept 전체 × `daily_cards` pk 조인 — 수만 건까지 문제없음(`shortcut:`) |
| `matches` | 목록(`created_at` 정렬) · 일별 · 공유 | 없음 | 전체 훑기 — 1만 줄 넘으면 `(created_at desc, id desc)` 인덱스(`shortcut:`) |
| **`daily_cards`** | **오늘 지급분(`issued_at >= 오늘 0시`)** | **없음(owner 로 시작하는 둘뿐)** | **가장 빨리 자라는 표 → 이 조각이 `(issued_at desc)` 인덱스 1개 추가** |
| `profile_avatars` · `pending_pushes` | 최근 실패 · 오래된 보류 | `profile_id` 뿐 | 훑기(사용자 수 × 시도, 밤사이 쌓임뿐이라 작다) |
| `unknown_email_domain_attempts` | 시도 많은 순 | PK `domain` | 행 상한 5000(`record_unknown_email_domain`) — 훑어도 된다 |

---

### Task 1: 마이그레이션 ① — 통계 숫자 · 일별 그래프 · 미등록 도메인 · 학교별 현황 · 인덱스

**Files:**
- Create: `supabase/migrations/20261018150000_admin_stats_matching.sql`(머리 주석 — 설계 §8-4 · §8-4b · §8-4c · D3 `20261018120000` 과 같은 모양으로 "읽기만 · service_role 만 · 날짜는 KST" 요약)
- Create: `supabase/tests/admin_stats_matching_test.sql`(Task 2 · 3 이 같은 파일에 구역을 더한다)
- 손대지 않음: `supabase/tests/rls_slice0_test.sql`(새 표 · 표 권한 변경 없음 — D3 편차 기록과 같다. 코더는 `grep -n "routine\|admin_stats" supabase/tests/rls_slice0_test.sql` 로 확인만 하고 편차 기록에 한 줄)

**Interfaces (Produces):**
- `public.admin_stats_overview() returns table (pending_count integer, active_count integer, suspended_count integer, withdrawn_count integer, open_reports integer, pending_proofs integer, signups_today integer, signups_7d integer)` — 한 행. 프로필 개수는 관리자 제외, 네 상태 모두(없으면 0). `open_reports` = `reports.status='open'`. `pending_proofs` = `heart_task_submissions.status='submitted'`. `signups_today` · `signups_7d` = 아래 daily 와 **같은 규칙**(오늘 · 오늘 포함 7 KST 날, 남+여).
- `public.admin_stats_daily(p_days integer) returns table (day date, male_signups integer, female_signups integer, report_count integer, proof_count integer)` — 항상 `p_days` 줄.
  - 가입 = `profiles.created_at` 의 KST 날짜, **`gender is not null` 인 프로필만**(성별을 고르기 전 가입 중인 줄은 남/여를 알 수 없다), 상태 불문(정지 · 탈퇴 포함), 관리자 제외. → 대장 결정 4.
  - 신고 = `reports.created_at` 의 KST 날짜(모든 대상 종류), 신고자(`reporter_id`)가 관리자면 제외 — 신고자가 탈퇴해 `null` 이면 센다.
  - 인증샷 = `heart_task_submissions.created_at` 의 KST 날짜(상태 불문), 제출자가 관리자면 제외.
- `public.admin_unknown_domains(p_limit integer) returns table (domain text, attempt_count integer, first_seen_at timestamptz, last_seen_at timestamptz)` — `p_limit` 1~500(밖이면 22023). `attempt_count desc, last_seen_at desc, domain`. **이미 `university_email_domains` 에 등록된 도메인은 뺀다**(등록한 뒤에도 시도 기록이 남아 "미등록" 으로 계속 보이면 안 된다 — 정확히 일치, 가입 쪽 `find_university_id` 도 정확히 일치). → 대장 결정 5.
- `public.admin_universities_status(p_include_empty boolean) returns table (id uuid, name text, region_group text, card_opens_at timestamptz, is_open boolean, male_active integer, female_active integer)` — 활성 = `region_active_counts()` 와 **같은 규칙**(`status='active'` · `not matching_paused` · `last_active_at > now() - interval '14 days'` · `gender is not null`) + 관리자 제외. `is_open` = `card_opens_at is null or card_opens_at <= now()`(`region_active_counts` · `card_issue_owners` 의 "열림" 과 같은 정의). `p_include_empty` 가 false 면 `male_active + female_active > 0` 이거나 `card_opens_at is not null` 인 학교만. `(남+여) desc, name`. `p_include_empty` null 은 22023. → 대장 결정 3.
- 인덱스 `create index daily_cards_issued_at_index on public.daily_cards (issued_at desc);` — Task 2 의 "오늘 카드 도착" 점검이 쓴다.

- [ ] **Step 1: pgTAP 먼저** — `admin_stats_matching_test.sql` 머리(D3 시험과 같은 `begin; create extension if not exists pgtap …`, `plan(N)` 은 Task 3 끝에서 스크립트로 맞춘다). 로컬 DB 에 시드 · 다른 시험 흔적이 있어도 흔들리지 않게 **개수는 "넣기 전과 뒤의 차이"로 단정**한다(`before` 를 임시 표에 담아 둔다). 준비: 학교 둘(`테스트대학교X` — 열림, `테스트대학교Y` — `card_opens_at` 가 미래의 월요일 07:00), 프로필 여럿(남 · 여 · 성별 없음 · 상태 넷 · 관리자 프로필 하나 이상을 `admin_users` 에), 신고 · 인증샷 · 도메인 줄. 시각은 모두 `(now() at time zone 'Asia/Seoul')::date` 에서 `… at time zone 'Asia/Seoul'` 로 만든 KST 자정 기준 상대 값이다.
  - 모양: 새 함수 4개 모두 invoker · `search_path=""` · `service_role` 만 execute(`has_function_privilege` — anon · authenticated · public 없음) · authenticated 가 부르면 42501 · 인덱스 존재(`has_index`).
  - `overview counts profiles by status`: 상태별 +차이가 넣은 수와 같다. `overview excludes admin profiles`: 관리자 프로필(상태 active 로 만들고 성별도 고른 것)을 넣어도 `active_count` · `signups_today` 가 안 는다.
  - `overview counts only open reports and submitted proofs`: 닫힌 신고 · 승인된 제출은 안 센다.
  - `overview signups use kst days`: KST 오늘 00:30 가입은 `signups_today` 에, 어제 23:30 은 `signups_7d` 에만, 7일 전(여덟 번째 날) 은 어디에도 없다. 성별 없는 가입은 안 센다.
  - `daily returns exactly p_days rows zero filled`: `p_days=3` → 3줄 · 오름차순 · 마지막 = 오늘(KST) · 첫 줄 = 오늘−2 · 데이터 없는 날 0 다섯 칸.
  - `daily buckets by kst midnight`: KST 00:30 은 그날, 직전 23:30 은 전날(가입 · 신고 · 인증샷 모두).
  - `daily separates male and female signups`: 남 2 · 여 1 · 성별 없음 1 → `male_signups` 2, `female_signups` 1.
  - `daily excludes admin signups reporters and submitters`: 관리자 가입 · 관리자가 낸 신고 · 관리자가 낸 인증샷은 안 센다, **탈퇴해 `reporter_id` 가 null 이 된 신고는 센다**.
  - `daily rejects bad days`: 0 · 91 · null → 22023.
  - `unknown domains ordered by count then recency`: 시도 수 많은 순, 같으면 최근 시도 먼저. `unknown domains hide registered ones`: `university_email_domains` 에 넣은 도메인은 사라진다. `unknown domains limit is bounded`: 0 · 501 22023, `p_limit=1` 은 한 줄.
  - `universities count active by gender with the card rules`: 활성 남 · 여가 맞고, **정지 · 일시중지(`matching_paused`) · 15일 전 접속 · 성별 없음 · 관리자는 안 센다**. `universities sums equal region_active_counts for open schools`: 열린 학교만 골라 학교별 합 = `region_active_counts()` 의 같은 지역 · 성별 합(차이 기준). `universities is_open follows card_opens_at`: null · 과거 → true, 미래 → false. `universities include_empty filter`: false 면 활성 0 · 오픈 시각 없음인 학교가 빠지고, 활성 0 이어도 `card_opens_at` 이 있으면 남고, true 면 모두 나온다. `p_include_empty` null 22023.
- [ ] **Step 2: 마이그레이션 구현** — 위 네 함수 + 인덱스 + 파일 끝 revoke/grant. 날짜 묶음은 D3 `admin_billing_daily` 의 `v_today` · `generate_series` · left join 모양 그대로(`v_from := ((v_today - (p_days-1))::timestamp at time zone 'Asia/Seoul')`). 출력 칸 이름은 테이블 칸과 겹치지 않게 지었다(`report_count` 등 — plpgsql OUT 변수와 열 이름이 겹쳐 모호해지는 일을 피함). 관리자 제외는 `not exists (select 1 from public.admin_users a where a.user_id = …)`. 오래 걸릴 수 있는 훑기에는 `shortcut: <한계>, <언제 인덱스>` 주석(위 표 기준).
- [ ] **Step 3: Commit** `🗃️ db(admin): 홈 통계 · 일별 그래프 · 미등록 도메인 · 학교별 현황 읽기 함수` / 시험은 따로.

---

### Task 2: 마이그레이션 ② — 운영 상태판 `admin_health`

**Files:**
- Modify: `supabase/migrations/20261018150000_admin_stats_matching.sql`(구역 추가 + 파일 끝 revoke/grant 에 한 줄)
- Modify: `supabase/tests/admin_stats_matching_test.sql`

**Interfaces (Produces):**
- `public.admin_health(p_cards_grace_minutes integer, p_room_hours integer, p_withdrawn_days integer, p_avatar_hours integer, p_push_hours integer) returns table (cards_checked integer, cards_missing integer, stuck_rooms integer, overdue_withdrawn integer, avatar_failures integer, stuck_pushes integer)` — 한 행. 인자 범위: `p_cards_grace_minutes` 0~1440, 나머지 1~1000(밖이면 22023). **개수만 돌려주고 "정상/경고" 판단은 서버**가 한다(Task 5). 기준 시각을 인자로 받는 이유: 기준값을 마이그레이션 없이 서버 상수로 바꾸려고.
- 상태판 ①~⑤ 가 읽는 표 · 조건(실제 스키마 근거):

| # | 칸 | 표 · 조건 | 근거 |
|---|---|---|---|
| ① | `cards_checked` · `cards_missing` | `region_group_settings` 지역마다: **오늘이 지급 요일**(`extract(isodow from 오늘 KST) = any(issue_weekdays)`) **이고 지금이 `issue_time + p_cards_grace_minutes` 이후**(시각은 `(v_today + r.issue_time + make_interval(mins => p_cards_grace_minutes)) at time zone 'Asia/Seoul'`(date + time = timestamp)로 비교 — `time` 끼리 더하면 자정에서 감겨 틀린다) **이고 `public.card_issue_owners()` 에 그 지역 사람이 1명 이상** → 점검 대상(`cards_checked` 에 +1). 그중 `daily_cards` 에 `source='daily'` · `issued_at >= 오늘 0시(KST)` 인 카드가 그 지역 사람(`owner_id` → `profiles.university_id` → `universities.region_group`)에게 **0장**이면 `cards_missing` 에 +1 | `region_group_settings` 열 `issue_weekdays` · `issue_time`(`20260920160540_create_region_group_settings.sql:6-14`) · 배치가 사다리 결과로 요일을 다시 적음(`cards/issuing.py:36-42`) · `card_issue_owners()` 가 열린 학교 · 활성 · 벡터 있음 · 자동 가림 아님을 이미 거른다(`20260928050000_add_university_card_opens_at.sql:165-199`) — **아직 안 열린 학교뿐인 11/2 전에는 받을 사람이 0 이라 점검 대상이 아니다** |
| ② | `stuck_rooms` | `matches` 중 `trust_passed_at is null and chat_closed_at is null and created_at < now() - p_room_hours 시간` 이면서 **참가자 둘 다 `left_at is null` 이고 둘의 `profiles.status` 가 `suspended`/`withdrawn` 이 아닌 것**(배치가 그런 방은 일부러 건너뜀) | 매시 배치가 48시간 뒤 닫는다(`chat/batch_router.py:21-27, 52-57`, `chat/gate.py:11`, `is_gone` `gate.py:27-35`) |
| ③ | `overdue_withdrawn` | `profiles` 중 `status='withdrawn' and withdrawn_at < now() - p_withdrawn_days 일` | 탈퇴 30일 뒤 하루 한 번 04:00 에 최대 100명 정리(`account/batch_router.py:21, 28-30, 71-72`), `withdrawn_at` 은 status 와 짝 check(`20260927010100…sql:13-14`) |
| ④ | `avatar_failures` | `profile_avatars` 중 `status='failed' and created_at >= now() - p_avatar_hours 시간` | `avatar_status` 열거형(`20260920043723_add_avatar_schema.sql:2,18`), 실패 기록 `profile_onboarding/repository.py:171-183, tasks_router.py:75` |
| ⑤ | `stuck_pushes` | `pending_pushes` 중 `created_at < now() - p_push_hours 시간` | 조용한 시간(22~08)에 쌓고 08시 이후 매시 배치가 보내고 지운다(`20261003010000_create_pending_pushes.sql:1-4`, `cards/push.py:211-238`) → 최대 10시간 정상 |

  환불 배치는 DB 흔적이 없어 이 함수에 없다(Task 5 응답의 `unobservable`).

- [ ] **Step 1: pgTAP 먼저** — 모양(invoker · `search_path` · service_role 만) + 인자 범위(`p_cards_grace_minutes` −1 · 1441, 나머지 0 · 1001 → 22023). **시험이 실행 시각에 흔들리지 않게** 시험용 지역(`region_group_settings` 한 줄, 요일 · 시각을 시험이 정함 — `card_issue_owners()` 에 잡히는 사람 준비는 `supabase/tests/cohort_open_test.sql:60-78` 의 `profile_vectors` 준비를 본뜬다)을 쓴다: 오늘 요일만 지급 요일에 넣고(`extract(isodow from (now() at time zone 'Asia/Seoul'))`), `issue_time='00:00'`, `p_cards_grace_minutes=0` 이면 "점검 대상", 오늘이 아닌 요일만 넣거나 `p_cards_grace_minutes=1440`(→ 내일 0시 = 지금은 항상 이전)이면 "점검 대상 아님"이 된다.
  - `cards check flags a due region with eligible owners and no card today`: `cards_checked` +1, `cards_missing` +1.
  - `cards check is clean once a card was issued today`: 그 지역 사람에게 오늘 `issued_at` 의 `daily` 카드를 넣으면 `cards_missing` +0(`cards_checked` +1).
  - `cards check skips a region on a non-issue weekday` · `cards check skips before issue time plus grace` · `cards check skips a region whose schools are not open yet`(받을 사람이 `card_issue_owners()` 에 없다 — 학교 `card_opens_at` 이 미래): 셋 다 `cards_checked` +0.
  - `cards check ignores purchased cards and other regions`: `source='purchased'` 오늘 카드 · 다른 지역에 나간 카드는 그 지역의 "오늘 지급분" 이 아니다(여전히 missing).
  - `stuck rooms count rooms past the deadline`: 51시간 전 매칭(참가자 둘 모두 남아 있음)은 +1, 10시간 전 · `trust_passed_at` 있음 · `chat_closed_at` 있음은 안 센다. `stuck rooms ignore rooms the batch skips on purpose`: 한쪽 `left_at` · 한쪽 `suspended` · 한쪽 `withdrawn` 인 방은 안 센다. `stuck rooms honor p_room_hours`: 같은 방이 `p_room_hours=60` 이면 안 센다.
  - `overdue withdrawn counts only withdrawn past the cutoff`: 32일 전 탈퇴 +1, 30일 전 탈퇴(인자 31) · 활성 프로필은 안 센다.
  - `avatar failures count failed rows inside the window`: 2시간 전 `failed` +1, `ready` · `pending` · 30시간 전 `failed` 는 안 센다.
  - `stuck pushes count rows older than the window`: 13시간 전 +1, 1시간 전은 안 센다.
- [ ] **Step 2: 구현** — 구역 ①②③④⑤ 를 한 함수 안 `select … into` 로 채워 `return query`/`return next`. ① 은 지역 `for` 루프(지역 수가 한 자리라 루프로 충분 — `shortcut:` 주석). 비교 시각은 모두 `now()` 기준 timestamptz, 날짜 경계만 KST.
- [ ] **Step 3: Commit** `🗃️ db(admin): 운영 상태판 읽기 함수(admin_health)` / 시험은 따로.

---

### Task 3: 마이그레이션 ③ — 매칭 현황 함수 셋 + pgTAP 마무리

**Files:**
- Modify: `supabase/migrations/20261018150000_admin_stats_matching.sql`
- Modify: `supabase/tests/admin_stats_matching_test.sql`(여기서 `plan(N)` 을 스크립트로 맞춘다 — 확인문 수를 세어 한 번에)

**Interfaces (Produces):**
- `public.admin_matching_summary() returns table (accepts_today integer, accepts_yesterday integer, accepts_total bigint, accepters_total bigint, matches_total bigint, shared_total bigint)` — 한 행. 수락 = `card_decisions.decision='accept'`(무료 · 유료 카드 모두, `decided_at` 의 KST 날짜로 오늘 · 어제). `accepters_total` = 수락한 카드의 `daily_cards.owner_id` 중복 없는 수. `matches_total` = `matches` 줄 수. `shared_total` = `trust_passed_at is not null` 인 줄 수(= 카톡 아이디 공유 완료 쌍 — 설계 §8-4c).
- `public.admin_matching_daily(p_days integer) returns table (day date, accept_count integer, match_count integer, share_count integer)` — 항상 `p_days` 줄. 수락 = `card_decisions` accept 의 `decided_at`, 매칭 = `matches.created_at`, 카톡 공유 = `matches.trust_passed_at`(**공유가 끝난 날**에 센다 — 매칭된 날이 아니다), 모두 KST 날짜.
- `public.admin_matching_pairs(p_status text, p_university uuid, p_before_at timestamptz, p_before_id uuid, p_limit integer) returns table (match_id uuid, matched_at timestamptz, status text, shared_at timestamptz, a_id uuid, a_nickname text, a_university text, b_id uuid, b_nickname text, b_university text)`:
  - `status` 파생: `shared` = `trust_passed_at is not null` / `closed` = 공유 전이고 (`chat_closed_at is not null` 이거나 참가자 중 `left_at is not null` 인 사람이 있음) / `chatting` = 그 밖. → 대장 결정 7(빌더 판단).
  - `p_status` 는 null(전체) 또는 위 셋 — 다른 글자 22023. `p_university` null(전체) 아니면 **A 또는 B 의 학교**가 그것인 매칭. 커서는 `p_before_at` · `p_before_id` 가 **둘 다 null 이거나 둘 다 값**(하나만이면 22023)이고, 값이면 `(m.created_at, m.id) < (p_before_at, p_before_id)`. `p_limit` 1~101(밖 22023). `matched_at desc, match_id desc`.
  - A = `profile_a`, B = `profile_b`(항상 `a < b` 정렬이라 시간순 의미 없음 — 화면은 그대로 "A ↔ B"). 반환 칸은 위 목록이 **전부**다 — 사진 · 카톡 아이디 · 대화 · 전화 칸을 함수에 두지 않는다.

- [ ] **Step 1: pgTAP 먼저**
  - 모양: 새 함수 3개 invoker · `search_path=""` · service_role 만 · authenticated 42501. 파일 끝에서 **새 함수 8개 전부**의 권한을 한 번에 검사하는 루프 하나(`has_function_privilege` anon/authenticated/public 거짓 · service_role 참).
  - `summary counts accepts by kst day and ignores rejects`: KST 오늘 00:30 수락 · 어제 23:30 수락 · reject 한 건 → `accepts_today` +1, `accepts_yesterday` +1, `accepts_total` +2. `summary counts accepters once`: 같은 사람이 카드 둘을 수락해도 `accepters_total` +1. `summary matches and shared`: `matches_total` +차이, `shared_total` 은 `trust_passed_at` 있는 줄만.
  - `matching daily returns exactly p_days rows zero filled` · `matching daily counts each event on its own kst day`(수락 어제 · 매칭 어제 · 공유 오늘 → 어제의 `accept_count`·`match_count`, 오늘의 `share_count`) · `matching daily rejects bad days`(0 · 91 · null).
  - `pairs ordered newest first with id tie break`: 같은 `created_at` 두 줄은 id 큰 쪽이 먼저. `pairs cursor returns only older rows`: 첫 쪽 마지막 줄을 커서로 주면 그 줄 이후만 나오고 겹치지 않는다. `pairs cursor needs both parts`: `p_before_at` 만 주면 22023.
  - `pairs status filter follows the derived status`: 공유 → `shared`, 한 사람 `left_at` → `closed`, `chat_closed_at` → `closed`, 둘 다 없음 → `chatting`, 공유된 방에서 한 사람이 나가도 여전히 `shared`. `pairs unknown status is 22023`(`ended` · `shared,closed`).
  - `pairs university filter matches either side`: A 쪽 학교로도 B 쪽 학교로도 그 매칭이 나온다.
  - `pairs show nicknames and university names`: `a_nickname` · `a_university` · `b_*` 가 채워진다.
  - `pairs result columns are exactly the allowed list`: `pg_get_function_result('public.admin_matching_pairs(text,uuid,timestamptz,uuid,integer)'::regprocedure)` 가 위 반환 칸 목록과 글자까지 같다(사진 · 카톡 · 대화 칸이 슬쩍 추가되면 이 시험이 떨어진다).
  - `pairs limit is bounded`: 0 · 102 → 22023, 1 → 한 줄.
- [ ] **Step 2: 구현** — 세 함수. `pairs` 는 `matches m join public.profiles a on a.id = m.profile_a join public.profiles b on b.id = m.profile_b left join public.universities ua/ub`, 파생 상태는 `case` 한 곳(필터와 반환이 같은 식을 쓰게 CTE 로). `shortcut:` 주석: `matches` 전체 훑기 — 1만 줄 넘으면 `(created_at desc, id desc)` 인덱스.
- [ ] **Step 3: `plan(N)` 맞추고 대장에게 pgTAP 요청** — 코더는 돌리지 않는다. 대장 pgTAP 때 함께 `explain` 으로 `admin_stats_daily` · `admin_matching_pairs` 가 의도한 인덱스를 타는지 보면 좋다.
- [ ] **Step 4: Commit** `🗃️ db(admin): 매칭 현황 읽기 함수(요약 · 일별 · 누가 누구랑)` / 시험은 따로.

---

### Task 4: 서버 — 통계 · 일별 그래프 · 미등록 도메인 · 학교별 현황

**Files:**
- Create: `backend/app/admin/stats_repository.py`(`class AdminStatsRepository(AdminRepository)`), `backend/app/admin/stats.py`(라우터 prefix 없이 `/stats` · `/stats/daily` · `/unknown-domains` · `/universities` — 서버는 `APIRouter()` 로 만들고 경로에 글자를 직접 쓴다), `backend/tests/admin/stats_world.py`
- Modify: `backend/app/admin/router.py`(include 한 줄)
- Test: `backend/tests/admin/test_admin_stats.py`

**Interfaces:**
- Consumes: Task 1 의 함수 네 개(`admin_stats_overview` · `admin_stats_daily` · `admin_unknown_domains` · `admin_universities_status`), `AdminCaller` · `get_admin_caller`, `AdminRepository._rpc`(이름 · 본문만 넘김).
- `AdminStatsRepository`: `overview() -> dict`(`_rpc("admin_stats_overview", {})` 의 첫 줄), `daily(days: int) -> list[dict]`, `unknown_domains(limit: int) -> list[dict]`, `universities(include_empty: bool) -> list[dict]`, `health(...)`(Task 5 가 더함).
- `stats_world.py`: `class StatsWorld(AdminWorld)` — `handle()` 이 `/rest/v1/rpc/admin_stats_` · `admin_unknown_domains` · `admin_universities_status` · `admin_health` · `admin_matching_` 로 시작하는 POST 를 **먼저** 받아 `self.rpcs` 에 `(이름, 본문)` 을 쌓고 `self.rpc_results.get(이름, [])`(오류는 `rpc_error_code`)를 돌려준다. 나머지는 `super().handle()`. 모든 `test_admin_*` 시험 모듈이 이 가짜를 쓰게 모듈 안에서 `world` 픽스처를 다시 정의한다(`@pytest.fixture def world(): return StatsWorld()`). `admin_world.py` · `conftest.py` 는 고치지 않는다.
- Produces(웹 W4 가 쓰는 JSON — 필드 이름은 이 표 그대로):

| 경로 | 요청 | 응답 |
|---|---|---|
| `GET /admin/stats` | — | `{"profiles":{"pending","active","suspended","withdrawn"}, "open_reports", "pending_proofs", "signups_today", "signups_7d"}` — 전부 int, 관리자 제외 |
| `GET /admin/stats/daily?days=30` | `days` 1~90 | `{"days":[{"date":"2026-10-18","male_signups","female_signups","report_count","proof_count"}]}` 오래된 순, 정확히 `days` 줄 |
| `GET /admin/unknown-domains?limit=200` | `limit` 1~500 | `{"items":[{"domain","attempt_count","first_seen_at","last_seen_at"}]}` 많은 순, 이미 등록된 도메인 제외 |
| `GET /admin/universities?include_empty=false` | `include_empty` bool | `{"items":[{"id","name","region_group","card_opens_at","is_open","male_active","female_active"}]}` 활성 많은 순 |

  W4 화면 연결: A2 카드 3개 = `pending_proofs`(검수 대기) · `open_reports`(열린 신고) · `signups_today`(오늘 가입). 가입 추이 선 그래프(30일, 남/여) = `daily` 의 `male_signups` · `female_signups`. 접수량 막대(최근 14일, 신고/인증샷) = **같은 `daily?days=30` 응답의 마지막 14줄**(`report_count` · `proof_count`)을 화면이 잘라 쓴다(경로를 따로 만들지 않는다). 학교별 활성 인원 막대 · 학교별 현황 표 = `universities`(같은 숫자). A6 표 = `unknown-domains`(`attempt_count` = "시도 횟수", `last_seen_at` = "마지막 시도"; 하단 문구 "많은 순 · 읽기 전용"은 화면).

- [ ] **Step 1: 실패하는 시험** — `test_admin_stats.py`(가짜는 경로 + params 키로 가른다 — 메모 `reference_backend_test_mock_traps` ① · 설정 덮기는 람다 — ②):
  - `test_every_stats_route_is_behind_the_admin_gate`: 네 경로 × (로그인 안 함 401 · 2단계 전 403 `mfa_required` · 관리자 아님 403 `not_admin`), 그때 `world.rpcs == []`.
  - `test_stats_maps_the_single_db_row_to_the_screen_shape`: DB 한 행 → 위 표 모양(`profiles` 중첩 · 이름 바꿈) · RPC 는 `("admin_stats_overview", {})`.
  - `test_daily_renames_day_to_date_and_keeps_every_row` · `test_daily_defaults_to_thirty_days`(`("admin_stats_daily", {"p_days": 30})`) · `test_daily_days_is_bounded`(0 · 91 → 422, RPC 없음).
  - `test_unknown_domains_passes_rows_with_exactly_the_four_keys`: DB 줄에 `email_prefix` 같은 엉뚱한 키를 넣어도 응답에 없다 · 기본 `p_limit` 200 · `limit` 0 / 501 → 422(RPC 없음).
  - `test_universities_passes_include_empty_as_a_boolean`: 기본 `{"p_include_empty": False}`, `?include_empty=true` → `True`, `?include_empty=maybe` → 422.
  - `test_a_db_rule_violation_is_422`: `rpc_error_code="22023"` → 422. `test_db_failure_is_500_not_empty`: RPC 500 이 빈 통계로 가려지지 않는다.
  - `test_stats_reads_are_never_recorded`: 위 모든 요청 뒤 `world.actions == []`.
- [ ] **Step 2: RED 확인** — `pytest backend/tests/admin/test_admin_stats.py -q` 가 `404`(라우터 없음)나 import 오류로 실패하는 것을 눈으로 본다(루트 `.venv` 파이썬, `-c "import app; print(app.__file__)"` 로 읽는 트리 확인).
- [ ] **Step 3: 구현** — `stats_repository.py` · `stats.py` · `router.py` include. 응답은 명시적 dict 로 만든다(DB 줄을 그대로 흘리지 않는다). `days` · `limit` 은 `Query(…, ge=, le=)`. 한 줄짜리 DB 응답이 비면(`overview` 가 `[]`) 500 이 되게 둔다(삼키지 않음).
- [ ] **Step 4: GREEN + 관문 · 경로 이름 확인** — 위 파일 통과, 그리고 `pytest backend/tests/admin/test_admin_caller.py backend/tests/admin/test_admin_route_names.py -q`.
- [ ] **Step 5: Commit** 저장소 / 라우터 / 시험(가짜 포함) 으로 나눠서.

---

### Task 5: 서버 — 운영 상태판 `GET /admin/health`

**Files:**
- Create: `backend/app/admin/health.py`(라우터 · 기준값 상수 · 판정 함수)
- Modify: `backend/app/admin/stats_repository.py`(`health()` 추가), `backend/app/admin/router.py`
- Test: `backend/tests/admin/test_admin_health.py`

**Interfaces:**
- Consumes: Task 2 `admin_health(...)`, `get_now`(`app.core.deps` — 시험이 `world.now` 로 덮는다).
- 기준값 상수(`health.py` 위쪽 한 곳 — **대장 결정 1 의 값, 마이그레이션 없이 여기만 고친다**):
  - 창: `CARDS_GRACE_MINUTES = 60` · `ROOM_HOURS = 50` · `WITHDRAWN_DAYS = 31` · `AVATAR_HOURS = 24` · `PUSH_HOURS = 12`
  - 판정 `THRESHOLDS: dict[str, tuple[int, int]]`(키 → (경고, 위험) 최소 개수): `stuck_chat_rooms (1, 5)` · `overdue_withdrawn (1, 100)` · `avatar_failures_24h (1, 3)` · `stuck_pending_pushes (1, 20)`. 카드(①)는 개수 기준 없이 `missing ≥ 1` 이면 위험.
- `status_for(count, warn, alert) -> "ok" | "warn" | "alert"` — `count >= alert` 위험, `>= warn` 경고, 아니면 정상. 카드(①)는 `cards_checked == 0` 이면 `"na"`(지금은 점검 대상 아님: 지급 요일 아님 · 지급 시각 전 · 받을 사람 없음), `cards_missing >= 1` 이면 `"alert"`, 아니면 `"ok"`.
- Produces:

| 경로 | 응답 |
|---|---|
| `GET /admin/health` | `{"checked_at": "2026-10-18T09:00:00+09:00", "items":[{"key","status","count"}×5], "unobservable":["refund_batch"]}` |

  - `items` 순서 = 화면 순서: `cards_issued_today`(count = 못 받은 지역 수) · `stuck_chat_rooms` · `overdue_withdrawn` · `avatar_failures_24h` · `stuck_pending_pushes`. `status` ∈ `ok` · `warn` · `alert` · `na`(① 만). 문구 · 단위("2개" · "4건")는 화면이 키로 정한다.
  - `unobservable` = 서버가 못 보는 점검 목록. `refund_batch`(환불 배치는 DB 흔적이 없다 — 설계 §8-4 (E)) 가 늘 들어 있고, 화면이 "여기서 볼 수 없어요(로그에서 확인)" 문구를 이 값으로 띄운다.

- [ ] **Step 1: 실패하는 시험** — `test_admin_health.py`:
  - `test_health_is_behind_the_admin_gate`(401 · 403 × 2, RPC 없음).
  - `test_health_sends_the_threshold_windows_to_the_db`: RPC 본문이 정확히 `{"p_cards_grace_minutes": 60, "p_room_hours": 50, "p_withdrawn_days": 31, "p_avatar_hours": 24, "p_push_hours": 12}`.
  - `test_status_boundaries`(parametrize): 각 항목 개수 0 → ok, 경고 경계 − 1 → ok, 경고 경계 → warn, 위험 경계 − 1 → warn, 위험 경계 → alert(표 네 줄).
  - `test_cards_not_due_is_na_not_ok_and_not_an_alert`: `cards_checked=0, cards_missing=0` → `na`(11/2 전 오탐 방지가 서버 쪽에서 뒤집히지 않는다). `test_cards_checked_and_nothing_missing_is_ok` · `test_cards_missing_is_alert_with_the_region_count`(`count == 2`).
  - `test_items_are_in_screen_order_and_always_five`; `test_refund_batch_is_always_listed_as_unobservable`; `test_checked_at_is_the_request_time`(`get_now` 덮기).
  - `test_health_db_failure_is_500_not_all_clear`: RPC 500 이 "전부 정상" 으로 보이지 않는다.
- [ ] **Step 2: RED 확인** — 라우터가 없어 실패하는 것을 본다.
- [ ] **Step 3: 구현** — 상수 · `status_for` · 라우터 · 저장소 `health()`(상수 인자를 본문으로).
- [ ] **Step 4: GREEN + 관문 · 경로 이름 확인**(Task 4 Step 4 와 같은 두 파일 포함).
- [ ] **Step 5: Commit** 라우터 / 시험 으로 나눠서.

---

### Task 6: 서버 — 매칭 현황 `summary` · `daily` · `pairs` + 최종 확인

**Files:**
- Create: `backend/app/admin/cursor.py`(커서 도우미), `backend/app/admin/matching_repository.py`(`class AdminMatchingRepository(AdminRepository)`), `backend/app/admin/matching.py`(라우터 `/matching/*`)
- Modify: `backend/app/admin/action_log.py`(`_cursor` · `_bad` 를 `cursor.py` 로 옮기고 import — **동작 불변**, `tests/admin/test_admin_action_log.py` 가 그대로 통과해야 한다), `backend/app/admin/router.py`
- Test: `backend/tests/admin/test_admin_matching.py`(+ 기존 `test_admin_action_log.py` 무변경 통과)

**Interfaces:**
- Consumes: Task 3 의 세 함수, `cursor.parse(value: str) -> tuple[str, str]`(= 옮긴 `_cursor`: `{created_at}|{id}` → (시각 문자열, 표준 하이픈 UUID), 시각 · UUID 로 읽히는 것만, `,` `(` `)` 있으면 422 `INVALID_INPUT`), `cursor.bad() -> HTTPException`(422 `INVALID_INPUT`).
- `AdminMatchingRepository`: `summary() -> dict`, `daily(days) -> list[dict]`, `pairs(status, university, before, limit) -> list[dict]`(`limit` 은 부르는 쪽이 `+1` 해서 넘김 — `action_log` 의 "다음 쪽 있나" 방식).
- Produces:

| 경로 | 요청 | 응답 |
|---|---|---|
| `GET /admin/matching/summary` | — | `{"accepts_today","accepts_yesterday","accepts_total","accepters_total","matches_total","shared_total","share_rate"}` — `share_rate` = `shared_total / matches_total`(0~1 소수), **`matches_total == 0` 이면 `null`**(0 으로 나누지 않는다). 화면이 "62%" 로 바꾼다 |
| `GET /admin/matching/daily?days=30` | `days` 1~90 | `{"days":[{"date","accept_count","match_count","share_count"}]}` 오래된 순, 정확히 `days` 줄 |
| `GET /admin/matching/pairs?status=&university=&limit=50&before=` | `status` ∈ `chatting` · `shared` · `closed`(없으면 전체), `university` = 학교 UUID(없으면 전체), `limit` 1~100, `before` = `{matched_at}\|{id}` | `{"items":[Pair], "next_before": "{matched_at}\|{match_id}" \| null}` |

  - `Pair = {"id": 매칭 id, "matched_at", "status": "chatting"|"shared"|"closed", "shared_at": … | null, "a": {"id","nickname","university"}, "b": {"id","nickname","university"}}` — `a`/`b` 의 `id` 는 화면이 닉네임을 눌러 사용자 상세(A5)로 가는 데 쓴다. **이 밖의 칸은 없다.** 한 줄 더 읽어 다음 쪽이 있을 때만 `next_before` 를 채운다.
  - W4 화면 연결: A9 숫자 카드 4개 = `accepts_today` / `accepts_total`(어제 `accepts_yesterday` 부제) · `accepters_total` · `matches_total` · `shared_total` + `share_rate`. 추이 선 그래프(수락 · 매칭 · 카톡 공유, 30일) = `daily`. 목록 · 칩(전체 / 대화 중 / 카톡 공유 완료 / 닫힘) = `pairs?status=`. "전체 학교" 드롭다운 = `GET /admin/universities?include_empty=true` 의 `id` · `name`.

- [ ] **Step 1: 실패하는 시험** — `test_admin_matching.py`:
  - `test_every_matching_route_is_behind_the_admin_gate`(세 경로 × 401 · 403 × 2, RPC 없음).
  - `test_summary_passes_numbers_and_computes_the_share_rate`: 41 / 67 → `share_rate` 가 `41/67`(`pytest.approx`) · RPC `("admin_matching_summary", {})`. `test_summary_with_no_matches_has_a_null_share_rate`(0 으로 나누지 않음, 500 아님).
  - `test_matching_daily_renames_day_to_date` · `…_defaults_to_thirty_days` · `…_days_is_bounded`(0 · 91).
  - `test_pairs_sends_typed_params_and_asks_for_one_extra_row`: 기본 → RPC 본문 `{"p_status": None, "p_university": None, "p_before_at": None, "p_before_id": None, "p_limit": 51}`; 필터를 주면 `p_status="shared"` · `p_university="<uuid 문자열>"` · 커서가 `p_before_at` · `p_before_id`(표준 하이픈 UUID)로 갈라져 간다.
  - `test_pairs_more_rows_give_a_cursor_and_the_last_page_gives_null`: DB 가 51줄 → 응답 50줄 + `next_before == f"{50번째 matched_at}|{50번째 id}"`, 50줄 이하 → `null`.
  - `test_pairs_never_pass_through_unlisted_columns`: 가짜 DB 줄에 `kakao_id` · `photo_path` · `last_message` · `phone` 을 섞어도 응답 `Pair` 의 키가 정확히 `{"id","matched_at","status","shared_at","a","b"}`, `a`/`b` 의 키가 정확히 `{"id","nickname","university"}`(응답 본문 글자에도 없다).
  - `test_bad_filters_never_reach_the_db`(parametrize): `status=ended` · `status=shared,or=(id.eq.1)` · `status=` · `university=not-a-uuid` · `university=1,or=(x)` · `before=garbage` · `before=2026-10-18T00:00:00+00:00|` · `before=x,y|11111111-0000-0000-0000-000000000001` · `limit=0` · `limit=101` → 전부 422 이고 `world.rpcs == []`. `status` · `university` · `before` 오류 본문(`INVALID_INPUT`)에 보낸 값이 되돌아오지 않는다(핸들러가 직접 검사하므로 FastAPI 기본 422 의 입력 반사가 없다).
  - `test_the_cursor_id_is_normalised_to_the_standard_hyphenated_form`(`{…}` · `urn:uuid:` · 하이픈 없는 꼴이 필터로 그대로 가지 않음 — `action_log` 시험과 같은 약속).
  - `test_pairs_talks_only_to_rpc`: 모든 요청 중 `/rest/v1/matches` · `/rest/v1/profiles` 직접 조회 0(필터 문법이 끼어들 PostgREST 표 조회 자체가 없다), `world.actions == []`(목록 보기는 기록하지 않는다 — 설계 §8-4c).
  - `test_action_log_still_uses_the_shared_cursor_helpers`: `tests/admin/test_admin_action_log.py` 전체가 무변경 통과(별도 시험이 아니라 Step 4 의 실행 항목).
- [ ] **Step 2: RED 확인** — 라우터가 없어 실패하는 것을 본다.
- [ ] **Step 3: 구현** — `cursor.py` 로 `_cursor` · `_bad` 를 옮기고 `action_log.py` 가 import(본문 불변) → 저장소 → 라우터. 필터 검사는 `status` 를 `str | None` 으로 받아 `{"chatting","shared","closed"}` 멤버십으로 직접 검사(빈 문자열도 422), `university` 는 `str | None` 으로 받아 `UUID()` 로 읽고 실패하면 `cursor.bad()`(FastAPI 기본 검사가 입력을 되돌리지 않게).
- [ ] **Step 4: 전체 확인** — 루트 `.venv` 파이썬(`backend/.venv/Scripts/python.exe`)으로 ① `pytest -q`(backend 전체) ② `pytest tests/admin -q` 에서 D3 끝 기준(398) 대비 새 시험 수 ③ `tests/admin/test_admin_caller.py::test_every_admin_route_goes_through_the_admin_gate` · `test_admin_route_names.py` ④ `python -m pytest e2e/test_area4_extra.py e2e/test_area3_safe.py -q`(`test_51` 이 main 에서도 같은 두 줄로 실패하는 기존 문제인지 확인만, D3 편차 기록 참고). 프런트엔드 · `admin_web` 은 건드리지 않아 `flutter analyze` · `flutter test` 는 돌리지 않는다(변경 파일 목록으로 증명). pgTAP 은 대장 차례.
- [ ] **Step 5: 구현 편차 기록** 이 계획서 맨 끝 "구현 편차 기록" 절에 덧붙이고(본문은 고치지 않는다) **Commit** 공용 커서 도우미 이동 / 저장소 / 라우터 / 시험 으로 나눠서.

---

## 하지 않을 것

웹 화면 W4(응답 모양만 정함), 작업 기록 화면 A7 의 검색 · 이름 바꿈(서버 `GET /admin/actions` 는 D3 그대로), 학교 · 도메인 · 카드 오픈 시각 편집(승인 받는 SQL), 환불 배치 점검(DB 흔적 없음), 가입 중인(성별 미선택) 프로필의 별도 선, 매칭 상세 · 대화 · 사진 보기, 매칭 목록 열람 기록 · 법률 확인 목록 문서 갱신(campus-docs), 상태판 알림 · 이메일 발송, 통계 캐시, 추천 많이 한 사람 · 동의 판 현황(설계 2판 이후).

---

## 대장 결정 필요 (추측 금지 — 아래는 계획서에 넣은 기본값이며, 이의 없으면 그대로 구현)

1. **상태판 기준값**(서버 상수라 나중에 마이그레이션 없이 바꿈) — 추천:
   ① 카드: 지급 요일 + 07:00 + **60분** 뒤에도 받을 사람이 있는데 오늘 카드 0장이면 위험 · ② 안 닫힌 방: 48시간 + 배치 여유 2시간 = **50시간** 지난 방이 **1개↑ 경고, 5개↑ 위험**(pen 시안 "2개" 노랑과 맞음) · ③ 탈퇴 **31일** 넘은 프로필 **1명↑ 경고, 100명↑ 위험**(하루 정리 한도 100) · ④ 아바타 실패 최근 24시간 **1건↑ 경고, 3건↑ 위험**(pen "4건" 빨강과 맞음) · ⑤ 보류 푸시 **12시간**(정상 최대 10시간 + 2) 넘은 것 **1건↑ 경고, 20건↑ 위험**.
2. **그래프 기간 선택지** — 추천: 서버는 1~90일을 받고, 화면은 **30일 고정**(접수량 막대는 그중 최근 14일을 잘라 씀, 기간 단추 없음). 7/30/90 단추를 원하면 W4 만 늘어난다(서버는 이미 지원).
3. **학교별 현황에 비활성 학교 포함 여부** — 추천: 기본은 **활성 1명 이상이거나 카드 오픈 시각이 정해진 학교만**(지금 65곳 중 대부분이 0명이라 표가 길어짐 · 11/2 오픈 예정 학교는 0명이어도 보여야 함), `include_empty=true` 로 전체. 그 밖에 "전체 학교"가 항상 나와야 하면 알려 주세요(함수는 이미 둘 다 지원).
4. **"가입"의 정의** — 추천: `profiles.created_at`(KST 날짜) 기준, **성별을 고른 사람만** 남/여로 세고, 정지 · 탈퇴 상태도 센다, 관리자 제외, "오늘 가입" 카드 = 남+여. 대안: 활성(`active`)만 — 활성이 된 시각을 적어 둔 칸이 없어 날짜를 못 잡고, 탈퇴하면 과거 숫자가 줄어서 비추천.
5. **미등록 도메인 목록에서 이미 등록된 도메인 숨김** — 추천: **숨김**(등록 뒤에도 시도 기록이 남아 계속 "미등록" 으로 보이는 혼란 방지). 상위 200개(상한 500).
6. **인덱스** — 추천: `daily_cards (issued_at desc)` **1개만** 추가(홈을 열 때마다 "오늘 지급분"을 찾는 가장 큰 표). 나머지는 현재 규모에서 훑기로 두고 코드 주석에 올릴 기준(profiles 5만 · matches 1만)을 적음. 지금 인덱스를 더 원하면 알려 주세요.
7. **(빌더 판단, 이의 없으면 그대로)** 매칭 "닫힘" 상태 = 공유 전이고 (`chat_closed_at` 있음 **또는 한 사람이라도 방을 나감**) / 공유가 끝난 방은 이후 누가 나가도 "카톡 공유 완료" 유지 / 정지 · 탈퇴 중인 사람은 상태에 반영하지 않음(닉네임은 그대로 보임) · 수락 수 = 무료 + 유료 카드 모두 · `accepters_total` 은 누적 · 카톡 공유 날짜 = 공유가 끝난 날.
8. **설계서와 달라진 점(알림)** — ① §8-4c 는 pairs 를 "PostgREST 임베드"로 적었으나 **DB 함수**로 바꿨다(학교 필터가 A 또는 B 쪽이고 상태가 세 칸에서 파생돼 PostgREST 필터로 안전하게 못 쓰며, 타입 있는 인자라야 주입이 구조적으로 불가능). ② §8-4 의 `GET /admin/stats` · `/health` · `/universities` 도 개수 · 조건 비교 때문에 함수로 간다. 둘 다 "새 표 없음 · 읽기 전용" 원칙 안.
9. **(W4 쪽 알림)** pen A7 검색칸 "관리자 · 대상 id 검색" — 서버 `GET /admin/actions` 는 관리자를 **UUID** 로만 거르고(이메일 검색 없음) 대상은 id 정확 일치. 추천: 칸 문구를 "대상 id 검색"으로(pen 수정은 campus-pen). 이메일로 관리자를 찾는 기능은 auth 관리자 API 가 필요해 비추천(관리자는 1명).

**확정(대장 10-18)**: 결정 1~8 모두 추천 안 그대로 확정(상태판 기준값 · 그래프 서버 1~90일 / 화면 30일 · 학교별 기본 필터 · 가입 정의 · 등록 도메인 숨김 · 인덱스 1개 · 빌더 판단 · DB 함수 방식). 9번(A7 검색칸 문구)은 W4 때 pen 과 함께 고친다.

## 구현 편차 기록 (코더가 이 아래에 덧붙임)


- **대장 DB 차례(10-18)로 pgTAP 을 코더가 직접 돌림**: Task 1~3 각각 시험을 먼저 쓰고 RED(함수 없음 오류로 파일이 멈춤)를 본 뒤 마이그레이션을 더해 GREEN. `supabase db reset` → 새 파일 단독 81건 PASS, 전체 `supabase test db` Files=37 Tests=1139 PASS. 시험은 개수를 "넣기 전과 뒤의 차이"(`before_*` 임시 표)로 단정한다. 처음 돌렸을 때 Task 1 의 3건이 떨어진 것은 함수 버그가 아니라 시험 준비 인원을 잘못 센 기대값(따로 센 지역 두 명 · 예정 학교 두 명을 빼먹음)이라 기대값을 고쳤다(함수는 그대로).
- **상태판 ① 의 오늘 지급분 조회를 `with today as materialized (…)` 로 씀(계획의 단순 join 에서 바뀜)**: 합성 데이터(프로필 3만 · 카드 30만, 롤백)로 `explain analyze` 해 보니 단순 join 은 `daily_cards_issued_at_index` 를 안 타고 프로필 3만 줄을 훑으며 사람마다 `daily_cards_owner_issued_index` 를 찾았다(오늘 카드가 0장일 때 **117 ms**, 인덱스 없이도 비슷 172 ms). 오늘 카드를 먼저 모으는 materialized CTE 로 바꾸니 새 인덱스를 타고 **0.9 ms**. 0장인 경우가 바로 경고가 필요한 경우라 이 모양을 택했다. 인덱스 1개는 계획 그대로.
- **explain 요약(합성 3만 프로필 · 3만 매칭 · 30만 카드, 함수 한 번 호출 시간)**: 통계 숫자 15 ms · 일별 12 ms · 학교별 32 ms · 매칭 요약 8 ms · 매칭 일별 20 ms · 매칭 목록 51줄 65 ms(안쪽은 `matches` 전체 훑기 + top-N 정렬 8 ms 수준, 나머지는 프로필 조인). 수락 일별은 `card_decisions_decided_at_index` 를 탄다. 지금 규모(수십 명)에서는 의미 없고, `shortcut:` 주석에 올릴 기준(profiles 5만 · matches 1만)을 적었다. 상태판 함수 전체 시간은 합성 데이터에 받을 사람(`card_issue_owners`)이 없어 ① 경로를 못 탔으므로 위 ① 조회 단독 측정을 근거로 삼는다.
- **`admin_universities_status` 안쪽 CTE 칸 이름**을 `uid · uname · ugroup · uopens` 로 지음(반환 칸 `id · name …` 과 겹쳐 plpgsql 이 모호하다고 할 위험을 피함). 반환 칸은 계획 그대로.
- **`open_reports` · `pending_proofs`** 는 신고자 · 제출자가 누구든 센다(처리할 일의 양) — 계획 표의 "상태 = open / submitted" 와 같고, 관리자 제외는 프로필 개수 · 가입 · 일별 신고 · 인증샷 · 학교별 활성에만 적용된다(SQL 주석에 이유).
- **시험 가짜**: `tests/admin/stats_world.py` 의 `StatsWorld` 기본 응답은 `[]` 이라 한 줄짜리 함수(`overview` · `health` · `matching summary`)를 부르는 시험은 `rpc_results` 에 한 줄을 넣어야 한다(비어 있으면 저장소의 `[0]` 이 IndexError → 서버 500, 삼키지 않음). `admin_world.py` · `conftest.py` · `repository.py` 는 고치지 않았다(D2b 와 충돌 없음).
- **공용 커서 도우미 이동**: `action_log.py` 의 `_cursor` · `_bad` 를 `app/admin/cursor.py` 의 `parse` · `bad` 로 옮기고 안 쓰게 된 import 셋(`datetime` · `HTTPException` · `errors`)을 지웠다. 동작 불변 — `tests/admin/test_admin_action_log.py` 무변경 통과(계획 Task 6 의 `test_action_log_still_uses_the_shared_cursor_helpers` 는 별도 시험 대신 이 기존 시험으로 갈음). pairs 의 `before` 는 쿼리에서 `+` 가 공백으로 풀리므로 클라이언트(W4)가 퍼센트 인코딩해야 한다(Dart `Uri(queryParameters:)` 는 자동).
- **`rls_slice0_test.sql`** 은 `grep -n "routine\|admin_stats"` 결과 없음 — 손대지 않음(새 표 · 표 권한 변경 없음).
- **전체 확인(10-18 코더)**: backend `pytest -q` 2856 passed(exit 0), `tests/admin` 518 passed(D3 끝 398 → +120), `test_admin_route_names.py` · `test_admin_caller.py` 54 passed 중 경로 이름 · 관문 시험 통과. `e2e/test_area4_extra.py` + `e2e/test_area3_safe.py` 130 중 1 실패 = `test_51_route_list_is_exactly_the_servers_verified_routes`(`GET /home/people` · `GET /cards/acceptances/{card_id}` 두 줄, **main 루트에서도 똑같이 실패하는 기존 문제**이고 이 조각이 `get_verified_caller` 경로를 늘리지 않았다). 프런트엔드 · `admin_web` 은 건드리지 않아 `flutter analyze` · `flutter test` 는 돌리지 않았다.
- **독립 검토 반영 ① 상태판 ① 판정 변경(대장 결정 10-18)**: 목적을 "지급 배치가 아예 안 돌았는지" 로 바꿨다. `admin_health` 의 반환 칸 `cards_missing`(점검 대상 중 0장인 지역 수)을 `cards_issued`(점검 대상 중 오늘 무료 카드가 한 장이라도 나간 지역 수)로 바꿨고, 점검 대상은 "지급 요일 · 시각 + 여유가 지난 지역 중 (오늘 카드가 나갔거나 받을 사람이 있는 지역)". 이전 판은 모두에게 지급된 날 `card_issue_owners()` 가 비어(카드를 다 받은 사람은 빠진다) "점검 대상 없음 = 해당 없음" 으로 보이는 버그가 있었다. 서버 판정: 점검 대상 0 → `na`, `cards_issued >= 1` → `ok`(일부 지역만 0장은 경고 안 함), 점검 대상이 있는데 0 → `alert`(count = 점검 대상 지역 수). SQL 주석도 같게 고쳤다. 시험: pgTAP 81 → 83건(모두 지급 · 일부 지역만 0장 · 받을 사람 있는데 전체 0장 · 받을 사람 없음), pytest `test_some_regions_without_cards_is_still_ok` 등.
- **독립 검토 반영 ② 중앙 관문 시험 맹점**: FastAPI 0.141 은 `include_router` 한 라우터를 접두사 없이 중첩 객체(`original_router` + `include_context.prefix`)로 들고 있어, 이전 `_routes` 가 하위 라우터 경로를 `/admin` 없이 보고 `/admin/me` 하나만 검사하고 있었다(D1~D4 경로 전부 맹점, 실제 admin 경로 23개). `tests/admin/test_admin_caller.py` 의 `_routes` 가 접두사를 이어 붙이게 고치고, `test_the_central_gate_test_sees_every_admin_route`(걸린 (메서드, 경로) 집합 == `app.openapi()` 의 admin 연산 집합, 1 보다 큼)와 실제로 모든 admin 경로를 불러 보는 `test_every_admin_route_answers_401_without_a_login_and_403_not_admin_for_a_stranger` 를 더했다. `/admin/universities` 에서 `Depends(get_admin_caller)` 를 빼 보니 구조 시험과 호출 시험이 모두 RED 였고(복원 뒤 GREEN) 직접 확인했다.
- **독립 검토 반영 ③ 커서 시각 모양**: `app/admin/cursor.py` 의 `parse` 가 `datetime.fromisoformat` 만 믿어 `2026-W42-1T00:00:00` · 날짜만 · 기본 꼴을 받고 DB 에서 500 이 났다. 표준 `YYYY-MM-DDTHH:MM:SS(.ffffff)(±HH:MM|Z)`(ASCII 숫자만)만 받고 나머지는 422. 작업 기록(`test_admin_action_log.py`)과 매칭 pairs(`test_admin_matching.py`) 양쪽에 비표준 꼴 거절 · 표준 꼴 수락 시험을 더했다. 기존의 `,()` 포함 검사는 모양 검사가 덮어 없앴다.
- **2026-10-27 확장(PR #631, 이 계획서와 별개로 계획서 없이 들어왔다) — A9 매칭 현황 맨 아래 "누가 누구에게 대화를 신청했나"**: §8-4c 의 pairs 는 서로 수락해 **성립한 매칭 쌍**만 보여 줘서 한쪽만 신청하고 끝난 신청이 안 보였다. 그래서 읽기 함수 `admin_matching_requests(p_status, p_before_at, p_before_id, p_limit)`(마이그레이션 `20261027100000`, 새 표 없음, `service_role` 만 실행)와 서버 `GET /admin/matching/requests`, 화면 구역을 더했다. 상태 4종(`waiting` · `accepted` · `rejected` · `expired`)은 앱 "보낸 신청"(`_sent_state`, 7일 만료)과 같은 규칙이고, 반환 칸 10개에는 사진 · 카톡 · 대화 · 전화가 없다. `20261018150000` 의 "관리자 계정(`admin_users`)은 통계에서 뺀다"(설계 §6-5)와 달리 **이 함수는 관리자 계정을 따로 거르지 않는다**. 운영 적용 DB 97개 · 서버 `00092-2zr`(`backend/DEPLOY.md` §4-16). 후속(사소): 수락 + 매칭인 줄의 응답 시각을 매칭 시각으로 맞출지, 배지 색 · 간격 pen 대조. 본문은 고치지 않았다.
