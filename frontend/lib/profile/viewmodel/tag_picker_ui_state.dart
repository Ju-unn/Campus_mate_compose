import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';

/// 종류마다 서버가 준 내 태그. 15c 칩 · 태그 편집 · 온보딩 뒤로가기 채우기가 같이 쓴다.
extension MyProfileTags on MyProfile {
  List<String> tagsOf(TagPickerKind kind) => switch (kind) {
        TagPickerKind.interests => interestTags,
        TagPickerKind.myTraits => myTraits,
        TagPickerKind.idealTraits => idealTraits,
      };
}

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

  /// 서버에 저장해 둔 이 종류의 태그로 처음 상태를 만든다(나 탭 편집 · 온보딩 뒤로가기).
  static TagPickerUiState fromProfile(MyProfile profile, TagPickerKind kind) {
    return TagPickerUiState(selected: {...profile.tagsOf(kind)});
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
