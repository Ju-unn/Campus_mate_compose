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
