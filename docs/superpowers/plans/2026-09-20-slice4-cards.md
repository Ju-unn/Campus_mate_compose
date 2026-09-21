# 조각 4: 일일 카드 지급 · 수락 · 푸시 알림 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Task 0(.gitignore) → Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다.
> **Part C 는 파일 작성 + 로컬 스택 검증까지만 하고 클라우드 적용은 하지 않는다**(`[[supabase-apply-gate]]` —
> ERD 그림 · 사용자 검토 · 사용자 승인 후 별도 supabase 세션이 적용한다).
> **Part A 의 새 의존성(firebase_core · firebase_messaging · google-services Gradle 플러그인)은
> 2026-09-21 사용자 승인이 끝났다.** 다만 `google-services.json` 은 Task 0(.gitignore)이 끝나기 전에
> 프로젝트 폴더로 옮기지 않는다.

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
`firebase_core` · `firebase_messaging`(**새 의존성 — 2026-09-21 사용자 승인 완료**).

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §2.1 · §2.2 · §2.4 · §2.6 ·
§6.7 · §6.8 · §7.1, `docs/ERD.md` §2(권한 표) · §3(`region_group_settings` · `matching_paused`) · §4(조각 4~5
테이블), `frontend/docs/DESIGN.md` §8.1 · §8.2 · §8.6 · §8.9 · §9, pen
`OneDrive\Desktop\datingApp\design\datingApp.pen` §3 "카드 · 매칭 · 채팅"(`qXpwn`)

## 새 의존성 (2026-09-21 사용자 승인 완료)

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
  `filePath: "C:\\Users\\home\\OneDrive\\Desktop\\datingApp\\design\\datingApp.pen"` 의 해당 노드를
  **읽고** 시작한다. 노드 id 는 각 Task 에 적혀 있다. pen 파일은 읽기만 한다(수정 금지).
  **경로 주의(2026-09-21 확인):** 바탕화면 바로 아래의 `datingApp.pen` 에는 ERD 보드만 들어 있어
  화면을 하나도 찾을 수 없다. 화면은 `datingApp\design\` 아래 파일에 있다.

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
재노출          → 무응답 만료(expired)는 만료 시각 + 14일 뒤 다시 후보. 수락 · 거절로 결정한 상대는
                  결정 시각 + 90일 뒤 다시 후보(2026-09-21 사용자 수정 — 종전 "영구 제외" 폐기).
                  매칭이 성사된 쌍은 기간과 무관하게 영구 제외.
점수            → 조각 3 scoring.py 그대로(활동성 계수 · 흡연 0.5 · 종교 0.8 포함). 카드는 1위 1명.
하드 필터 추가  → matching_paused(일시중지) 제외 + 이미 카드로 받은 사람 제외. 차단(blocks)은 조각 6.
스케줄러        → Cloud Scheduler 1개 job → FastAPI /batch/daily-cards (아래 "실행 전 확인 사항" 1번 참조).
푸시            → FCM HTTP v1. 서버는 Cloud Run 서비스 계정(ADC)으로 보낸다.
```

## 실행 전 확인 사항 (코드 쓰기 전에 대장에게 보고 — 차이만)

**2026-09-21 사용자 확정:** 1 · 2 · 3 · 5 · 6번은 적힌 그대로 승인. **4번만 수정** — 무응답 만료는 14일,
수락 · 거절로 결정한 상대는 90일 뒤 다시 후보가 된다(종전 "영구 제외" 폐기). 새 의존성 3건도 승인됐고,
Part A 의 가정 4건(pen 경로 정정 · 09b 메인 범위 밖 · 하단 내비 오늘·대화만 · `candidate_pool_empty` 추가)도
함께 승인됐다. **아래 1~6번 본문은 그때의 판단 근거로 남겨 둔다 — 결론은 이 문단이다.**

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
4. **재노출 금지 기간 — 무응답 14일 · 결정 90일(2026-09-21 사용자 확정, 이 항목만 수정됨).**
   설계 §2.4 는 "무응답 만료만 재노출 대상 복귀"라고만 쓰고 기간을 정하지 않았다. 기간이 없으면
   **무응답 상대가 바로 다음 지급일에 또 나온다**(점수 1위는 잘 안 바뀌므로 거의 확실하다).
   14일 = 주 2회 지급 기준 3~4번의 지급을 건너뛴다.
   **수락 · 거절로 결정한 상대는 종전 "영구 제외"에서 90일로 바뀌었다** — 한 번의 거절이 평생 가지 않게
   하되, 90일(약 3개월)이면 서로를 잊을 만큼은 된다는 사용자 판단이다. **매칭이 성사된 쌍만 영구 제외**로
   남는다(`matches` 조건이 따로 막는다). 세 기간은 전부 `match_candidates` 한 함수 안에 있어
   `interval '14 days'` · `interval '90 days'` 두 곳만 고치면 바뀐다.
5. **"남녀 각각 N명" 은 둘 중 적은 쪽으로 판정한다.** 남 300 · 여 150 이면 **150 기준(주 2회)** 이다. 카드가
   성별 무관 1장씩 나가므로 적은 쪽이 후보 풀의 병목이고, 많은 쪽에 맞추면 같은 사람이 계속 카드로 나간다.
6. **아침 7시 카드 알림은 조용한 시간(22~8시) 예외로 둔다.** `notification_settings.quiet_hours` 를 그대로
   적용하면 **지급 시각 07:00 이 조용한 시간 안이라 카드 도착 알림이 영영 안 간다**. 카드 도착 알림만 예외로
   보내고(사용자가 시간을 알고 기다리는 알림이다), 받은 수락 · 매칭 성사 · 그 밖의 알림은 조용한 시간을 지킨다.
   카드 알림 자체를 끄는 스위치는 `card_arrived` 로 따로 있다(화면 `NMgCa` 행 `ojaTK`, 토글 인스턴스
   `ZXJIi` — 2026-09-21 pen 실측으로 정정, 종전 `WUdhM` 은 잘못 적힌 id 였다).

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
frontend/lib/matching/viewmodel/    A3~A8  UiState · ViewModel
frontend/lib/matching/view/         A3~A8  화면(오늘의 카드 · 10b 상세 · 12 매칭 · 13 대화 · 16·16d 설정)
frontend/lib/common/widgets/        A3·A4·A6  AppBottomNav · TraitBar · CardActionBar(+ AppButton 높이 인자)
frontend/lib/core/push/             A7  PushMessaging 래퍼 · 토큰 등록 · route 변환
frontend/lib/core/router/           A3~A8  경로 추가(HomeScreen → ComingSoonScreen)
frontend/android/ · lib/main.dart   A1  Firebase 배선(google-services.json 은 커밋하지 않는다)
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
    -- 이미 카드로 받은 사람(설계 §6.7 · 2026-09-21 사용자 확정). 세 가지를 한 번에 본다:
    --   ① 아직 결정하지 않았고 만료도 안 된 카드 → 중복 지급 방지
    --      (구매 카드는 expires_at is null 이라 결정하기 전까지 항상 여기 걸린다)
    --   ② 수락·거절로 결정한 카드 → 결정 시각 + 90일은 쉬어 간다(영구 제외가 아니다)
    --   ③ 무응답으로 만료된 카드 → 만료 시각 + 14일은 쉬어 간다
    and not exists (
      select 1
      from public.daily_cards dc
      left join public.card_decisions cd on cd.card_id = dc.id
      where dc.owner_id = me.id
        and dc.target_id = c.id
        and (
          (cd.card_id is null and (dc.expires_at is null or dc.expires_at > now()))
          or (cd.card_id is not null and cd.decided_at > now() - interval '90 days')
          or (cd.card_id is null and dc.expires_at is not null
              and dc.expires_at > now() - interval '14 days')
        )
    )
    -- 내가 수락 응답을 한 상대(= 내가 수락을 받았던 상대)도 같은 90일을 쉰다(설계 §6.7).
    -- 쌍방 수락이었다면 아래 matches 조건이 영구히 막으므로 여기서 기간을 따질 일이 없다.
    and not exists (
      select 1
      from public.acceptance_responses ar
      join public.daily_cards dc2 on dc2.id = ar.card_id
      where ar.responder_id = me.id
        and dc2.owner_id = c.id
        and ar.decided_at > now() - interval '90 days'
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
- Produces: `supabase test db` 로 도는 회귀 테스트 20건(구현에서 1건 늘었다 — 아래 "구현 편차 기록" 참고)

- [ ] **Step 1: 테스트 파일을 쓴다(먼저 실패하는 채로)**

```sql
-- 조각 4 RLS · 권한 · 하드 필터 검증. 기대값 기준은 docs/ERD.md §2 와 설계 §2.1·§2.4·§6.7.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- 준비 --------------------------------------------------------------------
-- A = ...aa(남), B = ...bb(여), P = ...pp(여·일시중지), Q = ...qq(여·무응답 만료 3일 전),
-- R = ...rr(여·무응답 만료 20일 전 → 다시 후보), S = ...ss(여·10일 전 거절 → 90일 안이라 제외),
-- T = ...tt(여·100일 전 거절 → 90일이 지나 다시 후보, 2026-09-21 사용자 확정)
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
  ('00000000-0000-0000-0000-0000000000ss', 'm4-s@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000tt', 'm4-t@test.ac.kr');

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
update public.profiles set nickname = '머버서' where id = '00000000-0000-0000-0000-0000000000tt';

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
  -- S: 10일 전에 거절한 상대 → 결정 후 90일 안이라 아직 후보가 아니다
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000ss', 'daily', now() - interval '13 days', now() - interval '10 days'),
  -- T: 100일 전에 거절한 상대 → 90일이 지나 다시 후보가 된다(2026-09-21 사용자 확정)
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000tt', 'daily', now() - interval '103 days', now() - interval '100 days');

-- decided_at 을 직접 넣는다 — 90일 경계를 보는 테스트라 기본값 now() 로는 T 를 만들 수 없다.
insert into public.card_decisions (card_id, decision, decided_at) values
  ('00000000-0000-0000-0000-00000000c003', 'reject', now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000c004', 'reject', now() - interval '100 days');

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
  0::bigint, '거절한 지 90일이 지나지 않은 상대는 아직 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000tt'),
  1::bigint, '거절한 지 90일이 지난 상대는 다시 후보가 된다'
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

- [ ] **Step 2: 돌려서 19건이 다 통과하는지 본다**

```bash
supabase db reset && supabase test db
```

Expected: `rls_slice4_test.sql .. ok`, 20/20. 실패하면 마이그레이션(C1~C5)을 고친다 — **테스트의 기대값을
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

## Part A: Flutter (`frontend/lib/matching/` · `frontend/lib/core/push/`)

**새 의존성 3건은 2026-09-21 사용자 승인이 끝났다** — Part A 착수를 막는 관문은 이제 Task 0(.gitignore)뿐이다.

새 feature 루트 `frontend/lib/matching/` 은 조각 2 의 `frontend/lib/profile/` 와 같은 모양이다 —
`model/`(불변 모델 + Repository 인터페이스 + `Http*` 구현 + Provider) · `viewmodel/`(불변 `UiState` +
Riverpod `Notifier`) · `view/`(화면). 테스트도 같은 모양을 그대로 쓴다:

| 층 | 표본 파일 | 도구 |
| --- | --- | --- |
| Repository | `test/auth/model/http_verification_gate_repository_test.dart` | `MockClient`(`package:http/testing.dart`) + `mocktail` 로 `GoTrueClient` 흉내 |
| ViewModel | `test/profile/viewmodel/ideal_note_view_model_test.dart` | `Fake*Repository` + `ProviderContainer(overrides: …)` |
| 화면 | `test/auth/view/school_info_screen_test.dart` | `UncontrolledProviderScope` + `MaterialApp(home: …)` 위젯 테스트 |

**pen 파일 경로 정정 (2026-09-21 master3 확인 — 차이 보고 대상).** 이 계획서 위쪽(Global Constraints)과
대장 지시문의 `C:\Users\home\OneDrive\Desktop\datingApp.pen` 에는 **ERD 보드만** 들어 있고 화면이 하나도
없다(`qXpwn` 을 찾을 수 없다). 화면이 있는 파일은
**`C:\Users\home\OneDrive\Desktop\datingApp\design\datingApp.pen`** 이다. 아래 Task 의 노드 id 는 전부
이 파일에서 직접 읽은 값이다. `filePath` 를 반드시 명시해서 읽고, **pen 은 읽기만 한다**.

**Part A 가정 4건 (2026-09-21 사용자 승인 완료 — Part A 를 쓰면서 새로 생긴 판단이고, 넷 다 그대로 간다)**

1. **09b 메인 화면(`bpA8x`)은 조각 4 범위 밖이다.** 09b 는 `hero-today` · `mosaic-rail` · `stat-panel` ·
   `review-strip` · `campus-strip` 으로 이루어진 별도 화면이고, 그 재료(지인 리뷰 · 참여 대학 지표)는 조각 6
   이후에 생긴다. 그래서 `lvmAj` 의 "결정 대기 카드가 2장 남아 있어요" 배너(`Diw5U`)는 **백로그**로 옮긴다 —
   배너만 먼저 만들면 붙일 화면이 없다. 카드로 가는 길은 하단 내비 "오늘" 탭이 담당한다.
2. **하단 내비(`Migf0`)는 5탭을 그리되 이번 조각이 채우는 것은 "오늘"·"대화" 두 탭뿐이다.** 메인 · 커뮤니티 ·
   나 탭은 기존 `placeholder_screens.dart` 의 자리 화면을 그대로 띄운다(각각 조각 6·6·2+). 내비 없이 만들면
   받은 수락함(13)으로 가는 길이 앱 안에 존재하지 않게 된다.
3. **설정(16, `lMDpY`)은 조각 4 가 소유한 두 줄만 만든다** — 매칭 활성화 토글(`TLrmq`)과 "알림"(→ 16d).
   나머지 11줄(하트 · 차단 · 약관 · 탈퇴 …)은 조각 5~7 이 각자 붙인다. 진입점은 **오늘 탭 앱바 우측 아이콘**
   이다. DESIGN §9 화면15 는 "내 프로필(15)의 앱바 설정 아이콘이 16 의 유일한 진입점"이라고 적지만 15 는
   조각 4 에 없다 — 15 가 생기면 진입점을 그리로 옮기고 오늘 탭에서는 뗀다(백로그).
4. **잠금 카드(`daily-card-locked` `BpP33`) · 추가 카드 시트(10c `x2yPl`) · 구매 후(10e `wDKXv`) · 결정 대기
   구매 카드(`Keynu`)는 그리지 않는다.** 전부 하트를 쓰는 화면이라 조각 7 이다(확정 전제 "하트 소비는 조각 7").
   `GET /cards/today` 의 `locked_card_available` 은 받아만 두고 이번 조각에서는 쓰지 않는다.

**Part B 보완 1건 (2026-09-21 사용자 승인 — A2 가 못 박는 계약).**
`GET /cards/today` 응답에 **`candidate_pool_empty`(bool)** 을
추가한다. 화면 11(`i4VFS` "내일 오전 7시에 새로운 한 명이 도착해요")과 11b(`iQZoa` "지금은 소개할 사람이
없어요")를 가르는 값이 지금 응답에 없다. Task B5 가 **`cards` 가 비었을 때만** `match_candidates(owner, 1)`
를 한 번 더 불러 채운다(카드가 있으면 부르지 않는다 — 평소에는 추가 쿼리가 0 이다).

---

### Task A1: 의존성 · `google-services.json` · Firebase 초기화

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `frontend/android/settings.gradle.kts`
- Modify: `frontend/android/app/build.gradle.kts`
- Modify: `frontend/android/app/src/main/AndroidManifest.xml`
- Modify: `frontend/lib/main.dart`
- Move(커밋하지 않는다): 바탕화면 `google-services.json` → `frontend/android/app/google-services.json`

**Interfaces:**
- Consumes: Task 0 의 `.gitignore`(`**/google-services.json`) — **끝나 있어야 이 Task 를 시작한다**
- Produces: `Firebase.initializeApp()` 이 끝난 앱 — Task A7 의 `FirebaseMessaging.instance` 가 이것 없이는 죽는다

- [ ] **Step 1: 파일을 옮기기 전에 git 이 막는지부터 확인**

```bash
cd frontend
git check-ignore -v android/app/google-services.json
```

Expected: `.gitignore:<줄번호>:**/google-services.json` 이 나온다. **아무것도 안 나오면 멈추고 Task 0 을 먼저
끝낸다.** 그 뒤에 파일을 옮긴다(경로는 대장이 안다).

- [ ] **Step 2: 옮긴 뒤 git 이 정말 안 보는지 다시 확인**

```bash
git status --porcelain frontend/android/app/google-services.json
```

Expected: **아무것도 출력되지 않는다.** 한 줄이라도 나오면 커밋하지 말고 멈춘다.

- [ ] **Step 3: `pubspec.yaml` 에 의존성 2개 추가**

`dependencies:` 의 `path_provider` 아래에 붙인다(승인된 표 그대로):

```yaml
  # 푸시 알림(조각 4). firebase_core 는 firebase_messaging 이 요구해서 함께 들어간다.
  firebase_core: ^4.1.1
  firebase_messaging: ^16.0.2
```

Run: `cd frontend && flutter pub get`
Expected: 오류 없이 끝난다. **버전이 표(^4.x · ^16.x)를 벗어나면 멈추고 대장에게 보고한다.**

- [ ] **Step 4: Gradle 플러그인 배선(Kotlin DSL 2곳)**

`android/settings.gradle.kts` 의 `plugins { … }` 블록 맨 아래에 한 줄:

```kotlin
    id("com.google.gms.google-services") version "4.4.4" apply false
```

`android/app/build.gradle.kts` 의 `plugins { … }` 블록 맨 아래에 한 줄(Flutter 플러그인 **뒤**여야 한다):

```kotlin
    id("com.google.gms.google-services")
```

- [ ] **Step 5: 매니페스트에 알림 권한과 기본 채널을 적는다**

`android/app/src/main/AndroidManifest.xml` — `<manifest>` 바로 아래에 권한 한 줄,
`<application>` 안(`<activity>` 뒤)에 메타데이터 두 줄:

```xml
    <!-- Android 13+ 는 알림을 보내기 전에 사용자에게 물어봐야 한다(조각 4). -->
    <uses-permission android:name="android.permission.POST_NOTIFICATION" />
```

```xml
        <!-- 앱이 꺼져 있을 때 시스템이 알림을 띄울 채널. 지정하지 않으면 안드로이드가 경고를 남긴다. -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="campus_mate_default" />
```

**주의:** 권한 이름은 `android.permission.POST_NOTIFICATIONS`(복수형 S)다 — 위 블록을 그대로 붙여 넣은 뒤
**`POST_NOTIFICATION` 을 `POST_NOTIFICATIONS` 로 고친다**(오타가 나면 권한 요청이 조용히 무시된다).

- [ ] **Step 6: `main.dart` 에서 Firebase 를 켠다**

`main()` 의 `SupabaseInitializer.run(...)` **앞**에 한 줄을 넣는다:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 안드로이드는 google-services 플러그인이 넣어 준 리소스를 읽으므로 options 를 코드에 적지 않는다
  // (firebase_options.dart 를 만들지 않는 이유 — flutterfire CLI 를 새로 들이지 않는다).
  await Firebase.initializeApp();
  await SupabaseInitializer.run(SupabaseConfig.fromEnvironment());
  runApp(const ProviderScope(child: CampusMateApp()));
}
```

`import 'package:firebase_core/firebase_core.dart';` 를 함께 추가한다.

- [ ] **Step 7: 앱이 실제로 빌드되는지 본다 (이 Task 의 유일한 검증)**

```bash
cd frontend
flutter analyze
flutter test
flutter build apk --debug
```

Expected: `analyze` 무경고 · `flutter test` **280 passed**(기준선, 줄면 무언가 깨진 것이다) ·
APK 빌드 성공. 빌드가 `google-services.json` 을 못 찾는다고 하면 Step 1~2 로 돌아간다.

로직이 없는 배선 Task 라 단위 테스트를 새로 쓰지 않는다 — **빌드가 곧 테스트**다.

- [ ] **Step 8: 커밋**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/android/settings.gradle.kts \
        frontend/android/app/build.gradle.kts frontend/android/app/src/main/AndroidManifest.xml \
        frontend/lib/main.dart
git commit -m "🔔 feat(slice4): Firebase 메시징 의존성과 초기화를 붙인다"
```

`git status` 로 **`google-services.json` 이 스테이징되지 않았는지 눈으로 확인한 뒤** 커밋한다.

---

### Task A2: 카드 모델 · Repository · Provider

**Files:**
- Create: `frontend/lib/matching/model/card_profile.dart`
- Create: `frontend/lib/matching/model/daily_card.dart`
- Create: `frontend/lib/matching/model/card_detail.dart`
- Create: `frontend/lib/matching/model/acceptance.dart`
- Create: `frontend/lib/matching/model/notification_preferences.dart`
- Create: `frontend/lib/matching/model/card_repository.dart`
- Create: `frontend/lib/matching/model/http_card_repository.dart`
- Create: `frontend/lib/matching/model/card_repository_provider.dart`
- Test: `frontend/test/matching/model/http_card_repository_test.dart`

**Interfaces:**
- Consumes: Task B5 `GET /cards/today` · `GET /cards/{card_id}` · `POST /cards/{card_id}/decision`,
  Task B6 `GET /cards/acceptances` · `POST /cards/acceptances/{card_id}`,
  Task B7 `POST·DELETE /cards/push-tokens` · `GET·PATCH /cards/notification-settings` ·
  `PATCH /cards/matching-paused`
- Produces: `CardRepository`(추상) · `CardProfile` · `DailyCard` · `TodayCards` · `CardDetail` ·
  `Acceptance` · `AcceptanceOutcome` · `NotificationPreferences` · `cardRepositoryProvider` —
  Task A3~A8 이 전부 이 이름만 쓴다.
- **Produces(계약): `GET /cards/{card_id}` 응답 모양.** Task B5 가 이 모양으로 내려보내야 한다:

```json
{"card_id": "…", "profile": {"profile_id": "…", "nickname": "여우비", "age": 23,
                             "university": "테스트대학교", "major": "컴퓨터공학과",
                             "avatar_url": "https://…"},
 "survey": [0.5, -1.0, 0.0, 0.5, 1.0, -0.5, 0.0, 0.5, 1.0],
 "animal_type": "cat", "impression_type": "chic",
 "height_cm": 178, "mbti": "ENFP", "student_number": "21",
 "religion": "none", "is_smoker": false,
 "interests": ["등산", "재즈"], "my_traits": ["유머러스"], "ideal_traits": ["다정한"],
 "bio": "…", "ideal_note": "…"}
```

`survey` 는 **9축 순서 그대로의 배열**이다(05-01 활동성 … 05-09 새로움 — `survey_vector.py` 의 축 번호
1~9 와 같은 순서, 낯가림 2번 축도 표시에는 그대로 들어간다). `animal_type`·`impression_type`·`religion`
문자열은 **조각 2 `frontend/lib/profile/model/profile_enums.dart` 의 `name`** 과 같은 값이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// frontend/test/matching/model/http_card_repository_test.dart
import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/http_card_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpCardRepository buildRepository(http.Client client) {
    return HttpCardRepository('https://api.test', client, auth);
  }

  http.Response jsonResponse(Object body) {
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  test('오늘의 카드를 프로필까지 붙여 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/cards/today');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'cards': [
          {
            'card_id': 'card-1',
            'source': 'daily',
            'expires_at': '2026-09-24T07:00:00+09:00',
            'profile': {
              'profile_id': 't1',
              'nickname': '여우비',
              'age': 23,
              'university': '테스트대학교',
              'major': '컴퓨터공학과',
              'avatar_url': 'https://cdn.test/a.png',
            },
          },
        ],
        'next_issue_at': '2026-09-24T07:00:00+09:00',
        'locked_card_available': true,
        'candidate_pool_empty': false,
      });
    });

    final result = await buildRepository(client).fetchToday();

    final today = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(today!.cards.single.profile.nameWithAge, '여우비, 23');
    expect(today.cards.single.profile.schoolLine, '테스트대학교 · 컴퓨터공학과');
    expect(today.nextIssueAt, DateTime.parse('2026-09-24T07:00:00+09:00'));
  });

  test('카드가 하나도 없고 후보 풀도 비었으면 그 사실이 그대로 올라온다', () async {
    final client = MockClient((request) async => jsonResponse({
          'cards': <Object>[],
          'next_issue_at': null,
          'locked_card_available': false,
          'candidate_pool_empty': true,
        }));

    final result = await buildRepository(client).fetchToday();

    final today = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(today!.cards, isEmpty);
    expect(today.candidatePoolEmpty, isTrue);
  });

  test('결정은 decision 값을 그대로 보낸다', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request as http.Request;
      return jsonResponse({'ok': true});
    });

    await buildRepository(client).decide('card-1', CardDecision.reject);

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.test/cards/card-1/decision');
    expect(jsonDecode(sent.body), {'decision': 'reject'});
  });

  test('수락함 응답이 매칭으로 이어지면 match_id 가 올라온다', () async {
    final client = MockClient((request) async => jsonResponse({'matched': true, 'match_id': 'm-1'}));

    final result = await buildRepository(client).respondToAcceptance('card-1', CardDecision.accept);

    final outcome = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(outcome!.matched, isTrue);
    expect(outcome.matchId, 'm-1');
  });

  test('기한이 지난 수락(410)은 서버 문구를 그대로 보여준다', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({'detail': '기한이 지났어요'}),
          410,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    final result = await buildRepository(client).respondToAcceptance('card-1', CardDecision.accept);

    expect(
      result.when(onSuccess: (_) => null, onFailure: (f) => f.toDisplayMessage()),
      '기한이 지났어요',
    );
  });

  test('연결이 끊겨도 예외가 새지 않고 NetworkFailure 로 돌아온다', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).fetchToday();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/model/http_card_repository_test.dart`
Expected: FAIL — `card_repository.dart` 를 찾을 수 없다(컴파일 오류)

- [ ] **Step 3: 모델을 쓴다**

```dart
// frontend/lib/matching/model/card_profile.dart
/// 카드 앞면·수락함 행이 쓰는 최소 프로필(설계 §7.1 — 실명·연락처는 서버가 내려보내지 않는다).
class CardProfile {
  const CardProfile({
    required this.profileId,
    required this.nickname,
    required this.age,
    this.university,
    this.major,
    this.avatarUrl,
  });

  final String profileId;
  final String nickname;
  final int age;
  final String? university;
  final String? major;

  /// 표시용 만화 아바타. 실사진은 신뢰 확인(조각 5) 전까지 존재하지 않는다(§5.2).
  final String? avatarUrl;

  /// pen `eWD7g` 가 "여우비, 23" 한 줄로 쓴다.
  String get nameWithAge => '$nickname, $age';

  /// pen `Q8c2Y3` 가 "서울대학교 · 컴퓨터공학과" 한 줄로 쓴다. 한쪽이 비면 가운뎃점도 없앤다.
  String get schoolLine => [university, major].whereType<String>().join(' · ');

  factory CardProfile.fromJson(Map<String, dynamic> json) {
    return CardProfile(
      profileId: json['profile_id'] as String,
      nickname: json['nickname'] as String,
      age: json['age'] as int,
      university: json['university'] as String?,
      major: json['major'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
```

```dart
// frontend/lib/matching/model/daily_card.dart
import 'package:campus_mate/matching/model/card_profile.dart';

/// 카드가 어디서 왔는지(ERD `card_source`). 구매 카드는 조각 7 에서 생긴다.
enum CardSource {
  daily,
  purchased;

  static CardSource fromWire(String value) => value == 'purchased' ? purchased : daily;
}

/// 받은 카드 한 장(화면 10 `W0CjO`).
class DailyCard {
  const DailyCard({
    required this.cardId,
    required this.source,
    required this.profile,
    this.expiresAt,
  });

  final String cardId;
  final CardSource source;
  final CardProfile profile;

  /// 무응답 만료 시각. 구매 카드는 만료가 없어 null 이다(설계 §2.4).
  final DateTime? expiresAt;

  factory DailyCard.fromJson(Map<String, dynamic> json) {
    return DailyCard(
      cardId: json['card_id'] as String,
      source: CardSource.fromWire(json['source'] as String),
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      expiresAt: _parseTime(json['expires_at']),
    );
  }
}

/// `GET /cards/today` 응답 전체(화면 10 · 11 · 11b 가 이 하나로 갈린다).
class TodayCards {
  const TodayCards({
    required this.cards,
    this.nextIssueAt,
    this.lockedCardAvailable = false,
    this.candidatePoolEmpty = false,
  });

  final List<DailyCard> cards;

  /// 다음 지급 시각. 화면 11 의 카운트다운 재료다.
  final DateTime? nextIssueAt;

  /// 잠금 카드를 열 후보가 남아 있는지. **조각 7(하트) 전까지는 읽지 않는다.**
  final bool lockedCardAvailable;

  /// 후보 풀 자체가 비었는지. 화면 11(`i4VFS`)과 11b(`iQZoa`)를 가르는 값이다.
  final bool candidatePoolEmpty;

  factory TodayCards.fromJson(Map<String, dynamic> json) {
    return TodayCards(
      cards: (json['cards'] as List<dynamic>)
          .map((card) => DailyCard.fromJson(card as Map<String, dynamic>))
          .toList(),
      nextIssueAt: _parseTime(json['next_issue_at']),
      lockedCardAvailable: json['locked_card_available'] as bool? ?? false,
      candidatePoolEmpty: json['candidate_pool_empty'] as bool? ?? false,
    );
  }
}

DateTime? _parseTime(Object? value) => value == null ? null : DateTime.parse(value as String);
```

```dart
// frontend/lib/matching/model/card_detail.dart
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 10b 상대 프로필 상세(`TORAs`). 카드 앞면보다 많은 것을 보여주지만
/// 실사진·카카오톡 아이디는 여전히 없다 — 그건 신뢰 확인(조각 5) 뒤다.
class CardDetail {
  const CardDetail({
    required this.cardId,
    required this.profile,
    required this.survey,
    required this.animalType,
    required this.impressionType,
    required this.religion,
    required this.isSmoker,
    required this.interests,
    required this.myTraits,
    required this.idealTraits,
    this.heightCm,
    this.mbti,
    this.studentNumber,
    this.bio,
    this.idealNote,
  });

  final String cardId;
  final CardProfile profile;

  /// 9축 성향 값(-1.0 ~ 1.0). 축 순서는 05-01 활동성 … 05-09 새로움이다.
  final List<double> survey;
  final AnimalType animalType;
  final ImpressionType impressionType;
  final Religion religion;
  final bool isSmoker;
  final List<String> interests;
  final List<String> myTraits;
  final List<String> idealTraits;
  final int? heightCm;
  final String? mbti;
  final String? studentNumber;
  final String? bio;
  final String? idealNote;

  factory CardDetail.fromJson(Map<String, dynamic> json) {
    return CardDetail(
      cardId: json['card_id'] as String,
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      survey: (json['survey'] as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
      animalType: AnimalType.values.byName(json['animal_type'] as String),
      impressionType: ImpressionType.values.byName(json['impression_type'] as String),
      religion: Religion.values.byName(json['religion'] as String),
      isSmoker: json['is_smoker'] as bool,
      interests: _strings(json['interests']),
      myTraits: _strings(json['my_traits']),
      idealTraits: _strings(json['ideal_traits']),
      heightCm: json['height_cm'] as int?,
      mbti: json['mbti'] as String?,
      studentNumber: json['student_number'] as String?,
      bio: json['bio'] as String?,
      idealNote: json['ideal_note'] as String?,
    );
  }
}

List<String> _strings(Object? value) =>
    (value as List<dynamic>? ?? const []).map((v) => v as String).toList();
```

```dart
// frontend/lib/matching/model/acceptance.dart
import 'package:campus_mate/matching/model/card_profile.dart';

/// 나를 수락한 사람 한 명(13 대화 화면의 수락 대기 행 `XCN1f`).
/// 7일이 지난 수락은 서버가 아예 내려보내지 않는다 — 앱은 만료를 계산하지 않는다.
class Acceptance {
  const Acceptance({required this.cardId, required this.profile, this.expiresAt});

  final String cardId;
  final CardProfile profile;
  final DateTime? expiresAt;

  factory Acceptance.fromJson(Map<String, dynamic> json) {
    return Acceptance(
      cardId: json['card_id'] as String,
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// 수락함에 응답한 결과. 쌍방 수락이면 [matched] 가 참이고 [matchId] 가 채워진다.
class AcceptanceOutcome {
  const AcceptanceOutcome({required this.matched, this.matchId});

  final bool matched;
  final String? matchId;

  factory AcceptanceOutcome.fromJson(Map<String, dynamic> json) {
    return AcceptanceOutcome(
      matched: json['matched'] as bool,
      matchId: json['match_id'] as String?,
    );
  }
}
```

```dart
// frontend/lib/matching/model/notification_preferences.dart
/// 알림 스위치(화면 16d `NMgCa`). 서버에 행이 없으면 전부 켜짐 + 마케팅만 꺼짐이다(Task C4 기본값).
class NotificationPreferences {
  const NotificationPreferences({
    this.cardArrived = true,
    this.acceptanceReceived = true,
    this.matchMade = true,
    this.newMessage = true,
    this.trustReminder = true,
    this.newFriendReview = true,
    this.marketing = false,
    this.quietHours = true,
  });

  final bool cardArrived;
  final bool acceptanceReceived;
  final bool matchMade;
  final bool newMessage;
  final bool trustReminder;
  final bool newFriendReview;
  final bool marketing;
  final bool quietHours;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool read(String key, {bool fallback = true}) => json[key] as bool? ?? fallback;
    return NotificationPreferences(
      cardArrived: read('card_arrived'),
      acceptanceReceived: read('acceptance_received'),
      matchMade: read('match_made'),
      newMessage: read('new_message'),
      trustReminder: read('trust_reminder'),
      newFriendReview: read('new_friend_review'),
      marketing: read('marketing', fallback: false),
      quietHours: read('quiet_hours'),
    );
  }

  NotificationPreferences withValue(String key, bool value) {
    return NotificationPreferences(
      cardArrived: key == 'card_arrived' ? value : cardArrived,
      acceptanceReceived: key == 'acceptance_received' ? value : acceptanceReceived,
      matchMade: key == 'match_made' ? value : matchMade,
      newMessage: key == 'new_message' ? value : newMessage,
      trustReminder: key == 'trust_reminder' ? value : trustReminder,
      newFriendReview: key == 'new_friend_review' ? value : newFriendReview,
      marketing: key == 'marketing' ? value : marketing,
      quietHours: key == 'quiet_hours' ? value : quietHours,
    );
  }

  bool valueOf(String key) => switch (key) {
        'card_arrived' => cardArrived,
        'acceptance_received' => acceptanceReceived,
        'match_made' => matchMade,
        'new_message' => newMessage,
        'trust_reminder' => trustReminder,
        'new_friend_review' => newFriendReview,
        'marketing' => marketing,
        _ => quietHours,
      };
}
```

- [ ] **Step 4: Repository 인터페이스와 HTTP 구현을 쓴다**

```dart
// frontend/lib/matching/model/card_repository.dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';

/// 수락·거절 한 쌍. 카드 결정과 수락함 응답이 같은 값을 쓴다(ERD `card_decision`).
enum CardDecision {
  accept,
  reject;

  String get wire => name;
}

/// 조각 4 가 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
abstract interface class CardRepository {
  Future<Result<TodayCards>> fetchToday();
  Future<Result<CardDetail>> fetchCard(String cardId);
  Future<Result<void>> decide(String cardId, CardDecision decision);
  Future<Result<List<Acceptance>>> fetchAcceptances();
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision);
  Future<Result<void>> registerPushToken(String token);
  Future<Result<void>> deletePushToken(String token);
  Future<Result<NotificationPreferences>> fetchNotificationPreferences();
  Future<Result<void>> updateNotificationPreference(String key, bool value);
  Future<Result<void>> setMatchingPaused(bool paused);
}
```

```dart
// frontend/lib/matching/model/http_card_repository.dart
import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [CardRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// 조각 1b 의 [sendAuthorizedRequest] 가 이미 하므로 여기서는 URL·바디·파싱만 맡는다.
class HttpCardRepository implements CardRepository {
  const HttpCardRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  Future<Result<T>> _send<T>(
    String method,
    String path,
    T Function(Object body) parse, {
    Map<String, Object?>? body,
  }) async {
    final result = await sendAuthorizedRequest(_client, _auth, (accessToken) {
      final request = http.Request(method, Uri.parse('$_baseUrl$path'))
        ..headers['Authorization'] = 'Bearer $accessToken';
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      return request;
    });
    return result.when(
      onSuccess: (response) => Success(parse(jsonDecode(response.body))),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<Result<TodayCards>> fetchToday() =>
      _send('GET', '/cards/today', (body) => TodayCards.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) =>
      _send('GET', '/cards/$cardId', (body) => CardDetail.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) => _send(
        'POST',
        '/cards/$cardId/decision',
        (_) {},
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() => _send(
        'GET',
        '/cards/acceptances',
        (body) => ((body as Map<String, dynamic>)['acceptances'] as List<dynamic>)
            .map((item) => Acceptance.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) =>
      _send(
        'POST',
        '/cards/acceptances/$cardId',
        (body) => AcceptanceOutcome.fromJson(body as Map<String, dynamic>),
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<void>> registerPushToken(String token) =>
      _send('POST', '/cards/push-tokens', (_) {}, body: {'token': token, 'platform': 'android'});

  @override
  Future<Result<void>> deletePushToken(String token) =>
      _send('DELETE', '/cards/push-tokens/$token', (_) {});

  @override
  Future<Result<NotificationPreferences>> fetchNotificationPreferences() => _send(
        'GET',
        '/cards/notification-settings',
        (body) => NotificationPreferences.fromJson(body as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> updateNotificationPreference(String key, bool value) =>
      _send('PATCH', '/cards/notification-settings', (_) {}, body: {key: value});

  @override
  Future<Result<void>> setMatchingPaused(bool paused) =>
      _send('PATCH', '/cards/matching-paused', (_) {}, body: {'paused': paused});
}
```

```dart
// frontend/lib/matching/model/card_repository_provider.dart
import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/http_card_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return HttpCardRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
```

- [ ] **Step 5: 통과 확인**

Run: `cd frontend && flutter test test/matching/model/http_card_repository_test.dart`
Expected: 6 passed

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/matching/model frontend/test/matching/model
git commit -m "✨ feat(slice4): 카드 모델과 저장소를 추가한다"
```

---

### Task A3: 오늘의 카드 화면 · 하단 내비 · 라우트

**Files:**
- Create: `frontend/lib/matching/viewmodel/today_cards_ui_state.dart`
- Create: `frontend/lib/matching/viewmodel/today_cards_view_model.dart`
- Create: `frontend/lib/matching/view/today_cards_screen.dart`
- Create: `frontend/lib/matching/view/daily_card_summary.dart`
- Create: `frontend/lib/common/widgets/app_bottom_nav.dart`
- Modify: `frontend/lib/core/router/app_routes.dart`
- Modify: `frontend/lib/core/router/app_router.dart`
- Modify: `frontend/lib/core/router/placeholder_screens.dart`(`HomeScreen` 삭제)
- Modify: `frontend/lib/core/router/auth_redirect.dart`(주석만 — `home` 이 이제 오늘의 카드다)
- Test: `frontend/test/matching/model/fake_card_repository.dart`
- Test: `frontend/test/matching/viewmodel/today_cards_view_model_test.dart`
- Test: `frontend/test/matching/view/today_cards_screen_test.dart`
- Test: `frontend/test/core/router/placeholder_screens_test.dart`(`HomeScreen` 케이스 제거)

**Interfaces:**
- Consumes: Task A2 `cardRepositoryProvider`
- Produces: `todayCardsViewModelProvider`(A7 의 푸시 수신이 `refresh()` 를 부른다) ·
  `AppRoutes.cardDetail`(`/cards/:cardId`) · `AppRoutes.conversations`(`/conversations`) ·
  `AppBottomNav`(A6 의 13 화면이 같은 위젯을 쓴다)

**pen (읽고 시작한다 — `…\datingApp\design\datingApp.pen`)**

| 화면 | 노드 | 쓰는 것 |
| --- | --- | --- |
| 10 오늘의 카드 | `W0CjO` | 앱바 `KJyqC`(ref `YTDwe`) · 본문 `ECqGe` · 요약 카드 `X3jQt1`(ref `v26S7z`) · 하단 내비 `dSsgj`(ref `Migf0`) |
| 10 추가 카드 없음 | `eDPkz` | 요약 카드 1장만(`CnP1B`) — 이번 조각이 그리는 기본 모양이다 |
| 10 로딩 | `Ukg21` | `N4wO4` 안에 `Skeleton · Card`(ref `x4FuK`) 2장 |
| 11 카드 대기 | `i4VFS` | `xpiH6` "오늘 카드는 확인했어요" · `k1jPSY` "내일 오전 7시에 새로운 한 명이 도착해요" · `RcOFN` 카운트다운 · 마스코트 `XDUao`(ref `PKbwO`) |
| 11 다음 후보 없음 | `k2fF9y` | 같은 모양, 부제만 `exnx7` "월요일 오전 7시에 새로운 사람을 찾아볼게요" |
| 11b 후보 없음 | `iQZoa` | `kt3O8` "지금은 소개할 사람이 없어요" · `tdnaR` 2줄 설명 · 마스코트 2개(`gc8xO`·`Ev7dZ`) · 버튼 2개(`fqMl2`·`o1cRB`) |
| DailyCardSummary | `v26S7z` | `kaRGO` 배지 행 · `JvMzE` 아바타 96dp · `eWD7g` "여우비, 23" · `Q8c2Y3` 학교·학과 · `t4484l` "프로필 자세히 보기 ›" |
| BottomNav | `Migf0` | 탭 5개 — `DfsQO` 메인(house) · `FrwCV` 오늘(heart) · `fv6Kq` 커뮤니티(users) · `oaD2e` 대화(message-circle) · `eTvYk` 나(user-round) |

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// frontend/test/matching/model/fake_card_repository.dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';

/// 화면·ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeCardRepository implements CardRepository {
  Result<TodayCards> today = const Success(TodayCards(cards: []));
  Result<CardDetail>? card;
  Result<List<Acceptance>> acceptances = const Success([]);
  Result<AcceptanceOutcome> acceptanceOutcome = const Success(AcceptanceOutcome(matched: false));
  Result<void> writeResult = const Success(null);
  Result<NotificationPreferences> preferences = const Success(NotificationPreferences());

  int fetchTodayCount = 0;
  final List<({String cardId, CardDecision decision})> decisions = [];
  final List<({String key, bool value})> preferenceUpdates = [];
  final List<String> registeredTokens = [];
  final List<String> deletedTokens = [];
  bool? pausedValue;

  @override
  Future<Result<TodayCards>> fetchToday() async {
    fetchTodayCount += 1;
    return today;
  }

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) async => card!;

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
    return writeResult;
  }

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() async => acceptances;

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
    return acceptanceOutcome;
  }

  @override
  Future<Result<void>> registerPushToken(String token) async {
    registeredTokens.add(token);
    return writeResult;
  }

  @override
  Future<Result<void>> deletePushToken(String token) async {
    deletedTokens.add(token);
    return writeResult;
  }

  @override
  Future<Result<NotificationPreferences>> fetchNotificationPreferences() async => preferences;

  @override
  Future<Result<void>> updateNotificationPreference(String key, bool value) async {
    preferenceUpdates.add((key: key, value: value));
    return writeResult;
  }

  @override
  Future<Result<void>> setMatchingPaused(bool paused) async {
    pausedValue = paused;
    return writeResult;
  }
}
```

```dart
// frontend/test/matching/viewmodel/today_cards_view_model_test.dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _profile = CardProfile(profileId: 't1', nickname: '여우비', age: 23);
const _card = DailyCard(cardId: 'card-1', source: CardSource.daily, profile: _profile);

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  Future<TodayCardsUiState> load() async {
    await container.read(todayCardsViewModelProvider.notifier).refresh();
    return container.read(todayCardsViewModelProvider);
  }

  test('카드가 있으면 카드 상태가 된다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));

    final state = await load();

    expect(state.phase, TodayCardsPhase.cards);
    expect(state.cards.single.cardId, 'card-1');
  });

  test('카드가 없고 다음 지급일이 있으면 대기 상태다 (화면 11)', () async {
    repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7)));

    final state = await load();

    expect(state.phase, TodayCardsPhase.waiting);
  });

  test('후보 풀이 비었으면 대기가 아니라 "소개할 사람 없음"이다 (화면 11b)', () async {
    repository.today = Success(
      TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7), candidatePoolEmpty: true),
    );

    final state = await load();

    expect(state.phase, TodayCardsPhase.noCandidates);
  });

  test('실패하면 오류 문구를 들고 실패 상태가 된다', () async {
    repository.today = const FailureResult(NetworkFailure());

    final state = await load();

    expect(state.phase, TodayCardsPhase.failed);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('결정하면 목록을 다시 읽는다 — 카드가 사라진 화면을 남기지 않는다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));
    await load();

    await container.read(todayCardsViewModelProvider.notifier).markDecided();

    expect(repository.fetchTodayCount, 2);
  });
}
```

```dart
// frontend/test/matching/view/today_cards_screen_test.dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeCardRepository repository) async {
    final container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TodayCardsScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('카드가 있으면 닉네임·나이와 학교 줄을 보여준다', (tester) async {
    final repository = FakeCardRepository()
      ..today = const Success(
        TodayCards(
          cards: [
            DailyCard(
              cardId: 'card-1',
              source: CardSource.daily,
              profile: CardProfile(
                profileId: 't1',
                nickname: '여우비',
                age: 23,
                university: '테스트대학교',
                major: '컴퓨터공학과',
              ),
            ),
          ],
        ),
      );

    await pump(tester, repository);

    expect(find.text('여우비, 23'), findsOneWidget);
    expect(find.text('테스트대학교 · 컴퓨터공학과'), findsOneWidget);
    expect(find.text('프로필 자세히 보기'), findsOneWidget);
  });

  testWidgets('후보 풀이 비면 11b 문구를 보여준다', (tester) async {
    final repository = FakeCardRepository()
      ..today = const Success(TodayCards(cards: [], candidatePoolEmpty: true));

    await pump(tester, repository);

    expect(find.text('지금은 소개할 사람이 없어요'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching`
Expected: FAIL — `today_cards_view_model.dart` 없음(컴파일 오류)

- [ ] **Step 3: UiState 와 ViewModel 을 쓴다**

```dart
// frontend/lib/matching/viewmodel/today_cards_ui_state.dart
import 'package:campus_mate/matching/model/daily_card.dart';

/// 오늘 탭이 그릴 수 있는 다섯 모양. 화면은 이 값 하나로 갈린다.
enum TodayCardsPhase {
  /// 첫 조회 중 — `Skeleton · Card` 2장(화면 `Ukg21`)
  loading,

  /// 받은 카드가 있다(화면 `W0CjO`·`eDPkz`)
  cards,

  /// 오늘 몫은 끝났고 다음 지급일을 기다린다(화면 `i4VFS`)
  waiting,

  /// 후보 풀 자체가 비었다(화면 `iQZoa`)
  noCandidates,

  /// 조회 실패 — 다시 시도 버튼
  failed,
}

class TodayCardsUiState {
  const TodayCardsUiState({
    this.phase = TodayCardsPhase.loading,
    this.cards = const [],
    this.nextIssueAt,
    this.errorMessage,
  });

  final TodayCardsPhase phase;
  final List<DailyCard> cards;
  final DateTime? nextIssueAt;
  final String? errorMessage;
}
```

```dart
// frontend/lib/matching/viewmodel/today_cards_view_model.dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final todayCardsViewModelProvider =
    NotifierProvider<TodayCardsViewModel, TodayCardsUiState>(TodayCardsViewModel.new);

/// 오늘 탭(DESIGN.md 화면 10·11·11b)의 흐름을 맡는다.
class TodayCardsViewModel extends Notifier<TodayCardsUiState> {
  @override
  TodayCardsUiState build() {
    // 화면이 붙자마자 한 번 읽는다. 결과가 오기 전까지는 loading 이다.
    Future.microtask(refresh);
    return const TodayCardsUiState();
  }

  Future<void> refresh() async {
    final result = await ref.read(cardRepositoryProvider).fetchToday();
    state = result.when(
      onSuccess: _fromToday,
      onFailure: (failure) => TodayCardsUiState(
        phase: TodayCardsPhase.failed,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  /// 10b 에서 결정하고 돌아왔을 때. 결정한 카드가 그대로 남아 있으면 안 된다.
  Future<void> markDecided() => refresh();

  TodayCardsUiState _fromToday(TodayCards today) {
    if (today.cards.isNotEmpty) {
      return TodayCardsUiState(
        phase: TodayCardsPhase.cards,
        cards: today.cards,
        nextIssueAt: today.nextIssueAt,
      );
    }
    return TodayCardsUiState(
      // 후보가 아예 없으면 기다려도 오지 않는다 — 기다리라고 쓰지 않는다(화면 11b).
      phase: today.candidatePoolEmpty ? TodayCardsPhase.noCandidates : TodayCardsPhase.waiting,
      nextIssueAt: today.nextIssueAt,
    );
  }
}
```

- [ ] **Step 4: 요약 카드 위젯을 쓴다**

```dart
// frontend/lib/matching/view/daily_card_summary.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:flutter/material.dart';

/// 요약 카드(DESIGN.md §8.1 `daily-card-summary`, pen `v26S7z`).
/// 카드 전체가 탭 영역이고, 누르면 10b 상세로 이동한다 — 여기에 액션 바는 없다.
class DailyCardSummary extends StatelessWidget {
  const DailyCardSummary({required this.card, required this.onTap, super.key});

  final DailyCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.hairlineSoft),
          boxShadow: AppElevation.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BadgeRow(card: card),
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(card: card),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.hairlineSoft),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '프로필 자세히 보기',
                  style: AppTypography.label.copyWith(color: AppColors.primaryText),
                ),
                const Icon(AppIcons.chevronRight, size: 18, color: AppColors.primaryText),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// pen `kaRGO`. 이번 조각에서 켜지는 배지는 "학생 인증" 하나다 —
/// 구매 카드 배지는 조각 7, "무료 카드 초기화" 배지는 다음 지급 시각을 카드마다 들고 있어야 해서 백로그다.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.card});

  final DailyCard card;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceInk,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.badgeCheck, size: 13, color: AppColors.onInk),
              const SizedBox(width: AppSpacing.xxs),
              Text('학생 인증', style: AppTypography.badge.copyWith(color: AppColors.onInk)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.card});

  final DailyCard card;

  @override
  Widget build(BuildContext context) {
    final profile = card.profile;
    return Row(
      children: [
        _Avatar(url: profile.avatarUrl),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.nameWithAge, style: AppTypography.title.copyWith(color: AppColors.ink)),
              Text(
                profile.schoolLine,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 96dp 원형 + 흰 링 3px(§8.1). 아바타가 아직 없는 사람은 회색 원으로 둔다.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceStrong,
        border: Border.all(color: AppColors.canvas, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}
```

- [ ] **Step 5: 하단 내비를 쓴다**

```dart
// frontend/lib/common/widgets/app_bottom_nav.dart
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 하단 내비(DESIGN.md §8.9, pen `Migf0`). 탭 5개는 시안 그대로 두고,
/// 조각 4 가 채우는 것은 "오늘"·"대화" 둘뿐이다 — 나머지는 자리 화면으로 간다.
enum AppTab { main, today, community, chat, me }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({required this.current, super.key});

  final AppTab current;

  static const _routes = <AppTab, String>{
    AppTab.main: AppRoutes.home,
    AppTab.today: AppRoutes.today,
    AppTab.community: AppRoutes.community,
    AppTab.chat: AppRoutes.conversations,
    AppTab.me: AppRoutes.myProfile,
  };

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: AppTab.values.indexOf(current),
      onDestinationSelected: (index) => context.go(_routes[AppTab.values[index]]!),
      backgroundColor: AppColors.canvas,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        AppTypography.caption.copyWith(color: AppColors.muted),
      ),
      destinations: const [
        NavigationDestination(icon: Icon(AppIcons.house), label: '메인'),
        NavigationDestination(
          icon: Icon(AppIcons.heart),
          selectedIcon: Icon(AppIcons.heart, color: AppColors.primary),
          label: '오늘',
        ),
        NavigationDestination(icon: Icon(AppIcons.users), label: '커뮤니티'),
        NavigationDestination(icon: Icon(AppIcons.messageCircle), label: '대화'),
        NavigationDestination(icon: Icon(AppIcons.userRound), label: '나'),
      ],
    );
  }
}
```

- [ ] **Step 6: 화면과 라우트를 쓴다**

`app_routes.dart` 에 상수 6개를 더한다(`home` 은 09b 메인 자리 화면 그대로 둔다):

```dart
  /// 조각 4 — 오늘의 카드(화면 10), 카드 상세(10b), 매칭 성사(12), 대화(13), 설정(16)·알림(16d)
  static const String today = '/today';
  static const String cardDetail = '/cards'; // `/cards/:cardId`
  static const String matchMade = '/match-made';
  static const String conversations = '/conversations';
  static const String settings = '/settings';
  static const String notificationSettings = '/settings/notifications';

  /// 아직 화면이 없는 탭 — 자리 화면으로 보낸다(커뮤니티 조각 6, 내 프로필 후속)
  static const String community = '/community';
  static const String myProfile = '/me';
```

`app_router.dart` 의 `_routes()` 에 더한다:

```dart
      GoRoute(path: AppRoutes.today, builder: (context, state) => const TodayCardsScreen()),
      GoRoute(
        path: '${AppRoutes.cardDetail}/:cardId',
        builder: (context, state) => CardDetailScreen(cardId: state.pathParameters['cardId']!),
      ),
      GoRoute(path: AppRoutes.conversations, builder: (context, state) => const ConversationsScreen()),
      GoRoute(path: AppRoutes.community, builder: (context, state) => const ComingSoonScreen(tab: AppTab.community)),
      GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const ComingSoonScreen(tab: AppTab.me)),
```

`placeholder_screens.dart` 의 `HomeScreen` 은 **오늘의 카드가 실물이 됐으므로 이름만 남기지 않고 지운다.**
대신 아직 화면이 없는 탭을 위한 자리 화면 하나를 둔다:

```dart
/// 아직 만들지 않은 탭(메인 09b·커뮤니티·나). 하단 내비는 5탭을 그리므로 갈 곳은 있어야 한다.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.tab, super.key});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('곧 만나요', style: AppTypography.headline)),
      bottomNavigationBar: AppBottomNav(current: tab),
    );
  }
}
```

`AppRoutes.home` 은 `ComingSoonScreen(tab: AppTab.main)` 으로 연결한다(09b 는 범위 밖 — Part A 가정 1).
`auth_redirect.dart` 는 **고치지 않는다** — 온보딩을 마치면 `home` 으로 보내고, 거기서 사용자가 "오늘" 탭을
누른다. 다만 `_isBeforeHome` 위 주석에 "홈 = 09b 자리 화면, 카드 화면은 `/today`" 한 줄을 더한다.

```dart
// frontend/lib/matching/view/today_cards_screen.dart (발췌)
class TodayCardsScreen extends ConsumerWidget {
  const TodayCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayCardsViewModelProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('오늘의 카드', style: AppTypography.navTitle),
        actions: [
          IconButton(
            // 설정(16) 진입점. 내 프로필(15)이 생기면 그리로 옮긴다(Part A 가정 3).
            icon: const Icon(AppIcons.settings),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.today),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ref.read(todayCardsViewModelProvider.notifier).refresh,
          child: switch (state.phase) {
            TodayCardsPhase.loading => const _SkeletonCards(),
            TodayCardsPhase.cards => _CardList(cards: state.cards),
            TodayCardsPhase.waiting => _WaitingPanel(nextIssueAt: state.nextIssueAt),
            TodayCardsPhase.noCandidates => const _NoCandidatesPanel(),
            TodayCardsPhase.failed => _FailedPanel(message: state.errorMessage),
          },
        ),
      ),
    );
  }
}
```

각 조각의 알맹이:

- `_SkeletonCards` — `Container` 2장(328×231, `AppColors.surfaceStrong`, `AppRadius.lg`). 반짝임 애니메이션은
  넣지 않는다(pen `x4FuK` 도 정적이다).
- `_CardList` — `ListView` 에 `DailyCardSummary`. 탭하면
  `context.push('${AppRoutes.cardDetail}/${card.cardId}')` 로 가고, **돌아오면**
  `ref.read(todayCardsViewModelProvider.notifier).markDecided()` 를 부른다(`push` 의 `Future` 를 `await`).
- `_WaitingPanel` — "오늘 카드는 확인했어요"(`AppTypography.title`) + `nextIssueAt` 을 한국어로 푼 부제
  ("내일 오전 7시에 새로운 한 명이 도착해요" / 내일이 아니면 "목요일 오전 7시에 …") + 남은 시간
  `hh:mm:ss`(`AppTypography.countdown`) + 마스코트 이미지.
  카운트다운은 `_CountdownText` 라는 작은 `StatefulWidget` 이 `Timer.periodic(Duration(seconds: 1))` 로
  1초마다 `setState` 한다. `dispose` 에서 타이머를 **반드시 취소**한다.
- `_NoCandidatesPanel` — "지금은 소개할 사람이 없어요" + "지금 만날 수 있는 분들은 모두 소개해드렸어요.\n
  새로운 사람이 들어오면 바로 알려드릴게요." 두 줄 + 마스코트. **버튼 2개(초대 링크·커뮤니티)는 넣지 않는다** —
  초대는 조각 7, 커뮤니티는 조각 6 이라 지금 누르면 갈 곳이 없다(백로그).
- `_FailedPanel` — 문구 + `AppButton(label: '다시 시도', …)`.

- [ ] **Step 7: 통과 확인**

Run: `cd frontend && flutter test && flutter analyze`
Expected: 새 테스트 전부 passed · 기존 280개도 그대로 통과(`HomeScreen` 테스트는 이 Task 에서 지운 만큼
줄어든다 — 줄어든 개수가 지운 케이스 수와 같은지 확인한다) · analyze 무경고

- [ ] **Step 8: 커밋**

```bash
git add frontend/lib/matching frontend/lib/common/widgets/app_bottom_nav.dart \
        frontend/lib/core/router frontend/test/matching frontend/test/core/router
git commit -m "✨ feat(slice4): 오늘의 카드 화면과 하단 내비를 추가한다"
```

---

### Task A4: 10b 상대 프로필 상세 · 수락/거절

**Files:**
- Create: `frontend/lib/matching/viewmodel/card_detail_ui_state.dart`
- Create: `frontend/lib/matching/viewmodel/card_detail_view_model.dart`
- Create: `frontend/lib/matching/view/card_detail_screen.dart`
- Create: `frontend/lib/common/widgets/trait_bar.dart`
- Create: `frontend/lib/common/widgets/card_action_bar.dart`
- Test: `frontend/test/matching/viewmodel/card_detail_view_model_test.dart`
- Test: `frontend/test/matching/view/card_detail_screen_test.dart`

**Interfaces:**
- Consumes: A2 `fetchCard` · `decide`, A3 `AppRoutes.cardDetail`
- Produces: `cardDetailViewModelProvider(cardId)`(family) · `TraitBar` · `CardActionBar`

**pen:** `TORAs` "10b 상대 프로필 상세 · 결정" — 앱바 `q5MtRk`, 본문 `ROQRv`(`daily-card-back`),
성향 라벨 `cWQ08` "성향", 외모 타입 `MqLmZ`, 관심사 `wf9FY`, 특징 `CeA3f`, 이상형 특징 `EfI7z`.
**이름 행 오른쪽 "사진 보기" 버튼은 2026-09-14 에 삭제됐다 — 다시 만들지 않는다**(§9 10b).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// frontend/test/matching/viewmodel/card_detail_view_model_test.dart
void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository()..card = Success(_detail);
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('상세를 읽어 상태에 담는다', () async {
    await container.read(cardDetailViewModelProvider('card-1').notifier).load();

    final state = container.read(cardDetailViewModelProvider('card-1'));
    expect(state.detail!.profile.nickname, '여우비');
    expect(state.survey.length, 9);
  });

  test('수락하면 수락으로 보내고 결정 완료 상태가 된다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.accept);

    expect(repository.decisions.single.decision, CardDecision.accept);
    expect(container.read(cardDetailViewModelProvider('card-1')).decided, isTrue);
  });

  test('이미 결정한 카드(409)는 서버 문구를 그대로 보여준다', () async {
    repository.writeResult = const FailureResult(ServerRejectedFailure('이미 결정한 카드예요'));
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.reject);

    expect(
      container.read(cardDetailViewModelProvider('card-1')).errorMessage,
      '이미 결정한 카드예요',
    );
    expect(container.read(cardDetailViewModelProvider('card-1')).decided, isFalse);
  });

  test('보내는 동안에는 두 번 눌러도 한 번만 간다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await Future.wait([viewModel.decide(CardDecision.accept), viewModel.decide(CardDecision.accept)]);

    expect(repository.decisions.length, 1);
  });
}
```

(`_detail` 은 `CardDetail(cardId: 'card-1', profile: …, survey: List.filled(9, 0.5), animalType:
AnimalType.cat, impressionType: ImpressionType.chic, religion: Religion.none, isSmoker: false,
interests: ['등산'], myTraits: ['유머러스'], idealTraits: ['다정한'])` 로 파일 맨 위에 둔다.)

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/viewmodel/card_detail_view_model_test.dart`
Expected: FAIL — `cardDetailViewModelProvider` 없음

- [ ] **Step 3: ViewModel 을 쓴다**

```dart
// frontend/lib/matching/viewmodel/card_detail_view_model.dart
final cardDetailViewModelProvider =
    NotifierProvider.family<CardDetailViewModel, CardDetailUiState, String>(
  CardDetailViewModel.new,
);

/// 10b 상세 화면(`TORAs`)의 흐름. 카드 하나마다 상태가 따로 산다.
class CardDetailViewModel extends FamilyNotifier<CardDetailUiState, String> {
  @override
  CardDetailUiState build(String cardId) {
    Future.microtask(load);
    return const CardDetailUiState();
  }

  Future<void> load() async {
    final result = await ref.read(cardRepositoryProvider).fetchCard(arg);
    state = result.when(
      onSuccess: (detail) => CardDetailUiState(detail: detail),
      onFailure: (failure) => CardDetailUiState(errorMessage: failure.toDisplayMessage()),
    );
  }

  Future<void> decide(CardDecision decision) async {
    // 연타·중복 전송 방지. 수락이 두 번 가면 서버는 409 로 막지만 화면이 흔들린다.
    if (state.isSubmitting || state.decided) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).decide(arg, decision);
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, decided: true, decision: decision),
      onFailure: (failure) =>
          state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}
```

`CardDetailUiState` 는 `detail` · `isSubmitting` · `decided` · `decision` · `errorMessage` 5개와
`copyWith`, 그리고 화면이 쓰는 `List<double> get survey => detail?.survey ?? const []` 를 갖는다
(조각 2 의 `*_ui_state.dart` 들과 같은 모양 — `errorMessage` 는 `copyWith` 에서 **덮어쓰기**다).

- [ ] **Step 4: 표시 전용 성향 바와 액션 바를 쓴다**

```dart
// frontend/lib/common/widgets/trait_bar.dart
/// 표시 전용 성향 바(DESIGN.md §8.1 10b — 입력용 `TraitSlider` 와 별개다).
/// 라벨 고정폭 60 · 간격 8 · 바 150 은 시안 실측값이다(2026-09-13 라운드2 에서
/// 라벨 64 → 60 으로 줄여 우측 라벨이 잘리던 버그를 고쳤다 — 되돌리지 않는다).
class TraitBar extends StatelessWidget {
  const TraitBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    super.key,
  });

  final String leftLabel;
  final String rightLabel;

  /// -1.0 ~ 1.0
  final double value;

  @override
  Widget build(BuildContext context) {
    final ratio = ((value + 1) / 2).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            leftLabel,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 150,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 2, color: AppColors.hairline),
              Align(
                alignment: Alignment(ratio * 2 - 1, 0),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 60,
          child: Text(
            rightLabel,
            textAlign: TextAlign.right,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
```

```dart
// frontend/lib/common/widgets/card_action_bar.dart
/// 카드 액션 바(DESIGN.md §8.2). 거절 40% · 수락 60%, 높이 56, 사이 간격 `{space.sm}`.
/// 수락이 시각적으로 더 크다 — 거절을 어렵게 만들지는 않는다.
class CardActionBar extends StatelessWidget {
  const CardActionBar({required this.onReject, required this.onAccept, super.key});

  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              flex: 40,
              child: AppButton(
                label: '거절',
                onPressed: onReject,
                variant: AppButtonVariant.secondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 60, child: AppButton(label: '수락', onPressed: onAccept)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 상세 화면을 쓴다**

`CardDetailScreen(cardId:)` 은 `Scaffold`:
- `appBar` — `AppBar`(뒤로가기 기본), 제목 없음(§8.8 하위 화면 규격)
- `bottomNavigationBar` — `CardActionBar`. `isSubmitting` 이면 두 버튼 모두 `null`(비활성)
- `body` — `SingleChildScrollView` 안에 위에서부터:
  1. 아바타 + 이름 `AppTypography.title.copyWith(fontSize: 22, fontWeight: FontWeight.w700)`
     (§8.1 "22/700" — 토큰표 밖 드리프트라고 문서가 못 박아 둔 값이다)
  2. Facts 행 — 학과 · 키 · MBTI · 학번 · 종교 · 흡연 6칸(3열 2행, `Wrap`). 값이 없는 칸은 "—"
  3. "성향" 라벨 + `TraitBar` 9개. 라벨은 DESIGN.md §8.5 문항 표의 양 끝 라벨을 그대로 쓴다:

```dart
const _axisLabels = <({String left, String right})>[
  (left: '집이 편해요', right: '밖이 좋아요'),
  (left: '낯을 많이 가려요', right: '금방 친해져요'),
  (left: '즉흥적이에요', right: '계획적이에요'),
  (left: '필요할 때만 해요', right: '자주 연락해요'),
  (left: '담백해요', right: '표현이 풍부해요'),
  (left: '거의 안 마셔요', right: '자주 즐겨요'),
  (left: '관심 없어요', right: '꾸준히 해요'),
  (left: '천천히요', right: '빠르게요'),
  (left: '익숙한 게 편해요', right: '새로운 걸 찾아요'),
];
```

  4. "외모 타입" — `AnimalType.iconAsset` 이미지 48dp + `animalType.label` · `impressionType.label`
  5. "관심사" · "특징" · "이상형 특징" — `Wrap` + `SelectChip`(조각 2 `common/widgets/select_chip.dart`
     재사용, 선택 상태 없이 표시만)
  6. 자기소개 전문(`bio`) · "이런 사람이 좋아요"(`idealNote`)
  7. 신고/차단 진입점은 **조각 6** 이다 — 지금 그리지 않는다

결정이 끝나면(`decided`) `Navigator.pop` 한다. **수락이 쌍방이어도 이 화면에서는 매칭 화면으로 가지
않는다** — 상대의 수락은 나중에 오고, 매칭 성사(12)는 받은 수락함(A6)에서만 발생한다.

- [ ] **Step 6: 통과 확인**

Run: `cd frontend && flutter test test/matching && flutter analyze`

- [ ] **Step 7: 커밋**

```bash
git add frontend/lib/matching frontend/lib/common/widgets/trait_bar.dart \
        frontend/lib/common/widgets/card_action_bar.dart frontend/test/matching
git commit -m "✨ feat(slice4): 카드 상세 화면과 수락·거절을 추가한다"
```

---

### Task A5: 12 매칭 성사 화면

**Files:**
- Create: `frontend/lib/matching/view/match_made_screen.dart`
- Modify: `frontend/lib/core/router/app_router.dart`
- Test: `frontend/test/matching/view/match_made_screen_test.dart`

**Interfaces:**
- Consumes: A6 의 `AcceptanceOutcome`(닉네임과 함께 `extra` 로 넘어온다)
- Produces: `AppRoutes.matchMade` — A6 과 A7(푸시 `route=match`)이 둘 다 이리로 보낸다

**pen:** `UFNSi` "12 수락 완료 매칭 성사" — 마스코트 `sMv9a`(ref `i5Ud2`),
헤드라인 `T5kQ4x` "매칭됐어요!", 서브텍스트 `lPoQb` "{닉네임} 님도 수락했어요.\n대화를 시작해 보세요.",
CTA `U1dLF4`(ref `HE8FZ`), 아래 텍스트 버튼 `LMHxg` "나중에 확인하기".

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// frontend/test/matching/view/match_made_screen_test.dart
testWidgets('상대 닉네임을 넣은 두 줄 서브텍스트를 보여준다', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
  );

  expect(find.text('매칭됐어요!'), findsOneWidget);
  expect(find.text('토끼 님도 수락했어요.\n대화를 시작해 보세요.'), findsOneWidget);
  expect(find.text('나중에 확인하기'), findsOneWidget);
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/view/match_made_screen_test.dart`
Expected: FAIL — `MatchMadeScreen` 없음

- [ ] **Step 3: 화면을 쓴다**

```dart
/// 매칭 성사(DESIGN.md 화면 12, pen `UFNSi`). 채팅방은 조각 5 라 "대화 시작"은
/// 대화 목록(13)으로 보낸다 — 아직 방이 없다.
class MatchMadeScreen extends StatelessWidget {
  const MatchMadeScreen({required this.nickname, super.key});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/mascot-female-reward-v1.png', width: 120),
              const SizedBox(height: AppSpacing.lg),
              Text('매칭됐어요!', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$nickname 님도 수락했어요.\n대화를 시작해 보세요.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 40),
              AppButton(
                label: '대화 시작하기',
                onPressed: () => context.go(AppRoutes.conversations),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: '나중에 확인하기',
                variant: AppButtonVariant.text,
                onPressed: () => context.go(AppRoutes.today),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**마스코트 자산 확인:** `assets/images/` 에 `mascot-female-reward` 계열 파일이 실제로 있는지 먼저 본다
(`ls frontend/assets/images | grep mascot`). 없으면 **이미지를 새로 만들지 말고** 그 자리를 비운 채
헤드라인부터 그린 뒤 대장에게 보고한다(자산은 디자인 세션 몫이다).

라우트:

```dart
      GoRoute(
        path: AppRoutes.matchMade,
        builder: (context, state) => MatchMadeScreen(nickname: state.extra as String? ?? '상대'),
      ),
```

- [ ] **Step 4: 통과 확인**

Run: `cd frontend && flutter test test/matching/view/match_made_screen_test.dart`

- [ ] **Step 5: 커밋**

```bash
git add frontend/lib/matching/view/match_made_screen.dart frontend/lib/core/router/app_router.dart \
        frontend/test/matching/view/match_made_screen_test.dart
git commit -m "✨ feat(slice4): 매칭 성사 화면을 추가한다"
```

---

### Task A6: 받은 수락함 (13 대화 화면 상단 sticky 섹션)

**Files:**
- Create: `frontend/lib/matching/viewmodel/acceptances_ui_state.dart`
- Create: `frontend/lib/matching/viewmodel/acceptances_view_model.dart`
- Create: `frontend/lib/matching/view/conversations_screen.dart`
- Create: `frontend/lib/matching/view/acceptance_row.dart`
- Test: `frontend/test/matching/viewmodel/acceptances_view_model_test.dart`
- Test: `frontend/test/matching/view/conversations_screen_test.dart`

**Interfaces:**
- Consumes: A2 `fetchAcceptances` · `respondToAcceptance`, A5 `AppRoutes.matchMade`
- Produces: `acceptancesViewModelProvider`(A7 의 푸시 수신이 `refresh()` 를 부른다)

**pen:** `CeqVY` "13 대화" — 섹션 헤더 `P5A282`(ref `Ymhdq`), 수락 대기 행 `XCN1f`·`Q7zmGt`,
"대화 중" 헤더 `Yjs6e`, 채팅 행 `H0LiJ3`(ref `L061P2`). 빈 상태 `LD7Kb`, 로딩 `lpsOn`.
행 구조(§8.6 `acceptance-row`): **윗단 = 아바타 44dp + 이름·나이(`pbmGF`) + 대학·학과(`Kzv6q`),
아랫단 = 거절(`HCUo1`, 폭 104) + 수락하고 대화 시작(`T643ZR`, 나머지 폭), 둘 다 높이 44dp.**
배경 `{colors.primary-wash}`. 버튼을 이름과 한 줄에 두지 않는다(학과명이 길면 어긋난다 — 시안에서
확인된 실제 문제다).

**이번 조각은 "수락 대기" 섹션만 그린다.** "대화 중" 목록(`chat-list-row`)은 조각 5 다 —
§8.6 의 "건수가 0이면 섹션 전체를 그리지 않는다" 규칙을 그대로 지키면 지금은 그려지지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// frontend/test/matching/viewmodel/acceptances_view_model_test.dart
// 파일 맨 위에 둔다(다른 테스트와 같은 setUp/tearDown 모양):
//   const _acceptance = Acceptance(
//     cardId: 'card-1',
//     profile: CardProfile(
//       profileId: 'p1', nickname: '초코라떼', age: 25,
//       university: '고려대학교', major: '경영학과',
//     ),
//   );
test('수락함을 읽어 목록에 담는다', () async {
  repository.acceptances = const Success([_acceptance]);

  await container.read(acceptancesViewModelProvider.notifier).refresh();

  expect(container.read(acceptancesViewModelProvider).acceptances.single.cardId, 'card-1');
});

test('수락하면 매칭 결과를 상태에 올린다 — 화면이 12로 넘어갈 재료다', () async {
  repository.acceptances = const Success([_acceptance]);
  repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
  final viewModel = container.read(acceptancesViewModelProvider.notifier);
  await viewModel.refresh();

  await viewModel.respond('card-1', CardDecision.accept);

  final state = container.read(acceptancesViewModelProvider);
  expect(state.matchedNickname, '초코라떼');
  expect(state.acceptances, isEmpty);
});

test('거절은 목록에서만 사라지고 매칭 화면으로 가지 않는다', () async {
  repository.acceptances = const Success([_acceptance]);
  final viewModel = container.read(acceptancesViewModelProvider.notifier);
  await viewModel.refresh();

  await viewModel.respond('card-1', CardDecision.reject);

  final state = container.read(acceptancesViewModelProvider);
  expect(state.matchedNickname, isNull);
  expect(state.acceptances, isEmpty);
});

test('기한이 지난 수락(410)은 문구를 보여주고 목록을 다시 읽는다', () async {
  repository.acceptances = const Success([_acceptance]);
  final viewModel = container.read(acceptancesViewModelProvider.notifier);
  await viewModel.refresh();
  repository.acceptanceOutcome = const FailureResult(ServerRejectedFailure('기한이 지났어요'));
  repository.acceptances = const Success([]);

  await viewModel.respond('card-1', CardDecision.accept);

  expect(container.read(acceptancesViewModelProvider).errorMessage, '기한이 지났어요');
  expect(container.read(acceptancesViewModelProvider).acceptances, isEmpty);
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/viewmodel/acceptances_view_model_test.dart`
Expected: FAIL — `acceptancesViewModelProvider` 없음

- [ ] **Step 3: ViewModel 을 쓴다**

```dart
final acceptancesViewModelProvider =
    NotifierProvider<AcceptancesViewModel, AcceptancesUiState>(AcceptancesViewModel.new);

/// 받은 수락함(DESIGN.md 화면 13 상단 섹션). 7일 만료 판정은 서버가 하고 앱은 목록을 그대로 그린다.
class AcceptancesViewModel extends Notifier<AcceptancesUiState> {
  @override
  AcceptancesUiState build() {
    Future.microtask(refresh);
    return const AcceptancesUiState();
  }

  Future<void> refresh() async {
    final result = await ref.read(cardRepositoryProvider).fetchAcceptances();
    state = result.when(
      onSuccess: (list) => state.copyWith(
        isLoading: false,
        acceptances: list,
        errorMessage: null,
      ),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  Future<void> respond(String cardId, CardDecision decision) async {
    if (state.respondingCardId != null) {
      return;
    }
    // 화면이 12 로 넘어간 뒤 뒤로 돌아와도 같은 매칭이 또 뜨지 않게 미리 비운다.
    final nickname = state.nicknameOf(cardId);
    state = state.copyWith(respondingCardId: cardId, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).respondToAcceptance(cardId, decision);
    state = result.when(
      onSuccess: (outcome) => state.copyWith(
        respondingCardId: null,
        matchedNickname: outcome.matched ? nickname : null,
      ),
      onFailure: (failure) =>
          state.copyWith(respondingCardId: null, errorMessage: failure.toDisplayMessage()),
    );
    // 성공이든 실패든(410 만료 포함) 목록은 서버 기준으로 다시 맞춘다.
    await refresh();
  }

  /// 12 화면으로 한 번 보낸 뒤에는 상태에서 지운다 — 목록에 돌아왔을 때 또 튀지 않게.
  void consumeMatched() => state = state.copyWith(matchedNickname: null);
}
```

`AcceptancesUiState` 는 `isLoading` · `acceptances` · `respondingCardId` · `matchedNickname` ·
`errorMessage` 와 `copyWith`, `String? nicknameOf(String cardId)` 를 갖는다. `matchedNickname` 과
`errorMessage` 는 `copyWith` 에서 **덮어쓰기**(null 로도 지워져야 한다).

- [ ] **Step 4: 화면을 쓴다**

`ConversationsScreen` 은 `ConsumerWidget`:
- `appBar` — 제목 "대화"(pen `PjvNd`)
- `bottomNavigationBar` — `AppBottomNav(current: AppTab.chat)`
- `body` — `isLoading` 이면 스켈레톤 2행, 목록이 비면 `LD7Kb` 빈 상태 문구,
  아니면 `CustomScrollView` + `SliverPersistentHeader(pinned: true)` 에 섹션 헤더
  ("수락 대기" + 우측 "N명" — §8.6 은 "3 / 5" 같은 분수 표기를 금지한다) + `SliverList` 에 `AcceptanceRow`
- `ref.listen(acceptancesViewModelProvider, …)` 으로 `matchedNickname` 이 생기면
  `consumeMatched()` 를 부르고 `context.push(AppRoutes.matchMade, extra: nickname)` 한다

```dart
// frontend/lib/matching/view/acceptance_row.dart (요지)
Container(
  decoration: BoxDecoration(
    color: AppColors.primaryWash,
    borderRadius: BorderRadius.circular(AppRadius.md),
  ),
  padding: const EdgeInsets.all(AppSpacing.sm),
  child: Column(
    children: [
      Row(children: [_avatar44, Expanded(child: _nameAndSchool)]),      // 윗단
      const SizedBox(height: AppSpacing.xs),
      Row(                                                              // 아랫단
        children: [
          SizedBox(width: 104, height: 44, child: AppButton(label: '거절', …)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: SizedBox(height: 44, child: AppButton(label: '수락하고 대화 시작', …))),
        ],
      ),
    ],
  ),
)
```

`AppButton` 은 높이가 56 고정이라 44dp 행에서는 `SizedBox` 로 감싸도 넘친다 —
**`AppButton` 에 `height` 선택 인자(기본 56)를 더해** 44 를 넘긴다(§8.3 "인라인 버튼 높이 변형"이 이미
44dp 를 인정한다). `frontend/test/common/widgets/app_button_test.dart` 에 높이 케이스 한 줄을 더한다.

- [ ] **Step 5: 통과 확인**

Run: `cd frontend && flutter test && flutter analyze`

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/matching frontend/lib/common/widgets/app_button.dart \
        frontend/test/matching frontend/test/common/widgets/app_button_test.dart
git commit -m "✨ feat(slice4): 받은 수락함과 대화 목록 화면을 추가한다"
```

---

### Task A7: 푸시 토큰 등록 · 수신 · `data.route` 로 화면 열기

**Files:**
- Create: `frontend/lib/core/push/push_route.dart`
- Create: `frontend/lib/core/push/push_messaging.dart`
- Create: `frontend/lib/core/push/push_registrar.dart`
- Create: `frontend/lib/core/push/push_provider.dart`
- Modify: `frontend/lib/main.dart`
- Test: `frontend/test/core/push/push_route_test.dart`
- Test: `frontend/test/core/push/push_registrar_test.dart`

**Interfaces:**
- Consumes: A2 `registerPushToken`·`deletePushToken`, Task B3 의 `data` 페이로드
  (`route` = `daily_card` · `acceptances` · `match`)
- Produces: `PushRoute.resolve(Map<String, dynamic>)` → 경로 문자열(모르면 `null`) ·
  `PushMessaging`(인터페이스) · `PushRegistrar` · `pushRegistrarProvider`
  (앱 시작·로그인 시 `start()`, 로그아웃 시 `stop()`)

- [ ] **Step 1: 실패하는 테스트를 쓴다 — 경로 변환은 순수 함수다**

```dart
// frontend/test/core/push/push_route_test.dart
void main() {
  test('카드 도착 알림은 오늘 탭으로 간다', () {
    expect(PushRoute.resolve({'route': 'daily_card', 'card_id': 'c1'}), AppRoutes.today);
  });

  test('받은 수락 알림은 대화 목록으로 간다', () {
    expect(PushRoute.resolve({'route': 'acceptances', 'card_id': 'c1'}), AppRoutes.conversations);
  });

  test('매칭 성사 알림도 대화 목록으로 간다 — 채팅방은 조각 5다', () {
    expect(PushRoute.resolve({'route': 'match', 'match_id': 'm1'}), AppRoutes.conversations);
  });

  test('모르는 route 는 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'new_message'}), isNull);
    expect(PushRoute.resolve(const {}), isNull);
  });
}
```

```dart
// frontend/test/core/push/push_registrar_test.dart
test('토큰을 받으면 서버에 등록한다', () async {
  final messaging = FakePushMessaging(token: 'tok-1');
  final repository = FakeCardRepository();

  await PushRegistrar(messaging, repository).start();

  expect(repository.registeredTokens, ['tok-1']);
});

test('권한을 거부하면 토큰을 묻지도 않는다', () async {
  final messaging = FakePushMessaging(token: 'tok-1', granted: false);
  final repository = FakeCardRepository();

  await PushRegistrar(messaging, repository).start();

  expect(repository.registeredTokens, isEmpty);
});

test('토큰이 갱신되면 새 토큰도 등록한다', () async {
  final messaging = FakePushMessaging(token: 'tok-1');
  final repository = FakeCardRepository();
  await PushRegistrar(messaging, repository).start();

  messaging.emitRefreshedToken('tok-2');
  await Future<void>.delayed(Duration.zero);

  expect(repository.registeredTokens, ['tok-1', 'tok-2']);
});

test('로그아웃하면 그 기기의 토큰을 지운다 — 다음 사람에게 내 알림이 가면 안 된다', () async {
  final messaging = FakePushMessaging(token: 'tok-1');
  final repository = FakeCardRepository();
  final registrar = PushRegistrar(messaging, repository);
  await registrar.start();

  await registrar.stop();

  expect(repository.deletedTokens, ['tok-1']);
});
```

`FakePushMessaging` 은 같은 폴더(`test/core/push/fake_push_messaging.dart`)에 둔다:

```dart
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({required this.token, this.granted = true});

  final String token;
  final bool granted;
  final StreamController<String> _refresh = StreamController<String>.broadcast();

  void emitRefreshedToken(String value) => _refresh.add(value);

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onMessage => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/core/push`
Expected: FAIL — `push_route.dart` 없음

- [ ] **Step 3: 경로 변환과 얇은 래퍼를 쓴다**

```dart
// frontend/lib/core/push/push_route.dart
/// 푸시 `data.route`(Task B3)를 앱 경로로 바꾼다.
/// 모르는 값이면 null 을 돌려주고 **아무 데도 보내지 않는다** — 알림 하나 때문에
/// 사용자가 보던 화면을 빼앗지 않는다.
abstract final class PushRoute {
  static String? resolve(Map<String, dynamic> data) => switch (data['route']) {
        'daily_card' => AppRoutes.today,
        // 받은 수락도 매칭 성사도 지금은 대화 목록(13)이 종착지다. 채팅방은 조각 5.
        'acceptances' || 'match' => AppRoutes.conversations,
        _ => null,
      };
}
```

```dart
// frontend/lib/core/push/push_messaging.dart
/// `FirebaseMessaging` 을 감싼 얇은 인터페이스. 테스트가 Firebase 를 켜지 않아도 되게 한다
/// (조각 1b 의 `FaceDetector` 래퍼와 같은 이유).
abstract interface class PushMessaging {
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<Map<String, dynamic>> get onMessage;
  Stream<Map<String, dynamic>> get onMessageOpenedApp;
  Future<Map<String, dynamic>?> initialMessage();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onMessage =>
      FirebaseMessaging.onMessage.map((message) => message.data);

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);

  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await _messaging.getInitialMessage())?.data;
}
```

```dart
// frontend/lib/core/push/push_registrar.dart
/// 토큰 등록·해제와 갱신 구독. 앱이 켜질 때 한 번 [start], 로그아웃할 때 [stop].
class PushRegistrar {
  PushRegistrar(this._messaging, this._repository);

  final PushMessaging _messaging;
  final CardRepository _repository;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  Future<void> start() async {
    if (!await _messaging.requestPermission()) {
      // 거부해도 앱은 그대로 쓴다. 알림 설정 화면(16d)에서 다시 켤 수 있다.
      return;
    }
    final token = await _messaging.getToken();
    if (token != null) {
      await _register(token);
    }
    _refreshSubscription ??= _messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    _registeredToken = token;
    await _repository.registerPushToken(token);
  }

  /// 로그아웃. 토큰을 남겨 두면 다음에 로그인한 사람에게 내 알림이 간다.
  Future<void> stop() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token != null) {
      await _repository.deletePushToken(token);
    }
  }
}
```

- [ ] **Step 4: 앱에 배선한다**

`push_provider.dart` 에 `pushMessagingProvider`(실제 `FirebasePushMessaging`)와
`pushRegistrarProvider` 를 둔다. `main.dart` 의 `_CampusMateAppState` 에서:

- 로그인 상태가 되면 `ref.read(pushRegistrarProvider).start()`, 로그아웃하면 `stop()`
  (`_refreshVerificationGate` 가 이미 로그인·로그아웃마다 불리므로 **그 안에 두 줄만 더한다**)
- `onMessage`(앱이 켜져 있을 때) — 화면을 빼앗지 않는다. `route` 를 보고
  `todayCardsViewModelProvider.refresh()` 또는 `acceptancesViewModelProvider.refresh()` 만 부른다
  (계획서 맨 위 "새 의존성" 표가 `flutter_local_notifications` 를 안 쓰기로 한 이유가 이것이다)
- `onMessageOpenedApp` · `initialMessage()`(알림을 눌러서 열었을 때) —
  `PushRoute.resolve(data)` 가 null 이 아니면 `_router.go(path)`

백그라운드 수신 핸들러는 **만들지 않는다.** 서버가 `notification` 페이로드를 함께 보내므로 앱이 꺼져
있을 때의 알림은 안드로이드 시스템이 직접 띄운다(Task B3 `FcmSender.send`).

- [ ] **Step 5: 통과 확인**

Run: `cd frontend && flutter test test/core/push && flutter analyze`
Expected: 8 passed · 무경고

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/core/push frontend/lib/main.dart frontend/test/core/push
git commit -m "🔔 feat(slice4): 푸시 토큰 등록과 알림 열기 처리를 추가한다"
```

---

### Task A8: 알림 설정(16d) · 매칭 일시중지 · Part A PR

**Files:**
- Create: `frontend/lib/matching/viewmodel/notification_settings_ui_state.dart`
- Create: `frontend/lib/matching/viewmodel/notification_settings_view_model.dart`
- Create: `frontend/lib/matching/view/notification_settings_screen.dart`
- Create: `frontend/lib/matching/view/settings_screen.dart`
- Modify: `frontend/lib/core/router/app_router.dart`
- Test: `frontend/test/matching/viewmodel/notification_settings_view_model_test.dart`
- Test: `frontend/test/matching/view/notification_settings_screen_test.dart`

**Interfaces:**
- Consumes: A2 `fetchNotificationPreferences` · `updateNotificationPreference` · `setMatchingPaused`
- Produces: `AppRoutes.settings` · `AppRoutes.notificationSettings`

**pen:** `NMgCa` "16d 알림 설정" — 앱바 `zViPy`(제목 `HAIO1` "알림"), 목록 `UgGYL`.
섹션 4개와 그 안의 행(전부 `iF24N MatchToggle`):

| 섹션 | 노드 | 행 |
| --- | --- | --- |
| 매칭 | `imosa` / 카드 `c1W9t` | `ojaTK` 오늘의 카드 도착(`card_arrived`) · `Q7FGf` 받은 수락(`acceptance_received`) · `ZZmwy` 매칭 성립(`match_made`) |
| 대화 | `SLbwX` / `i1tdWe` | `D06sT` 새 메시지(`new_message`) · `IrYuh` 신뢰 확인 리마인드(`trust_reminder`) |
| 지인 리뷰·커뮤니티 | `oGFQl` / `b7JTyy` | `azFlB` 새 지인 리뷰(`new_friend_review`) · `KjGQd` 내 글의 새 댓글 |
| 기타 | `vpI3J` / `BGX6r` | `HokjM` 혜택·이벤트 소식(`marketing`, 기본 꺼짐 `C1OIUA`) · `L7yfzj` 방해 금지 시간(`quiet_hours`, 값 표시 `EMS3s` "22:00 ~ 08:00") |

**노드 id 정정(2026-09-21 반영 완료):** 카드 도착 스위치의 pen 실측 id 는 **`ojaTK`**(행) /
`ZXJIi`(토글 인스턴스)다. "실행 전 확인 사항" 6번 본문의 `WUdhM` 도 같은 값으로 고쳐 뒀다.

**행이 8개인데 서버 스위치는 7개다.** "내 글의 새 댓글"(`KjGQd`)은 `notification_settings` 에 대응 컬럼이
없다(Task C4 표 참조 — 커뮤니티는 조각 6). **이 행은 이번 조각에서 그리지 않는다.** 방해 금지 시간은
켜고 끄는 스위치이고 시간대(22:00~08:00)는 고정값이라 값만 표시한다(시간 고르기는 백로그).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('행이 없는 사람은 전부 켜짐, 마케팅만 꺼짐으로 그린다', () async {
  repository.preferences = const Success(NotificationPreferences());

  await container.read(notificationSettingsViewModelProvider.notifier).refresh();

  final state = container.read(notificationSettingsViewModelProvider);
  expect(state.preferences.cardArrived, isTrue);
  expect(state.preferences.marketing, isFalse);
});

test('스위치를 끄면 그 값만 서버로 간다', () async {
  await container.read(notificationSettingsViewModelProvider.notifier).refresh();

  await container.read(notificationSettingsViewModelProvider.notifier)
      .toggle('card_arrived', false);

  expect(repository.preferenceUpdates.single, (key: 'card_arrived', value: false));
});

test('저장에 실패하면 스위치를 원래대로 되돌린다', () async {
  await container.read(notificationSettingsViewModelProvider.notifier).refresh();
  repository.writeResult = const FailureResult(NetworkFailure());

  await container.read(notificationSettingsViewModelProvider.notifier)
      .toggle('match_made', false);

  final state = container.read(notificationSettingsViewModelProvider);
  expect(state.preferences.matchMade, isTrue);
  expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
});

test('매칭 일시중지는 프로필 쪽으로 간다', () async {
  await container.read(notificationSettingsViewModelProvider.notifier).setPaused(true);

  expect(repository.pausedValue, isTrue);
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/viewmodel/notification_settings_view_model_test.dart`
Expected: FAIL — provider 없음

- [ ] **Step 3: ViewModel 을 쓴다**

```dart
/// 알림 설정(화면 16d)과 매칭 일시중지(화면 16 `TLrmq`).
/// 스위치는 **먼저 화면에서 바꾸고 실패하면 되돌린다** — 토글은 즉시 반응해야 한다.
class NotificationSettingsViewModel extends Notifier<NotificationSettingsUiState> {
  @override
  NotificationSettingsUiState build() {
    Future.microtask(refresh);
    return const NotificationSettingsUiState();
  }

  Future<void> refresh() async {
    final result = await ref.read(cardRepositoryProvider).fetchNotificationPreferences();
    state = result.when(
      onSuccess: (preferences) => state.copyWith(isLoading: false, preferences: preferences),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  Future<void> toggle(String key, bool value) async {
    final previous = state.preferences;
    state = state.copyWith(preferences: previous.withValue(key, value), errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).updateNotificationPreference(key, value);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => state = state.copyWith(
        preferences: previous,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  Future<void> setPaused(bool paused) async {
    final previous = state.matchingPaused;
    state = state.copyWith(matchingPaused: paused, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).setMatchingPaused(paused);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => state = state.copyWith(
        matchingPaused: previous,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }
}
```

- [ ] **Step 4: 화면 2개를 쓴다**

`NotificationSettingsScreen` — 앱바 "알림" + 섹션 4개. 한 행은
`SwitchListTile.adaptive`(제목 `AppTypography.subtitle`, 설명 `AppTypography.bodySmall`)로 그리고
`activeThumbColor` 는 `AppColors.primary` 를 쓴다. 행 문구는 pen 그대로:

| 키 | 제목 | 아이콘 |
| --- | --- | --- |
| `card_arrived` | 오늘의 카드 도착 | `AppIcons.heart` |
| `acceptance_received` | 받은 수락 | `AppIcons.userPlus` |
| `match_made` | 매칭 성립 | `AppIcons.badgeCheck` |
| `new_message` | 새 메시지 | `AppIcons.messageCircle` |
| `trust_reminder` | 신뢰 확인 리마인드 | `AppIcons.timer`(§5.3 — 이 세트에 `clock` 이 없다) |
| `new_friend_review` | 새 지인 리뷰 | `AppIcons.users` |
| `marketing` | 혜택·이벤트 소식 | `AppIcons.bell` |
| `quiet_hours` | 방해 금지 시간 (22:00 ~ 08:00) | `AppIcons.pause` |

맨 아래에 안내 한 줄: "오늘의 카드 도착 알림은 방해 금지 시간에도 보내드려요. 카드가 도착하는 시각이
아침 7시예요."(계획서 "실행 전 확인 사항" 6번을 사용자에게 설명하는 문장 — 없으면 설정이 거짓말이 된다.)

`SettingsScreen` — 앱바 "설정" + 두 줄만:
1. **매칭 활성화**(pen `LJOdb`/`EoeQS`) — 제목 "매칭 활성화", 설명 "잠시 쉬고 싶으면 꺼두세요",
   스위치. **꺼짐 = `matching_paused = true`** 이므로 `setPaused(!value)` 로 뒤집어 보낸다.
2. **알림** — `AppIcons.bell` + `chevron-right`, 탭하면 `AppRoutes.notificationSettings`

- [ ] **Step 5: 전체 통과 확인**

```bash
cd frontend && flutter test && flutter analyze
cd ../backend && python -m pytest -q
```

Expected: flutter 테스트가 **280 + 이번 조각에서 더한 개수**만큼 통과(줄어든 것은 A3 에서 지운
`HomeScreen` 케이스뿐이어야 한다) · analyze 무경고 · pytest 는 Part B 까지 포함해 전부 통과

- [ ] **Step 6: 커밋 + Part A PR**

```bash
git add frontend/lib/matching frontend/lib/core/router/app_router.dart frontend/test/matching
git commit -m "✨ feat(slice4): 알림 설정과 매칭 일시중지 화면을 추가한다"
git push -u origin feat/slice4-part-a-flutter
"C:/Program Files/GitHub CLI/gh.exe" pr create --draft --base main \
  --title "조각 4 Part A: 오늘의 카드·수락함·푸시 화면" --body "..."
```

---

## 화면 목록 (pen 노드 id)

파일: **`C:\Users\home\OneDrive\Desktop\datingApp\design\datingApp.pen`**, 섹션 3 "카드·매칭·채팅"(`qXpwn`) —
행 `M40CgR`(카드·매칭)과 `xaESY`(대화·채팅). Task 를 시작하기 전에 해당 노드를 pencil MCP 로 읽는다.

| § 9 | 화면 | pen 노드 | 조각 4 | Task |
| --- | --- | --- | --- | --- |
| 10 | 오늘의 카드 | `W0CjO` | ○ | A3 |
| 10 | 오늘의 카드 · 추가 카드 없음 | `eDPkz` | ○ (기본 모양) | A3 |
| 10 | 오늘의 카드 · 로딩 | `Ukg21` | ○ | A3 |
| 10 | 오늘의 카드 · 결정 대기 구매 카드 있음 | `Keynu` | ✕ 조각 7 | — |
| 10b | 상대 프로필 상세 · 결정 | `TORAs` | ○ | A4 |
| 10c | 추가 카드 바텀시트 | `x2yPl` | ✕ 조각 7 | — |
| 10e | 오늘의 카드 · 추가 카드 구매 후 | `wDKXv` | ✕ 조각 7 | — |
| 11 | 카드 대기 | `i4VFS` | ○ | A3 |
| 11 | 카드 대기 · 다음 후보 없음 | `k2fF9y` | ○ (부제만 다르다) | A3 |
| 11b | 매칭 가능한 사람 없음 | `iQZoa` | ○ (버튼 2개 제외) | A3 |
| 12 | 수락 완료 · 매칭 성사 | `UFNSi` | ○ | A5 |
| 13 | 대화 (수락 대기 + 대화 중) | `CeqVY` | △ 수락 대기 섹션만 | A6 |
| 13 | 대화 · 빈 상태 | `LD7Kb` | ○ | A6 |
| 13 | 대화 · 로딩 | `lpsOn` | ○ | A6 |
| 14~14h | 채팅방 계열 | `ioKLk`·`p0XJA6`·`SJWl0`·`KGjJx`·`albnG` | ✕ 조각 5 | — |
| 16 | 설정 | `lMDpY` | △ 2줄만(`TLrmq` 매칭 활성화 · 알림) | A8 |
| 16d | 알림 설정 | `NMgCa` | ○ (댓글 행 제외) | A8 |
| 09b | 메인 | `bpA8x` · `lvmAj`(배너 `Diw5U`) | ✕ 범위 밖 | 백로그 |

**공용 컴포넌트(마스터 노드)**

| 컴포넌트 | pen | Flutter |
| --- | --- | --- |
| `DailyCardSummary` | `v26S7z` | `matching/view/daily_card_summary.dart` |
| `DailyCardLocked` | `BpP33` | 조각 7 |
| `AcceptanceRow` | `iKKP0`(13 화면은 인라인 `XCN1f`) | `matching/view/acceptance_row.dart` |
| `BottomNav` | `Migf0` | `common/widgets/app_bottom_nav.dart` |
| `AppBar · Tab` | `YTDwe` | `AppBar`(화면마다 인라인) |
| `MatchToggle` / `Switch · Off` | `iF24N` / `C1OIUA` | `SwitchListTile.adaptive` |
| `Skeleton · Card` / `· AcceptanceRow` | `x4FuK` / `R688B` | 화면 안 `Container` |
| `Mascot … Waiting` / `· Reward` / `· Calm Sad` | `PKbwO` / `i5Ud2` / `BSPUP` | `assets/images/` PNG |
| `Button` | `HE8FZ` | `common/widgets/app_button.dart` |
| `SectionHeader` | `Ymhdq` | 13 화면 안 sliver 헤더 |

---

## 테스트 전략

| 층 | 무엇을 | 어떻게 | Task |
| --- | --- | --- | --- |
| 요일 사다리 | 임계값 경계(199/200/499/500) · 요일 계산 · 다음 지급일 | 순수 함수 단위 테스트 | B1 |
| FCM 전송 | 죽은 토큰 삭제 · 조용한 시간 · 카드 도착 예외 · 스위치 꺼짐 | `httpx.MockTransport` + 가짜 자격증명 | B3 |
| 지급 배치 | 지급일이 아니면 0장 · 1인 1장 · 이미 받은 사람 제외 · 공유 비밀 없으면 401 | `MockTransport` + `TestClient` | B4 |
| 카드 API | 남의 카드 404 · 만료 409 · 중복 결정 409 · 수락만 알림 | `TestClient` + `MockTransport`(조각 2 `_wire`) | B5·B6·B7 |
| DB | RLS 정책 0건 · ACL · 순서 제약 · 하드 필터 3종 · 쿨다운 경계(무응답 14일 · 결정 90일) | pgTAP `supabase test db` | C6 |
| Flutter 저장소 | URL · 바디 · 4xx 문구 · 네트워크 실패 | `MockClient`(`package:http/testing.dart`) | A2 |
| Flutter ViewModel | 5가지 화면 상태 전환 · 연타 방지 · 실패 시 토글 되돌리기 · 결정 뒤 재조회 | `Fake CardRepository` + `ProviderContainer` | A3·A4·A6·A8 |
| Flutter 화면 | 카드 문구("여우비, 23") · 11b 빈 문구 · 12 서브텍스트 두 줄 | `UncontrolledProviderScope` 위젯 테스트 | A3·A5 |
| 푸시 | `route` → 경로 변환 · 권한 거부 · 토큰 갱신 · 로그아웃 삭제 | 순수 함수 + `FakePushMessaging` | A7 |
| 빌드 | Gradle 플러그인 · `google-services.json` 배선 | `flutter build apk --debug` | A1 |

**실제 FCM · 실제 Supabase 클라우드는 테스트에서 부르지 않는다.** 로컬 스택(Docker)은 pgTAP 에만 쓴다.
Flutter 테스트는 Firebase 를 켜지 않는다 — A7 의 `PushMessaging` 인터페이스가 그 경계다.

**기준선(2026-09-21):** pytest 149 · flutter test 280 · pgTAP 111. 조각 4 가 끝나면 세 숫자가 모두
늘어야 하고, **줄어든 항목이 있으면 무언가 깨진 것이다**(예외: A3 에서 지우는 `HomeScreen` 테스트 케이스).

---

## 백로그 (이번 조각에서 하지 않는다)

**조각이 정해져 있는 것**

- 잠금 카드 · 추가 카드 바텀시트(10c) · 구매 후(10e) · 결정 대기 구매 카드(`Keynu`) — 조각 7(하트)
- 채팅방(14 계열) · 대화 중 목록(`chat-list-row`) · 신뢰 확인 게이트 — 조각 5
- 차단(`blocks`) 하드 필터 · 신고 진입점(10b 하단) — 조각 6
- 09b 메인 화면과 "결정 대기 카드가 N장 남아 있어요" 배너(`Diw5U`) — 09b 를 만드는 조각
- 내 프로필(15)이 생기면 설정(16) 진입점을 오늘 탭 앱바에서 그리로 옮긴다
- 11b 의 "친구에게 초대 링크 보내기"(조각 7 추천) · "커뮤니티 둘러보기"(조각 6)
- 16d "내 글의 새 댓글" 스위치 — 커뮤니티(조각 6)가 컬럼과 함께 만든다

**조각이 정해져 있지 않은 것**

- 조용한 시간에 버려진 알림을 아침에 모아 보내기(지금은 그냥 버린다 — `push.py` 의 `ponytail:` 주석)
- 배치 실행이 600초를 넘으면 지역그룹별로 Cloud Scheduler job 나누기(B8)
- 요약 카드 "무료 카드 초기화" 배지("목요일 오전 7시까지") — 카드마다 다음 지급 시각이 필요해 응답 확장이 따른다
- 방해 금지 시간대 직접 고르기(지금은 22:00~08:00 고정)
- iOS APNs 설정(`device_platform` enum 에는 이미 `ios` 가 있다)
- 알림 권한을 거부한 사람에게 16d 에서 "기기 알림 설정 열기 ›" 링크 붙이기(pen `U6Lcq`)
- 카드 만료를 앱이 실시간으로 지우기(지금은 다음 조회 때 서버가 빼고 내려준다)

**앞 조각에서 넘어온 것(조각 3 백로그 유지)**

- `httpx` 클라이언트를 FastAPI lifespan 으로 옮기기 · `_raise_for_status` 공용화
- `BackgroundTasks` 로 임베딩 재생성 옮기기 · `/school-info` 재생성 배선
- ERD.md §3 `profile_vectors` 그림 갱신(erd 세션 몫)

---

## 구현 편차 기록 (2026-09-21)

계획서와 실제로 머지된 코드가 다른 곳. **계획서 본문은 그대로 두고 여기에 모은다** — 본문을 고치면
"무엇을 계획했고 왜 달라졌는지" 가 사라진다. 아래 내용은 전부 머지된 코드에서 직접 확인한 것이다.

### Part C (마이그레이션 · pgTAP)

- **C6 테스트 개수 19 → 20.** 계획서 SQL 블록에는 원래부터 단언이 20개였는데 `select plan(19)` 와
  본문 설명만 19 로 적혀 있었다. 실제 `supabase/tests/rls_slice4_test.sql` 은 `plan(20)` 이다.
  (이 문서의 해당 세 자리는 2026-09-21 문서 라운드에서 20 으로 고쳤다.)
- **테스트 사용자 UUID 접미사.** 계획서의 `…pp`·`…qq`·`…rr`·`…ss`·`…tt` 는 16진수가 아니라
  UUID 로 파싱되지 않는다. 구현은 `…fa`·`…fb`·`…fc`·`…fd`·`…fe` 로 바꿨다(사람 표기 A·B·P·Q·R·S·T 는 그대로).

### PR #65 — 백엔드 카드 · 수락 (편차 5)

1. **`SEOUL` 상수를 새로 만들지 않고 `app/core/time.py` 것을 쓴다.** 조각 3 까지는
   `profile_onboarding.schemas` 안에 있어서 카드 모듈이 상관없는 온보딩 모듈을 거쳐 가져다 썼다.
2. **받은 수락함 조회의 시각 비교를 `gte` 로 고쳤다.** `fetch_pending_acceptances` 는
   `decided_at=gte.<7일 전>` 으로 거른다 — 계획서의 비교 방향으로는 경계일이 빠졌다.
3. **저장소 메서드가 3개 늘었다**: `fetch_card_detail_profile`(10b 상세용 컬럼) ·
   `fetch_survey`(9축 원값) · `fetch_region_group`. 계획서 목록은 18개, 실제는 21개다.
4. **`/cards/acceptances` 라우트를 `/cards/{card_id}` 보다 먼저 선언한다.** 순서가 반대면
   `acceptances` 가 `card_id` 로 먹혀 422 가 난다. 지금 `GET /cards/{card_id}` 는 라우터 맨 끝에 있다.
5. **`locked_card_available` 은 항상 `false` 로 내려간다.** 잠금 카드(추가 카드)는 조각 7(하트) 몫이라
   이번 조각에선 응답 모양만 맞춰 두고 판정을 하지 않는다.

### PR #66 — Flutter 카드 화면 · 푸시 (편차 10)

1. **`FamilyNotifier` 대신 `Notifier` + 생성자.** Riverpod 3 에서 `FamilyNotifier` 가 없어졌다.
   `NotifierProvider.family(CardDetailViewModel.new)` 로 인자를 생성자가 받는다.
2. **겹쳐 들어온 조회는 `Future` 를 재사용한다.** `CardDetailViewModel._inFlight` — 화면이 붙을 때와
   사용자가 다시 시도할 때가 겹쳐도 요청은 한 번만 나가고, 늦은 응답이 결정 상태를 덮어쓰지 않는다.
3. **받은 수락함 `refresh()` 가 `matchedNickname`·`errorMessage` 를 지우지 않는다.** 매칭 성사 직후
   푸시로 들어온 갱신이 방금 띄운 "매칭됐어요" 문구를 지워 버리던 것을 막는다.
4. **마스코트 파일명 정정**: `mascot-male-waiting.png`(카드 대기) · `mascot-female-sad.png`(후보 없음) ·
   `mascot-female-reward.png`(매칭 성사).
5. **알림 스위치는 7개가 아니라 8개.** `card_arrived` · `acceptance_received` · `match_made` ·
   `new_message` · `trust_reminder` · `new_friend_review` · `marketing` · **`quiet_hours`**.
   `quiet_hours` 를 계획서가 컬럼으로만 세고 화면 스위치로는 세지 않았다.
6. **10b 상세에 구역이 둘 늘었다.** `_SectionLabel('자기소개')` 와 `_SectionLabel('이런 사람이 좋아요')` —
   계획서가 적어 둔 pen 노드 목록(`cWQ08` 성향 · `MqLmZ` 외모 타입 · `wf9FY` 관심사 · `CeA3f` 특징 ·
   `EfI7z` 이상형 특징)에는 없던 것이다. 성향 9축의 양끝 라벨은 DESIGN §8.5 표가 기준이고 계획서와 같다.
7. **`app_router_test` 의 자리표시자 문구는 '곧 만나요'** — `placeholder_screens.dart` 실제 문구와 맞췄다.
8. **`POST_NOTIFICATIONS` 권한을 `AndroidManifest.xml` 에 넣는다.** Android 13+ 에서 이게 없으면
   권한 요청 다이얼로그 자체가 뜨지 않는다.
9. **불필요한 캐스트를 걷어냈다**(계획서 예시 코드에 남아 있던 `as` 들).
10. **푸시는 로그인한 뒤에만 Firebase 를 건드린다.** `main.dart` 의 `_startPush()`/`_stopPush()` 가
    세션 상태에 붙어 있다 — 로그인 전에는 토큰을 등록할 주인이 없고, Firebase 를 켜지 않은 테스트도
    이 경로로는 들어오지 않는다.

### PR #67 — 리뷰 수정 3건

1. **PostgREST 임베드는 배열이 아니라 객체/`null`.** `card_decisions`·`acceptance_responses` 는
   `card_id` 가 PK 이자 `daily_cards` 참조라 PostgREST 가 one-to-one 으로 본다. 목록으로 읽던 곳을 고쳤다.
2. **`matches` 삽입을 `on_conflict=profile_a,profile_b` upsert 로.** A→B, B→A 카드가 같은 날 나가면
   두 사람이 각각 매칭을 만들려 해서 나중 쪽이 `matches_pair_unique` 로 터진다.
3. **시각은 앱에서 `.toLocal()` 로 바꿔 보여준다**(`daily_card.dart`) — 서버는 UTC 로 내려준다.
