/// 16c 최종 시트(pen `s7M9MC`)의 상태.
class WithdrawUiState {
  const WithdrawUiState({this.isSubmitting = false, this.errorMessage});

  /// 보내는 중. 성공한 뒤에도 켜 둔다 — 로그아웃이 화면을 통째로 바꿀 때까지 다시 누르지 못하게.
  final bool isSubmitting;

  /// pen 에 없는 상태 — 네트워크 등으로 탈퇴하지 못했을 때 시트 안에 한 줄.
  final String? errorMessage;
}
