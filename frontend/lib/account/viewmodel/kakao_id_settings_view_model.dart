import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_ui_state.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 들어올 때마다 저장된 아이디를 새로 읽는다.
final kakaoIdSettingsViewModelProvider =
    NotifierProvider.autoDispose<KakaoIdSettingsViewModel, KakaoIdSettingsUiState>(KakaoIdSettingsViewModel.new);

const Object _keep = Object();

/// 16e-1 카카오톡 아이디 변경. 읽기는 `GET /account/kakao-id`, 저장은 04-1b 와 같은
/// `POST /profile-onboarding/kakao-id` 다 — 온보딩 단계를 다시 읽지 않는다(이미 끝난 단계다).
class KakaoIdSettingsViewModel extends Notifier<KakaoIdSettingsUiState> {
  @override
  KakaoIdSettingsUiState build() {
    Future.microtask(load);
    return const KakaoIdSettingsUiState();
  }

  Future<void> load() async {
    final result = await ref.read(accountRepositoryProvider).fetchKakaoId();
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (kakaoId) => _copyWith(isLoading: false, kakaoIdInput: kakaoId ?? ''),
      onFailure: (failure) => _copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  void change(String value) {
    state = _copyWith(kakaoIdInput: value, errorMessage: null);
  }

  Future<void> save() async {
    if (!state.canSubmit) return;
    state = _copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref.read(kakaoIdRepositoryProvider).submit(state.kakaoIdInput.trim());
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  KakaoIdSettingsUiState _copyWith({
    String? kakaoIdInput,
    bool? isLoading,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return KakaoIdSettingsUiState(
      kakaoIdInput: kakaoIdInput ?? state.kakaoIdInput,
      isLoading: isLoading ?? state.isLoading,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? state.errorMessage : errorMessage as String?,
      completed: completed ?? state.completed,
    );
  }
}
