# 커뮤니티 탭: 익명 O/X 투표 + 투표 하트 보상 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다. PR 도 이 순서로 셋이다(아래 "PR 나누기").
> **Part C 는 통합대장이 "DB 차례"를 준 뒤에만** 마이그레이션 파일을 만들고 `supabase db reset` · `supabase test db`
> 를 돌린다. 클라우드 적용은 ERD 그림 확인 → 사용자 검토 → 사용자 승인 뒤 통합대장이 한다.
> **pen 값표(1~9절 + 10절 "수정 뒤", 2026-09-27)를 화면 대조표와 Part A 코드에 넣었다.** 사용자 pen 검토는 아직이라,
> 검토에서 바뀐 곳은 각 화면 Task 의 마지막 Step("pen 검토 반영")에서 맞춘다.
> **결정 대기 2건**(찬성 색의 뜻 · 선택지 글자 수)은 대조표 끝 "결정 대기" 에 있다.

**Goal:** 5번째 탭 "커뮤니티"(15d 피드 · 17b 질문 쓰기 · 17c 투표 상세)를 만든다. 누구나 익명으로 O/X 질문을
올리고, 투표 전에도 결과 비율을 보고, 한 번 투표하면 되돌릴 수 없다. 하루 첫 투표에 10하트를 주되 한 주 30하트를
넘기지 않는다.

**Architecture:** 표 두 개(`polls` · `poll_votes`)와 enum 두 개(`content_status` · `poll_choice`)를 새로 만든다.
클라이언트는 두 표에 **아무 권한도 없고**(ERD §2 87줄) FastAPI 가 `service_role` 로 DB 함수 네 개를 부른다.
작성자 숨기기와 집계는 DB 함수 `poll_feed` 한 곳에서 한다 — 함수가 돌려주는 칸에 `author_id` 가 **아예 없다.**
투표와 하트 지급은 DB 함수 `cast_poll_vote` 한 번(= 한 트랜잭션)에서 끝나고, 사람 단위 잠금
(`pg_advisory_xact_lock`)으로 "동시에 두 글에 투표해도 하루 한 번" 을 지킨다. 하트 지급은 조각 2 의
`grant_hearts` SQL 함수를 **그대로 안에서 부른다** — `hearts.py` 는 옮기지도 고치지도 않는다.

**Tech Stack:** Postgres 17 (Supabase) + pgTAP · FastAPI + httpx(PostgREST RPC) · Flutter(Riverpod `Notifier`,
go_router). **새 의존성 없음.**

**Spec:** `frontend/docs/DESIGN.md` §8.10(무료 획득 표 "커뮤니티 투표 참여") · §8.11 · §9(15d · 17b · 17c),
`docs/ERD.md` §2(87줄) · §6(508줄) · §7 · §8(`content_status` · `poll_choice`) · 264줄(탈퇴 즉시 빠지는 곳),
`docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §3.2(316줄) · §13 미결14,
메모리 `project_captain_status_2026-09-27.md`(커뮤니티 탭 앞당김)

---

## 사용자 결정 (2026-09-27, 이 창에서 직접 물음)

| # | 물은 것 | 답 | 반영된 곳 |
| --- | --- | --- | --- |
| 1 | 피드 범위 | **전체**(모든 학교 한 목록) | C2 `poll_feed` 에 학교 · 지역 조건 없음 |
| 2 | 내 글 삭제 | **가능** — 내 카드에만 "…" 메뉴 → 삭제 → 확인 창. 투표도 같이 지워지고, 이미 받은 하트는 그대로 | C1 cascade · B2 DELETE · A5 |
| 3 | 하루 질문 수 | **10개**(추천 3 과 다름, 사용자 지정) · 한국 시간 자정 기준 | C2 `create_poll` · B2 429 · A4 |
| 4 | 투표 전 결과 | **누구나 투표 전에도 봄**(추천과 다름) | C2 · B1(가리지 않음) · A3 |
| 4-1 | 투표 전 결과 자리 | **O/X 버튼 아래 한 줄** "찬성 62% · 반대 38% · 127명 참여", 투표하면 도넛 | A3 · pen 추가 |
| 4-2 | 작성자 자기 글 투표 | **허용**(결과가 이미 공개라 막을 이유가 적음, 사용자 이의 없음) | C2(막는 조건 없음) |

**통합대장 브리프로 이미 정해진 것:** 하트 보상 = 하루 한 번 10하트 · 한 주 최대 30하트(2026-09-27 사용자 "가"),
원장 기록은 `heart_reason 'poll_vote'` · `ref_id = poll_id`, 기존 `grant_hearts` 재사용.

### 기본값 (통합대장 확인 2026-09-27 — 한 주 · 차단 · active 세 줄은 그대로 확정)

| 무엇 | 기본값 | 이유 |
| --- | --- | --- |
| "한 주" | **월요일 0시 ~ 일요일 24시, 한국 시간** | Postgres `date_trunc('week')` 가 ISO 주(월요일 시작)다. 한국 달력 관행과 같다 |
| 옵션 라벨 글자 수 | **결정 대기(추천 6자)** — 통합대장이 사용자에게 묻는다 | DESIGN · pen 모두 상한이 없다. 근거는 대조표 "결정 대기". 답이 다르면 C1 check · B2 `OPTION_MAX_LENGTH` · A1 `pollOptionMaxLength` 와 그 테스트 숫자를 바꾼다 |
| 두 라벨이 같을 때 | **올리지 못함**(버튼 꺼짐 · 서버 422 · DB check) | "찬성/찬성" 은 투표가 성립하지 않는다 |
| 가려진 글(`blinded`) · 글쓴이가 active 가 아닌 글 | 피드 · 상세 · 투표 모두에서 **없는 글과 같게**(404) | ERD 264줄 — 탈퇴하면 "투표 글 · 투표 집계" 에서 즉시 빠진다 |
| active 가 아닌 투표자의 표 | **집계에서 뺀다** | 같은 ERD 264줄 |
| 차단한 사람 · 나를 차단한 사람의 글 | **거르지 않는다** | 글이 익명이라 보여도 누구인지 모르고, 걸러도 아무 것도 지켜지지 않는다 |
| 투표 보상 토스트 | "하트 10개를 받았어요" — pen 15d-3(Toast `I8UOWm`)으로 확정 | 보상이 조용히 들어오면 사용자가 모른다. 18a 화면은 아직 없다 |
| 불러오기 실패 문구 | `failure.dart` 의 종류별 문구 그대로, 모양은 가운데 문구 + "다시 시도"(대장 정정 2026-09-27) | 나 탭의 "잠시 뒤 다시 시도해 주세요" 고정 문구는 화면 15 전용 결정이다 |
| 지운 글 | 하루 10개 셈에서 빠진다 | 지운 글은 도배가 아니다 |
| 피드 한 쪽 | 20개, 최신순, 커서 = 맨 아래 글의 `created_at` + `id` | 채팅 메시지 페이지와 같은 방식(같은 시각 두 글이 경계에서 안 빠진다) |

### 통합대장 결정 (2026-09-27)

| # | 무엇 | 결정 | 근거 · 반영 |
| --- | --- | --- | --- |
| D1 | 한 주 · 차단 · active 기본값 | 위 표 그대로 | 한 주 = 한국 시간 월 0시(ISO 주, 한국 달력 관행) · 차단 관계라도 거르지 않음(익명이라 누가 쓴 글인지 새지 않는다) · active 아닌 사람의 글 404, 그 사람의 표는 집계 제외(ERD 264줄) |
| D2 | 앱 PR 을 서버 PR 과 나란히 | **허락.** 워크트리 `../campus_mate_compose-community-app`(`feat/community-polls-app`) | 서버 계약(아래 "API 계약" 표의 응답 키 · 오류 코드)을 이 계획서에 고정하고, 앱은 `FakeCommunityRepository` 로 먼저 만든다. 앱 PR 은 **서버 배포 뒤에 ready** |
| D3 | 공유 파일 | **미리 허락(허락: 통합대장 09-27)** — PR 2 `errors.py` 3줄 · `main.py` 2줄, PR 3 `app_routes` 2줄 · `app_router` 1+2줄 | 안전담당 PR 2(`errors.py` · `main.py`)나 채팅탭 PR 5(`app_routes` · `app_router`)와 겹치면 **나중에 merge 되는 쪽이 rebase**. 줄 수가 늘면 다시 요청 |
| D4 | 삭제 확인 시트(AlertSheet `D0TvG`) | 사용처가 두 번째라 **common 으로 올린다** | 채팅탭 PR 5 가 **먼저 merge 되면** PR 3 에서 `safety/view` 의 확인 시트를 `common/widgets` 로 옮기고 두 곳이 같이 쓴다(그때 공유 파일로 요청). **먼저 merge 되지 않으면** 이번에는 `community/view/poll_sheets.dart` 에 따로 두고 백로그 39 의 승격 줄에 합친다 |
| D5 | 표 정의 고정 | 검토 PASS 뒤 C1 의 칸 · 타입 · 제약은 **되도록 바꾸지 않는다** | PASS 뒤 campus-pen 이 ERD.pen 의 `polls` · `poll_votes` · enum 2개를 C1 과 대조한다. 예외는 "결정 대기" 선택지 글자 수 한 곳(check 숫자) |

### 이번에 하지 않는 것

- **질문마다 붙는 신고 버튼** — 안전담당 앱 PR 6 이 끝난 뒤 연결한다. DB 값 `report_target 'poll'` 은 이미 있다.
  신고 누적으로 `status = 'blinded'` 를 찍는 규칙(서로 다른 3명?)은 **그때 사용자에게 묻는다.** 이번에는
  `blinded` 인 글을 **읽는 쪽에서 빼는 것까지만** 한다 — 그래서 대시보드에서 손으로 가리는 것은 오늘부터 된다.
- 댓글, 18a "무료로 하트 모으기" 화면의 투표 항목 상태("이번 주 적립 완료"), 푸시 알림
- 노션(통합대장), 문서 정리(조각 끝에 사용자에게 물은 뒤 — 아래 "문서 갱신 대상")

---

## Global Constraints

1. **작성자 id 는 어떤 응답에도 담지 않는다.** DB 함수 `poll_feed` 의 반환 칸에 없고, 서버 `_card()` 가 칸을 한 번
   더 골라 낸다. 본인에게도 `author_id` 대신 `is_mine` 참/거짓만 준다.
2. **`polls` · `poll_votes` 는 클라이언트 권한 0.** `anon` · `authenticated` 에 select 도 주지 않는다(ERD §2 87줄).
   정책도 두지 않는다. 쓰기는 전부 FastAPI 가 `service_role` 로 한다.
3. **테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤 필요한 것만 준다**(ERD §2 62줄).
   DB 함수는 `revoke execute ... from public, anon, authenticated` + `grant execute ... to service_role`,
   `security invoker`, `set search_path = ''`(`home_stats` 와 같은 모양).
4. **투표는 되돌릴 수 없다**(DESIGN §8.11). 재투표는 PK(`poll_id`, `voter_id`)가 막는다 → 409.
5. **하트는 하루 첫 투표에 10, 한 주 30 넘지 않게. 동시 요청 두 개에도 한 번만.** 원장 집계로 검사한다(ERD 508줄).
6. **이미 적용된 마이그레이션은 고치지 않는다.** `grant_hearts` 도 그대로 부른다.
7. **새 마이그레이션 타임스탬프는 `20260927010500` 보다 뒤** — 기본 `20260927020000` · `20260927020100`.
   DB 차례를 받을 때 그 사이에 다른 브랜치가 번호를 썼는지 대장에게 확인한다.
8. **문구는 한 곳에서만** — 서버 `core/errors.py`, 앱은 화면 파일 상단 상수.
9. **새 화면은 COMMON §4-2 잉크 규칙을 지킨다** — 카드 안 탭 영역의 가장 가까운 `Material` 이 카드 자신이다.
10. 공유 파일은 아래 "공유 파일 요청" 목록 밖으로 고치지 않는다. 커밋에 도구 표식을 넣지 않는다.

---

## Review Focus

사양이 암시하지만 흔한 테스트가 놓치기 쉬운 것 다섯 가지. 각 줄의 테스트는 해당 Task 에 들어 있다.

1. **한 사람이 두 글에 거의 동시에 투표**(더블 탭 · 두 기기) → 하트는 그날 한 번만 들어가야 한다.
   → C2 pgTAP "잠금 줄이 함수에 있다" + C2 Step "경합 확인 스크립트"(잠금을 빼면 2, 넣으면 1 — RED/GREEN).
2. **글쓴이가 탈퇴 · 정지됨, 투표자가 탈퇴함** → 그 글은 피드 · 상세 · 투표에서 사라지고, 떠난 투표자의 표는
   비율과 참여자 수에서 빠져야 한다. → C2 pgTAP(GONE · VOFF 픽스처).
3. **같은 시각에 올라간 두 글이 페이지 경계에 걸림** → 빠지거나 두 번 나오면 안 된다.
   → C2 pgTAP 커서 단정 + B1 pytest(반쪽 커서 422) + A2 VM(겹친 id 거르기).
4. **다른 기기에서 이미 투표했거나, 누르는 사이 글이 지워짐** → 앱은 문구를 띄우고 그 카드만 서버 상태로
   맞춘다(이미 투표 = 도넛으로, 없어짐 = 목록에서 빠짐). 연결이 끊긴 실패로는 카드를 지우지 않는다.
   → B2 pytest(409 · 404) + A2 VM 테스트 3개.
5. **글자 크기 2배 · 긴 질문 · 긴 라벨** → 카드가 넘치거나(노란 줄무늬) 도넛 안 % 가 잘리지 않아야 한다.
   → A3 위젯 테스트(textScaleFactor 2.0 에서 예외 0).

---

## API 계약 (B · A 공통)

모두 `get_verified_caller`(학생증 인증 + 학과 입력 완료) 뒤. 오류 본문은 `{"detail": "<문구>"}`.

| 메서드 · 경로 | 요청 | 성공 | 실패 |
| --- | --- | --- | --- |
| `GET /community/polls` | `before`(ISO) · `before_id`(uuid) 둘 다 있거나 둘 다 없음 | 200 `{"polls": [Poll], "has_more": bool}` | 422 반쪽 커서 |
| `GET /community/polls/{poll_id}` | — | 200 `{"poll": Poll}` | 404 `POLL_NOT_FOUND` |
| `POST /community/polls` | `{"question", "option_a_label"?, "option_b_label"?}` 라벨 기본 찬성/반대 | 201 `{"id": uuid}` | 422 빈칸 · 80자 초과 · 라벨 6자 초과 · 두 라벨 같음 / 429 `POLL_DAILY_LIMIT` |
| `POST /community/polls/{poll_id}/votes` | `{"choice": "a" \| "b"}` | 200 `{"poll": Poll, "rewarded": bool}` | 404 `POLL_NOT_FOUND` / 409 `POLL_ALREADY_VOTED` / 422 |
| `DELETE /community/polls/{poll_id}` | — | 204 | 404 `POLL_NOT_FOUND`(남의 글도 같은 404 — 남의 글이라는 사실을 흘리지 않는다) |

`Poll` = `{"id", "question", "option_a_label", "option_b_label", "created_at", "a_count", "b_count",
"my_choice": "a" | "b" | null, "is_mine": bool}` — **이 9칸 말고는 없다.**

---

## 화면 대조표 (pen 값표 2026-09-27)

값표: `C:/Users/user/OneDrive/Desktop/커뮤니티_검토/값표_커뮤니티_15d_17b_17c.md` — 1~9절(처음 값) + **10절 "수정 뒤"**
(PNG 는 같은 폴더와 `수정후/` 12장). pen 파일 `datingApp.pen`. **pen 이 기준**이고, 통합대장이 정한 예외 네 가지(12px ·
우세한 쪽 % · 빈 상태 button-secondary · 17c 안내 muted)는 pen 도 이미 그렇게 고쳤다(10-2절). **사용자 pen 검토는
아직이다** — 검토에서 바뀐 곳은 각 화면 Task 의 마지막 Step 에서 맞춘다.

화면 id: 15d 피드 **XhEyI**(사본 JbguN, 하단 내비 tCsHU) · 15d 빈 상태 **n2tqZ** · 15d-1 내 질문 메뉴 **RCNu0** ·
15d-2 삭제 확인 **K64Q8p** · 15d-3 투표 보상 **L8qZK** · 15d-4 직접 적은 선택지 **l5OrW1** · 17b **p4wnJ**(사본 GKuxu) ·
17c **BwL1G**(사본 usTNp) · PollCard 마스터 **RpRBi**(Z54et 밖, 쇼케이스 wmzn0 안). 카드 높이: 투표 전 232 · 투표 후 279,
내 글 카드는 머리줄이 48 이라 26 더 높다.

### 15d 피드 (XhEyI)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 앱바 | 높이 56, 왼쪽 20 · 오른쪽 8, 제목 "커뮤니티" 20/700 lh1.5 #222 | Iblb3 · Wu1Ic | `AppBar(titleSpacing: 20, title: navTitle)` + actions 끝 `SizedBox(width: 8)` |
| + 버튼 | 터치 48, 원 32 #F7F7F7(surfaceSoft), lucide plus 18 #222 | uhk6J · I7U2Jp · zuIJJ | `IconButton` 안에 32 원 |
| 목록 | 위아래 8 · 좌우 16, 카드 사이 12 | FXyNI | `ListView.separated` |
| 카드 틀 | #FFF, 테두리 없음, radius 14, 안쪽 16, 세로 간격 12, 그림자 #00000014 (0,1) blur 8 | RpRBi | `DecoratedBox`(색·그림자) + `Material(transparency)` |
| 머리줄 | 가로, 간격 8 | Kt1Li | `Row` |
| "익명" 칩 | #F2F2F2(surfaceStrong), pill, 안쪽 [3,10], 11/600 #3F3F3F(body), 아이콘 없음 | LHkpo · MpYr6 | `badge` 글꼴 |
| 작성 시각 | **12/500** #6A6A6A(10-2절, 11 → 12) | G85OOq | `caption` w500 muted |
| 신고 flag | lucide flag 16 #929292, 시각 바로 오른쪽. 내 글 카드에서는 꺼짐 | z7tzx | **이번엔 안 붙인다**(안전 PR 6 뒤, 그때 터치 48) |
| 질문 | 16/700 lh1.35 #222, 목록에서는 2줄 말줄임(DESIGN — pen 은 줄 수 속성이 없다) | b5raym | `body` w700 h1.35 |
| O · X 버튼 줄 | 가로, 간격 8 | zH8G0 | `Row` |
| O 버튼 | 폭 반, 높이 72, #2D96DE(토큰 밖), radius 8, lucide circle 34 흰색 | VhiAe · e2NifA | `FilledButton` |
| X 버튼 | 높이 72, #FF385C(primary), radius 8, lucide x 34 흰색 | mUsfX · lzsKB | `FilledButton` |
| 직접 적은 선택지 버튼 | 줄 `ojrC5`(가로, 간격 8, O·X 줄 대신 켬) · 버튼 `ALBe4`/`OJ4rJ` = Button(HE8FZ) #E5E5E5 채움 · 라벨 #222 18/700 · 높이 56 · radius 16 · 폭 144(15d-4 `l5OrW1` 카드 `RxrNf`) | ojrC5 · ALBe4 · OJ4rJ | `AppButton(secondary)` 기본 높이 56 |
| **투표 전 결과 한 줄** | "찬성 62% · 반대 38% · 127명 참여" 12/400 lh1.4 #6A6A6A, **가운데 정렬**, 버튼 줄 바로 아래(카드 간격 12). 투표 후 카드에서는 꺼짐 | R2ZIGG | `caption` muted center |
| 결과 영역 | 세로, 가운데, 간격 8 | omkNb | `Column` |
| 도넛 | 지름 96, 바탕 #F2F2F2 전체, 호 #FF385C 12시에서 시계 방향 = **선택지 A 몫**, 안쪽 반지름 0.62 → **두께 약 18.2**(DESIGN 12 와 다름, pen 기준), 끝 평평, 틈 없음 | raSK1 · wnXtI · D18xFi | `CustomPainter` |
| 도넛 가운데 % | 20/700 #222, **우세한 쪽 %**(대장 예외 — pen 은 늘 A) | zJP3C | `title` w700 |
| 비율 줄 | "찬성 62% · 반대 38%" 14/600 #3F3F3F, 도넛 아래 8 | H1kGWf | `labelSmall` body |
| 참여자 수 | **12/500** muted(10-2절, 11 → 12) | rEJhW | `caption` w500 muted |
| 상세 진입 줄 | 오른쪽 정렬, "자세히 보기" 12/600 #6A6A6A + 간격 2 + chevron-right 14 #6A6A6A, **누르는 영역 48**(대장) | i5ugzn · h2orwk · c2sC82 | `InkWell` minHeight 48 |
| 내 글 "…" | IconButton(B8pl1) 터치 48, lucide ellipsis 20 #6A6A6A, 머리줄 끝(flag 자리). 내 글에서만 켬 → 머리줄 높이 48 | mc9mW(아이콘 EsCvW) | `IconButton(tooltip: '더보기')` |
| 내 질문 메뉴 시트 | **15d-1 `RCNu0`**, Menu · Chat(`RzZT8`) 인스턴스 `ofjwb`: #FFF, 위 radius 24, 안쪽 [12,16,24,16], 간격 4, 손잡이 36×4, 행 52(안쪽 [0,4], 아이콘 20 + 12 + 16/400 글자) — trash-2 + "삭제하기" 둘 다 error #C13515, 구분선 1 hairlineSoft, "취소" 16/600 #222 가운데 | RCNu0 · ofjwb | `poll_sheets.dart` `_PollMenuSheet`(채팅탭 PR 5 `ChatRoomMenuSheet` 와 같은 값, 결정 D4) |
| 삭제 확인 | **15d-2 `K64Q8p` = AlertSheet D0TvG 인스턴스 `CCdBk`**: 위 radius 24, 손잡이 36×4 #DDD, 안쪽 [8,16,32,16] 간격 16, 제목 "이 질문을 삭제할까요?" 20/700 #222, 본문 "질문과 받은 투표가 모두 사라지고 되돌릴 수 없어요." 14/400 lh1.55 #6A6A6A, 버튼 세로 간격 8: "삭제하기" button-danger(56, #E5E5E5 + #C13515) · "취소" button-text(48, #C4224B) | D0TvG | `showModalBottomSheet` + `AppButton(danger)` · `AppButton(text)` |
| 투표 보상 토스트 | **15d-3 `L8qZK`, Toast I8UOWm 인스턴스 `NDZnK`** "하트 10개를 받았어요" — #222 pill, 안쪽 [10,16], **아이콘 없이 글자만**(재화 하트는 Lucide 금지, DESIGN §8.10), 14/600 흰 글자, 하단 내비 위 16 | NDZnK | `AppToast(leading: null)` — **공용 위젯 한 줄 변경 요청**(아래 공유 파일) |
| 투표 실패 토스트 | pen 없음. 같은 Toast 에 경고 아이콘(`photos_screen` 과 같은 모양) | I8UOWm | `AppToast(leading: alertTriangle)` |
| 불러오는 중 | 가운데 스피너(pen 없음, 대장) | — | `CircularProgressIndicator` |
| 불러오기 실패 | 가운데 문구 + "다시 시도"(pen 없음). 문구는 `failure.dart` 종류별 문구 그대로(502/503 → "잠시 뒤 다시 시도해 주세요", 연결 → "네트워크 연결을 확인해 주세요" …) | — | `school_info_screen` `_SchoolNameError` 모양 |
| 하단 내비 | 커뮤니티 활성(아이콘 · 라벨 #FF385C) | tCsHU | 기존 `AppBottomNav(current: community)` |

### 15d 빈 상태 (n2tqZ)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 틀 | 세로, 가운데, 안쪽 [48,24] | TVc8b(cGomJ) | `Padding` |
| 마스코트 | **mascot-male.png** 120(파란 목도리 — DESIGN "핑크 포인트" 와 다르나 pen 기준) | c9BLt | `assets/images/mascot-male.png` |
| 간격 | 마스코트~제목 24, 제목~설명 8, 설명~버튼 32 | Wz22b · Zsy0s | `SizedBox` |
| 제목 | "아직 질문이 없어요" 17/600 #222 가운데 | ZBzIg | `subtitle` ink |
| 설명 | "궁금한 걸 익명으로 물어보고\n캠퍼스 사람들의 생각을 들어보세요." 14/400 lh1.55 #6A6A6A 가운데 | DFs55 | `bodySmall` muted |
| 버튼 | "질문 올리기" → **button-secondary**(대장 예외, pen 은 연분홍), 폭은 내용에 맞춤(pen 128) | l8vOF | `IntrinsicWidth(AppButton(secondary))` |

### 17b 질문 작성 (p4wnJ)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 앱바 | 56, 뒤로 48(arrow-left 22), 제목 "익명으로 질문하기" 20/700 lh1.5 | jrUTh · g58njs · RKulj | 설정 화면과 같은 `AppBar(title: navTitle)` |
| 본문 | 세로, 간격 20, 안쪽 16. **버튼이 본문 흐름 안**(화면 아래 고정 아님) | QhlmU | `ListView` 안에 버튼까지 |
| 안내 상자 | #F7F7F7, radius **10**(토큰 밖), 안쪽 12, 간격 8, lucide lock 16 #6A6A6A + "작성자 정보는 절대 공개되지 않아요" 12/600 #6A6A6A | XC6KK · JLMTr · PBN9z | `Container` |
| 질문 라벨 | "질문 내용" 14/600 #3F3F3F | BxeOU/VCwQo | `labelSmall` body |
| 질문 입력칸 | **Textarea 마스터 Zhq9p**(대장): #F7F7F7, radius 8, 테두리 #767676 1, 안쪽 12, 간격 4, 높이 최소 104, 자리글 14/400 lh1.5 #6A6A6A "예) 깻잎을 먼저 집으면 안 되는 거 아니야?", 카운터 "0 / 80" 12/400 lh1.5 #6A6A6A **상자 안 아래 왼쪽**. 17b 화면 `p4wnJ` 은 PccKZ 를 늘린 그대로다(10절에 17b 변경 없음) — 상자 · 카운터는 Zhq9p 값, 라벨 "질문 내용" · 자리글 문구는 p4wnJ 값을 합쳐 쓴다(대장 지시) | Zhq9p · BxeOU | `Container` + `TextField(collapsed)` + 카운터 `Text` |
| 선택지 줄 | 가로, 간격 12 | cDl1P | `Row` |
| 선택지 칸 | 세로 간격 6, 라벨 "선택지 A"/"선택지 B" 12/600 #3F3F3F, 상자 높이 44 #F7F7F7 radius 8 안쪽 [0,14] 테두리 없음, 값 14/600 #222(기본 "찬성"/"반대") | mYKYP · w4KZj · WyAj2 · P232O / ropSL · zsDjz · U5InwB · lKoAD | `Container` + `TextField(collapsed)` |
| 선택지 글자 수 | **pen 에 없음 → 추천 6자, 사용자 답 대기**(대장이 묻는다). 카운터는 두지 않는다 | — | `maxLength` |
| 올리기 버튼 | button-primary "익명으로 올리기" 56, radius 16. 꺼짐 = 공용 비활성(대장) | FlFPS | `AppButton` |
| 하루 한도 문구 | "오늘은 질문을 더 올릴 수 없어요"(pen 없음) — 버튼 위 빨간 한 줄 | — | `bodySmall` error |

### 17c 투표 상세 (BwL1G)

| 요소 | pen 값 | 노드 | 앱 |
| --- | --- | --- | --- |
| 앱바 | 17b 와 같은 규격, 제목 **"투표 상세"** | bcnJx · SKAG4 | `AppBar(title: navTitle)` |
| 본문 | 세로, 간격 16, 안쪽 16 | ZR52B | `ListView` |
| 카드 | 피드와 **같은 크기**(도넛 96, 확대 없음 — DESIGN "확대" 와 다르나 pen 기준), 상세 진입 줄 꺼짐 | v9Pmy0 | `PollCard(onOpen: null)` |
| 질문 | 상세에서는 줄 제한 없음(목록에서 잘린 글 전체) | — | `maxLines: null` |
| 투표 전 상태 | pen 없음. 사용자 결정 4 로 상세에서도 버튼을 그대로 보인다 | — | `PollCard` 투표 전 모양 |
| 신고 flag | pen 에 켜져 있음 | v9Pmy0/z7tzx | **이번엔 안 붙인다** |
| 댓글 안내 | "댓글 기능은 아직 준비 중이에요" 12/500, 색은 #929292 → **muted #6A6A6A**(대장 예외, 대비), 가운데, 카드 아래 16 | LyR5Y | `caption` w500 muted |

### 결정 대기

- **찬성 색의 뜻** — 투표 전 찬성(O) 버튼은 파랑 #2D96DE 인데 투표 후 도넛의 찬성(A) 호는 분홍 #FF385C 라 색 뜻이
  뒤바뀐다(값표 7절 22번). **통합대장이 사용자에게 묻는 중.** 답이 오면 `poll_card.dart` 의 `_agreeBlue` 또는
  `poll_donut.dart` 의 호 색 한 줄만 바뀐다.
- **선택지 글자 수** — 추천 **6자**. 이유: 커스텀 라벨 버튼 한 칸 폭이 144(카드 296 − 간격 8 을 반으로)이고 결과 줄이
  "{A} 62% · {B} 38%" 로 296 안에 한 줄로 들어가야 한다. 14/600 한글 한 자가 약 14px 라 6자 두 개 + 숫자 부분 ≈ 258px 로
  한 줄에 들어가고, 10자면 ≈ 370px 로 두 줄이 된다. 예시 "맞다/아니다" · "짜장/짬뽕" · "먼저 연락/기다린다" 가 다 들어간다.
  사용자 답이 다르면 C1 check · B2 `OPTION_MAX_LENGTH` · A1 `pollOptionMaxLength` 세 곳과 그 테스트 숫자를 바꾼다.
  **글자 수를 세는 기준은 세 층 모두 유니코드 코드 포인트다**(검토 권고 4 반영) — DB `char_length` · 서버 `len` 과 맞추려고
  앱은 Flutter `maxLength`(그래핌 단위) 대신 코드 포인트로 자르는 입력 필터를 쓴다(A4). 질문 80자도 같다.

---

## 공유 파일 (허락: 통합대장 09-27, 결정 D3 — 아래 줄 수를 넘으면 다시 요청)

| 파일 | 무엇 | 언제 |
| --- | --- | --- |
| `backend/app/core/errors.py` | 문구 3줄 추가(`POLL_NOT_FOUND` · `POLL_ALREADY_VOTED` · `POLL_DAILY_LIMIT`) | PR 2 |
| `backend/app/main.py` | import 1줄 + `include_router` 1줄 | PR 2 |
| `frontend/lib/core/router/app_routes.dart` | 상수 2줄(`communityNew` · `communityPoll`) | PR 3 |
| `frontend/lib/core/router/app_router.dart` | `/community` 의 `ComingSoonScreen` → `CommunityFeedScreen` 1줄 + 라우트 2개 | PR 3 |
| `frontend/lib/common/widgets/app_toast.dart` | **허락: 통합대장 09-27** — `leading` 을 선택으로만(생성자 1줄 · 칸 1줄 · 그리는 곳 `if` 4줄) + 테스트 1개. 15d-3 보상 토스트가 글자만이다. 채팅탭 PR 5 도 이 파일을 고친다(Flexible · copyWith(height)) — PR 5 가 먼저 들어갈 가능성이 커 그 위에 얹는다 | PR 3 |

**필요 없는 것:** `hearts.py` 이동(보상은 DB 함수 안에서 `grant_hearts` 를 부른다), `app_icons.dart`(`circle` ·
`x` · `plus` · `ellipsis` · `chevronRight` · `heart` · `alertTriangle` 이 이미 있다 — 값표가 다른 아이콘을 쓰면 그때
요청), `app_colors.dart`(찬성 파랑 `#2D96DE` 은 DESIGN 토큰표 밖 값이라 `kakao_id_screen.dart` 처럼 파일 안 상수),
그 밖의 `common/widgets/*`(`AppButton` · `AppBottomNav` 를 그대로 쓴다).

---

## 파일 구조

```
supabase/migrations/
  20260927020000_create_polls.sql              # enum 2 · 표 2 · 인덱스 · RLS · grant (C1)
  20260927020100_create_poll_functions.sql     # poll_feed · create_poll · poll_vote_reward_due · cast_poll_vote (C2)
supabase/tests/community_polls_test.sql        # C1 · C2

backend/app/community/
  __init__.py  repository.py  router.py        # (B1 · B2)
backend/tests/community/test_community_polls.py

frontend/lib/community/
  model/      poll.dart  community_repository.dart  http_community_repository.dart
              community_repository_provider.dart                        # (A1)
  viewmodel/  community_feed_ui_state.dart  community_feed_view_model.dart  # (A2)
  view/       community_feed_screen.dart  poll_card.dart  poll_donut.dart
              poll_time.dart  poll_toast.dart                           # (A3)
              poll_composer_screen.dart                                 # (A4)
              poll_detail_screen.dart  poll_sheets.dart                # (A5)
frontend/test/community/
  model/      fake_community_repository.dart  poll_test.dart  http_community_repository_test.dart
  viewmodel/  community_feed_view_model_test.dart
  view/       poll_time_test.dart  community_feed_screen_test.dart
              poll_composer_screen_test.dart  poll_detail_screen_test.dart
```

---

## PR 나누기

| PR | 브랜치 | 내용 | 관문 |
| --- | --- | --- | --- |
| 1 DB | `feat/community-polls`(지금 워크트리) | C1 · C2 | DB 차례 → draft → 검토 PASS → merge → ERD 그림 · 사용자 검토 · 승인 → 클라우드 적용(대장) |
| 2 서버 | `feat/community-polls-server`(PR 1 merge 뒤 같은 워크트리에서 새 main 으로) | B1 · B2 + 공유 파일 2 | 운영 DB 에 PR 1 이 **적용된 뒤** 배포(대장) — 먼저 배포하면 RPC 404 로 500 |
| 3 앱 | `feat/community-polls-app`(워크트리 `../campus_mate_compose-community-app`, 결정 D2) | A1~A5 + 공유 파일 2 | PR 2 와 나란히 쓴다 — 계약은 "API 계약" 표로 고정, 테스트는 가짜 저장소. 값표 "수정 뒤" 반영 · **PR 2 배포 뒤 ready** |

---

# Part C — Supabase (DB 차례를 받은 뒤)

### Task C1: 표 · enum · 권한

**Files:**
- Create: `supabase/migrations/20260927020000_create_polls.sql`
- Create: `supabase/tests/community_polls_test.sql`

**Interfaces:**
- Produces: `public.content_status`('visible','blinded'), `public.poll_choice`('a','b'),
  `public.polls(id, author_id, question, option_a_label, option_b_label, status, created_at)`,
  `public.poll_votes(poll_id, voter_id, choice, created_at)` PK(`poll_id`,`voter_id`)

- [ ] **Step 1: pgTAP 을 먼저 쓴다(RED).** `supabase/tests/community_polls_test.sql`:

```sql
-- 커뮤니티 탭(15d · 17b · 17c) 표 · 권한 · DB 함수 검증.
-- 기대값 기준: docs/superpowers/plans/2026-09-27-community-polls.md Task C1 · C2.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- 준비 --------------------------------------------------------------------
-- AU = ...80(글쓴이), V1 = ...81 · V2 = ...82(투표자), GONE = ...83(탈퇴할 글쓴이),
-- VOFF = ...84(탈퇴할 투표자), WK = ...85(주간 상한 확인), LIM = ...86(하루 10개 확인)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000007', '테스트대학교7', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test7.ac.kr', '00000000-0000-0000-0000-000000000007');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000080', 'p7-au@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000081', 'p7-v1@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000082', 'p7-v2@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000083', 'p7-gone@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000084', 'p7-voff@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000085', 'p7-wk@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000086', 'p7-lim@test7.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000007' from auth.users
where id between '00000000-0000-0000-0000-000000000080' and '00000000-0000-0000-0000-000000000086'
on conflict (id) do nothing;

-- active 전환 check(닉네임 · 성별 · 출생연도 · 키)만 채운다. 나머지 칸은 이 테스트와 상관없다.
update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-000000000080' then '글쓴이가'
    when '00000000-0000-0000-0000-000000000081' then '투표하나'
    when '00000000-0000-0000-0000-000000000082' then '투표둘이'
    when '00000000-0000-0000-0000-000000000083' then '떠난이다'
    when '00000000-0000-0000-0000-000000000084' then '떠난표다'
    when '00000000-0000-0000-0000-000000000085' then '주간이다'
    when '00000000-0000-0000-0000-000000000086' then '열개쓴이'
  end
where id between '00000000-0000-0000-0000-000000000080' and '00000000-0000-0000-0000-000000000086';

-- C1: 표 · enum · 권한 ---------------------------------------------------
select has_table('public', 'polls', 'polls 표가 있다');
select has_table('public', 'poll_votes', 'poll_votes 표가 있다');
select enum_has_labels('public', 'content_status', array['visible', 'blinded'], 'content_status 는 visible · blinded');
select enum_has_labels('public', 'poll_choice', array['a', 'b'], 'poll_choice 는 a · b');
select ok((select relrowsecurity from pg_class where oid = 'public.polls'::regclass), 'polls 는 RLS 가 켜져 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.poll_votes'::regclass), 'poll_votes 는 RLS 가 켜져 있다');
select is(
  (select count(*) from pg_policies where tablename in ('polls', 'poll_votes')),
  0::bigint, 'polls · poll_votes 에는 정책이 하나도 없다(FastAPI 전용, ERD §2 87줄)'
);
select table_privs_are('public', 'polls', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 polls 에 네 권한이 다 있다');
select table_privs_are('public', 'poll_votes', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 poll_votes 에 네 권한이 다 있다');

-- 제약 확인용 글 D1(...d1). C2 절이 시작할 때 polls 를 비우므로 여기서만 쓴다.
insert into public.polls (id, author_id, question)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000080', '짜장 짬뽕');
insert into public.poll_votes (poll_id, voter_id, choice)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000081', 'a');

select results_eq(
  $$select option_a_label, option_b_label, status::text from public.polls
     where id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$values ('찬성', '반대', 'visible')$$,
  '라벨을 안 주면 찬성 · 반대, 상태는 visible 이다'
);
select throws_ok(
  $$insert into public.polls (author_id, question)
    values ('00000000-0000-0000-0000-000000000080', repeat('가', 81))$$,
  '23514', null, '질문은 80자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, question) values ('00000000-0000-0000-0000-000000000080', '   ')$$,
  '23514', null, '빈칸뿐인 질문은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (author_id, question, option_a_label)
    values ('00000000-0000-0000-0000-000000000080', '질문', repeat('가', 7))$$,
  '23514', null, '라벨은 6자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-000000000080', '질문', '좋아', '좋아')$$,
  '23514', null, '두 라벨이 같으면 들어가지 않는다'
);
select throws_ok(
  $$insert into public.poll_votes (poll_id, voter_id, choice)
    values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000081', 'b')$$,
  '23505', null, '같은 사람이 같은 글에 두 번 투표할 수 없다(재투표 불가)'
);
select throws_ok(
  $$insert into public.poll_votes (poll_id, voter_id, choice)
    values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000082', 'c')$$,
  '22P02', null, '선택은 a · b 둘뿐이다'
);

delete from public.polls where id = '00000000-0000-0000-0000-0000000000d1';
select is(
  (select count(*) from public.poll_votes where poll_id = '00000000-0000-0000-0000-0000000000d1'),
  0::bigint, '글을 지우면 그 글의 투표도 지워진다(내 글 삭제 · 탈퇴 cascade)'
);

-- C2 자리 (Task C2 가 여기에 끼워 넣는다) ---------------------------------

-- 클라이언트 권한 --------------------------------------------------------
-- grant 가 없어 0행이 아니라 42501 이다(ERD §2 95줄 "읽기가 없는 테이블은 본인 행이라도 42501").
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000080", "role": "authenticated"}';

select throws_ok($$select id from public.polls$$, '42501', null, 'authenticated 는 polls 를 읽을 수 없다');
select throws_ok($$select poll_id from public.poll_votes$$, '42501', null, 'authenticated 는 poll_votes 를 읽을 수 없다');
select throws_ok(
  $$insert into public.polls (author_id, question) values ('00000000-0000-0000-0000-000000000080', '질문')$$,
  '42501', null, 'authenticated 는 polls 에 쓸 수 없다'
);

set local role anon;
select throws_ok($$select id from public.polls$$, '42501', null, 'anon 은 polls 를 읽을 수 없다');

select * from finish();
rollback;
```

- [ ] **Step 2: RED 확인.** 워크트리 루트에서 `supabase db reset` 은 아직 하지 말고 `supabase test db` →
  `has_table` 부터 실패(표가 없다)하는지 본다. 기대: `Failed 21/21` 근처, 첫 실패가 `polls 표가 있다`.

- [ ] **Step 3: 마이그레이션.** `supabase/migrations/20260927020000_create_polls.sql`:

```sql
-- 커뮤니티 탭(15d · 17b · 17c): 익명 O/X 질문과 투표. 기준 문서 docs/ERD.md §7 · §8, DESIGN §8.11.
-- 클라이언트는 두 표 모두 접근하지 않는다(ERD §2 87줄) — author_id 를 열면 익명이 깨지고,
-- poll_votes 는 본인 행만 열면 집계가 안 되고 다 열면 누가 뭘 골랐는지 보인다.
create type public.content_status as enum ('visible', 'blinded');
create type public.poll_choice as enum ('a', 'b');

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  question text not null,
  option_a_label text not null default '찬성',
  option_b_label text not null default '반대',
  status public.content_status not null default 'visible',
  created_at timestamptz not null default now(),
  -- 서버가 앞뒤 공백을 깎아 넣는다. 깎인 모양이 아니면 빈칸뿐인 글이 들어온 것이다.
  constraint polls_question_length check (char_length(question) between 1 and 80 and question = btrim(question)),
  constraint polls_option_a_length check (char_length(option_a_label) between 1 and 6 and option_a_label = btrim(option_a_label)),
  constraint polls_option_b_length check (char_length(option_b_label) between 1 and 6 and option_b_label = btrim(option_b_label)),
  constraint polls_options_differ check (option_a_label <> option_b_label)
);

comment on table public.polls is
  '커뮤니티 익명 질문. FastAPI 전용. author_id 는 어떤 응답에도 담지 않는다(poll_feed 가 칸을 주지 않는다)';

-- 피드: 최신순 + (created_at, id) 커서.
create index polls_created_at_id_index on public.polls (created_at desc, id desc);
-- 하루 10개 세기와 탈퇴 cascade 가 author_id 로 찾는다.
create index polls_author_id_created_at_index on public.polls (author_id, created_at);

create table public.poll_votes (
  poll_id uuid not null references public.polls (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  choice public.poll_choice not null,
  created_at timestamptz not null default now(),
  -- 재투표 불가(DESIGN §8.11). 두 번째 insert 는 23505 → 서버 409.
  primary key (poll_id, voter_id)
);

comment on table public.poll_votes is '커뮤니티 투표. FastAPI 전용. 되돌릴 수 없다';

-- PK 앞머리가 poll_id 라 집계는 PK 를 탄다. voter_id 는 탈퇴 cascade 용.
create index poll_votes_voter_id_index on public.poll_votes (voter_id);

alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;

revoke all on table public.polls from anon, authenticated, service_role;
grant select, insert, update, delete on table public.polls to service_role;

revoke all on table public.poll_votes from anon, authenticated, service_role;
grant select, insert, update, delete on table public.poll_votes to service_role;
```

- [ ] **Step 4: GREEN 확인.** `supabase db reset` → `supabase test db`. 기대: `community_polls_test.sql .. ok`,
  다른 파일도 전부 ok. 보고에 `docker ps --filter health=unhealthy` 한 줄.

- [ ] **Step 5: 커밋.** `🗃️ feat(db): 커뮤니티 질문 · 투표 표 추가` (마이그레이션 + pgTAP 두 파일)

---

### Task C2: DB 함수 네 개(피드 · 글쓰기 · 보상 판정 · 투표)

**Files:**
- Create: `supabase/migrations/20260927020100_create_poll_functions.sql`
- Modify: `supabase/tests/community_polls_test.sql`(plan 수 21 → 54, "C2 자리" 에 끼워 넣기, 끝에 함수 권한 4개)

**Interfaces:**
- Consumes: C1 표 · enum, 조각 2 `public.grant_hearts(uuid, integer, public.heart_reason, uuid)`
- Produces (서버가 PostgREST `/rpc/<이름>` 으로 부른다, 인자 이름 그대로 JSON 키):
  - `poll_feed(p_viewer uuid, p_poll_id uuid default null, p_before timestamptz default null, p_before_id uuid default null, p_limit integer default 20)`
    → `table(id uuid, question text, option_a_label text, option_b_label text, created_at timestamptz, a_count bigint, b_count bigint, my_choice poll_choice, is_mine boolean)`
  - `create_poll(p_author uuid, p_question text, p_option_a text, p_option_b text) returns uuid` — 하루 10개 넘으면 SQLSTATE **`CM429`**
  - `poll_vote_reward_due(p_voter uuid, p_now timestamptz) returns boolean`
  - `cast_poll_vote(p_poll_id uuid, p_voter uuid, p_choice poll_choice) returns boolean`(= 하트를 줬는가) — 없는 글 **`CM404`**, 재투표 **`23505`**

- [ ] **Step 1: pgTAP 을 먼저 늘린다(RED).** `select plan(21);` → `select plan(54);`. "C2 자리" 주석 바로 아래에:

```sql
-- C2: DB 함수 -------------------------------------------------------------
-- 피드 단정이 앞 절의 글 · 로컬에서 손으로 만든 글과 섞이지 않게 비운다(끝에 rollback 된다).
delete from public.polls;

-- P1(...a1) 3분 전, P2(...a2) · P3(...a3) 2분 전 같은 시각(커서 경계), PB(...b1) 가려짐, PG(...c1) 탈퇴할 글쓴이.
insert into public.polls (id, author_id, question, created_at) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', '첫 데이트 더치페이', now() - interval '3 minutes'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000080', '연락 빈도 하루 한 번', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000080', '카톡 답장 속도', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000083', '떠난 사람의 글', now() - interval '1 minute');
insert into public.polls (id, author_id, question, status)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000080', '가려진 글', 'blinded');

-- P1: V1 a · AU a(작성자 자기 투표 허용) · V2 b · VOFF a(탈퇴 → 집계에서 빠진다)
insert into public.poll_votes (poll_id, voter_id, choice) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000081', 'a'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', 'a'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000082', 'b'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000084', 'a');

update public.profiles set status = 'withdrawn', withdrawn_at = now()
where id in ('00000000-0000-0000-0000-000000000083', '00000000-0000-0000-0000-000000000084');

-- 피드 --
select ok(
  pg_get_function_result('public.poll_feed(uuid,uuid,timestamptz,uuid,integer)'::regprocedure) not like '%author%',
  'poll_feed 는 작성자 칸을 돌려주지 않는다(익명)'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081')$$,
  $$values ('00000000-0000-0000-0000-0000000000a3'::uuid), ('00000000-0000-0000-0000-0000000000a2'::uuid),
           ('00000000-0000-0000-0000-0000000000a1'::uuid)$$,
  '피드는 최신순 · 같은 시각이면 id 큰 것부터, 가려진 글 · 탈퇴한 사람의 글은 없다'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081',
      p_before => (select created_at from public.polls where id = '00000000-0000-0000-0000-0000000000a3'),
      p_before_id => '00000000-0000-0000-0000-0000000000a3')$$,
  $$values ('00000000-0000-0000-0000-0000000000a2'::uuid), ('00000000-0000-0000-0000-0000000000a1'::uuid)$$,
  '커서는 같은 시각의 글을 빠뜨리지 않는다'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081', p_limit => 1)$$,
  $$values ('00000000-0000-0000-0000-0000000000a3'::uuid)$$,
  'p_limit 만큼만 준다'
);
select results_eq(
  $$select a_count, b_count, my_choice, is_mine
      from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000a1')$$,
  $$values (2::bigint, 1::bigint, 'a'::public.poll_choice, false)$$,
  '집계는 active 투표자만(탈퇴한 VOFF 제외), my_choice 는 보는 사람의 표'
);
select is(
  (select is_mine from public.poll_feed('00000000-0000-0000-0000-000000000080', '00000000-0000-0000-0000-0000000000a1')),
  true, '글쓴이 본인에게만 is_mine 이 참이다'
);
select is_empty(
  $$select * from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000b1')$$,
  '가려진 글은 id 로 불러도 없다'
);
select is_empty(
  $$select * from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000c1')$$,
  '탈퇴한 사람의 글은 id 로 불러도 없다'
);

-- 글쓰기: 하루 10개 --
select isnt(
  public.create_poll('00000000-0000-0000-0000-000000000086', '오늘 첫 글', '찬성', '반대'), null,
  'create_poll 은 새 글 id 를 돌려준다'
);
insert into public.polls (author_id, question)
select '00000000-0000-0000-0000-000000000086', '오늘 ' || n || '번째' from generate_series(2, 10) n;
select throws_ok(
  $$select public.create_poll('00000000-0000-0000-0000-000000000086', '열한 번째', '찬성', '반대')$$,
  'CM429', null, '한국 시간 오늘 10개를 올렸으면 11번째는 막힌다'
);
insert into public.polls (author_id, question, created_at)
select '00000000-0000-0000-0000-000000000080', '어제 ' || n,
       (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '1 minute'
from generate_series(1, 10) n;
select lives_ok(
  $$select public.create_poll('00000000-0000-0000-0000-000000000080', '오늘 글', '찬성', '반대')$$,
  '어제(한국 시간) 올린 10개는 오늘 한도에 들지 않는다'
);

-- 보상 판정: 고정 시각(2026-09-28 월 ~ 10-04 일 한 주) --
insert into public.heart_transactions (profile_id, amount, reason, created_at) values
  ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-28 10:00+09'),
  ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-29 10:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-09-29 12:00+09'),
  false, '오늘 이미 받았으면 다시 주지 않는다');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-09-30 12:00+09'),
  true, '이번 주 20하트면 새 날에 또 준다');
insert into public.heart_transactions (profile_id, amount, reason, created_at)
values ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-30 10:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-04 23:59+09'),
  false, '이번 주 30하트를 채웠으면 일요일 밤까지 주지 않는다');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-05 00:00+09'),
  true, '월요일 0시(한국 시간)에 새 주가 시작된다');
insert into public.heart_transactions (profile_id, amount, reason, created_at)
values ('00000000-0000-0000-0000-000000000085', 10, 'admin_adjust', '2026-10-06 09:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-06 12:00+09'),
  true, 'poll_vote 가 아닌 적립은 셈하지 않는다');

-- 투표 (진짜 now()) --
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000082', 'a'),
  true, '오늘 첫 투표면 하트를 준다');
select results_eq(
  $$select amount, reason::text, ref_id from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-000000000082'$$,
  $$values (10, 'poll_vote', '00000000-0000-0000-0000-0000000000a2'::uuid)$$,
  '원장에 10 · poll_vote · ref_id = 글 id 로 남는다'
);
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000082'),
  10, '잔액 캐시도 같은 트랜잭션에서 오른다');
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000082', 'b'),
  false, '같은 날 두 번째 투표는 하트가 없다(투표 자체는 된다)');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000082'),
  10, '두 번째 투표 뒤에도 잔액은 그대로');
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000082', 'b')$$,
  '23505', null, '같은 글에 다시 투표할 수 없다'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '가려진 글에는 투표할 수 없다(없는 글과 같게)'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '탈퇴한 사람의 글에는 투표할 수 없다'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '없는 글'
);
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000080', 'a'),
  true, '글쓴이도 자기 글에 투표할 수 있다(사용자 결정 4-2)');
select ok(
  pg_get_functiondef('public.cast_poll_vote(uuid,uuid,public.poll_choice)'::regprocedure) like '%pg_advisory_xact_lock%',
  'cast_poll_vote 는 사람 단위 잠금을 건다(동시 투표 두 개에 하트 한 번) — 경합 스크립트는 계획서 C2 Step 5'
);

-- 탈퇴 cascade --
delete from auth.users where id = '00000000-0000-0000-0000-000000000082';
select is((select count(*) from public.poll_votes where voter_id = '00000000-0000-0000-0000-000000000082'),
  0::bigint, '계정이 지워지면 그 사람의 투표도 지워진다');
delete from auth.users where id = '00000000-0000-0000-0000-000000000083';
select is((select count(*) from public.polls where author_id = '00000000-0000-0000-0000-000000000083'),
  0::bigint, '계정이 지워지면 그 사람의 글도 지워진다');
```

  그리고 파일 끝 `set local role anon;` **앞**(authenticated 절 안)에 함수 권한 4개:

```sql
select throws_ok($$select * from public.poll_feed('00000000-0000-0000-0000-000000000080')$$,
  '42501', null, 'authenticated 는 poll_feed 를 부를 수 없다');
select throws_ok($$select public.create_poll('00000000-0000-0000-0000-000000000080', '질문', '찬성', '반대')$$,
  '42501', null, 'authenticated 는 create_poll 을 부를 수 없다');
select throws_ok($$select public.poll_vote_reward_due('00000000-0000-0000-0000-000000000080', now())$$,
  '42501', null, 'authenticated 는 poll_vote_reward_due 를 부를 수 없다');
select throws_ok($$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', 'a')$$,
  '42501', null, 'authenticated 는 cast_poll_vote 를 부를 수 없다');
```

- [ ] **Step 2: RED 확인.** `supabase test db` → C2 단정이 "function does not exist" 로 실패하는지 본다.

- [ ] **Step 3: 마이그레이션.** `supabase/migrations/20260927020100_create_poll_functions.sql`:

```sql
-- 커뮤니티 탭 DB 함수 네 개. 부르는 쪽은 FastAPI(service_role) 하나다.
-- 전부 security invoker — service_role 이 표 권한을 다 가지고 RLS 를 우회하므로 definer 로 권한을 빌릴 이유가 없다.
-- 앱 역할이 부르는 길은 파일 끝 revoke 로 막는다(home_stats 와 같은 모양).

-- 15d 피드 · 17c 상세. 반환 칸에 author_id 가 없다 — 익명은 여기서 끝난다. 본인에게는 is_mine 만 준다.
-- 가려진 글 · 글쓴이가 active 가 아닌 글은 없고, active 가 아닌 투표자의 표는 세지 않는다(ERD 264줄).
-- 피드 범위는 전체 학교다(2026-09-27 사용자 결정 1).
create function public.poll_feed(
  p_viewer uuid,
  p_poll_id uuid default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  question text,
  option_a_label text,
  option_b_label text,
  created_at timestamptz,
  a_count bigint,
  b_count bigint,
  my_choice public.poll_choice,
  is_mine boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.question, p.option_a_label, p.option_b_label, p.created_at,
         c.a_count, c.b_count,
         (select mv.choice from public.poll_votes mv where mv.poll_id = p.id and mv.voter_id = p_viewer),
         p.author_id = p_viewer
    from public.polls p
    join public.profiles author on author.id = p.author_id and author.status = 'active'
   -- ponytail: 요청마다 표를 센다. 글 하나에 표가 수천이 되면 polls 에 집계 칸을 두고 투표 때 올린다.
   cross join lateral (
     select count(*) filter (where v.choice = 'a') as a_count,
            count(*) filter (where v.choice = 'b') as b_count
       from public.poll_votes v
       join public.profiles voter on voter.id = v.voter_id and voter.status = 'active'
      where v.poll_id = p.id
   ) c
   where p.status = 'visible'
     and (p_poll_id is null or p.id = p_poll_id)
     -- 채팅 메시지와 같은 (시각, id) 커서. 같은 시각의 두 글이 경계에서 빠지지 않는다.
     and (p_before is null or (p.created_at, p.id) < (p_before, p_before_id))
   order by p.created_at desc, p.id desc
   limit p_limit;
$$;

-- 17b 질문 올리기. 한국 시간 하루 10개(2026-09-27 사용자 결정 3). 지운 글은 세지 않는다.
create function public.create_poll(p_author uuid, p_question text, p_option_a text, p_option_b text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- 같은 사람이 두 번 동시에 올려도 11번째가 끼지 않게 사람 단위로 줄 세운다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('create_poll'), hashtext(p_author::text));

  if (select count(*) from public.polls
       where author_id = p_author
         and created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 10 then
    -- 서버가 이 코드를 보고 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
    raise exception 'poll daily limit' using errcode = 'CM429';
  end if;

  insert into public.polls (author_id, question, option_a_label, option_b_label)
  values (p_author, p_question, p_option_a, p_option_b)
  returning id into v_id;
  return v_id;
end;
$$;

-- 투표 보상을 줄 차례인가: 한국 시간 오늘 poll_vote 적립이 없고, 이번 주(월 0시 시작) 합이 30 을 넘지 않을 때.
-- 원장(heart_transactions)으로 센다(ERD 508줄). p_now 를 받는 이유는 pgTAP 이 고정 시각으로 경계를 확인하려고.
-- volatile(기본값)로 둔다. 지금은 잠금이 별도 문장이라 stable 이어도 맞게 돌지만, 나중에 잠금과 한 문장 안에서
-- 불리게 바뀌면 stable 은 문장 시작 스냅샷을 써서 앞 트랜잭션이 막 커밋한 원장 행을 못 본다.
create function public.poll_vote_reward_due(p_voter uuid, p_now timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with bounds as (
    select date_trunc('day', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as day_start,
           date_trunc('week', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as week_start
  )
  select not exists (
           select 1 from public.heart_transactions t
            where t.profile_id = p_voter and t.reason = 'poll_vote'
              and t.created_at >= b.day_start and t.created_at < b.day_start + interval '1 day')
         -- 10하트를 더해도 주간 상한 30 안이어야 한다(DESIGN §8.10 무료 획득 표).
         and (select coalesce(sum(t.amount), 0) from public.heart_transactions t
               where t.profile_id = p_voter and t.reason = 'poll_vote'
                 and t.created_at >= b.week_start and t.created_at < b.week_start + interval '7 days') + 10 <= 30
    from bounds b;
$$;

-- 투표 + 보상을 한 트랜잭션에서. 돌려주는 값 = 이번 투표로 하트를 줬는가.
create function public.cast_poll_vote(p_poll_id uuid, p_voter uuid, p_choice public.poll_choice)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due boolean;
begin
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다.
  if not exists (
    select 1 from public.polls p
      join public.profiles a on a.id = p.author_id and a.status = 'active'
     where p.id = p_poll_id and p.status = 'visible'
  ) then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  -- 한 사람의 투표를 줄 세운다. 서로 다른 글 두 개에 동시에 투표하면 둘 다 "오늘 아직 안 받았다" 를 보고
  -- 20하트가 나간다 — 뒤에 온 쪽이 앞 트랜잭션이 끝날 때까지 여기서 기다린다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('cast_poll_vote'), hashtext(p_voter::text));

  -- 재투표는 PK(poll_id, voter_id) 가 23505 로 막는다 → 서버 409.
  insert into public.poll_votes (poll_id, voter_id, choice) values (p_poll_id, p_voter, p_choice);

  v_due := public.poll_vote_reward_due(p_voter, now());
  if v_due then
    -- 조각 2 의 원장 + 잔액 캐시 함수를 그대로 쓴다. 같은 트랜잭션이라 투표가 실패하면 하트도 없다.
    perform public.grant_hearts(p_voter, 10, 'poll_vote', p_poll_id);
  end if;
  return v_due;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
revoke execute on function public.create_poll(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.poll_vote_reward_due(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) from public, anon, authenticated;
grant execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer) to service_role;
grant execute on function public.create_poll(uuid, text, text, text) to service_role;
grant execute on function public.poll_vote_reward_due(uuid, timestamptz) to service_role;
grant execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) to service_role;
```

- [ ] **Step 4: GREEN 확인.** `supabase db reset` → `supabase test db`. 기대: `community_polls_test.sql .. ok`(54),
  다른 파일 전부 ok.

- [ ] **Step 5: 경합 확인(Review Focus 1, RED → GREEN).** pgTAP 은 연결이 하나라 동시성을 못 본다. 연결 두 개로 직접
  확인한다. 먼저 `cast_poll_vote` 의 `perform pg_advisory_xact_lock(...)` 줄을 **주석 처리**하고 `supabase db reset`
  뒤 아래를 돌려 **2 · 20** 이 나오는지(RED) 본다. 주석을 풀고 `db reset` 뒤 다시 돌려 **1 · 10**(GREEN)을 본다.
  스크립트는 커밋하지 않고, 두 번의 출력을 PR 본문에 붙인다.

```bash
DB='docker exec -i supabase_db_campus_mate_compose psql -U postgres -d postgres -qAt -v ON_ERROR_STOP=1'
U=00000000-0000-0000-0000-0000000000f
$DB <<SQL
insert into public.universities (id, name, region_group) values ('${U}7', '경합대학교', 'seoul');
insert into public.university_email_domains (domain, university_id) values ('race7.ac.kr', '${U}7');
insert into auth.users (id, email) values ('${U}1', 'race-a@race7.ac.kr'), ('${U}2', 'race-v@race7.ac.kr');
insert into public.profiles (id, university_id) select id, '${U}7' from auth.users
 where id in ('${U}1', '${U}2') on conflict (id) do nothing;
update public.profiles set status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id when '${U}1' then '경합글쓴' else '경합투표' end where id in ('${U}1', '${U}2');
insert into public.polls (id, author_id, question) values ('${U}a', '${U}1', '경합 하나'), ('${U}b', '${U}1', '경합 둘');
SQL
# 한 사람이 서로 다른 글 두 개에 거의 동시에 투표한다. 첫 트랜잭션은 투표한 뒤 2초 동안 커밋하지 않는다.
$DB -c "begin; select public.cast_poll_vote('${U}a', '${U}2', 'a'); select pg_sleep(2); commit;" &
sleep 0.5
$DB -c "select public.cast_poll_vote('${U}b', '${U}2', 'b');"
wait
$DB -c "select count(*) from public.heart_transactions where profile_id = '${U}2' and reason = 'poll_vote';"
$DB -c "select heart_balance from public.entitlements where profile_id = '${U}2';"
# 정리 — auth.users 를 지우면 profiles · polls · poll_votes · 원장이 cascade 로 따라간다.
$DB -c "delete from auth.users where id in ('${U}1', '${U}2');
        delete from public.university_email_domains where domain = 'race7.ac.kr';
        delete from public.universities where id = '${U}7';"
```

- [ ] **Step 6: 커밋.** `🗃️ feat(db): 커뮤니티 피드 · 글쓰기 · 투표 보상 DB 함수 추가` (마이그레이션 + pgTAP)

---

# Part B — FastAPI (PR 1 이 운영 DB 에 적용된 뒤 배포)

### Task B1: 피드 · 상세 읽기

**Files:**
- Create: `backend/app/community/__init__.py`(빈 파일), `backend/app/community/repository.py`, `backend/app/community/router.py`
- Modify(공유 파일, 결정 D3 허락): `backend/app/core/errors.py`(3줄), `backend/app/main.py`(2줄)
- Test: `backend/tests/community/test_community_polls.py`

**Interfaces:**
- Consumes: C2 `rpc/poll_feed`
- Produces: `CommunityRepository.fetch_polls(viewer, *, poll_id=None, before=None, before_id=None, limit=POLL_PAGE_SIZE) -> list[dict]`,
  `POLL_PAGE_SIZE = 20`, `_card(row) -> dict`(9칸), `GET /community/polls`, `GET /community/polls/{poll_id}`

- [ ] **Step 1: 실패 테스트.** `backend/tests/community/test_community_polls.py`:

```python
import json
from collections.abc import Callable

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
POLL_ID = "22222222-2222-2222-2222-222222222222"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
POLL_KEYS = {"id", "question", "option_a_label", "option_b_label", "created_at",
             "a_count", "b_count", "my_choice", "is_mine"}


def _row(**overrides) -> dict:
    row = {
        "id": POLL_ID, "question": "첫 데이트 더치페이", "option_a_label": "찬성", "option_b_label": "반대",
        "created_at": "2026-09-27T05:00:00+00:00", "a_count": 5, "b_count": 3, "my_choice": None, "is_mine": False,
    }
    return {**row, **overrides}


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


def _wire(handler: Callable[[httpx.Request], httpx.Response], seen: list[httpx.Request] | None = None,
          verification: str = "verified") -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": verification, "department": "컴공"}])
        if seen is not None:
            seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app)


def _rpc(name: str, response: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST" and request.url.path.endswith(f"/rpc/{name}"):
            return response
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_feed_gives_nine_keys_and_never_author_id():
    # DB 함수가 실수로 author_id 를 돌려줘도 응답에는 실리지 않아야 한다(익명, Global Constraint 1).
    leaked = _row(author_id=PROFILE_ID)
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[leaked]))).get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert set(response.json()["polls"][0]) == POLL_KEYS


def test_feed_sends_viewer_cursor_and_page_size():
    seen: list[httpx.Request] = []
    _wire(_rpc("poll_feed", httpx.Response(200, json=[])), seen).get(
        "/community/polls", params={"before": "2026-09-27T05:00:00+00:00", "before_id": POLL_ID},
        headers=AUTH_HEADERS)
    body = json.loads(seen[0].content)
    assert body["p_viewer"] == PROFILE_ID
    assert body["p_poll_id"] is None
    assert body["p_before"] == "2026-09-27T05:00:00+00:00"
    assert body["p_before_id"] == POLL_ID
    assert body["p_limit"] == 20


@pytest.mark.parametrize("params", [{"before": "2026-09-27T05:00:00+00:00"}, {"before_id": POLL_ID}])
def test_feed_rejects_half_cursor(params):
    # 하나만 오면 DB 커서 비교가 null 이 돼 빈 페이지가 "끝" 으로 읽힌다.
    seen: list[httpx.Request] = []
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[])), seen).get(
        "/community/polls", params=params, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


@pytest.mark.parametrize(("count", "has_more"), [(20, True), (3, False)])
def test_feed_has_more_only_when_page_is_full(count, has_more):
    rows = [_row(id=f"{i:08d}-2222-2222-2222-222222222222") for i in range(count)]
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=rows))).get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.json()["has_more"] is has_more


def test_detail_returns_one_poll():
    seen: list[httpx.Request] = []
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[_row(my_choice="a")])), seen).get(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json()["poll"]["my_choice"] == "a"
    body = json.loads(seen[0].content)
    assert body["p_poll_id"] == POLL_ID
    assert body["p_limit"] == 1


def test_detail_404_when_hidden_or_missing():
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[]))).get(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_feed_requires_student_verification():
    response = _wire(_rpc("poll_feed", httpx.Response(200, json=[])), verification="pending").get(
        "/community/polls", headers=AUTH_HEADERS)
    assert response.status_code == 403
```

- [ ] **Step 2: RED.** 루트 `.venv` 파이썬으로:
  `C:/Users/user/AndroidStudioProjects/campus_mate_compose/backend/.venv/Scripts/python.exe -c "import app; print(app.__file__)"`
  (워크트리 backend 에서 돌려 이 워크트리를 읽는지 확인) →
  `...python.exe -m pytest -q tests/community` → `ModuleNotFoundError: app.community` 또는 404 로 실패.

- [ ] **Step 3: 구현.** `backend/app/core/errors.py` 끝(공유 파일, 결정 D3 허락):

```python

# 커뮤니티
POLL_NOT_FOUND = "질문을 찾을 수 없어요"
POLL_ALREADY_VOTED = "이미 투표했어요"
POLL_DAILY_LIMIT = "오늘은 질문을 더 올릴 수 없어요"
```

`backend/app/community/repository.py`:

```python
from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 한 번에 내려주는 질문 수. 앱 pollPageSize 와 같은 값이다.
POLL_PAGE_SIZE = 20


class CommunityRepository(PostgrestRepository):
    """커뮤니티 질문 · 투표. 읽기와 쓰기가 DB 함수(RPC)를 거친다 — 집계 · 작성자 숨기기 · 하루 한도 ·
    투표 보상이 DB 한 곳에 있다(마이그레이션 20260927020100). 삭제만 PostgREST 로 바로 한다."""

    async def fetch_polls(self, viewer: UUID, *, poll_id: UUID | None = None,
                          before: datetime | None = None, before_id: UUID | None = None,
                          limit: int = POLL_PAGE_SIZE) -> list[dict]:
        response = await self._post("rpc/poll_feed", json={
            "p_viewer": str(viewer),
            "p_poll_id": str(poll_id) if poll_id else None,
            "p_before": before.isoformat() if before else None,
            "p_before_id": str(before_id) if before_id else None,
            "p_limit": limit,
        })
        raise_for_status(response)
        return response.json()
```

`backend/app/community/router.py`:

```python
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.community.repository import POLL_PAGE_SIZE, CommunityRepository
from app.core import errors
from app.core.deps import Caller, get_verified_caller

router = APIRouter()

# 응답에 싣는 칸. DB 함수가 author_id 를 주지 않지만 칸이 늘어도 새지 않게 여기서 한 번 더 고른다(익명).
_POLL_KEYS = ("id", "question", "option_a_label", "option_b_label", "created_at",
              "a_count", "b_count", "my_choice", "is_mine")


def _card(row: dict) -> dict:
    return {key: row[key] for key in _POLL_KEYS}


def _repo(caller: Caller) -> CommunityRepository:
    return CommunityRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@router.get("/community/polls")
async def list_polls(before: datetime | None = None, before_id: UUID | None = None,
                     caller: Caller = Depends(get_verified_caller)) -> dict:
    """15d 피드. 최신 글부터 20개, 전체 학교(사용자 결정 1). 더 내리면 화면 맨 아래 글의
    `created_at` · `id` 를 그대로 보낸다 — 채팅 메시지와 같은 커서다."""
    if (before is None) != (before_id is None):
        # 하나만 오면 DB 의 (created_at, id) 비교가 null 이 돼 빈 페이지가 "끝" 으로 읽힌다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    rows = await _repo(caller).fetch_polls(caller.profile_id, before=before, before_id=before_id)
    return {"polls": [_card(row) for row in rows], "has_more": len(rows) == POLL_PAGE_SIZE}


@router.get("/community/polls/{poll_id}")
async def get_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17c 상세. 가려진 글 · 떠난 사람의 글은 피드처럼 없다."""
    rows = await _repo(caller).fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0])}
```

`backend/app/main.py`(공유 파일, 결정 D3 허락): `from app.community.router import router as community_router` 를
import 목록 알파벳 자리(`chat` 과 `core` 사이)에, `app.include_router(community_router)` 를 `me_router` 다음 줄에.

- [ ] **Step 4: GREEN.** `...python.exe -m pytest -q tests/community` 전부 통과, 이어서 `...python.exe -m pytest -q`
  전체(기준선 대비 +9, 실패 0).

- [ ] **Step 5: 커밋.** 두 개로 나눈다 — `✨ feat(community): 커뮤니티 피드 · 상세 API 추가`(community/ 세 파일 +
  errors.py + main.py), `✅ test(community): 커뮤니티 피드 · 상세 테스트 추가`

---

### Task B2: 글쓰기 · 투표 · 삭제

**Files:**
- Modify: `backend/app/community/repository.py`, `backend/app/community/router.py`
- Test: `backend/tests/community/test_community_polls.py`(이어 쓰기)

**Interfaces:**
- Consumes: C2 `rpc/create_poll`(`CM429`), `rpc/cast_poll_vote`(`CM404` · `23503` → 404, `23505` → 409), B1 `fetch_polls` · `_card`
- Produces: `POST /community/polls` → 201 `{"id"}`, `POST /community/polls/{id}/votes` → 200 `{"poll", "rewarded"}`,
  `DELETE /community/polls/{id}` → 204

- [ ] **Step 1: 실패 테스트(이어 쓰기).**

```python
def _routes(**responses: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    """rpc 이름 → 응답. DELETE 는 키 'delete' 로 준다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "DELETE" and request.url.path.endswith("/polls"):
            return responses["delete"]
        name = request.url.path.rsplit("/rpc/", 1)[-1]
        if request.method == "POST" and name in responses:
            return responses[name]
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def test_create_trims_and_defaults_labels():
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_poll=httpx.Response(200, json=POLL_ID)), seen).post(
        "/community/polls", json={"question": "  짜장 vs 짬뽕  "}, headers=AUTH_HEADERS)
    assert response.status_code == 201
    assert response.json() == {"id": POLL_ID}
    assert json.loads(seen[0].content) == {
        "p_author": PROFILE_ID, "p_question": "짜장 vs 짬뽕", "p_option_a": "찬성", "p_option_b": "반대"}


@pytest.mark.parametrize("body", [
    {"question": "   "},
    {"question": "가" * 81},
    {"question": "질문", "option_a_label": "가" * 7},
    {"question": "질문", "option_a_label": "좋아", "option_b_label": "좋아"},
    {"question": "질문", "option_b_label": "  "},
])
def test_create_rejects_bad_input_before_db(body):
    seen: list[httpx.Request] = []
    response = _wire(_routes(create_poll=httpx.Response(200, json=POLL_ID)), seen).post(
        "/community/polls", json=body, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_create_daily_limit_is_429():
    response = _wire(_routes(create_poll=httpx.Response(400, json={"code": "CM429", "message": "poll daily limit"}))).post(
        "/community/polls", json={"question": "열한 번째"}, headers=AUTH_HEADERS)
    assert response.status_code == 429
    assert response.json()["detail"] == errors.POLL_DAILY_LIMIT


def test_vote_returns_fresh_poll_and_reward():
    seen: list[httpx.Request] = []
    handler = _routes(cast_poll_vote=httpx.Response(200, json=True),
                      poll_feed=httpx.Response(200, json=[_row(my_choice="a", a_count=6)]))
    response = _wire(handler, seen).post(
        f"/community/polls/{POLL_ID}/votes", json={"choice": "a"}, headers=AUTH_HEADERS)
    assert response.status_code == 200
    assert response.json()["rewarded"] is True
    assert set(response.json()["poll"]) == POLL_KEYS
    assert response.json()["poll"]["a_count"] == 6
    assert json.loads(seen[0].content) == {"p_poll_id": POLL_ID, "p_voter": PROFILE_ID, "p_choice": "a"}


def test_vote_twice_is_409():
    handler = _routes(cast_poll_vote=httpx.Response(409, json={"code": "23505", "message": "duplicate key"}))
    response = _wire(handler).post(f"/community/polls/{POLL_ID}/votes", json={"choice": "b"}, headers=AUTH_HEADERS)
    assert response.status_code == 409
    assert response.json()["detail"] == errors.POLL_ALREADY_VOTED


@pytest.mark.parametrize("db_error", [
    httpx.Response(400, json={"code": "CM404", "message": "poll not found"}),
    # 확인과 insert 사이에 글이 지워짐 — PostgREST 는 FK 위반을 409 로 보낸다.
    httpx.Response(409, json={"code": "23503", "message": "violates foreign key constraint"}),
])
def test_vote_on_missing_or_hidden_poll_is_404(db_error):
    handler = _routes(cast_poll_vote=db_error)
    response = _wire(handler).post(f"/community/polls/{POLL_ID}/votes", json={"choice": "a"}, headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_vote_rejects_unknown_choice():
    seen: list[httpx.Request] = []
    response = _wire(_routes(cast_poll_vote=httpx.Response(200, json=True)), seen).post(
        f"/community/polls/{POLL_ID}/votes", json={"choice": "c"}, headers=AUTH_HEADERS)
    assert response.status_code == 422
    assert seen == []


def test_delete_own_poll_filters_by_author():
    seen: list[httpx.Request] = []
    response = _wire(_routes(delete=httpx.Response(200, json=[{"id": POLL_ID}])), seen).delete(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 204
    # author_id 조건이 빠지면 남의 글 id 로 지울 수 있다.
    assert seen[0].url.params["author_id"] == f"eq.{PROFILE_ID}"
    assert seen[0].url.params["id"] == f"eq.{POLL_ID}"
    assert seen[0].headers["Prefer"] == "return=representation"


def test_delete_others_poll_is_404_not_403():
    response = _wire(_routes(delete=httpx.Response(200, json=[]))).delete(
        f"/community/polls/{POLL_ID}", headers=AUTH_HEADERS)
    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND
```

- [ ] **Step 2: RED.** `...python.exe -m pytest -q tests/community` → 새 테스트가 405/404 로 실패.

- [ ] **Step 3: 구현.** `repository.py` 에 추가(import 에 `from fastapi import HTTPException`,
  `from app.core import errors`, `from app.core.http import error_code, raise_for_status`):

```python
    async def create_poll(self, author: UUID, question: str, option_a: str, option_b: str) -> str:
        response = await self._post("rpc/create_poll", json={
            "p_author": str(author), "p_question": question, "p_option_a": option_a, "p_option_b": option_b,
        })
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.POLL_DAILY_LIMIT)
        raise_for_status(response)
        return response.json()

    async def cast_vote(self, poll_id: UUID, voter: UUID, choice: str) -> bool:
        """투표 + 하루 첫 투표 보상을 DB 한 트랜잭션에서. 돌려주는 값 = 하트를 줬는가."""
        response = await self._post("rpc/cast_poll_vote", json={
            "p_poll_id": str(poll_id), "p_voter": str(voter), "p_choice": choice,
        })
        # CM404 = 투표 전 확인에서 없음. 23503 = 확인과 insert 사이에 글이 지워져 FK 가 깨짐 — 둘 다 "없는 글" 이다.
        # 23503 을 그냥 두면 raise_for_status 가 422 "입력한 값을 다시 확인해 주세요" 를 낸다.
        if error_code(response) in ("CM404", "23503"):
            raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
        raise_for_status(response, conflict_detail=errors.POLL_ALREADY_VOTED)
        return response.json()

    async def delete_poll(self, poll_id: UUID, author: UUID) -> bool:
        """본인 글이면 지우고 참. 투표는 cascade 로 같이 지워진다(사용자 결정 2)."""
        # 지워진 행을 돌려받아야 "없었다" 와 "지웠다" 를 가른다 — 부모 _delete 는 Prefer 를 받지 않는다.
        response = await self._client.delete(
            f"{self._postgrest_url}/polls",
            params={"id": f"eq.{poll_id}", "author_id": f"eq.{author}", "select": "id"},
            headers=self._with_prefer("return=representation"),
        )
        raise_for_status(response)
        return bool(response.json())
```

`router.py` 에 추가(import 에 `from typing import Literal`, `from fastapi import Response`,
`from pydantic import BaseModel, Field, field_validator, model_validator`):

```python
# 앱 pollQuestionMaxLength · pollOptionMaxLength, DB polls_* check 와 같은 값이다.
QUESTION_MAX_LENGTH = 80
OPTION_MAX_LENGTH = 6


class PollRequest(BaseModel):
    question: str = Field(min_length=1, max_length=QUESTION_MAX_LENGTH)
    option_a_label: str = Field(default="찬성", min_length=1, max_length=OPTION_MAX_LENGTH)
    option_b_label: str = Field(default="반대", min_length=1, max_length=OPTION_MAX_LENGTH)

    @field_validator("question", "option_a_label", "option_b_label")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("빈칸뿐인 값은 올릴 수 없다")
        return stripped

    @model_validator(mode="after")
    def _options_differ(self) -> "PollRequest":
        if self.option_a_label == self.option_b_label:
            raise ValueError("두 선택지가 같다")
        return self


class VoteRequest(BaseModel):
    choice: Literal["a", "b"]


@router.post("/community/polls", status_code=201)
async def create_poll(body: PollRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17b. 한국 시간 하루 10개(사용자 결정 3) — 넘으면 429."""
    poll_id = await _repo(caller).create_poll(
        caller.profile_id, body.question, body.option_a_label, body.option_b_label)
    return {"id": poll_id}


@router.post("/community/polls/{poll_id}/votes")
async def vote(poll_id: UUID, body: VoteRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """투표는 되돌릴 수 없다. 하루 첫 투표면 10하트(주 30 상한) — `rewarded` 로 알려 앱이 토스트를 띄운다."""
    repo = _repo(caller)
    rewarded = await repo.cast_vote(poll_id, caller.profile_id, body.choice)
    rows = await repo.fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        # 투표와 다시 읽기 사이에 글이 지워졌다. 투표도 cascade 로 사라졌으니 없는 글과 같게 답한다.
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0]), "rewarded": rewarded}


@router.delete("/community/polls/{poll_id}", status_code=204)
async def delete_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller)) -> Response:
    if not await _repo(caller).delete_poll(poll_id, caller.profile_id):
        # 남의 글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 글이라는 게 샌다.
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return Response(status_code=204)
```

- [ ] **Step 4: GREEN.** `...python.exe -m pytest -q` 전체 통과(B2 +14, B1 과 합쳐 기준선 대비 +23).
- [ ] **Step 5: 커밋.** `✨ feat(community): 질문 올리기 · 투표 · 삭제 API 추가`, `✅ test(community): 글쓰기 · 투표 · 삭제 테스트 추가`

---

# Part A — Flutter (워크트리 `../campus_mate_compose-community-app`, PR 2 와 나란히 — 결정 D2)

> 화면 코드는 값표 1~10절의 노드 id · 값으로 썼다. **각 화면 Task 의 마지막 Step 이 "pen 검토 반영"** 이다 — 사용자 pen
> 검토에서 바뀐 곳(특히 결정 대기 2건)을 맞추고, 고친 값 옆에 `// pen <노드 id>` 주석을 단다(기존 화면들과 같은 관례).
> 새 화면은 COMMON §4-2(잉크) · 글자 확대(고정 높이 대신 minHeight) 규칙을 지킨다.

### Task A1: 모델 · 저장소

**Files:**
- Create: `frontend/lib/community/model/poll.dart`, `community_repository.dart`, `http_community_repository.dart`, `community_repository_provider.dart`
- Test: `frontend/test/community/model/poll_test.dart`, `http_community_repository_test.dart`, `fake_community_repository.dart`

**Interfaces:**
- Consumes: 위 API 계약, `ApiClient.send`, `apiClientProvider`
- Produces: `Poll`(id · question · optionA · optionB · createdAt · aCount · bCount · myChoice · isMine, getter `total` ·
  `aPercent` · `bPercent` · `usesDefaultLabels`), `PollChoice { a, b }`, `PollPage`, `VoteOutcome`, `pollPageSize = 20`,
  `defaultOptionA` · `defaultOptionB` · `pollQuestionMaxLength = 80` · `pollOptionMaxLength = 6`,
  `CommunityRepository`(fetchPolls · fetchPoll · createPoll · vote · deletePoll), `communityRepositoryProvider`,
  테스트용 `FakeCommunityRepository` · `pollFixture()`

- [ ] **Step 1: 실패 테스트.** `test/community/model/poll_test.dart`:

```dart
import 'package:campus_mate/community/model/poll.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? myChoice, int a = 5, int b = 3, String optionA = '찬성'}) => {
      'id': 'p1',
      'question': '첫 데이트 더치페이',
      'option_a_label': optionA,
      'option_b_label': '반대',
      'created_at': '2026-09-27T05:00:00+00:00',
      'a_count': a,
      'b_count': b,
      'my_choice': myChoice,
      'is_mine': false,
    };

void main() {
  test('서버 칸을 읽는다', () {
    final poll = Poll.fromJson(_json(myChoice: 'b'));
    expect(poll.id, 'p1');
    expect(poll.myChoice, PollChoice.b);
    expect(poll.total, 8);
    expect(poll.createdAt.isUtc, isFalse);
  });

  test('아직 투표 안 했으면 myChoice 는 null', () {
    expect(Poll.fromJson(_json()).myChoice, isNull);
  });

  test('퍼센트는 반올림하고 두 쪽 합이 100 이다', () {
    final poll = Poll.fromJson(_json(a: 2, b: 1));
    expect(poll.aPercent, 67);
    expect(poll.bPercent, 33);
  });

  test('아무도 투표하지 않았으면 0 · 0', () {
    final poll = Poll.fromJson(_json(a: 0, b: 0));
    expect(poll.aPercent, 0);
    expect(poll.bPercent, 0);
  });

  test('라벨이 둘 다 기본값일 때만 O·X 아이콘을 쓴다', () {
    expect(Poll.fromJson(_json()).usesDefaultLabels, isTrue);
    expect(Poll.fromJson(_json(optionA: '짜장')).usesDefaultLabels, isFalse);
  });
}
```

  `test/community/model/http_community_repository_test.dart` — `http_home_repository_test.dart` 의 `MockGoTrueClient`
  · `MockSession` · `jsonResponse` 준비를 그대로 복사하고:

```dart
  test('첫 쪽은 쿼리 없이, 다음 쪽은 맨 아래 글의 시각(UTC)과 id 로 부른다', () async {
    final urls = <String>[];
    final repository = buildRepository(MockClient((request) async {
      urls.add(request.url.toString());
      return jsonResponse({'polls': [], 'has_more': false});
    }));

    await repository.fetchPolls();
    await repository.fetchPolls(before: DateTime.utc(2026, 9, 27, 5), beforeId: 'p9');

    expect(urls[0], 'https://api.test/community/polls');
    expect(Uri.parse(urls[1]).queryParameters, {'before': '2026-09-27T05:00:00.000Z', 'before_id': 'p9'});
  });

  test('투표는 choice 를 보내고 새 글과 보상 여부를 읽는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/community/polls/p1/votes');
      expect(jsonDecode(request.body), {'choice': 'a'});
      return jsonResponse({
        'poll': {
          'id': 'p1', 'question': 'q', 'option_a_label': '찬성', 'option_b_label': '반대',
          'created_at': '2026-09-27T05:00:00+00:00', 'a_count': 1, 'b_count': 0, 'my_choice': 'a', 'is_mine': false,
        },
        'rewarded': true,
      });
    }));

    final outcome = await repository.vote('p1', PollChoice.a);

    outcome.when(
      onSuccess: (value) {
        expect(value.rewarded, isTrue);
        expect(value.poll.myChoice, PollChoice.a);
      },
      onFailure: (failure) => fail('$failure'),
    );
  });

  test('삭제는 204 빈 본문도 성공으로 읽는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/community/polls/p1');
      return http.Response('', 204);
    }));

    final result = await repository.deletePoll('p1');

    expect(result, isA<Success<void>>());
  });
```

- [ ] **Step 2: RED.** 워크트리 `frontend/` 에서 `flutter test test/community/model` → import 오류로 실패.

- [ ] **Step 3: 구현.** `lib/community/model/poll.dart`:

```dart
/// 선택지 기본 라벨. 둘 다 이 값이면 카드가 글자 대신 O·X 아이콘을 그린다(DESIGN §8.11).
const String defaultOptionA = '찬성';
const String defaultOptionB = '반대';

/// 서버 `QUESTION_MAX_LENGTH` · `OPTION_MAX_LENGTH`, DB check 와 같은 값이다.
const int pollQuestionMaxLength = 80;
const int pollOptionMaxLength = 6;

enum PollChoice { a, b }

/// 커뮤니티 질문 하나. **작성자가 누구인지는 모른다** — 서버가 [isMine] 만 준다.
class Poll {
  const Poll({
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.createdAt,
    required this.aCount,
    required this.bCount,
    this.myChoice,
    this.isMine = false,
  });

  final String id;
  final String question;
  final String optionA;
  final String optionB;
  final DateTime createdAt;
  final int aCount;
  final int bCount;
  final PollChoice? myChoice;
  final bool isMine;

  int get total => aCount + bCount;

  /// 반올림한 A 쪽 %. B 쪽은 100 에서 빼서 두 수의 합이 늘 100 이다("찬성 62% · 반대 38%").
  int get aPercent => total == 0 ? 0 : (aCount * 100 / total).round();
  int get bPercent => total == 0 ? 0 : 100 - aPercent;

  bool get usesDefaultLabels => optionA == defaultOptionA && optionB == defaultOptionB;

  factory Poll.fromJson(Map<String, dynamic> json) {
    return Poll(
      id: json['id'] as String,
      question: json['question'] as String,
      optionA: json['option_a_label'] as String,
      optionB: json['option_b_label'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      aCount: json['a_count'] as int,
      bCount: json['b_count'] as int,
      myChoice: switch (json['my_choice']) {
        'a' => PollChoice.a,
        'b' => PollChoice.b,
        _ => null,
      },
      isMine: json['is_mine'] as bool,
    );
  }
}
```

`lib/community/model/community_repository.dart`:

```dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/poll.dart';

/// 한 번에 받아 오는 질문 수. 서버 `POLL_PAGE_SIZE` 와 같은 값이다.
const int pollPageSize = 20;

class PollPage {
  const PollPage({required this.polls, required this.hasMore});

  final List<Poll> polls;
  final bool hasMore;

  factory PollPage.fromJson(Map<String, dynamic> json) {
    return PollPage(
      polls: (json['polls'] as List<dynamic>)
          .map((item) => Poll.fromJson(item as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
    );
  }
}

/// 투표 결과. [rewarded] 면 하루 첫 투표 하트 10개가 들어갔다.
class VoteOutcome {
  const VoteOutcome({required this.poll, required this.rewarded});

  final Poll poll;
  final bool rewarded;

  factory VoteOutcome.fromJson(Map<String, dynamic> json) {
    return VoteOutcome(
      poll: Poll.fromJson(json['poll'] as Map<String, dynamic>),
      rewarded: json['rewarded'] as bool,
    );
  }
}

/// 커뮤니티 탭이 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
abstract interface class CommunityRepository {
  /// [before] · [beforeId] 는 화면 맨 아래 글의 값을 그대로 보낸다 —
  /// 시각만 보내면 같은 시각에 올라간 두 글이 쪽 경계에서 하나 빠진다.
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId});
  Future<Result<Poll>> fetchPoll(String pollId);
  Future<Result<void>> createPoll({required String question, required String optionA, required String optionB});

  /// 되돌릴 수 없다(DESIGN §8.11).
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice);

  /// 내 글만 지워진다. 남의 글 id 면 서버가 "없음" 으로 답한다.
  Future<Result<void>> deletePoll(String pollId);
}
```

`lib/community/model/http_community_repository.dart`:

```dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [CommunityRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// `sendAuthorizedRequest` 가 이미 하므로 여기서는 URL · 바디 · 파싱만 맡는다.
class HttpCommunityRepository implements CommunityRepository {
  const HttpCommunityRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId}) => _api.send(
        'GET',
        '/community/polls',
        (body) => PollPage.fromJson(body as Map<String, dynamic>),
        // 첫 쪽에는 커서가 없다. 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
        query: before == null ? null : {'before': before.toUtc().toIso8601String(), 'before_id': ?beforeId},
      );

  @override
  Future<Result<Poll>> fetchPoll(String pollId) => _api.send(
        'GET',
        '/community/polls/$pollId',
        (body) => Poll.fromJson((body as Map<String, dynamic>)['poll'] as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> createPoll({
    required String question,
    required String optionA,
    required String optionB,
  }) =>
      _api.send(
        'POST',
        '/community/polls',
        (_) {},
        body: {'question': question, 'option_a_label': optionA, 'option_b_label': optionB},
      );

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) => _api.send(
        'POST',
        '/community/polls/$pollId/votes',
        (body) => VoteOutcome.fromJson(body as Map<String, dynamic>),
        body: {'choice': choice.name},
      );

  @override
  Future<Result<void>> deletePoll(String pollId) =>
      _api.send('DELETE', '/community/polls/$pollId', (_) {});
}
```

`lib/community/model/community_repository_provider.dart`:

```dart
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/http_community_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 커뮤니티 화면들이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return HttpCommunityRepository(ref.read(apiClientProvider));
});
```

`test/community/model/fake_community_repository.dart`:

```dart
import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';

Poll pollFixture({
  String id = 'p1',
  String question = '첫 데이트 더치페이',
  String optionA = defaultOptionA,
  String optionB = defaultOptionB,
  DateTime? createdAt,
  int aCount = 5,
  int bCount = 3,
  PollChoice? myChoice,
  bool isMine = false,
}) =>
    Poll(
      id: id,
      question: question,
      optionA: optionA,
      optionB: optionB,
      createdAt: createdAt ?? DateTime(2026, 9, 27, 14),
      aCount: aCount,
      bCount: bCount,
      myChoice: myChoice,
      isMine: isMine,
    );

/// 화면 · ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeCommunityRepository implements CommunityRepository {
  Result<PollPage> page = const Success(PollPage(polls: [], hasMore: false));

  /// 채워 두면 커서가 있는 요청(다음 쪽)에 이것을 돌려준다.
  Result<PollPage>? nextPage;
  Result<Poll>? poll;
  Result<void> createResult = const Success(null);
  Result<VoteOutcome>? voteResult;
  Result<void> deleteResult = const Success(null);

  /// 채워 두면 투표 응답이 이것이 끝날 때까지 멈춘다 — 누르는 도중 한 번 더 누르는 상황용.
  Completer<void>? holdVote;

  final List<({DateTime? before, String? beforeId})> pageRequests = [];
  final List<({String question, String optionA, String optionB})> created = [];
  final List<({String pollId, PollChoice choice})> votes = [];
  final List<String> fetchedPollIds = [];
  final List<String> deleted = [];

  @override
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId}) async {
    pageRequests.add((before: before, beforeId: beforeId));
    return before == null ? page : (nextPage ?? page);
  }

  @override
  Future<Result<Poll>> fetchPoll(String pollId) async {
    fetchedPollIds.add(pollId);
    return poll!;
  }

  @override
  Future<Result<void>> createPoll({
    required String question,
    required String optionA,
    required String optionB,
  }) async {
    created.add((question: question, optionA: optionA, optionB: optionB));
    return createResult;
  }

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) async {
    votes.add((pollId: pollId, choice: choice));
    await holdVote?.future;
    return voteResult!;
  }

  @override
  Future<Result<void>> deletePoll(String pollId) async {
    deleted.add(pollId);
    return deleteResult;
  }
}
```

- [ ] **Step 4: GREEN.** `flutter test test/community/model` 통과, `flutter analyze` 새 경고 0.
- [ ] **Step 5: 커밋.** `✨ feat(community): 커뮤니티 질문 모델 · 저장소 추가`, `✅ test(community): 질문 모델 · 저장소 테스트 추가`

---

### Task A2: 피드 ViewModel

**Files:**
- Create: `frontend/lib/community/viewmodel/community_feed_ui_state.dart`, `community_feed_view_model.dart`
- Test: `frontend/test/community/viewmodel/community_feed_view_model_test.dart`

**Interfaces:**
- Consumes: A1 전부
- Produces: `communityFeedViewModelProvider`(`NotifierProvider`, autoDispose 아님 — 17c · 17b 가 같은 목록을 본다),
  `CommunityFeedUiState`(isLoading · polls · hasMore · isLoadingMore · votingIds · errorMessage),
  `refresh()`, `loadMore()`, `Future<String?> vote(pollId, choice)`(토스트 문구), `Future<String?> delete(pollId)`(실패 문구),
  `pollRewardMessage`

- [ ] **Step 1: 실패 테스트.**

```dart
import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;

  Future<ProviderContainer> start() async {
    final container = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    container.read(communityFeedViewModelProvider);
    await container.read(communityFeedViewModelProvider.notifier).refresh();
    return container;
  }

  CommunityFeedViewModel viewModel(ProviderContainer c) => c.read(communityFeedViewModelProvider.notifier);

  setUp(() => repository = FakeCommunityRepository());

  test('열면 첫 쪽을 읽는다', () async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: true));
    final container = await start();
    final state = container.read(communityFeedViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.polls.single.id, 'p1');
    expect(state.hasMore, isTrue);
  });

  test('첫 쪽이 실패하면 문구를 둔다', () async {
    repository.page = const FailureResult(NetworkFailure());
    final container = await start();
    expect(container.read(communityFeedViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('더 내리면 맨 아래 글의 시각과 id 를 커서로 보내고 뒤에 붙인다(겹친 글은 거른다)', () async {
    final last = pollFixture(id: 'p2', createdAt: DateTime(2026, 9, 27, 13));
    repository
      ..page = Success(PollPage(polls: [pollFixture(), last], hasMore: true))
      ..nextPage = Success(PollPage(polls: [last, pollFixture(id: 'p3')], hasMore: false));
    final container = await start();

    await viewModel(container).loadMore();

    expect(repository.pageRequests.last, (before: last.createdAt, beforeId: 'p2'));
    expect(container.read(communityFeedViewModelProvider).polls.map((p) => p.id), ['p1', 'p2', 'p3']);
    expect(container.read(communityFeedViewModelProvider).hasMore, isFalse);
  });

  test('더 없으면 요청하지 않는다', () async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    final container = await start();
    await viewModel(container).loadMore();
    expect(repository.pageRequests, hasLength(1));
  });

  test('투표하면 그 글을 서버 값으로 바꾸고, 보상이면 토스트 문구를 준다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(aCount: 6, myChoice: PollChoice.a), rewarded: true));
    final container = await start();

    final message = await viewModel(container).vote('p1', PollChoice.a);

    expect(message, pollRewardMessage);
    expect(container.read(communityFeedViewModelProvider).polls.single.myChoice, PollChoice.a);
  });

  test('보상이 없으면 토스트도 없다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
    final container = await start();
    expect(await viewModel(container).vote('p1', PollChoice.b), isNull);
  });

  test('이미 다른 기기에서 투표했으면 문구를 주고 그 글만 다시 읽어 결과로 바꾼다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('이미 투표했어요'))
      ..poll = Success(pollFixture(myChoice: PollChoice.a));
    final container = await start();

    final message = await viewModel(container).vote('p1', PollChoice.b);

    expect(message, '이미 투표했어요');
    expect(repository.fetchedPollIds, ['p1']);
    expect(container.read(communityFeedViewModelProvider).polls.single.myChoice, PollChoice.a);
  });

  test('글이 사라졌으면(서버가 없다고 답함) 목록에서 뺀다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'))
      ..poll = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).polls, isEmpty);
  });

  test('연결 실패로는 글을 빼지 않는다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(NetworkFailure())
      ..poll = const FailureResult(NetworkFailure());
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).polls, hasLength(1));
  });

  test('투표가 끝나기 전에 다시 눌러도 요청은 한 번', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: false))
      ..holdVote = Completer<void>();
    final container = await start();

    final first = viewModel(container).vote('p1', PollChoice.a);
    await viewModel(container).vote('p1', PollChoice.b);
    repository.holdVote!.complete();
    await first;

    expect(repository.votes, hasLength(1));
  });

  test('내 글을 지우면 목록에서 빠지고, 실패하면 문구를 주고 남긴다', () async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2', isMine: true)], hasMore: false));
    final container = await start();

    expect(await viewModel(container).delete('p1'), isNull);
    repository.deleteResult = const FailureResult(NetworkFailure());
    expect(await viewModel(container).delete('p2'), '네트워크 연결을 확인해 주세요');

    expect(container.read(communityFeedViewModelProvider).polls.map((p) => p.id), ['p2']);
  });
}
```

- [ ] **Step 2: RED.** `flutter test test/community/viewmodel` → import 오류.

- [ ] **Step 3: 구현.** `community_feed_ui_state.dart`:

```dart
import 'package:campus_mate/community/model/poll.dart';

/// 15d 피드 상태. 17c 상세 · 17b 쓰기도 이 목록을 본다.
class CommunityFeedUiState {
  const CommunityFeedUiState({
    this.isLoading = true,
    this.polls = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.votingIds = const {},
    this.errorMessage,
  });

  final bool isLoading;
  final List<Poll> polls;
  final bool hasMore;
  final bool isLoadingMore;

  /// 투표 응답을 기다리는 글. 이 글의 버튼은 꺼 둔다(되돌릴 수 없는 투표가 두 번 가지 않게).
  final Set<String> votingIds;
  final String? errorMessage;

  CommunityFeedUiState copyWith({
    bool? isLoading,
    List<Poll>? polls,
    bool? hasMore,
    bool? isLoadingMore,
    Set<String>? votingIds,
    String? errorMessage,
  }) {
    return CommunityFeedUiState(
      isLoading: isLoading ?? this.isLoading,
      polls: polls ?? this.polls,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      votingIds: votingIds ?? this.votingIds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
```

`community_feed_view_model.dart`:

```dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityFeedViewModelProvider =
    NotifierProvider<CommunityFeedViewModel, CommunityFeedUiState>(CommunityFeedViewModel.new);

/// 하루 첫 투표 보상 토스트(DESIGN §8.10 — 하루 한 번 10하트). pen 에 문구가 있으면 그것으로 바꾼다.
const String pollRewardMessage = '하트 10개를 받았어요';

/// 15d 피드. **실시간 구독은 쓰지 않는다** — 당겨서 새로 고침과 투표 응답으로 충분하다.
class CommunityFeedViewModel extends Notifier<CommunityFeedUiState> {
  Future<void>? _inFlight;

  @override
  CommunityFeedUiState build() {
    Future.microtask(refresh);
    return const CommunityFeedUiState();
  }

  Future<void> refresh() => _inFlight ??= _loadFirst().whenComplete(() => _inFlight = null);

  Future<void> _loadFirst() async {
    final result = await ref.read(communityRepositoryProvider).fetchPolls();
    state = result.when(
      // 새 상태로 갈아 끼운다 — 지난 오류 문구를 지우려면 copyWith 로는 안 된다.
      onSuccess: (page) => CommunityFeedUiState(
        isLoading: false,
        polls: page.polls,
        hasMore: page.hasMore,
        votingIds: state.votingIds,
      ),
      onFailure: (failure) => state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 목록 끝에 가까워지면 화면이 부른다. 겹쳐 불려도 한 번만 간다. 실패하면 조용히 멈추고 다음 스크롤에 다시 간다.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.polls.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    final last = state.polls.last;
    final result = await ref
        .read(communityRepositoryProvider)
        .fetchPolls(before: last.createdAt, beforeId: last.id);
    state = result.when(
      onSuccess: (page) {
        // 새로 고침과 겹치면 같은 글이 두 번 올 수 있다 — id 로 거른다.
        final seen = state.polls.map((poll) => poll.id).toSet();
        return state.copyWith(
          isLoadingMore: false,
          hasMore: page.hasMore,
          polls: [...state.polls, ...page.polls.where((poll) => !seen.contains(poll.id))],
        );
      },
      onFailure: (_) => state.copyWith(isLoadingMore: false),
    );
  }

  /// 투표. 화면이 띄울 토스트 문구를 돌려준다(없으면 null).
  Future<String?> vote(String pollId, PollChoice choice) async {
    if (state.votingIds.contains(pollId)) return null;
    state = state.copyWith(votingIds: {...state.votingIds, pollId});
    final result = await ref.read(communityRepositoryProvider).vote(pollId, choice);
    final message = await result.when<Future<String?>>(
      onSuccess: (outcome) async {
        _replace(outcome.poll);
        return outcome.rewarded ? pollRewardMessage : null;
      },
      onFailure: (failure) async {
        // 다른 기기에서 이미 투표했거나(409) 글이 사라졌을 수 있다(404) — 그 글만 다시 읽어 서버에 맞춘다.
        await _reloadOne(pollId);
        return failure.toDisplayMessage();
      },
    );
    state = state.copyWith(votingIds: {...state.votingIds}..remove(pollId));
    return message;
  }

  /// 내 글 지우기. 성공하면 null, 실패하면 문구.
  Future<String?> delete(String pollId) async {
    final result = await ref.read(communityRepositoryProvider).deletePoll(pollId);
    return result.when(
      onSuccess: (_) {
        _remove(pollId);
        return null;
      },
      onFailure: (failure) => failure.toDisplayMessage(),
    );
  }

  Future<void> _reloadOne(String pollId) async {
    final result = await ref.read(communityRepositoryProvider).fetchPoll(pollId);
    result.when(
      onSuccess: _replace,
      onFailure: (failure) {
        // 서버가 "없다" 고 답한 것만 뺀다. 연결 실패로 빼면 멀쩡한 글이 사라진다.
        if (failure is ServerRejectedFailure) _remove(pollId);
      },
    );
  }

  void _replace(Poll poll) =>
      state = state.copyWith(polls: [for (final p in state.polls) p.id == poll.id ? poll : p]);

  void _remove(String pollId) =>
      state = state.copyWith(polls: state.polls.where((poll) => poll.id != pollId).toList());
}
```

- [ ] **Step 4: GREEN.** `flutter test test/community/viewmodel` 통과.
- [ ] **Step 5: 커밋.** `✨ feat(community): 커뮤니티 피드 상태 관리 추가`, `✅ test(community): 피드 상태 관리 테스트 추가`

---

### Task A3: 15d 피드 화면 · 카드 · 도넛 · 라우트

**Files:**
- Create: `frontend/lib/community/view/community_feed_screen.dart`, `poll_card.dart`, `poll_donut.dart`, `poll_time.dart`, `poll_toast.dart`
- Modify(공유 파일, 결정 D3 허락): `frontend/lib/core/router/app_routes.dart`, `frontend/lib/core/router/app_router.dart`
- Modify(공유 파일, 허락: 통합대장 09-27): `frontend/lib/common/widgets/app_toast.dart`(`leading` 선택으로만) — `poll_toast.dart` 가 `leading: null` 을 넘기므로 **이 파일을 먼저 고쳐야 컴파일된다**
- Test: `frontend/test/common/widgets/app_toast_test.dart`(새 파일, 1개)
- Test: `frontend/test/community/view/poll_time_test.dart`, `community_feed_screen_test.dart`

**Interfaces:**
- Consumes: A1 · A2, `AppBottomNav(current: AppTab.community)`, `AppButton`, `AppToast`
- Produces: `CommunityFeedScreen`, `PollCard(poll, now, isVoting, onVote, onOpen?, onMore?)`, `PollDonut(poll)`,
  `relativeTimeLabel(at, now)`, `communityNowProvider`, `showPollToast(context, message)`,
  `AppRoutes.communityNew = '/community/new'`, `AppRoutes.communityPoll = '/community/polls'`(`/community/polls/:pollId`)

- [ ] **Step 1: 실패 테스트.** `poll_time_test.dart`:

```dart
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 27, 14);

  test('상대 시간', () {
    expect(relativeTimeLabel(now.subtract(const Duration(seconds: 30)), now), '방금 전');
    expect(relativeTimeLabel(now.subtract(const Duration(minutes: 5)), now), '5분 전');
    expect(relativeTimeLabel(now.subtract(const Duration(hours: 3)), now), '3시간 전');
    expect(relativeTimeLabel(now.subtract(const Duration(days: 2)), now), '2일 전');
    expect(relativeTimeLabel(DateTime(2026, 9, 1), now), '9월 1일');
  });

  test('기기 시계가 서버보다 느려 미래 시각이 와도 방금 전', () {
    expect(relativeTimeLabel(now.add(const Duration(minutes: 1)), now), '방금 전');
  });
}
```

  `community_feed_screen_test.dart` — `pump` 는 `frontend/test/matching/view/conversations_screen_test.dart` 처럼 하단 내비 뱃지 때문에
  `chatRepositoryProvider` · `cardRepositoryProvider` 를 가짜로, `communityRepositoryProvider` 는 `FakeCommunityRepository`,
  `communityNowProvider` 는 `() => DateTime(2026, 9, 27, 14)` 로 덮고, `GoRouter` 에 `/community`(피드) ·
  `/community/new`(Text('쓰기')) · `/community/polls/:pollId`(Text('상세 ${id}')) 세 경로를 둔 뒤 `pumpAndSettle`.

```dart
  testWidgets('글이 없으면 빈 상태(n2tqZ)', (tester) async {
    await pump(tester);
    expect(find.text('아직 질문이 없어요'), findsOneWidget);
    expect(find.text('궁금한 걸 익명으로 물어보고\n캠퍼스 사람들의 생각을 들어보세요.'), findsOneWidget);
    await tester.tap(find.text('질문 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('쓰기'), findsOneWidget);
  });

  testWidgets('불러오기 실패는 빈 상태가 아니라 실패 문구와 다시 시도', (tester) async {
    repository.page = const FailureResult(ServerUnavailableFailure());
    await pump(tester);
    expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
    expect(find.text('아직 질문이 없어요'), findsNothing);

    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsOneWidget);
  });

  testWidgets('투표 전: O·X 버튼과 그 아래 결과 한 줄(사용자 결정 4-1)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(aCount: 5, bCount: 3)], hasMore: false));
    await pump(tester);
    expect(find.bySemanticsLabel('찬성'), findsOneWidget);
    expect(find.bySemanticsLabel('반대'), findsOneWidget);
    expect(find.text('찬성 63% · 반대 37% · 8명 참여'), findsOneWidget);
  });

  testWidgets('커스텀 라벨이면 글자 버튼', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(optionA: '짜장', optionB: '짬뽕')], hasMore: false));
    await pump(tester);
    expect(find.widgetWithText(FilledButton, '짜장'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '짬뽕'), findsOneWidget);
  });

  testWidgets('투표 후: 도넛 · 비율 줄 · 참여자 수, 버튼은 없다. 가운데 % 는 우세한 쪽', (tester) async {
    // A 3 · B 5 → A = round(37.5) = 38, B = 100 − 38 = 62. 호는 A(38%), 가운데는 우세한 B 의 62%(대장 예외).
    repository.page = Success(PollPage(polls: [pollFixture(aCount: 3, bCount: 5, myChoice: PollChoice.a)], hasMore: false));
    await pump(tester);
    expect(find.byType(PollDonut), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('찬성 38% · 반대 62%'), findsOneWidget);
    expect(find.text('8명 참여'), findsOneWidget);
    expect(find.bySemanticsLabel('찬성'), findsNothing);
  });

  testWidgets('불러오기 실패와 빈 목록을 가른다 — 두 번째 쪽 실패는 목록을 지우지 않는다', (tester) async {
    repository
      ..page = Success(PollPage(polls: [for (var i = 0; i < 20; i++) pollFixture(id: 'p$i')], hasMore: true))
      ..nextPage = const FailureResult(NetworkFailure());
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsWidgets);
    expect(find.text('다시 시도'), findsNothing);
  });
```

```dart
  testWidgets('O 를 누르면 a 로 투표하고 보상이면 토스트(15d-3)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('찬성'));
    await tester.pump();
    expect(repository.votes.single, (pollId: 'p1', choice: PollChoice.a));
    expect(find.text(pollRewardMessage), findsOneWidget);
    // 15d-3 은 글자만 — 재화 하트를 Lucide 로 그리지 않는다.
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });

  testWidgets('+ 는 17b, "자세히 보기" 는 17c 로 간다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('상세 p1'), findsOneWidget);
  });

  testWidgets('"자세히 보기" 누르는 영역은 48 이다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(ink).height, greaterThanOrEqualTo(48));
  });

  testWidgets('"자세히 보기" 눌림 효과는 카드 안에 그려진다(COMMON §4-2)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(find.byType(PollCard)));
  });

  testWidgets('폰 폭(360)에서 글자 2배 · 80자 질문 · 6자 라벨에도 넘치거나 잘리지 않는다', (tester) async {
    // 기본 800 폭에서는 버튼 한 칸이 넓어 6자 라벨이 한 줄로 들어간다 — 실기기 폭 144 로 줄여야 잡힌다.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repository.page = Success(PollPage(polls: [
      pollFixture(question: '가' * 80, optionA: '가나다라마바', optionB: '바마라다나가'),
      pollFixture(id: 'p2', optionA: '가나다라마바', optionB: '바마라다나가', myChoice: PollChoice.b),
    ], hasMore: false));
    await pump(tester);
    expect(tester.takeException(), isNull);
    // 버튼 높이 56 은 고정이라 두 줄로 꺾이면 예외 없이 조용히 잘린다 — 그려진 글자 폭이 버튼 안인지 본다.
    final button = find.ancestor(of: find.text('가나다라마바').first, matching: find.byType(FilledButton)).first;
    expect(tester.getRect(find.text('가나다라마바').first).width, lessThanOrEqualTo(tester.getRect(button).width));
  });

  testWidgets('끝까지 내리면 다음 쪽을 부른다', (tester) async {
    repository
      ..page = Success(PollPage(polls: [for (var i = 0; i < 20; i++) pollFixture(id: 'p$i')], hasMore: true))
      ..nextPage = const Success(PollPage(polls: [], hasMore: false));
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(repository.pageRequests.length, greaterThanOrEqualTo(2));
    expect(repository.pageRequests.last.beforeId, 'p19');
  });
```

- [ ] **Step 2: RED.** `flutter test test/community/view` → import 오류.

- [ ] **Step 3: 구현.** `poll_time.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카드의 "지금" — 테스트가 고정한다(chatRoomNowProvider 와 같은 이음매).
final communityNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 카드 머리의 작성 시각(DESIGN §8.11 상대 시간). 한 주가 넘으면 날짜로 바꾼다 —
/// "43일 전" 은 셈을 시킨다. 기기 시계가 느려 미래 시각이 와도 "방금 전".
String relativeTimeLabel(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return '방금 전';
  if (gap.inHours < 1) return '${gap.inMinutes}분 전';
  if (gap.inDays < 1) return '${gap.inHours}시간 전';
  if (gap.inDays < 7) return '${gap.inDays}일 전';
  return '${at.month}월 ${at.day}일';
}
```

`poll_toast.dart`:

```dart
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// 15d · 17c 가 같이 쓰는 토스트(pen Toast `I8UOWm`). 뜨고 사라지는 시간은 SnackBar 에 맡긴다 — 두 화면에
/// 타이머를 따로 두지 않는다. 보상(15d-3 `NDZnK`)은 글자만 — 재화 하트는 Lucide 로 그리지 않는다(DESIGN §8.10).
void showPollToast(BuildContext context, String message) {
  final isReward = message == pollRewardMessage;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Center(
        child: AppToast(
          leading: isReward ? null : const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: message,
        ),
      ),
    ));
}
```

`poll_donut.dart`:

```dart
import 'dart:math';

import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 투표 뒤 결과 도넛(pen `raSK1` 96×96). 호는 12시에서 시계 방향으로 **선택지 A 몫**(pen `D18xFi`),
/// 가운데 % 는 **우세한 쪽**이다(DESIGN §8.11 — 대장 예외). 끝은 평평하고 두 색 사이 틈이 없다.
/// CircularProgressIndicator 는 쓰지 않는다 — 버전마다 트랙 틈 · 둥근 끝 기본값이 바뀌어 pen 과 어긋난다.
class PollDonut extends StatelessWidget {
  const PollDonut({required this.poll, super.key});

  final Poll poll;

  static const double size = 96;

  /// pen 은 두께가 아니라 안쪽 반지름 비율 0.62 로 그렸다(`wnXtI`) → 두께 = 48 × 0.38 ≈ 18.2.
  static const double stroke = size / 2 * (1 - 0.62);

  @override
  Widget build(BuildContext context) {
    final lead = max(poll.aPercent, poll.bPercent);
    return Semantics(
      label: '${poll.optionA} ${poll.aPercent}%, ${poll.optionB} ${poll.bPercent}%',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(aShare: poll.total == 0 ? 0 : poll.aCount / poll.total),
          child: Padding(
            padding: const EdgeInsets.all(stroke),
            // 글자를 키워도 고리 밖으로 나가지 않게 줄여서 맞춘다. pen `zJP3C` 20/700 #222.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$lead%',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.aShare});

  final double aShare;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(PollDonut.stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = PollDonut.stroke;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = AppColors.surfaceStrong);
    canvas.drawArc(rect, -pi / 2, 2 * pi * aShare, false, paint..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => oldDelegate.aShare != aShare;
}
```

`poll_card.dart`:

```dart
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 찬성 O 버튼 파랑(pen `VhiAe`, DESIGN §8.11). 토큰표 밖 값이다. 색 뜻 결정 대기(계획서 "결정 대기").
const Color _agreeBlue = Color(0xFF2D96DE);

/// 카드 그림자(pen `RpRBi` #00000014 (0,1) blur 8). AppElevation 토큰과 값이 달라 여기 둔다.
const List<BoxShadow> _cardShadow = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 8)];

/// `poll-card`(pen 마스터 `RpRBi`). 15d 목록과 17c 상세가 같이 쓴다.
class PollCard extends StatelessWidget {
  const PollCard({
    required this.poll,
    required this.now,
    required this.isVoting,
    required this.onVote,
    this.onOpen,
    this.onMore,
    super.key,
  });

  final Poll poll;
  final DateTime now;

  /// 응답을 기다리는 중이면 버튼을 끈다 — 되돌릴 수 없는 투표가 두 번 가지 않게.
  final bool isVoting;
  final void Function(PollChoice choice) onVote;

  /// 17c 로 가는 줄. 상세 화면 안에서는 null 이라 줄이 없고 질문도 전부 보인다.
  final VoidCallback? onOpen;

  /// 내 글에만 준다(… 메뉴, 사용자 결정 2).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final inList = onOpen != null;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    // 색 · 그림자는 바깥 DecoratedBox, 눌림 효과는 안쪽 투명 Material 이 받는다 — InkWell 의 가장 가까운
    // Material 이 카드 자신이라 스크롤해도 효과가 카드와 같이 움직인다(COMMON §4-2).
    return DecoratedBox(
      decoration: ShapeDecoration(color: AppColors.canvas, shape: shape, shadows: _cardShadow),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(poll: poll, now: now, onMore: onMore),
              const SizedBox(height: AppSpacing.sm),
              Text(
                poll.question,
                // pen `b5raym` 16/700 lh1.35. 목록에서는 2줄(DESIGN §8.11).
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink),
                maxLines: inList ? 2 : null,
                overflow: inList ? TextOverflow.ellipsis : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (poll.myChoice == null)
                _BeforeVote(poll: poll, enabled: !isVoting, onVote: onVote)
              else
                _Result(poll: poll),
              if (inList) ...[
                const SizedBox(height: AppSpacing.sm),
                _OpenRow(onOpen: onOpen!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.poll, required this.now, required this.onMore});

  final Poll poll;
  final DateTime now;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // pen `LHkpo` · `MpYr6`: #F2F2F2 pill, [3,10], 11/600 #3F3F3F.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text('익명', style: AppTypography.badge.copyWith(color: AppColors.body)),
        ),
        const SizedBox(width: AppSpacing.xs),
        // pen `G85OOq` 은 11/500 — 11px 은 뱃지만이라 12 로 올린다(대장 예외).
        Expanded(
          child: Text(
            relativeTimeLabel(poll.createdAt, now),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
          ),
        ),
        // 신고 flag(`z7tzx`)는 안전 PR 6 뒤에 붙인다. "…" 는 pen `mc9mW`(터치 48 · ellipsis 20 muted) — 켜지면 머리줄이 48.
        if (onMore != null)
          IconButton(
            tooltip: '더보기',
            icon: const Icon(AppIcons.ellipsis, size: 20, color: AppColors.muted),
            onPressed: onMore,
          ),
      ],
    );
  }
}

class _BeforeVote extends StatelessWidget {
  const _BeforeVote({required this.poll, required this.enabled, required this.onVote});

  final Poll poll;
  final bool enabled;
  final void Function(PollChoice choice) onVote;

  @override
  Widget build(BuildContext context) {
    VoidCallback? tap(PollChoice choice) => enabled ? () => onVote(choice) : null;
    final buttons = poll.usesDefaultLabels
        ? [
            _IconVote(icon: AppIcons.circle, label: poll.optionA, color: _agreeBlue, onPressed: tap(PollChoice.a)),
            _IconVote(icon: AppIcons.x, label: poll.optionB, color: AppColors.primary, onPressed: tap(PollChoice.b)),
          ]
        : [
            _TextVote(label: poll.optionA, onPressed: tap(PollChoice.a)),
            _TextVote(label: poll.optionB, onPressed: tap(PollChoice.b)),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: buttons[1]),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 투표 전에도 결과를 보인다(사용자 결정 4 · 4-1). pen `R2ZIGG` 12/400 lh1.4 muted 가운데, 버튼 줄 아래 12.
        Text(
          poll.total == 0
              // 아무도 안 눌렀으면 "0%" 두 개 대신 참여자 수만 — 0 · 0 은 결과처럼 읽힌다.
              ? '0명 참여'
              : '${poll.optionA} ${poll.aPercent}% · ${poll.optionB} ${poll.bPercent}% · ${poll.total}명 참여',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 글자 없는 O · X 버튼(pen `VhiAe` · `mUsfX` 72 높이, radius 8, 아이콘 34 흰색).
/// 화면 읽기는 아이콘의 semanticLabel("찬성" · "반대")로 읽는다.
class _IconVote extends StatelessWidget {
  const _IconVote({required this.icon, required this.label, required this.color, required this.onPressed});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size.fromHeight(72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      child: Icon(icon, size: 34, semanticLabel: label),
    );
  }
}

/// 직접 적은 선택지 버튼(pen `ojrC5` · `ALBe4` · `OJ4rJ`, 15d-4): button-secondary 값(#E5E5E5 · #222 18/700 · 56 · radius 16).
/// AppButton 을 쓰지 않는 이유 — 높이가 56 으로 고정이라 글자를 키우면 라벨이 두 줄로 꺾여 조용히 잘린다.
/// 여기서는 한 줄로 두고 칸보다 길면 줄여서 맞춘다(한 칸 폭 144, 라벨 6자).
class _TextVote extends StatelessWidget {
  const _TextVote({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryDisabled,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.primaryDisabled,
        disabledForegroundColor: AppColors.disabled,
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: AppTypography.label)),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.poll});

  final Poll poll;

  @override
  Widget build(BuildContext context) {
    // pen `omkNb`: 세로 · 가운데 · 간격 8.
    return Column(
      children: [
        PollDonut(poll: poll),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${poll.optionA} ${poll.aPercent}% · ${poll.optionB} ${poll.bPercent}%',
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(color: AppColors.body), // pen `H1kGWf` 14/600
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${poll.total}명 참여',
          textAlign: TextAlign.center,
          // pen `rEJhW` 11/500 → 12/500(대장 예외).
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted);
    // pen `i5ugzn` 은 줄 높이 17 — 누르는 영역만 48 로 키운다(대장).
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('자세히 보기', style: style),
            const SizedBox(width: 2),
            const Icon(AppIcons.chevronRight, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
```

`community_feed_screen.dart`:

```dart
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15d 커뮤니티 피드(pen `XhEyI`). 전체 학교 한 목록(사용자 결정 1), 최신순, 무한 스크롤.
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // 바닥에 닿기 전에 부른다 — 닿은 뒤 부르면 빈칸이 잠깐 보인다.
      if (_scroll.position.extentAfter < 400) {
        ref.read(communityFeedViewModelProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _vote(String pollId, PollChoice choice) async {
    final message = await ref.read(communityFeedViewModelProvider.notifier).vote(pollId, choice);
    if (message != null && mounted) showPollToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityFeedViewModelProvider);
    return Scaffold(
      // pen `Iblb3`: 56, 왼쪽 20 · 오른쪽 8, 제목 20/700.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('커뮤니티', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: '질문 올리기',
            onPressed: () => context.push(AppRoutes.communityNew),
            // pen `uhk6J` 터치 48 · `I7U2Jp` 원 32 #F7F7F7 · `zuIJJ` plus 18.
            icon: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
              child: const Icon(AppIcons.plus, size: 18, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _body(state),
      bottomNavigationBar: const AppBottomNav(current: AppTab.community),
    );
  }

  Widget _body(CommunityFeedUiState state) {
    final viewModel = ref.read(communityFeedViewModelProvider.notifier);
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    if (state.polls.isEmpty && state.errorMessage != null) {
      return _LoadError(message: state.errorMessage!, onRetry: viewModel.refresh);
    }
    if (state.polls.isEmpty) return const _EmptyFeed();
    final now = ref.read(communityNowProvider)();
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView.separated(
        controller: _scroll,
        // pen `FXyNI`: 위아래 8 · 좌우 16, 카드 사이 12.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        itemCount: state.polls.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == state.polls.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final poll = state.polls[index];
          return PollCard(
            poll: poll,
            now: now,
            isVoting: state.votingIds.contains(poll.id),
            onVote: (choice) => _vote(poll.id, choice),
            onOpen: () => context.push('${AppRoutes.communityPoll}/${poll.id}'),
          );
        },
      ),
    );
  }
}

/// 빈 상태(pen `n2tqZ` · Empty 마스터 `TVc8b`).
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/mascot-male.png', width: 120, height: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '아직 질문이 없어요',
              textAlign: TextAlign.center,
              style: AppTypography.subtitle.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '궁금한 걸 익명으로 물어보고\n캠퍼스 사람들의 생각을 들어보세요.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xl),
            // pen 은 연분홍 채움 — button-secondary 로 바꾼다(대장 예외). 폭은 내용에 맞춘다(pen 128).
            IntrinsicWidth(
              child: AppButton(
                label: '질문 올리기',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.push(AppRoutes.communityNew),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 첫 쪽을 못 불러왔을 때. 문구는 `Failure` 종류별 문구 그대로(502/503 → "잠시 뒤 다시 시도해 주세요" 등),
/// 모양은 `school_info_screen` 의 `_SchoolNameError` 와 같다. 실패인데 "질문이 없어요" 를 보이면 거짓말이다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.body)),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
```

  공유 파일 — `common/widgets/app_toast.dart`(허락: 통합대장 09-27, 이 범위만): 15d-3 보상 토스트가
  글자만이라 `leading` 을 선택으로 바꾼다. 기존 호출 두 곳(`photos_screen` · `avatar_source_screen`)은 그대로 넘기므로 바뀌지 않는다.

```dart
  const AppToast({required this.label, this.leading, super.key});

  /// 16×16 자리에 들어가는 그림. 없으면 글자만 — 15d-3 투표 보상(재화 하트는 Lucide 로 그리지 않는다).
  final Widget? leading;
```

```dart
          children: [
            if (leading != null) ...[
              SizedBox(width: 16, height: 16, child: leading),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.onInk)),
          ],
```

  `test/common/widgets/app_toast_test.dart`(새 파일 — 이 Task 의 Step 1 에서 먼저 써서 RED 를 본다):

```dart
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leading 이 없으면 글자만 그리고 앞 간격도 없다(15d-3)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: AppToast(label: '하트 10개를 받았어요'))));

    // 안쪽 여백 16 만 — 16 칸 그림 자리 + 간격 8 이 남아 있으면 40 이 된다.
    final toast = tester.getRect(find.byType(AppToast));
    final label = tester.getRect(find.text('하트 10개를 받았어요'));
    expect(label.left - toast.left, AppSpacing.md);
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });
}
```

  공유 파일(결정 D3 허락) — `app_routes.dart` 의 `community` 아래:

```dart
  static const String communityNew = '/community/new';
  static const String communityPoll = '/community/polls'; // `/community/polls/:pollId`
```

  `app_router.dart` `_slice4Routes()` 의 `/community` 줄을 바꾸고 둘을 더한다(17b · 17c 화면은 A4 · A5 에서 만든다 —
  **이 두 줄은 A5 커밋에 넣는다.** A3 커밋에서는 `/community` 한 줄만 바꾼다):

```dart
      GoRoute(path: AppRoutes.community, builder: (context, state) => const CommunityFeedScreen()),
      // ↓ A5 에서
      GoRoute(path: AppRoutes.communityNew, builder: (context, state) => const PollComposerScreen()),
      GoRoute(
        path: '${AppRoutes.communityPoll}/:pollId',
        builder: (context, state) => PollDetailScreen(pollId: state.pathParameters['pollId']!),
      ),
```

  `ComingSoonScreen` 주석의 "(커뮤니티·나)" 는 나 탭이 15 를 끝내면 같이 정리한다 — 이 PR 에서는 건드리지 않는다
  (`placeholder_screens_test` 가 `ComingSoonScreen(tab: AppTab.community)` 를 직접 만들어 여전히 통과한다).

- [ ] **Step 4: GREEN.** `flutter test test/community` 통과, 이어서 `flutter test` 전체(한 건이 가끔 떨어지면 그 파일만
  단독으로 다시 돌려 구분 — COMMON §4-1), `flutter analyze` 새 경고 0.
- [ ] **Step 5: pen 검토 반영.** 사용자 pen 검토 뒤 값표가 바뀌었으면(특히 결정 대기 — 찬성 색 · 도넛 호 색) 그 값으로
  맞추고 `// pen <id>` 주석을 단다. 대조표에 없는 값이 나오면 멈추고 대장에게 묻는다.
- [ ] **Step 6: 커밋.** `✨ feat(community): 커뮤니티 피드 화면 추가`, `🔧 chore(router): 커뮤니티 탭을 피드 화면으로 연결`(공유
  파일 두 개), `✅ test(community): 피드 화면 테스트 추가`

---

### Task A4: 17b 질문 작성

**Files:**
- Create: `frontend/lib/community/view/poll_composer_screen.dart`
- Test: `frontend/test/community/view/poll_composer_screen_test.dart`

**Interfaces:**
- Consumes: `communityRepositoryProvider.createPoll`, `communityFeedViewModelProvider.notifier.refresh`
- Produces: `PollComposerScreen`(키 `questionKey` · `optionAKey` · `optionBKey`), `pollDailyLimitMessage`

- [ ] **Step 1: 실패 테스트.** 피드 테스트와 같은 준비에 `GoRouter(initialLocation: '/community')` 로 띄운 뒤
  `router.push('/community/new')`(피드 자리는 Text('피드')):

```dart
  ElevatedButton submit(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '익명으로 올리기'));

  testWidgets('질문이 비었거나 두 라벨이 같으면 올리기가 꺼져 있다', (tester) async {
    await pump(tester);
    expect(submit(tester).onPressed, isNull);

    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장 vs 짬뽕');
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '찬성');
    await tester.pump();
    expect(submit(tester).onPressed, isNull);
  });

  testWidgets('카운터는 상자 안에서 "n / 80"', (tester) async {
    await pump(tester);
    expect(find.text('0 / 80'), findsOneWidget);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장');
    await tester.pump();
    expect(find.text('2 / 80'), findsOneWidget);
  });

  testWidgets('앞뒤 공백을 깎아 보내고 피드로 돌아가 새로 읽는다', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '  짜장 vs 짬뽕  ');
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), ' 짜장 ');
    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '짬뽕');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();

    expect(repository.created.single, (question: '짜장 vs 짬뽕', optionA: '짜장', optionB: '짬뽕'));
    expect(find.text('피드'), findsOneWidget);
    expect(repository.pageRequests, isNotEmpty);
  });

  testWidgets('하루 10개를 넘기면(429) 한도 문구를 보이고 화면에 남는다', (tester) async {
    repository.createResult = const FailureResult(RateLimitedFailure());
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '열한 번째');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();

    expect(find.text(pollDailyLimitMessage), findsOneWidget);
    expect(find.text('피드'), findsNothing);
  });

  testWidgets('입력칸은 80자 · 6자에서 더 받지 않는다', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '가' * 90);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '가' * 15);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.questionKey)).controller!.text.length, 80);
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text.length, 6);
  });

  testWidgets('글자 수는 서버와 같이 코드 포인트로 센다(이모지 👍🏻 = 2)', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '👍🏻' * 4);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text.runes.length, 6);
  });
```

- [ ] **Step 2: RED.** `flutter test test/community/view/poll_composer_screen_test.dart` → import 오류.

- [ ] **Step 3: 구현.** `poll_composer_screen.dart`:

```dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 하루 10개를 넘겼을 때(서버 `POLL_DAILY_LIMIT` 과 같은 문구, 사용자 결정 3).
/// 429 는 공용 분류가 "너무 많이 시도했어요" 로 바꾸므로 이 화면이 문구를 바꿔 낀다.
const String pollDailyLimitMessage = '오늘은 질문을 더 올릴 수 없어요';

/// 글자 수는 서버(`len`) · DB(`char_length`)와 같은 **유니코드 코드 포인트** 로 센다.
/// Flutter `maxLength` 는 글자 모양(그래핌) 단위라 이모지(👍🏻 = 2)가 섞이면 앱은 통과시키고 서버가 422 를 낸다.
TextInputFormatter _maxCodePoints(int max) => TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.runes.length <= max) return newValue;
      final text = String.fromCharCodes(newValue.text.runes.take(max));
      return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    });

/// 17b `poll-composer`(pen `p4wnJ`). 입력 상태가 이 화면 안에서 끝나 ViewModel 을 두지 않는다.
class PollComposerScreen extends ConsumerStatefulWidget {
  const PollComposerScreen({super.key});

  static const questionKey = Key('poll-question');
  static const optionAKey = Key('poll-option-a');
  static const optionBKey = Key('poll-option-b');

  @override
  ConsumerState<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends ConsumerState<PollComposerScreen> {
  final _question = TextEditingController();
  final _optionA = TextEditingController(text: defaultOptionA);
  final _optionB = TextEditingController(text: defaultOptionB);
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _optionA.dispose();
    _optionB.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final a = _optionA.text.trim();
    final b = _optionB.text.trim();
    return !_isSubmitting && _question.text.trim().isNotEmpty && a.isNotEmpty && b.isNotEmpty && a != b;
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ref.read(communityRepositoryProvider).createPoll(
          question: _question.text.trim(),
          optionA: _optionA.text.trim(),
          optionB: _optionB.text.trim(),
        );
    if (!mounted) return;
    result.when(
      onSuccess: (_) {
        ref.read(communityFeedViewModelProvider.notifier).refresh();
        context.pop();
      },
      onFailure: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure is RateLimitedFailure ? pollDailyLimitMessage : failure.toDisplayMessage();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('익명으로 질문하기', style: AppTypography.navTitle)),
      body: SafeArea(
        // pen `QhlmU`: 세로 간격 20, 안쪽 16. 버튼도 본문 흐름 안에 있다(화면 아래 고정 아님).
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _AnonymityNotice(),
            const SizedBox(height: 20),
            Text('질문 내용', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
            const SizedBox(height: AppSpacing.xs),
            _QuestionBox(controller: _question, onChanged: () => setState(() {})),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _optionField('선택지 A', PollComposerScreen.optionAKey, _optionA)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _optionField('선택지 B', PollComposerScreen.optionBKey, _optionB)),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.xs),
            ],
            AppButton(label: '익명으로 올리기', onPressed: _canSubmit ? _submit : null),
          ],
        ),
      ),
    );
  }

  /// pen `mYKYP`: 라벨 12/600 · 간격 6 · 상자 44 #F7F7F7 radius 8 [0,14] 테두리 없음 · 값 14/600.
  Widget _optionField(String label, Key key, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.body)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: TextField(
            key: key,
            controller: controller,
            inputFormatters: [_maxCodePoints(pollOptionMaxLength)],
            style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
            decoration: const InputDecoration.collapsed(hintText: ''),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}

/// pen `XC6KK`: #F7F7F7, radius 10(토큰 밖), 안쪽 12, lock 16 + 12/600 muted.
class _AnonymityNotice extends StatelessWidget {
  const _AnonymityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          const Icon(AppIcons.lock, size: 16, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '작성자 정보는 절대 공개되지 않아요',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Textarea 마스터 `Zhq9p`: #F7F7F7 · radius 8 · 테두리 #767676 1 · 안쪽 12 · 간격 4 · 최소 104,
/// 카운터 "0 / 80" 은 상자 안 아래 왼쪽. 라벨 · 자리글 문구는 17b `p4wnJ` 값이다(대장 지시로 두 값을 합친다).
class _QuestionBox extends StatelessWidget {
  const _QuestionBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final counterStyle = AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted);
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: PollComposerScreen.questionKey,
            controller: controller,
            inputFormatters: [_maxCodePoints(pollQuestionMaxLength)],
            minLines: 2,
            maxLines: null,
            style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.ink),
            decoration: InputDecoration.collapsed(
              hintText: '예) 깻잎을 먼저 집으면 안 되는 거 아니야?',
              hintStyle: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('${controller.text.runes.length} / $pollQuestionMaxLength', style: counterStyle),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: GREEN.** `flutter test test/community` 통과.
- [ ] **Step 5: pen 검토 반영.** 10절에 17b 변경은 없다. 사용자 검토에서 17b 가 Zhq9p 로 바뀌면 라벨~상자 간격을 그 값으로 맞춘다.
- [ ] **Step 6: 커밋.** `✨ feat(community): 질문 작성 화면 추가`, `✅ test(community): 질문 작성 화면 테스트 추가`

---

### Task A5: 17c 투표 상세 · 내 글 삭제 · 라우트 마무리

**Files:**
- Create: `frontend/lib/community/view/poll_detail_screen.dart`, `frontend/lib/community/view/poll_sheets.dart`
- Modify: `frontend/lib/community/view/community_feed_screen.dart`(`onMore` 한 줄), `app_router.dart`(A3 에서 남긴 라우트 두 개)
- Test: `frontend/test/community/view/poll_detail_screen_test.dart`, `community_feed_screen_test.dart`(삭제 · … 세 개 이어 쓰기)

**Interfaces:**
- Consumes: A2 · A3(`PollCard` · `showPollToast` · `communityNowProvider`)
- Produces: `PollDetailScreen(pollId)`, `showPollMenu(context, ref, pollId)`

- [ ] **Step 1: 실패 테스트.** `poll_detail_screen_test.dart`(피드 목록을 먼저 채운 `ProviderContainer` 로 `PollDetailScreen` 을 띄운다):

```dart
  testWidgets('17c: 제목 "투표 상세", 피드 카드와 같은 크기, 질문 전문, 댓글 안내', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(question: '가' * 80, myChoice: PollChoice.a)], hasMore: false));
    await pumpDetail(tester, 'p1');
    expect(find.text('투표 상세'), findsOneWidget);
    expect(tester.getSize(find.byType(PollDonut)), const Size(96, 96));
    expect(find.text('자세히 보기'), findsNothing);
    expect(tester.widget<Text>(find.text('가' * 80)).maxLines, isNull);
    expect(find.text('댓글 기능은 아직 준비 중이에요'), findsOneWidget);
  });

  testWidgets('상세에서도 투표 전이면 투표할 수 있다(사용자 결정 4)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
    await pumpDetail(tester, 'p1');
    await tester.tap(find.bySemanticsLabel('반대'));
    await tester.pumpAndSettle();
    expect(repository.votes.single.choice, PollChoice.b);
    expect(find.byType(PollDonut), findsOneWidget);
  });

  testWidgets('목록에서 빠진 글이면 찾을 수 없다고 말한다', (tester) async {
    await pumpDetail(tester, 'gone');
    expect(find.text('질문을 찾을 수 없어요'), findsOneWidget);
  });
```

  `community_feed_screen_test.dart` 에 이어서:

```dart
  testWidgets('내 글에만 … 가 있다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2')], hasMore: false));
    await pump(tester);
    expect(find.byTooltip('더보기'), findsOneWidget);
  });

  testWidgets('… → 삭제하기 → 확인 창(15d-2) 삭제하기 를 누르면 지우고 목록에서 뺀다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(find.text('이 질문을 삭제할까요?'), findsOneWidget);
    expect(find.text('질문과 받은 투표가 모두 사라지고 되돌릴 수 없어요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['p1']);
    expect(find.byType(PollCard), findsNothing);
  });

  testWidgets('확인 창에서 취소하면 지우지 않는다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);
    expect(find.byType(PollCard), findsOneWidget);
  });
```

- [ ] **Step 2: RED.** `flutter test test/community/view/poll_detail_screen_test.dart test/community/view/community_feed_screen_test.dart`
  → 상세는 import 오류, 피드의 새 세 테스트는 `더보기` 를 못 찾아 실패.

- [ ] **Step 3: 구현.** `poll_sheets.dart`:

```dart
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 두 시트는 채팅탭 PR 5 의 `ChatRoomMenuSheet`(Menu · Chat `RzZT8`) · 차단 확인과 같은 마스터다(결정 D4).
// PR 5 가 먼저 merge 되면 common/widgets 로 옮긴 그 시트를 쓴다(공유 파일 요청). 아니면 여기 두고 백로그 39 승격 줄에 합친다.

/// 내 글 "…"(15d-1 `RCNu0`) → "삭제하기" → 확인(15d-2 `K64Q8p`) → 지우기(사용자 결정 2).
Future<void> showPollMenu(BuildContext context, WidgetRef ref, String pollId) async {
  final wantsDelete = await _showSheet<bool>(context, const _PollMenuSheet());
  if (wantsDelete != true || !context.mounted) return;
  if (await _showSheet<bool>(context, const _DeleteConfirmSheet()) != true) return;
  final error = await ref.read(communityFeedViewModelProvider.notifier).delete(pollId);
  if (error != null && context.mounted) showPollToast(context, error);
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다(채팅 시트와 같다).
    barrierColor: AppColors.scrim,
    builder: (_) => sheet,
  );
}

/// 손잡이 36×4 · 모서리 8 · hairline(두 시트 공통).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(AppRadius.sm)),
    );
  }
}

/// 누르는 행. ListTile 은 쓰지 않는다 — 가장 가까운 Material 이 시트 밖이면 눌림 효과가 떠 있다(COMMON §4-2).
class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: child),
      ),
    );
  }
}

/// 15d-1 메뉴(Menu · Chat 인스턴스 `ofjwb`): #FFF · 위 radius 24 · 안쪽 [12,16,24,16] · 간격 4,
/// 행 52(안쪽 [0,4], 아이콘 20 + 12 + 16/400), "삭제하기" 줄만 error, 구분선 1 hairlineSoft, "취소" 16/600.
class _PollMenuSheet extends StatelessWidget {
  const _PollMenuSheet();

  @override
  Widget build(BuildContext context) {
    void pick(bool? result) => Navigator.of(context).pop(result);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서 시트가 화면보다 길어지면 스크롤한다.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xxs,
            children: [
              const Center(child: _SheetHandle()),
              _SheetRow(
                onTap: () => pick(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: Row(
                    children: [
                      const Icon(AppIcons.trash2, size: 20, color: AppColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '삭제하기',
                          // pen 16 / normal, 줄높이 속성 없음 · 렌더 23(채팅 메뉴 행과 같다).
                          style: AppTypography.body.copyWith(color: AppColors.error, height: 23 / 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const ColoredBox(color: AppColors.hairlineSoft, child: SizedBox(height: 1)),
              _SheetRow(
                onTap: () => pick(null),
                child: Center(
                  child: Text('취소', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 23 / 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 15d-2 확인(AlertSheet `D0TvG` 인스턴스 `CCdBk`): 위 radius 24 · 그림자 #00000026 (0,-2) blur 16 ·
/// 손잡이 영역 위아래 12 · 내용 [8,16,32,16] 간격 16 · 제목 20/700 · 본문 14/400 lh1.55 muted ·
/// 버튼 세로 간격 8(button-danger 56 · button-text 48).
class _DeleteConfirmSheet extends StatelessWidget {
  const _DeleteConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: [BoxShadow(color: Color(0x26000000), offset: Offset(0, -2), blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(child: _SheetHandle()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('이 질문을 삭제할까요?', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '질문과 받은 투표가 모두 사라지고 되돌릴 수 없어요.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: '삭제하기',
                      variant: AppButtonVariant.danger,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      label: '취소',
                      variant: AppButtonVariant.text,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`poll_detail_screen.dart`:

```dart
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 17c 투표 상세(pen `BwL1G`). 카드는 피드와 같은 크기이고 질문만 다 보인다.
/// 들어오는 길이 피드 하나뿐이라 피드 목록의 같은 글을 본다 — 여기서 투표하면 피드도 같이 바뀐다.
class PollDetailScreen extends ConsumerWidget {
  const PollDetailScreen({required this.pollId, super.key});

  final String pollId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poll = ref.watch(
      communityFeedViewModelProvider.select((state) => state.polls.where((p) => p.id == pollId).firstOrNull),
    );
    final isVoting = ref.watch(communityFeedViewModelProvider.select((state) => state.votingIds.contains(pollId)));
    return Scaffold(
      appBar: AppBar(title: Text('투표 상세', style: AppTypography.navTitle)),
      body: poll == null
          ? Center(child: Text('질문을 찾을 수 없어요', style: AppTypography.body.copyWith(color: AppColors.body)))
          // pen `ZR52B`: 세로 간격 16, 안쪽 16.
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                PollCard(
                  poll: poll,
                  now: ref.read(communityNowProvider)(),
                  isVoting: isVoting,
                  onVote: (choice) => _vote(context, ref, choice),
                ),
                const SizedBox(height: AppSpacing.md),
                // pen `LyR5Y` 12/500 #929292 → muted(대장 예외, 대비 4.5:1).
                Text(
                  '댓글 기능은 아직 준비 중이에요',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
                ),
              ],
            ),
    );
  }

  Future<void> _vote(BuildContext context, WidgetRef ref, PollChoice choice) async {
    final message = await ref.read(communityFeedViewModelProvider.notifier).vote(pollId, choice);
    if (message != null && context.mounted) showPollToast(context, message);
  }
}
```

  `community_feed_screen.dart` 의 `PollCard(...)` 에 한 줄(import `poll_sheets.dart`):

```dart
            onMore: poll.isMine ? () => showPollMenu(context, ref, poll.id) : null,
```

  `app_router.dart` 에 A3 에서 남긴 17b · 17c 라우트 두 개를 넣는다.

- [ ] **Step 4: GREEN.** `flutter test` 전체, `flutter analyze` 새 경고 0.
- [ ] **Step 5: pen 검토 반영.** 사용자 pen 검토에서 15d-1 · 15d-2 가 바뀌었으면 맞춘다. 채팅탭 PR 5 가 먼저 merge 됐으면
  결정 D4 대로 두 시트를 common 으로 옮기고 `ChatRoomMenuSheet` · 차단 확인과 같이 쓴다(공유 파일 요청).
- [ ] **Step 6: 커밋.** `✨ feat(community): 투표 상세 · 내 글 삭제 추가`, `🔧 chore(router): 질문 작성 · 투표 상세 경로 추가`,
  `✅ test(community): 상세 · 삭제 테스트 추가`

---

## 테스트 목록 요약

| 층 | 파일 | 개수 | 무엇 |
| --- | --- | --- | --- |
| pgTAP | `supabase/tests/community_polls_test.sql` | 54 | 표 · enum · RLS · 정책 0 · service_role 권한 · 제약 7 · cascade 3 · 피드 8(익명 · 순서 · 커서 · 집계 · 가림 · 탈퇴) · 하루 10개 3 · 보상 경계 5 · 투표 11 · **클라이언트 42501 8**(표 4 · 함수 4 — 이 표들은 grant 가 없어 "0행" 이 아니라 42501 이 기대값이다, ERD §2 95줄) |
| 수동 | C2 Step 5 경합 스크립트 | 1 | 동시 투표 두 개 → 원장 1행 · 잔액 10(잠금 뺀 RED 2 · 20 도 PR 본문에) |
| pytest | `backend/tests/community/test_community_polls.py` | 23 | 9칸 · author 누수 차단 · 커서 · 반쪽 커서 422 · has_more · 상세 404 · 관문 403 · 글쓰기 트림 · 422 5종 · 429 · 투표 · 409 · 404(CM404 · 23503) · 422 · 삭제 조건 · 남의 글 404 |
| flutter | `test/community/**` + `test/common/widgets/app_toast_test.dart` | 46 | 모델 5 · HTTP 3 · VM 11 · 시간 2 · 피드 15(빈 상태 · 실패 · 투표 전/후 · 커스텀 라벨 · 둘째 쪽 실패 · 토스트 · 이동 · 48 · 잉크 · 폰 폭 글자 2배 · 무한 스크롤 · … · 삭제 · 취소) · 작성 6(코드 포인트 포함) · 상세 3 · AppToast 1 |

기준선은 각 PR 착수 때 main 에서 다시 센다(보고에 "기준선 → 결과" 두 숫자).

---

## 문서 갱신 대상 (조각 끝 문서 정리 때 — 지금 PR 금지)

| 문서 | 무엇 |
| --- | --- |
| ERD §7 | `polls` 라벨 1~6자(사용자 답) · 두 라벨 다름 · 인덱스 2 · `poll_votes` voter 인덱스 · DB 함수 4개와 오류 코드(`CM404` · `CM429`) |
| ERD §8 | `content_status` · `poll_choice` "확정 · 적용됨(날짜)" |
| ERD §12 검토 3 | 커뮤니티 조각 번호 → "커뮤니티 탭(2026-09-27 앞당김)" |
| DESIGN §8.11 | 투표 전에도 결과 공개 · 버튼 아래 한 줄(결정 4 · 4-1), 내 글 삭제 메뉴 · 확인 창(결정 2), 하루 10개(결정 3), 작성자 자기 투표 허용, 전체 학교 피드(결정 1) |
| DESIGN §9 | 15d 화면 id 정정(tCsHU 는 하단 내비, 화면은 XhEyI) · 17b p4wnJ · 17c BwL1G, 15d-1~4 신설 |
| DESIGN §8.11 · §2 | 값표 7절 pen↔DESIGN 차이 23건을 pen 기준으로 맞춘다(도넛 두께 ≈18 · 칩 모양 · 질문 16/700 · 카드 그림자 · 17c 확대 없음 · 댓글 안내 줄 · 마스코트 등). 대장 예외 4건(12px · 우세한 쪽 % · 빈 상태 button-secondary · 17c 안내 muted)은 DESIGN 쪽이 맞다 |
| 설계 §13 미결14 | "조각 8" → 앞당김 기록 |
| `backend/DEPLOY.md` | 없음(새 시크릿 · 환경변수 없음) |
