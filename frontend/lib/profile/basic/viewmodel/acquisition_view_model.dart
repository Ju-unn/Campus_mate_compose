import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/profile/basic/model/repository/acquisition_repository_provider.dart';
import 'package:campus_mate/profile/basic/viewmodel/acquisition_ui_state.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final acquisitionViewModelProvider =
    NotifierProvider<AcquisitionViewModel, AcquisitionUiState>(AcquisitionViewModel.new);

/// 유입경로(DESIGN.md 화면 20d)의 흐름을 맡는다.
/// 서버 온보딩 단계가 아니라서 단계 캐시를 새로 고치지 않는다(2026-09-28 대장 D2).
class AcquisitionViewModel extends Notifier<AcquisitionUiState> {
  @override
  AcquisitionUiState build() => const AcquisitionUiState();

  void select(AcquisitionChannel channel) {
    state = state.copyWith(channel: channel);
  }

  void changeNote(String value) {
    state = state.copyWith(note: value);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true);
    try {
      final result = await ref.read(acquisitionRepositoryProvider).submit(state.channel!, state.noteToSend);
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => state.copyWith(isSubmitting: false, error: failure),
      );
    } catch (_) {
      state = state.copyWith(isSubmitting: false, error: const UnknownFailure());
    }
  }
}
