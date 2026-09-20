import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kakaoIdViewModelProvider = NotifierProvider<KakaoIdViewModel, KakaoIdUiState>(
  KakaoIdViewModel.new,
);

const Object _keep = Object();

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b)의 흐름을 맡는다. 건너뛰기는 없다(§13-100).
class KakaoIdViewModel extends Notifier<KakaoIdUiState> {
  @override
  KakaoIdUiState build() => const KakaoIdUiState();

  void changeKakaoId(String value) {
    state = _copyWith(kakaoIdInput: value, errorMessage: null);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = _copyWith(isSubmitting: true, errorMessage: null);
    state = await _submittedState();
    _refreshOnboardingStepIfCompleted();
  }

  Future<KakaoIdUiState> _submittedState() async {
    try {
      final repository = ref.read(kakaoIdRepositoryProvider);
      final result = await repository.submit(state.kakaoIdInput.trim());
      return _stateFromResult(result);
    } catch (_) {
      return _copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }

  KakaoIdUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }

  KakaoIdUiState _copyWith({
    String? kakaoIdInput,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return KakaoIdUiState(
      kakaoIdInput: kakaoIdInput ?? state.kakaoIdInput,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? state.errorMessage : errorMessage as String?,
      completed: completed ?? state.completed,
    );
  }
}
