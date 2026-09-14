# CLAUDE.md — CampusMate

이 문서는 **CampusMate** 프로젝트에서 코드를 작성하거나 수정할 때 반드시 따라야 하는 규칙을 정의한다.

- **언어**: Dart
- **프로젝트 형태**: Flutter 앱 (Android + iOS), MVVM + Riverpod
- **백엔드**: FastAPI (비즈니스 로직) + Supabase (Auth·DB·RLS·Storage)
- **코드/네이밍**: 영어 / **주석·설명·문서**: 한국어

> ⚠️ **이 저장소는 공개(public)다.** `github.com/Ju-unn/Campus_mate_compose` 단일 저장소이고,
> 이 문서가 있는 `frontend/` 가 Flutter 프로젝트 루트다 (`backend/` 는 FastAPI 자리, `docs/` 는 공통 문서, `supabase/` 는 마이그레이션·시드·pgTAP 자리 — 셋 다 저장소 루트에 있고 `frontend/` 안이 아니다).
> 키·`.env`·실존 인물 사진을 커밋하지 않는다. 자세한 규칙은 `../docs/GIT.md`.
>
> ℹ️ 디자인 원본(`datingApp.pen`, 시안 미리보기, 경쟁사 리서치)은 이 저장소에 없다. OneDrive `datingApp`
> 저장소(Pencil 편집용)에 있고, 이 문서와 `docs/DESIGN.md` 는 거기서 결론만 옮겨온 것이다.

---

## 1. 필수 사항 (최우선 규칙)

1. **UI 작업 전에 `docs/DESIGN.md` 를 먼저 읽을 것.** 추측으로 화면을 만들지 않는다. 시안 원본(Pencil `.pen`)과 화면 미리보기 PNG는 이 저장소에 없고 OneDrive `datingApp` 저장소에 있다 — 필요하면 그쪽에서 확인한다. 화면 구현에 바로 쓸 PNG 자산은 `assets/images/`에 있다.
2. **색·타이포·간격·라운드·모션은 DESIGN.md 의 토큰만 사용할 것.** 위젯 안에 `Color(0xFF...)` 리터럴을 직접 쓰지 않는다. `lib/core/theme/` 의 상수를 통해서만 참조한다.
3. **dp 값은 화면 비율에 대응시킬 것.** 고정이 맞는 값(아이콘 크기, 코너 반경, 테두리 두께)만 그대로 쓴다.
4. **애매한 부분은 임의로 결정하지 말고 사용자에게 먼저 질문할 것.**
5. **하나의 작업이 끝나면 거기서 멈추고 사용자의 검토를 받을 것.**
6. **MVVM 에 맞게, 기능(조각)별로 패키지를 나눌 것.** 각 기능 아래 `model` / `view` / `viewmodel` 을 둔다.
7. **모든 비(non-)private 클래스는 테스트를 가질 것.** 테스트 없는 클래스가 포함된 채로 커밋 메시지를 제안하지 않는다.
8. **새 의존성 추가는 사전에 사용자에게 확인할 것.**
9. **git 작업(브랜치·커밋·푸시·PR) 전에 `../docs/GIT.md` 를 먼저 읽을 것.** 커밋 메시지는 gitmoji + Conventional Commits 형식, `main` 직접 푸시 금지, 커밋→푸시→draft PR 까지만 하고 merge 는 사용자가 한다.
10. **코드베이스를 탐색하기 전에 지식 그래프를 먼저 조회할 것** (`../docs/GRAPHIFY.md`). "X 는 어디서 쓰이나", "흐름 추적" 같은 질문은 `python -m graphify query` 가 먼저다. Grep·Read 로 뒤지는 건 그래프가 답을 못 줄 때만. **문서를 고친 작업 끝에는 `/graphify . --update` 를 실행**한다 (코드는 커밋 hook 이 자동 갱신).
11. **Supabase 작업(스키마·RLS·Storage·Auth) 전에 §10.1 을 먼저 읽을 것.** 스키마 변경은 반드시 저장소 루트 `supabase/migrations/*.sql` 파일로 남기고, 프로젝트 URL·키·ref 는 문서와 코드에 쓰지 않는다.

---

## 2. 프로젝트 개요

| 항목 | 결정 |
| --- | --- |
| 앱 이름 | CampusMate |
| 패키지명 | `io.github.juunn.campusmate` |
| 플랫폼 | Android + iOS |
| 프레임워크 | Flutter (Dart) |
| 상태 관리 | Riverpod (`Notifier`) |
| 라우팅 | `go_router` |
| 백엔드 | **FastAPI**(비즈니스 로직) + **Supabase**(Auth·DB·RLS·Storage) — 2026-09-12 확정, 설계 문서 §1·§7 |
| 벡터 검색 | PostgreSQL + pgvector |
| 임베딩 | OpenAI `text-embedding-3-small` (512차원) |
| 인증 | 대학 이메일 6자리 인증코드 (비밀번호 없음) + **학생증 또는 졸업증명서 사진 검증** |
| 가입 자격 | **연 나이 기준 만 19세 이상**(만 19세가 되는 해 1월 1일부터, 청소년보호법 방식, Asia/Seoul 기준 — 2026-09-13 확정, ERD.md §11-1), 재학생·졸업생 모두 가능. 앱 등급 19+ (설계 문서 §13 미결1) |
| 핵심 형태 | **가변 주기 큐레이션 카드(초기 주 2회 → 확대) + 상호 수락 + 매칭 후 신뢰 확인 게이트** |
| 핵심 차별점 | **지인 리뷰** — 추천 코드로 연결된 지인이 남긴 평가를 카드에 노출 (설계 문서 §2.8) |
| 출시 방식 | **학교별 코호트 순차 오픈** — 14일 모집 후 예고한 날짜에 카드 지급 시작 (설계 문서 §2.9) |
| 수익 모델 | 가입비 없음(남녀 동일 무료). **하트 1개 = 60원**(2026-09-14 가격 개편, 종전 40원 폐기 — 설계 문서 §13-114), 추가 카드 50하트(**구매 시점은 자유, 지급 주기당 1장**), 아바타 재생성 10하트 (설계 문서 §2.4) |
| 채팅 상한 | **없음** — 매칭 후 24h/48h 신뢰 확인 게이트가 방치된 대화를 정리 (설계 문서 §2.5). **채팅은 텍스트만, 이미지 전송 불가** |

**현재 상태: 조각 0(기반 공사) 진행 중 — 계획서 Task 2·3·5 완료.** `flutter create`, 기능별 패키지 골격, 패키지 ID(`io.github.juunn.campusmate`), 의존성 6개, iOS 사진·카메라 권한 문구, 공용 Result·Failure 타입(Task 3), `--dart-define` 으로 주입하는 Supabase 설정·초기화(Task 5)까지 끝났다.
**디자인이 아직 확정되지 않아 UI 작업은 보류한다.** 그래서 Task 4(디자인 토큰·테마)와 Task 6(라우팅 골격 — `AppTheme.light()` 에 의존)은 뒤로 미룬다.
다음 순서: **Task 7(스키마·RLS) → Task 8(시드·RLS 검증)**. 실제 진행 상황은 `../docs/superpowers/plans/2026-09-05-foundation-setup.md` 의 체크박스를 기준으로 삼는다.

### 2.1 문서 지도

| 파일 | 역할 |
| --- | --- |
| `../docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` | 제품·아키텍처·매칭·보안 전체 설계. **모든 결정의 기준**. FastAPI 백엔드도 참조하므로 이 저장소(frontend) 밖, workspace 루트에 둔다 |
| `../docs/superpowers/plans/2026-09-05-foundation-setup.md` | 조각 0 실행 계획 (작업 단위) |
| `../docs/GIT.md` | **Git 규칙 — gitmoji 커밋 형식, 브랜치 전략, 푸시 규칙.** git 작업 전 필독 |
| `../docs/GRAPHIFY.md` | **코드베이스 탐색 규칙 — 지식 그래프 조회·갱신.** Grep 전에 그래프 먼저 |
| `docs/DESIGN.md` | 디자인 시스템 전문. 색·타이포·컴포넌트·미결 항목 |
| `assets/images/` | DESIGN.md 기준 확정 채택된 UI용 PNG 자산 |
| *(별도 저장소)* `datingApp.pen` · `preview/*.png` | Pencil 시안 원본과 화면 미리보기. OneDrive `datingApp` 저장소에 있음 (이 저장소에는 없음) |

---

## 3. 아키텍처

### 3.1 계층

| 계층 | 위치 | 역할 |
| --- | --- | --- |
| **View** | `<기능>/view/` | 화면과 위젯. 표시와 이벤트 전달만 담당 |
| **ViewModel** | `<기능>/viewmodel/` | 흐름 제어. UiState 생성, View 이벤트 처리 |
| **Model** | `<기능>/model/` | 비즈니스 로직, 엔티티, Repository |

- **의존성 방향은 항상 안쪽(Model)을 향한다.** Model 은 View 를 모른다.
- **ViewModel 은 Flutter 위젯 타입을 참조하지 않는다** (`BuildContext`, `Widget` import 금지). Riverpod `Notifier` 는 순수 Dart 클래스로 쓴다.
- 핵심 로직은 위젯 없이 테스트 가능해야 한다.

### 3.2 패키지 구조

```
lib/
├── auth/                  조각 1 — 학생인증
│   ├── model/             UniversityEmail, VerificationCode, AuthRepository
│   ├── view/              SignUpScreen, VerifyCodeScreen
│   └── viewmodel/         SignUpViewModel, SignUpUiState
├── profile/               조각 2
├── matching/              조각 3·4 — 벡터, 일일 카드, 수락
├── chat/                  조각 5
├── safety/                조각 6 — 신고·차단
├── billing/               조각 7 — 결제
├── common/                값 객체, 확장, 에러 타입, Result
└── core/
    ├── supabase/          클라이언트 초기화, 테이블 상수
    ├── router/            go_router 라우팅
    ├── push/               FCM 초기화·토큰 관리
    └── theme/             디자인 토큰 (DESIGN.md §12 매핑)
```

새 화면을 추가할 때 이 3단 구조를 그대로 따른다. 벗어난 코드가 있으면 리팩터링해서 맞춘다.

### 3.3 데이터 흐름

```
View --이벤트--> ViewModel --호출--> Model(Repository)
View <--UiState-- ViewModel
```

- 상태는 `UiState` 클래스 **하나로 모아** 노출한다 (필드별 상태 남발 금지)
- 일회성 이벤트(스낵바, 화면 이동)는 상태가 아니라 별도 이벤트로 처리한다
- 위젯은 상태를 직접 만들지 않고 받는다 (stateless 우선, hoisting)

### 3.4 UseCase 사용 기준

**항상 만들지 않는다.** 아래일 때만 도입한다.

- 로직이 ViewModel 에 두기엔 복잡하거나 여러 화면에서 재사용될 때
- 여러 도메인 객체를 조합해야 할 때

단순한 흐름이면 ViewModel 이 Repository 를 직접 호출한다.

---

## 4. 객체지향 생활 체조 (Dart 이식)

> **적용 범위**: `model/`(Domain) 계층에는 **전부 엄격 적용**한다.
> `UiState` 클래스와 위젯 파라미터는 **원칙 7(변수 2개 이하)·9(프로퍼티 노출 금지)의 예외**다. 나머지는 모든 계층에 적용한다.

| 원칙 | Dart 에서의 형태 |
| --- | --- |
| 1. 한 메서드에 한 단계 들여쓰기 | early return, 컬렉션 함수, `switch` 표현식으로 중첩 제거 |
| 2. `else` 금지 | early return / guard clause / `switch` 표현식 |
| 3. 원시값 포장 | `extension type` 또는 불변 클래스 (`UniversityEmail`, `Nickname`, `Age`) |
| 4. 한 줄에 점 하나 | 컬렉션 체이닝과 **위젯 빌더 체이닝은 예외** |
| 5. 축약 금지 | 완전한 단어 (`id`, `url`, `ui`, `dp` 등 통용 약어는 예외) |
| 6. 엔티티를 작게 | **메서드 10줄 이하**, 한 가지 일만. 위젯도 길어지면 하위 위젯으로 분리 |
| 7. 인스턴스 변수 2개 이하 | Model 계층에 엄격 적용. `UiState` 는 예외 |
| 8. 일급 컬렉션 | 컬렉션 하나만 필드로 갖는 클래스 (`InterestTags`, `SurveyAnswers`) |
| 9. getter/프로퍼티 노출 금지 | 필드는 `_private`, **행위 메서드**만 공개. Tell, Don't Ask. `UiState` 는 예외 |

```dart
// 나쁜 예 — 값을 꺼내 외부에서 판단
if (tags.values.length > maxCount) { ... }

// 좋은 예 — 객체에게 묻는다
if (tags.exceeds(maxCount)) { ... }
```

---

## 5. 명시적 표현 (애매함 금지)

- 동작이 한눈에 명확하지 않거나 의도·예외 처리가 헷갈릴 수 있는 부분은 **한국어 주석 또는 명시적 코드**로 의도를 드러낸다
- 매직 넘버, 암시적 null 처리, 분기의 의미는 이름이나 주석으로 분명히 한다
- 문자열과 색상은 **상수/토큰을 통해서만** 참조한다

```dart
// 나쁜 예 — 0이 무슨 의미인지 불명확
if (status == 0) { ... }

// 좋은 예
const int statusPending = 0;
if (status == statusPending) { ... }   // 대기 상태일 때만 처리
```

---

## 6. 객체지향 5원칙 (SOLID)

- **SRP** 하나의 클래스는 하나의 변화 축만 담당한다
- **OCP** 확장에는 열려 있고 변경에는 닫혀 있다
- **LSP** 서브 타입은 기반 타입과 언제나 교체 가능하다
- **ISP** 쓰지 않는 인터페이스를 구현하지 않는다
- **DIP** 상위 모듈이 하위 모듈의 구현이 아니라 추상에 의존한다

---

## 7. UI 작업 규칙

- **DESIGN.md 먼저.** 해당 화면의 컴포넌트 스펙(§8)과 화면 목록(§9)을 읽고 시작한다. 시안에 없는 화면·상태를 만들어야 하면 **먼저 질문한다**
- **토큰만 사용한다.** `lib/core/theme/` 에 아래 파일을 두고, 위젯은 여기서만 값을 가져온다 (DESIGN.md §12)

  | 파일 | 클래스 | 근거 |
  | --- | --- | --- |
  | `app_colors.dart` | `AppColors` | DESIGN.md §2 |
  | `app_type.dart` | `AppType` | §3 |
  | `app_space.dart` | `AppSpace` | §4.1 |
  | `app_radius.dart` | `AppRadius` | §5.1 |
  | `app_icons.dart` | `AppIcons` | §5.3 Lucide 이름 매핑 |
  | `app_motion.dart` | `AppMotion` | §7 |

- **아이콘은 Lucide (`lucide_icons`)** 로 통일한다. 위젯에서 `LucideIcons.*` 를 직접 부르지 않고 `AppIcons` 상수를 거친다 (DESIGN.md §5.3)
  - **예외: 하트 재화 글리프.** 잔액·번들·리워드·CTA·아바타 코스트·설정 보유하트 등 "재화" 의미의 하트는 Lucide 가 아니라 이미지 자산 `assets/images/heart-flat-vector-v3.png` 를 쓴다 (2026-09-10, DESIGN.md §5.4·§8.10). 바텀 내비 오늘 탭·호감 하트·매칭 기록 등 비(非)재화 하트는 계속 Lucide `heart`. 재화 글리프는 다크 배경에서도 읽히는 렌더 + `@2x`/`@3x` 자산 + `Semantics(label: '하트')` 를 갖춘다
- **버튼 라벨은 18/700.** `{colors.primary}` (#FF385C) 위 흰 글씨는 대비 3.52:1 이라 **큰 글씨 예외에 의존한다.** 이보다 작게 쓰면 접근성 기준에 미달한다 (DESIGN.md §2.1)
- **`{colors.primary}` 는 채움 전용.** 흰 배경 위 텍스트에는 `{colors.primary-text}` (#C4224B) 를 쓴다
- **사용자는 전 화면에서 닉네임으로만 표시한다. 실명(`real_name`)은 서버 응답에 담지 않는다** (2026-09-10 개정, DESIGN.md §8.7 · 설계 문서 §7.3, ERD.md §11-2 — "설계 문서 §7 예외 2"는 설계 문서에 없는 참조였다). 실명은 `3b`에서 입력받아 `profile_private.real_name`(민감 컬럼)에만 저장하고, 학생증 대조와 본인 조회(16e) 전용이다. 예전 `김○○` 마스킹 방식은 폐기
- **`MediaQuery.disableAnimations` 를 존중한다.** 켜져 있으면 모든 모션 시간을 0으로 만들고 최종 상태를 즉시 그린다
- 문자열은 하드코딩하지 않는다

---

## 8. 테스트

**모든 비(non-)private 클래스는 테스트를 갖는다.**

| 대상 | 위치 | 방식 |
| --- | --- | --- |
| 값 객체 · Model | `test/` | `package:test` 단위 테스트 |
| Repository | `test/` | 인터페이스 뒤 **Fake 구현**으로 검증 |
| ViewModel | `test/` | Riverpod 컨테이너 + Fake repository |
| 화면 · 위젯 | `test/` | `testWidgets` 위젯 테스트 |
| **RLS 정책** | `../supabase/tests/` | **다른 사용자로 조회 시 0행인지 SQL 로 검증** |

마지막 항목을 별도로 두는 이유: **RLS 는 틀려도 앱이 정상 동작한다.** 테스트가 없으면 유출을 출시 후에야 알게 된다.

- 이름 규칙: `SignUpViewModel` → `sign_up_view_model_test.dart`
- 경로는 프로덕션 코드를 그대로 미러링한다 (`test/auth/viewmodel/`)
- private 클래스·함수는 직접 테스트하지 않고 public 진입점을 통해 커버한다
- 목(mock)은 `mocktail` 을 쓰되, Repository 는 **Fake 구현을 우선**한다

---

## 9. Git 전략

**규칙 전문은 `../docs/GIT.md` 에 있다. git 작업을 시작하기 전에 그 문서를 읽는다.**
(브랜치 전략, gitmoji 커밋 형식, 타입↔이모지 매핑, 푸시 전 확인 절차)

여기에는 자주 어기는 것만 옮겨 적는다.

- 커밋 메시지는 **`<이모지> <타입>(<scope>): <한국어 요약>`** — 예: `✨ feat(auth): 인증 코드 입력 화면 구현`
- 이모지는 **유니코드로 직접** 넣고, **한 커밋에 하나**만 쓴다
- 브랜치는 **`main` + `feature/*`** 만 쓴다. `main` 최신 상태에서 분기하고, **`main` 직접 커밋·푸시 금지**
  (`develop`·`release/*`·`hotfix/*` 는 첫 배포 이후 도입)
- **Claude 는 커밋 → 푸시 → draft PR 생성까지 하고 멈춘다.** 최종 merge 는 사용자가 한다
- **merge 가 끝나면 해당 브랜치를 로컬·원격 양쪽에서 바로 지운다** (묻지 않고 자동)
- **`git pull` 은 사용자가 요청할 때만 한다.** 로컬 `main` 이 뒤처졌으면 몇 커밋 차이인지만 알린다
- 테스트가 없는 클래스가 포함된 상태로는 커밋하지 않는다
- **공개 저장소다.** 푸시 전 `git status` 로 키·`.env`·실존 인물 사진이 섞이지 않았는지 확인한다

---

## 10. 빌드 / 실행 명령

Windows PowerShell 기준, 프로젝트 루트에서:

```powershell
flutter pub get
flutter run                      # 디버그 실행
flutter test                     # 전체 테스트
flutter analyze                  # 정적 분석
flutter build apk --debug
```

Supabase 마이그레이션(**저장소 루트**에서 실행 — `supabase/` 가 `frontend/` 밖에 있다):

```powershell
supabase db reset                # 빈 DB 에 마이그레이션 처음부터 적용
supabase test db                 # RLS 정책 SQL 테스트
```

### 10.1 Supabase 작업 규칙

Supabase **MCP 플러그인(`supabase`)이 설치·인증돼 있다.** 클라우드 프로젝트는 `campus_mate`(조직 CampusMate, Seoul) 하나뿐이다. 조각 0(테이블 4·RLS·정책 4·private 버킷 `profile-photos`·seed `universities` 20행·`university_email_domains` 20행)은 2026-09-14 사용자 승인 후 적용됐다. 조각 1 은 마이그레이션 초안만 있고 미적용, 조각 2 이후는 파일도 없다(현재 상태는 `docs/ERD.md` 상태줄 기준). 로컬 스택(Docker)은 없으므로 적용 대상은 항상 이 클라우드 프로젝트다.

**시작할 때**

- 스키마·RLS·Storage·Auth 를 건드리기 전에 `supabase:supabase` 스킬(보안 체크리스트)과 `supabase:supabase-postgres-best-practices` 스킬을 로드한다
- 현재 상태는 추측하지 않고 MCP `list_tables` · `list_extensions` · `list_migrations` 로 확인한다

**키·식별자 취급**

- 프로젝트 URL · project ref · anon/publishable 키 · `service_role` 키 · DB 비밀번호는 **문서·코드·커밋·PR 에 쓰지 않는다.** 필요할 때 MCP `get_project_url` · `get_publishable_keys` 로 조회하고, 앱에는 `--dart-define` 으로 주입한다 (§11)
- `service_role` 키는 FastAPI 서버 전용이다. Flutter 쪽 코드·설정에는 절대 두지 않는다

**스키마 변경 = 마이그레이션 파일**

- **`supabase/` 는 저장소 루트에 있다(`../supabase/`), `frontend/` 안이 아니다**(2026-09-13 사용자 결정). 모든 스키마 변경은 `../supabase/migrations/<timestamp>_<name>.sql` 로 저장소에 남긴다 (설계 문서 §5.4). 대시보드·`execute_sql` 로 DDL 을 손으로 실행하지 않는다
- 파일 이름은 `supabase migration new <name>` 으로 만든다(저장소 루트에서 실행). 직접 지어내지 않는다
- 클라우드 적용은 MCP `apply_migration` 에 **그 파일 내용을 그대로** 넘긴다(2026-09-14 사용자 결정, ERD §12-33). `apply_migration` 은 원격 버전을 적용 시각으로 찍어 파일명과 다르므로 `supabase db push`·`migration list` 는 `migration repair` 없이는 쓸 수 없고, repair 도 클라우드 쓰기라 사용자 승인이 필요하다. 클라우드 쓰기는 매번 사용자가 직접 승인한 뒤에만 한다.
- 적용 직후 MCP `get_advisors`(security · performance)를 돌려 경고를 0 으로 만든다
- 프로덕션 DB 에서 `execute_sql` 은 **읽기 전용 조회**에만 쓴다

**RLS 체크리스트 (정책 SQL 을 쓸 때마다)** — 테이블별 실제 접근 표는 `docs/ERD.md` §2 가 기준이다

- `public` 스키마의 모든 테이블은 RLS 를 켠다
- 정책은 `to authenticated` + `using ((select auth.uid()) = user_id)` 꼴. `auth.uid()` 는 항상 `(select …)` 로 감싼다
- `auth.role()` 은 쓰지 않는다(deprecated). `to authenticated` 만으로는 인가가 아니다 — **소유자 조건을 반드시 붙인다.** 예외는 공개 참조 테이블 4개뿐이다: `universities`·`university_email_domains`·`region_group_settings`·`faq`. 이 중 `anon` 까지 여는 건 앞의 2개(`universities`·`university_email_domains`)뿐이고, 나머지 둘은 `authenticated` 전체까지만 연다(ERD.md §2)
- UPDATE 정책은 `using` + `with check` 둘 다 쓴다. UPDATE 는 SELECT 정책이 있어야 동작한다
- `user_metadata` 로 권한을 판단하지 않는다(사용자가 수정 가능). 권한 데이터는 `app_metadata`
- `security definer` 함수는 쓰지 않는다(권한 오류 우회용 금지). 뷰는 `with (security_invoker = true)`
- **클라이언트 쓰기 정책은 두지 않는다.** 쓰기는 전부 FastAPI가 `service_role`로 한다(2026-09-13 확정, ERD.md §11-8). `anon`·`authenticated`에는 INSERT·UPDATE·DELETE 권한 자체를 주지 않는다(42501로 끝난다)
- **grant는 RLS와 같은 마이그레이션에 둔다.** 새 테이블에 `anon`·`authenticated` 권한이 자동으로 붙는지는 프로젝트 설정마다 달라 믿지 않는다 — 테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤에 ERD.md §2 표대로 `anon`·`authenticated`에는 필요한 `select`만 주고, `service_role`에는 `select`·`insert`·`update`·`delete`를 모두 준다. `service_role`까지 revoke하는 이유는 자동 grant 여부(프로젝트 설정·적용 시점)와 상관없이 결과를 같게 만들기 위해서다
- ~~Storage upsert 는 INSERT + SELECT + UPDATE 정책 3개가 다 있어야 한다~~ → **클라이언트 Storage 정책은 두지 않는다.** 업로드·조회는 FastAPI가 발급하는 서명 업로드 URL·서명 URL로만 한다(2026-09-13 확정, ERD.md §9·§11-8)
- RLS 테스트는 pgTAP (`../supabase/tests/*.sql`) — 다른 사용자로 조회 시 0행뿐 아니라, `anon`·`authenticated`·`service_role`·`PUBLIC`의 테이블·컬럼 권한(ACL), Storage 버킷·정책, 탈퇴 cascade까지 표대로 맞는지 검사한다. 기대값 기준은 ERD.md §2 (§8)

**pgvector**

- 아직 꺼져 있다. 대시보드에서 손으로 켜지 않고, Task 7 첫 마이그레이션 맨 앞에서 켠다: `create extension if not exists vector with schema extensions;`

---

## 11. 저장소와 자산 주의사항

- **⚠️ 이 저장소는 공개(public)다.** `assets/images/` 의 `human1.PNG` · `human2.PNG` 와 그 파생본(`card-*` · `avatar-*` · `rail-*`)은 **실존 인물 사진**이라 **`.gitignore` 로 제외되어 있다. 이 제외 규칙을 절대 풀지 않는다.** 로컬에만 두고, 커밋·푸시하지 않는다. 한 번 올라가면 히스토리·캐시·크롤러에 남아 되돌릴 수 없다
- **mock 이미지가 필요하면 `animal-face-*`(8종) 와 `mascot-*`(5종) 일러스트를 쓴다.** 실존 인물이 아니고 DESIGN.md 화면 구성이 이미 이쪽으로 대체됐다. 인물 사진은 참조하지 않는다
- **`datingApp.pen` 은 이 저장소에 없다.** OneDrive `datingApp` 저장소에 있고, 암호화된 바이너리라 git 이 diff·merge 를 하지 못하므로 그쪽에서도 두 대에서 동시에 편집하지 않는다
- **Supabase 키·OpenAI 키를 저장소에 넣지 않는다.** `--dart-define` 또는 `.env`(gitignore 대상)로 주입한다

---

## 12. 다른 PC 에서 이어받을 때

저장소에 들어오지 않는 것들이 있다. 새 환경에서 아래를 갖춰야 한다.

1. **Claude Code 대화 기록은 저장소에 없다.** 새 세션은 맥락 0 에서 시작한다. `docs/DESIGN.md` §13 미결 항목과 `../docs/superpowers/specs` (저장소 루트)를 먼저 읽으면 현재 상태를 복원할 수 있다
2. **스킬 재설치**
   ```
   claude plugin marketplace add leonxlnx/taste-skill
   claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
   claude plugin marketplace add pbakaus/impeccable
   claude plugin install taste-skill --scope user
   claude plugin install ui-ux-pro-max --scope user
   claude plugin install impeccable --scope user
   ```
3. **Pencil 앱 설치** — `.pen` 편집용. OneDrive `datingApp` 저장소에서 시안 작업을 할 때만 필요하고, 이 저장소에서 코드만 작업할 때는 필요 없다
4. **Pretendard 폰트 설치** — 없으면 시안 렌더링이 대체 폰트로 틀어진다
5. Flutter SDK, Supabase CLI, GitHub CLI(`gh` — draft PR 생성용)
5-1. **graphify** — `pip install graphifyy` → `python -m graphify install --platform claude` → 저장소 루트에서 `/graphify .` 로 그래프 빌드 → `python -m graphify hook install`. 자세한 건 `../docs/GRAPHIFY.md` §6. `graphify-out/` 은 저장소에 없으니 반드시 로컬에서 빌드한다
6. **IDE 는 저장소 루트가 아니라 `frontend/` 를 연다.** Flutter 프로젝트 루트가 `frontend/` 이기 때문이다
7. **실존 인물 목업 이미지는 저장소에 없다**(§11, `.gitignore` 제외). 필요하면 OneDrive `datingApp` 저장소에서 로컬로만 가져온다

---

## 13. 작업 진행 방식

- **한 번에 하나의 작업만 끝내고 멈춘다.** 여러 화면을 한꺼번에 만들지 않는다
- 작업 완료 시: 변경된 파일 목록 + 무엇을 왜 그렇게 했는지 + 확인이 필요한 지점을 요약해 보고한다
- 다음 중 하나라도 해당하면 진행 전에 사용자에게 질문한다
  - DESIGN.md 에 없는 화면/상태를 만들어야 할 때
  - DESIGN.md 와 설계 문서가 서로 모순될 때
  - 새 의존성을 추가해야 할 때
  - 기존 패키지 구조를 바꾸는 리팩터링이 필요할 때
  - DESIGN.md §13 의 미결 항목에 걸리는 결정을 해야 할 때

---

## 14. 요약 체크리스트

**아키텍처**

- [ ] View ↔ ViewModel ↔ Model 구조를 지켰는가?
- [ ] 기능별 패키지 아래 `model` / `view` / `viewmodel` 로 분리했는가?
- [ ] ViewModel 이 `BuildContext` / `Widget` 을 참조하지 않는가?
- [ ] UseCase 는 정말 필요할 때만 도입했는가?

**객체지향 생활 체조** (Model 은 엄격, UiState 는 원칙 7·9 예외)

- [ ] 메서드 들여쓰기가 한 단계인가? `else` 없이 early return 으로 풀었는가?
- [ ] 원시값을 의미 있는 타입으로 포장했는가?
- [ ] 메서드가 10줄 이하이고 한 가지 일만 하는가?
- [ ] 컬렉션을 일급 컬렉션으로 감쌌는가?
- [ ] Model 에서 프로퍼티 노출 없이 객체에게 일을 시켰는가?
- [ ] SOLID 를 위반하지 않았는가?

**UI**

- [ ] DESIGN.md 의 해당 컴포넌트 스펙을 읽고 시작했는가?
- [ ] 색·타이포·간격·라운드를 `core/theme/` 토큰으로만 참조했는가?
- [ ] 아이콘을 `AppIcons` 를 통해 Lucide 로 썼는가?
- [ ] `primary` 위 텍스트가 18/700 이상인가?
- [ ] 사용자를 닉네임으로 표시하고, 실명이 서버 응답에 들어가지 않는가?
- [ ] 축소 모션 설정을 존중하는가?

**기타**

- [ ] 코드·네이밍은 영어, 주석·문서는 한국어인가?
- [ ] 애매한 부분을 주석/이름으로 명시했는가?
- [ ] 핵심 로직과 UI 로직이 분리되어 있는가?
- [ ] 모든 비-private 클래스에 테스트가 있는가?
- [ ] 새 의존성을 사용자에게 확인받았는가?
- [ ] 키·비밀값이 저장소에 들어가지 않았는가?
