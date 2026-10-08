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

  /// 폰에 임시 저장할 값 — 06-3 입력칸의 **글만** 남긴다. 사용자가 고친 글뿐 아니라 AI 초안이 막 도착한 그 글도
  /// 포함된다(무해하다 — 같은 글로 06-3 에 들어가고 초안을 다시 만들지 않는다). 안내 문구 · 진행 표시는 남기지 않는다.
  Map<String, Object?> toDraft() => {'bio': bio};

  /// [toDraft] 로 남긴 글로 06-3 에 바로 들어간다(초안을 다시 만들어 고친 글을 덮지 않는다).
  /// 빈 글이면 null — 다시 열면 06-2b 에서 초안부터 받는다. 모양이 안 맞으면 던진다 — 저장소가 받아서 버린다.
  static BioUiState? fromDraft(Map<String, Object?> data) {
    final bio = data['bio'] as String;
    return bio.trim().isEmpty ? null : BioUiState(bio: bio, draftLoaded: true);
  }

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
