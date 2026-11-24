import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealIntroViewModelProvider = NotifierProvider<IdealIntroViewModel, bool>(IdealIntroViewModel.new);

/// 이상형 들어가기(pen 25-B)를 이 앱 실행 동안 이미 보였는가. 메모리에만 있다 — 앱을 다시 켜면 06-1 에서 한 번 더 보인다.
class IdealIntroViewModel extends Notifier<bool> {
  @override
  bool build() => false;

  /// 가입 길에서 06-1 에 처음 앞으로 들어올 때만 보인다. 이미 봤거나(06-1 · 들어가기에서 설문으로 돌아갔다 다시 온 길)
  /// 06-2 에서 돌아온 06-1(다시 보는 중)이면 보이지 않는다. 프로필 수정 길은 이 판단 전에 라우터가 들어가기를 두르지 않는다.
  bool shouldShow() => !state && !ref.read(onboardingStepListenableProvider).isRevisiting;

  void markSeen() => state = true;
}
