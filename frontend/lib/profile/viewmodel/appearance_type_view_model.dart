import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
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
  AppearanceTypeUiState build() => const AppearanceTypeUiState();

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
    _refreshOnboardingStepIfCompleted();
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
