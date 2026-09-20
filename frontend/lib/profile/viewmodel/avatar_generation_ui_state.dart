enum AvatarGenerationStatus { idle, generating, ready, failed, fallback }

/// 아바타 생성 화면(DESIGN.md 화면 04-3)의 상태.
class AvatarGenerationUiState {
  const AvatarGenerationUiState({
    this.status = AvatarGenerationStatus.idle,
    this.avatarPath,
    this.errorMessage,
    this.showCompensationDialog = false,
    this.compensationHearts = 0,
    this.completed = false,
  });

  final AvatarGenerationStatus status;
  final String? avatarPath;
  final String? errorMessage;
  final bool showCompensationDialog;
  final int compensationHearts;
  final bool completed;

  bool get canRetry => status == AvatarGenerationStatus.failed;
  bool get isGenerating => status == AvatarGenerationStatus.generating;
}
