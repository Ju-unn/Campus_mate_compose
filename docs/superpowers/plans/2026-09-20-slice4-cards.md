# 조각 4: 일일 카드 지급 · 수락 · 푸시 알림 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Task 0(.gitignore) → Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다.
> **Part C 는 파일 작성 + 로컬 스택 검증까지만 하고 클라우드 적용은 하지 않는다**(`[[supabase-apply-gate]]` —
> ERD 그림 · 사용자 검토 · 사용자 승인 후 별도 supabase 세션이 적용한다).
> **Part A 는 새 의존성(firebase_core · firebase_messaging · google-services Gradle 플러그인) 사용자 승인
> 전에는 시작하지 않는다.** 승인 전에도 Part C · Part B 는 전부 할 수 있다.

**Goal:** 지역그룹마다 정해진 요일 아침 7시에 **이성 1명을 카드로 자동 지급**하고, 받은 사람이 수락 · 거절하고,
상대가 다시 수락하면 **매칭(matches)까지 만들고**, 그 세 순간(카드 도착 · 받은 수락 · 매칭 성사)을 **FCM 푸시로
알리는** 것까지 만든다. 채팅방은 조각 5, 하트 소비(추가 카드 · 카드 열람)는 조각 7, 차단은 조각 6 이다.

**Architecture:** 지급은 **하루 한 번 도는 배치**다. Cloud Scheduler 가 매일 07:00(Asia/Seoul)에 FastAPI
`/batch/daily-cards` 를 공유 비밀 헤더와 함께 부르고, 배치는 지역그룹별로 ① 활성 사용자 수로 **지급 요일 사다리**를
판정해 오늘이 지급일인지 보고, ② 지급일이면 대상자마다 조각 3 의 `match_candidates` RPC + `scoring.py` 로 1위를
뽑아 `daily_cards` 에 한 행을 넣고, ③ 푸시를 보낸다. 지급 주기를 바꾸는 손잡이는 전부 `region_group_settings`
행에 있어 **배포 없이 대시보드 값만 고치면 된다**. 만료는 **행을 쓰지 않는다** — 카드 만료는 `expires_at` 이
지났는데 `card_decisions` 행이 없는 상태, 받은 수락함 만료는 `card_decisions.decided_at` 이 7일보다 오래됐는데
`acceptance_responses` 행이 없는 상태로 **조회 시점에 판정**한다(정리 배치도, 상태 컬럼도 없다).

**Tech Stack:** Postgres 17 (Supabase) + FastAPI + httpx(PostgREST · FCM 직접 호출) + **FCM HTTP v1**
(Cloud Run 서비스 계정 ADC, Vision 과 같은 방식) + Cloud Scheduler + Flutter(Riverpod `Notifier`) +
`firebase_core` · `firebase_messaging`(**새 의존성 — 사용자 승인 필요**).

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §2.1 · §2.2 · §2.4 · §2.6 ·
§6.7 · §6.8 · §7.1, `docs/ERD.md` §2(권한 표) · §3(`region_group_settings` · `matching_paused`) · §4(조각 4~5
테이블), `frontend/docs/DESIGN.md` §8.1 · §8.2 · §8.6, pen `datingApp.pen` §3 "카드 · 매칭 · 채팅"(`qXpwn`)

## 새 의존성 (사용자 승인 필요 — 승인 전에는 Part A 착수 금지)

| 구분 | 패키지 · 도구 | 용도 | 왜 없으면 안 되나 |
| --- | --- | --- | --- |
| Flutter | `firebase_core` (^4.x) | Firebase SDK 초기화 | `firebase_messaging` 이 요구한다. 단독으로 쓰는 기능은 없다 |
| Flutter | `firebase_messaging` (^16.x) | FCM 토큰 발급 · 푸시 수신 | 토큰(`getToken`)을 만드는 다른 방법이 없다. 안드로이드 푸시의 유일한 경로 |
| Android 빌드 | `com.google.gms:google-services` Gradle 플러그인 | `google-services.json` 을 빌드에 붙인다 | Firebase 공식 설정 방식. 이것 없이는 앱이 FCM 프로젝트를 모른다 |
| 백엔드 | **없음 — `google-auth` 재사용** | FCM v1 액세스 토큰(ADC) | `google-cloud-vision`(조각 1b 승인)이 이미 끌고 와 설치돼 있다. `import google.auth` 만 추가 |
| 백엔드 | **없음 — `httpx` 재사용** | FCM v1 `messages:send` POST | 이미 PostgREST 호출에 쓰는 것과 같은 클라이언트 |

**대안과 비교(왜 `firebase-admin` · `flutter_local_notifications` 를 안 쓰나)**

- 파이썬 `firebase-admin` 은 이 계획서가 쓰는 기능(토큰 1개에 알림 1건 전송)을 위해 새 의존성 트리를 통째로
  들여온다. 실제 필요한 건 **액세스 토큰 한 개 + POST 한 번**이라 이미 있는 `google-auth` + `httpx` 로 끝난다.
- `flutter_local_notifications` 는 **앱이 켜져 있을 때** 알림을 띄우려면 필요하다. 이번 조각은 앱이 켜져 있으면
  알림 배너 대신 **화면을 바로 갱신**한다(카드 화면 새로고침 · 대화 탭 수락 대기 갱신) — 그래서 넣지 않는다.
  앱이 꺼져 있거나 백그라운드일 때의 알림은 안드로이드 시스템이 `notification` 페이로드로 직접 띄워 준다.

**이 표 밖의 새 의존성이 실행 중 필요해지면 코드를 쓰기 전에 대장에게 보고한다**(사용자 승인 필요).

## Global Constraints

- **확정된 값은 아래 "확정 전제"가 전부다. 실행 중 다시 묻지 않는다.** 설계 문서 · ERD 와 다른 점이 보이면
  코드를 고치기 전에 대장에게 **차이만** 보고한다(이미 아는 차이 6건은 "실행 전 확인 사항"에 적혀 있다).
- **`google-services.json` 은 Task 0(.gitignore)이 끝나기 전에는 프로젝트 폴더로 옮기지 않는다.** 파일은
  바탕화면에 있고 경로는 대장이 안다. 커밋 이력에 한 번 들어가면 되돌릴 수 없다.
- **키 · URL · `service_role` 키 · FCM 자격증명을 저장소에 커밋하지 않는다.** 서버 비밀은 Secret Manager
  이름만 계획하고 값은 적지 않는다(`backend/DEPLOY.md` 방식).
- **쓰기는 전부 FastAPI 가 `service_role` 로 한다**(설계 §7.1 — 오늘의 카드 · 받은 수락함 모두 FastAPI 경유).
  클라이언트(`authenticated`)에 `daily_cards` · `card_decisions` · `acceptance_responses` · `push_tokens`
  권한 · 정책을 하나도 주지 않는다(`docs/ERD.md` §2).
- **새 테이블은 RLS 를 켜고, `revoke all ... from anon, authenticated, service_role` 뒤 필요한 것만 grant**
  한다(`docs/SUPABASE.md` §5). 읽기를 여는 곳은 ERD §2 표가 정한 3곳뿐이다 —
  `region_group_settings`(전체) · `matches`(당사자) · `match_participants` · `notification_settings`(본인 행).
- **새 함수는 `security definer` 를 쓰지 않고 `set search_path = ''` 를 반드시 건다.** 본문의 모든 식별자는
  `public.` · `extensions.` 로 수식한다(마이그레이션 `20260920061752` 가 advisor WARN 으로 지적받은 항목).
  RLS 정책의 `auth.uid()` 는 **`(select auth.uid())`** 형태로 쓴다(기존 정책과 같은 모양, initplan 최적화).
- **마이그레이션 파일명은 `supabase migration new <name>` 으로만 만든다.** **이미 클라우드에 적용된 마이그레이션
  파일은 절대 수정하지 않는다** — 새 파일만 추가한다(`match_candidates` 도 새 파일에서 `create or replace`).
- **클라우드 적용 금지.** Part C 는 파일 작성 + 로컬 스택(`supabase db reset`, `supabase test db`)까지다.
- **조각 3 의 `backend/app/matching/scoring.py` 를 고치지 않는다.** 활동성 계수 · 흡연 0.5 · 종교 0.8 은 거기에
  이미 있다 — `rank(owner, candidates)` 를 그대로 부른다. 계수를 다시 구현하면 두 곳이 갈라진다.
- **시간은 전부 `Asia/Seoul` 기준으로 판단한다.** DB 저장은 `timestamptz`(UTC), 요일 · 아침 7시 판정은
  `timezone('Asia/Seoul', now())` 또는 파이썬 `ZoneInfo("Asia/Seoul")` 로 변환한 뒤에 한다.
- **커밋 · PR 에 AI/도구 표식을 넣지 않는다**(`[[feedback-no-tool-attribution]]`). 커밋 형식은
  `<이모지> <타입>(<scope>): <한국어 요약>`, **`git add -A` 금지**(파일 이름으로만 스테이징).
- **화면은 pen 을 보고 만든다.** Part A 의 모든 화면 Task 는 작업 시작 전에 pencil MCP 로
  `filePath: "C:\\Users\\home\\OneDrive\\Desktop\\datingApp.pen"` 의 해당 노드를 **읽고** 시작한다.
  노드 id 는 각 Task 에 적혀 있다. pen 파일은 읽기만 한다(수정 금지).

## 확정 전제 (2026-09-19 · 2026-09-21 사용자 확정 — 다시 묻지 않는다)

```
지급 요일 사다리 (지역그룹 · 성별 각각 "14일 내 접속한 활성 사용자" 수로 판정, 둘 중 적은 쪽 기준)
    200명 미만   → 주 2회 (월 · 목)
    200명 이상   → 주 3회 (월 · 수 · 금)
    500명 이상   → 매일
  지급 시각 07:00 Asia/Seoul, 성별 무관 1장. 임계값 · 요일 · 시각은 region_group_settings 값으로 조정.

카드 무응답     → 다음 지급일 아침 7시에 자동 만료(expired). 거절이 아니다. 상대에게 아무 신호도 가지 않는다.
받은 수락함     → 수락을 받은 지 7일이 지나면 자동 만료. 역시 상대에게 신호 없음.
구매 카드       → 만료 없음(expires_at is null). 조각 7 에서 만든다.
재노출          → 무응답으로 만료된 상대만 다시 후보가 된다. 결정(수락 · 거절)한 상대는 영구 제외.
점수            → 조각 3 scoring.py 그대로(활동성 계수 · 흡연 0.5 · 종교 0.8 포함). 카드는 1위 1명.
하드 필터 추가  → matching_paused(일시중지) 제외 + 이미 카드로 받은 사람 제외. 차단(blocks)은 조각 6.
스케줄러        → Cloud Scheduler 1개 job → FastAPI /batch/daily-cards (아래 "실행 전 확인 사항" 1번 참조).
푸시            → FCM HTTP v1. 서버는 Cloud Run 서비스 계정(ADC)으로 보낸다.
```

## 실행 전 확인 사항 (코드 쓰기 전에 대장에게 보고 — 차이만)

1. **스케줄러를 `pg_cron` 이 아니라 Cloud Scheduler 로 택했다.** 설계 §2.1 은 "서버 배치(`pg_cron`)가
   생성한다"고 적혀 있다. 바꾼 이유 셋: ① 배치가 **푸시를 보내야 하는데** FCM 호출은 파이썬 쪽 일이라, pg_cron
   을 쓰면 `pg_net` 으로 FastAPI 를 한 번 더 불러야 해 부품이 하나 늘어난다. ② Cloud Scheduler 는 **재시도 ·
   실행 로그**가 기본이고 실패를 Cloud Logging 에서 바로 본다 — pg_cron 은 `cron.job_run_details` 를 직접 봐야
   한다. ③ **무료 한도 3 job** 안이라 비용이 0 이다. 요일 사다리 판정은 코드가 하므로 **job 은 매일 07:00
   하나**면 된다(요일마다 job 을 만들지 않는다).
2. **FCM 자격증명은 Secret Manager 에 넣지 않는다.** 대장 지시는 "서버 FCM 자격증명은 Secret Manager(이름만
   계획)"였지만, 바탕화면 준비 가이드(2026-09-20 완료분)가 **"FCM v1 사용 설정됨, 서버 키를 만들지 않는다 —
   Cloud Run 서버는 자기 계정으로 보낸다(Vision 과 같은 방식)"** 로 확정해 뒀다. 그래서 새 시크릿은 자격증명이
   아니라 **배치 엔드포인트 보호용 공유 비밀 `card-batch-secret` 하나**다(Cloud Run 이
   `--allow-unauthenticated` 라서 `/batch/*` 는 스스로를 지켜야 한다 — 조각 1a 의 auth hook 과 같은 이유).
3. **`region_group_settings` 에 임계값 컬럼 2개를 더 둔다.** ERD §3 그림은 `region_group` · `issue_weekdays`
   · `issue_time` · `updated_at` 4개다. 여기에 `ladder_three_per_week_min`(기본 200) ·
   `ladder_daily_min`(기본 500)을 더해, 사다리 임계값도 **배포 없이 대시보드에서** 바꿀 수 있게 한다.
   컬럼이 없으면 "200명 · 500명"이 파이썬 상수로 굳어 조정할 때마다 배포해야 한다.
   대신 `issue_weekdays` 는 **사다리가 계산해 채우는 결과값**이 된다(배치가 매일 갱신). 요일을 직접 정하는
   손잡이는 두지 않는다 — 같은 값을 정하는 손잡이가 둘이면 어느 쪽이 이겼는지 아무도 모르게 된다.
4. **재노출 금지 기간을 14일로 제안한다.** 설계 §2.4 는 "무응답 만료만 재노출 대상 복귀"라고만 쓰고 기간을
   정하지 않았다. 기간이 없으면 **무응답 상대가 바로 다음 지급일에 또 나온다**(점수 1위는 잘 안 바뀌므로 거의
   확실하다). 14일 = 주 2회 지급 기준 3~4번의 지급을 건너뛴다. `match_candidates` 의 `interval '14 days'`
   한 곳만 고치면 바뀐다.
5. **"남녀 각각 N명" 은 둘 중 적은 쪽으로 판정한다.** 남 300 · 여 150 이면 **150 기준(주 2회)** 이다. 카드가
   성별 무관 1장씩 나가므로 적은 쪽이 후보 풀의 병목이고, 많은 쪽에 맞추면 같은 사람이 계속 카드로 나간다.
6. **아침 7시 카드 알림은 조용한 시간(22~8시) 예외로 둔다.** `notification_settings.quiet_hours` 를 그대로
   적용하면 **지급 시각 07:00 이 조용한 시간 안이라 카드 도착 알림이 영영 안 간다**. 카드 도착 알림만 예외로
   보내고(사용자가 시간을 알고 기다리는 알림이다), 받은 수락 · 매칭 성사 · 그 밖의 알림은 조용한 시간을 지킨다.
   카드 알림 자체를 끄는 스위치는 `card_arrived` 로 따로 있다(화면 `NMgCa` 행 `WUdhM`).

**이름에 관한 메모(차이 아님):** 대장 지시문의 `card_responses/acceptances` · `fcm_tokens` 는 ERD §4 의
`card_decisions` · `acceptance_responses` · `push_tokens` 와 같은 것을 가리킨다. **ERD 이름을 쓴다**(ERD 가
기준 문서이고 조각 5 채팅이 같은 이름을 참조한다).

---

## 파일 구조

```
supabase/migrations/<ts>_create_region_group_settings.sql   C1  지급 설정 · matching_paused · 배치용 함수 2개
supabase/migrations/<ts>_create_daily_cards.sql             C2  enum 2종 · daily_cards · card_decisions · acceptance_responses
supabase/migrations/<ts>_create_matches.sql                 C3  matches · match_participants
supabase/migrations/<ts>_create_push_tokens.sql             C4  device_platform enum · push_tokens · notification_settings
supabase/migrations/<ts>_update_match_candidates_slice4.sql C5  하드 필터 3줄 추가(create or replace)
supabase/tests/rls_slice4_test.sql                          C6  pgTAP

backend/app/cards/__init__.py
backend/app/cards/ladder.py        B1  요일 사다리 판정(순수 함수)
backend/app/cards/repository.py    B2  PostgREST 접근 한 곳
backend/app/cards/issuing.py       B3  지급 배치 본체
backend/app/cards/push.py          B4  FCM v1 전송
backend/app/cards/batch_router.py  B3  POST /batch/daily-cards (공유 비밀)
backend/app/cards/router.py        B5·B6·B7  사용자 엔드포인트
backend/app/settings.py            B3  card_batch_secret 추가
backend/app/main.py                B3  라우터 등록
backend/DEPLOY.md                  B8  Cloud Scheduler · 시크릿 · IAM 문서

frontend/lib/matching/model/        A2  카드 모델 · Repository · Provider
frontend/lib/matching/viewmodel/    A2  UiState · ViewModel
frontend/lib/matching/view/         A3~A6  화면
frontend/lib/core/push/             A7  FCM 초기화 · 토큰 등록 · 수신 처리
frontend/lib/core/router/           A3  경로 추가
```

**PR 은 Part 마다 하나씩 3개**(조각 2 · 3 과 같은 방식). 전부 base `main` 의 **draft** 로 열고 merge 는
사용자가 한다. Task 0 은 Part C PR 의 첫 커밋으로 넣는다.

---

## Task 0: `google-services.json` 을 git 에서 먼저 막는다

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: `.gitignore` 에 `**/google-services.json` — Task A1 이 파일을 옮기기 전에 반드시 끝나 있어야 한다.

- [ ] **Step 1: 지금 저장소에 그 파일이 없는지부터 확인**

```bash
git ls-files | grep -i google-services || echo "추적 안 됨 — 계속 진행"
ls frontend/android/app/google-services.json 2>/dev/null || echo "아직 안 옮김 — 정상"
```

둘 중 하나라도 파일이 있다고 나오면 **멈추고 대장에게 보고한다**(이미 커밋됐다면 이력 처리가 필요하다).

- [ ] **Step 2: `.gitignore` 에 두 줄 추가**

`.gitignore` 맨 아래에:

```gitignore
# Firebase 앱 설정 파일 — 프로젝트 식별자가 들어 있어 저장소에 올리지 않는다(조각 4).
**/google-services.json
**/GoogleService-Info.plist
```

- [ ] **Step 3: 규칙이 실제로 먹는지 확인**

```bash
mkdir -p frontend/android/app && echo "{}" > frontend/android/app/google-services.json
git status --porcelain frontend/android/app/google-services.json   # 아무것도 안 나와야 한다
git check-ignore -v frontend/android/app/google-services.json      # .gitignore 규칙 줄이 나와야 한다
rm frontend/android/app/google-services.json
```

- [ ] **Step 4: 커밋**

```bash
git add .gitignore
git commit -m "🙈 chore(slice4): Firebase 앱 설정 파일을 git 에서 제외한다"
```

---

## Part C: Supabase 마이그레이션 (파일 작성 + 로컬 검증까지, 클라우드 적용 금지)

### Task C1: 지급 설정 테이블 · 일시중지 컬럼 · 배치용 함수 2개

**Files:**
- Create: `supabase/migrations/<timestamp>_create_region_group_settings.sql`
  (`supabase migration new create_region_group_settings`)

**Interfaces:**
- Produces: 테이블 `public.region_group_settings(region_group text pk, issue_weekdays smallint[],
  issue_time time, ladder_three_per_week_min int, ladder_daily_min int, updated_at timestamptz)`
- Produces: 컬럼 `public.profiles.matching_paused boolean not null default false` — Task C5 · B7 이 쓴다.
- Produces: 함수 `public.region_active_counts()` → `(region_group text, gender public.gender,
  active_count bigint)` — Task B3 이 사다리 판정에 쓴다.
- Produces: 함수 `public.card_issue_owners()` → `(profile_id uuid, region_group text)` — Task B3 이
  지급 대상 목록으로 쓴다.

- [ ] **Step 1: 마이그레이션 파일 만들기**

```bash
supabase migration new create_region_group_settings
```

- [ ] **Step 2: 테이블 · 컬럼 · 시드 · FK 를 한 파일에 쓴다**

```sql
-- 조각 4: 지역그룹별 카드 지급 주기(설계 §2.1). 주기를 바꾸는 손잡이는 전부 이 테이블 행에 있다 —
-- 배포 없이 대시보드에서 값만 고치면 다음 배치부터 적용된다.
create table public.region_group_settings (
  region_group text primary key,
  -- ISO 요일(1=월 … 7=일). 기본은 사다리 아래칸(주 2회 · 월 · 목)이다.
  -- **이 값은 배치가 사다리로 계산해 갱신하는 결과값이다**(Task B3) — 앱이 "다음 지급은 O요일" 문구를
  -- 그리는 재료이기도 하다. 요일을 바꾸고 싶으면 아래 임계값을 조정한다(손으로 고친 요일은 다음 배치가 덮는다).
  issue_weekdays smallint[] not null default array[1, 4]::smallint[],
  issue_time time not null default '07:00',            -- Asia/Seoul 기준
  -- 사다리 임계값(2026-09-19 사용자 확정 값이 기본). 남녀 중 적은 쪽 활성 인원과 비교한다.
  ladder_three_per_week_min integer not null default 200,
  ladder_daily_min integer not null default 500,
  updated_at timestamptz not null default now(),

  constraint region_group_settings_weekdays_valid check (
    issue_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    and cardinality(issue_weekdays) between 1 and 7
  ),
  constraint region_group_settings_ladder_order check (
    ladder_daily_min >= ladder_three_per_week_min
  )
);

comment on table public.region_group_settings is
  '지역그룹별 카드 지급 요일·시각·사다리 임계값(설계 §2.1). 값만 바꿔 주기를 조정한다';

-- 설계 §2.6 매칭 일시중지 토글: 새 카드 배치 대상에서 빠지고, 남의 후보에서도 빠진다(Task C5).
alter table public.profiles
  add column matching_paused boolean not null default false;

comment on column public.profiles.matching_paused is
  '매칭 일시중지(설계 §2.6). true 면 카드를 받지도, 남의 후보로 나오지도 않는다';

-- FK 를 걸기 전에 지금 존재하는 지역그룹의 행을 먼저 만든다(ERD §3 주석).
-- 첫 출시는 'seoul' 뿐이지만, 시드에 다른 값이 있어도 빠짐없이 들어가게 distinct 로 넣는다.
insert into public.region_group_settings (region_group)
values ('seoul')
on conflict (region_group) do nothing;

insert into public.region_group_settings (region_group)
select distinct u.region_group from public.universities u
on conflict (region_group) do nothing;

alter table public.universities
  add constraint universities_region_group_fkey
  foreign key (region_group) references public.region_group_settings (region_group);

-- FK 컬럼 인덱스(advisor WARN 방지 — 20260920061752 에서 지적받은 항목).
create index universities_region_group_index on public.universities (region_group);

alter table public.region_group_settings enable row level security;

-- ERD §2: authenticated 전체 읽기 — "다음 지급은 O요일 오전 7시" 문구(DESIGN §8.1 Badge Row)를 그리려면
-- 앱이 요일·시각을 알아야 한다. 개인정보가 아니라 지역 단위 설정값이라 소유자 조건이 없다.
create policy "region group settings are readable by signed in users"
  on public.region_group_settings
  for select
  to authenticated
  using (true);

revoke all on table public.region_group_settings from anon, authenticated, service_role;
grant select on table public.region_group_settings to authenticated;
grant select, insert, update, delete on table public.region_group_settings to service_role;

-- 사다리 판정 재료: 지역그룹 × 성별 활성 인원(14일 내 접속). 일시중지는 빼고 센다 —
-- 카드를 주고받을 수 없는 사람은 풀의 두께가 아니다.
create or replace function public.region_active_counts()
returns table (region_group text, gender public.gender, active_count bigint)
language sql
stable
set search_path = ''
as $$
  select u.region_group, p.gender, count(*)
  from public.profiles p
  join public.universities u on u.id = p.university_id
  where p.status = 'active'
    and not p.matching_paused
    and p.gender is not null
    and p.last_active_at > now() - interval '14 days'
  group by u.region_group, p.gender;
$$;

comment on function public.region_active_counts() is
  '지역그룹×성별 활성 인원(14일). 지급 주기 사다리 판정용(설계 §2.1)';

-- 오늘 카드를 받을 자격이 있는 사람들. 아직 답하지 않은 무료 카드가 살아 있으면 대상이 아니다 —
-- 지급 시각(07:00)에 직전 카드의 expires_at 이 지나므로, 무응답 카드는 이 시점에 자연히 만료다(설계 §2.4).
create or replace function public.card_issue_owners()
returns table (profile_id uuid, region_group text)
language sql
stable
set search_path = ''
as $$
  select p.id, u.region_group
  from public.profiles p
  join public.universities u on u.id = p.university_id
  join public.profile_vectors v on v.profile_id = p.id
  where p.status = 'active'
    and not p.matching_paused
    and p.last_active_at > now() - interval '14 days'
    and v.self_survey is not null
    and v.self_embedding is not null
    and v.want_embedding is not null
    and not exists (
      select 1
      from public.daily_cards dc
      left join public.card_decisions cd on cd.card_id = dc.id
      where dc.owner_id = p.id
        and dc.source = 'daily'
        and cd.card_id is null
        and dc.expires_at > now()
    );
$$;

comment on function public.card_issue_owners() is
  '오늘 무료 카드를 받을 자격이 있는 사람과 그 지역그룹(설계 §2.1·§2.6)';

revoke all on function public.region_active_counts() from public, anon, authenticated;
grant execute on function public.region_active_counts() to service_role;
revoke all on function public.card_issue_owners() from public, anon, authenticated;
grant execute on function public.card_issue_owners() to service_role;
```

> **주의:** 이 파일은 Task C2 의 `daily_cards` · `card_decisions` 를 참조한다. **마이그레이션 파일명 타임스탬프가
> C2 보다 빠르면 `supabase db reset` 이 깨진다.** `card_issue_owners` 만 C2 마이그레이션 끝으로 옮기거나,
> C2 를 먼저 만들고 C1 을 그 뒤 타임스탬프로 만든다. **권장: Step 1 을 C2 → C1 순서로 실행한다**(파일 이름의
> 시각이 순서다). 아래 Step 3 의 `supabase db reset` 이 이 실수를 바로 잡아 준다.

- [ ] **Step 3: 로컬 스택에서 적용해 본다**

```bash
supabase db reset
```

Expected: 오류 없이 끝난다. `relation "public.daily_cards" does not exist` 가 나오면 위 주의문대로
파일 순서를 고친다(새 파일명으로 다시 만들고 옛 파일은 지운다 — 아직 클라우드에 없으니 자유롭다).

- [ ] **Step 4: 시드 · FK 가 들어갔는지 눈으로 확인**

```bash
supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" \
  -c "select * from public.region_group_settings;" \
  -c "select conname from pg_constraint where conname = 'universities_region_group_fkey';"
```

Expected: `seoul` 행 1개 이상, FK 이름 1행.

- [ ] **Step 5: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_region_group_settings.sql
git commit -m "✨ feat(slice4): 지역그룹 지급 설정과 매칭 일시중지 컬럼 추가"
```

### Task C2: 카드 테이블 3종 (`daily_cards` · `card_decisions` · `acceptance_responses`)

**Files:**
- Create: `supabase/migrations/<timestamp>_create_daily_cards.sql`
  (`supabase migration new create_daily_cards`) — **타임스탬프가 C1 보다 앞서야 한다**

**Interfaces:**
- Produces: enum `public.card_source('daily','purchased')` · `public.card_decision('accept','reject')`
- Produces: `public.daily_cards(id uuid pk, owner_id uuid, target_id uuid, source public.card_source,
  issued_at timestamptz, expires_at timestamptz null)` — Task B2~B6 이 이 이름을 그대로 쓴다.
- Produces: `public.card_decisions(card_id uuid pk, decision public.card_decision, decided_at timestamptz)`
- Produces: `public.acceptance_responses(card_id uuid pk, responder_id uuid, decision public.card_decision,
  decided_at timestamptz)`

- [ ] **Step 1: 마이그레이션 파일 만들기**

```bash
supabase migration new create_daily_cards
```

- [ ] **Step 2: 테이블 3종을 쓴다**

```sql
-- 조각 4: 카드 지급과 결정(설계 §2.1·§2.2·§2.4, ERD §4).
create type public.card_source as enum ('daily', 'purchased');
create type public.card_decision as enum ('accept', 'reject');

create table public.daily_cards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  source public.card_source not null default 'daily',
  issued_at timestamptz not null default now(),
  -- daily 는 "다음 지급일 07:00", purchased 는 null(만료 없음, 설계 §2.4).
  expires_at timestamptz,

  constraint daily_cards_not_self check (owner_id <> target_id),
  constraint daily_cards_purchased_never_expires check (
    source <> 'purchased' or expires_at is null
  ),
  constraint daily_cards_daily_has_expiry check (
    source <> 'daily' or expires_at is not null
  )
);

comment on table public.daily_cards is
  '지급된 카드 한 장(설계 §2.1). 무응답 만료는 행을 쓰지 않고 expires_at 으로 판정한다';

-- (owner_id, target_id) 는 unique 가 아니다 — 무응답으로 만료된 상대는 다시 나올 수 있다(ERD §4).
create index daily_cards_owner_target_index on public.daily_cards (owner_id, target_id);
create index daily_cards_owner_issued_index on public.daily_cards (owner_id, issued_at desc);
create index daily_cards_target_index on public.daily_cards (target_id);

create table public.card_decisions (
  card_id uuid primary key references public.daily_cards (id) on delete cascade,
  decision public.card_decision not null,
  decided_at timestamptz not null default now()
);

comment on table public.card_decisions is
  '카드를 받은 사람의 결정(설계 §2.2). 행이 없으면 아직 무응답이다';

-- 받은 수락함 조회가 "최근 7일 안에 수락된 카드"를 시간으로 훑는다(Task B6).
create index card_decisions_decided_at_index on public.card_decisions (decided_at desc)
  where decision = 'accept';

create table public.acceptance_responses (
  card_id uuid primary key references public.daily_cards (id) on delete cascade,
  responder_id uuid not null references public.profiles (id) on delete cascade,
  decision public.card_decision not null,
  decided_at timestamptz not null default now()
);

comment on table public.acceptance_responses is
  '수락을 받은 사람(카드의 target)의 응답(설계 §2.2). 행이 없고 7일이 지나면 만료다';

create index acceptance_responses_responder_index on public.acceptance_responses (responder_id);

-- RLS: 세 테이블 모두 정책을 하나도 만들지 않는다 = authenticated 는 전부 막힌다(ERD §2 "읽기 없음").
-- 오늘의 카드·받은 수락함은 FastAPI 가 service_role 로 읽어 내려준다(설계 §7.1).
alter table public.daily_cards enable row level security;
alter table public.card_decisions enable row level security;
alter table public.acceptance_responses enable row level security;

revoke all on table public.daily_cards, public.card_decisions, public.acceptance_responses
  from anon, authenticated, service_role;
grant select, insert, update, delete
  on table public.daily_cards, public.card_decisions, public.acceptance_responses
  to service_role;
```

- [ ] **Step 3: 로컬 적용**

```bash
supabase db reset
```

Expected: 오류 없음.

- [ ] **Step 4: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_daily_cards.sql
git commit -m "✨ feat(slice4): 카드 지급·결정·수락 응답 테이블 추가"
```

### Task C3: `matches` · `match_participants`

**Files:**
- Create: `supabase/migrations/<timestamp>_create_matches.sql` (`supabase migration new create_matches`)

**Interfaces:**
- Produces: `public.matches(id uuid pk, profile_a uuid, profile_b uuid, created_at timestamptz,
  trust_passed_at timestamptz null, chat_closed_at timestamptz null)` — `profile_a < profile_b` 강제.
  Task B6 이 매칭을 만들고, 조각 5 채팅이 그대로 읽는다.
- Produces: `public.match_participants(match_id uuid, profile_id uuid, trust_response public.card_decision
  null, responded_at timestamptz null, left_at timestamptz null, last_read_at timestamptz null)` — pk 는
  `(match_id, profile_id)`.

- [ ] **Step 1: 마이그레이션 파일 만들기**

```bash
supabase migration new create_matches
```

- [ ] **Step 2: 두 테이블을 쓴다**

```sql
-- 조각 4~5: 쌍방 수락으로 성립한 매칭(설계 §2.2, ERD §4). 신뢰 게이트·채팅은 조각 5 가 이어서 쓴다.
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  profile_a uuid not null references public.profiles (id) on delete cascade,
  profile_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  trust_passed_at timestamptz,   -- 조각 5: 쌍방 카톡 아이디 공유가 끝난 시각
  chat_closed_at timestamptz,    -- 조각 5: 대화가 닫힌 시각

  -- 같은 두 사람의 매칭이 두 행이 되지 않게 순서를 고정한다(ERD §4).
  constraint matches_pair_order check (profile_a < profile_b),
  constraint matches_pair_unique unique (profile_a, profile_b)
);

comment on table public.matches is
  '쌍방 수락으로 성립한 매칭(설계 §2.2). 항상 profile_a < profile_b 로 저장한다';

create index matches_profile_b_index on public.matches (profile_b);

create table public.match_participants (
  match_id uuid not null references public.matches (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  trust_response public.card_decision,   -- 조각 5: 카톡 아이디 공유 수락/거절
  responded_at timestamptz,
  left_at timestamptz,
  last_read_at timestamptz,

  primary key (match_id, profile_id)
);

comment on table public.match_participants is
  '매칭 당사자 두 행(ERD §4). 신뢰 게이트 응답·읽음 시각은 조각 5 가 채운다';

create index match_participants_profile_index on public.match_participants (profile_id);

alter table public.matches enable row level security;
alter table public.match_participants enable row level security;

-- ERD §2: matches 는 당사자만, match_participants 는 본인 행만 읽는다.
-- 쓰기는 FastAPI(service_role) 전용이라 insert·update 정책은 두지 않는다.
create policy "matches are readable by participants"
  on public.matches
  for select
  to authenticated
  using ((select auth.uid()) in (profile_a, profile_b));

create policy "match participants rows are readable by owner"
  on public.match_participants
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.matches, public.match_participants
  from anon, authenticated, service_role;
grant select on table public.matches, public.match_participants to authenticated;
grant select, insert, update, delete on table public.matches, public.match_participants to service_role;
```

- [ ] **Step 3: 순서 제약이 실제로 막는지 손으로 확인**

```bash
supabase db reset
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -c \
  "insert into public.matches (profile_a, profile_b)
   values ('00000000-0000-0000-0000-0000000000bb','00000000-0000-0000-0000-0000000000aa');"
```

Expected: `new row for relation "matches" violates check constraint "matches_pair_order"`
(프로필 행이 없어 FK 오류가 먼저 날 수도 있다 — 그러면 이 확인은 Task C6 의 pgTAP 에 맡기고 넘어간다).

- [ ] **Step 4: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_matches.sql
git commit -m "✨ feat(slice4): 매칭과 매칭 참가자 테이블 추가"
```

### Task C4: `push_tokens` · `notification_settings`

**Files:**
- Create: `supabase/migrations/<timestamp>_create_push_tokens.sql`
  (`supabase migration new create_push_tokens`)

**Interfaces:**
- Produces: enum `public.device_platform('android','ios')`
- Produces: `public.push_tokens(token text pk, profile_id uuid, platform public.device_platform,
  updated_at timestamptz)` — Task B4 가 읽고 Task B7 이 쓴다.
- Produces: `public.notification_settings(profile_id uuid pk, card_arrived, acceptance_received,
  match_made, new_message, trust_reminder, new_friend_review, marketing, marketing_consented_at,
  quiet_hours)` — boolean 7개 + timestamptz 1개.

- [ ] **Step 1: 마이그레이션 파일 만들기**

```bash
supabase migration new create_push_tokens
```

- [ ] **Step 2: 두 테이블을 쓴다**

```sql
-- 조각 4: FCM 토큰과 알림 스위치(ERD §4, 화면 16d `NMgCa`).
create type public.device_platform as enum ('android', 'ios');

-- 토큰이 PK 다 — 같은 기기를 다른 계정으로 로그인하면 토큰의 주인만 바뀐다(중복 행이 생기지 않는다).
create table public.push_tokens (
  token text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  platform public.device_platform not null,
  updated_at timestamptz not null default now()
);

comment on table public.push_tokens is
  'FCM 등록 토큰(ERD §4). 탈퇴 시 cascade 로 즉시 지워진다. 클라이언트 읽기 권한 없음';

create index push_tokens_profile_index on public.push_tokens (profile_id);

create table public.notification_settings (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  card_arrived boolean not null default true,
  acceptance_received boolean not null default true,
  match_made boolean not null default true,
  new_message boolean not null default true,        -- 조각 5
  trust_reminder boolean not null default true,     -- 조각 5
  new_friend_review boolean not null default true,  -- 조각 6
  marketing boolean not null default false,
  marketing_consented_at timestamptz,
  -- 22시~8시 알림 보류. 단, 아침 7시 카드 도착 알림은 예외다(계획서 "실행 전 확인 사항" 6번).
  quiet_hours boolean not null default true
);

comment on table public.notification_settings is
  '알림 스위치(화면 16d). 행이 없으면 전부 기본값(마케팅만 false)으로 본다';

alter table public.push_tokens enable row level security;
alter table public.notification_settings enable row level security;

-- push_tokens: 정책 없음 = 클라이언트는 자기 토큰도 못 읽는다(ERD §2 "읽기 없음"). 등록은 FastAPI 경유.
create policy "notification settings are readable by owner"
  on public.notification_settings
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.push_tokens, public.notification_settings
  from anon, authenticated, service_role;
grant select on table public.notification_settings to authenticated;
grant select, insert, update, delete on table public.push_tokens, public.notification_settings
  to service_role;
```

- [ ] **Step 3: 로컬 적용**

```bash
supabase db reset
```

Expected: 오류 없음.

- [ ] **Step 4: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_push_tokens.sql
git commit -m "✨ feat(slice4): 푸시 토큰과 알림 설정 테이블 추가"
```

### Task C5: `match_candidates` 에 조각 4 하드 필터를 넣는다

**Files:**
- Create: `supabase/migrations/<timestamp>_update_match_candidates_slice4.sql`
  (`supabase migration new update_match_candidates_slice4`)
- Read only (수정 금지): `supabase/migrations/20260920101730_create_match_candidates.sql`

**Interfaces:**
- Consumes: Task C1 `profiles.matching_paused`, Task C2 `daily_cards` · `card_decisions` ·
  `acceptance_responses`, Task C3 `matches`
- Produces: 같은 시그니처의 `public.match_candidates(p_owner uuid)` — 반환 컬럼은 하나도 바뀌지 않는다.
  Task B3(지급 배치)과 조각 3 의 `/matching/candidates` 가 그대로 쓴다.

**주의:** `20260920101730` 파일은 **이미 클라우드에 적용됐다 — 열어서 베끼기만 하고 고치지 않는다.**
새 파일에서 함수 전체를 `create or replace` 로 다시 쓴다(where 절 4줄만 늘어난다).

- [ ] **Step 1: 옛 함수 본문을 새 파일로 그대로 옮긴다**

```bash
supabase migration new update_match_candidates_slice4
# 20260920101730_create_match_candidates.sql 의 create or replace function public.match_candidates ...
# 부분을 통째로 복사해 새 파일에 붙인다(주석 포함). jaccard 함수는 그대로 두고 건드리지 않는다.
```

- [ ] **Step 2: where 절에 조각 4 조건 4개를 넣는다**

기존 `where` 절 맨 끝(`and cv.want_embedding is not null` 다음)에 이어 붙인다:

```sql
    -- 조각 4 ---------------------------------------------------------------
    and not c.matching_paused                                  -- 일시중지(설계 §2.6)
    -- 이미 카드로 받은 사람(설계 §6.7). 세 가지를 한 번에 본다:
    --   ① 결정을 내린 카드 → 영구 제외(거절한 상대는 다시 안 나온다, 설계 §2.1)
    --   ② 아직 살아 있는 카드 → 중복 지급 방지(구매 카드는 expires_at is null 이라 항상 여기 걸린다)
    --   ③ 무응답으로 만료된 카드 → 만료 후 14일은 쉬어 간다(재노출 금지 기간, 계획서 "실행 전 확인" 4번)
    and not exists (
      select 1
      from public.daily_cards dc
      left join public.card_decisions cd on cd.card_id = dc.id
      where dc.owner_id = me.id
        and dc.target_id = c.id
        and (
          cd.card_id is not null
          or dc.expires_at is null
          or dc.expires_at > now()
          or dc.expires_at > now() - interval '14 days'
        )
    )
    -- 내가 수락 응답을 한 상대(= 내가 수락을 받았던 상대)도 다시 나오지 않는다(설계 §6.7)
    and not exists (
      select 1
      from public.acceptance_responses ar
      join public.daily_cards dc2 on dc2.id = ar.card_id
      where ar.responder_id = me.id
        and dc2.owner_id = c.id
    )
    -- 이미 매칭된 상대(설계 §6.7)
    and not exists (
      select 1
      from public.matches m
      where m.profile_a = least(me.id, c.id)
        and m.profile_b = greatest(me.id, c.id)
    )
```

파일 맨 위 주석의 "조각 4에서 추가할 조건" 안내는 지우고, 남은 "조각 6에서 추가할 조건"(blocks)은 그대로 둔다.
`revoke`/`grant` 두 줄도 새 파일 끝에 다시 넣는다(`create or replace` 는 권한을 유지하지만, 파일 하나만 봐도
권한이 보이게 반복한다 — 조각 3 파일과 같은 모양).

- [ ] **Step 3: 로컬 적용**

```bash
supabase db reset
```

Expected: 오류 없음. 동작 검증은 Task C6 pgTAP 가 한다.

- [ ] **Step 4: 커밋**

```bash
git add supabase/migrations/<timestamp>_update_match_candidates_slice4.sql
git commit -m "✨ feat(slice4): 일시중지·이미 받은 카드를 후보에서 제외한다"
```

### Task C6: pgTAP 회귀 테스트

**Files:**
- Create: `supabase/tests/rls_slice4_test.sql`
- Read only (본보기): `supabase/tests/rls_slice3_test.sql`

**Interfaces:**
- Consumes: Task C1~C5 의 테이블 · 함수 전부
- Produces: `supabase test db` 로 도는 회귀 테스트 18건

- [ ] **Step 1: 테스트 파일을 쓴다(먼저 실패하는 채로)**

```sql
-- 조각 4 RLS · 권한 · 하드 필터 검증. 기대값 기준은 docs/ERD.md §2 와 설계 §2.1·§2.4·§6.7.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- 준비 --------------------------------------------------------------------
-- A = ...aa(남), B = ...bb(여), P = ...pp(여·일시중지), Q = ...qq(여·무응답 만료 3일 전),
-- R = ...rr(여·무응답 만료 20일 전 → 다시 후보), S = ...ss(여·이미 거절한 상대)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'm4-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'm4-b@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000pp', 'm4-p@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000qq', 'm4-q@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000rr', 'm4-r@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000ss', 'm4-s@test.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000001' from auth.users
on conflict (id) do nothing;

update public.profiles set
  nickname = '가나다', gender = 'male', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['활발한'],
  height_cm = 180, birth_year = 2002, mbti = 'ENFP', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000aa';

update public.profiles set
  nickname = '라마바', gender = 'female', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['활발한'], ideal_traits = array['다정한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id <> '00000000-0000-0000-0000-0000000000aa';

update public.profiles set nickname = '사아자' where id = '00000000-0000-0000-0000-0000000000pp';
update public.profiles set nickname = '차카타' where id = '00000000-0000-0000-0000-0000000000qq';
update public.profiles set nickname = '파하거' where id = '00000000-0000-0000-0000-0000000000rr';
update public.profiles set nickname = '너더러' where id = '00000000-0000-0000-0000-0000000000ss';

-- 일시중지한 사람
update public.profiles set matching_paused = true where id = '00000000-0000-0000-0000-0000000000pp';

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles;

-- A 가 받았던 카드들
insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at) values
  -- Q: 3일 전 만료, 무응답 → 재노출 금지 기간(14일) 안이라 아직 후보가 아니다
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000qq', 'daily', now() - interval '6 days', now() - interval '3 days'),
  -- R: 20일 전 만료, 무응답 → 다시 후보가 된다
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000rr', 'daily', now() - interval '23 days', now() - interval '20 days'),
  -- S: 거절한 상대 → 영구 제외
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000ss', 'daily', now() - interval '30 days', now() - interval '27 days');

insert into public.card_decisions (card_id, decision)
values ('00000000-0000-0000-0000-00000000c003', 'reject');

-- 1. 구조 · 제약 -------------------------------------------------------------
select has_table('public', 'daily_cards', 'daily_cards 테이블이 있다');
select has_table('public', 'region_group_settings', 'region_group_settings 테이블이 있다');
select has_column('public', 'profiles', 'matching_paused', 'profiles 에 일시중지 컬럼이 있다');

select is(
  (select count(*) from public.region_group_settings where region_group = 'seoul'),
  1::bigint, 'seoul 설정 행이 시드로 들어 있다'
);

select throws_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, expires_at)
    values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000aa',
            'daily', now() + interval '1 day')$$,
  '23514', null, '자기 자신은 카드가 되지 않는다'
);

select throws_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, expires_at)
    values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000bb',
            'purchased', now() + interval '1 day')$$,
  '23514', null, '구매 카드는 만료 시각을 가질 수 없다'
);

select throws_ok(
  $$insert into public.matches (profile_a, profile_b)
    values ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000aa')$$,
  '23514', null, '매칭은 항상 작은 uuid 가 profile_a 다'
);

-- 2. RLS · 권한 --------------------------------------------------------------
select is(
  (select count(*) from pg_policies where tablename = 'daily_cards'),
  0::bigint, 'daily_cards 에는 정책이 하나도 없다(FastAPI 전용)'
);

select ok(
  not has_table_privilege('authenticated', 'public.daily_cards', 'select'),
  'authenticated 는 daily_cards 를 읽지 못한다'
);

select ok(
  not has_table_privilege('authenticated', 'public.push_tokens', 'select'),
  'authenticated 는 push_tokens 를 읽지 못한다'
);

select ok(
  has_table_privilege('authenticated', 'public.region_group_settings', 'select'),
  'authenticated 는 지급 주기 설정을 읽는다(다음 지급 시각 표시)'
);

select ok(
  has_table_privilege('authenticated', 'public.matches', 'select'),
  'authenticated 는 matches 를 읽는다(정책이 당사자로 좁힌다)'
);

select is(
  (select count(*) from pg_policies where tablename = 'matches'),
  1::bigint, 'matches 에는 당사자 읽기 정책 하나만 있다'
);

select ok(
  not has_function_privilege('authenticated', 'public.card_issue_owners()', 'execute'),
  'authenticated 는 지급 대상 목록 함수를 부르지 못한다'
);

-- 3. 하드 필터(설계 §6.7 · §2.4) ---------------------------------------------
select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000pp'),
  0::bigint, '매칭을 일시중지한 사람은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000ss'),
  0::bigint, '거절한 상대는 다시 후보가 되지 않는다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000qq'),
  0::bigint, '무응답 만료 뒤 14일이 지나지 않은 상대는 아직 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000rr'),
  1::bigint, '무응답 만료 뒤 14일이 지난 상대는 다시 후보가 된다'
);

-- 4. 지급 대상 함수 -----------------------------------------------------------
select is(
  (select count(*) from public.card_issue_owners()
    where profile_id = '00000000-0000-0000-0000-0000000000pp'),
  0::bigint, '일시중지한 사람은 카드를 받지 않는다'
);

select * from finish();
rollback;
```

- [ ] **Step 2: 돌려서 18건이 다 통과하는지 본다**

```bash
supabase db reset && supabase test db
```

Expected: `rls_slice4_test.sql .. ok`, 18/18. 실패하면 마이그레이션(C1~C5)을 고친다 — **테스트의 기대값을
고쳐 통과시키지 않는다**(기대값의 근거는 ERD §2 와 설계 §6.7 이다).

- [ ] **Step 3: 조각 0~3 테스트가 같이 통과하는지 확인**

```bash
supabase test db
```

Expected: 기존 `rls_slice0_test.sql` · `rls_slice3_test.sql` 도 전부 ok. `matching_paused` 컬럼이 늘어난
탓에 조각 3 하드 필터 테스트가 깨지면(기본값 false 라 깨지지 않아야 한다) 원인을 찾아 마이그레이션을 고친다.

- [ ] **Step 4: 커밋 + Part C PR**

```bash
git add supabase/tests/rls_slice4_test.sql
git commit -m "✅ test(slice4): 지급 설정·카드 하드 필터를 pgTAP 으로 못박는다"
git push -u origin feat/slice4-part-c-schema
gh pr create --draft --base main --title "조각 4 Part C: 카드·매칭·알림 스키마" --body "..."
```

PR 본문에 **"클라우드 미적용 — ERD 그림 · 사용자 승인 후 supabase 세션이 적용한다"** 를 적는다.
**PR 본문 · 커밋에 AI/도구 표식을 넣지 않는다.**

---

## Part B: FastAPI (`backend/app/cards/`)

조각 3 의 `backend/app/matching/` 는 **그대로 쓰고 고치지 않는다.** `MatchingRepository.fetch_owner` ·
`fetch_candidates` · `scoring.rank` 를 불러 쓴다.

### Task B1: 지급 요일 사다리 (순수 함수)

**Files:**
- Create: `backend/app/cards/__init__.py` (빈 파일)
- Create: `backend/app/cards/ladder.py`
- Test: `backend/tests/cards/test_ladder.py`

**Interfaces:**
- Produces: `ladder_weekdays(active_count: int, three_per_week_min: int, daily_min: int) -> list[int]`
- Produces: `bottleneck_count(counts: dict[str, int]) -> int` — `{"male": 300, "female": 150}` → `150`
- Produces: `next_issue_at(now: datetime, weekdays: Sequence[int], issue_time: time) -> datetime`
  — 오늘 이후 가장 가까운 지급 시각(카드 `expires_at` 이자 화면의 "다음 지급" 문구 재료)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
# backend/tests/cards/test_ladder.py
from datetime import datetime, time
from zoneinfo import ZoneInfo

from app.cards.ladder import bottleneck_count, ladder_weekdays, next_issue_at

SEOUL = ZoneInfo("Asia/Seoul")


def test_under_two_hundred_is_twice_a_week():
    assert ladder_weekdays(199, 200, 500) == [1, 4]


def test_two_hundred_is_three_times_a_week():
    assert ladder_weekdays(200, 200, 500) == [1, 3, 5]
    assert ladder_weekdays(499, 200, 500) == [1, 3, 5]


def test_five_hundred_is_every_day():
    assert ladder_weekdays(500, 200, 500) == [1, 2, 3, 4, 5, 6, 7]


def test_bottleneck_is_the_smaller_side():
    """남녀 각각 세고 적은 쪽으로 판정한다(2026-09-21 확정) — 많은 쪽에 맞추면 같은 사람이 계속 나온다."""
    assert bottleneck_count({"male": 300, "female": 150}) == 150


def test_missing_gender_counts_as_zero():
    assert bottleneck_count({"male": 300}) == 0


def test_next_issue_at_is_the_next_listed_weekday():
    monday_7am = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)  # 2026-09-21 은 월요일
    assert next_issue_at(monday_7am, [1, 4], time(7, 0)) == datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)


def test_next_issue_at_skips_today_even_when_today_is_an_issue_day():
    """오늘 07:00 지급 직후에 부르는 함수다 — 오늘이 또 나오면 카드가 즉시 만료된다."""
    monday_7am = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
    assert next_issue_at(monday_7am, [1, 2, 3, 4, 5, 6, 7], time(7, 0)).day == 22
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `cd backend && python -m pytest tests/cards/test_ladder.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.cards'`

- [ ] **Step 3: 최소 구현**

```python
# backend/app/cards/ladder.py
from collections.abc import Sequence
from datetime import datetime, time, timedelta

# 설계 §2.1 + 2026-09-21 사용자 확정. ISO 요일(1=월 … 7=일).
TWICE_A_WEEK = [1, 4]        # 월 · 목
THREE_TIMES_A_WEEK = [1, 3, 5]  # 월 · 수 · 금
EVERY_DAY = [1, 2, 3, 4, 5, 6, 7]


def ladder_weekdays(active_count: int, three_per_week_min: int, daily_min: int) -> list[int]:
    """활성 인원이 많을수록 자주 준다. 임계값은 region_group_settings 가 들고 있어 배포 없이 바꾼다."""
    if active_count >= daily_min:
        return list(EVERY_DAY)
    if active_count >= three_per_week_min:
        return list(THREE_TIMES_A_WEEK)
    return list(TWICE_A_WEEK)


def bottleneck_count(counts: dict[str, int]) -> int:
    """남녀 중 적은 쪽이 후보 풀의 두께다. 한쪽이 아예 없으면 0 이다."""
    return min(counts.get("male", 0), counts.get("female", 0))


def next_issue_at(now: datetime, weekdays: Sequence[int], issue_time: time) -> datetime:
    """오늘 다음으로 카드가 나가는 시각. 무료 카드의 expires_at 이 이 값이다(설계 §2.4)."""
    for ahead in range(1, 8):
        day = (now + timedelta(days=ahead)).date()
        if day.isoweekday() in weekdays:
            return datetime.combine(day, issue_time, tzinfo=now.tzinfo)
    raise ValueError(f"지급 요일이 비어 있다: {weekdays!r}")
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && python -m pytest tests/cards/test_ladder.py -v`
Expected: 7 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/__init__.py backend/app/cards/ladder.py backend/tests/cards/test_ladder.py
git commit -m "✨ feat(slice4): 지급 요일 사다리 계산 추가"
```

### Task B2: 카드 저장소 (`CardRepository`)

**Files:**
- Create: `backend/app/cards/repository.py`
- Test: `backend/tests/cards/test_card_repository.py`

**Interfaces:**
- Consumes: `app.profile_onboarding.repository._raise_for_status`(조각 2), PostgREST 헤더 패턴
  (`MatchingRepository.__init__` 과 같은 모양)
- Produces: `CardRepository(postgrest_url, service_role_key, client)` 의 메서드
  - `fetch_region_settings() -> list[dict]`
  - `fetch_active_counts() -> dict[str, dict[str, int]]` — `{"seoul": {"male": 12, "female": 9}}`
  - `fetch_issue_owners() -> list[dict]` — `[{"profile_id": ..., "region_group": "seoul"}]`
  - `save_issue_weekdays(region_group: str, weekdays: list[int]) -> None`
  - `insert_card(owner_id, target_id, expires_at: datetime | None, source="daily") -> dict`
  - `fetch_live_cards(owner_id) -> list[dict]` — 아직 결정 안 했고 만료도 안 된 카드(구매 카드 포함)
  - `fetch_card(card_id) -> dict | None`
  - `insert_decision(card_id, decision: str) -> None`
  - `fetch_pending_acceptances(profile_id) -> list[dict]`
  - `insert_acceptance_response(card_id, responder_id, decision: str) -> None`
  - `create_match(profile_a, profile_b) -> dict`
  - `fetch_card_profile(profile_id) -> dict` — 카드에 그릴 프로필 요약
  - `upsert_push_token(token, profile_id, platform) -> None` / `delete_push_token(token) -> None`
  - `fetch_push_tokens(profile_id) -> list[str]`
  - `fetch_notification_settings(profile_id) -> dict`
  - `update_notification_settings(profile_id, **fields) -> None`
  - `set_matching_paused(profile_id, paused: bool) -> None`

- [ ] **Step 1: 실패하는 테스트를 쓴다(요청이 어떤 모양으로 나가는지 못박는다)**

```python
# backend/tests/cards/test_card_repository.py
from datetime import datetime, timezone

import httpx
import pytest

from app.cards.repository import CardRepository

URL = "https://x.supabase.co/rest/v1"


def _repo(handler) -> tuple[CardRepository, httpx.AsyncClient]:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return CardRepository(URL, "service-key", client), client


async def test_insert_card_sends_owner_target_and_expiry():
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        seen.append(json.loads(request.content))
        return httpx.Response(201, json=[{"id": "card-1"}])

    repo, _ = _repo(handler)
    expires = datetime(2026, 9, 24, 22, 0, tzinfo=timezone.utc)
    card = await repo.insert_card("owner-1", "target-1", expires)

    assert card["id"] == "card-1"
    assert seen[0]["owner_id"] == "owner-1"
    assert seen[0]["target_id"] == "target-1"
    assert seen[0]["source"] == "daily"
    assert seen[0]["expires_at"] == expires.isoformat()


async def test_active_counts_are_grouped_by_region_and_gender():
    def handler(request: httpx.Request) -> httpx.Response:
        assert "/rpc/region_active_counts" in str(request.url)
        return httpx.Response(200, json=[
            {"region_group": "seoul", "gender": "male", "active_count": 12},
            {"region_group": "seoul", "gender": "female", "active_count": 9},
        ])

    repo, _ = _repo(handler)
    assert await repo.fetch_active_counts() == {"seoul": {"male": 12, "female": 9}}


async def test_pending_acceptances_drop_already_answered_ones():
    """7일 안에 받은 수락 중 아직 응답하지 않은 것만 받은 수락함에 보인다(설계 §2.2·§2.4)."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[
            {"card_id": "c1", "decided_at": "2026-09-20T07:00:00+00:00",
             "daily_cards": {"id": "c1", "owner_id": "o1", "target_id": "me"},
             "acceptance_responses": []},
            {"card_id": "c2", "decided_at": "2026-09-20T07:00:00+00:00",
             "daily_cards": {"id": "c2", "owner_id": "o2", "target_id": "me"},
             "acceptance_responses": [{"card_id": "c2"}]},
        ])

    repo, _ = _repo(handler)
    pending = await repo.fetch_pending_acceptances("me")

    assert [p["card_id"] for p in pending] == ["c1"]


async def test_create_match_orders_the_pair():
    """matches 는 항상 작은 uuid 가 profile_a 다(C3 체크 제약)."""
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        body = json.loads(request.content)
        seen.append(body if isinstance(body, dict) else body[0])
        return httpx.Response(201, json=[{"id": "match-1"}])

    repo, _ = _repo(handler)
    await repo.create_match("bbbb", "aaaa")

    assert seen[0]["profile_a"] == "aaaa"
    assert seen[0]["profile_b"] == "bbbb"
```

`backend/tests/cards/__init__.py` 는 만들지 않는다(기존 테스트 폴더와 같다). `asyncio_mode = "auto"` 라
`@pytest.mark.asyncio` 를 붙이지 않는다.

- [ ] **Step 2: 실패 확인**

Run: `cd backend && python -m pytest tests/cards/test_card_repository.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.cards.repository'`

- [ ] **Step 3: 구현**

```python
# backend/app/cards/repository.py
from datetime import datetime
from uuid import UUID

import httpx

from app.profile_onboarding.repository import _raise_for_status

# 카드 앞면(요약)과 뒷면(10b 상세)이 쓰는 프로필 컬럼. 실명·연락처는 한 글자도 넣지 않는다.
_CARD_PROFILE_COLUMNS = (
    "id,nickname,birth_year,major,animal_type,impression_type,"
    "interest_tags,my_traits,ideal_traits,ideal_note,bio,"
    "universities(name),profile_avatars(storage_path,status,created_at)"
)
_NOTIFICATION_COLUMNS = (
    "profile_id,card_arrived,acceptance_received,match_made,new_message,"
    "trust_reminder,new_friend_review,marketing,quiet_hours"
)
# 행이 없는 사람은 전부 켜진 것으로 본다(마케팅만 꺼짐) — C4 기본값과 같은 값이다.
NOTIFICATION_DEFAULTS = {
    "card_arrived": True, "acceptance_received": True, "match_made": True,
    "new_message": True, "trust_reminder": True, "new_friend_review": True,
    "marketing": False, "quiet_hours": True,
}


class CardRepository:
    """카드·매칭·알림 테이블 접근을 한 곳에 모은다(MatchingRepository 와 같은 패턴).
    프로필·후보 조회는 조각 3 MatchingRepository 를 그대로 쓴다 — 여기서 다시 만들지 않는다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def _get(self, path: str, params: dict) -> list[dict]:
        response = await self._client.get(
            f"{self._postgrest_url}/{path}", params=params, headers=self._headers
        )
        _raise_for_status(response)
        return response.json()

    async def _post(self, path: str, json: dict | list, prefer: str = "return=representation") -> list[dict]:
        response = await self._client.post(
            f"{self._postgrest_url}/{path}", json=json, headers={**self._headers, "Prefer": prefer}
        )
        _raise_for_status(response)
        return response.json() if response.content else []

    # 배치 ------------------------------------------------------------------
    async def fetch_region_settings(self) -> list[dict]:
        return await self._get("region_group_settings", {"select": "*"})

    async def fetch_active_counts(self) -> dict[str, dict[str, int]]:
        rows = await self._post("rpc/region_active_counts", {}, prefer="")
        counts: dict[str, dict[str, int]] = {}
        for row in rows:
            counts.setdefault(row["region_group"], {})[row["gender"]] = row["active_count"]
        return counts

    async def fetch_issue_owners(self) -> list[dict]:
        return await self._post("rpc/card_issue_owners", {}, prefer="")

    async def save_issue_weekdays(self, region_group: str, weekdays: list[int]) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/region_group_settings",
            params={"region_group": f"eq.{region_group}"},
            json={"issue_weekdays": weekdays, "updated_at": "now()"},
            headers=self._headers,
        )
        _raise_for_status(response)

    # 카드 ------------------------------------------------------------------
    async def insert_card(
        self, owner_id: UUID | str, target_id: UUID | str,
        expires_at: datetime | None, source: str = "daily",
    ) -> dict:
        rows = await self._post("daily_cards", {
            "owner_id": str(owner_id), "target_id": str(target_id),
            "source": source, "expires_at": expires_at.isoformat() if expires_at else None,
        })
        return rows[0]

    async def fetch_live_cards(self, owner_id: UUID | str) -> list[dict]:
        """아직 결정하지 않았고 만료도 되지 않은 카드. 노출 순서는 설계 §2.4 대로
        [이번 주기 무료 → 이전 주기 구매] 라서 issued_at 오름차순이 아니라 source 로 정렬한다."""
        rows = await self._get("daily_cards", {
            "owner_id": f"eq.{owner_id}",
            "select": "id,target_id,source,issued_at,expires_at,card_decisions(card_id)",
            "or": "(expires_at.is.null,expires_at.gt.now())",
            "order": "issued_at.desc",
        })
        return [row for row in rows if not row["card_decisions"]]

    async def fetch_card(self, card_id: UUID | str) -> dict | None:
        rows = await self._get("daily_cards", {
            "id": f"eq.{card_id}",
            "select": "id,owner_id,target_id,source,issued_at,expires_at,card_decisions(decision)",
        })
        return rows[0] if rows else None

    async def insert_decision(self, card_id: UUID | str, decision: str) -> None:
        await self._post("card_decisions", {"card_id": str(card_id), "decision": decision}, prefer="")

    # 받은 수락함 -------------------------------------------------------------
    async def fetch_pending_acceptances(self, profile_id: UUID | str, days: int = 7) -> list[dict]:
        """내가 받은 수락 중 7일이 지나지 않았고 아직 답하지 않은 것(설계 §2.2, 2026-09-21 확정).
        건수가 1인당 하루 0.3~0.5건이라 응답 여부는 파이썬에서 거른다 — 전용 SQL 함수를 만들지 않는다."""
        rows = await self._get("card_decisions", {
            "select": "card_id,decided_at,daily_cards!inner(id,owner_id,target_id),acceptance_responses(card_id)",
            "decision": "eq.accept",
            "decided_at": f"gte.{days}", "daily_cards.target_id": f"eq.{profile_id}",
            "order": "decided_at.desc",
        })
        return [row for row in rows if not row["acceptance_responses"]]

    async def insert_acceptance_response(
        self, card_id: UUID | str, responder_id: UUID | str, decision: str
    ) -> None:
        await self._post("acceptance_responses", {
            "card_id": str(card_id), "responder_id": str(responder_id), "decision": decision,
        }, prefer="")

    async def create_match(self, profile_a: UUID | str, profile_b: UUID | str) -> dict:
        """C3 의 check (profile_a < profile_b) 를 지키려고 여기서 한 번만 정렬한다."""
        first, second = sorted([str(profile_a), str(profile_b)])
        rows = await self._post("matches", {"profile_a": first, "profile_b": second})
        match = rows[0]
        await self._post("match_participants", [
            {"match_id": match["id"], "profile_id": first},
            {"match_id": match["id"], "profile_id": second},
        ], prefer="")
        return match

    # 프로필 요약 --------------------------------------------------------------
    async def fetch_card_profile(self, profile_id: UUID | str) -> dict:
        rows = await self._get("profiles", {"id": f"eq.{profile_id}", "select": _CARD_PROFILE_COLUMNS})
        return rows[0] if rows else {}

    # 푸시 · 알림 --------------------------------------------------------------
    async def upsert_push_token(self, token: str, profile_id: UUID | str, platform: str) -> None:
        await self._post("push_tokens", {
            "token": token, "profile_id": str(profile_id), "platform": platform, "updated_at": "now()",
        }, prefer="resolution=merge-duplicates")

    async def delete_push_token(self, token: str) -> None:
        response = await self._client.delete(
            f"{self._postgrest_url}/push_tokens",
            params={"token": f"eq.{token}"}, headers=self._headers,
        )
        _raise_for_status(response)

    async def fetch_push_tokens(self, profile_id: UUID | str) -> list[str]:
        rows = await self._get("push_tokens", {"profile_id": f"eq.{profile_id}", "select": "token"})
        return [row["token"] for row in rows]

    async def fetch_notification_settings(self, profile_id: UUID | str) -> dict:
        rows = await self._get("notification_settings", {
            "profile_id": f"eq.{profile_id}", "select": _NOTIFICATION_COLUMNS,
        })
        return rows[0] if rows else {"profile_id": str(profile_id), **NOTIFICATION_DEFAULTS}

    async def update_notification_settings(self, profile_id: UUID | str, **fields) -> None:
        await self._post("notification_settings", {
            "profile_id": str(profile_id), **fields,
        }, prefer="resolution=merge-duplicates")

    async def set_matching_paused(self, profile_id: UUID | str, paused: bool) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"matching_paused": paused},
            headers=self._headers,
        )
        _raise_for_status(response)
```

> `fetch_pending_acceptances` 의 `"decided_at": f"gte.{days}"` 는 **자리 표시가 아니다 — 고쳐야 한다.**
> 호출부에서 실제 시각을 만들어 넘긴다: `f"gte.{(datetime.now(timezone.utc) - timedelta(days=days)).isoformat()}"`.
> Step 3 구현 때 이 줄을 그렇게 쓰고, 위 테스트가 값을 검사하도록 한 줄 더 단언을 넣는다.

- [ ] **Step 4: 통과 확인**

Run: `cd backend && python -m pytest tests/cards/test_card_repository.py -v`
Expected: 4 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/repository.py backend/tests/cards/test_card_repository.py
git commit -m "✨ feat(slice4): 카드·매칭·알림 저장소 추가"
```

### Task B3: FCM 전송 (`push.py`)

**Files:**
- Create: `backend/app/cards/push.py`
- Test: `backend/tests/cards/test_push.py`

**Interfaces:**
- Consumes: `CardRepository.fetch_push_tokens` · `delete_push_token` · `fetch_notification_settings`
- Produces: `FcmSender(project_id, client, credentials=None)` 와 `await sender.send(token, title, body, data) -> bool`
  (False = 토큰이 죽었다)
- Produces: `await notify(repo, sender, profile_id, kind, title, body, data, now) -> int` — 실제로 보낸 건수.
  `kind` 는 `notification_settings` 컬럼 이름(`card_arrived` · `acceptance_received` · `match_made`)이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
# backend/tests/cards/test_push.py
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx

from app.cards.push import FcmSender, notify

SEOUL = ZoneInfo("Asia/Seoul")


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _FakeRepo:
    def __init__(self, tokens, settings):
        self._tokens, self._settings = tokens, settings
        self.deleted: list[str] = []

    async def fetch_push_tokens(self, profile_id):
        return list(self._tokens)

    async def fetch_notification_settings(self, profile_id):
        return dict(self._settings)

    async def delete_push_token(self, token):
        self.deleted.append(token)


def _sender(handler) -> FcmSender:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return FcmSender("campus-mate", client, credentials=_FakeCredentials())


async def test_send_posts_to_fcm_v1_with_bearer_token():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"name": "projects/campus-mate/messages/1"})

    assert await _sender(handler).send("tok", "제목", "본문", {"route": "daily_card"}) is True
    assert seen[0].url.path == "/v1/projects/campus-mate/messages:send"
    assert seen[0].headers["Authorization"] == "Bearer ya29.test"


async def test_dead_token_is_reported_as_false():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"status": "NOT_FOUND"}})

    assert await _sender(handler).send("dead", "제목", "본문", {}) is False


async def test_notify_deletes_tokens_that_came_back_dead():
    repo = _FakeRepo(["dead"], {"acceptance_received": True, "quiet_hours": False})

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={})

    sent = await notify(repo, _sender(handler), "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 0
    assert repo.deleted == ["dead"]


async def test_switched_off_kind_is_not_sent():
    repo = _FakeRepo(["tok"], {"acceptance_received": False, "quiet_hours": False})
    sent = await notify(repo, _sender(lambda r: httpx.Response(200, json={})), "p1",
                        "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))
    assert sent == 0


async def test_quiet_hours_block_everything_except_the_card_alarm():
    """22~8시는 보류. 단 카드 도착은 지급 시각이 07:00 이라 예외다(계획서 실행 전 확인 6번)."""
    night = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
    repo = _FakeRepo(["tok"], {"acceptance_received": True, "card_arrived": True, "quiet_hours": True})
    handler = lambda request: httpx.Response(200, json={})

    assert await notify(repo, _sender(handler), "p1", "acceptance_received", "제", "본", {}, now=night) == 0
    assert await notify(repo, _sender(handler), "p1", "card_arrived", "제", "본", {}, now=night) == 1
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && python -m pytest tests/cards/test_push.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.cards.push'`

- [ ] **Step 3: 구현**

```python
# backend/app/cards/push.py
import asyncio
import logging
from datetime import datetime

import google.auth
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
# 조용한 시간(설계 화면 16d): 22시 ~ 다음날 8시.
_QUIET_START_HOUR = 22
_QUIET_END_HOUR = 8
# 카드 도착 알림은 지급 시각(07:00)이 조용한 시간 안이라 예외다 — 아니면 영영 못 간다.
_QUIET_HOURS_EXEMPT = {"card_arrived"}


class FcmSender:
    """FCM HTTP v1 에 알림 한 건을 보낸다. 자격증명은 Cloud Run 서비스 계정(ADC)이다 —
    Vision 과 같은 방식이고 서버 키를 따로 만들지 않는다(2026-09-20 준비 가이드)."""

    def __init__(self, project_id: str, client: httpx.AsyncClient, credentials=None):
        self._project_id = project_id
        self._client = client
        self._credentials = credentials

    async def _access_token(self) -> str:
        if self._credentials is None:
            self._credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
        if not self._credentials.valid:
            # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다.
            await asyncio.to_thread(self._credentials.refresh, GoogleAuthRequest())
        return self._credentials.token

    async def send(self, token: str, title: str, body: str, data: dict[str, str]) -> bool:
        """보냈으면 True. 토큰이 죽었으면(404 UNREGISTERED) False — 부른 쪽이 그 토큰을 지운다."""
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                # data 값은 문자열만 허용된다. 앱은 route 로 어느 화면을 열지 고른다(Task A7).
                "data": {key: str(value) for key, value in data.items()},
                "android": {"priority": "high"},
            }
        }
        response = await self._client.post(
            f"https://fcm.googleapis.com/v1/projects/{self._project_id}/messages:send",
            json=payload,
            headers={"Authorization": f"Bearer {await self._access_token()}"},
        )
        if response.status_code in (404, 400):
            return False
        if not response.is_success:
            # 푸시 실패가 카드 지급을 되돌리게 두지 않는다 — 로그만 남기고 넘어간다.
            logger.warning("FCM 전송 실패 %s %s", response.status_code, response.text[:200])
            return False
        return True


def _is_quiet(now: datetime) -> bool:
    return now.hour >= _QUIET_START_HOUR or now.hour < _QUIET_END_HOUR


async def notify(repo, sender: FcmSender, profile_id, kind: str,
                 title: str, body: str, data: dict[str, str], now: datetime) -> int:
    """알림 스위치와 조용한 시간을 본 뒤 그 사람의 모든 기기로 보낸다. 보낸 건수를 돌려준다."""
    settings = await repo.fetch_notification_settings(profile_id)
    if not settings.get(kind, True):
        return 0
    if settings.get("quiet_hours", True) and kind not in _QUIET_HOURS_EXEMPT and _is_quiet(now):
        # ponytail: 지금은 그냥 버린다. 모아 뒀다 아침에 보내려면 큐가 필요하다(백로그).
        return 0

    sent = 0
    for token in await repo.fetch_push_tokens(profile_id):
        if await sender.send(token, title, body, data):
            sent += 1
        else:
            await repo.delete_push_token(token)
    return sent
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && python -m pytest tests/cards/test_push.py -v`
Expected: 5 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/push.py backend/tests/cards/test_push.py
git commit -m "✨ feat(slice4): FCM v1 알림 전송 추가"
```

### Task B4: 지급 배치 (`issuing.py` + `/batch/daily-cards`)

**Files:**
- Create: `backend/app/cards/issuing.py`
- Create: `backend/app/cards/batch_router.py`
- Modify: `backend/app/settings.py` (`card_batch_secret` 추가)
- Modify: `backend/app/main.py` (라우터 등록)
- Test: `backend/tests/cards/test_issuing.py`

**Interfaces:**
- Consumes: B1 `ladder_weekdays` · `bottleneck_count` · `next_issue_at`, B2 `CardRepository`,
  B3 `FcmSender` · `notify`, 조각 3 `MatchingRepository.fetch_owner` · `fetch_candidates` ·
  `scoring.rank`
- Produces: `await issue_daily_cards(card_repo, matching_repo, sender, now) -> dict`
  — `{"issued": 3, "skipped_regions": ["busan"], "no_candidate": 1}`
- Produces: `POST /batch/daily-cards` (헤더 `X-Batch-Secret`) → 위 dict 를 그대로 돌려준다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
# backend/tests/cards/test_issuing.py
from datetime import datetime
from zoneinfo import ZoneInfo

from app.cards.issuing import issue_daily_cards

SEOUL = ZoneInfo("Asia/Seoul")
MONDAY_7AM = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)     # 월요일
TUESDAY_7AM = datetime(2026, 9, 22, 7, 0, tzinfo=SEOUL)    # 화요일


class _FakeCardRepo:
    def __init__(self, owners, counts=None, settings=None):
        self._owners = owners
        self._counts = counts or {"seoul": {"male": 10, "female": 10}}
        self._settings = settings or [{
            "region_group": "seoul", "issue_weekdays": [1, 4], "issue_time": "07:00",
            "ladder_three_per_week_min": 200, "ladder_daily_min": 500,
        }]
        self.cards: list[dict] = []
        self.saved_weekdays: list[tuple] = []

    async def fetch_region_settings(self):
        return self._settings

    async def fetch_active_counts(self):
        return self._counts

    async def fetch_issue_owners(self):
        return self._owners

    async def save_issue_weekdays(self, region_group, weekdays):
        self.saved_weekdays.append((region_group, weekdays))

    async def insert_card(self, owner_id, target_id, expires_at, source="daily"):
        card = {"id": f"card-{len(self.cards)}", "owner_id": owner_id,
                "target_id": target_id, "expires_at": expires_at}
        self.cards.append(card)
        return card

    async def fetch_card_profile(self, profile_id):
        return {"nickname": "여우비"}

    async def fetch_push_tokens(self, profile_id):
        return []

    async def fetch_notification_settings(self, profile_id):
        return {"card_arrived": True, "quiet_hours": True}


class _FakeMatchingRepo:
    def __init__(self, candidates):
        self._candidates = candidates

    async def fetch_owner(self, profile_id):
        return {"id": profile_id, "status": "active", "gender": "male", "mbti": None,
                "preferred_mbti_flags": {}, "height_cm": 180, "preferred_height_min": None,
                "preferred_height_max": None, "birth_year": 2002, "preferred_age_min": None,
                "preferred_age_max": None, "is_smoker": False, "religion": "none"}

    async def fetch_candidates(self, profile_id):
        return list(self._candidates)


def _candidate(candidate_id: str, trait_score: float) -> dict:
    return {"candidate_id": candidate_id, "trait_score": trait_score, "tag_score": 0.0,
            "text_score": 0.0, "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
            "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
            "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False,
            "religion": "none", "last_active_at": "2026-09-21T00:00:00+00:00"}


async def test_issues_one_card_to_the_top_candidate():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("low", 0.1), _candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result["issued"] == 1
    assert repo.cards[0]["target_id"] == "high"


async def test_expiry_is_the_next_issue_day():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    # 월·목 지급이므로 월요일에 준 카드는 목요일 07:00 에 만료된다(설계 §2.4).
    assert repo.cards[0]["expires_at"] == datetime(2026, 9, 24, 7, 0, tzinfo=SEOUL)


async def test_non_issue_day_issues_nothing():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 0
    assert repo.cards == []


async def test_ladder_moves_up_and_is_written_back():
    """활성 500명을 넘으면 매일 지급으로 올라가고, 그 결과를 설정 행에 적어 둔다(앱이 읽는다)."""
    repo = _FakeCardRepo(
        [{"profile_id": "owner-1", "region_group": "seoul"}],
        counts={"seoul": {"male": 600, "female": 700}},
    )
    matching = _FakeMatchingRepo([_candidate("high", 0.9)])

    result = await issue_daily_cards(repo, matching, sender=None, now=TUESDAY_7AM)

    assert result["issued"] == 1
    assert repo.saved_weekdays == [("seoul", [1, 2, 3, 4, 5, 6, 7])]


async def test_owner_without_candidates_is_counted_not_crashed():
    repo = _FakeCardRepo([{"profile_id": "owner-1", "region_group": "seoul"}])
    matching = _FakeMatchingRepo([])

    result = await issue_daily_cards(repo, matching, sender=None, now=MONDAY_7AM)

    assert result == {"issued": 0, "no_candidate": 1, "skipped_regions": []}
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && python -m pytest tests/cards/test_issuing.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.cards.issuing'`

- [ ] **Step 3: 구현**

```python
# backend/app/cards/issuing.py
import logging
from datetime import datetime, time

from app.cards.ladder import bottleneck_count, ladder_weekdays, next_issue_at
from app.cards.push import notify
from app.matching.scoring import rank

logger = logging.getLogger(__name__)


def _parse_time(value: str) -> time:
    return time.fromisoformat(value)


async def issue_daily_cards(card_repo, matching_repo, sender, now: datetime) -> dict:
    """하루 한 번 도는 지급 배치(설계 §2.1). Cloud Scheduler 가 07:00 Asia/Seoul 에 부른다.

    ponytail: 대상자마다 RPC 2번(프로필 + 후보)을 부른다. 서울 한 그룹 · 수백 명 규모에서는 충분하고,
    수천 명이 되면 후보 조회를 한 번에 모아 오는 SQL 로 바꾼다(백로그)."""
    settings_by_region = {row["region_group"]: row for row in await card_repo.fetch_region_settings()}
    counts = await card_repo.fetch_active_counts()

    weekdays_by_region: dict[str, list[int]] = {}
    skipped: list[str] = []
    for region, row in settings_by_region.items():
        weekdays = ladder_weekdays(
            bottleneck_count(counts.get(region, {})),
            row["ladder_three_per_week_min"], row["ladder_daily_min"],
        )
        if weekdays != list(row["issue_weekdays"]):
            # 사다리 결과를 설정 행에 적어 둔다 — 앱이 "다음 지급은 O요일" 문구를 여기서 읽는다.
            await card_repo.save_issue_weekdays(region, weekdays)
        weekdays_by_region[region] = weekdays
        if now.isoweekday() not in weekdays:
            skipped.append(region)

    issued = 0
    no_candidate = 0
    for owner in await card_repo.fetch_issue_owners():
        region = owner["region_group"]
        weekdays = weekdays_by_region.get(region)
        if weekdays is None or now.isoweekday() not in weekdays:
            continue

        owner_id = owner["profile_id"]
        owner_row = await matching_repo.fetch_owner(owner_id)
        ranked = rank(owner_row, await matching_repo.fetch_candidates(owner_id))
        if not ranked:
            # 후보가 없으면 카드가 없다 — 화면 11b `iQZoa` 가 이 상태를 설명한다.
            no_candidate += 1
            continue

        settings_row = settings_by_region[region]
        expires_at = next_issue_at(now, weekdays, _parse_time(settings_row["issue_time"]))
        card = await card_repo.insert_card(owner_id, ranked[0]["candidate_id"], expires_at)
        issued += 1

        if sender is not None:
            await notify(
                card_repo, sender, owner_id, "card_arrived",
                "오늘의 카드가 도착했어요", "지금 확인해 보세요",
                {"route": "daily_card", "card_id": str(card["id"])}, now=now,
            )

    return {"issued": issued, "no_candidate": no_candidate, "skipped_regions": skipped}
```

```python
# backend/app/cards/batch_router.py
import hmac
from datetime import datetime
from functools import lru_cache
from zoneinfo import ZoneInfo

import httpx
from fastapi import APIRouter, Header, HTTPException

from app.cards.issuing import issue_daily_cards
from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.matching.repository import MatchingRepository
from app.settings import Settings

router = APIRouter()

SEOUL = ZoneInfo("Asia/Seoul")

_client_override: httpx.AsyncClient | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


@router.post("/batch/daily-cards")
async def run_daily_cards(x_batch_secret: str | None = Header(default=None)) -> dict:
    """Cloud Scheduler 전용. Cloud Run 이 --allow-unauthenticated 라 이 엔드포인트는 스스로를 지킨다
    (조각 1a 의 auth hook 이 서명으로 자기를 지키는 것과 같은 이유)."""
    settings = get_settings()
    if not settings.card_batch_secret or not x_batch_secret or not hmac.compare_digest(
        x_batch_secret, settings.card_batch_secret
    ):
        raise HTTPException(status_code=401, detail="unauthorized")

    client = _client_override or httpx.AsyncClient()
    card_repo = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    matching_repo = MatchingRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )
    sender = FcmSender(settings.google_cloud_project, client)
    return await issue_daily_cards(card_repo, matching_repo, sender, now=datetime.now(SEOUL))
```

`backend/app/settings.py` 의 `Settings` 에 한 줄 추가:

```python
    card_batch_secret: str = ""
```

`backend/app/main.py` 에 두 줄 추가:

```python
from app.cards.batch_router import router as cards_batch_router
...
app.include_router(cards_batch_router)
```

- [ ] **Step 4: 통과 확인 + 401 확인**

Run: `cd backend && python -m pytest tests/cards -v`
Expected: 전부 passed

`backend/tests/cards/test_batch_router.py` 에 한 건 더 쓴다:

```python
def test_batch_requires_the_shared_secret():
    client = TestClient(app)
    assert client.post("/batch/daily-cards").status_code == 401
    assert client.post("/batch/daily-cards", headers={"X-Batch-Secret": "wrong"}).status_code == 401
```

(`get_settings` 를 `monkeypatch` 로 덮어 `card_batch_secret="right"` 를 넣는 방식은 조각 3
`test_matching_router.py` 의 `overrides` 픽스처를 그대로 베낀다.)

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/issuing.py backend/app/cards/batch_router.py backend/app/settings.py \
        backend/app/main.py backend/tests/cards/test_issuing.py backend/tests/cards/test_batch_router.py
git commit -m "✨ feat(slice4): 하루 한 번 도는 카드 지급 배치 추가"
```

### Task B5: 오늘의 카드 조회 · 결정 (`router.py`)

**Files:**
- Create: `backend/app/cards/router.py`
- Modify: `backend/app/main.py` (라우터 등록)
- Test: `backend/tests/cards/test_cards_router.py`

**Interfaces:**
- Consumes: B2 `CardRepository`, B3 `notify`, `get_verified_user_id`(조각 1b)
- Produces: `GET /cards/today` →
  ```json
  {"cards": [{"card_id": "…", "source": "daily", "expires_at": "…",
              "profile": {"nickname": "여우비", "age": 23, "university": "○○대학교",
                          "major": "컴퓨터공학과", "avatar_url": "https://…"}}],
   "next_issue_at": "2026-09-24T07:00:00+09:00",
   "locked_card_available": true}
  ```
- Produces: `GET /cards/{card_id}` → 10b 상세(성향 · 얼굴상 · 관심사 · 특징 · 이상형 특징 · 이런 사람이 좋아요)
- Produces: `POST /cards/{card_id}/decision` `{"decision": "accept"|"reject"}` → `{"ok": true}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
# backend/tests/cards/test_cards_router.py (발췌 — 픽스처는 test_matching_router.py 와 같은 모양)
def test_today_returns_the_live_card_with_profile():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/daily_cards" in url:
            return httpx.Response(200, json=[{
                "id": "card-1", "target_id": "t1", "source": "daily",
                "issued_at": "2026-09-21T07:00:00+09:00", "expires_at": "2026-09-24T07:00:00+09:00",
                "card_decisions": [],
            }])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[{
                "id": "t1", "nickname": "여우비", "birth_year": 2003, "major": "컴퓨터공학과",
                "universities": {"name": "테스트대학교"},
                "profile_avatars": [{"storage_path": "t1/a.png", "status": "ready",
                                     "created_at": "2026-09-20T00:00:00+00:00"}],
            }])
        if "/rest/v1/region_group_settings" in url:
            return httpx.Response(200, json=[{"region_group": "seoul", "issue_weekdays": [1, 4],
                                              "issue_time": "07:00"}])
        return httpx.Response(200, json=[])

    response = _wire(handler).get("/cards/today", headers=AUTH_HEADERS)

    assert response.status_code == 200
    card = response.json()["cards"][0]
    assert card["card_id"] == "card-1"
    assert card["profile"]["nickname"] == "여우비"
    assert card["profile"]["age"] == 24  # 한국 나이 계산은 조각 2 규칙을 따른다
    assert card["profile"]["avatar_url"].endswith("/avatars/t1/a.png")


def test_decision_on_someone_elses_card_is_404():
    """카드 주인만 결정할 수 있다. 남의 카드 id 를 찍어 보는 시도는 존재 자체를 알려주지 않는다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/daily_cards" in str(request.url):
            return httpx.Response(200, json=[{"id": "card-1", "owner_id": "somebody-else",
                                              "target_id": "t1", "source": "daily",
                                              "expires_at": None, "card_decisions": []}])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/cards/card-1/decision", headers=AUTH_HEADERS,
                                   json={"decision": "accept"})
    assert response.status_code == 404


def test_expired_card_cannot_be_decided():
    """만료된 카드는 결정할 수 없다 — 무응답으로 끝난 카드다(설계 §2.4)."""
    ...  # expires_at 을 과거로 돌려주고 409 를 기대한다


def test_accept_notifies_the_target():
    """A 가 수락하면 B 에게 '받은 수락' 알림이 간다(설계 §2.2). 거절은 아무에게도 알리지 않는다."""
    ...  # push_tokens 를 1개 돌려주고 FCM 목이 1번 불렸는지 본다
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && python -m pytest tests/cards/test_cards_router.py -v`
Expected: FAIL — 404(라우터가 없다)

- [ ] **Step 3: 구현**

```python
# backend/app/cards/router.py (발췌)
from datetime import datetime
from functools import lru_cache
from zoneinfo import ZoneInfo

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, field_validator

from app.cards.ladder import next_issue_at
from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository
from app.settings import Settings
from app.student_verification.current_user import get_verified_user_id

router = APIRouter()
SEOUL = ZoneInfo("Asia/Seoul")

_client_override: httpx.AsyncClient | None = None
_sender_override = None


class DecisionRequest(BaseModel):
    decision: str

    @field_validator("decision")
    @classmethod
    def _known(cls, value: str) -> str:
        if value not in ("accept", "reject"):
            raise ValueError("accept 또는 reject 만 받는다")
        return value


def _card_profile(profile: dict, supabase_url: str, now: datetime) -> dict:
    """카드 앞면에 그릴 것만 고른다 — 실명·연락처·사진 원본은 내려보내지 않는다(설계 §7.1)."""
    avatars = [a for a in profile.get("profile_avatars", []) if a["status"] == "ready"]
    latest = max(avatars, key=lambda a: a["created_at"], default=None)
    return {
        "profile_id": profile["id"],
        "nickname": profile["nickname"],
        # 화면은 "여우비, 23" 처럼 쓴다(pen `eWD7g`). 조각 2 와 같은 계산식을 쓴다.
        "age": now.year - profile["birth_year"] + 1,
        "university": (profile.get("universities") or {}).get("name"),
        "major": profile.get("major"),
        "avatar_url": (
            f"{supabase_url}/storage/v1/object/public/avatars/{latest['storage_path']}"
            if latest else None
        ),
    }


@router.get("/cards/today")
async def get_today_cards(authorization: str | None = Header(default=None)) -> dict:
    """오늘의 카드(화면 10 `W0CjO`). 살아 있는 카드가 없으면 빈 목록 + 다음 지급 시각만 내려간다
    (화면 11 `i4VFS` 가 그 상태를 그린다)."""
    ...
```

나머지 엔드포인트(`GET /cards/{card_id}` · `POST /cards/{card_id}/decision`)는 같은 파일에 이어 쓴다.
결정 처리의 순서는 **저장 먼저, 알림 나중**이다(알림이 실패해도 결정은 남는다):

```python
@router.post("/cards/{card_id}/decision")
async def decide_card(card_id: str, body: DecisionRequest,
                      authorization: str | None = Header(default=None)) -> dict:
    ...
    card = await repo.fetch_card(card_id)
    if card is None or card["owner_id"] != profile_id:
        raise HTTPException(status_code=404, detail="카드를 찾을 수 없어요")
    if card["card_decisions"]:
        raise HTTPException(status_code=409, detail="이미 결정한 카드예요")
    if card["expires_at"] and datetime.fromisoformat(card["expires_at"]) <= now:
        raise HTTPException(status_code=409, detail="지난 카드예요")

    await repo.insert_decision(card_id, body.decision)
    if body.decision == "accept":
        # 거절은 조용히 끝난다 — 상대에게 아무 신호도 보내지 않는다(설계 §2.2).
        me = await repo.fetch_card_profile(profile_id)
        await notify(repo, sender, card["target_id"], "acceptance_received",
                     "나를 수락한 사람이 있어요", f"{me['nickname']} 님이 대화를 하고 싶어 해요",
                     {"route": "acceptances", "card_id": card_id}, now=now)
    return {"ok": True}
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && python -m pytest tests/cards -v`
Expected: 전부 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/router.py backend/app/main.py backend/tests/cards/test_cards_router.py
git commit -m "✨ feat(slice4): 오늘의 카드 조회·결정 엔드포인트 추가"
```

### Task B6: 받은 수락함 · 매칭 성사

**Files:**
- Modify: `backend/app/cards/router.py`
- Test: `backend/tests/cards/test_acceptances.py`

**Interfaces:**
- Produces: `GET /cards/acceptances` →
  `{"acceptances": [{"card_id": "…", "expires_at": "…", "profile": {…}}]}`
  (7일이 지난 것은 빠진 채로 내려간다 — 만료 표시 행은 만들지 않는다)
- Produces: `POST /cards/acceptances/{card_id}` `{"decision": "accept"|"reject"}` →
  `{"matched": true, "match_id": "…"}` 또는 `{"matched": false}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
async def test_accepting_creates_a_match_and_notifies_both():
    """쌍방 수락이면 matches 한 행 + participants 두 행이 생기고, 두 사람 모두에게 알림이 간다(설계 §2.2)."""
    ...


async def test_rejecting_does_not_notify_anyone():
    """거절은 조용히 끝난다 — 상대에게 신호가 가지 않는다(설계 §2.2)."""
    ...


async def test_acceptance_older_than_seven_days_is_gone():
    """받은 수락함은 7일이 지나면 목록에서 사라진다(2026-09-21 확정). 응답도 받지 않는다(410)."""
    ...


async def test_responding_twice_is_conflict():
    ...
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && python -m pytest tests/cards/test_acceptances.py -v`
Expected: FAIL — 404

- [ ] **Step 3: 구현**

```python
ACCEPTANCE_TTL_DAYS = 7


@router.post("/cards/acceptances/{card_id}")
async def respond_to_acceptance(card_id: str, body: DecisionRequest,
                                authorization: str | None = Header(default=None)) -> dict:
    ...
    card = await repo.fetch_card(card_id)
    if card is None or card["target_id"] != profile_id:
        raise HTTPException(status_code=404, detail="수락을 찾을 수 없어요")
    decided_at = ...  # card_decisions.decided_at
    if decided_at <= now - timedelta(days=ACCEPTANCE_TTL_DAYS):
        raise HTTPException(status_code=410, detail="기한이 지났어요")

    await repo.insert_acceptance_response(card_id, profile_id, body.decision)
    if body.decision != "accept":
        return {"matched": False}

    match = await repo.create_match(card["owner_id"], profile_id)
    me = await repo.fetch_card_profile(profile_id)
    other = await repo.fetch_card_profile(card["owner_id"])
    # 매칭 성사는 양쪽 모두에게 알린다(화면 12 `UFNSi`).
    await notify(repo, sender, card["owner_id"], "match_made", "매칭됐어요!",
                 f"{me['nickname']} 님도 수락했어요", {"route": "match", "match_id": match["id"]}, now=now)
    await notify(repo, sender, profile_id, "match_made", "매칭됐어요!",
                 f"{other['nickname']} 님과 대화를 시작해 보세요",
                 {"route": "match", "match_id": match["id"]}, now=now)
    return {"matched": True, "match_id": match["id"]}
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && python -m pytest tests/cards -v`

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/router.py backend/tests/cards/test_acceptances.py
git commit -m "✨ feat(slice4): 받은 수락함과 매칭 성사 처리 추가"
```

### Task B7: 푸시 토큰 · 알림 설정 · 매칭 일시중지

**Files:**
- Modify: `backend/app/cards/router.py`
- Test: `backend/tests/cards/test_notification_settings.py`

**Interfaces:**
- Produces: `POST /cards/push-tokens` `{"token": "…", "platform": "android"}` → `{"ok": true}`
- Produces: `DELETE /cards/push-tokens/{token}` → `{"ok": true}` (로그아웃 때 부른다)
- Produces: `GET /cards/notification-settings` → 스위치 8개(행이 없으면 기본값)
- Produces: `PATCH /cards/notification-settings` → 바뀐 것만 보낸다. `marketing` 을 켤 때
  `marketing_consented_at` 을 서버가 채운다(동의 시각은 클라이언트를 믿지 않는다)
- Produces: `PATCH /cards/matching-paused` `{"paused": true}` → `{"ok": true}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```python
async def test_marketing_opt_in_records_the_server_time():
    """동의 시각은 서버가 적는다 — 법적 근거가 되는 값이라 앱이 보낸 시각을 믿지 않는다."""
    ...


async def test_settings_row_missing_returns_defaults():
    """한 번도 저장한 적 없는 사람은 전부 켜짐(마케팅만 꺼짐)으로 본다 — 화면이 빈 스위치를 그리지 않는다."""
    ...


async def test_pausing_matching_updates_the_profile():
    ...
```

- [ ] **Step 2~4: 실패 확인 → 구현 → 통과 확인**

Run: `cd backend && python -m pytest tests/cards -v`

- [ ] **Step 5: 커밋**

```bash
git add backend/app/cards/router.py backend/tests/cards/test_notification_settings.py
git commit -m "✨ feat(slice4): 푸시 토큰·알림 설정·일시중지 엔드포인트 추가"
```

### Task B8: 배포 문서 (Cloud Scheduler · 시크릿 · 권한)

**Files:**
- Modify: `backend/DEPLOY.md`

**Interfaces:**
- Consumes: B4 `/batch/daily-cards` · `card_batch_secret`
- Produces: 배포 절차 문서 — **명령만 적고 실행하지 않는다**(실제 배포는 사용자 몫)

- [ ] **Step 1: 시크릿 항목을 표에 추가**

| 시크릿 이름 | 용도 |
| --- | --- |
| `card-batch-secret` | `/batch/daily-cards` 를 Cloud Scheduler 만 부르게 하는 공유 비밀 |

**FCM 자격증명 시크릿은 만들지 않는다** — Cloud Run 서비스 계정(ADC)으로 보낸다(Vision 과 같은 방식,
2026-09-20 준비 가이드). 서비스 계정에 **`roles/firebasemessaging.admin`** 만 추가하면 된다.

- [ ] **Step 2: Cloud Scheduler job 을 적는다**

```bash
# 매일 07:00 Asia/Seoul. 요일 판정은 코드가 하므로 job 은 하나면 된다.
gcloud scheduler jobs create http campus-mate-daily-cards \
  --location=asia-northeast3 \
  --schedule="0 7 * * *" \
  --time-zone="Asia/Seoul" \
  --uri="https://<cloud-run-url>/batch/daily-cards" \
  --http-method=POST \
  --headers="X-Batch-Secret=<card-batch-secret 값>" \
  --attempt-deadline=600s
```

실행 시간이 600초를 넘기 시작하면 지역그룹별로 job 을 나눈다(백로그).

- [ ] **Step 3: 커밋 + Part B PR**

```bash
git add backend/DEPLOY.md
git commit -m "📝 docs(slice4): 카드 배치 스케줄러·시크릿 배포 절차 추가"
git push -u origin feat/slice4-part-b-backend
gh pr create --draft --base main --title "조각 4 Part B: 카드 지급 배치·수락·푸시 API" --body "..."
```

---

## Part A: Flutter — 아직 쓰지 않음 (작성 중단 지점)

2026-09-21, 사용자 지시로 조각 4 착수 전 정지. 이 계획서는 **미완성 초안**이다.

**쓴 것:** 헤더 · 새 의존성 목록 · Global Constraints · 확정 전제 · 실행 전 확인 사항 6건 ·
파일 구조 · Task 0(.gitignore) · **Part C**(C1~C6, DB 마이그레이션 + pgTAP 전문) ·
**Part B**(B1~B8, FastAPI 사다리·저장소·FCM·배치·카드 API·받은 수락함·알림 설정·배포 문서).

**안 쓴 것 — 이어받는 사람이 할 일:**

| Task | 내용 | pen 노드 id |
| --- | --- | --- |
| A1 | 의존성 추가 · `google-services.json` 이동 · Firebase 초기화 | — |
| A2 | 모델 · Repository · Provider (조각 3 `http_*` 패턴 그대로) | — |
| A3 | 오늘의 카드 목록 · 빈 상태 · 로딩 · 구매 카드 | `W0CjO` 10 오늘의 카드, `eDPkz` 카드 없음, `Ukg21` 로딩, `Keynu` 구매 카드 있음, `i4VFS`·`k2fF9y` 11 카드 대기, `iQZoa` 11b 매칭 가능한 사람 없음 / components `v26S7z` DailyCardSummary, `BpP33` DailyCardLocked, `x4FuK` Skeleton Card, `PKbwO` Card Waiting Mascot |
| A4 | 10b 카드 상세 · 수락/거절 | `TORAs` |
| A5 | 매칭 성사 화면 + 09b 메인 배너 | `UFNSi`, `bpA8x` |
| A6 | 받은 수락함(13 대화 화면 상단 sticky 섹션) | `CeqVY` (섹션 `P5A282`, 행 `XCN1f`·`Q7zmGt`) |
| A7 | 푸시 수신 · 토큰 등록 · `data.route` 로 화면 열기 | — |
| A8 | 알림 설정 · 매칭 일시중지 토글 | `NMgCa` 16d |

**남은 정리 작업:** 화면 목록(pen id) 표 · 테스트 전략 표 · 백로그 섹션.

**섹션 3 전체 pen id:** `qXpwn`.
