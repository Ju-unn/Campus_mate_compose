# CampusMate

대학생 대상 큐레이션 매칭 앱. 학교 이메일로 학생 인증을 하고, 주기적으로 소수의 큐레이션 카드를 받아
상호 수락으로 매칭된다.

> **현재 상태(2026-10-30): 스토어 심사 중(두 스토어의 최근 결과는 이 문서 담당이 확인하지 못했다).** 조각 0 ~ 7(가입 · 온보딩 · 매칭 · 카드 · 채팅 · 안전 · 하트 · 인앱결제)과 관리자 웹이 main 에 들어와 있고, 운영 서버(Cloud Run 리비전 `00097-h87`)와 Supabase(마이그레이션 101개)가 돈다. 10-20 에 애플 TestFlight 빌드 25 + 앱 내 구입 5개, 구글 프로덕션 AAB vc18 을 제출했다(국가 대한민국만, 수동 출시). 카드 오픈은 서울 학교 64곳 **2026-11-02(월) 오전 7시**였으나 **10-28 에 운영 DB 에서 날짜를 풀어(null) 지금은 열려 있다 — 스토어 심사 통과 뒤 날짜를 정해 다시 막아야 한다**(`backend/DEPLOY.md` §4-17). 졸업생 인증(졸업증명서 + 관리자 검수)은 운영 서버 스위치가 켜져 있다(`backend/DEPLOY.md` §4-14). Firebase 사용 통계 · 오류 수집 · 성능 측정은 약관 동의 뒤에만 켠다. 10-27 에 관리자 웹 매칭 현황에 "대화 신청" 목록이 더해졌고(`backend/DEPLOY.md` §4-16), 10-28 에 매칭 점수 개편(무료 카드 상위 20~90%)이, 10-29 에 학번 숫자 규칙 · 가입 직후 첫 카드 · 무료 카드 하루 한 장이 서버에 들어갔다(앱 변경 없음, §4-17). 10-30 에는 **매칭 글 부딪힘 개선안("술 좋아함" ↔ "술 안 마심" 구별)이 운영에 반영됐다**(서버 PR #638 · `00096-pv6` · 마이그레이션 `20261030010000_taste_clash`, 기존 사용자 27명 채움, 앱 변경 없음 — 글 속 취향이 부딪히면 총점 × 0.6, 설계 §6.7 · §13 미결46, `backend/DEPLOY.md` §4-18). 같은 날 이어서 **새벽 4시 정리 배치에 ⑥ 단계**(나누기가 실패해 취향 단어 칸이 빈 사람을 매일 다시 채움)가 더해졌다(서버 PR #640 · `00097-h87`, DB 변경 없음 · 앱 변경 없음, 첫 실행은 10-31 04:00 이라 결과는 아직 모른다, `backend/DEPLOY.md` §4-19). 후보가 1명뿐이면 무료 카드가 0장인 한계는 사용자 결정 대기다. **구글 심사 대응으로 운영 DB 에 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 들어 있다 — 출시 전에 반드시 제거한다**(§4-16). 앱은 그대로 운영하면서 **웹 버전을 추가하는 계획**(방식 A, 아직 구현 전)이 있다: `docs/decisions/2026-10-27-web-version-decision.md`. 이 줄은 문서 정리 라운드마다 고친다(옛 문장: 10-30 앞 판 "스토어 심사 중 · 리비전 00096-pv6 · 마이그레이션 101개 · 매칭 글 부딪힘 개선안 운영 반영", 10-29 "스토어 심사 중 · 리비전 00095-7sz · 마이그레이션 100개 · 매칭 글 부딪힘 개선안은 시험 DB 검증만 끝나 운영 미반영(출시 후)", 10-27 "스토어 심사 중 · 리비전 00092-2zr · 마이그레이션 97개", 10-20 "스토어 심사 중 · 리비전 00091-rnc · 마이그레이션 96개", 10-19 "출시 준비 중 · 스토어 출시 10월 28일쯤", 그 전 "조각 0(기반 공사) 진행 중").

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `frontend/` | Flutter 앱 (Android + iOS). MVVM + Riverpod |
| `backend/` | FastAPI 비즈니스 로직 서버(Cloud Run, 서울). 배포 절차 · 운영 상태는 `backend/DEPLOY.md` |
| `admin_web/` | 운영자 전용 관리자 웹(Flutter 웹, Vercel). 앱과 따로 빌드하고 서로 import 하지 않는다 |
| `supabase/` | 마이그레이션 · 시드 · pgTAP 시험 |
| `e2e/` | 출시 전 통합 시험 하네스(파이썬) |
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
| [`docs/GIT.md`](docs/GIT.md) | **Git 규칙** — gitmoji 커밋 형식, 브랜치 전략, PR 규칙. git 작업 전 필독 |
| [`docs/GRAPHIFY.md`](docs/GRAPHIFY.md) | **코드베이스 탐색 규칙** — `/graphify` 지식 그래프 조회·갱신. Grep 전에 그래프 먼저 |
| [`docs/SUPABASE.md`](docs/SUPABASE.md) | **Supabase 작업 규칙** — 키 · 식별자 취급, 마이그레이션 파일, 클라우드 적용 절차, RLS · grant 체크리스트. Supabase 작업 전 필독 |
| [`docs/SETUP.md`](docs/SETUP.md) | 새 PC 준비 — 스킬 · Pencil · 폰트 · SDK · graphify · IDE |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | 제품·아키텍처·매칭·보안 전체 설계. 모든 결정의 기준 |
| [`docs/superpowers/plans/`](docs/superpowers/plans/) | 조각별 실행 계획 — 목록과 상태는 [`README.md`](docs/superpowers/plans/README.md) |
| [`docs/decisions/`](docs/decisions/) | **기술 결정 기록** — 한 결정에 한 파일(`날짜-주제-decision.md`). 계기 → 대안 → 선택과 이유 → 흐름 → 남은 위험. 졸업생 인증(10-19) · 출시 당일 결정(10-20) · 웹 버전 추가 계획(10-27) |
| [`backend/DEPLOY.md`](backend/DEPLOY.md) | **서버 배포 · 운영 상태** — 현재 리비전, 환경변수, 배치, 롤백 하한 |
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
