# 지인 리뷰(20b · 20c · 14c 섹션 · 14d · friend-review-card) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 추천 코드로 연결된 지인끼리 장점 태그 + 한마디 리뷰를 남기고(20b), 받은 사람은 자기 리뷰를 보고 신고만 할 수 있으며(20c), 매칭 상대는 14c 섹션과 14d 시트에서 그 리뷰를 본다.

**Architecture:** `friend_reviews` 표 하나(FastAPI 전용, 클라이언트 권한 없음)를 새 FastAPI 모듈 `app/friend_reviews` 가 PostgREST 로 읽고 쓴다. 쓸 자격은 온보딩 탭의 `referrals` 한 줄(양방향)이고, 숨김(작성자 active 아님 · 가림 · 차단)은 읽을 때 서버가 한 곳에서 거른다. 앱은 새 기능 폴더 `lib/friend_review` 에 모델 · ViewModel · 화면을 두고, 14c 는 섹션 위젯 하나만 꽂는다.

**Tech Stack:** Supabase Postgres(pgTAP) · FastAPI + httpx(PostgREST) · Flutter/Riverpod · go_router

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §2.8(지인 리뷰) · §2.6(탈퇴) · `docs/ERD.md` §6(friend_reviews · referrals) · `frontend/docs/DESIGN.md` §8.8(`friend-review-card` · `review-compose-sheet`) · §9(14c · 14d · 20b · 20c) · §13-25(태그 12종) · §13-29(학교 배지 폴백)

---

## 결정

### 대장 결정 (2026-09-28)

| # | 질문 | 결정 |
|---|---|---|
| 1 | 쓸 자격(추천 연결)을 누가 만드나 | **온보딩 탭(feat/referral)이 만든다.** 채팅탭은 추천을 만들지 않는다. 쓸 자격 = 두 사람 사이에 `referrals` 한 줄(어느 방향이든). DB 순서는 referral 이 먼저, friend_reviews 가 그 뒤 |
| 2 | 작성자 삭제 | 이번엔 삭제 화면 · API 없음. 백로그(pen 에 "내가 쓴 리뷰" 화면이 생기면) |
| 3 | 신고된 리뷰 가림 | 운영자가 대시보드에서 `status = blinded`. 디스코드 알림은 기존 신고와 같다. 자동 가림(3명) 없음 |
| 4 | 태그 개수 | 최소 1 · 최대 3(12종 고정). 한마디 선택 · 100자 |
| 5 | 노출 자리 | pen 대로. 오늘의 카드 상세 pen 에 섹션이 없으면 14c 섹션 + 14d 만 |
| 6 | 숨김 규칙 | 바로 안 보인다 — 작성자 active 아님(탈퇴 · 정지) · `blinded` · 보는 사람과 작성자 사이 차단(어느 방향이든) |
| 7 | 학교 배지 | DESIGN §13-29 폴백 — 한 가지 색 + 학교명 글자. 색 · 크기는 pen 값 |
| 8 | 푸시 두 개 | 추천인에게 "○○님이 가입했어요"(추천 연결 순간) · 받은 사람에게 "새 지인 리뷰"(리뷰 저장 순간). 알림 스위치는 둘 다 `new_friend_review`, 조용한 시간 규칙 따름 |
| — | 20b 진입 | 두 곳 — ① 온보딩 20(코드 확인 성공) 바로 뒤, 20d 로 가기 앞 ② 추천인 푸시. ① 연결은 referral merge 뒤 한 줄 |
| — | 내 추천 코드 보여 줄 자리 | 채팅탭 몫 아님(19 "친구 초대"는 홈탭) |
| — | 신고 대상 `friend_review` 422 풀기 | 채팅탭 범위(공유 파일 허락 필요) |
| — | 폰 점검 | 새 계정으로(기존 테스트 계정은 코드를 넣을 곳이 없다). 대장이 사용자에게 알림 |

### 파생 결정 (채팅탭 제안 → 대장 확정 2026-09-28: P1 은 가, P2~P6 은 기본값)

- **P1. 리뷰 신고는 차단하지 않는다.** 기존 신고는 "신고 = 차단"(조각 6 결정 4)이지만 지인 리뷰를 신고하는 사람은 받은 사람 본인이다. 작성자를 차단하면 결정 6 때문에 **받은 사람에게만** 리뷰가 사라지고 남에게는 그대로 보인다 — 신고의 뜻과 반대다. 그래서 `friend_review` 신고는 ④ 차단 · ⑦ 자동 가림을 건너뛰고 ② 하루 상한 · ③ 스냅샷 · ⑤ 신고 행 · ⑥ 디스코드만 한다. 리뷰 신고 행의 `target_profile_id` 는 작성자라 **작성자의 신고자 수(`count_open_reporters`)에는 들어간다** — 뒤이은 프로필 · 메시지 신고의 3명 자동 가림 계산에 합쳐진다. 서로 다른 사람이 신고한 작성자면 실제 신호다(대장 결정 09-28, 검토 권고 4 가).
- **P2. 리뷰를 신고할 수 있는 사람은 받은 사람(20c)뿐이다.** 14c · 14d 에는 신고 입구가 없다(pen 확인 뒤 확정). 서버는 `reviewee_id = 나` 가 아니면 404.
- **P3. 같은 사람에게 두 번 쓰면 409 "이미 리뷰를 남겼어요".** 수정도 없다(결정 2 와 같은 이유). 20b 는 열기 전에 서버에 물어 409 면 시트 대신 토스트.
- **P4. 태그는 한글 라벨 그대로 저장**하고 12종 목록 검사는 FastAPI 가 한다(`profiles.interest_tags` 관례). DB 는 개수(1~3)만 본다.
- **P5. 목록은 페이지 없이 전부** 내려준다. 한 사람이 받는 리뷰 수 = 그 사람과 추천으로 이어진 사람 수라 작다. `ponytail:` 주석으로 상한을 적는다.
- **P6. 14c 섹션은 보이는 리뷰가 0개면 통째로 숨긴다.** 단, pen 14c 에 빈 상태 모양이 있으면 pen 을 따른다(대장 09-28). 20c 는 빈 상태(pen 값).

### 온보딩 탭과 맞춘 계약 (2026-09-28, 온보딩 탭 답)

- `referrals`: `referee_id uuid PK FK profiles` · `referrer_id uuid FK profiles` · `created_at` · `rewarded_at`, 두 FK 모두 `on delete cascade`. RLS 켬 · 정책 없음(service_role 만). 인덱스 `referrals_referrer_id_index` 는 온보딩 탭이 단다.
- `rewarded_at` 은 입력 즉시 보상이라 늘 채워져 있다 → **"행이 있으면 연결"** 로 본다. 어뷰징은 DB 함수가 넣기 전에 거절하므로 행이 나중에 지워지는 일은 없다.
- `POST /referral/redeem` 200 응답 = `{"referrer_id": "<uuid>"}`. 오류 404(없는 코드 · 탈퇴 · 정지) · 409(이미 입력) · 422(자기 코드 · 같은 번호).
- 20b 자리: `frontend/lib/referral/viewmodel/referral_code_view_model.dart` 의 확인 성공 분기, 20d 로 가기 바로 앞에 `// 20b 자리(채팅탭 feat/friend-review): 지인 리뷰 시트를 여기서 띄운다`. 화면에서 띄워야 하면 `referral_code_screen.dart` 로 옮기고 주석도 같이(최종 위치는 referral PR 설명).
- 푸시 훅 자리: `backend/app/referral/router.py` 의 `redeem_referral_code`, `return` 바로 앞 `# 푸시 훅 자리(채팅탭)`.

### 이번에 하지 않는 것

- 추천 코드 · `referrals` · 화면 20 · 20d · 하트 보상 — 온보딩 탭
- 작성자 삭제 · 수정(결정 2, P3) — 백로그
- 자동 가림 · 받은 사람의 삭제(spec §2.8 표 "삭제 불가")
- 대학 로고 이미지(§13-29 파일 미수령) — 폴백 배지만
- 오늘의 카드 상세(10b) 리뷰 섹션 — pen 에 있을 때만 v2 에서 Task 를 더한다(결정 5)
- 조용한 시간에 버린 푸시를 아침에 다시 보내기(기존 `notify()` 백로그와 같음)

---

## Global Constraints

- 표 · 함수는 FastAPI 전용. `anon` · `authenticated` 에 어떤 권한도 주지 않는다(ERD §2 86줄 "`referrals` · `friend_reviews` 없음 · FastAPI 전용").
- 태그 12종(DESIGN §13-25, 순서 그대로): 약속을 잘 지켜요 · 대화가 편해요 · 배려가 깊어요 · 유머 감각이 좋아요 · 성실해요 · 솔직해요 · 이야기를 잘 들어줘요 · 긍정적이에요 · 센스 있어요 · 다정해요 · 차분해요 · 리액션이 좋아요. **외모 태그 없음.** pen 시안(태그 6종 · 0/80)이 아니라 이 목록을 따른다.
- 태그 1~3개, 중복 없음. 한마디는 선택, 앞뒤 공백을 깎아 1~100자, 비면 null.
- 리뷰어 표시는 **학교 배지 + 만화 아바타 + 닉네임 + 태그 + 한마디**(spec §2.8, 2026-09-10 — 실명 마스킹 폐기, 닉네임만).
- 응답에 `reviewer_id` 를 싣지 않는다 — 14c 를 보는 매칭 상대가 상대 지인의 profile_id 를 알 이유가 없다. 20c 신고는 리뷰 `id` 로 한다.
- 로그 · 디스코드에 닉네임 · 한마디 · 태그를 남기지 않는다. 디스코드는 기존 `report_line`(profile_id · 사유 · 신고자 수)만.
- 새 의존성 없음(pubspec · pyproject 그대로). `dart format` 돌리지 않는다. CRLF 파일은 Edit 또는 python `newline=''` 로만 고친다.
- 잉크(COMMON §4-2): 누르는 칸마다 자기 Material, 테스트로 가장 가까운 Material 크기 == 칸 크기.
- 누르는 영역은 보이는 크기를 pen 대로 두고 48 이상으로 넓힌다(PR 5 의 14b 버튼 방식).
- 이 계획서와 pen 이 다르면 **pen 이 이긴다**(단, 태그 목록 · 개수 · 100자는 위 결정이 이긴다 — DESIGN §8.8 "구현은 시안이 아니라 이 문서").

## Review Focus

1. **작성자가 탈퇴 · 정지되면** 그 리뷰는 14c · 14d · 20c 에서 곧바로 사라져야 한다(ERD "작성자 탈퇴 시 즉시 숨김"). → Task B1 `test_hides_reviews_by_inactive_reviewer` (embed `!inner` + `reviewer.status=eq.active`).
2. **보는 사람과 작성자 사이에 차단이 있으면** 그 리뷰는 보는 사람에게 안 보여야 한다(어느 방향이든). → Task B1 `test_hides_reviews_by_blocked_reviewer`.
3. **같은 사람에게 두 번** 쓰려 하면 서버는 409, 앱은 시트를 열지 않고 "이미 리뷰를 남겼어요". 동시에 두 번 눌러도 한 줄. → Task C1 unique 테스트 · B2 `test_second_review_is_409` · A2 `open 이 409 면 alreadyWritten`.
4. **태그 4개째를 누르면** 무시되고, 0개면 "리뷰 남기기"가 꺼져 있어야 한다. 한마디가 공백뿐이면 null 로 저장. → Task A2 태그 토글 테스트 · B2 `test_blank_comment_becomes_null` · C1 check 테스트.
5. **추천으로 이어지지 않은 사람의 id 를 직접 넣어** 쓰거나 읽으려 하면 404(있다는 사실도 알리지 않는다). → Task B2 `test_unlinked_target_is_404` · B1 `test_about_requires_match`.

---

## API 계약 (B · A 공통)

모두 `get_verified_caller`(학생증 · 학과 관문) 뒤. 404 문구는 전부 `errors.PROFILE_NOT_FOUND` 또는 `FRIEND_REVIEW_NOT_FOUND` 하나 — 이유를 가르지 않는다.

리뷰 한 장 모양(`ReviewItem`):

```json
{
  "id": "uuid",
  "reviewer": {"nickname": "달빛", "avatar_url": "https://…/avatars/…" , "university": "테스트대학교"},
  "tags": ["약속을 잘 지켜요", "대화가 편해요"],
  "comment": "한마디 또는 null",
  "created_at": "2026-09-28T05:00:00+00:00"
}
```

| 메서드 · 경로 | 누가 · 어디서 | 성공 | 실패 |
|---|---|---|---|
| `GET /friend-reviews/about/{profile_id}` | 매칭 상대 · 14c 섹션 · 14d | 200 `{"reviews": [ReviewItem…]}` 최신순 | 404 = 14c 와 같은 조건(자기 자신 · 매칭 이력 없음 · 누가 나감 · 상대 active 아님 · 차단) · 422 UUID 아님 |
| `GET /friend-reviews/received` | 받은 사람 본인 · 20c | 200 `{"reviews": [ReviewItem…]}` 최신순 | — |
| `GET /friend-reviews/targets/{profile_id}` | 작성자 · 20b 열기 전 | 200 `{"profile_id", "nickname", "avatar_url"}` | 404 자기 자신 · 추천 연결 없음 · 상대 active 아님 · 차단 / 409 이미 씀 |
| `POST /friend-reviews` body `{"reviewee_id", "tags": [..], "comment": str\|null}` | 작성자 · 20b "리뷰 남기기" | 201 `{"id"}` + 받은 사람에게 푸시 | 위 404 · 409 와 같음 / 422 태그 0개 · 4개 · 목록 밖 · 중복 · 한마디 101자 |
| `POST /reports` `target_type = "friend_review"` | 받은 사람 · 20c | 201(기존과 같음) | 404 없는 리뷰 · 내가 받은 리뷰 아님 · 이미 가려짐 / 409 이미 신고 / 429 하루 상한 |

푸시 `data`:

| 언제 | 받는 사람 | kind(스위치) | 제목 · 본문 | data |
|---|---|---|---|---|
| 리뷰 저장 | 받은 사람 | `new_friend_review` | "새 지인 리뷰가 도착했어요" · "{닉네임} 님이 리뷰를 남겼어요" | `{"route": "friend_reviews"}` → 20c |
| 추천 연결(redeem 성공) | 추천인 | `new_friend_review` | "친구가 가입했어요" · "{닉네임} 님이 가입했어요, 리뷰를 남겨 주세요" | `{"route": "friend_review_write", "profile_id": "<피추천인>"}` → 20b |

문구는 pen 값표가 오면 그쪽을 따른다(v2).

---

## DB 변경 목록

| 종류 | 이름 | 내용 |
|---|---|---|
| 표 | `public.friend_reviews` | ERD §6 그대로: `id` PK · `reviewer_id` FK(cascade) · `reviewee_id` FK(cascade) · `tags text[]` · `comment text` · `status content_status default 'visible'` · `created_at` |
| 제약 | `friend_reviews_once` | `unique (reviewer_id, reviewee_id)` — 두 번째는 23505 → 409 |
| 제약 | `friend_reviews_not_self` | `reviewer_id <> reviewee_id` |
| 제약 | `friend_reviews_tags_count` | `cardinality(tags) between 1 and 3` |
| 제약 | `friend_reviews_comment_length` | `comment is null or (1~100자 and comment = btrim(comment))` |
| 인덱스 | `friend_reviews_reviewee_id_created_at_index` | `(reviewee_id, created_at desc)` — 받은 목록 · 14c. `reviewer_id` 는 unique 앞머리가 cascade 를 받는다 |
| RLS | `friend_reviews` | 켬 · 정책 없음 · `anon` · `authenticated` 권한 전부 회수 · `service_role` 에만 select · insert · update · delete |
| 함수 | 없음 | 쓰기가 insert 한 번, 읽기가 embed 한 번이라 PostgREST 로 충분하다(투표처럼 집계 · 한도가 없다) |
| 재사용 | `content_status` | `20260927020000_create_polls.sql` 의 enum 그대로 |
| 의존 | `referrals` | 온보딩 탭 마이그레이션(먼저 적용). 이 마이그레이션은 참조하지 않는다 — 자격 확인은 FastAPI |

마이그레이션 파일 이름은 "DB 차례"를 받을 때 referral 마이그레이션보다 뒤 시각으로 정한다(예: `20260928020000_create_friend_reviews.sql`). 운영 적용 전에 ERD.pen 그림과 사용자 검토가 필요하다(ERD.md §6 에 이미 칸이 있어 그림 변경은 제약 · 인덱스 비고 정도).

---

## 화면 대조표 (v2 — pen 값표 B 2026-09-29)

값 원본 = `C:/Users/user/OneDrive/Desktop/조각6_검토/값표_B_지인리뷰.md`(175줄) + PNG 4장(`값표_B_지인리뷰_png/`). 아래는 판정만 적는다 — 치수는 값표 원본을 본다. **pen 이 이긴다**(단 태그 12종 · 상한 3 · 100자는 결정이 이긴다, 대장 결정 1 · 2).

| 화면 | pen 노드 | 칸 | 계획서 가정 | pen 값 | 판정 |
|---|---|---|---|---|---|
| 카드 | `S0MR2b` | 틀 | — | 폭 fill · hug, #FFF r14 stroke hairline 1, pad 16 gap 12, 그림자 없음 | pen |
| | | 학교 배지 | 20dp 한 색 + 학교명 | **36×36 surfaceInk r8, 학교명 첫 글자 12/700 흰색** | pen(대장 6: 실제 학교). 학교 null 이면 배지 없음 |
| | | 아바타 | 32dp 원 | **이니셜 원** 36 primaryWash, 첫 글자 14/700 primaryText | pen — avatar_url 안 씀(편차) |
| | | 닉네임 · 관계 | label | 16/600 ink · 12/400 muted, gap 1 | 관계 = 고정 "추천으로 연결된 친구"(대장 Q3 가 09-29 — DB · API 에 관계 칸 없음, 추천은 학교를 안 따짐) |
| | | 신고 | ⋯ 또는 길게 | **flag 20 muted, 누름칸 48** 머리 줄 오른쪽 | pen. `onReport` null 이면 없음 — 20c 만 넘긴다(P2 · 대장 Q2 09-29) |
| | | 태그 칩 | chip 줄바꿈 | primaryWash r999 pad[6,10], 12/600 primaryText, gap 8 | pen + 3개면 `Wrap`(pen 은 2개만 그림) |
| | | 한마디 | body-small 2줄 말줄임 | 14/400 body lh1.5 | pen, 말줄임 없음(pen 에 없음 — 100자라 전부 보인다). null 이면 줄 · 간격 없음 |
| 14c 섹션 | `t3hFo`(원본 `HlGva`) | 위치 | 태그 뒤 · 카카오 앞 | 이상형 메모 뒤 13 → 헤더 → 8 → 카드 → 8 → 카드 → 13 → 카카오 | pen |
| | | 헤더 | "친구 N명이 남겼어요" | "지인 리뷰" 14/600 muted · 오른쪽 "N개 모두 보기" 12/600 primaryText + chevron-right 14, gap 2 | pen(대장 5) |
| | | 카드 수 | 2 | 2 | 같음 |
| | | 모두 보기 | 늘 | 3개 이상일 때만(편차 — 2개 이하면 다 보인다), 누름 44 이상(대장 7) | 편차 |
| | | 0개 · 1개 | 숨김 | pen 없음 | P6 숨김 · 1개면 카드 1장(대장 4) |
| | | 신고 깃발 | — | pen 은 그림 | 없음(대장 Q2 09-29 — 서버가 받은 사람만 허용, pen 은 묶음 9 에서 정리) |
| 14d | `FXNL4` | 모양 | 725 고정 | hug(카드 3장 = 750), r[24,24,0,0], 그림자 (0,-2) 16 #00000026, 손잡이 36×4 hairline r2, 닫기 없음 | pen. 많으면 화면 90% 까지 · 스크롤(편차) |
| | | 헤더 | 같음 | "친구들이 본 {닉네임}" 20/700 ink · "리뷰 N개" 14/400 muted 오른쪽 | pen |
| | | 목록 · 끝 | 같음 | 카드 gap 12 → 안내 상자(info 20 primaryText, "리뷰는 추천 코드로 연결된 지인만 남길 수 있어요. 부적절한 내용은 신고해주세요.") | pen |
| 20b | `NHcsP`(판 `nIrPW`) | 모양 | 바텀시트 | 시트, 딤 #00000080, 664 고정, r[24,24,0,0], 그림자 없음, 손잡이 36×4 hairline r999, 제목 · X 없음 | pen. 12종이라 가운데 스크롤 · 버튼 바닥 고정(편차) |
| | | 머리 | 아바타 + 이름 | 이니셜 원 44 primaryWash(16/700 ink) · 이름 17/600 · 관계 12/400 muted | pen, 관계 = "추천으로 연결된 친구"(Q3) |
| | | 태그 | 12종 그리드 | "어떤 장점이 있나요?" 17/600 → 2열 칩 160×40 r999, 선택 = primaryWash · stroke primary · 14/600 primaryText / 안 선택 = 흰 · stroke hairline · 14/600 body, gap 8 | pen 모양 · 서버 12종(대장 2), 누름 44(대장 7) |
| | | 한마디 | 한 줄, 0/100 | "한마디를 남겨주세요" 17/600 → Textarea 104h surfaceSoft r8 stroke outline, placeholder "이 사람을 잘 보여주는 따뜻한 이야기를 적어주세요.", 카운터 왼쪽 아래 12/400 muted | pen 모양 · **"n / 100"**(대장 1) |
| | | 버튼 | button-primary | 328×52 primary r8, "리뷰 남기기" 18/700 흰색 | pen. 꺼짐 primaryDisabled/disabled, 보내는 중 버튼 안 스피너(대장 4) |
| | | 성공 · 실패 · 409 | 토스트 | pen 없음 | 계획서 v1 문구 + 기존 토스트(대장 4 · 8) |
| | | 푸시 진입 밑 화면 | D-A | pen 없음(가입 흐름 20 → 20b → 20d 만) | 홈 위 시트 `/home/friend-reviews/write/:id`(대장 Q1 가 09-29) |
| 20c | `HWM2G` | 앱바 | — | 56h, 뒤로 48(arrow-left 22) + "받은 리뷰" 20/700, 하단 내비 없음 | pen |
| | | 본문 | — | pad [8,16,24,16] gap 16, 안내 상자(info, "받은 리뷰는 직접 삭제할 수 없어요. 부적절한 내용은 신고해주세요.", 글 폭 270) → 카드들 | pen |
| | | 개수 | — | 없음 | pen(없음) |
| | | 신고 | ⋯ | 카드 깃발 → 기존 신고 시트, 성공 토스트 "신고했어요. 운영팀이 확인할게요", 이미 신고는 서버 문구 | 대장 9 |
| | | 빈 · 로딩 · 실패 | empty-state | pen 없음 | 기존 앱 모양(대장 4) — 안내 상자는 늘 보인다 |
| 10b | `TORAs` | 리뷰 섹션 | ? | 없음 | 14c + 14d 만(대장 8, P5) |
| 푸시 | — | 문구 | v1 | 없음 | v1 그대로(대장 8) |

pen 에 없는 상태는 기존 앱 모양으로 정하고 "구현 편차 기록" 에 적는다.

---

## 공유 파일 (줄 단위 허락 — PR 2 · PR 3 줄은 통합대장 09-28 · 09-29 허락)

| 파일 | 바꿀 줄 | 언제 |
|---|---|---|
| `backend/app/main.py` | import 1 · `include_router` 1 | PR 2 |
| `backend/app/core/errors.py` | `FRIEND_REVIEW_NOT_FOUND` · `FRIEND_REVIEW_ALREADY_WRITTEN` 2줄 + 빈 줄 · 절 주석 = +4(허락: 통합대장 09-28) | PR 2 |
| `backend/app/safety/router.py`(안전담당) | `ReportRequest.target_type` Literal 에 `"friend_review"` + 주석 1줄 수정 · `report()` 의 ① 분기 3줄 · ④⑦ 건너뛰기 조건 2줄 · `_friend_review_target()` 함수 약 12줄 | PR 2 |
| `frontend/lib/safety/model/safety_repository.dart`(안전) | +4 −2: 5~6줄 주석을 "세 가지"로(−2 +2) · 빈 줄 + 주석 1 + `ReportTarget.friendReview` 생성자 1 | PR 3 |
| `frontend/lib/safety/model/safety_errors.dart`(안전) | +3 −2: `_friendReviewGone` 상수 1 · `isReportTargetGone` 주석 · 판별식(검토 권고 1, 허락 09-29) | PR 3 |
| `frontend/lib/core/router/app_routes.dart` | +3: 주석 1 + 상수 2(`friendReviews` · `friendReviewWrite = '/home/friend-reviews/write'`), `account` 뒤 | PR 3 |
| `frontend/lib/core/router/app_router.dart` | import 2 + `_slice6Routes` 끝에 20c `GoRoute` 1 + home `GoRoute` 에 `routes:` 로 20b 시트 페이지(−1 +7, 대장 Q1 09-29) | PR 3 |
| `frontend/lib/core/push/push_route.dart` | +6: 주석 1 + `'friend_reviews'` 1 + `'friend_review_write'` 안쪽 switch 4 | PR 3 |
| `frontend/test/core/push/push_route_test.dart` | +약 12: 테스트 3개(받은 목록 · 쓰기 id 있음 · id 없음 → null) | PR 3 |
| `frontend/test/core/router/app_router_test.dart` | +약 15: import 2(화면 · 가짜 저장소) · 두 경로가 열리는 테스트 2개 | PR 3 |
| `frontend/lib/safety/view/partner_profile_screen.dart`(채팅탭 PR 5 가 만듦) | +약 5: import 1 · `_ProfileBody` 인자 1 · `_Footer` 필드 1 + 생성자 1 · build 에 섹션 1(간격은 pen) | PR 3 |
| `backend/app/referral/router.py`(온보딩) | 훅 자리에 푸시 1~3줄(+ sender 의존성) | referral merge 뒤 PR 4 |
| `frontend/lib/referral/view/referral_code_screen.dart`(온보딩, main 에 있음) | 46~48줄 20b 자리 주석 2줄 + `context.go` → 20b 여는 줄(모양은 D-A) | PR 4 |
| `frontend/lib/me/…`(나 탭 PR3 의 15 새 디자인 nkFJV) | 15 지인 리뷰 섹션 `Cux1p` + 분홍 줄 `o9BA0`(→ 20c) · 15-4 `gnEwq` 리뷰 섹션(카드 신고 깃발 숨김). 옛 `ZCpM4` 입구 대신(대장 09-28) | 나 탭 PR3 merge 뒤 PR 4 |

## 파일 구조

```
supabase/migrations/2026092802xxxx_create_friend_reviews.sql   표 · 제약 · 인덱스 · 권한
supabase/tests/friend_reviews_test.sql                         pgTAP

backend/app/friend_reviews/__init__.py
backend/app/friend_reviews/repository.py   FriendReviewRepository — 읽기 embed · 추천 연결 · 쓰기
backend/app/friend_reviews/router.py       4 엔드포인트 · 태그 목록 · 숨김 · 푸시 · notify_review_request()
backend/tests/friend_reviews/__init__.py
backend/tests/friend_reviews/test_friend_reviews.py
backend/tests/safety/test_report_friend_review.py

frontend/lib/friend_review/model/friend_review.dart                FriendReview · ReviewTarget
frontend/lib/friend_review/model/friend_review_tags.dart           12종 · 상한 3 · 100자
frontend/lib/friend_review/model/friend_review_repository.dart     추상
frontend/lib/friend_review/model/http_friend_review_repository.dart
frontend/lib/friend_review/model/friend_review_repository_provider.dart
frontend/lib/friend_review/viewmodel/friend_review_compose_ui_state.dart
frontend/lib/friend_review/viewmodel/friend_review_compose_view_model.dart   20b
frontend/lib/friend_review/viewmodel/friend_review_list_ui_state.dart
frontend/lib/friend_review/viewmodel/friend_review_list_view_model.dart      14c · 14d · 20c 공용(family: about/received)
frontend/lib/friend_review/view/friend_review_card.dart            S0MR2b
frontend/lib/friend_review/view/friend_review_compose_sheet.dart   20b
frontend/lib/friend_review/view/partner_reviews_section.dart       14c 섹션 + 14d 시트 여는 함수
frontend/lib/friend_review/view/received_reviews_screen.dart       20c
frontend/test/friend_review/…                                     위와 같은 모양 + fake_friend_review_repository.dart
```

카드 위젯은 이 기능만 쓰므로 `common` 으로 올리지 않는다.

## PR 나누기

| PR | 내용 | 조건 |
|---|---|---|
| PR 1 DB | Task C1 | 대장 "DB 차례"(순서 referral → heart-tasks → friend_reviews, 타임스탬프는 그때 받음) · ERD.pen · 사용자 검토 → 운영 적용 |
| PR 2 서버 | Task B1 · B2 · B3 | 목 테스트로 먼저 진행 가능(대장 09-28). PR 1 운영 적용 뒤 배포. 공유 파일 허락(safety/router.py 는 안전담당에도 알림) |
| PR 3 앱 | Task A1~A6 | pen 값표(v2) 뒤. PR 2 와 나란히 만들고 PR 2 배포 뒤 ready |
| PR 4 연결 | Task A7 · B4 | referral merge · 나 탭 PR merge 뒤. 줄 몇 개 |

---

# Part C — Supabase (대장 "DB 차례" 뒤에만)

### Task C1: `friend_reviews` 표 · 제약 · 권한

**Files:**
- Create: `supabase/migrations/2026092802xxxx_create_friend_reviews.sql`
- Test: `supabase/tests/friend_reviews_test.sql`

**Interfaces:**
- Consumes: `public.profiles(id)`, `public.content_status`(polls 마이그레이션)
- Produces: 표 `public.friend_reviews`, 제약 이름 `friend_reviews_once`(23505 → B2 409)

- [ ] **Step 1: pgTAP 테스트를 쓴다(RED)**

```sql
-- 지인 리뷰 표 · 제약 · 권한 검증. 기대값: docs/superpowers/plans/2026-09-28-friend-review.md Task C1.
-- 로컬 스택에서 `supabase test db`. 트랜잭션 안에서만 돌고 rollback 한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

-- 준비: R = ...90(작성자), E = ...91(받은 사람), GONE = ...92(탈퇴할 작성자)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000009', '테스트대학교9', 'seoul');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000090', 'fr-r@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000091', 'fr-e@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000092', 'fr-gone@test9.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000009' from auth.users
where id between '00000000-0000-0000-0000-000000000090' and '00000000-0000-0000-0000-000000000092'
on conflict (id) do nothing;

-- 1~3 표 · RLS · 권한
select has_table('public', 'friend_reviews', 'friend_reviews 표가 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.friend_reviews'::regclass),
  'friend_reviews 는 RLS 가 켜져 있다');
select is_empty($$
  select grantee, privilege_type from information_schema.role_table_grants
  where table_schema = 'public' and table_name = 'friend_reviews'
    and grantee in ('anon', 'authenticated')
$$, 'anon · authenticated 는 friend_reviews 에 아무 권한이 없다');

-- 4 기본값
insert into public.friend_reviews (id, reviewer_id, reviewee_id, tags)
values ('00000000-0000-0000-0000-0000000009a0', '00000000-0000-0000-0000-000000000090',
        '00000000-0000-0000-0000-000000000091', array['약속을 잘 지켜요']);
select is((select status::text from public.friend_reviews where id = '00000000-0000-0000-0000-0000000009a0'),
  'visible', 'status 기본값은 visible 이다');

-- 5 같은 사람에게 두 번
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000091', array['성실해요'])
$$, '23505', null, '같은 작성자가 같은 사람에게 두 번 쓸 수 없다');

-- 6 반대 방향은 된다(양방향 품앗이, spec §2.8)
select lives_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000090', array['성실해요'])
$$, '받은 사람이 작성자에게 거꾸로 쓰는 것은 된다');

-- 7 자기 자신
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000092', array['성실해요'])
$$, '23514', null, '자기 자신에게는 쓸 수 없다');

-- 8~9 태그 개수
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array[]::text[])
$$, '23514', null, '태그 0개는 안 된다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요', '솔직해요', '다정해요', '차분해요'])
$$, '23514', null, '태그 4개는 안 된다');

-- 10~12 한마디
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요'], repeat('가', 101))
$$, '23514', null, '한마디 101자는 안 된다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array['성실해요'], '')
$$, '23514', null, '빈 한마디는 null 로 넣어야 한다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array['성실해요'], ' 좋아요')
$$, '23514', null, '앞뒤 공백이 남은 한마디는 안 된다');

-- 13 100자는 된다
select lives_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요', '솔직해요', '다정해요'], repeat('가', 100))
$$, '태그 3개 · 한마디 100자는 된다');

-- 14 인덱스
select has_index('public', 'friend_reviews', 'friend_reviews_reviewee_id_created_at_index',
  '받은 목록 인덱스가 있다');

-- 15 계정 삭제(탈퇴 30일 뒤)면 쓴 리뷰도 사라진다(spec §2.6 FK 규칙)
delete from auth.users where id = '00000000-0000-0000-0000-000000000092';
select is_empty($$
  select 1 from public.friend_reviews where reviewer_id = '00000000-0000-0000-0000-000000000092'
$$, '작성자 계정이 지워지면 그 리뷰도 지워진다');

select * from finish();
rollback;
```

- [ ] **Step 2: 돌려서 실패를 확인한다**

Run: `supabase test db` (한 번에 한 도우미만. 워크트리에서 돌리는 법은 메모 reference_pgtap_from_worktree)
Expected: `friend_reviews_test.sql` FAIL — `relation "public.friend_reviews" does not exist`

- [ ] **Step 3: 마이그레이션을 쓴다**

```sql
-- 지인 리뷰(20b · 20c · 14c · 14d). 기준 문서 docs/ERD.md §6, spec §2.8, DESIGN §8.8 · §13-25.
-- 클라이언트는 이 표에 접근하지 않는다(ERD §2 "FastAPI 전용"). 쓸 자격(referrals 양방향)과
-- 숨김(작성자 active 아님 · 차단)을 FastAPI 가 한 곳에서 본다.
create table public.friend_reviews (
  id uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null references public.profiles (id) on delete cascade,
  reviewee_id uuid not null references public.profiles (id) on delete cascade,
  tags text[] not null,
  comment text,
  status public.content_status not null default 'visible',
  created_at timestamptz not null default now(),
  -- 한 사람에게 한 번. 두 번째 insert 는 23505 → 서버 409. 수정 · 삭제 화면은 없다(계획서 결정 2).
  constraint friend_reviews_once unique (reviewer_id, reviewee_id),
  constraint friend_reviews_not_self check (reviewer_id <> reviewee_id),
  -- 12종 목록 검사는 FastAPI 가 한다(profiles.interest_tags 와 같은 관례). DB 는 개수만 본다.
  constraint friend_reviews_tags_count check (cardinality(tags) between 1 and 3),
  -- 서버가 앞뒤 공백을 깎고 빈 한마디는 null 로 넣는다.
  constraint friend_reviews_comment_length
    check (comment is null or (char_length(comment) between 1 and 100 and comment = btrim(comment)))
);

comment on table public.friend_reviews is
  '지인 리뷰. FastAPI 전용. 받은 사람은 지울 수 없다(spec §2.8). 작성자가 active 가 아니면 읽을 때 숨긴다';

-- 받은 목록(20c · 14c · 14d)은 reviewee_id 로 최신순. reviewer_id 는 unique 앞머리가 탈퇴 cascade 를 받는다.
create index friend_reviews_reviewee_id_created_at_index
  on public.friend_reviews (reviewee_id, created_at desc);

alter table public.friend_reviews enable row level security;

revoke all on table public.friend_reviews from anon, authenticated, service_role;
grant select, insert, update, delete on table public.friend_reviews to service_role;
```

- [ ] **Step 4: 다시 돌려 통과를 확인한다**

Run: `supabase test db`
Expected: 모든 파일 PASS, `friend_reviews_test.sql .. ok`(15)

- [ ] **Step 5: 커밋은 campus-git 몫**(도우미는 커밋하지 않는다). 제안: `🗃️ feat(db): friend_reviews 표 · 제약 · 권한` / `✅ test(db): friend_reviews pgTAP`

---

# Part B — FastAPI (PR 1 운영 적용 뒤 배포)

### Task B1: 저장소 · 읽기 두 개(14c · 14d / 20c)

**Files:**
- Create: `backend/app/friend_reviews/__init__.py`(빈 파일), `backend/app/friend_reviews/repository.py`, `backend/app/friend_reviews/router.py`
- Modify: `backend/app/main.py`(import 1 · include 1 — 허락), `backend/app/core/errors.py`(3줄 — 허락)
- Test: `backend/tests/friend_reviews/__init__.py`, `backend/tests/friend_reviews/test_friend_reviews.py`

**Interfaces:**
- Consumes: `app.safety.router.find_match(chat, me, other)`, `app.cards.router.is_active(profile)`, `app.chat.router.avatar_url(profile, supabase_url)`, `CardRepository.fetch_block_partner_ids(id) -> set[str]`, `CardRepository.fetch_profile_status(id)`(notify 가 쓰는 것), `PostgrestRepository._rows(table, params)`
- Produces: `FriendReviewRepository.fetch_about(reviewee) -> list[dict]`, `GET /friend-reviews/about/{profile_id}`, `GET /friend-reviews/received`, 응답 `ReviewItem`(API 계약)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`backend/tests/friend_reviews/test_friend_reviews.py` 앞부분(설정 · `_wire` 는 `tests/community/test_community_polls.py` 와 같은 모양):

```python
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.cards.push import FcmSender
from app.core import errors
from app.core.deps import get_client, get_settings
from app.friend_reviews import router as router_module
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
PARTNER = "22222222-2222-2222-2222-222222222222"
FRIEND = "33333333-3333-3333-3333-333333333333"
REVIEW_ID = "44444444-4444-4444-4444-444444444444"
MATCH_ID = "55555555-5555-5555-5555-555555555555"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
ITEM_KEYS = {"id", "reviewer", "tags", "comment", "created_at"}


def _review_row(**overrides) -> dict:
    row = {
        "id": REVIEW_ID, "reviewer_id": FRIEND, "tags": ["약속을 잘 지켜요"], "comment": "믿음직해요",
        "created_at": "2026-09-28T05:00:00+00:00",
        "reviewer": {"nickname": "달빛", "status": "active", "universities": {"name": "테스트대학교"},
                     "profile_avatars": [{"storage_path": "f/a.png", "status": "ready",
                                          "created_at": "2026-09-01T00:00:00+00:00"}]},
    }
    return {**row, **overrides}


class _FakeCredentials:
    token = "fake-access-token"
    valid = True

    def refresh(self, _request) -> None:
        pass


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


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": ME})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _table(request: httpx.Request) -> str:
    return request.url.path.rsplit("/", 1)[-1]


def _received_handler(rows: list[dict], blocked: list[dict] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        if _table(request) == "friend_reviews":
            return httpx.Response(200, json=rows)
        if _table(request) == "blocks":
            return httpx.Response(200, json=blocked or [])
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def test_received_gives_item_keys_and_never_reviewer_id():
    response = _wire(_received_handler([_review_row()])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.status_code == 200
    item = response.json()["reviews"][0]
    assert set(item) == ITEM_KEYS
    assert item["reviewer"] == {"nickname": "달빛", "university": "테스트대학교",
                                "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/f/a.png"}


def test_received_asks_only_visible_rows_about_me_by_active_reviewers():
    seen: list[httpx.Request] = []
    _wire(_received_handler([]), seen).get("/friend-reviews/received", headers=AUTH_HEADERS)
    query = next(r for r in seen if _table(r) == "friend_reviews").url.params
    assert query["reviewee_id"] == f"eq.{ME}"
    assert query["status"] == "eq.visible"
    assert query["reviewer.status"] == "eq.active"
    assert "!inner" in query["select"]
    assert query["order"] == "created_at.desc"


def test_hides_reviews_by_inactive_reviewer():
    # DB 가 embed 필터를 무시하고 돌려줘도(목 서버) 서버가 한 번 더 거른다 — Review Focus 1.
    gone = _review_row(reviewer={**_review_row()["reviewer"], "status": "withdrawn"})
    response = _wire(_received_handler([gone])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json() == {"reviews": []}


def test_hides_reviews_by_blocked_reviewer():
    # Review Focus 2 — 어느 방향이든.
    blocked = [{"blocker_id": FRIEND, "blocked_id": ME}]
    response = _wire(_received_handler([_review_row()], blocked)).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json() == {"reviews": []}


def test_empty_comment_stays_null():
    response = _wire(_received_handler([_review_row(comment=None)])).get("/friend-reviews/received", headers=AUTH_HEADERS)
    assert response.json()["reviews"][0]["comment"] is None


def _about_handler(*, match: list[dict], status: str = "active", rows: list[dict] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        table = _table(request)
        if table == "matches":
            return httpx.Response(200, json=match)
        if table == "profiles":
            return httpx.Response(200, json=[{"status": status}])
        if table == "blocks":
            return httpx.Response(200, json=[])
        if table == "friend_reviews":
            return httpx.Response(200, json=rows or [])
        return httpx.Response(404, json={"message": f"unexpected {request.url}"})
    return handler


def _match(left_at: str | None = None) -> list[dict]:
    return [{"id": MATCH_ID, "chat_closed_at": None, "trust_passed_at": None, "match_participants": [
        {"profile_id": ME, "left_at": None}, {"profile_id": PARTNER, "left_at": left_at}]}]


def test_about_lists_partner_reviews():
    response = _wire(_about_handler(match=_match(), rows=[_review_row()])).get(
        f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert len(response.json()["reviews"]) == 1


def test_about_requires_match():
    # Review Focus 5 — 매칭 이력 없는 사람의 리뷰는 읽을 수 없다. 14c 와 같은 404.
    response = _wire(_about_handler(match=[])).get(f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.PROFILE_NOT_FOUND


@pytest.mark.parametrize("case", ["left", "inactive"])
def test_about_follows_14c_404_rules(case):
    handler = _about_handler(match=_match("2026-09-28T00:00:00+00:00")) if case == "left" \
        else _about_handler(match=_match(), status="suspended")
    response = _wire(handler).get(f"/friend-reviews/about/{PARTNER}", headers=AUTH_HEADERS)
    assert response.status_code == 404
```

목의 표 이름은 확인했다(09-28): `find_match` → `ChatRepository.fetch_match_between` 이 `matches`(+ `match_participants` embed)를 읽고 첫 행을 쓴다 · `CardRepository.fetch_profile_status` 는 `profiles?select=status` · `fetch_block_partner_ids` 는 `blocks`.

- [ ] **Step 2: 돌려서 실패를 확인한다**

Run: `.venv/Scripts/python -m pytest backend/tests/friend_reviews -q` (루트 .venv 파이썬 — 메모 reference_backend_pytest_python)
Expected: FAIL — `ModuleNotFoundError: No module named 'app.friend_reviews'`

- [ ] **Step 3: errors 3줄(허락 받은 뒤)**

`backend/app/core/errors.py` 맨 끝 투표 절 뒤에:

```python
# 지인 리뷰
FRIEND_REVIEW_NOT_FOUND = "리뷰를 찾을 수 없어요"
FRIEND_REVIEW_ALREADY_WRITTEN = "이미 리뷰를 남겼어요"
```

위에 빈 줄 하나를 두고 붙인다(다른 절과 같은 모양). 태그 오류 문구 상수는 두지 않는다 — pydantic 422 로 나간다.

- [ ] **Step 4: 저장소**

`backend/app/friend_reviews/repository.py`:

```python
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 리뷰 한 장과 작성자(닉네임 · 학교 · 아바타). `!inner` + `reviewer.status=eq.active` 로 작성자가
# active 가 아닌(탈퇴 · 정지) 리뷰는 DB 에서 빠진다 — ERD "작성자 탈퇴 시 즉시 숨김".
_REVIEW_SELECT = (
    "id,reviewer_id,tags,comment,created_at,"
    "reviewer:profiles!friend_reviews_reviewer_id_fkey!inner("
    "nickname,status,universities(name),profile_avatars(storage_path,status,created_at))"
)


class FriendReviewRepository(PostgrestRepository):
    """지인 리뷰. 쓰기가 insert 한 번, 읽기가 embed 한 번이라 DB 함수 없이 PostgREST 로 한다."""

    async def fetch_about(self, reviewee: UUID | str) -> list[dict]:
        """받은 리뷰 최신순. 가려진 것 · 작성자가 active 아닌 것은 빠진다. 차단은 부르는 쪽이 거른다.
        ponytail: 페이지 없음 — 받는 수 = 추천으로 이어진 사람 수라 작다. db-max-rows(1000) 넘으면 커서로."""
        return await self._rows("friend_reviews", {
            "reviewee_id": f"eq.{reviewee}", "status": "eq.visible", "reviewer.status": "eq.active",
            "select": _REVIEW_SELECT, "order": "created_at.desc",
        })

    async def is_linked(self, a: UUID | str, b: UUID | str) -> bool:
        """추천으로 이어졌는가(어느 방향이든). referrals 는 온보딩 탭 표 — 행이 있으면 연결이다(09-28 합의)."""
        rows = await self._rows("referrals", {
            "or": f"(and(referee_id.eq.{a},referrer_id.eq.{b}),and(referee_id.eq.{b},referrer_id.eq.{a}))",
            "select": "referee_id", "limit": "1",
        })
        return bool(rows)

    async def has_written(self, reviewer: UUID | str, reviewee: UUID | str) -> bool:
        rows = await self._rows("friend_reviews", {
            "reviewer_id": f"eq.{reviewer}", "reviewee_id": f"eq.{reviewee}", "select": "id",
        })
        return bool(rows)

    async def fetch_target(self, profile_id: UUID | str) -> dict | None:
        """20b 머리에 그릴 것(닉네임 · 아바타)과 active 판정용 status."""
        rows = await self._rows("profiles", {
            "id": f"eq.{profile_id}",
            "select": "id,nickname,status,profile_avatars(storage_path,status,created_at)",
        })
        return rows[0] if rows else None

    async def insert_review(self, row: dict) -> str:
        response = await self._client.post(
            f"{self._postgrest_url}/friend_reviews", json=row,
            headers=self._with_prefer("return=representation"),
        )
        # 23505 = friend_reviews_once — 동시에 두 번 눌러도 한 줄만 남고 나머지는 409.
        raise_for_status(response, conflict_detail=errors.FRIEND_REVIEW_ALREADY_WRITTEN)
        return response.json()[0]["id"]

    async def fetch_for_report(self, review_id: UUID | str) -> dict | None:
        """신고(B3)용 — 가려진 것까지 읽고 판단은 부르는 쪽이 한다."""
        rows = await self._rows("friend_reviews", {
            "id": f"eq.{review_id}", "select": "id,reviewer_id,reviewee_id,tags,comment,status,created_at",
        })
        return rows[0] if rows else None
```

`_rows` · `_with_prefer` · `self._client` · `self._postgrest_url` 는 `app/core/postgrest.py` 의 `PostgrestRepository` 에 있다(09-28 확인). 부모 클래스는 고치지 않는다.

- [ ] **Step 5: 라우터(읽기 둘)**

`backend/app/friend_reviews/router.py`:

```python
from datetime import datetime
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.cards.router import get_sender, is_active
from app.chat.repository import ChatRepository
from app.chat.router import avatar_url
from app.core import errors
from app.core.deps import Caller, get_now, get_verified_caller
from app.friend_reviews.repository import FriendReviewRepository
from app.safety.router import find_match
from app.settings import Settings

router = APIRouter()


class _Wiring:
    def __init__(self, caller: Caller, sender: FcmSender, now: datetime):
        settings, client, profile_id = caller
        key = settings.supabase_service_role_key
        self.settings: Settings = settings
        self.client: httpx.AsyncClient = client
        # PostgREST 가 돌려주는 id 는 문자열이라 비교가 되게 str 로 맞춘다.
        self.profile_id = str(profile_id)
        self.repo = FriendReviewRepository(settings.postgrest_url, key, client)
        self.cards = CardRepository(settings.postgrest_url, key, client)
        self.chat = ChatRepository(settings.postgrest_url, key, client)
        self.sender = sender
        self.now = now


async def _wire(caller: Caller = Depends(get_verified_caller), sender: FcmSender = Depends(get_sender),
                now: datetime = Depends(get_now)) -> _Wiring:
    return _Wiring(caller, sender, now)


def _item(row: dict, supabase_url: str) -> dict:
    """리뷰 한 장. reviewer_id 는 싣지 않는다 — 14c 를 보는 매칭 상대가 상대 지인의 id 를 알 이유가 없다."""
    reviewer = row["reviewer"]
    return {
        "id": row["id"],
        "reviewer": {
            "nickname": reviewer["nickname"],
            "avatar_url": avatar_url(reviewer, supabase_url),
            "university": (reviewer.get("universities") or {}).get("name"),
        },
        "tags": row["tags"],
        "comment": row["comment"],
        "created_at": row["created_at"],
    }


async def _visible(w: _Wiring, reviewee: str) -> dict:
    """reviewee 가 받은 리뷰 중 지금 보는 사람에게 보여 줄 것(결정 6). DB 가 active · visible 을 거르지만
    한 번 더 본다 — embed 필터 이름이 틀려도 탈퇴자 리뷰가 새지 않게."""
    blocked = await w.cards.fetch_block_partner_ids(w.profile_id)
    rows = await w.repo.fetch_about(reviewee)
    return {"reviews": [
        _item(row, w.settings.supabase_url) for row in rows
        if is_active(row["reviewer"]) and row["reviewer_id"] not in blocked
    ]}


@router.get("/friend-reviews/received")
async def list_received(w: _Wiring = Depends(_wire)) -> dict:
    """20c. 받은 사람은 지울 수 없고 신고만 한다(spec §2.8)."""
    return await _visible(w, w.profile_id)


@router.get("/friend-reviews/about/{profile_id}")
async def list_about(profile_id: UUID, w: _Wiring = Depends(_wire)) -> dict:
    """14c 섹션 · 14d. 여는 조건은 14c(safety GET /profiles/{id})와 같다 — 한쪽만 열리면 차단 · 나감이 샌다."""
    target = str(profile_id)
    match = await find_match(w.chat, w.profile_id, target)
    if any(p["left_at"] for p in match["match_participants"]):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    if await w.cards.fetch_profile_status(target) != "active" \
            or target in await w.cards.fetch_block_partner_ids(w.profile_id):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    return await _visible(w, target)
```

- [ ] **Step 6: main.py 2줄(허락 받은 뒤)**

```python
from app.friend_reviews.router import router as friend_reviews_router
...
app.include_router(friend_reviews_router)
```

import 는 알파벳 자리(`app.core.deps` 다음), include 는 맨 끝 `account_router` 다음.

- [ ] **Step 7: 통과 확인**

Run: `.venv/Scripts/python -m pytest backend/tests/friend_reviews -q`
Expected: PASS(10)

Run: `.venv/Scripts/python -m pytest backend -q`
Expected: 기존 전부 PASS(기준선은 main 에서 먼저 한 번 돌려 적어 둔다)

- [ ] **Step 8: 커밋 제안**(campus-git): `✨ feat(friend-review): 받은 리뷰 · 상대 리뷰 읽기 API` / `✅ test(friend-review): 읽기 · 숨김 테스트`

### Task B2: 쓰기(20b) · 새 리뷰 푸시

**Files:**
- Modify: `backend/app/friend_reviews/router.py`
- Test: `backend/tests/friend_reviews/test_friend_reviews.py`(이어서)

**Interfaces:**
- Consumes: B1 의 `_Wiring` · `FriendReviewRepository.is_linked/has_written/fetch_target/insert_review`, `app.cards.push.notify(repo, sender, profile_id, kind, title, body, data, now)`, `CardRepository.fetch_card_profile(id)`(닉네임)
- Produces: `GET /friend-reviews/targets/{profile_id}`, `POST /friend-reviews`, `TAGS: tuple[str, ...]`, `COMMENT_MAX_LENGTH = 100`, `notify_review_request(cards, sender, referrer_id, referee_id, now)`(B4 가 부름)

- [ ] **Step 1: 실패하는 테스트**

```python
def _write_handler(*, linked=True, status="active", written=False, blocked=None, insert: httpx.Response | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        table = _table(request)
        if table == "referrals":
            return httpx.Response(200, json=[{"referee_id": ME}] if linked else [])
        if table == "profiles":
            return httpx.Response(200, json=[{"id": FRIEND, "nickname": "달빛", "status": status,
                                              "profile_avatars": []}])
        if table == "blocks":
            return httpx.Response(200, json=blocked or [])
        if table == "friend_reviews" and request.method == "GET":
            return httpx.Response(200, json=[{"id": REVIEW_ID}] if written else [])
        if table == "friend_reviews" and request.method == "POST":
            return insert or httpx.Response(201, json=[{"id": REVIEW_ID}])
        # 푸시 쪽(알림 설정 · 토큰 · FCM)은 빈 값으로 흘려보낸다.
        return httpx.Response(200, json=[])
    return handler


def test_target_gives_header_fields():
    response = _wire(_write_handler()).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json() == {"profile_id": FRIEND, "nickname": "달빛", "avatar_url": None}


def test_unlinked_target_is_404():
    # Review Focus 5
    response = _wire(_write_handler(linked=False)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 404


@pytest.mark.parametrize("kwargs", [{"status": "suspended"}, {"status": "withdrawn"},
                                    {"blocked": [{"blocker_id": ME, "blocked_id": FRIEND}]}])
def test_target_inactive_or_blocked_is_404(kwargs):
    response = _wire(_write_handler(**kwargs)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 404


def test_target_self_is_404():
    response = _wire(_write_handler()).get(f"/friend-reviews/targets/{ME}", headers=AUTH_HEADERS)
    assert response.status_code == 404


def test_target_already_written_is_409():
    response = _wire(_write_handler(written=True)).get(f"/friend-reviews/targets/{FRIEND}", headers=AUTH_HEADERS)
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN


def _post(client: TestClient, **body):
    payload = {"reviewee_id": FRIEND, "tags": ["약속을 잘 지켜요"], "comment": None, **body}
    return client.post("/friend-reviews", json=payload, headers=AUTH_HEADERS)


def test_create_inserts_trimmed_row():
    seen: list[httpx.Request] = []
    response = _post(_wire(_write_handler(), seen), tags=["성실해요", "다정해요"], comment="  믿음직해요 ")
    assert response.status_code == 201
    assert response.json() == {"id": REVIEW_ID}
    insert = next(r for r in seen if _table(r) == "friend_reviews" and r.method == "POST")
    assert json.loads(insert.content) == {"reviewer_id": ME, "reviewee_id": FRIEND,
                                          "tags": ["성실해요", "다정해요"], "comment": "믿음직해요"}


def test_blank_comment_becomes_null():
    seen: list[httpx.Request] = []
    _post(_wire(_write_handler(), seen), comment="   ")
    insert = next(r for r in seen if _table(r) == "friend_reviews" and r.method == "POST")
    assert json.loads(insert.content)["comment"] is None


@pytest.mark.parametrize("tags", [[], ["성실해요", "솔직해요", "다정해요", "차분해요"], ["잘생겼어요"], ["성실해요", "성실해요"]])
def test_bad_tags_are_422(tags):
    assert _post(_wire(_write_handler()), tags=tags).status_code == 422


def test_comment_over_100_is_422():
    assert _post(_wire(_write_handler()), comment="가" * 101).status_code == 422


def test_second_review_is_409():
    # 확인과 insert 사이에 다른 요청이 먼저 넣었다 — unique 가 막는다(Review Focus 3).
    conflict = httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
    response = _post(_wire(_write_handler(insert=conflict)))
    assert response.status_code == 409
    assert response.json()["detail"] == errors.FRIEND_REVIEW_ALREADY_WRITTEN


def test_create_unlinked_is_404_and_inserts_nothing():
    seen: list[httpx.Request] = []
    assert _post(_wire(_write_handler(linked=False), seen)).status_code == 404
    assert not any(_table(r) == "friend_reviews" and r.method == "POST" for r in seen)


def test_create_pushes_reviewee_with_new_friend_review(monkeypatch):
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, data))
        return 1

    monkeypatch.setattr(router_module, "notify", fake_notify)
    _post(_wire(_write_handler()))
    assert calls == [(FRIEND, "new_friend_review", {"route": "friend_reviews"})]
```

파일 맨 위 import 에 `import json` 을 더한다.

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest backend/tests/friend_reviews -q`
Expected: 새 테스트 FAIL(404 Not Found — 경로 없음)

- [ ] **Step 3: 구현**

`router.py` 에 더한다(import 에 `from pydantic import BaseModel, Field, field_validator`, `from app.cards.push import FcmSender, notify`):

```python
# DESIGN §13-25 순서 그대로. 앱 friendReviewTags 와 같은 목록이다. 외모 태그는 넣지 않는다.
TAGS = (
    "약속을 잘 지켜요", "대화가 편해요", "배려가 깊어요", "유머 감각이 좋아요", "성실해요", "솔직해요",
    "이야기를 잘 들어줘요", "긍정적이에요", "센스 있어요", "다정해요", "차분해요", "리액션이 좋아요",
)
# 앱 friendReviewMaxTags · friendReviewCommentMaxLength, DB friend_reviews_* check 와 같은 값이다.
MAX_TAGS = 3
COMMENT_MAX_LENGTH = 100


class ReviewRequest(BaseModel):
    reviewee_id: UUID
    tags: list[str] = Field(min_length=1, max_length=MAX_TAGS)
    comment: str | None = Field(default=None, max_length=COMMENT_MAX_LENGTH)

    @field_validator("tags")
    @classmethod
    def _known_tags(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value) or any(tag not in TAGS for tag in value):
            raise ValueError("12종 목록 안에서 서로 다른 태그만 받는다")
        return value

    @field_validator("comment")
    @classmethod
    def _trim(cls, value: str | None) -> str | None:
        # 공백뿐이면 한마디가 없는 것이다 — DB check 는 빈 글을 막으므로 null 로 넣는다.
        return (value or "").strip() or None


async def _writable_target(w: _Wiring, target: str) -> dict:
    """20b 를 열거나 저장할 수 있는 상대인가. 이유를 가르지 않고 전부 같은 404 — 있다는 사실도 알리지 않는다.
    이미 썼으면 409(앱이 시트 대신 토스트)."""
    if target == w.profile_id or not await w.repo.is_linked(w.profile_id, target):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    profile = await w.repo.fetch_target(target)
    if profile is None or not is_active(profile) \
            or target in await w.cards.fetch_block_partner_ids(w.profile_id):
        raise HTTPException(status_code=404, detail=errors.PROFILE_NOT_FOUND)
    if await w.repo.has_written(w.profile_id, target):
        raise HTTPException(status_code=409, detail=errors.FRIEND_REVIEW_ALREADY_WRITTEN)
    return profile


@router.get("/friend-reviews/targets/{profile_id}")
async def get_target(profile_id: UUID, w: _Wiring = Depends(_wire)) -> dict:
    """20b 머리(상대 아바타 + 닉네임). 온보딩(20 뒤)과 추천인 푸시 양쪽이 연다."""
    profile = await _writable_target(w, str(profile_id))
    return {"profile_id": profile["id"], "nickname": profile["nickname"],
            "avatar_url": avatar_url(profile, w.settings.supabase_url)}


@router.post("/friend-reviews", status_code=201)
async def create_review(body: ReviewRequest, w: _Wiring = Depends(_wire)) -> dict:
    """20b "리뷰 남기기". 저장한 뒤 받은 사람에게 푸시(결정 8). 푸시가 실패해도 저장은 그대로다."""
    target = str(body.reviewee_id)
    await _writable_target(w, target)
    review_id = await w.repo.insert_review({
        "reviewer_id": w.profile_id, "reviewee_id": target, "tags": body.tags, "comment": body.comment,
    })
    me = await w.cards.fetch_card_profile(w.profile_id)
    await notify(w.cards, w.sender, target, "new_friend_review", "새 지인 리뷰가 도착했어요",
                 f"{me['nickname']} 님이 리뷰를 남겼어요", {"route": "friend_reviews"}, now=w.now)
    return {"id": review_id}


async def notify_review_request(cards: CardRepository, sender: FcmSender, referrer_id: str,
                                referee_id: str, now: datetime) -> None:
    """추천 연결 순간 추천인에게 "가입했어요, 리뷰를 남겨 주세요"(결정 8). redeem 경로가 한 줄로 부른다(Task B4)."""
    referee = await cards.fetch_card_profile(referee_id)
    await notify(cards, sender, referrer_id, "new_friend_review", "친구가 가입했어요",
                 f"{referee['nickname']} 님이 가입했어요, 리뷰를 남겨 주세요",
                 {"route": "friend_review_write", "profile_id": referee_id}, now=now)
```

`fetch_card_profile` 은 `profiles` 첫 행을 그대로 돌려주고 여기서는 `nickname` 만 읽는다 · `notify()` 는 `notification_settings` 가 빈 배열이면 기본값을 쓴다(09-28 확인) — 목의 마지막 갈래(빈 배열)로 충분하다.

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest backend/tests/friend_reviews -q`
Expected: PASS

- [ ] **Step 5: `notify_review_request` 테스트 하나**

```python
def test_review_request_push_goes_to_referrer_with_write_route(monkeypatch):
    import asyncio
    calls = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, data))
        return 1

    class _Cards:
        async def fetch_card_profile(self, profile_id):
            return {"nickname": "새싹"}

    monkeypatch.setattr(router_module, "notify", fake_notify)
    asyncio.run(router_module.notify_review_request(_Cards(), None, FRIEND, ME, None))
    assert calls == [(FRIEND, "new_friend_review", {"route": "friend_review_write", "profile_id": ME})]
```

Run: `.venv/Scripts/python -m pytest backend/tests/friend_reviews -q` → PASS

- [ ] **Step 6: 커밋 제안**: `✨ feat(friend-review): 20b 대상 확인 · 리뷰 저장 · 새 리뷰 푸시` / `✅ test(friend-review): 쓰기 · 자격 · 푸시 테스트`

### Task B3: 신고 대상 `friend_review`(안전담당 파일 — 허락 뒤)

**Files:**
- Modify: `backend/app/safety/router.py`(`ReportRequest` · `report()` · 새 함수 `_friend_review_target`)
- Test: `backend/tests/safety/test_report_friend_review.py`

**Interfaces:**
- Consumes: `FriendReviewRepository.fetch_for_report(review_id)`, 기존 `report()` 순서 ①~⑦
- Produces: `POST /reports` 가 `target_type="friend_review"` 를 받는다

- [ ] **Step 1: 실패하는 테스트** — `tests/safety/conftest.py` 의 `client` · `world`(FakeSupabase) 를 그대로 쓴다. `fake_supabase.py` 는 고치지 않고, 이 파일에서 `world._friend_reviews` 를 인스턴스에 끼운다(`handle()` 이 `getattr(self, f"_{table}")` 로 찾는다).

```python
"""지인 리뷰 신고(POST /reports, target_type=friend_review). 차단 · 자동 가림 없이 신고 행과 디스코드만(계획서 P1)."""
import httpx
import pytest

from app.core import errors
from app.core.deps import get_settings
from app.main import app
from fake_supabase import AUTH, ME, PARTNER, REPORT_WEBHOOK, settings

REVIEW_ID = "77777777-7777-7777-7777-777777777777"
OTHER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
OTHER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
# 작성자. 지인 리뷰 작성자는 매칭 상대일 필요가 없지만 fake 세상에 있는 프로필을 그대로 쓴다.
WRITER = PARTNER


@pytest.fixture
def webhook(client):
    app.dependency_overrides[get_settings] = lambda: settings(discord_report_webhook_url=REPORT_WEBHOOK)


@pytest.fixture
def reviews(world) -> dict[str, dict]:
    rows = {REVIEW_ID: {
        "id": REVIEW_ID, "reviewer_id": WRITER, "reviewee_id": ME, "tags": ["성실해요"],
        "comment": "믿음직해요", "status": "visible", "created_at": "2026-09-28T05:00:00+00:00",
    }}

    def table(method, params, body):
        row = rows.get(params.get("id", "").removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    world._friend_reviews = table
    return rows


def _body(**overrides) -> dict:
    return {"target_type": "friend_review", "target_id": REVIEW_ID, "reason": "abuse", **overrides}


def test_friend_review_report_saves_snapshot_without_block(client, world, reviews):
    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "friend_review"
    assert stored["target_id"] == REVIEW_ID
    assert stored["target_profile_id"] == WRITER
    assert stored["target_snapshot"] == {
        "review_id": REVIEW_ID, "tags": ["성실해요"], "comment": "믿음직해요",
        "created_at": "2026-09-28T05:00:00+00:00",
    }
    # P1: 받은 사람이 작성자를 막으면 받은 사람에게만 사라진다 — 차단 · 방 나가기 없음.
    assert world.blocks == []
    assert world.posted_messages == []


@pytest.mark.parametrize("change", [{"reviewee_id": PARTNER}, {"status": "blinded"}])
def test_someone_elses_or_blinded_review_is_404(client, world, reviews, change):
    reviews[REVIEW_ID].update(change)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.FRIEND_REVIEW_NOT_FOUND
    assert world.reports == []


def test_missing_review_is_404(client, world, reviews):
    reviews.clear()

    assert client.post("/reports", json=_body(), headers=AUTH).status_code == 404


def test_friend_review_report_never_auto_hides(client, world, reviews, webhook):
    # 다른 두 사람 + 나 = 신고자 3명이어도 프로필 자동 가림을 찍지 않는다(결정 3). 디스코드는 한 줄.
    world.open_reporters = [OTHER_A, OTHER_B]

    client.post("/reports", json=_body(), headers=AUTH)

    assert world.auto_hide_patches == []
    assert len(world.discord) == 1


def test_duplicate_friend_review_report_is_409(client, world, reviews):
    world.report_insert_status = 409
    world.report_insert_code = "23505"

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.ALREADY_REPORTED
```

- [ ] **Step 2: 실패 확인** — `.venv/Scripts/python -m pytest backend/tests/safety/test_report_friend_review.py -q` → FAIL, 201 기대에 422(Literal 이 막음)

- [ ] **Step 3: 구현**

```python
class ReportRequest(BaseModel):
    # poll 은 DB enum 에는 있지만 그 기능의 신고 입구가 아직 없다 — 여기서 422 로 막는다.
    target_type: Literal["profile", "message", "friend_review"]
```

```python
async def _friend_review_target(wiring: _Wiring, review_id: UUID) -> dict:
    """신고할 리뷰. 내가 받은 것만(20c 에만 입구가 있다) · 가려진 것은 없는 것과 같다 — 전부 같은 404."""
    repo = FriendReviewRepository(wiring.settings.postgrest_url, wiring.settings.supabase_service_role_key,
                                  wiring.client)
    review = await repo.fetch_for_report(review_id)
    if not review or review["reviewee_id"] != wiring.profile_id or review["status"] != "visible":
        raise HTTPException(status_code=404, detail=errors.FRIEND_REVIEW_NOT_FOUND)
    return review
```

`report()` 안:

```python
    # ① 대상 확인 + 접근 권한
    review = None
    if body.target_type == "profile":
        ...  # 그대로
    elif body.target_type == "message":
        ...  # 그대로
    else:
        review = await _friend_review_target(wiring, body.target_id)
        target, match, message = review["reviewer_id"], None, None
```

③ 스냅샷에 `friend_review` 갈래(`{"review_id", "tags", "comment", "created_at"}`), ④ `if review is None: await block_profile(...)`, ⑦ 조건 앞에 `review is None and`. 주석 한 줄: "지인 리뷰 신고는 차단 · 자동 가림을 하지 않는다 — 받은 사람이 작성자를 막으면 받은 사람에게만 사라진다(계획서 P1)".

- [ ] **Step 4: 통과 확인** — `.venv/Scripts/python -m pytest backend -q` → 전부 PASS
- [ ] **Step 5: 커밋 제안**: `✨ feat(safety): 지인 리뷰 신고 대상 열기(차단 · 자동 가림 없음)` / `✅ test(safety): 지인 리뷰 신고`

### Task B4: 추천 연결 푸시 훅(referral merge 뒤 · PR 4)

- [ ] `backend/app/referral/router.py` 의 `# 푸시 훅 자리(채팅탭)` 에 `await notify_review_request(cards, sender, result_referrer_id, str(caller.profile_id), now)` 한 줄. redeem 엔드포인트에 `sender` · `now` 의존성이 없으면 `get_sender` · `get_now` 를 더한다(줄 수는 허락 요청 때 정확히 센다).
- [ ] 테스트: 온보딩 탭 redeem 테스트 파일 모양대로 "200 이면 추천인에게 `friend_review_write` 푸시 한 번 · 404/409/422 면 푸시 없음" 두 개.

---

# Part A — Flutter (pen 값표 뒤 v2 에서 화면 Task 를 채운다)

### Task A1: 모델 · 저장소 · 가짜

**Files:**
- Create: `frontend/lib/friend_review/model/friend_review.dart`, `friend_review_tags.dart`, `friend_review_repository.dart`, `http_friend_review_repository.dart`, `friend_review_repository_provider.dart`
- Test: `frontend/test/friend_review/model/friend_review_test.dart`, `frontend/test/friend_review/model/http_friend_review_repository_test.dart`, `frontend/test/friend_review/model/fake_friend_review_repository.dart`

**Interfaces:**
- Produces:
  - `class FriendReview { String id; String nickname; String? avatarUrl; String? university; List<String> tags; String? comment; DateTime createdAt; factory FriendReview.fromJson(Map<String, dynamic>) }`
  - `class ReviewTarget { String profileId; String nickname; String? avatarUrl; factory ReviewTarget.fromJson(...) }`
  - `const List<String> friendReviewTags`(12종, 서버 `TAGS` 와 같은 순서), `const int friendReviewMaxTags = 3`, `const int friendReviewCommentMaxLength = 100`
  - `abstract interface class FriendReviewRepository { Future<Result<List<FriendReview>>> fetchAbout(String profileId); Future<Result<List<FriendReview>>> fetchReceived(); Future<Result<ReviewTarget>> fetchTarget(String profileId); Future<Result<void>> create({required String revieweeId, required List<String> tags, String? comment}); }`
  - `final friendReviewRepositoryProvider = Provider<FriendReviewRepository>(...)`

- [ ] **Step 1: 실패하는 테스트**

```dart
// friend_review_test.dart
test('fromJson 은 reviewer 를 펼치고 시각을 UTC 로 읽는다', () {
  final review = FriendReview.fromJson({
    'id': 'r1',
    'reviewer': {'nickname': '달빛', 'avatar_url': null, 'university': '테스트대학교'},
    'tags': ['약속을 잘 지켜요'],
    'comment': null,
    'created_at': '2026-09-28T05:00:00+00:00',
  });
  expect(review.nickname, '달빛');
  expect(review.university, '테스트대학교');
  expect(review.comment, isNull);
  expect(review.createdAt, DateTime.utc(2026, 9, 28, 5));
});

test('태그 목록은 서버 TAGS 와 같은 12종 · 외모 태그 없음', () {
  expect(friendReviewTags, hasLength(12));
  expect(friendReviewTags.first, '약속을 잘 지켜요');
  expect(friendReviewTags.last, '리액션이 좋아요');
});
```

```dart
// http_friend_review_repository_test.dart — 기존 http_safety_repository_test 의 가짜 ApiClient 방식 그대로
test('create 는 POST /friend-reviews 에 다듬은 한마디를 싣고, 빈 한마디는 null', ...);
test('fetchAbout 은 GET /friend-reviews/about/{id} 의 reviews 를 읽는다', ...);
test('fetchReceived 는 GET /friend-reviews/received', ...);
test('fetchTarget 은 GET /friend-reviews/targets/{id}', ...);
```

도우미는 `frontend/test/safety/model/http_safety_repository_test.dart` 를 먼저 읽고 같은 가짜 · 같은 단언 모양으로 몸통을 채운다(요청 메서드 · 경로 · 바디 · 파싱 결과 네 가지를 본다).

- [ ] **Step 2: 실패 확인** — `cd frontend && flutter test test/friend_review/model` → 컴파일 FAIL(파일 없음)
- [ ] **Step 3: 구현** — `HttpSafetyRepository` 모양 그대로(`_api.send(method, path, parse, body:)`). `create` 의 한마디는 `trim()` 후 비면 null. 가짜는 `FakeSafetyRepository` 처럼 결과 필드 + 호출 기록 + `Completer? hold…`.
- [ ] **Step 4: 통과 확인** — `flutter test test/friend_review/model` → PASS, `flutter analyze` → 0
- [ ] **Step 5: 커밋 제안**: `✨ feat(friend-review): 모델 · 저장소`

### Task A2: ViewModel 두 개(20b 작성 / 목록 공용)

**Files:**
- Create: `frontend/lib/friend_review/viewmodel/friend_review_compose_ui_state.dart`, `friend_review_compose_view_model.dart`, `friend_review_list_ui_state.dart`, `friend_review_list_view_model.dart`
- Test: `frontend/test/friend_review/viewmodel/friend_review_compose_view_model_test.dart`, `friend_review_list_view_model_test.dart`

**Interfaces:**
- Produces:
  - `friendReviewComposeViewModelProvider` = `NotifierProvider.autoDispose.family<FriendReviewComposeViewModel, FriendReviewComposeUiState, String>`(인자 = 상대 profileId)
  - `FriendReviewComposeUiState { bool isLoading; ReviewTarget? target; bool alreadyWritten; String? loadError; List<String> selected; String comment; bool isSubmitting; bool submitted; String? submitError; bool get canSubmit => selected.isNotEmpty && !isSubmitting; }`
  - `toggleTag(String)` — 이미 있으면 뺀다, 3개면 무시 · `setComment(String)` · `Future<void> submit()`
  - `enum FriendReviewListSource { about, received }` · `friendReviewListViewModelProvider` = `NotifierProvider.autoDispose.family<FriendReviewListViewModel, FriendReviewListUiState, ({FriendReviewListSource source, String? profileId})>`
  - `FriendReviewListUiState { bool isLoading; List<FriendReview> reviews; String? errorMessage; }`

- [ ] **Step 1: 실패하는 테스트**

```dart
test('열면 대상을 읽는다', () async { /* fake.target = Success(ReviewTarget(...)) → state.target.nickname == '달빛' */ });
test('open 이 409 면 alreadyWritten 이고 시트를 띄우지 않을 근거가 된다', () async {
  /* fake.target = Failure(Conflict('이미 리뷰를 남겼어요')) → state.alreadyWritten == true */
});
test('태그는 세 개까지 — 네 번째는 무시한다', () { /* 4번 toggle → selected.length == 3, 네 번째 없음 */ });
test('고른 태그를 다시 누르면 빠진다', () {});
test('태그가 없으면 canSubmit 이 false', () {});
test('submit 은 고른 순서 그대로 태그와 한마디를 보낸다', () async {});
test('submit 중에 한 번 더 눌러도 한 번만 보낸다', () async { /* holdCreate Completer */ });
test('submit 이 409 면 submitted 가 아니라 submitError', () async {});
test('목록 about 은 fetchAbout(profileId), received 는 fetchReceived 를 부른다', () async {});
test('목록 실패는 errorMessage', () async {});
```

실패 타입 이름(`Conflict` 등)은 `frontend/lib/common/result.dart` · `failure.dart` 에 있는 실제 이름을 쓴다(도우미가 먼저 읽는다). 409 판별은 상태코드로 한다(문구 비교 금지 — 백로그 47 과 같은 함정).

- [ ] **Step 2: 실패 확인** — `flutter test test/friend_review/viewmodel` → FAIL
- [ ] **Step 3: 구현** — `BlockListViewModel` 모양(`Future.microtask(_load)` · `ref.mounted` 확인 · `result.when`).
- [ ] **Step 4: 통과 확인** — `flutter test test/friend_review` → PASS · `flutter analyze` → 0
- [ ] **Step 5: 커밋 제안**: `✨ feat(friend-review): 작성 · 목록 ViewModel`

### Task A3: `FriendReviewCard`(S0MR2b) — v2(09-29)

**Files:** Create `frontend/lib/friend_review/view/friend_review_card.dart` · Test `frontend/test/friend_review/view/friend_review_card_test.dart`

**Interfaces:** `class FriendReviewCard extends StatelessWidget { const FriendReviewCard({required FriendReview review, VoidCallback? onReport}); }` · `const String friendReviewRelationLabel = '추천으로 연결된 친구';`(20b 머리도 쓴다) · 이니셜 원을 20b 가 44 로 다시 쓰도록 `FriendReviewInitial({required String nickname, required double size, required TextStyle style})` 공개

값은 화면 대조표 "카드" 줄 + 값표 §3. 폭은 부모가 준다(20c · 14d 328, 14c 288).

- [ ] **Step 1: 실패하는 테스트**
  - 순서: 학교 배지(학교명 첫 글자) · 이니셜(닉네임 첫 글자) · 닉네임 · 관계 문구 · 태그 칩 · 한마디가 있다
  - `university` null → 배지 없음 · `comment` null → 한마디 줄 없음(카드 높이가 줄어든다)
  - `onReport` null → flag 아이콘 없음 / 있으면 누름칸 48×48 · 누르면 한 번 불림
  - 태그 3개가 좁은 폭(288)에서 넘치지 않는다(`Wrap`)
  - 글자 크기 1.3 배에서 잘림 · overflow 0(메모 project_ui_handoff 방식)
- [ ] **Step 2: RED** — `flutter test test/friend_review/view/friend_review_card_test.dart`
- [ ] **Step 3: 구현** — 토큰(`AppColors.surfaceInk` · `primaryWash` · `primaryText` · `hairline` · `ink` · `muted` · `body`), 토큰에 없는 값은 파일 위 `const` + pen id 주석(referral_code_screen.dart 모양). 아바타 이미지 · avatar_url 은 쓰지 않는다(pen 이니셜)
- [ ] **Step 4: GREEN** + `flutter analyze` 0

### Task A4: 20b 리뷰 쓰기 시트 · 홈 위 경로 — v2(09-29)

**Files:** Create `frontend/lib/friend_review/view/friend_review_compose_sheet.dart` · Test `frontend/test/friend_review/view/friend_review_compose_sheet_test.dart` · Modify(허락) `app_router.dart` home `GoRoute` 에 `routes:`

**Interfaces:**
- `Future<bool?> showFriendReviewComposeSheet(BuildContext context, String revieweeId)` — 온보딩(PR 4)이 부른다. 남기면 true
- `FriendReviewComposePage(revieweeId)` — `Page` 를 상속해 `ModalBottomSheetRoute` 를 만드는 페이지. 홈 `GoRoute(routes: [GoRoute(path: 'friend-reviews/write/:profileId', pageBuilder: …)])` 가 쓴다. 푸시 `go('/home/friend-reviews/write/p2')` → 홈이 밑에 깔리고 시트가 뜬다(대장 Q1)
- 두 길 다 같은 `FriendReviewComposeSheet(revieweeId)` 본문

값은 화면 대조표 "20b" 줄 + 값표 §1. 시트 높이 664 · 딤 #00000080(`AppColors.scrim` 이 0.5 면 그것) · 손잡이 r999 · 제목/X 없음.

- [ ] **Step 1: 실패하는 테스트**(가짜 저장소 = `fake_friend_review_repository.dart`)
  - 대상 이름 · 관계 문구 · 이니셜 · 질문 두 줄 · 칩 12개(서버 순서) · placeholder · "0 / 100" · "리뷰 남기기"
  - 태그 0개 → 버튼 꺼짐(primaryDisabled / disabled 글자) · 1개 → 켜짐 · 네 번째 칩은 눌러도 안 골라진다
  - 칩 누름 영역 높이 ≥ 44 · 보이는 칩 40(대장 7) · 칩마다 잉크가 자기 모양 안(§4-2)
  - 한마디 100자 넘게 못 친다 · 카운터가 따라간다
  - 보내는 중 버튼 안 스피너 · 두 번 눌러도 한 번
  - 성공 → 시트 닫힘 + 토스트 "리뷰를 남겼어요"(pen · v1 에 문구 없음 — 채팅탭 안, 대장에게 알림 09-29) · 결과 true
  - 열 때 409 → 시트 대신 토스트 "이미 리뷰를 남겼어요" 뒤 닫힘 · 제출 409 · 기타 실패 → 토스트, 시트 유지
  - 열 때 읽는 중 → 시트 안 가운데 로딩 · 실패 → 토스트 뒤 닫힘
  - 12종이 664 안에 안 들어가도 overflow 0(가운데 스크롤, 버튼 바닥 고정) · 키보드가 올라와도 overflow 0 · 글자 1.3 배 overflow 0
  - 경로: `go('/home/friend-reviews/write/p2')` → HomeScreen 위에 시트, 닫으면 HomeScreen(app_router_test)
- [ ] **Step 2: RED** · **Step 3: 구현** · **Step 4: GREEN** + analyze 0

### Task A5: 14c 섹션 · 14d 시트 — v2(09-29)

**Files:** Create `frontend/lib/friend_review/view/partner_reviews_section.dart` · Test `frontend/test/friend_review/view/partner_reviews_section_test.dart` · Modify(허락) `partner_profile_screen.dart` 약 +5

**Interfaces:** `PartnerReviewsSection({required String profileId, required String nickname})` · `Future<void> showPartnerReviewsSheet(BuildContext, {required String profileId, required String nickname})`(같은 family 인자 `(source: about, profileId:)` 라 다시 읽지 않는다)

- [ ] **Step 1: 실패하는 테스트**
  - 0개 · 읽는 중 · 실패 → `SizedBox.shrink()`(P6, 14c 가 흔들리지 않게)
  - 1개 → 카드 1장, "모두 보기" 없음 · 2개 → 2장, 없음 · 3개 이상 → 2장 + "N개 모두 보기"(편차: 2개 이하면 다 보인다)
  - "모두 보기" 누름 영역 ≥ 44(대장 7 — 보이는 85×17 은 그대로, 주변 칸을 누름 영역으로. `_Footer` 링크 줄과 같은 방식)
  - 깃발 없음(14c · 14d 둘 다, 대장 Q2)
  - 14d: 제목 "친구들이 본 {닉네임}" · "리뷰 N개" · 카드 전부 · 끝 안내 상자 · 닫기 버튼 없음 · 카드 10개여도 overflow 0(화면 90% 까지 스크롤)
  - 14c 화면 테스트(partner_profile_screen_test 에 한 개): 리뷰가 있으면 섹션이 이상형 메모 뒤 · 카카오 카드 앞에 있다
- [ ] **Step 2: RED** · **Step 3: 구현** — `_Footer` 에 `reviews` 위젯 자리 하나, 간격은 대조표(13 → 헤더 → 8 → 카드 → 8 → 카드 → 13) · **Step 4: GREEN** + analyze 0

### Task A6: 20c 받은 리뷰 화면 · 신고 — v2(09-29)

**Files:** Create `frontend/lib/friend_review/view/received_reviews_screen.dart` · Test `frontend/test/friend_review/view/received_reviews_screen_test.dart` · Modify(허락) `app_router.dart` `_slice6Routes` 끝 `GoRoute(path: AppRoutes.friendReviews, …)`

- [ ] **Step 1: 실패하는 테스트**
  - 앱바: 뒤로(48) + "받은 리뷰" · 하단 내비 없음 · 안내 상자 문구 · 카드마다 깃발
  - 깃발 → 신고 시트(`showReportSheet(context, ReportTarget.friendReview(id))`) · 보낸 target = `{'target_type': 'friend_review', 'target_id': id}`
  - 결과 reported → 토스트 "신고했어요. 운영팀이 확인할게요"(대장 9) · alreadyReported → 서버 문구 · 카드는 그대로(결정 3) · 화면을 떠나지 않는다 · 차단 문구 없음(P1)
  - 0개 → 빈 상태(기존 앱 빈 상태 모양, 문구 "아직 받은 리뷰가 없어요") · 읽는 중 → 로딩 · 실패 → 문구 + 다시 시도 · 안내 상자는 늘 보인다
  - 글자 1.3 배 overflow 0
- [ ] **Step 2: RED** · **Step 3: 구현** — `reportThenLeave` 는 쓰지 않는다 · **Step 4: GREEN** + analyze 0

### Task A7: 연결 줄(PR 4 — 각 선행 PR merge 뒤)

- [ ] 온보딩 20 → 20b: referral PR 이 남긴 `// 20b 자리` 에 20b 여는 한 줄(모양은 D-A 결정대로), 닫힌 뒤 원래 흐름(20d)
- [ ] 15 → 20c: 나 탭 PR merge 뒤 `my_profile_screen.dart` `ZCpM4` 입구 한 줄(`context.push(AppRoutes.friendReviews)`)
- [ ] B4 훅
- [ ] 각 연결마다 화면 테스트 한 개(누르면 그 경로로 간다 / 푸시 한 번)

---

## 테스트 목록 요약

| 층 | 파일 | 개수(예상) |
|---|---|---|
| pgTAP | `supabase/tests/friend_reviews_test.sql` | 15 |
| pytest | `backend/tests/friend_reviews/test_friend_reviews.py` | 약 22 |
| pytest | `backend/tests/safety/test_report_friend_review.py` | 5 |
| flutter | `test/friend_review/model` · `viewmodel` | 약 16 |
| flutter | 화면(A3~A7) | v2 에서 셈 |

## 문서 갱신 대상(조각 끝 문서 정리 때 — 지금 PR 금지)

- `docs/ERD.md` §6 `friend_reviews` 비고: 제약 이름 · 태그 개수 확정(검토7 해결: 최소 1), §10 미결 7 해결 표시
- `frontend/docs/DESIGN.md` §8.8 · §9 20b/20c: 진입 두 곳 · 409 토스트 · 신고는 차단 없음(P1)
- spec §2.8: "리뷰 신고는 차단하지 않는다"(P1) · 작성자 삭제 화면 백로그(결정 2)

## 구현 편차 기록

### Part B 서버(B1 · B2 · B3, 2026-09-28)

- **`_rows` 는 부모에 없다.** `PostgrestRepository` 에는 `_get` · `_post` 뿐이고 `_rows` 는 저장소마다 따로 둔다(cards · chat · safety 와 같은 모양). `FriendReviewRepository` 도 자기 `_rows` 를 두고, `insert_review` 는 `self._client.post` 대신 부모 `_post(..., prefer="return=representation")` 를 쓴다. 부모는 고치지 않았다.
- **`tests/**/__init__.py` 를 만들지 않았다.** 저장소 tests 아래 어디에도 `__init__.py` 가 없다(rootdir 방식). 파일 이름이 겹치지 않아 그대로 모인다.
- **한마디 길이는 깎은 뒤에 잰다.** 계획서 코드(after 검사)는 `max_length` 를 깎기 전 글에 걸어 "가"×100 앞뒤 공백을 422 로 막는다. Global Constraints("앞뒤 공백을 깎아 1~100자")대로 `mode="before"` 로 깎는다. 테스트 `test_comment_length_counts_after_trim` 추가.
- **테스트를 더했다(계획서 테스트는 그대로 두고).** `test_about_follows_14c_404_rules` 에 `blocked` 갈래(14c 404 규칙 중 테스트가 없던 것) · `test_target_asks_referrals_both_ways`(결정 1 양방향 `or`) · `test_create_already_written_is_409_and_inserts_nothing` · safety `test_friend_review_report_keeps_daily_limit`(② 하루 상한). 404 테스트들은 경로가 없어도 404 라 RED 가 엉뚱하게 통과했다 — `detail == PROFILE_NOT_FOUND` 단언을 더했다.
- **`errors.py` 는 +4 그대로** — 쓰는 곳이 없는 `FRIEND_REVIEW_TAG_INVALID`(태그 오류는 pydantic 422)를 빼고 그 줄로 절 앞 빈 줄을 뒀다(허락: 통합대장 09-28).
- **기존 `tests/safety/test_reports.py:210` `test_unknown_targets_and_reasons_are_422[friend_review]` 가 깨진다.** 이 PR 이 일부러 연 동작("friend_review 는 422")을 못 박은 갈래다. 대장 허락(09-28)으로 그 갈래와 ids 의 "friend_review" 를 뺐다(-2 +1). poll 422 갈래는 남고, friend_review 신고는 `test_report_friend_review.py` 가 지킨다.

### Part A 앱(A1 · A2, 2026-09-28)

- **409 는 문구로 가른다(A2 "상태코드로" 와 다름).** `core/http/http_send.dart` 가 429 · 5xx 밖의 4xx 를 상태코드 없이 `ServerRejectedFailure(detail)` 로 묶는다 — 공유 파일을 고치지 않고는 상태코드를 볼 수 없다. `safety_errors.dart` · `chat_errors.dart` 와 같은 자리에 `friend_review_errors.dart` 의 `isAlreadyWritten` 을 두고, 문구는 서버 `FRIEND_REVIEW_ALREADY_WRITTEN` 과 바이트까지 같다. 백로그 47(서버 `code` 필드) 대상에 이 파일을 더한다.

### Part A 앱 화면(A3~A6, 2026-09-29)

pen 과 다르게 한 곳
- **이니셜 원만 그린다.** 카드 · 20b 머리 모두 pen 대로 이니셜(닉네임 첫 글자). 서버 `avatar_url` 은 그리지 않는다(대장 09-29). 이니셜 · 학교 배지 글자 줄높이는 1(pen 1.5) — 가운데 정렬이라 보이는 자리는 같고 배율 2.0 에서 원 안에 든다. 학교 null 이면 배지 없음.
- **관계 줄 = 고정 "추천으로 연결된 친구"**(대장 Q3 가). DB · API 에 관계 칸이 없고 추천은 학교를 따지지 않는다.
- **카드 태그는 `Wrap`**(3개가 한 줄에 안 들어가면 다음 줄, 줄 사이 8). 한마디는 말줄임 없이 다 보이고 없으면 줄 · 간격이 없다. 머리 · 칩 · 버튼 높이는 고정 대신 minHeight(글자 확대).
- **20c 안내 글 폭** fill(pen 270 고정) — 328 폭에서 결과 같다.
- **14c · 14d 깃발 없음**(대장 Q2 — 서버가 받은 사람만 신고 허용, P2). 20c 만 깃발.
- **14c "N개 모두 보기"는 3개 이상일 때만.** 누름 영역 44: 헤더 20 + 간격 8 + 첫 카드 위 여백 16 을 덮는 투명 칸을 줄 전체 폭으로 올렸다(위 13 은 앞 칸 몫). 높이는 보이지 않는 헤더 사본(`Visibility.maintain`)으로 재 배율을 키워도 덮는다.
- **14d 높이** hug · 화면 90% 넘으면 스크롤. 딤 = `AppColors.scrim`(pen 은 시트만). 그림자 `Color(0x26000000)` (0,-2) 16 · 손잡이 r2 는 토큰 밖 리터럴(pen `FXNL4` · `w8UdMw`).
- **20b 가운데 스크롤 · 버튼 바닥 고정**(12종이라 664 를 넘는다). 키보드가 오면 시트가 줄고 버튼은 키보드 위 24.
- **20b 칩** 보이는 40 · 누름 48(TextButton padded) → 격자 위아래 간격을 16 − 4 로 잡아 보이는 자리를 pen 과 맞춤. 칩 안 좌우 여백 8 은 pen 에 없음(줄바꿈 때 곡선에 글자가 붙지 않게).
- **20b 카운터 "n / 100"**(대장 1), 코드포인트 기준 · 신고 메모와 같은 formatter.
- **20b 손잡이** pen 대로 r999 — 조각 6 `SheetHandle`(r8) 안 씀.

pen 에 없어 정한 곳(대장 4 · 9 기존 모양)
- 20b 버튼: 꺼짐 primaryDisabled 바탕 · disabled 글자, 보내는 중 평상시 색 위 흰 스피너 20(`_SubmitButton` — 조각 6 시트 버튼에 스피너 상태가 없다).
- 20b 토스트(`showSafetyToast`): 성공 "리뷰를 남겼어요"(대장 09-29) · 열 때 409 "이미 리뷰를 남겼어요" · 열 때 실패 → 밑 화면에 띄우고 닫는다. 낼 때 실패(409 포함) → 시트 안(ScaffoldMessenger + 투명 Scaffold, 시트가 밑 화면 토스트를 가려서), 시트 유지. 열 때 읽는 중 = 가운데 스피너만.
- 20c: 빈 상태 = 16f 모양(마스코트 120 → 24 → "아직 받은 리뷰가 없어요"), 실패 = 문구 + "다시 시도", 안내 상자는 늘. 신고 reported → "신고했어요. 운영팀이 확인할게요"(대장 9), 그 밖은 신고 시트 문구, 화면에 남고 차단 없음. 돌아갈 곳이 없으면(푸시 `go`) 뒤로 = `/me`(PopScope, 백로그 23 방식). 뒤로 = lucide arrow-left 22 IconButton(pen `miO1L`).
- 20b 경로는 홈 하위 `friend-reviews/write/:profileId` → `FriendReviewComposePage`(ModalBottomSheetRoute 를 만드는 Page, 대장 Q1 가).

공유 파일(허락 · 통합대장 09-29): app_routes +3 · push_route +6 · safety_repository +4 −2 · safety_errors +3 −2 · app_icons +2(info — pen `PMMX8` · `z5kJa6`, circle-alert 와 그림이 다르다) · partner_profile_screen +6 −1(클래스 주석 한 줄 포함) · app_router +15 −1 · app_router_test +29 · partner_profile_screen_test +26 −1 · push_route_test +13.

검토(09-29) 반영
- **필수 1** 20b 가 닫히는 중(뒤로 · 바깥 탭 애니메이션)에 응답이 오면 조건 없는 `pop` 이 밑 화면을 꺼냈다 — 푸시로 연 홈 위 시트면 go_router 가 "마지막 페이지" 단정으로 깨진다. `close()` 가 `ModalRoute.isCurrentOf` 일 때만 닫는다(poll_sheets 와 같은 방어) + 회귀 테스트.
- **권고 1** 리뷰 신고 404 "리뷰를 찾을 수 없어요" 를 `isReportTargetGone` 이 몰라 시트가 안 닫혔다 → `safety_errors.dart` +3 −2(허락: 통합대장 09-29) + 20c 테스트.
- 사소: 20b `useSafeArea`(낮은 화면에서 손잡이가 상태 표시줄 밑) · 14c 누름칸 높이 사본 `ExcludeSemantics`("지인 리뷰" 두 번 낭독) + 낭독 테스트.
- 백로그 73 = main `report_sheet.dart:55` 같은 경합 · 74 = 리뷰 두 번 신고 토스트 "이미 신고한 사용자예요"(서버 문구 손볼 때).

### Part C DB(C1, 2026-09-28)

- **pgTAP 준비에 `university_email_domains` 한 줄을 넣고 `profiles` 직접 insert 를 뺐다.** 가입 트리거(`handle_new_user`)가 도메인이 없으면 예외를 내고, `profiles` 행은 트리거가 만든다(`referral_test.sql` 과 같은 준비). 파일 이름은 `20260928040000_create_friend_reviews.sql`(대장 09-28), `rls_slice0_test.sql` 권한 전수 표 +4(허락: 통합대장 09-28).
- **pgTAP 15 → 18(검토 권고 1 · 사소 1).** 받은 사람 계정 삭제 cascade · 서버 embed 가 기대는 FK 이름 두 개와 `confdeltype = 'c'` · `policies_are` 정책 0 을 더했다. 전체 12파일 355 PASS.
