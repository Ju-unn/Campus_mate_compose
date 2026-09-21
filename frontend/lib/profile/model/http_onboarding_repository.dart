import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';

/// [OnboardingRepository]를 FastAPI 호출로 구현한다.
class HttpOnboardingRepository implements OnboardingRepository {
  const HttpOnboardingRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() => _api.send(
        'GET',
        '/profile-onboarding/next-step',
        (body) => OnboardingStep.fromWire((body as Map<String, dynamic>)['step'] as String),
      );
}
