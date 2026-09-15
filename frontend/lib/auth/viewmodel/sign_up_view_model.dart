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

  /// 인증 메일 발송은 서버(Auth Hook) 연동 작업에서 채운다.
  void submit() {}
}
