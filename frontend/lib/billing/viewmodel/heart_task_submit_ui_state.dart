import 'dart:io';

/// 18b 인증샷 제출의 상태. 동작 하나가 끝날 때마다 새로 만든다 — [errorMessage] 는 그 한 번에만 붙는다.
class HeartTaskSubmitUiState {
  const HeartTaskSubmitUiState({this.photo, this.isSubmitting = false, this.errorMessage, this.submitted = false});

  final File? photo;
  final bool isSubmitting;

  /// 화면이 토스트로 한 번 띄운다.
  final String? errorMessage;

  /// 성공하면 화면이 18c 로 넘어간다.
  final bool submitted;

  bool get canSubmit => photo != null && !isSubmitting && !submitted;
}
