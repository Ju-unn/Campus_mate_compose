import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_ui_state.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tagPickerViewModelProvider =
    NotifierProvider.family<TagPickerViewModel, TagPickerUiState, TagPickerKind>(TagPickerViewModel.new);

/// 태그 선택 화면(04-5·04-6·06-2 공용)의 흐름을 맡는다.
/// Riverpod 3.x family notifier 는 인자를 생성자로 받는다(verify_code_view_model.dart 와 같은 패턴).
class TagPickerViewModel extends Notifier<TagPickerUiState> {
  TagPickerViewModel(this._kind);

  final TagPickerKind _kind;

  /// 온보딩일 때만 채워진다. 나 탭 편집 모드(`TagEditViewModel`)는 [build] 를 덮어써 비어 있다 —
  /// 편집은 열 때마다 서버 값으로 채우므로 임시 저장을 쓰지도 지우지도 않는다.
  DraftStore? _drafts;

  @override
  TagPickerUiState build() {
    final drafts = ref.read(draftStoreProvider);
    _drafts = drafts;
    listenSelf((previous, next) => _saveDraft(drafts, previous, next));
    return _initialState(drafts);
  }

  /// 처음 상태를 정하는 단 한 곳이다. 지금은 폰에 남긴 값 또는 빈 값 — 나중에 서버 값을 끼울 자리다.
  TagPickerUiState _initialState(DraftStore drafts) {
    final restored = drafts.read(_kind.draftScreen, (data) => TagPickerUiState.fromDraft(data, _kind));
    return restored ?? const TagPickerUiState();
  }

  /// 값이 바뀔 때마다 남긴다(저장소가 디바운스한다). 처음 상태(복원한 값 그대로)는 다시 쓰지 않고,
  /// 끝낸 단계는 서버에 있으니 남기지 않는다.
  void _saveDraft(DraftStore drafts, TagPickerUiState? previous, TagPickerUiState next) {
    if (previous == null || next.completed) {
      return;
    }
    drafts.write(_kind.draftScreen, next.toDraft());
  }

  void toggle(String tag) {
    final selected = {...state.selected};
    if (selected.contains(tag)) {
      selected.remove(tag);
    } else if (selected.length < TagPickerKind.maxCount) {
      selected.add(tag);
    }
    state = state.copyWith(selected: selected);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final repository = ref.read(tagPickerRepositoryProvider);
      final result = await repository.submit(_kind.endpoint, state.selected.toList());
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
    unawaited(drafts.clear(_kind.draftScreen));
  }

  /// 저장이 끝나면 다음 온보딩 단계로 넘어가도록 캐시를 다시 조회한다(Task A1).
  /// 나 탭 편집 모드(`TagEditViewModel`)는 이것 대신 화면 15 값을 다시 읽게 한다 — 온보딩 단계는 조회하지 않는다.
  @protected
  void onSaved() {
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
