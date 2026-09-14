# 조각 0 — 기반 공사 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CampusMate 앱의 뼈대를 세운다 — Flutter 프로젝트, 공용 기반 코드, Supabase 스키마와 권한, 코딩 규칙 문서까지. 빈 화면이 뜨고 DB가 준비된 상태에서 끝난다.

**Architecture:** 기능별 최상위 패키지 아래 `model / view / viewmodel` 3단으로 나누는 MVVM. 상태 관리는 Riverpod, 라우팅은 go_router. **백엔드는 FastAPI(비즈니스 로직) + Supabase(Auth·DB·RLS·Storage) 로 나눈다(2026-09-12 확정, 설계 문서 §1·§7. 호스팅은 §13 미결37).** 다만 이 조각 0 범위는 여전히 Flutter 프로젝트 뼈대 + Supabase 스키마/RLS뿐이다 — FastAPI 서버 자체는 그 로직이 처음 필요해지는 조각에서 시작한다는 원칙은 그대로이되, ~~(매칭·결제)~~ → **조각 1부터다(2026-09-13 확정, ERD.md §11-8)**: 클라이언트 쓰기가 전부 FastAPI를 거치는 구조(설계 문서 §7.1)라 이메일 인증 직후 `profiles` 생성과 `3b` 학생증 OCR부터 이미 FastAPI가 필요하다. 화면과 무관한 판단 로직(라우팅 리다이렉트, 설정 검증)은 순수 Dart 클래스로 분리해 위젯 없이 테스트한다.

**Tech Stack:** Flutter (Dart), Riverpod, go_router, supabase_flutter, PostgreSQL + pgvector, mocktail

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md`

## Global Constraints

스펙에서 그대로 가져온 프로젝트 전역 요구사항. 모든 태스크에 암묵적으로 적용된다.

- **패키지명**: `io.github.juunn.campusmate` — 스토어 등록 후 변경 불가
- **플랫폼**: Android + iOS 동시 (iOS 빌드는 클라우드 CI, 로컬 Mac 없음)
- **코드·네이밍은 영어, 주석·문서는 한국어**
- **`else` 금지** — early return 또는 `switch` 표현식으로 푼다
- **메서드 본문 10줄 이하**, 들여쓰기 1단계
- **Model 계층 클래스의 인스턴스 변수는 2개 이하** (UiState는 예외)
- **getter 노출 금지** — 필드는 `_private`, 행위 메서드만 공개 (UiState는 예외)
- **원시값 포장** — 의미 있는 클래스로 감싼다
- **축약 금지** — 완전한 단어. `id`, `url`, `ui` 등 통용 약어만 예외
- **모든 비공개가 아닌 클래스는 테스트를 갖는다**
- 색상·간격은 `core/theme/` 토큰을 통해서만 참조. 위젯 안에 색상 리터럴 금지
- 새 의존성 추가는 사전에 사용자 확인
- **Git**: `docs/GIT.md` 를 따른다 — gitmoji 커밋, 작업 브랜치 → 푸시 → draft PR, merge 는 사용자

---

## File Structure

이 조각에서 만드는 파일과 각자의 책임이다.

| 파일                                          | 책임                                                       |
| --------------------------------------------- | ---------------------------------------------------------- |
| `lib/main.dart`                               | 앱 진입점. Supabase 초기화 후 루트 위젯 실행               |
| `lib/common/result.dart`                      | 성공/실패를 한 타입으로 표현. 값을 꺼내지 않고 접어서 처리 |
| `lib/common/failure.dart`                     | 도메인 실패 종류와 사용자 표시 메시지                      |
| `lib/core/theme/app_colors.dart`              | 색상 토큰 (시안 확정 전 임시값)                            |
| `lib/core/theme/app_spacing.dart`             | 간격·반경 토큰                                             |
| `lib/core/theme/app_theme.dart`               | 토큰을 조립한`ThemeData`                                   |
| `lib/core/supabase/supabase_config.dart`      | 빌드 시 주입된 접속 정보 보관·검증                         |
| `lib/core/supabase/supabase_initializer.dart` | 실제 Supabase 초기화 (부수효과 격리)                       |
| `lib/core/router/app_routes.dart`             | 경로 문자열 상수                                           |
| `lib/core/router/auth_redirect.dart`          | 로그인 여부에 따른 이동 판단 (순수 로직)                   |
| `lib/core/router/app_router.dart`             | go_router 구성                                             |
| `lib/core/router/placeholder_screens.dart`    | 스플래시·로그인·홈 자리 화면                               |
| `supabase/migrations/*.sql`¹                  | 테이블·RLS·Storage 버킷                                    |
| `supabase/seed.sql`¹                          | 서울권 대학 도메인 시드                                    |
| `supabase/tests/*.sql`¹                       | RLS가 남의 행을 막는지 검증(pgTAP)                         |
| `CLAUDE.md`                                   | 이 프로젝트의 코딩 규칙 (Dart 기준)                        |

¹ **`supabase/` 는 저장소 루트 기준이다** — 위의 `lib/`·`test/`·`CLAUDE.md` 와 달리 `frontend/` 안이 아니다(2026-09-13 사용자 결정). Task 7·8은 이 경로로 작업한다.

**분리 원칙**: `supabase_config.dart` 는 값 검증만 하고 `supabase_initializer.dart` 가 실제 초기화를 맡는다. 이렇게 나눠야 설정 검증을 네트워크 없이 테스트할 수 있다. 같은 이유로 `auth_redirect.dart` 를 `app_router.dart` 에서 떼어냈다.

---

## Task 1: 개발 환경 준비 — 완료

> **요약(2026-09-14 문서 정리).** 설치 · 점검 단계는 끝나서 지웠다(원문은 git 이력). 새 PC 준비는 `frontend/CLAUDE.md` §12 를 본다.

| 도구 | 상태 |
| --- | --- |
| Flutter SDK | 3.47.3 stable (`C:\dev\flutter`). `flutter doctor` Android toolchain ✓ (SDK 36.1.0, 라이선스 동의, 2026-09-14) |
| Android Studio · Java · Git · Node.js | 설치됨 |
| Supabase | 클라우드 프로젝트 `campus_mate`(조직 CampusMate, Seoul). URL · 키는 문서에 적지 않고 MCP `get_project_url` · `get_publishable_keys` 로 조회한다 |
| Supabase CLI | 2.117.0 (`C:\dev\supabase-cli`, PATH 등록) |
| pgvector | 대시보드에서 켜지 않았다. 조각 0 첫 마이그레이션(`20260913054542`)에서 `extensions` 스키마에 켰다(2026-09-14 적용) |
| GitHub CLI · graphify | 설치됨 (`docs/GRAPHIFY.md`) |
| Docker | 없음 — 로컬 Supabase 스택 대신 클라우드 프로젝트를 쓴다. pgTAP 은 아직 실행하지 않았다 |

---

## Task 2: Flutter 프로젝트 생성과 패키지 골격 — 완료

> **진행 상황 (2026-09-12).** **Task 2 완료** (Step 1~9). UI 작업이 없어 디자인 확정 전에 먼저 끝냈다.
>
> 계획과 달라진 점:
> - 저장소 구조가 **단일 저장소 안의 `frontend/` + `backend/` + `docs/`** 로 바뀌었다. 아래 명령의 작업 디렉터리는 모두 `frontend/` 다
> - Dart 패키지명은 `campusmate` 가 아니라 **`campus_mate`** 다 (저장소명·Dart 관례에 맞춤). 이 문서의 `package:campus_mate/...` import 가 실제와 맞는 표기다
> - `flutter create` 가 `--org` 없이 실행돼 `com.example.*` 로 만들어져 있었고, 2026-09-12 에 `io.github.juunn.campusmate` 로 고쳤다
>
> **요약(2026-09-14 문서 정리).** 결과: 기능별 패키지 골격(`lib/<기능>/model · view · viewmodel`), 의존성 6개, `.gitignore` 비밀 파일 · 실존 인물 사진 제외, iOS 사진 · 카메라 권한 문구. 단계별 명령은 끝나서 지웠다(원문은 git 이력).

---

## Task 3: 공용 기반 — Result 와 Failure — 완료

> **요약(2026-09-14 문서 정리).** `frontend/lib/common/result.dart` · `failure.dart` 와 테스트(`frontend/test/common/`)로 구현했다(6 tests PASS, `No issues found!`). 단계별 TDD 코드는 저장소 코드와 같아 지웠다(원문은 git 이력).

---

## Task 4: 디자인 토큰과 테마

> **색 · 간격 · 라운드 값은 아래 임시값이 아니라 `frontend/docs/DESIGN.md` §12 확정값을 쓴다**(디자인 확정, 2026-09-14 사용자 확인). 이 Task 의 테스트도 그 값에 맞춘다.

**Files:**

- Create: `lib/core/theme/app_colors.dart`, `lib/core/theme/app_spacing.dart`, `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart`

**Interfaces:**

- Consumes: 없음
- Produces:
  - `abstract final class AppColors` — `primary`, `onPrimary`, `background`, `surface`, `onSurface`, `outline`, `error` (모두 `static const Color`)
  - `abstract final class AppSpacing` — `extraSmall`(4), `small`(8), `medium`(16), `large`(24), `extraLarge`(32), `cornerRadius`(12) (모두 `static const double`)
  - `abstract final class AppTheme` — `static ThemeData light()`

**설계 의도**: 시안이 아직 없다. 값은 조각 8에서 교체하되, **지금부터 위젯이 토큰만 참조하게** 만들어 나중에 값만 바꾸면 되도록 한다.

- [ ] **Step 1: 실패 테스트 작성**

`test/core/theme/app_theme_test.dart`:

```dart
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('라이트 테마의 주색은 토큰의 primary 를 그대로 쓴다', () {
    final theme = AppTheme.light();

    expect(theme.colorScheme.primary, AppColors.primary);
  });

  test('라이트 테마의 배경색은 토큰의 background 를 그대로 쓴다', () {
    final theme = AppTheme.light();

    expect(theme.scaffoldBackgroundColor, AppColors.background);
  });

  test('간격 토큰은 4의 배수로 증가한다', () {
    expect(AppSpacing.extraSmall, 4);
    expect(AppSpacing.small, 8);
    expect(AppSpacing.medium, 16);
    expect(AppSpacing.large, 24);
    expect(AppSpacing.extraLarge, 32);
  });

  test('라이트 테마는 Material 3 를 사용한다', () {
    final theme = AppTheme.light();

    expect(theme.useMaterial3, isTrue);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
flutter test test/core/theme/app_theme_test.dart
```

기대 결과: FAIL — 세 파일 모두 없다

- [ ] **Step 3: 색상 토큰 구현**

`lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// 색상 토큰.
/// 위젯 안에서 Color 리터럴을 직접 쓰지 않고 반드시 여기를 거친다.
///
/// 현재 값은 디자인 시안 확정 전의 임시 팔레트다.
/// 조각 8에서 시안이 나오면 이 파일의 값만 교체한다.
abstract final class AppColors {
  /// 주색 — 버튼, 강조 요소
  static const Color primary = Color(0xFFE85D75);

  /// 주색 위에 올라가는 글자색
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// 화면 바탕
  static const Color background = Color(0xFFFDFBFB);

  /// 카드·시트 등 바탕 위에 올라가는 면
  static const Color surface = Color(0xFFFFFFFF);

  /// 면 위에 올라가는 기본 글자색
  static const Color onSurface = Color(0xFF1C1B1F);

  /// 테두리·구분선
  static const Color outline = Color(0xFFD9D5D8);

  /// 오류 상태
  static const Color error = Color(0xFFB3261E);
}
```

- [ ] **Step 4: 간격 토큰 구현**

`lib/core/theme/app_spacing.dart`:

```dart
/// 간격과 모서리 반경 토큰.
/// 반복되는 수치를 위젯에 직접 적지 않고 여기서만 관리한다.
abstract final class AppSpacing {
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double extraLarge = 32;

  /// 카드·버튼의 기본 모서리 반경.
  /// 화면 비율과 무관하게 고정하는 것이 맞는 값이다.
  static const double cornerRadius = 12;
}
```

- [ ] **Step 5: 테마 조립 구현**

`lib/core/theme/app_theme.dart`:

```dart
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 토큰을 조립해 앱 전역 테마를 만든다.
abstract final class AppTheme {
  /// 라이트 테마. 현재 앱은 라이트만 지원한다.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _lightColorScheme(),
      scaffoldBackgroundColor: AppColors.background,
    );
  }

  static ColorScheme _lightColorScheme() {
    return const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      outline: AppColors.outline,
      error: AppColors.error,
    );
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
flutter test test/core/theme/
flutter analyze
```

기대 결과: 4 tests PASS, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/core/theme test/core/theme
git commit -m "feat(core): 디자인 토큰과 라이트 테마 추가

- 색상/간격 토큰을 분리해 위젯이 리터럴을 쓰지 않도록 함
- 값은 시안 확정 전 임시이며 조각 8에서 교체 예정"
```

---

## Task 5: Supabase 설정과 초기화 — 완료

> **요약(2026-09-14 문서 정리).** `frontend/lib/core/supabase/supabase_config.dart` · `supabase_initializer.dart` 와 테스트(5 tests PASS)로 구현했고, 실행 방법은 `frontend/run.md` 에 있다. 키는 코드에 넣지 않고 `--dart-define` 으로 주입한다. supabase_flutter 2.17.2 에서 `anonKey` 매개변수가 deprecated 라 `connect()` 안 호출만 `publishableKey:` 로 바꿨다(같은 키 자리). 단계별 코드는 저장소 코드와 같아 지웠다(원문은 git 이력).

---

## Task 6: 라우팅 골격과 인증 리다이렉트

**Files:**

- Create: `lib/core/router/app_routes.dart`, `lib/core/router/auth_redirect.dart`, `lib/core/router/placeholder_screens.dart`, `lib/core/router/app_router.dart`
- Modify: `lib/main.dart` (전체 교체)
- Test: `test/core/router/auth_redirect_test.dart`, `test/core/router/app_router_test.dart`

**Interfaces:**

- Consumes: `AppTheme.light()` (Task 4), `SupabaseConfig` / `SupabaseInitializer` (Task 5)
- Produces:
  - `abstract final class AppRoutes` — `static const String splash = '/'`, `login = '/login'`, `home = '/home'`
  - `class AuthRedirect` — `const AuthRedirect(bool isAuthenticated)`, `String? resolve(String location)`
  - `abstract final class AppRouter` — `static GoRouter create({required bool isAuthenticated})`
  - `class SplashScreen`, `class LoginScreen`, `class HomeScreen` (모두 `StatelessWidget`, `const` 생성자)

**설계 의도**: 이동 판단을 `AuthRedirect` 라는 순수 클래스로 떼어냈다. go_router 안에 조건문을 박아두면 위젯 없이는 검증할 수 없다. 인스턴스 변수는 1개, `else` 없이 early return으로 분기한다.

- [ ] **Step 1: AuthRedirect 실패 테스트 작성**

`test/core/router/auth_redirect_test.dart`:

```dart
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('로그인하지 않은 사용자', () {
    const redirect = AuthRedirect(false);

    test('로그인 화면에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.login), isNull);
    });

    test('홈으로 가려 하면 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.home), AppRoutes.login);
    });

    test('스플래시에서도 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.login);
    });
  });

  group('로그인한 사용자', () {
    const redirect = AuthRedirect(true);

    test('로그인 화면으로 가려 하면 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.login), AppRoutes.home);
    });

    test('스플래시에서는 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.home);
    });

    test('홈에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.home), isNull);
    });
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
flutter test test/core/router/auth_redirect_test.dart
```

기대 결과: FAIL — `app_routes.dart`, `auth_redirect.dart` 없음

- [ ] **Step 3: 경로 상수와 리다이렉트 구현**

`lib/core/router/app_routes.dart`:

```dart
/// 앱의 화면 경로.
/// 문자열을 화면마다 적지 않고 여기서만 관리한다.
abstract final class AppRoutes {
  /// 앱 진입 직후의 대기 화면
  static const String splash = '/';

  /// 로그인·가입 화면
  static const String login = '/login';

  /// 로그인 후 첫 화면
  static const String home = '/home';
}
```

`lib/core/router/auth_redirect.dart`:

```dart
import 'package:campus_mate/core/router/app_routes.dart';

/// 로그인 여부에 따라 이동해야 할 경로를 판단한다.
///
/// 라우터에서 떼어낸 이유는 이 판단이 화면과 무관한 규칙이고,
/// 위젯을 띄우지 않고 테스트해야 하기 때문이다.
class AuthRedirect {
  const AuthRedirect(this._isAuthenticated);

  final bool _isAuthenticated;

  /// 이동이 필요 없으면 null 을 돌려준다 (go_router 의 규약).
  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  /// 로그인한 사용자는 로그인·스플래시에 머무를 이유가 없다.
  String? _resolveForMember(String location) {
    if (location == AppRoutes.login || location == AppRoutes.splash) {
      return AppRoutes.home;
    }
    return null;
  }

  /// 로그인하지 않은 사용자는 로그인 화면 외에는 갈 수 없다.
  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login) {
      return null;
    }
    return AppRoutes.login;
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
flutter test test/core/router/auth_redirect_test.dart
```

기대 결과: PASS (6 tests)

- [ ] **Step 5: 자리 화면 위젯 테스트 작성**

`test/core/router/app_router_test.dart`:

```dart
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
    final router = AppRouter.create(isAuthenticated: false);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
    );
    await tester.pumpAndSettle();

    expect(find.text('로그인'), findsOneWidget);
  });

  testWidgets('로그인하면 홈 화면이 보인다', (tester) async {
    final router = AppRouter.create(isAuthenticated: true);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 카드'), findsOneWidget);
  });
}
```

- [ ] **Step 6: 테스트가 실패하는지 확인**

```bash
flutter test test/core/router/app_router_test.dart
```

기대 결과: FAIL — `app_router.dart` 없음

- [ ] **Step 7: 자리 화면 구현**

`lib/core/router/placeholder_screens.dart`:

```dart
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 앱 진입 직후 잠시 보이는 화면.
/// 실제 세션 확인 로직은 조각 1에서 채운다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// 로그인 화면 자리. 실제 인증은 조각 1에서 구현한다.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Text('로그인', style: Theme.of(context).textTheme.headlineMedium),
        ),
      ),
    );
  }
}

/// 홈 화면 자리. 오늘의 카드는 조각 4에서 구현한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Text(
            '오늘의 카드',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: 라우터 구성 구현**

`lib/core/router/app_router.dart`:

```dart
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 AuthRedirect 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({required bool isAuthenticated}) {
    final redirect = AuthRedirect(isAuthenticated);
    return GoRouter(
      initialLocation: AppRoutes.splash,
      redirect: (context, state) => redirect.resolve(state.matchedLocation),
      routes: _routes(),
    );
  }

  static List<RouteBase> _routes() {
    return <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ];
  }
}
```

- [ ] **Step 9: 테스트 통과 확인**

```bash
flutter test test/core/router/
```

기대 결과: PASS (8 tests)

- [ ] **Step 10: main.dart 교체**

`lib/main.dart` 전체를 아래로 바꾼다. flutter create가 만든 기본 카운터 앱을 지운다.

```dart
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseInitializer.run(SupabaseConfig.fromEnvironment());
  runApp(const ProviderScope(child: CampusMateApp()));
}

/// 앱 루트 위젯.
/// 로그인 상태 연동은 조각 1에서 채운다. 지금은 항상 비로그인으로 시작한다.
class CampusMateApp extends StatelessWidget {
  const CampusMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CampusMate',
      theme: AppTheme.light(),
      routerConfig: AppRouter.create(isAuthenticated: false),
    );
  }
}
```

- [ ] **Step 11: 기본 위젯 테스트 교체**

flutter create가 만든 `test/widget_test.dart` 는 카운터 앱을 검사하므로 이제 실패한다. 아래로 교체한다.

```dart
import 'package:campus_mate/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱을 실행하면 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CampusMateApp()));
    await tester.pumpAndSettle();

    expect(find.text('로그인'), findsOneWidget);
  });
}
```

- [ ] **Step 12: 전체 테스트와 분석 통과 확인**

```bash
flutter test
flutter analyze
```

기대 결과: 모든 테스트 PASS, `No issues found!`

- [ ] **Step 13: 커밋**

```bash
git add lib test
git commit -m "feat(core): 라우팅 골격과 인증 리다이렉트 추가

- 이동 판단을 AuthRedirect 로 분리해 위젯 없이 테스트
- 스플래시/로그인/홈 자리 화면 구성
- main.dart 를 Supabase 초기화 + 라우터 구조로 교체"
```

---

## Task 7: Supabase 스키마와 RLS 정책 — 완료 (2026-09-14 클라우드 적용)

> **요약(2026-09-14 문서 정리).** 실제 산출물은 `supabase/migrations/` 의 조각 0 파일 4개(`20260913054542` universities · `054544` profiles · `054547` profile_photos · `054549` 비공개 Storage 버킷)이고 기준은 `docs/ERD.md` §2 · §3 · §9 다. 조각 0 시점의 초안 SQL 과 `supabase init` · `link` · `db push` 단계는 ERD v3 와 달라 지웠다(원문은 git 이력, 초안과 달라진 점은 `20260913054544` 머리 주석).
>
> **실제 적용 기록(2026-09-14).** `supabase login` · `link` · `db push` 없이 MCP 플러그인 `apply_migration` 으로 `supabase/migrations/` 4개를 순서대로 적용했다. 원격 버전은 적용 시각으로 찍혀 `20260914045614` · `20260914045656` · `20260914045723` · `20260914045746` 이다(로컬 파일명과 다름, ERD §12-33). 시드 `supabase/seed.sql` 은 `execute_sql` 로 넣었다. 읽기 검증: public 테이블 4개(`universities` · `university_email_domains` · `profiles` · `profile_photos`) 모두 RLS on, 정책 4개, `profile-photos` 버킷 private, `universities` 20행.

---

## Task 8: 서울권 대학 시드와 RLS 검증 — 완료 (pgTAP 미실행)

> **요약(2026-09-14 문서 정리).** 실제 산출물은 `supabase/seed.sql`(서울권 대학 20개 · 메일 도메인 20개)과 `supabase/tests/rls_slice0_test.sql`(pgTAP 21항목)이다. 초안 seed · DO 블록 · 대시보드 SQL Editor 실행 단계는 지웠다(원문은 git 이력).
>
> **실제 적용 기록(2026-09-14).** 위 기록 뒤 사용자 승인(2026-09-14) 후 조각 0 이 클라우드에 적용됐다. `supabase login` · `link` · `db push` 없이 마이그레이션 4개는 MCP 플러그인 `apply_migration`, `supabase/seed.sql` 은 `execute_sql` 로 넣었다(원격 버전 · 읽기 검증 결과는 Task 7 실제 적용 기록). pgTAP 은 여전히 실행하지 않았다(Docker 없음, ERD §12-35).

---

## Task 9: 프로젝트 코딩 규칙 문서 — 완료

> **요약(2026-09-14 문서 정리).** 결과물은 `frontend/CLAUDE.md` 이고 그 문서가 기준이다. 초안(Kotlin 규칙 계승 · git flow · `develop` 브랜치 생성 단계)은 실제 규칙(`frontend/CLAUDE.md`, `docs/GIT.md`)과 달라 지웠다(원문은 git 이력).

---

## 완료 판정 기준

조각 0이 끝났다고 말하려면 아래가 모두 참이어야 한다.

- [ ] `flutter analyze` 가 `No issues found!` 를 출력한다
- [ ] `flutter test` 전체가 통과한다 (Task 3·4·5·6의 테스트 포함)
- [ ] 앱이 Android에서 실행되고 로그인 자리 화면까지 도달한다
- [x] 조각 0 마이그레이션 4개가 클라우드에 적용됐다 (MCP `apply_migration`, 2026-09-14, ERD §12-33)
- [ ] `supabase/tests/rls_slice0_test.sql`(pgTAP 21항목)이 통과한다 (Docker 설치 후 실행, 로컬 빈 DB 에 마이그레이션 처음부터 적용 포함, ERD §12-34 guard · §12-35)
- [x] `universities` 에 서울권 20개 대학이 들어 있다 (2026-09-14 적용)
- [x] `frontend/CLAUDE.md` 가 있다

**실행 확인 명령** (Task 1의 값으로 치환):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

---

## 이 조각에서 하지 않는 것

다음 조각에서 다룬다. 여기서 미리 만들지 않는다.

- 실제 로그인·인증 로직, Auth Hook 도메인 검증 → 조각 1 (DB 마이그레이션 초안만 2026-09-14 작성, 미적용)
- 프로필 입력 화면, 설문, 태그, 사진 업로드 → 조각 2
- 벡터 테이블, 임베딩 생성(FastAPI 엔드포인트, 2026-09-12: Edge Function에서 이전) → 조각 3
- 일일 카드 배치, 수락/거절, 푸시 알림 → 조각 4
- 채팅 → 조각 5
- 신고·차단·계정 삭제 → 조각 6
- 인앱결제(하트 구매) → 조각 7 (등록비 게이트는 2026-09-08 폐지)
- 실제 디자인 시안 반영 → 조각 8
