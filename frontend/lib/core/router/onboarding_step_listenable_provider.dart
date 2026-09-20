import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 전체가 같은 온보딩 단계 캐시를 보게 한다([verificationGateListenableProvider]와 같은 이유).
///
/// main.dart 는 이것을 라우터의 `refreshListenable` 에 걸고,
/// 각 온보딩 화면 ViewModel 은 저장에 성공한 순간 `refresh()` 를 불러 라우터를 다시 평가시킨다.
final onboardingStepListenableProvider = Provider<OnboardingStepListenable>((ref) {
  final listenable = OnboardingStepListenable(ref.read(onboardingRepositoryProvider));
  ref.onDispose(listenable.dispose);
  return listenable;
});
