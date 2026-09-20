/// 태그 선택 화면(04-5·04-6·06-2 공용)의 상태.
class TagPickerUiState {
  const TagPickerUiState({
    this.selected = const {},
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final Set<String> selected;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 최소 3개·최대 5개(백엔드 validate_tag_selection 과 같은 규칙, UX 상 먼저 막는다).
  bool get canSubmit => selected.length >= 3 && selected.length <= 5 && !isSubmitting;

  TagPickerUiState copyWith({
    Set<String>? selected,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return TagPickerUiState(
      selected: selected ?? this.selected,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
