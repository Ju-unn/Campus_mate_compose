import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';

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

  /// 최소·최대 개수는 [TagPickerKind] 에서 온다(서버보다 UX 상 먼저 막는다).
  bool get canSubmit => selected.length >= TagPickerKind.minCount && selected.length <= TagPickerKind.maxCount && !isSubmitting;

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
