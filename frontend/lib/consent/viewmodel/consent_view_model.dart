import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_repository_provider.dart';
import 'package:campus_mate/consent/viewmodel/consent_ui_state.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 화면을 떠나면 체크를 버린다 — 로그아웃 뒤 다음 사람이 앞 사람의 체크를 물려받지 않게.
final consentViewModelProvider = NotifierProvider.autoDispose<ConsentViewModel, ConsentUiState>(ConsentViewModel.new);

/// 약관 동의 화면(02-c · 재동의 02-c-4)의 흐름을 맡는다.
class ConsentViewModel extends Notifier<ConsentUiState> {
  @override
  ConsentUiState build() => const ConsentUiState();

  void toggle(ConsentItem item) {
    final checked = {...state.checked};
    if (!checked.remove(item)) {
      checked.add(item);
    }
    state = state.copyWith(checked: checked);
  }

  /// 다 켜져 있으면 모두 끄고, 아니면 모두 켠다.
  void toggleAll() {
    state = state.copyWith(checked: state.allChecked ? {} : ConsentItem.values.toSet());
  }

  /// 저장하는 동안 다시 눌러도 한 번만 보낸다.
  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true);
    Result<void> result;
    try {
      result = await ref.read(consentRepositoryProvider).submit(agreed: state.checked);
    } catch (_) {
      // 비정상 응답 등으로 Result 밖으로 새는 예외 — 버튼이 스피너로 굳지 않게 여기서 받는다.
      result = const FailureResult(UnknownFailure());
    }
    if (!ref.mounted) {
      return;
    }
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure != null) {
      state = state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage());
      return;
    }
    // 온보딩 단계를 먼저 다시 읽는다. 재동의 계정은 앱을 켤 때 next-step 이 403 이라 온보딩 캐시가
    // 기본값(04-1)에 머문다 — 게이트가 먼저 바뀌면 라우터가 온보딩을 마친 사람을 04-1 로 보낸다.
    final onboardingStep = ref.read(onboardingStepListenableProvider);
    final gate = ref.read(verificationGateListenableProvider);
    await onboardingStep.refresh();
    await gate.refresh();
    // 게이트가 바뀌었으면 라우터가 이 화면을 닫아 여기서 멈춘다. 남아 있으면(조회 실패) 다시 누를 수 있게 한다.
    if (ref.mounted) {
      state = state.copyWith(isSubmitting: false);
    }
  }
}
