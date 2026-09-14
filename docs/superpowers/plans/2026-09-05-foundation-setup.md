# 조각 0 — 기반 공사 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CampusMate 앱의 뼈대를 세운다 — Flutter 프로젝트, 공용 기반 코드, Supabase 스키마와 권한, 코딩 규칙 문서까지. 빈 화면이 뜨고 DB가 준비된 상태에서 끝난다.

**Architecture:** 기능별 최상위 패키지 아래 `model / view / viewmodel` 3단으로 나누는 MVVM. 상태 관리는 Riverpod, 라우팅은 go_router. **백엔드는 FastAPI(비즈니스 로직) + Supabase(Auth·DB·RLS·Storage) 로 나눈다(2026-09-12 확정, 설계 문서 §1·§7·§13 미결38).** 다만 이 조각 0 범위는 여전히 Flutter 프로젝트 뼈대 + Supabase 스키마/RLS뿐이다 — FastAPI 서버 자체는 그 로직이 처음 필요해지는 조각에서 시작한다는 원칙은 그대로이되, ~~(매칭·결제)~~ → **조각 1부터다(2026-09-13 확정, ERD.md §11-8)**: 클라이언트 쓰기가 전부 FastAPI를 거치는 구조(설계 문서 §7.1)라 이메일 인증 직후 `profiles` 생성과 `3b` 학생증 OCR부터 이미 FastAPI가 필요하다. 화면과 무관한 판단 로직(라우팅 리다이렉트, 설정 검증)은 순수 Dart 클래스로 분리해 위젯 없이 테스트한다.

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
- **커밋 메시지**: Conventional Commits, 타입은 영문 소문자, 설명은 한국어. scope는 기능 패키지명
- **`git push` 는 하지 않는다.** 커밋까지만 하고 푸시는 사용자가 직접 수행한다

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

## Task 1: 개발 환경 준비

**사용자 수행이 필요한 태스크다.** 코드 변경은 없고, 이후 모든 태스크의 전제 조건을 갖춘다.

현재 상태 (2026-09-12 재확인):

| 도구            | 상태                                                     |
| --------------- | -------------------------------------------------------- |
| Android Studio  | 설치됨 (`C:\Program Files\Android\Android Studio`)       |
| Android SDK     | 설치됨 (`C:\Users\home\AppData\Local\Android\Sdk`)       |
| Java            | 21.0.8 ✓                                                 |
| Git             | 2.49.0 ✓                                                 |
| Node.js         | v24.11.0 ✓                                               |
| **Flutter SDK** | **설치됨 — 3.47.3 stable (`C:\dev\flutter`)** ✓          |
| GitHub CLI      | 설치됨 (draft PR 생성용) ✓                               |
| Supabase CLI    | 설치됨 (`C:\dev\supabase-cli`, PATH 등록) ✓ — `npx` 불필요 |
| graphify        | 설치됨 (`graphifyy` 0.9.58 + 스킬) — 코드베이스 탐색용, `docs/GRAPHIFY.md` |
| Docker          | 없음 — 로컬 Supabase 스택 대신**클라우드 프로젝트 사용** |

- [x] **Step 1: Flutter SDK 설치** — 완료 (3.47.3 stable)

사용자가 직접 수행한다. [https://docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows) 의 zip을 받아
`C:\src\flutter` 에 풀고, `C:\src\flutter\bin` 을 사용자 환경변수 `Path` 에 추가한다.

설치 후 새 터미널에서 확인:

```bash
flutter --version
```

기대 결과: 버전 정보가 출력된다 (`command not found` 가 아니어야 한다).

- [x] **Step 2: Flutter 환경 점검** — 완료 (2026-09-14. Flutter 3.47.3 · Android toolchain(SDK 36.1.0, 라이선스 동의됨) ✓. 이 Flutter 버전은 Android Studio 를 별도 항목으로 보이지 않고 Android toolchain 이 Android Studio 번들 JDK 를 쓴다. Visual Studio ✗ 는 무시 항목)

```bash
flutter doctor -v
```

기대 결과: `Flutter`, `Android toolchain`, `Android Studio` 항목이 체크(✓)로 표시된다.
`Android license status unknown` 이 뜨면 `flutter doctor --android-licenses` 로 라이선스에 동의한다.
`Visual Studio` / `Xcode` 항목의 경고는 무시한다 (Windows 데스크톱·iOS 로컬 빌드를 하지 않는다).

- [x] **Step 3: Supabase 클라우드 프로젝트 생성** — 완료 (프로젝트 `campus_mate`, 조직 CampusMate, Seoul. URL·anon 키는 문서에 적지 않고 MCP `get_project_url` · `get_publishable_keys` 로 조회한다)

사용자가 [https://supabase.com/dashboard](https://supabase.com/dashboard) 에서 새 프로젝트를 만든다.

- 리전: **Northeast Asia (Seoul)** — 사용자가 국내에 있으므로 지연 시간이 가장 짧다
- 프로젝트명: `campusmate`
- 데이터베이스 비밀번호를 안전한 곳에 보관한다

생성 후 **Project Settings → API** 에서 아래 두 값을 확보한다.

- `Project URL` (예: `https://xxxxx.supabase.co`)
- `anon public` 키

- [ ] **Step 4: pgvector 확장 활성화 확인** — 미완료 (2026-09-12 확인: `vector` 꺼져 있음). **대시보드에서 손으로 켜지 않는다** — Task 7 첫 마이그레이션 맨 앞에 `create extension if not exists vector with schema extensions;` 로 켠다 (`frontend/CLAUDE.md` §10.1)

Supabase 대시보드 **Database → Extensions** 에서 `vector` 를 검색해 활성화한다.
(조각 3에서 쓰지만, 프로젝트 생성 시점에 켜두는 편이 낫다.)

확인용 SQL (대시보드 SQL Editor에서 실행):

```sql
select extname from pg_extension where extname = 'vector';
```

기대 결과: `vector` 한 행이 나온다.

- [x] **Step 5: Supabase CLI 동작 확인** — 완료 (`supabase --version` → 2.117.0, `C:\dev\supabase-cli`)

Node가 있으므로 전역 설치 없이 `npx` 로 쓴다.

```bash
npx --yes supabase --version
```

기대 결과: 버전 번호가 출력된다.

**이 태스크에는 커밋이 없다.** 다음 태스크로 넘어가기 전에 Step 1~5가 모두 통과해야 한다.

---

## Task 2: Flutter 프로젝트 생성과 패키지 골격

> **진행 상황 (2026-09-12).** **Task 2 완료** (Step 1~9). UI 작업이 없어 디자인 확정 전에 먼저 끝냈다.
>
> 계획과 달라진 점:
> - 저장소 구조가 **단일 저장소 안의 `frontend/` + `backend/` + `docs/`** 로 바뀌었다. 아래 명령의 작업 디렉터리는 모두 `frontend/` 다
> - Dart 패키지명은 `campusmate` 가 아니라 **`campus_mate`** 다 (저장소명·Dart 관례에 맞춤). 이 문서의 `package:campus_mate/...` import 가 실제와 맞는 표기다
> - `flutter create` 가 `--org` 없이 실행돼 `com.example.*` 로 만들어져 있었고, 2026-09-12 에 `io.github.juunn.campusmate` 로 고쳤다

**Files:**

- Create: `.gitignore`, `pubspec.yaml`, `lib/main.dart` (flutter create가 생성)
- Create: `lib/{auth,profile,matching,chat,safety,billing}/{model,view,viewmodel}/.gitkeep`
- Create: `lib/{common,core}/` 하위 디렉터리

**Interfaces:**

- Consumes: Task 1의 Flutter SDK
- Produces: 빌드 가능한 Flutter 프로젝트. 이후 모든 태스크가 이 위에서 작업한다

- [x] **Step 1: git 저장소 초기화** — 완료 (단일 저장소 Campus_mate_compose 로 통합)

**사용자에게 먼저 확인한다** (프로젝트 규칙: `git init` 은 사전 확인 대상).

```bash
cd "C:/Users/home/AndroidStudioProjects/campus_mate_compose/frontend"
git init
git branch -M main
```

- [x] **Step 2: Flutter 프로젝트 생성** — 완료 (실제로는 패키지명 campus_mate, 저장소 루트가 아니라 frontend/ 에 생성됨)

현재 디렉터리에 생성한다. `docs/` 는 그대로 유지된다.

```bash
cd "C:/Users/home/AndroidStudioProjects/campus_mate_compose/frontend"
flutter create --org io.github.juunn --project-name campusmate --platforms android,ios .
```

- [x] **Step 3: 패키지명이 올바른지 확인** — 완료 (com.example.* 로 생성돼 있던 것을 2026-09-12 에 io.github.juunn.campusmate 로 수정)

```bash
grep -r "io.github.juunn.campusmate" android/app/build.gradle.kts ios/Runner.xcodeproj/project.pbxproj | head -5
```

기대 결과: `applicationId = "io.github.juunn.campusmate"` 와 iOS 번들 ID가 함께 잡힌다.
**여기서 틀리면 나중에 고치기 어렵다.** 다르면 이 단계에서 바로잡는다.

- [x] **Step 4: 의존성 추가** — 완료 (2026-09-12. supabase_flutter 2.17.2, flutter_riverpod 3.4.3, go_router 18.0.1, image_picker 1.2.3, cached_network_image 4.0.0, dev:mocktail 1.0.5. riverpod 가 3.x 라 `Notifier` 는 그대로 쓰고 provider 기본값이 auto-dispose 다)

버전은 고정하지 않고 `flutter pub add` 가 해석하게 둔다. 손으로 적은 버전은 틀리기 쉽다.

```bash
flutter pub add supabase_flutter flutter_riverpod go_router image_picker cached_network_image
flutter pub add dev:mocktail
```

- [x] **Step 5: 패키지 골격 디렉터리 생성** — 완료

빈 디렉터리는 git이 추적하지 않으므로 `.gitkeep` 을 넣는다.

```bash
cd "C:/Users/home/AndroidStudioProjects/campus_mate_compose/frontend"
for feature in auth profile matching chat safety billing; do
  for layer in model view viewmodel; do
    mkdir -p "lib/$feature/$layer" && touch "lib/$feature/$layer/.gitkeep"
  done
done
mkdir -p lib/common lib/core/theme lib/core/supabase lib/core/router lib/core/push
mkdir -p test/common test/core/theme test/core/supabase test/core/router
```

`supabase/` 는 만들지 않는다. Task 7에서 `supabase init` 이 직접 생성한다.
미리 만들어두면 init 이 기존 디렉터리와 충돌한다.

- [x] **Step 6: `.gitignore` 에 비밀 파일 추가** — 완료 (실존 인물 목업 이미지 제외 규칙도 함께 추가)

`.gitignore` 끝에 아래를 덧붙인다. **Supabase 키가 저장소에 들어가면 안 된다.**

```gitignore

# 프로젝트 고유 — 비밀값
.env
.env.*
*.keystore
*.jks
ios/Runner/GoogleService-Info.plist
android/app/google-services.json
```

- [x] **Step 7: iOS 권한 문구 추가** — 완료 (NSPhotoLibraryUsageDescription · NSCameraUsageDescription)

사진 선택 권한 문구를 미리 넣어둔다. 조각 2에서 사진 업로드를 붙일 때 필요한데,
**문구가 없으면 앱스토어 심사에서 반려된다.** 지금 넣어두면 나중에 빠뜨릴 일이 없다.

`ios/Runner/Info.plist` 의 `</dict>` 바로 앞에 아래를 추가한다.

```xml
	<key>NSPhotoLibraryUsageDescription</key>
	<string>프로필 사진을 등록하기 위해 사진 접근 권한이 필요합니다.</string>
	<key>NSCameraUsageDescription</key>
	<string>프로필 사진을 촬영하기 위해 카메라 접근 권한이 필요합니다.</string>
```

추가 후 확인:

```bash
grep -A1 "NSPhotoLibraryUsageDescription" ios/Runner/Info.plist
```

기대 결과: 방금 넣은 한국어 문구가 출력된다.

- [x] **Step 8: 기본 상태에서 분석과 테스트가 통과하는지 확인** — 완료 (`No issues found!`, 기본 위젯 테스트 통과)

```bash
flutter analyze
flutter test
```

기대 결과: `flutter analyze` 는 `No issues found!`, `flutter test` 는 flutter create가 만든 기본 위젯 테스트가 통과한다.

- [x] **Step 9: 커밋** — 완료 (커밋 메시지는 `docs/GIT.md` 의 gitmoji 규칙을 따른다)

```bash
git add -A
git commit -m "chore: Flutter 프로젝트 생성 및 패키지 골격 구성

- io.github.juunn.campusmate 로 Android/iOS 프로젝트 생성
- 기능별 model/view/viewmodel 3단 디렉터리 구성
- supabase_flutter, flutter_riverpod, go_router 등 의존성 추가"
```

---

## Task 3: 공용 기반 — Result 와 Failure

**Files:**

- Create: `lib/common/failure.dart`
- Create: `lib/common/result.dart`
- Test: `test/common/failure_test.dart`, `test/common/result_test.dart`

**Interfaces:**

- Consumes: 없음
- Produces:
  - `sealed class Failure` — `String toDisplayMessage()`
  - 구현체: `NetworkFailure`, `NotFoundFailure`, `UnknownFailure` (모두 `const` 생성자)
  - `sealed class Result<T>` — `R when<R>({required R Function(T value) onSuccess, required R Function(Failure failure) onFailure})`
  - 구현체: `Success<T>(T value)`, `FailureResult<T>(Failure failure)`

**설계 의도**: 값을 꺼내는 getter를 만들지 않는다. `when` 으로 두 경우를 모두 처리하게 강제하면 분기 누락이 컴파일 단계에서 걸린다 (Tell, Don't Ask).

- [x] **Step 1: Failure 실패 테스트 작성**

`test/common/failure_test.dart`:

```dart
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('네트워크 실패는 연결 확인 안내를 보여준다', () {
    const failure = NetworkFailure();

    expect(failure.toDisplayMessage(), '네트워크 연결을 확인해 주세요');
  });

  test('찾을 수 없음 실패는 대상이 없다는 안내를 보여준다', () {
    const failure = NotFoundFailure();

    expect(failure.toDisplayMessage(), '요청한 정보를 찾을 수 없습니다');
  });

  test('알 수 없는 실패는 일반 오류 안내를 보여준다', () {
    const failure = UnknownFailure();

    expect(failure.toDisplayMessage(), '알 수 없는 오류가 발생했습니다');
  });
}
```

- [x] **Step 2: 테스트가 실패하는지 확인**

```bash
flutter test test/common/failure_test.dart
```

기대 결과: FAIL — `Target of URI doesn't exist: 'package:campus_mate/common/failure.dart'`

- [x] **Step 3: Failure 구현**

`lib/common/failure.dart`:

```dart
/// 도메인 실패를 표현한다.
/// 실패의 내부 사정을 노출하지 않고, 사용자에게 보여줄 문구만 제공한다.
sealed class Failure {
  const Failure();

  /// 화면에 표시할 한국어 안내 문구를 돌려준다.
  String toDisplayMessage();
}

/// 네트워크 연결 자체가 실패한 경우.
final class NetworkFailure extends Failure {
  const NetworkFailure();

  @override
  String toDisplayMessage() {
    return '네트워크 연결을 확인해 주세요';
  }
}

/// 요청한 리소스가 존재하지 않는 경우.
final class NotFoundFailure extends Failure {
  const NotFoundFailure();

  @override
  String toDisplayMessage() {
    return '요청한 정보를 찾을 수 없습니다';
  }
}

/// 위 어느 경우에도 해당하지 않는 예기치 못한 실패.
final class UnknownFailure extends Failure {
  const UnknownFailure();

  @override
  String toDisplayMessage() {
    return '알 수 없는 오류가 발생했습니다';
  }
}
```

- [x] **Step 4: 테스트 통과 확인**

```bash
flutter test test/common/failure_test.dart
```

기대 결과: PASS (3 tests)

- [x] **Step 5: Result 실패 테스트 작성**

`test/common/result_test.dart`:

```dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('성공 결과는 onSuccess 분기를 실행한다', () {
    const Result<int> result = Success<int>(3);

    final actual = result.when(
      onSuccess: (value) => value * 2,
      onFailure: (failure) => -1,
    );

    expect(actual, 6);
  });

  test('실패 결과는 onFailure 분기를 실행한다', () {
    const Result<int> result = FailureResult<int>(NetworkFailure());

    final actual = result.when(
      onSuccess: (value) => 'ok',
      onFailure: (failure) => failure.toDisplayMessage(),
    );

    expect(actual, '네트워크 연결을 확인해 주세요');
  });

  test('성공 결과는 실패 분기를 실행하지 않는다', () {
    const Result<String> result = Success<String>('value');
    var failureCallCount = 0;

    result.when(
      onSuccess: (value) => value,
      onFailure: (failure) {
        failureCallCount = failureCallCount + 1;
        return '';
      },
    );

    expect(failureCallCount, 0);
  });
}
```

- [x] **Step 6: 테스트가 실패하는지 확인**

```bash
flutter test test/common/result_test.dart
```

기대 결과: FAIL — `result.dart` 를 찾을 수 없다

- [x] **Step 7: Result 구현**

`lib/common/result.dart`:

```dart
import 'package:campus_mate/common/failure.dart';

/// 성공과 실패를 하나의 타입으로 표현한다.
/// 값을 꺼내는 getter 를 두지 않고 [when] 으로만 다루게 해서
/// 실패 처리를 빠뜨리는 것을 막는다.
sealed class Result<T> {
  const Result();

  /// 성공과 실패 두 경우를 모두 처리해 하나의 값으로 접는다.
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  });
}

/// 작업이 성공해 값을 가진 결과.
final class Success<T> extends Result<T> {
  const Success(this._value);

  final T _value;

  @override
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return onSuccess(_value);
  }
}

/// 작업이 실패한 결과.
final class FailureResult<T> extends Result<T> {
  const FailureResult(this._failure);

  final Failure _failure;

  @override
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return onFailure(_failure);
  }
}
```

- [x] **Step 8: 테스트 통과와 분석 확인** — 완료 (6 tests PASS, `No issues found!`)

```bash
flutter test test/common/
flutter analyze
```

기대 결과: 6 tests PASS, `No issues found!`

- [x] **Step 9: 커밋** — 완료 (커밋 메시지는 `docs/GIT.md` 의 gitmoji 규칙을 따른다)

```bash
git add lib/common test/common
git commit -m "feat(common): Result 와 Failure 공용 타입 추가

- 값을 꺼내지 않고 when 으로 접어 처리하도록 설계
- 실패 종류별 한국어 표시 문구 제공"
```

---

## Task 4: 디자인 토큰과 테마

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

## Task 5: Supabase 설정과 초기화

**Files:**

- Create: `lib/core/supabase/supabase_config.dart`, `lib/core/supabase/supabase_initializer.dart`
- Test: `test/core/supabase/supabase_config_test.dart`

**Interfaces:**

- Consumes: 없음
- Produces:
  - `class SupabaseConfig` — `const SupabaseConfig({required String url, required String anonKey})`, `factory SupabaseConfig.fromEnvironment()`, `bool isComplete()`, `Future<void> connect()`
  - `abstract final class SupabaseInitializer` — `static Future<void> run(SupabaseConfig config)`

**설계 의도**: 키를 코드에 넣지 않고 `--dart-define` 으로 주입한다. 값 검증(`isComplete`)과 실제 연결(`connect`)을 나눠서, 검증은 네트워크 없이 테스트한다. `SupabaseConfig` 의 인스턴스 변수는 2개(url, anonKey)로 규칙을 지킨다.

- [ ] **Step 1: 실패 테스트 작성**

`test/core/supabase/supabase_config_test.dart`:

```dart
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('url 과 anonKey 가 모두 있으면 설정이 완전하다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: 'anon-key',
    );

    expect(config.isComplete(), isTrue);
  });

  test('url 이 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(url: '', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('anonKey 가 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: '',
    );

    expect(config.isComplete(), isFalse);
  });

  test('공백만 있는 값은 비어 있는 것으로 본다', () {
    const config = SupabaseConfig(url: '   ', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('주입값이 없는 테스트 환경에서는 설정이 완전하지 않다', () {
    final config = SupabaseConfig.fromEnvironment();

    expect(config.isComplete(), isFalse);
  });
}
```

마지막 테스트가 성립하는 이유: `flutter test` 는 `--dart-define` 없이 실행되므로
`String.fromEnvironment` 가 빈 문자열을 돌려준다.

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
flutter test test/core/supabase/supabase_config_test.dart
```

기대 결과: FAIL — `supabase_config.dart` 없음

- [ ] **Step 3: SupabaseConfig 구현**

`lib/core/supabase/supabase_config.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// 빌드 시 주입된 Supabase 접속 정보를 담는다.
///
/// 키를 소스에 적지 않고 `--dart-define` 으로 넣는다.
/// 앱은 디컴파일되면 문자열이 그대로 드러나므로,
/// 여기에는 공개해도 되는 anon 키만 들어간다.
class SupabaseConfig {
  const SupabaseConfig({required String url, required String anonKey})
      : _url = url,
        _anonKey = anonKey;

  /// 빌드 명령의 --dart-define 값을 읽어 설정을 만든다.
  factory SupabaseConfig.fromEnvironment() {
    return const SupabaseConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  final String _url;
  final String _anonKey;

  /// 접속에 필요한 값이 모두 채워졌는지 확인한다.
  /// 잘못된 설정으로 앱이 뜨는 것을 진입 시점에 막기 위한 것이다.
  bool isComplete() {
    return _url.trim().isNotEmpty && _anonKey.trim().isNotEmpty;
  }

  /// Supabase 클라이언트를 실제로 초기화한다.
  Future<void> connect() {
    return Supabase.initialize(url: _url, anonKey: _anonKey);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
flutter test test/core/supabase/supabase_config_test.dart
```

기대 결과: PASS (5 tests)

- [ ] **Step 5: 초기화 진입점 구현**

`lib/core/supabase/supabase_initializer.dart`:

```dart
import 'package:campus_mate/core/supabase/supabase_config.dart';

/// 앱 시작 시 Supabase 연결을 준비한다.
///
/// 설정 검증(SupabaseConfig)과 실제 연결을 나눠 두어
/// 검증 로직을 네트워크 없이 테스트할 수 있게 했다.
abstract final class SupabaseInitializer {
  /// 설정이 불완전하면 즉시 예외를 던져 잘못된 빌드를 조기에 드러낸다.
  static Future<void> run(SupabaseConfig config) {
    if (config.isComplete()) {
      return config.connect();
    }
    throw StateError(
      'Supabase 설정이 비어 있습니다. '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... '
      '를 붙여 실행하세요.',
    );
  }
}
```

- [ ] **Step 6: 분석 통과 확인**

```bash
flutter analyze
```

기대 결과: `No issues found!`

- [ ] **Step 7: 실행 방법 문서화**

프로젝트 루트에 `run.md` 를 만든다. 키를 기억에 의존하지 않게 하기 위한 것이다.

````markdown
# 실행 방법

Supabase 키는 소스에 넣지 않고 실행할 때 주입한다.

## 개발 실행

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```
````

## 테스트

```bash
flutter test
```

테스트는 키 없이 돌아간다. 네트워크에 붙는 코드는 테스트하지 않는다.

## 주의

`--dart-define` 값을 이 파일에 적지 않는다. 실제 키는 각자 로컬에 보관한다.

````

- [ ] **Step 8: 커밋**

```bash
git add lib/core/supabase test/core/supabase run.md
git commit -m "feat(core): Supabase 설정 주입과 초기화 추가

- 키를 소스에 넣지 않고 --dart-define 으로 주입
- 설정 검증과 실제 연결을 분리해 네트워크 없이 테스트 가능하게 함"
````

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

## Task 7: Supabase 스키마와 RLS 정책

> ⚠️ **이 Task 아래의 SQL은 조각 0 시점(설계 문서 §5.3) 초안이며, 실제 최종본이 아니다.** `docs/ERD.md` v3(2026-09-13 검수 통과)가 스키마 기준을 크게 바꿨다 — `hide_same_major` 삭제·`admission_year` 추가, `email_domain` → `university_email_domains` 분리, 클라이언트 INSERT·UPDATE 정책 제거(쓰기는 전부 FastAPI), Storage 정책 제거(서명 URL로 대체), `auth.uid()` → `(select auth.uid())`, grant를 RLS와 같은 마이그레이션에 명시 추가 등.
>
> **사이클 B에서 `docs/ERD.md` §2·§10을 기준으로 마이그레이션을 새로 작성했다(완료).** 실제 산출물은 `supabase/migrations/` 4개(universities, profiles, profile_photos, 비공개 Storage 버킷)이며, 분석 검수·최종 검토·재검수를 모두 통과했다(2026-09-13). 아래 SQL은 조각 0 당시의 기록으로만 남긴다 — 실제 최종 SQL은 `supabase/migrations/`를 본다. Supabase 클라우드에는 아직 적용하지 않았다. 사용자가 ERD 그림을 검토·승인하기 전까지는 적용을 금지한다.

**Files:**

- Create: `supabase/migrations/20260905000001_create_universities.sql`
- Create: `supabase/migrations/20260905000002_create_profiles.sql`
- Create: `supabase/migrations/20260905000003_create_profile_photos.sql`
- Create: `supabase/migrations/20260905000004_create_storage_bucket.sql`
- Create: `supabase/config.toml` (CLI가 생성)

**Interfaces:**

- Consumes: Task 1의 Supabase 클라우드 프로젝트
- Produces: `public.universities`, `public.profiles`, `public.profile_photos` 테이블과 RLS 정책, `profile-photos` Storage 버킷

**설계 의도**: 마이그레이션을 SQL 파일로 저장소에 남긴다. 대시보드에서 손으로 만들면 재현이 불가능해지고 나중에 스테이징 환경을 만들 수 없다.

- [ ] **Step 1: Supabase 프로젝트 초기화와 연결**

```bash
cd "C:/Users/home/AndroidStudioProjects/campus_mate_compose"
npx --yes supabase init
npx --yes supabase login
npx --yes supabase link --project-ref <프로젝트 참조 ID>
mkdir -p supabase/tests
```

**`frontend/` 가 아니라 저장소 루트에서 실행한다**(2026-09-13 사용자 결정 — File Structure 각주 참조). `<프로젝트 참조 ID>` 는 Supabase 대시보드 URL의 `https://supabase.com/dashboard/project/여기` 부분이다.
`supabase init` 이 `supabase/migrations` 와 `config.toml` 을 만든다. 시드는 기본 위치인 `supabase/seed.sql` 하나만 쓰고(2026-09-13 결정), `tests`는 직접 추가한다.

- [ ] **Step 2: universities 마이그레이션 작성**

`supabase/migrations/20260905000001_create_universities.sql`:

```sql
-- 허용 대학 목록.
-- 이 테이블의 email_domain 화이트리스트가 곧 학생인증의 실체다.
create table public.universities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- 학교 이메일 도메인. ac.kr 이 아닌 학교(skku.edu 등)도 있어
  -- 접미사 규칙이 아니라 명시적 목록으로 관리한다.
  email_domain text not null unique,
  -- 오픈 범위를 통제하는 지역 묶음. 첫 출시는 'seoul' 만 사용한다.
  region_group text not null,
  created_at timestamptz not null default now()
);

comment on table public.universities is '가입을 허용하는 대학과 이메일 도메인 목록';

alter table public.universities enable row level security;

-- 가입 화면에서 학교를 골라야 하므로 로그인 전에도 읽을 수 있어야 한다.
-- 쓰기는 어떤 정책도 만들지 않아 서비스 롤 외에는 불가능하다.
create policy "universities are readable by everyone"
  on public.universities
  for select
  to anon, authenticated
  using (true);
```

- [ ] **Step 3: profiles 마이그레이션 작성**

> **범위 주의 (2026-09-10 갱신).** 이 마이그레이션은 조각 0 시점에 알던 컬럼만 담는다. 이후
> 스펙(§5.3)에서 확정됐지만 **여기 없는 컬럼은 해당 조각에서 추가**한다(스펙 §5.4 원칙):
> - `phone_number`(평문·필수), `real_name`(평문·필수), `student_id_verified` → **조각 1** (§5.3·§7 예외 1·2·§7.3)
> - `preferred_age_min`/`preferred_age_max` → 조각 4 (~~§13 미결32~~ → §13 미결28, 나이계수 감점 방식으로 해결. 2026-09-13, 문서 정정 — ERD.md §13)
> - `is_smoker`, `animal_type`, `impression_type`, `preferred_animal_types`,
>   `preferred_impression_types` → 조각 2·3 (§6.6a·§6.6b, ~~§13 미결36~~ → DESIGN.md §13-49, 상호 매칭 확정. 2026-09-13, 문서 정정 — ERD.md §13. 미결36은 HMAC 키 교체 절차로 무관한 참조였다)
> - `nickname_changed_at`(30일 1회 변경 제한 추적) → 조각 2
>
> `ideal_description`은 폐기됐다(§6.3, `ideal_text` 임베딩과 함께). 아래 SQL에서 제외한다.

`supabase/migrations/20260905000002_create_profiles.sql`:

```sql
-- 성별. 매칭의 하드 필터로 쓰인다.
create type public.gender as enum ('male', 'female');

-- 프로필 상태. pending 은 온보딩 미완료 상태다.
create type public.profile_status as enum ('pending', 'active', 'suspended');

-- 학과 계열. 표시와 통계에 쓰고 매칭 점수에는 넣지 않는다.
create type public.major_field as enum (
  'humanities', 'social', 'business', 'engineering',
  'natural_science', 'medical', 'arts_sports', 'education'
);

create table public.profiles (
  -- auth.users 의 id 를 그대로 기본키로 쓴다.
  id uuid primary key references auth.users (id) on delete cascade,
  university_id uuid not null references public.universities (id),
  -- 앱 전 화면에서 사용자를 가리키는 유일한 이름. 한글 완성형+영문 2~5자.
  -- 전체 서비스에서 유니크(대소문자 무시 — 아래 lower() 유니크 인덱스). 스펙 §5.3·§13-5
  nickname text not null,
  gender public.gender not null,
  looking_for public.gender not null,
  birth_year smallint not null,
  -- 키는 필수 입력이며 프로필에 공개된다.
  height_cm smallint not null,
  -- 선호 키 범위는 선택. 비어 있으면 점수에 관여하지 않는다.
  preferred_height_min smallint,
  preferred_height_max smallint,
  bio text,
  mbti text,
  -- 8개 극의 ok/no 토글. 예: {"E":true,"I":true,"N":true,"S":false, ...}
  -- 한 축에서 켜진 극이 1개면 그 극을 선호하고, 0개나 2개면 상관없음으로 본다.
  preferred_mbti_flags jsonb not null default '{}'::jsonb,
  major text,
  major_field public.major_field,
  -- 같은 학과를 추천에서 제외할지. 아는 사람에게 들키는 것을 피하기 위한 장치다.
  hide_same_major boolean not null default false,
  interest_tags text[] not null default '{}',
  status public.profile_status not null default 'pending',
  -- 활동성 계수 산출에 쓴다. 유령 계정에게 카드를 낭비하지 않기 위한 값이다.
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint profiles_birth_year_range check (birth_year between 1950 and 2020),
  constraint profiles_height_range check (height_cm between 120 and 230),
  constraint profiles_preferred_height_order check (
    preferred_height_min is null
    or preferred_height_max is null
    or preferred_height_min <= preferred_height_max
  ),
  -- 한글 완성형(가-힣) + 영문만, 2~5자. 숫자·공백·특수문자·한글 자모 단독 불가.
  constraint profiles_nickname_format check (nickname ~ '^[가-힣a-zA-Z]{2,5}$')
);

comment on table public.profiles is '사용자 프로필. 남의 행은 RLS 로 막고 이후 RPC 로만 노출한다';

create index profiles_matching_filter_index
  on public.profiles (gender, looking_for, status);

-- 닉네임은 전체 서비스에서 유니크하다. 대소문자만 무시하고(한글은 영향 없음)
-- 앞뒤 공백은 앱에서 이미 제거해 들어온다.
create unique index profiles_nickname_unique
  on public.profiles (lower(nickname));

alter table public.profiles enable row level security;

-- 본인 행만 읽는다. 남의 프로필은 조각 4의 FastAPI 엔드포인트로만 내보낸다(2026-09-12: 백엔드 FastAPI+Supabase 확정).
-- RLS 는 행 단위라 "이 컬럼만" 을 표현할 수 없기 때문이다.
create policy "profiles are readable by owner"
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy "profiles are insertable by owner"
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

create policy "profiles are updatable by owner"
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
```

- [ ] **Step 4: profile_photos 마이그레이션 작성**

`supabase/migrations/20260905000003_create_profile_photos.sql`:

```sql
-- 사진 메타데이터. 실제 이미지는 Storage 에 두고 경로만 보관한다.
create table public.profile_photos (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null,
  -- 프로필에서의 노출 순서. 0 이 대표 사진이다.
  position smallint not null,
  created_at timestamptz not null default now(),

  unique (profile_id, position),
  constraint profile_photos_position_range check (position between 0 and 5)
);

comment on table public.profile_photos is '프로필 사진 메타. 이미지 본체는 Storage 에 있다';

alter table public.profile_photos enable row level security;

create policy "profile photos are readable by owner"
  on public.profile_photos
  for select
  to authenticated
  using (profile_id = auth.uid());

create policy "profile photos are insertable by owner"
  on public.profile_photos
  for insert
  to authenticated
  with check (profile_id = auth.uid());

create policy "profile photos are deletable by owner"
  on public.profile_photos
  for delete
  to authenticated
  using (profile_id = auth.uid());
```

- [ ] **Step 5: Storage 버킷 마이그레이션 작성**

`supabase/migrations/20260905000004_create_storage_bucket.sql`:

```sql
-- 프로필 사진 버킷.
-- public = false 로 두는 것이 핵심이다. 공개 버킷이면 URL 만 알면 누구나 볼 수 있고,
-- 크롤링당하면 전체 사진이 통째로 유출된다. 조회는 서명 URL 로만 한다.
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

-- 업로드한 본인만 자기 파일을 다룰 수 있다.
-- 남의 사진은 이후 서버가 서명 URL 을 만들어 전달한다.
create policy "profile photo objects are readable by owner"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'profile-photos' and owner = auth.uid());

create policy "profile photo objects are insertable by owner"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'profile-photos' and owner = auth.uid());

create policy "profile photo objects are deletable by owner"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'profile-photos' and owner = auth.uid());
```

- [ ] **Step 6: 마이그레이션 적용**

```bash
npx --yes supabase db push
```

기대 결과: 4개 마이그레이션이 순서대로 적용됐다는 출력이 나온다.

- [ ] **Step 7: 적용 결과 확인**

Supabase 대시보드 SQL Editor에서 실행:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
```

기대 결과: `profile_photos`, `profiles`, `universities` 세 행.

이어서 RLS가 켜져 있는지 확인:

```sql
select relname, relrowsecurity
from pg_class
where relname in ('universities', 'profiles', 'profile_photos');
```

기대 결과: 세 행 모두 `relrowsecurity` 가 `true`.

- [ ] **Step 8: 커밋**

```bash
git add supabase
git commit -m "feat(core): Supabase 스키마와 RLS 정책 추가

- universities/profiles/profile_photos 테이블 생성
- 본인 행만 접근 가능하도록 RLS 정책 적용
- 프로필 사진용 비공개 Storage 버킷 생성"
```

---

## Task 8: 서울권 대학 시드와 RLS 검증

> ⚠️ **이 Task 아래의 SQL도 Task 7과 같은 이유로 조각 0 시점 초안이며, 실제 최종본이 아니다.** 시드는 `university_email_domains` 분리에 맞춰 다시 쓰고, 기본 위치는 `supabase/seed.sql` 하나로 둔다(2026-09-13 결정 — `seeds/` 폴더를 쓰려면 `config.toml`에 `[db.seed] sql_paths` 를 추가해야 하지만 기본값이면 충분하다).
>
> **실제로는 `supabase/seed.sql`(서울권 대학 20개)과 `supabase/tests/rls_slice0_test.sql`(pgTAP 21개 항목)을 작성 완료했고, 분석 검수·최종 검토·재검수를 모두 통과했다(2026-09-13).** pgTAP은 작성만 하고 아직 실행하지 않았다. Supabase 클라우드 프로젝트에는 쓰기(마이그레이션 적용·`db push`·`supabase link`·쓰기 `execute_sql`)를 하지 않았다 — 사용자가 ERD 그림을 검토·승인하기 전까지는 금지한다. 아래 SQL은 조각 0 당시의 기록으로만 남긴다 — 실제 최종 SQL은 `supabase/seed.sql`·`supabase/tests/rls_slice0_test.sql`을 본다.

**Files:**

- Create: `supabase/seed.sql`
- Create: `supabase/tests/*.sql`(pgTAP)

**Interfaces:**

- Consumes: Task 7의 테이블과 정책
- Produces: `region_group = 'seoul'` 인 대학 행들, RLS 회귀 검증 스크립트

**설계 의도**: RLS는 **틀려도 앱이 정상 동작한다.** 테스트가 없으면 유출을 출시 후에야 알게 되므로, 남의 행이 실제로 안 보이는지를 SQL로 증명해 둔다.

- [ ] **Step 1: 서울권 대학 시드 작성**

`supabase/seeds/seoul_universities.sql`:

```sql
-- 첫 출시 대상인 서울권 대학 목록.
-- 도메인은 학교마다 다르고 ac.kr 이 아닌 곳도 있어 명시적으로 적는다.
-- 실제 재학생 메일 도메인이 다를 수 있으므로, 조각 1에서 실제 가입을 시도해
-- 검증한 뒤 필요한 도메인을 추가한다.
insert into public.universities (name, email_domain, region_group) values
  ('서울대학교',       'snu.ac.kr',       'seoul'),
  ('연세대학교',       'yonsei.ac.kr',    'seoul'),
  ('고려대학교',       'korea.ac.kr',     'seoul'),
  ('성균관대학교',     'skku.edu',        'seoul'),
  ('한양대학교',       'hanyang.ac.kr',   'seoul'),
  ('중앙대학교',       'cau.ac.kr',       'seoul'),
  ('경희대학교',       'khu.ac.kr',       'seoul'),
  ('서강대학교',       'sogang.ac.kr',    'seoul'),
  ('이화여자대학교',   'ewha.ac.kr',      'seoul'),
  ('건국대학교',       'konkuk.ac.kr',    'seoul'),
  ('동국대학교',       'dongguk.edu',     'seoul'),
  ('홍익대학교',       'hongik.ac.kr',    'seoul'),
  ('숙명여자대학교',   'sookmyung.ac.kr', 'seoul'),
  ('국민대학교',       'kookmin.ac.kr',   'seoul'),
  ('세종대학교',       'sejong.ac.kr',    'seoul'),
  ('숭실대학교',       'ssu.ac.kr',       'seoul'),
  ('서울시립대학교',   'uos.ac.kr',       'seoul'),
  ('광운대학교',       'kw.ac.kr',        'seoul'),
  ('명지대학교',       'mju.ac.kr',       'seoul'),
  ('상명대학교',       'smu.ac.kr',       'seoul')
on conflict (email_domain) do nothing;
```

- [ ] **Step 2: 시드 적용**

```bash
npx --yes supabase db execute --file supabase/seeds/seoul_universities.sql
```

CLI 버전에 따라 위 명령이 없으면 대시보드 SQL Editor에 파일 내용을 붙여넣어 실행한다.

- [ ] **Step 3: 시드 결과 확인**

```sql
select count(*) as university_count from public.universities where region_group = 'seoul';
```

기대 결과: `20`

- [ ] **Step 4: RLS 검증 스크립트 작성**

`supabase/tests/rls_profiles_test.sql`:

```sql
-- RLS 회귀 검증.
-- RLS 는 잘못돼도 앱이 정상 동작하기 때문에, 남의 행이 실제로 막히는지를
-- 여기서 증명해 둔다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

do $$
declare
  user_a uuid := '00000000-0000-0000-0000-0000000000aa';
  user_b uuid := '00000000-0000-0000-0000-0000000000bb';
  seoul_university uuid;
  visible_count int;
begin
  select id into seoul_university
  from public.universities
  where region_group = 'seoul'
  limit 1;

  if seoul_university is null then
    raise exception '시드가 적용되지 않았다. seoul 지역 대학이 없다';
  end if;

  -- 테스트용 사용자 두 명
  insert into auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at
  ) values
    (user_a, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'rls-test-a@snu.ac.kr', '', now(), now(), now()),
    (user_b, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'rls-test-b@snu.ac.kr', '', now(), now(), now());

  insert into public.profiles (
    id, university_id, nickname, gender, looking_for, birth_year, height_cm
  ) values
    (user_a, seoul_university, '가나', 'male',   'female', 2002, 178),
    (user_b, seoul_university, '다라', 'female', 'male',   2003, 163);

  -- 사용자 B 로 위장해 조회한다.
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_b::text, 'role', 'authenticated')::text,
    true
  );

  select count(*) into visible_count from public.profiles;

  if visible_count <> 1 then
    raise exception
      'RLS 실패: 본인 프로필 1건만 보여야 하는데 %건이 보였다', visible_count;
  end if;

  select count(*) into visible_count
  from public.profiles
  where id = user_a;

  if visible_count <> 0 then
    raise exception 'RLS 실패: 남의 프로필이 조회되었다';
  end if;

  raise notice 'RLS 검증 통과: 본인 행만 조회된다';
end $$;

rollback;
```

- [ ] **Step 5: RLS 검증 실행**

대시보드 SQL Editor에 파일 내용을 붙여넣어 실행한다.

기대 결과: `RLS 검증 통과: 본인 행만 조회된다` 라는 NOTICE가 출력되고 오류가 없다.
`RLS 실패:` 로 시작하는 예외가 나오면 Task 7의 정책을 고친 뒤 다시 실행한다.

- [ ] **Step 6: 커밋**

```bash
git add supabase/seeds supabase/tests
git commit -m "feat(core): 서울권 대학 시드와 RLS 검증 스크립트 추가

- 서울권 20개 대학 이메일 도메인 등록
- 남의 프로필이 RLS 에 막히는지 SQL 로 검증"
```

---

## Task 9: 프로젝트 코딩 규칙 문서

**Files:**

- Create: `CLAUDE.md`

**Interfaces:**

- Consumes: 없음
- Produces: 이후 모든 조각이 따르는 규칙 문서

**설계 의도**: 상위 디렉터리의 `CLAUDE.md` 는 Kotlin/Android 프로젝트용이라 이 프로젝트에 맞지 않는다. 원칙(생활체조 9원칙·SOLID·테스트 필수·git flow·커밋 컨벤션)은 계승하고 언어·구조·도구만 Dart 기준으로 다시 쓴다.

- [ ] **Step 1: CLAUDE.md 작성**

프로젝트 루트에 `CLAUDE.md` 를 만든다.

```markdown
# CLAUDE.md

이 문서는 CampusMate 프로젝트에서 코드를 작성하거나 수정할 때 반드시 따라야 하는 규칙이다.

- **언어**: Dart
- **프로젝트 형태**: Flutter 하이브리드 앱 (Android + iOS), MVVM
- **패키지명**: `io.github.juunn.campusmate`
- **코드·네이밍**: 영어 / **주석·설명·문서**: 한국어

## 1. 필수 사항

1. **애매한 부분은 임의로 결정하지 말고 사용자에게 먼저 질문한다.**
2. **MVVM 패턴에 맞게 패키지를 분리한다.**
3. **기능(테마)별로 패키지를 나누고 그 아래에 model / view / viewmodel 을 둔다.**
4. **하나의 작업이 끝나면 멈추고 사용자의 검토를 받는다.**
5. **모든 비공개가 아닌 클래스는 테스트를 갖는다.**
6. **git commit 은 하되 push 는 하지 않는다.** 푸시는 사용자가 직접 한다.
7. **UI 작업은 디자인 시안을 확인한 뒤 진행한다.** 시안은 조각 8에서 Pencil 로 작성한다.

## 2. 아키텍처

| 계층      | 위치                | 역할                              |
| --------- | ------------------- | --------------------------------- |
| View      | `<기능>/view/`      | 위젯. 표시와 이벤트 전달만        |
| ViewModel | `<기능>/viewmodel/` | 흐름 제어. UiState 생성           |
| Model     | `<기능>/model/`     | 비즈니스 로직, 엔티티, Repository |

- **의존성 방향은 항상 안쪽(Model)을 향한다.** Model 은 View 를 모른다.
- **ViewModel 은 Flutter 위젯 타입을 참조하지 않는다** (`BuildContext`, `Widget` import 금지).
- 상태 관리는 Riverpod 의 `Notifier` 를 쓴다. 순수 Dart 클래스로 작성해 위젯 없이 테스트한다.
- 상태는 `UiState` 클래스 하나로 모아 노출한다.
- UseCase 는 항상 만들지 않는다. 로직이 복잡하거나 재사용될 때만 도입한다.

### 패키지 구조
```

lib/
├── auth/ model/ view/ viewmodel/
├── profile/ model/ view/ viewmodel/
├── matching/ model/ view/ viewmodel/
├── chat/ model/ view/ viewmodel/
├── safety/ model/ view/ viewmodel/
├── billing/ model/ view/ viewmodel/
├── common/ 값 객체, Result, Failure
└── core/ supabase/ router/ theme/ push/

````

## 3. 객체지향 생활 체조

`model/` 계층에는 전부 엄격히 적용한다.
`UiState` 클래스와 위젯 파라미터는 **원칙 7·9의 예외**로 허용한다.

1. **한 메서드에 한 단계 들여쓰기만.** 깊어지면 메서드를 분리한다.
2. **`else` 를 쓰지 않는다.** early return 또는 `switch` 표현식으로 푼다.
3. **원시값을 포장한다.** 검증은 포장 클래스 안에 둔다.
4. **한 줄에 점 하나.** 컬렉션 체이닝과 위젯 빌더 체이닝은 예외.
5. **줄여 쓰지 않는다.** `id`, `url`, `ui` 등 통용 약어만 예외.
6. **메서드는 10줄 이하, 한 가지 일만.** 위젯도 길어지면 분리한다.
7. **인스턴스 변수는 2개 이하.** `UiState` 는 예외.
8. **컬렉션은 일급 컬렉션으로 감싼다.** 컬렉션을 다루는 로직을 그 안에 둔다.
9. **getter 를 노출하지 않는다.** 필드는 `_private`, 행위 메서드만 공개한다. `UiState` 는 예외.

### 예시

```dart
// 나쁜 예 — else 사용
String grade(int score) {
  if (score >= 60) {
    return 'PASS';
  } else {
    return 'FAIL';
  }
}

// 좋은 예 — early return
String grade(int score) {
  if (score >= 60) {
    return 'PASS';
  }
  return 'FAIL';
}
````

```dart
// 나쁜 예 — 값을 꺼내 밖에서 판단
if (item.quantity > maxQuantity) { ... }

// 좋은 예 — 객체에게 묻는다
if (item.exceeds(maxQuantity)) { ... }
```

## 4. SOLID

- **SRP**: 클래스는 하나의 책임만 가진다
- **OCP**: 확장에 열리고 변경에 닫힌다
- **LSP**: 서브타입은 기반 타입을 대체할 수 있다
- **ISP**: 쓰지 않는 인터페이스를 구현하지 않는다
- **DIP**: 구체가 아니라 추상에 의존한다

## 5. 명시적 표현

- 매직 넘버는 이름 있는 상수로 뺀다
- 의도가 한눈에 드러나지 않는 부분은 한국어 주석으로 밝힌다
- 색상·간격은 `core/theme/` 토큰을 통해서만 참조한다. 위젯 안에 `Color(0xFF...)` 리터럴을 쓰지 않는다

## 6. 테스트

| 대상            | 방식                                                    |
| --------------- | ------------------------------------------------------- |
| 값 객체 · Model | `flutter test` 단위 테스트                              |
| Repository      | 인터페이스 뒤에 Fake 구현을 두고 검증                   |
| ViewModel       | `ProviderContainer` + Fake repository                   |
| 위젯            | `testWidgets`                                           |
| RLS 정책        | `supabase/tests/*.sql` — 다른 사용자로 조회 시 0행 확인 |

- 이름 규칙: `AuthRedirect` → `auth_redirect_test.dart`
- 테스트 디렉터리 구조는 `lib/` 를 그대로 미러링한다
- **Supabase 클라이언트를 직접 목킹하지 않는다.** Repository 인터페이스 뒤에 Fake 를 둔다
- 테스트 이름은 한국어로 동작을 서술한다

## 7. Git 전략

git flow 를 따른다.

| 브랜치      | 역할            | 분기 원본 | 병합 대상          |
| ----------- | --------------- | --------- | ------------------ |
| `main`      | 배포된 릴리스만 | —         | —                  |
| `develop`   | 개발 통합       | `main`    | —                  |
| `feature/*` | 기능 단위       | `develop` | `develop`          |
| `release/*` | 릴리스 준비     | `develop` | `main` + `develop` |
| `hotfix/*`  | 긴급 수정       | `main`    | `main` + `develop` |

브랜치명은 kebab-case. 예: `feature/auth-email-verification`

커밋 메시지는 Conventional Commits, 타입은 영문 소문자, 설명은 한국어.
scope 는 기능 패키지명(`auth`, `profile`, `matching`, `chat`, `safety`, `billing`, `core`).

| 타입       | 용도                              |
| ---------- | --------------------------------- |
| `feat`     | 새 기능                           |
| `fix`      | 버그 수정                         |
| `ui`       | 화면·스타일 변경 (기능 변화 없음) |
| `refactor` | 동작 변화 없는 구조 개선          |
| `test`     | 테스트 추가·수정                  |
| `chore`    | 빌드·의존성·설정                  |
| `docs`     | 문서                              |

## 8. 명령

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter test
flutter analyze
npx --yes supabase db push
```

## 9. 보안

- **Supabase 키를 소스에 넣지 않는다.** `--dart-define` 으로 주입한다
- **OpenAI API 키를 앱에 넣지 않는다.** FastAPI 서버 환경변수에만 둔다(2026-09-12: Edge Function에서 이전)
- **남의 프로필은 RLS 로 막고 FastAPI 엔드포인트로만 내보낸다**
- **사진 버킷은 비공개**로 두고 서명 URL 로만 조회한다
- **하트 잔액·결제는 서버에서 강제한다.** 앱 판단은 우회된다(2026-09-08 등록비 폐지, 설계 문서 §2.4)

## 10. 작업 진행 방식

- 한 번에 하나의 작업만 끝내고 멈춘다
- 완료 시 변경 파일 목록 + 무엇을 왜 그렇게 했는지 + 확인이 필요한 지점을 보고한다
- 다음 경우 진행 전에 질문한다: 새 의존성 추가, 패키지 구조 변경, 시안에 없는 화면, 스펙이 모순될 때

## 11. 참고 문서

- 설계: `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md`
- 계획: `docs/superpowers/plans/`

````

- [ ] **Step 2: 문서 링크가 실제 파일을 가리키는지 확인**

```bash
ls docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md
ls docs/superpowers/plans/2026-09-05-foundation-setup.md
````

기대 결과: 두 파일 모두 존재한다.

- [ ] **Step 3: 최종 전체 검증**

```bash
flutter analyze
flutter test
```

기대 결과: `No issues found!`, 모든 테스트 PASS.

- [ ] **Step 4: 커밋**

```bash
git add CLAUDE.md
git commit -m "docs: CampusMate 코딩 규칙 문서 작성

- Kotlin 프로젝트 규칙의 원칙을 계승하고 Dart 기준으로 재작성
- 생활체조 9원칙, SOLID, 테스트 전략, git flow, 보안 규칙 포함"
```

- [ ] **Step 5: develop 브랜치 생성**

이후 작업은 `develop` 에서 분기한다.

```bash
git branch develop
git checkout develop
```

---

## 완료 판정 기준

조각 0이 끝났다고 말하려면 아래가 모두 참이어야 한다.

- [ ] `flutter analyze` 가 `No issues found!` 를 출력한다
- [ ] `flutter test` 전체가 통과한다 (Task 3·4·5·6의 테스트 포함)
- [ ] 앱이 Android에서 실행되고 로그인 자리 화면까지 도달한다
- [ ] `supabase db push` 로 마이그레이션이 빈 DB에 처음부터 적용된다
- [ ] `rls_profiles_test.sql` 이 "RLS 검증 통과" 를 출력한다
- [ ] `universities` 에 서울권 20개 대학이 들어 있다
- [ ] 루트에 `CLAUDE.md` 가 있다
- [ ] `main` 과 `develop` 브랜치가 존재한다

**실행 확인 명령** (Task 1의 값으로 치환):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

---

## 이 조각에서 하지 않는 것

다음 조각에서 다룬다. 여기서 미리 만들지 않는다.

- 실제 로그인·인증 로직, Auth Hook 도메인 검증 → 조각 1
- 프로필 입력 화면, 설문, 태그, 사진 업로드 → 조각 2
- 벡터 테이블, 임베딩 생성(FastAPI 엔드포인트, 2026-09-12: Edge Function에서 이전) → 조각 3
- 일일 카드 배치, 수락/거절, 푸시 알림 → 조각 4
- 채팅 → 조각 5
- 신고·차단·계정 삭제 → 조각 6
- 인앱결제(하트 구매) → 조각 7 (등록비 게이트는 2026-09-08 폐지)
- 실제 디자인 시안 반영 → 조각 8
