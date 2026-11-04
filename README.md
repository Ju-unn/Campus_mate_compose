# CampusMate

대학생 대상 큐레이션 매칭 앱. 학교 이메일로 학생 인증을 하고, 주기적으로 소수의 큐레이션 카드를 받아
상호 수락으로 매칭된다.

> **2026-11-04 개정(문서 정리): 운영 서버는 리비전 `00101-bc9`(2026-11-04, 직전 `00100-jh4`)이고 Supabase 마이그레이션은 102개다**(종전 아래 "`00100-jh4`" · "101개" 는 11-03 값). 앱 1.0.2 가 main 에 쌓이고 있다 — 투어 4단계 문구 · 로그아웃 푸시 토큰 · **흡연 "상관없어요" 칸**(DB `profiles.accepts_smoker` + 서버 점수 규칙 + 06-1 화면) · 첫 방문 0장 문구 · 06-1 정리 · **Lottie 4곳**(새 의존성 `lottie`) · **글자 크기 토큰**(짝수 기준) · iOS dSYM — 전부 앱 빌드 · 제출 전이고(**2026-11-04 밤 개정: 빌드했다 — TestFlight 27(애플 제출은 광고 식별자 부품을 뺀 28) · AAB vc20, 구글은 1.0.0 반려 뒤 1.0.2 로 다시 제출 · 애플은 1.0 승인 · 출시 대기 후 1.0.2 업데이트 제출 · 1.0.1 은 제출하지 않았다, 안드로이드 전용 숨은 심사원 로그인 PR #662 포함**; `frontend/CLAUDE.md` §2 "앱 1.0.2", `frontend/docs/DESIGN.md` §13-157, 결정 `docs/decisions/2026-11-04-v102-decisions.md`) 패키지 구조 정리 · 문구 ARB 가 이어진다. 배포 창고 정리 규칙(업로드 버킷 30일 · 이미지 창고 최근 15개)으로 되돌림 하한이 `00086` 이 됐다(`backend/DEPLOY.md` §4-24). 아래는 2026-11-03 판 서술이다. **현재 상태(2026-11-03): 앱 1.0.0 은 아직 공개 전이다 — 두 스토어 심사 · 공개 대기 중이다(구글 프로덕션 AAB vc18 · 애플 TestFlight 빌드 25, 2026-11-03 사용자 확인; 11-02 는 출시 계획일이었다). 2026-11-03 정정: 같은 날 앞 판(PR #644)의 "1.0.0 은 2026-11-02 에 출시됐다" 는 잘못 전달된 값이었다. 앱 1.0.1 은 PR #642 가 merge 됐고(`61f8c1a5`) 서버도 배포했으며 빌드(구글 AAB vc19 · 애플 TestFlight 26)는 만들어 두었지만 둘 다 제출 전이다 — 1.0.0 공개 뒤 사용자가 제출한다.** 조각 0 ~ 7(가입 · 온보딩 · 매칭 · 카드 · 채팅 · 안전 · 하트 · 인앱결제)과 관리자 웹이 main 에 들어와 있고, 운영 서버(Cloud Run 리비전 `00100-jh4`, 2026-11-03 배포, 직전 `00099-7gp` · `00098-67v` — 2026-11-03 후속 문서 정리 개정, 종전 "리비전 `00098-67v`, 직전 `00097-h87`")와 Supabase(마이그레이션 101개)가 돈다. **앱 1.0.1(PR #642, 커밋 19개, DB 변경 없음)**: 학번 칸 숫자 키패드 · 반각 숫자 1~3자리 / 키 칸 오류 문구 "120~230 사이로 입력해 주세요" + 맨 앞 0 막기 / 선호 MBTI 안내를 칩 아래로 / 오늘 탭 띠 "다음에 만날 사람들"(오늘 · 내일 도착일 때만) / 유료 카드 머리글에서 "N명이" 빼기 / **강제 업데이트**(서버 `GET /app/version` + env `MIN_APP_VERSION`, 앱 `lib/core/app_update/`, 새 의존성 `package_info_plus`) / **사용 통계 이벤트 15종 + 앱이 버틴 API 오류의 비치명 Crashlytics 기록**(표 `frontend/docs/ANALYTICS_EVENTS.md`) / 안드로이드 릴리스 빌드는 카카오 키가 비면 실패 · iOS TestFlight 워크플로 `build_name` 입력 · lint 규칙 5개 · e2e 하네스 로컬 안전장치(`E2E_ENV`). 순서는 사용자 승인 → merge(11-03, 문서 PR #644 는 `a793d122`) → 서버 배포(11-03, `MIN_APP_VERSION` 은 비운 채 — 지금도 없다) → AAB vc19(`--build-number=19 --build-name=1.0.1`) · TestFlight 26(`build_name` 1.0.1)을 만든 데까지 끝났고, 제출은 1.0.0 공개 뒤다. **`MIN_APP_VERSION` 은 두 스토어에 1.0.1 이 모두 공개된 뒤에만 올린다**(`backend/DEPLOY.md` §2 · §4-20). 그다음 1.0.2 에서 문구(ARB) · 색 / 크기 토큰 · 공통 컴포넌트 · 패키지 구조 · lint 2단계 · SonarQube 를 정리할 계획이다(사용자 결정 11-02, `frontend/CLAUDE.md` §2). 카드 오픈은 서울 학교 64곳 2026-11-02(월) 오전 7시였으나 **10-28 에 운영 DB 에서 날짜를 풀어(null) 지금은 열려 있다 — 스토어 심사 통과 뒤 날짜를 정해 다시 막아야 한다. 1.0.0 이 아직 공개 전이라 지금도 열려 있는 것으로 읽는다**(2026-11-03 정정: 앞 판은 "출시가 지났는데 했다는 전달을 받지 못했다" 로 적었다, `backend/DEPLOY.md` §4-17). 졸업생 인증(졸업증명서 + 관리자 검수)은 운영 서버 스위치가 켜져 있다(`backend/DEPLOY.md` §4-14). Firebase 사용 통계 · 오류 수집 · 성능 측정은 약관 동의 뒤에만 켠다. 10-27 ~ 10-30 의 서버 변경(관리자 웹 "대화 신청" 목록 · 매칭 점수 개편 · 학번 숫자 규칙 · 가입 직후 첫 카드 · 무료 카드 하루 한 장 · 글 속 취향 부딪힘 × 0.6 · 새벽 4시 정리 배치 ⑥ 취향 단어 다시 채우기, 앱 변경 없음)은 `backend/DEPLOY.md` §4-16 ~ §4-19 와 `docs/superpowers/plans/README.md` 에 있다. 후보가 1명뿐이면 무료 카드가 0장이던 한계는 2026-11-03 사용자가 "후보가 1명이면 유료를 건너뛰고 무료로 준다" 로 정했고(종전 "사용자 결정 대기") 서버 PR #646 이 merge(`c7d086af`) 되어 `00099-7gp` 로 운영에 반영됐다(같은 날 앞 판은 "서버 구현은 검토 PASS 이고 서버 PR merge · 배포 전이라 운영에는 아직 없다" 였다; 설계 §13 미결45, `backend/DEPLOY.md` §4-21). 같은 날 서버 PR #647 도 `00100-jh4` 로 나갔다 — 푸시 고치기 4건(푸시 서버 연결 · 인증 오류가 채팅 · 신청 · 수락을 500 으로 만들지 않음 · 아침 묶음이 겹쳐도 한 번만 · 신뢰 확인 리마인드가 21시대 · 07시대에도 아침 8시로 · 죽은 토큰 정리 로그)과 서버 배포 업로드 제외 목록 `backend/.gcloudignore`(업로드 649 → 169 파일, `backend/DEPLOY.md` §2 · §4-22). 앱 변경 · DB 변경은 없다. 흡연 칸 "상관없음" 은 같은 날 사용자 결정으로 앱 1.0.2 에 넣는다(pen 시안부터, 설계 §13 미결46 ②; → 2026-11-04 구현됨, 위 개정 문장). **구글 심사 대응으로 운영 DB 에 넣은 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)는 1.0.0 공개 전 · 심사 통과 뒤에 제거한다**(2026-11-03 정정: 앞 판은 출시(11-02)가 지난 것으로 읽어 "제거 여부를 사용자에게 확인한다" 로 적었으나 1.0.0 은 아직 공개 전이다, `backend/DEPLOY.md` §4-16). 앱은 그대로 운영하면서 **웹 버전을 추가하는 계획**(방식 A, 아직 구현 전)이 있다: `docs/decisions/2026-10-27-web-version-decision.md`. 이 줄은 문서 정리 라운드마다 고친다(옛 문장: 11-03 오전 판 "리비전 00098-67v · 직전 00097-h87 · 후보 1명 무료는 서버 PR merge · 배포 전", 11-03 PR #644 판 "앱 1.0.0 은 2026-11-02 에 출시됐고 … 앱 1.0.1 은 draft PR #642 로 merge 를 기다린다 · 리비전 00097-h87" — 출시는 잘못 전달된 값이라 같은 날 정정, 그 앞 판 = 10-30 판 "스토어 심사 중 · 리비전 00097-h87 · 마이그레이션 101개 · 새벽 4시 정리 배치 ⑥ 취향 단어 다시 채우기", 10-30 첫 판 "스토어 심사 중 · 리비전 00096-pv6 · 마이그레이션 101개 · 매칭 글 부딪힘 개선안 운영 반영", 10-29 "스토어 심사 중 · 리비전 00095-7sz · 마이그레이션 100개 · 매칭 글 부딪힘 개선안은 시험 DB 검증만 끝나 운영 미반영(출시 후)", 10-27 "스토어 심사 중 · 리비전 00092-2zr · 마이그레이션 97개", 10-20 "스토어 심사 중 · 리비전 00091-rnc · 마이그레이션 96개", 10-19 "출시 준비 중 · 스토어 출시 10월 28일쯤", 그 전 "조각 0(기반 공사) 진행 중").

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `frontend/` | Flutter 앱 (Android + iOS). MVVM + Riverpod |
| `backend/` | FastAPI 비즈니스 로직 서버(Cloud Run, 서울). 배포 절차 · 운영 상태는 `backend/DEPLOY.md` |
| `admin_web/` | 운영자 전용 관리자 웹(Flutter 웹, Vercel). 앱과 따로 빌드하고 서로 import 하지 않는다 |
| `supabase/` | 마이그레이션 · 시드 · pgTAP 시험 |
| `e2e/` | 통합 시험 하네스(파이썬). 출시 전에 만들었고 앱 1.0.1 로컬 시험에도 썼다(2026-11-03 개정, 종전 "출시 전 통합 시험 하네스"). `E2E_ENV` 의 `SUPABASE_URL` 이 운영이 아니면 gcloud(운영 프로젝트)를 부르는 길을 모두 막는다(`e2e/tools.py` `require_cloud`, PR #642). 점수 기준 모델의 흡연 규칙은 옛 규칙 그대로다(2026-11-04, `frontend/run.md`) |
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
| [`docs/decisions/`](docs/decisions/) | **기술 결정 기록** — 한 결정에 한 파일(`날짜-주제-decision.md`). 계기 → 대안 → 선택과 이유 → 흐름 → 남은 위험. 졸업생 인증(10-19) · 출시 당일 결정(10-20) · 웹 버전 추가 계획(10-27) · 앱 1.0.2 결정 묶음(11-04) |
| [`backend/DEPLOY.md`](backend/DEPLOY.md) | **서버 배포 · 운영 상태** — 현재 리비전, 환경변수, 배치, 롤백 하한 |
| [`docs/ERD.md`](docs/ERD.md) | DB ERD — 테이블 · 컬럼 · RLS · 권한 기준 |
| [`docs/ERD_DECISIONS.md`](docs/ERD_DECISIONS.md) | ERD 결정 기록 · 끝난 검토 · 조각 0 적용 범위 |
| [`frontend/CLAUDE.md`](frontend/CLAUDE.md) | 코딩 규칙 (아키텍처·네이밍·테스트) |
| [`frontend/docs/DESIGN.md`](frontend/docs/DESIGN.md) | 디자인 시스템 — 색·타이포·컴포넌트 |
| [`frontend/docs/ANALYTICS_EVENTS.md`](frontend/docs/ANALYTICS_EVENTS.md) | 사용 통계 이벤트 · 앱이 버틴 오류(Crashlytics 비치명) 단일 기준표 — 앱 1.0.1 부터 |

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
