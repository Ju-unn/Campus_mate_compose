# 관리자 대시보드 D2 — 신고 검수 · 정지 · 가림 · 채팅 앞뒤 보기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 웹 대시보드에서 열린 신고를 오래된 순으로 보고, 그 자리에서 조치 완료 / 기각 · 정지 / 해제 · 자동 가림 해제 · 투표 글과 지인 리뷰 가림 / 해제 · 신고된 채팅 앞뒤 보기를 한다. 디스코드 신고 알림에는 그 건의 대시보드 주소를 싣는다.

**Architecture:** DB 를 바꾸는 조치마다 plpgsql 함수 하나(조건부 변경 + `admin_actions` insert 를 한 트랜잭션, 설계 §8 머리)를 마이그레이션 한 파일에 둔다. FastAPI 는 `get_admin_caller` 뒤에서 읽기는 PostgREST 로, 쓰기는 그 함수 RPC 로 한다. 채팅 앞뒤 보기는 DB 를 바꾸지 않으므로 서버가 `admin_actions` 한 줄(열람)을 먼저 남긴 뒤 읽어 바로 돌려준다(저장 · 캐시 없음).

**Tech Stack:** Postgres(plpgsql, pgTAP) · FastAPI + httpx(PostgREST · Storage).

**Spec:** 바탕화면 `C:/Users/user/OneDrive/Desktop/관리자_대시보드_설계_10-18.md` §2 · §8 머리 · §8-2 전체(D · C 포함) · §11 D2. 모양 · 관례의 기준은 D1 `docs/superpowers/plans/2026-10-18-admin-heart-task-review.md`(구현 편차 기록 포함).

**범위:** 서버 · DB 만. 웹 화면(W2)은 아래 Interfaces 의 응답 JSON 모양만 정하고 구현하지 않는다.

## Global Constraints

- 운영 DB 적용 · 서버 배포 금지. 코더는 로컬 DB 명령(`supabase db reset` · `test db` · `start`)도 돌리지 않는다 — pgTAP 은 대장 차례.
- 새 외부 의존성 금지. 공유 파일(`backend/app/main.py` · `backend/app/settings.py` · `backend/app/core/errors.py`)은 고치지 않는다 — 라우터는 `backend/app/admin/router.py` 에 붙이고(D1 편차 기록), 설정은 D1 이 만든 `admin_base_url` 을 그대로 쓴다.
- DB 함수: `security invoker`, `set search_path = ''`, `revoke all … from public, anon, authenticated` 뒤 `grant execute … to service_role` 만. 바뀐 줄이 0이면 없음 `CM404`(서버 404 `not_found`) / 이미 그 상태 `CM409`(서버 409 `already_done`), 규칙 위반 `22023`(서버 422). 기록 insert 는 같은 함수 안.
- 서버 경로 이름에 `e2e/area4_extra.py:38-44` 금지어(`refund` · `cashout` · `transfer` · `gift` · `send_heart` · `exchange` · `heart_withdraw` · `hearts/withdraw`)와 구매 단어(`purchase` · `buy` · `unlock` · `heart_store`)를 쓰지 않는다. `withdraw` 도 쓰지 않는다.
- 모든 관리자 경로는 `Depends(get_admin_caller)`. `get_verified_caller` 금지(`e2e/test_area3_safe.py::test_51` 의 경로 목록이 늘지 않게).
- "같은 대상" = 같은 `reports.target_profile_id`(신고당한 사람). 자동 가림을 세는 기준(`safety/repository.py:103-110` `count_open_reporters`)과 같다.
- 사유: 정지 · 해제 · 가림 해제 · 글 가림 · 글 해제 · 채팅 앞뒤 보기는 `reason` 필수(앞뒤 공백 뗀 1~500자 — `admin_actions_reason_length` 와 같은 상한). 조치 완료 / 기각의 `note` 는 선택(같은 상한).
- 사진: 목록에는 없다(PostgREST 한 번). 상세에서만 실사진 서명 URL 300초(`profile-photos` 비공개 버킷), 아바타는 공개 URL. 응답에 storage 경로 원문을 싣지 않는다.
- 채팅 앞뒤 보기: 메시지 신고에만 · 신고된 줄 앞뒤 5개씩 · 글자만 · 사유 필수 · 기록은 "열람"(`admin_actions` insert 한 번, 본문 · match id 없음) · 서버에 저장하지 않음 · 로그에 본문 없음.
- 디스코드에는 번호만(신고 id · 대상 profile_id · 사유 코드 · 신고자 수 · 주소의 번호). 파일 줄끝 CRLF, 커밋 · PR 에 도구 표식 금지.

## Review Focus

1. **두 관리자가 같은 신고 · 같은 사람에 동시에 조치** — 두 번째는 409, 기록은 한 번. → Task 1 pgTAP `second resolve raises CM409` · `second suspend raises CM409`, Task 3 pytest `test_second_action_is_409`.
2. **가림 해제 뒤 신고 한 건에 다시 가려짐** — 해제가 그 사람의 열린 신고를 같은 트랜잭션에서 기각해야 다음 신고의 "서로 다른 신고자 수" 가 0부터 센다. → Task 1 pgTAP `unhide leaves no open reporters`, Task 3 pytest 가 PATCH 가 아니라 RPC 한 번만 부르는지.
3. **정지 해제가 엉뚱한 상태로 돌림** — 대시보드 정지는 기록의 before 로(온보딩이 끝났어도 pending 이었으면 pending), SQL 정지(기록 없음)는 온보딩 체크(`nickname · gender · birth_year · height_cm`)로 active / pending. → Task 1 pgTAP 세 경우.
4. **대상이 사라진 신고**(탈퇴로 `target_profile_id` null, 실사진 파일 삭제, 대화방 삭제) — 목록 · 상세가 500 이 되지 않고 `target_profile: null` · `photo_urls: []` · `messages: []`. → Task 2 pytest.
5. **채팅 앞뒤 보기가 새는 길** — 메시지 신고가 아니면 기록 · 메시지 조회 없이 422, 기록이 실패하면 메시지를 읽지도 돌려주지도 않음, 기록에 본문이 없음. → Task 2 pytest.

---

### Task 1: DB 함수 다섯 개 `admin_report_review`

**Files:**
- Create: `supabase/migrations/20261018030000_admin_report_review.sql`(D1 `20261018011200` 다음)
- Create: `supabase/tests/admin_report_review_test.sql`

**Interfaces (Produces — 모두 `returns jsonb`):**
- `public.admin_resolve_report(p_admin uuid, p_report uuid, p_outcome public.report_status, p_note text, p_same_target boolean, p_ip inet)` → `{"id","status","closed_ids":[uuid…]}`. `p_outcome` 은 `actioned` · `dismissed` 만(`open` · null → 22023). 그 신고가 `open` 이 아니면 CM409. `p_same_target` 이면 같은 `target_profile_id` 의 다른 열린 신고도 같은 결과로 닫는다(대상이 null 이면 그 건만). 닫힌 신고마다 기록 한 줄 `action='report_resolve'`, `target_type='report'`, `before={"status":"open"}`, `after={"status":outcome}`, `reason=p_note`.
- `public.admin_suspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)` → `{"id","status":"suspended"}`. `pending` · `active` 만 정지(그 밖 CM409). 기록 `profile_suspend`, `before={"status":직전}`.
- `public.admin_unsuspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)` → `{"id","status"}`. `suspended` 만(그 밖 CM409). 되돌릴 상태 = 그 사람의 가장 최근 `profile_suspend` 기록의 `before.status`, 없으면 온보딩 체크 칸 네 개가 다 있으면 `active` 아니면 `pending`. 기록 `profile_unsuspend`.
- `public.admin_unhide_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)` → `{"id","auto_hidden_at":null,"dismissed_ids":[uuid…]}`. `auto_hidden_at` 이 있을 때만(없으면 CM409). 같은 함수에서 그 사람의 열린 신고를 모두 `dismissed` 로 닫는다(`safety/repository.py:103-119` 규칙). 기록 `profile_unhide` 한 줄(`before={"auto_hidden_at":…}`) + 닫힌 신고마다 `report_resolve` 한 줄.
- `public.admin_set_content_status(p_admin uuid, p_target public.report_target, p_content uuid, p_status public.content_status, p_reason text, p_ip inet)` → `{"id","status"}`. `p_target` 은 `poll` · `friend_review` 만(그 밖 22023). 이미 그 상태면 CM409. 기록 `content_blind` / `content_unblind`, `target_type` = `poll` · `friend_review`.
- 공통: `p_reason`(정지 · 해제 · 가림 해제 · 글) 이 null 이거나 공백뿐이면 22023. 행이 없으면 CM404.

- [ ] **Step 1: pgTAP 먼저** — `admin_report_review_test.sql`:
  - 모양: 다섯 함수가 invoker · `search_path=""`, `service_role` 만 execute(anon · authenticated · public 없음).
  - 조치 완료: 상태 · `resolved_at`, 다른 열린 신고는 그대로, 기록 한 줄(전후 · 사유 · ip). `second resolve raises CM409`, 없는 id CM404, `open` · null 결과 22023.
  - 같은 대상 함께 닫기: 같은 사람의 열린 신고만 닫히고 다른 사람 신고는 그대로, 닫힌 수만큼 기록.
  - 정지: 직전 상태 기록, `second suspend raises CM409`, 탈퇴 계정 CM409, 공백 사유 22023, 없는 id CM404.
  - 해제: 대시보드 정지(active) → active, 온보딩 끝난 pending 을 대시보드 정지 → pending(기록 우선), SQL 정지 + 온보딩 끝 → active, SQL 정지 + 온보딩 전 → pending, 정지 아님 CM409.
  - 가림 해제: `auto_hidden_at` null, 열린 신고 셋 → dismissed, 이미 닫힌 신고는 그대로, `unhide leaves no open reporters`, 기록 1 + 3줄, 가려지지 않은 사람 CM409.
  - 글: 투표 글 가림 · 다시 가림 CM409 · 해제, 지인 리뷰 가림, 대상 종류 `profile` 22023, 없는 글 CM404.
  - 기록 실패(`p_admin` null → 23502)면 조치도 없던 일(같은 대상 닫기 · 정지 · 가림 해제 각각 그대로).
  - 앱 역할: authenticated · anon 실행 42501.
- [ ] **Step 2: 함수 구현** — 대상 행을 `select … for update` 로 잡고(없으면 CM404, 조건이 아니면 CM409) 바꾼 뒤 같은 함수에서 기록 insert. 여러 줄 닫기는 `with closed as (update … returning id) insert into admin_actions … select … from closed`.
- [ ] **Step 3: 대장에게 pgTAP 실행 요청** — 코더는 돌리지 않는다. plan 수와 확인문 수는 스크립트로 맞춘다.
- [ ] **Step 4: Commit** `🗃️ db(admin): 신고 닫기 · 정지 · 해제 · 가림 해제 · 글 가림과 작업 기록을 한 번에` + 시험 커밋 분리.

### Task 2: 서버 신고 읽기 — 목록 · 상세 · 채팅 앞뒤 보기

**Files:**
- Create: `backend/app/admin/report_review.py`(라우터 `/reports`)
- Modify: `backend/app/admin/repository.py`(아래 메서드), `backend/app/admin/router.py`(include)
- Test: `backend/tests/admin/test_admin_reports.py`, `backend/tests/admin/admin_world.py`(가짜 응답)

**Interfaces:**
- Consumes: `AdminCaller`, `get_admin_caller`, `request_ip`, `ProfilePhotoStorage.create_signed_url(path, expires_in)`, `SafetyRepository.count_open_reporters(target_profile_id) -> int`.
- Produces(웹 W2 가 쓰는 JSON):
  - `GET /admin/reports?status=open|actioned|dismissed&type=profile|message|friend_review|poll&limit=50` → `{"items":[Summary]}`, 오래된 순(`created_at.asc`), `status` 기본 `open`, `limit` 1~100. "접수 뒤 지난 시간" 은 웹이 `created_at` 으로 그린다.
  - `Summary = {id, target_type, target_id, reason, reason_note, status, created_at, resolved_at, target_profile: {id, nickname, university, status, auto_hidden_at} | null}`.
  - `GET /admin/reports/{id}` → `Detail = Summary + {snapshot, content_status, open_reporters, other_reports}`. 없으면 404 `not_found`.
    - `snapshot`: 사본에서 `avatar_path` · `photo_paths` 를 빼고 `avatar_url`(공개 아바타 URL | null) · `photo_urls`(서명 300초, 서명 안 되는 파일은 뺌)를 넣은 것. 프로필 사본에만 두 키가 생긴다. 메시지 · 리뷰 · 투표 사본은 글자 그대로.
    - `content_status`: 투표 · 리뷰 신고면 그 글의 지금 상태(`visible` · `blinded`, 지워졌으면 null), 그 밖 null.
    - `open_reporters`: 같은 대상의 열린 신고의 서로 다른 신고자 수(자동 가림 기준 3).
    - `other_reports`: 같은 대상의 다른 신고 `[{id, target_type, reason, status, created_at}]` 최근 순 최대 20(대상 null 이면 []).
  - `POST /admin/reports/{id}/chat-context` 본문 `{"reason": str}` → `{"messages":[{id, kind, body, created_at, from_target, reported}]}` 오래된 순, 신고된 줄 앞 5 · 그 줄 · 뒤 5. `from_target` = 신고당한 사람이 보낸 줄. 대화가 지워졌으면 `[]`. 메시지 신고가 아니면 422 `not_message_report`.
- `AdminRepository.list_reports(status, target_type, limit) -> list[dict]`, `fetch_report(id) -> dict | None`, `fetch_other_reports(target_profile_id, exclude_id, limit=20) -> list[dict]`, `fetch_content_status(target_type, content_id) -> str | None`, `fetch_chat_context(match_id, message_id, created_at, each_side=5) -> list[dict]`.

- [ ] **Step 1: 실패하는 시험** — 경로마다 관문(401 · 403 두 이유), 목록 정렬 · 필터 · limit 범위 · 대상 프로필 임베드(`target_profile:profiles!target_profile_id(...)` 힌트 — FK 가 둘이다) · 목록은 PostgREST 한 번(서명 없음), 상세의 사진 서명(만료 300 본문) · 서명 실패 사진 빠짐 · 경로 원문 없음, 대상 null 신고, `content_status`, `open_reporters`, `other_reports` 자기 제외, 채팅 앞뒤(앞 `created_at=lt.` 최근 순 5 · 뒤 `gt.` 오래된 순 5 · 그 줄 `id=eq.`), 비메시지 422 에 기록 · 조회 없음, 사유 없음 · 공백 · 501자 422, 기록 실패면 메시지 조회 없음, 기록에 본문 · match id 없음. 가짜는 경로 + params 키로 가른다(메모 함정 ①), `get_settings` 덮기는 람다(함정 ②).
- [ ] **Step 2: 구현** — 위 Interfaces 그대로. 상세의 추가 조회 · 서명은 `asyncio.gather`.
- [ ] **Step 3: 확인** — pytest 전체, `e2e/test_area4_extra.py`, `e2e/test_area3_safe.py::test_51`(main 기존 두 줄 외 새 차이 없음).
- [ ] **Step 4: Commit** 저장소 / 라우터 / 시험 으로 나눠서.

### Task 3: 서버 조치 — 닫기 · 정지 · 해제 · 가림 해제 · 글 가림

**Files:**
- Create: `backend/app/admin/moderation.py`(라우터 `/profiles` · `/content`)
- Modify: `backend/app/admin/report_review.py`(`/resolve`), `backend/app/admin/repository.py`(RPC 메서드), `backend/app/admin/router.py`
- Test: `backend/tests/admin/test_admin_reports.py`, `backend/tests/admin/test_admin_moderation.py`, `backend/tests/admin/admin_world.py`

**Interfaces:**
- Consumes: Task 1 RPC 다섯 개, Task 2 `Detail`.
- Produces:
  - `POST /admin/reports/{id}/resolve` 본문 `{"outcome":"actioned"|"dismissed", "note": str|null, "same_target": bool=false}` → 처리 뒤 `Detail`.
  - `POST /admin/profiles/{id}/suspend` · `/unsuspend` · `/unhide` 본문 `{"reason": str}` → RPC 결과(`{"id","status"}` · `{"id","auto_hidden_at","dismissed_ids"}`).
  - `POST /admin/content/polls/{id}/blind` · `/unblind`, `POST /admin/content/friend-reviews/{id}/blind` · `/unblind` 본문 `{"reason": str}` → `{"id","status"}`.
  - 공통 오류: 없음 404 `not_found`, 이미 그 상태 409 `already_done`, 규칙 위반 422.
- `AdminRepository.resolve_report(admin, report_id, outcome, note, same_target, ip) -> dict`, `suspend_profile(admin, profile_id, reason, ip)`, `unsuspend_profile(...)`, `unhide_profile(...)`, `set_content_status(admin, target_type, content_id, status, reason, ip) -> dict` — 모두 하나의 `_rpc(name, body)` 로 CM404 · CM409 · 22023 을 바꾼다(D1 `review_heart_task` 를 이 위로 옮긴다).

- [ ] **Step 1: 실패하는 시험** — 경로마다 관문, RPC 인자(`p_admin` = caller id · `p_ip` · 사유 앞뒤 공백 뗌 · `same_target` 기본 false), 결과 `open` · 모르는 값 422(RPC 안 부름), 사유 없음 · 공백 · 501자 422, `test_second_action_is_409`, 없는 id 404, 가림 해제는 PATCH 없이 RPC 한 번, 글 경로가 `p_target` 을 `poll` · `friend_review` 로 보냄.
- [ ] **Step 2: 구현 · 확인(Task 2 Step 3 과 같은 세 명령) · Commit** 저장소 RPC / 라우터 로 나눠서.

### Task 4: 디스코드 신고 알림에 대시보드 주소 + 틀린 안내 고치기 (C)

**Files:**
- Modify: `backend/app/safety/discord.py`(`report_line` · `auto_hidden_line` 에 `admin_base_url` 인자), `backend/app/safety/router.py:226-232`(설정값 넘기기)
- Test: `backend/tests/safety/test_reports.py`

- [ ] **Step 1: 시험** — `ADMIN_BASE_URL` 이 비면 신고 줄은 지금 문구 그대로. 있으면 `"… 대시보드: {base}/reports/{report_id}"` 로 끝나고 "Supabase" 가 없음(끝 `/` 뗌). 자동 가림 줄은 주소가 비어도 "auto_hidden_at 을 지워 주세요"(틀린 안내)가 없고 열린 신고도 닫아야 한다고 적음, 주소가 있으면 "대시보드에서 정지하거나 가림 해제" + `{base}/reports/{report_id}`. 사본 · 닉네임 · 경로는 여전히 없음.
- [ ] **Step 2: 구현 · 확인 · Commit** `✨ feat(safety): 디스코드 신고 알림에 관리자 대시보드 주소, 자동 가림 안내 바로잡기`.

---

## 하지 않을 것

웹 화면 W2(응답 모양만 정함), 기간 정지 · 정지 사유 칸 · 정지 알림, 신고자 이력 · 신고자 id 노출(2판), 채팅 사진 · 앞뒤 5개 넘게 보기 · 채팅 내용 저장, 조치와 글 가림을 한 번에 묶는 단추(웹이 두 번 부른다), 신고 목록 검색 · 기간 필터(작업 기록 화면 몫), `reports` 에 처리 메모 칸 추가(메모는 작업 기록 `reason` 에).

---

## 구현 편차 기록 (Task 1~4, 10-18 코더)

- **조치 경로를 둘로 묶음**: 정지 · 해제 · 가림 해제는 `POST /admin/profiles/{profile_id}/{action}`(action = `suspend` · `unsuspend` · `unhide`), 글은 `POST /admin/content/{kind}/{content_id}/{action}`(kind = `polls` · `friend-reviews`, action = `blind` · `unblind`) 한 함수씩(`backend/app/admin/moderation.py`). 실제 주소는 설계 §8-2 와 글자까지 같다. 다른 점은 모르는 action · kind 가 404 가 아니라 422 라는 것뿐이다(`test_an_unknown_kind_or_action_reaches_no_db_function`).
- **사유 필수 범위**: 설계 화면 줄은 "정지 · 하트 · 열람은 사유 필수" 라고만 했지만 경로 표기가 `/unsuspend {reason}` · `/unhide {reason}` · `/blind · /unblind {reason}` 라 이 여섯 경로 모두 필수(1~500자)로 했다. 조치 완료 / 기각의 `note` 만 선택이다. 선택으로 바꾸려면 `ReasonBody` 한 줄과 DB 함수의 사유 검사를 고치면 된다.
- **"같은 대상" = `target_profile_id`**: 메시지 신고는 그 대화의 상대 한 명만 할 수 있어(`safety/router.py` `_message_target`) `target_id` 기준이면 "같은 대상의 다른 신고" 가 늘 비게 된다. 자동 가림을 세는 기준(`count_open_reporters`)과도 같게 했다.
- **409 코드**: D2 조치는 `already_done`. D1 인증샷은 그대로 `already_reviewed`(D1 `review_heart_task` 를 공용 `_rpc` 위로 옮겼고 D1 시험이 그대로 통과).
- **DB 함수의 "조건부 변경"**: 바꾸기 전 상태(before)와 대상 사람을 알아야 해서 `update … where 조건` 한 줄 대신 `select … for update` 로 행을 잡고 조건을 본 뒤 바꾼다. 두 관리자가 동시에 누르면 두 번째가 첫 번째 커밋을 기다렸다가 조건을 다시 보고 CM409 가 되는 것은 같다.
- **기록 모양**: 신고 닫기는 닫힌 신고마다 한 줄(`report_resolve`, 신고 한 건의 기록을 대상 인덱스로 바로 찾게). 가림 해제는 `profile_unhide` 한 줄 + 기각한 신고마다 `report_resolve`(`after.via = "profile_unhide"`). 채팅 앞뒤 보기는 `report_chat_view` 한 줄에 사유 · ip 만(before · after 없음 — 방 번호도 싣지 않음).
- **디스코드 자동 가림 줄**: 설계는 주소가 비면 "지금 문구" 라고 했지만 지금 문구("auto_hidden_at 을 지워 주세요")가 틀린 안내라 주소가 비어도 고쳤다 — "정지하거나, 풀려면 auto_hidden_at 을 비우고 열린 신고를 dismissed 로 닫아 주세요." 주소가 있으면 "대시보드에서 정지하거나 가림 해제해 주세요: {base}/reports/{그 신고 id}" — D2 에는 사람 화면이 없어 그 가림을 일으킨 신고의 화면으로 보낸다. 신고 줄은 주소가 비면 지금 문구 그대로.
- **"접수 뒤 지난 시간"**: 서버 칸을 따로 두지 않고 웹이 `created_at` 으로 그린다(D1 목록의 "n분 전" 과 같은 방식).
- **채팅 앞뒤 같은 시각**: 신고된 줄과 `created_at` 이 마이크로초까지 같은 다른 줄은 앞뒤 어디에도 안 잡힌다(`shortcut:` 주석, `AdminRepository.fetch_chat_context`).
- **같은 대상 함께 닫기 수와 화면 목록**: 상세의 `other_reports` 는 최근 20건까지인데 함께 닫기는 열린 신고를 모두 닫는다. 한 사람에게 신고가 20건을 넘을 때만 화면에 보인 수보다 많이 닫힌다(조치 응답의 상세가 결과를 다시 보여 준다).
- **마이그레이션 이름**: 손으로 `20261018030000_admin_report_review.sql`(D1 `20261018011200` 다음). CLI 를 부르지 않았다.
- **pgTAP 은 코더가 돌리지 않았다**(Global Constraints). plan 56 = 확인문 56(스크립트로 셈). 대장 차례: 워크트리 루트 `supabase db reset` → `supabase test db`.
- **잠금 순서(검토 권고 1, 10-18)**: `admin_resolve_report` 는 대상만 먼저 잠그지 않고 읽은 뒤, 그 신고와(함께 닫기면) 같은 사람의 열린 신고를 한 문장에서 `order by id for update` 로 잠근다. 대상만 먼저 잠그면 두 관리자가 같은 사람의 서로 다른 신고를 함께 닫을 때 반대 순서로 기다려 교착(40P01)이 난다. `admin_unhide_profile` 도 신고를 같은 순서로 잠근다(프로필 → 신고). 신고 닫기는 프로필을 잠그지 않는다.
