import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/viewmodel/onboarding_blocked.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/analytics/fake_analytics_service.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  group('onboardingBlockReasonOf — 실패를 정해진 종류값 하나로 접는다', () {
    test('인터넷 · 서버 · 한도 · 로그인', () {
      expect(onboardingBlockReasonOf(const NetworkFailure()), OnboardingBlockReason.network);
      expect(onboardingBlockReasonOf(const ServerUnavailableFailure()), OnboardingBlockReason.server);
      expect(onboardingBlockReasonOf(const UnknownFailure()), OnboardingBlockReason.server);
      expect(onboardingBlockReasonOf(const RateLimitedFailure('내일 다시 해 주세요')), OnboardingBlockReason.rateLimited);
      expect(onboardingBlockReasonOf(const SessionExpiredFailure()), OnboardingBlockReason.session);
      expect(onboardingBlockReasonOf(const SessionRejectedFailure()), OnboardingBlockReason.session);
    });

    test('서버가 입력을 거절하면 rejected — 서버 문구는 종류값에 들어가지 않는다', () {
      expect(onboardingBlockReasonOf(const ServerRejectedFailure('이미 있는 닉네임이에요')), OnboardingBlockReason.rejected);
    });
  });

  group('reportOnboardingBlocked', () {
    late FakeAnalyticsService analytics;
    late FakeOnboardingRepository onboardingRepository;
    late ProviderContainer container;
    late Ref ref;

    setUp(() {
      analytics = FakeAnalyticsService();
      onboardingRepository = FakeOnboardingRepository()..nextResult = const Success(OnboardingStep.photos);
      container = ProviderContainer(
        overrides: [
          analyticsServiceProvider.overrideWithValue(analytics),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        ],
      );
      ref = container.read(_refProbe);
    });

    tearDown(() => container.dispose());

    test('지금 서 있는 단계 이름과 종류값을 남긴다', () async {
      await container.read(onboardingStepListenableProvider).refresh();

      reportOnboardingBlocked(ref, const NetworkFailure());

      expect(analytics.calls, ['onboarding_blocked:photos:network']);
    });

    test('결과가 실패일 때만 남기고, 성공은 남기지 않는다', () async {
      await container.read(onboardingStepListenableProvider).refresh();

      reportIfOnboardingBlocked(ref, const Success<void>(null));
      reportIfOnboardingBlocked(ref, const FailureResult<void>(ServerUnavailableFailure()));

      expect(analytics.calls, ['onboarding_blocked:photos:server']);
    });
  });
}

final _refProbe = Provider<Ref>((ref) => ref);
