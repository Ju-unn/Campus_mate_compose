import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kakaoIdViewModelProvider = NotifierProvider<KakaoIdViewModel, KakaoIdUiState>(
  KakaoIdViewModel.new,
);

/// 이미 저장한 카카오톡 아이디(`GET /account/kakao-id`, 16e-1 과 같은 API). 04-2 에서 뒤로 돌아올 때
/// [OnboardingBackViewModel] 이 미리 읽어 둔다. **메모리에만 둔다** — 평문으로 폰에 남기지 않는다(2026-10-08 사용자 결정).
final savedKakaoIdProvider = FutureProvider<Result<String?>>((ref) => ref.watch(accountRepositoryProvider).fetchKakaoId());

const Object _keep = Object();

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b)의 흐름을 맡는다. 건너뛰기는 없다(§13-100).
class KakaoIdViewModel extends Notifier<KakaoIdUiState> {
  @override
  KakaoIdUiState build() => KakaoIdUiState(kakaoIdInput: _savedKakaoId() ?? '');

  /// 04-2 에서 뒤로 돌아왔을 때만 저장해 둔 아이디로 채운다(뒤로가기가 [savedKakaoIdProvider] 를 미리 읽어 둔다).
  String? _savedKakaoId() {
    // 미리 읽지 않았으면 여기서 읽기를 시작하지 않는다(revisit_profile.dart 와 같은 이유).
    if (!ref.read(onboardingStepListenableProvider).isRevisiting || !ref.exists(savedKakaoIdProvider)) {
      return null;
    }
    return ref.read(savedKakaoIdProvider).value?.when<String?>(onSuccess: (id) => id, onFailure: (_) => null);
  }

  void changeKakaoId(String value) {
    state = _copyWith(kakaoIdInput: value, errorMessage: null);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    // 지난 저장의 completed 를 내린다 — 되돌아와 다시 저장하다 실패하면 다음 화면으로 넘어가면 안 된다.
    state = _copyWith(isSubmitting: true, errorMessage: null, completed: false);
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
    unawaited(ref.read(onboardingStepListenableProvider).stepSaved());
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
