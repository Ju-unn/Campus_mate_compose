# 관리자 대시보드 D1+W1 — 인증샷 검수 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 웹 대시보드에서 에브리타임 홍보 · 단톡방 공유 인증샷을 크게 보고 승인(하트 자동 지급) / 반려(사유 3개)한다.

**Architecture:** DB 에 "검수 + 작업 기록"을 한 트랜잭션으로 하는 plpgsql 함수 하나를 두고(설계 §8 머리), FastAPI `/admin/heart-tasks*` 가 `get_admin_caller` 뒤에서 그 함수를 RPC 로 부른다. 사진은 비공개 버킷 `heart-task-proofs` 의 5분 서명 URL 로만 내려간다. 화면은 `admin_web/` 의 A3(pen `GX3T8`).

**Tech Stack:** Postgres(plpgsql, pgTAP) · FastAPI + httpx(PostgREST) · Flutter web(Riverpod 3, go_router 18).

**Spec:** 바탕화면 `C:/Users/user/OneDrive/Desktop/관리자_대시보드_설계_10-18.md` §2 · §6 · §8 머리 · §8-1 · §8-2(C 의 인증샷 부분) · §9 A3 · §11 D1+W1.

**나누기:** Task 1~3 = 서버 · DB PR(지금 시작, main `eb7e4a69` 위). Task 4~5 = 웹 PR(W0 `feat/admin-web-skeleton` 이 main 에 들어간 뒤 시작 — 그 패키지 구조를 쓴다).

## Global Constraints

- 운영 DB 적용 · 서버 배포 · Vercel 배포는 하지 않는다(사용자 승인 문장 뒤 대장이 함). 코더는 로컬 DB 명령도 돌리지 않는다(pgTAP 는 대장/검토 차례).
- 새 외부 의존성 금지(백엔드 · `admin_web` 모두).
- DB 함수: `security invoker`, `set search_path = ''`, `revoke all … from public, anon, authenticated` 뒤 `grant execute … to service_role` 만. `security definer` 금지(`docs/SUPABASE.md`).
- 서버 경로 이름에 `e2e/area4_extra.py:38-44` 금지어(`refund` · `cashout` · `transfer` · `gift` · `send_heart` · `exchange` · `heart_withdraw` · `hearts/withdraw`)와 구매 단어(`purchase` · `buy` · `unlock` · `heart_store`)를 쓰지 않는다.
- 모든 관리자 경로는 `Depends(get_admin_caller)`(`backend/app/admin/caller.py`). `get_verified_caller` 금지.
- 사진 URL 만료 300초. 다운로드 단추 없음. 사진 · 경로 · 이름을 디스코드에 싣지 않는다(번호만).
- 반려 사유는 enum `public.heart_task_reject_reason` 3개뿐: `date_missing` "날짜가 안 보여요" · `not_verified` "게시글·공유가 확인되지 않아요" · `reused` "이미 쓴 캡처예요"(앱 `frontend/lib/billing/model/heart_task.dart` 의 label 과 같은 글자).
- 항목 이름: `everytime_post` 목록 "에브리타임" · 정보 "에브리타임 홍보", `kakao_share` 목록 "단톡방" · 정보 "단톡방 공유". 보상은 "하트 {n}개".
- 파일 줄끝 CRLF(저장소 관례), 커밋 · PR 에 도구 표식 금지.

## Review Focus

1. **동시 검수** — 두 탭에서 같은 건을 승인하면 두 번째는 409 "이미 처리됨", 하트는 한 번만. → Task 1 pgTAP `second review raises CM409` + Task 2 pytest `test_second_review_is_409`.
2. **사진이 없는 제출**(60일 정리로 `storage_path` null, 또는 Storage 서명 실패) — 목록이 500 이 되지 않고 그 줄만 `photo_url: null` → 화면 "사진 없음". → Task 2 `test_missing_or_unsignable_photo_is_null`, Task 5 위젯 시험.
3. **서명 URL 만료 뒤 화면** — 5분 넘게 띄워 둔 사진을 다시 그리거나 지난 제출을 누르면 깨진 그림 대신 그 건을 다시 받아 온다. → Task 5 `photo error refetches the item`.
4. **반려 사유 누락 · 엉뚱한 값** — 서버 422, DB 함수도 거절. → Task 1 · Task 2.
5. **승인 직후 다음 건 이동** — 목록 마지막 건을 처리하면 빈 목록 화면(pen `t36bfq`), 필터가 걸린 상태에서도 같은 필터 안의 다음 건. → Task 5 시험.

---

### Task 1: DB 함수 `admin_review_heart_task`

**Files:**
- Create: `supabase/migrations/<supabase migration new 로 만든 2026-10-18 시각>_admin_review_heart_task.sql`
- Create: `supabase/tests/admin_heart_task_review_test.sql`
- Modify: `supabase/tests/rls_slice0_test.sql`(함수 권한 목록을 나열한다면 같은 방식으로 추가 — 없으면 손대지 않음)

**Interfaces:**
- Produces: `public.admin_review_heart_task(p_admin uuid, p_submission uuid, p_status public.submission_status, p_reject_reason public.heart_task_reject_reason, p_ip inet) returns jsonb` — 반환 `{"id","status","reject_reason","reward_hearts","reviewed_at"}`.
- 오류: 없는 제출 `CM404`, 이미 검수됨(`status <> 'submitted'`) `CM409`, `p_status = 'submitted'` 또는 (승인인데 사유 있음 / 반려인데 사유 없음) `22023`.

- [ ] **Step 1: pgTAP 먼저** — `plan(n)`:
  - 승인: 상태 `approved`, `reviewed_at` 찍힘, `heart_transactions` 에 `free_task` · `ref_id = 제출 id` · 금액 = `reward_hearts` 한 줄, `entitlements.heart_balance` 증가, `admin_actions` 한 줄(`action = 'heart_task_approve'`, `target_type = 'heart_task_submission'`, `target_id = 제출 id::text`, `before = {"status":"submitted"}`, `after` 에 status · reward_hearts, `admin_user_id = p_admin`, `ip`).
  - 반려: 상태 `rejected` · 사유 저장, 하트 원장 변화 0, 기록 `action = 'heart_task_reject'`, `after` 에 reject_reason.
  - `second review raises CM409`(승인 뒤 다시 승인 · 반려 모두), 하트는 한 번만.
  - 없는 id → `CM404`. 사유 규칙 위반 → `22023`. `p_status = 'submitted'` → `22023`.
  - 권한: `anon` · `authenticated` 실행 불가(42501), `service_role` 실행 가능, 함수가 invoker · search_path ''.
  - 실패한 호출 뒤 `admin_actions` 에 줄이 늘지 않음(트랜잭션 함께 되돌아감).
- [ ] **Step 2: 함수 구현** — `update public.heart_task_submissions set status = p_status, reject_reason = p_reject_reason where id = p_submission and status = 'submitted' returning …`; 0줄이면 존재 여부로 `CM404` / `CM409` 를 가른다. 지급은 기존 트리거(`heart_task_submissions_grant`)가 같은 트랜잭션에서 한다 — 함수가 직접 `grant_hearts` 를 부르지 않는다. 이어서 `insert into public.admin_actions …`.
- [ ] **Step 3: 대장에게 pgTAP 실행 요청**(코더는 돌리지 않음). 명령: 워크트리 루트 `supabase db reset` → `supabase test db`.
- [ ] **Step 4: Commit** `🗃️ db(admin): 인증샷 검수와 작업 기록을 한 번에 하는 admin_review_heart_task` + 시험 커밋 분리.

### Task 2: 서버 `/admin/heart-tasks*`

**Files:**
- Create: `backend/app/admin/heart_task_review.py`(라우터 + 응답 모양), `backend/app/admin/request_ip.py`
- Modify: `backend/app/heart_tasks/storage.py`(`create_signed_url` 추가), `backend/app/admin/repository.py`(아래 메서드), `backend/app/main.py`(라우터 등록)
- Test: `backend/tests/admin/test_admin_heart_tasks.py`, `backend/tests/admin/admin_world.py`(가짜 응답 추가)

**Interfaces:**
- Consumes: `AdminCaller(settings, client, admin_user_id)`, `get_admin_caller`, `AdminRepository`(PostgrestRepository 상속), Task 1 RPC.
- Produces(웹이 쓰는 JSON):
  - `GET /admin/heart-tasks?status=submitted&task=everytime_post|kakao_share&limit=50` → `{"items": [Item]}` 오래된 순(`created_at.asc`). `status` 기본 `submitted`, `limit` 1~100 기본 50.
  - `GET /admin/heart-tasks/{id}` → `Item`(없으면 404).
  - `POST /admin/heart-tasks/{id}/approve` → `Item`(처리 뒤 모양). `POST /admin/heart-tasks/{id}/reject` 본문 `{"reason": "date_missing"|"not_verified"|"reused"}` → `Item`. 이미 검수 409 `{"detail":"already_reviewed"}`, 없음 404.
  - `Item = {id, task, status, reject_reason, reward_hearts, created_at, reviewed_at, profile: {id, nickname, university}, photo_url: str|null, previous: [{id, status, created_at, photo_url}]}` — `previous` 는 같은 사람 · 같은 항목의 다른 제출 중 `storage_path` 가 남은 것, 최근 순 최대 5.
- `HeartProofStorage.create_signed_url(path: str, expires_in: int) -> str`(모양은 `profile_onboarding/storage.py:109-119` 와 같게, 버킷만 다름).
- `AdminRepository.list_heart_submissions(status, task, limit) -> list[dict]`, `fetch_heart_submission(id) -> dict | None`, `fetch_previous_heart_submissions(profile_id, task, exclude_id, limit=5) -> list[dict]`, `review_heart_task(admin_user_id, submission_id, status, reject_reason, ip) -> dict`(RPC, `CM404` → 404 · `CM409` → 409 · `22023` → 422).
- `request_ip(request) -> str | None`: `X-Forwarded-For` 첫 값이 IP 로 읽히면 그것, 아니면 `request.client.host`, 둘 다 아니면 None. 주석: `shortcut: 첫 값은 사용자가 꾸밀 수 있음 — 감사 참고용이지 보안 판단에 쓰지 않는다, 필요해지면 Cloud Run 앞단 기준 오른쪽 값으로`.

- [ ] **Step 1: 실패하는 시험** — 경로마다 관문(401/403 두 이유) 적용, 목록 정렬 · 필터 · limit 범위(0 · 101 → 422), 닉네임 · 학교 붙임(`profiles(nickname,universities(name))` 임베드 — FK 이름 충돌이 나면 명시 힌트), `photo_url` 서명(만료 300 요청 본문 확인), `test_missing_or_unsignable_photo_is_null`, previous 최대 5 · 자기 자신 제외 · 경로 없는 것 제외, 승인 · 반려가 RPC 인자(`p_admin` = caller id, `p_ip`)를 맞게 보냄, `test_second_review_is_409`, 없는 id 404, 잘못된 사유 422, 반려 사유 없이 approve 본문 무시. **가짜 Supabase 는 경로 + params 키로 가른다**(메모 함정 ①), `get_settings` 덮어쓰기는 람다(함정 ②).
- [ ] **Step 2: 구현** — 위 Interfaces 그대로. 응답에 `storage_path` 원문을 싣지 않는다.
- [ ] **Step 3: 확인** — `backend/` 에서 pytest 전체 통과(파이썬은 메모 `reference_backend_pytest_python.md`), `e2e/test_area4_extra.py` 통과(금지어), `e2e/test_area3_safe.py::test_51` 은 main 에서도 실패하는 기존 두 줄 외에 새 차이가 없는지.
- [ ] **Step 4: Commit** 저장소 서명 URL / 저장소 메서드 / 라우터 로 나눠서.

### Task 3: 디스코드 인증샷 알림에 대시보드 주소

**Files:**
- Modify: `backend/app/settings.py`(`admin_base_url: str = ""` — 환경 변수 `ADMIN_BASE_URL`, 끝 `/` 떼기), `backend/app/heart_tasks/router.py:53-66`(`_notify_review`)
- Test: `backend/tests/heart_tasks/test_heart_tasks.py`

- [ ] **Step 1: 시험** — `ADMIN_BASE_URL` 이 비면 지금 문구 그대로(기존 시험 통과), 있으면 문구가 `"… 대시보드: {ADMIN_BASE_URL}/heart-tasks/{submission_id}"` 로 끝나고 "Supabase 대시보드" 안내가 없음. 계정 id · 항목 · 번호 외에 사진 경로 · 이름이 없음.
- [ ] **Step 2: 구현 · 확인 · Commit** `✨ feat(heart-tasks): 디스코드 인증샷 알림에 관리자 대시보드 주소를 싣는다`.

### Task 4: 웹 데이터 층 (W0 머지 뒤)

**Files:**
- Create: `admin_web/lib/heart_tasks/heart_task_item.dart`(모델 + `fromJson`), `admin_web/lib/heart_tasks/heart_task_review_controller.dart`(Riverpod Notifier)
- Modify: `admin_web/lib/api/admin_api.dart`(`listHeartTasks({String? task})`, `getHeartTask(id)`, `approveHeartTask(id)`, `rejectHeartTask(id, reason)` — 409 는 `AlreadyReviewed` 예외로)
- Test: `admin_web/test/heart_tasks/*`

- [ ] **Step 1: 시험** — JSON 파싱(사진 null · previous 빈 목록), 필터 바꾸면 다시 받음, 처리 성공 시 목록에서 빠지고 **같은 필터 안의 다음 건**이 선택됨, 마지막 건이면 빈 상태, 409 면 "이미 처리됨" 상태 + 목록 새로 받음, 사진 오류 신호 → 그 건만 다시 받음.
- [ ] **Step 2: 구현 · 확인 · Commit**.

### Task 5: A3 화면 (pen `GX3T8`)

**Files:**
- Create: `admin_web/lib/heart_tasks/heart_task_review_screen.dart`, 필요하면 `admin_web/lib/widgets/{photo_viewer,status_badge,filter_chip,toast}.dart`(Web/ 컴포넌트 `DKRDo` · `DZhY4` · `xL1CC`/`wEkG9` · `nmb2y` 와 1:1, W0 에 이미 있으면 재사용)
- Modify: `admin_web/lib/router/admin_router.dart`(`/heart-tasks`, `/heart-tasks/:id` — 디스코드 링크로 열면 그 건 선택), 셸의 자리표시를 이 화면으로
- Test: `admin_web/test/heart_tasks/heart_task_review_screen_test.dart`

- [ ] **Step 1: pen 값표 받기** — 대장이 campus-pen 에게 `GX3T8` 값(목록 폭 320 · 사진 440 · 정보 카드 · 칩 · 배지 · 반려 펼침 · 단축키 안내 줄)을 받아 넘긴다. PNG: 바탕화면 `CampusMate_문서\디자인_pen\관리자_대시보드\A3_인증샷_검수.png`.
- [ ] **Step 2: 시험** — 칩 3개(전체/에브리타임/단톡방), 목록 줄(닉네임 · "{항목} · {학교} · {n분 전}" · 대기 배지), 선택 줄 강조, 사진 자리(사진 없음 문구), 지난 제출 썸네일 최대 5, 정보 5줄(제출자 · 학교 · 항목 · 제출 시각 · 보상), [승인] · [반려 ▾] 3사유 글자 정확히, 단축키 A/R(입력 칸에 초점이 있을 땐 무시), 처리 뒤 토스트 "처리했어요"와 다음 건, 409 안내, `photo error refetches the item`, 빈 목록.
- [ ] **Step 3: 구현 · `flutter analyze` 0 · `flutter test` · `flutter build web --release` · Commit**.

---

## 하지 않을 것
신고 · 사용자 · 결제 화면(다음 조각), 인증샷 결과 푸시(설계 §2), 반려 자유 글, 사진 내려받기, 기간 필터 · 검색(1판 목록은 대기 건만, 처리된 건 보기는 작업 기록 화면 몫).

---

## 구현 편차 기록 (Task 1~3, 10-18 코더)

- **라우터 등록 자리**: `backend/app/main.py`(공유 파일)를 고치지 않고 `backend/app/admin/router.py` 에서 `router.include_router(heart_task_review_router)` 로 붙였다. 경로는 똑같이 `/admin/heart-tasks*` 이고, 관문 누락 검사(`tests/admin/test_admin_caller.py::test_every_admin_route_goes_through_the_admin_gate`)가 새 경로까지 센다.
- **마이그레이션 이름**: `supabase migration new` 대신 손으로 `20261018011200_admin_review_heart_task.sql`(D0 의 `20261018002907` 다음, UTC 10-18 01:12). 로컬 DB 명령 금지 범위 밖이지만 CLI 를 부를 필요가 없었다.
- **"실패한 호출 뒤 기록이 늘지 않음" 시험의 모양**: 기록 insert 를 일부러 실패시키는 길로 `p_admin = null`(admin_actions.admin_user_id not null → 23502)을 썼다. update · 지급 트리거까지 간 뒤 막히므로 "기록이 실패하면 승인 · 하트도 없던 일" 을 직접 본다(pgTAP 22~24).
- **`rls_slice0_test.sql` 은 손대지 않음**: 표 · 시퀀스 · 컬럼 권한만 나열하고 함수 권한 목록은 없다(계획서 Task 1 Files 의 "없으면 손대지 않음").
- **404 본문**: 계획서는 409 만 `already_reviewed` 로 정했다. 404 도 같은 결의 기계 코드 `not_found` 로 했다(관리자 웹이 문구를 고른다). 422 는 기존 `errors.INVALID_INPUT`.
- **`request_ip`**: `request.client.host` 도 IP 로 읽힐 때만 쓴다(시험 클라이언트의 `"testclient"` 같은 글자가 inet 칸에 들어가면 검수가 22P02 로 실패한다).
- **`ADMIN_BASE_URL` 끝 `/` 떼기**: `settings.py` 의 검사기 대신 쓰는 곳(`heart_tasks/router.py` `_notify_review`)에서 `rstrip('/')`. 쓰는 곳이 하나뿐이다.
- **목록은 사진 없는 요약(대장 10-18 검토)**: `GET /admin/heart-tasks` 의 줄에서 `photo_url` · `previous` 키를 뺐다 — pen A3(`GX3T8`) 목록 줄에는 사진이 없고(닉네임 · 항목 · 학교 · 시각 · 배지), 건마다 서명 · 지난 제출을 붙이면 50건에 요청 300개를 넘는다. 목록은 PostgREST 한 번으로 끝난다. 사진 · 지난 제출(서명 포함)은 `GET /admin/heart-tasks/{id}` 와 승인 · 반려 응답에만 실린다. → 웹 Task 4: `listHeartTasks` 는 사진 없는 요약 모델, `getHeartTask` 가 사진 · 지난 제출을 받는다(줄을 고르면 한 건을 받아 온다).
- **pgTAP 은 코더가 돌리지 않았다**(Global Constraints). 대장 차례: 워크트리 루트 `supabase db reset` → `supabase test db`.
