import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tagPickerViewModelProvider =
    NotifierProvider.family<TagPickerViewModel, TagPickerUiState, TagPickerKind>(TagPickerViewModel.new);

/// 태그 선택 화면(04-5·04-6·06-2 공용)의 흐름을 맡는다.
/// Riverpod 3.x family notifier 는 인자를 생성자로 받는다(verify_code_view_model.dart 와 같은 패턴).
class TagPickerViewModel extends Notifier<TagPickerUiState> {
  TagPickerViewModel(this._kind);

  final TagPickerKind _kind;

  @override
  TagPickerUiState build() => const TagPickerUiState();

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
