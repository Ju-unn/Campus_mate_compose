import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  test('기본값은 빈 코드이고 제출할 수 없다', () {
    const state = VerifyCodeUiState();
    expect(state.codeInput, '');
    expect(state.canSubmit(now), isFalse);
  });

  test('6자리 코드를 넣으면 제출할 수 있다', () {
    const state = VerifyCodeUiState(codeInput: '123456');
    expect(state.canSubmit(now), isTrue);
  });

  test('제출 중이면 제출할 수 없다', () {
    const state = VerifyCodeUiState(codeInput: '123456', isSubmitting: true);
    expect(state.canSubmit(now), isFalse);
  });

  test('기한이 지난 코드는 제출할 수 없다', () {
    // 보내 봐야 서버가 "코드가 맞지 않아요" 로 돌려준다 — 틀린 코드처럼 보이면 안 된다.
    final state = VerifyCodeUiState(
      codeInput: '123456',
      codeExpiresAt: now.subtract(const Duration(seconds: 1)),
    );
    expect(state.canSubmit(now), isFalse);
    expect(state.isExpired(now), isTrue);
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
