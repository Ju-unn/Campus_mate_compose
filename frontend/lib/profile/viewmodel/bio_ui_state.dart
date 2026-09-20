/// 자기소개 화면(DESIGN.md 화면 06-2b 초안 생성 · 06-3 저장)의 상태.
/// 초안은 최초 1회만 생성되고(§13-71), 실패하면 빈 값으로 06-3 에 들어간다("직접 쓸게요").
class BioUiState {
  const BioUiState({
    this.bio = '',
    this.isLoadingDraft = false,
    this.draftLoaded = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String bio;
  final bool isLoadingDraft;

  /// 초안 생성을 한 번 시도해 끝났는가(성공·실패 무관). 06-3 으로 넘어가는 조건이다.
  final bool draftLoaded;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit => bio.trim().isNotEmpty && !isSubmitting;

  BioUiState copyWith({
    String? bio,
    bool? isLoadingDraft,
    bool? draftLoaded,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return BioUiState(
      bio: bio ?? this.bio,
      isLoadingDraft: isLoadingDraft ?? this.isLoadingDraft,
      draftLoaded: draftLoaded ?? this.draftLoaded,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
