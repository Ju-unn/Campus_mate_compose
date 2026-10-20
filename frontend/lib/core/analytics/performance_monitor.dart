import 'package:campus_mate/core/analytics/collection_switch.dart';

/// 성능 측정(Firebase Performance Monitoring). **자동 수집만 쓴다** — 앱 시작 시간 · 화면 렌더링 같은 플랫폼 자동 항목이다.
/// 사용자 지정 추적(`HttpMetric` · `Trace`)은 만들지 않는다: 서버 요청 주소에 계정 번호가 섞일 수 있어서다(2026-10-20).
/// 그래서 이 인터페이스는 켜고 끄는 일([CollectionSwitch])밖에 없다.
///
/// 시험과 Firebase 를 켜지 못한 빌드는 [NoPerformanceMonitor] 를 쓴다(`analytics_provider.dart`).
abstract interface class PerformanceMonitor implements CollectionSwitch {}

/// 아무것도 하지 않는 구현 — 시험과 Firebase 를 켜지 못한 빌드의 기본값이다.
class NoPerformanceMonitor implements PerformanceMonitor {
  const NoPerformanceMonitor();

  @override
  void enableAfterConsent() {}

  @override
  void disable() {}
}
