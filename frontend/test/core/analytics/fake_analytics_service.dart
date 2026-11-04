import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';

/// 시험이 Firebase 를 켜지 않고도 "무엇이 기록됐는지" 만 보는 가짜 구현. 부른 순서대로 한 줄씩 남긴다.
/// 한 줄은 `이벤트이름:매개변수값…` 꼴이다 — 실제 Firebase 이벤트 이름과 매개변수 값 순서(`docs/ANALYTICS_EVENTS.md`)와 같다.
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
  void logOnboardingStepComplete(OnboardingStep step, int seconds) =>
      calls.add('onboarding_step_complete:${step.wire}:$seconds');

  @override
  void logOnboardingStepBack(OnboardingStep step) => calls.add('onboarding_step_back:${step.wire}');

  @override
  void logOnboardingBlocked(OnboardingStep step, OnboardingBlockReason reason) =>
      calls.add('onboarding_blocked:${step.wire}:${reason.wire}');

  @override
  void logChatRequestSent() => calls.add('chat_request_sent');

  @override
  void logCardView(CardOrigin source) => calls.add('card_view:${source.wire}');

  @override
  void logCardDetailOpen(CardOrigin source) => calls.add('card_detail_open:${source.wire}');

  @override
  void logCardPass(CardOrigin source) => calls.add('card_pass:${source.wire}');

  @override
  void logPaidCardView(PaidCardState state) => calls.add('paid_card_view:${state.wire}');

  @override
  void logPaidCardSheetOpen() => calls.add('paid_card_sheet_open');

  @override
  void logHeartPurchase(String productId) => calls.add('heart_purchase:$productId');

  @override
  void logHeartStoreOpen(HeartStoreEntry from) => calls.add('heart_store_open:${from.wire}');

  @override
  void logHeartProductSelect(String productId) => calls.add('heart_product_select:$productId');

  @override
  void logHeartPurchaseResult(HeartPurchaseResult result, String productId) =>
      calls.add('heart_purchase_result:${result.wire}:$productId');

  @override
  void logPushOpen(PushOpenType type) => calls.add('push_open:${type.wire}');

  @override
  void logTourFinish(TourResult result, int step) => calls.add('tour_finish:${result.wire}:$step');

  @override
  void logPollVote() => calls.add('poll_vote');

  @override
  void logPollCreate() => calls.add('poll_create');

  @override
  void logScreen(String name) => calls.add('screen:$name');
}
