import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';

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
