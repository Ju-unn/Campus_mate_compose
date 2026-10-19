import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:campus_mate/graduate/viewmodel/verification_method_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final verificationMethodViewModelProvider =
    NotifierProvider.autoDispose<VerificationMethodViewModel, VerificationMethodUiState>(
  VerificationMethodViewModel.new,
);

/// 인증 방법 고르기(카드 두 장 + [다음]).
///
/// 카드를 눌러 보다 앱을 닫아도 서버 값이 바뀌지 않도록, 서버에 쓰는 것은 [next] 뿐이다.
/// 쓰기가 성공하면 관문을 다시 묻고, 화면은 `AuthRedirect` 가 옮긴다.
class VerificationMethodViewModel extends Notifier<VerificationMethodUiState> {
  @override
  VerificationMethodUiState build() => const VerificationMethodUiState();

  /// 앱 상태만 바꾼다(서버 호출 0). 보내는 중에는 카드를 바꾸지 않는다.
  void select(VerificationMethod method) {
    if (state.isSubmitting) return;
    state = VerificationMethodUiState(selected: method);
  }

  Future<void> next() async {
    final selected = state.selected;
    if (selected == null || !state.canGoNext) return;
    state = VerificationMethodUiState(selected: selected, isSubmitting: true);
    final result = await ref.read(graduateVerificationRepositoryProvider).chooseMethod(selected);
    if (!ref.mounted) return;
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure == null) {
      await ref.read(verificationGateListenableProvider).refresh();
    }
    if (!ref.mounted) return;
    state = VerificationMethodUiState(selected: selected, errorMessage: _messageOf(failure));
  }

  String? _messageOf(Failure? failure) => failure?.toDisplayMessage();
}
