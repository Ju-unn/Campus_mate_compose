# 인증샷 결과 알림 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 무료 하트 과제(에브리타임 홍보 · 단톡방 공유) 인증샷을 승인 · 반려하는 순간 사용자에게 푸시와 앱 알림함 한 줄을 보내고, 18a 목록의 반려 줄에 사유 한 줄을 보여 준다.

**Architecture:** DB 함수 `admin_review_heart_task` 는 고치지 않는다. 서버 `admin/heart_task_review.py` 가 RPC 성공 직후 기존 `cards/push.notify()`(알림함 한 줄 + 조용한 시간 보관 + FCM)를 부른다. 새 알림 종류 둘(`heart_task_approved` · `heart_task_rejected`)은 마이그레이션 1개로 두 표(notifications · pending_pushes)의 kind check 만 넓힌다. 앱은 푸시 `data.route` 두 값을 `PushRoute` 에 더하고, 알림함 종류 둘과 18a 반려 줄 사유를 그린다.

**Tech Stack:** FastAPI + PostgREST(httpx) · FCM HTTP v1(`FcmSender`) · Supabase Postgres + pgTAP · Flutter(Riverpod, go_router).

**Spec:** 사용자 10-18 결정 "가"(원문: "카카오톡 검수도 마찬가지야 알림을 보낼지, 아니면 따로 페이지 만들어서 보여줄지" → "가") + pen 시안 `C:/Users/user/OneDrive/Desktop/CampusMate_문서/디자인_pen/인증샷_결과_알림/` 다섯 장(`푸시_문구_표.png` · `알림함_인증_결과_행.png` · `18a_반려_사유_날짜_게시글.png` · `18a_반려_사유_이미_쓴_캡처.png` · `전체_영역.png`, pen 앱 영역 iVS6T 안 "15. 인증샷 결과 알림 · 반려 사유 표시 (승인 전)"). 관리자 쪽 기준: `docs/superpowers/plans/2026-10-18-admin-heart-task-review.md`(D1).

## Global Constraints

- DB 함수(`admin_review_heart_task`, 트리거 `heart_task_submissions_grant`)는 고치지 않는다. 마이그레이션은 두 표의 kind check 확장 1개뿐이다(파일 시각 `20261018130100` — 대장 지정 `20261018130000` 이후).
- 알림 발송이 실패해도 승인 · 반려 응답(200)을 뒤집지 않는다. 실패는 로그만, 로그에는 profile_id · kind 만(제목 · 본문 · 사진 경로 · 관리자 정보 금지).
- 푸시 · 알림함 data 에는 `route` · `task` · `reason` 만 싣는다. 사진 경로/주소, 관리자 id, IP, 닉네임, 메모는 싣지 않는다.
- 문구는 pen 표 그대로(아래 "문구 표"). 하트 수 n 은 RPC 응답의 `reward_hearts`(서버 값). 사유 문구 세 개는 앱 `HeartTaskRejectReason.label`(`frontend/lib/billing/model/heart_task.dart:27-29`)과 글자까지 같다 — 가운데점은 `·`(U+00B7), "게시글·공유가"는 앞뒤 공백 없음, 본문의 사유 뒤 구분점은 앞뒤 공백 있는 `·`.
- 앱 색 · 간격 · 글자는 토큰만(`AppColors` · `AppSpacing` · `AppTypography`). 토큰 밖 값은 pen 노드 id 를 주석에 단다.
- 눌림 잉크 규칙(COMMON §4-2): 새로 탭 위젯을 만들면 자기 `Material(type: transparency)` 안에 둔다. 이번 일은 기존 탭 위젯(`NotificationRow` · `HeartTaskRow`)만 고친다.
- 로컬 DB 명령(`supabase db reset` · `test db`), 클라우드 쓰기, 커밋은 이 계획서 단계에서 하지 않는다. 구현 단계에서 pgTAP 은 대장이 "DB 테스트 차례"를 준 도우미만 돌린다.

### 문구 표 (pen `푸시_문구_표.png`)

| 종류 | 제목 | 본문 | 누르면 | push · 알림함 kind | data |
| --- | --- | --- | --- | --- | --- |
| 승인 · 에브리타임 | 에브리타임 홍보 인증이 승인됐어요 | 하트 {n}개를 받았어요 | 18a | `heart_task_approved` | `{"route":"heart_tasks","task":"everytime_post"}` |
| 승인 · 단톡방 | 단톡방 공유 인증이 승인됐어요 | 하트 {n}개를 받았어요 | 18a | `heart_task_approved` | `{"route":"heart_tasks","task":"kakao_share"}` |
| 반려 · 에브리타임 | 에브리타임 홍보 인증이 반려됐어요 | {사유} · 다시 제출해 주세요 | 18b-2 | `heart_task_rejected` | `{"route":"heart_task_retry","task":"everytime_post","reason":"<enum>"}` |
| 반려 · 단톡방 | 단톡방 공유 인증이 반려됐어요 | {사유} · 다시 제출해 주세요 | 18b-2 | `heart_task_rejected` | `{"route":"heart_task_retry","task":"kakao_share","reason":"<enum>"}` |

사유: `date_missing` → "날짜가 안 보여요" · `not_verified` → "게시글·공유가 확인되지 않아요" · `reused` → "이미 쓴 캡처예요".

## 기존 코드에서 확인한 사실 (2026-10-18, main 4b2280bf)

| 사실 | 위치 |
| --- | --- |
| 승인 · 반려 경로. `_review` 가 RPC → `_one`(다시 읽어 응답) 순서. RPC 성공 뒤 알림 호출 자리가 없다 | `backend/app/admin/heart_task_review.py:84-87`, 라우트 `:107-119` |
| `repo.review_heart_task` → RPC `admin_review_heart_task`. CM404→404, CM409→409(`already_reviewed`), 22023→422. 응답 jsonb = `id,status,reject_reason,reward_hearts,reviewed_at` | `backend/app/admin/repository.py:127-134,160-175`, `supabase/migrations/20261018011200_admin_review_heart_task.sql:55-58` |
| 보상 지급은 같은 트랜잭션 트리거가 `reward_hearts` 로 `grant_hearts` | `supabase/migrations/20260928030100_create_heart_task_functions.sql:139-147` |
| 한 건 읽기 `fetch_heart_submission`(task · profiles(id) 포함). 응답 `_item` 은 `_summary`(task · profile.id · reward_hearts) 포함 | `repository.py:64-70`, `heart_task_review.py:52-73` |
| 알림 + 푸시 한 함수: `notify(repo, sender, profile_id, kind, title, body, data, now, defer=True, record=True)`. 정지 · 탈퇴면 0 으로 끝(알림함도 안 남김) → 알림함 한 줄(스위치와 무관) → 스위치(`settings.get(kind, True)` — 모르는 kind 는 늘 켜짐) → 조용한 시간(22~08) 이면 `_DEFERRED` 에 든 kind 만 `pending_pushes` 로 보관, 아니면 버림 → 기기마다 FCM | `backend/app/cards/push.py:173-204` |
| 알림함에 남길 kind 지도(푸시 kind → notifications.kind) `_INBOX_KINDS`, 보관 대상 `_DEFERRED`, 조용한 시간 예외 `_QUIET_HOURS_EXEMPT`(카드 도착 · 채팅뿐), 묶음 문구 `_BUNDLES`(여기 없는 (kind, route)는 한 건씩 보냄) | `push.py:58-80` |
| 알림함 한 줄 쓰기 `CardRepository.insert_notification`, 보관 `insert_pending_push`, 토큰 `fetch_push_tokens`, 정지 확인 `fetch_profile_status` | `backend/app/cards/repository.py:391,407,414,420` |
| 발송기 DI `get_sender`(테스트는 override), 지금 시각 DI `get_now`(조용한 시간 때문에 시험은 고정해야 함) | `backend/app/cards/router.py:78-83`, `backend/app/core/deps.py:65` |
| 학생증 결과가 같은 방식의 선례(서버 훅에서 `notify` 호출) | `backend/app/student_verification/review_hook.py:70-72` |
| `notifications.kind` check 6종: `card_arrived, chat_request, match_made, friend_review, verification_result, night_digest` (제약 이름 기본값 `notifications_kind_check`) | `supabase/migrations/20261010040000_create_notifications.sql:7-9` |
| `pending_pushes.kind` check 4종: `acceptance_received, match_made, new_friend_review, verification_result` (`pending_pushes_kind_check`) | `supabase/migrations/20261003010000_create_pending_pushes.sql:8` |
| 알림함 90일 보관 정리(매시 배치) | `backend/app/notifications/retention.py:9` |
| 알림함 API 는 kind 를 그대로 내려준다(걸러내지 않음) | `backend/app/notifications/router.py:33-35` |
| 앱 알림 종류 enum `NotificationKind` 6종 + `other`, `fromWire` 는 모르는 값을 `other` 로 읽는다(옛 앱은 종 그림) | `frontend/lib/notifications/model/app_notification.dart:4-20` |
| 알림함 행이 종류별 3D 그림을 `switch`(exhaustive)로 고른다. 모르는 종류 = `AppIcon3d.bell`. `AppIcon3d.heart`(`zxXQG`) · `AppIcon3d.ban`(금지 `eUCJv`) 이미 있다 | `frontend/lib/notifications/view/notification_row.dart:19-27`, `frontend/lib/core/theme/app_icons.dart:131-157` |
| 알림함 줄 탭 → `PushRoute.resolve(item.data)` → null 이면 읽음 처리만, 아니면 `refreshForPush` 후 `push`/`go` | `frontend/lib/notifications/view/notifications_screen.dart:90-110` |
| 푸시 탭 → `PushRoute.resolve(data)` → 라우터 규칙이 받아 줄 때 `go`. `route` 값 목록(`daily_card · acceptances · match · chat · friend_reviews · friend_review_write`)이 여기뿐 | `frontend/lib/core/push/push_route.dart:7-22`, `frontend/lib/main.dart:257-282` |
| 앱 켜진 채 받은 푸시는 시스템 알림 id 를 `route|match_id|profile_id` 해시로 만든다 → 같은 route 의 두 알림은 서로 덮는다 | `frontend/lib/core/push/foreground_push.dart:97-98` |
| #599 의 경로 id 검사: 경로에 실리는 id 는 `_uuidOr`(UUID 아니면 목록 · 홈)로 거른다. 18b 경로의 `:task` 는 UUID 가 아니라 enum 이라 기존 redirect 가 인증샷 항목만 통과시킨다(`needsProof`) | `frontend/lib/core/router/app_router.dart:147-152,175-185` |
| 18a 화면 `HeartTasksScreen`(autoDispose 뷰모델이 들어올 때마다 새로 읽음), 줄 위젯 `HeartTaskRow`(반려 상태는 "다시 제출" 글자만, 사유 줄 없음), 누르면 `heartTaskSubmitLocation(kind, rejectReason)` 로 18b-2 | `frontend/lib/billing/viewmodel/heart_tasks_view_model.dart`, `frontend/lib/billing/view/heart_task_row.dart:79-118`, `heart_task_actions.dart:14-15` |
| 앱 `HeartTask.rejectReason`(서버 `GET /heart-tasks` 가 `state==rejected` 일 때만 채움) → 18a 반려 사유는 서버 · 모델 변경 없이 줄 위젯만 바꾸면 된다 | `frontend/lib/billing/model/heart_task.dart:26-47,76-79`, `backend/app/heart_tasks/router.py:31,45` |
| 18b-2 경로 `/heart-tasks/submit/:task?reason=` 와 `heartTaskSubmitLocation`, 반려 알림 위젯 | `frontend/lib/billing/view/heart_task_submit_screen.dart:46-50,186-` |

## Review Focus

1. 푸시 · 알림함 실패(FCM 5xx · 연결 오류, notifications 쓰기 실패, 프로필 조회 실패)가 승인 · 반려 200 을 뒤집지 않는다. RPC 가 이미 커밋됐으므로 뒤집으면 관리자가 다시 눌러 409 만 본다.
2. 이미 처리된 건(409) · 없는 건(404) · 잘못된 사유(422)에서는 알림이 한 줄도 가지 않는다(두 탭 동시 승인에서 하트는 한 번, 알림도 한 번).
3. 정지 · 탈퇴한 사람: `notify` 가 0 을 돌려주고 알림함도 안 남긴다. 승인 · 반려 응답은 그대로 200.
4. 조용한 시간(22~08)에 관리자가 검수하면 푸시는 `pending_pushes` 로 보관돼 아침에 한 건씩(묶지 않고) 가고, 알림함 줄은 즉시 남는다. 같은 사람에게 두 과제 결과가 밤새 쌓여도 서로 합쳐지지 않는다.
5. 반려 사유가 비었거나 모르는 값이면(DB 가 막아 정상에서는 없다) 본문은 "다시 제출해 주세요"만, data 에 `reason` 을 빼고 보낸다. 앱은 `reason` 이 없거나 모르면 18b-2 알림 없는 18b 로, `task` 가 인증샷 항목이 아니면 18a 로 보낸다(원문 값을 경로에 그대로 싣지 않는다).
6. 옛 앱이 새 kind 를 받으면: 알림함에는 제목 · 본문과 종 그림으로 보이고 눌러도 아무 데도 안 간다(읽음 처리만). 푸시 탭은 앱만 열린다. (대장 결정 3)
7. 마이그레이션이 서버보다 먼저 적용돼야 한다 — 서버가 먼저 나가면 알림함 insert 가 check 위반으로 조용히 실패(로그만)해 줄이 안 남는다.

---

### Task 1: 마이그레이션 — 알림 종류 두 개 허용 (campus-coder, DB)

**Files:**
- Create: `supabase/migrations/20261018130100_heart_task_result_notification_kinds.sql`
- Modify: `supabase/tests/notifications_test.sql`, `supabase/tests/pending_pushes_test.sql`

**Interfaces:**
- Produces: `notifications.kind` 와 `pending_pushes.kind` 가 `heart_task_approved` · `heart_task_rejected` 를 받는다. 다른 값은 그대로 23514.

- [ ] **Step 1: 실패 시험 먼저**
  - `notifications_test.sql`: "나머지 다섯 종류" 배열 뒤에 두 종류를 더한 lives_ok 문장을 추가하고(`'나머지 일곱 종류도 모두 받는다'`) `select plan(17)` 을 새 개수로 맞춘다.
  - `pending_pushes_test.sql`: `lives_ok` 두 개 추가(승인 · 반려 kind 보관), 기존 `throws_ok` 의 설명을 "보류하는 6종 말고는 안 받는다"로 고치고 `new_message` 는 여전히 23514 를 확인, `plan(13)` 을 맞춘다.
- [ ] **Step 2: RED 확인** — 대장이 DB 테스트 차례를 줬을 때 `supabase test db`. Expected: 새 lives_ok 가 23514 로 FAIL.
- [ ] **Step 3: 마이그레이션 작성.** 두 표 각각 `alter table public.<표> drop constraint <표>_kind_check, add constraint <표>_kind_check check (kind in (...기존 값 그대로..., 'heart_task_approved', 'heart_task_rejected'));` (한 문장 안에서 drop + add = 원자적). 머리 주석에 이유 · 시험 파일 · "서버 배포보다 먼저 적용" 을 적는다. SECURITY DEFINER 함수가 없으므로 revoke 는 해당 없음. 표가 작아 검증 스캔 부담 없음(`not valid` 불필요).
- [ ] **Step 4: GREEN 확인** — 같은 명령. Expected: 두 시험 파일 전부 PASS. 보고에 docker 비정상 컨테이너를 한 줄로 적는다.

---

### Task 2: 서버 — notify 가 새 kind 를 알림함 · 보관함으로 보낸다 (campus-coder, backend)

**Files:**
- Modify: `backend/app/cards/push.py:58-70`(`_INBOX_KINDS` · `_DEFERRED`)
- Test: `backend/tests/cards/test_push_inbox.py`

**Interfaces:**
- Produces: `notify(..., kind="heart_task_approved" | "heart_task_rejected", ...)` 가 알림함에 같은 이름의 kind 로 한 줄을 남기고, 조용한 시간에는 `pending_pushes` 로 보관한다. `_BUNDLES` 에는 넣지 않는다(건마다 한 건씩). `_QUIET_HOURS_EXEMPT` · 알림 스위치 칸(`NOTIFICATION_DEFAULTS`)은 건드리지 않는다.

- [ ] **Step 1: 실패 시험.** `test_push_inbox.py` 의 `test_a_push_kind_is_recorded_under_its_inbox_kind` 파라미터에 `("heart_task_approved","heart_task_approved")` · `("heart_task_rejected","heart_task_rejected")` 를 더한다. 새 시험 `test_heart_task_result_at_night_is_kept_and_sent_one_by_one_in_the_morning`: `NIGHT` 에 같은 사람에게 data 가 다른(`task` 만 다른) 승인 둘 → `repo.inbox` 2줄, `pushes == []`, `repo.pending` 2줄; `MORNING` 에 `send_pending` → `pushes` 2건(묶음 문구 `밤사이` 가 없고 원래 제목 · 본문 그대로), `repo.pending_deleted` 2건.
- [ ] **Step 2: RED.** `backend/.venv/Scripts/python.exe -m pytest backend/tests/cards/test_push_inbox.py -q` Expected: 새 케이스 FAIL(알림함 비어 있음 · pending 0).
- [ ] **Step 3: 구현.** `_INBOX_KINDS` 에 두 kind(이름 같음) 추가, `_DEFERRED` 에 두 kind 추가. 주석에 "인증샷 결과(10-18 사용자 결정 가)는 학생증 결과처럼 조용한 시간엔 보관함" 한 줄.
- [ ] **Step 4: GREEN.** 같은 명령 + `pytest backend/tests/cards -q` Expected: 전부 PASS.

---

### Task 3: 서버 — 승인 · 반려 직후 알림 보내기 (campus-coder, backend)

**Files:**
- Create: `backend/app/admin/heart_task_notice.py`
- Modify: `backend/app/admin/heart_task_review.py:84-119`
- Modify(테스트 도구): `backend/tests/admin/admin_world.py`, `backend/tests/admin/conftest.py`
- Test: `backend/tests/admin/test_heart_task_notice.py`(문구 · 순수 함수), `backend/tests/admin/test_admin_heart_tasks.py`(경로 연결)

**Interfaces:**
- Consumes (Task 2): `notify(...)` 가 위 두 kind 를 안다. `FcmSender` · `CardRepository` · `get_sender`(`app.cards.router`) · `get_now`(`app.core.deps`).
- Produces:
  ```python
  # heart_task_notice.py
  class ResultNotice(NamedTuple): kind: str; title: str; body: str; data: dict[str, str]
  def result_notice(task: str, status: str, reward_hearts: int, reject_reason: str | None) -> ResultNotice
  async def send_result_notice(caller: AdminCaller, sender: FcmSender, now: datetime,
                               profile_id: str, notice: ResultNotice) -> None   # 모든 예외를 삼키고 logger.exception("... profile=%s kind=%s")
  ```
  `heart_task_review.py`: 승인 · 반려 라우트에 `sender: FcmSender = Depends(get_sender)`, `now: datetime = Depends(get_now)` 추가, `_review(caller, request, submission_id, status, reject_reason, sender, now)`.

**순서(결정):** `_review` 는 ① `repo.fetch_heart_submission` 로 줄을 **먼저** 읽어(없으면 기존대로 404) task · profile id 를 얻고 → ② RPC → ③ **RPC 직후** `send_result_notice`(RPC 응답의 `status` · `reject_reason` · `reward_hearts` 로 문구) → ④ 기존 `_one` 으로 응답. RPC 뒤의 읽기가 실패해도 알림은 이미 갔다. 발송은 **요청 안에서 기다린다**(BackgroundTasks 는 Cloud Run 이 응답 뒤 CPU 를 줄여 못 간다 — 확인 못 함, 대장 결정 7 참고). `result_notice` 는 순수 함수 — 사유가 `None`/모르는 값이면 본문 "다시 제출해 주세요", data 에서 `reason` 제외. task 는 `Task` 리터럴이라 항상 둘 중 하나.

- [ ] **Step 1: 시험 도구 확장(RED 전 준비).** `AdminWorld` 에 알림 관련 요청을 받는 가짜를 더한다: `GET /rest/v1/profiles?select=status`(→ `world.profile_status`, 기본 `"active"`), `GET /rest/v1/notification_settings`(→ `[]`), `GET /rest/v1/push_tokens`(→ `world.push_tokens`, 기본 `[{"token":"tok-1","platform":"android"}]`), `POST /rest/v1/notifications`(→ `world.notifications` 에 본문 기록, `world.notifications_status` 로 실패 흉내), `POST /rest/v1/pending_pushes`(→ `world.pending`), `POST https://fcm.googleapis.com/v1/projects/*/messages:send`(→ `world.pushes` 에 `message` 기록, `world.fcm_status`/`world.fcm_raises` 로 실패 흉내). `conftest.py` 의 `client` 에서 `app.dependency_overrides[get_sender]` 를 가짜 자격증명 `FcmSender`(`tests/cards/test_push_inbox.py` 의 `_Credentials` 방식)로, `get_now` 를 `world.now`(기본 한낮 2026-10-18 12:00 서울)로 덮는다. 기존 시험이 이 확장으로 안 깨지는지 `pytest backend/tests/admin -q` 로 확인(Expected: 기존 전부 PASS — 알림이 새로 가도 가짜가 받아 준다).
- [ ] **Step 2: 순수 함수 시험(RED).** `test_heart_task_notice.py`:
  - `test_result_notice_texts_match_the_pen_table` — 표(2 task × 승인 1 + 사유 3)의 **제목 · 본문 · kind · data 를 위 "문구 표" 글자 그대로** 비교(예: `result_notice("everytime_post","approved",40,None) == ResultNotice("heart_task_approved","에브리타임 홍보 인증이 승인됐어요","하트 40개를 받았어요",{"route":"heart_tasks","task":"everytime_post"})`, `result_notice("kakao_share","rejected",25,"reused")` → 제목 "단톡방 공유 인증이 반려됐어요", 본문 "이미 쓴 캡처예요 · 다시 제출해 주세요", data `{"route":"heart_task_retry","task":"kakao_share","reason":"reused"}`).
  - `test_the_hearts_in_the_body_are_the_servers_value` — `reward_hearts` 25 → "하트 25개를 받았어요".
  - `test_a_missing_or_unknown_reason_still_makes_a_plain_retry_notice` — `None` · `"blurry"` → 본문 "다시 제출해 주세요", `"reason" not in data`.
  - `test_the_data_only_has_route_task_and_reason` — 모든 케이스에서 `set(data) <= {"route","task","reason"}`.
- [ ] **Step 3: 경로 시험(RED).** `test_admin_heart_tasks.py` 에 추가(승인 · 반려 호출은 기존 `ADMIN_HEADERS`, `world.submissions[S1] = submission(S1)`):
  - `test_approve_records_the_inbox_line_and_pushes_with_the_rpc_reward` — 200, `world.notifications == [{"profile_id": PROFILE, "kind":"heart_task_approved","title":"에브리타임 홍보 인증이 승인됐어요","body":"하트 40개를 받았어요","data":{"route":"heart_tasks","task":"everytime_post"}}]`, `len(world.pushes)==1` 이고 같은 제목 · 본문 · data.
  - `test_reject_pushes_the_chosen_reason_and_the_retry_route` — 세 사유를 parametrize, 본문 `f"{문구} · 다시 제출해 주세요"`, data `route == "heart_task_retry"`.
  - `test_the_notice_never_carries_photo_admin_ip_or_nickname` — 알림함 본문 + FCM 본문 전체 JSON 문자열에 `storage_path` 값(`{PROFILE}/{S1}.jpg`), `ADMIN`, `203.0.113.7`(X-Forwarded-For 로 보냄), "하늘" 이 없다.
  - `test_a_push_failure_does_not_flip_the_review` — `world.fcm_status=500` 과 `world.fcm_raises=httpx.ConnectError` 두 경우 모두 200, 응답 `status == "approved"`, `world.notifications` 1줄 남음.
  - `test_an_inbox_write_failure_does_not_flip_the_review_and_the_push_still_goes` — `notifications_status=500` → 200, `world.pushes` 1건.
  - `test_a_profile_lookup_failure_does_not_flip_the_review` — `profiles` GET 500 → 200.
  - `test_second_review_409_sends_nothing_more` — 승인 두 번 → 두 번째 409, `notifications` · `pushes` 각 1건뿐. 반려 뒤 승인도 같음.
  - `test_unknown_submission_and_invalid_reason_send_nothing` — 404 · 422(`{"reason":"blurry"}`) 에서 알림 · FCM 요청 0.
  - `test_suspended_or_withdrawn_gets_no_line_and_no_push_but_the_review_stands` — `profile_status` 를 `"suspended"` · `"withdrawn"` → 200, 알림함 · FCM 0.
  - `test_at_night_the_push_waits_in_pending_but_the_inbox_line_is_immediate` — `world.now` = 23:00 → `notifications` 1, `pushes` 0, `pending` 1(kind `heart_task_approved`).
  - `test_the_notice_goes_out_even_if_the_follow_up_read_fails` — RPC 뒤 `heart_task_submissions` 읽기를 500 으로(첫 읽기 이후) → 응답은 500 이어도 `world.notifications` 1줄(알림이 RPC 직후라는 증거).
- [ ] **Step 4: RED 확인.** `backend/.venv/Scripts/python.exe -m pytest backend/tests/admin/test_heart_task_notice.py backend/tests/admin/test_admin_heart_tasks.py -q` (워크트리에서는 `-c "import app; print(app.__file__)"` 로 이 트리를 읽는지 먼저 확인). Expected: 새 시험 FAIL(모듈 없음 / 알림 0건), 기존은 PASS.
- [ ] **Step 5: 구현.** `heart_task_notice.py` 에 위 두 이름(상수 `TASK_TITLE` · `REASON_TEXT` 포함) 구현. `send_result_notice` 는 `CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)` 로 `notify(repo, sender, profile_id, notice.kind, notice.title, notice.body, notice.data, now)` 를 `try/except Exception` 으로 감싼다. `heart_task_review.py` 는 위 "순서(결정)" 대로 `_review` 를 바꾼다. 승인 라우트는 본문을 읽지 않는 기존 규칙 유지.
- [ ] **Step 6: GREEN.** 같은 명령 + `pytest backend -q` 전체. Expected: 전부 PASS(`tests/admin/test_admin_caller.py` 의 "모든 경로가 관문 뒤" 시험 포함).

---

### Task 4: 앱 — 알림 종류 · 푸시 경로 · 알림함 그림 (campus-coder, frontend 로직)

**Files:**
- Modify: `frontend/lib/notifications/model/app_notification.dart:4-20`, `frontend/lib/core/push/push_route.dart:7-22`, `frontend/lib/core/push/foreground_push.dart:97-98`, `frontend/lib/notifications/view/notification_row.dart:19-27`(switch 한 줄씩만 — enum 이 늘면 exhaustive switch 가 컴파일 오류라 이 Task 가 같이 고친다)
- Test: `frontend/test/core/push/push_route_test.dart`, `frontend/test/core/push/foreground_push_test.dart`, `frontend/test/notifications/model/http_notifications_repository_test.dart`, `frontend/test/notifications/view/notifications_screen_test.dart`

**Interfaces:**
- Produces: `NotificationKind.heartTaskApproved('heart_task_approved')` · `heartTaskRejected('heart_task_rejected')`; `PushRoute.resolve` 의 새 route 값 `heart_tasks` → `AppRoutes.heartTasks`, `heart_task_retry` → `18b 경로`; `notificationIcon`: 승인 → `AppIcon3d.heart`, 반려 → `AppIcon3d.ban`(pen 으로 확인 — Task 5 의 값표 확인 전 잠정).

**18b 경로 규칙(#599 와 같은 원칙):** `data` 의 `task` · `reason` 문자열을 경로에 그대로 싣지 않는다. `HeartTaskKind.tryParse(task)` 가 `needsProof` 일 때만 쓰고, 사유는 `HeartTaskRejectReason.tryParse` 로 거른 enum 의 `code` 만 쿼리에 싣는다. 모양은 `heartTaskSubmitLocation(kind, reason)`(`heart_task_submit_screen.dart:47`)과 같게 `Uri(path: '${AppRoutes.heartTaskSubmit}/${kind.code}', queryParameters: reason == null ? null : {'reason': reason.code}).toString()`. core 가 view 파일을 import 하지 않도록 이 한 줄을 `push_route.dart` 에 두고, 둘이 같은지 시험으로 못박는다. `task` 가 없거나 인증샷 항목이 아니면 `AppRoutes.heartTasks`(18a)로 보낸다(null 로 막지 않는다 — route 자체는 아는 값이므로 `_chatRoom` 과 같은 방침).

- [ ] **Step 1: 실패 시험(RED).**
  - `push_route_test.dart`: `heart_tasks 알림은 18a 로 간다`(`{'route':'heart_tasks','task':'kakao_share'}` → `AppRoutes.heartTasks`); `heart_task_retry 는 사유를 실은 18b-2 로 간다`(`{'route':'heart_task_retry','task':'everytime_post','reason':'date_missing'}` → `heartTaskSubmitLocation(HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing)` 와 같고 문자열은 `/heart-tasks/submit/everytime_post?reason=date_missing`); `사유가 없거나 모르면 사유 없는 18b 로`(reason 없음 · `'blurry'` · `''` → `/heart-tasks/submit/kakao_share`); `task 가 없거나 인증샷 항목이 아니면 18a 로`(없음 · `'poll_vote'` · `'../x'` · `''` → `AppRoutes.heartTasks`); `경로에 원문을 그대로 싣지 않는다`(`'task': 'everytime_post/../../me'` 도 `AppRoutes.heartTasks`, 결과에 `..` 없음).
  - `http_notifications_repository_test.dart`(또는 `app_notification` 모델 시험이 있는 곳): `fromWire('heart_task_approved') == heartTaskApproved`, `rejected` 도, `fromWire('heart_task_zzz') == other`(옛 앱 동작을 새 값 기준으로 못박음).
  - `foreground_push_test.dart`: 같은 route(`heart_tasks`)에 `task` 만 다른 두 푸시가 서로 다른 시스템 알림 id 로 뜬다(한쪽이 다른 쪽을 덮지 않는다). `_idFor` 가 private 라 기존 시험 방식(가짜 `SystemNotifications` 에 기록된 id 비교)을 따른다.
  - `notifications_screen_test.dart`: 승인 줄(`kind: heartTaskApproved`, data `{'route':'heart_tasks','task':'everytime_post'}`)을 누르면 `/heart-tasks`, 반려 줄(`heartTaskRejected`, `{'route':'heart_task_retry','task':'kakao_share','reason':'reused'}`)을 누르면 `/heart-tasks/submit/kakao_share?reason=reused` 가 열린다(둘 다 알림함 위에 `push` — 뒤로가기가 알림함으로 돌아옴); 줄 그림이 각각 `notificationIcon` 의 heart / ban 이다; 모르는 kind 줄은 종 그림이고 눌러도 화면이 안 바뀐다.
- [ ] **Step 2: RED 확인.** `cd frontend && flutter test test/core/push test/notifications` Expected: 새 시험 FAIL(enum 값 · route 없음).
- [ ] **Step 3: 구현.** 위 Interfaces 대로. `foreground_push.dart` `_idFor` 열쇠에 `data['task']` 추가(없으면 기존 값과 같아 다른 알림 id 는 변하지 않는다). `refreshForPush`(`push_refresh.dart`)는 건드리지 않는다 — 18a 는 autoDispose 라 들어올 때 새로 읽는다. 18a 를 이미 보고 있을 때 같은 경로로 `go` 하면 새로 읽는지는 확인 못 함(Task 5 에서 수동 확인 항목).
- [ ] **Step 4: GREEN.** `flutter test test/core/push test/notifications test/core/router` + `flutter analyze` Expected: 0 failures, 0 issues.

---

### Task 5: 화면 — 18a 반려 줄 사유 · 알림함 행 pen 대조 (campus-ui, frontend 화면)

**Files:**
- Modify: `frontend/lib/billing/view/heart_task_row.dart:21-100`(반려 줄 사유 한 줄), `frontend/lib/notifications/view/notification_row.dart`(pen 대조 결과 그림 · 글자만, 구조 변경 없음)
- Test: `frontend/test/billing/view/heart_tasks_screen_test.dart`, `frontend/test/notifications/view/notifications_screen_test.dart`

**campus-pen 값표 필요 (구현 전 대장이 campus-pen 에게 요청, pencil 직접 호출 금지):** pen 앱 영역 iVS6T 안 "15. 인증샷 결과 알림 · 반려 사유 표시" 섹션의 노드 id 와 아래 값.
1. 18a 반려 줄(왼쪽 2줄 `에브리타임 홍보 / 하트 40 · 월 1회 / ⚠ 반려 · 날짜가 안 보여요`): 사유 줄의 노드 id, 경고 아이콘 종류(삼각형 느낌표 — 앱 `AppIcons.alertTriangle` 인지)와 크기, 글자 크기 · 굵기 · 줄높이 · 색(`AppColors.error` 토큰과 같은지), 아이콘-글자 간격, 위 줄과의 간격, 줄 전체 높이(세 줄일 때) · 아래 선 유무(기존 `w3aZL` 은 반려 줄 아래 선이 투명).
2. 알림함 행 `알림함_인증_결과_행.png` 의 승인 · 반려 줄: 3D 그림 두 개의 노드 id(승인 = 분홍 하트, 반려 = 금지 표시 — 앱 `AppIcon3d.heart` `zxXQG` · `AppIcon3d.ban` `eUCJv` 와 같은 마스터인지), 안 읽음 점 · 굵기 등 기존 `Item · Notification` 마스터와 다른 값이 있는지(없으면 "마스터 그대로"로 확정).
3. 반려 본문이 길 때(`게시글·공유가 확인되지 않아요 · 다시 제출해 주세요`) pen 이 두 줄로 줄바꿈하는지(앱은 `maxLines: 2` 로 이미 두 줄까지 허용).
값표가 없으면 이 Task 는 "pen 값 필요: 노드/요소"로 멈춘다(추측 금지).

**Interfaces:**
- Consumes: `HeartTask.rejectReason`(기존), `HeartTaskRejectReason.label`, `AppIcons.alertTriangle`, Task 4 의 `NotificationKind`.
- Produces: `HeartTaskRow` 가 `state == rejected && rejectReason != null` 일 때 보상 줄 아래에 사유 줄 `반려 · ${rejectReason.label}` 을 그린다. 사유 줄은 키 `heartTaskRejectLineKey`(테스트가 크기를 재는 표식).

- [ ] **Step 1: 실패 시험(RED).** `heart_tasks_screen_test.dart`(기존 `sampleHeartTasks(everytime: rejected, everytimeReason: ...)` 활용):
  - `반려 줄에 사유 한 줄이 보인다` — 세 사유를 parametrize: `find.text('반려 · 날짜가 안 보여요')` · `'반려 · 게시글·공유가 확인되지 않아요'` · `'반려 · 이미 쓴 캡처예요'` 각각 `findsOneWidget`.
  - `사유 줄은 반려 줄에만 있다` — 미완료 · 검수중 · 완료 줄과 사유가 없는 반려(모델상 `rejectReason == null`)에는 `find.textContaining('반려 ·')` 가 `findsNothing`.
  - `단톡방 반려도 같다` — `kakaoShare` 줄에도 사유가 붙는다(pen `18a_반려_사유_날짜_게시글.png` 의 두 번째 줄).
  - `반려 줄을 누르면 사유를 실은 18b-2 로 간다` — 기존 시험 유지(`/heart-tasks/submit/everytime_post?reason=date_missing`).
  - `사유 줄이 낭독에 읽힌다` — `tester.getSemantics` 로 줄 안에 "반려 · …" 글자가 있고 경고 아이콘 단독 낭독이 없다(`excludeSemantics` 또는 `Icon` 의 `semanticLabel` 없음 확인).
  - 값 대조: 사유 줄 높이 · 글자 크기 · 색이 값표와 같다(pen 노드 id 주석).
  - `notifications_screen_test.dart`: pen 목록 `알림함_인증_결과_행.png` 대로 승인 줄(제목 "에브리타임 홍보 인증이 승인됐어요", 본문 "하트 40개를 받았어요")과 반려 줄(제목 "단톡방 공유 인증이 반려됐어요", 본문 "날짜가 안 보여요 · 다시 제출해 주세요")을 안 읽음으로 두고 제목 굵기 700 · 점 표시 · 그림 28 · 줄 높이가 기존 `Item · Notification` 값과 같다.
- [ ] **Step 2: RED 확인.** `flutter test test/billing/view/heart_tasks_screen_test.dart test/notifications/view/notifications_screen_test.dart` Expected: 사유 시험 FAIL(글자 없음).
- [ ] **Step 3: 구현.** `HeartTaskRow` 왼쪽 Column 의 보상 줄 아래에 조건부 사유 줄(`Row`: `Icon(AppIcons.alertTriangle, color: AppColors.error)` + 사유 `Text`) 추가. 토큰 밖 크기는 값표의 노드 id 를 주석으로. 줄 오른쪽 "다시 제출"과 세로 정렬은 값표대로. `Text` 는 `Flexible` 로 길면 줄바꿈 · 글자 배율 1.3 에서 넘치지 않는지 확인.
- [ ] **Step 4: 수동 확인 두 가지(보고에 적기).** (a) 푸시 탭으로 18a 에 들어왔을 때 하트 잔액 · 반려 줄이 최신인지, (b) 이미 18a 를 보고 있을 때 같은 경로 푸시를 눌러도 새로 읽는지. (a)(b) 가 낡으면 `refreshForPush` 에 `heart_tasks` · `heart_task_retry` 케이스를 더하는 후속 Task 를 대장에게 제안(이번 계획 범위 밖).
- [ ] **Step 5: GREEN.** `flutter analyze` 0 issues, `flutter test` 전체 0 failures(전체 테스트는 "전체 flutter test 차례"를 받은 도우미만 — 아니면 위 두 파일 + `test/core/push` · `test/notifications` · `test/billing`).

---

## 배포 · 문서 순서 (구현 뒤, 이 계획서 범위 밖)

1. 마이그레이션 먼저 적용(campus-supabase, 사용자 원문 승인 뒤) → 서버 배포 → 앱 빌드. 서버가 먼저 나가면 알림함 줄이 안 남는다(Review Focus 7).
2. 문서(campus-docs): `docs/ERD.md` 알림함 · 보관 알림 kind 목록 두 개 추가, `frontend/docs/DESIGN.md` 알림함(09c)과 18a 반려 줄, pen 섹션 15 의 "(승인 전)" 문구는 campus-pen.

## 대장 결정 필요 (추측 금지 — 아래는 내가 정한 안이고, 바꾸려면 알려 주세요)

**확정(대장, 2026-10-18):** 1 조용한 시간 = 푸시는 아침 · 알림함 줄은 즉시 / 2 새 알림 스위치 없음 / 3 옛 앱은 종 그림 · 무동작 그대로 /
4 보관 90일 그대로 / 5 kind 둘(`heart_task_approved` · `heart_task_rejected`) / 6 반려 사유 표시 기간 기존 규칙 그대로 /
7 요청 안에서 기다리되 **시간 상한을 둔다**(기존 FCM 모듈에는 별도 시간 제한이 없어 5초 상한 — 아래 편차 1) 시간 초과도 200 유지(로그만) /
8 마이그레이션 시각 `20261018130100`(D3 는 `20261018120000` 이라 안 겹침) / 9 pen 값표는 대장이 campus-pen 에 따로 요청, Task 5 는 값표가 오면 campus-ui 가 맡는다(이번 구현은 Task 1~4).

1. **조용한 시간(22~08시)에 관리자가 검수하면** — (추천) 푸시는 아침 8시에 한 건씩 보낸다, 알림함 줄은 바로 남는다(학생증 결과와 같은 보관함 방식, 사용자 규칙 "예외는 채팅 · 카드 도착뿐"). 대안: 즉시 보낸다(밤 푸시 허용 = 사용자 규칙을 깨므로 비추천).
2. **알림 스위치** — (추천) 새 스위치를 만들지 않는다. 푸시는 늘 켜짐(설정 8개 스위치 그대로, 학생증 결과와 같다), 알림함에는 늘 남는다. 대안: 스위치 칸 추가(설정 화면 16d · 표 칼럼 · pen 까지 번진다).
3. **옛 앱이 새 종류를 받으면** — (추천) 그대로 둔다: 알림함에 제목 · 본문 + 종 그림으로 보이고 눌러도 무동작, 푸시 탭은 앱만 열림(코드가 이미 모르는 kind 를 `other` 로 읽는다). 대안: 서버가 앱 버전을 보고 거르기 — 서버가 앱 버전을 모른다, 비추천.
4. **알림함에 남기는 기간** — (추천) 기존 90일 그대로(`RETENTION_DAYS=90`, 종류별 예외 없음).
5. **알림 종류를 둘로(승인 · 반려) 나눈 것** — (추천) 둘. 한 종류 + data 로 그림을 가르면 알림함 그림 switch 가 data 를 읽어야 한다. 둘이면 옛 앱 · 새 앱 모두 종류만 보고 그림이 정해진다.
6. **18a 반려 줄 사유는 언제까지 보이나** — 기존 서버 규칙 그대로: 다시 제출하면(검수중) 사라지고, 반려가 마지막 제출인 동안 보인다. 바꿀 일이면 알려 주세요.
7. **서버가 푸시 보내기를 기다린 뒤 200 을 준다**(기기 최대 5개 × FCM 한 번씩) — 관리자 버튼 응답이 그만큼 느려질 수 있다. 백그라운드로 돌리면 Cloud Run 이 응답 뒤 CPU 를 줄여 안 갈 수 있어 인라인으로 정했다. FCM 시간 제한은 확인 못 함(기본 httpx 시간 제한을 따른다) — 느리면 시간 제한 추가를 후속으로.
8. **마이그레이션 파일 시각** — `20261018130100` 로 정했다(지정하신 130000 이후). 다른 창이 같은 시각을 쓰고 있으면 알려 주세요.
9. **pen 값표** — Task 5 의 3가지(18a 사유 줄 값 · 알림함 그림 노드 id · 긴 본문 줄바꿈)를 campus-pen 에게 요청해 주세요.

## 구현 편차 기록

(구현하면서 계획서와 달라진 점을 여기에만 덧붙인다. 위 본문은 고치지 않는다.)

구현 범위: Task 1~4(2026-10-18). Task 5(화면)는 pen 값표 대기. 커밋 없음.

1. **결정 7 — 시간 상한(Task 3).** 기존 `FcmSender`/`get_client` 의 `httpx.AsyncClient()` 는 요청당 기본 5초 제한뿐이고 기기 여러 개를 차례로 보내 합계 제한이 없다(자격증명 갱신은 별도 스레드). 그래서 `heart_task_notice.NOTICE_TIMEOUT_SECONDS = 5.0` 으로 `notify()` 전체를 `asyncio.wait_for` 로 감쌌다. 시간 초과는 `logger.warning("... profile=%s kind=%s")` 만 남기고 200 을 유지한다. 시험: `test_a_slow_push_is_cut_off_and_the_review_still_answers_200`, `test_a_timeout_logs_the_profile_and_kind_but_never_the_words`(상수를 0.05 로 monkeypatch + 안 끝나는 발송기).
2. **Task 1 pgTAP 미실행.** 대장 지시로 마이그레이션 · pgTAP 파일은 쓰되 실행하지 않았다(RED · GREEN 확인은 대장 DB 차례 몫). `notifications_test.sql` 은 기존 "나머지 다섯 종류" 문장을 일곱 종류로 고쳐 plan 개수(17)가 그대로이고, `pending_pushes_test.sql` 은 lives_ok 하나를 더해 plan 13 → 14 로 바꿨다. 계획서 Step 1 의 "plan 개수를 새로 맞춘다"와 같다.
3. **Task 3 — 시험 도구.** 계획서의 가짜 확장에 더해 `AdminWorld.fail_submission_reads_after`(첫 읽기 뒤 읽기를 500 으로)와 `profile_status_http` 를 두었다. `FcmSender` 의 `get_sender` · `get_now` 덮어쓰기는 `tests/admin/conftest.py` 에서 모든 관리자 시험에 적용된다.
4. **Task 3 — 시험 수.** 문구 시험은 `test_heart_task_notice.py`(parametrize 풀면 14건), 경로 시험은 `test_admin_heart_tasks.py` 뒤쪽에 더했고 계획서 목록과 같되, "투표 · 사유 오류 · 없는 줄" 시험을 한 함수로 합쳤고 "ValueError · 알림함 쓰기 실패 · 프로필 조회 실패"는 `test_a_notice_failure_never_flips_the_review` 하나로 parametrize 했다.
5. **Task 4 — 기존 파일 한 줄 손질.** enum 이 늘면 `notification_row.dart` 의 exhaustive switch 가 컴파일 오류라 이 파일의 `notificationIcon` switch 에 두 줄만 더했다(화면 구조 변경 없음 — 계획서도 허용). 알림함 그림은 pen 값표 확인 전 잠정(승인 `AppIcon3d.heart`, 반려 `AppIcon3d.ban`).
6. **Task 4 — 경로 시험.** `PushRoute` 의 `task` · `reason` 이 문자열이 아닌 값(숫자)일 때도 막는 케이스를 더했다(`reason: 7`, `task: 3`).
