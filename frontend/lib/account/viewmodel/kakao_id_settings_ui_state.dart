/// 16e-1 카카오톡 아이디 변경(pen `bWrnD`)의 상태.
class KakaoIdSettingsUiState {
  const KakaoIdSettingsUiState({
    this.kakaoIdInput = '',
    this.isLoading = true,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String kakaoIdInput;

  /// 저장된 아이디를 읽는 중. 읽기 전에 저장하면 빈 칸이 덮어쓴다.
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;

  /// 저장까지 끝났다 — 화면이 true 를 들고 닫힌다.
  final bool completed;

  /// 04-1b(KakaoIdUiState)와 같은 규칙 — 공백만이면 못 보낸다. 읽는 중에도 못 보낸다.
  bool get canSubmit => !isLoading && kakaoIdInput.trim().isNotEmpty && !isSubmitting;
}
