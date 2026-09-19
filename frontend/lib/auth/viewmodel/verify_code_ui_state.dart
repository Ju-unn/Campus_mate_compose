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
