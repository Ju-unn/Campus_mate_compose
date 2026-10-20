import 'package:campus_mate/core/analytics/analytics_service.dart';
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
    }, returnsNormally);
  });
}
