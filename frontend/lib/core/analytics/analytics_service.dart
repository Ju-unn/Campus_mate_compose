import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/analytics/collection_switch.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';

/// 사용 통계(Firebase Analytics). **개인을 가리키는 값은 어디에도 싣지 않는다** —
/// 사용자 id · 닉네임 · 메일 · 학교 같은 값은 이벤트 매개변수에도, 사용자 속성에도 넣지 않는다(2026-10-20).
/// 기기에 자동으로 붙는 앱 인스턴스 ID 와 아래 이벤트 이름 · 상품 ID · `analytics_values.dart` 의 종류값 ·
/// 작은 정수(머문 초 · 단계 번호)만 나간다. 상대 id · 카드 id · 채팅방 id · 금액 · 글 내용은 받는 자리가 없다.
///
/// 이벤트를 더하거나 고치면 `docs/ANALYTICS_EVENTS.md` 표도 함께 고친다.
///
/// 약관 동의 전에는 수집하지 않는다 — 켜고 끄는 때는 [CollectionConsent] 가 정한다.
/// 시험과 Firebase 를 켜지 못한 빌드는 [NoAnalyticsService] 를 쓴다(`analytics_provider.dart`).
abstract interface class AnalyticsService implements CollectionSwitch {
  /// 로그인 성공. [method] 는 `kakao` · `google` · `apple` 중 하나다.
  void logLogin(String method);

  /// 가입(온보딩)을 끝냈다.
  void logOnboardingComplete();

  /// 가입 단계 하나를 끝냈다(서버 단계가 [step] 에서 앞으로 나아갔다). [seconds] 는 그 단계에 머문 초(앱을 껐다 켜면 다시 센다).
  void logOnboardingStepComplete(OnboardingStep step, int seconds);

  /// 가입 단계에서 앞 단계로 뒤로갔다. [step] 은 떠난(뒤로가기를 누른) 단계다.
  void logOnboardingStepBack(OnboardingStep step);

  /// 가입 단계에서 막혔다(사진 거절 · 서버 오류 등). [step] 은 막힌 단계, [reason] 은 정해진 종류값.
  void logOnboardingBlocked(OnboardingStep step, OnboardingBlockReason reason);

  /// 대화 신청을 보냈다.
  void logChatRequestSent();

  /// 오늘 탭에서 카드 한 장이 화면에 보였다(앱을 켠 동안 같은 카드는 한 번).
  void logCardView(CardOrigin source);

  /// 카드를 눌러 상세(10b)를 열었다.
  void logCardDetailOpen(CardOrigin source);

  /// 상세에서 "넘기기"(거절)를 서버가 받아 줬다.
  void logCardPass(CardOrigin source);

  /// 오늘 탭의 유료 카드 칸이 보였다.
  void logPaidCardView(PaidCardState state);

  /// 유료 카드 열기 확인 시트가 떴다.
  void logPaidCardSheetOpen();

  /// 하트 구매가 끝나 서버가 하트를 지급했다. [productId] 는 스토어 상품 ID 만이다(금액 · 거래 번호는 싣지 않는다).
  void logHeartPurchase(String productId);

  /// 하트 상점(18)에 들어왔다. [from] 은 들어온 곳.
  void logHeartStoreOpen(HeartStoreEntry from);

  /// 하트 상점에서 상품 카드를 골랐다. [productId] 는 스토어 상품 ID 만이다.
  void logHeartProductSelect(String productId);

  /// 하트 결제 창이 끝났다. [productId] 는 스토어 상품 ID 만이다.
  void logHeartPurchaseResult(HeartPurchaseResult result, String productId);

  /// 푸시를 눌러 앱이 열리거나 화면이 옮겨졌다.
  void logPushOpen(PushOpenType type);

  /// 앱 투어가 끝났다. [step] 은 끝난(건너뛴) 단계 번호(1부터, 단계 목록의 몇째).
  void logTourFinish(TourResult result, int step);

  /// 커뮤니티 투표에 참여했다(서버가 받아 줬다).
  void logPollVote();

  /// 커뮤니티 질문을 올렸다(서버가 받아 줬다).
  void logPollCreate();

  /// 화면에 들어왔다. [name] 은 경로 패턴(`/chat/:matchId`)이지 값이 채워진 경로가 아니다.
  void logScreen(String name);
}

/// 아무것도 기록하지 않는 구현 — 시험과 Firebase 를 켜지 못한 빌드(`google-services` 가 없는 CI · iOS)의 기본값이다.
class NoAnalyticsService implements AnalyticsService {
  const NoAnalyticsService();

  @override
  void enableAfterConsent() {}

  @override
  void disable() {}

  @override
  void logLogin(String method) {}

  @override
  void logOnboardingComplete() {}

  @override
  void logOnboardingStepComplete(OnboardingStep step, int seconds) {}

  @override
  void logOnboardingStepBack(OnboardingStep step) {}

  @override
  void logOnboardingBlocked(OnboardingStep step, OnboardingBlockReason reason) {}

  @override
  void logChatRequestSent() {}

  @override
  void logCardView(CardOrigin source) {}

  @override
  void logCardDetailOpen(CardOrigin source) {}

  @override
  void logCardPass(CardOrigin source) {}

  @override
  void logPaidCardView(PaidCardState state) {}

  @override
  void logPaidCardSheetOpen() {}

  @override
  void logHeartPurchase(String productId) {}

  @override
  void logHeartStoreOpen(HeartStoreEntry from) {}

  @override
  void logHeartProductSelect(String productId) {}

  @override
  void logHeartPurchaseResult(HeartPurchaseResult result, String productId) {}

  @override
  void logPushOpen(PushOpenType type) {}

  @override
  void logTourFinish(TourResult result, int step) {}

  @override
  void logPollVote() {}

  @override
  void logPollCreate() {}

  @override
  void logScreen(String name) {}
}
