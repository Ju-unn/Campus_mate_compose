import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/onboarding/model/repository/http_onboarding_repository.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return HttpOnboardingRepository(ref.read(apiClientProvider));
});
