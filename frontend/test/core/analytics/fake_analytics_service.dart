import 'package:campus_mate/core/analytics/analytics_service.dart';

/// 시험이 Firebase 를 켜지 않고도 "무엇이 기록됐는지" 만 보는 가짜 구현. 부른 순서대로 한 줄씩 남긴다.
class FakeAnalyticsService implements AnalyticsService {
  final List<String> calls = [];

  /// 마지막으로 켜고 끈 결과. 처음에는 꺼져 있다(앱의 기본값과 같다).
  bool collecting = false;

  @override
  void enableAfterConsent() {
    collecting = true;
    calls.add('enable');
  }

  @override
  void disable() {
    collecting = false;
    calls.add('disable');
  }

  @override
  void logLogin(String method) => calls.add('login:$method');

  @override
  void logOnboardingComplete() => calls.add('onboarding_complete');

  @override
  void logChatRequestSent() => calls.add('chat_request_sent');

  @override
  void logHeartPurchase(String productId) => calls.add('heart_purchase:$productId');

  @override
  void logScreen(String name) => calls.add('screen:$name');
}
