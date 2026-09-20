import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealConditionsViewModelProvider =
    NotifierProvider<IdealConditionsViewModel, IdealConditionsUiState>(IdealConditionsViewModel.new);

/// 이상형 조건 화면(DESIGN.md 화면 06-1)의 흐름을 맡는다.
class IdealConditionsViewModel extends Notifier<IdealConditionsUiState> {
  @override
  IdealConditionsUiState build() => const IdealConditionsUiState();

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
    _refreshOnboardingStepIfCompleted();
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

  /// 저장이 끝나면 다음 온보딩 단계로 넘어가도록 캐시를 다시 조회한다(Task A1).
  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
