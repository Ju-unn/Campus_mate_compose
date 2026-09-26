enum AvatarGenerationStatus { idle, generating, ready, failed, fallback }

/// 아바타 결과 화면(DESIGN.md 05-12 계열)의 상태.
class AvatarGenerationUiState {
  const AvatarGenerationUiState({
    this.status = AvatarGenerationStatus.idle,
    this.avatarUrl,
    this.errorMessage,
    this.showCompensationDialog = false,
    this.compensationHearts = 0,
  });

  final AvatarGenerationStatus status;

  /// 서버가 완성해서 준 **전체 주소**. 그대로 `Image.network` 에 넘긴다 — 앞에 무엇도 붙이지 않는다.
  final String? avatarUrl;
  final String? errorMessage;
  final bool showCompensationDialog;

  /// 5회 실패 보상으로 받은 하트 수. **서버가 준 값**이라 앱에 10 을 박지 않는다.
  final int compensationHearts;

  bool get canRetry => status == AvatarGenerationStatus.failed;

  /// 만드는 중(서버 `pending`). 이 동안 결과 화면이 되풀이해 물어본다.
  bool get isGenerating => status == AvatarGenerationStatus.generating;

  /// 아직 결과를 못 받은 동안 — 만드는 중이거나, 한 번도 제대로 못 물어봤거나(idle).
  /// **화면이 도는 표시를 그리는 두 경우와 같아야 한다.** 어긋나면 표시는 도는데 아무도 안 묻는다.
  bool get isWaiting => status == AvatarGenerationStatus.idle || isGenerating;
}
