import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/revisit_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealNoteViewModelProvider =
    NotifierProvider<IdealNoteViewModel, IdealNoteUiState>(IdealNoteViewModel.new);

/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a)의 흐름을 맡는다.
class IdealNoteViewModel extends Notifier<IdealNoteUiState> {
  @override
  IdealNoteUiState build() {
    final drafts = ref.read(draftStoreProvider);
    listenSelf((previous, next) => _saveDraft(drafts, previous, next));
    return _initialState(drafts);
  }

  /// 처음 상태를 정하는 단 한 곳이다. 폰에 남긴 값 > (뒤로가기로 돌아왔으면) 서버 글 > 빈 값.
  IdealNoteUiState _initialState(DraftStore drafts) {
    final restored = drafts.read(DraftScreen.idealNote, IdealNoteUiState.fromDraft);
    return restored ?? IdealNoteUiState(note: revisitProfile(ref)?.idealNote ?? '');
  }

  /// 값이 바뀔 때마다 남긴다(저장소가 디바운스한다). 처음 상태(복원한 값 그대로)는 다시 쓰지 않고,
  /// 끝낸 단계는 서버에 있으니 남기지 않는다.
  void _saveDraft(DraftStore drafts, IdealNoteUiState? previous, IdealNoteUiState next) {
    if (previous == null || next.completed) {
      return;
    }
    drafts.write(DraftScreen.idealNote, next.toDraft());
  }

  void changeNote(String value) {
    state = state.copyWith(note: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    // 짧은 글은 서버도 422 로 돌려보낸다 — 보내지 않고 오류로 바꾼다. 다시 쓰면 copyWith 가 지운다.
    if (!state.isLongEnough) {
      state = state.copyWith(errorMessage: IdealNoteUiState.lengthHint);
      return;
    }
    await _send(state.note.trim());
  }

  Future<void> _send(String note) async {
    // 같은 세션에서 다시 저장하면 지난 저장의 completed 가 남아 있다 — 내리지 않으면 실패해도 다음 화면으로 넘어간다.
    state = state.copyWith(isSubmitting: true, errorMessage: null, completed: false);
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
    _discardDraftIfCompleted();
    _refreshOnboardingStepIfCompleted();
  }

  /// 단계를 끝냈으면 이 화면의 임시 저장 값을 지운다 — 다음에 다시 열 일이 없다.
  void _discardDraftIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(draftStoreProvider).clear(DraftScreen.idealNote));
  }

  /// 저장이 끝나면 다음 온보딩 단계로 넘어가도록 캐시를 다시 조회한다(Task A1).
  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).stepSaved());
  }
}
