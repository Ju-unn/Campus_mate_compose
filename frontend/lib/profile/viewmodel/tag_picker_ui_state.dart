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

  /// 폰에 임시 저장할 값 — 고른 태그뿐이다.
  Map<String, Object?> toDraft() => {'selected': selected.toList()};

  /// [toDraft] 로 남긴 값으로 처음 상태를 만든다. 지금 [kind] 목록에 없는 태그(앱 업데이트로 빠진 태그)는 빼고,
  /// 최대 개수까지만 담는다. 모양이 안 맞으면 던진다 — 저장소가 받아서 버린다.
  static TagPickerUiState fromDraft(Map<String, Object?> data, TagPickerKind kind) {
    final saved = (data['selected'] as List).cast<String>();
    return TagPickerUiState(selected: saved.where(kind.pool.contains).take(TagPickerKind.maxCount).toSet());
  }

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
