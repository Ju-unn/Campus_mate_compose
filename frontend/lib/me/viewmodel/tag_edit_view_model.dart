import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tagEditViewModelProvider =
    NotifierProvider.autoDispose.family<TagEditViewModel, TagPickerUiState, TagPickerKind>(TagEditViewModel.new);

/// 태그 3종(04-5 · 04-6 · 06-2)의 나 탭 편집 모드(계획서 A3, 15c "수정 ›"). 고르기 · 저장 규칙은 온보딩과 같고
/// 채우기와 저장 뒤 할 일만 다르다.
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고르다 만 값이 남지 않는다(Review Focus 5).
/// 저장이 끝나면 화면 15 를 다시 읽게 하고(invalidate) 15c 로 돌아간다(U4 · T5). 온보딩 단계 조회는 부르지 않는다.
class TagEditViewModel extends TagPickerViewModel {
  /// 부모의 종류 칸은 private 이라 채우기(build)에 쓸 몫을 따로 든다.
  TagEditViewModel(super.kind) : _editKind = kind;

  final TagPickerKind _editKind;

  /// 내 프로필을 watch 하지 않고 read 한다 — 저장 뒤 invalidate 가 이 상태(completed)를 새로 짓지 않게.
  /// 편집 화면은 화면 15 · 15c 를 거쳐 열리므로 그때는 이미 읽혀 있다.
  @override
  TagPickerUiState build() {
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    return TagPickerUiState(selected: {...?profile?.tagsOf(_editKind)});
  }

  /// 저장 중에 뒤로 나가도 끝까지 저장하고 화면 15 를 다시 읽게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다.
  @override
  Future<void> submit() async {
    final keepAlive = ref.keepAlive();
    try {
      await super.submit();
    } finally {
      keepAlive.close();
    }
  }

  @override
  void onSaved() => ref.invalidate(myProfileProvider);
}

/// 종류마다 서버가 준 내 태그. 15c 칩과 태그 편집 채우기가 같이 쓴다.
extension MyProfileTags on MyProfile {
  List<String> tagsOf(TagPickerKind kind) => switch (kind) {
        TagPickerKind.interests => interestTags,
        TagPickerKind.myTraits => myTraits,
        TagPickerKind.idealTraits => idealTraits,
      };
}
