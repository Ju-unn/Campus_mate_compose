import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealConditionsEditViewModelProvider =
    NotifierProvider.autoDispose<IdealConditionsEditViewModel, IdealConditionsUiState>(IdealConditionsEditViewModel.new);

/// 06-1 이상형 조건의 나 탭 편집 모드(계획서 A5, 15-5 "이상형 조건 수정" 한 줄이 연다). 고르기 · 저장 규칙은 온보딩과
/// 같고 채우기와 저장 뒤 할 일만 다르다.
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고르다 만 값이 남지 않는다(Review Focus 5).
/// 저장이 끝나면 내 프로필을 다시 읽게 하고(invalidate) 15-5 로 돌아간다(U4). 온보딩 단계 조회는 부르지 않는다.
class IdealConditionsEditViewModel extends IdealConditionsViewModel {
  /// 내 프로필을 watch 하지 않고 read 한다 — 저장 뒤 invalidate 가 이 상태(completed)를 새로 짓지 않게.
  @override
  IdealConditionsUiState build() {
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    return profile == null ? const IdealConditionsUiState() : IdealConditionsUiState.fromProfile(profile);
  }

  /// 저장 중에 뒤로 나가도 끝까지 저장하고 15-5 를 다시 읽게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다.
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
