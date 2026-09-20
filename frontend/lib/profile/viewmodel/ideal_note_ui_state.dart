/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a)의 상태.
/// 자유 글이라 비워 둘 수 있고, 건너뛰면 빈 문자열을 저장해 다시 묻지 않는다.
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

  /// 하단 "다음"은 뭔가 썼을 때만 켠다. 안 쓰고 넘어가는 길은 상단 "건너뛰기"다.
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
