import 'package:campus_mate/core/analytics/collection_switch.dart';

/// 사용 통계(Firebase Analytics). **개인을 가리키는 값은 어디에도 싣지 않는다** —
/// 사용자 id · 닉네임 · 메일 · 학교 같은 값은 이벤트 매개변수에도, 사용자 속성에도 넣지 않는다(2026-10-20).
/// 기기에 자동으로 붙는 앱 인스턴스 ID 와 아래 이벤트 이름 · 상품 ID 만 나간다.
///
/// 약관 동의 전에는 수집하지 않는다 — 켜고 끄는 때는 [CollectionConsent] 가 정한다.
/// 시험과 Firebase 를 켜지 못한 빌드는 [NoAnalyticsService] 를 쓴다(`analytics_provider.dart`).
abstract interface class AnalyticsService implements CollectionSwitch {
  /// 로그인 성공. [method] 는 `kakao` · `google` · `apple` 중 하나다.
  void logLogin(String method);

  /// 가입(온보딩)을 끝냈다.
  void logOnboardingComplete();

  /// 대화 신청을 보냈다.
  void logChatRequestSent();

  /// 하트 구매가 끝나 서버가 하트를 지급했다. [productId] 는 스토어 상품 ID 만이다(금액 · 거래 번호는 싣지 않는다).
  void logHeartPurchase(String productId);

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
  void logChatRequestSent() {}

  @override
  void logHeartPurchase(String productId) {}

  @override
  void logScreen(String name) {}
}
