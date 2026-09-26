# 아바타 비동기 생성 (Cloud Tasks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **이 문서는 계획서다. 코드는 사용자 검토가 끝난 뒤에 시작한다**(2026-09-25 대장 지시).
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다.
> **Part C 는 파일 작성 + 로컬 스택 검증까지만 하고 클라우드 적용은 하지 않는다**(ERD 그림 · 사용자 검토 ·
> 사용자 승인 뒤 supabase 담당 세션이 적용한다).
> **화면 번호는 안 A 로 확정**(`05-12`~`05-12d`) — 아래 "화면 대조표" 가 pen(erd3) 과 코드를 잇는 표다.
> **클라우드 설정 6건(API · 큐 · 서비스 계정 · 권한 · 환경변수 · 타임아웃)은 전부 사용자 승인 대상**이다.
> 아래 "클라우드 쓰기 목록" 에 모아 뒀다. **새 파이썬 패키지는 넣지 않는다**(2026-09-25 결정).

**개정 이력:** 2026-09-25 초안 → 2026-09-25 분석담당33 1차 리뷰(FAIL, 필수 2건) 반영 + 사용자 결정 7건 확정
→ 2026-09-25 분석담당33 2차 리뷰(FAIL, 필수 2건: 상태 `fallback` 누락 · 워커가 안 돌면 5회 규칙이 안 걸림)
반영 + 권고 6건 · 사소 6건 · 테스트 7줄 추가
→ 2026-09-25 분석담당33 3차 리뷰(FAIL, 필수 2건: 응답 칸 이름 `storage_path`/`avatar_url` 어긋남 ·
워커가 기록할 때 행 수를 안 봄) 반영 + 권고 6건 · 사소 2건 · 테스트 3줄 추가.

**Goal:** 04-3 에서 "이 사진으로 아바타 만들기" 를 누르면 **기다리지 않고 바로 다음 온보딩으로** 넘어가고,
서버가 뒤에서 아바타를 만들고, **마지막 성향 질문(05-11 흡연)이 끝난 뒤** 결과를 확인한다(완성이면 보여 주고
다음으로, 실패면 다시 만들기, 아직이면 기다리는 화면). 2026-09-25 사용자 결정 = **방식 C(Cloud Tasks)**.

**왜 바꾸나:** 지금은 앱이 `POST /profile-onboarding/avatar/generate` 한 번에 **59초**를 기다린다(운영
00020 실측 59.6초 · 58.6초). 온보딩 한복판에서 1분을 세워 두는 것도 문제지만, Cloud Run 요청 타임아웃
300초와 모바일 네트워크 사이에서 언제든 끊길 수 있는 구간이기도 하다.

**Tech Stack:** Cloud Tasks(신규, asia-northeast3) + Cloud Run(기존) + FastAPI + httpx(기존) +
google-auth(기존 설치본, OIDC 발급·검증) + Postgres 17(Supabase) + Flutter(Riverpod `Notifier`).

**기준 문서:** `frontend/docs/DESIGN.md` §5.2 · §9(화면 5c `04-3` · 6b `04-4` · 05-01~05-11),
`docs/ERD.md` §3(`profile_avatars`), `supabase/migrations/20260920043723_add_avatar_schema.sql`,
`backend/DEPLOY.md` §2 · §4, `project_slice2_decisions_2026-09-19`(5회 실패 → 기본 아바타 + 하트 10),
`project_slice6_predecisions_2026-09-22`(배치 인증은 **OIDC**), 2026-09-20 결정(재시도 횟수는 우리 코드가 센다).

---

## 확정된 결정 (2026-09-25 사용자)

| # | 질문 | 답 |
| --- | --- | --- |
| 1 | 실패했을 때 서버가 자동으로 다시 시도할까? | **(가) 안 한다.** 큐 `--max-attempts=1` 그대로. 사람이 "다시 만들기" 를 누른다 |
| 2 | 10분 넘게 "만드는 중" 이면? | **(가) 실패로 보고 "다시 만들기" 를 띄운다** |
| 3 | 작업을 부를 서비스 계정은? | **(가) 조각 6 스케줄러 OIDC 와 같은 계정 하나**를 쓴다 |
| 4 | 결과 확인은 어디서? | **성향 질문이 끝난 뒤**(처음부터 정해진 흐름 — 질문하지 않음) |
| 5 | 새 파이썬 패키지(`google-cloud-tasks`)를 넣을까? | **안 넣는다.** 이미 있는 `httpx` + `google-auth` 로 간다 |
| 6 | 아바타 결과 화면 4장의 번호는? | **(안 A) `05-12` · `05-12b` · `05-12c` · `05-12d`** (05-11 흡연 뒤 · 06-1 앞) |
| 7 | 04-3 에서 넘어갈 때 띄울 문구는? | **"아바타는 만드는 동안 다음 질문을 이어 가요"** (pen `04-3` 과 같은 문구) |

**사용자에게 물을 것은 더 없다.** 클라우드 설정 6건 승인만 **실행 직전에 정확한 명령과 함께** 받는다
(2026-09-25 대장).

---

## 지금 흐름 ↔ 바뀌는 흐름

| 단계 | 지금 | 바뀐 뒤 |
| --- | --- | --- |
| 04-3 CTA | POST 하고 **59초 대기** | POST 하면 **즉시 202** → 다음 화면(04-4)으로 바로 이동 |
| 생성 | 요청 안에서 OpenAI 호출 | Cloud Tasks 가 워커 엔드포인트를 불러 서버 뒤에서 호출 |
| 결과 확인 | 같은 응답으로 받음 | 성향 질문(05-11) 끝난 뒤 `avatar` 단계에서 상태 조회 |
| 실패 | 같은 응답에 `failed` | 결과 화면에서 "다시 만들기" (새 작업 등록) |
| 5회째 실패 | 같은 응답에 `fallback` + 하트 10 | 결과 화면에서 **기본 아바타 그림 + 보상 안내**. 하트 지급은 워커가, **워커가 안 돌면 다음 POST 가** |
| 온보딩 순서 | photos → **avatar** → appearance_type → … → survey | photos → appearance_type → … → survey → **avatar** → ideal_conditions |

**바뀌지 않는 것:** 아바타는 최초 1회 무료(재생성 하트 차감은 조각 7), 5회 연속 실패 규칙, 공개 `avatars`
버킷, `{profile_id}/{uuid4}.png` 경로, 화풍 지시문(#101).

---

## 왜 Cloud Tasks 인가 (결정된 방식 C)

Cloud Run 안에서 `asyncio.create_task` 로 떼어 놓는 방법(방식 A)은 인스턴스가 내려가면 작업이 사라진다 —
Cloud Run 은 요청이 끝나면 CPU 를 회수하므로 "요청 없이 도는 백그라운드 작업" 이 보장되지 않는다. Cloud
Tasks 는 작업을 큐에 맡기고 **HTTP 로 우리를 다시 불러 주므로**, 그 재호출이 평범한 요청이라 Cloud Run 의
규칙(CPU · 타임아웃 · 오토스케일)을 그대로 탄다. 코드도 "엔드포인트 하나 더" 로 끝난다.

---

## 새 의존성 (6번 항목) — **결정: 새 패키지 없이 간다**

| 방법 | 장점 | 단점 |
| --- | --- | --- |
| **`httpx` + `google-auth`(둘 다 이미 있음)** ← 채택 | 새 승인 절차가 없다. 쓰는 API 는 작업 생성 하나뿐(REST `POST .../tasks`)이라 코드가 20줄 남짓이다. **이미 같은 패턴이 돌고 있다** — `backend/app/cards/push.py` `FcmSender` 가 `google.auth.default(scopes=...)` 로 토큰을 받아 httpx 로 FCM 을 부른다. 그대로 복사하면 된다. 테스트도 기존 `httpx.MockTransport` 로 본문까지 들여다볼 수 있다 | 요청 본문(JSON · base64)을 우리가 조립한다. Cloud Tasks API 가 바뀌면 우리가 고친다(v2 는 안정 버전이라 가능성 낮다) |
| `google-cloud-tasks` 추가 | 타입이 있는 클라이언트, 재시도 기본 제공 | **새 의존성 = 사용자 승인 필요.** grpc 계열 의존성이 딸려 와 배포 이미지가 커진다. 동기 클라이언트라 `asyncio.to_thread` 로 감싸야 하고, 테스트는 목으로 막는 수밖에 없어 "실제로 나가는 요청" 을 못 본다 |

**`google-auth` 를 `pyproject.toml` 에 명시로 적는다.** 지금은 `google-cloud-vision` 에 딸려 들어온
2.58.0 을 쓰고 있다 — 우리가 직접 `google.auth` · `google.oauth2.id_token` 을 `import` 하는데 선언이
없으면, 언젠가 Vision 을 떼거나 버전이 바뀔 때 조용히 사라진다. **새 패키지를 들이는 게 아니라 이미 쓰고
있는 것을 적어 두는 것**이라 승인 대상이 아니다(대장 판단, 2026-09-25).

---

## 클라우드 쓰기 목록 (5번 항목) — **전부 사용자 승인 대상, 지금은 문서에만**

| # | 할 일 | 명령(요지) | 비고 |
| --- | --- | --- | --- |
| 1 | Cloud Tasks API 사용 설정 | `gcloud services enable cloudtasks.googleapis.com` | 1회 |
| 2 | 큐 만들기 | `gcloud tasks queues create <QUEUE> --location=asia-northeast3 --max-attempts=1 --max-concurrent-dispatches=5` | `--max-attempts=1` 이 "자동 재시도 안 함"(결정 1). 동시 실행은 **3~5 로 시작**한다 — OpenAI 를 장당 1분 잡아 두는 작업이라 한꺼번에 열면 Cloud Run 인스턴스와 OpenAI rate limit 을 같이 민다. 모자라면 `queues update` 로 올린다(배포 없이 된다) |
| 3 | 작업 서비스 계정 | **조각 6 스케줄러와 같은 계정을 쓴다**(결정 3) — 없으면 `gcloud iam service-accounts create <SA_NAME>` | 먼저 만드는 조각이 만들고 다른 쪽은 그대로 쓴다 |
| 4 | 권한 2개 | 큐에 `roles/cloudtasks.enqueuer`(Cloud Run 런타임 계정), 작업 계정에 `roles/iam.serviceAccountUser` | 최소 권한 |
| 5 | Cloud Run 환경변수 3개 | `--set-env-vars AVATAR_TASKS_QUEUE=<QUEUE>,AVATAR_WORKER_URL=<CLOUD_RUN_URL>/tasks/avatar-generate,AVATAR_TASKS_SERVICE_ACCOUNT=<SA_EMAIL>` | 시크릿이 아니다(값은 문서에 남기지 않는다). 비어 있으면 POST 는 503, 워커는 아무도 통과시키지 않는다 |
| 6 | Cloud Run 타임아웃 확인 | `--timeout=300`(기본값) 유지 | 작업 `dispatchDeadline` 을 240초로 두어 **런타임 타임아웃보다 짧게** 맞춘다 |

**비용:** Cloud Tasks 는 **월 100만 작업까지 무료**, 초과분 100만 건당 약 $0.40(공개 가격표 기준). 아바타는
사람당 평생 1~6건이라 사실상 0원이다. Cloud Run 쪽은 지금도 같은 60초를 쓰고 있어 변화 없다. 돈이 드는 곳은
그대로 OpenAI(장당 약 $0.37 추정, #101 주석 참고)다.

---

## 실패 규칙 · 재시도 (2번 항목)

**원칙(2026-09-20 · 2026-09-25 사용자 결정):** 재시도 횟수는 **우리 코드가 센다**. 그래서 큐의 자동
재시도는 끈다(`--max-attempts=1`). 이러면 "자동 재시도" 라는 것이 아예 없어서, **실패 행 = 사람이 누른
횟수**가 되고 5회 규칙이 지금과 똑같이 작동한다. 구분할 필요 자체를 없애는 쪽이다.

### 10분 기준선 — 상수 하나로 둔다

`STALE_PENDING_AFTER = timedelta(minutes=10)` 을 **`avatars.py` 의 `MAX_CONSECUTIVE_FAILURES`(17줄) 바로
옆**에 두고 **POST 와 상태 조회가 같은 값을 본다.** 둘이 어긋나면 "상태 조회는 실패라는데 POST 는 아직
pending 이라고 튕기는" 잠긴 상태가 생긴다. 앱 폴링 상한도 같은 10분이다(아래 A3).
아바타의 두 숫자 규칙(5회 · 10분)이 한 화면에 보이는 자리다.

**기준 시각은 `datetime.now(SEOUL)`**(`app/core/time.py`)처럼 **시간대가 붙은 값**을 쓰고, 부르는 쪽이
`now` 를 넘기게 한다(`issue_daily_cards(card_repo, …, now)` 와 같은 방식 — `cards/issuing.py:15`).
`profile_avatars.created_at` 은 `timestamptz` 라 PostgREST 가 시간대 붙은 값을 돌려준다. naive 시각으로
비교하면 9시간 어긋나 **모든 pending 이 즉시 "낡음" 으로 판정**되고, 그러면 방금 등록한 작업이 실패로
내려가면서 유료 호출이 겹친다. 경계값 테스트도 `now` 를 넣어 줘야 돌릴 수 있다(아래 테스트 표).

### pending 이 남는 경우와 푸는 길

`pending` 은 세 가지 이유로 남는다: ① 워커가 통째로 죽음(배포 재시작 · OOM), ② 큐가
`dispatchDeadline` 240초에 요청을 끊음, ③ 작업 등록은 됐는데 큐가 아예 안 부름.

②는 특히 **코드로 못 잡는다** — 끊기면 asyncio 가 `CancelledError` 를 던지는데 이건 `BaseException` 이라
`except Exception` 을 그냥 통과한다. 워커 안에 "실패로 기록하고 끝내기" 를 붙여도 안 걸린다.
**그래서 ①②③ 전부 아래 10분 정리가 유일한 길**이다.

- **POST 쪽(고치는 주체):** 새 작업을 만들기 전에 `created_at` 이 10분보다 오래된 `pending` 행을
  먼저 `failed` 로 내린다. 그 다음에 새 `pending` 행을 넣는다.
  이 `failed` 는 **5회 카운트에 들어간다.**
- **상태 조회 쪽(읽는 주체):** 10분 넘은 `pending` 을 `failed` 로 **보여만 준다**(DB 는 안 고친다).
  결과 화면이 "다시 만들기" 를 띄우고, 사람이 누르면 그때 POST 가 위 정리를 한다.

### 워커가 한 번도 안 도는 경우 — POST 도 5회 규칙을 안다

5회 판정을 **워커 안에만** 두면 큰 구멍이 남는다. 큐가 아예 안 부르거나 워커가 매번 죽으면 `failed` 만
쌓이고 **기본 아바타 보상에 영영 못 닿아 온보딩이 갇힌다.** 5회 규칙("5번 실패하면 기본 아바타 + 하트 10",
`project_slice2_decisions_2026-09-19`)은 "OpenAI 가 5번 거절했을 때" 가 아니라 **"5번 해 봤을 때"** 의
약속이므로, 실패의 원인이 우리 쪽이어도 사람은 나갈 수 있어야 한다.

**그래서 POST 도 판정한다**(2026-09-25 대장 결정, 사용자 규칙 그대로라 따로 묻지 않음):
10분 정리 **직후**에 연속 실패 카운트를 세고, **5 이상이면 그 자리에서** 기본 아바타 복사 + 하트 10 +
`{"status": "fallback"}` 을 돌려준다. 작업을 새로 등록하지 않는다(어차피 무료 기회가 끝났다).

지금 라우터가 하는 그 일(`router.py:191~198` — `copy_fallback_avatar` → `insert_avatar_attempt(ready,
is_fallback=true)` → `grant_hearts` 10)을 **작은 공용 함수 하나로 빼서 POST(B3)와 워커(B4)가 같이
쓴다.** 두 자리에 같은 로직을 적으면 한쪽만 고쳐질 것이고, 그건 하트가 두 번 나가거나 안 나가는 길이다.

### pending 함정 (카운트)

`count_recent_consecutive_avatar_failures`(repository.py:129)는 최신 행부터 훑다가
`status != "failed"` 인 행을 만나면 멈춘다. 비동기가 되면 **가장 최신 행이 `pending`** 이라 항상 0 이 나온다.
→ `pending` 은 건너뛰고(`continue`), `ready` 에서만 멈추게 고친다.

### 중복 누름 (멱등성)

`profile_avatars` 에 `status = 'pending'` 부분 유니크 인덱스를 건다(Part C2). 두 번째 insert 가 23505 로
튕기면 **그 pending 행을 그대로 쓰고 작업도 다시 등록하지 않는다** → 같은 202.
단 이 재사용 분기는 **10분이 안 된 pending 에만** 적용한다. 오래된 pending 은 위 정리가 먼저 `failed` 로
내리므로 인덱스에 걸리지 않는다. (앱 쪽 1차 방어는 A2 의 진행 중 가드다.)

### 5회째 실패 → 기본 아바타 + 하트 10

지금 라우터가 하던 그대로 **행 두 줄로** 한다 — 마지막 실패를 `failed` 로 남기고, 기본 아바타를 복사한
새 행을 `status=ready, is_fallback=true` 로 insert 한다. 이력이 그대로 남는다.

부르는 자리는 **둘**이다 — 워커가 5번째 생성에 실패했을 때(B4), 그리고 POST 가 10분 정리 뒤 카운트 5 를
봤을 때(B3, 위 절). 둘 다 같은 공용 함수를 쓴다.

**하트가 두 번 나가지 않는 이유:** 이 함수를 부르고 나면 `ready` 행이 생기므로, 다음 POST 는 첫 관문인
`has_ready_avatar` 에서 409 로 막힌다. 워커 쪽 관문은 **기록하는 자리**다 — `status=eq.pending` 조건의
update 가 **0행을 돌려주면 5회 분기도 하트도 건너뛰고 200 으로 끝낸다**(B4 ④).
시작할 때 본 것(B4 ①)만으로는 부족하다: 생성이 60초 걸리는 사이에 POST 가 그 행을 10분 정리로 `failed`
로 내리고 **먼저 보상**할 수 있다(`queues pause` 를 오래 걸면 흔히 생긴다).
큐 재시도도 꺼져 있어 작업 하나는 한 번만 돈다.

### 지켜보기 — 지금의 한계

**대량 실패는 Cloud Run 로그로만 보인다.** 큐 재시도를 껐으므로 큐 쪽 지표도 잠잠하고, 앱은 개인별로만
"다시 만들기" 를 보여 준다. "어제부터 아무도 아바타를 못 만든다" 를 자동으로 알아차릴 길이 지금은 없다.
알림(디스코드 · 로그 기반 경보)은 이 계획 범위 밖으로 두고 조각 7 백로그에 적는다.

---

## 온보딩 순서 변경과 기존 사용자 (3번 항목)

`backend/app/profile_onboarding/onboarding_progress.py` `_STEPS` 에서 `("avatar", …)` 를
`("survey", …)` **뒤**, `("ideal_conditions", …)` **앞**으로 옮긴다. 조건식(`p["avatar_ready"]`)은 그대로다.
(pen 도 결과 화면 4장을 05-11 뒤 · 06-1 앞에 놓았다 — 같은 자리다.)

| 사람 | 지금 위치 | 바뀐 뒤 |
| --- | --- | --- |
| 이미 `ready` 인 사람 | 아무 영향 없음 | 아무 영향 없음 — `avatar` 단계를 지나칠 뿐 |
| 아직 아바타 없이 `avatar` 단계에 멈춰 있는 사람 | 04-3 | 04-4(외모 타입)로 **앞당겨** 이동하고, 성향 질문을 마치면 결과 화면으로 돌아온다. 데이터 이관 없음 |
| `pending` 인 사람 | 없음(새 상태) | `avatar_ready` 가 false 라 `avatar` 단계에 머문다 = 결과 화면에서 기다린다 |
| 원본 사진을 안 고른 사람 | `photos` 단계 | 그대로 — 원본 지정(`is_avatar_source`)은 여전히 `photos` 단계 조건이다 |

**주의:** 04-3(사진 고르기)은 `photos` 단계의 마지막 화면이고, 거기서 POST 를 쏜다. 즉 **작업 등록은
`photos` 단계에서, 결과 확인은 `avatar` 단계에서** 일어난다. `next_step` 은 아무것도 몰라도 된다.

---

## 화면 대조표 (4번 항목) — pen 담당(erd3) 과 맞추는 표

**2026-09-25:** erd3 가 결과 화면 4장을 **05-11(흡연) 뒤 · 06-1(이상형) 앞**으로 옮겼다.
번호는 **2026-09-25 사용자 결정으로 안 A 확정**이다 — `05-12` · `05-12b` · `05-12c` · `05-12d`.
`frontend/docs/DESIGN.md` §9 에 이 번호로 네 줄을 더한다(PR 4).

| 화면 번호 | pen 노드 | 화면 | 코드 | 상태 |
| --- | --- | --- | --- | --- |
| `04-3` | (기존 5c) | 아바타 사진 선택(DESIGN §9) | `frontend/lib/profile/view/avatar_source_screen.dart` | **있음.** CTA 동작만 바뀐다(대기 → 즉시 이동). 종전 "변환 중 토스트"(§13-56)는 안 쓰고, 누르고 넘어갈 때 **"아바타는 만드는 동안 다음 질문을 이어 가요"** 토스트를 띄운다(2026-09-25 사용자 확정, 문구는 pen `04-3` 과 같다) |
| `05-12` | `OgHRY` · `C4ixXA` | 만드는 중 | `avatar_generation_screen.dart` 의 `generating` 상태 | **pen 에 있음.** 문구가 "곧 끝나요" 류로 바뀔 수 있다 |
| `05-12b` | `c7QuSm` · `euW4T` | 실패 · 다시 만들기 | 같은 화면 `failed` 상태 | **pen 에 있음.** 다시 만들기 = 새 작업 등록 |
| `05-12c` | `tzqhO` · `GW3Yr` | 완성 — 아바타 보여 주고 다음 | 같은 화면 `ready` 상태 | **pen 에 있음(새로 그릴 필요 없음).** 코드 쪽만 신규 — 지금은 ready 가 되면 그림 없이 곧장 넘어간다 |
| `05-12d` | `Q7VmU` · `zXe2p` | 5회 실패 보상 안내 | `showCompensationDialog` | **pen 에 있음.** 하트 10 안내 + **기본 아바타 그림도 같이** 보여 준다(아래 A3) |

노드 짝은 **erd3 보고와 대조해 확인됨**(2026-09-25). 화면마다 노드가 둘인 것은 마스터와 플로우 사본이다 —
문구를 고칠 때 둘 다 같이 고친다(§9 관례).

---

## ERD · 문서 변경 목록 (Part C 를 클라우드에 적용하기 전에 처리)

1. `docs/ERD.md` §3 `profile_avatars` — `pending` 행이 실제로 쓰인다는 설명(지금까지는 default 값일 뿐
   아무도 안 넣었다), 새 칸 `is_fallback`, 새 부분 유니크 인덱스.
2. `frontend/docs/DESIGN.md` §9 — 04-3 CTA 문구/동작, 결과 화면 4장의 확정 번호, 온보딩 순서(아바타가
   성향 질문 뒤).
3. `backend/DEPLOY.md` — 새 절 "아바타 작업 큐(Cloud Tasks)", §2 `--set-env-vars` 3개 추가.
   (§2 `--set-secrets` 누락 3건은 **별개 문서 문제**다 — 운영에는 이미 들어가 있고,
   `project_slice6_deploy_docs_todo_2026-09-22` 로 조각 끝 문서 정리 때 처리한다. 이 계획 범위 밖)

---

## Part C: Supabase 마이그레이션 (파일 작성 + 로컬 검증까지)

**이미 클라우드에 적용된 파일은 고치지 않는다 — 새 파일을 만든다.**
`supabase/migrations/<타임스탬프>_avatar_async_generation.sql`:

- [ ] C1. `alter table public.profile_avatars add column is_fallback boolean not null default false;`
      — 5회 실패 보상으로 복사해 넣은 기본 아바타 행을 표시한다. 결과 화면이 하트 10 안내를 띄울지
      판단할 근거. `comment on column` 한 줄도 같이.
- [ ] C2. 부분 유니크 인덱스로 **중복 누름 차단**:
      `create unique index profile_avatars_one_pending on public.profile_avatars (profile_id) where status = 'pending';`
      — 앱이 CTA 를 두 번 눌러도 두 번째 insert 가 23505 로 튕긴다. 멱등성의 마지막 방어선이 DB 다.
- [ ] C3. pgTAP: 새 인덱스로 `pending` 두 줄이 안 들어가는지, `is_fallback` 기본값이 false 인지.
      기존 `profile_avatars_ready_has_storage_path` 체크는 그대로 둔다(`pending` 은 경로가 null 이어도 된다).
- [ ] C4. 로컬 스택에서 `supabase db reset` + pgTAP 통과 확인. **클라우드 적용은 하지 않는다.**
- [ ] C5. 파일 맨 위 주석에 **되돌리기 SQL** 두 줄을 적어 둔다(`drop index …one_pending;`,
      `alter table … drop column is_fallback;`) — 서버를 revert 할 때 인덱스가 발목을 잡는다(아래 "되돌리기").

---

## Part B: FastAPI

### B1. `backend/app/core/batch_auth.py` (신규, 조각 6 계획서와 **같은 파일**)

- [ ] 함수 하나로 둔다: `async def verify_oidc_token(token: str, *, audience: str, service_account_email: str) -> None`.
      **설정을 직접 읽지 않는다** — 값은 부르는 라우터가 넘긴다. 조각 6(스케줄러)과 아바타 워커가 서로 다른
      환경변수를 보기 때문이고, 그래야 테스트가 설정 없이 돈다.
- [ ] 구글이 서명한 OIDC ID 토큰을 검증한다. `google.oauth2.id_token.verify_oauth2_token(token,
      GoogleAuthRequest(), audience=audience)` 를 `asyncio.to_thread` 로 감싼다(인증서 조회가 동기 I/O다).
- [ ] audience 확인만으로는 부족하다 — 같은 URL 을 아는 다른 서비스 계정도 통과한다. **발급자 이메일이
      우리가 기대한 계정인지**(`claims["email"]`)까지 본다. `email_verified` 도 본다.
- [ ] 검증 실패는 `ValueError` **와** `google.auth.exceptions.GoogleAuthError` 둘 다 잡아 401 로 바꾼다
      (서명 · audience 불일치는 `ValueError`, 인증서 조회 실패 같은 전송 오류는 `GoogleAuthError` 다).
- [ ] `service_account_email` 이 빈 문자열이면 **아무도 통과시키지 않는다**(설정을 빠뜨린 배포가 열린 문이
      되지 않게 — `card_batch_secret` 과 같은 규칙).
- [ ] **조각 6 과 겹친다.** 먼저 머지되는 쪽이 이 파일을 만들고, 나중 쪽은 `import` 만 한다. 두 계획서에
      같은 파일이 있다는 것을 PR 설명에 적는다.

### B2. `backend/app/profile_onboarding/avatar_tasks.py` (신규)

- [ ] `AvatarTaskQueue.enqueue(profile_id, attempt_id)` — Cloud Tasks v2 REST 한 방:
      `POST https://cloudtasks.googleapis.com/v2/projects/{p}/locations/{loc}/queues/{q}/tasks`
      — `{p}` 는 **`settings.google_cloud_project`**(`FcmSender` 가 이미 쓰는 그 값), `{loc}` 은
      **모듈 상수 `_LOCATION = "asia-northeast3"`**. 둘 다 환경변수로 만들지 않는다 — 프로젝트는
      이미 설정에 있고 리전은 Cloud Run 과 같이 움직이는 값이라, 늘려 봐야 배포할 때 빠뜨릴 칸만 는다.
      **환경변수는 3개(큐 이름 · 워커 URL · 서비스 계정)를 유지한다.**
      본문 `{"task": {"httpRequest": {"url": <AVATAR_WORKER_URL>, "httpMethod": "POST",
      "headers": {"Content-Type": "application/json"}, "body": <base64 JSON>,
      "oidcToken": {"serviceAccountEmail": <SA>, "audience": <AVATAR_WORKER_URL>}},
      "dispatchDeadline": "240s"}}`.
- [ ] 액세스 토큰은 `FcmSender` 와 **같은 방식**으로 받는다(`google.auth.default(scopes=[cloud-platform])`
      + `asyncio.to_thread(credentials.refresh, ...)`). 자격증명 객체를 주입받는 자리를 남겨 테스트가 쉽게.
- [ ] 작업 이름(`task.name`)은 **주지 않는다.** 이름으로 중복 제거를 하면 구글 문서가 경고하는 처리량
      저하가 붙고, 우리 멱등성은 이미 C2 의 `pending` 유니크 인덱스가 맡는다.

### B3. `router.py` — POST /profile-onboarding/avatar/generate 를 "등록만" 하게

순서가 중요하다. **설정 검사 → 기존 검사 → 오래된 pending 정리 → 5회 판정 → insert → enqueue** 다.

- [ ] ① 설정 3개(`avatar_tasks_queue` · `avatar_worker_url` · `avatar_tasks_service_account`) 중
      하나라도 비면 **행을 만들기 전에** 503. 못 부를 걸 알면서 행부터 남기지 않는다.
- [ ] ② 기존 검사는 그대로: `has_ready_avatar` → 409(1회 무료), 원본 사진 없음 → 409.
      (5회 보상을 받은 사람도 `ready` 행이 있으므로 여기서 409 다 — 다시 눌러도 안 만들어진다.)
- [ ] ③ `created_at < now - STALE_PENDING_AFTER` 인 `pending` 행을 `failed` 로 내린다(위 "10분 기준선").
      `now` 는 `datetime.now(SEOUL)` 로 **부르는 쪽이 넘긴다**. 이걸 **insert 전에** 해야 유니크 인덱스가
      비고, 그 `failed` 가 5회 카운트에 들어간다.
- [ ] ④ **정리 직후에 연속 실패 카운트를 센다. 5 이상이면 그 자리에서 보상하고 끝낸다** —
      공용 fallback 함수(위 "5회째 실패") 호출 → `200 {"status": "fallback", "avatar_url": …,
      "compensation_hearts": 10}`. 작업은 등록하지 않는다. 워커가 한 번도 안 도는 상황에서 온보딩이
      갇히지 않게 하는 유일한 출구다(위 "워커가 한 번도 안 도는 경우").
      **칸 이름은 B5 와 글자까지 같은 `avatar_url`** 이다 — 앱은 POST 응답과 상태 조회를 `_toOutcome`
      **하나로** 읽는다(A1). 한쪽만 `storage_path` 로 내보내면 그 길에서만 캐스트가 터진다(D14 와 같은 모양).
- [ ] ⑤ `insert_avatar_attempt(profile_id, "pending", None)` 으로 행을 만들고 **id 를 돌려받는다**
      (PostgREST `Prefer: return=representation`).
      **23505 감지 주의:** 공용 `raise_for_status`(`core/http.py:30~38`)는 23505 를 **409
      `ALREADY_REGISTERED` 로 바꿔 던진다** — 그대로 두면 중복 누름이 409 로 나가 앱이 "이미 만들었어요"
      를 띄운다. `pending` 행 전용 insert 함수를 따로 두고 **23505 일 때만 `None` 을 돌려주게** 한다
      (다른 제약 위반은 지금처럼 `raise_for_status` 에 맡긴다). 라우터는 `None` 일 때만 재사용 분기로
      가서, **그 pending 행을 그대로 쓰고 작업도 다시 등록하지 않는다** → 중복 누름은 조용히 같은 202.
- [ ] ⑥ `AvatarTaskQueue.enqueue` 가 실패하면 **방금 만든 행을 지우고** 502. `failed` 로 두지 않는다 —
      OpenAI 를 부르기도 전이라 "사람이 시도한 이력" 이 아니고, 5회 카운트에 들어가면 우리 인프라 사고로
      사용자의 무료 기회를 깎는 셈이 된다. 행을 지우면 인덱스도 같이 풀려 바로 다시 누를 수 있다.
      **DELETE 마저 실패해도 갇히지 않는다** — 남은 `pending` 은 10분 뒤 ③ 이 치운다(최악 10분 대기).
- [ ] ⑦ 응답 `202 {"status": "pending"}`. 원본 사진 다운로드 · OpenAI 호출은 **여기서 사라진다**.

### B4. `backend/app/profile_onboarding/tasks_router.py` (신규, Cloud Tasks 전용) — POST /tasks/avatar-generate

- [ ] **파일을 따로 만들고 `main.py` 에서 `include_router` 한다** — `cards/batch_router.py` ·
      `chat/batch_router.py` 와 같은 관례다(`main.py:7~9` · `38~41`). 사람이 부르는 라우터와 기계가
      부르는 라우터는 인증이 통째로 달라서, 한 파일에 섞으면 의존성을 잘못 붙이기 쉽다.
- [ ] 인증은 **B1 `verify_oidc_token`**(`Authorization: Bearer <ID 토큰>`), audience 와 계정 이메일은
      라우터가 `settings` 에서 읽어 넘긴다.
- [ ] 본문 `{"profile_id": ..., "attempt_id": ...}`. 순서는 **① 행 잡기 → ② 카운트 → ③ 생성 → ④ 기록**.
- [ ] ① **먼저 그 attempt 행을 읽어 아직 `pending` 인지 본다**(읽기면 충분하다 — 여기서 상태를 바꾸면
      ④ 의 `status=eq.pending` 조건이 늘 0행이 된다). 240초에 끊겼다가 늦게 깨어난 워커가, 이미 10분
      정리로 `failed` 가 된 행을 되살리면 안 된다. `pending` 이 아니면 그 자리에서 **조용히 200**.
      이건 **유료 호출을 아끼는 빠른 관문**일 뿐이고, 하트 이중 지급을 막는 **진짜 관문은 ④** 다.
- [ ] ② **카운트는 생성하기 전에 센다.** `AvatarGenerator` 는 넘겨받은 카운트에 **+1 을 해서**
      `>= MAX_CONSECUTIVE_FAILURES` 를 본다(`avatars.py:99~100`). 이번 pending 행을 `failed` 로 바꾼 뒤에
      세면 그 행이 이중으로 잡혀 **4회째에 보상이 나간다.**
- [ ] ③ 원본 사진 다운로드 → `AvatarGenerator.generate`(그대로 재사용, 화풍 지시문 손대지 않음).
- [ ] ④ 성공이면 그 attempt 행을 `ready` + `storage_path` 로 update, 실패면 `failed` 로 update.
      **`status=eq.pending` 조건을 걸고, 돌아온 행 수를 그 자리에서 본다 — 0행이면 5회 분기도 하트 지급도
      건너뛰고 200 으로 끝낸다.** ① 은 생성하기 **전**의 사진일 뿐이다. 생성이 60초 걸리는 사이에 POST 가
      그 행을 정리하고 **먼저 보상**할 수 있어서(`queues pause` 를 오래 걸면 흔하다), 여기서 안 보면
      하트가 두 번 나간다.
- [ ] ④ 가 0행인데 **생성은 성공한** 경우, 올려 둔 그림은 아무도 안 쓰는 고아가 된다.
      **로그 한 줄만 남기고 200** — 지우러 가지 않는다(드물고, 지우다 실패하면 워커만 복잡해진다).
- [ ] 5회째면 **공용 fallback 함수**(위 "5회째 실패", B3 ④ 와 같은 함수)를 부른다 — 기본 아바타 복사 →
      `status=ready, is_fallback=true` 행 insert → `grant_hearts` 10. 마지막 실패 행은 그대로 남는다.
      **④ 가 0행이었으면 여기까지 오지 않는다.**
- [ ] **항상 200 을 돌려준다**(생성 실패도 우리에겐 정상 처리다). 큐가 5xx 를 재시도 대상으로 보게 두면
      우리 카운트와 겹친다 — 큐 설정(`--max-attempts=1`)과 코드 양쪽에서 막는다.
- [ ] `dispatchDeadline` 240초에 끊기면 `CancelledError`(= `BaseException`)라 `except Exception` 으로
      못 잡는다. **여기서 뒷정리를 시도하지 않는다** — 남은 `pending` 은 10분 정리가 치운다(위 참조).

### B5. `router.py` — GET /profile-onboarding/avatar/status (신규)

- [ ] 로그인한 본인 것만. 최신 행 1줄을 보고 돌려준다:
      `{"status": "pending" | "ready" | "fallback" | "failed" | "none", "avatar_url": ...,
      "compensation_hearts": 10 | null}`.
- [ ] **`fallback` 은 반드시 별도 상태값으로 나간다.** 앱은 문자열 `'fallback'` 로 갈래를 나누는데
      (`http_avatar_repository.dart:20`) 서버가 `ready` 로 보내면 `AvatarReady` 로 떨어져 **05-12d 보상
      안내가 영영 안 뜬다** — 하트 10 은 나갔는데 사람은 왜 받았는지 모른다. 판단 근거는 `is_fallback`
      칸(C1)이고, **`avatar_url`(기본 아바타)과 `compensation_hearts: 10` 을 같이 싣는다.**
      지금 동기 POST 응답(`router.py:198`)은 같은 자리에 **`storage_path`** 를 싣는다 — 이름이 다르다.
      비동기에서는 POST(B3 ④)와 이 조회 **둘 다 `avatar_url`** 로 통일하고, 앱도 그 이름을 읽게 고친다(A1).
- [ ] **`avatar_url` 은 서버가 완성해서 준다** — `{supabase_url}/storage/v1/object/public/avatars/{storage_path}`.
      카드(`cards/router.py:90`) · 채팅(`chat/router.py` `_avatar_url`)과 **같은 모양**이다.
      Dart 가 접두사를 손으로 붙이는 자리를 만들지 않는다(그런 자리는 버킷을 바꾸면 전부 깨진다).
- [ ] `pending` 인데 `created_at` 이 `STALE_PENDING_AFTER` 보다 오래됐으면 `failed` 로 내려 보낸다
      (DB 는 안 고친다 — 고치는 건 POST 다).
- [ ] 행이 하나도 없으면 `none`. **여기서 작업을 자동 등록하지 않는다** — 원본 사진만 고르고 앱을 닫은
      사람이 여기 온다. 앱은 `none` 을 `failed` 와 같게 다뤄 "다시 만들기" 를 띄운다.
- [ ] **D14 의 교훈:** ready 계열(`ready` · `fallback`) 응답에는 그림 주소를 반드시 같이 싣는다.
      앱이 캐스트하는 칸은 계약이다.

### B6. `repository.py` · `avatars.py` · `onboarding_progress.py`

- [ ] `count_recent_consecutive_avatar_failures` — `pending` 건너뛰기(위 "pending 함정").
- [ ] `insert_avatar_attempt` 가 만든 행의 id 를 돌려주도록 고친다.
- [ ] 신설: `insert_pending_avatar_attempt(profile_id) -> UUID | None`
      — **23505 일 때만 `None`**(= 아직 10분 안 된 pending 이 있다). 다른 오류는 `raise_for_status` 에
      맡긴다. 공용 `raise_for_status` 를 그냥 쓰면 23505 가 409 로 나가 버린다(B3 ⑤).
- [ ] 신설: `update_avatar_attempt(attempt_id, status, storage_path)`
      — **`status=eq.pending` 조건 포함**, 갱신된 행 수를 돌려준다(B4 ④ 가 이걸 본다).
      `is_fallback` 은 여기서 받지 않는다 — 보상 행은 update 가 아니라 **insert** 로 들어간다.
- [ ] `insert_avatar_attempt`(`repository.py:110`)에 **`is_fallback` 인자를 더한다**(기본 `False`).
      `apply_fallback_avatar` 가 이걸로 보상 행을 남긴다.
- [ ] 신설: `fetch_avatar_attempt(attempt_id)` — 워커 ①(읽기)이 "아직 `pending` 인가" 를 본다.
- [ ] 신설: `fail_stale_pending_avatars(profile_id, before)` — 10분 정리(B3 ③).
      `before` 는 부르는 쪽이 넘긴 시간대 붙은 값이고, **`profile_id` 로 한정**한다(남의 행은 안 건드린다).
- [ ] 신설: `delete_avatar_attempt(attempt_id)` — enqueue 실패 되돌리기(B3 ⑥).
- [ ] 신설: `fetch_latest_avatar_attempt(profile_id)` — 상태 조회(B5). `is_fallback` 도 같이 읽어 온다.
- [ ] 신설(`avatars.py`): `apply_fallback_avatar(...)` — 기본 아바타 복사 + `is_fallback=true` 행 insert +
      `grant_hearts` 10 을 한 함수로. **B3(POST)과 B4(워커)가 같이 쓴다.** `router.py:191~198` 에서
      그대로 옮겨 온다. 두 라우터 중 한쪽에 두면 다른 쪽이 라우터를 import 하게 되므로 `avatars.py` 에
      둔다(협력자는 인자로 받는다 — `AvatarGenerator` 와 같은 방식).
- [ ] `STALE_PENDING_AFTER` 도 `avatars.py` `MAX_CONSECUTIVE_FAILURES` 옆에(위 "10분 기준선").
- [ ] `_STEPS` 에서 `avatar` 를 `survey` 뒤로 이동(위 3번 항목).

### B7. `settings.py` · `pyproject.toml` · `DEPLOY.md`

- [ ] `avatar_tasks_queue: str = ""`, `avatar_worker_url: str = ""`, `avatar_tasks_service_account: str = ""`
      셋 다 기본 빈 값. 비면 POST 는 503(설정 안 됨), 워커는 401 — 조용히 열리지 않게.
- [ ] `pyproject.toml` `dependencies` 에 `"google-auth>=2.38"` 을 **명시로 추가**(위 "새 의존성" 참조.
      이미 설치돼 있는 2.58.0 을 적어 두는 것이라 실제로 받아 오는 패키지는 안 바뀐다).
- [ ] `DEPLOY.md` 에 큐 만드는 절을 추가한다. **값(URL · 계정 이메일)은 문서에 적지 않고 이름만 적는다.**
      전제 한 줄을 같이 적는다: **큐 리전 = Cloud Run 리전(`asia-northeast3`)** — 코드가 리전을 모듈
      상수로 박고 있어서(B2), 큐를 다른 리전에 만들면 등록이 조용히 404 로 실패한다.
- [ ] `DEPLOY.md` 에 각주 한 줄: **`OPENAI_API_KEY` 를 빠뜨리고 배포하면 화면에는 오류가 하나도 안 뜨고
      아바타만 안 만들어진다.** 비동기가 되면 실패가 워커 안에서 나므로 POST 는 멀쩡히 202 를 주고,
      사람은 "다시 만들기" 를 다섯 번 누른 뒤 기본 아바타를 받는다 — 겉보기엔 정상 동작이다.
      확인할 곳은 Cloud Run 로그의 `아바타 생성 실패`(`avatars.py:98`)뿐이다.

---

## Part A: Flutter

### A1. 모델 · 저장소

- [ ] `AvatarGenerationOutcome` 에 `AvatarPending` 을 더한다(sealed 라 `when` 쓰는 곳이 전부 컴파일
      오류로 드러난다 — 빠뜨릴 수 없다).
- [ ] **`AvatarFallback` 에 그림 주소를 더한다.** 지금은 `compensationHearts` 만 들고 있어
      (`avatar_generation_outcome.dart:42`) 서버가 준 기본 아바타 경로를 **버린다** — 결과 화면에서
      보상 안내와 함께 그림을 띄우려면 이 값이 있어야 한다(D14 리뷰 권고).
- [ ] `AvatarRepository.fetchAvatarStatus()` 추가, `HttpAvatarRepository` 는 `GET .../avatar/status`.
      매핑은 `_toOutcome`(`http_avatar_repository.dart:16~23`)을 그대로 넓힌다 —
      `pending` → `AvatarPending`, `fallback` → `AvatarFallback(avatar_url, compensation_hearts)`,
      `none` 은 `AvatarFailed` 로(자동 재등록 없음 — B5 와 같은 판단).
- [ ] **`ready` 도 `avatar_url` 을 읽는다.** 지금은 `storage_path` 를 읽고 있다
      (`http_avatar_repository.dart:19`). `AvatarReady` 가 들고 있는 값의 **뜻이 저장 경로에서 전체
      주소로 바뀐다** — 서버가 완성해서 준다(B5). 안 고치면 없는 칸을 캐스트해서 터진다(D14 재발).
      값을 쓰는 자리(A3 의 `Image.network`)도 같이 본다.
- [ ] **하트 수는 서버가 준 `compensation_hearts` 를 그대로 쓴다** — 앱에 `10` 을 박지 않는다.
      보상 액수는 서버 규칙이고, 바뀌면 앱만 거짓말을 하게 된다.
- [ ] `generateAvatar()` 의 성공값은 이제 `AvatarPending` 이다(202).

### A2. 04-3 (`avatar_source_screen.dart`) — 누르고 바로 넘어가기

**흐름을 한 줄로 못박는다:** 사진 업로드 성공 → `generate()`(202) → 토스트 → `refresh()`.
**부르는 자리는 화면이 아니라 `PhotosViewModel.submit()` 안**이고, 정확히 **`_submittedState()` 뒤 ·
`_refreshOnboardingStepIfCompleted()` 앞**이다(`photos_view_model.dart:152~159`).
**등록이 먼저, 이동이 나중** — 순서가 뒤집히면 다음 화면으로 넘어간 뒤에 POST 가 실패해도 보여 줄
자리가 없다. POST 는 이제 202 를 바로 주므로 여기서 기다리는 시간은 생성 시간이 아니다.

- [ ] `_submittedState()` 가 돌려준 상태를 **바로 `state` 에 넣지 말고 지역 변수로 받는다.**
      업로드가 성공했을 때만 `generate()` 를 부르고, 끝난 뒤 한 번에 `state` 를 갱신한다 —
      그래야 `isSubmitting` 이 **업로드와 `generate()` 호출을 모두 덮는다**(아래 토스트).
- [ ] `generate()` 가 실패하면 `PhotosUiState.errorMessage` 를 채우고 **`completed` 는 세우지 않는다**.
      04-3 은 photos 상태만 그린다(`avatar_source_screen.dart:60~64`) — 오류도 그 상태로 나가야 보이고,
      `completed` 가 없으면 `_refreshOnboardingStepIfCompleted()` 가 조용히 돌아가 화면에 머문다.
- [ ] **어디서 멈추고 어디서 넘어가나**(2026-09-25 대장 결정):
      **응답을 못 받은 경우(타임아웃 · 네트워크)와 409 `AVATAR_ALREADY_CREATED`(이미 있음)는 그대로
      `refresh()` 로 넘어간다** — 서버에는 이미 아바타나 작업이 있어 여기 붙잡아 둘 이유가 없고,
      결과는 05-12 가 보여 준다. **409 `AVATAR_SOURCE_REQUIRED` 와 503(설정 안 됨)은 그 자리에 오류를
      보여 준다** — 앞은 사람이 고칠 수 있고, 뒤는 넘어가 봐야 결과 화면이 빈다.
- [ ] **진행 중 가드는 화면이 아니라 `generate()` 안에 둔다** — `if (state.status ==
      AvatarGenerationStatus.generating) return;`. 04-3(업로드 직후)과 05-12b("다시 만들기")
      **두 화면이 같은 함수를 부르므로**, 화면마다 가드를 두면 한쪽을 빠뜨린다.
      D14 운영 로그에서 59초 사이에 POST 가 두 번 나가 **유료 호출이 2회** 일어났다. 서버 쪽은
      `pending` 유니크 인덱스가 막지만, 돈이 나가는 길은 양쪽에서 막는다.
- [ ] 토스트는 **지금 구조 그대로** 둔다 — `state.isSubmitting` 동안 `AppToast`
      (`avatar_source_screen.dart:70~78`). **타이머도, 새 상태 필드도 만들지 않는다.** 업로드가 몇 초
      걸리니 그동안 보인다. 1.5초 지연은 사용자가 정한 "누르면 바로 넘어가기" 와 어긋나 넣지 않는다
      (2026-09-25 대장 판단).
- [ ] 문구는 **"아바타는 만드는 동안 다음 질문을 이어 가요"**(2026-09-25 사용자 확정).
      pen `04-3` 과 글자까지 같아야 한다 — 왜 그림이 아직 없는지 알려 주는 유일한 안내다.
      자리는 §13-59 규칙대로 CTA 바로 위 · 가로 중앙(버튼과 12px).
- [ ] 이동은 지금처럼 `onboardingStepListenable.refresh()` 로 서버가 정한 다음 단계를 따른다 —
      앱이 순서를 따로 외우지 않는다(순서가 또 바뀌어도 앱은 그대로).

### A3. 결과 화면 (`avatar_generation_screen.dart`)

- [ ] **`initState` 의 `generate()` 호출을 지운다**(`avatar_generation_screen.dart:24`). 이제 이 화면은
      결과를 **보는** 자리다 — 그대로 두면 성향 질문을 마치고 들어올 때마다 새 작업이 등록된다.
- [ ] 진입하면 `fetchAvatarStatus()`. `pending` 이면 **5초 간격 폴링**, 화면을 떠나면 타이머를 끊는다
      (`ref.onDispose`). 폴링 상한 **10분** — 서버 `STALE_PENDING_AFTER` 와 같은 값이다.
- [ ] `ready` → 05-12c: 서버가 준 `avatar_url` 을 그대로 `Image.network` 에 넘기고 "다음".
      **접두사를 앱에서 붙이지 않는다**(B5).
- [ ] `fallback` → 05-12d: **기본 아바타 그림 + 보상 하트 안내**를 같이 보여 준다.
      하트 수는 서버가 준 `compensation_hearts` 를 그대로 쓴다(A1).
- [ ] `failed` · `none` → 05-12b: "다시 만들기" = `generateAvatar()` 를 다시 쏘고 pending 으로.
- [ ] **다시 만들기가 실패했을 때도 `refresh()` 를 한 번 부른다.** 지금은 `completed` 일 때만 부른다
      (`avatar_generation_view_model.dart:43` `_refreshOnboardingStepIfCompleted`). 앱이 응답을 놓쳤을
      뿐 서버에서는 이미 등록이 끝난 경우가 있는데, 지금 코드는 그 자리에 갇힌다(D14 리뷰 권고).
- [ ] **폴링은 화면이 열려 있는 동안만.** 백그라운드 폴링 · 푸시 알림은 안 넣는다(YAGNI — 결과를 보는
      시점이 온보딩 안이라 화면이 항상 열려 있다). 나중에 온보딩 밖에서도 알려야 하면 그때 FCM 을 붙인다.

---

## 테스트 전략 (7번 항목)

| 무엇을 | 어떻게 | 무엇이 깨지면 잡히나 |
| --- | --- | --- |
| 작업 등록 | 기존 `httpx.MockTransport` 로 **실제로 나가는 요청 본문**을 본다 — url · oidcToken.audience · base64 본문 | 큐 이름/URL/계정을 잘못 조립 |
| 중복 누름 | 같은 프로필로 POST 두 번, 두 번째는 23505 를 흉내 내고 **작업 등록이 1회**인지 | 작업이 두 배로 쌓임 |
| **10분 지난 pending + POST** | 오래된 pending 이 있는 상태로 POST → **작업 1회 등록**, 그 옛 행이 `failed` 로 바뀌고 **5회 카운트 +1** | 워커가 계속 죽을 때 영영 못 빠져나옴 |
| **POST 쪽 5회 보상** | failed 4 + 10분 지난 pending 1 로 POST → 정리 뒤 카운트 5 → **`fallback` 응답 · `grant_hearts` 1회 · 작업 등록 0회** | 워커가 한 번도 안 도는 배포에서 온보딩이 갇힘 |
| **경계값(now 주입)** | `now` 를 넣어 **9분 59초 = 재사용**(PATCH 0 · enqueue 0), **10분 1초 = 정리 1 · enqueue 1** | 기준이 한쪽으로 밀려 유료 호출이 겹치거나 영영 안 풀림 |
| **정리 범위** | 다른 프로필에도 오래된 pending 을 두고 POST → **그 행은 그대로** | 한 사람이 누르면 남의 작업이 실패 처리됨 |
| **23505 재사용 응답** | 10분 안 된 pending 이 있는 채로 POST → **409 가 아니라 202** (`raise_for_status` 가 409 로 바꾸는 길을 안 탄다) | 중복 누름에 "이미 만들었어요" 가 뜸 |
| **fallback 받은 뒤 재요청** | `is_fallback` ready 행이 있는 사람이 POST → **409**(`has_ready_avatar`) | 보상받고도 계속 만들 수 있음 |
| **워커 카운트 시점** | pending 1 + failed 4 에서 생성 실패 → **fallback**, pending 1 + failed 3 이면 **fallback 아님** | 4회째에 보상이 나가거나 6회까지 안 나감 |
| **enqueue 실패** | 큐 호출이 500 을 내게 하고 POST → **행이 남아 있지 않고** 502, 실패 카운트 그대로 | 우리 인프라 사고가 사용자 무료 기회를 깎음 |
| **설정 3개가 빔** | 빈 설정으로 POST → 503(**행 생성 전**), 워커 호출 → 401 | 설정 빠뜨린 배포가 열린 문이 됨 |
| 워커 인증 | 토큰 없음 · 다른 계정 이메일 · audience 불일치 → 401 | 누구나 부를 수 있는 생성 엔드포인트 |
| 워커 처리 | 성공/실패/5회째 세 갈래, 행이 update 되는지, 5회째에 `grant_hearts` 1회 · 행 두 줄 · `is_fallback=true` | 하트 중복 지급, 이력 사라짐 |
| **늦게 깨어난 워커** | 이미 `failed` 인 attempt 로 워커 호출 → `ready` 로 **안 바뀌고** 200 | 판정 끝난 행이 되살아남 |
| **늦게 깨어난 워커 + POST 보상** | failed 4 + 10분 지난 pending 으로 POST(보상 1회) → **그 pending 의 attempt 로 워커 호출** → 하트 추가 0 · `ready` 행 추가 0 · 200 | 하트가 두 번 나가고 보상 행이 두 줄 남음 |
| pending 함정 | pending 1 + failed 4 → 카운트 4 | 5회 규칙이 영영 안 걸림 |
| 상태 조회 | 5가지 응답 모양(pending · ready · fallback · failed · none) + 10분 지난 pending → failed + **`avatar_url` 접두사** | 무한 "만드는 중", 그림 안 뜸 |
| **상태 조회 fallback** | `is_fallback` 행 → `status: "fallback"` · **`avatar_url`(기본 아바타)** · `compensation_hearts: 10` 이 다 실리는지 | 하트는 나갔는데 보상 안내가 영영 안 뜸 |
| 순서 | `next_step` 이 survey 뒤에 avatar 를 내놓는지, ready 인 사람은 건너뛰는지 | 기존 사용자 흐름 깨짐 |
| 앱 계약 | D14 처럼 **서버가 실제로 보내는 본문 모양 그대로** 저장소를 돌린다(5종) | 계약 불일치 무한 로딩 재발 |
| **POST 쪽 fallback 본문** | B3 ④ 가 내는 본문 그대로 앱 저장소에 먹여 `AvatarFallback(그림 주소, 서버가 준 하트 수)` 가 나오는지 | 보상 화면에 그림이 안 뜨거나 하트 수가 앱 상수로 굳음 |
| **`avatar_url` 만 실린 ready** | `storage_path` 없이 `avatar_url` 만 있는 ready 본문 → `AvatarReady` | 이름을 바꾸다 캐스트가 터져 D14 재발 |
| **앱 `none` 처리** | 상태 `none` → 화면이 "다시 만들기" 를 띄우는지(자동 등록 안 함) | 사진만 고르고 나간 사람이 빈 화면에 갇힘 |
| **앱 진행 중 가드** | `generate()` 를 연달아 두 번 → 저장소 호출 1회 | 유료 호출 2회(D14 실측) |
| 앱 폴링 | 가짜 저장소로 pending→ready 전이, dispose 뒤 타이머가 안 도는지 | 화면 나가도 폴링이 계속됨 |

로컬 스택에는 Cloud Tasks 가 없다. **로컬에서 워커를 부르는 우회로는 만들지 않는다** — 두 갈래 코드가
생기면 운영에서만 나는 버그가 다시 생긴다. 로컬 확인은 목으로, 진짜 확인은 실기기 배포로 한다.

**기존 테스트에 영향 없음**(분석담당33 확인, 2026-09-25): 지금 pgTAP 과 카드 · 채팅 쪽은 이 변경이
건드리는 자리가 없다. 새 인덱스는 `pending` 행에만 걸리고 `is_fallback` 은 기본값이 있으며,
`profile_avatars` 를 읽는 다른 모듈이 없다.

---

## PR 나누기

| # | 범위 | 내용 | 선행 |
| --- | --- | --- | --- |
| 1 | DB | Part C 마이그레이션 + pgTAP + ERD 문서 | — (클라우드 적용은 사용자 승인 뒤) |
| 2 | 서버 | B1~B7 전부. 순서 변경(B6)까지 한 PR — 쪼개면 중간 상태가 "작업은 도는데 아무도 결과를 안 본다" 가 된다 | PR 1 클라우드 적용 |
| 3 | 앱 | A1~A3. 커밋은 **모델 / 뷰모델 / 화면 / 테스트** 로 나눈다(커밋 규칙) | PR 2 배포 |
| 4 | 문서 | DEPLOY.md · DESIGN.md · 노션 | 조각 끝에 한 번(문서 규칙) |

**배포 순서 주의:** PR 2 가 배포되면 **구 앱은 202 `pending` 을 못 알아듣고 실패 화면**을 띄운다
(`_ => AvatarFailed()`). 스토어 배포 전이라 실기기 한 대 문제지만, 앱을 같이 올리기 전에는 아바타를
만들지 않는 편이 낫다.

---

## 되돌리기

- **앱만** 되돌리기: 불가능하지 않다 — 구 앱 + 새 서버 = 위의 실패 화면. 쓰지 말 것.
- **서버 되돌리기**: PR 2 를 revert 하면 동기 방식으로 돌아간다. 남아 있던 `pending` 행은
  `has_ready_avatar` 가 false 라 다시 만들 수는 있지만, 옛 코드는 `pending` 을 정리할 줄 모른다 —
  최신 행이 영영 `pending` 이라 5회 카운트가 0 에서 멈추고, 유니크 인덱스도 그대로 남는다.
  → revert 할 때 **C5 의 되돌리기 SQL** 을 같이 적용한다.
- **큐만 멈추기**: `gcloud tasks queues pause <QUEUE>` — 코드 배포 없이 생성만 세운다. 사고 시 첫 손잡이.
  **단 10분 안에 푼다.** 넘기면 그동안 `pending` 이던 사람들의 행이 10분 정리에 `failed` 로 내려가
  5회 카운트를 먹는다 — 넘겼으면 그 사람들의 카운트는 **사람이 보정한다**(대시보드에서 그 `failed` 행 정리).

---

## 사용자에게 물을 것 (8번 항목)

**질문은 전부 답을 받았다**(2026-09-25, 위 "확정된 결정" 표 7건). 코드를 시작하기 전에 남은 것은
**승인 두 가지**뿐이고, 둘 다 그 일을 실제로 하기 직전에 받는다.

| # | 승인 | 언제 | 쉬운 말 |
| --- | --- | --- | --- |
| 1 | "클라우드 쓰기 목록" 6건 | Part B 를 배포하기 직전 | 구글 클라우드에 "작업 대기줄" 을 하나 만들고, 서버가 그걸 쓸 수 있게 열쇠를 주는 일입니다. 돈은 사실상 0원입니다 |
| 2 | Part C 마이그레이션을 클라우드 DB 에 적용 | ERD 그림 검토 뒤 | 아바타 표에 칸 하나(기본 아바타 표시)와 "한 사람당 만드는 중은 하나만" 규칙을 더합니다 |

**승인란(사용자):**
- [ ] "클라우드 쓰기 목록" 6건을 승인한다(실행 직전)
- [ ] Part C 마이그레이션을 클라우드에 적용하는 것을 승인한다(ERD 그림 검토 뒤)

---

## 구현 편차 기록 (2026-09-26)

계획서와 실제 코드가 다른 곳. **계획서 본문은 그대로 두고 여기에 모은다** — 본문을 고치면
"무엇을 계획했고 왜 달라졌는지" 가 사라진다. 아래는 `feat/avatar-async` 워크트리의 코드에서 직접 확인했다.

### A3 — 폴링을 끊는 자리 (`ref.onDispose` 가 아니라 화면 dispose)

계획서 A3 은 "화면을 떠나면 타이머를 끊는다(`ref.onDispose`)" 라고 적었는데, **실제로 끊는 쪽은 화면이다.**
`_AvatarGenerationScreenState.dispose()` 가 `stopPolling()` 을 부르고(`avatar_generation_screen.dart`),
`ref.onDispose(_stopPolling)` 는 보조로 남는다(`avatar_generation_view_model.dart`).
뷰모델이 **화면보다 오래 살기 때문**이다 — 04-3(등록)과 05-12(결과)가 같은 뷰모델을 쓰므로 화면이 닫혀도
provider 는 안 버려지고, `ref.onDispose` 만 믿으면 다른 화면에서도 5초마다 계속 묻는다.
뷰모델을 잡아 두는 자리도 `initState` 의 `late final` 이다 — `State.dispose()` 안에서 `ref.read` 를 쓰면 던져서
타이머가 아예 안 끊긴다(`chat_room_screen.dart` 와 같은 방식).

### A3 — "다시 만들기" 실패 뒤에 부르는 것 (`refresh()` 가 아니라 `refreshStatus()`)

계획서 A3 은 "다시 만들기가 실패했을 때도 `refresh()` 를 한 번 부른다" 라고 적었는데,
**실제로는 `retry()` 가 `generate()` 뒤에 `refreshStatus()`(아바타 상태 재조회)를 부른다.**
`refresh()`(온보딩 단계 재조회)는 **"다음" 버튼만** 부른다(`goToNextStep`).
최종 리뷰 필수 2("결과를 받자마자 단계를 다시 물으면 라우터가 06-1 로 화면을 바꿔 버려 아바타도 보상 안내도 못 본다")와
충돌하지 않게 하려는 것이다. 계획서가 막으려던 "앱이 응답을 놓쳤을 뿐 서버에는 이미 아바타가 있는데 화면에 갇힘" 은
상태 재조회가 그대로 해결한다 — 서버가 `ready` 를 돌려주면 결과 화면이 뜨고, 넘어가는 시점만 사람이 정한다.
