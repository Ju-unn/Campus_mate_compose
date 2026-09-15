import 'package:campus_mate/auth/model/university_email.dart';

/// 대학 이메일 입력 화면(DESIGN.md 화면 02)의 상태.
class SignUpUiState {
  const SignUpUiState({this.emailInput = '', this.email});

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String emailInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final UniversityEmail? email;

  bool get canSubmit => email != null;
}
