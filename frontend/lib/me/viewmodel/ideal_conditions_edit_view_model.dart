import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealConditionsEditViewModelProvider =
    NotifierProvider.autoDispose<IdealConditionsEditViewModel, IdealConditionsUiState>(IdealConditionsEditViewModel.new);

/// 06-1 이상형 조건의 나 탭 편집 모드(계획서 A5, 화면 15 선호 나이 · 키 행). 고르기 · 저장 규칙은 온보딩과 같고
/// 채우기와 저장 뒤 할 일만 다르다.
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고르다 만 값이 남지 않는다(Review Focus 5).
/// 저장이 끝나면 화면 15 를 다시 읽게 하고(invalidate) 15 로 돌아간다(U4). 온보딩 단계 조회는 부르지 않는다.
class IdealConditionsEditViewModel extends IdealConditionsViewModel {
  /// 내 프로필을 watch 하지 않고 read 한다 — 저장 뒤 invalidate 가 이 상태(completed)를 새로 짓지 않게.
  @override
  IdealConditionsUiState build() {
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    if (profile == null) {
      return const IdealConditionsUiState();
    }
    return _fromServer(profile);
  }

  /// "상관없어요" 는 저장 규칙의 거꾸로다 — 나이는 전 구간(19~35), 키는 null 로 저장된다(화면 15 결정 3 과 같은 뜻).
  /// 켜진 쪽 슬라이더는 06-1 기본값(22~27 · 165~180)으로 둔다 — 끄면 거기서 시작한다.
  IdealConditionsUiState _fromServer(MyProfile profile) {
    const defaults = IdealConditionsUiState();
    final (ageMin, ageMax) = (profile.preferredAgeMin, profile.preferredAgeMax);
    final (heightMin, heightMax) = (profile.preferredHeightMin, profile.preferredHeightMax);
    final ageIgnored = ageMin == null ||
        ageMax == null ||
        (ageMin == IdealConditionsUiState.ageFloor && ageMax == IdealConditionsUiState.ageCeiling);
    final heightIgnored = heightMin == null || heightMax == null;
    return IdealConditionsUiState(
      preferredAgeMin: ageIgnored ? defaults.preferredAgeMin : ageMin,
      preferredAgeMax: ageIgnored ? defaults.preferredAgeMax : ageMax,
      ageIgnored: ageIgnored,
      preferredHeightMin: heightMin ?? defaults.preferredHeightMin,
      preferredHeightMax: heightMax ?? defaults.preferredHeightMax,
      heightIgnored: heightIgnored,
      preferredMbtiFlags: profile.preferredMbtiFlags,
      preferredAnimalTypes: profile.preferredAnimalTypes,
      preferredImpressionTypes: profile.preferredImpressionTypes,
    );
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
