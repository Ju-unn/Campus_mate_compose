import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/appearance_type_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/appearance_type_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appearanceTypeViewModelProvider =
    NotifierProvider<AppearanceTypeViewModel, AppearanceTypeUiState>(AppearanceTypeViewModel.new);

/// 외모 타입 화면(DESIGN.md 화면 04-4)의 흐름을 맡는다.
class AppearanceTypeViewModel extends Notifier<AppearanceTypeUiState> {
  @override
  AppearanceTypeUiState build() {
    final drafts = ref.read(draftStoreProvider);
    listenSelf((previous, next) => _saveDraft(drafts, previous, next));
    return _initialState(drafts);
  }

  /// 처음 상태를 정하는 단 한 곳이다. 지금은 폰에 남긴 값 또는 빈 값 — 나중에 서버 값을 끼울 자리다.
  AppearanceTypeUiState _initialState(DraftStore drafts) {
    return drafts.read(DraftScreen.appearanceType, AppearanceTypeUiState.fromDraft) ?? const AppearanceTypeUiState();
  }

  /// 값이 바뀔 때마다 남긴다(저장소가 디바운스한다). 처음 상태(복원한 값 그대로)는 다시 쓰지 않고,
  /// 끝낸 단계는 서버에 있으니 남기지 않는다.
  void _saveDraft(DraftStore drafts, AppearanceTypeUiState? previous, AppearanceTypeUiState next) {
    if (previous == null || next.completed) {
      return;
    }
    drafts.write(DraftScreen.appearanceType, next.toDraft());
  }

  void changeAnimalType(AnimalType value) {
    state = AppearanceTypeUiState(animalType: value, impressionType: state.impressionType);
  }

  void changeImpressionType(ImpressionType value) {
    state = AppearanceTypeUiState(animalType: state.animalType, impressionType: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = AppearanceTypeUiState(
      animalType: state.animalType,
      impressionType: state.impressionType,
      isSubmitting: true,
    );
    state = await _submittedState();
    _discardDraftIfCompleted();
    _refreshOnboardingStepIfCompleted();
  }

  /// 단계를 끝냈으면 이 화면의 임시 저장 값을 지운다 — 다음에 다시 열 일이 없다.
  void _discardDraftIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(draftStoreProvider).clear(DraftScreen.appearanceType));
  }

  Future<AppearanceTypeUiState> _submittedState() async {
    try {
      final repository = ref.read(appearanceTypeRepositoryProvider);
      final result = await repository.submit(state.animalType!, state.impressionType!);
      return _stateFromResult(result);
    } catch (_) {
      return AppearanceTypeUiState(
        animalType: state.animalType,
        impressionType: state.impressionType,
        errorMessage: const UnknownFailure().toDisplayMessage(),
      );
    }
  }

  AppearanceTypeUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => AppearanceTypeUiState(
        animalType: state.animalType,
        impressionType: state.impressionType,
        completed: true,
      ),
      onFailure: (failure) => AppearanceTypeUiState(
        animalType: state.animalType,
        impressionType: state.impressionType,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
