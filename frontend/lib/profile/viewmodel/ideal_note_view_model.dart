import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealNoteViewModelProvider =
    NotifierProvider<IdealNoteViewModel, IdealNoteUiState>(IdealNoteViewModel.new);

/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a)의 흐름을 맡는다.
class IdealNoteViewModel extends Notifier<IdealNoteUiState> {
  @override
  IdealNoteUiState build() => const IdealNoteUiState();

  void changeNote(String value) {
    state = state.copyWith(note: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    await _send(state.note.trim());
  }

  /// 건너뛰어도 빈 문자열을 저장한다 — `ideal_note` 가 null 이 아니면 "본 것"으로 치기 때문에
  /// 그래야 다음 진입에서 다시 묻지 않는다(DB 에 `ideal_note_seen` 컬럼이 없다).
  Future<void> skip() async {
    if (state.isSubmitting) {
      return;
    }
    await _send('');
  }

  Future<void> _send(String note) async {
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final repository = ref.read(idealNoteRepositoryProvider);
      final result = await repository.submit(note);
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

  /// 저장이 끝나면 다음 온보딩 단계로 넘어가도록 캐시를 다시 조회한다(Task A1).
  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
