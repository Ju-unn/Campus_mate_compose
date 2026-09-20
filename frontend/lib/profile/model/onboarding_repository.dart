import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';

abstract interface class OnboardingRepository {
  Future<Result<OnboardingStep>> fetchNextStep();
}
