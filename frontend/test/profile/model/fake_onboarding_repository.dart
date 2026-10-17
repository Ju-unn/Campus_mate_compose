import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 테스트 전용 [OnboardingRepository].
/// 기본은 온보딩을 모두 마친 상태이고, `nextResult` 로 다른 결과를 흉내 낸다.
class FakeOnboardingRepository implements OnboardingRepository {
  Result<OnboardingStep> nextResult = const Success(OnboardingStep.complete);

  /// 라우터에 재평가를 알리려고 실제로 조회했는지 확인하는 용도.
  int fetchCount = 0;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() async {
    fetchCount++;
    return nextResult;
  }
}

/// 서버 단계를 [server] 로 두고, [visiting] 이 될 때까지 뒤로가기를 눌러 "다시 보는 중" 으로 만든다.
/// 서버 단계는 그대로 남는다(다음 조회도 [server]). 조회 횟수는 0 으로 되돌린다 — 저장 뒤 조회만 세게.
Future<void> revisit(
  ProviderContainer container,
  FakeOnboardingRepository repository, {
  required OnboardingStep server,
  required OnboardingStep visiting,
}) async {
  repository.nextResult = Success(server);
  final steps = container.read(onboardingStepListenableProvider);
  await steps.refresh();
  while (steps.value != visiting && steps.canGoBack) {
    steps.goBack();
  }
  repository.fetchCount = 0;
}
