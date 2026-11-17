import 'package:campus_mate/safety/model/data/safety_errors.dart';
import 'package:campus_mate/safety/model/repository/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/partner_profile_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 상대 한 명당 하나. 14c 에 들어올 때마다 새로 읽는다 — 그사이 게이트가 열렸거나 상대가 나갔을 수 있다.
final partnerProfileViewModelProvider =
    NotifierProvider.autoDispose.family<PartnerProfileViewModel, PartnerProfileUiState, String>(
  PartnerProfileViewModel.new,
);

/// 14c 상대 프로필. Riverpod 3 의 family 는 인자(profile id)를 생성자로 받는다.
class PartnerProfileViewModel extends Notifier<PartnerProfileUiState> {
  PartnerProfileViewModel(this._profileId);

  final String _profileId;

  @override
  PartnerProfileUiState build() {
    // 만들자마자 버려졌으면(로그아웃) 읽지 않는다 — 버려진 ref 를 쓰면 던진다.
    Future.microtask(() => ref.mounted ? _load() : null);
    return const PartnerProfileUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(safetyRepositoryProvider).fetchPartnerProfile(_profileId);
    // 응답을 기다리는 동안 14c 를 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (profile) => PartnerProfileUiState(isLoading: false, profile: profile),
      onFailure: (failure) => isProfileGone(failure)
          ? PartnerProfileUiState(isLoading: false, isGone: true, error: failure)
          : PartnerProfileUiState(isLoading: false, error: failure),
    );
  }
}
