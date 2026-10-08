/// 인증코드 입력 화면(DESIGN.md 화면 03)의 상태.
class VerifyCodeUiState {
  const VerifyCodeUiState({
    this.codeInput = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.errorHint,
    this.canChooseAnotherEmail = false,
    this.resendAvailableAt,
    this.codeExpiresAt,
    this.isCodeRejected = false,
    this.verified = false,
  });

  final String codeInput;
  final bool isSubmitting;
  final String? errorMessage;

  /// [errorMessage] 아래 둘째 줄(다른 소셜 계정이 쓰는 메일일 때 "카카오 계정으로 로그인해 주세요"). 없으면 한 줄.
  final String? errorHint;

  /// 이 메일로는 끝낼 수 없다(409 · 422 · 미확인) — 오류 문구 아래에 "다른 학교 메일 입력"(02 로)을 보인다.
  final bool canChooseAnotherEmail;

  /// 이 시각 전에는 재전송 버튼을 눌러도 요청을 보내지 않는다(60초 쿨다운, spec §13-38).
  final DateTime? resendAvailableAt;

  /// 받은 코드가 만료되는 시각. 화면 타이머("04:32 뒤에 만료돼요", pen `VuiDi`)가 여기서 뺀다.
  final DateTime? codeExpiresAt;

  /// 코드가 틀렸거나 만료돼 거부됐는지. 여섯 칸 테두리를 빨갛게 그린다(pen `Vn6w4`).
  final bool isCodeRejected;

  /// 학교 메일 인증(확인 + 서버 기록)이 끝났는지. 게이트를 다시 읽어 라우터가 다음 관문으로 보낸다.
  final bool verified;

  /// 기한이 지난 코드는 보내 봐야 "코드가 맞지 않아요" 만 돌아온다 — 버튼을 먼저 끈다.
  bool isExpired(DateTime now) {
    final expiresAt = codeExpiresAt;
    return expiresAt != null && !now.isBefore(expiresAt);
  }

  bool canSubmit(DateTime now) =>
      codeInput.length == 6 && !isSubmitting && !isExpired(now);

  bool canResend(DateTime now) {
    final availableAt = resendAvailableAt;
    return availableAt == null || !now.isBefore(availableAt);
  }
}
