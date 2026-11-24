import 'dart:async';

import 'package:campus_mate/account/model/repository/account_repository.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/profile/onboarding/model/repository/kakao_id_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 들어올 때마다 저장된 아이디를 새로 읽는다.
final kakaoIdSettingsViewModelProvider =
    NotifierProvider.autoDispose<KakaoIdSettingsViewModel, KakaoIdSettingsUiState>(KakaoIdSettingsViewModel.new);

const Object _keep = Object();

/// 16e-1 카카오톡 아이디 변경. 읽기는 `GET /account/kakao-id`, 저장은 04-1b 와 같은
/// `POST /profile-onboarding/kakao-id` 다 — 온보딩 단계를 다시 읽지 않는다(이미 끝난 단계다).
class KakaoIdSettingsViewModel extends Notifier<KakaoIdSettingsUiState> {
  /// 공백 아닌 거절 이유를 손을 멈춘 뒤에 알리는 타이머(04-1b 와 같은 300ms).
  Timer? _debounce;

  @override
  KakaoIdSettingsUiState build() {
    ref.onDispose(() => _debounce?.cancel());
    // 만들자마자 버려졌으면(로그아웃) 읽지 않는다 — 버려진 ref 를 쓰면 던진다.
    Future.microtask(() => ref.mounted ? load() : null);
    return const KakaoIdSettingsUiState();
  }

  Future<void> load() async {
    final result = await ref.read(accountRepositoryProvider).fetchKakaoId();
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (kakaoId) => _copyWith(isLoading: false, kakaoIdInput: kakaoId ?? '', savedKakaoId: kakaoId ?? ''),
      onFailure: (failure) => _copyWith(isLoading: false, error: failure),
    );
  }

  void change(String value) {
    state = _copyWith(kakaoIdInput: value, kakaoIdChecked: false, error: null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (ref.mounted) state = _copyWith(kakaoIdChecked: true);
    });
  }

  Future<void> save() async {
    if (!state.canSubmit) return;
    state = _copyWith(isSubmitting: true, error: null);
    final result = await ref.read(kakaoIdRepositoryProvider).submit(state.kakaoIdInput.trim());
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => _copyWith(isSubmitting: false, error: failure),
    );
  }

  KakaoIdSettingsUiState _copyWith({
    String? kakaoIdInput,
    String? savedKakaoId,
    bool? kakaoIdChecked,
    bool? isLoading,
    bool? isSubmitting,
    Object? error = _keep,
    bool? completed,
  }) {
    return KakaoIdSettingsUiState(
      kakaoIdInput: kakaoIdInput ?? state.kakaoIdInput,
      savedKakaoId: savedKakaoId ?? state.savedKakaoId,
      kakaoIdChecked: kakaoIdChecked ?? state.kakaoIdChecked,
      isLoading: isLoading ?? state.isLoading,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      error: identical(error, _keep) ? state.error : error as Failure?,
      completed: completed ?? state.completed,
    );
  }
}
