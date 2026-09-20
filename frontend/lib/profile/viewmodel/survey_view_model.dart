import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/survey_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final surveyViewModelProvider = NotifierProvider<SurveyViewModel, SurveyUiState>(SurveyViewModel.new);

/// 성향 설문 화면(DESIGN.md 화면 05-01~11)의 흐름을 맡는다.
class SurveyViewModel extends Notifier<SurveyUiState> {
  @override
  SurveyUiState build() => const SurveyUiState();

  /// 5단계(-1/-0.5/0/0.5/1) 슬라이더 값. 축은 1~9.
  void answer(int axis, double value) {
    state = SurveyUiState(
      answers: {...state.answers, axis: value},
      religion: state.religion,
      isSmoker: state.isSmoker,
    );
  }

  void changeReligion(Religion value) {
    state = SurveyUiState(answers: state.answers, religion: value, isSmoker: state.isSmoker);
  }

  void changeIsSmoker(bool value) {
    state = SurveyUiState(answers: state.answers, religion: state.religion, isSmoker: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = SurveyUiState(
      answers: state.answers,
      religion: state.religion,
      isSmoker: state.isSmoker,
      isSubmitting: true,
    );
    state = await _submittedState();
    _refreshOnboardingStepIfCompleted();
  }

  Future<SurveyUiState> _submittedState() async {
    try {
      final repository = ref.read(surveyRepositoryProvider);
      final result = await repository.submit(state.answers, state.religion!, state.isSmoker!);
      return _stateFromResult(result);
    } catch (_) {
      return SurveyUiState(
        answers: state.answers,
        religion: state.religion,
        isSmoker: state.isSmoker,
        errorMessage: const UnknownFailure().toDisplayMessage(),
      );
    }
  }

  SurveyUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => SurveyUiState(
        answers: state.answers,
        religion: state.religion,
        isSmoker: state.isSmoker,
        completed: true,
      ),
      onFailure: (failure) => SurveyUiState(
        answers: state.answers,
        religion: state.religion,
        isSmoker: state.isSmoker,
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
