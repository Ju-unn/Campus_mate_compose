import 'dart:async';

import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final avatarGenerationViewModelProvider =
    NotifierProvider<AvatarGenerationViewModel, AvatarGenerationUiState>(AvatarGenerationViewModel.new);

/// 아바타 생성 화면(DESIGN.md 화면 04-3)의 흐름을 맡는다.
class AvatarGenerationViewModel extends Notifier<AvatarGenerationUiState> {
  @override
  AvatarGenerationUiState build() => const AvatarGenerationUiState();

  Future<void> generate() async {
    state = const AvatarGenerationUiState(status: AvatarGenerationStatus.generating);
    final repository = ref.read(avatarRepositoryProvider);
    final result = await repository.generateAvatar();
    state = result.when(
      onSuccess: (outcome) => outcome.when(
        ready: (path) => AvatarGenerationUiState(
          status: AvatarGenerationStatus.ready,
          avatarPath: path,
          completed: true,
        ),
        failed: () => const AvatarGenerationUiState(status: AvatarGenerationStatus.failed),
        fallback: (hearts) => AvatarGenerationUiState(
          status: AvatarGenerationStatus.fallback,
          showCompensationDialog: true,
          compensationHearts: hearts,
          completed: true,
        ),
      ),
      onFailure: (failure) => AvatarGenerationUiState(
        status: AvatarGenerationStatus.failed,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
    _refreshOnboardingStepIfCompleted();
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
