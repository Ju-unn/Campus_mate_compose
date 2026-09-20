import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/bio_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bioViewModelProvider = NotifierProvider<BioViewModel, BioUiState>(BioViewModel.new);

/// 자기소개 초안 생성(06-2b)과 저장(06-3)의 흐름을 맡는다.
class BioViewModel extends Notifier<BioUiState> {
  @override
  BioUiState build() => const BioUiState();

  /// 06-2b 진입 즉시 한 번 부른다. 실패해도 오류 화면을 띄우지 않고 빈 값으로 06-3 에 보낸다
  /// (DESIGN.md §9 8 — "직접 쓸게요"/생성 실패 시 빈 상태로 진입). 다시 만들기 버튼은 없다.
  Future<void> loadDraft() async {
    if (state.draftLoaded || state.isLoadingDraft) {
      return;
    }
    state = state.copyWith(isLoadingDraft: true);
    try {
      final result = await ref.read(bioRepositoryProvider).generateDraft();
      state = result.when(
        onSuccess: (draft) => state.copyWith(bio: draft, isLoadingDraft: false, draftLoaded: true),
        onFailure: (_) => state.copyWith(isLoadingDraft: false, draftLoaded: true),
      );
    } catch (_) {
      state = state.copyWith(isLoadingDraft: false, draftLoaded: true);
    }
  }

  void changeBio(String value) {
    state = state.copyWith(bio: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final result = await ref.read(bioRepositoryProvider).submit(state.bio.trim());
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
      );
    } catch (_) {
      state = state.copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
      return;
    }
    _refreshOnboardingStepIfCompleted();
  }

  /// 저장이 끝나면 `next-step` 이 `complete` 가 되어 AuthRedirect 가 홈으로 보낸다(Task A1).
  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
