# 관리자 대시보드 D3 — 사용자 · 학교 메일 찾기 · 메모 · 하트 조정 · 탈퇴 대행 · 열람 · 결제 조회 · 작업 기록 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 웹 대시보드에서 사용자를 찾고(닉네임 · id · 학교 메일) 상세를 보고, 메모 · 하트 조정 · 앱 밖 탈퇴 대행 · 전화/카톡 열람을 하고, 결제를 조회하고(주문 번호 · 못 거둔 하트 · 매출 · 30일 그래프), 작업 기록을 본다.

**Architecture:** DB 를 바꾸는 조치(하트 조정 · 탈퇴 대행)마다 plpgsql 함수 하나(조건부 변경 + `admin_actions` insert 를 한 트랜잭션, 설계 §8 머리)를 마이그레이션 한 파일에 둔다. DB 변경이 기록 한 줄뿐인 동작(메모 · 열람)은 서버가 `admin_actions` insert 한 번. 읽기는 PostgREST, 날짜 묶음 집계와 두 열 비교가 필요한 결제 읽기 둘만 읽기 전용 DB 함수. 탈퇴 대행은 DB 함수(`withdraw_account` 재사용)를 **먼저** 부른 뒤 바깥 정리(푸시 토큰 · 인증 파일 · 카카오 연결)를 best-effort 로 하고 결과를 별도 기록 한 줄로 남긴다.

**Tech Stack:** Postgres(plpgsql, pgTAP) · FastAPI + httpx(PostgREST · auth admin API · Storage · 카카오 연결 끊기).

**Spec:** 바탕화면 `C:/Users/user/OneDrive/Desktop/관리자_대시보드_설계_10-18.md` §2 · §8 머리 · §8 경로 이름 규칙 · §8-3 전부 · §8-4b 중 `GET /admin/billing/daily` · §8-5 전부(작업 기록 보기 포함) · §11 D3 · §14. 화면 응답 모양 근거: `…/CampusMate_문서/디자인_pen/관리자_대시보드/` 의 `A5_사용자_찾기` · `A5_사용자_상세` · `A5_하트_조정_대화상자` · `A5_탈퇴_대행_대화상자` · `A5_전화카톡_열람_대화상자` · `A5_메모_대화상자` · `A7_작업_기록` · `A8_결제_조회`(PNG 를 읽기만 함, pen 값은 W3 몫). 모양 · 관례의 기준: D1 `2026-10-18-admin-heart-task-review.md` · D2 `2026-10-18-admin-report-review.md`(구현 편차 기록 포함).

**범위:** 서버 · DB 만. 웹 화면(W3)은 아래 응답 JSON 모양만 정하고 구현하지 않는다. 작업 기록 화면(A7)은 W4 지만 서버 읽기(`GET /admin/actions`)는 설계 §8-5 대로 여기서 만든다.

## Global Constraints

- 운영 DB 적용 · 서버 배포 금지. 코더는 로컬 DB 명령(`supabase db reset` · `test db` · `start`)도 돌리지 않는다 — pgTAP 은 대장 차례.
- 새 외부 의존성 금지. 공유 파일(`backend/app/main.py` · `settings.py` · `core/errors.py`)은 고치지 않는다 — 라우터는 `backend/app/admin/router.py` 에 붙인다.
- 새 마이그레이션은 **한 파일** `supabase/migrations/20261018120000_admin_users_billing.sql`(시각 20261018100000 은 다른 PR 이 씀). 함수 전부 `security invoker` + `set search_path = ''` + `revoke all … from public, anon, authenticated` 뒤 `grant execute … to service_role` 만(`security definer` 금지). 조치 함수는 맨 앞에서 `perform public.admin_assert(p_admin)`(D2 보안 보강 `20261018035204`).
- DB 오류 약속(D2 와 같음): 없음 `CM404`(서버 404 `not_found`) · 이미 그 상태 / 막힌 상태 `CM409`(서버 409) · 규칙 위반 `22023`(서버 422) · 관리자 아님 `42501`(서버 403 `not_admin`). `CM409` 는 DB 오류 **message** 로 서버 코드를 가른다: `insufficient hearts` → `insufficient_hearts`, `profile withdrawn` → `account_withdrawn`, 그 밖 → `already_done`.
- **관리자 계정(`admin_users`)은 사용자 기능에서 존재하지 않는 것으로 본다**(설계 §6-5 "관리자 프로필은 사용자 검색에서 뺀다"): 목록에서 빠지고, 상세 · 메모 · 하트 · 탈퇴 · 열람은 404.
- 서버 경로 이름에 `e2e/area4_extra.py:38-44` 금지어(`refund` · `cashout` · `transfer` · `gift` · `send_heart` · `send-heart` · `exchange` · `heart_withdraw` · `heart-withdraw` · `hearts/withdraw`)와 구매 단어(`purchase` · `buy` · `unlock` · `heart_store` · `heart-store`)를 **부분 문자열로도** 쓰지 않는다(e2e 는 `w in path`). `withdraw` 도 쓰지 않는다. 경로: `/admin/users…` · `/admin/users/{id}/close-account` · `/admin/billing/orders/search` · `/admin/billing/shortfall` · `/admin/billing/summary` · `/admin/billing/daily` · `/admin/actions`.
- 모든 관리자 경로는 `Depends(get_admin_caller)`. `get_verified_caller` 금지(`e2e/test_area3_safe.py::test_51` 경로 목록이 늘지 않게).
- **학교 메일 원문**: 요청 본문으로만 받고(GET 쿼리 금지 — 설계 §14-3), 응답 · 로그 · 작업 기록 · 예외 메시지 · 422 본문에 되돌리지 않는다. 해시는 `signup_policy.hash_email(settings.identity_hmac_key, email)` + `bytea_literal`. 검색은 `school_email_claims` **정확히 일치만**, 작업 기록에 남기지 않는다(pen "검색어는 기록되지 않아요").
- 사유: 하트 조정 · 탈퇴 대행 · 열람은 `reason` 필수(`app.admin.reason.Reason` — 공백 뗀 1~500자). 메모 글자도 같은 `Reason`(1~500자, 대장 결정 4).
- 하트 조정 한 번 상한 `ADJUST_MAX`(대장 결정 1, 임시 1000). DB 함수가 진짜 관문이고(`c_max_adjust` 상수), 서버 값은 같은 숫자를 빠르게 422 로 돌리는 용도(`# DB 함수 c_max_adjust 와 같은 값` 주석).
- 열람 응답은 `Cache-Control: no-store` + `Pragma: no-cache`. 전화 · 카톡 · 복호화 키는 로그 · 기록 · URL 에 없다(키는 JSON 본문으로만 DB 에 간다 — `encryption.py` 와 같은 이유).
- 시험 결제(`purchases.is_test`)는 매출 · 못 거둔 하트 목록에서 뺀다. 주문 번호로 **직접 찾을 때만** 보이고 `is_test` 칸을 싣는다.
- 날짜는 한국 시간(`Asia/Seoul`) 하루 단위, 데이터 없는 날은 0.
- 커밋 · PR 에 도구 표식 금지. 디스코드 알림에는 번호만(이 조각은 알림을 건드리지 않음).

## Review Focus

1. **학교 메일 원문이 새는 길** — 검색 요청의 응답(200 · 빈 결과 · 422) · 로그(httpx 포함) · 작업 기록 · 예외. 탈퇴 대행의 `verified_by` 칸에 사람이 메일 주소를 적어 기록으로 새는 길(→ `@` 포함 시 422). → Task 2 `test_school_email_never_reaches_response_logs_or_actions`, Task 5 `test_verified_by_with_an_at_sign_is_422`.
2. **동시 하트 조정 · 사용자가 쓰는 도중 조정** — 잔액 행을 `for update` 로 잠근 채 판단해 음수 불가, 모자라면 CM409 이고 원장 · 잔액 · 기록이 모두 그대로. → Task 1 pgTAP `minus over balance raises CM409 and changes nothing`.
3. **관리자 자신 · 다른 관리자 대상 조치** — 검색 · 상세 · 메모 · 하트 · 탈퇴 · 열람 모두 404(관리자 프로필이 탈퇴 대행으로 지워지거나 하트가 조정되면 안 된다). → Task 1 pgTAP `admin target is CM404`, Task 2 · 4 · 5 pytest.
4. **이미 탈퇴한 계정** — 탈퇴 대행 · 하트 조정 · 열람은 409 `account_withdrawn`(상세 · 메모는 허용: 탈퇴 뒤 문의 응대). 정지 중 탈퇴는 재가입 무기한 차단 경고(`rejoin_blocked: "forever"`). → Task 1 pgTAP, Task 4 · 5 pytest.
5. **결제 숫자의 함정** — 시험 결제 제외, 환불 구매는 매출에서 빼고 따로 표시, 계정이 지워진 구매는 못 거둔 하트로 세지 않음, 한국 시간 자정 경계, 탈퇴 대행의 바깥 정리가 일부 실패해도 200 + 별도 기록 한 줄(실패했다고 다시 부르면 409 라 재시도가 안 되므로). → Task 1 pgTAP `kst midnight boundary` · `shortfall excludes ...`, Task 5 `test_outside_cleanup_failure_still_closes_and_is_recorded`.

---

### Task 1: 마이그레이션 — 하트 조정 · 탈퇴 대행 · 결제 읽기 함수 넷 + 주문 번호 인덱스

**Files:**
- Create: `supabase/migrations/20261018120000_admin_users_billing.sql`
- Create: `supabase/tests/admin_users_billing_test.sql`
- 손대지 않음: `supabase/tests/rls_slice0_test.sql` — 새 표 · 표 권한 변경이 없다(그 시험은 표 · 시퀀스 · 컬럼 권한만 나열, 함수 권한 목록 없음). 코더는 Step 1 끝에 `grep -n "routine\|admin_adjust" supabase/tests/rls_slice0_test.sql` 로 확인만 하고 결과를 편차 기록에 한 줄 남긴다.

**Interfaces (Produces):**
- `public.admin_adjust_hearts(p_admin uuid, p_profile uuid, p_amount integer, p_reason text, p_ip inet) returns jsonb` → `{"id","amount","heart_balance","action_id"}`.
  - 순서: `admin_assert` → `p_amount` null · 0 · `abs > c_max_adjust` · 사유 공백이면 22023 → 대상 행 없음 CM404 · 관리자 대상 CM404 · `status='withdrawn'` CM409(`profile withdrawn`) → 잔액 행 `select … from entitlements where profile_id = p_profile for update`(없으면 0) → `p_amount < 0` 이고 잔액이 모자라면 CM409(`insufficient hearts`) → `admin_actions` insert(`action='hearts_adjust'`, `target_type='profile'`, `before={"heart_balance":n}`, `after={"heart_balance":n+amount,"amount":amount}`, 사유 · ip) `returning id` → `grant_hearts(p_profile, p_amount, 'admin_adjust', 그 id)`(기존 함수 · 음수 받음 — `20260928020000_fix_grant_hearts_spend.sql`; 원장 `ref_id` 가 기록 id 와 이어진다).
- `public.admin_close_account(p_admin uuid, p_profile uuid, p_email_hmac bytea, p_key_version smallint, p_reason text, p_verified_by text, p_ip inet) returns jsonb` → `{"id","was_status","status":"withdrawn","rejoin_blocked":"none"|"two_months"|"forever"}`.
  - 순서: `admin_assert` → 사유 · `p_verified_by` 공백이거나 `p_verified_by` 200자 초과 22023 → 대상 행 `for update`(없음 CM404 · 관리자 대상 CM404 · 이미 `withdrawn` CM409 `profile withdrawn`) → `perform public.withdraw_account(p_profile, p_email_hmac, p_key_version)`(기존 함수 그대로 재사용 · 멱등) → **맨 마지막에** `admin_actions` insert(`action='account_close'`, `before={"status":직전}`, `after={"status":"withdrawn","rejoin_blocked":…,"verified_by":…}`, 사유 · ip). `rejoin_blocked` = `p_email_hmac is null` → `none`, 직전이 `suspended` → `forever`, 아니면 `two_months`(`withdraw_account` 규칙 `20261008040000` 와 같음). 기록을 마지막에 두는 이유: 기록이 실패하면 탈퇴도 함께 되돌아간다(시험이 이 성질을 쓴다).
- `public.admin_billing_daily(p_days integer) returns table(day date, revenue_krw bigint, order_count integer, refunded_krw bigint)` — plpgsql · `stable`. `p_days` 가 null · 1 미만 · 90 초과면 22023. 오늘(KST)까지 `p_days` 개 날짜를 오래된 순으로 **항상 `p_days` 줄**(`generate_series` + left join, 없는 날 0). 날짜 = `(purchased_at at time zone 'Asia/Seoul')::date`. `is_test` 구매는 어느 칸에도 넣지 않는다. `revenue_krw` · `order_count` = `status='granted'` 의 `price_krw` 합 · 건수, `refunded_krw` = `status='refunded'` 의 `price_krw` 합.
- `public.admin_billing_shortfall(p_limit integer) returns table(purchase_id uuid, profile_id uuid, nickname text, store public.store_platform, product_id text, heart_amount integer, bonus_hearts integer, clawed_back_hearts integer, granted_hearts integer, shortfall_hearts integer, purchased_at timestamptz, refunded_at timestamptz)` — `p_limit` 1~500 밖이면 22023. 조건: `status='refunded'` · `profile_id is not null`(지워진 계정은 회수할 사람이 없다 — `refund_store_purchase` 의 shortfall 0 규칙) · `not is_test` · `coalesce(clawed_back_hearts,0) < heart_amount + bonus_hearts`. `granted_hearts = heart_amount + bonus_hearts`, `shortfall_hearts = granted_hearts - coalesce(clawed_back_hearts,0)`. `refunded_at desc`.
- `create index purchases_store_order_id_index on public.purchases (store_order_id) where store_order_id is not null` — 주문 번호 정확 일치 조회(없으면 표 전체 훑기).
- 상한 상수: 함수 안 `c_max_adjust constant integer := 1000;`(**대장 결정 1 로 값이 바뀔 수 있다 — 바뀌면 이 한 줄과 pgTAP 의 경계값 두 개, 서버 `ADJUST_MAX` 만 고친다**).

- [ ] **Step 1: pgTAP 먼저** — `admin_users_billing_test.sql`(D2 시험의 준비 모양 · `plan` 수는 스크립트로 맞춘다):
  - 모양: 네 함수 모두 invoker · `search_path=""`, `service_role` 만 execute(anon · authenticated · public 없음, `has_function_privilege`), 인덱스 존재(`has_index`).
  - `adjust plus adds balance one ledger row and one record`: 잔액 10 + 50 → 60, `heart_transactions` 1줄(50 · `admin_adjust` · `ref_id` = 기록 id), `admin_actions` 1줄(`hearts_adjust` · before 10 · after 60 · 사유 · ip). 반환 `action_id` 가 그 기록 id.
  - `adjust creates the balance row when missing`: 잔액 행이 없는 사람에게 +20 → 20.
  - `minus within balance works`: 60 에서 −20 → 40.
  - `minus over balance raises CM409 and changes nothing`(message `insufficient hearts`): 잔액 · 원장 줄 수 · 기록 줄 수가 전과 같다.
  - 규칙: 0 · `c_max_adjust + 1` · `−(c_max_adjust + 1)` 22023, `+c_max_adjust` 는 통과, 공백 사유 22023, 사유 501자 → 23514 이고 잔액 · 원장 그대로(기록이 실패하면 지급도 없던 일), 없는 id CM404, **`admin target is CM404`**(관리자 본인 프로필 · `admin_users` 의 다른 id), 탈퇴 계정 CM409(message `profile withdrawn`), `p_admin` 이 관리자가 아니면 42501.
  - `close active user blocks rejoin for two months`: 상태 `withdrawn`(`withdrawn_at` 있음), `signup_blocks` 에 해시 한 줄 `blocked_until` 이 `now()+1.9개월` ~ `now()+2.1개월`, 반환 `two_months`, 기록 `account_close` 1줄(before `active` · after `verified_by` 포함 · 사유).
  - `close suspended user blocks rejoin forever`: `blocked_until = 'infinity'`, 반환 `forever`.
  - `close without email hash leaves no block`: `p_email_hmac null` → `signup_blocks` 줄 없음, 반환 `none`, 그래도 탈퇴됨.
  - `close twice raises CM409`, 없는 id CM404, `admin target is CM404`, 공백 사유 · 공백 `verified_by` · 201자 `verified_by` 22023, 비관리자 42501, **사유 501자 → 23514 이고 상태가 그대로**(기록이 마지막이라 탈퇴까지 되돌아감).
  - `billing daily returns exactly p_days rows zero filled`: `days=3` → 3줄 · 오름차순 · 마지막 = 오늘(KST), 구매 없는 날 0.
  - `billing daily buckets by kst midnight`: KST 00:30 에 산 구매는 그 KST 날짜에, 직전 23:30 은 전날에(UTC 로는 같은 날이어도).
  - `billing daily excludes test and separates refunded`: `is_test` 구매는 어느 칸에도 없고, `refunded` 구매는 `refunded_krw` 에만(매출 · 건수에 안 들어감).
  - `billing daily rejects bad days`: 0 · 91 · null 22023.
  - `shortfall lists only partially clawed back real refunds`: 부분 회수(100 지급 · 60 회수 → `shortfall_hearts` 40, `granted_hearts` 에 보너스 포함)만 나오고, 전부 회수 · `granted` 구매 · `is_test` · `profile_id null` 은 안 나온다. `refunded_at` 최근 순, `p_limit` 0 · 501 22023, `nickname` 이 채워진다.
  - 앱 역할: authenticated · anon 이 네 함수를 부르면 42501.
- [ ] **Step 2: 마이그레이션 구현** — D2 `20261018030000` 의 머리 주석 · 잠금 · `jsonb_build_object` · `revoke … grant` 모양 그대로. 한 문장에서 잠금 순서: 하트 조정은 프로필 행(읽기 `select status … for update`) → 잔액 행 순서, 탈퇴 대행은 프로필 행만. 읽기 함수 둘은 `language plpgsql stable`(검사 때문에 plpgsql) + `return query`. Supabase best-practices: 주문 번호 인덱스는 부분 인덱스, 함수 안 `set search_path = ''` 이므로 모든 객체에 `public.` 을 붙인다.
- [ ] **Step 3: 대장에게 pgTAP 실행 요청** — 코더는 돌리지 않는다. plan 수와 확인문 수는 스크립트로 맞춘다(D2 편차 기록 방식).
- [ ] **Step 4: Commit** `🗃️ db(admin): 하트 조정 · 탈퇴 대행과 작업 기록을 한 번에, 결제 읽기 함수` + 시험 커밋 분리.

---

### Task 2: 서버 사용자 읽기 · 학교 메일 찾기 · 메모

**Files:**
- Create: `backend/app/admin/user_repository.py`(`class AdminUserRepository(AdminRepository)` — 이 조각의 사용자 · 하트 · 열람 · 탈퇴 DB 호출), `backend/app/admin/users.py`(라우터 `/users` — 목록 · 검색 · 상세 · 메모)
- Modify: `backend/app/admin/repository.py`(`_rpc` 에 `conflicts` 매개변수, 상수 `INSUFFICIENT_HEARTS` · `ACCOUNT_WITHDRAWN`), `backend/app/admin/router.py`(include)
- Test: `backend/tests/admin/test_admin_users.py`, `backend/tests/admin/admin_world.py`(가짜 응답 — `rpc/admin_` 접두 분기 **앞에** 새 함수 이름 분기를 둬서 D2 의 `_act` 가 새 함수를 가로채지 않게)

**Interfaces:**
- Consumes: `AdminCaller`, `get_admin_caller`, `request_ip`, `Reason`, `AdminRepository.is_admin` · `record_action`, `signup_policy.hash_email` · `bytea_literal`, `SupabaseAdmin.fetch_user`(auth admin API), `app.chat.router.avatar_url(profile, supabase_url)`.
- Produces(웹 W3 가 쓰는 JSON — 필드 이름은 이 표 그대로):

| 경로 | 요청 | 응답 |
|---|---|---|
| `GET /admin/users?q=&limit=50` | `q` 없으면 가입 최근 순. UUID 면 id 일치, 아니면 닉네임 부분 일치(대소문자 무시, LIKE 특수문자 `\` `%` `_` 는 이스케이프, 1~30자). `limit` 1~100. 관리자 제외 | `{"items":[UserSummary]}` |
| `POST /admin/users/search` | `{"school_email": str}` | `{"items":[UserSummary]}` (0 또는 1줄, 못 찾아도 200) |
| `GET /admin/users/{id}` | — | `UserDetail`, 없음 · 관리자 404 `not_found` |
| `POST /admin/users/{id}/notes` | `{"text": str}`(`Reason` — 공백 뗀 1~500자) | `{"saved": true}` (웹이 상세를 다시 받는다) |

  - `UserSummary = {id, nickname, university, status, created_at, report_count}` — `nickname` · `university` 는 null 가능(가입 중), `report_count` = 그 사람이 **받은** 신고 수(`reports.target_profile_id`, 목록은 한 번에 묶어 센다).
  - `UserDetail = UserSummary + {last_active_at, auto_hidden_at, avatar_url, school_email_verified, login_providers, heart_balance, contact_block_count, hearts, purchases, notes}`:
    - `avatar_url`: 공개 아바타 URL | null. `school_email_verified`: bool(`profiles.school_email_verified_at is not null`). `login_providers`: `["kakao"]` 같은 provider 목록(auth admin API `identities[].provider` — **로그인 메일 원문은 싣지 않는다**), 조회 실패 시 null(500 아님).
    - `heart_balance`: int(없으면 0). `contact_block_count`: 연락처 차단 **개수**만.
    - `hearts`: 최근 20 `[{id, created_at, amount, reason, balance_after}]` 최근 순. `balance_after` 는 서버가 현재 잔액에서 거슬러 계산(최신 줄 = 현재 잔액, 다음 줄 = 직전 줄의 `balance_after − amount`; 원장 합 = 잔액이라는 ERD 불변식에 기댄다).
    - `purchases`: 최근 20 `[{id, store, product_id, status, is_test, granted_hearts, bonus_hearts, clawed_back_hearts, purchased_at}]` 최근 순. `granted_hearts = heart_amount + bonus_hearts`. 주문 번호 · 토큰 해시는 싣지 않는다.
    - `notes`: 최근 20 `[{id, created_at, admin_user_id, text}]` 최근 순 — `admin_actions` 에서 `action='profile_note'` · `target_type='profile'` · `target_id=id` 의 `reason` 이 text.
- `AdminUserRepository`: `list_users(q, limit, exclude_ids) -> list[dict]`, `admin_ids() -> list[str]`, `count_reports_by_target(ids) -> dict[str,int]`, `find_profile_by_school_email(hmac_literal) -> str | None`, `fetch_user_profile(id) -> dict | None`(universities · profile_avatars 임베드), `count_reports(id)`, `count_contact_blocks(id)`(둘 다 `Prefer: count=exact` + `limit=1` 의 `Content-Range` — `AccountRepository.count_contact_blocks_not_on` 방식), `fetch_heart_balance(id) -> int`, `list_heart_ledger(id, 20)`, `list_purchases(id, 20)`, `list_notes(id, 20)`.

- [ ] **Step 1: 실패하는 시험** — `test_admin_users.py`(가짜는 경로 + params 키로 가른다 — 메모 함정 ① · `get_settings` 덮기는 람다 — 함정 ②):
  - 관문: 네 경로 모두 401 · 403 `mfa_required` · 403 `not_admin`, 그때 DB 호출 없음.
  - 목록: 가입 최근 순 · `limit` 0 / 101 422 · 닉네임 조회에 `ilike` 와 이스케이프된 패턴(`50%` → `50\%`) · UUID 는 id 일치 · **관리자 id 가 `id=not.in.(…)` 로 빠짐**(UUID 로 관리자 id 를 직접 찾아도 `items` 가 빈 목록) · `report_count` 가 PostgREST 한 번으로 묶여 옴.
  - `test_search_by_school_email_finds_by_hmac_only`: 요청의 PostgREST 필터가 `school_email_hmac=eq.\x…`(해시 hex)이고 메일 글자가 URL 에 없다 · 정확히 일치만(`+` 별칭 · 대소문자는 `hash_email` 규칙 그대로 — 대문자 · 앞뒤 공백 입력도 같은 해시) · 못 찾으면 `{"items":[]}` 200 · 관리자 프로필이 걸려도 빠짐.
  - `test_school_email_never_reaches_response_logs_or_actions`: 메일 `alice.test@campus.ac.kr` 로 성공 · 빈 결과 · 모양이 틀린 입력(`@` 없음 → 422, 핸들러가 직접 검사해 `input` 을 되돌리지 않음) · PostgREST 500 네 경우 모두 `caplog`(DEBUG, httpx 포함) · 응답 본문 · 가짜가 받은 모든 요청(URL · 본문) · `world.actions` 어디에도 메일 글자(와 `alice.test`)가 없고 `admin_actions` 에 쓰기가 0 번이다.
  - 상세: 관리자 404 · 없는 id 404 · `login_providers` 가 auth admin 응답의 provider 만(이메일 글자 없음) · auth admin 500 이면 `login_providers: null` 이고 나머지는 200 · `hearts` 의 `balance_after`(현재 120, 줄 +40 · −30 → 120 · 80) · `purchases` 에 주문 번호 · 토큰 해시 키 없음 · `contact_block_count` 는 개수 · 탈퇴한 계정도 상세는 열림(`status: "withdrawn"`) · 학교 메일 인증 전(대학 null) 에도 500 이 아님 · `notes` 의 text 가 `reason` · 요청이 `asyncio.gather` 로 나뉘어도 응답 모양이 같다.
  - 메모: 요청이 `admin_actions` 한 줄(`profile_note` · `target_type='profile'` · `target_id` · `reason`=text · `ip`)뿐이고 `before`/`after` 없음 · 공백뿐 · 0자 · 501자 422(기록 호출 없음) · 관리자 · 없는 사용자 404(기록 없음) · 탈퇴 계정은 저장됨 · 기록 insert 가 실패하면 그 상태 코드가 그대로(422 / 500 — `record_action` 관례).
- [ ] **Step 2: 구현** — `_rpc(self, name, body, already=ALREADY_DONE, conflicts: dict[str, str] | None = None)` 로 CM409 의 `message` 를 `conflicts` 에서 찾는다(기본은 `already`). 학교 메일 검색 본문은 `class SearchBody(BaseModel): school_email: str`(제약 없이 받고 핸들러가 `^[^@\s]+@[^@\s]+\.[^@\s]+$` · 254자로 직접 검사해 422 `INVALID_INPUT`, pydantic 이 입력을 되돌리지 않게). 상세는 `asyncio.gather`. `login_providers` 는 `SupabaseAdmin(caller.settings, caller.client).fetch_user(id)` 에서 `[i["provider"] for i in identities]` 만 뽑고 `httpx.HTTPError` · `KeyError` · `ValueError` 는 null(+ 번호만 경고 로그).
- [ ] **Step 3: 확인** — 루트 `.venv` 파이썬으로 `pytest -q`(워크트리에서 돌릴 때 `-c "import app; print(app.__file__)"` 로 읽는 트리 확인), `tests/admin/test_admin_caller.py::test_every_admin_route_goes_through_the_admin_gate` 포함.
- [ ] **Step 4: Commit** 저장소 / 라우터 / 시험 으로 나눠서.

---

### Task 3: 서버 결제 조회 — 주문 번호 · 못 거둔 하트 · 이번 달 매출 · 30일 그래프

**Files:**
- Create: `backend/app/admin/billing.py`(라우터 `/billing`), `backend/app/admin/billing_repository.py`(`class AdminBillingRepository(AdminRepository)`)
- Modify: `backend/app/admin/router.py`
- Test: `backend/tests/admin/test_admin_billing.py`, `backend/tests/admin/admin_world.py`(`purchases` 줄 · `rpc/admin_billing_*`)

**Interfaces:**
- Consumes: Task 1 의 `admin_billing_daily` · `admin_billing_shortfall`, `core.time.SEOUL`.
- Produces:

| 경로 | 요청 | 응답 |
|---|---|---|
| `POST /admin/billing/orders/search` | `{"order": str}` — 앞뒤 공백 뗀 1~64자, 글자는 `^[A-Za-z0-9._-]+$`(구글 `GPA.1234-5678-9012-34567` · 애플 숫자). 아니면 422(입력 되돌리지 않음) | `{"items":[Order]}` 최근 순 최대 10 |
| `GET /admin/billing/shortfall?limit=100` | `limit` 1~500 | `{"items":[Shortfall]}` |
| `GET /admin/billing/summary` | — | `{"month":"2026-10","revenue_krw":int,"order_count":int,"refunded_krw":int}` — 한국 시간 이번 달 1일부터 오늘까지(= `admin_billing_daily(오늘의 일)` 합) |
| `GET /admin/billing/daily?days=30` | `days` 1~90 | `{"days":[{"date":"2026-10-18","revenue_krw":int,"order_count":int,"refunded_krw":int}]}` 오래된 순, 정확히 `days` 줄 |

  - `Order = {id, store, product_id, store_order_id, status, is_test, heart_amount, bonus_hearts, granted_hearts, clawed_back_hearts, shortfall_hearts, price_krw, purchased_at, granted_at, refunded_at, profile: {id, nickname} | null}`. 애플은 거래 번호가 `store_order_id` 칸에 있다(`apple_router.py` 가 그렇게 넣음). `shortfall_hearts` = 환불됐고 `profile` 이 있을 때만 `granted_hearts − coalesce(clawed_back_hearts,0)`, 그 밖 0. `profile` 은 계정이 지워졌으면 null.
  - `Shortfall = {purchase_id, profile_id, nickname, store, product_id, heart_amount, bonus_hearts, granted_hearts, clawed_back_hearts, shortfall_hearts, purchased_at, refunded_at}` — DB 함수 열 그대로(`purchase_id` 로 이름을 맞춰 W3 가 줄 키로 쓴다).
  - 매출은 `price_krw`(서버 상품표 판매가) 기준이라 스토어 수수료 · 세금 · 환율이 빠진 "표시가 합계"다(대장 결정 5, 화면 문구는 W3 몫).
- `AdminBillingRepository`: `find_orders(order: str, limit=10) -> list[dict]`(`purchases?store_order_id=eq.…&select=…,profiles(id,nickname)`), `billing_daily(days) -> list[dict]`, `billing_shortfall(limit) -> list[dict]`.

- [ ] **Step 1: 실패하는 시험** — 관문(네 경로 401 · 403 두 이유). 주문 검색: 정확히 일치 필터(`store_order_id=eq.`) · 형식 밖(`a b` · 65자 · 공백뿐 · `,` `(`) 422 이고 DB 호출 없음 · 못 찾으면 `[]` 200 · 환불 · 부분 회수 줄의 `shortfall_hearts` · 계정이 지워진 구매의 `profile: null` 과 `shortfall_hearts: 0` · `is_test` 구매도 이 검색에서는 나오고 칸이 `true` · 응답에 토큰 해시 없음. 요약: 시계를 고정해(모듈의 `_today()` 를 덮음) 10/18 이면 `days=18` 로 DB 함수를 부르고 합을 낸다, 10/1 이면 `days=1`, 월말 31 일도 · `month` 문자열. 그래프: `days=0`/`91` 422, DB 줄을 그대로 `date` 키로 바꿔 돌려줌, 줄 수 = `days`. 못 거둔 목록: `limit` 범위, 줄 필드 이름. DB 함수 오류 22023 → 422.
- [ ] **Step 2: 구현** — 요약의 합은 파이썬에서(`sum`). DB 함수의 `day` 는 ISO 날짜 문자열로 오니 키 이름만 `date` 로 바꾼다.
- [ ] **Step 3: 확인 · Step 4: Commit**(Task 2 와 같은 방식) — 별도로 이 Task 끝에서 `e2e/area4_extra.py` 의 경로 이름 검사와 같은 검사를 Task 6 의 시험이 맡는다.

---

### Task 4: 서버 하트 조정 · 전화/카톡 열람

**Files:**
- Create: `backend/app/admin/user_actions.py`(라우터 `/users` — 하트 · 열람 · 탈퇴 대행(Task 5))
- Modify: `backend/app/admin/user_repository.py`(`adjust_hearts` · `decrypt_phone` · `private_contact`), `backend/app/admin/router.py`
- Test: `backend/tests/admin/test_admin_user_actions.py`, `backend/tests/admin/admin_world.py`

**Interfaces:**
- Consumes: Task 1 `admin_adjust_hearts`, Task 2 `_rpc(conflicts=…)`, `PostgrestRepository._read_private(profile_id, ("kakao_id",))`(`encryption_key` 를 넘긴 저장소만), 기존 DB 함수 `decrypt_phone_number(p_profile_id, p_key)` · `decrypt_profile_private`.
- Produces:
  - `POST /admin/users/{id}/hearts` 본문 `{"amount": int, "reason": Reason}`(`amount` 0 · `abs > ADJUST_MAX` 422) → `{"id","amount","heart_balance","action_id"}`. 오류: 없음 · 관리자 404 `not_found`, 잔액 부족 409 `insufficient_hearts`, 탈퇴 409 `account_withdrawn`, 규칙 위반 422.
  - `POST /admin/users/{id}/private` 본문 `{"reason": Reason}` → `{"phone_number": str | null, "kakao_id": str | null}` + 헤더 `Cache-Control: no-store` · `Pragma: no-cache`. 오류: 없음 · 관리자 404, 탈퇴 409 `account_withdrawn`(대장 결정 6), 복호화 실패 500.
- `AdminUserRepository.adjust_hearts(admin, profile_id, amount, reason, ip) -> dict`, `fetch_profile_status(id) -> str | None`, `read_private_contact(id, key) -> dict`(`phone_number` · `kakao_id`).

- [ ] **Step 1: 실패하는 시험** — 관문. 하트: RPC 인자(`p_admin` = caller id · `p_amount` 부호 그대로 · `p_reason` 앞뒤 공백 뗌 · `p_ip`) · `amount` 0 · `ADJUST_MAX+1` · `-(ADJUST_MAX+1)` · 문자열 · 소수 422(RPC 안 부름) · 사유 없음 · 공백 · 501자 422 · 서버가 `heart_transactions` · `entitlements` 를 직접 쓰지 않음(PATCH/POST 0) · CM409 message 가 `insufficient hearts` 면 `insufficient_hearts`, `profile withdrawn` 이면 `account_withdrawn` · CM404 404 · 22023 422 · 42501 `not admin` 403. 열람: `test_private_view_records_first_and_never_stores_values`(기록 insert 가 복호화 RPC 보다 **먼저**(요청 순서), 기록은 `profile_private_view` · `reason` · `ip` 만이고 전화 · 카톡 글자 · 키 글자가 기록 · 로그(caplog) · URL 에 없음) · 기록 insert 실패면 복호화 RPC 를 부르지도 않음 · 응답 헤더 `Cache-Control == "no-store"` · 복호화 키는 JSON 본문으로만 가고 URL 에 없음 · 탈퇴 계정 409 에 기록 · 복호화 호출 없음 · 관리자 · 없는 id 404(기록 없음) · 전화 없음(null) · 카톡 없음(null) 도 200 · 두 번 열면 기록 두 줄.
- [ ] **Step 2: 구현** — 열람 순서: `fetch_profile_status`(404 · 409) → `record_action("profile_private_view", target_type="profile", target_id=…, reason=…, ip=…)` → 복호화. 응답은 `JSONResponse(content, headers={"Cache-Control": "no-store", "Pragma": "no-cache"})`. 이 경로만 `AdminUserRepository(…, encryption_key=settings.phone_encryption_key)` 로 만든다.
- [ ] **Step 3: 확인 · Step 4: Commit** 저장소 / 라우터 / 시험 으로 나눠서.

---

### Task 5: 서버 탈퇴 대행 `close-account` + 카카오 연결 끊기(관리자 갈래)

**Files:**
- Modify: `backend/app/account/social_unlink.py`(관리자 갈래 추가 — 기존 `unlink_kakao` 가 같은 내부 함수를 쓰게 정리, 동작 불변), `backend/app/admin/user_actions.py`(`/close-account`), `backend/app/admin/user_repository.py`(`close_account`)
- Test: `backend/tests/admin/test_admin_close_account.py`, `backend/tests/account/test_withdraw_kakao_unlink.py`(기존 — 그대로 통과해야 한다), 새 갈래 시험은 `backend/tests/account/test_admin_kakao_unlink.py`, `backend/tests/admin/admin_world.py`(auth admin 사용자 · 푸시 토큰 삭제 · Storage 목록 · 카카오 `kapi.kakao.com`)

**Interfaces:**
- Consumes: Task 1 `admin_close_account`, `AccountRepository.fetch_school_email_claim` · `delete_push_tokens`, `SupabaseAdmin.fetch_user` · `empty_folder`, `social_unlink.kakao_member_id`, `signup_policy.IDENTITY_KEY_VERSION`, `AdminRepository.record_action`.
- Produces:
  - `social_unlink.unlink_kakao_for_user(settings, client, user_id) -> bool` — auth 관리자 API(`SupabaseAdmin.fetch_user`)의 identities 에서 `kakao_member_id(...)` 로 회원번호를 읽어 같은 카카오 연결 끊기 호출을 한다. 키(`kakao_admin_key`) 없음 · 카카오 가입 아님 → `False`(할 일 없음), 끊음 → `True`, 실패는 예외. 회원번호는 어디에도 남기지 않는다.
  - `POST /admin/users/{id}/close-account` 본문 `{"reason": Reason, "verified_by": 공백 뗀 1~200자, "@" 없음}` → `{"id","was_status","status":"withdrawn","rejoin_blocked":"none"|"two_months"|"forever","cleanup":{"push_tokens":"ok"|"failed","student_id_files":"ok"|"failed","kakao_unlink":"ok"|"failed"|"skipped"},"not_done":["apple_revoke","logout_everywhere"]}`. 오류: 없음 · 관리자 404, 이미 탈퇴 409 `account_withdrawn`, 학교 메일 인증 기록을 못 읽으면 503(`AUTH_UNAVAILABLE`, **아무것도 바꾸기 전에**), 규칙 위반 422.
  - 정지 중 계정 경고 = 응답 `rejoin_blocked == "forever"` + (확인 대화상자용) 상세 `status == "suspended"`(Task 2).
- 흐름(순서가 곧 약속):
  1. `AccountRepository.fetch_school_email_claim(id)` — `httpx.HTTPError` 면 503. 없으면 해시 `null` · 키 버전 `IDENTITY_KEY_VERSION`(앱 안 탈퇴 `account/router.py` 와 같다).
  2. `admin_close_account` RPC(탈퇴 + 기록 한 줄 `account_close`) — **바깥 호출보다 먼저**.
  3. 바깥 정리 셋을 각각 best-effort(한 단계가 실패해도 다음 단계로, 로그는 `step=` 과 `profile=` 번호만): 푸시 토큰 삭제, `student-id-temp` 폴더 비우기(앱 안 탈퇴와 같은 정리 — 옛 학생증 파일), 카카오 연결 끊기(`unlink_kakao_for_user`, `False` → `skipped`).
  4. 결과를 별도 기록 한 줄(`action="account_close_cleanup"`, `target_type="profile"`, `after=cleanup`, ip)로. 이 기록이 실패해도 응답은 200(이미 탈퇴됨 — 다시 부르면 409)이고 번호만 경고 로그.

- [ ] **Step 1: 실패하는 시험** — 관문. `test_close_account_runs_the_db_function_before_any_outside_call`(`world.requests` 순서: 학교 메일 인증 기록 읽기 → `rpc/admin_close_account` → 푸시 삭제 · Storage · 카카오). RPC 인자(`p_email_hmac` = 인증 기록의 `\x…` 그대로, 기록 없으면 null · `p_key_version` · `p_verified_by` 공백 뗌 · `p_ip`). `test_close_account_claim_read_failure_is_503_and_changes_nothing`(RPC · 바깥 호출 0). `test_verified_by_with_an_at_sign_is_422`(RPC 호출 0 · 응답에 입력 글자 없음) · `verified_by` 201자 · 사유 공백 422. 이미 탈퇴 409 `account_withdrawn`(바깥 호출 0) · 관리자 · 없는 id 404(바깥 호출 0). 정지 중 → 응답 `rejoin_blocked == "forever"`. `test_outside_cleanup_failure_still_closes_and_is_recorded`: 푸시 삭제 500 · 카카오 500 이어도 200, `cleanup` 이 `failed` 로 채워지고 `account_close_cleanup` 기록 한 줄의 `after` 와 같다. 카카오: 가입 방식이 카카오가 아니면 `skipped` · 키 비면 `skipped` · 회원번호가 어떤 기록 · 로그 · 응답에도 없음. `account_close_cleanup` 기록 실패 → 그래도 200. `backend/tests/account/test_withdraw_kakao_unlink.py` 기존 시험 무변경 통과 + 새 `unlink_kakao_for_user` 의 세 갈래(키 없음 / 카카오 아님 / 끊음 · 호출이 `target_id_type=user_id` · `KakaoAK`).
- [ ] **Step 2: 구현** — 위 흐름 그대로. `unlink_kakao` 는 `fetch_auth_user(...)` 로 얻은 사용자로 `_unlink_member(settings, client, member_id)` 를 부르게 앞부분만 고친다(동작 불변).
- [ ] **Step 3: 확인 · Step 4: Commit** `social_unlink` 정리 / 서버 탈퇴 대행 / 시험 으로 나눠서.

---

### Task 6: 서버 작업 기록 보기 `GET /admin/actions` + 경로 이름 · 누수 점검

**Files:**
- Modify: `backend/app/admin/repository.py`(`list_actions`), `backend/app/admin/router.py`
- Create: `backend/app/admin/action_log.py`(라우터 `/actions`)
- Test: `backend/tests/admin/test_admin_action_log.py`, `backend/tests/admin/test_admin_route_names.py`, `backend/tests/admin/admin_world.py`

**Interfaces:**
- Consumes: `admin_actions` 읽기(service_role select 권한 있음), `SupabaseAdmin.fetch_user`(관리자 메일 표시용).
- Produces: `GET /admin/actions?admin=<uuid>&target=<id>&type=<target_type>&limit=50&before=<cursor>` → `{"items":[ActionRow],"next_before": str | null}`.
  - `ActionRow = {id, created_at, admin_user_id, admin_email, action, target_type, target_id, target_nickname, before, after, reason, ip}`. `admin_email`: 그 관리자의 로그인 메일(관리자 본인 정보 — 화면 A7 의 "관리자" 칸; 조회 실패 · 계정 삭제면 null). `target_nickname`: `target_type='profile'` 줄만 그 사람의 닉네임(없으면 null, 한 번에 묶어 조회). 나머지는 표 칸 그대로.
  - `admin` 은 UUID, `target` 은 `target_id` 정확 일치(공백 뗀 1~64자 — 프로필 · 신고 · 제출 id), `type` 은 `target_type` 정확 일치. 최근 순 `created_at.desc,id.desc`, `limit` 1~100(기본 50 — 설계 §12).
  - 쪽 나누기(대장 결정 3 의 추천안): `next_before` = 마지막 줄의 `"{created_at}|{id}"`, 다음 요청의 `before` 로 보내면 `or=(created_at.lt.X,and(created_at.eq.X,id.lt.Y))`. 같은 트랜잭션 줄들은 `created_at` 이 같아서(`now()`) 시각만으로 자르면 줄을 놓친다.
  - 읽기 화면이라 기록을 남기지 않는다.

- [ ] **Step 1: 실패하는 시험** — 관문 · 정렬 · `limit` 범위 · 필터 세 가지(각각 PostgREST 필터로) · 형식 밖 `admin`(UUID 아님) · `before`(모양 아님) 422 · `test_cursor_does_not_skip_rows_sharing_a_timestamp`(같은 `created_at` 줄 셋을 `limit=2` 로 나눠 받아도 셋 모두 한 번씩) · 마지막 쪽 `next_before: null` · `admin_email` 은 관리자 id 마다 auth admin 을 **한 번씩만** 부르고 실패하면 null(500 아님) · `target_nickname` 이 프로필 줄에만 · `before`/`after` jsonb 그대로. `test_admin_route_names_avoid_e2e_forbidden_words`: `app.openapi()` 의 모든 경로(`openapi_url=None` 이어도 호출 가능)를 소문자로 해 `e2e/area4_extra.py` 의 `FORBIDDEN_HEART` · `PURCHASE_WORDS` 가 **부분 문자열로도** 없고 `withdraw` 도 없음(금지어 목록은 테스트에 복사하되 출처 주석), 그리고 `/cards/paid/{offer_id}/purchase` 하나만 `purchase` 를 가진다.
- [ ] **Step 2: 구현** — Task 2 의 `_rpc` 가 아니라 `_rows` 를 쓴다. 관리자 메일은 `SupabaseAdmin.fetch_user(id)["email"]` 한 칸만 꺼내고 그 응답 나머지를 버린다.
- [ ] **Step 3: 확인** — 루트 `.venv` 파이썬 `pytest -q` 전체, 그리고 `python -m pytest e2e/test_area4_extra.py -q` · `e2e/test_area3_safe.py::test_51_route_list_is_exactly_the_servers_verified_routes`(main 기존 결과 외 새 차이 없음 — `get_verified_caller` 경로가 늘지 않았음).
- [ ] **Step 4: 구현 편차 기록** 이 계획서 맨 끝 "구현 편차 기록" 절에 덧붙이고(본문은 고치지 않는다) **Commit** 저장소 / 라우터 / 시험 으로 나눠서.

---

## 하지 않을 것

웹 화면 W3(응답 모양만 정함), 작업 기록 화면 A7 · 홈 통계 · 미등록 도메인 · 상태판 · 매칭 현황(D4/W4), 사용자 목록의 상태 · 학교 필터와 정렬 선택, 닉네임 · 학교 메일 외 검색, 메모 수정 · 삭제(작업 기록은 고칠 수 없다), 하트 조정 되돌리기 버튼(반대 부호로 다시 조정), 애플 철회 · 전체 로그아웃 대행(본인 토큰 필요 — 응답 `not_done` 으로 알림), 탈퇴 요청 접수 대장, 결제 환불 번복 자동 처리(사용자 결정 A-6 대기), 구매 토큰 · 영수증 원문 조회, 스토어 수수료 · 세금 반영 매출.

---

## 대장 결정 (10-18 확정 — 아래 번호 순서대로 모두 "추천대로", 4번만 500자로 바뀜)

**확정**: 1 ±1000 · 2 회수 허용(잔액 이하) · 3 50줄 + 더 보기(시각 + id 커서) · **4 메모 상한 500자(`Reason` 과 같은 검사 재사용, `NOTE_MAX` 상수 없음)** · 5 매출(시험 제외, 환불분 따로, `price_krw`, 서버는 숫자만) · 6 탈퇴 계정 열람 409 · 7 `POST /admin/billing/orders/search` · 8 관리자 정지 막기는 D3 밖(대장 후속 목록). 빌더 판단 네 가지도 모두 그대로.

(아래는 결정 당시 원문)

1. **하트 조정 한 번 상한** — 추천 **±1000**(가장 큰 상품 800 + 첫 구매 보너스 50 = 850 을 한 번에 복구할 수 있고, 그 이상은 지금처럼 승인 받는 SQL). 값은 DB 함수 상수 한 줄 · pgTAP 경계값 · 서버 `ADJUST_MAX` 로 바뀐다(계획서의 1000 은 임시).
2. **회수(음수) 허용 여부** — 추천 **허용, 단 잔액 이하만**(모자라면 409 `insufficient_hearts`). 화면 시안(A5 하트 조정)이 "더하거나 빼요. 빼면 잔액이 모자랄 때 거절돼요"라 이미 허용으로 그려져 있다. 허용하지 않으면 `amount > 0` 만 받는다(회수는 SQL).
3. **작업 기록 목록 쪽 나누기** — 추천 **50줄씩 + "더 보기"(시각 · id 커서)**. 대안: 최근 100줄만(쪽 없음, 가장 단순하지만 옛 기록을 서버에서 못 봄).
4. **메모 글자 수 상한** — 추천 **300자**(DB 의 사유 칸 상한 500 이 절대 한도). 상세 화면의 메모 목록이 읽기 편한 길이. 계획서의 300 은 임시.
5. **매출 정의** — 추천 **환불된 구매는 매출에서 빼고 `refunded_krw` 로 따로 표시, 시험 결제 제외, 구매 시각(한국 시간) 기준, 금액은 서버 상품표의 표시가(`price_krw`)**(스토어 수수료 · 세금 · 환율은 반영 안 됨 — 화면 문구로 알림). 환불 포함 총액이 필요하면 `revenue_krw + refunded_krw`.
6. **탈퇴한 계정의 전화 · 카톡 열람** — 추천 **막음(409 `account_withdrawn`)**: 탈퇴 뒤에는 열람 사유가 없고 30일 뒤 지워질 값이다. 신고 · 수사 협조가 필요하면 지금처럼 승인 받는 SQL.
7. **설계서 안의 충돌** — §8-5 는 `GET /admin/billing/orders?order=`, §8-3(보안 검토 10-18)은 "결제 주문 번호 검색도 같은 방식(본문)". 계획서는 보안 검토를 따라 **`POST /admin/billing/orders/search`** 로 했다. 이의가 없으면 그대로.
8. **(참고, D3 범위 밖)** D2 `admin_suspend_profile` 은 관리자 본인 · 다른 관리자도 정지할 수 있다(정지는 관문에 영향이 없어 위험 낮음). 막으려면 D3 마이그레이션에 `create or replace` 한 줄을 더하면 된다 — 하지 않는 쪽이 추천(D2 PR 이 운영에 아직 적용 전이라 D2 쪽 수정이 더 깔끔).

빌더 판단(이의 없으면 그대로): 탈퇴 대행 `verified_by` 칸에 `@` 가 있으면 422(메일 원문이 작업 기록에 남는 것을 막음), 못 거둔 하트 목록에서 시험 결제 제외, 작업 기록 동작 이름 `hearts_adjust` · `account_close` · `account_close_cleanup` · `profile_note` · `profile_private_view`(설계의 "note 동작" 은 `profile_*` 이름 규칙에 맞춰 `profile_note`).

## 구현 편차 기록 (코더가 이 아래에 덧붙임)

- **메모 상한 500자(대장 결정 4)**: `NOTE_MAX` 상수 없이 `Reason`(1~500자)을 그대로 재사용(`users.py` `NoteBody.text`). 계획 본문의 300 은 쓰지 않았다.
- **`rls_slice0_test.sql` 은 손대지 않음**: `grep -n "routine\|admin_adjust" supabase/tests/rls_slice0_test.sql` 가 아무것도 찾지 못했다(표 · 시퀀스 · 컬럼 권한 목록뿐, 새 표 없음).
- **Task 5 새 갈래 시험 위치**: `backend/tests/account/test_admin_kakao_unlink.py` 가 아니라 `backend/tests/admin/test_admin_kakao_unlink.py`(가짜 세상 `settings()` 를 같은 폴더가 쓴다). 기존 `tests/account/test_withdraw_kakao_unlink.py` 는 무변경 통과. 이 시험은 `unlink_kakao_for_user` 를 먼저 쓰고 나중에 썼다 — 함수 한 줄(`_unlink_member` 호출)을 지워 두 시험이 떨어지는 것을 보아 RED 를 확인했다.
- **`_rpc` 에 `conflicts` 매개변수**: CM409 의 DB 오류 `message`(`insufficient hearts` · `profile withdrawn`)로 서버 이유 코드를 가른다(`repository.py`). D1 · D2 호출은 기본값 `already` 라 무변경.
- **pgTAP 시험 준비의 닉네임**: `profiles_nickname_format`(한글 · 영문 2~5자)에 걸려 `유저a`~`유저g` 로 지었다. 못 거둔 하트 기대값의 닉네임도 `유저a`(F1) · `유저b`(F2).
- **`last_active_at` · 구매 `granted_at`** 등 응답 필드는 계획 표 그대로. 작업 기록 `GET /admin/actions` 의 `next_before` 는 한 줄 더 읽어(`limit+1`) 다음 쪽이 있을 때만 채운다(마지막 쪽에서 헛 "더 보기" 가 없다).
- **가짜 세상(`admin_world.py`)**: D3 요청은 `_d3()` 한 곳에서 받고 D2 의 `rpc/admin_` 접두 분기 앞에 둔다. 시험마다 설정을 바꾸는 `settings_overrides`(conftest 람다가 요청마다 읽음)와 경로 단위 실패 `table_status` 를 더했다. purchases 응답은 `select` 에 적힌 칸만 남겨 "서버가 주문 번호 · 토큰 해시를 고르지 않았다" 를 시험이 볼 수 있다.
- **사용자 목록의 신고 수**: PostgREST 응답 상한(기본 1000줄)을 넘으면 세던 값이 잘린다 — `shortcut:` 주석(`user_repository.count_reports_by_target`).
- **전체 확인(10-18 코더)**: 루트 `.venv` 파이썬 `pytest -q`(backend) 2700 passed, `tests/admin` 398 passed(D2 끝 234 → +164). pgTAP `supabase db reset` 뒤 `supabase test db` Files=35 Tests=1053 PASS(새 파일 56). `e2e/test_area4_extra.py` + `e2e/test_area3_safe.py` 130 중 1 실패 — `test_51_route_list_is_exactly_the_servers_verified_routes` 가 main 에서도 똑같이(`GET /home/people` · `GET /cards/acceptances/{card_id}` 두 줄) 실패하는 기존 문제이고 D3 가 `get_verified_caller` 경로를 늘리지 않았다. 프런트엔드는 건드리지 않아 `flutter analyze` · `flutter test` 는 돌리지 않았다.
- **독립 검토 반영(10-18)**: 작업 기록 커서의 id 를 `str(UUID(last_id))` 로 정규화해 필터에 넣는다(`{…}` · `urn:uuid:` · 하이픈 없는 꼴이 그대로 나가지 않음, `test_the_cursor_id_is_normalised_to_the_standard_hyphenated_form`). 주문 번호가 로그 · 오류 본문 · 작업 기록에 남지 않는 시험 추가(`test_order_number_never_reaches_response_logs_or_actions`).
