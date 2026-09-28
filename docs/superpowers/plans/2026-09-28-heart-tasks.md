# 무료로 하트 모으기(18a · 18b · 18c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **상태: v2 (2026-09-28).** 결정 D1~D6 은 통합대장이 확정했다(아래 표). **Part C 는 구현 · 검토 중(DB 차례 3번째),
> Part B · A 는 코드까지 채웠다.** Part A 는 pen 묶음 7 값표(`값표_새기능_A.md`)와 대장 결정 6개로 채웠다 — 편차 8개는
> "화면 대조표" 끝에 있고 대장이 확인했다(09-28, 6번 에브리타임 안내 줄은 (가)로 결정).
>
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다. **Part C 는 통합대장이 "DB 차례"를 준 뒤에만**
> (referral 다음 순서) 마이그레이션 파일을 만들고 `supabase db reset` · `supabase test db` 를 돌린다. 클라우드 적용은
> ERD.pen 그림 → 사용자 검토 → 사용자 승인 뒤 통합대장이 한다.

**Goal:** 설정(16) "무료로 하트 모으기" 행에서 18a 목록으로 들어가, 에브리타임 홍보글 · 학교 단톡방 공유 인증샷을
18b 에서 올리고 18c 에서 검수를 기다린다. 운영자가 승인하면 약속한 하트가 한 번만 들어온다.

**Architecture:** 표 `heart_task_submissions` 하나, enum 셋(`heart_task` · `submission_status` · `heart_task_reject_reason`),
비공개 버킷 `heart-task-proofs` 하나. 제출은 FastAPI 가 사진을 받아 매직바이트를 확인하고 버킷에 올린 뒤 DB 함수
`submit_heart_task` 로 넣는다. 한 항목에 검수 중인 줄은 부분 unique 인덱스로 하나뿐이라 월 한도에 잠금이 필요 없다.
승인은 운영자가 대시보드에서 `status` 를 바꾸면 트리거 두 개가 처리한다 — `guard`(승인 · 반려는 끝 상태, 검수 시각
기록) 와 `grant`(검수 중 → 승인일 때만 기존 `grant_hearts`). 18a 의 상태는 DB 함수 `heart_task_status` 한 곳에서 계산한다.
60일 지난 인증샷은 기존 `/batch/cleanup` 이 지운다. 앱은 `frontend/lib/billing/`(지금 빈 폴더)에 MVVM 으로 둔다.

**Tech Stack:** Postgres 17 (Supabase) + pgTAP · FastAPI + httpx(PostgREST · Storage) · Flutter(Riverpod `Notifier`,
go_router, 이미 있는 `image_picker` · `flutter_image_compress`). **새 의존성 없음.**

**Spec:** `frontend/docs/DESIGN.md` §8.10(무료 획득 섹션 · 상태 4가지 · 항목 표 · `review-submission` · `review-pending`) ·
§9(16 행별 라우팅 · 18a · 18b · 18c) · §13-16(수동 검수 · 영업일 1~2일) · §13-32(구조 확정) · §13-111(아이콘 3D 보류),
`docs/ERD.md` §1(43줄) · §2(85줄 본인 행 읽기) · 271줄(탈퇴 뒤 인증샷 삭제는 FastAPI) · §6(`heart_task_submissions`) ·
§8(`heart_task` · `submission_status` · `heart_reason 'free_task'`) · §9(`heart-task-proofs` 비공개),
통합대장 배정 · 결정 메시지(2026-09-28, pen 보드 "6. 하트·결제" `qm5kq`)

---

## 이미 정해진 것 (문서 근거)

| 무엇 | 값 | 근거 |
| --- | --- | --- |
| 항목 · 주기 · 하트 | 에브리타임 홍보 게시글 **월 1회** 50(초기) / 30(100명 이후) · 학교 카카오톡 단톡방 공유 **월 3회** 25 / 20 | DESIGN §8.10 표 |
| 검수 | 전부 사람이 본다, 영업일 1~2일. 해시 → 비전 모델 자동화는 나중 | DESIGN §13-16 |
| 상태 4가지 | 미완료 "인증하기" · 검수중(`timer`) · 완료(`check`, 버튼 꺼짐) · 반려("다시 제출", error 색) | DESIGN §8.10 |
| 18b 안내 | "스크린샷을 첨부하면 확인 후 하트를 드려요", 에브리타임만 "날짜가 보이게 찍어주세요" 추가, 업로더는 `fit` | DESIGN §8.10 `review-submission` |
| 18c | 마스코트 128 + "확인하고 있어요" + 설명(D2 로 pen 에서 문구 바뀜), 앱바 없음, 나가도 됨 | DESIGN §8.10 `review-pending` · §8.8 |
| 원장 | `heart_reason 'free_task'`, `ref_id` = 제출 id, 기존 `grant_hearts` 로 | ERD §8 · 마이그레이션 `20260920043832` |
| 클라이언트 쓰기 0 | 표 · 버킷 모두 FastAPI(`service_role`)와 운영자만 쓴다. 본인 행 select 만 | ERD §2 · §9 |
| 범위 밖 | 15e 하트 스토어 · 결제 · 10c `x2yPl` 시트의 "무료로 하트 모으기" 버튼(시트 자체가 아직 없음) | 대장 배정 |

## 결정 (통합대장 2026-09-28 — 사용자에게는 대장이 한 줄로 알림)

| # | 무엇 | 결정 | 반영 |
| --- | --- | --- | --- |
| D1 | 승인 방법 | **대시보드에서 `status` 를 바꾸면 트리거가 한 번만 지급.** 제출 때 디스코드(학생증 재검토 채널, 제출 id · profile_id · 항목 코드만) | C2 트리거 · B1 `_notify_review` |
| D1-1 | 검수 뒤 변경 | **승인 · 반려는 끝 상태.** 승인 → 승인 재저장 = 아무 일 없음, 승인 → 반려 = 막힘(회수 없음), 반려 → 승인 = 막힘(지급 0). 운영자 실수는 다시 제출 또는 `admin_adjust`. 검수 끝난 줄에서 바뀔 수 있는 건 `storage_path → null`(60일 정리) 하나 | C2 `heart_task_submissions_guard` · pgTAP |
| D2 | 결과 푸시 | **이번엔 없음.** 18a 상태 · 잔액으로 확인. 18c 문구는 pen 에서 바꿈 | A(18c) |
| D3 | 반려 사유 | **정해진 3개 중 하나를 18b 위 한 줄로**: `date_missing` "날짜가 안 보여요" · `not_verified` "게시글·공유가 확인되지 않아요" · `reused` "이미 쓴 캡처예요". pen 자리는 대장이 그림 | C1 enum · check · B1 응답 · A(18b) |
| D4 | "한 달" | **한국 시간 달력 월**(1일 0시 시작), 검수 중 + 승인을 합쳐 센다. 반려는 빠진다 | C2 `heart_task_status` |
| D5 | 하트 수 | **초기값 50 · 25 를 서버 상수 한 줄**, 제출 때 금액을 행에 적는다 | B1 `REWARD_HEARTS` · C1 `reward_hearts` |
| D6 | 인증샷 보관 | **검수 끝나고 60일 뒤 삭제 + 탈퇴 때 삭제.** 기존 `/batch/cleanup` 에 붙인다(공유 파일, 그때 줄 단위 허락) | B2 · C1 `storage_path` null 허용 |
| — | 표 개수 | **1개**(대장 "표 2개" 는 짐작이었다고 정정) | C1 |

### 기본값 (대장 확인 2026-09-28)

| 무엇 | 기본값 | 이유 |
| --- | --- | --- |
| 업로드 방식 | 앱이 JPEG 로 압축 → FastAPI multipart → 매직바이트 확인 → 서버가 버킷에 올림 | 학생증 · 사진이 이미 이렇다. ERD §9 "서명 업로드 URL" 문구는 문서 정리 때 고친다 |
| 버킷 제한 | 비공개 · 10MB · `image/jpeg` `image/png` | `student-id-temp` · `profile-photos` 와 같다 |
| 파일 경로 | `{profile_id}/{submission_id}.jpg`(png 면 `.png`) | 탈퇴 정리가 `{profile_id}/` 폴더째 지운다 |
| 크기 · 형식 오류 | 둘 다 400 `PHOTO_UNREADABLE`("사진을 다시 확인해 주세요") | `student_id_content_type` 이 10MB 초과도 None 으로 준다 — 학생증 · 사진과 같은 문구 |
| 디스코드 | 학생증 재검토 채널(`discord_webhook_url`), 번호만, 실패해도 제출은 201 | 제출은 이미 끝났다. 운영자는 대시보드 목록으로도 본다 |
| 호출자 | `get_verified_caller`(학생증 인증 + 학과 입력 완료) | 커뮤니티와 같다 |
| 18a 투표 줄 | 둔다. 이번 주 `poll_vote` 적립 횟수 / 3, 3이면 "완료"(이번 주 적립 완료). 누르면 커뮤니티 탭 | DESIGN §8.10 표 3줄 |
| 새 의존성 | 없음 | — |

### 이번에 하지 않는 것

- 하트 스토어(15e) · 결제 · 18d 구매 확인 · `x2yPl` 시트 버튼, 결과 푸시(D2)
- 사진 해시 · 비전 모델 자동 판정(DESIGN §13-16 "향후"), 관리자 페이지
- 노션(통합대장), 문서 정리(조각 끝에 사용자에게 물은 뒤 — 아래 "문서 갱신 대상")

---

## Global Constraints

1. **클라이언트 쓰기 0.** `heart_task_submissions` 는 `authenticated` 에 본인 행 `select` 만, 버킷에는 Storage 정책 없음.
2. **테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤 필요한 것만 준다**(ERD §2). DB 함수는
   `revoke execute ... from public, anon, authenticated` + `grant execute ... to service_role`, `security invoker`,
   `set search_path = ''`(`poll_feed` 와 같은 모양). 트리거 함수도 `search_path = ''`, execute 는 revoke.
3. **하트는 승인 한 번에 한 번.** 같은 줄을 다시 저장하거나 검수 뒤 상태를 바꾸려 해도 원장 행은 1개다.
4. **이미 적용된 마이그레이션은 고치지 않는다.** `grant_hearts` 도 그대로 부른다.
5. **새 마이그레이션 타임스탬프 `20260928030000` · `20260928030100`**(대장 09-28 DB 차례 때 확정, 나 탭 020000 뒤).
   바뀌면 세 곳을 같이 고친다(파일 이름 · C2 주석 · B1 docstring).
6. **로그 · 디스코드에 사진 경로 · 실명 · 캡처 내용을 싣지 않는다.** profile_id 와 제출 id 만.
7. **문구는 한 곳에서만** — 서버 `core/errors.py`, 앱은 화면 파일 상단 상수.
8. **새 화면은 COMMON §4-2 잉크 규칙을 지킨다.** 목록 줄의 가장 가까운 `Material` 이 줄 자신이다.
9. 공유 파일은 아래 목록 밖으로 고치지 않는다. 커밋 · PR 에 도구 표식을 넣지 않는다. `dart format` 을 돌리지 않는다.

---

## Review Focus

1. **같은 항목을 거의 동시에 두 번 제출**(더블 탭 · 두 기기) → 검수 중 줄은 1개, 월 한도도 넘지 않는다.
   → C1 pgTAP "두 번째 submitted 는 23505" + B1 pytest "RPC 23505 → 409, 올린 파일 삭제".
2. **운영자가 승인을 두 번 저장 · 승인 → 반려 · 반려 → 승인** → 원장 1줄 · 잔액 한 번, 반려 → 승인은 지급 0.
   → C2 pgTAP 트리거 묶음.
3. **달이 바뀌는 순간**(한국 시간 10월 1일 0시 = UTC 9월 30일 15시) → 9월 한도는 10월에 다시 시작한다.
   → C2 pgTAP "09-30 23:59:59+09 는 9월, 10-01 00:00+09 는 10월".
4. **사진은 올렸는데 DB 판정에서 막힘**(다른 기기가 먼저 냄) → 고아 파일이 남지 않는다.
   → B1 pytest "RPC CM429 → 429, 같은 경로 DELETE".
5. **사진이 아닌 파일 · 없는 항목 이름 · 글자 크기 2배** → 400 · 422, 파일 안 올림, 18a 줄이 넘치지 않는다.
   → B1 pytest + A(pen 뒤) 위젯 테스트(textScaleFactor 2.0 예외 0).

---

## DB 변경 목록 (ERD.pen 반영 대상 — DB 차례 때 대장에게 같이 드린다)

ERD.pen 에는 `heart_task_submissions` 가 그림만 있고, enum 둘과 버킷은 ERD.md 표에만 있다. **굵은 것은 ERD 에 없는 새 것**이다.

| # | 무엇 | 내용 | ERD 대비 |
| --- | --- | --- | --- |
| 1 | enum `heart_task` | `everytime_post` · `kakao_share` | ERD §8 그대로 |
| 2 | enum `submission_status` | `submitted` · `approved` · `rejected` | ERD §8 그대로 |
| 3 | **enum `heart_task_reject_reason`** | `date_missing` · `not_verified` · `reused` (D3) | **새 enum** |
| 4 | 표 `heart_task_submissions` | `id` uuid PK · `profile_id` FK → profiles **on delete cascade** · `task` · `status` default `submitted` · `created_at` · `reviewed_at` | ERD §6 그대로 |
| 4a | 칸 `storage_path` | **null 허용**으로 바꿈 + check "검수 중이면 반드시 있음"(60일 정리가 비운다, D6) | **ERD 는 not null 뜻** |
| 4b | **칸 `reward_hearts`** | integer not null, check > 0 — 제출 때 약속한 하트(D5) | **새 칸** |
| 4c | **칸 `reject_reason`** | `heart_task_reject_reason`, check "반려일 때만, 반려면 반드시" | **새 칸** |
| 4d | check | `reviewed_at is null` ⇔ `status = 'submitted'` | 새 제약 |
| 5 | 인덱스 | **부분 unique `(profile_id, task) where status = 'submitted'`** · `(profile_id, created_at)` | 새 |
| 6 | RLS · grant | 본인 행 select 정책, `authenticated` select 만, `service_role` 네 권한 | ERD §2 85줄 그대로 |
| 7 | 함수 `heart_task_monthly_limit(task)` | 1 · 3 — 한도는 여기 한 곳 | 새 |
| 8 | 함수 `heart_task_status(profile, now)` | 18a 세 줄: 이번 달 쓴 횟수 · 한도 · 검수 중 · 이번 달 마지막 상태 · 반려 사유, 투표 줄은 이번 주 적립 횟수 / 3 | 새 |
| 9 | 함수 `submit_heart_task(id, profile, task, path, reward, now)` | 검수 중이면 `CM409`, 한도면 `CM429`, 아니면 insert | 새 |
| 10 | 트리거 `heart_task_submissions_guard` | before update — 고정 칸 5개 · 끝 상태 · `reviewed_at` 찍기 · 검수 뒤엔 `storage_path → null` 만 | 새 |
| 11 | 트리거 `heart_task_submissions_grant` | after update of status, 검수 중 → 승인일 때만 `grant_hearts(profile_id, reward_hearts, 'free_task', id)` | 새 |
| 12 | 버킷 `heart-task-proofs` | 비공개 · 10MB · jpeg/png, Storage 정책 없음 | ERD §9 그대로 + 제한 |

---

## API 계약 (B · A 공통)

모두 `get_verified_caller` 뒤. 오류 본문은 `{"detail": "<문구>"}`.

| 메서드 · 경로 | 요청 | 성공 | 실패 |
| --- | --- | --- | --- |
| `GET /heart-tasks` | — | 200 `{"tasks": [HeartTask × 3]}` — 늘 `everytime_post` · `kakao_share` · `poll_vote` 순 | — |
| `POST /heart-tasks/{task}/submissions` | multipart `photo`, `task` 는 `everytime_post` \| `kakao_share` | 201 `{"task": HeartTask}`(보통 `state: "reviewing"`) | 400 `PHOTO_UNREADABLE`(사진 아님 · 10MB 초과) / 409 `HEART_TASK_IN_REVIEW` / 429 `HEART_TASK_MONTHLY_LIMIT` / 422 없는 항목 |

`HeartTask` = `{"task": str, "reward_hearts": int, "state": "open" | "reviewing" | "done" | "rejected", "used": int,
"limit": int, "reject_reason": "date_missing" | "not_verified" | "reused" | null}` — **이 6칸 말고는 없다.**
`state` 판정 순서: 검수 중 → `reviewing`, `used >= limit` → `done`, 이번 달 마지막 제출이 반려 → `rejected`, 나머지 `open`.
`reject_reason` 은 `state == "rejected"` 일 때만 값이 있다. 투표 줄은 `reward_hearts` 10 · `limit` 3 · `used` = 이번 주 적립 횟수.

---

## 운영자 절차 (DEPLOY 문서 정리 때 옮긴다)

1. 디스코드 "무료 하트 인증 1건 (제출: `<id>`, 계정: `<profile_id>`, 항목: `everytime_post`)" 을 본다.
2. Supabase 대시보드 → Table editor → `heart_task_submissions` 에서 `id` 로 줄을 찾고, `storage_path` 로
   Storage → `heart-task-proofs` 의 파일을 연다.
3. 승인: 그 줄의 `status` 를 `approved` 로 저장 — 하트는 트리거가 준다. 반려: **"Edit row" 패널에서 `status` =
   `rejected` 와 `reject_reason` 을 한 번에 저장**(칸 하나씩 저장하면 check 23514 로 막힌다).
   Edit row 가 바꾸지 않은 칸(`created_at` 등)까지 다시 보내 CM409 로 막히면 SQL Editor 에서 한 줄로 한다 —
   `update public.heart_task_submissions set status = 'rejected', reject_reason = '<사유>' where id = '<id>';`
   (승인은 `set status = 'approved'`). 클라우드 적용 뒤 첫 검수 때 Edit row 가 되는지 한 번 확인한다(검토 09-28 권고 1).
4. 잘못 눌렀을 때: 되돌리지 못한다. 반려를 잘못했으면 사용자가 다시 내면 되고, 승인을 잘못했으면 `admin_adjust` 로
   원장을 보정한다(`grant_hearts` 음수 호출 — 나 탭이 고치는 음수 동작이 merge 된 뒤의 규칙을 따른다. 문서 정리 때 그 PR
   기준으로 한 줄 예시를 적는다).

---

## 화면 대조표 (pen 묶음 7 — 대장 09-28 `값표_새기능_A.md`, PNG `수정후_새기능/02~05`)

pen 이 기준이다. 리뷰어는 이 표와 PNG 를 앱 위젯 테스트 치수 · 실제 코드와 대조한다.

### 18a 무료로 하트 모으기 `qyUgZ` (360 폭, #FFFFFF)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 앱바 | 56, 좌우 16, 간격 12, 가운데 | `Q9II4` | `AppBar` toolbarHeight 56 · leadingWidth 52(왼쪽 4 + 뒤로 48) · titleSpacing 0 → 아이콘 x16~40, 제목 x52 |
| 뒤로 | arrow-left 24 #222222, **누름 48**(대장) | `uV0zU` | `IconButton` 48 · `AppIcons.arrowLeft` 24 ink |
| 제목 | "무료로 하트 모으기" 24/700 #222222 | `J9lLtW` | `AppTypography.headline` ink, 한 줄 말줄임(글자 2배 대비) |
| 스크롤 | 세로, 여백 [8,16,32,16] | `NYgh7` | `ListView` padding LTRB(16,8,16,32) |
| 섹션 제목 | "무료로 모으기" 20/600 **꺼짐** | `OocPD` | 그리지 않는다 |
| 안내 | "초기 보상 기준 · 인증 후 지급⏎100명 이후 홍보 30 / 단톡방 20 하트" 12/400 #6A6A6A lh1.4 | `EJDsZ` | `caption` muted(토큰 1.4) |
| 간격 | 섹션 간격 8 + 빈칸 8 + 간격 8 | `Kszjl` · `vlmhj` | 안내 → 첫 줄 24(`AppSpacing.lg`), 줄 사이 8 |
| 줄 1 · 2 · 3 | 에브리타임(검수중) · 단톡방(완료) · 투표(매일 · 참여) | `S4hZup` · `K7Lvdg` · `Gur8f` | `HeartTaskRow` × 서버 세 줄 |

### HeartTaskRow `R99dx` (Z54et)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 줄 | 328×64, 간격 12, 가운데, 아래 선 1 #DDDDDD | `R99dx` | 최소 높이 64(글자 키우면 늘어남) · `Border(bottom: hairline)` |
| 아이콘 | 20 #3F3F3F — megaphone · share-2 · vote | `Fwoqx` | `AppIcons.megaphone` · `share2` · `vote` 20 body(**새 아이콘 3 — 공유 파일**) |
| 가운데 열 | 세로 간격 2, 채움 | `y8E3m` | `Expanded` Column, 간격 2 |
| 제목 | 14/600 #222222, 렌더 20 | `gIE0E` | `labelSmall` ink, height 20/14 |
| "매일" 배지 | #F2F2F2 pill [2,6] 11/700 #6A6A6A, 제목과 간격 6, 투표 줄만 | `Uaex2` · `klkPA` | `surfaceStrong` · `badge` w700 muted |
| 보상 줄 | 간격 4, 재화 하트 `l4vdk` 18, 12/600 #6A6A6A | `FsKp0` · `wYL8o` · `h76RpG` | `heart-flat-vector-v3.png` 18(`semanticLabel: '하트'`) + `caption` w600 muted |
| 보상 글자 | "50 · 월 1회" · "25 · 월 3회" · "10 · 주 최대 30" — **이번 주 · 1/3 표시 없음**(대장) | — | 서버 `reward_hearts` · `limit` 로 만든다 |
| 검수중 | #F2F2F2 pill 72×28 [6,10] 간격 4, timer 12 #6A6A6A, "검수중" 11/700 #6A6A6A | `e2aMg` | `_Chip` surfaceStrong / muted |
| 완료 | #FFF0F2, check 12 #C4224B, "완료" #C4224B | `gGX34` | `_Chip` primaryWash / primaryText |
| 미완료 | #E5E5E5 pill 72×28 [6,10] 11/700 #222222 — **과제 "인증하기"**(대장, pen 변형은 다음 묶음) · 투표 "참여" | `xGTbF` · `JQNcz` | `_Chip` primaryDisabled(#E5E5E5 토큰) / ink |
| 반려 | "다시 제출" 14/600 #C13515, **아래 선 투명**, 사유 표시 없음 | `K34l9g` · `w3aZL` | `labelSmall` error, 선 `Colors.transparent` |
| 누름 | **줄 전체**(대장) — 과제 미완료 · 반려 → 18b, 투표 미완료 → 커뮤니티 탭. 검수중 · 완료는 안 눌림 | — | 줄 자신의 투명 `Material` + `InkWell`(COMMON §4-2), 64 ≥ 48 |

### 18b 인증샷 제출 `F15q0W` · 18b-2 반려 뒤 다시 제출 `DMrAI`

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 앱바 | 56 [0,8] 간격 4, 뒤로 48(arrow-left 22) | `k9nvth` · `syyGc` | 17c `poll_detail_screen` 앱바 그대로(leadingWidth 56, titleSpacing 4) |
| 제목 | "인증샷 제출" 20/700 lh1.5 | `EHxAe` | `navTitle` |
| 본문 | 세로 간격 16, 여백 16 | `re6T6` | `ListView` padding 16, 사이 16 |
| 반려 알림(18b-2) | Body 맨 위, #FAEFEC, [12,16], 간격 10, triangle-alert 20 #C13515, "반려 사유: {사유}" 14/600 #C13515 lh1.5, "다시 찍어 올려 주세요" 12/400 #6A6A6A lh1.5, 모서리 없음, 높이 67 | `kdibh`(`teNRJ`) | `_RejectReasonAlert` errorWash · `AppIcons.alertTriangle` 20 error · 두 줄 사이 4(67 − 24 − 21 − 18) |
| 안내 | "스크린샷을 첨부하면 확인 후 하트를 드려요" 16/600 #3F3F3F, 렌더 23 | `qLG9R` | `bodyStrong` body, height 23/16 |
| 업로더 | 328×220 #F7F7F7 r14 선 #DDDDDD 1, image-plus 32 #929292, "스크린샷 첨부하기" 14/600 #929292 | `moNIO` · `u7vbr` | `_ProofUploader` — 자기 `Material`(surfaceSoft · 모서리 14 · 선 hairline) + `InkWell` |
| 버튼 | 56 primary r16 18/700 흰색, 업로더 바로 아래(y291) — "제출하기" / 18b-2 "다시 제출하기" | `TVB6v` · `jC1iu` | `AppButton` primary, 본문 안(하단 고정 아님) |
| 배치(18b-2) | 알림 16..83 / 안내 99..122 / 업로더 138..358 / 버튼 374..430 (본문 기준) | — | 위젯 테스트로 고정 |

### 18c 검수 대기 `xA8en`

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 화면 | 앱바 · 버튼 없음, 세로 · 가로 가운데 | `xA8en` | `Scaffold` 앱바 없음, 시스템 뒤로 → 18a(18b 를 대체했으므로) |
| 내용 | 폭 280, 세로 간격 16 | `Bjhpo` | `SizedBox(width: 280)` Column 사이 16 |
| 마스코트 | 88×88 mascot-female fit(DESIGN 128 → pen, 문서 정리 때) | `qoDjV` | `Image.asset` 88 contain |
| 제목 | "확인하고 있어요" 18/700 #222222 | `AI5GP` | `label` ink |
| 설명 | "확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요" 14/500 #6A6A6A 가운데 | `o8rRLe` | `bodySmall` w500 muted height 20/14 |
| 새 줄 | "보통 영업일 1~2일 걸려요" 14/500 #6A6A6A 가운데 | `WtYfW` | 같은 스타일 |

### 16 설정 행 `oNgRd` (카드 `auq6h`, A6)

52, [0,14], 간격 12, 아래 선 투명, gift 20 #3F3F3F(`JWxQo`), "무료로 하트 모으기" 16/400 #222222(`cC4Xz`),
chevron-right 20 #6A6A6A(`nqlvc`) → 18a.

### 편차 — pen 에 없는 것은 앱의 기존 패턴을 따른다(대장 09-28)

1. **18a 불러오는 중**: 가운데 `CircularProgressIndicator`(16f 차단 목록과 같다). 빈 상태는 없다 — 서버가 늘 세 줄.
2. **18a 읽기 실패**: 회색 문구 + "다시 시도" 글자 버튼(16f `_LoadError` 와 같다).
3. **18b 업로더 채운 상태**: 같은 칸 안에 고른 사진을 `BoxFit.contain`(DESIGN §8.10 "fit"). 다시 누르면 다시 고른다.
4. **18b 올리는 중**: 버튼이 꺼진다(17b 질문 쓰기와 같다). 업로더도 안 눌린다.
5. **18b 실패**: 버튼 위 토스트 3초 · 경고 아이콘(04-2 사진 화면 `AppToast` 와 같다). 문구는 서버 문구 그대로, **429 만 앱
   상수 "이번 달에는 더 인증할 수 없어요"**(공용 429 문구 "잠시 후 다시 시도" 는 달이 바뀌어야 풀리는 한도와 맞지 않다 —
   17b 하루 상한 · 신고 상한과 같은 처리). 압축 실패는 "사진을 다시 확인해 주세요"(서버 `PHOTO_UNREADABLE` 과 같은 문구).
6. **에브리타임 18b 의 "날짜가 보이게 찍어 주세요"**(DESIGN §8.10 `review-submission`): **대장 09-28 결정 (가)** — 에브리타임
   18b 에만 안내 `qLG9R` 아래 캡션 한 줄 12/400 #6A6A6A(간격 4), 단톡방에는 없다. 글자는 대장 문구 그대로(띄어 씀). pen 변형
   "18b 에브리타임" 은 다음 묶음에서 그리고, 값이 다르면 대장이 알려 준다.
7. **18c 로 넘어갈 때 18b 를 대체**(`pushReplacement`) — 18c 에서 뒤로 가면 18a. 제출이 성공하면 18a 목록을 다시 읽어 "검수중" 이 보인다.
8. **반려 줄 아래 선 투명**은 pen `w3aZL` 그대로 둔다.

---

## 공유 파일 (줄 단위로 한 번에 허락받는다 — 아직 요청 전, PR 2 · 3 착수 때 요청)

| 파일 | 무엇 | 언제 |
| --- | --- | --- |
| `backend/app/core/errors.py` | 제목 주석 1줄 + 문구 2줄(`HEART_TASK_IN_REVIEW` · `HEART_TASK_MONTHLY_LIMIT`) | PR 2 |
| `backend/app/main.py` | import 1줄 + `include_router` 1줄 | PR 2 |
| `backend/app/account/batch_router.py` | **허락: 통합대장 09-28(미리)** — `STORAGE_BUCKETS` 에 `"heart-task-proofs"`(탈퇴 30일 뒤 폴더째) · import 3줄 · `run_cleanup_batch` 끝에 60일 정리 호출 3줄 · 주석 1줄 = 8줄(B2 Step 5 에 그대로). `run_cleanup` 시그니처 그대로, 기존 테스트 0줄 | PR 2 |
| `frontend/lib/core/theme/app_icons.dart` | **허락: 통합대장 09-28(미리)** — 아이콘 4줄 `megaphone` · `share2` · `vote`(18a) · `gift`(설정 행). triangle-alert 는 이미 있는 `alertTriangle` 을 쓴다 | PR 3 |
| `frontend/lib/core/router/app_routes.dart` | 주석 1줄 + 상수 3줄(18a · 18b · 18c) — A5 Step 3 그대로 | PR 3 |
| `frontend/lib/core/router/app_router.dart` | import 4줄 + `_slice6Routes()` 끝에 라우트 3개(18b 는 잘못된 항목이면 18a 로 redirect) — A5 Step 3 그대로 | PR 3 |
| `frontend/lib/matching/view/settings_screen.dart` | "무료로 하트 모으기" 행 1개 — **프로필탭 · 안전담당 행이 merge 된 뒤 rebase 해서**, 카드 `auq6h` 안 자리는 그때 대장에게 확인 | PR 3 |

---

## 파일 구조

```
supabase/migrations/
  20260928030000_create_heart_task_submissions.sql   # enum 3 · 표 · 인덱스 · RLS · grant · 버킷 (C1)
  20260928030100_create_heart_task_functions.sql     # 한도 · 상태 · 제출 함수 + 검수 트리거 2 (C2)
supabase/tests/heart_tasks_test.sql                   # C1 · C2

backend/app/heart_tasks/
  __init__.py
  repository.py      # heart_task_status · submit_heart_task RPC, 60일 정리용 읽기 · 비우기 (B1 · B2)
  storage.py         # heart-task-proofs 올리기 · 지우기 (B1)
  router.py          # GET 목록 · POST 제출 · 디스코드 알림 (B1)
  cleanup.py         # purge_reviewed_proofs (B2)
backend/tests/heart_tasks/
  test_heart_tasks.py      # B1
  test_proof_cleanup.py    # B2

frontend/lib/billing/
  model/heart_task.dart                        # HeartTaskKind · HeartTaskState · HeartTaskRejectReason · HeartTask (A1)
  model/heart_task_repository.dart             # 인터페이스 (A1)
  model/http_heart_task_repository.dart        # GET 목록 · multipart 제출 (A1)
  model/heart_task_repository_provider.dart    # (A1)
  viewmodel/heart_tasks_ui_state.dart          # 18a 상태 (A2)
  viewmodel/heart_tasks_view_model.dart        # 18a 읽기 (A2)
  viewmodel/heart_task_submit_ui_state.dart    # 18b 상태 (A2)
  viewmodel/heart_task_submit_view_model.dart  # 사진 고르기 · 압축 · 제출 (A2)
  view/heart_task_row.dart                     # R99dx 4상태 (A3)
  view/heart_tasks_screen.dart                 # 18a (A3)
  view/heart_task_submit_screen.dart           # 18b · 18b-2 (A4)
  view/heart_task_pending_screen.dart          # 18c (A5)
frontend/test/billing/
  model/fake_heart_task_repository.dart · model/heart_task_test.dart · model/http_heart_task_repository_test.dart
  viewmodel/heart_task_view_models_test.dart
  view/heart_tasks_screen_test.dart · view/heart_task_submit_screen_test.dart · view/heart_task_pending_screen_test.dart
```

---

## PR 나누기

| PR | 브랜치 | 내용 | 관문 |
| --- | --- | --- | --- |
| 1 DB | `feat/heart-tasks`(지금 워크트리) | C1 · C2 | DB 차례(referral → 나 탭 grant_hearts 음수 수정 → 이것, 대장 09-28) — 대장 09-28: rebase 없이 b3f7a25 위에서(트리거는 양수 지급이라 grant_hearts 옛 함수로도 같다), heart-tasks 워크트리에서 `supabase db reset` 한 번 뒤 pgTAP → draft → 검토 PASS → merge → ERD.pen 그림 · 사용자 검토 · 승인 → 클라우드 적용(대장) |
| 2 서버 | `feat/heart-tasks-server`(PR 1 merge 뒤 같은 워크트리에서 새 main 으로) | B1 · B2 + 공유 파일 3 | 운영 DB 에 PR 1 이 **적용된 뒤** 배포(대장) — 먼저 배포하면 RPC 404 로 500 |
| 3 앱 | `feat/heart-tasks-app` | Part A + 공유 파일 3 | 가짜 저장소로 PR 2 와 나란히(대장 허락 시), PR 2 배포 뒤 ready. settings 행은 프로필탭 · 안전 merge 뒤 |

---

# Part C — Supabase ("DB 차례" 뒤에만)

작업 위치: `C:/Users/user/AndroidStudioProjects/campus_mate_compose-heart-tasks`. 로컬 스택은 루트와 같은
project_id 라 워크트리에서 돌려도 같은 DB 다 — **DB 차례를 쥔 동안만** `supabase db reset` · `supabase test db`.
로컬 DB 명령은 차례를 쥔 이 창의 코더·리뷰어만 쓴다. 도우미(campus-git · campus-ui · 차례 없는 코더·리뷰어) 요청문에는
"supabase db reset·test db 등 로컬 DB 명령 금지. 수치는 리뷰어 값 인용" 을 꼭 적는다(대장 09-28 전체 규칙).

### Task C1: 표 · enum · 권한 · 버킷

**Files:**
- Create: `supabase/migrations/20260928030000_create_heart_task_submissions.sql`
- Create: `supabase/tests/heart_tasks_test.sql`
- Modify: `supabase/tests/rls_slice0_test.sql`(권한 누적표에 5줄 — 새 표를 만들면 여기가 깨진다, 커뮤니티 C1 에서 걸린 적 있음)

**Interfaces:**
- Consumes: `public.profiles(id)`, `auth.uid()`
- Produces: `public.heart_task`('everytime_post','kakao_share'), `public.submission_status`('submitted','approved','rejected'),
  `public.heart_task_reject_reason`('date_missing','not_verified','reused'), 표 `public.heart_task_submissions`
  (`id uuid`, `profile_id uuid`, `task heart_task`, `storage_path text null`, `status submission_status`,
  `reward_hearts integer`, `reject_reason heart_task_reject_reason null`, `created_at timestamptz`, `reviewed_at timestamptz null`),
  부분 unique 인덱스 `heart_task_submissions_one_reviewing`, 버킷 `heart-task-proofs`

- [ ] **Step 1: 실패하는 pgTAP 을 쓴다(C1 절 22개 + C2 절 자리, 모두 55).** `supabase/tests/heart_tasks_test.sql` 전체를 아래로
  만든다. C2 절도 함께 넣는다 — C1 만 적용한 상태에서는 C2 절이 함수 없음으로 실패하는 것이 맞다.

```sql
-- 무료로 하트 모으기(18a · 18b · 18c) 표 · 권한 · DB 함수 · 검수 트리거 검증.
-- 기대값 기준: docs/superpowers/plans/2026-09-28-heart-tasks.md Task C1 · C2.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

-- 준비 --------------------------------------------------------------------
-- A = ...90(주 사용자), B = ...91(남 — RLS), M = ...92(달 경계), K = ...93(단톡방 3회 · 반려),
-- P = ...94(검수 중 · 투표 줄), G = ...95(탈퇴 cascade)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000009', '테스트대학교9', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test9.ac.kr', '00000000-0000-0000-0000-000000000009');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000090', 'h-a@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000091', 'h-b@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000092', 'h-m@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000093', 'h-k@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000094', 'h-p@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000095', 'h-g@test9.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000009' from auth.users
where id between '00000000-0000-0000-0000-000000000090' and '00000000-0000-0000-0000-000000000095'
on conflict (id) do nothing;

-- C1: 표 · enum · 권한 · 버킷 ---------------------------------------------
select has_table('public', 'heart_task_submissions', 'heart_task_submissions 표가 있다');                   -- 1
select enum_has_labels('public', 'heart_task', array['everytime_post', 'kakao_share'],
  'heart_task 는 everytime_post · kakao_share');                                                            -- 2
select enum_has_labels('public', 'submission_status', array['submitted', 'approved', 'rejected'],
  'submission_status 는 submitted · approved · rejected');                                                  -- 3
select enum_has_labels('public', 'heart_task_reject_reason', array['date_missing', 'not_verified', 'reused'],
  '반려 사유는 정해진 셋(D3)');                                                                              -- 4
select ok((select relrowsecurity from pg_class where oid = 'public.heart_task_submissions'::regclass),
  'heart_task_submissions 는 RLS 가 켜져 있다');                                                             -- 5
select is((select count(*) from pg_policies where tablename = 'heart_task_submissions'), 1::bigint,
  '정책은 본인 읽기 하나뿐이다(ERD §2 85줄)');                                                                -- 6
select table_privs_are('public', 'heart_task_submissions', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'service_role 은 네 권한이 다 있다');                        -- 7
select table_privs_are('public', 'heart_task_submissions', 'authenticated', array['SELECT'],
  'authenticated 는 select 만 있다');                                                                        -- 8
select table_privs_are('public', 'heart_task_submissions', 'anon', array[]::text[],
  'anon 은 아무 권한도 없다');                                                                                -- 9
select results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'heart-task-proofs'$$,
  $$values (false, 10485760::bigint, array['image/jpeg', 'image/png'])$$,
  'heart-task-proofs 는 비공개 · 10MB · jpeg/png 다'
);                                                                                                           -- 10

-- 제약 확인용 줄 E1(A 의 에브리타임, 검수 중). 이 절 끝에서 비운다.
insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000090', 'everytime_post',
        'a/e1.jpg', 50);

select results_eq(
  $$select status::text, reviewed_at is null, reject_reason is null from public.heart_task_submissions
     where id = '00000000-0000-0000-0000-0000000000e1'$$,
  $$values ('submitted', true, true)$$,
  '새 줄은 검수 중 · 검수 시각 없음 · 사유 없음이다'
);                                                                                                           -- 11
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/x.jpg', 0)$$,
  '23514', null, '약속 하트는 0보다 커야 한다'
);                                                                                                           -- 12
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', null, 25)$$,
  '23514', null, '검수 중인 줄에는 인증샷 경로가 반드시 있다'
);                                                                                                           -- 13
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'everytime_post', 'a/e9.jpg', 50)$$,
  '23505', null, '한 항목에 검수 중인 줄은 하나뿐이다 — 거의 동시에 낸 두 번째도 여기서 막힌다'
);                                                                                                           -- 14
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts, reject_reason)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/x.jpg', 25, 'reused')$$,
  '23514', null, '반려가 아닌 줄에는 반려 사유가 없다'
);                                                                                                           -- 15
select lives_ok(
  $$insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000090', 'kakao_share',
            'a/e2.jpg', 25)$$,
  '다른 항목은 동시에 검수 중일 수 있다'
);                                                                                                           -- 16

-- B 의 줄 E3 — A 가 못 봐야 한다.
insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
values ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000091', 'kakao_share',
        'b/e3.jpg', 25);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000090", "role": "authenticated"}';

select results_eq(
  $$select id from public.heart_task_submissions order by id$$,
  $$values ('00000000-0000-0000-0000-0000000000e1'::uuid), ('00000000-0000-0000-0000-0000000000e2'::uuid)$$,
  'A 는 본인 줄 둘만 본다'
);                                                                                                           -- 17
select is_empty(
  $$select 1 from public.heart_task_submissions where profile_id = '00000000-0000-0000-0000-000000000091'$$,
  'A 는 B 의 줄을 볼 수 없다'
);                                                                                                           -- 18
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/y.jpg', 25)$$,
  '42501', null, 'A 는 직접 insert 할 수 없다'
);                                                                                                           -- 19
select throws_ok(
  $$update public.heart_task_submissions set status = 'approved'
     where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A 는 자기 줄을 승인할 수 없다'
);                                                                                                           -- 20
select throws_ok(
  $$delete from public.heart_task_submissions where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A 는 직접 delete 할 수 없다'
);                                                                                                           -- 21

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select 1 from public.heart_task_submissions$$,
  '42501', null, 'anon 은 읽을 수도 없다'
);                                                                                                           -- 22

reset role;
reset request.jwt.claims;
delete from public.heart_task_submissions;

-- C2: 제출 함수 · 검수 트리거 · 상태 함수 ------------------------------
-- 시각은 전부 고정한다. 트랜잭션 안의 now() 는 테스트를 돌린 날이라 달 경계를 못 잡는다.

-- A: 에브리타임 제출 → 검수 중 막힘 → 고정 칸 막힘 → 승인 한 번 → 끝 상태
select lives_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f1.jpg', 50, '2026-09-15 12:00:00+09')$$,
  '처음 제출은 들어간다'
);                                                                                                           -- 23
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f2.jpg', 50, '2026-09-15 12:00:01+09')$$,
  'CM409', null, '검수 중인 항목은 다시 낼 수 없다(서버 409)'
);                                                                                                           -- 24
select throws_ok(
  $$update public.heart_task_submissions set reward_hearts = 999
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '약속 하트는 운영자도 못 바꾼다'
);                                                                                                           -- 25
select throws_ok(
  $$update public.heart_task_submissions set storage_path = null
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '검수 중에는 인증샷 경로를 바꿀 수 없다'
);                                                                                                           -- 26
select throws_ok(
  $$update public.heart_task_submissions set status = 'rejected'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '23514', null, '사유 없이 반려할 수 없다(대시보드에서는 두 칸을 한 번에 저장)'
);                                                                                                           -- 27

update public.heart_task_submissions set status = 'approved'
 where id = '00000000-0000-0000-0000-0000000000f1';

select results_eq(
  $$select amount, reason::text, ref_id from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-000000000090'$$,
  $$values (50, 'free_task', '00000000-0000-0000-0000-0000000000f1'::uuid)$$,
  '승인하면 원장에 free_task 50 이 제출 id 로 한 줄 생긴다'
);                                                                                                           -- 28
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000090'),
  50, '잔액도 50 이다'
);                                                                                                           -- 29
select ok(
  (select reviewed_at is not null from public.heart_task_submissions
    where id = '00000000-0000-0000-0000-0000000000f1'),
  '승인하면 검수 시각이 찍힌다'
);                                                                                                           -- 30
select lives_ok(
  $$update public.heart_task_submissions set status = 'approved'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '승인 → 승인 다시 저장은 통과한다'
);                                                                                                           -- 31
select throws_ok(
  $$update public.heart_task_submissions set status = 'rejected', reject_reason = 'reused'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '승인 → 반려는 막힌다(끝 상태)'
);                                                                                                           -- 32
select results_eq(
  $$select (select count(*) from public.heart_transactions
             where profile_id = '00000000-0000-0000-0000-000000000090'),
           (select heart_balance from public.entitlements
             where profile_id = '00000000-0000-0000-0000-000000000090')$$,
  $$values (1::bigint, 50)$$,
  '다시 저장 · 반려 시도 뒤에도 원장 1줄 · 잔액 50 — 두 번 주지도 회수하지도 않는다'
);                                                                                                           -- 33
select throws_ok(
  $$update public.heart_task_submissions set storage_path = 'a/other.jpg'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '검수 뒤 인증샷 경로를 다른 값으로 바꿀 수 없다'
);                                                                                                           -- 34
select lives_ok(
  $$update public.heart_task_submissions set storage_path = null
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '검수 뒤 인증샷 경로 비우기(60일 정리)는 된다'
);                                                                                                           -- 35
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f3.jpg', 50, '2026-09-20 12:00:00+09')$$,
  'CM429', null, '에브리타임은 한 달 1회 — 승인된 달에는 더 못 낸다(서버 429)'
);                                                                                                           -- 36

-- M: 달 경계. 한국 시간 10월 1일 0시 = UTC 9월 30일 15시.
-- 준비용 호출은 do 블록의 perform 으로 한다 — 맨 select 는 빈 줄을 TAP 출력에 섞는다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-000000000092',
    'everytime_post', 'm/f4.jpg', 50, '2026-09-30 23:59:59+09');
  update public.heart_task_submissions set status = 'approved'
   where id = '00000000-0000-0000-0000-0000000000f4';
end $$;

select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-000000000092',
      'everytime_post', 'm/f5.jpg', 50, '2026-09-30 23:59:59.9+09')$$,
  'CM429', null, '9월 30일 23:59:59.9(한국)는 아직 9월이다'
);                                                                                                           -- 37
select lives_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-000000000092',
      'everytime_post', 'm/f6.jpg', 50, '2026-10-01 00:00:00+09')$$,
  '10월 1일 0시(한국)부터 새 달이다 — UTC 로는 아직 9월 30일이어도'
);                                                                                                           -- 38

-- K: 단톡방. 반려는 한도에서 빠지고 끝 상태다. 승인 3번이면 그 달은 끝.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a1.jpg', 25, '2026-09-10 12:00:00+09');
  update public.heart_task_submissions set status = 'rejected', reject_reason = 'date_missing'
   where id = '00000000-0000-0000-0000-0000000000a1';
end $$;

select results_eq(
  $$select used, task_limit, reviewing, last_status::text, last_reject_reason::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000093', '2026-09-15 12:00:00+09')
     where task = 'kakao_share'$$,
  $$values (0, 3, false, 'rejected', 'date_missing')$$,
  '반려는 쓴 횟수에 안 들어가고, 마지막 상태 · 사유로 보인다'
);                                                                                                           -- 39
select throws_ok(
  $$update public.heart_task_submissions set status = 'approved', reject_reason = null
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '반려 → 승인은 막힌다(끝 상태)'
);                                                                                                           -- 40
select is(
  (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-000000000093'),
  0::bigint, '반려 → 승인 시도로는 하트가 나가지 않는다'
);                                                                                                           -- 41

do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a2.jpg', 25, '2026-09-11 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a2';
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a3.jpg', 25, '2026-09-12 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a3';
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a4.jpg', 25, '2026-09-13 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a4';
end $$;

select results_eq(
  $$select used, task_limit, last_status::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000093', '2026-09-15 12:00:00+09')
     where task = 'kakao_share'$$,
  $$values (3, 3, 'approved')$$,
  '단톡방은 반려 1 + 승인 3 이면 3/3 이다'
);                                                                                                           -- 42
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000093',
      'kakao_share', 'k/a5.jpg', 25, '2026-09-15 12:00:00+09')$$,
  'CM429', null, '단톡방은 한 달 3회까지다'
);                                                                                                           -- 43
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000093'),
  75, '단톡방 승인 3번 = 75하트'
);                                                                                                           -- 44

-- P: 검수 중 표시 · 투표 줄. 2026-09-14 가 월요일이다(주 시작). 09-14 05:00(한국)은 UTC 로 아직 09-13 이라
-- 주를 UTC 로 세면 1 이 나온다 — 한국 시간 주 경계를 여기서 잡는다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000094',
    'everytime_post', 'p/b1.jpg', 50, '2026-09-15 12:00:00+09');
end $$;
insert into public.heart_transactions (profile_id, amount, reason, created_at) values
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-13 10:00:00+09'),
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-14 05:00:00+09'),
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-15 10:00:00+09');

select results_eq(
  $$select used, task_limit, reviewing, last_status::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000094', '2026-09-15 12:00:00+09')
     where task = 'everytime_post'$$,
  $$values (1, 1, true, 'submitted')$$,
  '검수 중인 제출은 쓴 횟수에 들어가고 reviewing 이다'
);                                                                                                           -- 45
select results_eq(
  $$select used, task_limit, reviewing
      from public.heart_task_status('00000000-0000-0000-0000-000000000094', '2026-09-15 12:00:00+09')
     where task = 'poll_vote'$$,
  $$values (2, 3, false)$$,
  '투표 줄은 이번 주(월요일 0시부터) 적립 횟수 — 지난 일요일 것은 빠진다'
);                                                                                                           -- 46
select results_eq(
  $$select task, used, task_limit
      from public.heart_task_status('00000000-0000-0000-0000-000000000095', '2026-09-15 12:00:00+09')
     order by task$$,
  $$values ('everytime_post', 0, 1), ('kakao_share', 0, 3), ('poll_vote', 0, 3)$$,
  '처음 온 사람도 세 줄을 받는다'
);                                                                                                           -- 47

-- 함수 권한
select ok(
  not has_function_privilege('authenticated',
        'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute')
  and not has_function_privilege('anon',
        'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute'),
  '앱 역할은 제출 함수를 부를 수 없다'
);                                                                                                           -- 48
select ok(
  not has_function_privilege('authenticated', 'public.heart_task_status(uuid, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_status(uuid, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.heart_task_monthly_limit(public.heart_task)', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_monthly_limit(public.heart_task)', 'execute'),
  '앱 역할은 상태 · 한도 함수를 부를 수 없다'
);                                                                                                           -- 49
select ok(
  has_function_privilege('service_role',
    'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute')
  and has_function_privilege('service_role', 'public.heart_task_status(uuid, timestamptz)', 'execute'),
  'service_role 은 두 함수를 부를 수 있다'
);                                                                                                           -- 50
select ok(
  not has_function_privilege('authenticated', 'public.heart_task_submissions_grant()', 'execute')
  and not has_function_privilege('authenticated', 'public.heart_task_submissions_guard()', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_submissions_grant()', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_submissions_guard()', 'execute'),
  '앱 역할은 트리거 함수를 직접 부를 수 없다'
);                                                                                                           -- 51

-- G: 탈퇴 30일 뒤 auth 사용자를 지우면 제출도 cascade 로 사라진다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000095',
    'kakao_share', 'g/c1.jpg', 25, '2026-09-15 12:00:00+09');
end $$;
delete from auth.users where id = '00000000-0000-0000-0000-000000000095';

select is(
  (select count(*) from public.heart_task_submissions where profile_id = '00000000-0000-0000-0000-000000000095'),
  0::bigint, '탈퇴로 지워진 사람의 제출은 남지 않는다'
);                                                                                                           -- 52

select is(
  (select count(*) from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('heart_task_monthly_limit', 'heart_task_status', 'submit_heart_task',
                       'heart_task_submissions_guard', 'heart_task_submissions_grant')
       and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')),
  5::bigint, '다섯 함수 모두 search_path 가 고정돼 있다(advisor function_search_path_mutable)'
);                                                                                                           -- 53

-- 검수 뒤 칸 하나씩(K 의 반려된 a1): guard 끝 상태 블록의 사유 줄 · 검수 시각 줄을 따로 못 박는다(검토 09-28).
select throws_ok(
  $$update public.heart_task_submissions set reject_reason = 'reused'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '반려 뒤 사유만 바꿀 수도 없다 — 사용자에게 보이는 사유가 바뀐다'
);                                                                                                           -- 54
select throws_ok(
  $$update public.heart_task_submissions set reviewed_at = reviewed_at - interval '1 day'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '검수 시각도 검수 뒤에는 고칠 수 없다'
);                                                                                                           -- 55

select * from finish();
rollback;
```

- [ ] **Step 2: 실패를 확인한다.**

Run: `supabase test db` (워크트리에서, DB 차례를 쥔 동안)
Expected: `heart_tasks_test.sql` FAIL — `relation "public.heart_task_submissions" does not exist`(1번부터). 다른 테스트 파일은 그대로 PASS.

- [ ] **Step 3: 마이그레이션을 쓴다.** `supabase/migrations/20260928030000_create_heart_task_submissions.sql`:

```sql
-- 무료로 하트 모으기(18a · 18b · 18c): 인증샷 제출과 사람 검수. 기준 문서 docs/ERD.md §6 · §8 · §9, DESIGN §8.10.
-- 클라이언트는 본인 줄 읽기만 한다(ERD §2 85줄). 쓰기는 FastAPI(service_role)와 대시보드의 운영자뿐이다.
create type public.heart_task as enum ('everytime_post', 'kakao_share');
create type public.submission_status as enum ('submitted', 'approved', 'rejected');
-- 운영자는 고르기만 한다 — 자유 글이면 캡처 속 이름 같은 것이 사용자 화면으로 샐 수 있다(계획서 D3).
create type public.heart_task_reject_reason as enum ('date_missing', 'not_verified', 'reused');

create table public.heart_task_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  task public.heart_task not null,
  -- 검수가 끝나고 60일 뒤 정리 배치가 파일을 지우고 비운다(D6). 검수 중에는 반드시 있다(아래 check).
  storage_path text,
  status public.submission_status not null default 'submitted',
  -- 제출 때 약속한 하트. 승인 트리거가 이 값을 준다 — 서버 값이 바뀌는 날 검수 중이던 제출도 약속대로(D5).
  reward_hearts integer not null,
  reject_reason public.heart_task_reject_reason,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,

  constraint heart_task_submissions_reward_positive check (reward_hearts > 0),
  constraint heart_task_submissions_proof_while_reviewing check (status <> 'submitted' or storage_path is not null),
  constraint heart_task_submissions_reviewed_at check ((status = 'submitted') = (reviewed_at is null)),
  -- 반려면 사유가 반드시 있고, 반려가 아니면 없다. 대시보드에서는 "Edit row" 로 두 칸을 한 번에 저장한다.
  constraint heart_task_submissions_reject_reason check ((status = 'rejected') = (reject_reason is not null))
);

comment on table public.heart_task_submissions is
  '무료 하트 인증샷 제출. FastAPI 가 넣고 운영자가 대시보드에서 status 를 바꾼다. 승인하면 트리거가 하트를 한 번 준다';

-- 한 항목에 검수 중인 줄은 하나뿐. 거의 동시에 낸 두 번째는 23505 → 서버 409.
-- 월 한도(검수 중 + 승인)도 이 인덱스 덕에 잠금 없이 맞다 — 같은 항목의 두 번째 insert 가 여기서 막힌다.
create unique index heart_task_submissions_one_reviewing
  on public.heart_task_submissions (profile_id, task) where status = 'submitted';
-- 이번 달 세기와 탈퇴 cascade 가 profile_id 로 찾는다.
create index heart_task_submissions_profile_id_created_at_index
  on public.heart_task_submissions (profile_id, created_at);

alter table public.heart_task_submissions enable row level security;

create policy "heart task submissions are readable by owner"
  on public.heart_task_submissions for select to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.heart_task_submissions from anon, authenticated, service_role;
grant select on table public.heart_task_submissions to authenticated;
grant select, insert, update, delete on table public.heart_task_submissions to service_role;

-- 인증샷 버킷. 다른 버킷처럼 클라이언트용 storage.objects 정책은 없다 — FastAPI 가 service_role 로 올리고 지운다.
-- 버킷 제한은 신고된 content type · 크기로만 막으므로 파일 내용(매직 바이트)은 FastAPI 가 올리기 전에 본다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('heart-task-proofs', 'heart-task-proofs', false, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
```

- [ ] **Step 4: 권한 누적표를 고친다.** `supabase/tests/rls_slice0_test.sql` 의 기대 `values` 목록에서
  `('entitlements', 'service_role', 'UPDATE'),` 줄 바로 아래(정렬이 `collate "C"` 라 `heart_task_submissions` 가
  `heart_transactions` 보다 앞이다)에 5줄을 넣는다. 파일 머리의 `plan(21)` 은 그대로다(assert 수는 같고 기대 행만 는다).

```sql
      ('heart_task_submissions', 'authenticated', 'SELECT'),
      ('heart_task_submissions', 'service_role', 'DELETE'),
      ('heart_task_submissions', 'service_role', 'INSERT'),
      ('heart_task_submissions', 'service_role', 'SELECT'),
      ('heart_task_submissions', 'service_role', 'UPDATE'),
```

  referral(온보딩 탭) PR 이 먼저 merge 되면 같은 목록에 그쪽 줄이 들어가 있다 — rebase 때 두 묶음을 정렬 순서대로 둔다.

- [ ] **Step 5: C1 절이 통과하는지 본다.**

Run: `supabase db reset` → `supabase test db`
Expected: `rls_slice0_test.sql` ok, `heart_tasks_test.sql` 1~22 ok, 23번부터 FAIL(`function public.submit_heart_task(...)
does not exist`) — C2 몫. 다른 파일은 PASS. docker 비정상 컨테이너 한 줄을 보고에 적는다(`docker ps --filter health=unhealthy`).

- [ ] **Step 6: 커밋은 campus-git 이 한다** — 이 Task 의 세 파일은 "표 · 권한 · 버킷" 커밋 하나(테스트 파일은 C2 와 같이).

### Task C2: 한도 · 상태 · 제출 함수와 검수 트리거

**Files:**
- Create: `supabase/migrations/20260928030100_create_heart_task_functions.sql`
- Test: `supabase/tests/heart_tasks_test.sql`(C1 Step 1 에서 이미 씀 — 23~55)

**Interfaces:**
- Consumes: C1 의 표 · enum, `public.grant_hearts(uuid, integer, heart_reason, uuid)`(조각 2)
- Produces:
  - `public.heart_task_monthly_limit(p_task heart_task) → integer`
  - `public.heart_task_status(p_profile uuid, p_now timestamptz default now()) → table(task text, used integer,
    task_limit integer, reviewing boolean, last_status submission_status, last_reject_reason heart_task_reject_reason)`
    — 늘 세 줄(`everytime_post` · `kakao_share` · `poll_vote`)
  - `public.submit_heart_task(p_id uuid, p_profile uuid, p_task heart_task, p_path text, p_reward integer,
    p_now timestamptz default now()) → void` — 오류 `CM409`(검수 중) · `CM429`(한도) · `23505`(동시 제출)
  - 트리거 `heart_task_submissions_guard`(before update) · `heart_task_submissions_grant`(after update of status)

- [ ] **Step 1: 실패를 확인한다.** C1 Step 5 의 결과 그대로 — 23번부터 FAIL.

- [ ] **Step 2: 마이그레이션을 쓴다.** `supabase/migrations/20260928030100_create_heart_task_functions.sql`:

```sql
-- 무료로 하트 모으기 DB 함수 셋과 검수 트리거 둘. 함수를 부르는 쪽은 FastAPI(service_role) 하나다.
-- 트리거는 누가 status 를 바꾸든(FastAPI · 대시보드) 같은 규칙을 지킨다 — 승인 한 번에 하트 한 번.
-- 함수는 security invoker — service_role 이 표 권한을 다 가지고 RLS 를 우회한다(poll_feed 와 같은 모양).

-- 항목별 한 달 한도(DESIGN §8.10 표). 한도는 여기 한 곳에만 둔다 — 제출 판정과 18a 표시가 같이 본다.
create function public.heart_task_monthly_limit(p_task public.heart_task)
returns integer
language sql
immutable
set search_path = ''
as $$
  -- 모르는 항목은 0 — enum 에 항목을 더하고 여기를 잊으면 한도가 풀리지 않고 닫힌다(검토 09-28).
  select case p_task when 'everytime_post' then 1 when 'kakao_share' then 3 else 0 end;
$$;

-- 18a 세 줄. 항목마다 이번 달(한국 시간 1일 0시 시작, D4) 쓴 횟수 = 검수 중 + 승인(반려는 빠진다), 검수 중인가,
-- 이번 달 마지막 제출의 상태 · 반려 사유. 투표 줄은 이번 주(월요일 0시 시작) poll_vote 적립 횟수와 한도 3
-- (10하트 × 3 = 주 30, poll_vote_reward_due 와 같은 상한).
-- 검수 중은 달과 상관없이 본다 — 지난달 말에 낸 것이 아직 검수 중이면 부분 unique 인덱스가 새 제출을 막는다.
-- p_now 를 받는 이유는 pgTAP 이 고정 시각으로 달 경계를 확인하려고.
create function public.heart_task_status(p_profile uuid, p_now timestamptz default now())
returns table (
  task text,
  used integer,
  task_limit integer,
  reviewing boolean,
  last_status public.submission_status,
  last_reject_reason public.heart_task_reject_reason
)
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select date_trunc('month', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as month_start,
           (date_trunc('month', p_now at time zone 'Asia/Seoul') + interval '1 month') at time zone 'Asia/Seoul'
             as month_end,
           date_trunc('week', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as week_start
  )
  select t.task::text,
         (select count(*) from public.heart_task_submissions s
           where s.profile_id = p_profile and s.task = t.task and s.status in ('submitted', 'approved')
             and s.created_at >= b.month_start and s.created_at < b.month_end)::integer,
         public.heart_task_monthly_limit(t.task),
         exists (select 1 from public.heart_task_submissions s
                  where s.profile_id = p_profile and s.task = t.task and s.status = 'submitted'),
         last.status,
         last.reject_reason
    from bounds b
   cross join unnest(enum_range(null::public.heart_task)) as t (task)
    left join lateral (
      select s.status, s.reject_reason from public.heart_task_submissions s
       where s.profile_id = p_profile and s.task = t.task
         and s.created_at >= b.month_start and s.created_at < b.month_end
       order by s.created_at desc
       limit 1
    ) last on true
  union all
  select 'poll_vote',
         (select count(*) from public.heart_transactions h
           where h.profile_id = p_profile and h.reason = 'poll_vote'
             and h.created_at >= b.week_start and h.created_at < b.week_start + interval '7 days')::integer,
         3, false, null, null
    from bounds b;
$$;

-- 18b 제출. 검수 중이면 CM409, 이번 달 한도면 CM429 — 서버가 409 · 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
-- 잠금을 두지 않는다: 같은 항목에 검수 중인 줄은 부분 unique 인덱스로 하나뿐이라, 두 요청이 동시에 "한도 안" 을 보고
-- 넣어도 두 번째는 23505 로 막힌다(서버 409).
create function public.submit_heart_task(
  p_id uuid, p_profile uuid, p_task public.heart_task, p_path text, p_reward integer,
  p_now timestamptz default now()
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_used integer;
  v_limit integer;
  v_reviewing boolean;
begin
  select s.used, s.task_limit, s.reviewing into v_used, v_limit, v_reviewing
    from public.heart_task_status(p_profile, p_now) s
   where s.task = p_task::text;

  if v_reviewing then
    raise exception 'heart task in review' using errcode = 'CM409';
  end if;
  if v_used >= v_limit then
    raise exception 'heart task monthly limit' using errcode = 'CM429';
  end if;

  -- 파일 경로가 제출 id 를 담아서 id 를 서버가 정해 넘긴다. created_at 도 판정에 쓴 시각 그대로 — 달이 어긋나지 않게.
  insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts, created_at)
  values (p_id, p_profile, p_task, p_path, p_reward, p_now);
end;
$$;

-- 검수 규칙(D1 · 통합대장 2026-09-28): 승인과 반려는 끝 상태다. 되돌리지 않는다 — 운영자 실수는 사용자가 다시 내거나
-- admin_adjust 로 보정한다. 검수가 끝난 줄에서 바뀔 수 있는 것은 60일 정리의 storage_path → null 하나뿐이다.
-- 같은 값으로 다시 저장(대시보드 재저장)은 아무것도 바꾸지 않아 통과한다.
create function public.heart_task_submissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.id, new.profile_id, new.task, new.reward_hearts, new.created_at)
     is distinct from (old.id, old.profile_id, old.task, old.reward_hearts, old.created_at) then
    raise exception 'heart task submission fields are fixed' using errcode = 'CM409';
  end if;

  if old.status = 'submitted' then
    if new.storage_path is distinct from old.storage_path then
      raise exception 'heart task proof is fixed while reviewing' using errcode = 'CM409';
    end if;
    -- 검수 시각은 DB 가 찍는다. 대시보드에서 손으로 넣은 값은 덮는다.
    new.reviewed_at := case when new.status = 'submitted' then null else now() end;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.reject_reason is distinct from old.reject_reason
     or new.reviewed_at is distinct from old.reviewed_at
     or (new.storage_path is distinct from old.storage_path and new.storage_path is not null) then
    raise exception 'heart task submission already reviewed' using errcode = 'CM409';
  end if;
  return new;
end;
$$;

create trigger heart_task_submissions_guard
  before update on public.heart_task_submissions
  for each row execute function public.heart_task_submissions_guard();

-- 승인 = 원장 + 잔액(조각 2 grant_hearts). 같은 트랜잭션이라 지급이 실패하면 승인도 되돌아간다.
-- 승인은 끝 상태라(위 guard) 한 줄에서 이 트리거는 많아야 한 번 돈다.
create function public.heart_task_submissions_grant()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform public.grant_hearts(new.profile_id, new.reward_hearts, 'free_task', new.id);
  return null;
end;
$$;

create trigger heart_task_submissions_grant
  after update of status on public.heart_task_submissions
  for each row
  when (old.status = 'submitted' and new.status = 'approved')
  execute function public.heart_task_submissions_grant();

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.heart_task_monthly_limit(public.heart_task) from public, anon, authenticated;
revoke execute on function public.heart_task_status(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.heart_task_submissions_guard() from public, anon, authenticated;
revoke execute on function public.heart_task_submissions_grant() from public, anon, authenticated;
grant execute on function public.heart_task_monthly_limit(public.heart_task) to service_role;
grant execute on function public.heart_task_status(uuid, timestamptz) to service_role;
grant execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)
  to service_role;
```

- [ ] **Step 3: 전부 통과하는지 본다.**

Run: `supabase db reset` → `supabase test db`
Expected: `heart_tasks_test.sql .. ok`(55/55), 다른 파일도 전부 ok. 실패하면 superpowers:systematic-debugging.

- [ ] **Step 4: 트리거 RED 확인(검토용).** `heart_task_submissions_guard` 의 "끝 상태" 블록(`if new.status is distinct from
  old.status ...` 줄부터 `end if;` 까지)을 잠깐 지우고 `supabase db reset` → `supabase test db` 를 돌리면 32 · 34 · 36 · 40 이
  FAIL(승인 → 반려 · 검수 뒤 경로 변경 · 반려 → 승인이 통과, 반려로 9월 사용량이 줄어 36 한도도 깨짐)이고 41 이후는 연쇄로
  스크립트가 멈춘다(09-28 코더 실측). 33 · 41(두 번 지급 · 반려 → 승인 지급)은 grant 트리거의 `when (old.status = 'submitted')`
  이 guard 없이도 막는다 — 이중 방어. 되돌리고 다시 55/55 를 확인한다.
  (search_path 고정은 53번이 본다. 클라우드 advisor 는 대장이 적용 뒤 확인.)

- [ ] **Step 5: 커밋은 campus-git 이 한다** — "함수 · 트리거", "pgTAP" 커밋. PR 본문에 위 "DB 변경 목록" 표를 넣는다.

---

# Part B — FastAPI (PR 1 이 운영 DB 에 적용된 뒤 배포)

작업 위치: PR 1 merge 뒤 같은 워크트리에서 새 main 으로 `feat/heart-tasks-server`. 파이썬은 루트 `.venv`
(`C:/Users/user/AndroidStudioProjects/campus_mate_compose/.venv/Scripts/python.exe`, bare python 은 3.14 라 pytest 없음).
`cd backend && <그 python> -m pytest tests/heart_tasks -q` 로 돌린다.

### Task B1: 목록 · 제출 · 디스코드 알림

**Files:**
- Create: `backend/app/heart_tasks/__init__.py`(빈 파일)
- Create: `backend/app/heart_tasks/repository.py`
- Create: `backend/app/heart_tasks/storage.py`
- Create: `backend/app/heart_tasks/router.py`
- Modify: `backend/app/core/errors.py`(끝에 3줄 — 공유 파일)
- Modify: `backend/app/main.py`(import 1줄 · `include_router` 1줄 — 공유 파일)
- Test: `backend/tests/heart_tasks/test_heart_tasks.py`

**Interfaces:**
- Consumes: C2 의 `rpc/heart_task_status`(`p_profile`) · `rpc/submit_heart_task`(`p_id`, `p_profile`, `p_task`, `p_path`,
  `p_reward`), `app.core.deps.get_verified_caller`, `app.student_verification.image_validation.student_id_content_type`
- Produces:
  - `HeartTaskRepository.fetch_status(profile_id: UUID) -> dict[str, dict]` · `.submit(submission_id: UUID,
    profile_id: UUID, task: str, path: str, reward: int) -> None` (B2 가 `.fetch_expired_proofs` · `.clear_proof_paths` 를 더한다)
  - `HeartProofStorage.upload(profile_id: UUID, submission_id: UUID, data: bytes, content_type: str) -> str` ·
    `.delete(paths: list[str]) -> None`(실패하면 `httpx.HTTPStatusError`)
  - `GET /heart-tasks` · `POST /heart-tasks/{task}/submissions` — 위 "API 계약"
  - `errors.HEART_TASK_IN_REVIEW` · `errors.HEART_TASK_MONTHLY_LIMIT`

- [ ] **Step 1: 실패하는 테스트를 쓴다.** `backend/tests/heart_tasks/test_heart_tasks.py`:

```python
import json
import re
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
JPEG = b"\xff\xd8\xff" + b"0" * 64
TASK_KEYS = {"task", "reward_hearts", "state", "used", "limit", "reject_reason"}


def _status(**overrides: dict) -> list[dict]:
    rows = {
        "everytime_post": {"used": 0, "task_limit": 1, "reviewing": False, "last_status": None, "last_reject_reason": None},
        "kakao_share": {"used": 0, "task_limit": 3, "reviewing": False, "last_status": None, "last_reject_reason": None},
        "poll_vote": {"used": 0, "task_limit": 3, "reviewing": False, "last_status": None, "last_reject_reason": None},
    }
    for name, changed in overrides.items():
        rows[name] = {**rows[name], **changed}
    # DB 는 순서를 약속하지 않는다(union all) — 일부러 섞어서 준다.
    return [{"task": name, **rows[name]} for name in ("poll_vote", "kakao_share", "everytime_post")]


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _backend(statuses: list[list[dict]], submit: httpx.Response | None = None,
             discord: httpx.Response | None = None) -> Callable[[httpx.Request], httpx.Response]:
    """상태 RPC 는 부를 때마다 statuses 를 하나씩 꺼낸다(마지막 것은 계속). 나머지는 경로로 가른다."""
    calls = iter(statuses)
    last: list[list[dict]] = [statuses[-1]]

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/rpc/heart_task_status"):
            last[0] = next(calls, last[0])
            return httpx.Response(200, json=last[0])
        if path.endswith("/rpc/submit_heart_task"):
            return submit or httpx.Response(204)
        if "/storage/v1/object/heart-task-proofs" in path:
            return httpx.Response(200, json={})
        if request.url.host == "discord.com":
            return discord or httpx.Response(204)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _post(client: TestClient, task: str = "everytime_post", data: bytes = JPEG):
    return client.post(f"/heart-tasks/{task}/submissions", files={"photo": ("proof.jpg", data)},
                       headers=AUTH_HEADERS)


def _storage_calls(seen: list[httpx.Request]) -> list[httpx.Request]:
    return [r for r in seen if "/storage/v1/object/heart-task-proofs" in r.url.path]


def test_list_gives_three_rows_in_fixed_order_with_six_keys():
    rows = _status(everytime_post={"reviewing": True, "used": 1}, kakao_share={"used": 3}, poll_vote={"used": 1})
    response = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS)
    assert response.status_code == 200
    tasks = response.json()["tasks"]
    assert [t["task"] for t in tasks] == ["everytime_post", "kakao_share", "poll_vote"]
    assert all(set(t) == TASK_KEYS for t in tasks)
    assert [t["state"] for t in tasks] == ["reviewing", "done", "open"]
    assert [t["reward_hearts"] for t in tasks] == [50, 25, 10]
    assert [(t["used"], t["limit"]) for t in tasks] == [(1, 1), (3, 3), (1, 3)]


def test_reject_reason_only_on_rejected_row():
    rows = _status(everytime_post={"last_status": "rejected", "last_reject_reason": "date_missing"},
                   kakao_share={"used": 1, "last_status": "approved"})
    tasks = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"]
    assert (tasks[0]["state"], tasks[0]["reject_reason"]) == ("rejected", "date_missing")
    # 한 번 승인되고 한도가 남은 단톡방은 다시 "인증하기" 다.
    assert (tasks[1]["state"], tasks[1]["reject_reason"]) == ("open", None)


def test_resubmitted_after_reject_shows_reviewing_without_old_reason():
    rows = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted"})
    task = _wire(_backend([rows])).get("/heart-tasks", headers=AUTH_HEADERS).json()["tasks"][0]
    assert (task["state"], task["reject_reason"]) == ("reviewing", None)


def test_submit_rejects_non_image_before_touching_anything():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), data=b"GIF89a" + b"0" * 64)
    assert response.status_code == 400
    assert response.json()["detail"] == errors.PHOTO_UNREADABLE
    assert seen == []


def test_submit_while_reviewing_is_409_without_upload():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status(everytime_post={"reviewing": True, "used": 1})]), seen))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.HEART_TASK_IN_REVIEW
    assert _storage_calls(seen) == []


def test_submit_at_monthly_limit_is_429_without_upload():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status(kakao_share={"used": 3})]), seen), task="kakao_share")
    assert response.status_code == 429
    assert response.json()["detail"] == errors.HEART_TASK_MONTHLY_LIMIT
    assert _storage_calls(seen) == []


def test_submit_uploads_records_and_alerts_with_ids_only():
    seen: list[httpx.Request] = []
    after = _status(everytime_post={"reviewing": True, "used": 1, "last_status": "submitted"})
    response = _post(_wire(_backend([_status(), after]), seen))

    assert response.status_code == 201
    assert response.json()["task"]["state"] == "reviewing"

    upload = _storage_calls(seen)[0]
    path = upload.url.path.split("/object/heart-task-proofs/")[1]
    match = re.fullmatch(rf"{PROFILE_ID}/([0-9a-f-]{{36}})\.jpg", path)
    assert match, path
    assert upload.headers["Content-Type"] == "image/jpeg"

    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    body = json.loads(rpc.content)
    assert body == {"p_id": match.group(1), "p_profile": PROFILE_ID, "p_task": "everytime_post",
                    "p_path": path, "p_reward": 50}

    alert = json.loads(next(r for r in seen if r.url.host == "discord.com").content)["content"]
    assert match.group(1) in alert and PROFILE_ID in alert and "everytime_post" in alert
    # 경로 · 파일 이름은 싣지 않는다(Global Constraint 6).
    assert ".jpg" not in alert and "heart-task-proofs" not in alert


def test_kakao_promises_25():
    seen: list[httpx.Request] = []
    _post(_wire(_backend([_status()]), seen), task="kakao_share")
    rpc = next(r for r in seen if r.url.path.endswith("/rpc/submit_heart_task"))
    assert json.loads(rpc.content)["p_reward"] == 25


@pytest.mark.parametrize(("code", "status", "detail"), [
    ("CM409", 409, errors.HEART_TASK_IN_REVIEW),
    ("23505", 409, errors.HEART_TASK_IN_REVIEW),
    ("CM429", 429, errors.HEART_TASK_MONTHLY_LIMIT),
])
def test_db_says_no_after_upload_then_file_is_removed(code, status, detail):
    # 먼저 본 상태는 "낼 수 있음" 인데 그사이 다른 기기가 냈다 — 올린 파일을 지워야 고아가 안 남는다.
    seen: list[httpx.Request] = []
    submit = httpx.Response(400 if code.startswith("CM") else 409, json={"code": code, "message": "x"})
    response = _post(_wire(_backend([_status()], submit=submit), seen))
    assert response.status_code == status
    assert response.json()["detail"] == detail

    upload, removal = _storage_calls(seen)
    uploaded = upload.url.path.split("/object/heart-task-proofs/")[1]
    assert removal.method == "DELETE"
    assert json.loads(removal.content) == {"prefixes": [uploaded]}


def test_discord_failure_still_201():
    after = _status(everytime_post={"reviewing": True, "used": 1})
    response = _post(_wire(_backend([_status(), after], discord=httpx.Response(500))))
    assert response.status_code == 201


def test_poll_vote_is_not_submittable():
    seen: list[httpx.Request] = []
    response = _post(_wire(_backend([_status()]), seen), task="poll_vote")
    assert response.status_code == 422
    assert seen == []
```

- [ ] **Step 2: 실패를 확인한다.**

Run: `cd backend && ../.venv/Scripts/python.exe -m pytest tests/heart_tasks/test_heart_tasks.py -q`
(워크트리에서는 루트 `.venv` 절대경로로)
Expected: FAIL — `AttributeError: module 'app.core.errors' has no attribute 'HEART_TASK_IN_REVIEW'`(수집 단계).

- [ ] **Step 3: 문구 두 줄을 넣는다(공유 파일, 허락 받은 줄만).** `backend/app/core/errors.py` 맨 끝에:

```python

# 무료로 하트 모으기
HEART_TASK_IN_REVIEW = "이미 확인 중이에요, 결과를 기다려 주세요"
HEART_TASK_MONTHLY_LIMIT = "이번 달에는 더 인증할 수 없어요"
```

- [ ] **Step 4: 저장소를 쓴다.** `backend/app/heart_tasks/repository.py`:

```python
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository


class HeartTaskRepository(PostgrestRepository):
    """무료 하트 인증. 달 경계 · 한도 · 검수 중 판정은 DB 함수 한 곳에 있다(마이그레이션 20260928030100)."""

    async def fetch_status(self, profile_id: UUID) -> dict[str, dict]:
        """항목 이름 → {used, task_limit, reviewing, last_status, last_reject_reason}. 늘 세 항목이다."""
        response = await self._post("rpc/heart_task_status", json={"p_profile": str(profile_id)})
        raise_for_status(response)
        return {row["task"]: row for row in response.json()}

    async def submit(self, submission_id: UUID, profile_id: UUID, task: str, path: str, reward: int) -> None:
        response = await self._post("rpc/submit_heart_task", json={
            "p_id": str(submission_id), "p_profile": str(profile_id), "p_task": task,
            "p_path": path, "p_reward": reward,
        })
        # CM409 = 함수가 본 검수 중, 23505 = 거의 동시에 들어온 두 번째 제출(부분 unique 인덱스) — 둘 다 "이미 확인 중".
        if error_code(response) in ("CM409", "23505"):
            raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)
        raise_for_status(response)
```

- [ ] **Step 5: 버킷 클래스를 쓴다.** `backend/app/heart_tasks/storage.py`:

```python
from uuid import UUID

import httpx

from app.core.http import raise_for_status

BUCKET = "heart-task-proofs"


class HeartProofStorage:
    """`heart-task-proofs` 비공개 버킷. 올리기 · 지우기 모두 서버가 service_role 로 한다(ERD §9).

    ponytail: student_verification/storage.py 와 모양이 같다. 같은 모양의 버킷 클래스가 셋이 되면
    버킷 이름을 받는 클래스 하나로 합친다."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}
        self._client = client

    async def upload(self, profile_id: UUID, submission_id: UUID, data: bytes, content_type: str) -> str:
        # 운영자가 대시보드에서 내려받아 여는 파일이라 확장자가 실제 형식과 맞아야 한다.
        extension = "png" if content_type == "image/png" else "jpg"
        # `{profile_id}/` 한 층 — 탈퇴 정리 배치가 폴더째 지운다(account/batch_router.py STORAGE_BUCKETS).
        path = f"{profile_id}/{submission_id}.{extension}"
        response = await self._client.post(
            f"{self._storage_url}/object/{BUCKET}/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        raise_for_status(response)
        return path

    async def delete(self, paths: list[str]) -> None:
        """여러 개를 한 번에 지운다. 실패하면 예외 — 부른 쪽이 경로를 비우지 않고 다음에 다시 지운다."""
        response = await self._client.request(
            "DELETE", f"{self._storage_url}/object/{BUCKET}", json={"prefixes": paths}, headers=self._headers,
        )
        response.raise_for_status()
```

- [ ] **Step 6: 라우터를 쓴다.** `backend/app/heart_tasks/router.py`:

```python
import logging
from typing import Literal
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core import errors
from app.core.deps import Caller, get_verified_caller
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage
from app.student_verification.image_validation import student_id_content_type

router = APIRouter()
logger = logging.getLogger(__name__)

# 제출 때 약속하는 하트(DESIGN §8.10 "초기(~100명)" 값, 계획서 D5). 100명 이후 값(30 · 20)으로 바꾸는 날 이 줄만
# 고친다 — 이미 낸 제출은 줄에 적힌 금액으로 승인된다.
REWARD_HEARTS = {"everytime_post": 50, "kakao_share": 25}
# 투표 보상은 여기서 주지 않는다(DB cast_poll_vote). 18a 에 보여 주기만 한다.
POLL_VOTE_REWARD = 10
# 18a 줄 순서(DESIGN §8.10 표).
TASK_ORDER = ("everytime_post", "kakao_share", "poll_vote")


def _state(row: dict) -> str:
    if row["reviewing"]:
        return "reviewing"
    if row["used"] >= row["task_limit"]:
        return "done"
    if row["last_status"] == "rejected":
        return "rejected"
    return "open"


def _task(name: str, row: dict) -> dict:
    state = _state(row)
    return {
        "task": name,
        "reward_hearts": REWARD_HEARTS.get(name, POLL_VOTE_REWARD),
        "state": state,
        "used": row["used"],
        "limit": row["task_limit"],
        # 반려 줄에만 싣는다. 다시 내서 검수 중이 되면 지난 사유는 보이지 않는다.
        "reject_reason": row["last_reject_reason"] if state == "rejected" else None,
    }


def _repo(caller: Caller) -> HeartTaskRepository:
    return HeartTaskRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


async def _notify_review(webhook_url: str, client: httpx.AsyncClient,
                         submission_id: UUID, profile_id: UUID, task: str) -> None:
    """학생증 재검토와 같은 채널. **번호만** 싣는다 — 사진 · 경로 · 이름은 싣지 않는다(웹훅 기록에 영구히 남는다).
    실패를 삼킨다 — 제출은 이미 끝났고, 운영자는 대시보드 목록으로도 본다."""
    content = (f"무료 하트 인증 1건 (제출: {submission_id}, 계정: {profile_id}, 항목: {task}). "
               "Supabase 대시보드 heart_task_submissions 에서 확인해 주세요.")
    try:
        response = await client.post(webhook_url, json={"content": content})
    except httpx.HTTPError:
        logger.warning("무료 하트 인증 디스코드 알림 실패 submission=%s", submission_id)
        return
    if not response.is_success:
        # raise_for_status 를 쓰지 않는다 — 그 예외 문구에는 웹훅 주소(토큰 포함)가 통째로 들어간다.
        logger.warning("무료 하트 인증 디스코드 알림 실패 status=%s submission=%s", response.status_code, submission_id)


@router.get("/heart-tasks")
async def list_heart_tasks(caller: Caller = Depends(get_verified_caller)) -> dict:
    """18a 목록. 세 줄을 늘 같은 순서로."""
    rows = await _repo(caller).fetch_status(caller.profile_id)
    return {"tasks": [_task(name, rows[name]) for name in TASK_ORDER]}


@router.post("/heart-tasks/{task}/submissions", status_code=201)
async def submit_heart_task(
    task: Literal["everytime_post", "kakao_share"],
    photo: UploadFile = File(),
    caller: Caller = Depends(get_verified_caller),
) -> dict:
    """18b 제출. 검수 중이면 409, 이번 달 한도면 429 — 둘 다 사진을 올리기 전에 먼저 본다(고아 파일을 줄이려고).
    최종 판정은 DB 함수가 다시 한다. 그 판정에서 막히면 방금 올린 파일을 지운다."""
    data = await photo.read()
    # 앱이 보낸 Content-Type 은 믿지 않는다 — 학생증과 같은 판정(10MB 초과 · jpeg/png 아님 → None).
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)

    repo = _repo(caller)
    before = (await repo.fetch_status(caller.profile_id))[task]
    if before["reviewing"]:
        raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
    if before["used"] >= before["task_limit"]:
        raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)

    settings = caller.settings
    storage = HeartProofStorage(settings.storage_url, settings.supabase_service_role_key, caller.client)
    submission_id = uuid4()
    path = await storage.upload(caller.profile_id, submission_id, data, content_type)
    try:
        await repo.submit(submission_id, caller.profile_id, task, path, REWARD_HEARTS[task])
    except Exception:
        try:
            await storage.delete([path])
        except httpx.HTTPError:
            # 경로는 남기지 않는다(Global Constraint 6) — 두 id 로 대시보드에서 찾는다.
            logger.warning("무료 하트 인증샷 되돌리기 실패(고아 파일) profile=%s submission=%s",
                           caller.profile_id, submission_id)
        raise

    await _notify_review(settings.discord_webhook_url, caller.client, submission_id, caller.profile_id, task)
    after = await repo.fetch_status(caller.profile_id)
    return {"task": _task(task, after[task])}
```

- [ ] **Step 7: 라우터를 연결한다(공유 파일, 허락 받은 줄만).** `backend/app/main.py` — import 줄은 알파벳 순 자리
  (`from app.core.deps import get_settings` 아래)에, `include_router` 는 `community_router` 줄 아래에:

```python
from app.heart_tasks.router import router as heart_tasks_router
```

```python
app.include_router(heart_tasks_router)
```

- [ ] **Step 8: 통과를 확인한다.**

Run: `cd backend && <루트 .venv python> -m pytest tests/heart_tasks/test_heart_tasks.py -q`
Expected: 13 passed(11개 함수, parametrize 3개 포함).

Run: `cd backend && <루트 .venv python> -m pytest -q`
Expected: 전부 PASS(기준선 수 + 13).

- [ ] **Step 9: 커밋은 campus-git 이 한다** — "저장소 · 버킷", "라우터 · 문구 · 연결", "테스트" 로 나눈다.

### Task B2: 60일 지난 인증샷 정리

**Files:**
- Create: `backend/app/heart_tasks/cleanup.py`
- Modify: `backend/app/heart_tasks/repository.py`(메서드 2개 추가)
- Modify: `backend/app/account/batch_router.py`(공유 파일 — Step 5 의 줄만, 그때 대장 허락)
- Test: `backend/tests/heart_tasks/test_proof_cleanup.py`

**Interfaces:**
- Consumes: B1 의 `HeartTaskRepository` · `HeartProofStorage.delete(paths)`
- Produces:
  - `HeartTaskRepository.fetch_expired_proofs(reviewed_before: datetime, limit: int) -> list[dict]`(`id` · `storage_path`)
  - `HeartTaskRepository.clear_proof_paths(submission_ids: list[str]) -> None`
  - `app.heart_tasks.cleanup.purge_reviewed_proofs(repo, storage, now: datetime) -> int`(지운 개수, 실패면 0)
  - `/batch/cleanup` 응답에 `"deleted_heart_proofs": int` 한 칸

- [ ] **Step 1: 실패하는 테스트를 쓴다.** `backend/tests/heart_tasks/test_proof_cleanup.py`:

```python
import json
from datetime import datetime, timedelta

import httpx

from app.core.time import SEOUL
from app.heart_tasks.cleanup import purge_reviewed_proofs
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage

NOW = datetime(2026, 12, 1, 4, 0, tzinfo=SEOUL)
ROWS = [{"id": "a1", "storage_path": "p1/a1.jpg"}, {"id": "a2", "storage_path": "p2/a2.png"}]


def _parts(handler, seen: list[httpx.Request]):
    def wrapped(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)
    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return (HeartTaskRepository("https://x.supabase.co/rest/v1", "service-key", client),
            HeartProofStorage("https://x.supabase.co/storage/v1", "service-key", client))


def _handler(rows: list[dict], delete_status: int = 200):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET" and request.url.path.endswith("/heart_task_submissions"):
            return httpx.Response(200, json=rows)
        if request.method == "DELETE" and request.url.path.endswith("/object/heart-task-proofs"):
            return httpx.Response(delete_status, json=[])
        if request.method == "PATCH" and request.url.path.endswith("/heart_task_submissions"):
            return httpx.Response(204)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


async def test_deletes_files_first_then_clears_paths():
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler(ROWS), seen), NOW) == 2

    methods = [r.method for r in seen]
    assert methods == ["GET", "DELETE", "PATCH"]
    assert json.loads(seen[1].content) == {"prefixes": ["p1/a1.jpg", "p2/a2.png"]}
    assert seen[2].url.params["id"] == "in.(a1,a2)"
    assert json.loads(seen[2].content) == {"storage_path": None}


async def test_asks_only_for_rows_reviewed_60_days_ago_with_a_file():
    seen: list[httpx.Request] = []
    await purge_reviewed_proofs(*_parts(_handler([]), seen), NOW)
    params = seen[0].url.params
    assert params["reviewed_at"] == f"lt.{(NOW - timedelta(days=60)).isoformat()}"
    assert params["storage_path"] == "not.is.null"
    assert params["select"] == "id,storage_path"


async def test_nothing_expired_touches_nothing_else():
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler([]), seen), NOW) == 0
    assert [r.method for r in seen] == ["GET"]


async def test_file_delete_failure_keeps_paths_for_tomorrow():
    # 경로를 먼저 비우면 파일을 다시 찾을 길이 없다 — 삭제가 실패하면 PATCH 하지 않는다.
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler(ROWS, delete_status=500), seen), NOW) == 0
    assert "PATCH" not in [r.method for r in seen]
```

- [ ] **Step 2: 실패를 확인한다.**

Run: `cd backend && <루트 .venv python> -m pytest tests/heart_tasks/test_proof_cleanup.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.heart_tasks.cleanup'`.

- [ ] **Step 3: 저장소에 두 메서드를 더한다.** `backend/app/heart_tasks/repository.py` — 맨 위 import 에
  `from datetime import datetime` 을 넣고, 클래스 끝에:

```python
    async def fetch_expired_proofs(self, reviewed_before: datetime, limit: int) -> list[dict]:
        """검수가 reviewed_before 보다 전에 끝났고 파일이 아직 남은 줄(D6 60일 정리)."""
        response = await self._get("heart_task_submissions", params={
            "select": "id,storage_path",
            "reviewed_at": f"lt.{reviewed_before.isoformat()}",
            "storage_path": "not.is.null",
            "order": "reviewed_at",
            "limit": str(limit),
        })
        raise_for_status(response)
        return response.json()

    async def clear_proof_paths(self, submission_ids: list[str]) -> None:
        """파일을 지운 줄의 경로를 비운다. 검수 끝난 줄에서 허락된 유일한 변경이다(C2 guard)."""
        response = await self._patch(
            "heart_task_submissions",
            params={"id": f"in.({','.join(submission_ids)})"},
            json={"storage_path": None},
        )
        raise_for_status(response)
```

- [ ] **Step 4: 정리 함수를 쓴다.** `backend/app/heart_tasks/cleanup.py`:

```python
import logging
from datetime import datetime, timedelta

from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage

logger = logging.getLogger(__name__)

# 검수가 끝나고 이만큼 지나면 인증샷을 지운다(계획서 D6). 단톡방 캡처에는 다른 학생 이름 · 대화가 찍힌다 —
# 60일이면 운영자가 지난달 캡처와 비교할 수 있다.
PROOF_RETENTION = timedelta(days=60)
# ponytail: 하루 500장. 남은 것은 다음 날 이어서 지운다 — 하루 검수가 이보다 많아지면 올린다.
PROOF_CLEANUP_LIMIT = 500


async def purge_reviewed_proofs(repo: HeartTaskRepository, storage: HeartProofStorage, now: datetime) -> int:
    """매일 04:00 `/batch/cleanup` 이 부른다. 지운 개수를 돌려주고, 멱등이다 — 다시 돌리면 0이다.

    파일을 먼저 지우고 경로를 나중에 비운다. 반대 순서면 비운 뒤 삭제가 실패할 때 파일을 다시 찾을 길이 없다.
    파일은 지웠는데 비우기가 실패하면 내일 같은 파일을 다시 지운다(없는 파일 삭제는 오류가 아니다)."""
    try:
        rows = await repo.fetch_expired_proofs(now - PROOF_RETENTION, PROOF_CLEANUP_LIMIT)
        if not rows:
            return 0
        await storage.delete([row["storage_path"] for row in rows])
        await repo.clear_proof_paths([row["id"] for row in rows])
    except Exception:
        # 계정 · 신고 정리를 멈추지 않는다. 내일 다시 고른다. 경로는 로그에 남기지 않는다.
        logger.warning("무료 하트 인증샷 정리 건너뜀")
        return 0
    return len(rows)
```

- [ ] **Step 5: 정리 배치에 붙인다(공유 파일 — 대장에게 아래 줄 그대로 허락받은 뒤).** `backend/app/account/batch_router.py`:
  - import 3줄(기존 import 블록의 알파벳 순 자리):

```python
from app.heart_tasks.cleanup import purge_reviewed_proofs
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage
```

  - `STORAGE_BUCKETS` 한 줄(탈퇴 30일 뒤 폴더째 — ERD 271줄):

```python
STORAGE_BUCKETS = ("avatars", "profile-photos", "student-id-temp", "heart-task-proofs")
```

  - `run_cleanup_batch` 의 `return await run_cleanup(...)` 를 아래로 바꾼다(`run_cleanup` 시그니처와 기존 테스트는 그대로):

```python
    result = await run_cleanup(
        AccountRepository(settings.postgrest_url, key, client), SupabaseAdmin(settings, client), now
    )
    # ⑤ 검수 끝나고 60일 지난 무료 하트 인증샷(heart_tasks/cleanup.py).
    result["deleted_heart_proofs"] = await purge_reviewed_proofs(
        HeartTaskRepository(settings.postgrest_url, key, client),
        HeartProofStorage(settings.storage_url, key, client), now,
    )
    return result
```

- [ ] **Step 6: 통과를 확인한다.**

Run: `cd backend && <루트 .venv python> -m pytest tests/heart_tasks tests/account -q`
Expected: heart_tasks 17 passed, account 기존 전부 PASS(STORAGE_BUCKETS 를 세는 테스트가 있으면 그 기대값 4 로 — 있으면
그 줄도 공유 파일 요청에 넣는다). 전체 `pytest -q` PASS.

- [ ] **Step 7: 커밋은 campus-git 이 한다** — "60일 정리", "정리 배치 연결" 로 나눈다.

---

# Part A — Flutter (가짜 저장소로 PR 2 와 나란히, 대장 허락 시)

작업 위치: `feat/heart-tasks-app`(PR 1 merge 뒤 새 main 에서 새 워크트리 — 이름은 그때 대장과 맞춘다). `cd frontend` 뒤
`flutter test test/billing` · `flutter analyze`. **같은 워크트리에서 `flutter test` 를 두 개 동시에 돌리지 않는다.
`dart format` 을 돌리지 않는다.** 로컬 DB 는 쓰지 않는다. 화면 값은 위 "화면 대조표" 가 기준이다.

### Task A1: 모델 · 저장소 · 가짜 저장소

**Files:**
- Create: `frontend/lib/billing/model/heart_task.dart` · `heart_task_repository.dart` · `http_heart_task_repository.dart` ·
  `heart_task_repository_provider.dart`
- Test: `frontend/test/billing/model/fake_heart_task_repository.dart` · `heart_task_test.dart` · `http_heart_task_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient.send` · `ApiClient.sendMultipart`(`core/http/api_client.dart`), `apiClientProvider`, `Result` · `Success` · `FailureResult`
- Produces: `HeartTaskKind { everytimePost, kakaoShare, pollVote }`(`code`, `needsProof`, `tryParse`),
  `HeartTaskState { open, reviewing, done, rejected }`, `HeartTaskRejectReason { dateMissing, notVerified, reused }`(`code`, `label`, `tryParse`),
  `HeartTask(kind, rewardHearts, state, used, limit, rejectReason)` + `fromJson`,
  `HeartTaskRepository.fetchTasks() → Future<Result<List<HeartTask>>>` · `submit(HeartTaskKind, File) → Future<Result<HeartTask>>`,
  `heartTaskRepositoryProvider`, 테스트용 `FakeHeartTaskRepository` · `sampleHeartTasks({everytime, everytimeReason})`

- [ ] **Step 1: 모델 테스트를 쓴다.** `frontend/test/billing/model/heart_task_test.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 한 줄을 읽는다', () {
    final task = HeartTask.fromJson({
      'task': 'everytime_post',
      'reward_hearts': 50,
      'state': 'rejected',
      'used': 0,
      'limit': 1,
      'reject_reason': 'date_missing',
    });

    expect(task.kind, HeartTaskKind.everytimePost);
    expect(task.rewardHearts, 50);
    expect(task.state, HeartTaskState.rejected);
    expect(task.limit, 1);
    expect(task.rejectReason, HeartTaskRejectReason.dateMissing);
    expect(task.rejectReason!.label, '날짜가 안 보여요');
  });

  test('사유가 없거나 모르는 값이면 null 이다', () {
    expect(HeartTaskRejectReason.tryParse(null), isNull);
    expect(HeartTaskRejectReason.tryParse('blurry'), isNull);
  });

  test('모르는 항목 이름은 읽지 못한다 — ApiClient 가 알 수 없는 오류로 바꾼다', () {
    expect(
      () => HeartTask.fromJson({'task': 'x', 'reward_hearts': 1, 'state': 'open', 'used': 0, 'limit': 1}),
      throwsA(anything),
    );
  });

  test('인증샷을 내는 항목은 둘뿐이다', () {
    expect(HeartTaskKind.values.where((kind) => kind.needsProof), [HeartTaskKind.everytimePost, HeartTaskKind.kakaoShare]);
    expect(HeartTaskKind.tryParse('kakao_share'), HeartTaskKind.kakaoShare);
    expect(HeartTaskKind.tryParse('nope'), isNull);
  });
}
```

- [ ] **Step 2: 실패를 확인한다.** Run: `flutter test test/billing/model/heart_task_test.dart` — Expected: FAIL(`heart_task.dart` 없음).

- [ ] **Step 3: 모델을 쓴다.** `frontend/lib/billing/model/heart_task.dart`:

```dart
/// 18a 한 줄의 항목. [code] 는 서버 값 그대로다.
enum HeartTaskKind {
  everytimePost('everytime_post'),
  kakaoShare('kakao_share'),
  pollVote('poll_vote');

  const HeartTaskKind(this.code);

  final String code;

  /// 인증샷을 내는 항목인가. 투표 줄은 커뮤니티 탭에서 투표하면 저절로 쌓인다.
  bool get needsProof => this != pollVote;

  static HeartTaskKind? tryParse(String? code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// 18a 상태 넷(DESIGN §8.10). 판정은 서버가 한다(계획서 "API 계약").
enum HeartTaskState { open, reviewing, done, rejected }

/// 운영자가 고르는 반려 사유(계획서 D3). [label] 은 18b-2 "반려 사유: …" 뒤에 붙는다.
enum HeartTaskRejectReason {
  dateMissing('date_missing', '날짜가 안 보여요'),
  notVerified('not_verified', '게시글·공유가 확인되지 않아요'),
  reused('reused', '이미 쓴 캡처예요');

  const HeartTaskRejectReason(this.code, this.label);

  final String code;
  final String label;

  static HeartTaskRejectReason? tryParse(String? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

/// `GET /heart-tasks` 의 한 줄.
class HeartTask {
  const HeartTask({
    required this.kind,
    required this.rewardHearts,
    required this.state,
    required this.used,
    required this.limit,
    this.rejectReason,
  });

  final HeartTaskKind kind;
  final int rewardHearts;
  final HeartTaskState state;

  /// 이번 달(투표는 이번 주) 쓴 횟수. 화면에는 보이지 않는다(대장 09-28) — 서버 판정 확인용으로만 둔다.
  final int used;
  final int limit;

  /// `state == rejected` 일 때만 있다.
  final HeartTaskRejectReason? rejectReason;

  /// 모르는 항목 · 상태면 던진다 — `ApiClient.send` 가 받아서 알 수 없는 오류로 바꾼다.
  factory HeartTask.fromJson(Map<String, dynamic> json) {
    return HeartTask(
      kind: HeartTaskKind.tryParse(json['task'] as String) ?? (throw FormatException('heart task ${json['task']}')),
      rewardHearts: json['reward_hearts'] as int,
      state: HeartTaskState.values.byName(json['state'] as String),
      used: json['used'] as int,
      limit: json['limit'] as int,
      rejectReason: HeartTaskRejectReason.tryParse(json['reject_reason'] as String?),
    );
  }
}
```

- [ ] **Step 4: 통과를 확인한다.** Run: `flutter test test/billing/model/heart_task_test.dart` — Expected: 4 passed.

- [ ] **Step 5: 저장소 테스트를 쓴다.** `frontend/test/billing/model/http_heart_task_repository_test.dart`(모양은
  `test/auth/model/http_student_verification_repository_test.dart` 와 같다):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/http_heart_task_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

Map<String, Object?> _task(String code, String state, {int reward = 25, int limit = 3, String? reason}) => {
      'task': code,
      'reward_hearts': reward,
      'state': state,
      'used': 0,
      'limit': limit,
      'reject_reason': reason,
    };

void main() {
  late MockGoTrueClient auth;
  late Directory tempDir;
  late File photo;

  setUp(() async {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    tempDir = Directory.systemTemp.createTempSync('heart_task_test');
    photo = File('${tempDir.path}/proof.jpg');
    await photo.writeAsBytes([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  HttpHeartTaskRepository build(http.Client client) => HttpHeartTaskRepository(ApiClient('https://api.test', client, auth));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  test('목록은 GET /heart-tasks 의 세 줄을 순서대로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/heart-tasks');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return json({
        'tasks': [
          _task('everytime_post', 'reviewing', reward: 50, limit: 1),
          _task('kakao_share', 'done'),
          _task('poll_vote', 'open', reward: 10),
        ],
      });
    });

    final result = await build(client).fetchTasks();

    final tasks = result.when(onSuccess: (tasks) => tasks, onFailure: (_) => <HeartTask>[]);
    expect(tasks.map((task) => task.kind), HeartTaskKind.values);
    expect(tasks.map((task) => task.state), [HeartTaskState.reviewing, HeartTaskState.done, HeartTaskState.open]);
  });

  test('제출은 항목 경로로 photo 칸 multipart 를 보내고 새 줄을 돌려준다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.test/heart-tasks/kakao_share/submissions');
      expect(request.headers['content-type'], startsWith('multipart/form-data'));
      // 본문에 JPEG 바이트(0xFF)가 섞여 utf8 로는 못 읽는다.
      expect(latin1.decode(request.bodyBytes), contains('name="photo"'));
      return json({'task': _task('kakao_share', 'reviewing')}, 201);
    });

    final result = await build(client).submit(HeartTaskKind.kakaoShare, photo);

    expect(result.when(onSuccess: (task) => task.state, onFailure: (_) => null), HeartTaskState.reviewing);
  });

  test('월 한도 429 는 RateLimitedFailure 로 온다 — 문구는 ViewModel 이 바꾼다', () async {
    final client = MockClient((request) async => json({'detail': '이번 달에는 더 인증할 수 없어요'}, 429));

    final result = await build(client).submit(HeartTaskKind.everytimePost, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<RateLimitedFailure>());
  });

  test('검수 중 409 는 서버 문구를 그대로 보여 준다', () async {
    final client = MockClient((request) async => json({'detail': '이미 확인 중이에요, 결과를 기다려 주세요'}, 409));

    final result = await build(client).submit(HeartTaskKind.everytimePost, photo);

    expect(
      result.when(onSuccess: (_) => '', onFailure: (failure) => failure.toDisplayMessage()),
      '이미 확인 중이에요, 결과를 기다려 주세요',
    );
  });

  test('201 인데 본문 모양이 다르면 알 수 없는 오류다(예외가 Result 밖으로 튀지 않는다)', () async {
    final client = MockClient((request) async => json({'unexpected': true}, 201));

    final result = await build(client).submit(HeartTaskKind.kakaoShare, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<UnknownFailure>());
  });
}
```

- [ ] **Step 6: 실패를 확인한다.** Run: `flutter test test/billing/model/http_heart_task_repository_test.dart` — Expected: FAIL(파일 없음).

- [ ] **Step 7: 저장소를 쓴다.**

`frontend/lib/billing/model/heart_task_repository.dart`:

```dart
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/common/result.dart';

/// 무료로 하트 모으기(18a · 18b)가 쓰는 서버 호출 전부.
abstract interface class HeartTaskRepository {
  /// 늘 세 줄 — 에브리타임 · 단톡방 · 투표 순.
  Future<Result<List<HeartTask>>> fetchTasks();

  /// [photo] 는 압축한 JPEG. 성공하면 그 항목의 새 줄(보통 검수 중)을 돌려준다.
  Future<Result<HeartTask>> submit(HeartTaskKind kind, File photo);
}
```

`frontend/lib/billing/model/http_heart_task_repository.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [HeartTaskRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `sendAuthorizedRequest` 가 한다.
class HttpHeartTaskRepository implements HeartTaskRepository {
  const HttpHeartTaskRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<HeartTask>>> fetchTasks() => _api.send(
        'GET',
        '/heart-tasks',
        (body) => ((body as Map<String, dynamic>)['tasks'] as List<dynamic>)
            .map((item) => HeartTask.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  /// 인증샷은 multipart 라 JSON 지름길([ApiClient.send])을 쓰지 못한다.
  @override
  Future<Result<HeartTask>> submit(HeartTaskKind kind, File photo) async {
    final result = await _api.sendMultipart('/heart-tasks/${kind.code}/submissions', const {}, photo.path);
    return result.when(
      onSuccess: (response) {
        // ApiClient.send 와 같은 이유 — 약속과 다른 본문의 캐스트 오류가 Result 밖으로 튀면 화면이 멈춘다.
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return Success(HeartTask.fromJson(body['task'] as Map<String, dynamic>));
        } catch (_) {
          return const FailureResult<HeartTask>(UnknownFailure());
        }
      },
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
```

`frontend/lib/billing/model/heart_task_repository_provider.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/billing/model/http_heart_task_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 18a · 18b 가 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final heartTaskRepositoryProvider = Provider<HeartTaskRepository>((ref) {
  return HttpHeartTaskRepository(ref.read(apiClientProvider));
});
```

- [ ] **Step 8: 가짜 저장소를 쓴다.** `frontend/test/billing/model/fake_heart_task_repository.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/common/result.dart';

/// pen 18a 세 줄(에브리타임 검수중 · 단톡방 완료 · 투표 미완료)과 같은 값. [everytime] 으로 첫 줄 상태만 바꾼다.
List<HeartTask> sampleHeartTasks({
  HeartTaskState everytime = HeartTaskState.reviewing,
  HeartTaskRejectReason? everytimeReason,
}) {
  return [
    HeartTask(
      kind: HeartTaskKind.everytimePost,
      rewardHearts: 50,
      state: everytime,
      used: everytime == HeartTaskState.rejected || everytime == HeartTaskState.open ? 0 : 1,
      limit: 1,
      rejectReason: everytimeReason,
    ),
    const HeartTask(kind: HeartTaskKind.kakaoShare, rewardHearts: 25, state: HeartTaskState.done, used: 3, limit: 3),
    const HeartTask(kind: HeartTaskKind.pollVote, rewardHearts: 10, state: HeartTaskState.open, used: 0, limit: 3),
  ];
}

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeHeartTaskRepository implements HeartTaskRepository {
  Result<List<HeartTask>> tasks = Success(sampleHeartTasks());
  Result<HeartTask> submitResult = const Success(
    HeartTask(kind: HeartTaskKind.everytimePost, rewardHearts: 50, state: HeartTaskState.reviewing, used: 1, limit: 1),
  );

  int fetchCount = 0;
  final List<(HeartTaskKind, String)> submitted = [];

  /// 채워 두면 제출이 이것이 끝날 때까지 멈춘다 — 보내는 중에 한 번 더 누르는 상황용.
  Completer<void>? holdSubmit;

  @override
  Future<Result<List<HeartTask>>> fetchTasks() async {
    fetchCount++;
    return tasks;
  }

  @override
  Future<Result<HeartTask>> submit(HeartTaskKind kind, File photo) async {
    submitted.add((kind, photo.path));
    await holdSubmit?.future;
    return submitResult;
  }
}
```

- [ ] **Step 9: 통과를 확인한다.** Run: `flutter test test/billing/model` — Expected: 9 passed. `flutter analyze lib/billing test/billing` 0.

### Task A2: ViewModel 둘(18a 목록 · 18b 제출)

**Files:**
- Create: `frontend/lib/billing/viewmodel/heart_tasks_ui_state.dart` · `heart_tasks_view_model.dart` ·
  `heart_task_submit_ui_state.dart` · `heart_task_submit_view_model.dart`
- Test: `frontend/test/billing/viewmodel/heart_task_view_models_test.dart`

**Interfaces:**
- Consumes: A1 전부, `imageCompressorProvider`(`auth/model/image_compressor_provider.dart` — 학생증 · 사진과 같은 압축),
  테스트용 `FakeImageCompressor`(`test/auth/model/fake_image_compressor.dart`)
- Produces: `heartTasksViewModelProvider`(autoDispose, `HeartTasksUiState{isLoading, tasks, errorMessage}`),
  `heartTaskSubmitViewModelProvider`(autoDispose, `HeartTaskSubmitUiState{photo, isSubmitting, errorMessage, submitted, canSubmit}`),
  `HeartTaskSubmitViewModel.pickFromGallery`(테스트 훅) · `pickPhoto()` · `submit(HeartTaskKind)`,
  문구 `heartTaskMonthlyLimitMessage` · `heartTaskPhotoUnreadableMessage`

- [ ] **Step 1: 실패하는 테스트를 쓴다.** `frontend/test/billing/viewmodel/heart_task_view_models_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;
  late FakeImageCompressor compressor;
  late ProviderContainer container;
  final photo = File('picked.jpg');

  setUp(() {
    repository = FakeHeartTaskRepository();
    compressor = FakeImageCompressor();
    container = ProviderContainer(overrides: [
      heartTaskRepositoryProvider.overrideWithValue(repository),
      imageCompressorProvider.overrideWithValue(compressor),
    ]);
    addTearDown(container.dispose);
  });

  /// autoDispose 라 듣는 쪽이 있어야 살아 있다. 갤러리는 늘 [photo] 를 고른 것으로 한다.
  HeartTaskSubmitViewModel submitViewModel() {
    container.listen(heartTaskSubmitViewModelProvider, (_, _) {});
    return container.read(heartTaskSubmitViewModelProvider.notifier)..pickFromGallery = () async => photo;
  }

  test('18a 는 처음 불러오는 중이고, 읽으면 서버 세 줄이다', () async {
    container.listen(heartTasksViewModelProvider, (_, _) {});
    expect(container.read(heartTasksViewModelProvider).isLoading, isTrue);

    await pumpEventQueue();

    final state = container.read(heartTasksViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.tasks.map((task) => task.kind), HeartTaskKind.values);
  });

  test('18a 읽기가 실패하면 문구를 둔다', () async {
    repository.tasks = const FailureResult(NetworkFailure());
    container.listen(heartTasksViewModelProvider, (_, _) {});

    await pumpEventQueue();

    expect(container.read(heartTasksViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('사진을 고르지 않고 닫으면 아무것도 바뀌지 않는다', () async {
    final viewModel = submitViewModel()..pickFromGallery = () async => null;

    await viewModel.pickPhoto();

    expect(container.read(heartTaskSubmitViewModelProvider).photo, isNull);
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isFalse);
  });

  test('제출이 성공하면 압축본을 올리고 submitted 가 되며 18a 목록을 다시 읽는다', () async {
    container.listen(heartTasksViewModelProvider, (_, _) {});
    await pumpEventQueue();
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isTrue);
    await viewModel.submit(HeartTaskKind.everytimePost);
    await pumpEventQueue();

    expect(compressor.compressedSources, [photo]);
    expect(repository.submitted, [(HeartTaskKind.everytimePost, photo.path)]);
    expect(container.read(heartTaskSubmitViewModelProvider).submitted, isTrue);
    expect(repository.fetchCount, 2);
  });

  test('월 한도 429 는 공용 문구가 아니라 월 한도 문구다', () async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    final state = container.read(heartTaskSubmitViewModelProvider);
    expect(state.errorMessage, heartTaskMonthlyLimitMessage);
    expect(state.submitted, isFalse);
    expect(state.photo, photo);
  });

  test('검수 중 409 는 서버 문구 그대로다', () async {
    repository.submitResult = const FailureResult(ServerRejectedFailure('이미 확인 중이에요, 결과를 기다려 주세요'));
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, '이미 확인 중이에요, 결과를 기다려 주세요');
  });

  test('압축이 사진을 못 읽으면 올리지 않고 사진 문구를 둔다', () async {
    compressor.nextError = Exception('unreadable');
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    expect(repository.submitted, isEmpty);
    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, heartTaskPhotoUnreadableMessage);
  });

  test('보내는 중에 한 번 더 눌러도 한 번만 올린다', () async {
    repository.holdSubmit = Completer<void>();
    final viewModel = submitViewModel();
    await viewModel.pickPhoto();

    final first = viewModel.submit(HeartTaskKind.kakaoShare);
    await pumpEventQueue();
    expect(container.read(heartTaskSubmitViewModelProvider).isSubmitting, isTrue);
    await viewModel.submit(HeartTaskKind.kakaoShare);
    repository.holdSubmit!.complete();
    await first;

    expect(repository.submitted, hasLength(1));
  });
}
```

- [ ] **Step 2: 실패를 확인한다.** Run: `flutter test test/billing/viewmodel` — Expected: FAIL(파일 없음).

- [ ] **Step 3: 상태 · ViewModel 을 쓴다.**

`frontend/lib/billing/viewmodel/heart_tasks_ui_state.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task.dart';

/// 18a 무료로 하트 모으기의 상태. 읽기가 끝나면 늘 새로 만든다(바꿀 칸이 없다).
class HeartTasksUiState {
  const HeartTasksUiState({this.isLoading = true, this.tasks = const [], this.errorMessage});

  final bool isLoading;
  final List<HeartTask> tasks;
  final String? errorMessage;
}
```

`frontend/lib/billing/viewmodel/heart_tasks_view_model.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 18a 에 들어올 때마다 새로 읽는다(autoDispose). 제출이 성공하면 [HeartTaskSubmitViewModel] 이 이 provider 를
/// 버려 다시 읽게 한다 — 18c 에서 뒤로 오면 "검수중" 이 보인다.
final heartTasksViewModelProvider =
    NotifierProvider.autoDispose<HeartTasksViewModel, HeartTasksUiState>(HeartTasksViewModel.new);

class HeartTasksViewModel extends Notifier<HeartTasksUiState> {
  @override
  HeartTasksUiState build() {
    Future.microtask(_load);
    return const HeartTasksUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(heartTaskRepositoryProvider).fetchTasks();
    // 응답을 기다리는 동안 18a 를 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (tasks) => HeartTasksUiState(isLoading: false, tasks: tasks),
      onFailure: (failure) => HeartTasksUiState(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}
```

`frontend/lib/billing/viewmodel/heart_task_submit_ui_state.dart`:

```dart
import 'dart:io';

/// 18b 인증샷 제출의 상태. 동작 하나가 끝날 때마다 새로 만든다 — [errorMessage] 는 그 한 번에만 붙는다.
class HeartTaskSubmitUiState {
  const HeartTaskSubmitUiState({this.photo, this.isSubmitting = false, this.errorMessage, this.submitted = false});

  final File? photo;
  final bool isSubmitting;

  /// 화면이 토스트로 한 번 띄운다.
  final String? errorMessage;

  /// 성공하면 화면이 18c 로 넘어간다.
  final bool submitted;

  bool get canSubmit => photo != null && !isSubmitting && !submitted;
}
```

`frontend/lib/billing/viewmodel/heart_task_submit_view_model.dart`:

```dart
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 월 한도 429. 공용 429 문구("잠시 후 다시 시도")는 달이 바뀌어야 풀리는 한도와 맞지 않아
/// 서버 `errors.HEART_TASK_MONTHLY_LIMIT` 과 같은 문구를 여기 둔다(17b 하루 상한 · 신고 상한과 같은 처리).
const String heartTaskMonthlyLimitMessage = '이번 달에는 더 인증할 수 없어요';

/// 압축이 사진을 못 읽었을 때. 서버 `errors.PHOTO_UNREADABLE` 과 같은 문구.
const String heartTaskPhotoUnreadableMessage = '사진을 다시 확인해 주세요';

/// image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어 훅으로 갈아끼운다(3b 와 같다).
Future<File?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

final heartTaskSubmitViewModelProvider =
    NotifierProvider.autoDispose<HeartTaskSubmitViewModel, HeartTaskSubmitUiState>(HeartTaskSubmitViewModel.new);

/// 18b · 18b-2. 사진 고르기 → 압축 → 올리기.
class HeartTaskSubmitViewModel extends Notifier<HeartTaskSubmitUiState> {
  /// 테스트에서 갤러리 호출을 대체하기 위한 훅. 기본은 실제 image_picker.
  Future<File?> Function() pickFromGallery = _pickFromGallery;

  @override
  HeartTaskSubmitUiState build() => const HeartTaskSubmitUiState();

  /// 고르지 않고 닫으면 아무것도 하지 않는다. 보내는 중에는 사진을 바꾸지 않는다.
  Future<void> pickPhoto() async {
    if (state.isSubmitting) return;
    final picked = await pickFromGallery();
    if (picked == null || !ref.mounted) return;
    state = HeartTaskSubmitUiState(photo: picked);
  }

  Future<void> submit(HeartTaskKind kind) async {
    final photo = state.photo;
    if (photo == null || !state.canSubmit) return;
    state = HeartTaskSubmitUiState(photo: photo, isSubmitting: true);

    final File compressed;
    try {
      compressed = await ref.read(imageCompressorProvider).compressToJpeg(photo);
    } on Exception {
      if (!ref.mounted) return;
      state = HeartTaskSubmitUiState(photo: photo, errorMessage: heartTaskPhotoUnreadableMessage);
      return;
    }

    final result = await ref.read(heartTaskRepositoryProvider).submit(kind, compressed);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) {
        ref.invalidate(heartTasksViewModelProvider);
        return HeartTaskSubmitUiState(photo: photo, submitted: true);
      },
      onFailure: (failure) => HeartTaskSubmitUiState(
        photo: photo,
        errorMessage: failure is RateLimitedFailure ? heartTaskMonthlyLimitMessage : failure.toDisplayMessage(),
      ),
    );
  }
}
```

- [ ] **Step 4: 통과를 확인한다.** Run: `flutter test test/billing/viewmodel` — Expected: 8 passed. `flutter analyze lib/billing test/billing` 0.

### Task A3: 18a 목록과 HeartTaskRow 4상태

**Files:**
- Create: `frontend/lib/billing/view/heart_task_row.dart` · `heart_tasks_screen.dart`
- Modify: `frontend/lib/core/theme/app_icons.dart`(공유 — 아이콘 4줄, 대장 허락 뒤)
- Test: `frontend/test/billing/view/heart_tasks_screen_test.dart`

**Interfaces:**
- Consumes: A1 · A2, `AppRoutes.heartTaskSubmit` · `AppRoutes.community`(A5 Step 3 에서 상수가 생긴다 — A3 을 A5 보다 먼저
  하면 A5 Step 3 의 `app_routes.dart` 네 줄을 여기서 먼저 넣는다)
- Produces: `HeartTaskRow({task, onTap})`, `HeartTasksScreen`, `heartTaskSubmitLocation(kind, [reason])`(A4 파일에 둔다 — A3 이
  먼저면 A4 Step 3 의 그 함수 한 개를 먼저 만든다)

- [ ] **Step 1: 아이콘 4줄을 넣는다.** `frontend/lib/core/theme/app_icons.dart` 의 `AppIcons` 안, 마지막 상수 뒤에:

```dart
  /// 18a 무료로 하트 모으기 줄 아이콘(pen R99dx `Fwoqx`) · 16 설정 행(`JWxQo`).
  static const IconData megaphone = LucideIcons.megaphone;
  static const IconData share2 = LucideIcons.share2;
  static const IconData vote = LucideIcons.vote;
  static const IconData gift = LucideIcons.gift;
```

- [ ] **Step 2: 실패하는 화면 테스트를 쓴다.** `frontend/test/billing/view/heart_tasks_screen_test.dart`:

```dart
import 'dart:async';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;

  setUp(() => repository = FakeHeartTaskRepository());

  /// 설정(16)에서 18a 로 들어온 것처럼 한 번 push 한다 — 뒤로 버튼이 보이게.
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (context, state) => const Text('설정')),
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const HeartTasksScreen()),
        GoRoute(path: '${AppRoutes.heartTaskSubmit}/:task', builder: (context, state) => Text('제출 ${state.uri}')),
        GoRoute(path: AppRoutes.community, builder: (context, state) => const Text('커뮤니티')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [heartTaskRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(AppRoutes.heartTasks));
    await tester.pumpAndSettle();
  }

  testWidgets('pen 18a — 제목 · 안내 · 세 줄의 글자와 상태 칩', (tester) async {
    await pump(tester);

    expect(find.text('무료로 하트 모으기'), findsOneWidget);
    expect(find.text('초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트'), findsOneWidget);
    expect(find.text('무료로 모으기'), findsNothing);
    expect(find.text('에브리타임 홍보'), findsOneWidget);
    expect(find.text('50 · 월 1회'), findsOneWidget);
    expect(find.text('검수중'), findsOneWidget);
    expect(find.text('학교 단톡방 공유'), findsOneWidget);
    expect(find.text('25 · 월 3회'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('커뮤니티 투표'), findsOneWidget);
    expect(find.text('매일'), findsOneWidget);
    expect(find.text('10 · 주 최대 30'), findsOneWidget);
    expect(find.text('참여'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/heart-flat-vector-v3.png')), findsNWidgets(3));
  });

  testWidgets('pen 치수 — 줄 328×64 · 줄 사이 8 · 안내에서 첫 줄 24 · 칩 72×28', (tester) async {
    await pump(tester);

    final rows = find.byType(HeartTaskRow);
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(first.left, 16);
    expect(first.size, const Size(328, 64));
    expect(second.top - first.bottom, 8);
    expect(first.top - tester.getRect(find.textContaining('초기 보상 기준')).bottom, 24);
    final chip = find.ancestor(of: find.text('검수중'), matching: find.byType(ConstrainedBox)).first;
    expect(tester.getSize(chip), const Size(72, 28));
  });

  testWidgets('뒤로 누름 영역은 48 이고 아이콘은 x16 에서 시작한다', (tester) async {
    await pump(tester);

    final back = find.ancestor(of: find.byIcon(AppIcons.arrowLeft), matching: find.byType(IconButton));
    expect(tester.getSize(back), const Size(48, 48));
    expect(tester.getRect(find.byIcon(AppIcons.arrowLeft)).left, 16);
    expect(tester.getRect(find.text('무료로 하트 모으기')).left, 52);
  });

  testWidgets('미완료 인증 항목은 "인증하기" 이고 누르면 18b', (tester) async {
    repository.tasks = Success(sampleHeartTasks(everytime: HeartTaskState.open));
    await pump(tester);

    expect(find.text('인증하기'), findsOneWidget);
    await tester.tap(find.text('에브리타임 홍보'));
    await tester.pumpAndSettle();

    expect(find.text('제출 /heart-tasks/submit/everytime_post'), findsOneWidget);
  });

  testWidgets('반려 줄은 "다시 제출" 글자가 아니라 줄 전체가 눌리고 사유를 18b-2 로 넘긴다', (tester) async {
    repository.tasks = Success(
      sampleHeartTasks(everytime: HeartTaskState.rejected, everytimeReason: HeartTaskRejectReason.dateMissing),
    );
    await pump(tester);

    expect(find.text('다시 제출'), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.megaphone));
    await tester.pumpAndSettle();

    expect(find.text('제출 /heart-tasks/submit/everytime_post?reason=date_missing'), findsOneWidget);
  });

  testWidgets('검수중 · 완료 줄은 누를 수 없다', (tester) async {
    await pump(tester);

    for (final title in ['에브리타임 홍보', '학교 단톡방 공유']) {
      expect(find.ancestor(of: find.text(title), matching: find.byType(InkWell)), findsNothing);
    }
  });

  testWidgets('투표 미완료 줄을 누르면 커뮤니티 탭으로 간다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('커뮤니티 투표'));
    await tester.pumpAndSettle();

    expect(find.text('커뮤니티'), findsOneWidget);
  });

  testWidgets('누르는 줄의 잉크는 줄 자신의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);

    final label = find.text('커뮤니티 투표');
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: label, matching: find.byType(Material)).first;
    expect(tester.getSize(painter), tester.getSize(tile));
  });

  testWidgets('읽기 실패면 문구와 "다시 시도", 누르면 다시 읽는다', (tester) async {
    repository.tasks = const FailureResult(NetworkFailure());
    await pump(tester);

    expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    repository.tasks = Success(sampleHeartTasks());
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('에브리타임 홍보'), findsOneWidget);
    expect(repository.fetchCount, 2);
  });

  testWidgets('글자 2배에서도 넘침 예외가 없다(반려 줄 포함)', (tester) async {
    repository.tasks = Success(
      sampleHeartTasks(everytime: HeartTaskState.rejected, everytimeReason: HeartTaskRejectReason.reused),
    );
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('다시 제출'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 실패를 확인한다.** Run: `flutter test test/billing/view/heart_tasks_screen_test.dart` — Expected: FAIL(파일 없음).

- [ ] **Step 4: 줄을 쓴다.** `frontend/lib/billing/view/heart_task_row.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk` 18.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// pen HeartTaskRow `R99dx` — 18a 한 줄. 상태 넷: 미완료 `JQNcz` · 검수중(마스터) · 완료 `gGX34` · 반려 `w3aZL`.
/// 쓴 횟수(1/3) · "이번 주" 는 pen 에 없어 보이지 않는다(대장 09-28).
class HeartTaskRow extends StatelessWidget {
  const HeartTaskRow({required this.task, required this.onTap, super.key});

  final HeartTask task;

  /// 누를 수 있는 줄(미완료 · 반려)만 준다. 검수중 · 완료 줄은 null.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(
          // 반려 줄은 아래 선이 투명하다(pen `w3aZL`).
          bottom: BorderSide(
            color: task.state == HeartTaskState.rejected ? Colors.transparent : AppColors.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 20, color: AppColors.body),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // pen 14/600, 줄높이 속성 없음 · 렌더 20.
                    Flexible(
                      child: Text(_title, style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14)),
                    ),
                    if (task.kind == HeartTaskKind.pollVote) ...[const SizedBox(width: 6), const _DailyBadge()],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Image.asset(_heartAsset, width: 18, height: 18, semanticLabel: '하트'),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        _rewardText,
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _trailing,
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    // 잉크는 줄 자신에 그린다 — 목록을 밀어도 눌림 테두리가 제자리에 뜨지 않게(COMMON §4-2).
    return Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, child: row));
  }

  IconData get _icon => switch (task.kind) {
        HeartTaskKind.everytimePost => AppIcons.megaphone,
        HeartTaskKind.kakaoShare => AppIcons.share2,
        HeartTaskKind.pollVote => AppIcons.vote,
      };

  String get _title => switch (task.kind) {
        HeartTaskKind.everytimePost => '에브리타임 홍보',
        HeartTaskKind.kakaoShare => '학교 단톡방 공유',
        HeartTaskKind.pollVote => '커뮤니티 투표',
      };

  /// "50 · 월 1회" · "10 · 주 최대 30"(pen 글자). 하트 수 · 한도는 서버 값이다.
  String get _rewardText => task.kind == HeartTaskKind.pollVote
      ? '${task.rewardHearts} · 주 최대 ${task.rewardHearts * task.limit}'
      : '${task.rewardHearts} · 월 ${task.limit}회';

  Widget get _trailing => switch (task.state) {
        // 과제는 "인증하기"(대장 09-28, pen 인스턴스 이름 JQNcz), 투표는 pen "참여". #E5E5E5 토큰은 primaryDisabled 하나다.
        HeartTaskState.open => _Chip(
            label: task.kind.needsProof ? '인증하기' : '참여',
            background: AppColors.primaryDisabled,
            foreground: AppColors.ink,
          ),
        HeartTaskState.reviewing => const _Chip(
            icon: AppIcons.timer,
            label: '검수중',
            background: AppColors.surfaceStrong,
            foreground: AppColors.muted,
          ),
        HeartTaskState.done => const _Chip(
            icon: AppIcons.check,
            label: '완료',
            background: AppColors.primaryWash,
            foreground: AppColors.primaryText,
          ),
        HeartTaskState.rejected => Text('다시 제출', style: AppTypography.labelSmall.copyWith(color: AppColors.error)),
      };
}

/// pen Status `e2aMg` · Action `xGTbF` — 72×28 알약. 글자를 키우면 늘어난다.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.background, required this.foreground, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72, minHeight: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 12, color: foreground), const SizedBox(width: AppSpacing.xxs)],
              Text(label, style: AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// pen "매일" 배지 `Aioxz`(투표 줄만).
class _DailyBadge extends StatelessWidget {
  const _DailyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text('매일', style: AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted)),
    );
  }
}
```

- [ ] **Step 5: 화면을 쓴다.** `frontend/lib/billing/view/heart_tasks_screen.dart`:

```dart
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// pen `EJDsZ`. 초기값 기준 안내(DESIGN §8.10 표) — 줄의 하트 수는 서버 값이다.
const String _rewardNotice = '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트';

/// pen `NYgh7` 여백 [8,16,32,16].
const EdgeInsets _listPadding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl);

/// 18a 무료로 하트 모으기(pen `qyUgZ`). 설정(16)에서 들어온다.
class HeartTasksScreen extends ConsumerWidget {
  const HeartTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heartTasksViewModelProvider);
    return Scaffold(
      // pen `Q9II4` 56, 좌우 16, 간격 12, 뒤로 24. 누름 48(대장)이라 왼쪽 4 + 48 — 아이콘은 x16, 제목은 x52 그대로.
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 52,
        titleSpacing: 0,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxs),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, size: 24, color: AppColors.ink),
                ),
              )
            : null,
        title: Text(
          '무료로 하트 모으기',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.headline.copyWith(color: AppColors.ink),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, HeartTasksUiState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final errorMessage = state.errorMessage;
    if (errorMessage != null) {
      return _LoadError(message: errorMessage, onRetry: () => ref.invalidate(heartTasksViewModelProvider));
    }
    return ListView(
      padding: _listPadding,
      children: [
        Text(_rewardNotice, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        // pen 섹션 간격 8 + 빈칸 `vlmhj` 8 + 간격 8.
        const SizedBox(height: AppSpacing.lg),
        for (final (index, task) in state.tasks.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          HeartTaskRow(task: task, onTap: _onTap(context, task)),
        ],
      ],
    );
  }

  /// 누르는 줄: 인증 항목의 미완료 · 반려(→ 18b, 반려면 사유를 실어 18b-2), 투표 미완료(→ 커뮤니티 탭).
  VoidCallback? _onTap(BuildContext context, HeartTask task) {
    if (!task.kind.needsProof) {
      return task.state == HeartTaskState.open ? () => context.go(AppRoutes.community) : null;
    }
    return switch (task.state) {
      HeartTaskState.open => () => context.push(heartTaskSubmitLocation(task.kind)),
      HeartTaskState.rejected => () => context.push(heartTaskSubmitLocation(task.kind, task.rejectReason)),
      HeartTaskState.reviewing || HeartTaskState.done => null,
    };
  }
}

/// 읽기 실패. pen 에 없는 상태 — 16f 차단 목록과 같은 회색 문구에 "다시 시도" 를 붙인다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 통과를 확인한다.** Run: `flutter test test/billing/view/heart_tasks_screen_test.dart` — Expected: 10 passed.
  치수 테스트가 1~2 차이로 틀리면 pen 값표를 다시 보고 위젯을 고친다(테스트 기대값은 pen 값이다). `flutter analyze` 0.

### Task A4: 18b 인증샷 제출 · 18b-2 반려 뒤 다시 제출

**Files:**
- Create: `frontend/lib/billing/view/heart_task_submit_screen.dart`
- Test: `frontend/test/billing/view/heart_task_submit_screen_test.dart`

**Interfaces:**
- Consumes: A1 · A2, `AppToast`, `AppButton`, `AppRoutes.heartTaskSubmit` · `heartTaskPending`
- Produces: `HeartTaskSubmitScreen({required HeartTaskKind kind, HeartTaskRejectReason? rejectReason})`,
  `heartTaskSubmitLocation(HeartTaskKind kind, [HeartTaskRejectReason? reason]) → String`

- [ ] **Step 1: 실패하는 테스트를 쓴다.** `frontend/test/billing/view/heart_task_submit_screen_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;
  // 없는 파일이어도 된다 — 위젯 테스트의 가짜 시계에서는 파일을 실제로 읽지 않는다.
  final photo = File('proof.jpg');

  setUp(() => repository = FakeHeartTaskRepository());

  /// 18a 에서 들어온 것처럼 push 한다. 18c 는 글자만 있는 자리 화면.
  Future<GoRouter> pump(
    WidgetTester tester, {
    HeartTaskKind kind = HeartTaskKind.kakaoShare,
    HeartTaskRejectReason? reason,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.heartTasks,
      routes: [
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const Text('18a')),
        GoRoute(
          path: '${AppRoutes.heartTaskSubmit}/:task',
          builder: (context, state) => HeartTaskSubmitScreen(kind: kind, rejectReason: reason),
        ),
        GoRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const Text('18c')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          heartTaskRepositoryProvider.overrideWithValue(repository),
          imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(heartTaskSubmitLocation(kind, reason)));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(HeartTaskSubmitScreen)))
        .read(heartTaskSubmitViewModelProvider.notifier)
        .pickFromGallery = () async => photo;
    return router;
  }

  testWidgets('18b — 안내 · 업로더 · 꺼진 "제출하기", 반려 알림 · 에브리타임 줄은 없다', (tester) async {
    await pump(tester);

    expect(find.text('인증샷 제출'), findsOneWidget);
    expect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요'), findsOneWidget);
    expect(find.text('스크린샷 첨부하기'), findsOneWidget);
    expect(find.text('날짜가 보이게 찍어 주세요'), findsNothing);
    expect(find.textContaining('반려 사유'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.text('제출하기'), findsOneWidget);
  });

  testWidgets('에브리타임만 "날짜가 보이게 찍어 주세요" 한 줄이 붙는다(편차 6)', (tester) async {
    await pump(tester, kind: HeartTaskKind.everytimePost);

    expect(find.text('날짜가 보이게 찍어 주세요'), findsOneWidget);
  });

  testWidgets('18b-2 — 사유 알림과 "다시 제출하기", pen 배치 16 · 99 · 138 · 374', (tester) async {
    await pump(tester, reason: HeartTaskRejectReason.dateMissing);

    expect(find.text('반려 사유: 날짜가 안 보여요'), findsOneWidget);
    expect(find.text('다시 찍어 올려 주세요'), findsOneWidget);
    expect(find.text('다시 제출하기'), findsOneWidget);
    // 본문은 앱바(56) 아래에서 시작한다.
    const body = 56.0;
    final alert = find.ancestor(
      of: find.text('반려 사유: 날짜가 안 보여요'),
      matching: find.byWidgetPredicate((widget) => widget is Container && widget.color == AppColors.errorWash),
    );
    expect(tester.getRect(alert).top - body, 16);
    expect(tester.getRect(alert).height, 67);
    expect(tester.getRect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요')).top - body, 99);
    expect(tester.getRect(find.byKey(heartTaskUploaderKey)).top - body, 138);
    expect(tester.getRect(find.byKey(heartTaskUploaderKey)).height, 220);
    expect(tester.getRect(find.byType(ElevatedButton)).top - body, 374);
  });

  testWidgets('사진을 고르면 버튼이 켜지고, 제출하면 18c 로 바뀌며 뒤로 가면 18a 다', (tester) async {
    final router = await pump(tester);

    await tester.tap(find.byKey(heartTaskUploaderKey));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await tester.tap(find.text('제출하기'));
    await tester.pumpAndSettle();

    expect(find.text('18c'), findsOneWidget);
    expect(repository.submitted, [(HeartTaskKind.kakaoShare, photo.path)]);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('18a'), findsOneWidget);
  });

  testWidgets('실패하면 버튼 위에 토스트로 알리고 화면에 남는다', (tester) async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    await pump(tester);

    await tester.tap(find.byKey(heartTaskUploaderKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출하기'));
    // 토스트 타이머는 프레임을 걸지 않아 pumpAndSettle 이 기다리지 않는다.
    await tester.pumpAndSettle();

    expect(find.text(heartTaskMonthlyLimitMessage), findsOneWidget);
    expect(find.text('18c'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(heartTaskMonthlyLimitMessage), findsNothing);
  });

  testWidgets('업로더 잉크는 업로더 자신의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);

    final label = find.text('스크린샷 첨부하기');
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: label, matching: find.byType(Material)).first;
    expect(tester.getSize(painter), tester.getSize(tile));
  });

  testWidgets('글자 2배에서도 넘침 예외가 없다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, kind: HeartTaskKind.everytimePost, reason: HeartTaskRejectReason.notVerified);

    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 실패를 확인한다.** Run: `flutter test test/billing/view/heart_task_submit_screen_test.dart` — Expected: FAIL(파일 없음).

- [ ] **Step 3: 화면을 쓴다.** `frontend/lib/billing/view/heart_task_submit_screen.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const String _guide = '스크린샷을 첨부하면 확인 후 하트를 드려요';

/// 에브리타임만 붙는다(DESIGN §8.10 `review-submission`). 안내 아래 캡션 한 줄(대장 09-28 (가), 계획서 편차 6).
const String _everytimeHint = '날짜가 보이게 찍어 주세요';
const String _uploaderLabel = '스크린샷 첨부하기';
const String _retryCaption = '다시 찍어 올려 주세요';

/// 테스트가 업로더를 찾는 표식.
const Key heartTaskUploaderKey = ValueKey('heart-task-uploader');

/// 18b 경로. 반려 뒤 다시 낼 때는 사유를 `reason` 으로 실어 18b-2 알림을 띄운다.
String heartTaskSubmitLocation(HeartTaskKind kind, [HeartTaskRejectReason? reason]) => Uri(
      path: '${AppRoutes.heartTaskSubmit}/${kind.code}',
      queryParameters: reason == null ? null : {'reason': reason.code},
    ).toString();

/// 18b 인증샷 제출(pen `F15q0W`) · 18b-2 반려 뒤 다시 제출(`DMrAI`).
class HeartTaskSubmitScreen extends ConsumerStatefulWidget {
  const HeartTaskSubmitScreen({required this.kind, this.rejectReason, super.key});

  final HeartTaskKind kind;

  /// 반려 뒤 다시 내는 18b-2 면 있다 — 맨 위 알림(pen `kdibh`)과 버튼 글자가 바뀐다.
  final HeartTaskRejectReason? rejectReason;

  @override
  ConsumerState<HeartTaskSubmitScreen> createState() => _HeartTaskSubmitScreenState();
}

class _HeartTaskSubmitScreenState extends ConsumerState<HeartTaskSubmitScreen> {
  /// 04-2 사진 화면과 같은 3초.
  static const Duration _toastDuration = Duration(seconds: 3);

  String? _toast;
  Timer? _toastTimer;

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(heartTaskSubmitViewModelProvider, (previous, next) {
      if (next.submitted && previous?.submitted != true) {
        // 18b 를 18c 로 바꾼다 — 18c 에서 뒤로 가면 18a 로 돌아간다.
        context.pushReplacement(AppRoutes.heartTaskPending);
        return;
      }
      final message = next.errorMessage;
      if (message != null) _showToast(message);
    });
    final state = ref.watch(heartTaskSubmitViewModelProvider);
    final viewModel = ref.read(heartTaskSubmitViewModelProvider.notifier);
    final reason = widget.rejectReason;
    final toast = _toast;
    return Scaffold(
      // pen `k9nvth`: 17c 와 같은 규격 — 뒤로 `syyGc` 48(arrow-left 22), 제목 x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
                ),
              )
            : null,
        title: Text('인증샷 제출', style: AppTypography.navTitle),
      ),
      body: SafeArea(
        // pen `re6T6`: 세로 간격 16, 안쪽 16.
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (reason != null) ...[_RejectReasonAlert(reason: reason), const SizedBox(height: AppSpacing.md)],
            // pen `qLG9R` 16/600 #3F3F3F, 줄높이 속성 없음 · 렌더 23.
            Text(_guide, style: AppTypography.bodyStrong.copyWith(color: AppColors.body, height: 23 / 16)),
            if (widget.kind == HeartTaskKind.everytimePost) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(_everytimeHint, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            ],
            const SizedBox(height: AppSpacing.md),
            _ProofUploader(photo: state.photo, onTap: state.isSubmitting ? null : viewModel.pickPhoto),
            const SizedBox(height: AppSpacing.md),
            if (toast != null) ...[
              Center(
                child: AppToast(
                  leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                  label: toast,
                ),
              ),
              // 버튼과 간격 12(04-2 pen 실측).
              const SizedBox(height: AppSpacing.sm),
            ],
            AppButton(
              label: reason == null ? '제출하기' : '다시 제출하기',
              onPressed: state.canSubmit ? () => unawaited(viewModel.submit(widget.kind)) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 18b-2 반려 알림(pen Alert `kdibh`, 마스터 `teNRJ`). 모서리 없이 본문 폭을 채운다.
class _RejectReasonAlert extends StatelessWidget {
  const _RejectReasonAlert({required this.reason});

  final HeartTaskRejectReason reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.errorWash,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(AppIcons.alertTriangle, size: 20, color: AppColors.error),
          // pen 실측 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '반려 사유: ${reason.label}',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
                ),
                // pen 알림 높이 67 = 위아래 24 + 21 + 18 + 4.
                const SizedBox(height: AppSpacing.xxs),
                Text(_retryCaption, style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 업로더(pen `moNIO` 인스턴스 `u7vbr`). 고른 뒤에는 같은 칸에 사진을 통째로 보여 준다(DESIGN §8.10 "fit",
/// pen 에 채운 상태 없음 — 편차 3). 잉크는 업로더 자신의 Material 에 그린다(COMMON §4-2).
class _ProofUploader extends StatelessWidget {
  const _ProofUploader({required this.photo, required this.onTap});

  final File? photo;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final onTap = this.onTap;
    return Material(
      key: heartTaskUploaderKey,
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null ? null : () => unawaited(onTap()),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: photo == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(AppIcons.imagePlus, size: 32, color: AppColors.disabled),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_uploaderLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.disabled)),
                  ],
                )
              : Image.file(photo, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 통과를 확인한다.** Run: `flutter test test/billing/view/heart_task_submit_screen_test.dart` — Expected: 7 passed.
  배치 테스트가 틀리면 PNG `04_18b-2` 와 값표를 다시 보고 위젯을 고친다. `flutter analyze` 0.

### Task A5: 18c 검수 대기 · 라우트 3개

**Files:**
- Create: `frontend/lib/billing/view/heart_task_pending_screen.dart`
- Modify: `frontend/lib/core/router/app_routes.dart` · `app_router.dart`(공유 — 대장 허락 뒤, 아래 줄 그대로)
- Test: `frontend/test/billing/view/heart_task_pending_screen_test.dart`

**Interfaces:**
- Consumes: A1 `HeartTaskKind.tryParse` · `HeartTaskRejectReason.tryParse`, A3 `HeartTasksScreen`, A4 `HeartTaskSubmitScreen`
- Produces: `AppRoutes.heartTasks` · `heartTaskSubmit` · `heartTaskPending`, `HeartTaskPendingScreen`

- [ ] **Step 1: 실패하는 테스트를 쓴다.** `frontend/test/billing/view/heart_task_pending_screen_test.dart`:

```dart
import 'package:campus_mate/billing/view/heart_task_pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MaterialApp(home: HeartTaskPendingScreen()));
  }

  testWidgets('pen 18c — 마스코트 88 · 제목 · 설명 두 줄, 앱바 · 버튼 없음', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(Image)), const Size(88, 88));
    expect(find.text('확인하고 있어요'), findsOneWidget);
    expect(find.text('확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요'), findsOneWidget);
    expect(find.text('보통 영업일 1~2일 걸려요'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.getSize(find.text('확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요')).width, lessThanOrEqualTo(280));
  });

  testWidgets('내용 묶음은 화면 가운데다', (tester) async {
    await pump(tester);

    final title = tester.getRect(find.text('확인하고 있어요'));
    expect(title.center.dx, closeTo(180, 1));
  });

  testWidgets('글자 2배에서도 넘침 예외가 없다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 실패를 확인한다.** Run: `flutter test test/billing/view/heart_task_pending_screen_test.dart` — Expected: FAIL(파일 없음).

- [ ] **Step 3: 라우트를 넣는다(공유 파일 — 허락 받은 줄만).**

`frontend/lib/core/router/app_routes.dart` 의 `myProfile` 줄 아래:

```dart
  /// 무료로 하트 모으기 — 18a 목록, 18b 인증샷 제출(`/heart-tasks/submit/:task`, 반려 뒤면 `?reason=`), 18c 검수 대기
  static const String heartTasks = '/heart-tasks';
  static const String heartTaskSubmit = '/heart-tasks/submit';
  static const String heartTaskPending = '/heart-tasks/pending';
```

`frontend/lib/core/router/app_router.dart` — import 4줄(알파벳 순서 자리에):

```dart
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_pending_screen.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
```

`_slice6Routes()` 목록 끝(`partnerProfile` 라우트 뒤)에:

```dart
      GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const HeartTasksScreen()),
      GoRoute(
        path: '${AppRoutes.heartTaskSubmit}/:task',
        // 인증샷 항목이 아니면(투표 · 잘못된 값) 18a 로 돌려보낸다.
        redirect: (context, state) =>
            HeartTaskKind.tryParse(state.pathParameters['task'])?.needsProof == true ? null : AppRoutes.heartTasks,
        builder: (context, state) => HeartTaskSubmitScreen(
          kind: HeartTaskKind.tryParse(state.pathParameters['task'])!,
          rejectReason: HeartTaskRejectReason.tryParse(state.uri.queryParameters['reason']),
        ),
      ),
      GoRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const HeartTaskPendingScreen()),
```

  `_slice6Routes` 위 주석 한 줄을 "조각 6 — 16f 차단 목록(설정 아래), 14c 상대 프로필, 18a~c 무료로 하트 모으기." 로 바꾸지
  않는다(허락 받은 줄 밖). 라우트 순서상 `/heart-tasks/pending` 이 `:task` 와 겹치지 않는다(`submit/` 아래만 `:task`).

- [ ] **Step 4: 화면을 쓴다.** `frontend/lib/billing/view/heart_task_pending_screen.dart`:

```dart
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

const String _title = '확인하고 있어요';
const String _body = '확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요';
const String _duration = '보통 영업일 1~2일 걸려요';

/// pen 14/500 #6A6A6A, 줄높이 속성 없음 · 렌더 20.
final TextStyle _bodyStyle =
    AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted, height: 20 / 14);

/// 18c 검수 대기(pen `xA8en`). 앱바 · 버튼이 없다 — 18b 가 이 화면으로 바뀌었으므로 시스템 뒤로가 18a 로 간다.
/// 결과 푸시는 없다(계획서 D2) — 18a 상태와 잔액으로 확인한다.
class HeartTaskPendingScreen extends StatelessWidget {
  const HeartTaskPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            // pen `Bjhpo` 폭 280, 세로 간격 16.
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // DESIGN 은 128 이지만 pen 88 을 따른다(대장 09-28, DESIGN 은 문서 정리 때).
                  Image.asset('assets/images/mascot-female.png', width: 88, height: 88, fit: BoxFit.contain),
                  const SizedBox(height: AppSpacing.md),
                  Text(_title, textAlign: TextAlign.center, style: AppTypography.label.copyWith(color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.md),
                  Text(_body, textAlign: TextAlign.center, style: _bodyStyle),
                  const SizedBox(height: AppSpacing.md),
                  Text(_duration, textAlign: TextAlign.center, style: _bodyStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 통과를 확인한다.** Run: `flutter test test/billing` — Expected: A1~A5 전부 passed(9 + 8 + 10 + 7 + 3 = 37).
  `flutter test`(전체) 한 번 — 기존 테스트 실패 0. `flutter analyze` 0.

### Task A6: 설정(16) "무료로 하트 모으기" 행 — 프로필탭 · 안전담당 설정 행 merge 뒤

**Files:**
- Modify: `frontend/lib/matching/view/settings_screen.dart`(공유 — 행 1개)
- Test: 그 파일의 기존 테스트 파일(rebase 뒤 이름 확인 — 지금은 `test/matching/view/settings_screen_test.dart`)

- [ ] **Step 1: rebase 한다.** 프로필탭(16 설정 재구성) · 안전담당(탈퇴 · 정지) PR 이 main 에 들어간 뒤 `git fetch` →
  `git rebase origin/main`. 설정 화면이 그때 어떤 모양인지(행 위젯을 따로 뒀는지, 카드 `auq6h` 순서) 읽는다. 행 자리는
  대장에게 확인한다(pen 카드 안 순서).
- [ ] **Step 2: 실패하는 테스트를 쓴다.** 그 테스트 파일에 한 개:

```dart
  testWidgets('"무료로 하트 모으기" 를 누르면 18a 로 간다(pen oNgRd)', (tester) async {
    // 이 파일의 기존 pump 도우미를 쓴다 — 라우터에 AppRoutes.heartTasks → Text('18a') 를 더한다.
    await tester.tap(find.text('무료로 하트 모으기'));
    await tester.pumpAndSettle();

    expect(find.text('18a'), findsOneWidget);
  });
```

- [ ] **Step 3: 행을 넣는다.** 그때 이웃 행이 쓰는 모양(예: 공용 행 위젯)을 그대로 쓰되 값은 pen `oNgRd` 다 — 행 위젯이 없고
  지금처럼 `ListTile` 이면:

```dart
              ListTile(
                // pen `oNgRd` 52 · [0,14] · 간격 12 · gift 20 #3F3F3F · 16/400 #222222 · 셰브런 20 #6A6A6A.
                leading: const Icon(AppIcons.gift, size: 20, color: AppColors.body),
                title: Text('무료로 하트 모으기', style: AppTypography.body.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.heartTasks),
              ),
```

- [ ] **Step 4: 통과를 확인한다.** 그 테스트 파일 + `flutter test test/billing` + `flutter analyze` 0.
- [ ] **Step 5: 커밋은 campus-git 이 한다** — 요청문에 "supabase db reset·test db 등 로컬 DB 명령 금지. 수치는 리뷰어 값 인용".
  커밋 단위: 모델 · 저장소 / ViewModel / 18a / 18b / 18c · 라우트 / 설정 행.

---

## 문서 갱신 대상 (조각 끝 문서 정리 때 — 지금 PR 금지)

- `docs/ERD.md` §6 `heart_task_submissions` 새 칸(`reward_hearts` · `reject_reason`)과 `storage_path` null 허용 ·
  §8 새 enum `heart_task_reject_reason` · §9 `heart-task-proofs` 제한과 "서명 업로드 URL" → 서버 업로드 정정
- `frontend/docs/DESIGN.md` §8.10 "알림 채널 미정" → D2(푸시 없음) · §13 새 번호로 D1~D6 기록
- `docs/SUPABASE.md` §1 적용 상태 · `DEPLOY.md` 위 "운영자 절차" 와 `/batch/cleanup` ⑤ 설명
