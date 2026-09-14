# CampusMate

대학생 대상 큐레이션 매칭 앱. 학교 이메일로 학생 인증을 하고, 주기적으로 소수의 큐레이션 카드를 받아
상호 수락으로 매칭된다.

> **현재 상태: 조각 0(기반 공사) 진행 중.** Flutter 프로젝트 골격과 설계 문서만 있고 기능 구현은 시작 전이다.

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `frontend/` | Flutter 앱 (Android + iOS). MVVM + Riverpod |
| `backend/` | FastAPI 비즈니스 로직 서버 — 조각 4에서 시작 (현재 자리만) |
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
| [`docs/GIT.md`](docs/GIT.md) | **Git 규칙** — gitmoji 커밋 형식, 브랜치 전략, PR 규칙. git 작업 전 필독 |
| [`docs/GRAPHIFY.md`](docs/GRAPHIFY.md) | **코드베이스 탐색 규칙** — `/graphify` 지식 그래프 조회·갱신. Grep 전에 그래프 먼저 |
| [`docs/SUPABASE.md`](docs/SUPABASE.md) | **Supabase 작업 규칙** — 키 · 식별자 취급, 마이그레이션 파일, 클라우드 적용 절차, RLS · grant 체크리스트. Supabase 작업 전 필독 |
| [`docs/SETUP.md`](docs/SETUP.md) | 새 PC 준비 — 스킬 · Pencil · 폰트 · SDK · graphify · IDE |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | 제품·아키텍처·매칭·보안 전체 설계. 모든 결정의 기준 |
| [`docs/superpowers/plans/`](docs/superpowers/plans/) | 조각별 실행 계획 |
| [`docs/ERD.md`](docs/ERD.md) | DB ERD — 테이블 · 컬럼 · RLS · 권한 기준 |
| [`docs/ERD_DECISIONS.md`](docs/ERD_DECISIONS.md) | ERD 결정 기록 · 끝난 검토 · 조각 0 적용 범위 |
| [`frontend/CLAUDE.md`](frontend/CLAUDE.md) | 코딩 규칙 (아키텍처·네이밍·테스트) |
| [`frontend/docs/DESIGN.md`](frontend/docs/DESIGN.md) | 디자인 시스템 — 색·타이포·컴포넌트 |

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
