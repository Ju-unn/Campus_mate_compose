# 조각 1a — 이메일 OTP 가입 + FastAPI Auth Hook 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대학 이메일 OTP로 가입해 인증된 Supabase 세션을 얻고, FastAPI HTTP Auth Hook이 가입 시점에 학교 도메인 화이트리스트·재가입 제한을 검사해 통과한 사용자만 `profiles`(pending) 행을 갖도록 만든다.

**Architecture:** Flutter는 `supabase_flutter`로 `signInWithOtp`(코드 요청)·`verifyOTP`(코드 검증)만 직접 호출한다 — 이 둘은 Supabase Auth 표준 기능이라 클라이언트가 호출해도 "쓰기는 FastAPI 경유" 원칙에 어긋나지 않는다(auth.users 자체는 Supabase Auth 소유). 도메인 화이트리스트·재가입 제한 검사와 `profiles` 행 생성은 클라이언트가 호출하지 않고, Supabase가 가입 요청 시점에 자동으로 호출하는 **Before User Created HTTP Auth Hook**(FastAPI, Cloud Run) 안에서 서버가 처리한다. 이 훅은 Supabase가 만들 예정인 사용자 id를 페이로드로 미리 받으므로, 승인 응답을 돌려주기 전에 같은 요청 안에서 `profiles` pending 행까지 service_role로 만든다 — 별도의 "가입 완료" 엔드포인트를 두지 않는다.

**Tech Stack:** Flutter/Riverpod(기존 스택 그대로), `supabase_flutter` ^2.17.2(이미 의존성), FastAPI + Python 3.13, httpx, uvicorn, Docker, Google Cloud Run asia-northeast3(서울)

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §3.1·§7.3·§13-37·§13-38·§13-39, `docs/ERD.md` §2·§3, `docs/ERD_DECISIONS.md` §11-8·§11-12

## Global Constraints

스펙·CLAUDE.md·GIT.md·SUPABASE.md 에서 그대로 가져온 전역 요구사항.

- **Flutter**: 코드·네이밍 영어, 주석·문서 한국어 / `else` 금지 — early return 또는 `switch` 표현식 / 메서드 본문 10줄 이하 / Model 계층 인스턴스 변수 2개 이하(UiState 예외) / getter 노출 금지, 필드는 `_private` / 원시값은 값 객체로 포장 / 축약 금지 / 모든 비-private 클래스는 테스트를 가짐 / 색상·간격은 `core/theme/` 토큰만 참조 / ViewModel은 Flutter 위젯 타입을 참조하지 않는다(`BuildContext`·`Widget` import 금지)
- **새 의존성 추가는 사전 사용자 확인** — Part B(FastAPI)에서 `fastapi`·`uvicorn`·`httpx`·`pydantic-settings`를 새로 추가하므로, Task B1 실행 전에 사용자 승인을 받는다
- **Git**: `docs/GIT.md` 를 따른다 — gitmoji 커밋, `<타입>/<주제>` 작업 브랜치 → 푸시 → draft PR, merge는 사용자. **커밋·PR에 도구 표식을 넣지 않는다**(`Co-Authored-By` 등)
- **Supabase 클라우드 쓰기**(마이그레이션 적용, Auth 설정 변경, Auth Hook 등록)는 **매번 사용자가 직접 승인한 뒤에만** 한다(`docs/SUPABASE.md`) — 이 계획의 Part C는 전부 이 승인 게이트 뒤에 있다
- **키 취급**: 프로젝트 URL·anon 키·`service_role` 키·DB 비밀번호는 문서·코드·커밋에 쓰지 않는다. `service_role` 키는 FastAPI 전용, Flutter 코드에는 절대 두지 않는다
- 이 계획은 **조각 1a만** 다룬다. 학생증 사진 인증(조각 1b)·커스텀 SMTP(출시 조각)는 범위 밖이다

---

## 범위 밖 (이 조각에서 하지 않는 것)

- 학생증 사진 인증(OCR·사람 재검토) → 조각 1b. `student_verification` 관련 6개 마이그레이션(`20260914055607`~`20260914061821`)은 이 조각에서 적용하지 않는다
- 커스텀 SMTP(우리 도메인 메일 발신) → 출시 조각. 1a는 Supabase 기본 메일 그대로 쓴다(spec §13-39)
- 온보딩 화면(04-1 이후) → 조각 2. OTP 검증에 성공하면 기존 `AuthRedirect`가 알아서 `/home` 플레이스홀더로 보낸다
- `profiles` 온보딩 컬럼 채우기 → 조각 2. 1a는 `id`·`university_id`·기본값 `status='pending'` 행만 만든다

---

## File Structure

### Part A — Flutter

| 파일 | 책임 |
| --- | --- |
| `frontend/lib/common/failure.dart` (수정) | `RateLimitedFailure`·`SignUpRejectedFailure` 추가 |
| `frontend/lib/auth/model/verification_code.dart` | 6자리 인증코드 값 객체 |
| `frontend/lib/auth/model/auth_repository.dart` | OTP 요청·검증 인터페이스 |
| `frontend/lib/auth/model/supabase_auth_repository.dart` | `AuthRepository`의 Supabase 구현체 |
| `frontend/lib/auth/model/auth_repository_provider.dart` | Riverpod provider |
| `frontend/lib/auth/viewmodel/sign_up_ui_state.dart` (수정) | `isSubmitting`·`errorMessage`·`otpSentTo` 추가 |
| `frontend/lib/auth/viewmodel/sign_up_view_model.dart` (수정) | `submit()` 구현, `acknowledgeNavigation()` |
| `frontend/lib/auth/view/sign_up_screen.dart` (수정) | 코드 화면 이동·에러 표시 연결 |
| `frontend/lib/auth/viewmodel/verify_code_ui_state.dart` | 인증코드 화면 상태 |
| `frontend/lib/auth/viewmodel/verify_code_view_model.dart` | 코드 검증, 재전송 60초 쿨다운 |
| `frontend/lib/auth/view/verify_code_screen.dart` | DESIGN.md 화면 03 |
| `frontend/lib/core/router/app_routes.dart` (수정) | `verifyCode` 경로 추가 |
| `frontend/lib/core/router/app_router.dart` (수정) | 라우트 등록, `isAuthenticated`를 콜백으로 변경 |
| `frontend/lib/core/router/auth_redirect.dart` (수정) | 게스트가 `verifyCode`에도 머무를 수 있게 |
| `frontend/lib/core/supabase/auth_session_listenable.dart` | Supabase 인증 상태 변화를 `go_router`에 알림 |
| `frontend/lib/main.dart` (수정) | 실제 세션으로 `isAuthenticated` 연동 |

### Part B — `backend/`

| 파일 | 책임 |
| --- | --- |
| `backend/pyproject.toml` | 의존성·패키지 메타데이터 |
| `backend/Dockerfile` | Cloud Run 컨테이너 이미지 |
| `backend/.dockerignore` | 이미지에서 제외할 파일 |
| `backend/.env.example` | 필요한 환경변수 이름만(값 없음) |
| `backend/app/main.py` | FastAPI 앱, `/healthz`, 훅 라우터 등록 |
| `backend/app/settings.py` | `pydantic-settings` 기반 설정 |
| `backend/app/webhook_signature.py` | Standard Webhooks HMAC 서명 검증 |
| `backend/app/signup_policy.py` | 도메인 화이트리스트·재가입 제한 검사, pending 프로필 생성 |
| `backend/app/auth_hooks/schemas.py` | 훅 요청·응답 pydantic 모델 |
| `backend/app/auth_hooks/router.py` | `POST /hooks/before-user-created` |
| `backend/tests/test_webhook_signature.py` | 서명 검증 단위 테스트 |
| `backend/tests/test_signup_policy.py` | 정책 로직 단위 테스트(httpx 모킹) |
| `backend/tests/test_auth_hooks_router.py` | 엔드포인트 통합 테스트(`TestClient`) |

### Part C — Supabase 설정 (사용자 승인 후)

| 파일 | 책임 |
| --- | --- |
| `supabase/migrations/<timestamp>_create_signup_blocks.sql` | `signup_blocks` 테이블·RLS·grant |
| `supabase/tests/rls_slice1_test.sql` (수정) | `signup_blocks` 접근 제어 pgTAP 추가 |

---

## Part A: Flutter (GCP 없이 지금 바로 가능)

### Task A1: Failure 서브타입 추가

**Files:**
- Modify: `frontend/lib/common/failure.dart`
- Test: `frontend/test/common/failure_test.dart`

**Interfaces:**
- Produces: `RateLimitedFailure`, `SignUpRejectedFailure(String message)` — 이후 모든 Task가 이 타입을 씀

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
test('시간당 재전송 한도 실패는 잠시 후 다시 시도하라는 안내를 보여준다', () {
  const failure = RateLimitedFailure();
  expect(failure.toDisplayMessage(), '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요');
});

test('가입 거부 실패는 서버가 준 이유를 그대로 보여준다', () {
  const failure = SignUpRejectedFailure('허용되지 않은 학교 이메일이에요');
  expect(failure.toDisplayMessage(), '허용되지 않은 학교 이메일이에요');
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/common/failure_test.dart`
Expected: FAIL — `RateLimitedFailure`·`SignUpRejectedFailure` 없음

- [ ] **Step 3: 구현**

```dart
/// 시간당 재전송·요청 한도에 걸린 경우.
final class RateLimitedFailure extends Failure {
  const RateLimitedFailure();

  @override
  String toDisplayMessage() {
    return '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요';
  }
}

/// Auth Hook이 도메인 화이트리스트·재가입 제한으로 가입을 거부한 경우.
/// 서버가 돌려준 문구를 그대로 보여준다(내부 사정을 새로 지어내지 않는다).
final class SignUpRejectedFailure extends Failure {
  const SignUpRejectedFailure(this._message);

  final String _message;

  @override
  String toDisplayMessage() => _message;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/common/failure_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add frontend/lib/common/failure.dart frontend/test/common/failure_test.dart
git commit -m "✨ feat(auth): OTP 재전송 한도·가입 거부 Failure 추가"
```

---

### Task A2: VerificationCode 값 객체

**Files:**
- Create: `frontend/lib/auth/model/verification_code.dart`
- Test: `frontend/test/auth/model/verification_code_test.dart`

**Interfaces:**
- Produces: `VerificationCode.tryParse(String) -> VerificationCode?`, `VerificationCode.toRequestValue() -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('숫자 6자리면 값을 만든다', () {
    final code = VerificationCode.tryParse('123456');
    expect(code, isNotNull);
    expect(code!.toRequestValue(), '123456');
  });

  test('앞뒤 공백은 잘라낸다', () {
    final code = VerificationCode.tryParse(' 123456 ');
    expect(code!.toRequestValue(), '123456');
  });

  test('6자리가 아니면 null', () {
    expect(VerificationCode.tryParse('12345'), isNull);
    expect(VerificationCode.tryParse('1234567'), isNull);
  });

  test('숫자가 아닌 문자가 섞이면 null', () {
    expect(VerificationCode.tryParse('12345a'), isNull);
  });

  test('같은 값이면 동등하다', () {
    expect(VerificationCode.tryParse('123456'), VerificationCode.tryParse('123456'));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/model/verification_code_test.dart`
Expected: FAIL — 파일 없음

- [ ] **Step 3: 최소 구현**

```dart
/// 이메일로 받은 6자리 인증코드 값 객체 (CLAUDE.md §4 원칙 3 — 원시값 포장).
final class VerificationCode {
  VerificationCode._(this._value);

  final String _value;

  static final RegExp _pattern = RegExp(r'^\d{6}$');

  /// 형식이 올바르면 인스턴스를, 아니면 `null` 을 돌려준다.
  static VerificationCode? tryParse(String raw) {
    final normalized = raw.trim();
    if (!_pattern.hasMatch(normalized)) {
      return null;
    }
    return VerificationCode._(normalized);
  }

  /// 서버 전송 등 원시 문자열이 필요한 경계에서만 쓴다.
  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) {
    return other is VerificationCode && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/auth/model/verification_code_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add frontend/lib/auth/model/verification_code.dart frontend/test/auth/model/verification_code_test.dart
git commit -m "✨ feat(auth): 6자리 인증코드 값 객체 VerificationCode 추가"
```

---

### Task A3: AuthRepository 인터페이스 + FakeAuthRepository

**Files:**
- Create: `frontend/lib/auth/model/auth_repository.dart`
- Create: `frontend/test/auth/model/fake_auth_repository.dart` (테스트 전용, `lib/`에 두지 않는다)
- Test: `frontend/test/auth/model/fake_auth_repository_test.dart`

**Interfaces:**
- Consumes: `UniversityEmail.toRequestValue()`, `VerificationCode.toRequestValue()`, `Result<void>`(Task A1 Failure 사용)
- Produces: `AuthRepository.requestOtp(UniversityEmail) -> Future<Result<void>>`, `AuthRepository.verifyOtp(UniversityEmail, VerificationCode) -> Future<Result<void>>` — Task A4·A5·A7이 이 타입을 씀

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_auth_repository.dart';

void main() {
  test('기본값은 두 호출 모두 성공한다', () async {
    final repository = FakeAuthRepository();
    final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    final requestResult = await repository.requestOtp(email);
    final verifyResult = await repository.verifyOtp(email, VerificationCode.tryParse('123456')!);

    expect(requestResult.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    expect(verifyResult.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('nextRequestOtpResult를 지정하면 그 결과를 돌려준다', () async {
    final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
    final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/model/fake_auth_repository_test.dart`
Expected: FAIL — `AuthRepository`·`FakeAuthRepository` 없음

- [ ] **Step 3: 인터페이스 구현**

```dart
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 대학 이메일 OTP 가입을 처리한다. 도메인 화이트리스트·재가입 제한 검사는
/// FastAPI Auth Hook(서버)이 가입 시점에 하므로, 여기서는 Supabase Auth
/// 호출만 감싼다(설계 §7.3, ERD.md §11-12).
abstract interface class AuthRepository {
  /// 인증코드 이메일 발송을 요청한다.
  Future<Result<void>> requestOtp(UniversityEmail email);

  /// 인증코드를 검증하고 성공하면 세션을 만든다.
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code);
}
```

- [ ] **Step 4: FakeAuthRepository 구현**

```dart
import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [AuthRepository]. 기본은 항상 성공이고,
/// `nextRequestOtpResult`·`nextVerifyOtpResult` 를 지정해 실패를 흉내 낼 수 있다.
class FakeAuthRepository implements AuthRepository {
  Result<void> nextRequestOtpResult = const Success(null);
  Result<void> nextVerifyOtpResult = const Success(null);
  final List<UniversityEmail> requestedEmails = [];
  final List<VerificationCode> verifiedCodes = [];

  @override
  Future<Result<void>> requestOtp(UniversityEmail email) async {
    requestedEmails.add(email);
    return nextRequestOtpResult;
  }

  @override
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code) async {
    verifiedCodes.add(code);
    return nextVerifyOtpResult;
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `flutter test test/auth/model/fake_auth_repository_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/auth/model/auth_repository.dart frontend/test/auth/model/fake_auth_repository.dart frontend/test/auth/model/fake_auth_repository_test.dart
git commit -m "✨ feat(auth): AuthRepository 인터페이스와 테스트용 FakeAuthRepository 추가"
```

---

### Task A4: SupabaseAuthRepository + Provider

**Files:**
- Create: `frontend/lib/auth/model/supabase_auth_repository.dart`
- Create: `frontend/lib/auth/model/auth_repository_provider.dart`
- Test: `frontend/test/auth/model/supabase_auth_repository_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`(Task A3), `supabase_flutter`의 `SupabaseClient`·`GoTrueClient`
- Produces: `authRepositoryProvider`(Riverpod) — Task A5·A7이 `ref.read(authRepositoryProvider)`로 씀

`SupabaseClient`·`GoTrueClient`는 `final` 클래스가 아니라 `mocktail`로 스텁할 수 있다(supabase_flutter 2.x).

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
import 'package:campus_mate/auth/model/supabase_auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockGoTrueClient auth;
  late SupabaseAuthRepository repository;
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  setUp(() {
    auth = MockGoTrueClient();
    repository = SupabaseAuthRepository(auth);
  });

  test('요청이 성공하면 Success 를 돌려준다', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email'))).thenAnswer((_) async {});

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    verify(() => auth.signInWithOtp(email: 'hong@snu.ac.kr')).called(1);
  });

  test('429 응답이면 RateLimitedFailure', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email')))
        .thenThrow(const AuthException('rate limit', statusCode: '429'));

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });

  test('Auth Hook이 거부하면 SignUpRejectedFailure 에 서버 메시지를 담는다', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email')))
        .thenThrow(const AuthException('허용되지 않은 학교 이메일이에요', statusCode: '422'));

    final result = await repository.requestOtp(email);

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<SignUpRejectedFailure>());
    expect(failure!.toDisplayMessage(), '허용되지 않은 학교 이메일이에요');
  });

  test('검증에 성공하면 Success', () async {
    final code = VerificationCode.tryParse('123456')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenAnswer((_) async => AuthResponse());

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('검증 코드가 틀리면 UnknownFailure', () async {
    final code = VerificationCode.tryParse('000000')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenThrow(const AuthException('Token has expired or is invalid'));

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/model/supabase_auth_repository_test.dart`
Expected: FAIL — `SupabaseAuthRepository` 없음

- [ ] **Step 3: 구현**

```dart
import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AuthRepository]를 Supabase Auth로 구현한다.
class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  @override
  Future<Result<void>> requestOtp(UniversityEmail email) async {
    try {
      await _auth.signInWithOtp(email: email.toRequestValue());
      return const Success(null);
    } on AuthException catch (error) {
      return FailureResult(_toFailure(error));
    }
  }

  @override
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code) async {
    try {
      await _auth.verifyOTP(
        email: email.toRequestValue(),
        token: code.toRequestValue(),
        type: OtpType.email,
      );
      return const Success(null);
    } on AuthException catch (error) {
      return FailureResult(_toFailure(error));
    }
  }

  /// 429는 재전송·요청 한도, 그 외 Auth Hook 거부(422)는 서버 메시지를
  /// 그대로 보여준다. 나머지는 사용자에게 내부 사정을 노출하지 않는다.
  Failure _toFailure(AuthException error) {
    if (error.statusCode == '429') {
      return const RateLimitedFailure();
    }
    if (error.statusCode == '422') {
      return SignUpRejectedFailure(error.message);
    }
    return const UnknownFailure();
  }
}
```

- [ ] **Step 4: Provider 작성**

```dart
import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/supabase_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(Supabase.instance.client.auth);
});
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `flutter test test/auth/model/supabase_auth_repository_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/auth/model/supabase_auth_repository.dart frontend/lib/auth/model/auth_repository_provider.dart frontend/test/auth/model/supabase_auth_repository_test.dart
git commit -m "✨ feat(auth): AuthRepository 를 Supabase Auth OTP 로 구현"
```

---

### Task A5: SignUpUiState·SignUpViewModel — OTP 요청 연결

**Files:**
- Modify: `frontend/lib/auth/viewmodel/sign_up_ui_state.dart`
- Modify: `frontend/lib/auth/viewmodel/sign_up_view_model.dart`
- Modify: `frontend/test/auth/viewmodel/sign_up_ui_state_test.dart`
- Modify: `frontend/test/auth/viewmodel/sign_up_view_model_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider`(Task A4), `Result`(Task A1)
- Produces: `SignUpUiState.otpSentTo`(nullable) — Task A6의 `SignUpScreen`이 내비게이션 트리거로 씀

- [ ] **Step 1: 실패하는 테스트 추가 (UiState)**

```dart
test('기본값은 제출 중이 아니고 에러도 없다', () {
  const state = SignUpUiState();
  expect(state.isSubmitting, isFalse);
  expect(state.errorMessage, isNull);
  expect(state.otpSentTo, isNull);
});

test('제출 중이면 canSubmit 이 false', () {
  final state = SignUpUiState(email: UniversityEmail.tryParse('hong@snu.ac.kr'), isSubmitting: true);
  expect(state.canSubmit, isFalse);
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/viewmodel/sign_up_ui_state_test.dart`
Expected: FAIL — `isSubmitting`·`otpSentTo` 없음

- [ ] **Step 3: SignUpUiState 구현**

```dart
import 'package:campus_mate/auth/model/university_email.dart';

/// 대학 이메일 입력 화면(DESIGN.md 화면 02)의 상태.
class SignUpUiState {
  const SignUpUiState({
    this.emailInput = '',
    this.email,
    this.isSubmitting = false,
    this.errorMessage,
    this.otpSentTo,
  });

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String emailInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final UniversityEmail? email;

  /// OTP 요청이 서버 응답을 기다리는 중인지.
  final bool isSubmitting;

  /// 요청이 실패하면 보여줄 문구.
  final String? errorMessage;

  /// 요청이 성공한 이메일. 화면이 이 값을 보고 인증코드 화면으로 이동한다.
  final UniversityEmail? otpSentTo;

  bool get canSubmit => email != null && !isSubmitting;
}
```

- [ ] **Step 4: 테스트 통과 확인 (UiState)**

Run: `flutter test test/auth/viewmodel/sign_up_ui_state_test.dart`
Expected: PASS

- [ ] **Step 5: 실패하는 테스트 추가 (ViewModel)**

```dart
import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  group('SignUpViewModel', () {
    // ... 기존 3개 테스트는 그대로 ...

    test('제출에 성공하면 otpSentTo 가 채워진다', () async {
      final repository = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');

      await viewModel.submit();

      final state = container.read(signUpViewModelProvider);
      expect(state.otpSentTo?.toRequestValue(), 'hong@snu.ac.kr');
      expect(state.isSubmitting, isFalse);
    });

    test('제출이 실패하면 errorMessage 가 채워진다', () async {
      final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');

      await viewModel.submit();

      final state = container.read(signUpViewModelProvider);
      expect(state.errorMessage, '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요');
      expect(state.otpSentTo, isNull);
    });

    test('acknowledgeNavigation 은 otpSentTo 를 지운다', () async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');
      await viewModel.submit();

      viewModel.acknowledgeNavigation();

      expect(container.read(signUpViewModelProvider).otpSentTo, isNull);
    });
  });
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `flutter test test/auth/viewmodel/sign_up_view_model_test.dart`
Expected: FAIL — `submit()`이 아무 일도 하지 않음

- [ ] **Step 7: SignUpViewModel 구현**

```dart
import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final signUpViewModelProvider = NotifierProvider<SignUpViewModel, SignUpUiState>(
  SignUpViewModel.new,
);

/// 대학 이메일 입력 화면(DESIGN.md 화면 02)의 흐름을 맡는다.
class SignUpViewModel extends Notifier<SignUpUiState> {
  @override
  SignUpUiState build() => const SignUpUiState();

  void changeEmail(String value) {
    state = SignUpUiState(emailInput: value, email: UniversityEmail.tryParse(value));
  }

  /// OTP 발송을 요청한다. 형식이 올바른 이메일이 없으면 아무 일도 하지 않는다.
  Future<void> submit() async {
    final email = state.email;
    if (email == null) {
      return;
    }
    state = SignUpUiState(emailInput: state.emailInput, email: email, isSubmitting: true);
    final result = await ref.read(authRepositoryProvider).requestOtp(email);
    state = result.when(
      onSuccess: (_) => SignUpUiState(emailInput: state.emailInput, email: email, otpSentTo: email),
      onFailure: (failure) => SignUpUiState(
        emailInput: state.emailInput,
        email: email,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  /// 인증코드 화면으로 이동한 뒤 같은 이벤트가 다시 발화하지 않도록 지운다.
  void acknowledgeNavigation() {
    state = SignUpUiState(emailInput: state.emailInput, email: state.email);
  }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `flutter test test/auth/viewmodel/sign_up_view_model_test.dart test/auth/viewmodel/sign_up_ui_state_test.dart`
Expected: PASS

- [ ] **Step 9: 커밋**

```bash
git add frontend/lib/auth/viewmodel/sign_up_ui_state.dart frontend/lib/auth/viewmodel/sign_up_view_model.dart frontend/test/auth/viewmodel/sign_up_ui_state_test.dart frontend/test/auth/viewmodel/sign_up_view_model_test.dart
git commit -m "✨ feat(auth): SignUpViewModel 이 OTP 요청을 실제로 보내도록 구현"
```

---

### Task A6: SignUpScreen — 이동·에러·로딩 반영

**Files:**
- Modify: `frontend/lib/auth/view/sign_up_screen.dart`
- Modify: `frontend/test/auth/view/sign_up_screen_test.dart`

**Interfaces:**
- Consumes: `SignUpUiState.otpSentTo`(Task A5), `AppRoutes.verifyCode`(Task A9)

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
testWidgets('제출 중에는 CTA 가 비활성이다', (tester) async {
  final repository = FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: SignUpScreen()),
    ),
  );
  await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
  await tester.pump();

  await tester.tap(find.text('인증 메일 받기'));
  await tester.pump();

  final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  expect(button.enabled, isFalse);
});

testWidgets('요청이 실패하면 에러 문구를 보여준다', (tester) async {
  final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: SignUpScreen()),
    ),
  );
  await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
  await tester.pump();

  await tester.tap(find.text('인증 메일 받기'));
  await tester.pumpAndSettle();

  expect(find.text('너무 많이 시도했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/view/sign_up_screen_test.dart`
Expected: FAIL — 버튼이 계속 활성, 에러 문구 없음

- [ ] **Step 3: 구현**

```dart
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signUpViewModelProvider);
    final viewModel = ref.read(signUpViewModelProvider.notifier);
    ref.listen(signUpViewModelProvider, _onStateChanged);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: double.infinity,
                height: 124,
                child: Image(
                  image: AssetImage('assets/images/campus-heart-orbit-v1.png'),
                  fit: BoxFit.contain,
                ),
              ),
              Text('대학 이메일로 시작해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('학교 이메일 주소만 가입할 수 있어요.', style: AppTypography.body.copyWith(color: AppColors.body)),
              Text(
                '인증이 끝나면 이메일은 어디에도 공개되지 않아요.',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('대학 이메일', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
              const SizedBox(height: AppSpacing.xs),
              _EmailField(controller: _emailController, onChanged: viewModel.changeEmail),
              const SizedBox(height: AppSpacing.xs),
              const _DomainHint(),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              AppButton(label: '인증 메일 받기', onPressed: state.canSubmit ? viewModel.submit : null),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '계속하면 이용약관과 개인정보처리방침에 동의하게 돼요.',
                style: AppTypography.caption.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onStateChanged(previous, next) {
    final email = next.otpSentTo;
    if (email == null) {
      return;
    }
    ref.read(signUpViewModelProvider.notifier).acknowledgeNavigation();
    context.go(AppRoutes.verifyCode, extra: email);
  }
}
```

`_EmailField`·`_EmailInput`·`_DomainHint` 는 그대로 둔다(변경 없음).

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/auth/view/sign_up_screen_test.dart`
Expected: PASS (기존 4개 + 새 2개)

- [ ] **Step 5: 커밋**

```bash
git add frontend/lib/auth/view/sign_up_screen.dart frontend/test/auth/view/sign_up_screen_test.dart
git commit -m "✨ feat(auth): SignUpScreen 에서 인증코드 화면 이동·에러 표시 연결"
```

---

### Task A7: VerifyCodeUiState·VerifyCodeViewModel — 코드 검증 + 재전송 쿨다운

**Files:**
- Create: `frontend/lib/auth/viewmodel/verify_code_ui_state.dart`
- Create: `frontend/lib/auth/viewmodel/verify_code_view_model.dart`
- Test: `frontend/test/auth/viewmodel/verify_code_ui_state_test.dart`
- Test: `frontend/test/auth/viewmodel/verify_code_view_model_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`(Task A3), `UniversityEmail`, `VerificationCode`(Task A2)
- Produces: `verifyCodeViewModelProvider`(family, `UniversityEmail` 파라미터) — Task A8이 씀

재전송 쿨다운(60초)은 spec §13-38 OTP 정책을 화면에 반영한 것이다. 실제 강제(시간당 5회 한도 포함)는 Part C에서 Supabase Auth 설정이 하고, 여기서는 버튼을 다시 누를 수 없게 안내만 한다. 시간 판단을 테스트할 수 있도록 `now` 를 주입한다.

- [ ] **Step 1: 실패하는 테스트 작성 (UiState)**

```dart
import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기본값은 빈 코드이고 제출할 수 없다', () {
    const state = VerifyCodeUiState();
    expect(state.codeInput, '');
    expect(state.canSubmit, isFalse);
  });

  test('6자리 코드를 넣으면 제출할 수 있다', () {
    const state = VerifyCodeUiState(codeInput: '123456');
    expect(state.canSubmit, isTrue);
  });

  test('제출 중이면 제출할 수 없다', () {
    const state = VerifyCodeUiState(codeInput: '123456', isSubmitting: true);
    expect(state.canSubmit, isFalse);
  });

  test('resendAvailableAt 이 now 이후면 재전송할 수 없다', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);
    final state = VerifyCodeUiState(resendAvailableAt: now.add(const Duration(seconds: 10)));
    expect(state.canResend(now), isFalse);
  });

  test('resendAvailableAt 이 지났으면 재전송할 수 있다', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);
    final state = VerifyCodeUiState(resendAvailableAt: now.subtract(const Duration(seconds: 1)));
    expect(state.canResend(now), isTrue);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/viewmodel/verify_code_ui_state_test.dart`
Expected: FAIL — 파일 없음

- [ ] **Step 3: VerifyCodeUiState 구현**

```dart
/// 인증코드 입력 화면(DESIGN.md 화면 03)의 상태.
class VerifyCodeUiState {
  const VerifyCodeUiState({
    this.codeInput = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.resendAvailableAt,
    this.verified = false,
  });

  final String codeInput;
  final bool isSubmitting;
  final String? errorMessage;

  /// 이 시각 전에는 재전송 버튼을 눌러도 요청을 보내지 않는다(60초 쿨다운, spec §13-38).
  final DateTime? resendAvailableAt;

  /// 검증에 성공했는지. 화면이 이 값을 보고 라우터 재평가를 트리거한다.
  final bool verified;

  bool get canSubmit => codeInput.length == 6 && !isSubmitting;

  bool canResend(DateTime now) {
    final availableAt = resendAvailableAt;
    return availableAt == null || !now.isBefore(availableAt);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인 (UiState)**

Run: `flutter test test/auth/viewmodel/verify_code_ui_state_test.dart`
Expected: PASS

- [ ] **Step 5: 실패하는 테스트 작성 (ViewModel)**

```dart
import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  ProviderContainer buildContainer(FakeAuthRepository repository) {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('올바른 코드를 제출하면 verified 가 true', () async {
    final container = buildContainer(FakeAuthRepository());
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(container.read(verifyCodeViewModelProvider(email)).verified, isTrue);
  });

  test('검증이 실패하면 errorMessage 가 채워진다', () async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(UnknownFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.errorMessage, '알 수 없는 오류가 발생했습니다');
    expect(state.verified, isFalse);
  });

  test('재전송하면 60초 뒤로 resendAvailableAt 이 설정된다', () async {
    final repository = FakeAuthRepository();
    final container = buildContainer(repository);
    final now = DateTime(2026, 1, 1, 12);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..now = () => now;

    await viewModel.resend();

    expect(repository.requestedEmails, [email]);
    expect(container.read(verifyCodeViewModelProvider(email)).resendAvailableAt, now.add(const Duration(seconds: 60)));
  });

  test('쿨다운 중에는 재전송을 보내지 않는다', () async {
    final repository = FakeAuthRepository();
    final container = buildContainer(repository);
    final now = DateTime(2026, 1, 1, 12);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..now = () => now;
    await viewModel.resend();
    repository.requestedEmails.clear();

    await viewModel.resend();

    expect(repository.requestedEmails, isEmpty);
  });
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `flutter test test/auth/viewmodel/verify_code_view_model_test.dart`
Expected: FAIL — `verifyCodeViewModelProvider` 없음

- [ ] **Step 7: VerifyCodeViewModel 구현**

```dart
import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final verifyCodeViewModelProvider = NotifierProvider.family<VerifyCodeViewModel, VerifyCodeUiState, UniversityEmail>(
  VerifyCodeViewModel.new,
);

const _resendCooldown = Duration(seconds: 60);

/// 인증코드 입력 화면(DESIGN.md 화면 03)의 흐름을 맡는다.
class VerifyCodeViewModel extends FamilyNotifier<VerifyCodeUiState, UniversityEmail> {
  @override
  VerifyCodeUiState build(UniversityEmail arg) => const VerifyCodeUiState();

  /// 테스트에서 시각을 고정하기 위한 훅. 기본은 실제 현재 시각.
  DateTime Function() now = DateTime.now;

  void changeCode(String value) {
    state = VerifyCodeUiState(codeInput: value, resendAvailableAt: state.resendAvailableAt);
  }

  Future<void> submit() async {
    final code = VerificationCode.tryParse(state.codeInput);
    if (code == null) {
      return;
    }
    state = VerifyCodeUiState(
      codeInput: state.codeInput,
      isSubmitting: true,
      resendAvailableAt: state.resendAvailableAt,
    );
    final result = await ref.read(authRepositoryProvider).verifyOtp(arg, code);
    state = result.when(
      onSuccess: (_) => VerifyCodeUiState(codeInput: state.codeInput, verified: true),
      onFailure: (failure) => VerifyCodeUiState(
        codeInput: state.codeInput,
        errorMessage: failure.toDisplayMessage(),
        resendAvailableAt: state.resendAvailableAt,
      ),
    );
  }

  /// 쿨다운 중이면 아무 일도 하지 않는다(spec §13-38, 60초 재전송 제한).
  Future<void> resend() async {
    if (!state.canResend(now())) {
      return;
    }
    state = VerifyCodeUiState(
      codeInput: state.codeInput,
      resendAvailableAt: now().add(_resendCooldown),
    );
    await ref.read(authRepositoryProvider).requestOtp(arg);
  }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `flutter test test/auth/viewmodel/verify_code_view_model_test.dart test/auth/viewmodel/verify_code_ui_state_test.dart`
Expected: PASS

- [ ] **Step 9: 커밋**

```bash
git add frontend/lib/auth/viewmodel/verify_code_ui_state.dart frontend/lib/auth/viewmodel/verify_code_view_model.dart frontend/test/auth/viewmodel/verify_code_ui_state_test.dart frontend/test/auth/viewmodel/verify_code_view_model_test.dart
git commit -m "✨ feat(auth): VerifyCodeViewModel 구현 — 코드 검증과 60초 재전송 쿨다운"
```

---

### Task A8: VerifyCodeScreen

**Files:**
- Create: `frontend/lib/auth/view/verify_code_screen.dart`
- Test: `frontend/test/auth/view/verify_code_screen_test.dart`

**Interfaces:**
- Consumes: `verifyCodeViewModelProvider`(Task A7), DESIGN.md §8.5 `otp-field`(6칸, 각 48×56)

`extra`(이메일)가 없이 이 경로에 들어오면(딥링크·새로고침) 로그인 화면으로 되돌린다 — 이 조각 범위에서는 세션 복구 없이 단순 가드로 충분하다.

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  Future<void> pumpScreen(WidgetTester tester, {FakeAuthRepository? repository}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository ?? FakeAuthRepository())],
        child: MaterialApp(home: VerifyCodeScreen(email: email)),
      ),
    );
  }

  testWidgets('안내 문구와 재전송 버튼을 보여준다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('인증코드를 입력해 주세요'), findsOneWidget);
    expect(find.text('재전송'), findsOneWidget);
  });

  testWidgets('앱바가 없다', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('6자리를 모두 입력하기 전에는 CTA 가 비활성이다', (tester) async {
    await pumpScreen(tester);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
    expect(button.enabled, isFalse);
  });

  testWidgets('검증에 실패하면 에러 문구를 보여준다', (tester) async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(UnknownFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('알 수 없는 오류가 발생했습니다'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/auth/view/verify_code_screen_test.dart`
Expected: FAIL — `VerifyCodeScreen` 없음

- [ ] **Step 3: 구현**

```dart
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 인증코드 입력 화면 (DESIGN.md 화면 03).
class VerifyCodeScreen extends ConsumerWidget {
  const VerifyCodeScreen({required this.email, super.key});

  final UniversityEmail email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(verifyCodeViewModelProvider(email));
    final viewModel = ref.read(verifyCodeViewModelProvider(email).notifier);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('인증코드를 입력해 주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('${email.toRequestValue()} 로 보냈어요', style: AppTypography.body.copyWith(color: AppColors.body)),
              const SizedBox(height: AppSpacing.xl),
              _CodeField(onChanged: viewModel.changeCode),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: '재전송',
                variant: AppButtonVariant.text,
                onPressed: () => viewModel.resend(),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              AppButton(label: '확인', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: TextField(
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        maxLength: 6,
        style: AppTypography.body.copyWith(color: AppColors.ink),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, counterText: ''),
      ),
    );
  }
}
```

DESIGN.md §8.5 `otp-field`(6칸 개별 셀)는 §13-109에서 문서·실측 드리프트가 사용자 결정 대기 중이다. 결정 전까지는 단일 `TextField`(6자리 제한)로 최소 구현하고, 결정이 나면 6칸 셀 컴포넌트로 교체한다 — 이 계획 범위 밖의 후속 작업으로 남긴다.

- [ ] **Step 4: 라우터에 `extra` 없이 진입했을 때 가드 추가**

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
```
이 위에 정적 팩토리를 하나 더 두는 대신, `app_router.dart`(Task A9)의 라우트 builder에서 `state.extra`가 `UniversityEmail`이 아니면 `SignUpScreen`으로 바로 보낸다. `VerifyCodeScreen` 자체는 항상 유효한 `email`을 받는다고 가정한다(생성자가 `required`).

- [ ] **Step 5: 테스트 통과 확인**

Run: `flutter test test/auth/view/verify_code_screen_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add frontend/lib/auth/view/verify_code_screen.dart frontend/test/auth/view/verify_code_screen_test.dart
git commit -m "✨ feat(auth): 인증코드 입력 화면 VerifyCodeScreen 구현"
```

---

### Task A9: 라우팅 연결

**Files:**
- Modify: `frontend/lib/core/router/app_routes.dart`
- Modify: `frontend/lib/core/router/app_router.dart`
- Modify: `frontend/lib/core/router/auth_redirect.dart`
- Modify: `frontend/test/core/router/auth_redirect_test.dart`
- Modify: `frontend/test/core/router/app_router_test.dart`

**Interfaces:**
- Consumes: `VerifyCodeScreen`(Task A8)
- Produces: `AppRoutes.verifyCode`, `AppRouter.create({required bool Function() isAuthenticated, Listenable? refreshListenable})` — Task A10이 콜백·리스너를 넘김

기존 `AppRouter.create(isAuthenticated: bool)`을 `bool Function()`로 바꾼다. 로그인 상태가 앱 실행 중에 바뀔 수 있게 됐으므로(Task A10), 라우터 생성 시점에 고정된 값이 아니라 매번 다시 읽어야 한다.

- [ ] **Step 1: 실패하는 테스트 작성 (auth_redirect)**

```dart
test('인증코드 화면에서는 이동시키지 않는다', () {
  const redirect = AuthRedirect(false);
  expect(redirect.resolve(AppRoutes.verifyCode), isNull);
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/core/router/auth_redirect_test.dart`
Expected: FAIL — `AppRoutes.verifyCode` 없음

- [ ] **Step 3: AppRoutes에 경로 추가**

```dart
  /// 인증코드 입력 화면 (로그인 화면에서 이메일과 함께 이동)
  static const String verifyCode = '/verify-code';
```

- [ ] **Step 4: AuthRedirect 수정**

```dart
  /// 로그인하지 않은 사용자는 로그인·인증코드 화면 외에는 갈 수 없다.
  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login || location == AppRoutes.verifyCode) {
      return null;
    }
    return AppRoutes.login;
  }
```

- [ ] **Step 5: 테스트 통과 확인 (auth_redirect)**

Run: `flutter test test/core/router/auth_redirect_test.dart`
Expected: PASS

- [ ] **Step 6: 실패하는 테스트 수정 (app_router — 기존 2개를 콜백 형태로)**

```dart
testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
  final router = AppRouter.create(isAuthenticated: () => false);
  // ... 이하 동일 ...
});

testWidgets('로그인하면 홈 화면이 보인다', (tester) async {
  final router = AppRouter.create(isAuthenticated: () => true);
  // ... 이하 동일 ...
});

testWidgets('extra 없이 인증코드 화면에 진입하면 로그인 화면으로 보낸다', (tester) async {
  final router = AppRouter.create(isAuthenticated: () => false);
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router, theme: AppTheme.light())),
  );
  router.go(AppRoutes.verifyCode);
  await tester.pumpAndSettle();

  expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
});
```

- [ ] **Step 7: 테스트 실패 확인 (app_router)**

Run: `flutter test test/core/router/app_router_test.dart`
Expected: FAIL — `isAuthenticated`가 아직 `bool`

- [ ] **Step 8: AppRouter 구현**

```dart
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({
    required bool Function() isAuthenticated,
    Listenable? refreshListenable,
  }) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        return AuthRedirect(isAuthenticated()).resolve(state.matchedLocation);
      },
      routes: _routes(),
    );
  }

  static List<RouteBase> _routes() {
    return <RouteBase>[
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
      GoRoute(path: AppRoutes.verifyCode, redirect: _verifyCodeGuard, builder: _buildVerifyCode),
      GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
    ];
  }

  /// 이메일 없이 이 경로에 들어오면 로그인부터 다시 시작한다.
  static String? _verifyCodeGuard(BuildContext context, GoRouterState state) {
    return state.extra is UniversityEmail ? null : AppRoutes.login;
  }

  static Widget _buildVerifyCode(BuildContext context, GoRouterState state) {
    return VerifyCodeScreen(email: state.extra as UniversityEmail);
  }
}
```

- [ ] **Step 9: 테스트 통과 확인**

Run: `flutter test test/core/router/`
Expected: PASS

- [ ] **Step 10: 커밋**

```bash
git add frontend/lib/core/router/app_routes.dart frontend/lib/core/router/app_router.dart frontend/lib/core/router/auth_redirect.dart frontend/test/core/router/auth_redirect_test.dart frontend/test/core/router/app_router_test.dart
git commit -m "✨ feat(auth): 인증코드 화면 라우팅 연결, isAuthenticated 를 콜백으로 변경"
```

---

### Task A10: main.dart — 실제 세션 연동

**Files:**
- Create: `frontend/lib/core/supabase/auth_session_listenable.dart`
- Modify: `frontend/lib/main.dart`
- Test: `frontend/test/core/supabase/auth_session_listenable_test.dart`

**Interfaces:**
- Consumes: `AppRouter.create`(Task A9), `supabase_flutter`의 `SupabaseClient`
- Produces: 앱 전체가 실제 로그인 상태를 반영

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late StreamController<AuthState> authStateController;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    authStateController = StreamController<AuthState>.broadcast();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange).thenAnswer((_) => authStateController.stream);
  });

  tearDown(() => authStateController.close());

  test('세션이 없으면 isAuthenticated 는 false', () {
    when(() => auth.currentSession).thenReturn(null);
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);

    expect(listenable.isAuthenticated, isFalse);
  });

  test('세션이 있으면 isAuthenticated 는 true', () {
    when(() => auth.currentSession).thenReturn(MockSession());
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);

    expect(listenable.isAuthenticated, isTrue);
  });

  test('인증 상태가 바뀌면 리스너에 알린다', () async {
    when(() => auth.currentSession).thenReturn(null);
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);
    var notified = false;
    listenable.addListener(() => notified = true);

    authStateController.add(AuthState(AuthChangeEvent.signedIn, MockSession()));
    await Future<void>.delayed(Duration.zero);

    expect(notified, isTrue);
  });
}
```

`import 'dart:async';` 를 테스트 파일 상단에 추가한다(`StreamController` 사용).

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/core/supabase/auth_session_listenable_test.dart`
Expected: FAIL — `AuthSessionListenable` 없음

- [ ] **Step 3: 구현**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 인증 상태가 바뀔 때마다 [notifyListeners] 를 호출해
/// go_router 가 redirect 를 다시 계산하게 한다.
class AuthSessionListenable extends ChangeNotifier {
  AuthSessionListenable(SupabaseClient client) : _auth = client.auth {
    _subscription = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final GoTrueClient _auth;
  late final StreamSubscription<AuthState> _subscription;

  bool get isAuthenticated => _auth.currentSession != null;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/core/supabase/auth_session_listenable_test.dart`
Expected: PASS

- [ ] **Step 5: main.dart 수정**

```dart
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseInitializer.run(SupabaseConfig.fromEnvironment());
  runApp(const ProviderScope(child: CampusMateApp()));
}

/// 앱 루트 위젯. 로그인 상태는 [AuthSessionListenable] 이 실시간으로 알려준다.
class CampusMateApp extends StatefulWidget {
  const CampusMateApp({super.key});

  @override
  State<CampusMateApp> createState() => _CampusMateAppState();
}

class _CampusMateAppState extends State<CampusMateApp> {
  late final AuthSessionListenable _authSession;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionListenable(Supabase.instance.client);
    _router = AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      refreshListenable: _authSession,
    );
  }

  @override
  void dispose() {
    _authSession.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CampusMate',
      theme: AppTheme.light(),
      // 시스템 다크에 끌려가지 않게 고정한다 (DESIGN.md §2.7 — 다크 모드는 MVP 범위 밖)
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
```

- [ ] **Step 6: 전체 테스트 실행**

Run: `flutter test`
Expected: PASS (전체)

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add frontend/lib/core/supabase/auth_session_listenable.dart frontend/lib/main.dart frontend/test/core/supabase/auth_session_listenable_test.dart
git commit -m "✨ feat(auth): 실제 Supabase 세션으로 라우팅 인증 상태 연동"
```

---

## Part B: `backend/` (사용자 GCP 준비 끝난 뒤)

이 조각들은 GCP 프로젝트·Cloud Run·Secret Manager 준비가 끝나야 배포할 수 있다. 코드 작성과 로컬 테스트(Task B1~B7)는 그 전에도 할 수 있다.

**새 의존성** (Task B1 실행 전 사용자 승인 필요): `fastapi`, `uvicorn[standard]`, `httpx`, `pydantic-settings`. `supabase-py` 는 추가하지 않는다 — service_role 키로 PostgREST를 직접 호출하는 데는 이미 필요한 `httpx`만으로 충분하다(YAGNI).

### Task B1: FastAPI 프로젝트 스캐폴딩

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/Dockerfile`
- Create: `backend/.dockerignore`
- Create: `backend/.env.example`
- Create: `backend/app/__init__.py`
- Create: `backend/app/main.py`
- Test: `backend/tests/test_main.py`

**Interfaces:**
- Produces: `app.main:app`(FastAPI 인스턴스), `GET /healthz` — Cloud Run 헬스체크·이후 모든 Task가 씀

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from fastapi.testclient import TestClient
from app.main import app


def test_healthz_returns_ok():
    client = TestClient(app)
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_main.py -v`
Expected: FAIL — 모듈 없음

- [ ] **Step 3: pyproject.toml**

```toml
[project]
name = "campus-mate-backend"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "httpx>=0.27",
    "pydantic-settings>=2.6",
]

[project.optional-dependencies]
dev = ["pytest>=8.3", "pytest-asyncio>=0.24"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
```

- [ ] **Step 4: app/main.py**

```python
from fastapi import FastAPI

app = FastAPI(title="CampusMate Backend")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd backend && pip install -e ".[dev]" && python -m pytest tests/test_main.py -v`
Expected: PASS

- [ ] **Step 6: Dockerfile**

```dockerfile
FROM python:3.13-slim

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir .

COPY app ./app

# Cloud Run 이 $PORT 로 리스닝 포트를 알려준다 — 하드코딩하지 않는다.
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
```

- [ ] **Step 7: .dockerignore**

```
tests/
.venv/
__pycache__/
*.pyc
.env
```

- [ ] **Step 8: .env.example**

```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
AUTH_HOOK_SIGNING_SECRET=
```

- [ ] **Step 9: 커밋**

```bash
git add backend/pyproject.toml backend/Dockerfile backend/.dockerignore backend/.env.example backend/app/__init__.py backend/app/main.py backend/tests/test_main.py
git commit -m "🔧 chore(backend): FastAPI 프로젝트 뼈대와 헬스체크 엔드포인트"
```

---

### Task B2: 설정 로딩

**Files:**
- Create: `backend/app/settings.py`
- Test: `backend/tests/test_settings.py`

**Interfaces:**
- Produces: `Settings`(pydantic-settings) — Task B5·B7이 씀

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import pytest
from app.settings import Settings


def test_settings_reads_from_env(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-key")
    monkeypatch.setenv("AUTH_HOOK_SIGNING_SECRET", "whsec_test")

    settings = Settings()

    assert settings.supabase_url == "https://example.supabase.co"
    assert settings.postgrest_url == "https://example.supabase.co/rest/v1"


def test_settings_requires_all_values(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    with pytest.raises(Exception):
        Settings(_env_file=None)
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_settings.py -v`
Expected: FAIL — 모듈 없음

- [ ] **Step 3: 구현**

```python
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    auth_hook_signing_secret: str

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && python -m pytest tests/test_settings.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/app/settings.py backend/tests/test_settings.py
git commit -m "✨ feat(backend): 환경변수 기반 Settings 추가"
```

---

### Task B3: Standard Webhooks 서명 검증

**Files:**
- Create: `backend/app/webhook_signature.py`
- Test: `backend/tests/test_webhook_signature.py`

**Interfaces:**
- Produces: `verify_webhook_signature(secret, webhook_id, timestamp, body, signature_header) -> bool` — Task B7이 씀

Supabase Auth Hook은 [Standard Webhooks](https://www.standardwebhooks.com) 규격을 쓴다. 서명 대상 문자열은 `"{webhook_id}.{timestamp}.{body}"`이고, 시크릿은 `whsec_` 접두사를 뗀 뒤 base64 디코딩해 HMAC-SHA256 키로 쓴다. `signature_header`는 `v1,<base64>` 형태이고 공백으로 여러 개가 올 수 있다(키 회전 대비) — 하나라도 일치하면 통과시킨다.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import base64
import hashlib
import hmac

from app.webhook_signature import verify_webhook_signature


def _sign(secret: str, webhook_id: str, timestamp: str, body: bytes) -> str:
    key = base64.b64decode(secret.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    digest = hmac.new(key, signed_content, hashlib.sha256).digest()
    return f"v1,{base64.b64encode(digest).decode()}"


def test_valid_signature_passes():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    body = b'{"type":"test"}'
    signature = _sign(secret, "msg_1", "1700000000", body)

    assert verify_webhook_signature(secret, "msg_1", "1700000000", body, signature) is True


def test_tampered_body_fails():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    signature = _sign(secret, "msg_1", "1700000000", b'{"type":"test"}')

    assert verify_webhook_signature(secret, "msg_1", "1700000000", b'{"type":"tampered"}', signature) is False


def test_one_matching_signature_among_several_passes():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    body = b'{"type":"test"}'
    valid = _sign(secret, "msg_1", "1700000000", body)

    assert verify_webhook_signature(secret, "msg_1", "1700000000", body, f"v0,garbage {valid}") is True
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_webhook_signature.py -v`
Expected: FAIL — 모듈 없음

- [ ] **Step 3: 구현**

```python
import base64
import hashlib
import hmac


def verify_webhook_signature(
    secret: str,
    webhook_id: str,
    timestamp: str,
    body: bytes,
    signature_header: str,
) -> bool:
    """Standard Webhooks 서명을 검증한다. 공백으로 구분된 서명 중 하나라도
    맞으면 통과시킨다(발신 측 키 회전 대비, Standard Webhooks 규격)."""
    key = base64.b64decode(secret.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    expected = hmac.new(key, signed_content, hashlib.sha256).digest()
    expected_encoded = base64.b64encode(expected).decode()

    for candidate in signature_header.split(" "):
        _, _, value = candidate.partition(",")
        if hmac.compare_digest(value, expected_encoded):
            return True
    return False
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && python -m pytest tests/test_webhook_signature.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/app/webhook_signature.py backend/tests/test_webhook_signature.py
git commit -m "✨ feat(backend): Standard Webhooks HMAC 서명 검증 구현"
```

---

### Task B4: Auth Hook 요청·응답 스키마

**Files:**
- Create: `backend/app/auth_hooks/__init__.py`
- Create: `backend/app/auth_hooks/schemas.py`
- Test: `backend/tests/test_auth_hooks_schemas.py`

**Interfaces:**
- Produces: `BeforeUserCreatedPayload`, `HookDecision`(허용/거부) — Task B5·B7이 씀

Supabase의 Before User Created 훅 페이로드는 `{"user_id": "...", "claims": {...}, "user": {"id": "...", "email": "..."}}` 형태로 온다(id는 Supabase가 미리 만들어 둔 값). 거부 응답은 `{"decision": "reject", "message": "..."}`, 허용은 `{"decision": "continue"}`이다.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision


def test_payload_parses_user_id_and_email():
    payload = BeforeUserCreatedPayload.model_validate(
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@SNU.ac.kr"}}
    )

    assert str(payload.user_id) == "11111111-1111-1111-1111-111111111111"
    assert payload.email_domain == "snu.ac.kr"


def test_reject_decision_serializes_with_message():
    decision = HookDecision.reject("허용되지 않은 학교 이메일이에요")

    assert decision.model_dump() == {"decision": "reject", "message": "허용되지 않은 학교 이메일이에요"}


def test_continue_decision_has_no_message():
    decision = HookDecision.allow()

    assert decision.model_dump() == {"decision": "continue", "message": None}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_auth_hooks_schemas.py -v`
Expected: FAIL — 모듈 없음

- [ ] **Step 3: 구현**

```python
from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr


class _HookUser(BaseModel):
    email: EmailStr


class BeforeUserCreatedPayload(BaseModel):
    user_id: UUID
    user: _HookUser

    @property
    def email(self) -> str:
        return self.user.email.lower()

    @property
    def email_domain(self) -> str:
        return self.email.rsplit("@", 1)[-1]


class HookDecision(BaseModel):
    decision: Literal["continue", "reject"]
    message: str | None = None

    @classmethod
    def allow(cls) -> "HookDecision":
        return cls(decision="continue")

    @classmethod
    def reject(cls, message: str) -> "HookDecision":
        return cls(decision="reject", message=message)
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && python -m pytest tests/test_auth_hooks_schemas.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/app/auth_hooks/__init__.py backend/app/auth_hooks/schemas.py backend/tests/test_auth_hooks_schemas.py
git commit -m "✨ feat(backend): Auth Hook 요청·응답 스키마 추가"
```

---

### Task B5: 가입 정책 — 도메인 화이트리스트·재가입 제한 검사

**Files:**
- Create: `backend/app/signup_policy.py`
- Test: `backend/tests/test_signup_policy.py`

**Interfaces:**
- Consumes: `Settings`(Task B2)
- Produces: `SignupPolicy.find_university_id`, `SignupPolicy.is_blocked`, `SignupPolicy.create_pending_profile` — Task B7이 씀

`signup_blocks.email_hmac`은 `bytea`라 PostgREST 필터에는 `\x<hex>` 리터럴로 보낸다. HMAC 키는 `AUTH_HOOK_SIGNING_SECRET`과 별개로 두지 않고, 이 조각에서는 같은 시크릿을 재사용한다 — `signup_blocks`에 실제로 쓰는 조각 6에서 키 분리가 필요해지면 그때 나눈다(YAGNI).

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import httpx
import pytest
from app.signup_policy import SignupPolicy


@pytest.fixture
def transport_factory():
    def _factory(handler):
        return httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return _factory


async def test_find_university_id_returns_id_when_domain_known(transport_factory):
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["domain"] == "eq.snu.ac.kr"
        return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])

    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    result = await policy.find_university_id("snu.ac.kr")

    assert result == "22222222-2222-2222-2222-222222222222"


async def test_find_university_id_returns_none_when_domain_unknown(transport_factory):
    handler = lambda request: httpx.Response(200, json=[])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.find_university_id("unknown.ac.kr") is None


async def test_is_blocked_true_when_row_exists(transport_factory):
    handler = lambda request: httpx.Response(200, json=[{"blocked_until": "2027-01-01T00:00:00Z"}])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.is_blocked(b"\x01\x02") is True


async def test_is_blocked_false_when_no_row(transport_factory):
    handler = lambda request: httpx.Response(200, json=[])
    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    assert await policy.is_blocked(b"\x01\x02") is False


async def test_create_pending_profile_posts_id_and_university(transport_factory):
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["json"] = request.content
        return httpx.Response(201)

    policy = SignupPolicy("https://x.supabase.co/rest/v1", "service-key", transport_factory(handler))

    await policy.create_pending_profile("33333333-3333-3333-3333-333333333333", "22222222-2222-2222-2222-222222222222")

    assert b"33333333-3333-3333-3333-333333333333" in captured["json"]
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_signup_policy.py -v`
Expected: FAIL — 모듈 없음

- [ ] **Step 3: 구현**

```python
import httpx


class SignupPolicy:
    """도메인 화이트리스트·재가입 제한 검사와 pending 프로필 생성을 맡는다
    (spec §7.3, ERD.md §11-12). service_role 키로 PostgREST 를 직접 호출한다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def find_university_id(self, domain: str) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/university_email_domains",
            params={"domain": f"eq.{domain}", "select": "university_id"},
            headers=self._headers,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["university_id"] if rows else None

    async def is_blocked(self, email_hmac: bytes) -> bool:
        hex_literal = f"\\x{email_hmac.hex()}"
        response = await self._client.get(
            f"{self._postgrest_url}/signup_blocks",
            params={"email_hmac": f"eq.{hex_literal}", "blocked_until": "gt.now()", "select": "blocked_until"},
            headers=self._headers,
        )
        response.raise_for_status()
        return len(response.json()) > 0

    async def create_pending_profile(self, user_id: str, university_id: str) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/profiles",
            json={"id": user_id, "university_id": university_id},
            headers={**self._headers, "Prefer": "return=minimal"},
        )
        response.raise_for_status()
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && python -m pytest tests/test_signup_policy.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/app/signup_policy.py backend/tests/test_signup_policy.py
git commit -m "✨ feat(backend): 도메인 화이트리스트·재가입 제한 검사, pending 프로필 생성"
```

---

### Task B6: 이메일 HMAC 계산

**Files:**
- Modify: `backend/app/signup_policy.py`
- Modify: `backend/tests/test_signup_policy.py`

**Interfaces:**
- Produces: `hash_email(secret, email) -> bytes` — Task B7이 씀

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from app.signup_policy import hash_email


def test_hash_email_is_deterministic():
    assert hash_email("secret", "hong@snu.ac.kr") == hash_email("secret", "hong@snu.ac.kr")


def test_hash_email_differs_by_secret():
    assert hash_email("secret-a", "hong@snu.ac.kr") != hash_email("secret-b", "hong@snu.ac.kr")


def test_hash_email_normalizes_case():
    assert hash_email("secret", "HONG@SNU.AC.KR") == hash_email("secret", "hong@snu.ac.kr")
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_signup_policy.py -k hash_email -v`
Expected: FAIL — `hash_email` 없음

- [ ] **Step 3: 구현 (파일 맨 위에 추가)**

```python
import hashlib
import hmac


def hash_email(secret: str, email: str) -> bytes:
    """탈퇴 후 재가입 제한 대조용 HMAC. 원본 이메일은 저장하지 않는다
    (ERD.md `signup_blocks`, §11-12)."""
    return hmac.new(secret.encode(), email.strip().lower().encode(), hashlib.sha256).digest()
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && python -m pytest tests/test_signup_policy.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/app/signup_policy.py backend/tests/test_signup_policy.py
git commit -m "✨ feat(backend): 재가입 제한 대조용 이메일 HMAC 함수 추가"
```

---

### Task B7: Auth Hook 엔드포인트

**Files:**
- Create: `backend/app/auth_hooks/router.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_auth_hooks_router.py`

**Interfaces:**
- Consumes: `verify_webhook_signature`(B3), `BeforeUserCreatedPayload`·`HookDecision`(B4), `SignupPolicy`·`hash_email`(B5·B6), `Settings`(B2)
- Produces: `POST /hooks/before-user-created` — Supabase가 호출하는 최종 엔드포인트

서명이 틀리면 401, 도메인이 화이트리스트에 없거나 재가입 제한에 걸리면 `HookDecision.reject`를 담아 200으로 돌려준다(Supabase Auth Hook 규격 — 거부도 200 + reject 바디).

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import base64
import hashlib
import hmac
import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.settings import Settings
import app.auth_hooks.router as router_module


SECRET = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()


def _sign(webhook_id: str, timestamp: str, body: bytes) -> str:
    key = base64.b64decode(SECRET.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    digest = hmac.new(key, signed_content, hashlib.sha256).digest()
    return f"v1,{base64.b64encode(digest).decode()}"


@pytest.fixture(autouse=True)
def settings_override(monkeypatch):
    monkeypatch.setattr(
        router_module,
        "get_settings",
        lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret=SECRET,
        ),
    )


def _post_hook(client: TestClient, body: dict, mock_transport: httpx.MockTransport):
    raw_body = json.dumps(body).encode()
    headers = {
        "webhook-id": "msg_1",
        "webhook-timestamp": "1700000000",
        "webhook-signature": _sign("msg_1", "1700000000", raw_body),
    }
    router_module._client_override = httpx.AsyncClient(transport=mock_transport)
    return client.post("/hooks/before-user-created", content=raw_body, headers=headers)


def test_allows_known_domain_and_creates_profile():
    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        if "signup_blocks" in str(request.url):
            return httpx.Response(200, json=[])
        return httpx.Response(201)

    client = TestClient(app)
    response = _post_hook(
        client,
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.status_code == 200
    assert response.json() == {"decision": "continue", "message": None}


def test_rejects_unknown_domain():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@unknown.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.status_code == 200
    assert response.json()["decision"] == "reject"


def test_rejects_blocked_email():
    def handler(request: httpx.Request) -> httpx.Response:
        if "university_email_domains" in str(request.url):
            return httpx.Response(200, json=[{"university_id": "22222222-2222-2222-2222-222222222222"}])
        return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00Z"}])

    client = TestClient(app)
    response = _post_hook(
        client,
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@snu.ac.kr"}},
        httpx.MockTransport(handler),
    )

    assert response.json()["decision"] == "reject"


def test_invalid_signature_returns_401():
    client = TestClient(app)
    response = client.post(
        "/hooks/before-user-created",
        content=b'{"user_id":"11111111-1111-1111-1111-111111111111","user":{"email":"hong@snu.ac.kr"}}',
        headers={"webhook-id": "msg_1", "webhook-timestamp": "1700000000", "webhook-signature": "v1,invalid"},
    )

    assert response.status_code == 401
```

`router_module._client_override`는 테스트가 `httpx.AsyncClient`를 주입하기 위한 훅이다 — 아래 구현에서 실제 사용한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && python -m pytest tests/test_auth_hooks_router.py -v`
Expected: FAIL — 라우터 없음

- [ ] **Step 3: 구현**

```python
from functools import lru_cache

import httpx
from fastapi import APIRouter, HTTPException, Request

from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision
from app.settings import Settings
from app.signup_policy import SignupPolicy, hash_email
from app.webhook_signature import verify_webhook_signature

router = APIRouter()

# 테스트가 실제 Supabase 대신 목 트랜스포트를 주입할 수 있게 하는 훅.
# 프로덕션에서는 None 이라 매 요청마다 새 AsyncClient 를 만든다.
_client_override: httpx.AsyncClient | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


@router.post("/hooks/before-user-created")
async def before_user_created(request: Request) -> HookDecision:
    settings = get_settings()
    body = await request.body()
    _verify_signature_or_raise(settings, request.headers, body)

    payload = BeforeUserCreatedPayload.model_validate_json(body)
    client = _client_override or httpx.AsyncClient()
    policy = SignupPolicy(settings.postgrest_url, settings.supabase_service_role_key, client)

    university_id = await policy.find_university_id(payload.email_domain)
    if university_id is None:
        return HookDecision.reject("허용되지 않은 학교 이메일이에요")

    email_hmac = hash_email(settings.auth_hook_signing_secret, payload.email)
    if await policy.is_blocked(email_hmac):
        return HookDecision.reject("재가입이 제한된 이메일이에요")

    await policy.create_pending_profile(str(payload.user_id), university_id)
    return HookDecision.allow()


def _verify_signature_or_raise(settings: Settings, headers, body: bytes) -> None:
    webhook_id = headers.get("webhook-id", "")
    timestamp = headers.get("webhook-timestamp", "")
    signature = headers.get("webhook-signature", "")
    valid = verify_webhook_signature(settings.auth_hook_signing_secret, webhook_id, timestamp, body, signature)
    if not valid:
        raise HTTPException(status_code=401, detail="invalid signature")
```

- [ ] **Step 4: main.py에 라우터 등록**

```python
from fastapi import FastAPI

from app.auth_hooks.router import router as auth_hooks_router

app = FastAPI(title="CampusMate Backend")
app.include_router(auth_hooks_router)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd backend && python -m pytest -v`
Expected: PASS (전체)

- [ ] **Step 6: 커밋**

```bash
git add backend/app/auth_hooks/router.py backend/app/main.py backend/tests/test_auth_hooks_router.py
git commit -m "✨ feat(backend): Before User Created Auth Hook 엔드포인트 조립"
```

---

### Task B8: Cloud Run 배포 절차 문서화

**Files:**
- Create: `backend/DEPLOY.md`

**Interfaces:** 없음(문서, 실행은 사용자 승인 후)

- [ ] **Step 1: 배포 문서 작성**

```markdown
# backend 배포 — Google Cloud Run (asia-northeast3, 서울)

**아래 명령은 GCP 프로젝트가 준비되고 사용자가 승인한 뒤에만 실행한다** (spec §13-37).

## 1. 최초 1회

​```bash
gcloud config set project <PROJECT_ID>
gcloud services enable run.googleapis.com secretmanager.googleapis.com

# 시크릿 등록 (값은 여기 문서에 남기지 않는다)
echo -n "<service-role-key>" | gcloud secrets create supabase-service-role-key --data-file=-
echo -n "<hook-signing-secret>" | gcloud secrets create auth-hook-signing-secret --data-file=-
​```

## 2. 배포

​```bash
cd backend
gcloud run deploy campus-mate-backend \
  --source . \
  --region asia-northeast3 \
  --no-allow-unauthenticated \
  --set-env-vars SUPABASE_URL=<project-url> \
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest \
  --set-secrets AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest
​```

`--no-allow-unauthenticated` 로 배포하고, Supabase Auth Hook 설정에서 서비스 계정 기반 호출을 쓴다(Part C Task C3).

## 3. 배포 확인

​```bash
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  https://<서비스 URL>/healthz
​```

`{"status":"ok"}` 가 나오면 성공.
```

- [ ] **Step 2: 커밋**

```bash
git add backend/DEPLOY.md
git commit -m "📝 docs(backend): Cloud Run 배포 절차 문서화"
```

---

## Part C: Supabase 설정 (사용자 승인 후)

### Task C1: `signup_blocks` 마이그레이션

**Files:**
- Create: `supabase/migrations/<timestamp>_create_signup_blocks.sql` (파일명은 저장소 루트에서 `supabase migration new create_signup_blocks` 로 만든다)

**Interfaces:** 없음(스키마) — Part B의 `SignupPolicy`가 이 테이블을 읽는다

`signup_blocks`는 ERD.md에 "조각6 제안"으로 적혀 있지만, Auth Hook(조각 1a)이 가입 시점에 **읽어야** 하므로 테이블 자체는 지금 만든다. 쓰기(탈퇴 시 행 추가)는 조각 6에서 채운다 — 지금은 빈 테이블로 시작해도 안전하다(행이 없으면 `is_blocked`는 항상 `false`).

- [ ] **Step 1: 마이그레이션 파일 작성**

```sql
-- 조각 1a: 재가입 제한 표. 쓰기(탈퇴 시 삽입)는 조각 6에서 채운다 — 이 조각은
-- Auth Hook 이 가입 시점에 읽기만 한다. 관계가 없는 독립 테이블이다(ERD.md §11-12).
create table public.signup_blocks (
  -- 원본 이메일을 남기지 않으려고 FastAPI 환경변수 키로 계산한 HMAC 만 저장한다.
  email_hmac bytea primary key,
  -- 탈퇴 요청 시각 + 2개월. 정지 중 탈퇴는 infinity 로 기간 없이 막는다(ERD.md §11-22).
  blocked_until timestamptz not null
);

comment on table public.signup_blocks is '탈퇴 후 재가입 제한. FastAPI Auth Hook 전용, 클라이언트 접근 없음';

-- RLS: 클라이언트는 존재 자체를 몰라도 된다. anon·authenticated 정책을 두지 않는다(default deny).
alter table public.signup_blocks enable row level security;

revoke all on table public.signup_blocks from anon, authenticated, service_role;
grant select, insert, update, delete on table public.signup_blocks to service_role;
```

- [ ] **Step 2: 커밋 (아직 클라우드 적용 전 — 파일만)**

```bash
git add supabase/migrations/<timestamp>_create_signup_blocks.sql
git commit -m "🗃️ db(slice1): signup_blocks 테이블 마이그레이션 작성"
```

- [ ] **Step 3: 클라우드 적용 (사용자 승인 필요)**

사용자 승인 후 MCP `apply_migration`에 이 파일 내용을 그대로 넘긴다(`docs/SUPABASE.md` §4). 적용 직후 `get_advisors`(security·performance)로 경고 0건을 확인한다.

---

### Task C2: pgTAP 회귀 테스트 추가

**Files:**
- Modify: `supabase/tests/rls_slice1_test.sql`

**Interfaces:** 없음(SQL 테스트)

- [ ] **Step 1: `plan(30)` 을 `plan(33)` 으로 바꾸고 "5. 탈퇴 cascade" 앞에 새 절 추가**

```sql
-- 4b. signup_blocks 접근 제어 (postgres) ------------------------------------

insert into public.signup_blocks (email_hmac, blocked_until)
  values ('\x0102030405'::bytea, now() + interval '1 day');

set role anon;

select throws_ok(
  $$select * from public.signup_blocks$$,
  '42501', null,
  'anon 은 signup_blocks 를 읽을 수 없다'
);

reset role;
set role authenticated;

select throws_ok(
  $$select * from public.signup_blocks$$,
  '42501', null,
  'authenticated 도 signup_blocks 를 읽을 수 없다'
);

reset role;

select lives_ok(
  $$select * from public.signup_blocks where email_hmac = '\x0102030405'::bytea$$,
  'service_role 은 signup_blocks 를 읽을 수 있다'
);
```

`plan(30)`을 `plan(33)`으로 바꾸는 이유: 위 3개 `throws_ok`/`lives_ok`가 새 검증이다.

- [ ] **Step 2: 커밋**

```bash
git add supabase/tests/rls_slice1_test.sql
git commit -m "✅ test(slice1): signup_blocks RLS 회귀 테스트 추가"
```

Docker 로컬 스택이 없어 `supabase test db`는 아직 실행하지 않는다(파일 상단 주석과 동일한 제약, 2026-09-13 결정) — 로컬 스택이 생기면 그때 실행해 통과를 확인한다.

---

### Task C3: Supabase Auth 설정 (사용자 승인 후 수동)

**Files:** 없음(Supabase Dashboard 또는 Management API 조작) — 문서화된 MCP 도구가 없어 체크리스트로 남긴다

**Interfaces:** 없음

- [ ] **Step 1: OTP 설정** — Dashboard → Authentication → Providers → Email
  - OTP expiry: `600`초 (spec §13-38)
  - Rate limit: 시간당 5회로 제한(Dashboard의 "Rate Limits" 항목, 이메일당)
- [ ] **Step 2: Auth Hook 등록** — Dashboard → Authentication → Hooks → Before User Created
  - Hook type: HTTPS
  - URL: Task B8에서 배포한 Cloud Run 서비스의 `/hooks/before-user-created`
  - Secret: `AUTH_HOOK_SIGNING_SECRET`과 같은 값(Supabase가 발급하는 `whsec_...` 값을 그대로 Secret Manager에 반영)
  - Cloud Run이 `--no-allow-unauthenticated`이므로 Supabase 쪽에서 서비스 계정 인증 헤더를 함께 보내도록 설정한다(Supabase Auth Hooks 문서의 "Adding Custom Headers" 참고)
- [ ] **Step 3: 확인** — 테스트 이메일(화이트리스트 도메인)로 가입을 시도해 인증코드가 오는지, 화이트리스트에 없는 도메인으로는 422 거부가 오는지 확인
- [ ] **Step 4: 확인 결과를 사용자에게 보고** — 스크린샷 없이 결과(성공/실패, 받은 에러 메시지)만 텍스트로 보고한다

---

## Self-Review 체크리스트 (구현 착수 전 재확인)

- [ ] spec §3.1 조각 1a 정의(이메일 OTP + Auth Hook)가 Part A+B+C 전체로 커버되는가 — Yes
- [ ] spec §13-38 OTP 정책(10분·60초·시간당 5회)이 반영됐는가 — 10분·시간당 5회는 Part C(Supabase 설정), 60초는 Part A(`VerifyCodeViewModel` 쿨다운)
- [ ] spec §13-39 메일 발신(1a는 기본 메일)이 반영됐는가 — 이 계획 어디에도 커스텀 SMTP 코드가 없음, 반영됨
- [ ] ERD.md §11-12(재가입 제한을 Auth Hook이 검사)가 반영됐는가 — Task B5·B7
- [ ] 플레이스홀더 스캔 — "TBD"·"나중에 구현"·"적절히 처리" 문구 없음(직접 검색 완료)
- [ ] 타입 일관성 — `AuthRepository.requestOtp`/`verifyOtp` 시그니처가 Task A3·A4·A5·A7에서 동일, `SignupPolicy`의 메서드명이 Task B5·B7에서 동일
