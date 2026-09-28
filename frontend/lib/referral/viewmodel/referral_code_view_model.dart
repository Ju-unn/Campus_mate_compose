import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final referralCodeViewModelProvider =
    NotifierProvider<ReferralCodeViewModel, ReferralCodeUiState>(ReferralCodeViewModel.new);

/// 추천 코드 입력(DESIGN.md 화면 20)의 흐름을 맡는다.
/// 서버 온보딩 단계가 아니라서 단계 캐시를 새로 고치지 않는다(2026-09-28 대장 D2).
class ReferralCodeViewModel extends Notifier<ReferralCodeUiState> {
  @override
  ReferralCodeUiState build() => const ReferralCodeUiState();

  /// 대문자 · 공백 빼기 · 6자 자르기는 화면의 입력 포매터가 이미 했다.
  void changeCode(String value) {
    state = state.copyWith(code: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true);
    try {
      final result = await ref.read(referralRepositoryProvider).redeem(state.code);
      state = result.when(
        onSuccess: (referrerId) => state.copyWith(isSubmitting: false, referrerId: referrerId),
        // 404 · 409 · 422 는 서버 문구(errors.py)를 그대로 보여 준다 — 거절 이유를 앱이 지어내지 않는다.
        onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
      );
    } catch (_) {
      state = state.copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }
}
