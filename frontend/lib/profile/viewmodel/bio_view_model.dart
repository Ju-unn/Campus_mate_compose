import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/bio_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bioViewModelProvider = NotifierProvider<BioViewModel, BioUiState>(BioViewModel.new);

const _draftFailedMessage = '초안을 만들지 못했어요. 직접 써 주세요';

/// 자기소개 초안 생성(06-2b)과 저장(06-3)의 흐름을 맡는다.
class BioViewModel extends Notifier<BioUiState> {
  /// "직접 쓸게요" 를 누른 뒤 뒤늦게 도착한 초안이 사용자가 쓰던 글을 덮지 않게 막는 표식.
  bool _skipped = false;

  @override
  BioUiState build() => const BioUiState();

  /// 06-2b 에서 "직접 쓸게요" 를 누르면 초안을 기다리지 않고 빈 상태로 06-3 에 들어간다.
  void skipDraft() {
    _skipped = true;
    state = state.copyWith(isLoadingDraft: false, draftLoaded: true);
  }

  /// 06-2b 진입 즉시 한 번 부른다. 실패해도 오류 화면을 띄우지 않고 빈 값으로 06-3 에 보내되,
  /// 왜 칸이 비었는지는 안내 문구로 남긴다(2026-09-20 리뷰 필수 4 — 실패를 삼키지 않는다).
  /// 다시 만들기 버튼은 없다.
  Future<void> loadDraft() async {
    if (state.draftLoaded || state.isLoadingDraft) {
      return;
    }
    state = state.copyWith(isLoadingDraft: true);
    try {
      final result = await ref.read(bioRepositoryProvider).generateDraft();
      if (_skipped) {
        return;
      }
      state = result.when(
        onSuccess: (draft) => state.copyWith(bio: draft, isLoadingDraft: false, draftLoaded: true),
        onFailure: (_) => _draftFailedState(),
      );
    } catch (_) {
      if (_skipped) {
        return;
      }
      state = _draftFailedState();
    }
  }

  /// 실패 원인이 무엇이든 사용자가 할 일은 하나다 — 직접 쓰면 된다.
  BioUiState _draftFailedState() {
    return state.copyWith(
      isLoadingDraft: false,
      draftLoaded: true,
      errorMessage: _draftFailedMessage,
    );
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
