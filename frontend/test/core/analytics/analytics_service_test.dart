import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 시험과 Firebase 를 켜지 못한 빌드의 기본값 — 어떤 호출도 던지지 않고 아무 일도 하지 않는다.
  test('기록 없는 구현은 모든 행위를 조용히 받는다', () {
    const AnalyticsService service = NoAnalyticsService();

    expect(() {
      service.enableAfterConsent();
      service.disable();
      service.logLogin('kakao');
      service.logOnboardingComplete();
      service.logChatRequestSent();
      service.logHeartPurchase('heart_100');
      service.logScreen('/home');
      service.logOnboardingStepComplete(OnboardingStep.photos, 10);
      service.logOnboardingStepBack(OnboardingStep.photos);
      service.logOnboardingBlocked(OnboardingStep.photos, OnboardingBlockReason.server);
      service.logCardView(CardOrigin.free);
      service.logCardDetailOpen(CardOrigin.purchased);
      service.logCardPass(CardOrigin.free);
      service.logPaidCardView(PaidCardState.offered);
      service.logPaidCardSheetOpen();
      service.logHeartStoreOpen(HeartStoreEntry.other);
      service.logHeartProductSelect('heart_100');
      service.logHeartPurchaseResult(HeartPurchaseResult.success, 'heart_100');
      service.logPushOpen(PushOpenType.chat);
      service.logTourFinish(TourResult.done, 6);
      service.logPollVote();
      service.logPollCreate();
    }, returnsNormally);
  });
}
