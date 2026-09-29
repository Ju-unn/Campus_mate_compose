# 19 코호트 대기 화면 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다. PR 도 이 순서로 셋이다.
**Part C 는 통합대장이 "DB 차례"를 준 뒤에만** 마이그레이션 파일을 만들고 `supabase db reset` · `supabase test db` 를 돌린다.
클라우드 적용은 ERD 그림 확인 → 사용자 검토 → 사용자 승인 뒤 통합대장이 한다.
**결정 7건은 2026-09-28 대장이 정했다(아래 "결정").** 화면 값은 대장이 주는 pen 값표로만 맞춘다(campus-pen 을 띄우지 않는다).

**Goal:** 가입은 끝났지만 학교 카드가 아직 안 열린 사람에게, 메인(9b) 자리에 첫 카드 날짜("D-14 · 9월 23일", 결정 8) · 우리 학교 모집 인원 · 친구 초대를 보여 준다. 그리고 열리기 전에는 카드를 주지도, 남의 후보로 나오지도 않게 한다.

**Architecture:** 학교마다 첫 카드 여는 시각 `universities.card_opens_at` 하나를 둔다(null 이면 이미 열린 학교). 열렸는지는 DB 함수 셋(카드 받을 사람 · 후보 · 사다리 인원)이 같은 조건 한 줄로 본다. 앱은 새 경로 없이 기존 `GET /home/summary` 응답의 `cohort` 칸을 보고 **메인 탭 안에서** 09b 대신 19 를 그린다 — 라우터 · `auth_redirect` 는 한 줄도 고치지 않는다.

**Tech Stack:** Postgres(Supabase) · pgTAP · FastAPI + httpx(PostgREST) · Flutter + Riverpod 3 · go_router

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §2.9(249줄) · §2.7(208줄) · `frontend/docs/DESIGN.md` §9 화면 19(935줄) · §13-11(1087줄) · `docs/ERD.md` 125~126줄(`universities` 조각4 제안 칸)

---

## 찾은 것 (spec · ERD · 코드, 2026-09-28)

| 물음 | 찾은 답 | 근거 |
| --- | --- | --- |
| 학교별 오픈 날짜를 어디에 두나 | ERD 에 **제안만** 있다: `universities.recruit_starts_at` · `card_opens_at`. 마이그레이션에는 없다(조각 0 에서 "코호트 컬럼 제외") | ERD.md 125~126 · ERD_DECISIONS §10 |
| 지급 주기 | 학교가 아니라 **지역그룹** 단위. 새 학교는 14일 모집 뒤 그 지역의 지금 주기에 합류 | spec §2.9 끝 · ERD §11-7 |
| 약속한 날짜 | "14일이 끝나면 성비와 무관하게 **예고한 날짜에 연다**" | spec §2.9 |
| 오픈 전 카드 배치가 건너뛰나 | **안 건너뛴다.** `card_issue_owners()` · `match_candidates()` · `region_active_counts()` 어디에도 학교 오픈 조건이 없다 | 20260927010500 · 20260920160540 |
| 오픈 순간 알림 | spec · ERD 에 따로 없다. 오픈 날 07:00 배치가 카드를 넣으면 기존 `card_arrived`("오늘의 카드가 도착했어요") 알림이 간다. 조용한 시간 예외라 07:00 에도 간다 | `cards/issuing.py:67` · `cards/push.py:19` |
| 모집 인원 | 칸 없음. `profiles` 를 학교로 세면 된다(새 테이블 불필요) | — |
| 친구 초대 API | 온보딩 탭 `feat/referral` 이 만든다: **`GET /referral/my-code` → `{"code": "K7QMX2"}`**, 관문 `get_verified_caller`, 코드는 계정당 하나 · 안 바뀜 · 캐시 가능. 보상 숫자(`reward_hearts`)는 필요하면 요청(2026-09-28 온보딩 탭과 맞춤, 대장 확인) | 온보딩 탭 메시지 |
| 공유 방식 | 정해진 것 없음. `share_plus` 는 pubspec 에 없다(새 의존성) | `frontend/pubspec.yaml` |
| **함정 — 활동 시각** | **`profiles.last_active_at` 을 고치는 코드가 어디에도 없다**(서버 · 앱 · DB 전부 grep 0건, 가입 때 `default now()` 뿐). 그래서 지금은 **모든 사람이 가입 14일 뒤 카드를 못 받고 15일 뒤 남의 후보에서 빠진다.** 14일 모집 첫날 가입한 사람은 오픈 날 딱 경계에 걸린다(→ 결정 F1 로 고침, #141) | `create_profiles.sql:50` · 20260927010500 74·163줄 |

## 결정 (2026-09-28 통합대장 — 사용자에게는 대장이 한 줄로 알림)

| # | 물음 | 결정 | 걸린 스텝 |
| --- | --- | --- | --- |
| 1 | 화면을 넣는 자리 | **메인 탭 안에서 바꿔 끼우기**(`/home/summary` 에 `cohort` 칸). 라우터 · auth_redirect 0줄 | A3 |
| 2 | 첫 카드 여는 날 | **(가) 월요일 오전 7시에만** — 배치를 안 고친다 | C1 check |
| 3 | 모집 인원 세는 기준 | **(가) 가입을 다 끝낸 사람**(`status='active'`) | B1 |
| 4 | 오픈 순간 알림 | **(가) 기존 "오늘의 카드가 도착했어요"로 충분** — B2 없음 | — |
| 5 | 친구 초대 공유 방식 | **(가) 휴대폰 공유 창 `share_plus`**(pubspec 한 줄). 공유 글은 아래 제안대로. **사용자 직접 승인("가", 2026-09-28 대장 전달)** | A4 |
| 6 | 모집 중 "오늘" 탭 | **(가) 대기 화면.** `today_cards_screen.dart` 는 줄 단위 허락 뒤 | A5 |
| 7 | pen 19 값표 | **받음**(2026-09-28): `조각6_검토/값표_새기능_A.md` "19 코호트 대기 tUaGw" · PNG `수정후_새기능/08_19_코호트대기_tUaGw.png` | A3 · 화면 대조표 |
| 8 | 날짜 표시 | pen 은 날짜만("9월 23일" 48/700, countdown `sZZ14` 안 씀). **"D-14 · 9월 23일" 형식, 초 단위 카운트다운 없음.** 당일은 "D-day", 7시 전이면 "오늘 오전 7시". pen 은 대장이 다음 묶음에서 고침 | A3 |
| 9 | 하단 내비 대화 배지 | pen "4" 는 첫 카드 전이라 나올 수 없다(끌 예정). 앱은 0 이면 숨기는 기존 규칙 그대로 — 고칠 것 없음 | — |
| 10 | 친구 초대 버튼 | pen 일반 frame `FftE4` 52h r8 "친구에게 초대 링크 보내기" — **pen 값을 따른다**(`AppButton` 56h r16 아님) | A3 · A4 |
| 11 | 모집 중 오늘 탭 모양 | pen 에 없다 → 결정 6 대로 19 와 같은 대기 화면 | A5 |
| F1 | `last_active_at` 갱신 없음 | **고침** — #141 merge(cefaa53) · 배포 00033-tk6. `/home/summary` 에서 조건부 PATCH | 오픈 날 카드 전제 |

"DB 차례" 순서(대장, 2026-09-28): referral → 나 탭 → heart-tasks → friend_reviews → **cohort**. 차례가 오면 먼저 origin/main 으로 rebase 한다 — 마이그레이션 시각이 앞 차례들보다 뒤여야 한다.

공유 글 제안(결정 5 와 함께 대장 확인): `CampusMate 에서 같이 해요! 가입할 때 추천 코드 {code} 를 넣어 줘.` — 하트 숫자는 넣지 않는다(보상은 학생증 통과 뒤라 조건이 길고, 숫자를 넣으려면 서버 `reward_hearts` 가 필요하다). 스토어 링크는 출시 뒤에 더한다.

### pen 19 값표에서 나온 물음 — **셋 다 (가) 확정(2026-09-28 대장 결정, pen 은 다음 묶음에서 맞춤)**

| # | 물음 | 선택지 | 결정 |
| --- | --- | --- | --- |
| Q1 | "D-14 · 9월 23일" 을 48/700 한 줄에 넣으면 폭이 약 320 인데, 쓸 수 있는 폭은 288(히어로 328 − 좌우 20) 이다(pen "9월 23일" 이 184 로 잰 글자 폭 기준) | (가) 큰 줄은 pen 대로 날짜만 48 — "9월 23일" / "오늘 오전 7시", "D-14" · "D-day" 는 위 작은 줄 끝에 — "우리 학교 첫 카드까지 · D-14" (나) 큰 줄에 "D-14 · 9월 23일" 그대로, 폭에 맞춰 약 43px 로 줄여 보임 | **(가) 확정** — 48 크기를 지키고 pen 은 작은 줄 문구만 바뀐다 |
| Q2 | 앱바 오른쪽: pen 19 는 톱니(`stzJJ` 에 settings), 09b 는 같은 `stzJJ` 에 종(`NotifyIconButton`) | (가) 09b 와 같은 종 그대로 — 앱바 0줄, pen 을 종으로 (나) pen 대로 톱니(설정으로 가기) — 앱바에 코호트 갈래 하나 | **(가) 확정** — 결정 1 대로 메인 탭 안에서 바꿔 끼우니 앱바는 하나 |
| Q3 | 배지 "첫 100명 모집 중"(`R6EEu`): spec · DESIGN §9 화면 19 에 모집 목표가 없다("100명"은 하트 보상표 DESIGN 748줄뿐). 배지 글자 값도 값표에 없다 | (가) 배지 빼기 — pen 에서 지움 (나) 고정 글 — 100명을 넘어도 그대로(틀린 말이 됨) (다) 100명 미만일 때만 보이기 | **(가) 확정** — 근거 없는 숫자를 약속처럼 보이지 않게. 모집 판은 "현재 모집 인원 · N명"만 |

## ERD 변경 (그림은 대장이 pen 에 반영)

- `universities.card_opens_at timestamptz null` — **"조각4 제안" → 실제 칸.** null 이면 코호트 없이 이미 열린 학교(지금 시드 학교 전부). 대시보드에서 값만 넣는다(`region_group_settings` 와 같은 운영 방식).
- `universities.recruit_starts_at` — **제안 삭제.** 학교 행을 넣는 순간이 곧 모집 시작이다(가입 화이트리스트가 이 테이블이다). 화면도 배치도 이 값을 안 쓴다.
- `universities` 는 anon 까지 읽기라 여는 시각도 공개된다 — 공지하는 날짜라 문제없다.

## PR 나누기

1. **PR C** `feat/cohort-wait` 첫 PR — 마이그레이션 1개 + pgTAP 1개 + 이 계획서
2. **PR B** — `/home/summary` 에 `cohort` 칸
3. **PR A** — 19 화면(+ 결정 6 이면 오늘 탭)

## Global Constraints

- 커밋 · PR 에 도구 표식(Co-Authored-By 등) 금지. `dart format` 금지. 새 의존성은 결정 5 허락 뒤에만.
- 공유 파일(core/router/* · core/theme/* · common/widgets/* · pubspec · main.py) 은 대장 1회 허락 뒤에만. **이 계획은 pubspec(결정 5) 말고는 공유 파일을 건드리지 않는다.**
- 로그에 실명 · 코드 · 경로를 남기지 않는다.
- 함수는 `create or replace` 만 — 시그니처 · 반환 칸을 바꾸지 않는다(운영 서버가 부르고 있다, 20260927010500 머리말과 같은 규칙).
- 로컬 DB 명령(`supabase db reset` · `supabase test db`)은 대장이 DB 차례를 준 동안 이 창의 코더 · 리뷰어만 쓴다. 도우미(campus-git · campus-ui · 차례 없는 코더 · 리뷰어) 요청문에는 "supabase db reset·test db 등 로컬 DB 명령 금지. 수치는 리뷰어 값 인용" 을 적는다(대장 규칙, 2026-09-28).

## Review Focus

1. **여는 시각을 막 지난 순간 · 자정을 넘김** — 앱을 켜 둔 채 여는 시각이 되면 화면이 스스로 09b 로 바뀌고, 자정을 넘기면 D-14 가 D-13 이 된다(껐다 켜지 않아도). 기기 시계가 서버보다 빨라 다시 읽어도 아직 `cohort` 면 **1분 뒤** 다시 읽는다 — 0초로 되풀이해 서버를 두드리지 않는다. → A3 테스트 "여는 시각에 요약을 다시 읽는다" · "자정에 D-숫자가 바뀐다" · "지난 시각이면 1분 뒤에만 다시 읽는다".
2. **여는 시각 null 인 학교** — 지금 있는 모든 학교다. 한 곳이라도 "안 열림"으로 보면 운영 중인 사람 전부의 카드가 끊긴다. → C1 pgTAP "null 은 열림" 3함수 각각.
3. **요약을 못 받은 코호트 사람** — 지금처럼 hero-today 만 남는다(카드로 가는 길). 코호트 여부를 모르니 09b 쪽으로 떨어지는 게 맞다. → A3 테스트 "요약 실패면 대기 화면이 없다".
4. **추천 코드를 못 받음** — 버튼을 눌러도 앱이 죽지 않고 실패 토스트. → A4 테스트.
5. **글자 크게(1.3배) · 긴 날짜** — 48px 줄("12월 28일" · "오늘 오전 7시")이 360 폭 · 1.3배에서 넘치지 않고, 버튼이 화면 밖으로 밀리면 스크롤로 닿는다. → A3 테스트 textScaler 1.3 · 360 폭에서 overflow 없음 + 버튼 보이게 스크롤.

---

## Part C — Supabase (DB 차례를 받은 뒤)

### Task C1: `card_opens_at` 과 "열린 학교" 조건 셋

**Files:**
- Create: `supabase/migrations/<DB 차례 때 시각>_add_university_card_opens_at.sql`
- Create: `supabase/tests/cohort_open_test.sql`

**Interfaces:**
- Produces: `public.universities.card_opens_at timestamptz` (null = 열림). "열림" 정의는 딱 하나: `card_opens_at is null or card_opens_at <= now()`.

- [x] **Step 1: 실패하는 pgTAP 를 쓴다** — `cohort_open_test.sql`. 학교 셋(null · 지난 시각 · 앞으로 시각)에 남녀 한 명씩, 벡터까지 채운 active 프로필을 만든다(`home_stats_test.sql` · `rls_slice6_test.sql` 의 시드 방식을 따른다). 단정:
  - `card_issue_owners()` 에 null 학교 · 지난 학교 사람은 **있고**, 앞으로 학교 사람은 **없다**
  - 열린 학교 사람의 `match_candidates()` 에 앞으로 학교 사람이 **없다**
  - 앞으로 학교 사람의 `match_candidates()` 는 **0행** (구매 카드가 생겨도 열리기 전엔 못 받는다)
  - `region_active_counts()` 가 앞으로 학교 사람을 **세지 않는다**
  - 월요일이 아닌 시각을 넣으면 check 위반 `23514`
  - (검토 권고 반영) 서울 월요일이어도 07:00 이 아니면(`16:00+09`) · `infinity` 면 check 위반 `23514`
- [x] **Step 2: 돌려서 실패를 본다** — `supabase test db` → 칸이 없어서 실패. (2026-09-28: 새 파일만 실패, 나머지 11파일 337 통과. 칸 · check 만 `migration up` 으로 넣은 중간 상태에서 1~5번이 조건 없음으로 실패, check 6~8 · 9번 통과 — 함수 조건 RED 확인. 번호는 단정 9개 때 기준 — 권고 반영으로 07:00 · infinity 단정 2개가 7 · 8번에 끼어 지금은 11개)
- [x] **Step 3: 마이그레이션을 쓴다.** — `20260928050000_add_university_card_opens_at.sql`(시각은 대장 예약)

```sql
-- 코호트(설계 §2.9): 학교마다 첫 카드를 여는 시각. null 이면 코호트 없이 이미 열린 학교다.
-- 여는 날은 월요일 07:00(Asia/Seoul) — 지급 요일이 어떻게 바뀌어도 월요일은 늘 지급일이라
-- 배치가 따로 갈래를 두지 않는다(결정 2). 카드 배치는 Cloud Scheduler 가 07:00 에 한 번 부른다(cards/issuing.py) —
-- 스케줄 시각을 바꾸면 이 check 도 마이그레이션으로 같이 바꾼다. infinity 는 isfinite 로 막는다.
alter table public.universities
  add column card_opens_at timestamptz,
  add constraint universities_card_opens_monday_0700
    check (
      card_opens_at is null
      or (
        isfinite(card_opens_at)
        and extract(isodow from card_opens_at at time zone 'Asia/Seoul') = 1
        and (card_opens_at at time zone 'Asia/Seoul')::time = time '07:00'
      )
    );

comment on column public.universities.card_opens_at is
  '첫 카드 지급 시각(설계 §2.9). null = 이미 열림. 열리기 전 사람은 카드 · 후보 · 사다리 인원에서 빠진다';
```

  그 아래에 **세 함수를 최신 본문 그대로 통째로 옮겨 오고 조건 한 줄씩만 더한다**:
  - `match_candidates` · `card_issue_owners` ← `20260927010500_update_candidate_filters_slice6.sql` (**DB 차례 때 main 에 더 새 본문이 있으면 그것**)
  - `region_active_counts` ← `20260920160540_create_region_group_settings.sql`
  - 더할 줄: `card_issue_owners` · `region_active_counts` 의 where 에 `and (u.card_opens_at is null or u.card_opens_at <= now())   -- 코호트: 열린 학교만(설계 §2.9)`, `match_candidates` 의 후보 where 에 `and (cu.card_opens_at is null or cu.card_opens_at <= now())`, `me` CTE 의 where 에 `and (u.card_opens_at is null or u.card_opens_at <= now())`
  - grant · revoke 줄도 원본 그대로 다시 적는다.
- [x] **Step 4: `supabase db reset` → `supabase test db` 전부 통과.** 기존 pgTAP 수(기준선)가 줄지 않았는지 적는다. (2026-09-28: 12파일 346 = 기준선 337 + 새 9. 검토 권고 반영 뒤 — check 에 서울 07:00 · isfinite 추가, 단정 2개 추가(RED: 그 둘만 실패) — origin/main cd353a5 로 rebase 하고 15파일 388 통과)
- [ ] **Step 5: 커밋은 campus-git 몫** — 검토 PASS 뒤.

## Part B — FastAPI

### Task B1: `/home/summary` 에 `cohort`

**Files:**
- Modify: `backend/app/home/repository.py` · `backend/app/home/router.py`
- Test: `backend/tests/home/test_home_summary.py`

**Interfaces:**
- Consumes: C1 `universities.card_opens_at`
- Produces: 응답에 `"cohort": null | {"first_card_at": "<ISO 8601, 시간대 포함>", "recruit_count": <int>}` — 열렸으면 null.

- [x] **Step 1: 실패하는 테스트 셋**(가짜 PostgREST 는 URL 부분문자열이 아니라 **params 키**로 가른다 — 메모리 함정):
  - `card_opens_at` 이 null → `cohort` 가 null, 모집 인원 조회를 **부르지 않는다**
  - 지난 시각 → null
  - 앞으로 시각 → `{"first_card_at": 그 값, "recruit_count": 37}`, 인원 조회 params 에 `profiles.status=eq.active` 가 있다(결정 3 (가))
- [x] **Step 2: 실패 확인** — 루트 `.venv` 파이썬으로 `pytest backend/tests/home -q`.
- [x] **Step 3: 구현.** `fetch_completion_materials` 의 select 에 `,university_id,universities(card_opens_at)` 를 더한다(한 번 조회 그대로). 새 메서드:

```python
    async def fetch_recruit_count(self, university_id: str) -> int:
        # 모집 인원 = 그 학교에서 가입을 끝낸 사람(홈 "가입 수"와 같은 기준). 사진 수와 같은 embed count 모양.
        response = await self._get("universities", params={
            "id": f"eq.{university_id}",
            "select": "profiles(count)",
            "profiles.status": "eq.active",
        })
        raise_for_status(response)
        return response.json()[0]["profiles"][0]["count"]
```

  라우터는 `opens_at = me["universities"]["card_opens_at"]` 가 있고 `datetime.fromisoformat(opens_at) > datetime.now(timezone.utc)` 일 때만 인원을 세서 `cohort` 를 채운다.

  **구현 편차(2026-09-28):** 위 embed `profiles(count)` + `profiles.status` 대신 `count_recruits` 가 `profiles?university_id=eq.…&status=eq.active` 를 `Prefer: count=exact` 로 세고 Content-Range 에서 수를 읽는다 — `account/repository.py` `count_contact_blocks_not_on` 과 같은 모양. embed 안 필터가 count 에 걸리는지 로컬에서 확인할 길 없이 기대는 대신, 이미 운영 중인 방식을 쓴다. 테스트 가짜는 `university_id` 키로 가른다.
- [x] **Step 1~3** — 새 테스트 3개 + 기존 2개 기대값(`cohort: None` · select 에 `universities(card_opens_at)`) 먼저 고쳐 5개 실패 확인 → 구현.
- [x] **Step 4: 통과 + 전체 `pytest -q` 기준선 비교.** (2026-09-28: home 15 · 전체 568 통과 = 기준선 565 + 새 3)

### Task B2 — 없음

결정 2 · 4 가 둘 다 (가)라 배치 · 알림을 고치지 않는다.

## Part A — Flutter

### Task A1: 모델 · 저장소

**Files:**
- Create: `frontend/lib/home/model/cohort_wait.dart`
- Modify: `frontend/lib/home/model/home_summary.dart` · `http_home_repository.dart`
- Test: `frontend/test/home/model/http_home_repository_test.dart`

**Interfaces:**
- Produces: `class CohortWait { final DateTime firstCardAt; final int recruitCount; }` · `HomeSummary.cohort` (`CohortWait?`)

- [x] 실패 테스트: `cohort` null → `summary.cohort == null`, 객체 → 두 값이 파싱된다(`firstCardAt` 은 `.toLocal()`).
- [x] 구현 → 통과. `test/home/model/fake_home_repository.dart` 는 기본 `cohort: null` 로.

### Task A2: 내 추천 코드 — 새로 만들지 않는다

온보딩 탭 `feat/referral-app`(2026-09-28 그 워크트리에서 확인, 아직 미커밋)이 이미 만든다: `frontend/lib/referral/model/referral_repository.dart` 의 `Future<Result<String>> myCode()`(주석 "홈탭 19 코호트 대기 '친구 초대'가 쓴다") · `referralRepositoryProvider` · 테스트용 `test/referral/model/fake_referral_repository.dart`. **Part A 는 그 PR 이 merge 된 뒤 시작하고 이것을 그대로 쓴다.** 그때 main 에 없으면 대장에게 알린다.

### Task A3: 19 화면 (메인 탭 안에서 바꿔 끼우기)

**Files:**
- Create: `frontend/lib/home/view/cohort_wait_view.dart`
- Modify: `frontend/lib/home/view/home_screen.dart` — `summary?.cohort` 가 있으면 `body` 를 `ListView` 대신 `CohortWaitView(cohort: …)`. 앱바 · 하단 내비는 그대로(Q2 (가))
- Test: `frontend/test/home/view/cohort_wait_view_test.dart` · `home_screen_test.dart`

**Interfaces:**
- Consumes: A1 `CohortWait` · A2 `referralRepositoryProvider` · 기존 `homeSummaryProvider`
- Produces: `CohortWaitView({required CohortWait cohort})`(ConsumerStatefulWidget, 본문만 — 앱바 · 내비 없음, A5 가 그대로 씀) · `homeNowProvider` · `cohortDayLabel` · `cohortDateLabel`

- [x] 시계: `final homeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);` — `verifyCodeNowProvider` · `communityNowProvider` 와 같은 모양.
- [x] 글은 순수 함수 둘(같은 파일, 테스트가 직접 부른다). 날짜 차이는 달력 날짜로 센다 — 시각 차이 `inDays` 는 06:59 와 07:00 사이에서 하루가 틀린다. 시각은 7 을 박지 않고 `opensAt` 에서 읽는다(지금 check 는 07:00 고정이지만, 스케줄 시각이 바뀌면 check 와 함께 바뀐다 — C1 주석):

```dart
/// "D-14" · 당일은 "D-day"(결정 8). 기기 시간대의 달력 날짜로 센다.
String cohortDayLabel(DateTime now, DateTime opensAt) {
  final days = DateTime.utc(opensAt.year, opensAt.month, opensAt.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
  return days <= 0 ? 'D-day' : 'D-$days';
}

/// 큰 줄: 당일은 "오늘 오전 7시", 그 전은 "9월 23일"(결정 8).
String cohortDateLabel(DateTime now, DateTime opensAt) {
  if (cohortDayLabel(now, opensAt) != 'D-day') return '${opensAt.month}월 ${opensAt.day}일';
  final h = opensAt.hour;
  final minute = opensAt.minute == 0 ? '' : ' ${opensAt.minute}분';
  return '오늘 ${h < 12 ? '오전' : '오후'} ${h % 12 == 0 ? 12 : h % 12}시$minute';
}
```

- [x] 타이머: 초마다 돌지 않는다. 한 번짜리 `Timer` 하나 — 다음 자정과 `opensAt` 중 먼저. `initState` · `didUpdateWidget`(다시 읽은 요약이 새 `cohort` 로 들어옴) 에서 걸고 `dispose` 에서 끈다:

```dart
  void _schedule() {
    _timer?.cancel();
    final now = ref.read(homeNowProvider)();
    final opensAt = widget.cohort.firstCardAt;
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final opening = !midnight.isBefore(opensAt);
    var wait = (opening ? opensAt : midnight).difference(now);
    // 기기 시계가 서버보다 빠르면 다시 읽어도 cohort 가 온다 — 0초로 되풀이해 서버를 두드리지 않게.
    if (wait <= Duration.zero) wait = const Duration(minutes: 1);
    _timer = Timer(wait, () {
      if (opening) {
        ref.invalidate(homeSummaryProvider);
      } else {
        _schedule();
        setState(() {});
      }
    });
  }
```

- [x] 배치(값은 아래 화면 대조표에서만): `CustomScrollView` → `SliverPadding(8,16,24,16)` → `SliverFillRemaining(hasScrollBody: false)` 안 `Column` — 히어로 · 20 · 모집 판 · 20 · 초대 안내 · `Spacer` · 버튼. 보통 글자에선 버튼이 아래에 붙고(pen), 1.3배로 넘치면 같이 스크롤된다. 큰 줄은 `FittedBox(fit: BoxFit.scaleDown)` 로 감싸 폭을 넘지 않게.
- [x] 버튼 눌림 효과(COMMON §4-2): `overlayColor` 투명 + 눌림 배경 `AppColors.primaryPressed` — `AppButton` 과 같은 규칙.
- [x] 실패 테스트(`cohort_wait_view_test.dart`) — 시계는 바꿀 수 있는 변수로 override(`var now = …; homeNowProvider.overrideWithValue(() => now)`):
  - 함수: 14일 전 → "D-14" · "9월 23일" / 전날 23:59 → "D-1" / 당일 06:59 → "D-day" · "오늘 오전 7시" / 여는 시각 지남 → "D-day"
  - 화면: "우리 학교 첫 카드까지 · D-14"(Q1 (가)) · "9월 23일" · "같은 날, 같은 설렘으로 시작해요" · "현재 모집 인원" · "87명" · 초대 안내 · "친구에게 초대 링크 보내기" 가 있고, "첫 100명 모집 중" 은 없다(Q3 (가))
  - 여는 시각 5초 전 → 5초 pump → 가짜 요약 저장소 부른 수 +1
  - 자정 10초 전(여는 날은 8일 뒤) → `now` 를 10초 앞으로 · 10초 pump → "D-8" 이 "D-7"
  - 여는 시각 1초 지남(요약이 아직 cohort) → 59초 pump 까지는 안 읽고, 60초에 한 번 읽는다
  - textScaler 1.3 · 360×640 에서 overflow 없음, 버튼까지 스크롤로 닿음 — "12월 28일" 과 "오늘 오전 7시" 둘 다
- [x] `home_screen_test.dart`: `cohort` 가 있으면 대기 화면이 있고 hero-today 는 없다 / 요약 실패면 대기 화면이 없다(hero-today 남음) / `cohort` null 이면 지금 그대로.
- [x] 구현 → 통과 → `flutter test` 전체, 기준선 비교(한 워크트리에서 동시에 돌리지 않는다).

### Task A4: 친구 초대 (결정 5 (가) — 사용자 승인)

**Files:**
- Modify: `frontend/pubspec.yaml` · `pubspec.lock` — `flutter pub add share_plus` 한 줄(결정 5 가 이 한 줄을 허락)
- Modify: `frontend/lib/home/view/cohort_wait_view.dart`
- Test: `frontend/test/home/view/cohort_wait_view_test.dart`

- [x] 공유는 provider 로 주입: `final shareTextProvider = Provider<Future<void> Function(String)>((ref) => (text) => SharePlus.instance.share(ShareParams(text: text)));` — 테스트는 받은 글을 목록에 모은다.
- [x] 실패 테스트: 버튼 → `myCode()` 가 `K7QMX2` 면 공유 글이 `CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.` / 실패 `Result` 면 공유를 부르지 않고 `Failure` 문구로 토스트(`AppToast`, `photos_screen` `_showToast` 와 같은 방식), 화면 그대로 / 코드를 기다리는 동안 한 번 더 눌러도 공유는 한 번.
- [x] 구현 → 통과.

### Task A5: 모집 중 오늘 탭 (결정 6 · 11)

**Files:**
- Modify: `frontend/lib/matching/view/today_cards_screen.dart` — **다른 탭 파일이라 고칠 줄을 적어 대장에게 줄 단위 허락을 먼저 받는다**
- Test: `frontend/test/matching/view/today_cards_screen_test.dart`

- [x] 실패 테스트: `homeSummaryProvider` 의 `cohort` 가 있으면 본문이 `CohortWaitView` 이고 카드는 없다 / null 이면 지금 그대로.
- [x] 구현: `ref.watch(homeSummaryProvider).value?.cohort` 가 있으면 본문만 `CohortWaitView(cohort: …)`. 앱바 · 하단 내비(오늘 활성)는 오늘 탭 것 그대로 → 통과.

**Part A 진행 · 편차(2026-09-28):**
- A2 는 새 코드 0 — main 의 `referralRepositoryProvider.myCode()` · 테스트 `FakeReferralRepository` 를 그대로 쓴다.
- A3 배치는 `SliverPadding` 대신 `SliverFillRemaining` 안쪽 `Padding` — SliverPadding 으로 감싸면 채움 높이가 아래 24 를 빼지 않아 버튼이 내비에 붙는다(테스트 "버튼 52 가 내비 위 24"로 잡음).
- A3 타이머는 콜백에서 `setState(_schedule)` 하나로 자정 · 여는 시각 · 1분 재시도를 모두 다시 건다(열렸으면 요약이 cohort 없이 와서 위젯이 사라진다).
- A3 검토 권고 반영: 앱으로 돌아오면(`AppLifecycleListener.onResume`) 지금 시각으로 다시 센다 — 잠든 시간은 타이머 시계에 안 잡힐 수 있다. 여는 시각이 지났으면 곧바로 요약을 다시 읽는다. `didUpdateWidget` 을 지키는 테스트도 더했다. 큰 줄 letterSpacing(`IDJ3M`, 그때 countdown 토큰 −1.44)은 #159 merge 뒤 후속 PR 에서 맞췄다(아래 표, 대장 값표 `값표_작은값_0929.md` §1).
- A4 공유 창이 예외를 던지면 `UnknownFailure` 문구로 토스트.
- A4 토스트 자리는 pen 에 없어 `photos_screen` 과 같이 버튼 위 가운데 · 간격 12 · alertTriangle.
- A5 는 대장 줄 단위 허락 그대로(import 2 · watch 1 · body 1줄). 기존 테스트 pump 에 home 저장소 override 한 줄을 더했다(없으면 실제 HTTP provider 를 부른다).
- 검증: `test/home` + `today_cards_screen_test` 62 통과, analyze 0. A4 는 동작 빼기 → 3개 실패, 두 번 누르기 가드 빼기 → 1개 실패로 RED 확인(첫 RED 는 800×600 화면에서 tap 이 버튼을 빗나간 실패라 무효였다 — `ensureVisible` + `pump` 로 고침).

---

## 화면 대조표 (pen 19 `tUaGw` — 대장 값표 2026-09-28)

출처: `조각6_검토/값표_새기능_A.md` "19 코호트 대기 tUaGw" · PNG `수정후_새기능/08_19_코호트대기_tUaGw.png`. **Q1~Q3 는 (가) 확정(2026-09-28 대장).** pen 이 다음 묶음에서 바뀌면 노드 값을 이 표와 다시 맞춘다.

| 부분 | pen 노드 | 값(크기 · 색 · 간격 · 문구) | Flutter | 테스트 |
| --- | --- | --- | --- | --- |
| 앱바 | `D4Q6U`(`YTDwe`) | "CampusMate" #FF385C, 오른쪽 `stzJJ`(pen 은 settings) | 09b `HomeScreen` 앱바 그대로 — 종(Q2 (가)) | 0줄 |
| 본문 | `R1DPu` | vertical gap 20, padding [8,16,24,16] | `SliverPadding` + `SliverFillRemaining(hasScrollBody: false)` 안 `Column` | 1.3배 스크롤 |
| 히어로 | `gFbj2` | 328×330 #FFF0F2 r32 gap 8 padding [20,20,18,20], 가운데 | `AppColors.primaryWash` · `AppRadius.xl` | |
| 마스코트 | `of3fj` | 132, male | `Image.asset('assets/images/mascot-male.png', width: 132, height: 132)` | |
| 작은 줄 | `BBGsm` | "우리 학교 첫 카드까지" 14/600 #C4224B lh1.5 — 뒤에 " · D-14"(Q1 (가)) | `AppTypography.labelSmall.copyWith(color: AppColors.primaryText, height: 1.5)` | 문구 |
| 큰 줄 | `IDJ3M` | "9월 23일" 48/700 #222222 lh1.5 자간 0 (184×74) · 당일 "오늘 오전 7시"(결정 8). countdown `sZZ14`(lh1.1 · −1.44) 인스턴스 아님(0929 값표) | `AppTypography.display.copyWith(fontSize: 48, height: 1.5, letterSpacing: 0, color: AppColors.ink)` — 날짜라 tabular 없음 + `FittedBox(scaleDown)` | 문구 · 1.3배 · 글자 값 |
| 부제 | `ocR77` | "같은 날, 같은 설렘으로 시작해요" 14/400 #6A6A6A | `AppTypography.bodySmall` · `AppColors.muted` | 문구 |
| 모집 판 | `u7XsyB` | 92h #F7F7F7 r14 padding 16, 양끝 | `AppColors.surfaceSoft` · `AppRadius.md`, 배지가 빠져(Q3) `Container(alignment: centerLeft)` 안 `Column` 두 줄, 높이는 `minHeight: 92`(글자 확대로 늘 수 있게). 왼쪽 열 `o6UY45` vertical gap 4(0929 값표) → `SizedBox(height: 4)`. pen 은 92 고정에 두 줄(63)을 가운데 둬 위아래가 15 · 14 라, padding 16 을 지키면 93 이 되어 `symmetric(horizontal: 16, vertical: 14)` | 92 · 사이 4 |
| 모집 라벨 | `WEPFQ` | "현재 모집 인원" 14/400 #6A6A6A lh1.5 | `bodySmall` · `muted`, `height: 1.5`(토큰 1.55) | 문구 · 줄 높이 |
| 모집 숫자 | `ebHk4` | "87명" 24/700 #222222 lh1.5 | `AppTypography.headline` · `ink`, `height: 1.5`(토큰 1.35), `'${cohort.recruitCount}명'` | 숫자 · 줄 높이 |
| 목표 배지 | `R6EEu`(`h1CMd`) | #FFFFFF, users 18, "첫 100명 모집 중" 134×35(글자 값 없음) | **없음(Q3 (가))** | 없음 단정 |
| 초대 안내 | `G5OV3t` | "친구와 함께 시작하면 첫날부터 더 많은 캠퍼스 친구를 만날 수 있어요." 14/400 #3F3F3F lh1.5 (문구는 PNG 08) | `bodySmall.copyWith(color: AppColors.body, height: 1.5)` | 문구 |
| 친구 초대 | `FftE4` | 일반 frame 328×52 #FF385C r8, "친구에게 초대 링크 보내기" 18/700 흰색. 본문 아래에 붙음(y567 + 52 = 619 = 본문 643 − 아래 24, PNG 로 잰 계산값) | 로컬 `ElevatedButton` 52h · `AppRadius.sm` · `AppColors.primary` · `AppTypography.label` 흰색(결정 10) | 누르면 공유(A4) |
| 하단 내비 | `k5rbD`(`Migf0`) | 활성 = 메인. 대화 배지 "4" 는 pen 에서 끌 예정 | `AppBottomNav(current: AppTab.main)` 그대로 — 0 이면 숨김(결정 9) | 0줄 |
| 오늘 탭 모집 중 | 없음 | 결정 6 · 11 | `CohortWaitView` 재사용(A5) | A5 |

표에 없는 값은 구현하지 않는다(말로 받은 값은 노드 id 와 함께). DESIGN §9 화면 19 행("`{type.countdown}` 48px 로 N월 N일 첫 카드까지 남은 시간", `button-primary`)은 결정 8 · 10 과 달라졌다 → 문서 정리 때 대장.
