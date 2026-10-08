import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealConditionsViewModelProvider =
    NotifierProvider<IdealConditionsViewModel, IdealConditionsUiState>(IdealConditionsViewModel.new);

/// 이상형 조건 화면(DESIGN.md 화면 06-1)의 흐름을 맡는다.
class IdealConditionsViewModel extends Notifier<IdealConditionsUiState> {
  /// 온보딩일 때만 채워진다. 나 탭 편집 모드(`IdealConditionsEditViewModel`)는 [build] 를 덮어써 비어 있다 —
  /// 편집은 열 때마다 서버 값으로 채우므로 임시 저장을 쓰지도 지우지도 않는다.
  DraftStore? _drafts;

  @override
  IdealConditionsUiState build() {
    final drafts = ref.read(draftStoreProvider);
    _drafts = drafts;
    listenSelf((previous, next) => _saveDraft(drafts, previous, next));
    return _initialState(drafts);
  }

  /// 처음 상태를 정하는 단 한 곳이다. 지금은 폰에 남긴 값 또는 기본값 — 나중에 서버 값을 끼울 자리다.
  IdealConditionsUiState _initialState(DraftStore drafts) {
    return drafts.read(DraftScreen.idealConditions, IdealConditionsUiState.fromDraft) ?? const IdealConditionsUiState();
  }

  /// 값이 바뀔 때마다 남긴다(저장소가 디바운스한다). 처음 상태(복원한 값 그대로)는 다시 쓰지 않고,
  /// 끝낸 단계는 서버에 있으니 남기지 않는다.
  void _saveDraft(DraftStore drafts, IdealConditionsUiState? previous, IdealConditionsUiState next) {
    if (previous == null || next.completed) {
      return;
    }
    drafts.write(DraftScreen.idealConditions, next.toDraft());
  }

  void changeAgeRange(int min, int max) {
    state = state.copyWith(preferredAgeMin: min, preferredAgeMax: max);
  }

  void changeAgeIgnored(bool value) {
    state = state.copyWith(ageIgnored: value);
  }

  void changeHeightRange(int min, int max) {
    state = state.copyWith(preferredHeightMin: min, preferredHeightMax: max);
  }

  void changeHeightIgnored(bool value) {
    state = state.copyWith(heightIgnored: value);
  }

  void toggleMbtiPole(String pole) {
    final flags = {...state.preferredMbtiFlags};
    if (flags[pole] ?? false) {
      flags.remove(pole);
    } else {
      flags[pole] = true;
    }
    state = state.copyWith(preferredMbtiFlags: flags);
  }

  void toggleAnimalType(AnimalType value) {
    state = state.copyWith(
      preferredAnimalTypes: _toggledWithinCap(state.preferredAnimalTypes, value),
    );
  }

  void toggleImpressionType(ImpressionType value) {
    state = state.copyWith(
      preferredImpressionTypes: _toggledWithinCap(state.preferredImpressionTypes, value),
    );
  }

  /// 최대 3개까지만 담는다(Task A2 태그 선택과 같은 규칙, 상한만 다르다).
  List<T> _toggledWithinCap<T>(List<T> selected, T value) {
    final next = [...selected];
    if (next.remove(value)) {
      return next;
    }
    if (next.length < IdealConditionsUiState.maxAppearanceChoices) {
      next.add(value);
    }
    return next;
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final repository = ref.read(idealConditionsRepositoryProvider);
      final result = await repository.submit(_submission());
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
      );
    } catch (_) {
      state = state.copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
      return;
    }
    _notifySavedIfCompleted();
  }

  /// "키는 상관없어요"는 null 로, "나이는 상관없어요"는 전 구간으로 보낸다(서버가 나이는 필수로 받는다).
  IdealConditionsSubmission _submission() {
    return IdealConditionsSubmission(
      preferredAgeMin: state.ageIgnored ? IdealConditionsUiState.ageFloor : state.preferredAgeMin,
      preferredAgeMax: state.ageIgnored ? IdealConditionsUiState.ageCeiling : state.preferredAgeMax,
      preferredHeightMin: state.heightIgnored ? null : state.preferredHeightMin,
      preferredHeightMax: state.heightIgnored ? null : state.preferredHeightMax,
      preferredMbtiFlags: state.preferredMbtiFlags,
      preferredAnimalTypes: state.preferredAnimalTypes,
      preferredImpressionTypes: state.preferredImpressionTypes,
    );
  }

  void _notifySavedIfCompleted() {
    if (!state.completed) {
      return;
    }
    _discardDraft();
    onSaved();
  }

  /// 단계를 끝냈으면 이 화면의 임시 저장 값을 지운다. 편집 모드는 [_drafts] 가 없어 아무것도 하지 않는다.
  void _discardDraft() {
    final drafts = _drafts;
    if (drafts == null) {
      return;
    }
    unawaited(drafts.clear(DraftScreen.idealConditions));
  }

  /// 저장이 끝나면 다음 온보딩 단계로 넘어가도록 캐시를 다시 조회한다(Task A1).
  /// 나 탭 편집 모드(`IdealConditionsEditViewModel`)는 이것 대신 화면 15 값을 다시 읽게 한다 — 온보딩 단계는 조회하지 않는다.
  @protected
  void onSaved() {
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
