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
/// Riverpod 3.x 의 family notifier 는 인자를 생성자로 받는다(2.x `FamilyNotifier.build(arg)` 방식이 아니다).
class VerifyCodeViewModel extends Notifier<VerifyCodeUiState> {
  VerifyCodeViewModel(this._email);

  final UniversityEmail _email;

  @override
  VerifyCodeUiState build() => const VerifyCodeUiState();

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
    final result = await ref.read(authRepositoryProvider).verifyOtp(_email, code);
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
    await ref.read(authRepositoryProvider).requestOtp(_email);
  }
}
