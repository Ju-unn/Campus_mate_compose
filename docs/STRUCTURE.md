# 저장소 구조와 개발 환경

> 루트 [`README.md`](../README.md) 를 소개 페이지로 바꾸면서(2026-11-10) 그 안에 있던 저장소 구조 · 기술 스택 · 문서 목록 · 개발 절차를 이 문서로 옮겼다. 내용은 그대로다.

대학생 · 졸업생 대상 큐레이션 매칭 앱. 소셜 로그인 뒤 학교 메일로 인증하고(학교 메일이 없는 졸업생은 졸업증명서 사진 + 관리자 검수로 인증), 주기적으로 소수의 큐레이션 카드를 받아 상호 수락으로 매칭된다.

> **지금 상태는 이 문서에 적지 않는다.** 운영 서버 리비전 · 환경변수 · 배치 · 롤백 하한은 [`backend/DEPLOY.md`](../backend/DEPLOY.md) §5, 운영 DB 적용 상태는 [`docs/ERD.md`](ERD.md) 상태줄, 결정의 이유는 [`docs/decisions/`](decisions/), 앱 규칙은 [`frontend/CLAUDE.md`](../frontend/CLAUDE.md), 화면 규칙은 [`frontend/docs/DESIGN.md`](../frontend/docs/DESIGN.md) 에 있다.
> 조각 0 ~ 7(가입 · 온보딩 · 매칭 · 카드 · 채팅 · 안전 · 하트 · 인앱결제)과 관리자 웹이 main 에 들어와 있다. 졸업생 인증은 서버 스위치 `GRADUATE_VERIFICATION_ENABLED` 가 켜져야 앱에 나온다(`docs/decisions/2026-10-19-graduate-verification-decision.md`). Firebase 사용 통계 · 오류 수집 · 성능 측정은 약관 동의 뒤에만 켠다. 앱은 그대로 운영하면서 웹 버전을 추가하는 계획(방식 A, 구현 전)이 있다: `docs/decisions/2026-10-27-web-version-decision.md`.

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `frontend/` | Flutter 앱 (Android + iOS). MVVM + Riverpod |
| `backend/` | FastAPI 비즈니스 로직 서버(Cloud Run, 서울). 배포 절차 · 운영 상태는 `backend/DEPLOY.md` |
| `admin_web/` | 운영자 전용 관리자 웹(Flutter 웹, Vercel). 앱과 따로 빌드하고 서로 import 하지 않는다 |
| `supabase/` | 마이그레이션 · 시드 · pgTAP 시험 |
| `e2e/` | 통합 시험 하네스(파이썬). 로컬 시험에 쓴다. `E2E_ENV` 의 `SUPABASE_URL` 이 운영이 아니면 gcloud(운영 프로젝트)를 부르는 길을 모두 막는다(`e2e/tools.py` `require_cloud`). 04-1 문자 인증을 거치는 기기 E2E 7건은 로컬 서버의 가짜 발송기 로그에서 인증번호를 읽는다(`e2e/phone_sms.py`, 준비물은 `frontend/run.md`). 점수 기준 모델의 흡연 규칙은 옛 규칙 그대로다(e2e 계정은 `accepts_smoker` 가 null 이라 결과는 같다, `frontend/run.md`). |
| `site/` | 소개 페이지(홈페이지 `campus-mates.com`). `site/privacy/` 는 노션 개인정보 처리방침의 **사본**이라, **노션 방침을 고치면 이 사본도 같이 고친다**(`docs/decisions/2026-10-20-launch-day-decisions.md` §3). 바닥글 사업자 정보(`site/index.html`, 2026-10-27 에 채움)는 방침 맨 아래 회사 정보와 같은 값이어야 한다 |
| `docs/` | 앱·서버가 공통으로 참조하는 설계 문서 |

## 기술 스택

| 항목 | 선택 |
| --- | --- |
| 앱 | Flutter (Dart), Riverpod, go_router |
| 백엔드 | FastAPI (비즈니스 로직) + Supabase (Auth·DB·RLS·Storage) |
| DB | PostgreSQL + pgvector |
| 패키지명 | `io.github.juunn.campusmate` |

## 문서

| 문서 | 역할 |
| --- | --- |
| [`docs/GIT.md`](GIT.md) | **Git 규칙** — gitmoji 커밋 형식, 브랜치 전략, PR 규칙. git 작업 전 필독 |
| [`docs/GRAPHIFY.md`](GRAPHIFY.md) | **코드베이스 탐색 규칙** — `/graphify` 지식 그래프 조회·갱신. Grep 전에 그래프 먼저 |
| [`docs/SUPABASE.md`](SUPABASE.md) | **Supabase 작업 규칙** — 키 · 식별자 취급, 마이그레이션 파일, 클라우드 적용 절차, RLS · grant 체크리스트. Supabase 작업 전 필독 |
| [`docs/SETUP.md`](SETUP.md) | 새 PC 준비 — 스킬 · Pencil · 폰트 · SDK · graphify · IDE |
| [`docs/superpowers/specs/`](superpowers/specs/) | 제품·아키텍처·매칭·보안 전체 설계. 모든 결정의 기준 |
| [`docs/superpowers/plans/`](superpowers/plans/) | 조각별 실행 계획 — 목록과 상태는 [`README.md`](superpowers/plans/README.md) |
| [`docs/decisions/`](decisions/) | **기술 결정 기록** — 한 결정에 한 파일(`날짜-주제-decision.md`). 계기 → 대안 → 선택과 이유 → 흐름 → 남은 위험. 졸업생 인증(10-19) · 출시 당일 결정(10-20) · 웹 버전 추가 계획(10-27) · 앱 1.0.2 결정 묶음(11-04) · 11-08 회의 할 일 묶음(11-11) |
| [`backend/DEPLOY.md`](../backend/DEPLOY.md) | **서버 배포 · 운영 상태** — 현재 리비전, 환경변수, 배치, 롤백 하한 |
| [`docs/ERD.md`](ERD.md) | DB ERD — 테이블 · 컬럼 · RLS · 권한 기준 |
| [`docs/ERD_DECISIONS.md`](ERD_DECISIONS.md) | ERD 결정 기록 · 끝난 검토 · 조각 0 적용 범위 |
| [`frontend/CLAUDE.md`](../frontend/CLAUDE.md) | 코딩 규칙 (아키텍처·네이밍·테스트) |
| [`frontend/docs/DESIGN.md`](../frontend/docs/DESIGN.md) | 디자인 시스템 — 색·타이포·컴포넌트 |
| [`frontend/docs/ANALYTICS_EVENTS.md`](../frontend/docs/ANALYTICS_EVENTS.md) | 사용 통계 이벤트 · 앱이 버틴 오류(Crashlytics 비치명) 단일 기준표 — 앱 1.0.1 부터 |

## 개발

Flutter 프로젝트 루트는 저장소 루트가 아니라 **`frontend/`** 다. IDE 에서는 `frontend/` 를 연다.

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
```

실행할 때 Supabase 접속 정보를 주입한다. **키는 저장소에 넣지 않는다.**

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```
