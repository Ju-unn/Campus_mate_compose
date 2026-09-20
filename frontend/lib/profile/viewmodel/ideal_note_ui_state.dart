/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a)의 상태.
/// 필수 입력이다(2026-09-20 사용자 결정 "온보딩 입력은 전부 필수") — 건너뛰기가 없다.
class IdealNoteUiState {
  const IdealNoteUiState({
    this.note = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String note;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 하단 "다음"은 뭔가 썼을 때만 켜다 — 공백만 쓴 글은 서버도 422 로 돌려보낸다.
  bool get canSubmit => note.trim().isNotEmpty && !isSubmitting;

  IdealNoteUiState copyWith({
    String? note,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return IdealNoteUiState(
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
