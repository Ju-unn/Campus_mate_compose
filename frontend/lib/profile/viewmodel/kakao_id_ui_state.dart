/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b)의 상태.
class KakaoIdUiState {
  const KakaoIdUiState({
    this.kakaoIdInput = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String kakaoIdInput;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit => kakaoIdInput.trim().isNotEmpty && !isSubmitting;
}
