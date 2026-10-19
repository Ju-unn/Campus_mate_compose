# 인증샷 여러 장 + 단톡방 공유 이어서 제출 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 무료 하트 인증샷을 제출 1건당 1~3장으로 받고, 단톡방 공유(`kakao_share`)는 검수 중이어도 월 3회 한도 안에서 이어서 낼 수 있게 하며, 18a 에 검수 대기 목록을, 관리자 웹에는 여러 장 보기를 만든다.

**Architecture:** 사진 경로를 `heart_task_submissions.storage_paths text[]` 한 칸으로 옮기고(옛 `storage_path` 폐기), "항목당 검수 중 한 줄" 부분 unique 인덱스를 없앤 뒤 `submit_heart_task` 가 사람·항목별 advisory lock 아래에서 한도를 센다. 서버는 multipart 한 요청으로 사진 1~3장을 받고(옛 앱의 `photo` 한 장도 받는다), 18a 응답에 옛 여섯 칸을 그대로 둔 채 `can_submit` · `max_photos` · `pending` 을 더한다.

**Tech Stack:** Postgres(pgTAP), FastAPI + PostgREST/Storage(httpx), Flutter(Riverpod, `image_picker`, `http` multipart), Flutter 웹 관리자(`admin_web/`). 새 의존성 없음.

**Spec:** 대장 결정 4가지(요청문 2026-10-19) + `docs/superpowers/plans/2026-09-28-heart-tasks.md`(원 설계) + `2026-10-18-admin-heart-task-review.md`(관리자 검수) + `2026-10-18-heart-task-result-notify.md`(결과 알림). 사용자 원문(10-19): "에브리타임 홍보랑 카카오톡 홍보는 사진 3장씩 넣게 해줘 / 현재 문제점: 앱에 카카오톡 월 3회인데 하나 보면 승인대기해야 함, 또 보내고 승인 대기 승인 번거로움. 단톡방 공유 밑에 대기 목록 보이게 하고 3회 보낼 수 있게 해줘. 앱도 고쳐야함."

## Global Constraints

- 제출 1건당 인증샷 **최소 1장, 최대 3장**. 에브리타임(월 1회) · 단톡방 공유(월 3회) 둘 다.
- 월 한도는 그대로: `heart_task_monthly_limit` 에브리타임 1 · 단톡방 3. 쓴 횟수 = 이번 달(한국 시간) 검수 중 + 승인, 반려는 빠진다. **검수 중 + 승인 ≥ 한도면 제출 거절.** 동시 요청에서도 새지 않아야 한다.
- 거절 코드는 지금과 같다: 한도에 찼고 검수 중인 줄이 있으면 409 `HEART_TASK_IN_REVIEW`("이미 확인 중이에요, 결과를 기다려 주세요"), 찼고 검수 중이 없으면 429 `HEART_TASK_MONTHLY_LIMIT`("이번 달에는 더 인증할 수 없어요"). 에브리타임은 월 1회라 동작이 사실상 그대로다.
- 하위 호환: 옛 앱(vc11/vc12)은 multipart 필드 `photo` 한 장으로 계속 제출할 수 있어야 하고, 응답에는 옛 여섯 칸(`task` `reward_hearts` `state` `used` `limit` `reject_reason`)이 그대로 남는다. 옛 앱은 `state` 의 네 값(`open` `reviewing` `done` `rejected`)만 안다.
- 10-18 보안 수정 유지: 사진마다 `photo.read(MAX_IMAGE_BYTES + 1)`(한도+1 바이트만 읽기), 앱이 보낸 Content-Type 은 믿지 않고 매직바이트로 판정(`student_id_content_type`), 파일당 10MB · jpeg/png.
- 로그 · 알림 · 디스코드 · 작업 기록에 사진 경로 · 서명 URL 을 싣지 않는다(번호만). 서명 URL 은 응답에만 간다.
- 마이그레이션 시각은 **20261019100000 이후**(운영에는 10-18 묶음 11개까지 적용, 마지막 파일 `20261018150000`). 함수에는 `revoke execute ... from public, anon, authenticated` 를 처음부터 같이 쓴다.
- 클라이언트는 본인 줄 읽기만(RLS 정책 하나 `heart task submissions are readable by owner`). 쓰기는 FastAPI(service_role) 뿐.
- 공용 위젯(`common/**`, `core/theme/**`)은 이 계획에서 고치지 않는다. 화면 값(간격 · 크기 · 글자)은 pen 노드 id 와 값표가 있어야 쓴다 — 없으면 **"pen 값 필요: 노드/요소"**.
- 운영 DB 적용 · 서버 배포 · 앱 빌드 · 스토어 업로드는 하지 않는다(사용자 10-19: 내일 아침 검토 뒤). 구현은 로컬 워크트리와 draft PR 까지.

## Review Focus

(spec 이 말하지 않았지만 사람이 쓰다 깨질 입력. 각 줄의 시험은 맡은 Task 에 있다.)

1. **마지막 한 칸을 두 요청이 동시에 노린다**(단톡방 승인 1 + 검수 중 1 = 2/3 에서 두 기기가 동시에 제출 → 4건이 되면 안 됨). → Task 1 `submit takes a per-person-per-task advisory lock` + 수동 두 세션 확인(Step 6).
2. **3장 중 한 장만 올라가고 끝났다**(두 번째 업로드 실패 · DB 거절 · 응답 끊김). 거절이면 시도한 파일을 전부 지우고, 응답을 못 받았으면(줄이 생겼을 수 있음) 파일을 둔다. → Task 2.
3. **세 장 중 한 장이 형식 오류 · 10MB 초과 · 4장째 · 0장.** 어떤 것도 올리지 않고 거절, 큰 파일은 한도+1 바이트만 읽는다. → Task 2.
4. **옛 앱이 `photo` 한 장으로 낸다 / 새 앱이 옛 서버(새 칸 없음)를 읽는다.** 서로 죽지 않는다. → Task 2 · Task 4.
5. **60일 정리가 사진 3장 줄을 다룬다**: 파일 3개를 모두 지우고 경로를 비우며, 이미 비운 줄이 매일 다시 뽑혀 100개 한도를 채우지 않는다. 관리자 상세에서 3장 중 일부만 서명에 실패해도 나머지는 보인다. → Task 2 · Task 3.

## 읽어서 확인한 사실 (파일:줄)

| 사실 | 근거 |
| --- | --- |
| 표는 `storage_path text` 한 칸, 검수 중이면 필수 check `proof_while_reviewing` | `supabase/migrations/20260928030000_create_heart_task_submissions.sql:15-27` |
| 항목당 검수 중 한 줄 부분 unique 인덱스 | 같은 파일 `:38-39` (`heart_task_submissions_one_reviewing`) |
| `heart_task_status` 는 `used`(검수 중+승인, 이번 달) · `reviewing`(달 무관) 를 계산 — **이 함수는 바꿀 필요가 없다** | `20260928030100_create_heart_task_functions.sql:29-80` |
| `submit_heart_task` 는 `v_reviewing` 이면 CM409, `v_used >= v_limit` 이면 CM429, 잠금 없음 | 같은 파일 `:88-118` |
| guard 트리거가 `storage_path` 를 검수 중 고정, 검수 뒤엔 null 로 비우기만 허용 | 같은 파일 `:126-157` |
| 승인 트리거는 줄마다 한 번 `grant_hearts` — 줄이 여러 개여도 줄마다 한 번 | 같은 파일 `:164-180` |
| 관리자 검수 함수 · 결과 알림 문구는 사진 경로를 쓰지 않는다 → **바꿀 필요 없음** | `20261018011200_admin_review_heart_task.sql`, `backend/app/admin/heart_task_notice.py:37-49` |
| 이미 쓰는 advisory lock 관례(`hashtextextended`) | `20260928010000_create_referrals.sql:87`, `20261013010100_billing_purchases.sql:93` |
| 제출 라우터: `photo: UploadFile`, 한 장 `read(MAX+1)`, 사전 409/429, 업로드→DB→실패 시 삭제, 응답 끊김은 파일 둠 | `backend/app/heart_tasks/router.py:78-123` |
| **제출 사진은 Vision 을 거치지 않는다.** `check_photo` 는 `me/router.py:188` · `profile_onboarding/router.py:152` 에서만 불리고 하루 30회 상한(`photos.py:15`)은 거기서만 센다. | `Grep check_photo` |
| 정리 배치: `storage_path not.is.null` 을 `reviewed_at` 순 100개, 파일 삭제 후 `storage_path=null` PATCH | `backend/app/heart_tasks/repository.py:32-51`, `cleanup.py:18-33` |
| 관리자 읽기: `_SUBMISSION_SELECT` 에 `storage_path`, 사진 한 장 서명(300초), 지난 제출 최대 5건 | `backend/app/admin/repository.py:24,82-92`, `heart_task_review.py:28-79` |
| 앱: 사진 한 장 `File? photo`, `pickImage`, `sendMultipart`(필드 `photo` 한 장 전용) | `heart_task_submit_view_model.dart:20-60`, `http_heart_task_repository.dart:27-31`, `core/http/api_client.dart:73-81` |
| 다중 파일 multipart 선례: `savePhotos` 가 `sendRequest` 로 `MultipartRequest` 를 직접 만든다 | `frontend/lib/me/model/http_me_repository.dart:113-132` |
| 앱 줄은 18a 와 하트 스토어(18)가 같이 쓴다 | `heart_tasks_screen.dart:71`, `heart_store_screen.dart:334` |
| 관리자 웹: `HeartTaskDetail.photoUrl` 한 장, `ProofPhotoViewer`(큰 380 + 지난 제출 썸네일 64), `ProofZoom(photoId=제출 번호)` | `admin_web/lib/heart_tasks/heart_task_item.dart:100-130`, `proof_photo_viewer.dart` |
| `storage_path` 를 직접 쓰는 다른 곳(이 변경으로 깨짐): pgTAP `heart_tasks_test.sql`(11곳) · `rls_slice0_test.sql`(3) · `admin_heart_task_review_test.sql`(1) · `admin_stats_matching_test.sql`(2), `backend/tests/admin/admin_world.py:55`, e2e `area2*.py`(9) | `Grep storage_path` |

## 결정과 근거

### D1. 데이터 모델: `storage_paths text[]` (추천) vs 새 표 `heart_task_submission_photos`

| 비교 | `text[]` 한 칸 | 새 표 (submission_id, position, storage_path) |
| --- | --- | --- |
| 쓰기 원자성 | 줄 하나 insert 로 끝 | 줄 + 사진 줄 최대 3개를 한 함수 안에서(같은 트랜잭션이라 가능하나 문장이 늘어남) |
| "검수 중이면 1~3장" 불변식 | **check 제약** 한 줄(`cardinality between 1 and 3`) | 표 사이 제약은 check 로 못 건다 → 함수 + 지연 제약 트리거 필요 |
| 기존 guard 트리거 | 칸 이름만 바꾸면 됨(검수 중 고정, 검수 뒤엔 `'{}'` 로 비우기만) | 사진 표에도 guard 트리거 하나 더 |
| RLS | 그대로(정책 하나, 본인 줄) | 새 표에 정책 + grant + pgTAP 새로, 부모 줄 소유자 join 정책 |
| 관리자 읽기 | `select storage_paths` 그대로 | 임베드 `heart_task_submission_photos(position,storage_path)` |
| 정리 배치 | 줄당 경로 배열 → 평탄화해 삭제 → `storage_paths=[]` PATCH | 사진 줄 단위로 삭제/비움(부분 실패 단위가 작음) |
| 백필(운영에 이미 있는 제출은 사진 1장) | `update ... set storage_paths = array[storage_path] where storage_path is not null` 한 문장 | insert ... select 한 문장 + 부모 check 완화 |
| 사진별 속성(해시 · 크기)을 나중에 붙이기 | 어려움(표로 다시 이전) | 쉬움 |
| 이번 요구에 필요한가 | 사진은 순서 있는 경로 목록일 뿐 | **아니오**(해시로 "이미 쓴 캡처" 자동 판별은 요구에 없음) |

**추천: `text[]`.** 이번 요구는 "순서 있는 경로 최대 3개"뿐이고, 표를 나누면 RLS · guard · 정리 · 불변식 어느 하나도 이득 없이 면이 두 배가 된다. 사진별 해시가 필요해지는 날 표로 옮긴다(마이그레이션 머리에 `-- shortcut:` 주석으로 남긴다). 순서 = 배열 순서(1번째가 큰 사진 기본).

### D2. 동시 요청에서 한도가 새지 않게: 사람·항목별 advisory lock (추천)

- **(a) 채택.** `pg_advisory_xact_lock(hashtextextended('heart_task:' || p_profile::text || ':' || p_task::text, 0))` 를 함수 맨 앞(검증 다음)에서 잡고, 그 아래에서 `heart_task_status` 를 읽고 insert. PostgREST RPC 는 한 트랜잭션(READ COMMITTED)이라 두 번째 요청은 락에서 기다렸다가 첫 요청이 커밋한 뒤 **새 스냅샷**으로 센다 → 3/3 을 보고 거절. 저장소 선례(구매 · 투표 · 추천)와 같은 모양이고 다른 줄을 막지 않는다(에브리타임과 단톡방, 다른 사람끼리도 서로 안 막는다).
- (b) `profiles`/`entitlements` 줄 `for update`: 하트 지급 · 구매 등 다른 쓰기까지 같이 막고 승인 트리거(`grant_hearts`)와 락 순서가 얽힐 위험 → 기각.
- (c) insert 뒤 다시 세고 넘으면 삭제: READ COMMITTED 에서는 둘 다 서로의 미커밋 줄을 못 봐 둘 다 통과 → 기각.
- (d) `(profile, task, month, slot)` unique + 빈 칸 찾기: 동작은 하지만 월 경계 · 반려 반환 계산이 복잡해 YAGNI → 기각.

부분 unique 인덱스 `heart_task_submissions_one_reviewing` 은 **삭제**(남기면 단톡방의 두 번째 검수 중 줄이 23505 로 막힌다). 에브리타임이 검수 중에 또 오면 `used(1) >= limit(1)` 이고 `reviewing` 이라 CM409 그대로.

### D3. 한 요청에 사진 여러 장: multipart 한 요청 (추천) vs 1장씩 올리고 제출 확정

- **multipart 한 요청(`photos` 여러 파트 + 옛 `photo`) 채택.** ① 선례(`PUT /me/photos` 가 `list[UploadFile]`)와 앱 쪽 `sendRequest` 패턴이 이미 있다. ② 서버가 DB 판정(한도) 뒤에만 줄을 만들고, 실패하면 방금 올린 경로 목록만 지우면 되어 "미확정 업로드" 상태가 서버에 생기지 않는다. ③ 옛 앱 호환용 단일 `photo` 요청을 어차피 받아야 한다.
- 1장씩 업로드 후 확정은 임시 업로드 표 · 만료 정리 · 확정 API 가 새로 필요하고 고아 파일이 구조적으로 생긴다 → 기각.
- 요청 크기: 앱이 장당 압축(≤1920px JPEG)해서 보내므로 실제는 수 MB. 서버 상한 3 × 10MB = 30MB(Cloud Run HTTP/1 요청 상한 32MiB 안). 장수는 파싱 뒤 `len` 으로 막고(0장 · 4장 → 422), 장마다 `read(MAX+1)`.
- 부분 실패: 3장을 `asyncio.gather(return_exceptions=True)` 로 올리고 하나라도 실패하면 **시도한 경로 전부**를 지우고(없는 파일 삭제는 오류가 아님, `cleanup.py:22`) 그 예외를 올린다. DB 가 답하고 거절(`HTTPException` · `HTTPStatusError`)하면 같은 삭제, `TransportError`(답 못 받음)면 파일을 둔다(기존 규칙 유지).
- 파일 이름: `{profile_id}/{submission_id}-{n}.{jpg|png}` (n=1..3). 백필된 옛 경로(`{submission_id}.jpg`)는 그대로 유효. 탈퇴 배치는 `{profile_id}/` 폴더째 지우므로 영향 없음.
- 제출 사진은 Vision 검사를 **걸지 않는다**(지금과 같음). 스크린샷이라 "문서형" 판정이 정상 인증샷을 막고, Vision 하루 30회 상한(`PHOTO_CHECKS`)과는 무관하다.

### D4. 응답 필드 (18a 한 줄) — 옛 여섯 칸 유지 + 새 칸

| 필드 | 타입 | 옛/새 | 뜻 |
| --- | --- | --- | --- |
| `task` | string | 옛 | `everytime_post` `kakao_share` `poll_vote` |
| `reward_hearts` | int | 옛 | 서버 상수(40 · 25 · 5) |
| `state` | `open`/`reviewing`/`done`/`rejected` | 옛 | **파생 규칙 그대로**: 검수 중이 있으면 `reviewing`, 아니면 `used>=limit` 이면 `done`, 마지막이 반려면 `rejected`, 그 외 `open`. 옛 앱은 `reviewing` 줄을 못 누른다(지금과 같음) |
| `used` | int | 옛 | 이번 달 검수 중+승인 |
| `limit` | int | 옛 | 월 한도 |
| `reject_reason` | string/null | 옛 | `state==rejected` 일 때만 |
| `can_submit` | bool | **새** | 인증 항목이고 `used < limit`. `poll_vote` 는 false. **새 앱은 이 값으로 [제출하기]를 켠다** |
| `max_photos` | int | **새** | 인증 항목 3, `poll_vote` 0 |
| `pending` | list | **새** | 검수 중인 줄, 오래된 순. 없으면 `[]`(`poll_vote` 도 `[]`) |
| `pending[].id` | string(uuid) | 새 | 제출 번호 |
| `pending[].created_at` | string(ISO 8601) | 새 | 제출 시각 |
| `pending[].photo_urls` | list<string\|null> | 새 | 사진 순서대로 10분 서명 URL, 서명 실패한 장은 `null`(장수는 유지) |

`POST /heart-tasks/{task}/submissions`: multipart, 파트 이름 `photos`(1~3, 새 앱) 또는 `photo`(1장, 옛 앱) — 둘 다 오면 합쳐서 센다. 201 `{"task": <위 한 줄>}`. 오류: 400 `PHOTO_UNREADABLE`(어느 한 장이라도 형식 · 10MB 위반), 422(0장 · 4장 이상 · `poll_vote`), 409 / 429(Global Constraints).

관리자 `GET/POST /admin/.../heart-tasks/{id}` 한 건 응답(Task 3): `photo_urls: list<string|null>` 신설, 옛 `photo_url`(= 첫 장 또는 null) 유지, `previous[]` 도 같은 두 칸. `storage_paths` 원문은 싣지 않는다.

`state` 를 새 앱에서도 `reviewing` 으로 두는 이유: 옛 앱이 "검수 중" 칩을 계속 보이게 하려고. 새 앱은 `pending` · `can_submit` 만 본다(대장 결정 필요 3번).

### D5. 배포 틈과 되돌리기 (대장 확정 10-19: 받아들임)

**마이그레이션 `20261019100000` 적용 직후에 곧바로 서버를 배포한다. 서버만 이전 리비전으로 되돌리면 깨진다(옛 서버는 `storage_path` 칸과 `p_path` 인자를 쓴다).**

컬럼을 교체(옛 `storage_path` 폐기)하므로 마이그레이션 적용 **직후** 새 서버를 배포해야 한다. 그 사이 몇 분은 제출(옛 함수 없음)과 관리자 사진 보기(옛 칸 없음)가 오류다. 사용자 19명 · 출시 전이라 이 틈을 받아들이고, 두 단계 호환 마이그레이션(옛 컬럼 유지 + 옛 시그니처 래퍼)은 만들지 않는다(대장 결정 필요 1번). 서버만 이전 리비전으로 되돌리면 깨지므로 되돌림은 "고친 서버 새 리비전"으로 한다. 정리 배치 시각(04:00 KST) 전후는 피한다.

## File Structure

| 파일 | 일 | Task |
| --- | --- | --- |
| Create `supabase/migrations/20261019100000_heart_task_multi_photos.sql` | `storage_paths` 추가 · 백필 · `storage_path` 삭제 · check · 인덱스 삭제 · guard 교체 · `submit_heart_task` 교체 | 1 |
| Modify `supabase/tests/heart_tasks_test.sql` | `storage_path` → `storage_paths`, 새 단언 | 1 |
| Modify `supabase/tests/rls_slice0_test.sql` · `admin_heart_task_review_test.sql` · `admin_stats_matching_test.sql` | `storage_path` 입력을 `storage_paths` 로 | 1 |
| Modify `backend/app/heart_tasks/router.py` | 다중 파일 받기 · 사전 판정 · 업로드/삭제 · 응답 새 칸 | 2 |
| Modify `backend/app/heart_tasks/repository.py` | `submit(paths)` · `fetch_pending` · 정리용 조회/비우기 | 2 |
| Modify `backend/app/heart_tasks/storage.py` | `upload(..., index, ...)` 경로 이름 | 2 |
| Modify `backend/app/heart_tasks/cleanup.py` | 경로 평탄화 | 2 |
| Modify `backend/tests/heart_tasks/test_heart_tasks.py` · `test_proof_cleanup.py` | 새 시험 | 2 |
| Modify `backend/app/admin/repository.py` · `backend/app/admin/heart_task_review.py` | `storage_paths` 읽기 · 사진 여러 장 서명 · 응답 `photo_urls` | 3 |
| Modify `backend/tests/admin/admin_world.py` · `test_admin_heart_tasks.py` | 새 모양 | 3 |
| Modify `frontend/lib/billing/model/heart_task.dart`; Create `heart_task_pending.dart` | `canSubmit` `maxPhotos` `pending` | 4 |
| Modify `frontend/lib/billing/model/heart_task_repository.dart` · `http_heart_task_repository.dart` | `submit(kind, List<File>)` | 4 |
| Modify `frontend/lib/billing/viewmodel/heart_task_submit_view_model.dart` · `heart_task_submit_ui_state.dart` | 사진 목록 · 최대 3 | 4 |
| Modify `frontend/lib/billing/view/heart_task_actions.dart` | 누름 조건을 `canSubmit` 으로 | 4 |
| Modify `frontend/lib/billing/view/heart_task_submit_screen.dart` · `heart_tasks_screen.dart` · `heart_task_row.dart` · `heart_store_screen.dart`; Create `heart_task_pending_list.dart` | 화면(**값표 대기**) | 5 (campus-ui) |
| Modify `admin_web/lib/heart_tasks/heart_task_item.dart` · `heart_task_review_controller.dart` | `photoUrls` · 고른 장 | 6 |
| Modify `admin_web/lib/heart_tasks/proof_photo_viewer.dart` · `heart_task_review_screen.dart` | 큰 보기 + 썸네일 줄(**값표 대기**) | 6 |
| Modify `e2e/area2*.py`(+ 그 단위시험) | `storage_path` → `storage_paths` | 7 |
| 문서(campus-docs 몫): `docs/ERD.md`(:583-590 · :636 · :726), `backend/DEPLOY.md` §4-5, `frontend/docs/DESIGN.md` §8.10 | 이 계획에서 고치지 않음 | — |

의존: Task 1 → 2 → 4 → 5, Task 1 → 3 → 6, Task 7 은 1 뒤 아무 때나. Task 2 · 3 은 `HeartProofStorage` 를 같이 쓰지만 Task 2 만 고치고 Task 3 은 읽기만 하므로 병렬 가능.

---

### Task 1: DB — `storage_paths`, 인덱스 삭제, 잠금 있는 제출 함수

**Files:**
- Create: `supabase/migrations/20261019100000_heart_task_multi_photos.sql`
- Modify (시험): `supabase/tests/heart_tasks_test.sql`, `rls_slice0_test.sql`, `admin_heart_task_review_test.sql`, `admin_stats_matching_test.sql`

**Interfaces:**
- Produces: 표 칸 `public.heart_task_submissions.storage_paths text[] not null default '{}'` (옛 `storage_path` 없음). 함수 `public.submit_heart_task(p_id uuid, p_profile uuid, p_task public.heart_task, p_paths text[], p_reward integer, p_now timestamptz default now()) returns void` (service_role 만 실행). 오류 코드: `p_paths` 가 null · 빈 배열 · 4개 이상이면 `22023`, 한도에 찼고 검수 중이 있으면 `CM409`, 찼고 검수 중이 없으면 `CM429`. `heart_task_status` · `heart_task_monthly_limit` · 승인 트리거 · `admin_review_heart_task` 는 **그대로**.
- Consumes: 없음.

**마이그레이션 뼈대 (시간순, 구현자가 본문을 쓴다):**
1. `alter table public.heart_task_submissions add column storage_paths text[] not null default '{}'`.
2. 백필 `update ... set storage_paths = array[storage_path] where storage_path is not null` — 이때 옛 guard 트리거는 `storage_paths` 를 보지 않아 통과한다. **guard 교체보다 먼저** 한다.
3. `drop constraint heart_task_submissions_proof_while_reviewing` → `drop column storage_path` → check 둘: `heart_task_submissions_paths_max (cardinality(storage_paths) <= 3)`, `heart_task_submissions_proof_while_reviewing (status <> 'submitted' or cardinality(storage_paths) between 1 and 3)`.
4. `drop index public.heart_task_submissions_one_reviewing`.
5. `create or replace function public.heart_task_submissions_guard()`: 옛 본문에서 `storage_path` → `storage_paths` 로만 바꾼다. 검수 뒤 허용 변경은 "`storage_paths` 를 `'{}'` 로 비우기" 하나뿐(`new.storage_paths is distinct from old.storage_paths and new.storage_paths <> '{}'` 이면 CM409).
6. `drop function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)` 후 새 시그니처로 `create`: ① `p_paths` null 이거나 `cardinality` 가 1..3 이 아니면 22023 ② `perform pg_advisory_xact_lock(hashtextextended('heart_task:' || p_profile::text || ':' || p_task::text, 0))` ③ `heart_task_status(p_profile, p_now)` 로 `used · task_limit · reviewing` ④ `if v_used >= v_limit then raise exception ... using errcode = case when v_reviewing then 'CM409' else 'CM429' end` ⑤ insert(`storage_paths = p_paths`, `created_at = p_now`). `security invoker`, `set search_path = ''`.
7. `revoke execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text[], integer, timestamptz) from public, anon, authenticated; grant execute ... to service_role;`
8. `comment on column ...storage_paths` 한 줄, 파일 머리 주석에 "단톡방은 검수 중에도 한도 안에서 이어서 낼 수 있다 — 동시 요청은 사람·항목 락이 막는다"와 `-- shortcut: 사진별 해시가 필요해지면 새 표로` 를 한국어로.

- [ ] **Step 1: 시험을 먼저 바꾼다 (RED).** `heart_tasks_test.sql` 에서 `storage_path`/`submit_heart_task(... 'x/y.jpg' ...)` 를 `storage_paths = array['x/y.jpg']` / `array['x/y.jpg']::text[]` 로 기계적으로 바꾸고 아래 새 단언을 더한다(`select plan(N)` 은 단언 수에 맞게). 옛 줄 80 의 `23505` 단언("한 항목에 검수 중인 줄은 하나뿐")은 아래 `kakao can queue` 단언으로 **대체**한다. `rls_slice0_test.sql`(3곳) · `admin_heart_task_review_test.sql`(1) · `admin_stats_matching_test.sql`(2)는 입력만 바꾼다.
  - `table has storage_paths and no legacy storage_path`: `has_column('public','heart_task_submissions','storage_paths')` · `hasnt_column(..., 'storage_path')`.
  - `one-reviewing index is gone`: `hasnt_index('public','heart_task_submissions','heart_task_submissions_one_reviewing')`.
  - `kakao can queue while reviewing`: 사람 K 가 단톡방 2건을 연달아 제출 → 둘째 `lives_ok`; `heart_task_status` 가 `used=2, reviewing=true`.
  - `kakao at 3 with a pending is CM409 and with three approved is CM429`: 승인 1 + 검수 2 에서 네 번째 → `throws_ok(..., 'CM409')`; 전부 승인 3 에서 → `'CM429'`.
  - `everytime second while reviewing is still CM409` (기존 단언이 그대로 통과하는지).
  - `rejecting a pending gives the slot back`: 3/3(검수 중 포함)에서 하나를 반려 → `used=2`, 다음 제출 `lives_ok`.
  - `paths must be one to three`: `submit_heart_task(..., array[]::text[], ...)` · 4개 · `null` 각각 `throws_ok(..., '22023')`; 직접 `insert` 로 `status='submitted'` + `'{}'` 또는 4개 → `throws_ok(..., '23514')`.
  - `three paths are stored in order`: 제출 뒤 `select storage_paths` = `array['k/a-1.jpg','k/a-2.jpg','k/a-3.jpg']`.
  - `guard keeps paths fixed while reviewing and after review only allows clearing`: 검수 중 `update set storage_paths = array['x']` → `CM409`; 검수 뒤 다른 비어 있지 않은 값 · 일부만 남기기 → `CM409`; `'{}'` → `lives_ok`.
  - `submit takes a per-person-per-task advisory lock`: 제출 호출 뒤, **같은 트랜잭션에 다른 호출이 락을 여럿 남기므로 "개수 1" 이 아니라 그 키로** 확인한다. 키 `k = hashtextextended('heart_task:<P>:kakao_share', 0)` 의 상위 32비트 `(k >> 32) & 4294967295` 가 `pg_locks.classid`, 하위 32비트 `k & 4294967295` 가 `objid` 인 advisory 락이 `pid = pg_backend_pid()` 로 `granted` → `ok(exists(...))`. 반대로 제출한 적 없는 (사람, 항목) 키는 `ok(not exists(...))`.
  - `submit function is service_role only`: `function_privs_are('public','submit_heart_task', array['uuid','uuid','heart_task','text[]','integer','timestamp with time zone'], 'authenticated', array[]::text[])` (anon 도 같게), `service_role` 은 `EXECUTE`; `hasnt_function('public','submit_heart_task', array['uuid','uuid','heart_task','text','integer','timestamp with time zone'])`.
  - `other person cannot read the paths`: 기존 RLS 단언이 새 칸에도 0행으로 통과.
- [ ] **Step 2: RED 확인 — 대장이 준 DB 차례에만.** Run: 워크트리 루트 `supabase test db`. Expected: `storage_paths` 없음으로 실패. *이 계획서를 쓰는 동안은 돌리지 않았다.*
- [ ] **Step 3: 마이그레이션 작성** (위 뼈대 1~8).
- [ ] **Step 4: GREEN.** Run: `supabase test db`. Expected: 전부 통과(기존 + 이번 추가분), 실패 0. docker 비정상 컨테이너를 한 줄로 보고.
- [ ] **Step 5: 백필 리허설 (수동, DB 차례).** 새 마이그레이션 **전까지만** 적용한 로컬 DB 에 옛 줄 둘 — (검수 중, `storage_path='p/a.jpg'`) · (승인, `storage_path=null`) — 을 넣고 새 마이그레이션을 적용한다. Expected: 앞줄 `storage_paths = {p/a.jpg}`, 뒷줄 `{}`, check 위반 없이 끝남. 운영 적용 전 **읽기 전용** 점검(대장/campus-supabase): `select status, count(*), count(storage_path) from heart_task_submissions group by 1` — `submitted` 줄은 모두 경로가 있어야 한다(옛 check 가 보장).
- [ ] **Step 6: 동시 두 세션 확인 (수동, DB 차례).** 사람 P 의 단톡방을 승인 1 + 검수 중 1(=2/3)로 준비. 세션 A: `begin; select public.submit_heart_task(<id1>,<P>,'kakao_share',array['a'],25);`(커밋 보류). 세션 B: 같은 사람 · 같은 항목으로 `submit_heart_task(<id2>,...)` → B 가 **멈춘다**. A `commit` → B 가 `CM409`(3/3 + 검수 중)로 끝나고 P 의 단톡방 줄은 3개. Expected: `count(*) = 3` (4 아님). 같은 시각 `everytime_post` 제출은 A 가 락을 쥐고 있는 동안에도 막히지 않는다.
- [ ] **Step 7: 커밋 제안**(campus-git): `🗃️ feat(db): 인증샷 경로를 배열로 바꾸고 단톡방은 검수 중에도 이어서 제출`.

---

### Task 2: 서버 — 제출 · 목록 · 정리

**Files:**
- Modify: `backend/app/heart_tasks/router.py`, `repository.py`, `storage.py`, `cleanup.py`
- Test: `backend/tests/heart_tasks/test_heart_tasks.py`, `test_proof_cleanup.py` (`backend/tests/account/account_world.py:251` 은 빈 응답이라 변경 없음 — 확인만)

**Interfaces:**
- Consumes: Task 1 의 `submit_heart_task(p_id, p_profile, p_task, p_paths, p_reward)`, 표 칸 `storage_paths`.
- Produces: D4 의 응답 필드 표. 상수 `MAX_PHOTOS = 3`, `PENDING_URL_TTL_SECONDS = 600`. `HeartTaskRepository.submit(self, submission_id: UUID, profile_id: UUID, task: str, paths: list[str], reward: int) -> None` · `HeartTaskRepository.fetch_pending(self, profile_id: UUID) -> list[dict]`(각 `{"id","task","created_at","storage_paths"}`, `status=eq.submitted`, `created_at.asc`) · `HeartProofStorage.upload(self, profile_id: UUID, submission_id: UUID, index: int, data: bytes, content_type: str) -> str`(경로 `{profile}/{submission}-{index}.{ext}`, index 는 1부터) · `fetch_expired_proofs` 는 `{"id","storage_paths"}` 를 돌려준다.

- [ ] **Step 1: 시험 (RED).** `test_heart_tasks.py` 의 `_wire`/`_backend` 가짜를 쓰되 분기는 `request.url.params` 키로 가르고(`reference_backend_test_mock_traps ①`), `get_settings` 오버라이드는 람다(②). `_backend` 에 `GET .../heart_task_submissions`(pending)와 서명 분기를 더한다. `_post` 도우미는 `files` 목록을 받게 넓힌다.
  - `test_submit_three_photos_uploads_each_and_records_one_row`: 파트 `photos`×3 → 201, 업로드 3번(경로 `-1` `-2` `-3`), RPC 본문 `p_paths == [그 세 경로]` 이고 `"p_path" not in body`, 디스코드 알림 1번에 `.jpg` · 버킷 이름 없음.
  - `test_legacy_photo_field_still_works`: 파트 `photo` 한 장 → 201, `p_paths` 길이 1, 응답에 옛 여섯 칸 전부 존재.
  - `test_zero_photos_or_four_photos_is_422_and_touches_nothing`: 0장, 4장 → 422, `seen == []`.
  - `test_one_bad_photo_among_three_is_400_and_uploads_nothing`: 둘째가 GIF → 400 `PHOTO_UNREADABLE`, `_storage_calls(seen) == []`.
  - `test_each_photo_is_read_at_most_one_byte_past_the_limit`(`upload_read_sizes`): 셋째가 한도 초과 → 400, `upload_read_sizes` 의 모든 값이 `MAX_IMAGE_BYTES + 1`(`-1` 없음).
  - `test_kakao_submit_is_allowed_while_one_is_reviewing`: 상태 `kakao_share={"reviewing": True, "used": 1}` → 201(사전 409 없음).
  - `test_submit_at_limit_with_pending_is_409_and_without_pending_is_429`: `{"reviewing": True, "used": 3}` → 409, `{"used": 3}` → 429, 둘 다 업로드 0번.
  - `test_second_upload_failing_removes_every_attempted_path`: 둘째 업로드 500 → 5xx, DELETE 본문 `prefixes` 가 시도한 세 경로 전부, RPC 는 부르지 않음.
  - `test_db_says_no_after_upload_removes_all_three_files`(parametrize CM409/CM429; 옛 `23505` 행은 삭제): DELETE 본문 == 올린 세 경로.
  - `test_no_answer_from_db_keeps_all_files`: `ReadTimeout` → storage 호출이 POST 3개뿐(DELETE 없음).
  - `test_list_has_old_six_keys_plus_can_submit_max_photos_pending`: 키 집합 `TASK_KEYS | {"can_submit","max_photos","pending"}`, 줄 순서 고정 유지, `poll_vote` 는 `can_submit False · max_photos 0 · pending []`.
  - `test_state_stays_reviewing_while_a_pending_exists_even_if_can_submit`: 단톡방 `reviewing, used 1` → `state == "reviewing"` 이고 `can_submit is True`.
  - `test_pending_lists_signed_urls_in_photo_order_and_null_for_a_failed_sign`: 대기 1줄(사진 3, 둘째 서명 500) → `photo_urls == [url1, None, url3]`; 응답 어디에도 `storage_paths` 키나 버킷 경로 원문이 없다.
- [ ] **Step 2: RED 확인.** Run: `cd backend && C:/Users/user/AndroidStudioProjects/campus_mate_compose/backend/.venv/Scripts/python.exe -m pytest tests/heart_tasks -q` (먼저 `-c "import app; print(app.__file__)"` 로 읽는 트리가 워크트리인지 확인). Expected: 새 시험 FAIL(키 없음 · `photos` 무시).
- [ ] **Step 3: 구현 시그니처.**
  - `router.py`: `async def submit_heart_task(task: Literal["everytime_post","kakao_share"], photo: UploadFile | None = File(None), photos: list[UploadFile] = File(default=[]), caller: Caller = Depends(get_verified_caller)) -> dict`; 비공개 도우미 `_read_proofs(uploads: list[UploadFile]) -> list[tuple[bytes, str]]`(장수 1..3 아니면 422 `INVALID_INPUT`, 장마다 `read(MAX+1)` → 판정, 위반 400 `PHOTO_UNREADABLE`), `_upload_all(storage, profile_id, submission_id, proofs) -> list[str]`(gather + 실패 시 시도 경로 전부 삭제), `_pending_view(storage, rows) -> list[dict]`. 사전 판정은 `if used >= limit: 409 if reviewing else 429` — 옛 `if reviewing: 409` 는 **지운다**. `_task(name, row, pending=())` 가 새 세 칸을 더한다. `GET` 은 `fetch_status` 와 `fetch_pending` 을 `asyncio.gather` 로 함께 부른다.
  - `repository.py`: `submit` 은 `p_paths` 를 보내고 `23505` 매핑을 지운다(인덱스가 없다). `fetch_expired_proofs`: `select=id,storage_paths`, `storage_paths=not.eq.{}`. `clear_proof_paths`: `{"storage_paths": []}`.
  - `cleanup.py`: `paths = [p for row in rows for p in row["storage_paths"]]` 를 지운다(100줄 × 3장 = 300경로는 DELETE **본문**이라 주소 길이 걱정 없음; 경로 비우기 PATCH 는 여전히 id 100개).
- [ ] **Step 4: 정리 시험 (RED→GREEN).** `test_proof_cleanup.py`: `ROWS` 를 `storage_paths` 배열로 바꾸고
  - `test_deletes_every_file_of_each_row_then_clears_the_paths`: 줄 둘(사진 3장 · 1장) → DELETE `prefixes` 가 4개 전부, PATCH 본문 `{"storage_paths": []}`, 요청 순서 `GET → DELETE → PATCH`.
  - `test_asks_only_for_rows_that_still_have_files`: GET 파라미터 `storage_paths == "not.eq.{}"` · `select == "id,storage_paths"` · `reviewed_at == lt.<60일 전>` · `(order, limit) == ("reviewed_at", "100")`.
  - 기존 `test_file_delete_failure_keeps_paths_for_tomorrow` · `test_nothing_expired_touches_nothing_else` 는 새 칸에 맞춰 유지.
- [ ] **Step 5: GREEN + 전체.** Run: `... -m pytest tests/heart_tasks -q` 그리고 `... -m pytest -q`. Expected: 통과, 실패 0(전체 수치 보고).
- [ ] **Step 6: 커밋 제안**: `✨ feat(heart-tasks): 인증샷 1~3장을 한 요청으로 받고 단톡방은 검수 중에도 이어서 제출` · `✨ feat(heart-tasks): 18a 응답에 can_submit · max_photos · 검수 대기 목록` · `♻️ refactor(heart-tasks): 60일 정리가 줄마다 여러 장을 지운다`.

---

### Task 3: 서버 — 관리자 검수 읽기 (여러 장)

**Files:**
- Modify: `backend/app/admin/repository.py:24,82-92`, `backend/app/admin/heart_task_review.py:45-79`
- Test: `backend/tests/admin/admin_world.py:55`, `backend/tests/admin/test_admin_heart_tasks.py`

**Interfaces:**
- Consumes: Task 1 `storage_paths`; `HeartProofStorage.create_signed_url(path, expires_in)`(변경 없음).
- Produces (관리자 웹이 읽는 모양): 한 건 · 승인 · 반려 응답에 `photo_urls: list[str|None]`(순서대로, 서명 실패 장은 null, 정리로 비면 `[]`)와 옛 `photo_url`(= `photo_urls` 첫 장, 없으면 null). `previous[]` 의 각 항목도 `photo_urls` + 옛 `photo_url`. `storage_paths` 원문은 응답에 싣지 않는다. 목록(`GET /heart-tasks`)은 그대로(사진 없음). 비공개 도우미 `async def _photo_urls(storage: HeartProofStorage, row: dict) -> list[str | None]`. 한 건 응답은 본 건 + 지난 5건의 모든 장을 **한 번의 `asyncio.gather`** 로 서명한다(최대 3 + 15 = 18번, 개별 실패는 `None`).

- [ ] **Step 1: 시험 (RED).**
  - `test_one_submission_returns_photo_urls_in_order_and_the_legacy_photo_url`: `admin_world` 줄에 `storage_paths` 3개 → `photo_urls` 길이 3 · 순서 유지 · `photo_url == photo_urls[0]` · 서명 `expiresIn == 300` · 응답에 `storage_path` 문자열이 없다.
  - `test_one_unsignable_photo_among_three_is_null_and_the_rest_stay`: 둘째 서명 500 → `[url1, None, url3]`, 응답 200.
  - `test_purged_row_has_empty_photo_urls_and_null_photo_url`: `storage_paths == []` → `photo_urls == []`, `photo_url is None`.
  - `test_previous_submissions_are_read_with_storage_paths_and_carry_photo_urls`: 지난 제출 조회 파라미터 `select == "id,status,created_at,storage_paths"` · `storage_paths == "not.eq.{}"`, 각 항목에 `photo_urls`.
  - 기존 `test_missing_or_unsignable_photo_is_null` · `test_a_sign_answer_without_a_url_is_a_missing_photo_not_a_500` 는 새 모양에 맞춰 같은 의도로 유지.
- [ ] **Step 2: RED**: `... -m pytest tests/admin/test_admin_heart_tasks.py -q` → 새 시험 FAIL.
- [ ] **Step 3: 구현.** `_SUBMISSION_SELECT` 의 `storage_path` → `storage_paths`; `_item` 이 줄마다 `_photo_urls`; 옛 `_photo_url` 삭제(쓰는 곳이 이 파일뿐인지 Grep 으로 확인).
- [ ] **Step 4: GREEN + 전체 pytest.** Expected: 통과.
- [ ] **Step 5: 커밋 제안**: `✨ feat(admin): 인증샷 검수 응답에 사진 여러 장(photo_urls)`.

---

### Task 4: 앱 로직 — 모델 · 저장소 · 뷰모델

**Files:**
- Modify: `frontend/lib/billing/model/heart_task.dart`, `heart_task_repository.dart`, `http_heart_task_repository.dart`; `viewmodel/heart_task_submit_view_model.dart`, `heart_task_submit_ui_state.dart`; `view/heart_task_actions.dart`
- Create: `frontend/lib/billing/model/heart_task_pending.dart`
- Test: `frontend/test/billing/model/heart_task_test.dart`, `http_heart_task_repository_test.dart`, `fake_heart_task_repository.dart`; `viewmodel/heart_task_view_models_test.dart`; `view/heart_tasks_screen_test.dart`(누름 조건만)

**Interfaces:**
- Consumes: Task 2 의 D4 응답 필드.
- Produces:
  - `class HeartTaskPending { const HeartTaskPending({required this.id, required this.createdAt, required this.photoUrls}); final String id; final DateTime createdAt; final List<String?> photoUrls; factory HeartTaskPending.fromJson(Map<String, dynamic> json) }`
  - `HeartTask` 에 `final bool canSubmit; final int maxPhotos; final List<HeartTaskPending> pending;` 추가. **옛 서버 응답(새 칸 없음)이면** `canSubmit = kind.needsProof && (state == open || state == rejected)`, `maxPhotos = kind.needsProof ? 1 : 0`, `pending = const []` 로 읽는다(새 앱이 옛 서버를 읽어도 죽지 않고, 이때 최대 1장).
  - `Future<Result<HeartTask>> submit(HeartTaskKind kind, List<File> photos)` (옛 `File photo` 시그니처 교체).
  - `HeartTaskSubmitUiState({List<File> photos = const [], bool isSubmitting = false, String? errorMessage, bool submitted = false})`, `bool get canSubmit => photos.isNotEmpty && !isSubmitting && !submitted`, `static const int maxPhotos = 3`.
  - `HeartTaskSubmitViewModel`: 훅 `Future<List<File>> Function(int remaining) pickFromGallery`(기본은 `ImagePicker().pickMultiImage(limit: remaining)` — **`limit` 지원은 구현 때 확인, 안 지키면 앞 `remaining` 장만 취한다**), `Future<void> addPhotos()`, `void removePhoto(int index)`, `Future<void> submit(HeartTaskKind kind)`.
  - `heartTaskOnTap(context, task)`: 인증 항목은 `task.canSubmit` 이면 누르면 18b(`state == rejected` 이면 사유 실어 18b-2), 아니면 null. 투표 줄은 그대로.

- [ ] **Step 1: 시험 (RED).**
  - `heart_task_test.dart` `parses pending with signed urls and nulls`: JSON `pending:[{id,created_at,photo_urls:["u1",null,"u3"]}]` → `pending.single.photoUrls == ['u1', null, 'u3']`, `canSubmit true`, `maxPhotos 3`.
  - `heart_task_test.dart` `old server response without new keys still parses`: 새 칸 없는 JSON(`state:'open'`) → `canSubmit true`, `maxPhotos 1`, `pending` 비어 있음; `state:'reviewing'` → `canSubmit false`.
  - `http_heart_task_repository_test.dart` `submit sends every photo under the photos field`: 사진 3개 → multipart 파일 3개 모두 이름 `photos`, 경로 `/heart-tasks/kakao_share/submissions`, 이름 `photo` 는 없다.
  - `heart_task_view_models_test.dart` `addPhotos keeps at most three and keeps order`: 1장 있을 때 훅이 `remaining == 2` 로 불리고 3장 유지; 이미 3장이면 훅을 부르지 않는다.
  - `removePhoto drops that photo and canSubmit is false with none`.
  - `submit compresses every photo, sends them all, and discards every compressed copy`: `FakeImageCompressor` 가 3번 압축 · 3번 discard, 저장소가 받은 `List<File>` 길이 3.
  - `a compression failure on any photo sends nothing and shows the unreadable message`.
  - `a 429 shows the monthly limit message and a 409 shows the in-review message, photos are kept`(기존 매핑 확인).
  - `heart_tasks_screen_test.dart` `kakao row with pending and canSubmit is tappable; at the limit it is not`.
- [ ] **Step 2: RED**: `cd frontend && flutter test test/billing -r expanded` → FAIL(컴파일 오류 포함).
- [ ] **Step 3: 구현.** `HttpHeartTaskRepository.submit` 은 `savePhotos`(`http_me_repository.dart:113`)처럼 `_api.sendRequest` 로 `MultipartRequest('POST', _api.uri(...))` 를 만들고 `photos` 파트를 반복해 붙인다(`sendMultipart` 는 건드리지 않는다 — 프로필 사진이 쓴다).
- [ ] **Step 4: GREEN + 정적 분석**: `flutter test test/billing`, `flutter analyze` → 통과 · 이슈 0. 전체 `flutter test` 는 대장 차례에만.
- [ ] **Step 5: 커밋 제안**: `✨ feat(billing): 인증샷 여러 장 모델 · 저장소 · 뷰모델`.

---

### Task 5: 앱 화면 (campus-ui 몫, **pen 값표 대기**)

**상태: pen 값 필요.** 시안은 campus-pen 이 `CampusMate_문서\디자인_pen\인증샷_여러장\` 에 만드는 중. 노드 id · 값표를 받기 전에는 아래 "값 필요"를 추측하지 않는다.

**Files:**
- Modify: `heart_task_submit_screen.dart`(업로더 → 최대 3칸), `heart_tasks_screen.dart`(줄 아래 대기 목록), `heart_task_row.dart`(검수중 칩 · 하단 구분선 · 단톡방 활성 조건), `heart_store_screen.dart`(같은 줄을 쓰므로 영향 확인)
- Create: `frontend/lib/billing/view/heart_task_pending_list.dart`
- Test: `test/billing/view/heart_task_submit_screen_test.dart`, `heart_tasks_screen_test.dart`, `heart_store_screen_test.dart`, 새 `heart_task_pending_list_test.dart`

**Interfaces:**
- Consumes: Task 4 의 `HeartTask.pending/canSubmit/maxPhotos`, `HeartTaskSubmitViewModel.addPhotos/removePhoto`, `HeartTaskSubmitUiState.photos`.
- Produces: 위젯 `HeartTaskPendingList({required List<HeartTaskPending> pending, super.key})` — 줄마다 제출 시각 · 썸네일 최대 3 · "검수 중" 배지.

**pen 값 필요 (노드/요소 — 받을 때까지 비워 둠):** 18b 업로더 칸 3개의 크기 · 간격 · 채운 칸/빈 칸/삭제(×) 모양 · "n/3" 글자 여부 / 18a 대기 줄의 높이 · 썸네일 크기 · 모서리 · 시각 글자 형식 · "검수 중" 배지 색(기존 `surfaceStrong`/`muted` 칩 재사용 여부) / 한도 찬 상태의 비활성 [제출하기]와 안내 문구 / 대기 줄이 없을 때 / 썸네일 로딩 · null(서명 실패) 모양 / 단톡방 줄에서 [제출하기]가 놓이는 곳(줄의 칩인지 대기 목록 아래 버튼인지). 모든 색 · 글자 · 간격은 토큰만(`AppColors/AppSpacing/AppTypography/AppRadius`), 아이콘은 `AppIcons`. 눌리는 칸마다 잉크는 자기 `Material(type: transparency)` 에 그린다(COMMON §4-2).

- [ ] **Step 1: 시험 이름(값표 도착 뒤 확정):** `submit screen shows three slots and a remove control per photo` · `add control disappears at three` · `submit button is enabled with one photo` · `pending list shows one row per pending with its photos and a reviewing badge` · `kakao row stays tappable while pending exists and shows full guidance at the limit` · `ink of every tappable box is painted by its own Material` · `store screen free-tasks section shows the same pending rows`.
- [ ] **Step 2~4:** RED → 구현 → GREEN(`flutter test test/billing`, `flutter analyze`).
- [ ] **Step 5: 보고에 쓸 목록:** 공용 위젯은 안 고치지만 `HeartTaskRow` 는 18a 와 하트 스토어(18) 둘이 쓴다 — 바꾸면 두 화면을 같이 보고한다.
- [ ] **Step 6: 커밋 제안**: `✨ feat(billing): 18b 사진 최대 3칸과 18a 검수 대기 목록`.

---

### Task 6: 관리자 웹 — 사진 여러 장 보기

**Files:**
- Modify: `admin_web/lib/heart_tasks/heart_task_item.dart`(모델), `heart_task_review_controller.dart`(고른 장), `proof_photo_viewer.dart` · `heart_task_review_screen.dart`(화면, **값표 대기**)
- Test: `admin_web/test/heart_tasks/heart_task_item_test.dart`, `heart_task_review_controller_test.dart`, `heart_task_review_screen_test.dart`; `admin_web/test/helpers/heart_task_fakes.dart`

**Interfaces:**
- Consumes: Task 3 의 `photo_urls` · 옛 `photo_url`.
- Produces: `HeartTaskDetail.photoUrls: List<String?>`(옛 `photoUrl` getter 는 `photoUrls.firstOrNull` 로 유지해 호출부가 한 번에 안 깨지게), `HeartTaskPrevious.photoUrls`. 파서는 `photo_urls` 가 있으면 그것을, 없으면(옛 서버) `photo_url` 하나짜리 목록을 쓴다 → 관리자 웹이 서버보다 먼저 나가도 죽지 않는다. 컨트롤러 상태에 `selectedPhotoIndex`(기본 0, 다른 건을 고르면 0), `void selectPhoto(int index)`. 크게 보기 인자는 `(제출 번호, 장 번호)` 로 넓힌다(`showProofZoom(... photoId:` → 제출 번호 + `photoIndex`).

- [ ] **Step 1: 시험 (RED).**
  - `HeartTaskDetail parses photo_urls in order and keeps nulls`; `falls back to a one-item list from the legacy photo_url`; `photo_url null and photo_urls absent gives an empty list`.
  - controller: `selecting another submission resets the selected photo to the first`; `selectPhoto ignores an index out of range`; `photoFailed still refetches only that submission once`(기존 동작 유지).
  - screen: `with three photos the big view shows the selected one and a thumbnail strip of three; tapping a thumbnail changes the big view; with one photo no strip is shown`(**strip 치수 · 위치는 pen 값 필요**); `zoom opens the selected photo of the selected submission`.
- [ ] **Step 2~4:** RED(`cd admin_web && flutter test test/heart_tasks`) → 구현 → GREEN + `flutter analyze`. 전체 `flutter test` 는 대장 차례.
- [ ] **Step 5: pen 값 필요:** 큰 보기 아래 현재 건 썸네일 줄 vs 기존 "지난 제출" 썸네일 줄의 위치 · 구분, 선택 장 표시(테두리 색), 장 번호 표시("1/3"), 크게 보기에서 이전/다음 이동 유무. 지난 제출은 항목마다 여러 장이므로 줄에 첫 장만 + "n장"인지 전부인지도 pen 에서 정한다 — 서버는 둘 다 줄 수 있다.
- [ ] **Step 6: 커밋 제안**: `✨ feat(admin-web): 인증샷 여러 장 보기(큰 사진 + 썸네일 줄)`.

---

### Task 7: E2E 하네스 맞춤 (작음)

**Files:** `e2e/area2.py:711-721`, `area2_phone_b.py:265-272,352`, `area2_time_api.py:501`, `area2_time_batch.py:512`, `test_area2*.py`(그 가짜 응답)

- [ ] **Step 1:** 직접 `insert` 하는 `storage_path` 를 `storage_paths: [path]` 로, 읽는 `select=storage_path` 를 `storage_paths` 로(비교는 `row['storage_paths'] == [path]` / 정리 뒤 `== []`).
- [ ] **Step 2:** 그 폴더의 단위시험(`test_area2*.py`)을 평소 방식으로 돌려 통과 확인. 에뮬 · 운영 시나리오는 돌리지 않는다.
- [ ] **Step 3: 커밋 제안**: `🧪 test(e2e): 인증샷 경로 칸 이름을 storage_paths 로`.

---

## 검증 (끝내기 전, 대장 차례에 맞춰)

1. backend: `C:/Users/user/AndroidStudioProjects/campus_mate_compose/backend/.venv/Scripts/python.exe -m pytest -q` — exit 0, 수치 보고.
2. `cd frontend && flutter analyze` / `flutter test` — exit 0.
3. `cd admin_web && flutter analyze` / `flutter test` — exit 0.
4. DB 를 건드렸으므로 `supabase test db`(DB 차례에만) — 실패 0, 비정상 컨테이너 한 줄.
5. 공용 위젯은 고치지 않았음을 `git diff --stat` 으로 확인, `HeartTaskRow` 를 쓰는 화면(18a · 18) 목록을 보고에 적는다.

## 배포 순서 (사용자 승인 뒤 — 이 계획은 적용하지 않는다)

1. 마이그레이션 `20261019100000` 적용(campus-supabase, 사용자 원문 승인 필요) → `NOTIFY pgrst, 'reload schema';`
2. **곧바로** 서버 배포(D5: 그 사이 몇 분은 제출 · 관리자 사진 오류). **서버만 이전 리비전으로 되돌리면 깨진다 — 되돌림은 고친 새 리비전으로 한다.** 04:00 KST 정리 시각 피하기. 배포 뒤 `GET /heart-tasks` 읽기 점검(새 칸 존재), 관리자 상세 사진 확인.
3. 관리자 웹은 main 머지로 Vercel 자동 배포 — 파서가 `photo_urls` 없는 옛 서버도 읽으므로 서버보다 먼저 나가도 죽지 않는다(사진은 첫 장만).
4. 앱(AAB · TestFlight)은 서버 배포 뒤. 새 앱도 옛 서버 응답을 읽도록 Task 4 가 막아 두지만 3장 제출은 새 서버에서만 된다(옛 서버는 `photos` 를 모르고 `photo` 필수라 422).
5. 문서(campus-docs): ERD · DEPLOY(§4-5 적용 순서 · 롤백) · DESIGN §8.10.

## 대장 결정 필요 (추측 금지 — 선택지와 추천)

**확정(2026-10-19 대장):** 1 (가) 받아들임 · 2 `storage_paths text[]` · 3 `state` 그대로(검수 중이 있으면 `reviewing`) · 4 제출 성공 뒤 18c 유지(pen 이 18a 복귀를 그리지 않음) · 5 새 앱이 옛 서버를 만나면 사진 최대 1장(넣음) · 6 썸네일은 지금 방식 그대로. 아래 본문은 결정 당시의 선택지다.

1. **컬럼 교체의 배포 틈을 받아들일까?** (가) 받아들임 — 옛 `storage_path` 폐기, 마이그레이션 직후 서버 배포, 몇 분 제출 · 관리자 사진 오류. (나) 호환 유지 — 옛 컬럼 · 옛 함수 시그니처를 남기는 2단 마이그레이션(마이그레이션 둘 + 나중 정리). **추천 (가)**: 사용자 19명 · 출시 전, 코드 면이 반으로 준다. 단 서버만 이전 리비전으로 되돌리기는 안 된다.
2. **데이터 모델 `text[]` 로 확정?** (D1). 추천 `text[]`. 사진별 해시로 "이미 쓴 캡처" 자동 판별을 곧 만들 계획이면 새 표.
3. **`state` 를 검수 중이 있으면 계속 `reviewing` 으로 둘까?** (가) 그대로 — 옛 앱은 검수중 줄을 못 누름(지금과 같음), 새 앱은 `can_submit` 사용. (나) 한도가 남으면 `open` — 옛 앱도 이어서 낼 수 있지만 옛 앱에서 검수 중 표시가 사라짐. **추천 (가).**
4. **제출 성공 뒤 어디로?** 지금은 18c("확인하고 있어요")로 바꿔 보낸 뒤 뒤로 가면 18a. 대기 목록을 바로 보여 주려면 18a 로 돌아가는 편이 낫다. **추천: pen 이 18a 복귀를 그리지 않으면 18c 유지**, 그리면 따른다.
5. **새 앱이 옛 서버를 만났을 때 사진 최대 1장으로 줄이는 처리(Task 4)를 넣을까?** 서버를 먼저 배포하는 원칙이면 필요 없다. **추천: 넣는다**(몇 줄이고 TestFlight 가 서버보다 먼저 나가는 사고를 막음).
6. **썸네일 용량:** 18a 대기 목록이 원본 크기 서명 URL 을 받는다(앱이 ≤1920px 로 압축해 한 장 수백 KB). Supabase 이미지 변환(`?width=`)은 플랜 확인이 필요해 쓰지 않는다. **추천: 지금은 이대로**, 문제 되면 그때.

## 확인 못 한 것

- **pen 값 전부**(Task 5 · 6): 시안 PNG 미도착. 값표 도착 전에는 화면 단계를 시작하지 않는다.
- PostgREST 의 배열 필터 `storage_paths=not.eq.{}` 가 "비지 않은 줄"만 거르는지(정리 배치 · 관리자 지난 제출). 모의 서버로는 못 본다 — Task 2 구현 때 로컬 스택에서 한 번 눌러 본다(DB 차례). 틀리면 표에 `has_proof boolean` 생성 컬럼을 더하는 길이 있다.
- `image_picker ^1.2.3` 의 `pickMultiImage(limit:)` 가 안드로이드 · iOS 에서 한도를 지키는지(Task 4 에서 에뮬 확인 필요).
- 운영 `heart_task_submissions` 의 현재 줄 수 · 상태 분포(운영 읽기 금지라 보지 않음) — 백필 리허설(Task 1 Step 5)의 점검 쿼리는 적용 전에 campus-supabase 가 읽는다.
- 로컬 DB 시험(`supabase test db`)은 이 계획서를 쓰는 동안 돌리지 않았다(다른 창이 쓸 수 있음). pgTAP 기대값은 읽은 SQL 에서 도출했다. 앱 · 서버 시험도 구현 전이라 돌리지 않았다.

## 서버 응답 계약 (확정 — Task 2 · 3 구현 기준, 앱 화면 · 관리자 웹은 이 필드 이름을 쓴다)

`GET /heart-tasks` → `{"tasks": [줄 3개: everytime_post, kakao_share, poll_vote 순]}`. 줄 하나(= `POST /heart-tasks/{task}/submissions` 201 의 `{"task": …}` 도 같은 모양):

```json
{"task": "kakao_share", "reward_hearts": 25, "state": "reviewing", "used": 2, "limit": 3, "reject_reason": null,
 "can_submit": true, "max_photos": 3,
 "pending": [{"id": "<제출 uuid>", "created_at": "2026-10-19T01:00:00+00:00",
              "photo_urls": ["<서명 URL 1>", null, "<서명 URL 3>"]}]}
```

- `pending` 은 오래된 순, `photo_urls` 는 사진 순서(서명 실패한 장은 `null`, 장수 유지). 서명 URL 유효 600초. `poll_vote` 는 `can_submit false · max_photos 0 · pending []`.
- `POST` 요청: multipart 파트 `photos`(1~3장) 또는 옛 `photo`(1장). 오류: 400 사진 형식 · 크기 · 422 0장 · 4장 이상 · 409 한도 + 검수 중 · 429 한도 + 검수 중 없음.

관리자(`/admin/heart-tasks/{id}` 한 건 · 승인 · 반려 응답): 기존 칸 + `"photo_urls": ["<서명 URL>", null, …]`(5분, 정리로 비면 `[]`) + 옛 `"photo_url"`(= 첫 장 또는 null); `previous[]` 항목도 `photo_url` + `photo_urls`. 목록 `GET /admin/heart-tasks` 는 그대로(사진 없음).

## 구현 편차 기록

(구현 중 계획과 달라진 점만 여기에 덧붙인다. 위 본문은 고치지 않는다.)

- **2026-10-19 Task 1 · 2 · 3 · 4 · 7 구현(캠퍼스 코더, 커밋 전).** Task 5 · 6 은 하지 않았다(campus-ui 몫).
- Task 1: pgTAP `plan(56)` → `plan(78)`. 시험 사용자 Q(`…96`)를 추가했다. 옛 `23505` 단언(인덱스)은 "4장은 check 위반 23514" 로 바꿨다. `admin_stats_matching_test.sql` 의 반려 줄은 경로 `null` 대신 `'{}'` 를 넣는다(배열 칸이 not null 이라). 락 시험은 계획의 "개수 1" 이 아니라 **이 키의 락이 있는가**(같은 트랜잭션의 다른 제출도 락을 남기므로)로 했다. 백필 리허설 · 두 세션 동시 제출 · PostgREST 배열 필터는 로컬에서 직접 확인했다(보고서 참고).
- Task 2: `HeartProofStorage.proof_path(...)` 정적 도우미를 추가했다(업로드가 실패해도 지울 경로를 올리기 전에 알기 위해). 저장소 호출 실패(500)는 `main.py` 처리기가 `HTTPStatusError` 를 500 응답으로 바꾸므로 "둘째 업로드 실패" 시험은 예외가 아니라 500 을 단정한다.
- Task 3: 관리자 시험 가짜 `submission(path=…)` 인자를 `paths=[…]` 로 바꿨다.
- Task 4: 계획의 `Future<void> addPhotos()` 는 `addPhotos({int maxPhotos = 3})`(옛 서버 값 1 을 넘기려고), `replacePhoto(int index)` 를 추가했다(계획에 없음 — 임시 단일 칸 화면이 종전처럼 "다시 눌러 바꾸기"를 하려고, 취소하면 사진 유지). `HeartTaskSubmitUiState` 에 `defaultMaxPhotos` · `hasRoomFor(int)` 를 두었다. `HeartTask` 생성자의 새 칸 기본값은 `canSubmit false · maxPhotos 0 · pending []`, 옛 서버 폴백은 `fromJson` 에서만 한다.
- Task 4 (Task 5 경계): 제출 화면(`heart_task_submit_screen.dart`)은 **컴파일 유지용 최소 연결만** 했다 — 한 칸 업로더가 첫 사진을 보이고 다시 누르면 바꾼다. 3칸 화면 · 대기 목록 · 단톡방 줄 모양은 Task 5. `integration_test/area2_b.dart` 도 새 훅 · `photos` 에 맞췄다(실행은 하지 않음).
- Task 4: 공용 시험 보조 `test/auth/model/fake_image_compressor.dart` 에 `failOnCall`(n 번째 압축만 실패)을 더했다.
- Task 7: e2e 는 하네스 4개(`area2.py` `area2_phone_b.py` `area2_time_api.py` `area2_time_batch.py`) + 그 가짜 세계 시험 5개를 맞췄다. 제출 뒤 새 경로 이름은 `{profile}/{id}-1.jpg`. `python -m unittest e2e.test_area2 e2e.test_area2_phone_b e2e.test_area2_time_api e2e.test_area2_time_batch` 339 통과(2 건너뜀). 실행형 시나리오(에뮬 · 운영)는 돌리지 않았다.

- **2026-10-19 머지 · 운영 반영 기록 (문서 정리 라운드, 대장 전달 값).** PR #613 이 main 에 머지됐고(`fc430713` 기준), 마이그레이션 `20261019100000` 이 운영에 적용된 직후 서버 `campus-mate-backend-00087-9qj`(직전 `00086-7zf`)가 나갔다. 계획의 "받아들인 배포 틈"(D5)대로 그 사이에 제출 · 관리자 사진 보기 오류가 있을 수 있었다. **되돌림 하한: 서버를 `00087` 아래로 되돌리면 인증샷 제출 · 관리자 사진 보기가 깨진다 — 되돌림은 고친 서버의 새 리비전으로 한다**(`backend/DEPLOY.md` §4-14). 사용자 확정 결정: 한도 안내에 "승인 n건" 서버 칸 추가는 보류(드문 경우), 하트 스토어(18) 대기 목록 시안은 출시 후. 앱은 안드로이드 vc14(vc13 은 이미 사용됨) · TestFlight 빌드 21 로 나간다. 문서는 `docs/ERD.md` §6 · `frontend/docs/DESIGN.md` §8.10 · §9 18a · 18b · `backend/DEPLOY.md` §4-14 · `docs/decisions/2026-10-19-graduate-verification-decision.md` §7-1 로 옮겼다.
