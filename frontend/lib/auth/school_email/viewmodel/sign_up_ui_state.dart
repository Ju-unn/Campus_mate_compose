import 'package:campus_mate/auth/school_email/model/data/university_email.dart';
import 'package:campus_mate/common/failure.dart';

/// 대학 이메일 입력 화면(DESIGN.md 화면 02)의 상태.
class SignUpUiState {
  const SignUpUiState({
    this.emailInput = '',
    this.email,
    this.isSubmitting = false,
    this.error,
    this.otpSentTo,
  });

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String emailInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final UniversityEmail? email;

  /// OTP 요청이 서버 응답을 기다리는 중인지.
  final bool isSubmitting;

  /// 요청이 실패한 종류. 화면이 `context.errorText` 로 글자를 만들어 보인다.
  final Failure? error;

  /// 요청이 성공한 이메일. 화면이 이 값을 보고 인증코드 화면으로 이동한다.
  final UniversityEmail? otpSentTo;

  bool get canSubmit => email != null && !isSubmitting;
}
