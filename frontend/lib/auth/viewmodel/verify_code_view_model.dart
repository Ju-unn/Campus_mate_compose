import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final verifyCodeViewModelProvider = NotifierProvider.family<VerifyCodeViewModel, VerifyCodeUiState, UniversityEmail>(
  VerifyCodeViewModel.new,
);

const _resendCooldown = Duration(seconds: 60);

/// 코드 유효 시간(pen 값, 2026-09-23 사용자 결정).
/// Supabase Auth 의 `otp_expiry`(supabase/config.toml 300초)와 **같아야 한다** —
/// 여기만 줄이면 화면은 만료라고 말하는데 서버는 코드를 받아 준다.
const codeLifetime = Duration(minutes: 5);

/// 인증코드 입력 화면(DESIGN.md 화면 03)의 흐름을 맡는다.
/// Riverpod 3.x 의 family notifier 는 인자를 생성자로 받는다(2.x `FamilyNotifier.build(arg)` 방식이 아니다).
class VerifyCodeViewModel extends Notifier<VerifyCodeUiState> {
  VerifyCodeViewModel(this._email);

  final UniversityEmail _email;

  /// 테스트에서 시각을 고정하기 위한 훅. 기본은 실제 현재 시각.
  /// 필드 초기화가 [build] 보다 먼저라 여기서도 쓸 수 있다.
  DateTime Function() now = DateTime.now;

  @override
  // 이 화면은 로그인 화면이 코드를 보낸 직후에 열린다 — 화면이 열린 때를 보낸 때로 본다.
  // 첫 계산은 훅을 갈아끼우기 **전에** 돌아가므로 테스트에서 고정할 수 없다(재전송 쪽은 고정된다).
  VerifyCodeUiState build() => VerifyCodeUiState(codeExpiresAt: now().add(codeLifetime));

  void changeCode(String value) {
    state = VerifyCodeUiState(
      codeInput: value,
      resendAvailableAt: state.resendAvailableAt,
      codeExpiresAt: state.codeExpiresAt,
    );
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
      codeExpiresAt: state.codeExpiresAt,
    );
    final result = await ref.read(authRepositoryProvider).verifyOtp(_email, code);
    state = result.when(
      onSuccess: (_) => VerifyCodeUiState(codeInput: state.codeInput, verified: true),
      onFailure: (failure) => VerifyCodeUiState(
        codeInput: state.codeInput,
        errorMessage: failure.toDisplayMessage(),
        resendAvailableAt: state.resendAvailableAt,
        codeExpiresAt: state.codeExpiresAt,
        isCodeRejected: failure is WrongCodeFailure,
      ),
    );
  }

  /// 쿨다운 중이면 아무 일도 하지 않는다(spec §13-38, 60초 재전송 제한).
  Future<void> resend() async {
    if (!state.canResend(now())) {
      return;
    }
    // 새 코드가 오므로 입력칸을 비운다 — 안 비우면 예전 코드가 남아 그대로 제출된다.
    state = VerifyCodeUiState(
      resendAvailableAt: now().add(_resendCooldown),
      codeExpiresAt: now().add(codeLifetime),
    );
    await ref.read(authRepositoryProvider).requestOtp(_email);
  }
}
